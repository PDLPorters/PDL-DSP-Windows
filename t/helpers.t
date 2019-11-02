use Test::More;

use strict;
use warnings;

use PDL;
use PDL::DSP::Windows qw(
    chebpoly
    cos_mult_to_pow
    cos_pow_to_mult
);

use lib 't/lib';
use MyTest::Helper qw( dies is_approx );

subtest 'chebpoly.' => sub {
    is_approx(
        chebpoly( 3, pdl( [ 0.5, 1, 1.2 ] ) ),
        [ -1, 1, 3.312 ],
        'chebpoly takes piddle'
    );

    is_approx(
        chebpoly( 3, [ 0.5, 1, 1.2 ] ),
        [ -1, 1, 3.312 ],
        'chebpoly takes arrayref',
    );

    is chebpoly( 3, 1.2 ), 3.312, 'chebpoly takes plain scalar';
};


subtest 'relation between periodic and symmetric.' => sub {
    my @tests = (
        []                         => [],
        [  0 ]                     => [  0 ],
        [ -1,  1 ]                 => [ -1,     -1, ],
        [  1,  0, -1 ]             => [  0.5,    0,    -0.5, ],
        [ -2,  1, -1, 2 ]          => [ -2.5,   -2.5,  -0.5,     -0.5, ],
        [  2,  1,  0, 1, 2 ]       => [  2.75,  -1.75,  1,       -0.25,   0.25, ],
        [  3,  2,  1, 1, 2, 3 ]    => [  4.25,  -4.625, 1.5,     -1.1875, 0.25,   -0.1875 ],
        [ -3, -2, -1, 0, 1, 2, 3 ] => [ -2.1875, 0.75,  1.40625, -0.625,  0.6875, -0.125, 0.09375 ],

    );

    while ( my ( $in, $want ) = splice @tests, 0, 2 ) {
        my @cos  = cos_pow_to_mult( @{$in} );
        my @mult = cos_mult_to_pow( @cos );

        is_deeply \@cos, $want, '[ ' . join( ' ', @{$in} ) . ' ]'
            or diag '[ ' . join( ' ', @cos ) . ' ]';

        is_deeply \@mult, $in, 'Roundtrip: [ ' . join( ' ', @{$in} ) . ' ]'
            or diag '[ ' . join( ' ', @mult ) . ' ]';
    }

    dies { cos_pow_to_mult( 0 .. 7 ) } qr/number of args not less than 8/,
        'cos_pow_to_mult dies with too many args';

    dies { cos_mult_to_pow( 0 .. 7 ) } qr/number of args not less than 8/,
        'cos_mult_to_pow dies with too many args';
};

done_testing;
