requires 'PDL' => '2.055';

recommends 'PDL::LinearAlgebra::Special';
recommends 'PDL::GSLSF::BESSEL';
recommends 'PDL::Graphics::Simple';

on test => sub {
    requires 'Test::More'    => '0.96';
};
