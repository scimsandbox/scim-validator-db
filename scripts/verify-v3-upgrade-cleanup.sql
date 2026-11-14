-- scripts/verify-v3-upgrade-cleanup.sql
-- Verifies that upgrading a dirty V2 database to V3 preserved all published runs/publications,
-- normalized malformed slugs/URLs/counts in place, purged only unpublished invalid runs & cross-run exchanges,
-- and truncated oversized > 2 MiB ASCII/UTF-8 TEXT values to ~2 MiB with the '...[truncated]' marker.

\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    v_run RECORD;
    v_pub RECORD;
    v_tr RECORD;
    v_ex RECORD;
    v_pub_count INTEGER;
    v_run_count INTEGER;
BEGIN
    -- 1. Zero helper functions left in public schema
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
    ) THEN
        RAISE EXCEPTION 'Unexpected function(s) found in public schema after V3 upgrade';
    END IF;

    -- 2. Verify all 4 live publications survived (ZERO publications deleted)
    SELECT COUNT(*) INTO v_pub_count
    FROM validation_run_publication
    WHERE created_by_email = 'upgrade-user@example.com';

    IF v_pub_count <> 4 THEN
        RAISE EXCEPTION 'Expected all 4 validation_run_publication rows to survive V3 upgrade, found %', v_pub_count;
    END IF;

    -- 3. Verify Runs 1..6 survived and unpublished invalid Runs 7..8 were deleted
    SELECT COUNT(*) INTO v_run_count
    FROM validation_run
    WHERE created_by_email = 'upgrade-user@example.com';

    IF v_run_count <> 6 THEN
        RAISE EXCEPTION 'Expected 6 validation_run rows to survive V3 upgrade (Runs 1..6), found %', v_run_count;
    END IF;

    IF EXISTS (
        SELECT 1 FROM validation_run
        WHERE id IN (
            'd0000000-0000-0000-0000-000000000007',
            'd0000000-0000-0000-0000-000000000008'
        )
    ) THEN
        RAISE EXCEPTION 'Unpublished invalid Runs 7/8 should have been deleted during V3 upgrade';
    END IF;

    IF EXISTS (
        SELECT 1 FROM validation_test_result WHERE id = 'e0000000-0000-0000-0000-000000000007'
    ) OR EXISTS (
        SELECT 1 FROM validation_http_exchange WHERE id = 'f0000000-0000-0000-0000-000000000007'
    ) THEN
        RAISE EXCEPTION 'Child rows of deleted unpublished Run 7 should have been cascade-deleted';
    END IF;

    -- 4. Verify validation_run target_url and test-count normalizations
    SELECT * INTO v_run FROM validation_run WHERE id = 'd0000000-0000-0000-0000-000000000001';
    IF v_run.target_url <> 'HTTPS://scim.example.com/v2' THEN
        RAISE EXCEPTION 'Run 1 target_url mismatch: %', v_run.target_url;
    END IF;

    SELECT * INTO v_run FROM validation_run WHERE id = 'd0000000-0000-0000-0000-000000000002';
    IF v_run.target_url <> 'https://scim.example.com/v2'
       OR v_run.total_tests <> 8 OR v_run.passed_tests <> 8 OR v_run.failed_tests <> 0 THEN
        RAISE EXCEPTION 'Run 2 normalization mismatch: url=%, counts=(%,%,%)',
            v_run.target_url, v_run.total_tests, v_run.passed_tests, v_run.failed_tests;
    END IF;

    SELECT * INTO v_run FROM validation_run WHERE id = 'd0000000-0000-0000-0000-000000000003';
    IF v_run.target_url <> 'HTTPS://scim.example.com/v2'
       OR v_run.total_tests <> 7 OR v_run.passed_tests <> 4 OR v_run.failed_tests <> 3 THEN
        RAISE EXCEPTION 'Run 3 normalization mismatch: url=%, counts=(%,%,%)',
            v_run.target_url, v_run.total_tests, v_run.passed_tests, v_run.failed_tests;
    END IF;

    SELECT * INTO v_run FROM validation_run WHERE id = 'd0000000-0000-0000-0000-000000000004';
    IF v_run.target_url <> 'https://scim.legacy.example.com:8443/scim/v2' THEN
        RAISE EXCEPTION 'Run 4 published schemeless target_url normalization mismatch: %', v_run.target_url;
    END IF;

    SELECT * INTO v_run FROM validation_run WHERE id = 'd0000000-0000-0000-0000-000000000005';
    IF v_run.target_url <> 'https://legacy-invalid-target.invalid/' THEN
        RAISE EXCEPTION 'Run 5 published FTP target_url fallback mismatch: %', v_run.target_url;
    END IF;

    SELECT * INTO v_run FROM validation_run WHERE id = 'd0000000-0000-0000-0000-000000000006';
    IF v_run.target_url <> 'https://legacy-invalid-target.invalid/' THEN
        RAISE EXCEPTION 'Run 6 published empty-host target_url fallback mismatch: %', v_run.target_url;
    END IF;

    -- 5. Verify validation_run_publication in-place normalizations
    SELECT * INTO v_pub FROM validation_run_publication WHERE run_id = 'd0000000-0000-0000-0000-000000000003';
    IF v_pub.product_slug <> 'my-cool-scim'
       OR v_pub.project_url <> 'HTTPS://github.com/acme/scim'
       OR v_pub.report_url <> 'https://scimsandbox.org/compliance/?run=d0000000-0000-0000-0000-000000000003'
       OR v_pub.badge_url <> 'https://scimsandbox.org/compliance/badges/d0000000-0000-0000-0000-000000000003.svg'
       OR v_pub.pr_url <> 'HTTPS://github.com/scimsandbox/scim-website/pull/42' THEN
        RAISE EXCEPTION 'Pub 3 normalization mismatch: %', v_pub;
    END IF;

    SELECT * INTO v_pub FROM validation_run_publication WHERE run_id = 'd0000000-0000-0000-0000-000000000004';
    IF v_pub.product_slug <> 'product-33333333-3333-3333-3333-333333333333'
       OR v_pub.project_url IS NOT NULL
       OR v_pub.report_url <> 'HTTPS://scimsandbox.org/compliance/?run=4'
       OR v_pub.badge_url <> 'Http://scimsandbox.org/compliance/badges/4.svg'
       OR v_pub.pr_url <> 'PENDING_RESERVATION' THEN
        RAISE EXCEPTION 'Pub 4 normalization mismatch: %', v_pub;
    END IF;

    SELECT * INTO v_pub FROM validation_run_publication WHERE run_id = 'd0000000-0000-0000-0000-000000000005';
    IF v_pub.product_slug <> 'acme-enterprise-scim'
       OR v_pub.project_url IS NOT NULL
       OR v_pub.report_url <> 'https://scimsandbox.org/compliance/?run=d0000000-0000-0000-0000-000000000005'
       OR v_pub.badge_url <> 'https://scimsandbox.org/compliance/badges/d0000000-0000-0000-0000-000000000005.svg'
       OR v_pub.pr_url IS NOT NULL THEN
        RAISE EXCEPTION 'Pub 5 normalization mismatch: %', v_pub;
    END IF;

    SELECT * INTO v_pub FROM validation_run_publication WHERE run_id = 'd0000000-0000-0000-0000-000000000006';
    IF v_pub.product_slug <> 'legacy-product'
       OR v_pub.project_url <> 'HTTPS://github.com/acme/repo'
       OR v_pub.report_url <> 'https://scimsandbox.org/r/6'
       OR v_pub.badge_url <> 'https://scimsandbox.org/b/6.svg'
       OR v_pub.pr_url <> 'HTTPS://github.com/scimsandbox/scim-website/pull/6' THEN
        RAISE EXCEPTION 'Pub 6 normalization mismatch: %', v_pub;
    END IF;

    -- 6. Verify cross-run HTTP exchange removal and negative sequence_number normalization
    IF EXISTS (
        SELECT 1 FROM validation_http_exchange WHERE id = 'f0000000-0000-0000-0000-000000000099'
    ) THEN
        RAISE EXCEPTION 'Cross-run HTTP exchange f0000000-...0099 should have been deleted';
    END IF;

    -- 7. Verify 2 MiB UTF-8 truncation with '...[truncated]' suffix across all 6 TEXT columns
    SELECT * INTO v_tr FROM validation_test_result WHERE id = 'e0000000-0000-0000-0000-000000000001';
    IF octet_length(v_tr.error_message) <> 2097152
       OR right(v_tr.error_message, 14) <> '...[truncated]' THEN
        RAISE EXCEPTION 'error_message truncation mismatch: bytes=%, tail=%',
            octet_length(v_tr.error_message), right(v_tr.error_message, 14);
    END IF;
    IF octet_length(v_tr.stack_trace) <> 2097152
       OR right(v_tr.stack_trace, 14) <> '...[truncated]' THEN
        RAISE EXCEPTION 'stack_trace 3-byte UTF-8 truncation mismatch: bytes=%, tail=%',
            octet_length(v_tr.stack_trace), right(v_tr.stack_trace, 14);
    END IF;

    SELECT * INTO v_ex FROM validation_http_exchange WHERE id = 'f0000000-0000-0000-0000-000000000001';
    IF v_ex.sequence_number <> 0 THEN
        RAISE EXCEPTION 'Expected negative sequence_number to be normalized to 0, got %', v_ex.sequence_number;
    END IF;
    IF octet_length(v_ex.request_headers) NOT BETWEEN 2097149 AND 2097152
       OR right(v_ex.request_headers, 14) <> '...[truncated]' THEN
        RAISE EXCEPTION 'request_headers 4-byte emoji truncation mismatch: bytes=%, tail=%',
            octet_length(v_ex.request_headers), right(v_ex.request_headers, 14);
    END IF;
    IF octet_length(v_ex.request_body) NOT BETWEEN 2097149 AND 2097152
       OR right(v_ex.request_body, 14) <> '...[truncated]' THEN
        RAISE EXCEPTION 'request_body misaligned 3-byte UTF-8 truncation mismatch: bytes=%, tail=%',
            octet_length(v_ex.request_body), right(v_ex.request_body, 14);
    END IF;
    IF octet_length(v_ex.response_headers) <> 2097152
       OR right(v_ex.response_headers, 14) <> '...[truncated]' THEN
        RAISE EXCEPTION 'response_headers misaligned 4-byte UTF-8 truncation mismatch: bytes=%, tail=%',
            octet_length(v_ex.response_headers), right(v_ex.response_headers, 14);
    END IF;
    IF octet_length(v_ex.response_body) <> 2097152
       OR right(v_ex.response_body, 14) <> '...[truncated]' THEN
        RAISE EXCEPTION 'response_body ASCII truncation mismatch: bytes=%, tail=%',
            octet_length(v_ex.response_body), right(v_ex.response_body, 14);
    END IF;

    -- 8. Verify < 2 MiB control rows were NOT modified
    SELECT * INTO v_tr FROM validation_test_result WHERE id = 'e0000000-0000-0000-0000-000000000002';
    IF v_tr.error_message <> 'Short error' OR octet_length(v_tr.stack_trace) <> 100000 THEN
        RAISE EXCEPTION 'Control validation_test_result < 2 MiB was unexpectedly modified';
    END IF;

    SELECT * INTO v_ex FROM validation_http_exchange WHERE id = 'f0000000-0000-0000-0000-000000000002';
    IF octet_length(v_ex.response_body) <> 50000 THEN
        RAISE EXCEPTION 'Control validation_http_exchange < 2 MiB was unexpectedly modified';
    END IF;
END $$;

COMMIT;
