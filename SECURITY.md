# Security Policy

## Supported Versions

This repository supports the latest code on the `main` branch and the latest image or artifact built from that branch.

Because this repository was split out of a larger SCIM Sandbox codebase, it does not publish long-lived release branches. Fixes are expected to land on `main` first.

## Reporting a Vulnerability

Do not open public GitHub issues for security vulnerabilities.

Use GitHub Security Advisories for private reporting:

1. Open the repository Security tab.
2. Select Advisories.
3. Create a new draft security advisory.
4. Include the affected migration file(s), reproduction steps, impact, and any suggested mitigation.

If GitHub private reporting is unavailable, use the maintainer contact options on the GitHub profile.

## Scope of Security Review

Security-sensitive areas in this repository include:

- SQL migration scripts under `sql/`
- the Flyway container image defined by `Dockerfile`
- database connection credentials passed to the migration container

## Operational Guidance

If you run these migrations outside a local sandbox, apply these controls first:

1. Use a dedicated migration user with only the privileges needed to create and alter the schema.
2. Protect database passwords and connection strings as secrets.
3. Use separate databases or schemas per environment.
4. Review new DDL carefully before applying it to shared or production databases.
5. Verify that destructive changes are intentional and coordinated.

## Secrets Handling

- Do not commit database passwords or connection strings.
- Do not commit production credentials for migration jobs.
- Treat sample environment values as local-only unless explicitly documented otherwise.

## Current Mitigations

The repository currently relies on these baseline controls:

- Flyway versioned migration history
- a small, auditable image surface built from the Flyway base image
- explicit database connection parameters supplied at runtime rather than baked into the image

## Security Testing Expectations

When changing SQL migrations or the migration container, contributors should validate the new scripts against a fresh database and review the resulting schema for unintended privilege or data exposure changes.
