use v6.d;
unit module Async::Workers::X;

class Base is Exception { }

class Manager::Down is Base {
    method message {
        "Manager is shut down"
    }
}

class Manager::NoQueue is Base {
    method message {
        "Queue is not ready. This is likely to be an internal error"
    }
}

class NoWorker is Base {
    has Str:D $.helper is required;
    method message {
        $!helper ~ " called outside of a running job"
    }
}

class WrongWorker is Base {
    has Str:D $.op is required;
    has $.worker is required;
    has $.expected is required;
    method message {
        "Attempted $!op in a wrong worker scope; expected #{$!expected.id} but done in #{$!worker.id}"
    }
}

class OutsideOfWorker is Base {
    has Str:D $.op is required;
    method message {
        "Attempted $!op outside of a worker scope"
    }
}

class Threshold {
    has $.lo is required;
    has $.hi is required;
    method message {
        "Low queue threshold ($!lo) is greater then high ($!hi)"
    }
}