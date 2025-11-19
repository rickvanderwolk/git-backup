# git-backup

Simple Bash script to backup GitHub repositories to USB drives. Designed to run on Raspberry Pi.

## Features

- Backs up all public GitHub repositories
- Creates both mirror (git database) and working copy (browsable files)
- Processes repositories one-by-one to minimize temporary storage usage
- Syncs to multiple USB drives automatically
- Temporary local storage during backup, then cleaned up per repo
- Simple configuration via `config.env`

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
   - Script will create a `git-backup/` subdirectory in each target
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

The script will process each repository one-by-one:
1. Fetch list of your public repositories
2. For each repo:
   - Clone mirror (bare repository) to `/tmp/git-backup/repo.git/`
   - Clone working copy (with files) to `/tmp/git-backup/repo/`
   - Sync both to all mounted USB drives
   - Clean up that repo from `/tmp/`
3. Repeat for next repository

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

After running, your USB drives will contain:
```
/mnt/usb1/
└── git-backup/
    ├── repo1/              # Working copy (browsable files)
    │   ├── README.md
    │   ├── src/
    │   └── ...
    ├── repo1.git/          # Bare mirror (git database)
    │   ├── HEAD
    │   ├── refs/
    │   └── objects/
    ├── repo2/
    ├── repo2.git/
    └── ...
```

- **Working copy** (`repo/`): Browse files, read code directly
- **Bare mirror** (`repo.git/`): Complete git database for restoring

## Restoring a Repository

### Option 1: Copy working files directly
```bash
# Simply copy the folder
cp -r /mnt/usb1/git-backup/repo-name ~/restored-repo
cd ~/restored-repo
# All files are there, including .git folder
```

### Option 2: Clone from mirror
```bash
# Clone from bare mirror
git clone /mnt/usb1/git-backup/repo-name.git ~/restored-repo
```

### Option 3: Push to new GitHub repo
```bash
# Push mirror to new remote
cd /mnt/usb1/git-backup/repo-name.git
git push --mirror https://github.com/username/new-repo.git
```

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
