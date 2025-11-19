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

# Clone or update a repository
backup_repository() {
    local repo_url="$1"
    local repo_name=$(basename "$repo_url" .git)
    local repo_path="${TMP_DIR}/${repo_name}.git"

    if [ -d "$repo_path" ]; then
        log "Updating: $repo_name"
        git -C "$repo_path" remote update --prune
    else
        log "Cloning: $repo_name"
        git clone --mirror "$repo_url" "$repo_path"
    fi
}

# Sync to USB targets
sync_to_targets() {
    log "Syncing to backup targets..."

    for target in $BACKUP_TARGETS; do
        if [ -d "$target" ]; then
            log "  → Syncing to: $target"
            mkdir -p "$target"
            rsync -av --delete "$TMP_DIR/" "$target/"
        else
            log "  ⚠ Skipping (not mounted): $target"
        fi
    done
}

# Cleanup temporary directory
cleanup() {
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

    # Fetch and backup repositories
    repos=$(fetch_repositories)

    if [ -z "$repos" ]; then
        log "No repositories found for user: $GITHUB_USER"
        cleanup
        exit 1
    fi

    local repo_count=$(echo "$repos" | wc -l)
    log "Found $repo_count repositories"

    # Backup each repository
    while IFS= read -r repo_url; do
        backup_repository "$repo_url"
    done <<< "$repos"

    # Sync to USB targets
    sync_to_targets

    # Cleanup
    cleanup

    log "=== GitHub Backup Completed ==="
}

# Run main function
main
