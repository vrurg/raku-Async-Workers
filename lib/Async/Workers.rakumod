use v6.d;
unit class Async::Workers:ver<0.2.2>:auth<zef:vrurg>:api<0.2.0>;
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

method messages(--> Supply:D) {
    $!messages.Supply
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

our sub META6 {
	use META6;
    name           => 'Async::Workers',
    description    => 'Asynchronous threaded workers',
    version        => Async::Workers.^ver,
	api			   => Async::Workers.^api,
	auth		   => Async::Workers.^auth,
    perl-version   => Version.new('6.d'),
    rake-version   => Version.new('6.d'),
    depends        => [<AttrX::Mooish>],
    test-depends   => <Test Test::Async Test::META Test::When>,
    tags           => <threads async>,
    authors        => ['Vadim Belman'],
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
}

# Copyright (c) 2019, Vadim Belman <vrurg@cpan.org>
# vim: ft=perl6
