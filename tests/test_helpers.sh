#!/bin/bash
# test_helpers.sh — shared utilities for the Sudowoodo test suite
# Source this, don't execute it.

PASS=0
FAIL=0
SKIP=0
ERRORS=()

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[0;33m'
RST='\033[0m'

assert_ok() {
    local desc="$1"; shift
    "$@" >/dev/null 2>&1
    local rc=$?
    if [ $rc -eq 0 ]; then
        echo -e "  ${GRN}PASS${RST}  $desc"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${RST}  $desc  (exit $rc)"
        ((FAIL++))
        ERRORS+=("$desc (exit $rc)")
    fi
}

assert_fail() {
    local desc="$1"; shift
    "$@" >/dev/null 2>&1
    local rc=$?
    if [ $rc -ne 0 ]; then
        echo -e "  ${GRN}PASS${RST}  $desc  (expected failure, got $rc)"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${RST}  $desc  (expected failure, got 0)"
        ((FAIL++))
        ERRORS+=("$desc (expected nonzero, got 0)")
    fi
}

assert_output() {
    local desc="$1"
    local expected="$2"
    shift 2
    local actual
    actual=$("$@" 2>/dev/null)
    local rc=$?
    if [ "$actual" = "$expected" ]; then
        echo -e "  ${GRN}PASS${RST}  $desc"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${RST}  $desc"
        echo "         expected: $(echo "$expected" | head -c 120)"
        echo "         got:      $(echo "$actual" | head -c 120)"
        ((FAIL++))
        ERRORS+=("$desc (output mismatch)")
    fi
}

assert_output_contains() {
    local desc="$1"
    local needle="$2"
    shift 2
    local actual
    actual=$("$@" 2>&1)
    if echo "$actual" | grep -qF "$needle"; then
        echo -e "  ${GRN}PASS${RST}  $desc"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${RST}  $desc  (missing: $needle)"
        ((FAIL++))
        ERRORS+=("$desc (output missing '$needle')")
    fi
}

assert_exit_code() {
    local desc="$1"
    local expected_rc="$2"
    shift 2
    "$@" >/dev/null 2>&1
    local rc=$?
    if [ $rc -eq "$expected_rc" ]; then
        echo -e "  ${GRN}PASS${RST}  $desc"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${RST}  $desc  (expected exit $expected_rc, got $rc)"
        ((FAIL++))
        ERRORS+=("$desc (exit $rc != $expected_rc)")
    fi
}

skip_test() {
    local desc="$1"
    local reason="$2"
    echo -e "  ${YLW}SKIP${RST}  $desc  ($reason)"
    ((SKIP++))
}

summary() {
    echo ""
    echo "========================================"
    echo -e "  ${GRN}PASS: $PASS${RST}  ${RED}FAIL: $FAIL${RST}  ${YLW}SKIP: $SKIP${RST}"
    if [ ${#ERRORS[@]} -gt 0 ]; then
        echo ""
        echo "  Failed tests:"
        for e in "${ERRORS[@]}"; do
            echo -e "    ${RED}✗${RST} $e"
        done
    fi
    echo "========================================"
    return $FAIL
}

# Create a temp dir that cleans itself up
TESTDIR=$(mktemp -d /tmp/sudowoodo-test.XXXXXX)
trap "rm -rf '$TESTDIR'" EXIT
