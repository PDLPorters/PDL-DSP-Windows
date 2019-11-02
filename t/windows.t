use Test::More;

use strict;
use warnings;

use PDL;
use PDL::DSP::Windows qw( window chebpoly ) ;

eval { require PDL::LinearAlgebra::Special };
my $HAVE_LinearAlgebra = 1 if !$@;

eval { require PDL::GSLSF::BESSEL; };
my $HAVE_BESSEL = 1 if !$@;

use lib 't/lib';
use MyTest::Helper qw( dies is_approx );

# Most of these were checked with Octave
subtest 'explict values of windows.' => sub {
    is_approx
        window( 4, 'hamming' ),
        [ 0.08, 0.77, 0.77, 0.08 ],
        'hamming';

    is_approx
        window( 4, 'hann' ),
        [ 0, 0.75, 0.75, 0 ],
        'hann';

    is_approx
        window( 4, 'hann_matlab' ),
        [ 0.3454915,  0.9045085,  0.9045085,  0.3454915 ],
        'hann_matlab';

    is_approx
        window( 6, 'bartlett_hann' ),
        [ 0, 0.35857354, 0.87942646, 0.87942646, 0.35857354, 0 ],
        'bartlett_hann';

    is_approx
        window( 6, 'bohman' ),
        [ 0, 0.17912389, 0.83431145, 0.83431145, 0.17912389, 0 ],
        'bohman',
        6;

    is_approx
        window( 6, 'triangular' ),
        [ 0.16666667, 0.5, 0.83333333, 0.83333333, 0.5, 0.16666667 ],
        'triangular';

    is_approx
        window( 6, 'welch' ),
        [ 0, 0.64, 0.96, 0.96, 0.64, 0 ],
        'welch';

    is_approx
        window( 6, 'blackman_harris4' ),
        [ 6e-05, 0.10301149, 0.79383351, 0.79383351, 0.10301149, 6e-05 ],
        'blackman_harris4';

    is_approx
        window( 6, 'blackman_nuttall' ),
        [ 0.0003628, 0.11051525, 0.7982581, 0.7982581, 0.11051525, 0.0003628 ],
        'blackman_nuttall';

    is_approx
        window( 6, 'flattop' ),
        [ -0.000421051, -0.067714252, 0.60687215, 0.60687215, -0.067714252, -0.000421051 ],
        'flattop',
        6;

    SKIP: {
        skip 'PDL::GSLSF::BESSEL not installed', 1 unless $HAVE_BESSEL;
        is_approx
            window( 6, 'kaiser', 0.5 / 3.1415926 ),
            [ 0.94030619, 0.97829624, 0.9975765, 0.9975765, 0.97829624, 0.94030619 ],
            'kaiser',
            7;
    }

    is_approx
        window( 10, 'tukey', 0.4 ),
        [ 0, 0.58682409, 1, 1, 1, 1, 1, 1, 0.58682409, 0 ],
        'tukey',
        6;

    is_approx
        window( 10, 'parzen' ),
        [ 0, 0.021947874, 0.17558299, 0.55555556, 0.93415638, 0.93415638, 0.55555556, 0.17558299, 0.021947874, 0],
        'parzen',
        7;

    is_approx
        window( 10, 'parzen_octave' ),
        [ 0.002, 0.054, 0.25, 0.622, 0.946, 0.946, 0.622, 0.25, 0.054, 0.002 ],
        'parzen';

    is_approx
        window( 8, 'chebyshev', 10 ),
        [ 1, 0.45192476, 0.5102779, 0.54133813, 0.54133813, 0.5102779, 0.45192476, 1 ],
        'chebyshev',
        6;

    is_approx
        window( 9, 'chebyshev', 10 ),
        [ 1, 0.39951163, 0.44938961, 0.48130908, 0.49229345, 0.48130908, 0.44938961, 0.39951163, 1 ],
        'chebyshev',
        6;
};

subtest 'relations between windows.' => sub {
    is_approx
        window( 6, 'rectangular' ),
        window( 6, 'cos_alpha', 0 ),
        'rectangular window is equivalent to cos_alpha 0';

    is_approx
        window( 6, 'cosine' ),
        window( 6, 'cos_alpha', 1 ),
        'cosine window is equivalent to cos_alpha 1';

    is_approx
        window( 6, 'hann' ),
        window( 6, 'cos_alpha', 2 ),
        'hann window is equivalent to cos_alpha 2';
};

subtest 'enbw of windows.' => sub {
    my $Nbw = 16384;
    my $win = PDL::DSP::Windows->new;

    for (
        # The following agree with Thomas Cokelaer's python package
        [ [ $Nbw, 'hamming'                 ], 1.36288567 ],
        [ [ $Nbw, 'rectangular'             ], 1.0        ],
        [ [ $Nbw, 'triangular'              ], 4 / 3      ],
        [ [ $Nbw * 10, 'hann'               ], 1.5  =>  4 ],
        [ [ $Nbw, 'blackman'                ], 1.72686277 ],
        [ [ $Nbw, 'blackman_harris4'        ], 2.00447524 ],
        [ [ $Nbw, 'bohman'                  ], 1.78584988 ],
        [ [ $Nbw, 'cauchy', 3               ], 1.48940773 ],
        [ [ $Nbw, 'poisson', 2              ], 1.31307123 ],
        [ [ $Nbw, 'hann_poisson', 0.5       ], 1.60925592 ],
        [ [ $Nbw, 'lanczos'                 ], 1.29911200 ],
        [ [ $Nbw, 'tukey', 0.25             ], 1.10210808 ],
        [ [ $Nbw, 'parzen'                  ], 1.91757736 ],
        [ [ $Nbw, 'parzen_octave'           ], 1.91746032 ],
        # These agree with other values found on web
        [ [ $Nbw, 'flattop'                 ], 3.77 =>  3 ],
    ) {
        my ( $args, $expected, $precision ) = @{$_};
        my ( undef, $name ) = @{$args};
        is_approx $win->init( @{$args} )->enbw, $expected, $name, $precision;
    }

    SKIP: {
        skip 'PDL::GSLSF::BESSEL not installed', 1 unless $HAVE_BESSEL;
        is_approx
            $win->init( $Nbw, 'kaiser', 8.6 / 3.1415926 )->enbw,
            1.72147863,
            'kaiser',
            5;
    }
};

subtest 'relation between periodic and symmetric.' => sub {
    for my $N (100, 101) {
        my $Nm = $N - 1;

        my %tests = (
            bartlett_hann    => [],
            bartlett         => [],
            blackman         => [],
            blackman_bnh     => [],
            blackman_ex      => [],
            blackman_harris  => [],
            blackman_harris4 => [],
            blackman_nuttall => [],
            bohman           => [],
            cosine           => [],
            exponential      => [],
            flattop          => [],
            hamming          => [],
            hamming_ex       => [],
            hann             => [],
            hann_poisson     => [ 0.5 ],
            lanczos          => [],
            nuttall          => [],
            nuttall1         => [],
            parzen           => [],
            rectangular      => [],
            triangular       => [],
            welch            => [],
            blackman_gen3    => [ 0.42, 0.5, 0.08 ],
            blackman_gen4    => [ 0.35875, 0.48829, 0.14128, 0.01168 ],
            blackman_gen     => [ 0.5 ],
            cauchy           => [ 3 ],
            kaiser           => [ 0.5 ],
            cos_alpha        => [ 2 ],
            hamming_gen      => [ 0.5 ],
            gaussian         => [ 1 ],
            poisson          => [ 1 ],
            tukey            => [ 0.4 ],
            dpss             => [ 4 ],
            blackman_gen5    => [
                0.21557895, 0.41663158, 0.277263158, 0.083578947, 0.006947368
            ],
        );

        for my $name ( keys %tests ) {
            # diag $name;

            SKIP: {
                skip 'PDL::GSLSF::BESSEL not installed', 1
                    if $name eq 'kaiser' and not $HAVE_BESSEL;

                skip 'PDL::LinearAlgebra::Special not installed', 1
                    if $name eq 'dpss' and not $HAVE_LinearAlgebra;

                my %args;
                $args{params} = $tests{$name} if @{ $tests{$name} };

                my $window = window( $N + 1, $name, { %args } );
                is_approx
                    $window->slice("0:$Nm"),
                    window( $N, $name, { per => 1, %args } ),
                    $name;
            }
        }
    }
};

subtest 'modfreqs.' => sub {
    is +PDL::DSP::Windows->new({ N => 10 })->modfreqs->nelem, 1000,
        'modfreqs defaults to 1000 bins';

    is +PDL::DSP::Windows->new({ N => 10 })
        ->modfreqs({ min_bins => 100 })->nelem, 100,
        'can pass bin number to modfreqs with hashref';
};

done_testing;
