#!/usr/bin/env bats
#
# test_extract_bash_blocks.bats — Task 1.7 coverage for extract-bash-blocks.sh
#
# Tests the tiny awk-based filter that reads markdown on stdin and prints the
# contents of all triple-backtick-fenced code blocks, EXCLUDING the fence lines
# themselves. Used by Step 7 block-mirror tests in Tasks 2.1/2.2.
#
# Per-test isolation: each test creates a fresh $TEST_CWD via mktemp -d under
# $BATS_TMPDIR and removes it in teardown.

SCRIPT="$HOME/.claude/tests/recovery/extract-bash-blocks.sh"

setup() {
  TEST_CWD="$(mktemp -d "$BATS_TMPDIR/recovery-extract-XXXXXX")"
  export TEST_CWD
}

teardown() {
  if [ -n "${TEST_CWD:-}" ] && [ -d "$TEST_CWD" ]; then
    rm -rf "$TEST_CWD"
  fi
}

@test "script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "test_extracts_single_fenced_block" {
  local md_file="$TEST_CWD/single.md"
  cat > "$md_file" <<'EOF'
Some intro prose.

```
echo "hello"
ls -la
```

Trailing prose.
EOF

  run bash -c "bash '$SCRIPT' < '$md_file'"
  [ "$status" -eq 0 ]
  [ "$output" = 'echo "hello"
ls -la' ]
}

@test "test_extracts_multiple_blocks_concatenated" {
  local md_file="$TEST_CWD/multi.md"
  cat > "$md_file" <<'EOF'
First section.

```
first block line 1
first block line 2
```

Middle prose.

```
second block
```

More prose.

```
third block line 1
third block line 2
third block line 3
```

End.
EOF

  run bash -c "bash '$SCRIPT' < '$md_file'"
  [ "$status" -eq 0 ]
  expected='first block line 1
first block line 2
second block
third block line 1
third block line 2
third block line 3'
  [ "$output" = "$expected" ]
}

@test "test_no_blocks_yields_empty_output" {
  local md_file="$TEST_CWD/none.md"
  cat > "$md_file" <<'EOF'
This is markdown with no fenced code blocks.

Some prose, a list:
- item one
- item two

Inline `code` in a paragraph but no fences at the start of a line.

The end.
EOF

  run bash -c "bash '$SCRIPT' < '$md_file'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "test_empty_stdin_yields_empty_output" {
  # C1-I-13 — verify empty input produces empty output, exit 0.
  run bash -c "bash '$SCRIPT' < /dev/null"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "test_fence_lines_are_excluded" {
  # Ensure ```bash, ```, and any fence line text never appears in output.
  local md_file="$TEST_CWD/fence.md"
  cat > "$md_file" <<'EOF'
Prose.

```bash
real content here
```

More.

```
another block
```
EOF

  run bash -c "bash '$SCRIPT' < '$md_file'"
  [ "$status" -eq 0 ]
  # Output must NOT contain the fence-line text.
  ! printf '%s\n' "$output" | grep -qF '```'
  ! printf '%s\n' "$output" | grep -qF 'bash'
  # Output MUST contain the block contents.
  printf '%s\n' "$output" | grep -qF 'real content here'
  printf '%s\n' "$output" | grep -qF 'another block'
}
