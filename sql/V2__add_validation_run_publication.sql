CREATE TABLE validation_run_publication (
    run_id UUID PRIMARY KEY,
    created_by_email VARCHAR(500) NOT NULL,
    product_name VARCHAR(120) NOT NULL,
    product_slug VARCHAR(120) NOT NULL,
    product_version VARCHAR(60) NOT NULL,
    vendor_name VARCHAR(120),
    project_url VARCHAR(500),
    license_type VARCHAR(40) NOT NULL,
    show_submitter BOOLEAN NOT NULL DEFAULT FALSE,
    core_score INTEGER NOT NULL,
    supported_capabilities INTEGER NOT NULL,
    total_capabilities INTEGER NOT NULL,
    report_url VARCHAR(500) NOT NULL,
    badge_url VARCHAR(500) NOT NULL,
    pr_url VARCHAR(500),
    published_at TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT fk_validation_run_publication_run
        FOREIGN KEY (run_id) REFERENCES validation_run (id) ON DELETE RESTRICT,
    CONSTRAINT fk_validation_run_publication_user
        FOREIGN KEY (created_by_email) REFERENCES validator_mgmt_users (email)
);

CREATE INDEX idx_validation_run_publication_email
    ON validation_run_publication (created_by_email, published_at DESC);
