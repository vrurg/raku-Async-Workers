use v6.d;
unit class Async::Workers::Worker;
use Async::Workers::Job;
use Async::Workers::Msg;
use Async::Workers::CX;
use Async::Workers::X;

my atomicint $next-id = 0;
has Int:D $.id = $next-id⚛++;

has Promise $.completed;
has &!callback is required is built;

has $.manager is required;
has Channel $!queue;

has atomicint $!stop-loop = 0;

has $!max-jobs;

submethod TWEAK(Channel:D :$!queue, :&!callback) {
    $!max-jobs = $_ with $!manager.max-jobs;
}

method run {
    $!completed = start {
        self!queue-loop
    }
}

method stop($rc?, Bool:D :$soft = False) {
    if $soft {
        ++⚛$!stop-loop;
    }
    else {
        with $*AW-WORKER {
            Async::Workers::X::OutsideOfWorker.new(:worker(self), :expected($*AW-WORKER)).throw
                unless .id == $!id;
        }
        else {
            Async::Workers::X::OutsideOfWorker.new(:worker(self)).throw
        }
        Async::Workers::CX::AW::StopWorker.new(:$rc).throw
    }
}

method !queue-loop(--> Nil) {
    $!queue.closed.then: { ++⚛$!stop-loop };
    &!callback('register-worker', self);
    QLOOP: until $!stop-loop {
        my $job = try $!queue.receive;
        with $job {
            CONTROL {
                when CX::AW::StopWorker {
                    ++⚛$!stop-loop;
                    last QLOOP;
                }
                default { .rethrow }
            }
            with $!max-jobs {
                ++⚛$!stop-loop unless --$!max-jobs;
            }
            my $*AW-JOB = $job;
            my $*AW-JOB-ID = $job.id;
            my $*AW-WORKER = self;
            &!callback.('job-invoke', $job);
            LEAVE &!callback.('job-complete', $job);
            $job.invoke;
        }
        else {
            given $! {
                when X::Channel::ReceiveOnClosed {
                    ++⚛$!stop-loop;
                }
                default {
                    $!.rethrow
                }
            }
        }
    }
    &!callback('deregister-worker', self);
}
