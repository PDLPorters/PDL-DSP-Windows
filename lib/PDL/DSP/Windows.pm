package PDL::DSP::Windows;
$PDL::DSP::Windows::VERSION = '0.008';

use strict; use warnings;
use PDL::LiteF;
use PDL::FFT;
use PDL::Math qw( acos cosh acosh );
use PDL::Core qw( topdl );
use PDL::MatrixOps qw( eigens_sym );
use PDL::Options qw( iparse ifhref );

use constant {
    HAVE_LinearAlgebra => eval { require PDL::LinearAlgebra::Special; 1 } || 0,
    HAVE_BESSEL        => eval { require PDL::GSLSF::BESSEL; 1 }          || 0,
    HAVE_GNUPLOT       => eval { require PDL::Graphics::Gnuplot; 1 }      || 0,
    USE_FFTW_DIRECTION => do {
        use version;
        version->parse($PDL::VERSION) < version->parse('2.006_04');
    },
};

use namespace::clean;

# These constants defined after cleaning our namespace to avoid
# breaking existing code that might use them.
use constant PI  => 4 * atan2(1, 1);
use constant TPI => 2 * PI;

use Exporter 'import';

our @EXPORT_OK = qw(
    window
    list_windows

    chebpoly
    cos_mult_to_pow
    cos_pow_to_mult

    bartlett                   bartlett_per
    bartlett_hann         bartlett_hann_per
    blackman                   blackman_per
    blackman_bnh           blackman_bnh_per
    blackman_ex             blackman_ex_per
    blackman_gen           blackman_gen_per
    blackman_gen3         blackman_gen3_per
    blackman_gen4         blackman_gen4_per
    blackman_gen5         blackman_gen5_per
    blackman_harris     blackman_harris_per
    blackman_harris4   blackman_harris4_per
    blackman_nuttall   blackman_nuttall_per
    bohman                       bohman_per
    cauchy                       cauchy_per
    chebyshev
    cos_alpha                 cos_alpha_per
    cosine                       cosine_per
    dpss                           dpss_per
    exponential             exponential_per
    flattop                     flattop_per
    gaussian                   gaussian_per
    hamming                     hamming_per
    hamming_ex               hamming_ex_per
    hamming_gen             hamming_gen_per
    hann                           hann_per
    hann_matlab
    hann_poisson           hann_poisson_per
    kaiser                       kaiser_per
    lanczos                     lanczos_per
    nuttall                     nuttall_per
    nuttall1                   nuttall1_per
    parzen                       parzen_per
    parzen_octave
    poisson                     poisson_per
    rectangular             rectangular_per
    triangular               triangular_per
    tukey                         tukey_per
    welch                         welch_per
);

$PDL::onlinedoc->scan(__FILE__) if $PDL::onlinedoc;

our %winsubs;
our %winpersubs;
our %window_definitions;

=encoding utf8

=head1 NAME

PDL::DSP::Windows - Window functions for signal processing

=head1 SYNOPSIS

       use PDL;
       use PDL::DSP::Windows('window');
       my $samples = window( 10, 'tukey', { params => .5 });

       use PDL;
       use PDL::DSP::Windows;
       my $win = new PDL::DSP::Windows(10, 'tukey', { params => .5 });
       print $win->coherent_gain , "\n";
       $win->plot;

=head1 DESCRIPTION

This module provides symmetric and periodic (DFT-symmetric)
window functions for use in filtering and spectral analysis.
It provides a high-level access subroutine
L</window>. This functional interface is sufficient for getting the window
samples. For analysis and plotting, etc. an object oriented
interface is provided. The functional subroutines must be either explicitly exported, or
fully qualified. In this document, the word I<function> refers only to the
mathematical window functions, while the word I<subroutine> is used to describe
code.

Window functions are also known as apodization
functions or tapering functions. In this module, each of these
functions maps a sequence of C<$N> integers to values called
a B<samples>. (To confuse matters, the word I<sample> also has
other meanings when describing window functions.)
The functions are often named for authors of journal articles.
Be aware that across the literature and software,
some functions referred to by several different names, and some names
refer to several different functions. As a result, the choice
of window names is somewhat arbitrary.

The L</kaiser($N,$beta)> window function requires
L<PDL::GSLSF::BESSEL>. The L</dpss($N,$beta)> window function requires
L<PDL::LinearAlgebra>. But the remaining window functions may
be used if these modules are not installed.

The most common and easiest usage of this module is indirect, via some
higher-level filtering interface, such as L<PDL::DSP::Fir::Simple>.
The next easiest usage is to return a pdl of real-space samples with the subroutine L</window>.
Finally, for analyzing window functions, object methods, such as L</new>,
L</plot>, L</plot_freq> are provided.

In the following, first the functional interface (non-object oriented) is described in
L</"FUNCTIONAL INTERFACE">. Next, the object methods are described in L</METHODS>.
Next the low-level subroutines returning samples for each named window
are described in  L</"WINDOW FUNCTIONS">. Finally,
some support routines that may be of interest are described in
L</"AUXILIARY SUBROUTINES">.

=head1 FUNCTIONAL INTERFACE

=head2 window

       $win = window({OPTIONS});
       $win = window($N,{OPTIONS});
       $win = window($N,$name,{OPTIONS});
       $win = window($N,$name,$params,{OPTIONS});
       $win = window($N,$name,$params,$periodic);

Returns an C<$N> point window of type C<$name>.
The arguments may be passed positionally in the order
C<$N,$name,$params,$periodic>, or they may be passed by
name in the hash C<OPTIONS>.

=head3 EXAMPLES

 # Each of the following return a 100 point symmetric hamming window.

   $win = window(100);
   $win = window(100, 'hamming');
   $win = window(100, { name => 'hamming' );
   $win = window({ N=> 100, name => 'hamming' );

 # Each of the following returns a 100 point symmetric hann window.

   $win = window(100, 'hann');
   $win = window(100, { name => 'hann' );

 # Returns a 100 point periodic hann window.

   $win = window(100, 'hann', { periodic => 1 } );

 # Returns a 100 point symmetric Kaiser window with alpha=2.

   $win = window(100, 'kaiser', { params => 2 });

=head3 OPTIONS

The options follow default PDL::Options rules-- They may be abbreviated,
and are case-insensitive.

=over

=item B<name>

(string) name of window function. Default: C<hamming>.
This selects one of the window functions listed below. Note
that the suffix '_per', for periodic, may be ommitted. It
is specified with the option C<< periodic => 1 >>


=item B<params>


ref to array of parameter or parameters for the  window-function
subroutine. Only some window-function subroutines take
parameters. If the subroutine takes a single parameter,
it may be given either as a number, or a list of one
number. For example C<3> or C<[3]>.

=item B<N>

number of points in window function (the same as the order
of the filter) No default value.

=item B<periodic>

If value is true, return a periodic rather than a symmetric window function. Default: 0
(that is, false. that is, symmetric.)

=back

=cut

sub window {
    my $win = new PDL::DSP::Windows(@_);
    $win->samples();
}

=head2 list_windows

     list_windows
     list_windows STR

C<list_windows> prints the names all of the available windows.
C<list_windows STR> prints only the names of windows matching
the string C<STR>.

=cut

sub list_windows {
    my ($expr) = @_;
    my @match;
    if ($expr) {
        my @alias;
        foreach (sort keys %winsubs) {
            push(@match,$_) , next if /$expr/i;
            push(@match, $_ . ' (alias ' . $alias[0] . ')') if @alias = grep(/$expr/i,@{$window_definitions{$_}->{alias}});
        }
    }
    else {
        @match = sort keys %winsubs;
    }
    print join(', ',@match),"\n";
}


=head1 METHODS

=head2 new

=for usage

  my $win = new PDL::DSP::Windows(ARGS);

=for ref

Create an instance of a Windows object. If C<ARGS> are given, the instance
is initialized. C<ARGS> are interpreted in exactly the
same way as arguments the subroutine L</window>.

=for example

For example:

  my $win1 = new PDL::DSP::Windows(8,'hann');
  my $win2 = new PDL::DSP::Windows( { N => 8, name => 'hann' } );

=cut

sub new {
  my $proto = shift;
  my $self  = bless {}, ref $proto || $proto;
  $self->init(@_) if @_;
  return $self;
}

=head2 init

=for usage

  $win->init(ARGS);

=for ref

Initialize (or reinitialize) a Windows object.  ARGS are interpreted in exactly the
same way as arguments the subroutine L</window>.

=for example

For example:

  my $win = new PDL::DSP::Windows(8,'hann');
  $win->init(10,'hamming');

=cut

sub init {
    my $self = shift;

    my ( $N, $name, $params, $periodic );

    $N        = shift unless ref $_[0];
    $name     = shift unless ref $_[0];
    $params   = shift unless ref $_[0] eq 'HASH';
    $periodic = shift unless ref $_[0];

    my $opts = PDL::Options->new({
        name     => 'hamming',
        periodic => 0,          # symmetric or periodic
        N        => undef,      # order
        params   => undef,
    })->options( shift // {} );

    $name     ||= $opts->{name};
    $N        ||= $opts->{N};
    $periodic ||= $opts->{periodic};
    $params   //= $opts->{params};
    $params   = [$params] if defined $params && !ref $params;

    $name =~ s/_per$//;

    my $ws = $periodic ? \%winpersubs : \%winsubs;
    if ( not exists $ws->{$name}) {
        my $perstr = $periodic ? 'periodic' : 'symmetric';
        barf "window: Unknown $perstr window '$name'.";
    }

    $self->{name}     = $name;
    $self->{N}        = $N;
    $self->{periodic} = $periodic;
    $self->{params}   = $params;
    $self->{code}     = $ws->{$name};
    $self->{samples}  = undef;
    $self->{modfreqs} = undef;

    return $self;
}

=head2 samples

=for usage

  $win->samples();

=for ref

Generate and return a reference to the piddle of $N samples for the window C<$win>.
This is the real-space representation of the window.

The samples are stored in the object C<$win>, but are regenerated
every time C<samples> is invoked. See the method
L</get_samples> below.

=for example

For example:

  my $win = new PDL::DSP::Windows(8,'hann');
  print $win->samples(), "\n";

=cut

sub samples {
    my $self = shift;
    my @args = ( $self->{N}, @{ $self->{params} // [] } );
    $self->{samples} = $self->{code}->(@args);
}

=head2 modfreqs

=for usage

  $win->modfreqs();

=for ref

Generate and return a reference to the piddle of the modulus of the
fourier transform of the samples for the window C<$win>.

These values are stored in the object C<$win>, but are regenerated
every time C<modfreqs> is invoked. See the method
L</get_modfreqs> below.

=head3 options

=over

=item min_bins => MIN

This sets the minimum number of frequency bins.
Default 1000. If necessary, the piddle of window samples
are padded with zeros before the fourier transform is performed.

=back

=cut

sub modfreqs {
    my $self = shift;
    my %opts = iparse( { min_bins => 1000 }, ifhref(shift) );

    my $data = $self->get_samples;

    my $n = $data->nelem;
    my $fn = $n > $opts{min_bins} ? 2 * $n : $opts{min_bins};

    $n--;

    my $freq = zeroes($fn);
    $freq->slice("0:$n") .= $data;

    PDL::FFT::realfft($freq);

    my $real = zeros($freq);
    my $img  = zeros($freq);
    my $mid  = ( $freq->nelem ) / 2 - 1;
    my $mid1 = $mid + 1;

    $real->slice("0:$mid")   .= $freq->slice("$mid:0:-1");
    $real->slice("$mid1:-1") .= $freq->slice("0:$mid");
    $img->slice("0:$mid")    .= $freq->slice("-1:$mid1:-1");
    $img->slice("$mid1:-1")  .= $freq->slice("$mid1:-1");

    return $self->{modfreqs} = $real ** 2 + $img ** 2;
}

=head2 get

=for usage

  my $windata = $win->get('samples');

=for ref

Get an attribute (or list of attributes) of the window C<$win>.
If attribute C<samples> is requested, then the samples are created with the
method L</samples> if they don't exist.

=for example

For example:

  my $win = new PDL::DSP::Windows(8,'hann');
  print $win->get('samples'), "\n";

=cut

sub get {
    my $self = shift;
    my @res;
    foreach (@_) {
        $self->samples() if $_ eq 'samples' and not defined $self->{samples};
        $self->freqs() if $_ eq 'modfreqs' and not defined $self->{modfreqs};
        push @res, $self->{$_};
    };
    return wantarray ? @res : $res[0];
}

=head2 get_samples

=for usage

  my $windata = $win->get_samples

=for ref

Return a reference to the pdl of samples for the Window instance C<$win>.
The samples will be generated with the method L</samples> if and only if
they have not yet been generated.

=cut

sub get_samples {
    my $self = shift;
    return $self->{samples} if defined $self->{samples};
    return $self->samples;
}

=head2 get_modfreqs

=for usage

  my $winfreqs = $win->get_modfreqs;
  my $winfreqs = $win->get_modfreqs({OPTS});

=for ref

Return a reference to the pdl of the frequency response (modulus of the DFT)
for the Window instance C<$win>.

Options are passed to the method L</modfreqs>.
The data are created with L</modfreqs>
if they don't exist. The data are also created even
if they already exist if options are supplied. Otherwise
the cached data are returned.

=head3 options

=over

=item min_bins => MIN

This sets the minimum number of frequency bins. See
L</modfreqs>. Default 1000.

=back

=cut

sub get_modfreqs {
    my $self = shift;
    return $self->modfreqs(@_) if @_;
    return $self->{modfreqs} if defined $self->{modfreqs};
    return $self->modfreqs;
}

=head2 get_params

=for usage

  my $params = $win->get_params

=for ref

Create a new array containing the parameter values for the instance C<$win>
and return a reference to the array.
Note that not all window types take parameters.

=cut

sub get_params { shift->{params} }

sub get_N { shift->{N} }

=head2 get_name

=for usage

  print  $win->get_name , "\n";

=for ref

Return a name suitable for printing associated with the window $win. This is
something like the name used in the documentation for the particular
window function. This is static data and does not depend on the instance.

=cut

sub get_name {
    my $self = shift;
    my $wd = $window_definitions{$self->{name}};
    return $wd->{pfn} . ' window' if $wd->{pfn};
    return $wd->{fn} . ' window' if $wd->{fn} and not $wd->{fn} =~ /^\*/;
    return $wd->{fn} if $wd->{fn};
    return ucfirst($self->{name}) . ' window';
}

sub get_param_names {
    my $self = shift;
    my $wd = $window_definitions{$self->{name}};
    $wd->{params} ? ref($wd->{params}) ? $wd->{params} : [$wd->{params}] : undef;
}

sub format_param_vals {
    my $self = shift;
    my $p = $self->get('params');
    return '' unless $p;
    my $names = $self->get_param_names;
    my @p = @$p;
    my @names = @$names;
    return '' unless $names;
    my @s;
    map { s/^\$// } @names;
    foreach (@p) {
        push @s, (shift @names) . ' = ' . $_;
    }
    join(', ', @s);
}

sub format_plot_param_vals {
    my $self = shift;
    my $ps = $self->format_param_vals;
    return '' unless $ps;
    ': ' . $ps;
}

=head2 plot

=for usage

    $win->plot;

=for ref

Plot the samples. Currently, only PDL::Graphics::Gnuplot is supported.
The default display type is used.

=cut

sub plot {
    my $self = shift;
    barf "PDL::DSP::Windows::plot Gnuplot not available!" unless HAVE_GNUPLOT;
    my $w = $self->get('samples');
    my $title = $self->get_name() .$self->format_plot_param_vals;
    PDL::Graphics::Gnuplot::plot( title => $title, xlabel => 'Time (samples)',
          ylabel => 'amplitude', $w );
    return $self;
}

=head2 plot_freq

=for usage

Can be called like this

    $win->plot_freq;


Or this

    $win->plot_freq( {ordinate => ORDINATE });


=for ref

Plot the frequency response (magnitude of the DFT of the window samples).
The response is plotted in dB, and the frequency
(by default) as a fraction of the Nyquist frequency.
Currently, only PDL::Graphics::Gnuplot is supported.
The default display type is used.

=head3 options

=over

=item coord => COORD

This sets the units of frequency of the co-ordinate axis.
C<COORD> must be one of C<nyquist>, for
fraction of the nyquist frequency (range C<-1,1>),
C<sample>, for fraction of the sampling frequncy (range
C<-.5,.5>), or C<bin> for frequency bin number (range
C<0,$N-1>). The default value is C<nyquist>.

=item min_bins => MIN

This sets the minimum number of frequency bins. See
L</get_modfreqs>. Default 1000.

=back

=cut

sub plot_freq {
    my $self = shift;
    my $opt = new PDL::Options(
        {
            coord => 'nyquist',
            min_bins => 1000
        });
    my $iopts = @_ ? shift : {};
    my $opts = $opt->options($iopts);
    barf "PDL::DSP::Windows::plot Gnuplot not available!" unless HAVE_GNUPLOT;
    my $mf = $self->get_modfreqs({ min_bins => $opts->{min_bins}});
    $mf /= $mf->max;
    my $param_str = $self->format_plot_param_vals;
    my $title = $self->get_name() . $param_str
        . ', frequency response. ENBW=' . sprintf("%2.3f",$self->enbw);
    my $coord = $opts->{coord};
    my ($coordinate_range,$xlab);
    if ($coord eq 'nyquist') {
        $coordinate_range = 1;
        $xlab = 'Fraction of Nyquist frequency';
    }
    elsif ($coord eq 'sample') {
        $coordinate_range = .5;
        $xlab = 'Fraction of sampling freqeuncy';
    }
    elsif ($coord eq 'bin') {
        $coordinate_range = ($self->get_N)/2;
        $xlab = 'bin';
    }
    else {
        barf "plot_freq: Unknown ordinate unit specification $coord";
    }
    my $coordinates = zeroes($mf)->xlinvals(-$coordinate_range,$coordinate_range);
    my $ylab = 'freqeuncy response (dB)';
    PDL::Graphics::Gnuplot::plot(title => $title,
       xmin => -$coordinate_range, xmax => $coordinate_range,
       xlabel => $xlab,  ylabel => $ylab,
       with => 'line', $coordinates, 20 * log10($mf) );
    return $self;
}

=head2 enbw

=for usage

    $win->enbw;

=for ref

Compute and return the equivalent noise bandwidth of the window.

=cut

sub enbw {
    my $self = shift;
    my $w = $self->get('samples'); # hmm have to quote samples here
    ($w->nelem) * ($w**2)->sum / ($w->sum)**2;
}

=head2 coherent_gain

=for usage

    $win->coherent_gain;

=for ref

Compute and return the coherent gain (the dc gain) of the window.
This is just the average of the samples.

=cut

sub coherent_gain {
    my $w = shift->get_samples;
    $w->sum / $w->nelem;
}


=head2 process_gain

=for usage

    $win->coherent_gain;

=for ref

Compute and return the processing gain (the dc gain) of the window.
This is just the multiplicative inverse of the C<enbw>.

=cut

sub process_gain { 1 / shift->enbw }

# not quite correct for some reason.
# Seems like 10*log10(this) / 1.154
# gives the correct answer in decibels

=head2 scallop_loss

=for usage

    $win->scallop_loss;

=for ref

**BROKEN**.
Compute and return the scalloping loss of the window.

=cut

sub scallop_loss {
    my ($w) = @_;
    my $x = sequence($w) * (PI/$w->nelem);
    sqrt( (($w*cos($x))->sum)**2 + (($w*sin($x))->sum)**2 ) /
        $w->sum;
}

=head1 WINDOW FUNCTIONS

These window-function subroutines return a pdl of $N samples. For most
windows, there are a symmetric and a periodic version.  The
symmetric versions are functions of $N points, uniformly
spaced, and taking values from x_lo through x_hi.  Here, a
periodic function of C< $N > points is equivalent to its
symmetric counterpart of C<$N+1> points, with the final
point omitted. The name of a periodic window-function subroutine is the
same as that for the corresponding symmetric function, except it
has the suffix C<_per>.  The descriptions below describe the
symmetric version of each window.

The term 'Blackman-Harris family' is meant to include the Hamming family
and the Blackman family. These are functions of sums of cosines.

Unless otherwise noted, the arguments in the cosines of all symmetric
window functions are multiples of C<$N> numbers uniformly spaced
from C<0> through C<2 pi>.

=cut

sub bartlett {
  barf "bartlett: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    1 - abs (zeroes($N)->xlinvals(-1,1));
}
$window_definitions{bartlett} = {
alias => [ 'fejer'],
};
$winsubs{bartlett} = \&bartlett;

sub bartlett_per {
  barf "bartlett: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    1 - abs (zeroes($N)->xlinvals(-1, (-1+1*($N-1))/$N));
}
$window_definitions{bartlett} = {
alias => [ 'fejer'],
};
$winpersubs{bartlett}= \&bartlett_per;

sub bartlett_hann {
  barf "bartlett_hann: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    0.62 - 0.48 * abs (zeroes($N)->xlinvals(-0.5,0.5)) + 0.38* (cos(zeroes($N)->xlinvals(-(PI),PI)));
}
$window_definitions{bartlett_hann} = {
fn => q!Bartlett-Hann!,
alias => [ 'Modified Bartlett-Hann'],
};
$winsubs{bartlett_hann} = \&bartlett_hann;

sub bartlett_hann_per {
  barf "bartlett_hann: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    0.62 - 0.48 * abs (zeroes($N)->xlinvals(-0.5, (-0.5+0.5*($N-1))/$N)) + 0.38* (cos(zeroes($N)->xlinvals(-(PI), (-(PI)+PI*($N-1))/$N)));
}
$window_definitions{bartlett_hann} = {
fn => q!Bartlett-Hann!,
alias => [ 'Modified Bartlett-Hann'],
};
$winpersubs{bartlett_hann}= \&bartlett_hann_per;

sub blackman {
  barf "blackman: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0,TPI)));

    (0.34) +  ($cx * ((-0.5) +  ($cx * (0.16))));
}
$window_definitions{blackman} = {
fn => q!'classic' Blackman!,
};
$winsubs{blackman} = \&blackman;

sub blackman_per {
  barf "blackman: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0, TPI*($N-1)/$N)));

    (0.34) +  ($cx * ((-0.5) +  ($cx * (0.16))));
}
$window_definitions{blackman} = {
fn => q!'classic' Blackman!,
};
$winpersubs{blackman}= \&blackman_per;

sub blackman_bnh {
  barf "blackman_bnh: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0,TPI)));

    (0.3461008) +  ($cx * ((-0.4973406) +  ($cx * (0.1565586))));
}
$window_definitions{blackman_bnh} = {
pfn => q!Blackman-Harris (bnh)!,
fn => q!*An improved version of the 3-term Blackman-Harris window given by Nuttall (Ref 2, p. 89).!,
};
$winsubs{blackman_bnh} = \&blackman_bnh;

sub blackman_bnh_per {
  barf "blackman_bnh: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0, TPI*($N-1)/$N)));

    (0.3461008) +  ($cx * ((-0.4973406) +  ($cx * (0.1565586))));
}
$window_definitions{blackman_bnh} = {
pfn => q!Blackman-Harris (bnh)!,
fn => q!*An improved version of the 3-term Blackman-Harris window given by Nuttall (Ref 2, p. 89).!,
};
$winpersubs{blackman_bnh}= \&blackman_bnh_per;

sub blackman_ex {
  barf "blackman_ex: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0,TPI)));

    (0.349742046431642) +  ($cx * ((-0.496560619088564) +  ($cx * (0.153697334479794))));
}
$window_definitions{blackman_ex} = {
fn => q!'exact' Blackman!,
};
$winsubs{blackman_ex} = \&blackman_ex;

sub blackman_ex_per {
  barf "blackman_ex: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0, TPI*($N-1)/$N)));

    (0.349742046431642) +  ($cx * ((-0.496560619088564) +  ($cx * (0.153697334479794))));
}
$window_definitions{blackman_ex} = {
fn => q!'exact' Blackman!,
};
$winpersubs{blackman_ex}= \&blackman_ex_per;

sub blackman_gen {
  barf "blackman_gen: 2 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 2;
  my ($N,$alpha) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0,TPI)));

    (.5 - $alpha) +  ($cx * ((-.5) +  ($cx * ($alpha))));
}
$window_definitions{blackman_gen} = {
pfn => q!General classic Blackman!,
fn => q!*A single parameter family of the 3-term Blackman window. !,
params => [ '$alpha'],
};
$winsubs{blackman_gen} = \&blackman_gen;

sub blackman_gen_per {
  barf "blackman_gen: 2 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 2;
  my ($N,$alpha) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0, TPI*($N-1)/$N)));

    (.5 - $alpha) +  ($cx * ((-.5) +  ($cx * ($alpha))));
}
$window_definitions{blackman_gen} = {
pfn => q!General classic Blackman!,
fn => q!*A single parameter family of the 3-term Blackman window. !,
params => [ '$alpha'],
};
$winpersubs{blackman_gen}= \&blackman_gen_per;

sub blackman_gen3 {
  barf "blackman_gen3: 4 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 4;
  my ($N,$a0,$a1,$a2) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0,TPI)));

    ($a0 - $a2) +  ($cx * ((-$a1) +  ($cx * (2*$a2))));
}
$window_definitions{blackman_gen3} = {
fn => q!*The general form of the Blackman family. !,
params => [ '$a0','$a1','$a2'],
};
$winsubs{blackman_gen3} = \&blackman_gen3;

sub blackman_gen3_per {
  barf "blackman_gen3: 4 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 4;
  my ($N,$a0,$a1,$a2) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0, TPI*($N-1)/$N)));

    ($a0 - $a2) +  ($cx * ((-$a1) +  ($cx * (2*$a2))));
}
$window_definitions{blackman_gen3} = {
fn => q!*The general form of the Blackman family. !,
params => [ '$a0','$a1','$a2'],
};
$winpersubs{blackman_gen3}= \&blackman_gen3_per;

sub blackman_gen4 {
  barf "blackman_gen4: 5 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 5;
  my ($N,$a0,$a1,$a2,$a3) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0,TPI)));

    ($a0 - $a2) +  ($cx * ((-$a1 + 3 * $a3) +  ($cx * (2*$a2 + $cx * (-4*$a3)  ))));
}
$window_definitions{blackman_gen4} = {
fn => q!*The general 4-term Blackman-Harris window. !,
params => [ '$a0','$a1','$a2','$a3'],
};
$winsubs{blackman_gen4} = \&blackman_gen4;

sub blackman_gen4_per {
  barf "blackman_gen4: 5 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 5;
  my ($N,$a0,$a1,$a2,$a3) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0, TPI*($N-1)/$N)));

    ($a0 - $a2) +  ($cx * ((-$a1 + 3 * $a3) +  ($cx * (2*$a2 + $cx * (-4*$a3)  ))));
}
$window_definitions{blackman_gen4} = {
fn => q!*The general 4-term Blackman-Harris window. !,
params => [ '$a0','$a1','$a2','$a3'],
};
$winpersubs{blackman_gen4}= \&blackman_gen4_per;

sub blackman_gen5 {
  barf "blackman_gen5: 6 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 6;
  my ($N,$a0,$a1,$a2,$a3,$a4) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0,TPI)));

    ($a0 - $a2 + $a4) +  ($cx * ((-$a1 + 3 * $a3) +  ($cx * (2*$a2 -8*$a4 + $cx * (-4*$a3 +$cx *(8*$a4))  ))));
}
$window_definitions{blackman_gen5} = {
fn => q!*The general 5-term Blackman-Harris window. !,
params => [ '$a0','$a1','$a2','$a3','$a4'],
};
$winsubs{blackman_gen5} = \&blackman_gen5;

sub blackman_gen5_per {
  barf "blackman_gen5: 6 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 6;
  my ($N,$a0,$a1,$a2,$a3,$a4) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0, TPI*($N-1)/$N)));

    ($a0 - $a2 + $a4) +  ($cx * ((-$a1 + 3 * $a3) +  ($cx * (2*$a2 -8*$a4 + $cx * (-4*$a3 +$cx *(8*$a4))  ))));
}
$window_definitions{blackman_gen5} = {
fn => q!*The general 5-term Blackman-Harris window. !,
params => [ '$a0','$a1','$a2','$a3','$a4'],
};
$winpersubs{blackman_gen5}= \&blackman_gen5_per;

sub blackman_harris {
  barf "blackman_harris: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0,TPI)));

    (0.343103) +  ($cx * ((-0.49755) +  ($cx * (0.15844))));
}
$window_definitions{blackman_harris} = {
fn => q!Blackman-Harris!,
alias => [ 'Minimum three term (sample) Blackman-Harris'],
};
$winsubs{blackman_harris} = \&blackman_harris;

sub blackman_harris_per {
  barf "blackman_harris: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0, TPI*($N-1)/$N)));

    (0.343103) +  ($cx * ((-0.49755) +  ($cx * (0.15844))));
}
$window_definitions{blackman_harris} = {
fn => q!Blackman-Harris!,
alias => [ 'Minimum three term (sample) Blackman-Harris'],
};
$winpersubs{blackman_harris}= \&blackman_harris_per;

sub blackman_harris4 {
  barf "blackman_harris4: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0,TPI)));

    (0.21747) +  ($cx * ((-0.45325) +  ($cx * (0.28256 + $cx * (-0.04672)  ))));
}
$window_definitions{blackman_harris4} = {
fn => q!minimum (sidelobe) four term Blackman-Harris!,
alias => [ 'Blackman-Harris'],
};
$winsubs{blackman_harris4} = \&blackman_harris4;

sub blackman_harris4_per {
  barf "blackman_harris4: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0, TPI*($N-1)/$N)));

    (0.21747) +  ($cx * ((-0.45325) +  ($cx * (0.28256 + $cx * (-0.04672)  ))));
}
$window_definitions{blackman_harris4} = {
fn => q!minimum (sidelobe) four term Blackman-Harris!,
alias => [ 'Blackman-Harris'],
};
$winpersubs{blackman_harris4}= \&blackman_harris4_per;

sub blackman_nuttall {
  barf "blackman_nuttall: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0,TPI)));

    (0.2269824) +  ($cx * ((-0.4572542) +  ($cx * (0.273199 + $cx * (-0.0425644)  ))));
}
$window_definitions{blackman_nuttall} = {
fn => q!Blackman-Nuttall!,
};
$winsubs{blackman_nuttall} = \&blackman_nuttall;

sub blackman_nuttall_per {
  barf "blackman_nuttall: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0, TPI*($N-1)/$N)));

    (0.2269824) +  ($cx * ((-0.4572542) +  ($cx * (0.273199 + $cx * (-0.0425644)  ))));
}
$window_definitions{blackman_nuttall} = {
fn => q!Blackman-Nuttall!,
};
$winpersubs{blackman_nuttall}= \&blackman_nuttall_per;

sub bohman {
  barf "bohman: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    my $x = abs((zeroes($N)->xlinvals(-1,1)));
(1-$x)*cos(PI*$x) +(1/PI)*sin(PI*$x);
}
$window_definitions{bohman} = {
};
$winsubs{bohman} = \&bohman;

sub bohman_per {
  barf "bohman: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    my $x = abs((zeroes($N)->xlinvals(-1, (-1+1*($N-1))/$N)));
(1-$x)*cos(PI*$x) +(1/PI)*sin(PI*$x);
}
$window_definitions{bohman} = {
};
$winpersubs{bohman}= \&bohman_per;

sub cauchy {
  barf "cauchy: 2 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 2;
  my ($N,$alpha) = @_;
    1 / (1 + ((zeroes($N)->xlinvals(-1,1)) * $alpha)**2);
}
$window_definitions{cauchy} = {
params => [ '$alpha'],
alias => [ 'Abel','Poisson'],
};
$winsubs{cauchy} = \&cauchy;

sub cauchy_per {
  barf "cauchy: 2 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 2;
  my ($N,$alpha) = @_;
    1 / (1 + ((zeroes($N)->xlinvals(-1, (-1+1*($N-1))/$N)) * $alpha)**2);
}
$window_definitions{cauchy} = {
params => [ '$alpha'],
alias => [ 'Abel','Poisson'],
};
$winpersubs{cauchy}= \&cauchy_per;

sub chebyshev {
  barf "chebyshev: 2 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 2;
  my ($N,$at) = @_;

    my ($M,$M1,$pos,$pos1);
    my $cw;
    my $beta = cosh(1/($N-1) * acosh(1/(10**(-$at/20))));
    my $k = sequence($N);
    my $x = $beta * cos(PI*$k/$N);
    $cw = chebpoly($N-1,$x);
    if ( $N % 2 ) {  # odd
        $M1 = ($N+1)/2;
        $M = $M1 - 1;
        $pos = 0;
        $pos1 = 1;
        PDL::FFT::realfft($cw);
    }
    else { # half-sample delay (even order)
        my $arg = PI/$N * sequence($N);
        my $cw_im = $cw * sin($arg);
        $cw *= cos($arg);
        if (USE_FFTW_DIRECTION) {
          PDL::FFT::fftnd($cw,$cw_im);
        }
        else {
          PDL::FFT::ifftnd($cw,$cw_im);
        }
        $M1 = $N/2;
        $M = $M1-1;
        $pos = 1;
        $pos1 = 0;
    }
    $cw /= ($cw->at($pos));
    my $cwout = zeroes($N);
    $cwout->slice("0:$M") .= $cw->slice("$M:0:-1");
    $cwout->slice("$M1:-1") .= $cw->slice("$pos1:$M");
    $cwout /= max($cwout);
    $cwout;
   ;
}
$window_definitions{chebyshev} = {
params => [ '$at'],
alias => [ 'Dolph-Chebyshev'],
};
$winsubs{chebyshev} = \&chebyshev;

sub cos_alpha {
  barf "cos_alpha: 2 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 2;
  my ($N,$alpha) = @_;
     (sin(zeroes($N)->xlinvals(0,PI)))**$alpha ;
}
$window_definitions{cos_alpha} = {
params => [ '$alpha'],
alias => [ 'Power-of-cosine'],
};
$winsubs{cos_alpha} = \&cos_alpha;

sub cos_alpha_per {
  barf "cos_alpha: 2 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 2;
  my ($N,$alpha) = @_;
     (sin(zeroes($N)->xlinvals(0, PI*($N-1)/$N)))**$alpha ;
}
$window_definitions{cos_alpha} = {
params => [ '$alpha'],
alias => [ 'Power-of-cosine'],
};
$winpersubs{cos_alpha}= \&cos_alpha_per;

sub cosine {
  barf "cosine: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    (sin(zeroes($N)->xlinvals(0,PI)));
}
$window_definitions{cosine} = {
alias => [ 'sine'],
};
$winsubs{cosine} = \&cosine;

sub cosine_per {
  barf "cosine: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    (sin(zeroes($N)->xlinvals(0, PI*($N-1)/$N)));
}
$window_definitions{cosine} = {
alias => [ 'sine'],
};
$winpersubs{cosine}= \&cosine_per;

sub dpss {
  barf "dpss: 2 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 2;
  my ($N,$beta) = @_;

        barf 'dpss: PDL::LinearAlgebra not installed.' unless HAVE_LinearAlgebra;
        barf "dpss: $beta not between 0 and $N." unless
              $beta >= 0 and $beta <= $N;
        $beta /= ($N/2);
        my $k = sequence($N);
        my $s = sin(PI*$beta*$k)/$k;
        $s->slice('0') .= $beta;
        my ($ev,$e) = eigens_sym(PDL::LinearAlgebra::Special::mtoeplitz($s));
        my $i = $e->maximum_ind;
        $ev->slice("($i)")->copy;
    ;
}
$window_definitions{dpss} = {
fn => q!Digital Prolate Spheroidal Sequence (DPSS)!,
params => [ '$beta'],
alias => [ 'sleppian'],
};
$winsubs{dpss} = \&dpss;

sub dpss_per {
  barf "dpss: 2 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 2;
  my ($N,$beta) = @_;
    $N++;

        barf 'dpss: PDL::LinearAlgebra not installed.' unless HAVE_LinearAlgebra;
        barf "dpss: $beta not between 0 and $N." unless
              $beta >= 0 and $beta <= $N;
        $beta /= ($N/2);
        my $k = sequence($N);
        my $s = sin(PI*$beta*$k)/$k;
        $s->slice('0') .= $beta;
        my ($ev,$e) = eigens_sym(PDL::LinearAlgebra::Special::mtoeplitz($s));
        my $i = $e->maximum_ind;
        $ev->slice("($i),0:-2")->copy;
    ;
}
$window_definitions{dpss} = {
fn => q!Digital Prolate Spheroidal Sequence (DPSS)!,
params => [ '$beta'],
alias => [ 'sleppian'],
};
$winpersubs{dpss}= \&dpss_per;

sub exponential {
  barf "exponential: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    2 ** (1 - abs (zeroes($N)->xlinvals(-1,1))) - 1;
}
$window_definitions{exponential} = {
};
$winsubs{exponential} = \&exponential;

sub exponential_per {
  barf "exponential: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    2 ** (1 - abs (zeroes($N)->xlinvals(-1, (-1+1*($N-1))/$N))) - 1;
}
$window_definitions{exponential} = {
};
$winpersubs{exponential}= \&exponential_per;

sub flattop {
  barf "flattop: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0,TPI)));

    (-0.05473684) +  ($cx * ((-0.165894739) +  ($cx * (0.498947372 + $cx * (-0.334315788 +$cx *(0.055578944))  ))));
}
$window_definitions{flattop} = {
fn => q!flat top!,
};
$winsubs{flattop} = \&flattop;

sub flattop_per {
  barf "flattop: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0, TPI*($N-1)/$N)));

    (-0.05473684) +  ($cx * ((-0.165894739) +  ($cx * (0.498947372 + $cx * (-0.334315788 +$cx *(0.055578944))  ))));
}
$window_definitions{flattop} = {
fn => q!flat top!,
};
$winpersubs{flattop}= \&flattop_per;

sub gaussian {
  barf "gaussian: 2 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 2;
  my ($N,$beta) = @_;
    exp (-0.5 * ($beta * (zeroes($N)->xlinvals(-1,1)) )**2);
}
$window_definitions{gaussian} = {
params => [ '$beta'],
alias => [ 'Weierstrass'],
};
$winsubs{gaussian} = \&gaussian;

sub gaussian_per {
  barf "gaussian: 2 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 2;
  my ($N,$beta) = @_;
    exp (-0.5 * ($beta * (zeroes($N)->xlinvals(-1, (-1+1*($N-1))/$N)) )**2);
}
$window_definitions{gaussian} = {
params => [ '$beta'],
alias => [ 'Weierstrass'],
};
$winpersubs{gaussian}= \&gaussian_per;

sub hamming {
  barf "hamming: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    0.54 + -0.46 * (cos(zeroes($N)->xlinvals(0,TPI)));
}
$window_definitions{hamming} = {
};
$winsubs{hamming} = \&hamming;

sub hamming_per {
  barf "hamming: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    0.54 + -0.46 * (cos(zeroes($N)->xlinvals(0, TPI*($N-1)/$N)));
}
$window_definitions{hamming} = {
};
$winpersubs{hamming}= \&hamming_per;

sub hamming_ex {
  barf "hamming_ex: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    0.53836 + -0.46164 * (cos(zeroes($N)->xlinvals(0,TPI)));
}
$window_definitions{hamming_ex} = {
fn => q!'exact' Hamming!,
};
$winsubs{hamming_ex} = \&hamming_ex;

sub hamming_ex_per {
  barf "hamming_ex: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    0.53836 + -0.46164 * (cos(zeroes($N)->xlinvals(0, TPI*($N-1)/$N)));
}
$window_definitions{hamming_ex} = {
fn => q!'exact' Hamming!,
};
$winpersubs{hamming_ex}= \&hamming_ex_per;

sub hamming_gen {
  barf "hamming_gen: 2 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 2;
  my ($N,$a) = @_;
    $a + -(1-$a) * (cos(zeroes($N)->xlinvals(0,TPI)));
}
$window_definitions{hamming_gen} = {
fn => q!general Hamming!,
params => [ '$a'],
};
$winsubs{hamming_gen} = \&hamming_gen;

sub hamming_gen_per {
  barf "hamming_gen: 2 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 2;
  my ($N,$a) = @_;
    $a + -(1-$a) * (cos(zeroes($N)->xlinvals(0, TPI*($N-1)/$N)));
}
$window_definitions{hamming_gen} = {
fn => q!general Hamming!,
params => [ '$a'],
};
$winpersubs{hamming_gen}= \&hamming_gen_per;

sub hann {
  barf "hann: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    0.5 + -0.5 * (cos(zeroes($N)->xlinvals(0,TPI)));
}
$window_definitions{hann} = {
alias => [ 'hanning'],
};
$winsubs{hann} = \&hann;

sub hann_per {
  barf "hann: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    0.5 + -0.5 * (cos(zeroes($N)->xlinvals(0, TPI*($N-1)/$N)));
}
$window_definitions{hann} = {
alias => [ 'hanning'],
};
$winpersubs{hann}= \&hann_per;

sub hann_matlab {
  barf "hann_matlab: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    0.5 - 0.5 * (cos(zeroes($N)->xlinvals(TPI/($N+1),TPI *$N /($N+1))));
}
$window_definitions{hann_matlab} = {
pfn => q!Hann (matlab)!,
fn => q!*Equivalent to the Hann window of N+2 points, with the endpoints (which are both zero) removed.!,
};
$winsubs{hann_matlab} = \&hann_matlab;

sub hann_poisson {
  barf "hann_poisson: 2 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 2;
  my ($N,$alpha) = @_;
    0.5 * (1 + (cos(zeroes($N)->xlinvals(-(PI),PI)))) * exp (-$alpha * abs (zeroes($N)->xlinvals(-1,1)));
}
$window_definitions{hann_poisson} = {
fn => q!Hann-Poisson!,
params => [ '$alpha'],
};
$winsubs{hann_poisson} = \&hann_poisson;

sub hann_poisson_per {
  barf "hann_poisson: 2 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 2;
  my ($N,$alpha) = @_;
    0.5 * (1 + (cos(zeroes($N)->xlinvals(-(PI), (-(PI)+PI*($N-1))/$N)))) * exp (-$alpha * abs (zeroes($N)->xlinvals(-1, (-1+1*($N-1))/$N)));
}
$window_definitions{hann_poisson} = {
fn => q!Hann-Poisson!,
params => [ '$alpha'],
};
$winpersubs{hann_poisson}= \&hann_poisson_per;

sub kaiser {
  barf "kaiser: 2 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 2;
  my ($N,$beta) = @_;

              barf "kaiser: PDL::GSLSF not installed" unless HAVE_BESSEL;
              $beta *= PI;
              my @n = PDL::GSLSF::BESSEL::gsl_sf_bessel_In ($beta * sqrt(1 - (zeroes($N)->xlinvals(-1,1)) **2),0);
        my @d = PDL::GSLSF::BESSEL::gsl_sf_bessel_In($beta,0);
        (shift @n)/(shift @d);
}
$window_definitions{kaiser} = {
params => [ '$beta'],
alias => [ 'Kaiser-Bessel'],
};
$winsubs{kaiser} = \&kaiser;

sub kaiser_per {
  barf "kaiser: 2 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 2;
  my ($N,$beta) = @_;

              barf "kaiser: PDL::GSLSF not installed" unless HAVE_BESSEL;
              $beta *= PI;
              my @n = PDL::GSLSF::BESSEL::gsl_sf_bessel_In ($beta * sqrt(1 - (zeroes($N)->xlinvals(-1, (-1+1*($N-1))/$N)) **2),0);
        my @d = PDL::GSLSF::BESSEL::gsl_sf_bessel_In($beta,0);
        (shift @n)/(shift @d);
}
$window_definitions{kaiser} = {
params => [ '$beta'],
alias => [ 'Kaiser-Bessel'],
};
$winpersubs{kaiser}= \&kaiser_per;

sub lanczos {
  barf "lanczos: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;

 my $x = PI * (zeroes($N)->xlinvals(-1,1));
 my $res = sin($x)/$x;
 my $mid;
 $mid = int($N/2), $res->slice($mid) .= 1 if $N % 2;
 $res;;
}
$window_definitions{lanczos} = {
alias => [ 'sinc'],
};
$winsubs{lanczos} = \&lanczos;

sub lanczos_per {
  barf "lanczos: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;

 my $x = PI * (zeroes($N)->xlinvals(-1, (-1+1*($N-1))/$N));
 my $res = sin($x)/$x;
 my $mid;
 $mid = int($N/2), $res->slice($mid) .= 1 unless $N % 2;
 $res;;
}
$window_definitions{lanczos} = {
alias => [ 'sinc'],
};
$winpersubs{lanczos}= \&lanczos_per;

sub nuttall {
  barf "nuttall: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0,TPI)));

    (0.2269824) +  ($cx * ((-0.4572542) +  ($cx * (0.273199 + $cx * (-0.0425644)  ))));
}
$window_definitions{nuttall} = {
};
$winsubs{nuttall} = \&nuttall;

sub nuttall_per {
  barf "nuttall: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0, TPI*($N-1)/$N)));

    (0.2269824) +  ($cx * ((-0.4572542) +  ($cx * (0.273199 + $cx * (-0.0425644)  ))));
}
$window_definitions{nuttall} = {
};
$winpersubs{nuttall}= \&nuttall_per;

sub nuttall1 {
  barf "nuttall1: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0,TPI)));

    (0.211536) +  ($cx * ((-0.449584) +  ($cx * (0.288464 + $cx * (-0.050416)  ))));
}
$window_definitions{nuttall1} = {
pfn => q!Nuttall (v1)!,
fn => q!*A window referred to as the Nuttall window.!,
};
$winsubs{nuttall1} = \&nuttall1;

sub nuttall1_per {
  barf "nuttall1: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    my $cx = (cos(zeroes($N)->xlinvals(0, TPI*($N-1)/$N)));

    (0.211536) +  ($cx * ((-0.449584) +  ($cx * (0.288464 + $cx * (-0.050416)  ))));
}
$window_definitions{nuttall1} = {
pfn => q!Nuttall (v1)!,
fn => q!*A window referred to as the Nuttall window.!,
};
$winpersubs{nuttall1}= \&nuttall1_per;

sub parzen {
  barf "parzen: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;

  my $x = zeroes($N)->xlinvals(-1,1);
  my $x1 = $x->where($x <= -.5);
  my $x2 = $x->where( ($x < .5)  & ($x > -.5) );
  my $x3 = $x->where($x >= .5);
  $x1 .= 2 * (1-abs($x1))**3;
  $x3 .= $x1->slice('-1:0:-1');
  $x2 .= 1 - 6 * $x2**2 *(1-abs($x2));
  return $x;
}
$window_definitions{parzen} = {
alias => [ 'Jackson','Valle-Poussin'],
};
$winsubs{parzen} = \&parzen;

sub parzen_per {
  barf "parzen: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;

  my $x = zeroes($N)->xlinvals(-1,(-1 + ($N-1))/($N));
  my $x1 = $x->where($x <= -.5);
  my $x2 = $x->where( ($x < .5)  & ($x > -.5) );
  my $x3 = $x->where($x >= .5);
  $x1 .= 2 * (1-abs($x1))**3;
  $x3 .= $x1->slice('-1:1:-1');
  $x2 .= 1 - 6 * $x2**2 *(1-abs($x2));
  return $x;
}
$window_definitions{parzen} = {
alias => [ 'Jackson','Valle-Poussin'],
};
$winpersubs{parzen}= \&parzen_per;

sub parzen_octave {
  barf "parzen_octave: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;

        my $L = $N-1;
        my $r = ($L/2);
        my $r4 = ($r/2);
        my $n = sequence(2*$r+1)-$r;
        my $n1 = $n->where(abs($n) <= $r4);
        my $n2 = $n->where($n > $r4);
        my $n3 = $n->where($n < -$r4);
        $n1 .= 1 -6.*(abs($n1)/($N/2))**2 + 6*(abs($n1)/($N/2))**3;
        $n2 .= 2.*(1-abs($n2)/($N/2))**3;
        $n3 .= 2.*(1-abs($n3)/($N/2))**3;
        $n;
    ;
}
$window_definitions{parzen_octave} = {
fn => q!Parzen!,
};
$winsubs{parzen_octave} = \&parzen_octave;

sub poisson {
  barf "poisson: 2 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 2;
  my ($N,$alpha) = @_;
    exp (-$alpha * abs (zeroes($N)->xlinvals(-1,1)));
}
$window_definitions{poisson} = {
params => [ '$alpha'],
};
$winsubs{poisson} = \&poisson;

sub poisson_per {
  barf "poisson: 2 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 2;
  my ($N,$alpha) = @_;
    exp (-$alpha * abs (zeroes($N)->xlinvals(-1, (-1+1*($N-1))/$N)));
}
$window_definitions{poisson} = {
params => [ '$alpha'],
};
$winpersubs{poisson}= \&poisson_per;

sub rectangular {
  barf "rectangular: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    ones($N);
}
$window_definitions{rectangular} = {
alias => [ 'dirichlet','boxcar'],
};
$winsubs{rectangular} = \&rectangular;

sub rectangular_per {
  barf "rectangular: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    ones($N);
}
$window_definitions{rectangular} = {
alias => [ 'dirichlet','boxcar'],
};
$winpersubs{rectangular}= \&rectangular_per;

sub triangular {
  barf "triangular: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    1 - abs (zeroes($N)->xlinvals(-($N-1)/$N,($N-1)/$N));
}
$window_definitions{triangular} = {
};
$winsubs{triangular} = \&triangular;

sub triangular_per {
  barf "triangular: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    1 - abs (zeroes($N)->xlinvals(-$N/($N+1),-1/($N+1)+($N-1)/($N+1)));
}
$window_definitions{triangular} = {
};
$winpersubs{triangular}= \&triangular_per;

sub tukey {
  barf "tukey: 2 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 2;
  my ($N,$alpha) = @_;

  barf("tukey: alpha must be between 0 and 1") unless
         $alpha >=0 and $alpha <= 1;
  return ones($N) if $alpha == 0;
  my $x = zeroes($N)->xlinvals(0,1);
  my $x1 = $x->where($x < $alpha/2);
  my $x2 = $x->where( ($x <= 1-$alpha/2) & ($x >= $alpha/2) );
  my $x3 = $x->where($x > 1 - $alpha/2);
  $x1 .= 0.5 * ( 1 + cos( PI * (2*$x1/$alpha -1)));
  $x2 .= 1;
  $x3 .= $x1->slice('-1:0:-1');
  return $x;
}
$window_definitions{tukey} = {
params => [ '$alpha'],
alias => [ 'tapered cosine'],
};
$winsubs{tukey} = \&tukey;

sub tukey_per {
  barf "tukey: 2 arguments expected. Got " . scalar(@_) . ' arguments.' unless @_ == 2;
  my ($N,$alpha) = @_;

  barf("tukey: alpha must be between 0 and 1") unless
         $alpha >=0 and $alpha <= 1;
  return ones($N) if $alpha == 0;
  my $x = zeroes($N)->xlinvals(0,($N-1)/$N);
  my $x1 = $x->where($x < $alpha/2);
  my $x2 = $x->where( ($x <= 1-$alpha/2) & ($x >= $alpha/2) );
  my $x3 = $x->where($x > 1 - $alpha/2);
  $x1 .= 0.5 * ( 1 + cos( PI * (2*$x1/$alpha -1)));
  $x2 .= 1;
  $x3 .= $x1->slice('-1:1:-1');
  return $x;
}
$window_definitions{tukey} = {
params => [ '$alpha'],
alias => [ 'tapered cosine'],
};
$winpersubs{tukey}= \&tukey_per;

sub welch {
  barf "welch: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    1 - (zeroes($N)->xlinvals(-1,1))**2;
}
$window_definitions{welch} = {
alias => [ 'Riez','Bochner','Parzen','parabolic'],
};
$winsubs{welch} = \&welch;

sub welch_per {
  barf "welch: 1 argument expected. Got " . scalar(@_) . ' arguments.' unless @_ == 1;
  my ($N) = @_;
    1 - (zeroes($N)->xlinvals(-1, (-1+1*($N-1))/$N))**2;
}
$window_definitions{welch} = {
alias => [ 'Riez','Bochner','Parzen','parabolic'],
};
$winpersubs{welch}= \&welch_per;

=head1  Symmetric window functions

=head2 bartlett($N)

The Bartlett window. (Ref 1). Another name for this window is the fejer window.  This window is defined by

 1 - abs arr,

where the points in arr range from -1 through 1.
See also L<triangular|/triangular($N)>.

=head2 bartlett_hann($N)

The Bartlett-Hann window. Another name for this window is the Modified Bartlett-Hann window.  This window is defined by

 0.62 - 0.48 * abs arr + 0.38* arr1,

where the points in arr range from -1/2 through 1/2, and arr1 are the cos of points ranging from -PI through PI.

=head2 blackman($N)

The 'classic' Blackman window. (Ref 1). One of the Blackman-Harris family, with coefficients

 a0 = 0.42, a1 = 0.5, a2 = 0.08

=head2 blackman_bnh($N)

The Blackman-Harris (bnh) window. An improved version of the 3-term Blackman-Harris window given by Nuttall (Ref 2, p. 89). One of the Blackman-Harris family, with coefficients

 a0 = 0.4243801, a1 = 0.4973406, a2 = 0.0782793

=head2 blackman_ex($N)

The 'exact' Blackman window. (Ref 1). One of the Blackman-Harris family, with coefficients

 a0 = 0.426590713671539, a1 = 0.496560619088564, a2 = 0.0768486672398968

=head2 blackman_gen($N,$alpha)

The General classic Blackman window. A single parameter family of the 3-term Blackman window.   This window is defined by

 my $cx = arr;

    (.5 - $alpha) +  ($cx * ((-.5) +  ($cx * ($alpha)))),

where the points in arr are the cos of points ranging from 0 through 2PI.

=head2 blackman_gen3($N,$a0,$a1,$a2)

The general form of the Blackman family.  One of the Blackman-Harris family, with coefficients

 a0 = $a0, a1 = $a1, a2 = $a2

=head2 blackman_gen4($N,$a0,$a1,$a2,$a3)

The general 4-term Blackman-Harris window.  One of the Blackman-Harris family, with coefficients

 a0 = $a0, a1 = $a1, a2 = $a2, a3 = $a3

=head2 blackman_gen5($N,$a0,$a1,$a2,$a3,$a4)

The general 5-term Blackman-Harris window.  One of the Blackman-Harris family, with coefficients

 a0 = $a0, a1 = $a1, a2 = $a2, a3 = $a3, a4 = $a4

=head2 blackman_harris($N)

The Blackman-Harris window. (Ref 1). One of the Blackman-Harris family, with coefficients

 a0 = 0.422323, a1 = 0.49755, a2 = 0.07922

Another name for this window is the Minimum three term (sample) Blackman-Harris window.

=head2 blackman_harris4($N)

The minimum (sidelobe) four term Blackman-Harris window. (Ref 1). One of the Blackman-Harris family, with coefficients

 a0 = 0.35875, a1 = 0.48829, a2 = 0.14128, a3 = 0.01168

Another name for this window is the Blackman-Harris window.

=head2 blackman_nuttall($N)

The Blackman-Nuttall window. One of the Blackman-Harris family, with coefficients

 a0 = 0.3635819, a1 = 0.4891775, a2 = 0.1365995, a3 = 0.0106411

=head2 bohman($N)

The Bohman window. (Ref 1).  This window is defined by

 my $x = abs(arr);
(1-$x)*cos(PI*$x) +(1/PI)*sin(PI*$x),

where the points in arr range from -1 through 1.

=head2 cauchy($N,$alpha)

The Cauchy window. (Ref 1). Other names for this window are: Abel, Poisson.  This window is defined by

 1 / (1 + (arr * $alpha)**2),

where the points in arr range from -1 through 1.

=head2 chebyshev($N,$at)

The Chebyshev window. The frequency response of this window has C<$at> dB of attenuation in the stop-band.
Another name for this window is the Dolph-Chebyshev window. No periodic version of this window is defined.
This routine gives the same result as the routine B<chebwin> in Octave 3.6.2.

=head2 cos_alpha($N,$alpha)

The Cos_alpha window. (Ref 1). Another name for this window is the Power-of-cosine window.  This window is defined by

  arr**$alpha ,

where the points in arr are the sin of points ranging from 0 through PI.

=head2 cosine($N)

The Cosine window. Another name for this window is the sine window.  This window is defined by

 arr,

where the points in arr are the sin of points ranging from 0 through PI.

=head2 dpss($N,$beta)

The Digital Prolate Spheroidal Sequence (DPSS) window. The parameter C<$beta> is the half-width of the mainlobe, measured in frequency bins. This window maximizes the power in the mainlobe for given C<$N> and C<$beta>.
Another name for this window is the sleppian window.

=head2 exponential($N)

The Exponential window.  This window is defined by

 2 ** (1 - abs arr) - 1,

where the points in arr range from -1 through 1.

=head2 flattop($N)

The flat top window. One of the Blackman-Harris family, with coefficients

 a0 = 0.21557895, a1 = 0.41663158, a2 = 0.277263158, a3 = 0.083578947, a4 = 0.006947368

=head2 gaussian($N,$beta)

The Gaussian window. (Ref 1). Another name for this window is the Weierstrass window.  This window is defined by

 exp (-0.5 * ($beta * arr )**2),

where the points in arr range from -1 through 1.

=head2 hamming($N)

The Hamming window. (Ref 1). One of the Blackman-Harris family, with coefficients

 a0 = 0.54, a1 = 0.46

=head2 hamming_ex($N)

The 'exact' Hamming window. (Ref 1). One of the Blackman-Harris family, with coefficients

 a0 = 0.53836, a1 = 0.46164

=head2 hamming_gen($N,$a)

The general Hamming window. (Ref 1). One of the Blackman-Harris family, with coefficients

 a0 = $a, a1 = (1-$a)

=head2 hann($N)

The Hann window. (Ref 1). One of the Blackman-Harris family, with coefficients

 a0 = 0.5, a1 = 0.5

Another name for this window is the hanning window. See also L<hann_matlab|/hann_matlab($N)>.

=head2 hann_matlab($N)

The Hann (matlab) window. Equivalent to the Hann window of N+2 points, with the endpoints (which are both zero) removed. No periodic version of this window is defined.
 This window is defined by

 0.5 - 0.5 * arr,

where the points in arr are the cosine of points ranging from 2PI/($N+1) through 2PI*$N/($N+1).
This routine gives the same result as the routine B<hanning> in Matlab.
See also L<hann|/hann($N)>.

=head2 hann_poisson($N,$alpha)

The Hann-Poisson window. (Ref 1).  This window is defined by

 0.5 * (1 + arr1) * exp (-$alpha * abs arr),

where the points in arr range from -1 through 1, and arr1 are the cos of points ranging from -PI through PI.

=head2 kaiser($N,$beta)

The Kaiser window. (Ref 1). The parameter C<$beta> is the approximate half-width of the mainlobe, measured in frequency bins.
Another name for this window is the Kaiser-Bessel window.  This window is defined by


              barf "kaiser: PDL::GSLSF not installed" unless HAVE_BESSEL;
              $beta *= PI;
              my @n = PDL::GSLSF::BESSEL::gsl_sf_bessel_In ($beta * sqrt(1 - arr **2),0);
        my @d = PDL::GSLSF::BESSEL::gsl_sf_bessel_In($beta,0);
        (shift @n)/(shift @d),

where the points in arr range from -1 through 1.

=head2 lanczos($N)

The Lanczos window. Another name for this window is the sinc window.  This window is defined by

 my $x = PI * arr;
 my $res = sin($x)/$x;
 my $mid;
 $mid = int($N/2), $res->slice($mid) .= 1 if $N % 2;
 $res;,

where the points in arr range from -1 through 1.

=head2 nuttall($N)

The Nuttall window. One of the Blackman-Harris family, with coefficients

 a0 = 0.3635819, a1 = 0.4891775, a2 = 0.1365995, a3 = 0.0106411

See also L<nuttall1|/nuttall1($N)>.

=head2 nuttall1($N)

The Nuttall (v1) window. A window referred to as the Nuttall window. One of the Blackman-Harris family, with coefficients

 a0 = 0.355768, a1 = 0.487396, a2 = 0.144232, a3 = 0.012604

This routine gives the same result as the routine B<nuttallwin> in Octave 3.6.2.
See also L<nuttall|/nuttall($N)>.

=head2 parzen($N)

The Parzen window. (Ref 1). Other names for this window are: Jackson, Valle-Poussin. This function disagrees with the Octave subroutine B<parzenwin>, but agrees with Ref. 1.
See also L<parzen_octave|/parzen_octave($N)>.

=head2 parzen_octave($N)

The Parzen window. No periodic version of this window is defined.
This routine gives the same result as the routine B<parzenwin> in Octave 3.6.2.
See also L<parzen|/parzen($N)>.

=head2 poisson($N,$alpha)

The Poisson window. (Ref 1).  This window is defined by

 exp (-$alpha * abs arr),

where the points in arr range from -1 through 1.

=head2 rectangular($N)

The Rectangular window. (Ref 1). Other names for this window are: dirichlet, boxcar.

=head2 triangular($N)

The Triangular window.  This window is defined by

 1 - abs arr,

where the points in arr range from -$N/($N-1) through $N/($N-1).
See also L<bartlett|/bartlett($N)>.

=head2 tukey($N,$alpha)

The Tukey window. (Ref 1). Another name for this window is the tapered cosine window.

=head2 welch($N)

The Welch window. (Ref 1). Other names for this window are: Riez, Bochner, Parzen, parabolic.  This window is defined by

 1 - arr**2,

where the points in arr range from -1 through 1.

=head1 AUXILIARY SUBROUTINES

These subroutines are used internally, but are also available for export.

=head2 cos_mult_to_pow

Convert Blackman-Harris coefficients. The BH windows are usually defined via coefficients
for cosines of integer multiples of an argument. The same windows may be written instead
as terms of powers of cosines of the same argument. These may be computed faster as they
replace evaluation of cosines with  multiplications.
This subroutine is used internally to implement the Blackman-Harris
family of windows more efficiently.

This subroutine takes between 1 and 7 numeric arguments  a0, a1, ...

It converts the coefficients of this

  a0 - a1 cos(arg) + a2 cos( 2 * arg) - a3 cos( 3 * arg)  + ...

To the cofficients of this

  c0 + c1 cos(arg) + c2 cos(arg)**2 + c3 cos(arg)**3  + ...

=head2 cos_pow_to_mult

This function is the inverse of L</cos_mult_to_pow>.

This subroutine takes between 1 and 7 numeric arguments  c0, c1, ...

It converts the coefficients of this

  c0 + c1 cos(arg) + c2 cos(arg)**2 + c3 cos(arg)**3  + ...

To the cofficients of this

  a0 - a1 cos(arg) + a2 cos( 2 * arg) - a3 cos( 3 * arg)  + ...

=cut

sub cos_pow_to_mult {
    my( @cin )  = @_;
    barf "cos_pow_to_mult: number of args not less than 8." if @cin > 7;
    my $ex = 7 - @cin;
    my @c = (@cin, (0) x $ex);
    my (@as) = (
        10*$c[6]+12*$c[4]+16*$c[2]+32*$c[0], 20*$c[5]+24*$c[3]+32*$c[1],
         15*$c[6]+16*$c[4]+16*$c[2], 10*$c[5]+8*$c[3], 6*$c[6]+4*$c[4], 2*$c[5], $c[6]);
    foreach (1..$ex) {pop (@as)}
    my $sign = -1;
    foreach (@as) { $_ /= (-$sign*32); $sign *= -1 }
    @as;
}

=head2 chebpoly

=for usage

    chebpoly($n,$x)

=for ref

Returns the value of the C<$n>-th order Chebyshev polynomial at point C<$x>.
$n and $x may be scalar numbers, pdl's, or array refs. However,
at least one of $n and $x must be a scalar number.

All mixtures of pdls and scalars could be handled much more
easily as a PP routine. But, at this point PDL::DSP::Windows
is pure perl/pdl, requiring no C/Fortran compiler.

=cut

sub chebpoly {
    barf 'chebpoly: Two arguments expected. Got ' .scalar(@_) ."\n" unless @_==2;
    my ($n,$x) = @_;
    if (ref($x)) {
        $x = topdl($x);
        barf "chebpoly: neither $n nor $x is a scalar number" if ref($n);
        my $tn = zeroes($x);
        my ($ind1,$ind2);
        ($ind1,$ind2) = which_both(abs($x) <= 1);
        $tn->index($ind1) .= cos($n*(acos($x->index($ind1))));
        $tn->index($ind2) .= cosh($n*(acosh($x->index($ind2))));
        return $tn;
    }
    else {
        $n = topdl($n) if ref($n);
        return cos($n*(acos($x))) if abs($x) <= 1;
        return cosh($n*(acosh($x)));
    }
}


sub cos_mult_to_pow {
    my( @ain )  = @_;
    barf("cos_mult_to_pow: number of args not less than 8.") if @ain > 7;
    my $ex = 7 - @ain;
    my @a = (@ain, (0) x $ex);
    my (@cs) = (
        -$a[6]+$a[4]-$a[2]+$a[0], -5*$a[5]+3*$a[3]-$a[1], 18*$a[6]-8*$a[4]+2*$a[2], 20*$a[5]-4*$a[3],
        8*$a[4]-48*$a[6], -16*$a[5], 32*$a[6]);
    foreach (1..$ex) {pop (@cs)}
    @cs;
}

=head1 REFERENCES

=over

=item 1

Harris, F.J. C<On the use of windows for harmonic analysis with the discrete Fourier transform>,
I<Proceedings of the IEEE>, 1978, vol 66, pp 51-83.

=item 2

Nuttall, A.H. C<Some windows with very good sidelobe behavior>, I<IEEE Transactions on Acoustics, Speech, Signal Processing>,
1981, vol. ASSP-29, pp. 84-91.

=back

=head1 AUTHOR

John Lapeyre, C<< <jlapeyre at cpan.org> >>

=head1 ACKNOWLEDGMENTS

For study and comparison, the author used documents or output from:
Thomas Cokelaer's spectral analysis software; Julius O Smith III's
Spectral Audio Signal Processing web pages; André Carezia's
chebwin.m Octave code; Other code in the Octave signal package.

=head1 LICENSE AND COPYRIGHT

Copyright 2012 John Lapeyre.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

This software is neither licensed nor distributed by The MathWorks, Inc.,
maker and liscensor of MATLAB.

=cut

1;
