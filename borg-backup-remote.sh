#!/bin/bash

# Backup multiple sets of folders to a locally mounted drive or over SSH.

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

status_file=/etc/borg/remote-status

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
done < /etc/borg/remote-targets

# Array to register complete backup jobs in.
declare -a backups_done

# What to back up to A and B part of the setdeclare -A backup_sets.
# Format of /etc/borg/local-sets:
# a=/home
# b=/ /etc /var
declare -A backup_sets
while IFS== read -r key value; do
	backup_sets[$key]=$value
done < /etc/borg/remote-sets

# Specific things you want to exclude per part.
# Format of /etc/borg/local-exclude:
# 0=sh:**/.Trash*
# a=/home/user/temp
# b=/swap.img
declare -A backup_exclude
while IFS== read -r key value; do
	backup_exclude[$key]=$value
done < /etc/borg/remote-exclude

# Global variables to be filled by functions
backup_index=""
backup_path=""

# Get next backup run and set vars
backups () {
	# Iterate over backup indentifiers.
	for backup_index in "${!backup_sets[@]}"
	do
		#store borg repos in the order to try them for this set
		declare -a backup_set_targets
		for backup_target in "${!backup_targets[@]}"
		do
			if [ ${backup_target:1} = $backup_index ]; then
				backup_set_targets[${backup_target:0:1}]=${backup_targets[$backup_target]}
			fi
		done
		#parse over the sorted paths for the set
		for target in "${backup_set_targets[@]}"
		do
			backup_path=$target
			#echo $backup_path
			#echo ${backups_done[@]}
			#echo $backup_index
			# Check that the backup isn't already done
			if [[ ! " ${backups_done[@]} " =~ " $backup_index " ]]; then
				[ ${backup_path:0:1} = "/" ] && [ -e $backup_path ] && backup_do
				if [ ${backup_path:0:6} = "ssh://" ]; then
					IFS=/ read -ra up <<< $backup_path
					nc -z ${up[2]} 22 2> /dev/null
					[ $? -eq 0 ] && backup_do
				fi
			fi
		done
	done
	# There was no runnable backup jobs, return 1/false and exit.
	# No drives mounted o all jobs finished.
	return 1
}

# Mount a drive and run borg.
backup_do () {
	#Do the backup
	[ $VERBOSE -eq 1 ] && echo Doing backup $backup_index to $backup_path

	# sudo BORG_RELOCATED_REPO_ACCESS_IS_OK=yes BORG_PASSPHRASE=`sudo cat /etc/borg/password` borg create ssh://remote-local/backup/borg::aurora-etc-221205 /etc

	#Run borg
	exclude=""
	[ -n "${backup_exclude["*"]}" ] && exclude+=" ${backup_exclude["*"]}"
	[ -n "${backup_exclude[${backup_index: -1}]}" ] && exclude+=" ${backup_exclude[${backup_index: -1}]}"
	exclude=`echo "$exclude"|sed -e 's/ / -e /g'`
	date=`date +%Y-%m-%d`
	day_last=`BORG_RELOCATED_REPO_ACCESS_IS_OK=yes BORG_PASSPHRASE=$pw borg list ${backup_path}borg | grep $date | cut -d" " -f1 | cut -d'_' -f4 | sort -n | tail -n 1`
	day_index=`expr $day_last + 1`
	backup_name="Backup_${backup_index}_${date}_${day_index}"
	borg_command="borg create $borg_options $exclude ${backup_path}borg::$backup_name ${backup_sets[${backup_index: -1}]}"
	[ $VERBOSE -eq 1 ] && echo "Running: $borg_command"
	[ $DRY_RUN -eq 1 ] && echo "DRY RUN!"
	if [ $DRY_RUN -eq 0 ]; then
		#BORG_RELOCATED_REPO_ACCESS_IS_OK=yes allows us to access the same repo locally ore remotely without annying questions
		BORG_RELOCATED_REPO_ACCESS_IS_OK=yes BORG_PASSPHRASE=$pw $borg_command
		borg_ecode=$?
		#echo $borg_ecode
	fi

	#Mark as done and log todays date to the status file to later check when the backup was completed last
	if [ $DRY_RUN -eq 0 ]; then
		if [ $borg_ecode -eq 0 ]; then
			backups_done+=("$backup_index")
			echo -e "$(cat $status_file|grep -v $backup_index=)\n$backup_index=$(date +%F)">$status_file
		fi
	fi

	#Blank line between jobs
	[ $VERBOSE -eq 1 ] && echo ""
}

# Backup_next() will exit with 0 as long as there is a backup to run. Info about the job to run is stored in the global variables.
while backups; do
	echo > /dev/null
done

# Remove the lock file so the script can run again
rm $lockfile
