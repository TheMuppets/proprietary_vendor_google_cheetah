#!/vendor/bin/sh
#
# This script is for storage related init service including the below
#  - adjusting storage total size to the nearest power of 2.
#  - adjusting reserved_segments with 12 x {zone size} for ZUFS.
#  - Under 128GB devices, halve the value of logd.logpersistd.size
#  - adjusting max_sectors_kb for rootdisk and zoned_device
#

ufs_size_prop="ro.boot.hardware.ufs"
logpersistd_size_prop="logd.logpersistd.size"

ufs_size_str=`getprop "ro.boot.hardware.ufs"`
ufs_size=`echo "$ufs_size_str" | sed 's/[^0-9].*//'`
block_size=`getprop "ro.boot.hardware.cpu.pagesize"`

sysfs_userdata="/dev/sys/fs/by-name/userdata"

if [[ -z "$ufs_size" || -z "$block_size" ]]; then
	exit 1
fi

# Function to find the nearest LOWER power of 2 (make number 1000 from 1024)
nearest_lower_power_of_2() {
	local num=$1
	local power

	if [[ "$num" -le 0 ]]; then
		return 1
	fi

	if [[ "$num" -ge 1000 ]]; then
		power=1000
	else
		power=1
	fi

	while [[ "$((power * 2))" -le "$num" ]]; do
		power=$((power * 2))
	done

	echo "$power"
	return 0
}

diff_from_nearest_lower_power_of_2() {
	local num=$1
	local lower_power=$(nearest_lower_power_of_2 "$num")

	if [[ $? -ne 0 ]]; then
		return 1
	fi

	local twenty_percent=$((lower_power / 5))

	if [[ "$((num - lower_power))" -le "$twenty_percent" ]]; then
		local difference=$((num - lower_power))
		echo "$difference"
		return 0
	else
		return 1
	fi
}

# Function to adjust max_sectors_kb if it's larger than optimal_io_size
adjust_max_sectors() {
	local dev=$1
	local max_sectors_kb_path="/sys/block/$dev/queue/max_sectors_kb"
	local optimal_io_size_path="/sys/block/$dev/queue/optimal_io_size"

	if [[ ! -f "$max_sectors_kb_path" ]] || [[ ! -f "$optimal_io_size_path" ]]; then
		return
	fi

	local max_sectors_kb=$(cat "$max_sectors_kb_path")
	local optimal_io_size=$(cat "$optimal_io_size_path")

	if [[ -n "$optimal_io_size" ]] && [[ "$optimal_io_size" -gt 0 ]]; then
		local optimal_io_size_kb=$((optimal_io_size / 1024))
		if [[ "$max_sectors_kb" -gt "$optimal_io_size_kb" ]]; then
			echo "$optimal_io_size_kb" > "$max_sectors_kb_path"
			echo "Set max_sectors_kb to $optimal_io_size_kb for $dev"
		fi
	fi
}

adjust_storage_size() {
	difference=$(diff_from_nearest_lower_power_of_2 "$ufs_size")

	if [[ $? -eq 0 ]] && [[ -e "$sysfs_userdata/carve_out" ]]; then
		reserved_blocks=$((difference * (1024 * 1024 * 1024 / block_size)))
		echo "1" > $sysfs_userdata/carve_out
		echo "$reserved_blocks" > $sysfs_userdata/reserved_blocks
	fi
}

adjust_log_buffer() {
	if [[ "$ufs_size" -le 128 ]]; then
		local log_buf_size=`getprop $logpersistd_size_prop`
		log_buf_size=$((log_buf_size / 2))
		setprop $logpersistd_size_prop "$log_buf_size"
	fi
}

configure_zufs() {
	dm_dev_name=$(basename "$(readlink "$sysfs_userdata")")
	proc_disk_map="/proc/fs/f2fs/$dm_dev_name/disk_map"
	sysfs_reserved_segs="$sysfs_userdata/reserved_segments"
	zufs=`getprop "ro.boot.zufs_provisioned"`

	if [ "$zufs" != "true" ]; then
		echo "Storage is not ZUFS."
		return 0
	fi

	if [ ! -f "$proc_disk_map" ]; then
		echo "$proc_disk_map is not found."
		return 0
	fi

	reserved_segs=$(grep "Section size" "$proc_disk_map" | awk '{print $4}' | grep -oE '^[0-9]+$')
	if [ -z "$reserved_segs" ]; then
		echo "Invalid section size: $reserved_segs"
		return 0
	fi

	# Make it segment count by dividing by 2MB and mutiply it by 12 zones
	reserved_segs=$(( (reserved_segs / 2) * 12 ))

	if [ ! -f "$sysfs_reserved_segs" ]; then
		echo "$sysfs_reserved_segs is not found."
		return 0
	fi

	sysfs_val=$(cat "$sysfs_reserved_segs" | grep -oE '^[0-9]+$')

	if [ -z "$sysfs_val" ]; then
		echo "Invalid reserved_segments: $sysfs_val"
		return 0
	fi

	if [ "$sysfs_val" -gt "$reserved_segs" ]; then
		echo "$reserved_segs" > "$sysfs_reserved_segs"
		echo "Set reserved_segments with $reserved_segs"
	fi
}

configure_max_sectors() {
	# Adjust max_sectors_kb for rootdisk and zoned_device if they exist
	if [[ -e "/dev/sys/block/by-name/rootdisk" ]]; then
		rootdisk_dev=$(basename "$(readlink -f "/dev/sys/block/by-name/rootdisk")")
		adjust_max_sectors "$rootdisk_dev"
	fi

	if [[ -e "/dev/sys/block/by-name/zoned_device" ]]; then
		zoned_dev=$(basename "$(readlink -f "/dev/sys/block/by-name/zoned_device")")
		adjust_max_sectors "$zoned_dev"
	fi
}

adjust_storage_size
adjust_log_buffer
configure_zufs
configure_max_sectors
