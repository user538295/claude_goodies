#!/usr/bin/env bash
# collect.sh — deterministic data collection for /clean-code-review.
# Resolves the review target, builds the file list / added-line index / diff,
# runs all scriptable detection patterns, and writes results to a temp dir.
#
# Usage: collect.sh [staged] [unstaged] [untracked] [local] [<git-ref-or-range>] [<file>...]
#   no args            -> local (staged + unstaged + untracked) in a git repo
#   staged/unstaged/untracked -> any combination of those areas
#   <ref> or <A..B>    -> diff a ref against the worktree, or between two commits
#   <file>...          -> review whole files; works outside git repos
#
# Stdout: the output directory path (single line). Everything else -> stderr.
# Output dir contents: mode.txt files.txt skipped.txt languages.txt
#   unanalysed.txt addedlines.txt diff.patch hits.txt warnings.txt
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKS_DIR="$SCRIPT_DIR/checks"
TAB="$(printf '\t')"
HIT_CAP=200
LARGE_DIFF_FILES=100

err() { echo "ERROR: $*" >&2; exit 1; }

command -v perl >/dev/null 2>&1 || err "perl is required for detection patterns (preinstalled on macOS and virtually all Linux distributions)."

EXCLUDE_RE='(^|/)(vendor|node_modules|dist|\.build|build|target|obj|bin|Pods)/|\.(generated\.|pb\.|min\.js$|lock$|snap$)|\.(log|bak)$|_pb2\.py$|package-lock\.json$|pnpm-lock\.yaml$|go\.sum$|\.gradle\.kts$|(^|/)buildSrc/'
NONCODE_EXT_RE='\.(md|txt|json|yml|yaml|toml|xml|csv|svg|png|jpg|jpeg|gif|ico|lock|gitignore|gitattributes|editorconfig|env|sh|bash|zsh|sql|html|css|scss|less|plist|pdf|zip)$'

# ---------------------------------------------------------------- helpers
# PCRE matching helpers (mgrep/mgrepc/mwc) are shared with the test suite.
. "$SCRIPT_DIR/lib.sh"

is_text_file() { perl -e 'exit(-T $ARGV[0] ? 0 : 1)' "$1" 2>/dev/null; }

# Append a pseudo-diff (whole file as added) for untracked / explicit files.
append_whole_file() {  # $1=file, appends to $DIFF_PATCH and $ADDED
  local f="$1" n
  n="$(awk 'END{print NR}' "$f")"
  {
    printf -- '--- /dev/null\n'
    printf -- '+++ b/%s\n' "$f"
    printf -- '@@ -0,0 +1,%d @@\n' "$n"
    sed 's/^/+/' "$f"
  } >> "$DIFF_PATCH"
  awk -v f="$f" '{print f":"FNR}' "$f" >> "$ADDED"
}

# Prefix each added/context diff line with its file line number ("N|+code").
# Agents anchor findings from these prefixes instead of counting hunk offsets.
number_diff() {
  awk '
    /^\+\+\+ /{print; next}
    /^@@/{ match($0, /\+[0-9]+/); n = substr($0, RSTART + 1, RLENGTH - 1) + 0; print; next }
    /^\+/{ printf "%d|%s\n", n, $0; n++; next }
    /^ /{ printf "%d|%s\n", n, $0; n++; next }
    { print }'
}

# Parse a git unified diff (-U0) into file:line added-line entries.
added_lines_from_diff() {
  awk '
    /^diff --git /{inhdr=1; saw_minus=0; next}
    /^@@@/{next}
    /^--- /{ if(inhdr) saw_minus=1; next }
    /^\+\+\+ /{
      if(inhdr && saw_minus==1) {
        f = substr($0, 5)
        if (substr(f, 1, 2) == "b/") f = substr(f, 3)
      }
      saw_minus=0
      next
    }
    /^@@/{
      inhdr=0
      n = split($3, a, ",")
      start = substr(a[1], 2) + 0
      count = (n > 1 ? a[2] + 0 : 1)
      for (i = 0; i < count; i++) print f ":" start + i
    }'
}

# ---------------------------------------------------------------- argument parsing

IN_GIT=0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && IN_GIT=1

WANT_STAGED=0; WANT_UNSTAGED=0; WANT_UNTRACKED=0
REF=""
FILE_ARGS=()

for a in "$@"; do
  case "$a" in
    local)     WANT_STAGED=1; WANT_UNSTAGED=1; WANT_UNTRACKED=1 ;;
    staged)    WANT_STAGED=1 ;;
    unstaged)  WANT_UNSTAGED=1 ;;
    untracked) WANT_UNTRACKED=1 ;;
    *)
      if [ -f "$a" ]; then
        FILE_ARGS+=("$a")
      elif [ "$IN_GIT" = 1 ] && git rev-parse --verify --quiet "${a%%..*}" >/dev/null 2>&1; then
        [ -n "$REF" ] && err "Only one git ref/range is allowed (got '$REF' and '$a')."
        REF="$a"
      else
        err "'$a' is not a file, git ref/range, or target keyword (staged, unstaged, untracked, local)."
      fi
      ;;
  esac
done

ANY_KEYWORD=$((WANT_STAGED + WANT_UNSTAGED + WANT_UNTRACKED))
if [ "${#FILE_ARGS[@]}" -gt 0 ] && { [ -n "$REF" ] || [ "$ANY_KEYWORD" -gt 0 ]; }; then
  err "File paths cannot be combined with git targets."
fi
if [ -n "$REF" ] && [ "$ANY_KEYWORD" -gt 0 ]; then
  err "A git ref/range cannot be combined with staged/unstaged/untracked/local."
fi

MODE="git"
if [ "${#FILE_ARGS[@]}" -gt 0 ]; then
  MODE="files"
elif [ "$IN_GIT" = 0 ]; then
  err "Not inside a git repository. Pass file paths to review, or cd into a git project."
elif [ -n "$REF" ]; then
  MODE="ref"
else
  [ "$ANY_KEYWORD" -eq 0 ] && { WANT_STAGED=1; WANT_UNSTAGED=1; WANT_UNTRACKED=1; }
fi

# ---------------------------------------------------------------- output dir

OUT="$(mktemp -d "${TMPDIR:-/tmp}/ccr.XXXXXX")"
FILES_RAW="$OUT/.files_raw"; ADDED="$OUT/addedlines.txt"; DIFF_PATCH="$OUT/diff.patch"
WARN="$OUT/warnings.txt"
: > "$FILES_RAW"; : > "$ADDED"; : > "$DIFF_PATCH"; : > "$WARN"
: > "$OUT/hits.txt"; : > "$OUT/languages.txt"; : > "$OUT/unanalysed.txt"; : > "$OUT/skipped.txt"

GITD() { git -c core.quotePath=false -c diff.relative=false diff --no-ext-diff --no-color "$@"; }

# ---------------------------------------------------------------- build diff + file list

if [ "$MODE" = "files" ]; then
  echo "files" > "$OUT/mode.txt"
  for f in "${FILE_ARGS[@]}"; do printf '%s\n' "$f" >> "$FILES_RAW"; done
else
  cd "$(git rev-parse --show-toplevel)" || err "Cannot cd to git toplevel."
  if git ls-files --unmerged | grep -q .; then
    err "Unresolved merge conflicts detected. Resolve all conflicts before reviewing."
  fi

  HAS_HEAD=0
  git rev-parse --verify --quiet HEAD >/dev/null 2>&1 && HAS_HEAD=1

  if [ "$MODE" = "ref" ]; then
    echo "ref: $REF" > "$OUT/mode.txt"
    GITD "$REF" > "$DIFF_PATCH" 2>/dev/null || err "'$REF' is not a valid diff target."
    GITD "$REF" --name-only --diff-filter=d >> "$FILES_RAW"
    GITD "$REF" -U0 | added_lines_from_diff >> "$ADDED"
  else
    {
      [ "$WANT_STAGED" = 1 ]    && echo "staged"
      [ "$WANT_UNSTAGED" = 1 ]  && echo "unstaged"
      [ "$WANT_UNTRACKED" = 1 ] && echo "untracked"
    } > "$OUT/mode.txt"

    if [ "$WANT_STAGED" = 1 ] && [ "$WANT_UNSTAGED" = 1 ] && [ "$HAS_HEAD" = 1 ]; then
      # Combined staged+unstaged vs HEAD: line numbers match the worktree.
      GITD HEAD > "$DIFF_PATCH"
      GITD HEAD --name-only --diff-filter=d >> "$FILES_RAW"
      GITD HEAD -U0 | added_lines_from_diff >> "$ADDED"
    else
      if [ "$WANT_STAGED" = 1 ]; then
        GITD --cached >> "$DIFF_PATCH"
        GITD --cached --name-only --diff-filter=d >> "$FILES_RAW"
        GITD --cached -U0 | added_lines_from_diff >> "$ADDED"
      fi
      if [ "$WANT_UNSTAGED" = 1 ]; then
        GITD >> "$DIFF_PATCH"
        GITD --name-only --diff-filter=d >> "$FILES_RAW"
        GITD -U0 | added_lines_from_diff >> "$ADDED"
      fi
    fi

    if [ "$WANT_UNTRACKED" = 1 ]; then
      git -c core.quotePath=false ls-files --others --exclude-standard > "$OUT/.untracked"
      while IFS= read -r f; do
        [ -f "$f" ] || continue
        printf '%s\n' "$f" >> "$FILES_RAW"
        if printf '%s\n' "$f" | grep -Eq "$EXCLUDE_RE"; then continue; fi
        if is_text_file "$f"; then append_whole_file "$f"; fi
      done < "$OUT/.untracked"
      rm -f "$OUT/.untracked"
    fi
  fi
fi

if [ "$MODE" = "files" ]; then
  for f in "${FILE_ARGS[@]}"; do
    if is_text_file "$f"; then append_whole_file "$f"; fi
  done
fi

# ---------------------------------------------------------------- filter file list

sort -u "$FILES_RAW" | while IFS= read -r f; do
  [ -f "$f" ] || continue
  if printf '%s\n' "$f" | grep -Eq "$EXCLUDE_RE"; then
    printf '%s\n' "$f" >> "$OUT/skipped.txt"
  else
    printf '%s\n' "$f" >> "$OUT/files.txt"
  fi
done
rm -f "$FILES_RAW"
[ -f "$OUT/files.txt" ] || : > "$OUT/files.txt"

if [ ! -s "$DIFF_PATCH" ]; then
  rm -rf "$OUT"
  err "No changes to review. Make changes, or pass a ref/range (e.g. main..HEAD) or file paths."
fi
if [ ! -s "$OUT/files.txt" ]; then
  if [ -s "$OUT/skipped.txt" ]; then
    rm -rf "$OUT"
    err "All changed files are in excluded paths (vendor/generated/build) — nothing to review."
  fi
  rm -rf "$OUT"
  err "No changes to review. Make changes, or pass a ref/range (e.g. main..HEAD) or file paths."
fi

FILE_COUNT="$(grep -c . "$OUT/files.txt")"
if [ "$FILE_COUNT" -gt "$LARGE_DIFF_FILES" ]; then
  echo "NOTICE-LARGE-DIFF: Diff covers $FILE_COUNT files — review coverage may be partial. Recommend narrowing the target." >> "$WARN"
fi

# ---------------------------------------------------------------- languages

while IFS= read -r f; do
  case "$f" in
    *.ts|*.tsx|*.mts|*.cts) echo typescript ;;
    *.js|*.jsx|*.mjs|*.cjs) echo javascript ;;
    *.cs)                   echo csharp ;;
    *.py)                   echo python ;;
    *.swift)                echo swift ;;
    *.kt|*.kts)             echo kotlin ;;
    *.java)                 echo java ;;
    *)
      base="${f##*/}"
      ext=".${base##*.}"
      if [ "$base" != "${base#*.}" ] && ! printf '%s\n' "$f" | grep -Eiq "$NONCODE_EXT_RE"; then
        printf '%s\n' "$ext" >> "$OUT/.unanalysed_raw"
      fi
      ;;
  esac
done < "$OUT/files.txt" | sort -u > "$OUT/languages.txt"
[ -f "$OUT/.unanalysed_raw" ] && sort -u "$OUT/.unanalysed_raw" > "$OUT/unanalysed.txt" && rm -f "$OUT/.unanalysed_raw"

sort -u -o "$ADDED" "$ADDED"

# ---------------------------------------------------------------- run detection checks

# Checks whose hit is a whole-file measurement rather than a diff line — an
# absence (no hash method, no assertions) or a count (branch count, file
# length) — have no per-line evidence to filter against, so they are exempt
# from added-line filtering. This set is asserted against the `**Scope**:
# files` declarations in groups/*.md by tests/test_collect.sh, so keep them
# in sync — the coupling is discoverable from the code side.
# tests-01 is also declared `**Scope**: files` in groups/tests.md but is
# deliberately NOT listed here: its per-symbol hits are collapsed to one
# finding per file downstream (see the tests-01 dedup below), and unlike the
# five checks here it still needs added-line filtering to avoid flagging
# pre-existing symbols in a touched file that this diff didn't add.
FILTER_EXEMPT=" clarity-16 clarity-17 smells-01 smells-20 tests-13 "

run_checks() {
  local tsv id lang cmd raw="$OUT/.raw_hits" errf="$OUT/.check_err"
  for tsv in "$CHECKS_DIR"/*.tsv; do
    [ -f "$tsv" ] || continue
    while IFS="$TAB" read -r id lang cmd <&3 || [ -n "${id:-}" ]; do
      case "$id" in ''|'#'*) continue ;; esac
      if [ "$lang" != "all" ] && ! grep -qx "$lang" "$OUT/languages.txt"; then continue; fi
      : > "$errf"
      eval "$cmd" < "$OUT/files.txt" > "$raw" 2>"$errf" || true
      if [ -s "$errf" ]; then
        echo "WARN-DETECT: $id/$lang detection error: $(head -n 1 "$errf")" >> "$WARN"
      fi
      [ -s "$raw" ] || continue

      if printf '%s' "$FILTER_EXEMPT" | grep -q " $id "; then
        : # file-level output (counts) — no line filter
      else
        awk -F: 'NR==FNR{added[$0]=1; next} { key=$1":"$2; if (key in added) print }' \
          "$ADDED" "$raw" > "$raw.f" && mv "$raw.f" "$raw"
      fi

      if [ "$id" = "tests-01" ] && [ -s "$raw" ]; then
        awk -F: '!seen[$1]++' "$raw" > "$raw.f" && mv "$raw.f" "$raw"
      fi

      if [ -s "$raw" ]; then
        local n
        n="$(grep -c . "$raw")"
        if [ "$n" -gt "$HIT_CAP" ]; then
          head -n "$HIT_CAP" "$raw" > "$raw.f" && mv "$raw.f" "$raw"
          echo "WARN-CAP: $id findings capped at $HIT_CAP/$n after added-line filtering — narrow the target for complete coverage" >> "$WARN"
        fi
        sed "s|^|$id$TAB|" "$raw" >> "$OUT/hits.txt"
      fi
    done 3< "$tsv"
  done
  rm -f "$raw" "$errf" 2>/dev/null
}
run_checks

number_diff < "$DIFF_PATCH" > "$OUT/numbered.patch"

echo "$OUT"
