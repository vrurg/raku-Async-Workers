use v6.d;
unit package Async::Workers;

class Msg is export {
    method gist {
        self.^name
    }
}

class Msg::Shutdown is Msg { }
class Msg::Complete is Msg { }
class Msg::Exception is Msg {
    has Exception:D $.exception is required;
}

class Msg::Queue        is Msg {
    has Int:D $.size is required;

    method gist {
        callsame() ~ " size=$!size"
    }
}
class Msg::Queue::Inc   is Msg::Queue { }
class Msg::Queue::Dec   is Msg::Queue { }
class Msg::Queue::Full  is Msg::Queue { }
class Msg::Queue::Low   is Msg::Queue { }
class Msg::Queue::Empty is Msg::Queue { }

class Msg::Job is Msg {
    has $.job is required;
}
class Msg::Job::Enter    is Msg::Job { }
class Msg::Job::Complete is Msg::Job { }
class Msg::Job::Died     is Msg::Job {
    has Exception:D $.exception is required;
}

class Msg::Worker is Msg {
    has $.worker is required;
}
class Msg::Worker::Started  is Msg::Worker { }
class Msg::Worker::Complete is Msg::Worker { }
class Msg::Worker::Died     is Msg::Worker {
    has Exception:D $.exception is required;
}
