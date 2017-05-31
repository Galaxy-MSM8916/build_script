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

# declare globals for argv helper
# declare some globals
release_type=""
ver=""
distroTxt=""
recovery_variant=""
platform_common_dir=""
common_dir=""
recovery_flavour=""

kernel_name="msm8916"
vendors[0]="samsung"
vendors[1]="qcom"

function bootstrap {
	# set the common dir
	platform_common_dir="$BUILD_TOP/device/${vendors[0]}/msm8916-common/"
	if [ "$(echo $DEVICE_NAME | cut -c -3)" == "gte" ]; then
		common_dir="$BUILD_TOP/device/${vendors[0]}/gte-common/"
	elif [ "$(echo $DEVICE_NAME | cut -c -2)" == "j5" ]; then
		common_dir="$BUILD_TOP/device/${vendors[0]}/j5-common/"
	else
		common_dir="$BUILD_TOP/device/${vendors[0]}/gprimelte-common/"
	fi

	#setup the path
	if [ -n ${BUILD_BIN_ROOT} ]; then
		export PATH=$PATH:${BUILD_BIN_ROOT}
	fi
}

DISTROS="
omni
lineage
cm
RR"

function get_platform_info {
	#move into the build dir
	cd $BUILD_TOP
	#get the platform version
	platform_version=$(grep 'PLATFORM_VERSION[ ]*:' build/core/version_defaults.mk  | cut -d '=' -f 2)
	export WITH_SU

	# try to get distribution version from path
	if [ "x$DISTRIBUTION" == "x" ]; then
		for i in ${DISTROS}; do
			if [ `echo $BUILD_TOP | grep -o $i | wc -c` -gt 1 ]; then
				DISTRIBUTION=`echo $BUILD_TOP | grep -o $i`
				logr "Guessed distribution is $DISTRIBUTION/`echo $BUILD_TOP | grep -o $i`"
			fi
		done
	fi

	if [ "x$DISTRIBUTION" == "x" ]; then
		logr "Error: No distribution specified!"
		exit_error 1
	fi

	if [ "`echo $platform_version | grep -o "7.1"`" == "7.1" ]; then
		export JACK_SERVER_VM_ARGUMENTS="-Dfile.encoding=UTF-8 -XX:+TieredCompilation -Xmx4g"
		if [ "x$DISTRIBUTION" == "xlineage" ]; then
			ver="14.1"
			distroTxt="LineageOS"
		elif [ "x$DISTRIBUTION" == "xRR" ]; then
			ver="5.8"
			distroTxt="ResurrectionRemix"
		elif [ "x$DISTRIBUTION" == "xcm" ]; then
			ver="14.1"
			distroTxt="CyanogenMod"
		elif [ "x$DISTRIBUTION" == "xomni" ]; then
			ver="7.1"
			distroTxt="Omni"
		fi
	elif [ "`echo $platform_version | grep -o "6.0"`" == "6.0" ]; then
		if [ "x$DISTRIBUTION" == "xlineage" ]; then
			ver="13.0"
			distroTxt="LineageOS"
		elif [ "x$DISTRIBUTION" == "xRR" ]; then
			ver="5.7"
			distroTxt="ResurrectionRemix"
		elif [ "x$DISTRIBUTION" == "xcm" ]; then
			ver="13.0"
			distroTxt="CyanogenMod"
		elif [ "x$DISTRIBUTION" == "xomni" ]; then
			ver="6.0"
			distroTxt="Omni"
		fi
	elif [ "`echo $platform_version | grep -o "5.1"`" == "5.1" ]; then
		if [ "x$DISTRIBUTION" == "xcm" ]; then
			ver="12.1"
			distroTxt="CyanogenMod"
		elif [ "x$DISTRIBUTION" == "xRR" ]; then
			ver="5.6"
			distroTxt="ResurrectionRemix"
		elif [ "x$DISTRIBUTION" == "xomni" ]; then
			ver="5.1"
			distroTxt="Omni"
		fi
	elif [ "`echo $platform_version | grep -o "5.0"`" == "5.0" ]; then
		if [ "x$DISTRIBUTION" == "xcm" ]; then
			ver="12.0"
			distroTxt="CyanogenMod"
		elif [ "x$DISTRIBUTION" == "xomni" ]; then
			ver="5.0"
			distroTxt="Omni"
		fi

	fi

	# print the distribution and platform
	logb "Distro is: ${distroTxt}/${DISTRIBUTION}-${ver} on platform ${platform_version}"

	#set the recovery type
	recovery_variant=$(grep RECOVERY_VARIANT ${platform_common_dir}/BoardConfigCommon.mk 2>/dev/null | sed s'/ //'g)
	# get the release type
	if [ "x${release_type}" == "x" ]; then
		release_type=$(grep "CM_BUILDTYPE" ${common_dir}/${DISTRIBUTION}.mk 2>/dev/null | cut -d'=' -f2 | sed s'/ //'g)
	fi

	# check if it was succesfully set, and set it to the default if not
	if [ "x${release_type}" == "x" ]; then
		release_type="NIGHTLY"
	fi

	# get the recovery type
	if [ "$recovery_variant" == "RECOVERY_VARIANT:=twrp" ]; then
		if [ "`echo $ver | grep -o "7.1"`" == "7.1" ]; then
			recovery_flavour="TWRP-3.1.x"
		elif [ "`echo $ver | grep -o "6.0"`" == "6.0" ]; then
			recovery_flavour="TWRP-3.0.x"
		else
			recovery_flavour="TWRP-2.8.7.0"
		fi
	elif [ "x$DISTRIBUTION" == "xlineage" ]; then
		recovery_flavour="LineageOSRecovery"
	elif [ "x$DISTRIBUTION" == "xcm" ]; then
		recovery_flavour="CyanogenModRecovery"
	elif [ "x$DISTRIBUTION" == "xomni" ]; then
		if [ "`echo $ver | grep -o "7.1"`" == "7.1" ]; then
			recovery_flavour="TWRP-3.1.x"
		elif [ "`echo $ver | grep -o "6.0"`" == "6.0" ]; then
			recovery_flavour="TWRP-3.0.x"
		else
			recovery_flavour="TWRP-2.8.7.0"
		fi
	fi
}

function setup_env {

	#move into the build dir
	cd $BUILD_TOP

	#set up the environment
	. build/envsetup.sh

	# remove duplicate crypt_fs.
	if [ -d ${BUILD_TOP}/device/qcom-common/cryptfs_hw ] && [ -d ${BUILD_TOP}/vendor/qcom/opensource/cryptfs_hw ]; then
		rm -r ${BUILD_TOP}/vendor/qcom/opensource/cryptfs_hw
	fi

	#select the device
	lunch ${DISTRIBUTION}_${DEVICE_NAME}-${BUILD_VARIANT}

	# exit if there was an error
	exit_error $?

	#create the directories
	mkdir ${BUILD_TEMP}/ -p
	mkdir ${OUTPUT_DIR}/builds/boot -p
	mkdir ${OUTPUT_DIR}/builds/full -p
	mkdir ${OUTPUT_DIR}/builds/odin -p
	mkdir ${OUTPUT_DIR}/builds/recovery -p
	mkdir ${OUTPUT_DIR}/builds/recovery/${DEVICE_NAME} -p
	mkdir ${OUTPUT_DIR}/builds/su -p
}
