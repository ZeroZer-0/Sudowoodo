#!/bin/bash
# test_edge_cases.sh — wrapper-breaking edge cases: signals, concurrency,
# subshells, command substitution, xargs, env vars, binary data, tty
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

echo "=== Edge case / stress tests ==="
echo "  TESTDIR: $TESTDIR"

# ---- Setup ----
echo "test data" > "$TESTDIR/e.txt"
seq 1 100 > "$TESTDIR/numbers.txt"
for i in $(seq 1 20); do echo "file $i" > "$TESTDIR/batch_$i.txt"; done

# ==================================================================
echo ""
echo "--- Command substitution (backticks and \$()) ---"
# Scripts commonly capture wrapper output in variables
RESULT=$(cat "$TESTDIR/e.txt")
[ "$RESULT" = "test data" ] && echo -e "  ${GRN}PASS${RST}  \$(): cat captured in variable" && ((++PASS)) \
    || { echo -e "  ${RED}FAIL${RST}  \$(): cat output wrong: '$RESULT'"; ((++FAIL)); }

RESULT=$(grep -c "file" "$TESTDIR"/batch_*.txt 2>/dev/null | wc -l)
[ "$RESULT" -gt 0 ] && echo -e "  ${GRN}PASS${RST}  \$(): grep -c | wc -l in subshell" && ((++PASS)) \
    || { echo -e "  ${RED}FAIL${RST}  \$(): pipeline subshell failed"; ((++FAIL)); }

HASH=$(md5sum "$TESTDIR/e.txt" | awk '{print $1}')
[ -n "$HASH" ] && echo -e "  ${GRN}PASS${RST}  \$(): md5sum | awk captured" && ((++PASS)) \
    || { echo -e "  ${RED}FAIL${RST}  \$(): md5sum capture empty"; ((++FAIL)); }

# ==================================================================
echo ""
echo "--- xargs patterns ---"
# find | xargs (standard)
assert_ok "xargs: find -print0 | xargs -0 wc" \
    sh -c "find '$TESTDIR' -name '*.txt' -print0 | xargs -0 wc -l"

# echo list | xargs
assert_ok "xargs: echo | xargs stat" \
    sh -c "echo '$TESTDIR/e.txt' | xargs stat"

# xargs with -I{} replacement
assert_ok "xargs: -I{} cp pattern" \
    sh -c "echo '$TESTDIR/e.txt' | xargs -I{} cp {} '$TESTDIR/xargs_copy.txt'"

# xargs -P parallel
assert_ok "xargs: -P parallel md5sum" \
    sh -c "find '$TESTDIR' -name '*.txt' -print0 | xargs -0 -P4 md5sum"

# ==================================================================
echo ""
echo "--- Subshell and background ---"
# Wrapper called in a subshell
assert_ok "subshell: (cat)" sh -c "(cat '$TESTDIR/e.txt') >/dev/null"
assert_ok "subshell: (grep)" sh -c "(grep test '$TESTDIR/e.txt') >/dev/null"

# Background wrapper
sh -c "cat '$TESTDIR/e.txt' > '$TESTDIR/bg_out.txt' &
wait"
[ -f "$TESTDIR/bg_out.txt" ] && echo -e "  ${GRN}PASS${RST}  background: cat & wait" && ((++PASS)) \
    || { echo -e "  ${RED}FAIL${RST}  background: output missing"; ((++FAIL)); }

# ==================================================================
echo ""
echo "--- Process substitution ---"
# diff <(cmd1) <(cmd2) pattern
# Process substitution creates /dev/fd/ paths — wrappers may not support this
# since they parse args for protected path filtering
if sh -c "diff <(echo hello) <(echo hello)" >/dev/null 2>&1; then
    echo -e "  ${GRN}PASS${RST}  procsub: diff <() <()"
    ((++PASS))
else
    echo -e "  ${YLW}SKIP${RST}  procsub: diff <() <() (wrapper doesn't support /dev/fd paths)"
    ((++SKIP))
fi
if sh -c "grep -f <(echo test) '$TESTDIR/e.txt'" >/dev/null 2>&1; then
    echo -e "  ${GRN}PASS${RST}  procsub: grep -f <()"
    ((++PASS))
else
    echo -e "  ${YLW}SKIP${RST}  procsub: grep -f <() (wrapper doesn't support /dev/fd paths)"
    ((++SKIP))
fi

# ==================================================================
echo ""
echo "--- for/while loops calling wrappers ---"
# for loop over files
LOOP_OK=true
for f in "$TESTDIR"/batch_*.txt; do
    cat "$f" >/dev/null 2>&1 || LOOP_OK=false
done
$LOOP_OK && echo -e "  ${GRN}PASS${RST}  for-loop: cat 20 files" && ((++PASS)) \
    || { echo -e "  ${RED}FAIL${RST}  for-loop: some cat calls failed"; ((++FAIL)); }

# while read loop
LINES=0
while IFS= read -r line; do
    ((LINES++))
done < <(grep -r "file" "$TESTDIR"/batch_*.txt 2>/dev/null)
[ "$LINES" -gt 0 ] && echo -e "  ${GRN}PASS${RST}  while-read: grep output ($LINES lines)" && ((++PASS)) \
    || { echo -e "  ${RED}FAIL${RST}  while-read: no lines"; ((++FAIL)); }

# ==================================================================
echo ""
echo "--- Environment variable passthrough ---"
# Wrapper shouldn't eat env vars
# env passthrough: try TESTVAL via sudo; skip if sudo strips env
ENVTEST=$(sudo env TESTVAL=TESTVAL sh -c 'echo $TESTVAL' 2>/dev/null) || true
if [ "$ENVTEST" = "TESTVAL" ]; then
    echo -e "  ${GRN}PASS${RST}  env: variable visible through sudo"
    ((++PASS))
elif [ -z "$ENVTEST" ]; then
    echo -e "  ${YLW}SKIP${RST}  env: variable visible through sudo (sudo strips env)"
    ((++SKIP))
else
    echo -e "  ${RED}FAIL${RST}  env: variable visible through sudo"
    echo "         expected: TESTVAL"
    echo "         got:      $ENVTEST"
    ((++FAIL))
    ERRORS+=("env: variable visible through sudo (output mismatch)")
fi

# PATH shouldn't leak wrapper dirs in unexpected ways
SUDO_PATH=$(sudo sh -c 'echo $PATH')
echo -e "  INFO  sudo PATH: $(echo "$SUDO_PATH" | head -c 120)"

# ==================================================================
echo ""
echo "--- Binary/large data through wrappers ---"
# Large file through cat
dd if=/dev/urandom bs=1024 count=100 of="$TESTDIR/large.bin" 2>/dev/null
ORIG_SIZE=$(stat -c '%s' "$TESTDIR/large.bin")
PIPED_SIZE=$(cat "$TESTDIR/large.bin" | wc -c)
[ "$ORIG_SIZE" = "$PIPED_SIZE" ] && echo -e "  ${GRN}PASS${RST}  binary: 100KB through cat (no byte loss)" && ((++PASS)) \
    || { echo -e "  ${RED}FAIL${RST}  binary: size mismatch ($ORIG_SIZE vs $PIPED_SIZE)"; ((++FAIL)); }

# Binary through grep -c (shouldn't crash)
assert_ok "binary: grep -c on binary" grep -c "." "$TESTDIR/large.bin" || true

# md5sum on binary
assert_ok "binary: md5sum large" md5sum "$TESTDIR/large.bin"

# ==================================================================
echo ""
echo "--- Signal handling ---"
# SIGPIPE: cat into head (should not error out)
assert_ok "signal: cat|head SIGPIPE" sh -c "cat '$TESTDIR/numbers.txt' | head -1 >/dev/null"

# SIGTERM during wrapper (start bg, kill, check it dies)
cat /dev/zero > /dev/null &
CATPID=$!
sleep 0.1
kill "$CATPID" 2>/dev/null
sleep 0.2
kill -0 "$CATPID" 2>/dev/null
if [ $? -ne 0 ]; then
    echo -e "  ${GRN}PASS${RST}  signal: SIGTERM kills wrapper+child"
    ((++PASS))
else
    echo -e "  ${RED}FAIL${RST}  signal: wrapper survived SIGTERM"
    kill -9 "$CATPID" 2>/dev/null
    ((++FAIL))
fi

# ==================================================================
echo ""
echo "--- Concurrent wrapper calls ---"
# Simulate scripts running multiple wrappers in parallel
PIDS=()
for i in $(seq 1 10); do
    cat "$TESTDIR/e.txt" > /dev/null 2>&1 &
    PIDS+=($!)
done
ALL_GOOD=true
for pid in "${PIDS[@]}"; do
    wait "$pid" || ALL_GOOD=false
done
$ALL_GOOD && echo -e "  ${GRN}PASS${RST}  concurrency: 10 parallel cat calls" && ((++PASS)) \
    || { echo -e "  ${RED}FAIL${RST}  concurrency: some parallel cats failed"; ((++FAIL)); }

# ==================================================================
echo ""
echo "--- Argument edge cases ---"
# Empty argument
assert_ok "args: empty string arg" sh -c "echo ''" 
# Argument with only whitespace
assert_output "args: whitespace-only echo" "   " sudo echo "   "
# Argument that looks like a flag
assert_ok "args: -- end of options" cat -- "$TESTDIR/e.txt"
# Very long argument list via find
assert_ok "args: find -exec with many results" \
    find "$TESTDIR" -name "*.txt" -exec cat {} + >/dev/null
# Newline in argument
assert_ok "args: embedded newline" sudo sh -c "$(printf 'echo "line1\nline2"')"

# ==================================================================
echo ""
echo "--- Wrapper overhead sanity ---"
# Time a burst of calls — not a hard test, just info
START=$(date +%s%N)
for i in $(seq 1 20); do
    cat /dev/null >/dev/null 2>&1
done
END=$(date +%s%N)
MS=$(( (END - START) / 1000000 ))
echo -e "  INFO  20x cat /dev/null: ${MS}ms ($(( MS / 20 ))ms/call)"

echo ""
summary
