# mnemonic-dbs

> **Maturity Level**: Emerging - Pre-seeded database images and schema migrations for the Mnemonic project
> **Version**: v1.0.0

> - **Emerging**: Prototype, not production-ready, expect breaking changes
> - **Basic**: Production-ready but actively evolving, expect minor version changes
> - **Mature**: Stable, battle-tested, changes are rare

---

## Table of Contents

- [Usage](#usage)
- [How it works](#how-it-works)
- [Key Considerations](#key-considerations)
- [Development Considerations](#development-considerations)
- [Versioning](#versioning)

## Usage

Pull the pre-seeded images for use in local development or testing:

```bash
docker pull ghcr.io/twistingmercury/mnemonic-postgres:latest-dev
docker pull ghcr.io/twistingmercury/mnemonic-neo4j:latest-dev
```

Both images are self-initializing — the schema is applied on first container start. No migration tool required.

## How it works

**PostgreSQL image** (`ghcr.io/twistingmercury/mnemonic-postgres`): built `FROM pgvector/pgvector:pg16`. All `.up.sql` migration files are copied into `/docker-entrypoint-initdb.d/` and executed automatically in order on first start.

**Neo4j image** (`ghcr.io/twistingmercury/mnemonic-neo4j`): built `FROM neo4j:5` with APOC enabled. The build script starts a temporary container, applies the Cypher constraint and index files via `cypher-shell`, then commits the result as the final image.

**CI**: a GitHub Actions workflow triggers on any change to `src/postgres/**` or `src/neo4j/**`, runs the BATS test suites for both databases, then builds and pushes both images to GHCR.

## Key Considerations

- `002_create_existence_constraints.cypher` is skipped at build time — existence constraints require Neo4j Enterprise Edition
- `.down.sql` files are not included; rollback is handled by rebuilding from a prior image tag
- Images are tagged `latest` + version on `main`, `latest-dev` + version-dev on `develop`

## Development Considerations

### Quick Start

Requires Docker 27+, Docker Compose 2.32+, `bats-core`, and `psql`.

Build both images locally:

```bash
make build
```

Build individually:

```bash
make build-postgres
make build-neo4j
```

### Testing

BATS tests verify the schema state after all migrations have been applied.

```bash
make test           # run both test suites
make test-postgres  # PostgreSQL only
make test-neo4j     # Neo4j only
```

Tests spin up a local Docker Compose stack on isolated ports (Postgres `5435`, Neo4j bolt `7690`) so they do not conflict with other running stacks.

### Versioning

This project follows [Semantic Versioning 2.0.0](https://semver.org/).

Version is determined from git tags:

```bash
git describe --tags --always
```
