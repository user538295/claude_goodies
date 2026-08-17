#!/usr/bin/env bash
# Validates that every detection command in scripts/checks/*.tsv executes
# without errors (pattern compiles, pipeline runs) across all 7 languages.
# Run: bash tests/test_checks.sh
set -u

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SKILL_DIR/scripts/collect.sh"
FAIL=0

# All temp artifacts live under one root, removed at the end.
WORKROOT="$(mktemp -d)"
export TMPDIR="$WORKROOT"
trap 'cd /; rm -rf "$WORKROOT"' EXIT

d="$(mktemp -d)"; cd "$d" || exit 1
git init -q; git config user.email t@t.t; git config user.name t
printf 'seed\n' > seed.md; git add seed.md; git commit -qm init

# One production + one test file per language so every TSV row runs.
mkdir -p src/__tests__ src/test/kotlin src/test/java App.Tests AppTests tests
cat > src/main.ts <<'EOF'
export class OrderManager {
  public count = 42;
  process(flag: boolean): string | null { return flag ? null : "x"; }
}
EOF
printf 'export const f = () => 1;\n' > src/util.js
printf 'class DataProcessor:\n    def run(self):\n        return None\n' > src/mod.py
printf 'public class OrderHelper { public bool Run(bool f) { return f; } }\n' > src/Svc.cs
printf 'class ItemHandler { var count: Int = 99 }\n' > src/App.swift
printf 'class CartUtils { var total = 123 }\n' > src/Cart.kt
printf 'public class UserInfo { public int age = 7; }\n' > src/User.java
printf 'import { it } from "vitest";\nit.skip("x", () => { expect(true).toBe(true); });\n' > src/__tests__/main.test.ts
printf 'import time\ndef test_x():\n    time.sleep(1)\n    assert True\n' > test_mod.py
printf 'public class SvcTests { [Fact] public void Placeholder() { } }\n' > App.Tests/SvcTests.cs
printf 'import XCTest\nclass AppTests: XCTestCase { func testPlaceholder() { let sut = ItemHandler() } }\n' > AppTests.swift
printf 'class CartTest { @Test fun placeholder() { val fixture = CartUtils() } }\n' > src/test/kotlin/CartTest.kt
printf 'public class UserTest { @Test public void placeholder() { int n = 1; } }\n' > src/test/java/UserTest.java

# tests-13 fixtures whose names do NOT contain test/spec — proves the selector
# is directory-driven, not merely coincidental with a *Test(s) filename suffix.
# Each still carries its language's test-declaration marker (def test_/@Test/
# [Fact]/func test) so tests-13's content filter (looks-like-a-test, not just
# in-a-test-dir) still recognizes them as tests with zero assertions.
printf 'def test_login_flow():\n    service.login(creds)\n' > tests/login_flow.py
printf 'public class LoginFlow { @Test void run() { service.login(creds); } }\n' > src/test/java/LoginFlow.java
printf 'class LoginFlow { @Test fun run() { service.login(creds) } }\n' > src/test/kotlin/LoginFlow.kt
printf 'public class Checkout { [Fact] public void Run() { service.Checkout(cart); } }\n' > App.Tests/Checkout.cs
printf 'class Checkout { func testRun() { service.checkout(cart) } }\n' > AppTests/Checkout.swift

OUT="$("$SCRIPT" 2>"$WORKROOT/checks_err")" || { echo "collect.sh failed: $(cat "$WORKROOT/checks_err")"; exit 1; }

for lang in typescript javascript python csharp swift kotlin java; do
  grep -qx "$lang" "$OUT/languages.txt" || { echo "FAIL: $lang not detected"; FAIL=1; }
done

if grep -q "WARN-DETECT" "$OUT/warnings.txt" 2>/dev/null; then
  echo "FAIL: detection command errors:"
  grep "WARN-DETECT" "$OUT/warnings.txt"
  FAIL=1
fi

# Golden comparison: the fixture must produce exactly the known hits.
sort "$OUT/hits.txt" > "$WORKROOT/hits.sorted"
if ! diff -u "$SKILL_DIR/tests/golden_hits.tsv" "$WORKROOT/hits.sorted"; then
  echo "FAIL: hits differ from tests/golden_hits.tsv (see diff above)."
  echo "If the change is intentional, regenerate: sort \"\$OUT/hits.txt\" > tests/golden_hits.tsv"
  FAIL=1
fi

# Row order: each checks/*.tsv file must list its rows in ascending numeric
# ID order (ties across languages are fine — only the numeric part must never
# go backwards). Note: plain `sort -c -k1,1` is NOT used here — BSD sort (the
# macOS default) falls back to whole-line comparison when the key ties, so it
# flags disorder on files that ARE correctly ID-ordered but not lang-ordered.
for f in "$SKILL_DIR"/scripts/checks/*.tsv; do
  awk -F'\t' '
    /^#/ || NF==0 { next }
    { n = $1; sub(/^[a-zA-Z]+-/, "", n); n = n + 0
      if (n < prev) { print "FAIL: " FILENAME " row " NR " (" $1 ") is out of ascending ID order"; bad = 1 }
      prev = n }
    END { exit bad }
  ' "$f" || FAIL=1
done

TSV_CMDS="$(cat "$SKILL_DIR"/scripts/checks/*.tsv | grep -c .)"
echo "validated: $TSV_CMDS commands, hits produced: $(grep -c . "$OUT/hits.txt")"
[ "$FAIL" -eq 0 ] && echo "passed" || echo "FAILED"
exit "$FAIL"
