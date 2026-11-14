-- scripts/seed-v2-dirty-data.sql
-- Populates a V2 database with representative legacy/dirty data across all tables
-- so CI verifies that V3 normalizes live records safely without deleting publications.

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO validator_mgmt_users (email, last_login_at)
VALUES ('upgrade-user@example.com', NOW() - INTERVAL '1 day');

-- Runs 1..8 covering mixed-case URLs, userinfo, published malformed targets, unpublished invalid targets, and bad test counts
INSERT INTO validation_run (
    id, name, target_url, executed_at, status, created_by_email, total_tests, passed_tests, failed_tests
)
VALUES
    -- Run 1: Unpublished, mixed-case HTTPS scheme with leading/trailing whitespace (must survive, trimmed)
    ('d0000000-0000-0000-0000-000000000001', 'Dirty Run 1 (Mixed Case)', '  HTTPS://scim.example.com/v2  ', NOW() - INTERVAL '80 minutes', 'PASSED', 'upgrade-user@example.com', 10, 10, 0),
    -- Run 2: Unpublished, embedded userinfo + negative test counts (must survive, userinfo stripped & counts normalized)
    ('d0000000-0000-0000-0000-000000000002', 'Dirty Run 2 (Userinfo + Counts)', 'https://user:secret@scim.example.com/v2', NOW() - INTERVAL '70 minutes', 'PASSED', 'upgrade-user@example.com', -5, 8, -2),
    -- Run 3: Published, uppercase HTTPS + userinfo + inconsistent test counts (must survive, stripped & normalized)
    ('d0000000-0000-0000-0000-000000000003', 'Dirty Run 3 (Published Userinfo)', '  HTTPS://admin:pw@scim.example.com/v2  ', NOW() - INTERVAL '60 minutes', 'FAILED', 'upgrade-user@example.com', 5, 4, 3),
    -- Run 4: Published, schemeless target_url with port and internal whitespace (must survive, normalized in place)
    ('d0000000-0000-0000-0000-000000000004', 'Dirty Run 4 (Published Schemeless)', '  scim.legacy.example.com:8443 / scim/v2  ', NOW() - INTERVAL '50 minutes', 'PASSED', 'upgrade-user@example.com', 20, 20, 0),
    -- Run 5: Published, non-HTTP scheme target_url (must survive, normalized to safe .invalid fallback)
    ('d0000000-0000-0000-0000-000000000005', 'Dirty Run 5 (Published FTP)', 'ftp://legacy.example.com/scim', NOW() - INTERVAL '40 minutes', 'PASSED', 'upgrade-user@example.com', 20, 19, 1),
    -- Run 6: Published, userinfo with empty host after strip (must survive, normalized to safe .invalid fallback)
    ('d0000000-0000-0000-0000-000000000006', 'Dirty Run 6 (Published Empty Host)', 'https://user:pw@', NOW() - INTERVAL '30 minutes', 'PASSED', 'upgrade-user@example.com', 20, 20, 0),
    -- Run 7: Unpublished, unsalvageable ftp:// scheme (must be deleted along with child rows)
    ('d0000000-0000-0000-0000-000000000007', 'Dirty Run 7 (Unpublished FTP)', 'ftp://files.example.com/scim', NOW() - INTERVAL '20 minutes', 'FAILED', 'upgrade-user@example.com', 10, 0, 10),
    -- Run 8: Unpublished, empty host after userinfo strip (must be deleted)
    ('d0000000-0000-0000-0000-000000000008', 'Dirty Run 8 (Unpublished Empty Host)', 'https://user:pw@', NOW() - INTERVAL '10 minutes', 'FAILED', 'upgrade-user@example.com', 10, 0, 10);

-- Test results: oversized > 2 MiB ASCII & multi-byte UTF-8, normal control row, Run 2 row for cross-run test, and Run 7 child row
INSERT INTO validation_test_result (
    id, run_id, test_identifier, class_name, test_name, display_name, status, error_message, stack_trace, started_at, finished_at
)
VALUES
    (
        'e0000000-0000-0000-0000-000000000001',
        'd0000000-0000-0000-0000-000000000001',
        'OversizedTest#asciiAndEuro',
        'com.example.OversizedTest',
        'asciiAndEuro',
        'Oversized > 2 MiB error_message and 3-byte UTF-8 stack_trace',
        'FAILED',
        repeat('a', 2200000),
        repeat('€', 800000),
        NOW() - INTERVAL '79 minutes',
        NOW() - INTERVAL '78 minutes'
    ),
    (
        'e0000000-0000-0000-0000-000000000002',
        'd0000000-0000-0000-0000-000000000001',
        'ControlTest#underLimit',
        'com.example.ControlTest',
        'underLimit',
        'Control < 2 MiB row',
        'FAILED',
        'Short error',
        repeat('z', 100000),
        NOW() - INTERVAL '77 minutes',
        NOW() - INTERVAL '76 minutes'
    ),
    (
        'e0000000-0000-0000-0000-000000000003',
        'd0000000-0000-0000-0000-000000000002',
        'Run2Test#ok',
        'com.example.Run2Test',
        'ok',
        'Run 2 Test',
        'PASSED',
        NULL,
        NULL,
        NOW() - INTERVAL '69 minutes',
        NOW() - INTERVAL '68 minutes'
    ),
    (
        'e0000000-0000-0000-0000-000000000007',
        'd0000000-0000-0000-0000-000000000007',
        'Run7Test#deletedCascade',
        'com.example.Run7Test',
        'deletedCascade',
        'Cascade deleted with Run 7',
        'FAILED',
        'FTP error',
        NULL,
        NOW() - INTERVAL '19 minutes',
        NOW() - INTERVAL '18 minutes'
    );

-- HTTP exchanges: oversized > 2 MiB (4-byte emoji + misaligned UTF-8 boundaries + negative sequence_number),
-- control row, cross-run mismatched row, and Run 7 child row
INSERT INTO validation_http_exchange (
    id, run_id, test_result_id, sequence_number, method, url, request_headers, request_body, response_status, response_headers, response_body, created_at
)
VALUES
    (
        'f0000000-0000-0000-0000-000000000001',
        'd0000000-0000-0000-0000-000000000001',
        'e0000000-0000-0000-0000-000000000001',
        -7,
        'POST',
        'https://scim.example.com/v2/Users',
        repeat('🚀', 600000),
        'x' || repeat('€', 800000),
        500,
        'ab' || repeat('🚀', 600000),
        repeat('b', 2500000),
        NOW() - INTERVAL '78 minutes'
    ),
    (
        'f0000000-0000-0000-0000-000000000002',
        'd0000000-0000-0000-0000-000000000001',
        'e0000000-0000-0000-0000-000000000002',
        1,
        'GET',
        'https://scim.example.com/v2/Users',
        'Accept: application/scim+json',
        NULL,
        200,
        'Content-Type: application/scim+json',
        repeat('c', 50000),
        NOW() - INTERVAL '76 minutes'
    ),
    -- Cross-run exchange: run_id is Run 1, but test_result_id belongs to Run 2 (must be deleted)
    (
        'f0000000-0000-0000-0000-000000000099',
        'd0000000-0000-0000-0000-000000000001',
        'e0000000-0000-0000-0000-000000000003',
        1,
        'GET',
        'https://scim.example.com/v2/Groups',
        NULL,
        NULL,
        200,
        NULL,
        NULL,
        NOW() - INTERVAL '68 minutes'
    ),
    -- Child exchange of unpublished invalid Run 7 (must cascade-delete with Run 7)
    (
        'f0000000-0000-0000-0000-000000000007',
        'd0000000-0000-0000-0000-000000000007',
        'e0000000-0000-0000-0000-000000000007',
        1,
        'GET',
        'ftp://files.example.com/scim/Users',
        NULL,
        NULL,
        500,
        NULL,
        NULL,
        NOW() - INTERVAL '18 minutes'
    );

-- Live publications on Runs 3, 4, 5, 6 (ALL 4 MUST SURVIVE V3 WITHOUT DELETION)
INSERT INTO validation_run_publication (
    run_id, created_by_email, product_name, product_slug, product_version, vendor_name,
    project_url, license_type, show_submitter, core_score, supported_capabilities, total_capabilities,
    report_url, badge_url, pr_url, published_at
)
VALUES
    -- Pub 3: Spaces/uppercase/punctuation slug, userinfo in HTTPS project_url & pr_url, invalid report_url & badge_url
    (
        'd0000000-0000-0000-0000-000000000003',
        'upgrade-user@example.com',
        'My Cool SCIM',
        '  My Cool SCIM!  ',
        '1.0.0',
        'Acme',
        '  HTTPS://user:secret@github.com/acme/scim  ',
        'Apache-2.0',
        TRUE,
        92,
        8,
        10,
        'javascript:alert(1)',
        'ftp://bad.example.com/badge.svg',
        '  HTTPS://token@github.com/scimsandbox/scim-website/pull/42  ',
        NOW() - INTERVAL '59 minutes'
    ),
    -- Pub 4: UUID product_slug, schemeless project_url, mixed-case report_url & badge_url, PENDING_RESERVATION pr_url
    (
        'd0000000-0000-0000-0000-000000000004',
        'upgrade-user@example.com',
        'UUID Slug Product',
        '33333333-3333-3333-3333-333333333333',
        '2.1.0',
        'Acme',
        'not-a-valid-url',
        'MIT',
        FALSE,
        98,
        9,
        10,
        'HTTPS://scimsandbox.org/compliance/?run=4',
        'Http://scimsandbox.org/compliance/badges/4.svg',
        'PENDING_RESERVATION',
        NOW() - INTERVAL '49 minutes'
    ),
    -- Pub 5: Path-traversal punctuation slug falling back to product_name, blank/empty-host URLs, invalid pr_url
    (
        'd0000000-0000-0000-0000-000000000005',
        'upgrade-user@example.com',
        'Acme Enterprise SCIM!',
        '../..//',
        '3.0.0',
        NULL,
        '   ',
        'Apache-2.0',
        FALSE,
        95,
        8,
        10,
        'https://user:pw@',
        '   ',
        'javascript:void(0)',
        NOW() - INTERVAL '39 minutes'
    ),
    -- Pub 6: Unsalvageable slug AND non-alphanumeric product_name falling back to 'legacy-product', mixed-case valid URLs
    (
        'd0000000-0000-0000-0000-000000000006',
        'upgrade-user@example.com',
        '!!!',
        '---',
        '1.2.3',
        NULL,
        'HTTPS://github.com/acme/repo',
        'GPL-3.0',
        TRUE,
        100,
        10,
        10,
        'https://scimsandbox.org/r/6',
        'https://scimsandbox.org/b/6.svg',
        'HTTPS://github.com/scimsandbox/scim-website/pull/6',
        NOW() - INTERVAL '29 minutes'
    );

COMMIT;
