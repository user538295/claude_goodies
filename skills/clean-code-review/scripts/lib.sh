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
