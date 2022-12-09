#!/bin/bash

VERBOSE=0

while [[ $# -gt 0 ]]; do
	case $1 in
		-v|--verbose)
			VERBOSE=1
			shift
			;;
		-*|--*)
			echo "Unknown option $1"
			exit 1
			;;
	esac
done

# function to figure out how many days old a backup is
get_age() {
	declare -i days
	days=($(date +%s)-$(date +%s -d $1))/86400
	echo $days
	return 0
}

# Load status of local backups
declare -A status_local
while IFS== read -r key value; do
	status_local[$key]=$value
done <<< $(cat /etc/borg/local-status | grep --invert-match -e "^$")

# Backup sets, a,b,c etc
declare -A sets_local
for key in "${!status_local[@]}"
do
	sets_local[${key: -1}]=1
done

# Load status of remote backups
declare -A status_remote
while IFS== read -r key value; do
	status_remote[$key]=$value
done <<< $(cat /etc/borg/remote-status | grep --invert-match -e "^$")

# Load limits of how old is OK from file
declare -A limits
while IFS== read -r key value; do
	limits[$key]=$value
done <<< $(cat /etc/borg/status-limits | grep --invert-match -e "^$")

declare -A props_local
# Iterate over local backups
for key in "${!status_local[@]}"
do
	# last date the backup was completed
	last_date=${status_local[$key]}

	# check and store the age of backup in days
	age=$(get_age "$last_date")
	props_local[${key}_age]=$age

	# check if it's older than the min date
	if [[ $age -gt ${limits[local_min]} ]]
		then props_local[${key}_min_old]=1
		else props_local[${key}_min_old]=0; sets_local[${key: -1}]=0 #also clear the 1 for the set, that way we know one of the backups is fresh
	fi

	# check if it's older than the max date
	if [[ $age -gt ${limits[local_max]} ]]
		then props_local[${key}_max_old]=1
		else props_local[${key}_max_old]=0
	fi

	# set the min age of every set
	if [[ $age -lt ${props_local[${key: -1}_min_age]} ]] || [[ -z ${props_local[${key: -1}_min_age]} ]]
		then props_local[${key: -1}_min_age]=$age
	fi
done

# Iterate over remote backup sets
declare -A props_remote
for key in "${!status_remote[@]}"
do
	# last date the backup was completed
	last_date=${status_remote[$key]}

	# check and store the age of backup in days
	age=$(get_age "$last_date")
	props_remote[${key}_age]=$age

	# check if it's older than the limit
	if [[ $age -gt ${limits[remote]} ]]
	        then props_remote[${key}_old]=1
	        else props_remote[${key}_old]=0
	fi

done

#Print out remote sets older than the limit
for key in "${!status_remote[@]}"
do
	[ ${props_remote[${key}_old]} -eq 1 ] && echo "Remote backup set $key haven't completed recently! It's ${props_remote[${key}_age]} days old."
done

# Print out local sets where all copies are older than min age
for key in "${!sets_local[@]}"
do
	if [ ${sets_local[$key]} -eq 1 ]
		then echo "No backup instances of local set $key have completed recently! The freshest instance is ${props_local[${key}_min_age]} days old."
	fi
done

# Print instances of local sets older than max age
for key in "${!status_local[@]}"
do
	if [ ${props_local[${key}_max_old]} -eq 1 ]
		then echo "Backup instace $key of local set ${key: -1} is older than the max age! It's ${props_local[${key}_age]} days old."
	fi
done

# Print age of all backups if verbose.
if [ $VERBOSE -eq 1 ]; then
	echo ""
	# Remote backups
	for key in "${!status_remote[@]}"
	do
        	echo "Remote backup set $key is ${props_remote[${key}_age]} days old."
	done
	# Local backups
	for key in "${!status_local[@]}"
	do
		echo "Local backup $key is ${props_local[${key}_age]} days old."
	done
fi

