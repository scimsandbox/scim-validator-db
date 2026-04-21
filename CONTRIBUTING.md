# Contributing

Thanks for contributing to scim-validator-db.

This repository is intentionally small. It only contains the validator database migrations and the Flyway packaging needed to apply them. Keep changes focused on schema evolution, migration delivery, and documentation that matches the live repository structure.

## Ground Rules

- Keep each change narrow and intentional.
- Prefer forward-only migrations.
- Do not edit already-published migrations unless you are resetting a disposable environment.
- Do not add application code, secrets, or environment-specific connection details.
- Keep SQL readable, explicit, and easy to review.

## Before You Start

1. Check for existing issues or pull requests that cover the same schema change.
2. For non-trivial schema changes, describe the target state before you start coding.
3. Add a new migration file under `sql/` instead of rewriting earlier versions.
4. If the packaging flow changes, update the Dockerfile and this documentation together.

## Current Schema

The initial migration creates `validator_mgmt_users`, `validation_run`, `validation_test_result`, and `validation_http_exchange` tables. If your change affects any of those areas, call that out clearly in the PR description so reviewers can understand the impact.

## Migration Conventions

- Use Flyway versioned filenames such as `V2__add_validation_index.sql`.
- Keep one logical change per file when possible.
- Make scripts safe to run in order on a fresh database.
- Prefer additive changes; if a destructive change is required, call it out clearly in the PR description.
- Keep object names and constraints consistent with the existing schema.

## Validation

Validate migration changes against a clean PostgreSQL instance before opening a PR.

Common checks:

- run the Flyway container against the target database
- confirm the migration order is correct
- verify the resulting schema with `psql` or your preferred inspection tool

## Pull Request Checklist

Before opening a PR, make sure it:

- explains the schema change and why it is needed
- includes any new migration file(s)
- updates the Dockerfile or docs if the packaging flow changes
- avoids unrelated cleanup
- passes validation against a clean database

## Reporting Bugs

When reporting a migration problem, include:

- the migration file name
- the database engine and version
- the failing SQL statement or error
- the expected schema outcome
- the steps used to reproduce the issue

## Security Issues

Do not report vulnerabilities through public issues. Follow [SECURITY.md](./SECURITY.md) instead.
