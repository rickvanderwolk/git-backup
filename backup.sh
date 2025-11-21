#!/bin/bash

# GitHub Backup Script
# Backs up all public GitHub repositories to USB drives
# Uses incremental updates and skip logic for efficiency

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Lock file for preventing concurrent runs
LOCKFILE="/tmp/git-backup.lock"

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
MASTER_BACKUP_DIR="${MASTER_BACKUP_DIR:-/home/pi/git-backup-master}"
TMP_DIR="${TMP_DIR:-/tmp/git-backup}"
CREATE_WORKING_COPY="${CREATE_WORKING_COPY:-false}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

# Acquire lock to prevent concurrent runs
acquire_lock() {
    if [ -f "$LOCKFILE" ]; then
        local pid=$(cat "$LOCKFILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "ERROR: Backup already running (PID: $pid)"
            exit 1
        else
            log "Removing stale lock file"
            rm -f "$LOCKFILE"
        fi
    fi
    echo $$ > "$LOCKFILE"
    trap "rm -f $LOCKFILE" EXIT
}

# Release lock
release_lock() {
    rm -f "$LOCKFILE"
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

# Clone or update a repository in master backup directory
# Returns: 0 if changes detected, 1 if no changes, 2 if error
backup_repository() {
    local repo_url="$1"
    local repo_name=$(basename "$repo_url" .git)
    local mirror_path="${MASTER_BACKUP_DIR}/${repo_name}.git"

    log "Processing: $repo_name"

    # Get hash before update (for change detection)
    local hash_before="new_repo"
    if [ -d "$mirror_path" ]; then
        hash_before=$(git -C "$mirror_path" rev-parse --all 2>/dev/null | sha256sum | cut -d' ' -f1)
        if [ $? -ne 0 ]; then
            log "  ⚠ Warning: Could not get git hash, will treat as changed"
            hash_before="error"
        fi
    fi

    # Clone or fetch repository
    if [ -d "$mirror_path" ]; then
        log "  → Fetching updates"
        if ! git -C "$mirror_path" fetch --all --prune 2>&1 | sed 's/^/    /' >&2; then
            log "  ✗ ERROR: Git fetch failed for $repo_name"
            return 2
        fi
    else
        log "  → Cloning mirror (first time)"
        if ! git clone --mirror "$repo_url" "$mirror_path" 2>&1 | sed 's/^/    /' >&2; then
            log "  ✗ ERROR: Git clone failed for $repo_name"
            return 2
        fi
    fi

    # Get hash after update
    local hash_after=$(git -C "$mirror_path" rev-parse --all 2>/dev/null | sha256sum | cut -d' ' -f1)
    if [ $? -ne 0 ]; then
        log "  ⚠ Warning: Could not verify git hash after update"
        hash_after="error"
    fi

    # Detect if changes occurred
    if [ "$hash_before" == "$hash_after" ] && [ "$hash_before" != "error" ]; then
        log "  ✓ No changes detected, skipping sync"
        return 1
    else
        if [ "$hash_before" == "new_repo" ]; then
            log "  ✓ New repository cloned"
        else
            log "  ✓ Changes detected, will sync"
        fi
        return 0
    fi
}

# Sync single repository to USB targets (sequentially)
# Returns: 0 if at least one sync succeeded, 1 if all failed
sync_repo_to_targets() {
    local repo_name="$1"
    local mirror_path="${MASTER_BACKUP_DIR}/${repo_name}.git"
    local sync_success=0

    for target in $BACKUP_TARGETS; do
        if [ ! -d "$target" ]; then
            log "  ⚠ Skipping (not mounted): $target"
            continue
        fi

        log "  → Syncing to: $target"
        mkdir -p "$target/git-backup/mirrors"

        # Sync mirror (always)
        if rsync -a --delete "$mirror_path/" "$target/git-backup/mirrors/${repo_name}.git/" 2>&1 | sed 's/^/    /' >&2; then
            log "    ✓ Mirror synced to $target"
            sync_success=1
        else
            log "    ✗ ERROR: Mirror sync failed to $target"
            continue
        fi

        # Sync working copy (optional)
        if [ "$CREATE_WORKING_COPY" == "true" ]; then
            local working_path="${TMP_DIR}/${repo_name}"
            mkdir -p "$target/git-backup/checkouts"

            # Create working copy if it doesn't exist
            if [ ! -d "$working_path" ]; then
                log "    → Creating working copy"
                if ! git clone "$mirror_path" "$working_path" 2>&1 | sed 's/^/      /' >&2; then
                    log "    ✗ ERROR: Failed to create working copy"
                    continue
                fi
            fi

            # Sync working copy
            if rsync -a --delete "$working_path/" "$target/git-backup/checkouts/${repo_name}/" 2>&1 | sed 's/^/    /' >&2; then
                log "    ✓ Working copy synced to $target"
            else
                log "    ✗ ERROR: Working copy sync failed to $target"
            fi
        fi
    done

    return $((1 - sync_success))
}

# Cleanup temporary working copy (master backup is kept!)
cleanup_repo() {
    local repo_name="$1"
    local working_path="${TMP_DIR}/${repo_name}"

    if [ -d "$working_path" ]; then
        log "  → Cleaning up temporary working copy"
        rm -rf "$working_path"
    fi
}

# Cleanup temporary directory (master backup is kept!)
cleanup_all() {
    if [ -d "$TMP_DIR" ]; then
        log "Cleaning up temporary directory"
        rm -rf "$TMP_DIR"
    fi
    # Note: MASTER_BACKUP_DIR is intentionally NOT cleaned up (persistent storage)
}

# Main execution
main() {
    log "=== GitHub Backup Started ==="

    # Acquire lock
    acquire_lock

    # Check dependencies
    check_dependencies

    # Create master backup directory and temporary directory
    mkdir -p "$MASTER_BACKUP_DIR"
    mkdir -p "$TMP_DIR"

    # Fetch repository list
    repos=$(fetch_repositories)

    if [ -z "$repos" ]; then
        log "No repositories found for user: $GITHUB_USER"
        cleanup_all
        release_lock
        exit 1
    fi

    local repo_count=$(echo "$repos" | wc -l)
    log "Found $repo_count repositories"
    log "Master backup: $MASTER_BACKUP_DIR"
    log "Working copies: $([ "$CREATE_WORKING_COPY" == "true" ] && echo "enabled" || echo "disabled")"
    log ""

    # Process each repository one by one with error handling
    local current=0
    local success_count=0
    local skipped_count=0
    local failed_count=0

    while IFS= read -r repo_url; do
        current=$((current + 1))
        local repo_name=$(basename "$repo_url" .git)

        log "[$current/$repo_count] $repo_name"

        # Backup repository (fetch/clone)
        backup_repository "$repo_url"
        local backup_status=$?

        if [ $backup_status -eq 2 ]; then
            # Error occurred
            log "  ✗ Skipping sync due to backup error"
            failed_count=$((failed_count + 1))
        elif [ $backup_status -eq 1 ]; then
            # No changes detected
            skipped_count=$((skipped_count + 1))
        else
            # Changes detected, sync to USB
            if sync_repo_to_targets "$repo_name"; then
                success_count=$((success_count + 1))
            else
                log "  ⚠ Warning: Sync failed to all targets"
                failed_count=$((failed_count + 1))
            fi
        fi

        # Cleanup temporary files
        cleanup_repo "$repo_name"

        log ""
    done <<< "$repos"

    # Final cleanup
    cleanup_all

    # Release lock
    release_lock

    log "=== GitHub Backup Completed ==="
    log "Statistics:"
    log "  - Total repositories: $repo_count"
    log "  - Synced (with changes): $success_count"
    log "  - Skipped (no changes): $skipped_count"
    log "  - Failed: $failed_count"
    log ""
    log "Master backup location: $MASTER_BACKUP_DIR"
    log "USB backup locations:"
    for target in $BACKUP_TARGETS; do
        if [ -d "$target" ]; then
            log "  - $target/git-backup/mirrors/"
            if [ "$CREATE_WORKING_COPY" == "true" ]; then
                log "  - $target/git-backup/checkouts/"
            fi
        fi
    done
}

# Run main function
main
