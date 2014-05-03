use Modern::Perl;
use Path::Tiny;

my $arg= shift;
my $qr = qr/$arg/;

my @lines = grep {m/$qr/} path("weaver.ini")->lines;

say foreach @lines;
