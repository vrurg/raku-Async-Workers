use v6.d;
use Test::Async;
use Async::Workers;

plan 2;

my %results;

for 1..10 -> $n {
    do-async: {
        %results{"result$n"} = $n;
    }
}

my $awaited = False;
await Promise.anyof:
    Promise.in(1),
    start {
        await async-workers;
        $awaited = True;
    };

ok $awaited, "all workers done";

my %expected =
    :result1(1),
    :result2(2),
    :result3(3),
    :result4(4),
    :result5(5),
    :result6(6),
    :result7(7),
    :result8(8),
    :result9(9),
    :result10(10),
;
is-deeply %results, %expected, "workers results";

done-testing;
