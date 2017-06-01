#! /bin/bash
# Copyright (C) 2017 Vincent Zvikaramba
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

function copy_bootimage {
	if [ "x$BUILD_TARGET" == "xbootimage" ]; then
		boot_pkg_dir=${BUILD_TEMP}/boot_pkg
		if [ "x$DISTRIBUTION" == "xlineage" ] || [ "x$DISTRIBUTION" == "xRR" ]; then
			boot_pkg_zip=${BUILD_TEMP}/boot_caf-based_j${JOB_BUILD_NUMBER}_$(date +%Y%m%d)-${DEVICE_NAME}.zip
		else
			boot_pkg_zip=${BUILD_TEMP}/boot_aosp-based_j${JOB_BUILD_NUMBER}_$(date +%Y%m%d)-${DEVICE_NAME}.zip
		fi

		revert_pkg_dir=${BUILD_TEMP}/boot_pkg_revert
		revert_zip=${BUILD_TEMP}/revert_boot_image_j${JOB_BUILD_NUMBER}_$(date +%Y%m%d)-${DEVICE_NAME}.zip

		binary_target_dir=META-INF/com/google/android
		install_target_dir=install/bin
		blob_dir=blobs
		proprietary_dir=proprietary

		# create the directories
		exit_on_failure mkdir -p ${boot_pkg_dir}/${binary_target_dir}
		exit_on_failure mkdir -p ${boot_pkg_dir}/${blob_dir}
		exit_on_failure mkdir -p ${boot_pkg_dir}/${proprietary_dir}
		exit_on_failure mkdir -p ${boot_pkg_dir}/${install_target_dir}/installbegin
		exit_on_failure mkdir -p ${boot_pkg_dir}/${install_target_dir}/installend
		exit_on_failure mkdir -p ${boot_pkg_dir}/${install_target_dir}/postvalidate
		exit_on_failure mkdir -p ${revert_pkg_dir}/${binary_target_dir}
		exit_on_failure mkdir -p ${revert_pkg_dir}/${blob_dir}
		exit_on_failure mkdir -p ${revert_pkg_dir}/${proprietary_dir}
		exit_on_failure mkdir -p ${revert_pkg_dir}/${install_target_dir}/installbegin
		exit_on_failure mkdir -p ${revert_pkg_dir}/${install_target_dir}/installend
		exit_on_failure mkdir -p ${revert_pkg_dir}/${install_target_dir}/postvalidate


		# download the update binary
		echoTextBlue "Fetching update binary..."
		${CURL} ${url}/updater/update-binary 1>${BUILD_TEMP}/update-binary 2>/dev/null
		cp ${BUILD_TEMP}/update-binary ${revert_pkg_dir}/${binary_target_dir}

		echoTextBlue "Fetching mkbootimg..."
		${CURL} ${url}/bootimg-tools/mkbootimg 1>${BUILD_TEMP}/mkbootimg 2>/dev/null

		echoTextBlue "Fetching unpackbootimg..."
		${CURL} ${url}/bootimg-tools/unpackbootimg 1>${BUILD_TEMP}/unpackbootimg 2>/dev/null

		if [ -e ${ANDROID_PRODUCT_OUT}/system/lib/modules/wlan.ko ]; then
			echoTextBlue "Copying wifi module..."
			cp ${ANDROID_PRODUCT_OUT}/system/lib/modules/wlan.ko ${boot_pkg_dir}/${blob_dir}/wlan.ko
		fi

		cp ${ANDROID_PRODUCT_OUT}/boot.img ${boot_pkg_dir}/${blob_dir}
		cp ${BUILD_TEMP}/update-binary ${boot_pkg_dir}/${binary_target_dir}
		cp ${BUILD_TEMP}/mkbootimg ${boot_pkg_dir}/${install_target_dir}
		cp ${BUILD_TEMP}/unpackbootimg ${boot_pkg_dir}/${install_target_dir}

		# Create the scripts
		create_scripts

		#archive the image
		echoTextBlue "Creating flashables..."
		cd ${boot_pkg_dir} && zip ${boot_pkg_zip} `find ${boot_pkg_dir} -type f | cut -c $(($(echo ${boot_pkg_dir}|wc -c)+1))-`
		cd ${revert_pkg_dir} && zip ${revert_zip} `find ${revert_pkg_dir} -type f | cut -c $(($(echo ${revert_pkg_dir}|wc -c)+1))-`
		echoTextBlue "Copying boot image..."
		exit_on_failure rsync -v -P ${boot_pkg_zip} ${OUTPUT_DIR}/builds/boot/

		echoTextBlue "Copying reversion zip..."
		exit_on_failure rsync -v -P ${revert_zip} ${OUTPUT_DIR}/builds/boot/
	fi
}

function create_scripts {
cat <<A_SCRIPT_F > ${boot_pkg_dir}/${binary_target_dir}/updater-script
package_extract_dir("install", "/tmp/install");
set_metadata_recursive("/tmp/install", "uid", 0, "gid", 0, "dmode", 0755, "fmode", 0644);
set_metadata_recursive("/tmp/install/bin", "uid", 0, "gid", 0, "dmode", 0755, "fmode", 0755);
ui_print("Extracting files...");
package_extract_dir("proprietary", "/tmp/proprietary");
set_metadata_recursive("/tmp/proprietary", "uid", 0, "gid", 0, "dmode", 0755, "fmode", 0644);
package_extract_dir("blobs", "/tmp/blobs");
set_metadata_recursive("/tmp/blobs", "uid", 0, "gid", 0, "dmode", 0755, "fmode", 0644);
assert(run_program("/tmp/install/bin/run_scripts.sh", "installbegin") == 0);
assert(run_program("/tmp/install/bin/run_scripts.sh", "installend") == 0);
assert(run_program("/tmp/install/bin/run_scripts.sh", "postvalidate") == 0);
A_SCRIPT_F


if [ "x$DISTRIBUTION" == "xlineage" ] || [ "x$DISTRIBUTION" == "xRR" ]; then
	kern_base="CAF"
else
	kern_base="AOSP"
fi
dist_str="$kern_base $ver kernel only guaranteed to boot on $kern_base $ver based systems"
plat_short=`echo $platform_version|cut -c -3`

cat <<SWAP_K_F > ${boot_pkg_dir}/${install_target_dir}/installbegin/swap_kernel.sh
#!/sbin/sh

#convert cpio recovery image to bootfs one

error_msg="Error creating boot image! Aborting..."

BOOT_PARTITION=/dev/block/bootdevice/by-name/boot
BOOT_IMG=/tmp/blobs/boot.img

BIN_PATH=/tmp/install/bin/

BOOT_PARTITION_BASENAME=\$(basename \$BOOT_PARTITION)
BOOT_IMG_BASENAME=\$(basename \$BOOT_IMG)

BOOT_PARTITION_TMPDIR=\$(mktemp -d)
BOOT_IMG_TMPDIR=\$(mktemp -d)

ui_print ""
ui_print "==========================================="
ui_print ""
ui_print "Kernel swapper v1.0"
ui_print ""
ui_print "$dist_str"
ui_print ""
sleep 1
ui_print "CAF = CodeAuroraForums (Qualcomm source)"
ui_print "AOSP = Upstream Google source code"
ui_print ""
ui_print "==========================================="
ui_print ""

sleep 1

mount_fs system

ui_print "Backing up boot partition to /system/boot.img.bak ..."
ui_print ""
dd if=\$BOOT_PARTITION of=/system/boot.img.bak

if [ \$? != 0 ]; then
    ui_print "Failed to back up boot image."
    ui_print ""
fi

display_id=\`cat /system/build.prop |grep ro.build.display.id\`
dist=\`echo \$display_id | grep -o $DISTRIBUTION\`
plat=\`echo \$display_id | grep -o $plat_short\`

umount_fs system

if [ -n "\$dist" ] && [ -n "\$plat" ]; then
	ui_print
	ui_print "Detected android distribution ${distroTxt}/${DISTRIBUTION}-${ver} on platform ${platform_version}"
	ui_print
	ui_print "Flashing boot image without repacking..."
	dd if=\$BOOT_IMG of=\$BOOT_PARTITION
	if [ \$? != 0 ]; then
	    ui_print
	    ui_print "Failed to back up boot image."
	    ui_print
	    exit 1
	fi
else
	ui_print "Unpacking \$BOOT_PARTITION..."
	\$BIN_PATH/unpackbootimg -i \$BOOT_PARTITION -o \$BOOT_PARTITION_TMPDIR/

	if [ \$? != 0 ]; then
	    ui_print \$error_msg
	    ui_print ""
	    exit 1
	fi

	ui_print "Unpacking \$BOOT_IMG..."
	\$BIN_PATH/unpackbootimg -i \$BOOT_IMG -o \$BOOT_IMG_TMPDIR/

	if [ \$? != 0 ]; then
	    ui_print \$error_msg
	    ui_print ""
	    exit 1
	fi

	ui_print "Replacing kernel..."
	rm \$BOOT_PARTITION_TMPDIR/\${BOOT_PARTITION_BASENAME}-zImage
	cp \$BOOT_IMG_TMPDIR/\${BOOT_IMG_BASENAME}-zImage \$BOOT_PARTITION_TMPDIR/\${BOOT_PARTITION_BASENAME}-zImage

	ui_print "Replacing dt..."
	rm \$BOOT_PARTITION_TMPDIR/\${BOOT_PARTITION_BASENAME}-dt
	cp \$BOOT_IMG_TMPDIR/\${BOOT_IMG_BASENAME}-dt \$BOOT_PARTITION_TMPDIR/\${BOOT_PARTITION_BASENAME}-dt

	if [ \$? != 0 ]; then
	    ui_print \$error_msg
	    ui_print ""
	    exit 1
	fi

	base=\`cat \$BOOT_PARTITION_TMPDIR/\${BOOT_PARTITION_BASENAME}-base\`
	ramdisk_offset=\`cat \$BOOT_PARTITION_TMPDIR/\${BOOT_PARTITION_BASENAME}-ramdisk_offset\`
	pagesize=\`cat \$BOOT_PARTITION_TMPDIR/\${BOOT_PARTITION_BASENAME}-pagesize\`
	#cmdline="\`cat \$BOOT_PARTITION_TMPDIR/\${BOOT_PARTITION_BASENAME}-cmdline\`"
	cmdline="\`cat \$BOOT_IMG_TMPDIR/\${BOOT_IMG_BASENAME}-cmdline\`"
	zImage=\$BOOT_PARTITION_TMPDIR/\${BOOT_PARTITION_BASENAME}-zImage
	ramdisk=\$BOOT_PARTITION_TMPDIR/\${BOOT_PARTITION_BASENAME}-ramdisk.gz
	dt=\$BOOT_PARTITION_TMPDIR/\${BOOT_PARTITION_BASENAME}-dt
	file_out=\$BOOT_PARTITION_TMPDIR/boot.img

	ui_print "Repacking boot image..."
	\$BIN_PATH/mkbootimg --kernel \$zImage --ramdisk \$ramdisk --cmdline "\$cmdline" \\
		--base \$base --pagesize \$pagesize --ramdisk_offset \$ramdisk_offset \\
		--dt \$dt -o \$file_out

	if [ \$? != 0 ]; then
	    ui_print \$error_msg
	    ui_print ""
	    exit 1
	fi

	ui_print "Making bootimage SEAndroid enforcing..."
	echo -n "SEANDROIDENFORCE" >> \${file_out}

	ui_print "Flashing boot image..."
	dd if=\$file_out of=\$BOOT_PARTITION

	if [ \$? != 0 ]; then
	    ui_print \$error_msg
	    ui_print ""
	    exit 1
	fi
fi

ui_print "Cleaning up..."
ui_print ""
rm -r \$BOOT_PARTITION_TMPDIR
rm -r \$BOOT_IMG_TMPDIR

ui_print "Successfully flashed new boot image."
ui_print ""
SWAP_K_F

cat <<A_INSTALL_F > ${boot_pkg_dir}/${install_target_dir}/installend/update_wifi_module.sh
#!/sbin/sh
if [ -e /tmp/blobs/wlan.ko ]; then
	mount_fs system

	if [ -e /system/lib/modules/wlan.ko ]; then
		ui_print "Backing up previous wlan module..."
		ui_print ""
		mv /system/lib/modules/wlan.ko /system/lib/modules/wlan.ko.old
	fi
	ui_print "Copying new wlan module..."
	ui_print ""
	cp /tmp/blobs/wlan.ko /system/lib/modules/wlan.ko
	chmod 0644 /system/lib/modules/wlan.ko

	umount_fs system
fi
A_INSTALL_F

cat <<B_INSTALL_F > ${revert_pkg_dir}/${install_target_dir}/installbegin/revert_boot_img.sh
#!/sbin/sh
mount_fs system
BOOT_PARTITION=/dev/block/bootdevice/by-name/boot
if [ -e /system/boot.img.bak ]; then
	ui_print "Restoring boot image..."
	ui_print ""
	dd if=/system/boot.img.bak of=\$BOOT_PARTITION

	if [ \$? != 0 ]; then
	    ui_print "Failed to restore boot image."
	    ui_print ""
	    exit 1
	fi
	rm /system/boot.img.bak
else
	    ui_print "No backup boot image found."
	    ui_print ""
fi
umount_fs system
B_INSTALL_F

cat <<B_INSTALL_F > ${revert_pkg_dir}/${install_target_dir}/installbegin/revert_wifi_module.sh
#!/sbin/sh
mount_fs system
if [ -e /system/lib/modules/pronto/pronto_wlan.ko.old ]; then
	ui_print "Restoring previous pronto wlan module..."
	ui_print ""
	rm /system/lib/modules/pronto/pronto_wlan.ko
	mv /system/lib/modules/pronto/pronto_wlan.ko.old /system/lib/modules/pronto/pronto_wlan.ko
fi
if [ -e /system/lib/modules/wlan.ko.old ]; then
	ui_print "Restoring previous wlan module..."
	ui_print ""
	rm /system/lib/modules/wlan.ko
	mv /system/lib/modules/wlan.ko.old /system/lib/modules/wlan.ko
fi
umount_fs system
B_INSTALL_F

cat <<CP_VARIANT_F > ${boot_pkg_dir}/${install_target_dir}/postvalidate/copy_variant_blobs.sh
#!/sbin/sh

BLOBBASE=/tmp/proprietary

# Mount /system
mount_fs system

if [ -d \$BLOBBASE ]; then

	cd \$BLOBBASE

	# copy all the blobs
	for FILE in \`find . -type f | cut -c 3-\` ; do
		mkdir -p \`dirname /system/\$FILE\`
		ui_print "Copying \$FILE to /system/\$FILE ..."
		cp \$FILE /system/\$FILE
	done

	# set permissions on binary files
	for FILE in \`find bin -type f | cut -c 3-\`; do
		ui_print "Setting /system/\$FILE executable ..."
		chmod 755 /system/\$FILE
	done
umount_fs system
fi
CP_VARIANT_F

logb "\t\tFetching scripts..."
common_url="https://raw.githubusercontent.com/Galaxy-MSM8916/android_device_samsung_msm8916-common/cm-14.1"

${CURL} ${common_url}/releasetools/functions.sh 1>${boot_pkg_dir}/${install_target_dir}/functions.sh 2>/dev/null
${CURL} ${common_url}/releasetools/run_scripts.sh 1>${boot_pkg_dir}/${install_target_dir}/run_scripts.sh 2>/dev/null

exit_on_failure mkdir -p ${boot_pkg_dir}/${proprietary_dir}/etc/
exit_on_failure mkdir -p ${revert_pkg_dir}/${proprietary_dir}/etc/
${CURL} ${common_url}/rootdir/etc/init.qcom.post_boot.sh 1>${revert_pkg_dir}/${proprietary_dir}/etc/init.qcom.post_boot.sh 2>/dev/null
if [ "$EXPERIMENTAL_KERNEL"  == "y" ]; then
	${CURL} ${common_url}-experimental/rootdir/etc/init.qcom.post_boot.sh 1>${boot_pkg_dir}/${proprietary_dir}/etc/init.qcom.post_boot.sh 2>/dev/null
else
	cp ${revert_pkg_dir}/${proprietary_dir}/etc/init.qcom.post_boot.sh ${boot_pkg_dir}/${proprietary_dir}/etc/
fi

cp ${boot_pkg_dir}/${install_target_dir}/run_scripts.sh ${revert_pkg_dir}/${install_target_dir}/run_scripts.sh
cp ${boot_pkg_dir}/${install_target_dir}/postvalidate/copy_variant_blobs.sh ${revert_pkg_dir}/${install_target_dir}/postvalidate/copy_variant_blobs.sh
cp ${boot_pkg_dir}/${install_target_dir}/functions.sh ${revert_pkg_dir}/${install_target_dir}/functions.sh
cp ${boot_pkg_dir}/${binary_target_dir}/updater-script ${revert_pkg_dir}/${binary_target_dir}/updater-script
}

COPY_FUNCTIONS=("${COPY_FUNCTIONS[@]}" "copy_bootimage")
