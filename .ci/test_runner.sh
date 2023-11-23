#!/bin/bash

# This shell script runs test files that have been scheduled to run.  It can be controlled either from
# PostgreSQL tables or from a fallback file containing TSV records with tests to run.  Due to the dual
# mode support, the script makes use of a number of global variables.  Don't extend it too much, please.

set -e

missing=0
for var in PGUSER PGPASSWORD PGDATABASE PGHOST WORKFLOW_ID RUN_ATTEMPT RUNNER_NUMBER
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
FALLBACK_FILE=test-chunk.$RUNNER_NUMBER

if [ -f $FALLBACK_FILE ]
then
    set +e
    IFS=$'\n' read -d '' -r -a TESTS_TO_RUN < $FALLBACK_FILE
    set -e
    echo "Running ${#TESTS_TO_RUN[@]} tests from fallback file $FALLBACK_FILE"
    FALLBACK_INDEX=0
else
    FALLBACK_FILE=""
fi

get_next_test_to_run () {
    if [ -z "$FALLBACK_FILE" ]
    then
        local busted_test_run=$($PSQL -c "select create_busted_test_run($WORKFLOW_ID, $RUNNER_NUMBER, $RUN_ATTEMPT)")
        if [ -z "$busted_test_run" ]
        then
            return 1
        fi
        # Parse the $busted_test_run (which is a JSON object) into the
        # shell variables $busted_test_run_id, $test_file, $exclude_tags
        # and $environment.
        eval $(echo "$busted_test_run" | jq -r 'to_entries | .[] | "\(.key)=\"\(.value)\""')
    else
        if [ ${#TESTS_TO_RUN[@]} = $FALLBACK_INDEX ]
        then
            return 1
        fi
        IFS=$'\t' read -r workflow_id test_file suite exclude_tags environment <<< "${TESTS_TO_RUN[$FALLBACK_INDEX]}"
        FALLBACK_INDEX=$(( FALLBACK_INDEX + 1 ))
    fi
}

save_test_result () {
    if [ -z "$FALLBACK_FILE" ]
    then
        (
            echo "\\set output \`cat $output_file\`"
            echo "select finish_busted_test_run($busted_test_run_id, '$STATUS', :'output')"
        ) | $PSQL > /dev/null
    fi
}

FAILURES=0
FAILED_TESTS=()
COUNT=0
# Process tests off the queue
while get_next_test_to_run
do
    # Run the test
    COUNT=$(( COUNT + 1 ))
    echo "### Running #$COUNT $busted_test_run"
    output_file=/tmp/test-out.$$.txt
    env $environment bin/busted -o gtest --exclude-tags=$exclude_tags $test_file 2>&1 | tee $output_file
    if [ ${PIPESTATUS[0]} = 0 ]
    then
        STATUS=passed
    else
        STATUS=failed
        FAILURES=$(( FAILURES + 1 ))
        FAILED_TESTS+=("$test_file")
    fi

    save_test_result
done

if [ $FAILURES != 0 ]
then
    echo "$FAILURES test files failed:"
    echo
    printf "   %s\n" "${FAILED_TESTS[@]}"
    exit 1
fi

exit 0
