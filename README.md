# borg-scripts
BorgBackup scripts

Some scripts and guides on how to set them up to help you make good use of BorgBackup, especially on servers.

# Generate and use a password file
To help you use encrypted backups automatically you can store the pass-word/phrase in a file, i use the same password for all repos on one system.

Generate a password file:
```
sudo mkdir /etc/borg
openssl rand -base64 32 | sudo tee /etc/borg/password > /dev/null
sudo chmod 600 /etc/borg/password
```

To use the password when running borg:
```
BORG_PASSPHRASE=`sudo cat /etc/borg/password` borg ...
```

# sudoedit
I some times mention the command ```sudoedit```, it runs an editor of your choice as root/sudo. I don't know it it's universal but just substitute it for ```sudo nano``` if you don't know what to do.
If you want ```sudoedit``` to use another editor:
```sudo update-alternatives --config editor```

# Let your computer(s) talk to you
By enabling outgoing emails you can get information about events in your computer(s), like if a raid fails or a cron script isn't working as expected. As many of us don't host our own mailserver we might want to set up a service to send email for us.

## Gmail + sSMTP
sSMTP makes it possible to send email with a regular email account like Gmail.

### On Gmail
1. Create a new account just for this. If you use your regular one you could expose your self to password recovery attacks.
2. Go to <myaccount.google.com/apppasswords>.
3. Select E-mail and Other in the drop down menus. Enter "ssmtp <hostname>" so you remember what the password is for.
4. Click CREATE
5. Copy the password and jump over to the ssmtp config section.
6. When sSMTP is ocnfigured and tested you can click done.

### Configure sSMTP
1. Install ssmtp from your package manager ```sudo apt install ssmtp```.
2. Edit the ssmtp congig ```sudoedit /etc/ssmtp/ssmtp.conf```.
3. Enter this:
```
root=<personal.email@example.com>
mailhub=smtp.gmail.com:587
hostname=<hostname.example.com>
FromLineOverride=NO
AuthUser=<server.email>@gmail.com
AuthPass=<app password>
UseTLS=Yes
UseSTARTTLS=Yes
```
4. Check that it's working by running ```echo -e "Subject: Test mail\n\nThis is only a test." | sendmail root```

## Make sure email works
Usually everything is fine and you get no email, but set up a weekly mail test just so you know it's fine. If email have failed and not let you know that your backups isn't working and your raid have failed drives , you will feel really sorry for your self.

```crontab -e```
```
MAILTO="<personal.email@example.com>"
00 12 * * 0     echo "Weekly mail test!"
```

# Scripts included

## [borg-backup-local.sh](borg-backup-local.md)
Backup to local block devices that's normally sits unmounted, like a hot-swappable harddrive or USB drive.
See <borg-backup-local.md>

## [borg-backup-remote.sh](borg-backup-remote.md)
Backup to an already mounted disk, or to a remote host over SSH, it can try to find a drive locally before trying SSH.
See <borg-backup-remote.md>

## [borg-status.sh](borg-status.md)
Make sure the backups isn't too old, it will tell you what backups is older than the set limits.
