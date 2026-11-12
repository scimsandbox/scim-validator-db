-- scripts/verify-schema.sql
-- Comprehensive schema and constraint verification for scim-validator-db against PostgreSQL 17.

\set ON_ERROR_STOP on

BEGIN;

-- 1. Verify existence of all expected tables, indexes, and constraints
DO $$
DECLARE
    tbl TEXT;
    idx TEXT;
BEGIN
    FOREACH tbl IN ARRAY ARRAY[
        'validator_mgmt_users',
        'validation_run',
        'validation_test_result',
        'validation_http_exchange',
        'validation_run_publication'
    ]
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = 'public' AND table_name = tbl
        ) THEN
            RAISE EXCEPTION 'Expected table public.% does not exist', tbl;
        END IF;
    END LOOP;

    FOREACH idx IN ARRAY ARRAY[
        'idx_validation_run_created_by_email',
        'idx_validation_run_executed_at',
        'idx_validation_test_result_run_id_started_at',
        'idx_validation_http_exchange_test_result_sequence',
        'idx_validation_http_exchange_run_id',
        'idx_validation_run_publication_email',
        'idx_validation_run_publication_slug_version'
    ]
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_indexes
            WHERE schemaname = 'public' AND indexname = idx
        ) THEN
            RAISE EXCEPTION 'Expected index public.% is missing', idx;
        END IF;
    END LOOP;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE table_schema = 'public'
          AND table_name = 'validation_run'
          AND constraint_name = 'uk_validation_run_id_created_by_email'
          AND constraint_type = 'UNIQUE'
    ) THEN
        RAISE EXCEPTION 'Unique constraint uk_validation_run_id_created_by_email is missing on validation_run';
    END IF;
END $$;

-- 2. Positive Inserts across all 5 tables
INSERT INTO validator_mgmt_users (email, last_login_at)
VALUES
    ('alice@example.com', NOW()),
    ('bob@example.com', NOW());

INSERT INTO validation_run (
    id, name, target_url, executed_at, status, created_by_email, total_tests, passed_tests, failed_tests
)
VALUES
    ('11111111-1111-1111-1111-111111111111', 'CI Run 1', 'https://scim.example.com/v2', NOW() - INTERVAL '10 minutes', 'PASSED', 'alice@example.com', 42, 42, 0),
    ('22222222-2222-2222-2222-222222222222', 'CI Run 2', 'https://scim.example.com/v2', NOW() - INTERVAL '5 minutes', 'PASSED', 'alice@example.com', 42, 41, 1),
    ('33333333-3333-3333-3333-333333333333', 'CI Run 3 (Unpublished)', 'https://scim.example.com/v2', NOW(), 'PASSED', 'alice@example.com', 42, 40, 2);

INSERT INTO validation_test_result (
    id, run_id, test_identifier, class_name, test_name, display_name, status, error_message, stack_trace, started_at, finished_at
)
VALUES
    (
        'a0000000-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        'UsersEndpointTest#createUser',
        'com.example.UsersEndpointTest',
        'createUser',
        'Create User (POST /Users)',
        'PASSED',
        NULL,
        NULL,
        NOW() - INTERVAL '9 minutes',
        NOW() - INTERVAL '8 minutes'
    ),
    (
        'a0000000-0000-0000-0000-000000000002',
        '11111111-1111-1111-1111-111111111111',
        'GroupsEndpointTest#createGroup',
        'com.example.GroupsEndpointTest',
        'createGroup',
        'Create Group (POST /Groups)',
        'PASSED',
        NULL,
        NULL,
        NOW() - INTERVAL '8 minutes',
        NOW() - INTERVAL '7 minutes'
    );

INSERT INTO validation_http_exchange (
    id, run_id, test_result_id, sequence_number, method, url, request_headers, request_body, response_status, response_headers, response_body, created_at
)
VALUES
    (
        'b0000000-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        'a0000000-0000-0000-0000-000000000001',
        1,
        'POST',
        'https://scim.example.com/v2/Users',
        'Content-Type: application/scim+json',
        '{"userName":"alice"}',
        201,
        'Content-Type: application/scim+json',
        '{"id":"u-1","userName":"alice"}',
        NOW() - INTERVAL '9 minutes'
    ),
    (
        'b0000000-0000-0000-0000-000000000002',
        '11111111-1111-1111-1111-111111111111',
        'a0000000-0000-0000-0000-000000000002',
        1,
        'POST',
        'https://scim.example.com/v2/Groups',
        'Content-Type: application/scim+json',
        '{"displayName":"eng"}',
        201,
        'Content-Type: application/scim+json',
        '{"id":"g-1","displayName":"eng"}',
        NOW() - INTERVAL '8 minutes'
    );

-- Insert first publication omitting show_submitter to verify DEFAULT FALSE
INSERT INTO validation_run_publication (
    run_id,
    created_by_email,
    product_name,
    product_slug,
    product_version,
    vendor_name,
    project_url,
    license_type,
    core_score,
    supported_capabilities,
    total_capabilities,
    report_url,
    badge_url,
    pr_url,
    published_at
)
VALUES (
    '11111111-1111-1111-1111-111111111111',
    'alice@example.com',
    'Acme SCIM Server',
    'acme-scim',
    '1.0.0',
    'Acme Corp',
    'https://github.com/acme/scim-server',
    'Apache-2.0',
    100,
    8,
    10,
    'https://scimsandbox.org/reports/11111111',
    'https://scimsandbox.org/badges/11111111.svg',
    'https://github.com/scimsandbox/leaderboard/pull/1',
    NOW() - INTERVAL '4 minutes'
);

DO $$
DECLARE
    v_show_submitter BOOLEAN;
BEGIN
    SELECT show_submitter INTO v_show_submitter
    FROM validation_run_publication
    WHERE run_id = '11111111-1111-1111-1111-111111111111';

    IF v_show_submitter IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'Expected show_submitter default to be FALSE, got %', v_show_submitter;
    END IF;
END $$;

-- Insert second publication with the same (product_slug, product_version) to verify re-runs are permitted
INSERT INTO validation_run_publication (
    run_id,
    created_by_email,
    product_name,
    product_slug,
    product_version,
    vendor_name,
    project_url,
    license_type,
    show_submitter,
    core_score,
    supported_capabilities,
    total_capabilities,
    report_url,
    badge_url,
    pr_url,
    published_at
)
VALUES (
    '22222222-2222-2222-2222-222222222222',
    'alice@example.com',
    'Acme SCIM Server',
    'acme-scim',
    '1.0.0',
    'Acme Corp',
    'https://github.com/acme/scim-server',
    'Apache-2.0',
    TRUE,
    0,
    0,
    10,
    'https://scimsandbox.org/reports/22222222',
    'https://scimsandbox.org/badges/22222222.svg',
    'https://github.com/scimsandbox/leaderboard/pull/2',
    NOW() - INTERVAL '2 minutes'
);

-- 3. Negative Constraint Tests
-- 3a-3e. chk_validation_run_publication_core_score and chk_validation_run_publication_capabilities
DO $$
DECLARE
    v_case RECORD;
BEGIN
    FOR v_case IN
        SELECT *
        FROM (
            VALUES
                ('core_score = -1', -1, 5, 10),
                ('core_score = 101', 101, 5, 10),
                ('total_capabilities = 0', 80, 0, 0),
                ('supported_capabilities = -1', 80, -1, 10),
                ('supported_capabilities > total_capabilities', 80, 11, 10)
        ) AS t(label, score, supported, total)
    LOOP
        BEGIN
            INSERT INTO validation_run_publication (
                run_id, created_by_email, product_name, product_slug, product_version,
                license_type, core_score, supported_capabilities, total_capabilities,
                report_url, badge_url, published_at
            )
            VALUES (
                '33333333-3333-3333-3333-333333333333', 'alice@example.com', 'Acme SCIM', 'acme-scim', '1.0.0',
                'Apache-2.0', v_case.score, v_case.supported, v_case.total,
                'https://scimsandbox.org/reports/3', 'https://scimsandbox.org/badges/3.svg', NOW()
            );
            RAISE EXCEPTION 'Expected check_violation for %', v_case.label;
        EXCEPTION WHEN check_violation THEN
            NULL;
        END;
    END LOOP;
END $$;

-- 3f. fk_validation_run_publication_run rejects mismatched created_by_email
DO $$
BEGIN
    INSERT INTO validation_run_publication (
        run_id, created_by_email, product_name, product_slug, product_version,
        license_type, core_score, supported_capabilities, total_capabilities,
        report_url, badge_url, published_at
    )
    VALUES (
        '33333333-3333-3333-3333-333333333333', 'bob@example.com', 'Acme SCIM', 'acme-scim', '1.0.0',
        'Apache-2.0', 95, 8, 10,
        'https://scimsandbox.org/reports/3', 'https://scimsandbox.org/badges/3.svg', NOW()
    );
    RAISE EXCEPTION 'Expected foreign_key_violation for mismatched created_by_email';
EXCEPTION WHEN foreign_key_violation THEN
    NULL;
END $$;

-- 3g. ON DELETE RESTRICT on fk_validation_run_publication_run blocks deleting a published validation_run
DO $$
BEGIN
    DELETE FROM validation_run WHERE id = '11111111-1111-1111-1111-111111111111';
    RAISE EXCEPTION 'Expected foreign_key_violation or restrict_violation when deleting published validation_run';
EXCEPTION WHEN foreign_key_violation OR restrict_violation THEN
    NULL;
END $$;

-- 4. Explicit publication deletion + ON DELETE CASCADE verification + cleanup
DELETE FROM validation_run_publication
WHERE run_id IN (
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222'
);

DELETE FROM validation_run
WHERE id IN (
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333'
);

DO $$
DECLARE
    test_result_cnt INTEGER;
    http_exchange_cnt INTEGER;
BEGIN
    SELECT COUNT(*) INTO test_result_cnt
    FROM validation_test_result
    WHERE run_id = '11111111-1111-1111-1111-111111111111';

    IF test_result_cnt <> 0 THEN
        RAISE EXCEPTION 'ON DELETE CASCADE failed on validation_test_result; % rows remain', test_result_cnt;
    END IF;

    SELECT COUNT(*) INTO http_exchange_cnt
    FROM validation_http_exchange
    WHERE run_id = '11111111-1111-1111-1111-111111111111';

    IF http_exchange_cnt <> 0 THEN
        RAISE EXCEPTION 'ON DELETE CASCADE failed on validation_http_exchange; % rows remain', http_exchange_cnt;
    END IF;
END $$;

DELETE FROM validator_mgmt_users
WHERE email IN ('alice@example.com', 'bob@example.com');

COMMIT;
