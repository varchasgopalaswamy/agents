#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHER="$REPO_ROOT/start-agents"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

log() {
    printf '==> %s\n' "$*" >&2
}

choose_runtime() {
    if [ -n "${AGENTS_SMOKE_RUNTIME:-}" ]; then
        command -v "$AGENTS_SMOKE_RUNTIME" >/dev/null 2>&1 ||
            fail "requested runtime not found on PATH: $AGENTS_SMOKE_RUNTIME"
        printf '%s\n' "$AGENTS_SMOKE_RUNTIME"
        return
    fi

    if command -v podman >/dev/null 2>&1; then
        printf 'podman\n'
        return
    fi
    if command -v docker >/dev/null 2>&1; then
        printf 'docker\n'
        return
    fi
    fail "neither podman nor docker found on PATH"
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    case "$haystack" in
        *"$needle"*) ;;
        *) fail "expected output to contain: $needle" ;;
    esac
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    case "$haystack" in
        *"$needle"*) fail "did not expect output to contain: $needle" ;;
        *) ;;
    esac
}

CONTAINER_SCRIPT="set -euo pipefail; echo startup-ok; if touch /workspace/.git/agents-smoke-write-test 2>/tmp/git-write.err; then echo 'git metadata write unexpectedly succeeded' >&2; exit 40; fi; echo git-readonly-ok; if curl --connect-timeout 5 --max-time 8 https://example.com >/dev/null 2>&1; then echo 'external access unexpectedly succeeded' >&2; exit 41; fi; echo external-blocked-ok"

RUNTIME="$(choose_runtime)"
TMP_ROOT="$(mktemp -d)"
IMAGE="${AGENTS_SMOKE_IMAGE:-agents-security-smoke:$(date +%Y%m%d%H%M%S)-$$}"
CHECK_IMAGE="${AGENTS_SMOKE_CHECK_IMAGE:-${IMAGE}-check}"
IMAGE_BUILT=0
CHECK_IMAGE_BUILT=0
NESTED_MOUNT=""
REAL_HOME="${HOME:?HOME must be set}"

cleanup() {
    if [ -n "$NESTED_MOUNT" ] && command -v mountpoint >/dev/null 2>&1 &&
        mountpoint -q "$NESTED_MOUNT"; then
        umount "$NESTED_MOUNT" >/dev/null 2>&1 || true
    fi
    if [ "$CHECK_IMAGE_BUILT" = "1" ]; then
        "${RUNTIME_ENV[@]}" "$RUNTIME" rmi "$CHECK_IMAGE" >/dev/null 2>&1 || true
    fi
    if [ "$IMAGE_BUILT" = "1" ]; then
        "${RUNTIME_ENV[@]}" "$RUNTIME" rmi "$IMAGE" >/dev/null 2>&1 || true
    fi
    rm -rf "$TMP_ROOT"
}

SMOKE_HOME="$TMP_ROOT/home"
WORKSPACE="$TMP_ROOT/workspace"
HISTORY="$TMP_ROOT/history"
OTHER_HOST_PATH="$TMP_ROOT/other-host-path"
XDG_CONFIG_HOME_SMOKE="$TMP_ROOT/xdg-config"
XDG_CACHE_HOME_SMOKE="$TMP_ROOT/xdg-cache"
DOCKER_CONFIG_SMOKE="$TMP_ROOT/docker-config"
REGISTRY_AUTH_FILE_SMOKE="$TMP_ROOT/registry-auth.json"
mkdir -p "$SMOKE_HOME" "$WORKSPACE" "$HISTORY" "$OTHER_HOST_PATH" \
    "$XDG_CONFIG_HOME_SMOKE" "$XDG_CACHE_HOME_SMOKE" "$DOCKER_CONFIG_SMOKE"
printf '{}\n' > "$DOCKER_CONFIG_SMOKE/config.json"
printf '{}\n' > "$REGISTRY_AUTH_FILE_SMOKE"

git -C "$WORKSPACE" init -q
printf 'security smoke workspace\n' > "$WORKSPACE/README.md"

COMMON_ENV=(
    env -i
    "PATH=$PATH"
    "TERM=${TERM:-dumb}"
    "TZ=${TZ:-UTC}"
    "USER=${USER:-agent-smoke}"
    "LOGNAME=${LOGNAME:-agent-smoke}"
    "PYTHONDONTWRITEBYTECODE=1"
    "XDG_CONFIG_HOME=$XDG_CONFIG_HOME_SMOKE"
    "XDG_CACHE_HOME=$XDG_CACHE_HOME_SMOKE"
    "DOCKER_CONFIG=$DOCKER_CONFIG_SMOKE"
    "REGISTRY_AUTH_FILE=$REGISTRY_AUTH_FILE_SMOKE"
)

if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    COMMON_ENV+=("XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR")
fi
if [ -n "${DOCKER_HOST:-}" ]; then
    COMMON_ENV+=("DOCKER_HOST=$DOCKER_HOST")
fi
if [ -n "${CONTAINER_HOST:-}" ]; then
    COMMON_ENV+=("CONTAINER_HOST=$CONTAINER_HOST")
fi
if [ -n "${PODMAN_HOST:-}" ]; then
    COMMON_ENV+=("PODMAN_HOST=$PODMAN_HOST")
fi
if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    COMMON_ENV+=("DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS")
fi

DRY_RUN_ENV=("${COMMON_ENV[@]}" "HOME=$SMOKE_HOME")
RUNTIME_ENV=("${COMMON_ENV[@]}" "HOME=$REAL_HOME")
trap cleanup EXIT

run_launcher() {
    "${DRY_RUN_ENV[@]}" "$LAUNCHER" \
        --dry-run \
        --runtime "$RUNTIME" \
        --workspace "$WORKSPACE" \
        --history-dir "$HISTORY" \
        "$@" 2>&1
}

expect_rejected() {
    local label="$1"
    shift
    local output
    local status

    set +e
    output="$(run_launcher "$@")"
    status=$?
    set -e

    if [ "$status" -eq 0 ]; then
        printf '%s\n' "$output" >&2
        fail "$label was accepted"
    fi
    assert_contains "$output" "ERROR:"
}

log "Checking dry-run command shape"
dry_run_output="$(run_launcher)"
assert_contains "$dry_run_output" "--cap-drop=ALL"
assert_contains "$dry_run_output" "--cap-add=NET_ADMIN"
assert_contains "$dry_run_output" "--cap-add=SETGID"
assert_contains "$dry_run_output" "--cap-add=SETUID"
assert_contains "$dry_run_output" "--security-opt=no-new-privileges:true"
assert_contains "$dry_run_output" "--volume=$WORKSPACE:/workspace:z"
assert_contains "$dry_run_output" "--volume=$HISTORY:/commandhistory:z"
assert_contains "$dry_run_output" "--volume=$WORKSPACE/.git:/workspace/.git:ro,z"

cap_add_count="$(grep -o -- '--cap-add=' <<< "$dry_run_output" | wc -l | tr -d '[:space:]')"
if [ "$cap_add_count" != "3" ]; then
    fail "expected exactly 3 cap-add flags, found $cap_add_count"
fi

log "Checking rejected runtime flags"
expect_rejected "--privileged" --privileged
expect_rejected "--volume" --volume "$OTHER_HOST_PATH:/other"
expect_rejected "--mount" --mount "type=bind,src=$OTHER_HOST_PATH,dst=/other"
expect_rejected "--network" --network=host
expect_rejected "--dns" --dns=1.1.1.1
expect_rejected "--env-host" --env-host
expect_rejected "protected env passthrough" --env AGENTS_DISABLE_FIREWALL=1
expect_rejected "--detach" --detach
expect_rejected "-d" -d
expect_rejected "--restart" --restart=always
expect_rejected "--rm=false" --rm=false
expect_rejected "--cidfile" --cidfile "$TMP_ROOT/cid"
expect_rejected "--pidfile" --pidfile "$TMP_ROOT/pid"
expect_rejected "--authfile" --authfile "$TMP_ROOT/auth.json"
expect_rejected "--cert-dir" --cert-dir "$TMP_ROOT/certs"

log "Checking custom image guard"
expect_rejected "custom image without opt-in" "$IMAGE" /bin/true
custom_image_output="$(run_launcher --allow-custom-image "$IMAGE" /bin/true)"
assert_contains "$custom_image_output" "$IMAGE"
assert_contains "$custom_image_output" "DANGER: YOU ARE OVERRIDING A CONTAINER SAFETY REJECTION."
custom_image_env_output="$(
    "${DRY_RUN_ENV[@]}" AGENTS_ALLOW_CUSTOM_IMAGE=1 "$LAUNCHER" \
        --dry-run \
        --runtime "$RUNTIME" \
        --workspace "$WORKSPACE" \
        --history-dir "$HISTORY" \
        "$IMAGE" /bin/true 2>&1
)"
assert_contains "$custom_image_env_output" "$IMAGE"

run_nested_mount_check() {
    if ! command -v mount >/dev/null 2>&1 ||
        ! command -v umount >/dev/null 2>&1 ||
        ! command -v mountpoint >/dev/null 2>&1; then
        log "Skipping nested mount check; mount tools are unavailable"
        return
    fi
    if [ "$(id -u)" -ne 0 ]; then
        log "Skipping nested mount check; bind mounting requires root"
        return
    fi

    NESTED_MOUNT="$WORKSPACE/nested-mount"
    mkdir -p "$NESTED_MOUNT"
    if ! mount --bind "$OTHER_HOST_PATH" "$NESTED_MOUNT"; then
        log "Skipping nested mount check; bind mount failed"
        NESTED_MOUNT=""
        return
    fi

    expect_rejected "nested workspace mount" 
    nested_allow_output="$(run_launcher --allow-unsafe-host-path "$NESTED_MOUNT")"
    assert_contains "$nested_allow_output" "DANGER: YOU ARE OVERRIDING A CONTAINER SAFETY REJECTION."

    umount "$NESTED_MOUNT"
    NESTED_MOUNT=""
}

run_container_checks() {
    local output
    local status

    set +e
    output="$(
        "${RUNTIME_ENV[@]}" "$LAUNCHER" \
            --runtime "$RUNTIME" \
            --workspace "$WORKSPACE" \
            --history-dir "$HISTORY" \
            --allow-custom-image \
            --no-tty \
            "$CHECK_IMAGE" 2>&1
    )"
    status=$?
    set -e

    printf '%s\n' "$output"
    if [ "$status" -ne 0 ]; then
        fail "container runtime smoke failed with status $status"
    fi

    assert_contains "$output" "startup-ok"
    assert_contains "$output" "git-readonly-ok"
    assert_contains "$output" "external-blocked-ok"
    assert_not_contains "$output" "Firewall verification passed - reached"
}

run_nested_mount_check

if [ "${AGENTS_SMOKE_SKIP_BUILD:-0}" = "1" ]; then
    log "Skipping image build and runtime launch because AGENTS_SMOKE_SKIP_BUILD=1"
else
    log "Building local test image with $RUNTIME: $IMAGE"
    "${RUNTIME_ENV[@]}" "$RUNTIME" build -t "$IMAGE" "$REPO_ROOT"
    IMAGE_BUILT=1

    check_containerfile="$TMP_ROOT/Containerfile.check"
    printf 'FROM %s\nCMD ["/bin/bash", "-lc", "%s"]\n' \
        "$IMAGE" \
        "$CONTAINER_SCRIPT" > "$check_containerfile"
    log "Building derived runtime-check image with $RUNTIME: $CHECK_IMAGE"
    "${RUNTIME_ENV[@]}" "$RUNTIME" build -t "$CHECK_IMAGE" -f "$check_containerfile" "$TMP_ROOT"
    CHECK_IMAGE_BUILT=1

    log "Launching local test image under the default firewall"
    run_container_checks
fi

log "Security smoke checks passed"
