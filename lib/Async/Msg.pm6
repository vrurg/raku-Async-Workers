use v6.d;

role Async::Msg {
}

enum WorkerStatus is export <WEnter WComplete WNone>;

class Async::Msg::Workers does Async::Msg is export {
    has WorkerStatus:D $.status is required;
}

enum QueueStatus is export <QInc QDec QFull QLow QEmpty>;
class Async::Msg::Queue does Async::Msg is export {
    has QueueStatus:D $.status is required;
}

# Copyright (c) 2019, Vadim Belman <vrurg@cpan.org>
# vim: ft=perl6
