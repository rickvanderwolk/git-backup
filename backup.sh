#!/bin/bash
set -e

# GitHub Backup Script
# Backs up all public GitHub repositories to USB drives

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
CONFIG_FILE="${SCRIPT_DIR}/config.env"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: config.env not found. Copy config.env.example to config.env and configure it."
    exit 1
fi

source "$CONFIG_FILE"

# Validate required config
if [ -z "$GITHUB_USER" ]; then
    echo "ERROR: GITHUB_USER not set in config.env"
    exit 1
fi

# Set defaults if not configured
TMP_DIR="${TMP_DIR:-/tmp/git-backup}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

# Check dependencies
check_dependencies() {
    local missing=()
    for cmd in git curl jq rsync; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo "ERROR: Missing dependencies: ${missing[*]}"
        echo "Install with: sudo apt install ${missing[*]}"
        exit 1
    fi
}

# Fetch list of public repositories from GitHub
fetch_repositories() {
    log "Fetching repository list for user: $GITHUB_USER"

    local api_url="https://api.github.com/users/${GITHUB_USER}/repos?per_page=100&type=public"
    local auth_header=""

    if [ -n "$GITHUB_TOKEN" ]; then
        auth_header="Authorization: token $GITHUB_TOKEN"
    fi

    if [ -n "$auth_header" ]; then
        curl -s -H "$auth_header" "$api_url" | jq -r '.[].clone_url'
    else
        curl -s "$api_url" | jq -r '.[].clone_url'
    fi
}

# Clone or update a repository (both mirror and working copy)
backup_repository() {
    local repo_url="$1"
    local repo_name=$(basename "$repo_url" .git)
    local mirror_path="${TMP_DIR}/${repo_name}.git"
    local working_path="${TMP_DIR}/${repo_name}"

    log "Processing: $repo_name"

    # Clone mirror (bare repository)
    log "  → Cloning mirror"
    git clone --mirror "$repo_url" "$mirror_path" 2>&1 | sed 's/^/    /' >&2

    # Clone working copy (with files)
    log "  → Cloning working copy"
    git clone "$repo_url" "$working_path" 2>&1 | sed 's/^/    /' >&2
}

# Sync single repository to USB targets
sync_repo_to_targets() {
    local repo_name="$1"

    for target in $BACKUP_TARGETS; do
        if [ -d "$target" ]; then
            log "  → Syncing to: $target"
            mkdir -p "$target/git-backup"
            rsync -a "$TMP_DIR/${repo_name}.git/" "$target/git-backup/${repo_name}.git/"
            rsync -a "$TMP_DIR/${repo_name}/" "$target/git-backup/${repo_name}/"
        else
            log "  ⚠ Skipping (not mounted): $target"
        fi
    done
}

# Cleanup single repository from temp
cleanup_repo() {
    local repo_name="$1"
    log "  → Cleaning up temp files"
    rm -rf "$TMP_DIR/${repo_name}.git" "$TMP_DIR/${repo_name}"
}

# Cleanup temporary directory
cleanup_all() {
    if [ -d "$TMP_DIR" ]; then
        log "Cleaning up temporary directory"
        rm -rf "$TMP_DIR"
    fi
}

# Main execution
main() {
    log "=== GitHub Backup Started ==="

    # Check dependencies
    check_dependencies

    # Create temporary directory
    mkdir -p "$TMP_DIR"

    # Fetch repository list
    repos=$(fetch_repositories)

    if [ -z "$repos" ]; then
        log "No repositories found for user: $GITHUB_USER"
        cleanup_all
        exit 1
    fi

    local repo_count=$(echo "$repos" | wc -l)
    log "Found $repo_count repositories"
    log ""

    # Process each repository one by one
    local current=0
    while IFS= read -r repo_url; do
        current=$((current + 1))
        local repo_name=$(basename "$repo_url" .git)

        log "[$current/$repo_count] $repo_name"

        # Clone both mirror and working copy
        backup_repository "$repo_url"

        # Sync to USB targets
        sync_repo_to_targets "$repo_name"

        # Cleanup this repo from temp
        cleanup_repo "$repo_name"

        log ""
    done <<< "$repos"

    # Final cleanup
    cleanup_all

    log "=== GitHub Backup Completed ==="
    log "Backed up $repo_count repositories to:"
    for target in $BACKUP_TARGETS; do
        if [ -d "$target" ]; then
            log "  - $target/git-backup/"
        fi
    done
}

# Run main function
main
