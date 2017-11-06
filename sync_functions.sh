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

function sync_manifests {
	if [ "x$ver" == "x13.0" ]; then
		manifest_name=los-13.0_manifest.xml
	elif [ "x$ver" == "x14.1" ]; then
		manifest_name=los-14.1_manifest.xml
	elif [ "x$ver" == "x15.0" ]; then
		manifest_name=los-15.0_manifest.xml
	fi
	manifest_dir=${BUILD_TOP}/.repo/local_manifests
	manifest_url="https://git.msm8916.com/Galaxy-MSM8916/local_manifests.git/plain"

	if [ "x${manifest_name}" != "x" ]; then
		mkdir -p ${manifest_dir}
		logb "Removing old manifests..."
		rm ${manifest_dir}/*xml

		logb "Syncing manifests..."
		${CURL} ${manifest_url}/${manifest_name} | tee ${manifest_dir}/${manifest_name} > /dev/null
	fi

    # Sync the substratum manifest
	if [ "x$ver" == "x14.1" ]; then
		logb "Syncing Substratum manifest..."
		mkdir -p ${manifest_dir}
		${CURL} --output ${manifest_dir}/substratum.xml \
		https://raw.githubusercontent.com/LineageOMS/merge_script/master/substratum.xml
	fi
}

function sync_vendor_trees {
if [ -n "$SYNC_VENDOR" ]; then
	logb "Syncing vendor trees..."
	cd ${BUILD_TOP}
	for vendor in ${vendors[*]}; do
		targets="device vendor kernel"
		for dir in ${targets}; do
			if ! [ -d ${dir}/${vendor} ]; then continue; fi
			repo sync ${dir}/${vendor}/* --force-sync --prune
		done
	done
	if [ "x$ver" == "x15.0" ]; then
		REPOPICK_FILE=${BUILD_TEMP}/repopicks.sh
		wget https://msm8916.com/~vincent/repopicks.sh -O $REPOPICK_FILE
		if [ "$?" -eq 0 ]; then
			echoText "Picking Lineage gerrit changes..."
			. $REPOPICK_FILE
		fi
	fi
fi
}

function sync_all_trees {
if [ -n "$SYNC_ALL" ]; then
	logb "Syncing all trees..."
	cd ${BUILD_TOP}

	# sync substratum if we're on LOS 14.1
	if [ "x$ver" == "x14.1" ]; then
		unsync_substratum
	fi

	repo sync --force-sync --prune

	# sync substratum if we're on LOS 14.1
	if [ "x$ver" == "x14.1" ]; then
		sync_substratum;
	fi

	cd $OLDPWD
fi
}

function sync_script {
	logb "Updating build script..."
	if [ -z "$UPDATE_SCRIPT" ]; then
		${CURL} ${SCRIPT_REPO_URL}/$(basename $0) | tee $0 > /dev/null
	else
		${CURL} ${SCRIPT_REPO_URL}/$(basename $0) | tee $0 > /dev/null && exit || exit
	fi
	logb "Done."
}
