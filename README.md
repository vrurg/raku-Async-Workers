NAME
====

`Async::Workers` - Asynchronous threaded workers

SYNOPSIS
========

    use Async::Workers;

    my $wm = Async::Workers.new( :max-workers(5) );

    for 1..10 -> $n {
        $wm.do-async: {
            sleep 1.rand;
            say "Worker #$n";
        }
    }

    await $wm;

DESCRIPTION
===========

This module provides an easy way to execute a number of jobs in parallel while allowing to keep the resources consumed by your code under control.

Both OO and procedural interfaces are provided.

Reliability
-----------

This module has been tested by running 20k repetitions of it's test suite using 56 parallel processes. This doesn't prove there're no bugs, but what can be told for certain is that within the tested scenarios the robustness is high enough.

Terminology
-----------

  * *job* is what gets executed. Depending on context, a *job* could be an instance of `Async::Workers::Job` class, or a user provided code object.

  * *worker* is an instance of `Async::Workers::Worker` class. It is controlling a dedicated thread in which the job code is ran.

  * *worker manager* or just *manager* is an instance of `Async::Workers` class which controls the execution flow and manages workers.

How it works.
-------------

The goal is achieved by combining a *queue of jobs* and a number of pre-spawned threads controlled by *workers*. A job is picked from the queue by a currently unoccupied worker and the code object associated with it is invoked. Since the number of workers is limited it is easier to predict and plan CPU usage.

Yet, it is still possible to over-use memory and cause heavy swapping or even overflows in cases when there is too many jobs are produced and an average one takes longer to complete than it is needed to generate a new one. To provide some control over this situation one can define *hi* and *lo* thresholds on the queue size. When the queue contains as many jobs, as defined by the *hi* threshold, `do-async` method blocks upon receiving a new job request and unblocks only when the queue shortens down to its *lo* threshold.

The worker manager doesn't start workers until the first job is sent to the queue. It is also possible to shutdown all workers if they're no longer needed.

Some internal events are reported with messages from `Async::Workers::Msg`. See the `on_msg` method below.

ATTRIBUTES
==========

`max-workers`
-------------

Maximum number of workers. Defaults to `$*KERNEL.cpu-cores`.

`max-jobs`
----------

Set the maximum number of jobs a worker should process before stopping and letting the manager to spawn a new one. The functionality is not activated if the attribute is left undefined.

`lo-threshold`, `hi-threshold`
------------------------------

Low and high thresholds of the queue size.

`queued`
--------

Current queue size. If the queue has been blocked due to reaching `hi-threshold` then jobs awaiting for unblock are not counted toward this value.

`running`
---------

The number of currently occupied workers.

`completed`
-----------

A `Promise` which is kept when manager completes all jobs after transitioning into *shutdown* state. When this happens the job queue is closed and all workers are requested to stop. Submission of a new job with `do-async` at this point will re-vivify the queue and return the manager into working state.

In case of an internal failure the promise will be broken with an exception.

`empty`
-------

A `Promise` which is kept each time the queue gets emptied. Note that the initially empty queue is not reflected with this attribute. Only when the queue contained at least one element and then went down to zero length this promise is kept. In other words, it happens when `Async::Workers::Msg::Queue::Empty` is emitted.

Immediately after being kept the attribute gets replaced with a fresh `Promise`. So that the following example will finish only if the queue has been emptied twice:

    await $wm.empty;
    await $wm.empty;

`quiet`
-------

If set to *True* then no exceptions thrown by jobs are reported. In this case it is recommended to monitor messages for `Async::Workers::Msg::Job::Died`.

METHODS
=======

`do-async( &code, |params --> Async::Workers::Job )`
----------------------------------------------------

Takes a `&code` object and wraps it into a job object. `params` are passed to `&code` when it gets executed.

This method blocks if `hi-threshold` is defined and the queue size has reached the limit.

If no error happens then the method returns an `Async::Workers::Job` instance. Otherwise it may throw either `X::Manager::Down` if the manager is in `shutdown` or `completed` status; or it may throw `X::Manager::NoQueue` if somehow the job queue has not been initialized properly.

`shutdown`
----------

Switches the manager into *shutdown* state and closes the job queue. Since the queue might still contain some incomplete jobs it is likely to take some time until the `completed` promise gets kept. Normally it'd be helpful to `await` for the manager:

    my $wm = Async::Workers.new(...);
    ...
    $wm.shutdown;
    await $wm;

In this case the execution blocks until the job queue is emptied. Note that at this point `completed` might still not been fulfilled because workers are being shutting down in the meanwhile.

`workers`
---------

Returns the number of started workers.

`workers( UInt $num )`
----------------------

Sets the maximum number of workers (`max-workers` attribute). Can be used at any time without shutting down the manager:

    $wm = Async::Worker.new: :max-workers(20);
    $wm.do-async: &job1 for ^$repetitions;
    $wm.workers($wm.workers - 5);
    $wm.do-async: &job2 for ^$repetitions;

If user increases the number of workers then as many additional ones are started as necessary.

On the contrary, if the number of workers is reduced then as many of them are requested to stop as needed to meet user's demand. **Note** that this is done by injecting special jobs. It means that for a really long queue it may take quite a time before the extra workers receive the stop command. This behaviour may change in the future.

`set-threshold( UInt :$lo, Num :$hi )`
--------------------------------------

Dynamically sets high and low queue thresholds. The high might be set to `Inf` to define unlimited queue size. Note that this would translate into undefined value of `hi-threshold` attribute.

`on_msg( &callback )`
---------------------

Submits a `Async::Workers::Msg` message object to user code passed in `&callback`. Internally this method does tapping on a message [`Supply`](https://docs.raku.org/type/Supply) and returns a resulting [`Tap`](https://docs.raku.org/type/Tap) object.

The following messages can currently be emitted by the manager (names are shortened to not include `Async::Workers::Msg::` prefix):

  * `Shutdown` - when the manager is switched into shutdown state

  * `Complete` - when manager completed all jobs and shut down all workers

  * `Exception` - when an internal failure is intercepted; the related exception object is stored in attribute `exception`

  * `Worker` - not emitted, a base class for other `Worker` messages. Defines attribute `worker` which contains the worker object

  * `Worker::Started` - when a new worker thread has started

  * `Worker::Complete` - when a worker finishes

  * `Worker::Died` - when a worker throws. `exception` attribute will then contain the exception thrown. This message normally should not be seen as it signals about an internal error.

  * `Queue` – not emitted, a base class for other `Queue` messages. Defines attribute `size` which contains queue size at the moment when message was emitted.

  * `Queue::Inc` - queue size inceased; i.e. a new job submitted. Note that if the queue has reached the *hi* threshold then a job passed to `do-async` doesn't make it into the queue and thus no message is emitted until the queue is unblocked.

  * `Queue::Dec` – a job has finished and the queue size is reduced

  * `Queue::Full` - *hi* threshold is reached

  * `Queue::Low` - queue size reduced down to *lo* threshold

  * `Queue::Empty` – the queue was emtied

  * `Job` – not emitted, a parent class of job-related messages. Defines `job` attribute which holds a `Async::Workers::Job` object.

  * `Job::Enter` - emitted right before a worker is about to invoke a job

  * `Job::Complete` – emitted right after a job finishes

  * `Job::Died` – when a job throws. `exception` attribute contains the exception object.

`messages`
----------

This method produces a [`Supply`](https://docs.raku.org/type/Supply) which emits messages.

HELPER SUBS
===========

`stop-worker($rc?, :$soft = False)`
-----------------------------------

Bypasses to the current worker `stop` method.

If called from within a job code it would cause the worker controlling the job to stop. If this would reduce the number of workers to less than `max-workers` then the manager will spawn as many new ones as needed:

    $wm.do-async: {
        if $something-went-wrong {
            stop-worker
        }
    }

Note that the job would be stopped too, unless `:soft` parameter is used. In this case both the job and its worker will be allowed to complete. The worker will stop after the job is done.

PROCEDURAL
==========

Procedural interface hides a singleton object behind it. The following subs are exported by the module:

`async-workers( |params --> Async::Workers:D )`
-----------------------------------------------

Returns the singleton object. Creates it if necessary. If supplied with parameters they're passed to the constructor. If singleton is already created then the parameters are ignored.

`do-async`
----------

Bypasses to the corresponding method on the singleton.

    do-async {
        say "My task";
    }

`shutdown-workers`
------------------

Bypasses to `shutdown` on the singleton.

AUTHOR
======

Vadim Belman <vrurg@cpan.org>

LICENSE
=======

Artistic License 2.0

See the *LICENSE* file in this distribution.

