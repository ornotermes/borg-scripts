# borg-backup-local.sh

This is a script to backup to multiple sets of localy attached hard drives.

It's designed to support running multiple backups, that way you could use a pile of older, smaller harddrives to distribute your backups to (but you could use it with just one set).

## How I use this
Personally I use it with hard drives split in to two sets with two copies each. 1a+1b and 2a+2b.

I have only one of the copies connected at a time, if 1a and 1b is connected and online 2a and 2b is disconnected and offline. 

By regularly swapping the disks it's managable to maintain a relatively recent off-line backup.

## Running as root
I run this script as root as it gets access to everything, you might be able to get it to work as a user if you create a dedicated user that's member of pretty much all groups, but I have not tested this. Some files might not even be readable by it's group and would not be able to back those up, but that could be useful if used wisely.

## Configuration
You need to create a few files with configuration for this script, they support no comments or quoted paths at this time, don't leave any blank lines, just rows of "key=value". If you have spaces in paths, try escaping them as i havn't tested this.

The backup sets are denoted by letters, each set can have a set of folders to backup, you can exlude paths from all sets or specific sets, and you can set up multiple harddrives to backup each set to, they have a number followed by a letter for the set, like 1a, 1b, 2a, 2b.

### Mounting
This script assumes the drives are set up in /etc/fstab to not auto mount, it will mount drives, run the backup then unmount the drives again. This means that under normal conditions you should be able to just pull a drive whenever a backup is not running, but check that's it's unmounted just to be sure.

#### /etc/fstab
Here is example lines for 4 disks
```
/dev/disk/by-uuid/6ddf3a8f-7aad-4a0d-b312-219486f75b63  /backup/1a ext4 noauto,defaults 0 0
/dev/disk/by-uuid/5551d792-a8b5-40ef-92b2-97ea880c708b  /backup/1b ext4 noauto,defaults 0 0
/dev/disk/by-uuid/28b60aed-2ce8-428c-94e4-69e31f986b50  /backup/2a ext4 noauto,defaults 0 0
/dev/disk/by-uuid/62a96444-9983-4a0e-b85a-5c57bb694ccb  /backup/2b ext4 noauto,defaults 0 0
```

### /etc/borg/password
See [a README.md](README.md#generate-and-use-a-password-file).

### /etc/borg/local-base-dir
Base path for your backup mount points. Could be for example ```/backup/``` for it to use /backup/1a for that job, or ```/backup-``` to use /backup-1a/.

### /etc/borg/local-sets
Defines what folders to include in the backup set. This script has the ```--one-file-system``` option to net traverse partitions, it's a preference for me and makes backuping to multiple sets easier, but you need to be a bit more specific.
In the example below the a-set backups /home, and the b-set backups pretty much the rest of a normal system.
```
a=/home/
b=/ /var/ /srv/ /boot/ /boot/efi/ /etc/
```

### /etc/borg/local-exclude
Things we don't want to include in the backups. The \*-line is appended to all sets, then you can add thicns to just one set.
In the example below we exclude .Trash* (any trash folder) from all sets, and /swap.img from the b-set that backups /.
You can find more about exclusion patterns here: <https://borgbackup.readthedocs.io/en/stable/usage/help.html>
```
*=sh:**/.Trash*
b=/swap.img
```
### /etc/borg/local-targets
Maps a backup to a block device, preferrably by UUID.If you would want a 3rd copy of the /home/ you would add a line for 3a, for example.
```
1a=/dev/disk/by-uuid/6ddf3a8f-7aad-4a0d-b312-219486f75b63
1b=/dev/disk/by-uuid/5551d792-a8b5-40ef-92b2-97ea880c708b
2a=/dev/disk/by-uuid/28b60aed-2ce8-428c-94e4-69e31f986b50
2b=/dev/disk/by-uuid/62a96444-9983-4a0e-b85a-5c57bb694ccb
```

## Preparations
If you havn't made the directories for the mounts do it now.
```
sudo mkdir -pv /backup/{1,2}{a,b}
```
Mount each drive, initiate the borg repo and then unmount.

When intiating there is a few options. Like if you want encryption, authentication or even no security. You can also select if you want the encryption key in the repos folder or on the system you're backuping from.

By using ```--encyption=repokey``` or ```--encryption=repokey-blake2``` you have an encytion key in the repo folder (for a less trusted system you might want one of the ```--ecryption=keyfile``` options), depending on your CPU one or the other might be faster. Read more: <https://borgbackup.readthedocs.io/en/stable/usage/init.html>

To later extract data from your encrypted backups you will need 3 parts. The backup repo, encryption key, and password. Backup your password and encryption keys in multiple secure places. See <https://borgbackup.readthedocs.io/en/stable/usage/key.html#borg-key-export>
```
sudo mount /backup/1a/
sudo BORG_PASSPHRASE=`sudo cat /etc/borg/password` borg init --encryption=repokey /backup/1a/borg/
sudo BORG_PASSPHRASE=`sudo cat /etc/borg/password` borg export /backup/1a/borg/ /media/usb-drive/borg-repo-key-backup-1a.txt
sudo umount /backup/1a/
```

## Usage
The command have these options:
```-d | --dry-run``` to run the script except it doesn't run the borg command or update the dates in /etc/borg/local-status.

```-v | --verbose``` to output more messages about what's going one, as well as running borg with ```--progress --one-file-system``` so you can tell what is going on.

After changing any configs you should run this to see that it mounts and unmounts, and the borg command looks sensible.
```
sudo /opt/borg-scripts/borg-backup-local.sh -v -d
```

When you run the script manually, especially sharp for the forst time you probably want to run in verbose to see the progress... as it might be very slow.
```
sudo /opt/borg-scripts/borg-backup-local.sh -v
```

If you set it up to run automatically with cron, use no option and it should be quiet if there is no problems, this is handy if you set up your server to send you emails.
```
sudo /opt/borg-scripts/borg-backup-local.sh
```
### /etc/cron.d/borg-backup-local
This is an example that will run your backup to hard drives every night at 02:00. Make sure to set up your computers for e-mail so you find out if there is a problem.
```
# /etc/cron.d/borg-backup-local
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

00 02 * * * root /opt/borg-scripts/borg-backup-local.sh
```

### Generated files

#### /run/borg-backup-local.sh.pid
Is used as a lockfile, prevents multiple copies of the script to run at the same time. Contains the PID of the script. If the script is interrupted you might have to remove it manually.
```
sudo rm /run/borg-backup-local.sh.pid
```

#### /etc/borg/local-status
Contains the dates of when each backup target was last completed, could be used to script a reminder to manually run backups it that's how you want to do it, or swap disks because your offline set is pretty old.
