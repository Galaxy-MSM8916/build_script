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
	if [ "x$MANIFEST_NAME" == "x" ]; then
		MANIFEST_NAME=los-${ver}_manifest.xml
	fi
	manifest_dir=${BUILD_TOP}/.repo/local_manifests
	manifest_url="https://git.msm8916.com/Galaxy-MSM8916/local_manifests.git/plain"

	mkdir -p ${manifest_dir}
	logb "Removing old manifests..."
	rm ${manifest_dir}/*xml

	logb "Syncing manifests..."
	${CURL} ${manifest_url}/${MANIFEST_NAME} | tee ${manifest_dir}/${MANIFEST_NAME} > /dev/null

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

function apply_repo_map {
	echoTextBold "Applying custom repository branch maps.."
	count=0
	for ix in `seq 0 $((${#REPO_REF_MAP[@]}-1))`; do
		count=$((count+1))
		repo=`echo ${REPO_REF_MAP[$ix]} | cut -d ':' -f 1`
		ref=`echo ${REPO_REF_MAP[$ix]} | cut -d ':' -f 2`

		if [ -d "${BUILD_TOP}/$repo" ]; then
			local GIT="git -C ${BUILD_TOP}/$repo"

			echoTextBlue "Repo is $repo. Reverting..."
			cd ${BUILD_TOP} && repo sync $repo -d

			echoTextBlue "Deleting branch $ref."
			${GIT} branch -D $ref 2>/dev/null

			echoTextBlue "Removing rogue patches in $repo..."
			${GIT} diff | patch -Rp1
			echoTextBlue "Fetching and checking out ref $ref..."
			${GIT} fetch $($GIT remote show|head -1) $ref:$ref && ${GIT} checkout $ref || exit_error $?
		else
			echoTextRed "Directory $repo does not exist!!"
			exit_error 1
		fi
		echo
	done

	if [ $count -eq 0 ]; then
		echoTextBold "No branch maps to apply."
	fi
}

function reverse_repo_map {
	echoTextBold "Reversing custom repository branch maps.."
	count=0
	for ix in `seq 0 $((${#REPO_REF_MAP[@]}-1))`; do
		count=$((count+1))
		repo=`echo ${REPO_REF_MAP[$ix]} | cut -d ':' -f 1`
		ref=`echo ${REPO_REF_MAP[$ix]} | cut -d ':' -f 2`

		if [ -d "${BUILD_TOP}/$repo" ]; then
			local GIT="git -C ${BUILD_TOP}/$repo"

			echoTextBlue "Repo is $repo.\n Reverting..."
			cd ${BUILD_TOP} && repo sync $repo -d

			echoTextBlue "Deleting branch $ref."
			${GIT} branch -D $ref 2>/dev/null

			echoTextBlue "Removing rogue patches in $repo..."
			${GIT} diff | patch -Rp1
		fi
		echo
	done

	if [ $count -eq 0 ]; then
		echoTextBold "No branch maps to apply."
	fi
}

function apply_repopicks {
	cd ${BUILD_TOP}
	gerrit_url="https://review.msm8916.com"

	#pick local gerrit changes
	[ -n "$LOCAL_REPO_PICKS" ] && repopick -g $gerrit_url -r $LOCAL_REPO_PICKS
	[ -n "$LOCAL_REPO_TOPICS" ] && repopick -g $gerrit_url -r -t $LOCAL_REPO_TOPICS

	#pick lineage gerrit changes
	[ -n "$LINEAGE_REPO_PICKS" ] && repopick -r $LINEAGE_REPO_PICKS
	[ -n "$LINEAGE_REPO_TOPICS" ] && repopick -r -t $LINEAGE_REPO_TOPICS
}
