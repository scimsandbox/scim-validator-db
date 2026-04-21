# SCIM Sandbox - Validator DB

This repository is the standalone database migration bundle for the SCIM Sandbox validator database.

## What Is In This Repo

- `sql/` contains the Flyway migration scripts.
- `sql/V1__init_validator_schema.sql` creates the initial validator schema.
- `Dockerfile` packages those migrations into a Flyway image that runs `flyway migrate` against a target PostgreSQL database.
- `CONTRIBUTING.md` and `SECURITY.md` describe the workflow and reporting process.

## Schema Overview

The initial migration creates:

- `validator_mgmt_users` for validator user records.
- `validation_run` for run metadata and aggregate results.
- `validation_test_result` for per-test outcomes.
- `validation_http_exchange` for the HTTP request and response traces captured during a run.

The migration also adds indexes for run lookup and ordered trace access.

## Working With Migrations

Add new migrations under `sql/` using Flyway versioned filenames such as `V2__add_validation_index.sql`. Keep migrations forward-only and avoid editing scripts that may already have been applied in another environment.

When you build or run the bundle, supply the Flyway connection settings at runtime with `FLYWAY_URL`, `FLYWAY_USER`, and `FLYWAY_PASSWORD`.

## Versioning

The release version is stored in [`VERSION`](./VERSION). The GitHub release workflow bumps that file with a patch, minor, or major increment, then tags and publishes the resulting commit. Publishing that GitHub release triggers the Docker publish workflow, which builds and pushes `edipal/scim-validator-db`.

## Published Image

Published releases build and push a multi-arch Flyway image to `edipal/scim-validator-db` with `latest`, `vX.Y.Z`, `X.Y.Z`, and `X.Y` tags.

## Validation

Before merging a migration change, apply it to a fresh PostgreSQL database and verify that the resulting schema matches the intended design. A typical check is to build the image and run it against an empty database, then inspect the resulting schema with `psql` or your preferred tooling.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

## Security

See [SECURITY.md](./SECURITY.md).
