#!/bin/bash

# This shell script runs test files that have been scheduled to run.

set -e

missing=0
for var in PGUSER PGPASSWORD PGDATABASE PGHOST WORKFLOW_ID RUN_ATTEMPT
do
    if [ -z $(eval echo \$$var) ]
    then
        echo $var environment variable not set
        missing=1
    fi
done

if [ $missing != 0 ]
then
    exit 1
fi

PSQL="psql -tA -v ON_ERROR_STOP=1"

if ! $PSQL -c 'select 1' > /dev/null
then
  echo "Could not connect to PostgreSQL, falling back to file based"
fi
failures=0
count=0
# Process tests off the queue
while true
do
    # Get the next test to run
    busted_test_run=$($PSQL -c "select create_busted_test_run($WORKFLOW_ID, $RUNNER_NUMBER, $RUN_ATTEMPT)")
    if [ -z "$busted_test_run" ]
    then
        break
    fi
    # Parse the $busted_test_run (which is a JSON object) into the
    # shell variables $busted_test_run_id, $test_file, $exclude_tags
    # and $environment.
    eval $(echo "$busted_test_run" | jq -r 'to_entries | .[] | "\(.key)=\"\(.value)\""')

    # Run the test
    count=$(expr $count + 1)
    echo "Running #$count $busted_test_run"
    output_file=/tmp/test-out.$$.txt
    if env $environment bin/busted -o gtest --exclude-tags=$exclude_tags $test_file >& $output_file
    then
        status=passed
    else
        status=failed
        failures=$(expr $failures + 1)
    fi

    # Update the test run with the result
    (
        echo "\\set output \`cat $output_file\`"
        echo "select finish_busted_test_run($busted_test_run_id, '$status', :'output')"
    ) | $PSQL > /dev/null
done

if [ $failures != 0 ]
then
    echo "$failures test files failed"
    exit 1
fi

exit 0
