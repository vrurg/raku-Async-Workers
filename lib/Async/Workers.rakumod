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

This module provides an easy way to execute a number of jobs in parallel while allowing to keep the resources consumed
by your code under control.

Both OO and procedural interfaces are provided.

=head2 Reliability

This module has been tested by running 20k repetitions of it's test suite using 56 parallel processes. This doesn't
prove there're no bugs, but what can be told for certain is that within the tested scenarios the robustness is high
enough.

=head2 Terminology

=item I<job> is what gets executed. Depending on context, a I<job> could be an instance of C<Async::Workers::Job> class,
or a user provided code object.

=item I<worker> is an instance of C<Async::Workers::Worker> class. It is controlling a dedicated thread in which the job
code is ran.

=item I<worker manager> or just I<manager> is an instance of C<Async::Workers> class which controls the execution flow
and manages workers.

=head2 How it works.

The goal is achieved by combining a I<queue of jobs> and a number of pre-spawned threads controlled by I<workers>. A
job is picked from the queue by a currently unoccupied worker and the code object associated with it is invoked. Since
the number of workers is limited it is easier to predict and plan CPU usage.

Yet, it is still possible to over-use memory and cause heavy swapping or even overflows in cases when there is too many
jobs are produced and an average one takes longer to complete than it is needed to generate a new one. To provide some
control over this situation one can define I<hi> and I<lo> thresholds on the queue size. When the queue contains as many
jobs, as defined  by the I<hi> threshold, C<do-async> method blocks upon receiving a new job request and unblocks only
when the queue shortens down to its I<lo> threshold.

The worker manager doesn't start workers until the first job is sent to the queue. It is also possible to shutdown all
workers if they're no longer needed.

Some internal events are reported with messages from C<Async::Workers::Msg>. See the C<on_msg> method below.

=head1 ATTRIBUTES

=head2 C<max-workers>

Maximum number of workers. Defaults to C<$*KERNEL.cpu-cores>.

=head2 C<max-jobs>

Set the maximum number of jobs a worker should process before stopping and letting the manager to spawn a new one. The
functionality is not activated if the attribute is left undefined.

=head2 C<lo-threshold>, C<hi-threshold>

Low and high thresholds of the queue size.

=head2 C<queued>

Current queue size. If the queue has been blocked due to reaching C<hi-threshold> then jobs awaiting for unblock are not
counted toward this value.

=head2 C<running>

The number of currently occupied workers.

=head2 C<completed>

A C<Promise> which is kept when manager completes all jobs after transitioning into I<shutdown> state. When this happens
the job queue is closed and all workers are requested to stop. Submission of a new job with C<do-async> at this point will
re-vivify the queue and return the manager into working state.

In case of an internal failure the promise will be broken with an exception.

=head2 C<empty>

A C<Promise> which is kept each time the queue gets emptied. Note that the initially empty queue is not reflected with
this attribute. Only when the queue contained at least one element and then went down to zero length this promise is
kept. In other words, it happens when C<Async::Workers::Msg::Queue::Empty> is emitted.

Immediately after being kept the attribute gets replaced with a fresh C<Promise>. So that the following example will
finish only if the queue has been emptied twice:

    await $wm.empty;
    await $wm.empty;

=head2 C<quiet>

If set to I<True> then no exceptions thrown by jobs are reported. In this case it is recommended to monitor messages
for C<Async::Workers::Msg::Job::Died>.

=head1 METHODS

=head2 C<<do-async( &code, |params --> Async::Workers::Job )>>

Takes a C<&code> object and wraps it into a job object. C<params> are passed to C<&code> when it gets executed.

This method blocks if C<hi-threshold> is defined and the queue size has reached the limit.

If no error happens then the method returns an C<Async::Workers::Job> instance. Otherwise it may throw either
C<X::Manager::Down> if the manager is in C<shutdown> or C<completed> status; or it may throw C<X::Manager::NoQueue> if
somehow the job queue has not been initialized properly.

=head2 C<shutdown>

Switches the manager into I<shutdown> state and closes the job queue. Since the queue might still contain some
incomplete jobs it is likely to take some time until the C<completed> promise gets kept. Normally it'd be helpful
to C<await> for the manager:

    my $wm = Async::Workers.new(...);
    ...
    $wm.shutdown;
    await $wm;

In this case the execution blocks until the job queue is emptied. Note that at this point C<completed> might still not
been fulfilled because workers are being shutting down in the meanwhile.

=head2 C<workers>

Returns the number of started workers.

=head2 C<workers( UInt $num )>

Sets the maximum number of workers (C<max-workers> attribute). Can be used at any time without shutting down the
manager:

    $wm = Async::Worker.new: :max-workers(20);
    $wm.do-async: &job1 for ^$repetitions;
    $wm.workers($wm.workers - 5);
    $wm.do-async: &job2 for ^$repetitions;

If user increases the number of workers then as many additional ones are started as necessary.

On the contrary, if the number of workers is reduced then as many of them are requested to stop as needed to meet
user's demand. B<Note> that this is done by injecting special jobs. It means that for a really long queue it may take
quite a time before the extra workers receive the stop command. This behaviour may change in the future.

=head2 C<set-threshold( UInt :$lo, Num :$hi )>

Dynamically sets high and low queue thresholds. The high might be set to C<Inf> to define unlimited queue size. Note
that this would translate into undefined value of C<hi-threshold> attribute.

=head2 C<on_msg( &callback )>

Submits a C<Async::Workers::Msg> message object to user code passed in C<&callback>. Internally this method does tapping
on a message <Supply> and returns a resulting C<Tap> object (see documentation on C<Supply>).

The following messages can currently be emitted by the manager (names are shortened to not include
C<Async::Workers::Msg::> prefix):

=item C<Shutdown> - when the manager is switched into shutdown state

=item C<Complete> - when manager completed all jobs and shut down all workers

=item C<Exception> - when an internal failure is intercepted; the related exception object is stored in attribute
      C<exception>

=item C<Worker> - not emitted, a base class for other C<Worker> messages. Defines attribute C<worker> which contains
      the worker object

=item C<Worker::Started> - when a new worker thread has started

=item C<Worker::Complete> - when a worker finishes

=item C<Worker::Died> - when a worker throws. C<exception> attribute will then contain the exception thrown. This
      message normally should not be seen as it signals about an internal error.

=item C<Queue> – not emitted, a base class for other C<Queue> messages. Defines attribute C<size> which contains queue
      size at the moment when message was emitted.

=item C<Queue::Inc> - queue size inceased; i.e. a new job submitted. Note that if the queue has reached the I<hi>
      threshold then a job passed to C<do-async> doesn't make it into the queue and thus no message is emitted until
      the queue is unblocked.

=item C<Queue::Dec> – a job has finished and the queue size is reduced

=item C<Queue::Full> - I<hi> threshold is reached

=item C<Queue::Low> - queue size reduced down to I<lo> threshold

=item C<Queue::Empty> – the queue was emtied

=item C<Job> – not emitted, a parent class of job-related messages. Defines C<job> attribute which holds a
      C<Async::Workers::Job> object.

=item C<Job::Enter> - emitted right before a worker is about to invoke a job

=item C<Job::Complete> – emitted right after a job finishes

=item C<Job::Died> – when a job throws. C<exception> attribute contains the exception object.

=head1 HELPER SUBS

=head2 C<stop-worker($rc?, :$soft = False)>

Bypasses to the current worker C<stop> method.

If called from within a job code it would cause the worker controlling the job to stop. If this would reduce the number
of workers to less than C<max-workers> then the manager will spawn as many new ones as needed:

    $wm.do-async: {
        if $something-went-wrong {
            stop-worker
        }
    }

Note that the job would be stopped too, unless C<:soft> parameter is used. In this case both the job and its worker
will be allowed to complete. The worker will stop after the job is done.

=head1 PROCEDURAL

Procedural interface hides a singleton object behind it. The following subs are exported by the module:

=head2 C«async-workers( |params --> Async::Workers:D )»

Returns the singleton object. Creates it if necessary. If supplied with parameters they're passed to the constructor. If
singleton is already created then the parameters are ignored.

=head2 C<do-async>

Bypasses to the corresponding method on the singleton.

    do-async {
        say "My task";
    }

=head2 C<shutdown-workers>

Bypasses to C<shutdown> on the singleton.

=end pod

unit class Async::Workers:ver<0.2.1>;
also does Awaitable;

use Async::Workers::Msg;
use Async::Workers::Job;
use Async::Workers::Worker;
use Async::Workers::X;
use Async::Workers::CX;
use AttrX::Mooish;

my $singleton;

has Channel $!queue is mooish( :lazy, :clearer );
has Lock::Async $!ql .= new;
# Queue lock
has Promise:D $!queue-unblock .= kept;

has UInt $.max-workers = $*KERNEL.cpu-cores;
has UInt $.lo-threshold;
has UInt $.hi-threshold;
has atomicint $.queued = 0;
has atomicint $.running = 0;
has UInt $.max-jobs where { !.defined || $_ > 0 };

has Bool:D $.quiet = False;

has %!workers;
has Lock::Async $!wl .= new;
# Workers lock

has Promise $.completed;
has $!completion-vow;
has Promise $.empty .= new;
has $!empty-vow = $!empty.vow;
has Promise $!shutdown .= new;

has Supplier $!messages .= new;

has atomicint $!active-workers = 0;

has $.debug = ?%*ENV<ASYNC_WORKERS_DEBUG>;

sub stop-worker( $rc?, Bool:D :$soft = False ) is export {
    with $*AW-WORKER {
        .stop: $rc, :$soft
    }
    else {
        X::NoWorker.new(:helper<stop-worker>).throw
    }
}

sub async-workers( |c ) is export {
    $singleton //= Async::Workers.new(|c)
}

sub worker-manager( |c ) is export {
    $singleton //= Async::Workers.new(|c)
}

sub do-async( |c ) is export {
    worker-manager.do-async(|c)
}

sub shutdown-workers is export {
    .shutdown with $singleton;
}

my proto as-soon( | ) {*}
multi as-soon( Promise:D $promise, Pair:D $event ) {
    my $mgr = CALLER::LEXICAL::<self>;
    my $what = $event.key;
    my &code = $event.value;
    $promise.then: {
        CATCH {
            CATCH { note "===INTERNAL=== Died in as-soon CATCH:\n", .message, "\n", .backtrace.Str }
            $mgr.message: Async::Workers::Msg::Exception, exception => $_;
            $mgr.x-sorry($_, $what ~ " promise handler");
            $mgr.bail-out: $_;
            .rethrow
        }
        &code( $_ )
    }
}

multi as-soon( Promise:D $promise, &code ) {
    as-soon($promise, "A" => &code)
}

submethod TWEAK( | ) {
    $!lo-threshold //= $!max-workers;
    die "High queue threshold ($!hi-threshold) can't be lower than the low ($!lo-threshold)"
    if $!lo-threshold > ( $!hi-threshold // Inf );
}

method !build-queue {
    # For Attrx::Mooish
    $!completion-vow = ( $!completed = Promise.new ).vow;
    as-soon $!completed, "Manager completion" => { self.message: Async::Workers::Msg::Complete };
    $!shutdown = Promise.new;
    Channel.new
}

method do-async ( &code, |args --> Async::Workers::Job ) {
    with $!queue {
        if $!completed.status == Planned && $!shutdown.status == Planned {
            self!start-workers;

            $!ql.lock;
            LEAVE $!ql.unlock;

            my $size = ++⚛$!queued;
            self.message: Async::Workers::Msg::Queue::Inc, :$size;

            with $.hi-threshold -> $ht {
                if $size == $ht {
                    self.message: Msg::Queue::Full, :$size;
                }
                if $size > $ht {
                    my $qu = $!queue-unblock;
                    cas($!queue-unblock, $qu, Promise.new);
                    await $!queue-unblock;
                }
            }
            self!queue-job: &code, args
        }
        else {
            self!throw: X::Manager::Down
        }
    }
    else {
        self!throw: X::Manager::NoQueue
    }
}

method !queue-job( &code, Capture:D $args --> Async::Workers::Job ) {
    my $job = Async::Workers::Job.new(:&code, :$args, :manager( self ));
    $!queue.send: $job;
    $job
}

method !job-invoke( Async::Workers::Job:D $job ) {
    ++⚛$!running;
    self.message: Async::Workers::Msg::Job::Enter, :$job;
}

method !job-complete( Async::Workers::Job:D $job ) {
    --⚛$!running;
    if $job.completed.status == Broken {
        my $exception = $job.completed.cause;
        self.message: Async::Workers::Msg::Job::Died, :$job, :$exception;
        self.x-sorry: $exception, "JOB #" ~ $job.id unless $!quiet;
    }
    self.message: Async::Workers::Msg::Job::Complete, :$job;
    self!dec-queue;
}

proto method message( | ) {*}
multi method message( Msg:U \msg, *%profile ) {
    self.message: msg.new(|%profile)
}
multi method message( Msg:D $msg ) {
    $!messages.emit: $msg
}

method !throw( Exception \ex, |c ) {
    ex.new(|c).throw
}

method !start-workers {
    return unless $!shutdown.status == Planned;
    while $!active-workers < $!max-workers {
        my $need-one = False;
        cas $!active-workers, {
            ( $need-one = $_ < $!max-workers ) ?? $_ + 1 !! $_
        }

        if $need-one {
            # Worker callback, simply redispatches to a private method.
            my sub wcb( Str:D $method, |c ) {
                self!"$method"(|c)
            }

            my $worker = Async::Workers::Worker.new: :manager( self ), :$!queue, :callback( &wcb );

            # Whatever is the reason for a worker to stop – try starting a new one again. Even if it's a part of
            # reducing $!max-workers number procedure, then the start-workers method would just skip and do nothing.
            as-soon $worker.run, "Worker #" ~ $worker.id ~ " completion" => {
                if .status == Broken {
                    self.x-sorry(.cause, "Worker #" ~ $worker.id);
                    self!deregister-worker($worker)
                }
            };
        }
    }
}

method !register-worker( Async::Workers::Worker:D $worker ) {
    self.message: Async::Workers::Msg::Worker::Started, :$worker;
    $!wl.protect: { %!workers{$worker.id} = $worker };
}

method !deregister-worker( Async::Workers::Worker:D $worker ) {
    my $active = --⚛$!active-workers;
    self.message: Async::Workers::Msg::Worker::Complete, :$worker;
    $!wl.protect: { %!workers{$worker.id}:delete };
    if $!shutdown.status != Planned {
        if $active == 0 && $!completed.status == Planned {
            $!completion-vow.keep(True);
            self!clear-queue;
        }
    }
    else {
        self!start-workers
    }
}

method shutdown {
    $!shutdown.keep;
    $!queue.close;
    self.message: Async::Workers::Msg::Shutdown;
}

method bail-out( Exception:D $exception ) {
    return if $!queue.closed;
    $!shutdown.keep;
    $!queue.close;
    $!completion-vow.break($exception);
}

my class AsyncWorkersAwaitHandle does Awaitable::Handle {
    has &!add-subscriber;
    method not-ready ( &add-subscriber ) {
        use nqp;
        nqp::create(self)!not-ready(&add-subscriber);
    }
    method !not-ready ( &add-subscriber ) {
        $!already = False;
        &!add-subscriber := &add-subscriber;
        self
    }
    method subscribe-awaiter ( &subscriber --> Nil ) {
        &!add-subscriber( &subscriber );
    }
}

method get-await-handle ( --> Awaitable::Handle:D ) {
    if $!queued || $!running {
        AsyncWorkersAwaitHandle.not-ready: -> &on-ready {
            my $tap = $!messages.Supply.tap: -> $msg {
                if $msg ~~ Async::Workers::Msg::Queue::Empty {
                    $tap.close;
                    on-ready(True, Nil);
                }
            }
            # Re-check queue status because we could've missed a message while preparing the tap.
            unless $!queued || $!running {
                $tap.close;
                on-ready(True, Nil);
            }
        }
    }
    else {
        AsyncWorkersAwaitHandle.already-success(Nil);
    }
}

multi method set-threshold( UInt $lo, Num $hi ) {
    self.set-threshold(:$lo, :$hi)
}
multi method set-threshold( UInt :$lo, Num :$hi ) {
    $!lo-threshold = $_ with $lo;
    $!hi-threshold = !.defined || $_ == Inf ?? Nil !! .Int with $hi;
    self.throw: Async::Workers::X::Threshold, lo => $!lo-threshold, hi => $!hi-threshold
    if defined($!lo-threshold & $!hi-threshold) && $!lo-threshold > $!hi-threshold;
}

multi method workers( UInt:D $max where * > 0 ) {
    my $old-max;
    loop {
        $old-max = $!max-workers;
        last if cas($!max-workers, $old-max, $max) == $old-max;
    }
    return if $max == $old-max;

    if $max < $old-max {
        for ^( $old-max - $max ) {
            # This would stop the necessary number of workers
            self.do-async: { stop-worker }
        }
    }
    else {
        self!start-workers;
    }
}

multi method workers ( --> UInt ) {
    $!active-workers
}

method on_msg ( &code ) {
    $!messages.Supply.tap: &code;
}

method x-sorry( Exception:D $exception, Str $what ) {
    my @sorry = ( '===SORRY!===' );
    @sorry.push: $_ with $what;
    #    @sorry.push: "thrown " ~ $exception.^name ~ ":";
    given $exception {
        note
            @sorry.join(" "), "\n",
            ( "[" ~ .^name ~ "] " ~ .message ).indent(2), "\n",
            .backtrace.Str.indent(2)
    }
}

method !dec-queue {
    my $size = --⚛$!queued;
    if $size == $!lo-threshold {
        self.message: Async::Workers::Msg::Queue::Low, :$size;
        $!queue-unblock.keep if $!queue-unblock.status == Planned;
    }
    if $size == 0 {
        self.message: Async::Workers::Msg::Queue::Empty, :$size;
        my $oempty = $!empty;
        if cas($!empty, $oempty, Promise.new) === $oempty {
            $!empty-vow.keep: True;
            $!empty-vow = $!empty.vow;
        }
    }
}

=begin pod

=head1 AUTHOR

Vadim Belman <vrurg@cpan.org>

=head1 LICENSE

Artistic License 2.0

See the I<LICENSE> file in this distribution.

=end pod

# Copyright (c) 2019, Vadim Belman <vrurg@cpan.org>
# vim: ft=perl6
