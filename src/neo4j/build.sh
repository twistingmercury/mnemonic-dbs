#!/usr/bin/env bash
# build.sh — Build the mnemonic-neo4j pre-seeded Docker image.
#
# Strategy: build a base image from the Dockerfile, start a container, apply
# Cypher schema migrations, stop the container, then commit it as the final
# image.  A trap ensures the temp container and base image are cleaned up even
# when the script exits early due to an error.
#
# Usage: bash src/neo4j/build.sh
#
# Set the VERSION environment variable to override the git-derived version.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log_info() {
    printf 'INFO: %s\n' "$*"
}

log_success() {
    printf 'SUCCESS: %s\n' "$*"
}

log_error() {
    printf 'ERROR: %s\n' "$*" >&2
}

# ---------------------------------------------------------------------------
# Version and image names
# ---------------------------------------------------------------------------
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null || echo 'dev')}"

IMAGE_BASE="ghcr.io/twistingmercury/mnemonic-neo4j"
IMAGE_VERSIONED="${IMAGE_BASE}:${VERSION}"
IMAGE_LATEST="${IMAGE_BASE}:latest"

TEMP_BASE_IMAGE="mnemonic-neo4j-base:build-$$"
TEMP_CONTAINER="neo4j-schema-init-$$"

# ---------------------------------------------------------------------------
# Cleanup — called by trap on EXIT
# ---------------------------------------------------------------------------
cleanup() {
    log_info "Cleaning up temp container and base image..."
    docker rm -f "${TEMP_CONTAINER}" 2>/dev/null || true
    docker rmi -f "${TEMP_BASE_IMAGE}" 2>/dev/null || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Build base image
# ---------------------------------------------------------------------------
log_info "Building Neo4j base image"
log_info "Version : ${VERSION}"
log_info "Image   : ${IMAGE_VERSIONED}"

docker build \
    --progress=plain \
    -t "${TEMP_BASE_IMAGE}" \
    "${SCRIPT_DIR}"

# ---------------------------------------------------------------------------
# Start temp container
# ---------------------------------------------------------------------------
log_info "Starting temp container: ${TEMP_CONTAINER}"

docker run -d \
    --name "${TEMP_CONTAINER}" \
    --env NEO4J_AUTH=neo4j/mnemonic_dev \
    --env NEO4J_PLUGINS='["apoc"]' \
    --env NEO4J_dbms_security_procedures_unrestricted='apoc.*' \
    --env NEO4J_dbms_security_procedures_allowlist='apoc.*' \
    "${TEMP_BASE_IMAGE}"

# ---------------------------------------------------------------------------
# Wait for Neo4j to be ready
# ---------------------------------------------------------------------------
log_info "Waiting for Neo4j to become ready..."

MAX_RETRIES=30
RETRY_SLEEP=2
READY=0

for i in $(seq 1 "${MAX_RETRIES}"); do
    if docker exec "${TEMP_CONTAINER}" cypher-shell \
            -u neo4j -p mnemonic_dev "RETURN 1" >/dev/null 2>&1; then
        READY=1
        log_info "Neo4j ready after ${i} attempt(s)"
        break
    fi
    log_info "Attempt ${i}/${MAX_RETRIES} — not ready yet, retrying in ${RETRY_SLEEP}s..."
    sleep "${RETRY_SLEEP}"
done

if [ "${READY}" -eq 0 ]; then
    log_error "Neo4j did not become ready after $((MAX_RETRIES * RETRY_SLEEP))s — aborting"
    exit 1
fi

# ---------------------------------------------------------------------------
# Apply schema migrations
# ---------------------------------------------------------------------------

# Migration 001: uniqueness constraints
log_info "Applying 001_create_constraints.cypher..."
docker cp "${SCRIPT_DIR}/001_create_constraints.cypher" \
    "${TEMP_CONTAINER}:/tmp/001_create_constraints.cypher"
docker exec "${TEMP_CONTAINER}" cypher-shell \
    -u neo4j -p mnemonic_dev \
    -f /tmp/001_create_constraints.cypher

# Migration 002: existence constraints — SKIPPED
# 002_create_existence_constraints.cypher requires Neo4j Enterprise Edition.
# The Community Edition image (neo4j:5) does not support property existence
# constraints, so this migration is intentionally omitted here.
log_info "Skipping 002_create_existence_constraints.cypher (Enterprise Edition only)"

# Migration 003: indexes
log_info "Applying 003_create_indexes.cypher..."
docker cp "${SCRIPT_DIR}/003_create_indexes.cypher" \
    "${TEMP_CONTAINER}:/tmp/003_create_indexes.cypher"
docker exec "${TEMP_CONTAINER}" cypher-shell \
    -u neo4j -p mnemonic_dev \
    -f /tmp/003_create_indexes.cypher

# ---------------------------------------------------------------------------
# Stop container and commit
# ---------------------------------------------------------------------------
log_info "Stopping temp container..."
docker stop "${TEMP_CONTAINER}"

log_info "Committing image as ${IMAGE_VERSIONED} and ${IMAGE_LATEST}..."
docker commit "${TEMP_CONTAINER}" "${IMAGE_VERSIONED}"
docker tag "${IMAGE_VERSIONED}" "${IMAGE_LATEST}"

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
IMAGE_SIZE="$(docker image inspect "${IMAGE_VERSIONED}" --format '{{.Size}}' | awk '{printf "%.1f MB", $1/1024/1024}')"
log_success "Image built: ${IMAGE_VERSIONED}"
log_success "Image size : ${IMAGE_SIZE}"
