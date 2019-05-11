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

This module provides an easy way to execute a number of tasks in parallel while allowing to limit the number of simultaneous workers. I.e. it won't consume more more resources than a user would consider reasonable.

Both OO and procedural interfaces are provided.

Terminology
-----------

An instance of `Async::Workers` class is called *worker manager* or just *manager*.

How it works.
-------------

The goal is achieved by combining a *queue of tasks* and a number of pre-spawned threads for *workers*. A *task* is picked from the queue by a currently unoccupied worker and associated with it code object gets executed. The number of workers can be defined by a user.

By default the size of the queue is not limited. But if there expected to be a big numebr of tasks with an average completion time higher than the time needed to create a new task, the growing queue may consume too much of available resources. This would eliminate any possible advantage of parallilizing.

To prevent such scenario the user can set low and high thresholds on the queue size. So, when the queue reaches the high threshold it would stop accepting new tasks. From user perspective it means that `do-async` would block until the queue size would reduce to the low threshold.

The worker manager doesn't start workers until first task is been sent to the queue. It is also possible to shutdown all workers if they're no longer needed.

In addition to workers the manager starts a monitoring thread which overlooks the workers. The monitor starts all workers and it shutdowns after they all are stopped.

ATTRIBUTES
==========

`max-workers`
-------------

Maximum number of workers. Defaults to 10.

`client`
--------

Client object is the object which wants to implement a worker replacing the default one. In this case the object must have a `worker` method using the following template:

    method worker ( Channel $queue ) {
        react {
            whenever $queue -> $task {
                ...
                $task.run;
                ...
            }
        }
    }

**Note** that it is mandatory to use `.run` method of the `$task` object or certain functionality would be broken.

`lo-threshold`, `hi-threshold`
------------------------------

Low and high thresholds of the queue size.

`queued`
--------

Current queue size.

`running`
---------

The number of currently occupied workers.

METHODS
=======

`do-async( &code, |params )`
----------------------------

Takes a `&code` object and turns it into a task. `params` are passed to `&code` when it gets executed.

This method blocks if `hi-threshold` is defined and the queue size has reached the limit.

`await`
-------

Awaits for all workers to complete. See [SYNOPSIS](#SYNOPSIS).

`shutdown`
----------

Await until all workers complete and stop them. Blocks until the queue is emtied and all workers stopped.

`workers`
---------

Returns the number of started workers.

`workers( UInt $num )`
----------------------

Sets the number of workers. Can be used at runtime without shutting down the manager.

If user increases the number of workers then the monitor would start as many additional ones as necessary.

On the contrary, if the number of workers is reduced then monitor request as many of them to stop as needed to meet user's demand. **Note** that current implementation does it by installing special tasks into the queue. It means that for a really long queue it may take quite significant time before the surplus workers receive the command to stop. This behaviour might and very likely will change in the future.

`set-threshold( UInt :$lo, Num :$hi )`
--------------------------------------

Dynamically set high and low queue thresholds. The high might be set to `Inf` to define unlimited queue size. Note that this would translate into undefined value of `hi-threshold` attribute.

Set the number of

AUTHOR
======

Vadim Belman <vrurg@cpan.org>

LICENSE
=======

Artistic License 2.0

See the LICENSE file in this distribution.

