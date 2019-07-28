use v6.d;

=begin pod
=head1 NAME

C<Async::Workers> - Asynchronous threaded workers

=head1 SYNOPSIS

    use Async::Workers;

    my $wm = Async::Workers.new( :max-workers(5) );

    for 1..10 -> $n {
        $wm.do-async: {
            sleep 1.rand;
            say "Worker #$n";
        }
    }

    await $wm;

=head1 DESCRIPTION

This module provides an easy way to execute a number of tasks in parallel while allowing to limit the number of
simultaneous workers. I.e. it won't consume more more resources than a user would consider reasonable.

Both OO and procedural interfaces are provided.

=head2 Terminology

An instance of C<Async::Workers> class is called I<worker manager> or just I<manager>.

=head2 How it works.

The goal is achieved by combining a I<queue of tasks> and a number of pre-spawned threads for I<workers>. A I<task> is
picked from the queue by a currently unoccupied worker and a code object associated with it gets executed. The number of
workers can be defined by a user.

By default the size of the queue is not limited. But if there expected to be a big numebr of tasks with an average task
completion time higher than the time needed to create a new one, the growing queue may consume too much of available
resources. This would eliminate any possible advantage of parallelizing.

To prevent such scenario the user can set low and high thresholds on the queue size. So, when the queue reaches the high
threshold it would stop accepting new tasks. From user perspective it means that C<do-async> would block until the queue
size is reduced to the low threshold.

The worker manager doesn't start workers until first task is been sent to the queue. It is also possible to shutdown all
workers if they're no longer needed.

In addition to workers the manager starts a monitoring thread which overlooks the workers. As a matter of fact, it's the
monitor starts all workers. It is also shutdowns after they all are stopped.

=head1 ATTRIBUTES

=head2 C<max-workers>

Maximum number of workers. Defaults to 10.

=head2 C<client>

Client object is the object which wants to implement a worker replacing the default one. In this case the object must
have a C<worker> method using the following template:

    method worker ( Channel $queue ) {
        react {
            whenever $queue -> $task {
                ...
                $task.run;
                ...
            }
        }
    }

B<Note> that it is mandatory to use C<.run> method of the C<$task> object or certain functionality would be broken.

=head2 C<lo-threshold>, C<hi-threshold>

Low and high thresholds of the queue size.

=head2 C<queued>

Current queue size.

=head2 C<running>

The number of currently occupied workers.

=head1 METHODS

=head2 C<do-async( &code, |params )>

Takes a C<&code> object and turns it into a task. C<params> are passed to C<&code> when it gets executed.

This method blocks if C<hi-threshold> is defined and the queue size has reached the limit.

=head2 C<shutdown>

Await until all workers complete and stop them. Blocks until the queue is emtied and all workers stopped.

=head2 C<workers>

Returns the number of started workers.

=head2 C<workers( UInt $num )>

Sets the number of workers. Can be used at runtime without shutting down the manager.

If user increases the number of workers then the monitor would start as many additional ones as necessary.

On the contrary, if the number of workers is reduced then monitor request as many of them to stop as needed to meet
user's demand. B<Note> that current implementation does it by installing special tasks into the queue. It means that for
a really long queue it may take quite significant time before the surplus workers receive the command to stop. This
behaviour might and very likely will change in the future.

=head2 C<set-threshold( UInt :$lo, Num :$hi )>

Dynamically set high and low queue thresholds. The high might be set to C<Inf> to define unlimited queue size. Note that
this would translate into undefined value of C<hi-threshold> attribute.

=head1 HELPER SUBS

=head2 C<stop-worker>

If called from within a task code it would cause the worker executing that task to stop. If this would reduce the number
of workers to less than C<max-workers> then the monitor would start a new one:

    $wm.do-async: {
        if $something-went-wrong {
            stop-worker
        }
    }

=head1 PROCEDURAL

Procedural interface hides a singleton object behind it. The following subs are exported by the module:

=head2 C«async-workers( |params --> Async::Workers:D )»

Returns the singleton object. Creates it if necessary. If supplied with parameters they're passed to the constructor. If
singleton is already created then the parameters are ignored.

=head2 C<do-async>

Bypasses to the corresponding method on the singleton.

    do-async: {
        say "My task";
    }

=head2 C<shutdown-workers>

Bypasses to C<shutdown> on the singelton.

=end pod

unit class Async::Workers:ver<0.0.7>;
also does Awaitable;
use Async::Msg;

my $singleton;

my class CX::AW::StopWorker does X::Control { }

class AWCode { ... }
trusts AWCode;

class AWCode {
    has &.code is required;
    has Capture:D $.params = \();
    has Async::Workers:D $.manager is required;
    has $.processed is rw = False;
    my atomicint $id = 0;
    has $.id = $id⚛++;

    method run {
        $.manager!Async::Workers::call-worker-code(self);
    }
}

has UInt $.max-workers = 10;
has UInt $.max-queue = $!max-workers * 2;
has $.client; # Client object – the one which will provide .worker method
has UInt $.lo-threshold;
# has UInt $.lo-threshold is mooish(:lazy);
has UInt $.hi-threshold;
has atomicint $.queued = 0;
has atomicint $.running = 0;

has %!workers;
has Bool $!shutdown;
# has Channel $!queue is mooish(:lazy, :clearer);
has Channel $!evt-queue;
has Promise $!monitor;

has Lock::Async $!ql .= new; # Queue lock
has Lock::Async $!wl .= new; # Workers lock

has Lock $!qbl .= new ;
has $!queue-block = $!qbl.condition;
has atomicint $!queue-blocked = 0;

has Supplier $!messages .= new;

has $.debug = ? %*ENV<ASYNC_WORKERS_DEBUG>;

sub stop-worker is export { CX::AW::StopWorker.new.throw }

sub async-workers (|c) is export {
    $singleton = Async::Workers.new(|c) unless $singleton;
    $singleton
}

submethod TWEAK(|) {
    $!lo-threshold //= $!max-workers;
    die "High queue threshold ($!hi-threshold) can't be lower than the low ($!lo-threshold)"
        if $!lo-threshold > ($!hi-threshold // Inf);
}

# method build-lo-threshold { $!max-workers }

sub do-async (|c) is export {
    async-workers.do-async(|c)
}

sub shutdown-workers is export {
    $singleton.shutdown if $singleton;
}

# method !build-queue { # For Attrx::Mooish
#     $!shutdown = False;
#     self!start-monitor;
#     Channel.new;
# }

method !queue {
    $!ql.with-lock-hidden-from-recursion-check: {
        unless $!evt-queue {
            $!shutdown = False;
            self!start-monitor;
            $!evt-queue = Channel.new;
        }
    }
    $!evt-queue
}

method !clear-queue {
    $!evt-queue = Nil;
}

method !check-workers {
    return if $!shutdown;
    while %!workers.elems < $.max-workers {
        my $worker = start {
            with $.client {
                .worker(self!queue);
            } else {
                self!worker
            }
            $!wl.protect: {
                %!workers{ $worker.WHICH }:delete;
            }
            CATCH {
                default {
                    .rethrow;
                }
            }
        }
        $!wl.protect: {
            %!workers{ $worker.WHICH } = $worker;
        }
    }
}

method !start-monitor {
    return if $!monitor && $!monitor.status ~~ Planned;
    $!monitor = start { self!run-monitor };
}

method !run-monitor {
    $!messages.Supply.tap: -> $msg {
        given $msg {
            when Async::Msg::Workers {
                given .status {
                    when WEnter {
                        $!running⚛++;
                    }
                    when WComplete {
                        if --⚛$!running == 0 {
                            $!messages.emit: Async::Msg::Workers.new( status => WNone );
                        }
                    }
                }
            }
        }
    };
    my @v;
    until $!shutdown {
        self!check-workers;
        @v = eager %!workers.values; # Workaround for MoarVM/MoarVM#1101
        await Promise.anyof( @v );
        note "%%%%%%%%%%%%%%% Re-check workers, active: ", %!workers.elems if $.debug;
    }
    await @v if @v;
}

has atomicint $!active-workers = 0;
method !call-worker-code (AWCode:D $evt) {
    $!messages.emit: Async::Msg::Workers.new( status => WEnter );
    $!active-workers⚛++;
    $evt.code.(|$evt.params);
    LEAVE {
        $!active-workers⚛--;
        note "<<<<<<<<<<<< ACTIVE WORKERS LEFT: ", $!active-workers if $.debug;
        $!messages.emit: Async::Msg::Workers.new( status => WComplete );
    }
}

method !worker {
    note "Worker, entering react" if $.debug;
    react {
        whenever self!queue -> $evt {
            note ">>>>>>>>> WORKER[{$*THREAD.id.fmt: "%3d"}] {self.WHICH} ENTER, queued: ", $!queued, "        " if $.debug;
            $evt.run;
            LEAVE {
                note "<<<<<<<<< WORKER[{$*THREAD.id.fmt: "%3d"}] {self.WHICH} DONE, queued: ", $!queued, " workers ", %!workers.elems, "         " if $.debug;
                self!dec-queue;
            }
            CONTROL {
                when CX::AW::StopWorker {
                    $!active-workers⚛--;
                    note "<<<<<<<<<<<< A WORKER[{$*THREAD.id}] IS REQUESTED TO STOP: ", $!active-workers if $.debug;
                    done;
                    return;
                }
                default {
                    .rethrow
                }
            }
        }
    }
}

method shutdown {
    return unless $!wl.protect: { %!workers.elems };
    $!shutdown = True;
    self!queue.close;
    await $!monitor;
    self!clear-queue;
    $!queued ⚛= 0;
}

my class AsyncWorkersAwaitHandle does Awaitable::Handle {
    has &!add-subscriber;
    method not-ready (&add-subscriber) {
        use nqp;
        nqp::create(self)!not-ready(&add-subscriber);
    }
    method !not-ready (&add-subscriber) {
        $!already = False;
        &!add-subscriber := &add-subscriber;
        self
    }
    method subscribe-awaiter (&subscriber --> Nil) {
        &!add-subscriber(&subscriber);
    }
}

method get-await-handle ( --> Awaitable::Handle:D ) {
    if $!queued {
        AsyncWorkersAwaitHandle.not-ready: -> &on-ready {
            start react {
                whenever $!messages -> $msg {
                    if $msg ~~ Async::Msg::Workers and $msg.status ~~ WNone {
                        on-ready(True, Nil);
                        done;
                    }
                }
            }
        }
    }
    else {
        AsyncWorkersAwaitHandle.already-success(Nil);
    }
}

method do-async (&code, |params) {
    my $closed = self!queue.closed;
    unless $closed.status ~~ Kept {
        $!ql.protect: {
            $!queued⚛++;
            self!queue.send(
                AWCode.new( :&code, :params(params), :manager(self) )
            );
            if $!hi-threshold and $!queued >= $!hi-threshold {
                $!messages.emit(
                    Async::Msg::Queue.new(status => QFull)
                );
                note "//// Blocking until queue decreased" if $.debug;
                $!qbl.protect: {
                    $!queue-blocked ⚛= 1;
                    $!queue-block.wait;
                    note "//// Queue unblocked" if $.debug;
                }
                # note "??????? [{$*THREAD.id}] QUEUE BLOCKED: ", $!queue-blocked, " total ", $!queued if $.debug;
            }
        }
    }
}

method set-threshold(UInt :$lo where * > 0, Num :$hi where * > 0) {
    die "Low queue threshold ($lo) is greater then high ($hi)"
        if ( defined $lo & $hi ) and ( $lo > $hi );
    $!lo-threshold = $lo with $lo;
    $!hi-threshold = ( $_ ~~ Inf ?? Nil !! $_ ) with $hi;
}

multi method workers (UInt:D $max where * > 0) {
    return if $max == $!max-workers;
    my $old-max = $!max-workers;
    $!max-workers = $max;

    if $max < $old-max {
        for 1..($old-max - $max) {
            # This would stop the necessary number of workers
            self.do-async: { stop-worker }
        }
    }
    else {
        self!check-workers;
    }
}

multi method workers ( --> UInt ) {
    $!wl.protect: { %!workers.elems }
}

method on_msg ( &code ) {
    $!messages.Supply.tap: &code;
}

method !dec-queue {
    $!queued⚛--;
    note "---------- deced queue: ", $!queued if $.debug;
    if $!queue-blocked and $!queued <= $!lo-threshold {
        $!messages.emit: Async::Msg::Queue.new(status => QLow);
        $!queue-block.signal;
        $!queue-blocked ⚛= 0;
    }
    if $!queued == 0 {
        $!messages.emit: Async::Msg::Queue.new(status => QEmpty);
    }
}

=begin pod

=head1 AUTHOR

Vadim Belman <vrurg@cpan.org>

=head1 LICENSE

Artistic License 2.0

See the LICENSE file in this distribution.

=end pod

# Copyright (c) 2019, Vadim Belman <vrurg@cpan.org>
# vim: ft=perl6
