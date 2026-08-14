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
