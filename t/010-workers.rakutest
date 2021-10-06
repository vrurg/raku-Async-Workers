use v6.d;
BEGIN {
    $*SCHEDULER = ThreadPoolScheduler.new: :max_threads(500);
    $*ERR.out-buffer = False;
    $*OUT.out-buffer = False;
}
use Test::Async;
use Async::Workers;
use Async::Workers::Job;
use Async::Workers::Msg;

plan 7, :parallel, :random, :job-timeout(20);

subtest "Basics" => -> \suite {
    plan 10;
    my $wm = Async::Workers.new(:max-workers(10));

    my $expected-msg;
    my atomicint $expected-count = 0;
    my $expecting-promise;

    # Monitor manager messages and count worker starts/completions when necessary
    $wm.on_msg: -> $msg {
        if ($expected-count > 0)  && ($msg.WHAT === $expected-msg) {
            $expecting-promise.keep unless --⚛$expected-count;
        }
    }

    sub check-workers-count($count) {
        $wm.do-async: { suite.pass: "job for workers count $count" };
        await Promise.anyof(
            Promise.in(30),
            $expecting-promise);
        is $wm.workers, $count, "got all expected $count workers";
    }

    sub expect-for($count) {
        $expected-msg = $count < 0
            ?? Async::Workers::Msg::Worker::Complete
            !! Async::Workers::Msg::Worker::Started;
        $expecting-promise = Promise.new;
        $expected-count ⚛= $count.abs;
    }

    is $wm.workers, 0, "No workers on start";
    expect-for(10);
    my $rc = $wm.do-async: { suite.pass: "Async job" };
    isa-ok $rc, Async::Workers::Job, "got a job type from do-asyn";
    check-workers-count(10);

    for 15,12 -> $jcount {
        expect-for($jcount - $wm.workers);
        $wm.workers($jcount);
        check-workers-count($jcount);
    }

    $wm.shutdown;

    await $wm.completed;

    is $wm.workers, 0, "all workers are shut down";
}

subtest "Await" => -> \suite {
    plan 3;
    my $wm = Async::Workers.new;

    my $sleep = Promise.new;
    $wm.do-async: { await $sleep };

    $wm.shutdown;
    suite.start: {
        sleep 1;
        is $wm.running, 1, "job is still awaiting in 1 second";
        $sleep.keep(True);
    }
    my Bool $awaited-ok;
    await Promise.anyof(
            $sleep.then({
                # Let the await to complete.
                sleep 10;
                cas $awaited-ok, Bool, False;
            }),
            start {
                await $wm;
                cas $awaited-ok, Bool, True;
            }
        );
    ok $awaited-ok, "await awaits as expected";
    is $wm.running, 0, "all running jobs are done by now";
}

subtest "Limited queue", -> \suite {
    my $tries = 10;
    plan $tries, :parallel;
    for 1..$tries -> $try-id {
        subtest "Queue limits with $try-id workers", -> \suite {
            plan 6;

            my $lo-threshold = 10;
            my $hi-threshold = 20;
            my $total-cycles = 5;
            my $expected-workers = $lo-threshold + ($hi-threshold - $lo-threshold) * $total-cycles;
            my atomicint $fulls = 0;
            my atomicint $empties = 0;
            my atomicint $promised-empties = 0;
            my atomicint $lows = 0;
            my atomicint $started = 0;
            my atomicint $completed = 0;
            my atomicint $cycles = $total-cycles;

            my $finish = Promise.new;
            my $timeout = Promise.in(60);

            $timeout.then: {
                if $finish.status ~~ Planned {
                    diag "Test takes too long...";
                    $finish.keep(True);
                }
            };

            my $wm = Async::Workers.new(max-workers => $try-id, :$lo-threshold, :$hi-threshold);

            my $job-unblock = Promise.new;
            my atomicint $release-count = 0;
            sub add-workers(Int:D $num) {
                for ^$num {
                    $wm.do-async: {
                        my $release-job = False;
                        until $release-job || $finish {
                            my $ju = ⚛$job-unblock;
                            await $ju;
                            my $old-rcount;
                            my $new-rcount = cas $release-count, {
                                $old-rcount = $_;
                                ($release-job = $_ > 0) ?? $_ - 1 !! $_
                            };
                            my $left = False;
                            cas $job-unblock, {
                                $left = ($new-rcount != 0 || $old-rcount != 1 || $finish || .status == Planned)
                                    ?? $_
                                    !! Promise.new
                            };
                        }
                        ++⚛$completed;
                    }
                    ++⚛$started;
                }
            }

            $wm.empty.then: { ++⚛$promised-empties };
            $wm.on_msg: -> $msg {
                given $msg {
                    when Async::Workers::Msg::Job::Died {
                        $wm.x-sorry: .exception, "JOB #" ~ .job.id;
                    }
                    when Async::Workers::Msg::Queue::Full {
                        ++⚛$fulls;
                        $release-count ⚛= $wm.hi-threshold - $wm.lo-threshold;
                        $job-unblock.keep;
                    }
                    when Async::Workers::Msg::Queue::Low {
                        my $c = --⚛$cycles;
                        if $c {
                            add-workers($wm.hi-threshold - $wm.lo-threshold);
                        }
                        else {
                            $finish.keep;
                            $release-count ⚛= $wm.lo-threshold;
                            my $ju = $job-unblock;
                            cas $job-unblock, $ju, Promise.kept;
                            $ju.keep if $ju.status == Planned;
                        }
                        ++⚛$lows;
                    }
                    when Async::Workers::Msg::Queue::Empty {
                        ++⚛$empties;
                    }
                }
            };

            add-workers($wm.hi-threshold);
            await $finish;

            $wm.shutdown;
            await $wm.completed;

            is $started, $expected-workers, "all workers started";
            is $completed, $expected-workers, "all workers done";
            is $fulls, $total-cycles, "queue on high threshold";
            is $lows, $total-cycles, "queue on low threshold";
            is $empties, 1, "queue empty";
            is $promised-empties, 1, "queue emptiness reported via a Promise";
        }
    }
}

subtest "Await Workers", -> \suite {
    plan 5;

    my $num-jobs = 20;

    my $wm = Async::Workers.new;

    my $awaited = False;

    await Promise.anyof:
        Promise.in(.1), start {
            await $wm;
            $awaited = True;
        };

    ok $awaited, "await on fresh state";

    my atomicint $counter ⚛= 0;
    my &code = -> $max-delay = .1 {
        sleep $max-delay.rand;
        ++⚛$counter;
    }

    for ^$num-jobs {
        $wm.do-async: &code
    }

    $awaited = False;
    await Promise.anyof:
        Promise.in(10),
        start {
            await $wm;
            $awaited = True;
        };

    ok $awaited, "await for non-finished queue";

    is $counter, $num-jobs, "all workers completed";

    my $wm1 = Async::Workers.new(:max-workers(5));
    my $wm2 = Async::Workers.new(:max-workers(10));

    $awaited = False;
    $counter ⚛= 0;

    for ^$num-jobs {
        $wm1.do-async: &code, .5;
        $wm2.do-async: &code, .5;
    }

    $awaited = Nil;
    my $tout = Promise.in(60);
    $tout.then({ cas $awaited, Any, False }),
    my $workers = start { await $wm1, $wm2; cas $awaited, Any, True; };
    await Promise.anyof($tout, $workers);

    ok $awaited, "await for non-finished queue on two managers";

    is $counter, (2 * $num-jobs), "all workers of both managers completed";
}

subtest "Hard Stop Worker", -> \suite {
    # In this test we check if stop-worker causes both current job and its worker to be aborted immediately.
    plan 1;
    my $w = Async::Workers.new;
    my atomicint $steps = 0;
    $w.do-async: {
        $steps++;
        stop-worker;
        flunk "must not be here";
        $steps++;
    }

    $w.shutdown;
    await $w.completed;

    is $steps, 1, "a worker has been stopped";
}

subtest "Gradually Shutdown Worker", -> \suite {
    # In this test we check if worker method shutdown results in worker shutting down when job is complete.
    plan 4;
    my $wm = Async::Workers.new;
    my atomicint $worker-id;
    my atomicint $steps = 0;
    my Promise:D $worker-down .= new;

    $wm.on_msg: -> $msg {
        given $msg {
            when Async::Workers::Msg::Worker::Complete {
                with $worker-id {
                    if $steps == 2 && $msg.worker.id == $worker-id {
                        suite.pass: "worker shut down when job completed";
                        $worker-down.keep;
                    }
                }
            }
        }
    }

    $wm.do-async: {
        $steps++;
        $worker-id ⚛= $*AW-WORKER.id;
        $*AW-WORKER.stop: :soft;
        pass "the job is still running";
        $steps++;
    }

    await Promise.anyof(Promise.in(10), $worker-down);

    is $worker-down.status, Kept, "worker shut down on request";
    is $steps, 2, "job hasn't been stopped";

    $wm.shutdown;
    await $wm.completed;
}

subtest "Single worker", -> \suite {
    plan 1;
    my $num-workers = 20;
    my $w = Async::Workers.new(:max-workers(1));
    my atomicint $counter = 0;
    for ^$num-workers {
        $w.do-async: {
            ++⚛$counter;
        }
    }
    $w.shutdown;
    await $w.completed;
    is $counter, $num-workers, 'single "concurrent" worker is ok';
}

#subtest "Self-restarting workers", -> \suite {
#    my $try-expected = 5;
#    my $try-jobs = 10;
#    plan ($try-expected * $try-jobs), :parallel;
#
#    for 1..$try-jobs -> $max-jobs {
#        for 1..$try-expected -> $expected {
#            subtest "Expect $expected restarts", -> \suite {
#                plan 1;
#                my $jobs = $max-jobs * $expected;
#                my $wm = Async::Workers.new(:max-workers( 1 ), :$max-jobs);
#
#                my atomicint $worker-completions = 0;
#                my atomicint $completed = 0;
#
#                $wm.on_msg: -> $msg {
#                    ++⚛$worker-completions if $msg ~~ Async::Workers::Msg::Worker::Complete;
#                }
#
#                for ^$jobs {
#                    $wm.do-async: { ++⚛$completed; };
#                }
#
#                await $wm;
#
#                is $worker-completions, $expected, "workers were restarting as needed";
#            }
#        }
#    }
#}

done-testing;
