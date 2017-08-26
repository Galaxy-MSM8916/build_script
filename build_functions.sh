#!/bin/bash
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

function make_targets {
	#start building
	if [ "x$ver" == "x13.0" ]; then
		exit_on_failure make -j${JOB_NUMBER} $BUILD_TARGET CM_UPDATER_OTA_URI="cm.updater.uri=http://ota13.msm8916.com/api" CM_BUILDTYPE=NIGHTLY
	elif [ "x$ver" == "x14.1" ]; then
		exit_on_failure make -j${JOB_NUMBER} $BUILD_TARGET CM_UPDATER_OTA_URI="cm.updater.uri=http://ota14.msm8916.com/api" CM_BUILDTYPE=NIGHTLY
	elif [ "x$ver" == "x15.0" ]; then
		exit_on_failure make -j${JOB_NUMBER} $BUILD_TARGET CM_UPDATER_OTA_URI="cm.updater.uri=http://ota15.msm8916.com/api" CM_BUILDTYPE=NIGHTLY
	else
		exit_on_failure make -j${JOB_NUMBER} $BUILD_TARGET CM_UPDATER_OTA_URI="cm.updater.uri=http://ota.msm8916.com/api" CM_BUILDTYPE=NIGHTLY
	fi
	#build su
	#if [ $ver == "13.0" ] && [ "$BUILD_TARGET" != "recoveryimage" ] && [ "$BUILD_TARGET" != "bootimage" ]; then
		#exit_on_failure make -j${JOB_NUMBER} addonsu
	#fi
}

function generate_changes {
	logb "Generating changes..."

	# use a preset time (6 days ago)
	dates=$(date -d "`date` - 6 days" +%Y%m%d)

	cd ${platform_common_dir}

	changelog_name=changelog-${arc_name}.txt

	echo -e "\nMSM8916-COMMON\n---------\n" > ${BUILD_TEMP}/${changelog_name}

	git log --decorate=full \
		--since=$(date -d ${dates[0]} +%m-%d-%Y) >> ${BUILD_TEMP}/${changelog_name}

	cd ${ANDROID_BUILD_TOP}/kernel/${vendors[0]}/${kernel_name}

	echo -e "\nKERNEL\n---------\n" >> ${BUILD_TEMP}/${changelog_name}

	git log --decorate=full \
		--since=$(date -d ${dates[0]} +%m-%d-%Y) >> ${BUILD_TEMP}/${changelog_name}

	if [ "x$BUILD_TARGET" == "xotapackage" ]; then
		#generate the changes
		cd ${ANDROID_BUILD_TOP}/device/${vendors[0]}/${DEVICE_NAME}

		echo -e "\nDEVICE\n---------\n" >> ${BUILD_TEMP}/${changelog_name}

		git log --decorate=full \
			--since=$(date -d ${dates[0]} +%m-%d-%Y) >> ${BUILD_TEMP}/${changelog_name}

		cd ${common_dir}

		echo -e "\nDEVICE-COMMON\n---------\n" >> ${BUILD_TEMP}/${changelog_name}

		git log --decorate=full \
			--since=$(date -d ${dates[0]} +%m-%d-%Y) >> ${BUILD_TEMP}/${changelog_name}

		cd ${ANDROID_BUILD_TOP}/vendor/${vendors[0]}/${DEVICE_NAME}

		echo -e "\nVENDOR\n---------\n" >> ${BUILD_TEMP}/${changelog_name}

		git log --decorate=full \
			--since=$(date -d ${dates[0]} +%m-%d-%Y) >> ${BUILD_TEMP}/${changelog_name}

	fi

	rsync_cp ${BUILD_TEMP}/${changelog_name} ${OUTPUT_DIR}/builds/full/${changelog_name}
}

