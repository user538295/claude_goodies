bash ~/.claude/scripts/check-task-commit.sh "<START_SHA>"
END_CHECKED=$(awk '/^- \[[xX]\]/{c++} END{print c+0}' "$ARGUMENTS")
test $((END_CHECKED - START_CHECKED)) -ge 1
if git log -1 --format='%s' HEAD | grep -q '^recovery(R-B):'; then
  echo "Step 7 check 3: SKIPPED (R-B recovery commit is plan-only by design)"
else
  git show --stat HEAD | grep -q "$(basename "$ARGUMENTS")"
  git show --stat HEAD | awk 'NR>1 && /\|/ {print $1}' | grep -v "$(basename "$ARGUMENTS")" | grep -q .
fi
bash ~/.claude/scripts/implement-next-state-clear.sh "$(pwd)"
