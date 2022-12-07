# borg-backup-remote.sh

This is a script to backup to multiple sets to a mounted folder or remotely over SSH.

It's designed to support running multiple backups, each backuping against a possibly moving target.

It will look for an avalible backup target for all sets in order and backup to the forst availible one, it could be internal disk first, then on-site SSH, then off-site SSH.

## How I use this
I have not put this in to use quite yet, but my tests over SSH have worked so far.

## Running as root
I run this script as root as it gets access to everything, you might be able to get it to work as a user if you create a dedicated user that's member of pretty much all groups, but I have not tested this. Some files might not even be readable by it's group and would not be able to back those up, but that could be useful if used wisely.

## Configuration
You need to create a few files with configuration for this script, they support no comments or quoted paths at this time, don't leave any blank lines, just rows of "key=value". If you have spaces in paths, try escaping them as i havn't tested this.

The backup sets are denoted by letters, each set can have a set of folders to backup, you can exlude paths from all sets or specific sets, and you can set up multiple ways to backup each set, they have a number followed by a letter for the set, like 1a, 2a, 3a for example.

### /etc/borg/password
Contains a plain text password shared among all your backups, this is used to encrypt the backups so your data is safe if someone gets their grubby mits on one of your backup drives. I don't see a strong reason to use different passwords, one good password should be enough.
```
your_secret_password_for_archive_keys
```

### /etc/borg/local-sets
Defines what folders to include in the backup set. This script has the ```--one-file-system``` option to not traverse partitions, it's a preference for me and makes backuping to multiple sets easier, but you need to be a bit more specific.
In the example below it's set to just have an a-backup set.
```
a=/ /home/ /var/ /srv/ /boot/ /boot/efi/ /etc/
```

### /etc/borg/local-exclude
Things we don't want to include in the backups. The \*-line is appended to all sets, then you can add thicns to just one set.
In the example below we exclude .Trash* (any trash folder) and /swap.img from all sets.
You can find more about exclusion patterns here: <https://borgbackup.readthedocs.io/en/stable/usage/help.html>
```
*=sh:**/.Trash* /swap.img
```
### /etc/borg/local-targets
Maps a backup to a block device, preferrably by UUID.If you would want a 3rd copy of the /home/ you would add a line for 3a, for example.
```
1a=/backup/remote/
2a=ssh://remote-local/backup/
3a=ssh://remote-offsite/backup/
```

## Preparations
You have different options for this, but let's assume you put the disk in the machine locally for the initial backup.
Make sure the SSH server is installed and running on the remote machine, and install BorgBackup.
You will have your regular user account as well as a special account for borg. For the best security you should disable password logins on the remote system, if that's not an option at least use fail2ban and use secure passwords not stored in case systems gets compromised.

### Init repo loally
We assume the backup drive is already locally monted on /backup/remote/ on the machine we want to backup.

When intiating the repo there is a few options. Like if you want encryption, authentication or even no security. You can also select if you want the encryption key in the repos folder or on the system you're backuping from.

By using ```--encyption=repokey``` or ```--encryption=repokey-blake2``` you have an encytion key in the repo folder (for a less trusted system you might want one of the ```--ecryption=keyfile``` options), depending on your CPU one or the other might be faster. Read more: <https://borgbackup.readthedocs.io/en/stable/usage/init.html>

The actual repo is created on /backup/remote/borg/, not /backup/remote/ in case you want to have other things as well on the disk.

To later extract data from your encrypted backups you will need 3 parts. The backup repo, encryption key, and password. Backup your password and encryption keys in multiple secure places. See <https://borgbackup.readthedocs.io/en/stable/usage/key.html#borg-key-export>
```
sudo BORG_PASSPHRASE=`sudo cat /etc/borg/password` borg init --encryption=repokey /backup/remote/borg/
sudo BORG_PASSPHRASE=`sudo cat /etc/borg/password` borg export /backup/remote/borg/ /media/usb-drive/borg-repo-key-backup-1a.txt
```

### Do an initial backup locally
This will be a quite slow step if you have a lot of data, but it should be faster locally than over LAN, and for sure faster than over internet. We start by doing a dry run to check that the command line looks good, then we run the backup.
```
sudo /opt/borg-scripts/borg-backup-remote.sh -v -d
sudo /opt/borg-scripts/borg-backup-remote.sh -v
```
You can prepare som things on the remote host while the backup is running.

### Create user account on the remote host
This user should be setup to only be able to use borg, you don't want someone to be able to connect and delete the repo manually.
The password will be used for setting up public key authentication, if you do it manually you can skip the password. If you can't disable password logins for SSH completely, at least clear the password when you're done.
```
sudo useradd -m borg
sudo passwd borg
```

### Set up SSH on the local machine
Generate an SSH key for root on the local machine for when it connects as borg on the remote machine.
Do not use a password as you want to use it for automatic backups.
```
sudo ssh-keygen -t ed25519 -f /root/.ssh/borg-remote-client.key
```

Then transfer the key to the remote server.
```
sudo ssh-copy-id -i /root/.ssh/borg-remote-client.pub borg@remote-local
```

Lastly configure root to use your new key when connecting to the remote host
```
sudo vim /root/.ssh/config
```

You might have one hostname to connect to your remote host over LAN and a different on connecting over internet. This allows the script to test them in order, because this the ```Host``` and ```HostName``` in config should be the same. The script only supports port 22 currently.
```
Host remote-local
        HostName remote-local
        User borg
        PubKeyAuthentication yes
        IdentityFile /root/.ssh/borg-remote-client.key

Host remote-offsite
        HostName remote-offsite
        User borg
        PubKeyAuthentication yes
        IdentityFile /root/.ssh/borg-remote-client.key
```

### Set up SSH for administration of the remote host on a machine of your choise
You could use the same machine you're backing up for the admin account but it makes it harder for a hacker if it is on another machine, like a laptop. Either way use a unique and strong password.
```
ssh-keygen  -t ed25519 -f ~/.ssh/borg-renote-admin
ssh-copy-id -i ~/.ssh/borg-remote-admin.pub <admin-user>@<remote-host>
```

Similar to above you could change your SSH-config to make it easy to connect.
```
editor ~/.ssh/config
```
```
Host remote-local-admin
        HostName remote-local
        User <admin-user>
        PubKeyAuthentication yes
        IdentityFile ~/.ssh/borg-remote-admin.key

Host remote-offsite-admin
        HostName remote-offsite
        User <admin-user>
        PubKeyAuthentication yes
        IdentityFile ~/.ssh/borg-remote-admin.key
```

### Disable password login on the remote host
Now you have SSH key logins for both your borg and admin account. It should now be fine to disable SSH password logins. Make sure you can access the server by some other way in case you mess something up.
```
sudoedit /etc/ssh/sshd_config
```
Change ```PasswordAuthentication yes``` to ```PasswordAuthentication no```.

Then restart SSH.
```
sudo service ssh restart
```

### Limit what the borg account on the remote host can do
We can limit what the borg account can do when loggin in with the key. Start by connecting as an admin.
```
ssh remote-local-admin
sudoedit /home/borg/.ssh/authorized_keys
```
There should be one line ```ssh-ed25519 ...```, we need to add some rules to the beginning of that line. It should be changed to:
```
restrict,command="borg serve --append-only --restrict-to-repository /backup/borg" ssh-ed25519 ...
```
That means when you connect with that public key, it ```restrict``` limits SSH features like tunneling, and ```command=``` makes it ignores what command you send, it can only execute the supplied command. So the borg user should only be able to login by key, and that key can only run the borg serve.

Borg serve have some restrictions as well, ```--append-only``` means the SSH client can't immideatly destry backups, they can only be marked for deletion... you need to delete them with your admin account. See more at <https://borgbackup.readthedocs.io/en/stable/usage/notes.html#append-only-mode>.

```--restrict-to-repository``` will only allow borg to use that repo. You could use different SSH-keys for different repos. That way an attacker shouldn't be able to get to files from other systems. But don't take it as an absolute.

## Usage
The command have these options:
```-d | --dry-run``` to run the script except it doesn't run the borg command or update the dates in /etc/borg/local-status.

```-v | --verbose``` to output more messages about what's going one, as well as running borg with ```--progress --one-file-system``` so you can tell what is going on.

After changing any configs you should run this to see that it mounts and unmounts, and the borg command looks sensible.
```
sudo /opt/borg-scripts/borg-backup-remote.sh -v -d
```

When you run the script manually, especially sharp for the forst time you probably want to run in verbose to see the progress... as it might be very slow.
```
sudo /opt/borg-scripts/borg-backup-remote.sh -v
```

If you set it up to run automatically with cron, use no option and it should be quiet if there is no problems, this is handy if you set up your server to send you emails.
```
sudo /opt/borg-scripts/borg-backup-remote.sh
```
### /etc/cron.d/borg-backup-remote
This is an example that will run your backup to the remote host every evening at 20:00. Make sure to set up your computers for e-mail so you find out if there is a problem.
```
# /etc/cron.d/borg-backup-remote
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

00 20 * * * root /opt/borg-scripts/borg-backup-remote.sh
```

### Generated files

#### /run/borg-backup-remote.sh.pid
Is used as a lockfile, prevents multiple copies of the script to run at the same time. Contains the PID of the script. If the script is interrupted you might have to remove it manually.
```
sudo rm /run/borg-backup-remote.sh.pid
```

#### /etc/borg/remote-status
Contains the dates of when each backup target was last completed, could be used to script a reminder to manually run backups it that's how you want to do it, or swap disks because your offline set is pretty old.
