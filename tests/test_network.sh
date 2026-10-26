#!/bin/bash
# test_network.sh — test network discovery wrappers (netstat, ss, lsof, nmap, fuser)
# Non-destructive: read-only operations only.
# Must run AFTER deploy so wrappers are in /usr/local/bin and Karen is on port 8443.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

echo "=== Network wrapper tests ==="
echo ""

# ---- netstat ----
echo "--- netstat ---"
if command -v netstat >/dev/null 2>&1; then
    assert_ok "netstat: basic" netstat
    assert_ok "netstat: -tulpn" sudo netstat -tulpn
    assert_ok "netstat: -an" netstat -an

    # Filtering test: port 8443 should NOT appear in output
    if sudo netstat -tulpn 2>/dev/null | grep -q ":8443 "; then
        echo -e "  ${RED}FAIL${RST}  netstat: port 8443 visible (should be hidden)"
        ((FAIL++))
    else
        echo -e "  ${GRN}PASS${RST}  netstat: port 8443 hidden"
        ((PASS++))
    fi

    # Legitimate ports should still show
    if sudo netstat -tulpn 2>/dev/null | grep -q ":22 "; then
        echo -e "  ${GRN}PASS${RST}  netstat: port 22 (SSH) still visible"
        ((PASS++))
    else
        skip_test "netstat: port 22 visibility" "SSH not listening (can't verify passthrough)"
    fi
else
    skip_test "netstat: all" "not available (net-tools not installed)"
fi

# ---- ss ----
echo ""
echo "--- ss ---"
if command -v ss >/dev/null 2>&1; then
    assert_ok "ss: basic" ss
    assert_ok "ss: -tulpn" sudo ss -tulpn
    assert_ok "ss: -an" ss -an
    assert_ok "ss: -tnp" sudo ss -tnp

    # Filtering test: port 8443 should NOT appear
    if sudo ss -tulpn 2>/dev/null | grep -q ":8443 "; then
        echo -e "  ${RED}FAIL${RST}  ss: port 8443 visible (should be hidden)"
        ((FAIL++))
    else
        echo -e "  ${GRN}PASS${RST}  ss: port 8443 hidden"
        ((PASS++))
    fi

    # Legitimate ports should still show
    if sudo ss -tulpn 2>/dev/null | grep -q ":22 "; then
        echo -e "  ${GRN}PASS${RST}  ss: port 22 (SSH) still visible"
        ((PASS++))
    else
        skip_test "ss: port 22 visibility" "SSH not listening (can't verify passthrough)"
    fi
else
    skip_test "ss: all" "not available"
fi

# ---- lsof ----
echo ""
echo "--- lsof ---"
if command -v lsof >/dev/null 2>&1; then
    assert_ok "lsof: -i (all network)" sudo lsof -i
    assert_ok "lsof: -i TCP" sudo lsof -i TCP
    assert_ok "lsof: -i :22 (SSH)" sudo lsof -i :22

    # Filtering test: port 8443 should NOT appear
    if sudo lsof -i :8443 2>/dev/null | grep -q "8443"; then
        echo -e "  ${RED}FAIL${RST}  lsof: port 8443 visible (should be hidden)"
        ((FAIL++))
    else
        echo -e "  ${GRN}PASS${RST}  lsof: port 8443 hidden"
        ((PASS++))
    fi

    # lsof -i (all) should not show 8443 either
    if sudo lsof -i 2>/dev/null | grep -q ":8443"; then
        echo -e "  ${RED}FAIL${RST}  lsof: port 8443 visible in -i listing (should be hidden)"
        ((FAIL++))
    else
        echo -e "  ${GRN}PASS${RST}  lsof: port 8443 hidden from -i listing"
        ((PASS++))
    fi
else
    skip_test "lsof: all" "not available"
fi

# ---- nmap ----
echo ""
echo "--- nmap ---"
if command -v nmap >/dev/null 2>&1; then
    assert_ok "nmap: localhost quick scan" timeout 30 nmap -sT -p 22 localhost

    # Filtering test: scan for 8443 should not show open
    NMAP_OUT=$(timeout 30 nmap -sT -p 8443 localhost 2>/dev/null)
    if echo "$NMAP_OUT" | grep -q "8443/tcp.*open"; then
        echo -e "  ${RED}FAIL${RST}  nmap: port 8443 shows open (should be hidden)"
        ((FAIL++))
    else
        echo -e "  ${GRN}PASS${RST}  nmap: port 8443 hidden from scan"
        ((PASS++))
    fi
else
    skip_test "nmap: all" "not available"
fi

# ---- fuser ----
echo ""
echo "--- fuser ---"
if command -v fuser >/dev/null 2>&1; then
    # fuser for a known port should work
    assert_ok "fuser: 22/tcp (SSH)" sudo fuser 22/tcp

    # fuser for 8443 should return nothing (exit 1)
    if sudo fuser 8443/tcp >/dev/null 2>&1; then
        echo -e "  ${RED}FAIL${RST}  fuser: 8443/tcp returned a PID (should be blocked)"
        ((FAIL++))
    else
        echo -e "  ${GRN}PASS${RST}  fuser: 8443/tcp blocked (no output)"
        ((PASS++))
    fi

    # fuser for 9001 should also return nothing
    if sudo fuser 9001/tcp >/dev/null 2>&1; then
        echo -e "  ${RED}FAIL${RST}  fuser: 9001/tcp returned a PID (should be blocked)"
        ((FAIL++))
    else
        echo -e "  ${GRN}PASS${RST}  fuser: 9001/tcp blocked (no output)"
        ((PASS++))
    fi
else
    skip_test "fuser: all" "not available"
fi

echo ""
summary
