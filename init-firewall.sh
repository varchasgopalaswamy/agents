#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

ALLOW_HOST_NETWORK=0

for arg in "$@"; do
    case "$arg" in
        --allow-host-network)
            ALLOW_HOST_NETWORK=1
            ;;
        *)
            echo "ERROR: unknown firewall option: $arg" >&2
            exit 2
            ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: init-firewall.sh must run as root" >&2
    exit 1
fi

ALLOWED_NETWORKS=()
ALLOWED_DOMAINS=()
VERIFY_ALLOWED_URLS=()
VERIFY_ALLOWED_LABELS=()
ALLOW_GITHUB_RANGES=0

OPENAI_DOMAINS=(
    "api.openai.com"
    "auth.openai.com"
    "chatgpt.com"
)

ANTHROPIC_DOMAINS=(
    "api.anthropic.com"
    "claude.ai"
)

GOOGLE_DOMAINS=(
    "accounts.google.com"
    "cloudcode-pa.googleapis.com"
    "generativelanguage.googleapis.com"
    "oauth2.googleapis.com"
    "www.googleapis.com"
)

GITHUB_DOMAINS=(
    "api.github.com"
    "codeload.github.com"
    "github.com"
    "github-releases.githubusercontent.com"
    "gist.githubusercontent.com"
    "objects.githubusercontent.com"
    "raw.githubusercontent.com"
)

COPILOT_DOMAINS=(
    "api.githubcopilot.com"
    "copilot-proxy.githubusercontent.com"
)

PYPI_DOMAINS=(
    "files.pythonhosted.org"
    "pypi.org"
)

NPM_DOMAINS=(
    "registry.npmjs.org"
)

VSCODE_DOMAINS=(
    "marketplace.visualstudio.com"
    "update.code.visualstudio.com"
    "vscode.blob.core.windows.net"
)

split_config_list() {
    local raw="${1:-}"
    raw="${raw//$'\r'/,}"
    raw="${raw//$'\n'/,}"
    raw="${raw//$'\t'/,}"
    raw="${raw// /,}"

    local items=()
    IFS=',' read -r -a items <<< "$raw"
    printf '%s\n' "${items[@]}"
}

normalize_domain() {
    local domain="$1"
    domain="${domain#http://}"
    domain="${domain#https://}"
    domain="${domain%%/*}"
    domain="${domain%%:*}"
    domain="${domain%.}"
    domain="${domain,,}"
    printf '%s' "$domain"
}

env_flag_enabled() {
    local name="$1"
    local value="${!name:-0}"
    case "$value" in
        1|true|True|TRUE|yes|Yes|YES|on|On|ON)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

add_bundle_domains() {
    local bundle="$1"
    shift

    local domain
    for domain in "$@"; do
        echo "Enabling $bundle firewall domain $domain"
        ALLOWED_DOMAINS+=("$domain")
    done
}

add_verify_allowed() {
    local url="$1"
    local label="$2"

    VERIFY_ALLOWED_URLS+=("$url")
    VERIFY_ALLOWED_LABELS+=("$label")
}

configure_provider_bundles() {
    if env_flag_enabled AGENTS_ALLOW_OPENAI; then
        add_bundle_domains "OpenAI" "${OPENAI_DOMAINS[@]}"
        add_verify_allowed "https://api.openai.com/v1/models" "OpenAI API"
    fi

    if env_flag_enabled AGENTS_ALLOW_ANTHROPIC; then
        add_bundle_domains "Anthropic" "${ANTHROPIC_DOMAINS[@]}"
        add_verify_allowed "https://api.anthropic.com/v1/messages" "Anthropic API"
    fi

    if env_flag_enabled AGENTS_ALLOW_GOOGLE; then
        add_bundle_domains "Google" "${GOOGLE_DOMAINS[@]}"
        add_verify_allowed "https://generativelanguage.googleapis.com" "Gemini API"
    fi

    if env_flag_enabled AGENTS_ALLOW_GITHUB; then
        add_bundle_domains "GitHub" "${GITHUB_DOMAINS[@]}"
        add_verify_allowed "https://api.github.com/zen" "GitHub API"
        ALLOW_GITHUB_RANGES=1
    fi

    if env_flag_enabled AGENTS_ALLOW_COPILOT; then
        add_bundle_domains "GitHub Copilot" "${COPILOT_DOMAINS[@]}"
        add_verify_allowed "https://api.githubcopilot.com" "GitHub Copilot API"
    fi

    if env_flag_enabled AGENTS_ALLOW_PYPI; then
        add_bundle_domains "PyPI" "${PYPI_DOMAINS[@]}"
        add_verify_allowed "https://pypi.org/simple/pip/" "PyPI"
    fi

    if env_flag_enabled AGENTS_ALLOW_NPM; then
        add_bundle_domains "npm" "${NPM_DOMAINS[@]}"
        add_verify_allowed "https://registry.npmjs.org/npm" "npm registry"
    fi

    if env_flag_enabled AGENTS_ALLOW_VSCODE; then
        add_bundle_domains "VS Code" "${VSCODE_DOMAINS[@]}"
        add_verify_allowed "https://update.code.visualstudio.com" "VS Code updates"
    fi
}

append_configured_domains() {
    if [ -z "${AGENTS_ALLOWED_DOMAINS:-}" ]; then
        return
    fi

    while read -r configured_domain; do
        [ -n "$configured_domain" ] || continue
        local domain
        domain=$(normalize_domain "$configured_domain")
        if [[ ! "$domain" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || [[ "$domain" != *.* ]]; then
            echo "ERROR: Invalid configured allowed domain: $configured_domain" >&2
            exit 1
        fi
        echo "Adding configured allowed domain $domain"
        ALLOWED_DOMAINS+=("$domain")
    done < <(split_config_list "$AGENTS_ALLOWED_DOMAINS")
}

is_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

    local IFS=.
    local octets=()
    read -r -a octets <<< "$ip"
    [ "${#octets[@]}" -eq 4 ] || return 1

    local octet
    for octet in "${octets[@]}"; do
        [[ "$octet" =~ ^[0-9]+$ ]] || return 1
        [ "$((10#$octet))" -le 255 ] || return 1
    done
}

is_ipv4_cidr() {
    local cidr="$1"
    [[ "$cidr" == */* ]] || return 1

    local ip="${cidr%/*}"
    local prefix="${cidr#*/}"
    [[ "$prefix" =~ ^[0-9]+$ ]] || return 1
    is_ipv4 "$ip" || return 1
    [ "$((10#$prefix))" -le 32 ]
}

ipv6_available() {
    [ -r /proc/net/if_inet6 ] || return 1
    awk '$6 != "lo" { found=1 } END { exit found ? 0 : 1 }' /proc/net/if_inet6
}

have_ip6tables() {
    command -v ip6tables >/dev/null 2>&1 && ip6tables -L >/dev/null 2>&1
}

reset_ipv4_firewall() {
    iptables -P INPUT ACCEPT || true
    iptables -P FORWARD ACCEPT || true
    iptables -P OUTPUT ACCEPT || true
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
}

drop_ipv6_firewall() {
    if ! have_ip6tables; then
        if ipv6_available; then
            echo "ERROR: IPv6 appears available but ip6tables cannot enforce a deny policy" >&2
            exit 1
        fi
        echo "IPv6 unavailable; skipping IPv6 rules"
        return
    fi

    ip6tables -P INPUT ACCEPT || true
    ip6tables -P FORWARD ACCEPT || true
    ip6tables -P OUTPUT ACCEPT || true
    ip6tables -F
    ip6tables -X
    ip6tables -t mangle -F 2>/dev/null || true
    ip6tables -t mangle -X 2>/dev/null || true

    ip6tables -A INPUT -i lo -j ACCEPT
    ip6tables -A OUTPUT -o lo -j ACCEPT
    ip6tables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    ip6tables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    ip6tables -A OUTPUT -j REJECT --reject-with icmp6-adm-prohibited 2>/dev/null || ip6tables -A OUTPUT -j REJECT

    ip6tables -P INPUT DROP
    ip6tables -P FORWARD DROP
    ip6tables -P OUTPUT DROP
}

restore_docker_dns_rules() {
    local docker_dns_rules="$1"

    if [ -n "$docker_dns_rules" ]; then
        echo "Restoring Docker DNS NAT rules..."
        iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
        iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
        echo "$docker_dns_rules" | xargs -L 1 iptables -t nat
    else
        echo "No Docker DNS NAT rules to restore"
    fi
}

allow_base_ipv4_traffic() {
    iptables -A OUTPUT -p udp --dport 53 -j REJECT
    iptables -A OUTPUT -p tcp --dport 53 -j REJECT --reject-with tcp-reset 2>/dev/null || iptables -A OUTPUT -p tcp --dport 53 -j REJECT
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
}

add_github_ranges() {
    echo "Fetching GitHub IP ranges..."
    local gh_ranges
    gh_ranges=$(curl -fsSL --retry 3 https://api.github.com/meta)

    if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
        echo "ERROR: GitHub API response missing required fields" >&2
        exit 1
    fi

    echo "Processing GitHub IP ranges..."
    while read -r cidr; do
        if ! is_ipv4_cidr "$cidr"; then
            echo "ERROR: Invalid CIDR range from GitHub meta: $cidr" >&2
            exit 1
        fi
        echo "Adding GitHub range $cidr"
        ALLOWED_NETWORKS+=("$cidr")
    done < <(
        echo "$gh_ranges" |
            jq -r '(.web + .api + .git + (.packages // []))[] | select(test("^[0-9]"))' |
            aggregate -q
    )
}

add_allowed_domain() {
    local domain="$1"
    local ips
    ips=$(dig +short A "$domain" | awk '/^[0-9.]+$/ {print $1}')

    if [ -z "$ips" ]; then
        echo "ERROR: Failed to resolve $domain" >&2
        exit 1
    fi

    while read -r ip; do
        if ! is_ipv4 "$ip"; then
            echo "ERROR: Invalid IP from DNS for $domain: $ip" >&2
            exit 1
        fi
        echo "Adding $ip for $domain"
        ALLOWED_NETWORKS+=("$ip")
        printf '%s\t%s\n' "$ip" "$domain" >> /etc/hosts
    done < <(echo "$ips")
}

add_allowed_network() {
    local network="$1"
    if ! is_ipv4 "$network" && ! is_ipv4_cidr "$network"; then
        echo "ERROR: Invalid configured allowed CIDR/IP: $network" >&2
        exit 1
    fi
    echo "Adding configured allowed network $network"
    ALLOWED_NETWORKS+=("$network")
}

add_configured_cidrs() {
    if [ -z "${AGENTS_ALLOWED_CIDRS:-}" ]; then
        return
    fi

    while read -r configured_network; do
        [ -n "$configured_network" ] || continue
        add_allowed_network "$configured_network"
    done < <(split_config_list "$AGENTS_ALLOWED_CIDRS")
}

add_allowed_domains() {
    for domain in "${ALLOWED_DOMAINS[@]}"; do
        echo "Resolving $domain..."
        add_allowed_domain "$domain"
    done
}

allow_host_gateway_if_requested() {
    if [ "$ALLOW_HOST_NETWORK" != "1" ]; then
        echo "Host gateway access disabled"
        return
    fi

    local host_ip
    host_ip=$(ip route | awk '/default/ {print $3; exit}')
    if [ -z "$host_ip" ] || ! is_ipv4 "$host_ip"; then
        echo "ERROR: Failed to detect host gateway IP" >&2
        exit 1
    fi

    echo "Allowing host gateway access: $host_ip"
    iptables -A INPUT -s "$host_ip" -j ACCEPT
    iptables -A OUTPUT -d "$host_ip" -j ACCEPT
}

apply_default_denies() {
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT DROP

    for network in "${ALLOWED_NETWORKS[@]}"; do
        iptables -A OUTPUT -d "$network" -j ACCEPT
    done
    iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited
}

verify_blocked() {
    local url="$1"
    local label="$2"

    if curl --connect-timeout 5 --max-time 8 "$url" >/dev/null 2>&1; then
        echo "ERROR: Firewall verification failed - reached $label" >&2
        exit 1
    fi
    echo "Firewall verification passed - blocked $label"
}

verify_allowed() {
    local url="$1"
    local label="$2"

    if ! curl --connect-timeout 5 --max-time 8 "$url" >/dev/null 2>&1; then
        echo "ERROR: Firewall verification failed - unable to reach $label" >&2
        exit 1
    fi
    echo "Firewall verification passed - reached $label"
}

verify_allowed_bundles() {
    local index
    for index in "${!VERIFY_ALLOWED_URLS[@]}"; do
        verify_allowed "${VERIFY_ALLOWED_URLS[$index]}" "${VERIFY_ALLOWED_LABELS[$index]}"
    done
}

revoke_firewall_sudo() {
    if [ -f /etc/sudoers.d/agent-firewall ]; then
        rm -f /etc/sudoers.d/agent-firewall
        echo "Revoked passwordless firewall sudo permission"
    fi
}

DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

reset_ipv4_firewall
drop_ipv6_firewall
restore_docker_dns_rules "$DOCKER_DNS_RULES"

configure_provider_bundles
add_configured_cidrs
append_configured_domains
if [ "$ALLOW_GITHUB_RANGES" = "1" ]; then
    add_github_ranges
fi
add_allowed_domains
allow_base_ipv4_traffic
allow_host_gateway_if_requested
apply_default_denies

echo "Firewall configuration complete"
echo "Verifying firewall rules..."
verify_blocked "https://example.com" "https://example.com"
verify_allowed_bundles
revoke_firewall_sudo
