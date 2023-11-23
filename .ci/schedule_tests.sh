#!/usr/bin/env bash

# This shell script schedules the test files that need to run.

set -e

missing=0
for var in PGUSER PGPASSWORD PGDATABASE PGHOST WORKFLOW_ID
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

ALL_TESTS_FILE=all-tests.txt

(
    SUITE="Postgres"
    for test in $(find spec/01-unit \
                       spec/02-integration \
                       spec/03-plugins \
                       -name '*_spec.lua')
    do
        printf "$WORKFLOW_ID\t$test\t$SUITE\tflaky,ipv6,off\tKONG_TEST_DATABASE=postgres\n"
    done

    SUITE="dbless"
    for test in $(find spec/02-integration/02-cmd \
                       spec/02-integration/05-proxy \
                       spec/02-integration/04-admin_api/02-kong_routes_spec.lua \
                       spec/02-integration/04-admin_api/15-off_spec.lua \
                       spec/02-integration/08-status_api/01-core_routes_spec.lua \
                       spec/02-integration/08-status_api/03-readiness_endpoint_spec.lua \
                       spec/02-integration/11-dbless \
                       spec/02-integration/20-wasm \
                       -name '*_spec.lua')
    do
        printf "$WORKFLOW_ID\t$test\t$SUITE\tflaky,ipv6,postgres,db\t\n"
    done
) > $ALL_TESTS_FILE


if psql -q -c "delete from busted_test_run_request where workflow_id = $WORKFLOW_ID;"
then
  psql -1 -q -v ON_ERROR_STOP=1 -c '\copy busted_test_run_request (workflow_id, test_file, suite, exclude_tags, environment) from stdin' < $ALL_TESTS_FILE
else
  echo "Could not connect to PostgreSQL, falling back to file based scheduling"
  shuf $ALL_TESTS_FILE \
      | split -l $(( ($(wc -l < $ALL_TESTS_FILE) + $RUNNER_COUNT - 1) / $RUNNER_COUNT )) -d -a 1 - test-chunk.
fi
