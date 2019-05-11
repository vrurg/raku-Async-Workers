#!/usr/bin/env perl6

use lib <lib>;
use META6;
use Async::Workers;

my $m = META6.new(
    name           => 'Async::Workers',
    description    => 'Asynchronous threaded workers',
    version        => Async::Workers.^ver,
    perl-version   => Version.new('6.d'),
    depends        => [ <AttrX::Mooish> ],
    test-depends   => <Test Test::META Test::When>,
    build-depends  => <META6 p6doc Pod::To::Markdown>,
    tags           => <threads async>,
    authors        => ['Vadim Belman <vrurg@cpan.org>'],
    auth           => 'github:vrurg',
    source-url     => 'https://github.com/vrurg/Perl6-Async-Workers.git',
    support        => META6::Support.new(
        source          => 'https://github.com/vrurg/Perl6-Async-Workers.git',
    ),
    provides => {
        'Async::Workers' => 'lib/Async/Workers.pm6',
    },
    license        => 'Artistic-2.0',
    production     => False,
);

print $m.to-json;

#my $m = META6.new(file => './META6.json');
#$m<version description> = v0.0.2, 'Work with Perl 6 META files even better';
#spurt('./META6.json', $m.to-json);
