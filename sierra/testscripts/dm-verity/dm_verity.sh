#!/bin/sh
#
# Script to test DM verity

cleanup()
{
	if [ -n "$UBI_DEV_NUM" ]; then
		ls /dev/ubi* | grep "${UBI_DEV_NUM}" > /dev/null
		if [ $? -eq 0 ]; then
			ubidetach -m $UBI_DEV_NUM
		fi
	fi

	if [ -d $DATADIR ]; then
		rm -rf $DATADIR
	fi

}

exit_script()
{
	cleanup
	echo "DM verity test FAIL."
	exit 1
}

#########################################################
# Check if DM Verity works for rootfs
#########################################################
do_check_dm_verity_for_rt()
{
	# Check if /dev/mapper/rt exists
	df -h | grep "/dev/mapper/rt" > /dev/null
	if [ $? -ne 0 ]; then
		echo "Can't not found /dev/mapper/rt, test FAIL."
		exit_script
	fi

	# Make sure rt is verified
	veritysetup status rt | grep "verified" > /dev/null
	if [ $? -eq 0 ]; then
		echo "/dev/mapper/rt verify PASS."
	else
		echo "/dev/mapper/rt verify FAIL."
		exit_script
	fi

}

#########################################################
# Fully verify the DM verity image by commands
#########################################################
do_verify_dm_verity_image()
{
	local ubi_dev_num=$1

	if [ -z "$ubi_dev_num" ]; then
		echo "Err, UBI device number not correct."
		exit_script
	fi

	hash=$(dd if=/dev/ubi${ubi_dev_num}_2 bs=64 count=1 | cut -c 0-64)

	veritysetup verify /dev/ubiblock${ubi_dev_num}_0 /dev/ubiblock${ubi_dev_num}_1 $hash --debug | grep "Command successful" > /dev/null
	result=$?
	if [ $result -eq 0 ]; then
		echo "Verify PASS."
		return $result
	elif [ $result -eq 1 ]; then
		echo "Verify FAIL."
		return $result
	else
		echo "veritysetup FAIL."
		exit_script
	fi
}

# Get the test partition for the corresponding product.
# customer1 is for AR products, swirx is for EM.
get_test_partition_num()
{
	local parti_list="customer1 \
	                  swirw \
	                  "
	for mtd_part_name in $parti_list; do
		cat /proc/mtd | grep ${mtd_part_name} > /dev/null
		if [ $? -eq 0 ]; then
			break;
		else
			mtd_part_name=""
		fi
	done

	echo "mtd_part_name is $mtd_part_name"
	if [ -n "$mtd_part_name" ]; then
		ubi_dev_num=$(cat /proc/mtd | grep $mtd_part_name | cut -d : -f 1 | cut -c 4-)
		echo "ubi_dev_num is $ubi_dev_num"
	else
		echo "get_test_partition_num FAIL."
		exit_script
	fi
}

# Wait until file shows up. Note that this will wait on any file and there
# will be no distinction between regular or device file. While covering wide
# range of cases, we may need to restrict this to device files in the future.
# Limit the time spent here to about 3 sec. If file does not show up for 3 sec.
# it will probably never show up.
wait_on_file()
{
	local cntmax=150
	local ret=0

	while [ ! -e "$1" ] ; do
		usleep 20000
		cntmax=$( echo $(( ${cntmax} - 1 )) )
		if [ ${cntmax} -eq 0 ] ; then
			ret=1
			break
		fi
	done

	return ${ret}

}

# Attach ubi device, create /dev/ubi* and /dev/ubiblock*
attach_ubi_device()
{
	local dev_num=$1

	local img_vol="0"
	local hash_vol="1"
	local rhash_vol="2"

	local ubi_img_block_dev=/dev/ubiblock${dev_num}_0
	local ubi_hash_block_dev=/dev/ubiblock${dev_num}_1

	if [ -z "$dev_num" ]; then
		echo "dev_num is NULL"
		return 1
	fi

	ls /dev/ubi* | grep "${dev_num}" > /dev/null
	if [ $? -eq 0 ]; then
		ubidetach -m $dev_num
	fi

	ubiattach -m $dev_num -d $dev_num
	if [ $? -ne 0 ] ; then
		echo "Unable to attach mtd partition to UBI logical device ${dev_num}"
		return 1
	fi

	# Important:
	# After ubiattach, for multi volumes UBI image, we need to wait for all the UBI
	# volumes ready which are needed at the following step. There is a low probability
	# that when the last volume is ready but some of the other volumes are not ready.
	# E.g ubix_4 is ready, but ubix_2 or ubix_3 is not ready.
	# Wait for all the UBI volumes that used for security authentication.
	ubi_dev_list="/dev/ubi${dev_num}_${img_vol} \
	              /dev/ubi${dev_num}_${hash_vol} \
	              /dev/ubi${dev_num}_${rhash_vol} \
	              "
	for ubi_dev in ${ubi_dev_list} ; do
		echo "ubi_dev is $ubi_dev"
		wait_on_file "${ubi_dev}"
		if [ $? -ne 0 ] ; then
			echo "Tired of waiting on ${ubi_dev}."
			ubidetach -m $dev_num
			return 1
		fi
	done

	# Create ubiblock volume 0 and volume 1
	blk_vol_list="${img_vol} \
	              ${hash_vol} \
	              "

	ubiattach -V | grep " 1." > /dev/null
	if [ $? -eq 0 ]; then
		create_blk_cmd="ubiblkvol -a"
		rm_blk_cmd="ubiblkvol -d"
	else
		create_blk_cmd="ubiblock -c"
		rm_blk_cmd="ubiblock -r"
	fi

	for vol_num in ${blk_vol_list}; do
		ls /dev/ubi* | grep "ubiblock${dev_num}_${vol_num}" > /dev/null
		if [ $? -eq 0 ]; then
			${rm_blk_cmd} /dev/ubi${dev_num}_${vol_num}
		fi

		${create_blk_cmd} /dev/ubi${dev_num}_${vol_num}
		if [ $? -ne 0 ] ; then
			echo "Unable to create /dev/ubi${dev_num}_${vol_num}."
			ubidetach -m $dev_num
			return 1
		fi
		wait_on_file /dev/ubiblock${dev_num}_${vol_num}
		if [ $? -ne 0 ] ; then
			echo "Tired of waiting on ${ubi_img_block_dev}, exiting."
			ubidetach -m $dev_num
			return 1
		fi

	done

	return 0
}

#########################################################
# Check dm verity image on customer partition
#########################################################
do_verify_on_customer_parti()
{
	get_test_partition_num
	if [ -z "$UBI_DEV_NUM" ]; then
		echo "get_test_partition_num FAIL."
		exit_script
	fi

	attach_ubi_device "$UBI_DEV_NUM"
	if [ $? -ne 0 ] ; then
		echo "attach_ubi_device FAIL."
		exit_script
	fi

	do_verify_dm_verity_image "$UBI_DEV_NUM"
	if [ $? -ne 0 ] ; then
		echo "do_verify_dm_verity_image FAIL."
		exit_script
	fi
}

# Created the test and recover image.
#  - To create test image for volume 0, img_1 and img_2 are needed.
#  - To create test image for volume 1, img_1, img_2 and img_3 are needed.
create_image()
{
	local img_1=$1
	local img_2=$2
	local img_3=$3

	# Create image for testing
	if [[ -f $img_1 ]] && [[ -f $img_1 ]]; then
		if [ -f $TEST_IMG ]; then
			rm $TEST_IMG
		fi

		echo "write $img_1 and $img_2 to $TEST_IMG."
		cat $img_1 > $TEST_IMG
		cat $img_2 >> $TEST_IMG
	else
		echo "$img_1 or $img_2 does not exist."
		exit_script
	fi

	if [ -f "${img_3}" ]; then
		echo "write $img_3 to $TEST_IMG."
		cat $img_3 >> $TEST_IMG
	fi
}

# Update ubi volume
# vol_num - 0,1,2 means volume 0, volume 1, volume 2
update_ubi_vol()
{
	local vol_num=$1

	if [ ! -f $TEST_IMG ]; then
		echo "$TEST_IMG does not exist."
		return 1
	fi

	echo "update volume $vol_num"

	ubiattach -V | grep " 1." > /dev/null
	if [ $? -eq 0 ]; then
		create_blk_cmd="ubiblkvol -a"
		rm_blk_cmd="ubiblkvol -d"
	else
		create_blk_cmd="ubiblock -c"
		rm_blk_cmd="ubiblock -r"
	fi

	# Remove ubiblock for volume 0 and 1
	if [[ "${vol_num}" = "0" ]] || [[ "${vol_num}" = "1" ]]; then
		# Remove ubiblock${UBI_DEV_NUM}_${vol_num}
		${rm_blk_cmd} /dev/ubi${UBI_DEV_NUM}_${vol_num}
		if [ $? -ne 0 ] ; then
			echo "Volume${vol_num} remove FAIL."
			return 1
		else
			echo "Volume${vol_num} remove done."
		fi
	fi

	# Update ubi${UBI_DEV_NUM}_${vol_num}
	ubiupdatevol /dev/ubi${UBI_DEV_NUM}_${vol_num} ${TEST_IMG}
	if [ $? -eq 0 ] ; then
		rm -rf $TEST_IMG

		# Update ubiblock for volume 0 and 1
		if [[ "${vol_num}" = "0" ]] || [[ "${vol_num}" = "1" ]]; then
			${create_blk_cmd} /dev/ubi${UBI_DEV_NUM}_${vol_num}
			if [ $? -ne 0 ] ; then
				echo "Unable to create /dev/ubi${UBI_DEV_NUM}_${vol_num}."
				return 1
			fi
			wait_on_file "/dev/ubi${UBI_DEV_NUM}_${vol_num}"
			if [ $? -ne 0 ] ; then
				echo "Tired of waiting on ${ubi_hash_block_dev}, exiting."
				return 1
			else
				echo "Volume${vol_num} update done."
			fi
		fi
		return 0
	else
		echo "Volume${vol_num} update FAIL."
		return 1
	fi
}

#########################################################
# Test destoryed image for volume 0, volume 1 and volume 2.
#########################################################
do_verify_destoryed_img()
{
	action_lst="test \
	            recover \
	            "

	# Get the first 1024 of image in volume0
	dd if=/dev/ubi${UBI_DEV_NUM}_0 of=$DATADIR/vol0_1.bin bs=1024 count=1

	# Get the left data in volume0
	dd if=/dev/ubi${UBI_DEV_NUM}_0 of=$DATADIR/vol0_2.bin bs=1024 skip=1

	# Get the first 4096 of image in volume1
	dd if=/dev/ubi${UBI_DEV_NUM}_1 of=$DATADIR/vol1_1.bin bs=4096 count=1

	# Get the 1024 data which need to destory in volume1
	dd if=/dev/ubi${UBI_DEV_NUM}_1 of=$DATADIR/vol1_2.bin bs=1024 skip=4 count=1

	# Get the left data in volume1
	dd if=/dev/ubi${UBI_DEV_NUM}_1 of=$DATADIR/vol1_3.bin bs=1024 skip=5

	############################
	# Test and recover volume 0
	############################
	for action in $action_lst; do
		if [ $action = "test" ]; then
			# Use the data from volume 1 to destory the image.
			diff_img=$DATADIR/vol1_2.bin
		elif [ $action = "recover" ]; then
			diff_img=$DATADIR/vol0_1.bin
		else
			echo "ERR, not supported action $action"
			exit_script
		fi

		echo "diff_img is $diff_img"

		# Create image for volume0 testing
		create_image $diff_img $DATADIR/vol0_2.bin

		# update destoryed image in volume0
		update_ubi_vol "0"
		if [ $? -ne 0 ] ; then
			echo "update_ubi_vol FAIL."
			exit_script
		fi

		# Verify the image.
		do_verify_dm_verity_image "$UBI_DEV_NUM"
		result=$?
		if [[ $result -ne 1 ]] && [[ $action = "test" ]]; then
			echo "Destroy volume 0 test FAIL!"
			exit_script
		elif [[ $result -ne 0 ]] && [[ $action = "recover" ]]; then
			echo "recover volume 0 test FAIL!"
			exit_script
		fi

	done

	echo "Test destroyed Volume 0 PASS. "

	# Remove the useless data
	rm -rf $DATADIR/vol0_2.bin


	############################
	# Test and recover volume 1
	############################
	for action in $action_lst; do
		if [ $action = "test" ]; then
			# Use the data from volume 2 to destory the image.
			diff_img=$DATADIR/vol0_1.bin
		elif [ $action = "recover" ]; then
			diff_img=$DATADIR/vol1_2.bin
		fi

		echo "diff_img is $diff_img"

		# Create image for volume1 testing
		create_image $DATADIR/vol1_1.bin $diff_img $DATADIR/vol1_3.bin

		# update destoryed image in volume1
		update_ubi_vol "1"
		if [ $? -ne 0 ] ; then
			echo "update_ubi_vol FAIL."
			exit_script
		fi

		# Verify the image.
		do_verify_dm_verity_image "$UBI_DEV_NUM"
		result=$?
		if [[ $result -ne 1 ]] && [[ $action = "test" ]]; then
			echo "Destroy volume 1 test FAIL!"
			exit_script
		elif [[ $result -ne 0 ]] && [[ $action = "recover" ]]; then
			echo "recover volume 1 test FAIL!"
			exit_script
		fi

	done

	echo "Test destroyed Volume 1 PASS. "

	# Remove the useless data
	rm -rf $DATADIR/vol0_1.bin
	rm -rf $DATADIR/vol1_1.bin
	rm -rf $DATADIR/vol1_2.bin
	rm -rf $DATADIR/vol1_3.bin


	############################
	# Test and recover volume 2
	############################

	# backup image in volume2
	dd if=/dev/ubi${UBI_DEV_NUM}_2 of=$DATADIR/vol2.bin bs=1024

	# Test and recover volume 2
	for action in $action_lst; do
		# Create image for volume0 testing
		if [ -f $TEST_IMG ]; then
			rm $TEST_IMG
		fi

		if [ $action = "test" ]; then
			# Create test image
			echo "112233445566778899aabbccddeeff294948ba2139d64ef898a7ff010822a520" > $TEST_IMG
		elif [ $action = "recover" ]; then
			cat $DATADIR/vol2.bin > $TEST_IMG
		fi

		# update destoryed image in volume1
		update_ubi_vol "2"
		if [ $? -ne 0 ] ; then
			echo "update_ubi_vol FAIL."
			exit_script
		fi

		# Verify the image.
		do_verify_dm_verity_image "$UBI_DEV_NUM"
		result=$?
		if [[ $result -ne 1 ]] && [[ $action = "test" ]]; then
			echo "Destroy volume 2 test FAIL!"
			exit_script
		elif [[ $result -ne 0 ]] && [[ $action = "recover" ]]; then
			echo "recover volume 2 test FAIL!"
			exit_script
		fi

	done

	echo "Test destroyed Volume 2 PASS. "

	# Remove the useless data
	rm -rf $DATADIR/vol2.bin
}

#########################################################
# Test runtime destory partition by erasing the partition 
#########################################################
do_test_runtime_destory()
{
	mount_dir=$DATADIR/test_dir

	if [ -d $mount_dir ]; then
		rm -rf $mount_dir
	fi

	mkdir $mount_dir

	# Mount partition
	mount -t squashfs /dev/ubiblock${UBI_DEV_NUM}_0 $mount_dir -oro
	if [ $? -ne 0 ] ; then
		echo "mount /dev/ubiblock${UBI_DEV_NUM}_0 FAIL."
		exit_script
	fi

	cp -a $mount_dir/etc /tmp
	if [ $? -ne 0 ] ; then
		echo "cp $mount_dir/etc FAIL."
		exit_script
	fi

	# Erase customer partition
	mtd_num=$(cat /sys/class/ubi/ubi$UBI_DEV_NUM/mtd_num)
	flash_erase /dev/mtd$mtd_num 0 0 -N
	if [ $? -ne 0 ] ; then
		echo "flash_erase /dev/mtd$mtd_num FAIL."
		exit_script
	fi

	cp -a $mount_dir/usr/sbin $DATADIR
	if [ $? -ne 0 ] ; then
		echo "Test destory partition PASS."
		umount -l ${mount_dir} &>/dev/null
		return 0
	else
		echo "Test destory partition FAIL."
		exit_script
	fi
}

UBI_DEV_NUM=""
DATADIR="test_dm_verity"
if [ -d $DATADIR ]; then
	rm -rf $DATADIR
fi

mkdir $DATADIR

TEST_IMG="$DATADIR/test.img"

# Test 1: Check if dm verity works.
do_check_dm_verity_for_rt

# Test 2: Fully verify the DM verity image by commands
do_verify_dm_verity_image "0"
if [ $? -ne 0 ] ; then
	echo "do_verify_dm_verity_image FAIL."
	return
fi

# Test 3: check dm verity image on customer partition
do_verify_on_customer_parti

# Test 4: Test destoryed image
do_verify_destoryed_img

# Test 5: Test runtime destory partition
do_test_runtime_destory

exit 0


