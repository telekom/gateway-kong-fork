CREATE TYPE test_run_status AS ENUM ('running', 'passed', 'failed');

CREATE TABLE busted_test_run_request
(
    id           SERIAL PRIMARY KEY,
    workflow_id  BIGINT    NOT NULL,
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    test_file    VARCHAR   NOT NULL,
    suite        VARCHAR   NOT NULL,
    exclude_tags VARCHAR   NOT NULL,
    environment  VARCHAR   NOT NULL
);

CREATE TABLE busted_test_run
(
    id                         SERIAL PRIMARY KEY,
    busted_test_run_request_id INT REFERENCES busted_test_run_request (id) ON DELETE CASCADE,
    runner_number              INTEGER NOT NULL,
    run_attempt                INTEGER NOT NULL,
    run_start_at               TIMESTAMP,
    run_end_at                 TIMESTAMP,
    status                     test_run_status,
    output                     TEXT
);

CREATE OR REPLACE FUNCTION create_busted_test_run(p_workflow_id BIGINT, p_runner_number INTEGER, p_run_attempt INTEGER)
    RETURNS JSONB
AS
$$
DECLARE
    run_id         INTEGER;
    run_request_id INTEGER;
BEGIN
    -- Select a request that meets the criteria and lock the row
    SELECT btrr.id
    INTO run_request_id
    FROM busted_test_run_request btrr
             LEFT JOIN busted_test_run btr
                       ON btrr.id = btr.busted_test_run_request_id
                           AND (btr.run_attempt = p_run_attempt OR btr.status = 'passed')
    WHERE btrr.workflow_id = p_workflow_id
      AND btr.id IS NULL
    LIMIT 1 FOR UPDATE OF btrr
        SKIP LOCKED;

    -- If no suitable row is found, return null
    IF run_request_id IS NULL THEN
        RETURN NULL;
    END IF;

    -- Insert a new busted_test_run row
    INSERT INTO busted_test_run (runner_number, busted_test_run_request_id, run_attempt, run_start_at, status)
    VALUES (p_runner_number, run_request_id, p_run_attempt, CURRENT_TIMESTAMP, 'running')
    RETURNING id INTO run_id;

    -- Return the requested information
    RETURN (SELECT JSONB_BUILD_OBJECT(
                           'busted_test_run_id', run_id,
                           'test_file', btrr.test_file,
                           'exclude_tags', btrr.exclude_tags,
                           'environment', btrr.environment
                       )
            FROM busted_test_run_request btrr
            WHERE btrr.id = run_request_id);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION finish_busted_test_run(
    p_busted_test_run_id INTEGER,
    p_status test_run_status,
    p_diagnostic_text TEXT
)
    RETURNS BOOLEAN AS
$$
BEGIN
    -- Update the row with the provided values
    UPDATE busted_test_run
    SET status     = p_status,
        run_end_at = NOW(),
        output     = p_diagnostic_text
    WHERE id = p_busted_test_run_id;

    -- Check if the row was updated
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Row with busted_test_run_id % not found', p_busted_test_run_id;
    END IF;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Create trigger function
CREATE OR REPLACE FUNCTION notify_busted_test_run()
    RETURNS TRIGGER AS
$$
DECLARE
    workflow_id_val BIGINT;
BEGIN
    -- Get the workflow_id from the referenced busted_test_run_request row
    SELECT workflow_id INTO workflow_id_val FROM busted_test_run_request WHERE id = NEW.busted_test_run_request_id;

    -- Notify the channel with the workflow_id and id in the payload
    PERFORM pg_notify('busted_test_run_request_' || workflow_id_val::TEXT, NEW.id::TEXT);

    -- Return the new row
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for INSERT on busted_test_run
CREATE TRIGGER busted_test_run_insert_trigger
    AFTER INSERT
    ON busted_test_run
    FOR EACH ROW
EXECUTE FUNCTION notify_busted_test_run();

-- Create trigger for UPDATE on busted_test_run
CREATE TRIGGER busted_test_run_update_trigger
    AFTER UPDATE
    ON busted_test_run
    FOR EACH ROW
EXECUTE FUNCTION notify_busted_test_run();

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE busted_test_run_request TO github_ci;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE busted_test_run TO github_ci;
GRANT USAGE, SELECT ON SEQUENCE busted_test_run_request_id_seq TO github_ci;
GRANT USAGE, SELECT ON SEQUENCE busted_test_run_id_seq TO github_ci;
