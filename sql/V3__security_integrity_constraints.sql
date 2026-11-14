-- Forward security and referential-integrity hardening migration (V3).
-- Compatible with scim-validator-ui-spring JPA entities, localhost dev/test targets,
-- mixed-case RFC 3986 URL schemes, pre-GitHub PENDING_RESERVATION publication claims,
-- and generous 2 MiB trace/stacktrace sizes.

-- 1. Session-scoped temporary helpers in pg_temp (no objects left in public schema).

CREATE OR REPLACE FUNCTION pg_temp.truncate_utf8_bytes(
    val TEXT,
    max_bytes INTEGER DEFAULT 2097152,
    suffix TEXT DEFAULT '...[truncated]'
) RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    suffix_bytes INTEGER;
    budget INTEGER;
    char_limit INTEGER;
    candidate TEXT;
BEGIN
    IF val IS NULL OR octet_length(val) <= max_bytes THEN
        RETURN val;
    END IF;
    IF max_bytes <= 0 THEN
        RETURN '';
    END IF;

    suffix_bytes := octet_length(suffix);
    IF max_bytes <= suffix_bytes THEN
        candidate := left(suffix, max_bytes);
        WHILE octet_length(candidate) > max_bytes LOOP
            candidate := left(candidate, char_length(candidate) - 1);
        END LOOP;
        RETURN candidate;
    END IF;

    budget := max_bytes - suffix_bytes;
    char_limit := LEAST(char_length(val), budget);
    candidate := left(val, char_limit);
    WHILE octet_length(candidate) > budget LOOP
        char_limit := char_limit - GREATEST(1, div(octet_length(candidate) - budget, 4));
        candidate := left(val, char_limit);
    END LOOP;

    RETURN candidate || suffix;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.clean_http_url(raw_url TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    cleaned TEXT;
BEGIN
    IF raw_url IS NULL THEN
        RETURN NULL;
    END IF;

    cleaned := regexp_replace(raw_url, '^\s+|\s+$', '', 'g');
    IF cleaned = '' THEN
        RETURN NULL;
    END IF;

    cleaned := regexp_replace(cleaned, '^(https?://)[^/?#]*@', '\1', 'i');
    IF char_length(cleaned) <= 500
       AND cleaned ~* '^https?://[^/?#\s]\S*$'
       AND cleaned !~* '^https?://[^/?#]*@' THEN
        RETURN cleaned;
    END IF;

    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_published_target_url(raw_url TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    cleaned TEXT;
    collapsed TEXT;
BEGIN
    cleaned := pg_temp.clean_http_url(raw_url);
    IF cleaned IS NOT NULL THEN
        RETURN cleaned;
    END IF;

    collapsed := regexp_replace(coalesce(raw_url, ''), '\s+', '', 'g');
    IF collapsed = ''
       OR collapsed ~* '^(?:javascript|data|vbscript|mailto|file|ftp|ftps|sftp|ssh|gopher|ldap|ldaps|urn|tel|blob|about):'
       OR (collapsed ~* '^[a-z][a-z0-9+.-]*://' AND collapsed !~* '^https?://') THEN
        RETURN 'https://legacy-invalid-target.invalid/';
    END IF;

    IF collapsed ~ '^//+' THEN
        collapsed := 'https://' || regexp_replace(collapsed, '^//+', '');
    ELSIF collapsed !~* '^https?://' THEN
        collapsed := 'https://' || collapsed;
    END IF;

    collapsed := left(regexp_replace(collapsed, '^(https?://)[^/?#]*@', '\1', 'i'), 500);
    cleaned := pg_temp.clean_http_url(collapsed);
    IF cleaned IS NOT NULL
       AND cleaned ~* '^https?://(?:\[[0-9a-f:]+\]|localhost|[a-z0-9-]+(?:\.[a-z0-9-]+)*)(?::[0-9]{1,5})?(?:$|[/?#])' THEN
        RETURN cleaned;
    END IF;

    RETURN 'https://legacy-invalid-target.invalid/';
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.normalize_product_slug(raw_slug TEXT, raw_name TEXT)
RETURNS VARCHAR(120)
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    slug TEXT;
BEGIN
    IF raw_slug IS NOT NULL
       AND char_length(raw_slug) <= 120
       AND raw_slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
       AND raw_slug !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RETURN raw_slug;
    END IF;

    slug := btrim(regexp_replace(lower(coalesce(raw_slug, '')), '[^a-z0-9]+', '-', 'g'), '-');
    IF slug = '' THEN
        slug := btrim(regexp_replace(lower(coalesce(raw_name, '')), '[^a-z0-9]+', '-', 'g'), '-');
    END IF;
    IF slug = '' THEN
        slug := 'legacy-product';
    END IF;
    IF slug ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        slug := 'product-' || slug;
    END IF;

    slug := btrim(left(slug, 120), '-');
    IF slug = '' THEN
        slug := 'legacy-product';
    ELSIF slug ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        slug := 'product-' || slug;
    END IF;

    RETURN slug;
END;
$$;

-- 2. Pre-constraint cleanup / normalization for existing databases so V3 applies cleanly.

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

-- Bound any oversized legacy TEXT columns to <= 2 MiB (2,097,152 UTF-8 bytes) with '...[truncated]' marker.
UPDATE validation_test_result
SET error_message = CASE
        WHEN error_message IS NOT NULL AND octet_length(error_message) > 2097152
        THEN pg_temp.truncate_utf8_bytes(error_message)
        ELSE error_message
    END,
    stack_trace = CASE
        WHEN stack_trace IS NOT NULL AND octet_length(stack_trace) > 2097152
        THEN pg_temp.truncate_utf8_bytes(stack_trace)
        ELSE stack_trace
    END
WHERE (error_message IS NOT NULL AND octet_length(error_message) > 2097152)
   OR (stack_trace IS NOT NULL AND octet_length(stack_trace) > 2097152);

UPDATE validation_http_exchange
SET request_headers = CASE
        WHEN request_headers IS NOT NULL AND octet_length(request_headers) > 2097152
        THEN pg_temp.truncate_utf8_bytes(request_headers)
        ELSE request_headers
    END,
    request_body = CASE
        WHEN request_body IS NOT NULL AND octet_length(request_body) > 2097152
        THEN pg_temp.truncate_utf8_bytes(request_body)
        ELSE request_body
    END,
    response_headers = CASE
        WHEN response_headers IS NOT NULL AND octet_length(response_headers) > 2097152
        THEN pg_temp.truncate_utf8_bytes(response_headers)
        ELSE response_headers
    END,
    response_body = CASE
        WHEN response_body IS NOT NULL AND octet_length(response_body) > 2097152
        THEN pg_temp.truncate_utf8_bytes(response_body)
        ELSE response_body
    END
WHERE (request_headers IS NOT NULL AND octet_length(request_headers) > 2097152)
   OR (request_body IS NOT NULL AND octet_length(request_body) > 2097152)
   OR (response_headers IS NOT NULL AND octet_length(response_headers) > 2097152)
   OR (response_body IS NOT NULL AND octet_length(response_body) > 2097152);

-- Normalize legacy run test counts, trim whitespace, and strip embedded userinfo credentials.
UPDATE validation_run
SET passed_tests = GREATEST(passed_tests, 0),
    failed_tests = GREATEST(failed_tests, 0),
    total_tests = GREATEST(total_tests, GREATEST(passed_tests, 0) + GREATEST(failed_tests, 0))
WHERE total_tests < 0
   OR passed_tests < 0
   OR failed_tests < 0
   OR passed_tests + failed_tests > total_tests;

UPDATE validation_run
SET target_url = regexp_replace(
        regexp_replace(target_url, '^\s+|\s+$', '', 'g'),
        '^(https?://)[^/?#]*@',
        '\1',
        'i'
    )
WHERE target_url ~ '^\s|\s$'
   OR regexp_replace(target_url, '^\s+|\s+$', '', 'g') ~* '^https?://[^/?#]*@';

-- Preserve published validation_run rows in place so live leaderboard entries never fail V3 or get deleted.
UPDATE validation_run r
SET target_url = pg_temp.normalize_published_target_url(r.target_url)
WHERE (r.target_url !~* '^https?://[^/?#\s]\S*$' OR r.target_url ~* '^https?://[^/?#]*@')
  AND EXISTS (
      SELECT 1 FROM validation_run_publication p WHERE p.run_id = r.id
  );

-- Purge only unpublished validation_run rows whose target_url remains invalid.
DELETE FROM validation_run r
WHERE (r.target_url !~* '^https?://[^/?#\s]\S*$' OR r.target_url ~* '^https?://[^/?#]*@')
  AND NOT EXISTS (
      SELECT 1 FROM validation_run_publication p WHERE p.run_id = r.id
  );

-- Normalize live validation_run_publication rows in place without deleting any published leaderboard records.
UPDATE validation_run_publication
SET product_slug = pg_temp.normalize_product_slug(product_slug, product_name),
    project_url = pg_temp.clean_http_url(project_url),
    pr_url = CASE
        WHEN pr_url IS NULL THEN NULL
        WHEN regexp_replace(pr_url, '^\s+|\s+$', '', 'g') = 'PENDING_RESERVATION' THEN 'PENDING_RESERVATION'
        ELSE pg_temp.clean_http_url(pr_url)
    END,
    report_url = COALESCE(
        pg_temp.clean_http_url(report_url),
        'https://scimsandbox.org/compliance/?run=' || run_id::text
    ),
    badge_url = COALESCE(
        pg_temp.clean_http_url(badge_url),
        'https://scimsandbox.org/compliance/badges/' || run_id::text || '.svg'
    )
WHERE product_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
   OR product_slug ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   OR (project_url IS NOT NULL AND (project_url ~ '^\s|\s$' OR project_url !~* '^https?://[^/?#\s]\S*$' OR project_url ~* '^https?://[^/?#]*@'))
   OR (pr_url IS NOT NULL AND pr_url <> 'PENDING_RESERVATION' AND (pr_url ~ '^\s|\s$' OR pr_url !~* '^https?://[^/?#\s]\S*$' OR pr_url ~* '^https?://[^/?#]*@'))
   OR report_url ~ '^\s|\s$'
   OR report_url !~* '^https?://[^/?#\s]\S*$'
   OR report_url ~* '^https?://[^/?#]*@'
   OR badge_url ~ '^\s|\s$'
   OR badge_url !~* '^https?://[^/?#\s]\S*$'
   OR badge_url ~* '^https?://[^/?#]*@';

-- 3. Consolidated table constraint hardening (one ALTER TABLE per table to minimize scans under lock).

ALTER TABLE validation_test_result
    ADD CONSTRAINT uk_validation_test_result_id_run_id
        UNIQUE (id, run_id),
    ADD CONSTRAINT chk_validation_test_result_error_message_length
        CHECK (error_message IS NULL OR octet_length(error_message) <= 2097152),
    ADD CONSTRAINT chk_validation_test_result_stack_trace_length
        CHECK (stack_trace IS NULL OR octet_length(stack_trace) <= 2097152);

ALTER TABLE validation_http_exchange
    DROP CONSTRAINT IF EXISTS fk_validation_http_exchange_test_result,
    ADD CONSTRAINT fk_validation_http_exchange_test_result
        FOREIGN KEY (test_result_id, run_id)
        REFERENCES validation_test_result (id, run_id)
        ON DELETE CASCADE,
    ADD CONSTRAINT chk_validation_http_exchange_sequence_number
        CHECK (sequence_number >= 0),
    ADD CONSTRAINT chk_validation_http_exchange_request_headers_length
        CHECK (request_headers IS NULL OR octet_length(request_headers) <= 2097152),
    ADD CONSTRAINT chk_validation_http_exchange_request_body_length
        CHECK (request_body IS NULL OR octet_length(request_body) <= 2097152),
    ADD CONSTRAINT chk_validation_http_exchange_response_headers_length
        CHECK (response_headers IS NULL OR octet_length(response_headers) <= 2097152),
    ADD CONSTRAINT chk_validation_http_exchange_response_body_length
        CHECK (response_body IS NULL OR octet_length(response_body) <= 2097152);

ALTER TABLE validation_run
    ADD CONSTRAINT chk_validation_run_target_url_scheme
        CHECK (target_url ~* '^https?://[^/?#\s]\S*$'),
    ADD CONSTRAINT chk_validation_run_target_url_no_userinfo
        CHECK (target_url !~* '^https?://[^/?#]*@'),
    ADD CONSTRAINT chk_validation_run_test_counts
        CHECK (total_tests >= 0 AND passed_tests >= 0 AND failed_tests >= 0 AND passed_tests + failed_tests <= total_tests);

ALTER TABLE validation_run_publication
    ADD CONSTRAINT chk_validation_run_publication_product_slug
        CHECK (
            product_slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
            AND product_slug !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        ),
    ADD CONSTRAINT chk_validation_run_publication_project_url
        CHECK (project_url IS NULL OR (project_url ~* '^https?://[^/?#\s]\S*$' AND project_url !~* '^https?://[^/?#]*@')),
    ADD CONSTRAINT chk_validation_run_publication_report_url
        CHECK (report_url ~* '^https?://[^/?#\s]\S*$' AND report_url !~* '^https?://[^/?#]*@'),
    ADD CONSTRAINT chk_validation_run_publication_badge_url
        CHECK (badge_url ~* '^https?://[^/?#\s]\S*$' AND badge_url !~* '^https?://[^/?#]*@'),
    ADD CONSTRAINT chk_validation_run_publication_pr_url
        CHECK (
            pr_url IS NULL
            OR pr_url = 'PENDING_RESERVATION'
            OR (pr_url ~* '^https?://[^/?#\s]\S*$' AND pr_url !~* '^https?://[^/?#]*@')
        );

DROP FUNCTION IF EXISTS pg_temp.truncate_utf8_bytes(TEXT, INTEGER, TEXT);
DROP FUNCTION IF EXISTS pg_temp.clean_http_url(TEXT);
DROP FUNCTION IF EXISTS pg_temp.normalize_published_target_url(TEXT);
DROP FUNCTION IF EXISTS pg_temp.normalize_product_slug(TEXT, TEXT);
