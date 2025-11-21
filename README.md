# git-backup

Simple Bash script to backup GitHub repositories to USB drives. Designed to run on Raspberry Pi.

## Features

- **Incremental backups**: Only fetches new commits instead of re-cloning entire repos
- **Smart skip logic**: Automatically skips repos without changes (saves time and bandwidth)
- **Master backup on Pi**: Persistent storage for faster updates, USB drives are replicas
- **Dual backup format**: Mirror (git database) + optional working copy (browsable files)
- **Robust error handling**: Continues backing up other repos if one fails
- **Lock mechanism**: Prevents concurrent runs from conflicting
- **Sequential USB sync**: Safe, controlled syncing to multiple drives
- **Configurable**: Optional working copies, custom paths via `config.env`

## Requirements

- Bash
- git
- curl
- jq
- rsync

Install on Raspberry Pi:
```bash
sudo apt update
sudo apt install git curl jq rsync
```

## Setup

1. Clone this repository:
```bash
git clone https://github.com/rickvanderwolk/git-backup.git
cd git-backup
```

2. Create configuration file:
```bash
cp config.env.example config.env
nano config.env
```

3. Edit `config.env`:
   - Set `GITHUB_USER` to your GitHub username
   - Set `BACKUP_TARGETS` to your USB mount points (e.g., `/mnt/usb1 /mnt/usb2`)
   - Set `MASTER_BACKUP_DIR` (default: `/home/pi/git-backup-master`)
   - Set `CREATE_WORKING_COPY` to `true` or `false` (default: `false`)
     - `false` = Only mirrors (compact, ~50% less space)
     - `true` = Mirrors + browsable files on USB
   - Optionally set `GITHUB_TOKEN` for private repos and higher rate limits

4. Mount your USB drive(s):
```bash
# Find your USB device
lsblk

# Create mount point if needed
sudo mkdir -p /mnt/usb1

# Mount the drive (example for /dev/sda1)
sudo mount /dev/sda1 /mnt/usb1

# Auto-mount on boot (optional): add to /etc/fstab
# /dev/sda1 /mnt/usb1 ext4 defaults 0 2
```

## Usage

Run the backup script:
```bash
./backup.sh
```

The script uses incremental backups for efficiency:

**First run:**
1. Fetch list of your public repositories
2. For each repo:
   - Clone mirror to master backup on Pi: `/home/pi/git-backup-master/repo.git/`
   - Sync mirror to mounted USB drives: `/mnt/usb1/git-backup/mirrors/repo.git/`
   - Optionally create and sync working copy (if `CREATE_WORKING_COPY=true`)
3. Master backup persists on Pi for next run

**Subsequent runs (much faster!):**
1. Fetch list of repositories
2. For each repo:
   - Fetch new commits into existing master backup (only downloads changes)
   - Compare git hashes: if unchanged, skip entirely ⚡
   - If changed, sync updated mirror to USB drives
   - Clean up temporary files
3. Master backup remains on Pi, continuously updated

## Automated Backups with Cron

Edit crontab:
```bash
crontab -e
```

Add one of these lines:

```bash
# Daily at 2:00 AM
0 2 * * * /home/pi/git-backup/backup.sh >> /home/pi/git-backup/backup.log 2>&1

# Weekly on Sunday at 2:00 AM
0 2 * * 0 /home/pi/git-backup/backup.sh >> /home/pi/git-backup/backup.log 2>&1

# Monthly on the 1st at 2:00 AM
0 2 1 * * /home/pi/git-backup/backup.sh >> /home/pi/git-backup/backup.log 2>&1
```

## Directory Structure

After running, your system will contain:

**Pi Master Backup (persistent):**
```
/home/pi/git-backup-master/
├── repo1.git/              # Bare mirror (git database)
│   ├── HEAD
│   ├── refs/
│   └── objects/
├── repo2.git/
└── ...
```

**USB Drives (replicas):**
```
/mnt/usb1/git-backup/
├── mirrors/
│   ├── repo1.git/          # Synced from Pi master
│   ├── repo2.git/
│   └── ...
└── checkouts/              # Only if CREATE_WORKING_COPY=true
    ├── repo1/              # Working copy (browsable files)
    │   ├── README.md
    │   ├── src/
    │   └── ...
    ├── repo2/
    └── ...
```

- **Master on Pi**: Persistent backup, updated incrementally
- **Mirrors**: Complete git database for restoring
- **Checkouts** (optional): Browse files, read code directly

## Restoring a Repository

### Option 1: Clone from USB mirror
```bash
# Clone from bare mirror (always available)
git clone /mnt/usb1/git-backup/mirrors/repo-name.git ~/restored-repo
```

### Option 2: Clone from Pi master
```bash
# Clone from master backup on Pi
git clone /home/pi/git-backup-master/repo-name.git ~/restored-repo
```

### Option 3: Copy working files directly (if enabled)
```bash
# Only works if CREATE_WORKING_COPY=true
cp -r /mnt/usb1/git-backup/checkouts/repo-name ~/restored-repo
cd ~/restored-repo
# All files are there, including .git folder
```

### Option 4: Push to new GitHub repo
```bash
# Push mirror to new remote
cd /mnt/usb1/git-backup/mirrors/repo-name.git
git push --mirror https://github.com/username/new-repo.git
```

## Performance

The incremental backup system significantly reduces backup time and bandwidth:

**Example scenario: 50 repositories, 5 receive updates**

| Metric | First Run | Subsequent Runs |
|--------|-----------|-----------------|
| Repos cloned | 50 | 0 |
| Repos fetched | 0 | 50 |
| Repos skipped | 0 | 45 (no changes) |
| Repos synced | 50 | 5 (only changed) |
| Time | ~30 minutes | ~5 minutes |
| Bandwidth | Full repo size | Only new commits |

**Benefits:**
- ✅ 80-90% faster on subsequent runs
- ✅ Minimal bandwidth usage (only deltas)
- ✅ Safe: errors in one repo don't stop others
- ✅ Persistent master backup survives crashes/reboots
- ✅ Lock prevents multiple runs from conflicting

## Troubleshooting

**Script fails with "config.env not found"**
- Copy `config.env.example` to `config.env` and configure it

**"Missing dependencies" error**
- Install required packages: `sudo apt install git curl jq rsync`

**"No repositories found"**
- Check your GitHub username in `config.env`
- Verify you have public repositories

**USB target skipped**
- Ensure USB drive is mounted
- Check mount point matches `BACKUP_TARGETS` in config

**Rate limit errors**
- Without token: 60 requests/hour
- Add `GITHUB_TOKEN` in config for 5000 requests/hour
