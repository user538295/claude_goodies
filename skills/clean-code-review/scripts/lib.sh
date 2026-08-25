# lib.sh — PCRE matching helpers via perl (no GNU grep dependency, space-safe).
# Sourced by collect.sh and by tests/test_corpus.sh so tests exercise the exact
# helpers production uses. Each helper reads a newline-separated file list on stdin.

mgrep() {  # mgrep 'PCRE' -> file:line:text per match
  perl -e '
    my $pat = eval { qr/$ARGV[0]/ };
    die "bad pattern: $@" unless $pat;
    while (defined(my $f = <STDIN>)) {
      chomp $f; next unless -f $f && -r $f;
      open(my $fh, "<", $f) or next;
      my $n = 0;
      while (defined(my $l = <$fh>)) { $n++; chomp $l; print "$f:$n:$l\n" if $l =~ $pat; }
      close $fh;
    }' "$1"
}

mgrepc() {  # mgrepc 'PCRE' -> file:match_count per file (like grep -cH)
  perl -e '
    my $pat = eval { qr/$ARGV[0]/ };
    die "bad pattern: $@" unless $pat;
    while (defined(my $f = <STDIN>)) {
      chomp $f; next unless -f $f && -r $f;
      open(my $fh, "<", $f) or next;
      my $c = 0;
      while (defined(my $l = <$fh>)) { $c++ if $l =~ $pat; }
      close $fh;
      print "$f:$c\n";
    }' "$1"
}

mwc() {  # -> "linecount file" per file (like wc -l, space-safe)
  perl -e '
    while (defined(my $f = <STDIN>)) {
      chomp $f; next unless -f $f && -r $f;
      open(my $fh, "<", $f) or next;
      my $n = 0; $n++ while <$fh>;
      close $fh;
      print "$n $f\n";
    }'
}

mparams() {  # mparams 'DECL_RE' MAX -> file:line:text for declarations with more than MAX parameters
  # Used by smells-02: a comma-counting regex only sees a signature written on
  # one line, and most real 4+-parameter signatures wrap. This joins the
  # declaration line with its continuations until the parentheses balance, then
  # splits the argument list on top-level commas — nested calls, generics in
  # parens, defaults, and collection literals do not inflate the count. A
  # leading `self`/`cls` is not a parameter (python convention).
  # ponytail: quoted defaults are blanked before counting; a comma inside a
  # triple-quoted default still over-counts — use a tokenizer if that shows up.
  perl -e '
    my ($decl, $max) = @ARGV;
    my $decl_re = qr/$decl/;
    while (defined(my $f = <STDIN>)) {
      chomp $f; next unless -f $f && -r $f;
      open(my $fh, "<", $f) or next;
      my @l = <$fh>; close $fh;
      for my $i (0 .. $#l) {
        next unless $l[$i] =~ $decl_re;
        my $open = $+[0] - 1;                 # DECL_RE ends at the signature paren
        $open = index($l[$i], "(") unless substr($l[$i], $open, 1) eq "(";
        next if $open < 0;
        my ($depth, $args, $done) = (0, "", 0);
        for my $j ($i .. $#l) {
          my $text = $j == $i ? substr($l[$j], $open) : $l[$j];
          $text =~ s/(["\x27])(?:\\.|(?!\1).)*\1/_/g;   # a comma inside a default string is not a separator
          for my $c (split //, $text) {
            if ($c =~ /[\(\[\{]/) { $depth++; $args .= "_" if $depth == 2; next }
            if ($c =~ /[\)\]\}]/) { $depth--; if ($depth == 0) { $done = 1; last } next }
            $args .= $c if $depth == 1;
          }
          last if $done || $j - $i > 40;
        }
        next unless $done;
        my @parts = grep { /\S/ } split /,/, $args, -1;
        @parts = grep { $_ !~ m{^\s*(self|cls|[*/])\s*$} } @parts;   # python: bare * and / are markers, not parameters
        next unless @parts > $max;
        my $line = $l[$i]; chomp $line;
        print "$f:", $i + 1, ":$line\n";
      }
    }' "$1" "$2"
}

mbody() {  # mbody 'KEEP_RE' 'DROP_RE' — filter file:line:text hits by the block that follows
  # Used by smells-12: a `catch`/`except` line alone cannot say whether the
  # error is swallowed — the body does. Keeps a hit when the body is empty, or
  # matches KEEP_RE (empty KEEP_RE = no requirement), and never when it matches
  # DROP_RE. Both patterns are PCRE, matched against the body text.
  # Body extent: for .py, the following lines indented deeper than the hit line;
  # otherwise the brace block opened by the LAST `{` on the hit line.
  # ponytail: last-brace-on-the-line, so a catch whose signature wraps across
  # lines yields an empty body (kept) — switch to a real tokenizer if that shows up.
  perl -e '
    my ($keep, $drop) = @ARGV;
    my $keep_re = length($keep) ? qr/$keep/ : undef;
    my $drop_re = length($drop) ? qr/$drop/ : undef;
    my %src;
    while (defined(my $hit = <STDIN>)) {
      my ($f, $n) = $hit =~ /^(.+?):(\d+):/ or next;
      unless (exists $src{$f}) {
        $src{$f} = [];
        if (open(my $fh, "<", $f)) { $src{$f} = [ <$fh> ]; close $fh }
      }
      my @l = @{$src{$f}};
      my $i = $n - 1;               # 0-based index of the hit line
      next unless $i >= 0 && $i < @l;
      my $body = "";
      if ($f =~ /\.py$/) {
        my ($ind) = $l[$i] =~ /^(\s*)/;
        for my $j ($i + 1 .. $#l) {
          next if $l[$j] =~ /^\s*$/;
          my ($jind) = $l[$j] =~ /^(\s*)/;
          last if length($jind) <= length($ind);
          $body .= $l[$j];
        }
      } elsif ((my $p = rindex($l[$i], "{")) >= 0) {
        my $depth = 0;
        my $text = substr($l[$i], $p);
        for my $j ($i .. $#l) {
          $text = $l[$j] if $j > $i;
          for my $c (split //, $text) {
            if ($c eq "{") { $depth++; next }
            if ($c eq "}") { $depth--; last if $depth == 0; next }
            $body .= $c if $depth > 0;
          }
          last if $depth == 0;
        }
      }
      next if defined($drop_re) && $body =~ $drop_re;
      next if defined($keep_re) && $body =~ /\S/ && $body !~ $keep_re;
      print $hit;
    }' "$1" "$2"
}

notested() {  # filter file:line:text hits -> drop files whose module already has a test file
  # Used by tests-01: the check only fires when NO test file exists for the module
  # anywhere in the repo. Repo inventory comes from `git ls-files` (tracked +
  # untracked-not-ignored) of the nearest ancestor holding .git, cached per root.
  # A repo file counts as this module's test when it is test-shaped (lives in a
  # test directory or carries a test marker in its name) AND its stem — test
  # markers stripped, non-alphanumerics removed — equals the module stem, so
  # FooBarTests.swift covers FooBar.swift but FooBarPickerTests.swift does not.
  # Outside a git repo nothing is dropped: never lose a finding to a missing tool.
  perl -e '
    use Cwd qw(abs_path);
    my (%keep, %inv);
    while (defined(my $line = <STDIN>)) {
      my ($f) = $line =~ /^(.+?):\d+:/;
      next unless defined $f;
      unless (exists $keep{$f}) {
        my $dir = abs_path($f) || $f; $dir =~ s{/[^/]+$}{};
        my $root = ""; my $c = $dir;
        while ($c && $c ne "/") { if (-d "$c/.git") { $root = $c; last } last unless $c =~ s{/[^/]+$}{}; }
        my $stem = lc $f; $stem =~ s{.*/}{}; $stem =~ s/\..*$//; $stem =~ s/[^a-z0-9]//g;
        my $tested = 0;
        if ($root ne "" && length $stem) {
          $inv{$root} ||= [ split /\n/, qx(git -C "$root" ls-files -c -o --exclude-standard 2>/dev/null) ];
          for my $p (@{$inv{$root}}) {
            my $lp = lc $p;
            next unless $lp =~ m{(^|/)(tests?|__tests__|spec|specs)/}
                     || $lp =~ m{(^|/)test_|[_.](test|spec|cy|e2e)\.|tests?\.[a-z]+$|spec\.[a-z]+$};
            my $b = $lp; $b =~ s{.*/}{}; $b =~ s/\..*$//;
            $b =~ s/^test_//; $b =~ s/_test$//; $b =~ s/tests?$//; $b =~ s/spec$//;
            $b =~ s/[^a-z0-9]//g;
            if ($b eq $stem) { $tested = 1; last }
          }
        }
        $keep{$f} = !$tested;
      }
      print $line if $keep{$f};
    }'
}

mfunc() {  # mfunc 'DECL_RE' MAX -> file:line:text for functions spanning more than MAX lines
  # Used by clarity-17: the rule is per-function, but a line count is per-file, so
  # a long file of short functions is a false positive and a long function in a
  # short file is invisible. This measures each declaration's own span and anchors
  # the hit on the declaration line. Span = declaration line through closing line,
  # inclusive — the same count a reader gets from the editor gutter.
  # Extent: for .py, the lines after the signature indented deeper than the
  # declaration (blank lines and triple-quoted string bodies do not end it);
  # otherwise the brace block the declaration opens.
  # Nested declarations are reported too (an inner 200-line function is its own
  # violation); two declarations closing on the same line are one function written
  # across two lines, so only the outer one is emitted.
  # ponytail: quoted spans and `//` comments are blanked before counting braces;
  # a brace inside a block comment or a Swift `"""` literal still miscounts —
  # use a tokenizer if that shows up.
  perl -e '
    my ($decl, $max) = @ARGV;
    my $decl_re = qr/$decl/;
    my $ctrl_re = qr/^\s*(?:\}\s*)?(?:if|else|for|foreach|while|switch|case|catch|do|try|guard|repeat|when|return|using|lock|synchronized)\b/;
    while (defined(my $f = <STDIN>)) {
      chomp $f; next unless -f $f && -r $f;
      open(my $fh, "<", $f) or next;
      my @l = <$fh>; close $fh;
      my $py = $f =~ /\.py$/;
      my @instr;
      if ($py) {   # a heredoc-style literal continuing at column 0 is not dedent
        my $q = "";
        for my $j (0 .. $#l) {
          $instr[$j] = ($q ne "");
          my $t = $l[$j];
          while (1) {
            if ($q eq "") { $t =~ s/^.*?("""|\x27\x27\x27)//s ? ($q = $1) : last }
            else          { $t =~ s/^.*?\Q$q\E//s ? ($q = "") : last }
          }
        }
      }
      my %seen_end;
      for my $i (0 .. $#l) {
        next unless $l[$i] =~ $decl_re;
        next if $l[$i] =~ $ctrl_re;
        my $end;
        if ($py) {
          my ($ind) = $l[$i] =~ /^(\s*)/;
          my ($depth, $sig) = (0, $i);
          for my $j ($i .. $#l) {      # a wrapped signature closes at the def indent; skip past it
            my $t = $l[$j]; $t =~ s/(["\x27])(?:\\.|(?!\1).)*\1/_/g;
            for my $c ($t =~ /([()])/g) { $c eq "(" ? $depth++ : $depth-- }
            $sig = $j;
            last if $depth <= 0;
          }
          $end = $sig;
          for my $j ($sig + 1 .. $#l) {
            next if $l[$j] =~ /^\s*$/ || $instr[$j];
            my ($jind) = $l[$j] =~ /^(\s*)/;
            last if length($jind) <= length($ind);
            $end = $j;
          }
        } else {
          my ($depth, $opened) = (0, 0);
          for my $j ($i .. $#l) {
            my $t = $l[$j];
            $t =~ s/(["\x27`])(?:\\.|(?!\1).)*\1/_/g;
            $t =~ s{//.*$}{};
            for my $c ($t =~ /([{}])/g) { $c eq "{" ? ($depth++, $opened = 1) : $depth-- }
            if ($opened) { if ($depth <= 0) { $end = $j; last } }
            elsif ($t =~ /;\s*$/) { last }          # declaration with no body (protocol/interface/abstract)
          }
        }
        next unless defined $end && $end - $i + 1 > $max;
        next if $seen_end{$end}++;
        my $line = $l[$i]; chomp $line;
        print "$f:", $i + 1, ":$line\n";
      }
    }' "$1" "$2"
}

msig() {  # msig 'TARGET_RE' — filter file:line:text hits by `def` signature membership
  # Used by smells-08: `x: T | None = None` is a null parameter default inside a
  # signature and an ordinary Optional field in a class body, and mgrep is
  # line-local so it cannot tell the two apart. A hit whose line matches
  # TARGET_RE survives only when that line lies inside a `def` signature's
  # parentheses (the declaration line itself included); every other hit passes
  # through untouched, so returns and return-type annotations are unaffected.
  # python only — the languages that spell the difference with a keyword
  # (`let`/`var`/`val`) exclude the declaration in the pattern instead.
  # ponytail: quoted spans are blanked before counting parens; a paren inside a
  # triple-quoted default still miscounts — use a tokenizer if that shows up.
  perl -e '
    my $target = qr/$ARGV[0]/;
    my (%sig, %loaded);
    while (defined(my $hit = <STDIN>)) {
      my ($f, $n, $t) = $hit =~ /^(.+?):(\d+):(.*)$/s or next;
      unless ($t =~ $target) { print $hit; next }
      unless ($loaded{$f}++) {
        $sig{$f} = {};
        if (open(my $fh, "<", $f)) {
          my @l = <$fh>; close $fh;
          for my $i (0 .. $#l) {
            next unless $l[$i] =~ /^\s*(?:async\s+)?def\s+\w+\s*\(/;
            my $open = index($l[$i], "(");
            my $depth = 0;
            for my $j ($i .. $#l) {
              my $text = $j == $i ? substr($l[$j], $open) : $l[$j];
              $text =~ s/(["\x27])(?:\\.|(?!\1).)*\1/_/g;
              for my $c (split //, $text) { $depth++ if $c eq "("; $depth-- if $c eq ")" }
              $sig{$f}{$j + 1} = 1;
              last if $depth <= 0 || $j - $i > 40;
            }
          }
        }
      }
      print $hit if $sig{$f}{$n};
    }' "$1"
}
