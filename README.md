# git-backup

Simple Bash script to backup GitHub repositories to USB drives. Designed to run on Raspberry Pi.

## Features

- Backs up all public GitHub repositories
- Uses `git clone --mirror` for complete repository copies
- Incremental updates (only fetches new commits on subsequent runs)
- Syncs to multiple USB drives automatically
- Temporary local storage during backup, then cleaned up
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
   - Set `BACKUP_TARGETS` to your USB mount points (space-separated)
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

The script will:
1. Fetch list of your public repositories
2. Clone/update each repository to `/tmp/git-backup/`
3. Sync to all mounted USB drives specified in `BACKUP_TARGETS`
4. Clean up temporary directory

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
/mnt/usb1/git-backup/
├── repo1.git/
├── repo2.git/
└── repo3.git/
```

Each `.git` directory is a complete mirror that can be updated incrementally.

## Restoring a Repository

To restore a repository from backup:
```bash
# Clone from backup
git clone /mnt/usb1/git-backup/repo-name.git

# Or push to a new remote
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

## License

MIT
