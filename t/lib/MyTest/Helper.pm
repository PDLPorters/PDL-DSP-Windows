package MyTest::Helper;

use Test::More;
use PDL;
use Exporter 'import';
use Try::Tiny;

our @EXPORT_OK = qw( is_approx dies );

sub dies (&$$) {
    my ( $code, $check, $message ) = @_;

    my $error;
    try { $code->() } catch { chomp( $error = $_ ) }
    finally {
        $error //= '';
        like $error, $check, $message;
    };
}

sub is_approx ($$;$$) {
    my( $got, $expected, $message, $precision ) = @_;

    $message   //= '';
    $precision //= 8;

    my $in = 0 + sprintf(
        "%.${precision}f",
        ref $got ? $got->sum : $got,
    ),

    my $out = 0 + sprintf(
        "%.${precision}f",
        ref $got ? pdl($expected)->sum : $expected,
    ),

    is $in, $out, $message or diag $got;
}

1;
