#!/bin/bash
# test_file_ops.sh — test defense/monitoring wrappers with real-world usage patterns
# Non-destructive: all work happens in a temp dir.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

echo "=== File operation wrapper tests ==="
echo "  TESTDIR: $TESTDIR"

# ---- Setup test fixtures ----
echo "hello world" > "$TESTDIR/simple.txt"
echo -e "line1\nline2\nline3" > "$TESTDIR/multi.txt"
echo '{"key":"val.ue","num":4.2}' > "$TESTDIR/data.json"
printf 'binary\x00content\x01here\x02' > "$TESTDIR/binary.bin"
mkdir -p "$TESTDIR/subdir/nested"
echo "nested file" > "$TESTDIR/subdir/file.txt"
echo "deep file" > "$TESTDIR/subdir/nested/deep.txt"
# Files with evil names
touch "$TESTDIR/has spaces.txt"
touch "$TESTDIR/has\"quotes.txt"
touch "$TESTDIR/has\$dollar.txt"
echo "special" > "$TESTDIR/has spaces.txt"

echo ""
echo "--- cat ---"
assert_output "cat: basic read" "hello world" cat "$TESTDIR/simple.txt"
assert_output "cat: multi-file concat" "$(printf 'hello world\nline1\nline2\nline3')" \
    cat "$TESTDIR/simple.txt" "$TESTDIR/multi.txt"
assert_output "cat: stdin passthrough" "piped data" sh -c 'echo "piped data" | cat'
assert_output "cat: /dev/null" "" cat /dev/null
assert_ok "cat: binary file doesn't crash" cat "$TESTDIR/binary.bin"
assert_output "cat: file with spaces in name" "special" cat "$TESTDIR/has spaces.txt"
# here-doc through cat (common script pattern)
assert_output "cat: heredoc" "injected" sh -c "cat <<'X'
injected
X"
# cat -n (numbered lines)
assert_output_contains "cat -n: numbered output" "     1" cat -n "$TESTDIR/simple.txt"

echo ""
echo "--- grep ---"
assert_output "grep: basic match" "line2" grep "line2" "$TESTDIR/multi.txt"
assert_exit_code "grep: no match returns 1" 1 grep "nonexistent" "$TESTDIR/multi.txt"
assert_output "grep: -c count" "3" grep -c "line" "$TESTDIR/multi.txt"
assert_ok "grep: -r recursive" grep -r "nested" "$TESTDIR/subdir/"
assert_ok "grep: -l files-with-matches" grep -rl "line" "$TESTDIR/"
assert_output "grep: -i case insensitive" "hello world" grep -i "HELLO" "$TESTDIR/simple.txt"
assert_ok "grep: -E extended regex" grep -E 'line[0-9]+' "$TESTDIR/multi.txt"
assert_ok "grep: -P perl regex" grep -P '\d' "$TESTDIR/multi.txt" || true
# pipe pattern (very common)
assert_output "grep: stdin pipe" "line2" sh -c "cat '$TESTDIR/multi.txt' | grep line2"
# grep | wc -l pattern
assert_output "grep|wc: count matches" "3" sh -c "grep 'line' '$TESTDIR/multi.txt' | wc -l"
# grep -v invert
assert_output "grep -v: invert match" "hello world" \
    sh -c "cat '$TESTDIR/simple.txt' '$TESTDIR/multi.txt' | grep -v line"
# grep with special chars in pattern
assert_output "grep: literal dot" '{"key":"val.ue","num":4.2}' grep '\.' "$TESTDIR/data.json"
# grep -q quiet mode (scripts check $? only)
assert_ok "grep -q: quiet match" grep -q "hello" "$TESTDIR/simple.txt"
assert_fail "grep -q: quiet no-match" grep -q "zzzzz" "$TESTDIR/simple.txt"

echo ""
echo "--- ls ---"
assert_ok "ls: basic listing" ls "$TESTDIR"
assert_ok "ls: -la long+hidden" ls -la "$TESTDIR"
assert_ok "ls: -1 one-per-line" ls -1 "$TESTDIR"
assert_ok "ls: -R recursive" ls -R "$TESTDIR"
assert_ok "ls: -t time sort" ls -t "$TESTDIR"
assert_ok "ls: -S size sort" ls -lS "$TESTDIR"
assert_ok "ls: multiple dirs" ls "$TESTDIR" "$TESTDIR/subdir"
# ls | while read pattern (common in scripts)
COUNT=$(ls -1 "$TESTDIR" | wc -l)
[ "$COUNT" -gt 0 ] && echo -e "  ${GRN}PASS${RST}  ls|wc: got $COUNT entries" && ((PASS++)) \
    || { echo -e "  ${RED}FAIL${RST}  ls|wc: no entries"; ((FAIL++)); }
# ls nonexistent
assert_fail "ls: nonexistent dir returns error" ls "$TESTDIR/nope_not_here"

echo ""
echo "--- find ---"
assert_ok "find: basic" find "$TESTDIR" -type f
assert_ok "find: -name glob" find "$TESTDIR" -name "*.txt"
assert_ok "find: -name -exec" find "$TESTDIR" -name "*.txt" -exec wc -l {} \;
assert_ok "find: -name -exec +" find "$TESTDIR" -name "*.txt" -exec wc -l {} +
assert_ok "find: -maxdepth" find "$TESTDIR" -maxdepth 1 -type f
assert_ok "find: -newer" find "$TESTDIR" -newer "$TESTDIR/simple.txt"
# find with -print0 | xargs -0 pattern
assert_ok "find|xargs: null-delimited" \
    sh -c "find '$TESTDIR' -name '*.txt' -print0 | xargs -0 wc -l"
# find on file with spaces
FOUND=$(find "$TESTDIR" -name "has spaces.txt" | wc -l)
[ "$FOUND" -eq 1 ] && echo -e "  ${GRN}PASS${RST}  find: file with spaces" && ((PASS++)) \
    || { echo -e "  ${RED}FAIL${RST}  find: file with spaces (found $FOUND)"; ((FAIL++)); }

echo ""
echo "--- stat ---"
assert_ok "stat: basic" stat "$TESTDIR/simple.txt"
assert_ok "stat: -c format" stat -c '%a %U %s' "$TESTDIR/simple.txt"
assert_ok "stat: multiple files" stat "$TESTDIR/simple.txt" "$TESTDIR/multi.txt"
assert_fail "stat: nonexistent" stat "$TESTDIR/nope"

echo ""
echo "--- file ---"
assert_output_contains "file: text detection" "text" file "$TESTDIR/simple.txt"
assert_output_contains "file: json detection" "text" file "$TESTDIR/data.json"
assert_ok "file: binary" file "$TESTDIR/binary.bin"
assert_ok "file: -i mime type" file -i "$TESTDIR/simple.txt"

echo ""
echo "--- cp ---"
assert_ok "cp: basic copy" cp "$TESTDIR/simple.txt" "$TESTDIR/copy1.txt"
assert_output "cp: content preserved" "hello world" cat "$TESTDIR/copy1.txt"
assert_ok "cp: -r recursive" cp -r "$TESTDIR/subdir" "$TESTDIR/subdir_copy"
assert_ok "cp: -p preserve" cp -p "$TESTDIR/simple.txt" "$TESTDIR/copy2.txt"
assert_ok "cp: -a archive" cp -a "$TESTDIR/subdir" "$TESTDIR/subdir_archive"
# cp file with spaces
assert_ok "cp: filename with spaces" cp "$TESTDIR/has spaces.txt" "$TESTDIR/copied spaces.txt"

echo ""
echo "--- mv ---"
echo "moveme" > "$TESTDIR/tomove.txt"
assert_ok "mv: basic rename" mv "$TESTDIR/tomove.txt" "$TESTDIR/moved.txt"
assert_output "mv: content preserved" "moveme" cat "$TESTDIR/moved.txt"
assert_fail "mv: source gone" test -f "$TESTDIR/tomove.txt"
# mv back
mv "$TESTDIR/moved.txt" "$TESTDIR/tomove.txt" 2>/dev/null

echo ""
echo "--- rm ---"
echo "deleteme" > "$TESTDIR/todelete.txt"
assert_ok "rm: basic delete" rm "$TESTDIR/todelete.txt"
assert_fail "rm: file gone" test -f "$TESTDIR/todelete.txt"
mkdir -p "$TESTDIR/rmdir_test/inner"
echo x > "$TESTDIR/rmdir_test/inner/f.txt"
assert_ok "rm: -rf recursive" rm -rf "$TESTDIR/rmdir_test"
assert_fail "rm: dir gone" test -d "$TESTDIR/rmdir_test"
# rm nonexistent (should fail)
assert_fail "rm: nonexistent fails" rm "$TESTDIR/nope_not_here_$$"

echo ""
echo "--- chmod ---"
echo "chmodtest" > "$TESTDIR/chmod_test.txt"
assert_ok "chmod: numeric mode" chmod 644 "$TESTDIR/chmod_test.txt"
assert_ok "chmod: symbolic +x" chmod +x "$TESTDIR/chmod_test.txt"
assert_ok "chmod: symbolic u+rw" chmod u+rw "$TESTDIR/chmod_test.txt"
assert_ok "chmod: -R recursive" chmod -R 755 "$TESTDIR/subdir"
PERMS=$(stat -c '%a' "$TESTDIR/chmod_test.txt")
echo -e "  INFO  chmod_test.txt perms after +x: $PERMS"

echo ""
echo "--- chown ---"
# chown needs root to actually change, but shouldn't crash
MYUSER=$(whoami)
assert_ok "chown: own user (noop)" chown "$MYUSER" "$TESTDIR/simple.txt" || true
# chown to another user will fail without root — that's fine, just shouldn't crash the wrapper
echo -e "  ${YLW}SKIP${RST}  chown: cross-user (needs root)"
((SKIP++))

echo ""
echo "--- diff ---"
echo "hello world" > "$TESTDIR/diff_a.txt"
echo "hello mars" > "$TESTDIR/diff_b.txt"
assert_exit_code "diff: files differ returns 1" 1 diff "$TESTDIR/diff_a.txt" "$TESTDIR/diff_b.txt"
assert_exit_code "diff: identical returns 0" 0 diff "$TESTDIR/simple.txt" "$TESTDIR/copy1.txt"
assert_exit_code "diff: -u unified format" 1 diff -u "$TESTDIR/diff_a.txt" "$TESTDIR/diff_b.txt"

echo ""
echo "--- md5sum / sha256sum ---"
assert_ok "md5sum: basic" md5sum "$TESTDIR/simple.txt"
assert_ok "md5sum: multiple files" md5sum "$TESTDIR/simple.txt" "$TESTDIR/multi.txt"
assert_ok "sha256sum: basic" sha256sum "$TESTDIR/simple.txt"
# check mode
md5sum "$TESTDIR/simple.txt" > "$TESTDIR/checkfile.md5"
assert_ok "md5sum: -c check" md5sum -c "$TESTDIR/checkfile.md5"
# pipe pattern
assert_ok "md5sum: stdin pipe" sh -c "echo test | md5sum"

echo ""
echo "--- which ---"
assert_ok "which: bash" which bash
assert_ok "which: ls" which ls
assert_ok "which: grep" which grep
assert_fail "which: nonexistent" which definitely_not_a_real_command_$$

echo ""
echo "--- strings ---"
assert_ok "strings: basic" strings "$TESTDIR/binary.bin"
assert_ok "strings: text file" strings "$TESTDIR/simple.txt"

echo ""
echo "--- kill ---"
# Start a background sleep, kill it, verify
sleep 300 &
BGPID=$!
assert_ok "kill: SIGTERM background proc" kill "$BGPID"
for _i in $(seq 1 20); do kill -0 "$BGPID" 2>/dev/null || break; sleep 0.1; done
assert_fail "kill: proc is dead" kill -0 "$BGPID" 2>/dev/null
# kill nonexistent PID
assert_fail "kill: nonexistent PID" kill 99999999

echo ""
echo "--- Special character stress tests ---"
# Filenames with nasty chars through wrappers
echo 'content' > "$TESTDIR/back\\slash.txt"
assert_ok "special: cat backslash filename" cat "$TESTDIR/back\\slash.txt"
assert_ok "special: ls dir with special files" ls "$TESTDIR"
assert_ok "special: grep in file with spaces" grep "special" "$TESTDIR/has spaces.txt"
assert_ok "special: find files with quotes" find "$TESTDIR" -name '*quote*'
assert_ok "special: stat file with spaces" stat "$TESTDIR/has spaces.txt"
assert_ok "special: cp file with dollar" cp "$TESTDIR/has\$dollar.txt" "$TESTDIR/dollar_copy.txt"

echo ""
echo "--- Pipeline chains ---"
# Real-world compound commands
assert_ok "pipeline: find|grep|wc" \
    sh -c "find '$TESTDIR' -type f | grep '.txt' | wc -l"
assert_ok "pipeline: cat|grep|sort" \
    sh -c "cat '$TESTDIR/multi.txt' | grep line | sort -r"
assert_ok "pipeline: ls|head" \
    sh -c "ls -1 '$TESTDIR' | head -3"

echo ""
summary
