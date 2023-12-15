use v6.d;

unit class Async::Workers::Job;
use Async::Workers::CX;
use Async::Workers::Msg;

my atomicint $next-id = 0;

has &.code is required;
has Promise:D $.invoked .= new;
has $!invoked-vow = $!invoked.vow;
has Promise:D $.completed .= new;
has $!completion-vow = $!completed.vow;
has $.id = $next-id⚛++;
has Str $.name;
has Instant $.started;
has Instant $.ended;
has $.manager;

method invoke {
    CONTROL {
        when CX::AW::StopWorker {
            # Bypass control we know about
            $!completion-vow.keep: .rc;
            .rethrow
        }
        when CX::AW { .rethrow }
        default {
            # Consider any unknown CX::* harmful and abort upon receiving.
            $!completion-vow.break: $_;
            return $!completed
        }
    }
    $!started = now;
    $!invoked-vow.keep(True);
    my $rc = try { &!code.() };
    $!ended = now;
    with $! {
        $!completion-vow.break: $!;
    }
    else {
        $!completion-vow.keep: $rc;
    }
    $!completed
}

method is-completed { (⚛$!completed).staus != Planned }
method is-started { (⚛$!started).defined }

multi method Str(::?CLASS:D:) { "JOB#" ~ $!id ~ ($!name andthen " '$_'" orelse "") }
multi method gist(::?CLASS:D:) { self.Str }