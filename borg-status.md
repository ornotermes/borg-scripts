# borg-backup-local.sh

This is a script to check how old the backups are.

## How I use this
This i a fresh script but i run it with cron to make sure there is no major issues with backups.

## Running as root
As long as the status files exists and is readable this script runs fine as a user.

## Configuration
It currently presumes both status files exists. If you don't use both remote and local backup scripts you should create the status files:
```
sudo touch /etc/borg/{remote,local}-status
```

### /etc/borg/status-limits
This sets limits for how many days old you want backups to be before the script tell you about them.
```remote``` sets the age limit for all remote backups.
Local backups have two settings: No backup should be older than ```local_max```, and at least one backup shouldn't be older than ```local_min```.
```
local_min=3
local_max=45
remote=7
```

## Usage
The command have these options:
```-v | --verbose``` After the script lists old backups, it will also list all backups and how old they are in days.  

If you set it up to run automatically with cron, use no option and it should be quiet if there is no problems, this is handy if you set up your server to send you emails.
```
/opt/borg-scripts/borg-status.sh
```
### /etc/cron.d/borg-status
This is an example that will run your backup to hard drives every night at 02:00. Make sure to set up your computers for e-mail so you find out if there is a problem.
```
# /etc/cron.d/borg-status
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

0 12 * * * root /opt/borg-scripts/borg-status.sh
```
