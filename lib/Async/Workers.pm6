use v6.d;
unit class Async::Workers:ver<0.0.1>;
use AttrX::Mooish;
use Async::Msg;

my $singleton;

my class CX::AW::StopWorker does X::Control { }

class AWCode { ... }
trusts AWCode;

class AWCode {
    has &.code is required;
    has Capture:D $.params = \();
    has Async::Workers:D $.manager is required;

    method run {
        $.manager!Async::Workers::dec-queue;
        $.manager.call-worker-code(self);
    }
}

has UInt $.max-workers = 10;
has %!workers;
has Bool $!shutdown;
has Channel $!queue is mooish(:lazy, :clearer);
has Promise $!monitor;
has $.client; # Client object – the one which will provide .worker method
has Lock $.wl .= new;

has UInt $.lo-threshold is mooish(:lazy);
has UInt $.hi-threshold;
has atomicint $.queued = 0;
has atomicint $.running = 0;
has Promise $!overflow;
has $!overflow-vow;
has Lock $!overflow-lock .= new;

has Supplier $!messages .= new;

sub stop-worker is export { CX::AW::StopWorker.new.throw }

sub async-workers (|c) is export {
    $singleton = Async::Workers.new(|c) unless $singleton;
    $singleton
}

submethod TWEAK(|) {
    die "High queue threshold ($!hi-threshold) can'b lower than the low ($!lo-threshold)"
        if $!lo-threshold > ($!hi-threshold // Inf);
}

sub do-async (|c) is export {
    async-workers.do-async(|c)
}

sub shutdown-workers is export {
    $singleton.shutdown if $singleton;
}

multi await ( Async::Workers:D $wm ) is export {
    $wm.await
}

method !build-queue {
    $!shutdown = False;
    self!start-monitor;
    Channel.new;
}

method build-lo-threshold { $!max-workers }

method !start-monitor {
    return if $!monitor && $!monitor.status ~~ Planned;
    $!monitor = start { self!run-monitor };
}

method !check-workers {
    return if $!shutdown;
    while %!workers.elems < $.max-workers {
        my $worker = start {
            with $.client {
                .worker($!queue);
            } else {
                self.worker
            }
            $.wl.protect: {
                %!workers{ $worker.WHICH }:delete;
            }
        }
        $.wl.protect: {
            %!workers{ $worker.WHICH } = $worker;
        }
    }
}

method !run-monitor {
    until $!shutdown {
        self!check-workers;
        my $rc = await Promise.anyof( |%!workers.values );
    }
    await %!workers.values if %!workers.elems > 0;
}

method call-worker-code (AWCode:D $evt) {
    $!running⚛++;
    $evt.code.(|$evt.params);
    LEAVE {
        $!running⚛--;
        if $!running == 0 {
            $!messages.emit( Async::Msg::Workers.new( status => WNone ) )
        }
    }
    CONTROL {
        when CX::AW::StopWorker {
            done();
        }
        default {
            .rethrow
        }
    }
}

method worker {
    react {
        whenever $!queue -> $evt {
            $evt.run;
        }
    }
}

method shutdown {
    return unless $.wl.protect: { %!workers.elems };
    $!shutdown = True;
    $!queue.close;
    await $!monitor;
    self!clear-queue;
    $!queued ⚛= 0;
}

method await ( --> Nil ) {
    return unless $!queued;
    react {
        whenever $!messages -> $msg {
            if $msg ~~ Async::Msg::Workers and $msg.status ~~ WNone {
                done;
            }
        }
    }
}

method do-async (&code, |params) {
    my $closed = $!queue.closed;
    unless $closed.status ~~ Kept {
        self!inc-queue;
        $!queue.send(
            AWCode.new( :&code, :params(params), :manager(self) )
        );
    }
}

method set-threshold(UInt :$lo where * > 0, Num :$hi where * > 0) {
    die "Low queue threshold ($lo) is greater then high ($hi)"
        if ( defined $lo & $hi ) and ( $lo > $hi );
    $!lo-threshold = $lo with $lo;
    $!hi-threshold = ( $_ ~~ Inf ?? Nil !! $_ ) with $hi;
}

method set-max-workers (UInt $max where * > 0) {
    return if $max == $!max-workers;
    $.wl.protect: {
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
}

method workers ( --> UInt ) {
    $.wl.protect: { %!workers.elems }
}

method !inc-queue {
    if $!hi-threshold.defined and $!queued >= $!hi-threshold {
        $!overflow-lock.protect: {
            unless $!overflow.defined and $!overflow.status ~~ Planned {
                $!overflow = Promise.new;
                $!overflow-vow = $!overflow.vow;
            }
        }
        await $!overflow;
        $!overflow-lock.protect: {
            $!overflow = Nil;
            $!overflow-vow = Nil;
        }
    }
    $!queued⚛++;
}

method !dec-queue {
    $!queued⚛--;
    $!overflow-lock.protect: {
        if $!queued <= $!lo-threshold && $!overflow-vow {
            $!overflow-vow.keep(True);
        }
    }
}
