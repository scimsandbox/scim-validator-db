-- Forward security and referential-integrity hardening migration (V3).
-- Compatible with scim-validator-ui-spring JPA entities, localhost dev/test targets,
-- pre-GitHub PENDING_RESERVATION publication claims, and generous trace/stacktrace sizes.

-- 1. Pre-constraint cleanup / normalization for existing databases so V3 applies cleanly.

-- Remove any orphaned or cross-run HTTP exchanges whose (test_result_id, run_id) pair does not match.
DELETE FROM validation_http_exchange e
WHERE NOT EXISTS (
    SELECT 1
    FROM validation_test_result tr
    WHERE tr.id = e.test_result_id
      AND tr.run_id = e.run_id
);

UPDATE validation_http_exchange
SET sequence_number = 0
WHERE sequence_number < 0;

-- Bound any oversized legacy TEXT columns to <= 2 MiB (524,288 UTF-8 chars <= 2,097,152 bytes).
UPDATE validation_test_result
SET error_message = left(error_message, 524288)
WHERE error_message IS NOT NULL AND octet_length(error_message) > 2097152;

UPDATE validation_test_result
SET stack_trace = left(stack_trace, 524288)
WHERE stack_trace IS NOT NULL AND octet_length(stack_trace) > 2097152;

UPDATE validation_http_exchange
SET request_headers = left(request_headers, 524288)
WHERE request_headers IS NOT NULL AND octet_length(request_headers) > 2097152;

UPDATE validation_http_exchange
SET request_body = left(request_body, 524288)
WHERE request_body IS NOT NULL AND octet_length(request_body) > 2097152;

UPDATE validation_http_exchange
SET response_headers = left(response_headers, 524288)
WHERE response_headers IS NOT NULL AND octet_length(response_headers) > 2097152;

UPDATE validation_http_exchange
SET response_body = left(response_body, 524288)
WHERE response_body IS NOT NULL AND octet_length(response_body) > 2097152;

-- Normalize any legacy run test counts or strip embedded userinfo credentials from target_url.
UPDATE validation_run
SET passed_tests = GREATEST(passed_tests, 0),
    failed_tests = GREATEST(failed_tests, 0),
    total_tests = GREATEST(total_tests, GREATEST(passed_tests, 0) + GREATEST(failed_tests, 0))
WHERE total_tests < 0
   OR passed_tests < 0
   OR failed_tests < 0
   OR passed_tests + failed_tests > total_tests;

UPDATE validation_run
SET target_url = regexp_replace(target_url, '^(https?://)[^/?#]*@', '\1')
WHERE target_url ~ '^https?://[^/?#]*@';

DELETE FROM validation_run r
WHERE (r.target_url !~ '^https?://\S+$' OR r.target_url ~ '^https?://[^/?#]*@')
  AND NOT EXISTS (
      SELECT 1 FROM validation_run_publication p WHERE p.run_id = r.id
  );

-- Normalize nullable publication URLs and purge any malformed publication rows before adding CHECKs.
UPDATE validation_run_publication
SET project_url = NULL
WHERE project_url IS NOT NULL
  AND project_url !~ '^https?://\S+$';

UPDATE validation_run_publication
SET pr_url = NULL
WHERE pr_url IS NOT NULL
  AND pr_url <> 'PENDING_RESERVATION'
  AND pr_url !~ '^https?://\S+$';

DELETE FROM validation_run_publication
WHERE product_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
   OR product_slug ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   OR report_url !~ '^https?://\S+$'
   OR badge_url !~ '^https?://\S+$';

-- 2. Referential integrity: enforce same-run composite FK between validation_http_exchange and validation_test_result.
ALTER TABLE validation_test_result
    ADD CONSTRAINT uk_validation_test_result_id_run_id UNIQUE (id, run_id);

ALTER TABLE validation_http_exchange
    DROP CONSTRAINT IF EXISTS fk_validation_http_exchange_test_result;

ALTER TABLE validation_http_exchange
    ADD CONSTRAINT fk_validation_http_exchange_test_result
        FOREIGN KEY (test_result_id, run_id)
        REFERENCES validation_test_result (id, run_id)
        ON DELETE CASCADE;

-- 3. Domain & URL scheme CHECK constraints on validation_run.
ALTER TABLE validation_run
    ADD CONSTRAINT chk_validation_run_target_url_scheme
        CHECK (target_url ~ '^https?://\S+$');

ALTER TABLE validation_run
    ADD CONSTRAINT chk_validation_run_target_url_no_userinfo
        CHECK (target_url !~ '^https?://[^/?#]*@');

ALTER TABLE validation_run
    ADD CONSTRAINT chk_validation_run_test_counts
        CHECK (total_tests >= 0 AND passed_tests >= 0 AND failed_tests >= 0 AND passed_tests + failed_tests <= total_tests);

-- 4. Generous 2 MiB (2,097,152 bytes) upper bounds on unbounded TEXT columns (blocks multi-hundred-MB abuse).
ALTER TABLE validation_test_result
    ADD CONSTRAINT chk_validation_test_result_error_message_length
        CHECK (error_message IS NULL OR octet_length(error_message) <= 2097152);

ALTER TABLE validation_test_result
    ADD CONSTRAINT chk_validation_test_result_stack_trace_length
        CHECK (stack_trace IS NULL OR octet_length(stack_trace) <= 2097152);

ALTER TABLE validation_http_exchange
    ADD CONSTRAINT chk_validation_http_exchange_sequence_number
        CHECK (sequence_number >= 0);

ALTER TABLE validation_http_exchange
    ADD CONSTRAINT chk_validation_http_exchange_request_headers_length
        CHECK (request_headers IS NULL OR octet_length(request_headers) <= 2097152);

ALTER TABLE validation_http_exchange
    ADD CONSTRAINT chk_validation_http_exchange_request_body_length
        CHECK (request_body IS NULL OR octet_length(request_body) <= 2097152);

ALTER TABLE validation_http_exchange
    ADD CONSTRAINT chk_validation_http_exchange_response_headers_length
        CHECK (response_headers IS NULL OR octet_length(response_headers) <= 2097152);

ALTER TABLE validation_http_exchange
    ADD CONSTRAINT chk_validation_http_exchange_response_body_length
        CHECK (response_body IS NULL OR octet_length(response_body) <= 2097152);

-- 5. Slug format and URL scheme CHECK constraints on validation_run_publication.
ALTER TABLE validation_run_publication
    ADD CONSTRAINT chk_validation_run_publication_product_slug
        CHECK (
            product_slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
            AND product_slug !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        );

ALTER TABLE validation_run_publication
    ADD CONSTRAINT chk_validation_run_publication_project_url
        CHECK (project_url IS NULL OR project_url ~ '^https?://\S+$');

ALTER TABLE validation_run_publication
    ADD CONSTRAINT chk_validation_run_publication_report_url
        CHECK (report_url ~ '^https?://\S+$');

ALTER TABLE validation_run_publication
    ADD CONSTRAINT chk_validation_run_publication_badge_url
        CHECK (badge_url ~ '^https?://\S+$');

ALTER TABLE validation_run_publication
    ADD CONSTRAINT chk_validation_run_publication_pr_url
        CHECK (pr_url IS NULL OR pr_url = 'PENDING_RESERVATION' OR pr_url ~ '^https?://\S+$');
