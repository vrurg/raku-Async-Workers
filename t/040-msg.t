use Test::Async;
use Async::Workers;
use Async::Workers::Msg;

BEGIN {
    $*ERR.out-buffer = False;
    $*OUT.out-buffer = False;
}

plan 1;

subtest "Basic sequence", -> \suite {
    my $wm = Async::Workers.new;
    my $job-id;
    my $worker-id;
    my Promise:D $seq-over .= new;
    my Promise:D $worker-completed .= new;

    my @seq =
        {
            msg => Async::Workers::Msg::Worker::Started,
        },
        {
            msg => Async::Workers::Msg::Job::Enter,
        },
        {
            msg => Async::Workers::Msg::Job::Complete,
            check => -> $msg {
                suite.is: $msg.job.id, $job-id, "job id matches the one in message";
            },
        },
        {
            msg => Async::Workers::Msg::Shutdown,
        },
        ;
    my $seq-num = +@seq;
    my atomicint $stage = 0;

    plan @seq + 3;

    my $tap-l = Lock.new;
    $wm.on_msg: -> $msg {
        $tap-l.lock;
        LEAVE $tap-l.unlock;
        if $msg ~~ Async::Workers::Msg::Worker::Complete && $msg.worker.id == $worker-id {
            suite.pass: "our worker completed";
            $worker-completed.keep;
        }
        if $stage < $seq-num {
            my $test = @seq[$stage];
            if $msg.WHAT ~~ $test<msg> {
                if $test<check>:exists ?? $test<check>($msg) !! True {
                    suite.pass: $test<msg>.^name ~ " encountered";
                    if ++⚛$stage >= +@seq {
                        $seq-over.keep;
                    }
                }
            }
        }
    }

    $wm.do-async: {
        suite.pass: "job invoked";
        $job-id = $*AW-JOB.id;
        $worker-id = $*AW-WORKER.id;
    };

    await $wm;

    $wm.shutdown;
    await $wm.completed;
    await $seq-over;
    await $worker-completed;
}

done-testing;
