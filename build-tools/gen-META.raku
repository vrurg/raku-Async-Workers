#!/usr/bin/env raku

use lib <lib>;
use META6;
use Async::Workers;

my $m = META6.new(
    name           => 'Async::Workers',
    description    => 'Asynchronous threaded workers',
    version        => Async::Workers.^ver,
    perl-version   => Version.new('6.d'),
    depends        => [<AttrX::Mooish>],
    test-depends   => <Test Test::Async Test::META Test::When>,
    tags           => <threads async>,
    authors        => ['Vadim Belman <vrurg@cpan.org>'],
    auth           => 'github:vrurg',
    source-url     => 'https://github.com/vrurg/raku-Async-Workers.git',
    support        => META6::Support.new(
        source => 'https://github.com/vrurg/raku-Async-Workers.git',
    ),
    provides => {
        'Async::Workers' => 'lib/Async/Workers.rakumod',
        'Async::Workers::CX' => 'lib/Async/Workers/CX.rakumod',
        'Async::Workers::Job' => 'lib/Async/Workers/Job.rakumod',
        'Async::Workers::Msg' => 'lib/Async/Workers/Msg.rakumod',
        'Async::Workers::Worker' => 'lib/Async/Workers/Worker.rakumod',
        'Async::Workers::X' => 'lib/Async/Workers/X.rakumod',
    },
    license        => 'Artistic-2.0',
    production     => True,
);

print $m.to-json;

#my $m = META6.new(file => './META6.json');
#$m<version description> = v0.0.2, 'Work with Perl 6 META files even better';
#spurt('./META6.json', $m.to-json);
