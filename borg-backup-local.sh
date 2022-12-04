#!/bin/bash

# Backup multiple sets of folders to multiple dedicated drive sets.
# If you have a set on-line and a set off-line it aoutomatically mounts and backups to the availible set
# Backup set uses a letter.
# Each backup target uses a number.
# first backup set would be 1a and 1b, second set would be 2a and 2b

VERBOSE=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
	case $1 in
		-v|--verbose)
			VERBOSE=1
			shift
			;;
		-d|--dry-run)
			DRY_RUN=1
			shift
			;;
		-*|--*)
			echo "Unknown option $1"
			exit 1
			;;
	esac
done	

#[ $VERBOSE -eq 1 ] && echo "Verbose!"

# Check if the script is already running, exit if it does.
lockfile=/var/run/`basename "$0"`.pid
# Check if lock file exists.
if [ -e $lockfile ]
then
	# If it does print a message and exit.
	echo "There is another instance running or the lock file wasn't removed, exiting."
	exit 8
else
	# Else write this instances PID to the lock file and go on.
	echo $$ > $lockfile
fi

# Load the password.
pw=`cat /etc/borg/password`

status_file=/etc/borg/local-status

# Load base paths.
# /base-dir/prefix- or /base-dir/
backup_base_dir=`cat /etc/borg/local-base-dir`

# Borg command options
if [ $VERBOSE -eq 1 ]; then
       	borg_options="--stats --progress --one-file-system"; else
	borg_options="--one-file-system"
fi

# Backup identifiers and dev path. Allows (normally) automatic mounting and unmounting as they are used.
# Format of /etc/borg/local-targets:
# 1a=/dev/disk/by-uuid/6ddf3a8f-7aad-4a0d-b312-219486f75b63
# 1b=/dev/disk/by-uuid/5551d792-a8b5-40ef-92b2-97ea880c708b

declare -A backup_targets
while IFS== read -r key value; do
	backup_targets[$key]=$value
done < /etc/borg/local-targets

# Array to register complete backup jobs in.
declare -a backups_done

# What to back up to A and B part of the setdeclare -A backup_sets.
# Format of /etc/borg/local-sets:
# a=/home
# b=/ /etc /var
declare -A backup_sets
while IFS== read -r key value; do
	backup_sets[$key]=$value
done < /etc/borg/local-sets

# Specific things you want to exclude per part.
# Format of /etc/borg/local-exclude:
# 0=sh:**/.Trash*
# a=/home/user/temp
# b=/swap.img
declare -A backup_exclude
while IFS== read -r key value; do
	backup_exclude[$key]=$value
done < /etc/borg/local-exclude

# Global variables to be filled by functions
backup_index=""
backup_path=""
dev_path=""
dev_mount=""
dev_ecode=""
backup_name=""

# Get next backup run and set vars
backup_next () {
	# Iterate over backup indentifiers.
	for backup_index in "${!backup_targets[@]}"
	do
		# Path to the mount point for the backup identifier.
		backup_path="${backup_base_dir}${backup_index}/"
		# Check that the backup isn't already done
		if [[ ! " ${backups_done[@]} " =~ " $backup_index " ]]
		then
			# Get the path to the UUID device link.
			dev_path="${backup_targets[${backup_index}]}"
			# Check if the device link exists
			if [ -e $dev_path ]
			then
				# Get the real device listed by mount.
				dev_mount="`readlink -f $dev_path`"
				# Check if the device is mounted with grep exit code
				dev_ecode="`mount|grep -q $dev_mount; echo $?`"
				# This is the next thing to backup
				# All details is stored in global variables, return 0/true and exit the function.
				return 0
				break
			fi
		fi
	done
	# There was no runnable backup jobs, return 1/false and exit.
	# No drives mounted o all jobs finished.
	return 1
}

# Mount a drive and run borg.
backup_do () {
	#Do the backup
	[ $VERBOSE -eq 1 ] && echo Doing backup $backup_index

	#Mount the drive
	if mount $backup_path; then
	#echo -n ""; else
	[ $VERBOSE -eq 1 ] && echo "Mounted $backup_path."; else
	echo "Failed to mount $backup_path!";fi

	#Run borg
	exclude=""
	[ -n "${backup_exclude["*"]}" ] && exclude+=" ${backup_exclude["*"]}"
	[ -n "${backup_exclude[${backup_index: -1}]}" ] && exclude+=" ${backup_exclude[${backup_index: -1}]}"
	exclude=`echo "$exclude"|sed -e 's/ / -e /g'`
	date=`date +%Y-%m-%d`
	day_last=`BORG_PASSPHRASE=$pw borg list ${backup_path}borg | grep $date | cut -d" " -f1 | cut -d'_' -f4 | sort -n | tail -n 1`
	day_index=`expr $day_last + 1`
	backup_name="Backup_${backup_index}_${date}_${day_index}"
	borg_command="borg create $borg_options $exclude ${backup_path}borg::$backup_name ${backup_sets[${backup_index: -1}]}"
	[ $VERBOSE -eq 1 ] && echo "Running: $borg_command"
	[ $DRY_RUN -eq 1 ] && echo "DRY RUN!"
	if [ $DRY_RUN -eq 0 ]; then
	       BORG_PASSPHRASE=$pw $borg_command
	       borg_ecode=$?
	       #echo $borg_ecode
	fi

	#sync, then wait a moment before unmounting
	[ $VERBOSE -eq 1 ] && echo -n "Syncing... "
	sync
	[ $VERBOSE -eq 1 ] && echo "Done!"
	sleep 5
	if umount $backup_path; then
	[ $VERBOSE -eq 1 ] && echo "Unmounted $backup_path."; else
	echo "Failed to unmount $backup_path!";fi

	#Mark as done
	backups_done+=("$backup_index")

	#Log todays date to the status file to later check when the backup was completed last
	if [ $DRY_RUN -eq 0 ]; then
		if [ $borg_ecode -eq 0 ]; then
			echo -e "$(cat $status_file|grep -v $backup_index=)\n$backup_index=$(date +%F)">$status_file
		fi
	fi

	#Blank line between jobs
	[ $VERBOSE -eq 1 ] && echo ""
}

# Backup_next() will exit with 0 as long as there is a backup to run. Info about the job to run is stored in the global variables.
while backup_next
do
	backup_do
done

# Remove the lock file so the script can run again
rm $lockfile
