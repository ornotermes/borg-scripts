#!/bin/bash

# Some times my local backup disks gets locked mounted by NFS, don't know how and why. This is an example on how to unlock them

# Load base paths.
# /base-dir/prefix- or /base-dir/
backup_base_dir=`cat /etc/borg/local-base-dir`

# Load list of devices
declare -A backup_targets
while IFS== read -r key value; do
	        backup_targets[$key]=$value
	done < /etc/borg/local-targets

# Shutdown NFS server
echo "Stopping NFS"
sudo service nfs-server stop

# Parse over the targets
for index in "${!backup_targets[@]}"
do
	dev_path=${backup_targets[${index}]}
	echo "Checking $index at $dev_path"
	if [ -e $dev_path ]
	then
		mount_dev=`readlink -f ${backup_targets[$index]}`
		backup_path="${backup_base_dir}${index}/"
		echo "Unmounting $backup_path on $mount_dev"
		# Unmount folder
		sudo umount $backup_path
	fi
done

echo "Starting NFS"
# Start NFS again
sudo service nfs-server start

echo "Exporting ZFS shares"
# Share the NFS mounts again
sudo zfs share -a nfs
