use Test::Async;
use Async::Workers;
use Async::Workers::Msg;

plan 2;

subtest "Job dies", -> \suite {
    plan 2;

    my class X::Nevermind is Exception {
        method message { "just testing" }
    }

    my $wm = Async::Workers.new: :quiet;

    $wm.on_msg: -> $msg {
        given $msg {
            when Async::Workers::Msg::Job::Died {
                suite.isa-ok: $msg.exception, X::Nevermind, "the exception message received";
            }
        }
    }

    $wm.do-async: {
        suite.pass: "job invoked";
        X::Nevermind.new.throw
    }

    $wm.shutdown;
    await $wm.completed;
}

subtest "Quietness", -> \suite {
    plan 2;

    my $lib-path = $?FILE.IO.parent(2).add('lib').Str;
    diag "LIB PATH: ", $lib-path;

    my @tests =
        {
            mode => "quiet",
            new_arg => ':quiet',
            out => '',
            err => '',
        },
        {
            mode => "verbose",
            new_arg => '',
            out => '',
            :err(/
            '===SORRY!=== JOB #0' \n
            ^^ .* 'testing job failure'
            /),
        };

    for @tests -> $test {
        my $code =
            qq:to/CODE/;
            use Async::Workers;
            my class X::Nevermind is Exception \{
                method message \{ "testing job failure" }
            }
            my \$wm = Async::Workers.new({$test<new_arg>});
            \$wm.do-async: \{
                X::Nevermind.new.throw
            }
            \$wm.shutdown;
            await \$wm.completed;
            CODE
        is-run $code, "job fails in " ~ $test<mode> ~ " mode",
               :compiler-args["-I$lib-path"],
               :out($test<out>),
               :err($test<err>),
               :exitcode(0);
    }
}

done-testing;
