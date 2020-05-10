use v6.d;
use Test::Async;
use Async::Workers;
use Async::Msg;

plan 6, :parallel, :random;

subtest "Basics" => -> \suite {
    plan 6;
    my $w = Async::Workers.new(:max-workers(10));

    is $w.workers, 0, "No workers on start";

    $w.do-async: { suite.pass: "Async job" };

    sleep .1;
    is $w.workers, 10, "Vivified all workers on demand";

    $w.workers(15);

    sleep .1;
    is $w.workers, 15, "Started 5 additional";

    $w.workers(12);

    sleep .1;
    is $w.workers, 12, "Shut down 3 workers";

    $w.shutdown;

    sleep .1;
    is $w.workers, 0, "Shut down all workers";
}

subtest "Await" => -> \suite {
    plan 3;
    my $w = Async::Workers.new;

    my $sleep = Promise.new;
    $w.do-async: { await $sleep; };

    $w.shutdown;
    suite.start: {
        sleep 1;
        is $w.running, 1, "job is still awaiting in 1 second";
        $sleep.keep(True);
    }
    my $awaited-ok;
    await Promise.anyof(
            $sleep.then({
                # Let the await to complete.
                sleep 10;
                cas $awaited-ok, Any, False;
            }),
            start {
                await $w;
                cas $awaited-ok, Any, True;
            }
        );
    ok $awaited-ok, "await awaits as expected";
    is $w.running, 0, "all running jobs are done by now";
}

subtest "Limited queue" => {
    plan 10;
    my @w;
    for 1 .. 10 {
        subtest "Queue limits $_", {
            plan 5;

            my $lo-threshold = 10;
            my $hi-threshold = 20;
            my $total-cycles = 20;
            my $expected-workers = $lo-threshold + ($hi-threshold - $lo-threshold) * $total-cycles;
            my atomicint $fulls = 0;
            my atomicint $empties = 0;
            my atomicint $lows = 0;
            my atomicint $started = 0;
            my atomicint $completed = 0;
            my atomicint $cycles = $total-cycles;

            my $starter = Promise.new;
            my $finish = Promise.new;
            my $timeout = Promise.in(30);

            $timeout.then: {
                if $finish.status ~~ Planned {
                    $finish.keep(True);
                }
            };

            my $w = Async::Workers.new(max-workers => 1, :$lo-threshold, :$hi-threshold);

            my atomicint $id = 0;
            sub add_workers($num) {
                for ^$num {
                    ++⚛$id;
                    $w.do-async: {
                        await $starter;
                        ++⚛$completed;
                    };
                    ++⚛$started;
                }
            }

            $w.on_msg: -> $msg {
                if $msg ~~ Async::Msg::Queue {
                    given $msg.status {
                        when QFull {
                            # Release the workers
                            $starter.keep(True);
                            $fulls⚛++;
                        }
                        when QLow {
                            if --⚛$cycles {
                                # We still have cycles to complete.
                                $starter = Promise.new;
                                start add_workers($w.hi-threshold - $w.queued);
                            }
                            else {
                                $finish.keep(True);
                            }
                            $lows⚛++;
                        }
                        when QEmpty {
                            $empties⚛++;
                        }
                    }
                }
            };

            # Should result in first QFull
            add_workers($w.hi-threshold);
            await $finish;

            $w.shutdown;

            is $started, $expected-workers, "all workers started";
            is $completed, $expected-workers, "all workers done";
            is $fulls, $total-cycles, "queue on high threshold";
            is $lows, $total-cycles, "queue on low threshold";
            is $empties, 1, "queue empty";
        }
    }
}

subtest "Await Workers" => {
    plan 5;

    my $num-workers = 20;

    my $w = Async::Workers.new;

    my $awaited = False;

    await Promise.anyof:
        Promise.in(.1), start {
            await $w;
            $awaited = True;
        };

    ok $awaited, "await on fresh state";

    my atomicint $counter ⚛= 0;
    my &code = -> $max-delay = .1 {
        sleep $max-delay.rand;
        $counter⚛++;
    }

    for ^$num-workers {
        $w.do-async: &code
    }

    $awaited = False;
    await Promise.anyof:
        Promise.in(10), start {
            await $w;
            $awaited = True;
        };

    ok $awaited, "await for non-finished queue";

    is $counter, $num-workers, "all workers completed";

    my $w1 = Async::Workers.new(:max-workers(5));
    my $w2 = Async::Workers.new(:max-workers(10));

    $awaited = False;
    $counter ⚛= 0;

    for ^$num-workers {
        $w1.do-async: &code, .5;
        $w2.do-async: &code, .5;
    }

    $awaited = Nil;
    my $tout = Promise.in(60);
    $tout.then({ cas $awaited, Any, False }),
    my $workers = start { await $w1, $w2; cas $awaited, Any, True; };
    await Promise.anyof($tout, $workers);

    ok $awaited, "await for non-finished queue on two managers";

    is $counter, (2 * $num-workers), "all workers of both managers completed";
}

subtest "Stop Worker", {
    plan 1;

    my $w = Async::Workers.new;

    my atomicint $steps = 0;
    $w.do-async: {
        $steps++;
        stop-worker;
        flunk "must not be here";
        $steps++;
        # Must not reach this point.
    }

    $w.shutdown;
    await $w;

    is $steps, 1, "a worker has been stopped";
}

subtest "Single worker" => {
    plan 1;
    my $num-workers = 20;
    my $w = Async::Workers.new(:max-workers(1));
    my atomicint $counter = 0;
    for ^$num-workers -> $id; {
        $w.do-async: {
            ++⚛$counter;
        }
    }
    $w.shutdown;
    await $w;
    is $counter, $num-workers, "single concurrent worker is ok";
}

done-testing;
