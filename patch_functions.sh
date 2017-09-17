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


PATCH_DIR=$BUILD_TEMP/patches

function extract_patches {
	mkdir -p ${PATCH_DIR}

	for ix in `seq 0 $((${#PRE_PATCH_FUNCTIONS[@]}-1))`; do
		echoTextBlue "Running function ${PRE_PATCH_FUNCTIONS[$ix]}"
		${PRE_PATCH_FUNCTIONS[$ix]} $@
	done

	for ix in `seq 0 $((${#PATCH_FUNCTIONS[@]}-1))`; do
		echoTextBlue "Running function ${PATCH_FUNCTIONS[$ix]}"
		${PATCH_FUNCTIONS[$ix]} $@
	done
}

function apply_repo_map {
	echoTextBold "Applying custom repository branch maps.."
	count=0
	for ix in `seq 0 $((${#REPO_REF_MAP[@]}-1))`; do
		count=$((count+1))
		repo=`echo ${REPO_REF_MAP[$ix]} | cut -d ':' -f 1`
		branch=`echo ${REPO_REF_MAP[$ix]} | cut -d ':' -f 2`

		if [ -d "${BUILD_TOP}/$repo" ]; then
			local GIT="git -C ${BUILD_TOP}/$repo"

			echoTextBlue "Repo is $repo. Reverting..."
			cd ${BUILD_TOP} && repo sync $repo -d

			echoTextBlue "Removing rogue patches in $repo..."
			${GIT} diff | patch -Rp1
			echoTextBlue "Fetching and checking out ref $ref..."
			${GIT} fetch github $ref && ${GIT} checkout FETCH_HEAD
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
		branch=`echo ${REPO_REF_MAP[$ix]} | cut -d ':' -f 2`

		if [ -d "${BUILD_TOP}/$repo" ]; then
			local GIT="git -C ${BUILD_TOP}/$repo"

			echoTextBlue "Repo is $repo.\n Reverting..."
			cd ${BUILD_TOP} && repo sync $repo -d

			echoTextBlue "Removing rogue patches in $repo..."
			${GIT} diff | patch -Rp1
		fi
		echo
	done

	if [ $count -eq 0 ]; then
		echoTextBold "No branch maps to apply."
	fi
}

function apply_patch {

	if ! [ -e ${BUILD_TOP}/.patched ]; then
		echoTextBlue "Patching build top..."
		cd ${BUILD_TOP}

		count=0

		for patch_file in $(find ${platform_common_dir}/patch/ -type f 2>/dev/null | sort); do
			# test applying the patch
			cat ${patch_file} | patch -p1 --dry-run -f

			if [ $? -eq 0 ]; then
				cat  ${patch_file} | patch -p1 -f 1>/dev/null 2>/dev/null
				count=$(($count+1))
			else
				echoText "Failed to apply patch ${patch_file}! Fix this."
			fi
		done

		for patch_file in $(find ${PATCH_DIR} -type f 2>/dev/null | sort); do
			# test applying the patch
			cat ${patch_file} | patch -p1 -f --dry-run

			if [ $? -eq 0 ]; then
				cat ${patch_file} | patch -p1 -f 1>/dev/null 2>/dev/null
				count=$(($count+1))
			else
				echoText "Failed to apply patch ${patch_file}! Fix this."
			fi
		done

		if [ ${count} -eq 0 ]; then
			echoTextBlue "Nothing to patch."
		else
			echoTextBlue "Removing patch artifacts..."
			cd ${BUILD_TOP}/frameworks
			find -name '*.orig' | xargs rm -f
			find -name '*.rej' | xargs rm -f

			cd ${BUILD_TOP}/packages
			find -name '*.orig' | xargs rm -f
			find -name '*.rej' | xargs rm -f

			cd ${BUILD_TOP}/system
			find -name '*.orig' | xargs rm -f
			find -name '*.rej' | xargs rm -f
			touch ${BUILD_TOP}/.patched

			logb "Done."
		fi

		echoTextBlue "Replacing ld.gold ..."
		for ld_bin in $(ls prebuilts/gcc/linux-x86/host/x86_64-linux-glibc*/x86_64-linux/bin/ld 2>/dev/null); do
			cp ${ld_bin} ${ld_bin}.old
			cp $(which ld.gold) $ld_bin
		done

		logb "Done."
		cd $OLDPWD
	fi
}

function reverse_patch {

	if [ -e ${BUILD_TOP}/.patched ]; then
		echoTextBlue "Unpatching build top..."
		cd ${BUILD_TOP}
		count=0

		for patch_file in $(find ${platform_common_dir}/patch/ -type f 2>/dev/null | sort -r); do
			# test applying the patch
			cat ${patch_file} | patch -Rp1 --dry-run -f

			if [ $? -eq 0 ]; then
				cat ${patch_file} | patch -Rp1 -f 1>/dev/null 2>/dev/null
				count=$(($count+1))
			else
				echoText "Failed to apply patch ${patch_file}! Fix this."
			fi
		done

		for patch_file in $(find ${PATCH_DIR} -type f 2>/dev/null | sort -r); do
			# test applying the patch
			cat  ${patch_file} | patch -Rp1 --dry-run -f

			if [ $? -eq 0 ]; then
				cat ${patch_file} | patch -Rp1 -f 1>/dev/null 2>/dev/null
				count=$(($count+1))
			else
				echoText "Failed to apply patch ${patch_file}! Fix this."
			fi
		done

		if [ ${count} -eq 0 ]; then
			logb "Nothing to patch."
		else
			echoTextBlue "Removing patch artifacts..."
			cd ${BUILD_TOP}/frameworks
			find -name '*.orig' | xargs rm -f
			find -name '*.rej' | xargs rm -f

			cd ${BUILD_TOP}/packages
			find -name '*.orig' | xargs rm -f
			find -name '*.rej' | xargs rm -f

			cd ${BUILD_TOP}/system
			find -name '*.orig' | xargs rm -f
			find -name '*.rej' | xargs rm -f

			rm ${BUILD_TOP}/.patched
			logb "Done."
		fi

		echoTextBlue "Replacing ld.gold ..."
		for ld_bin in $(ls prebuilts/gcc/linux-x86/host/x86_64-linux-glibc*/x86_64-linux/bin/ld 2>/dev/null); do
			cp ${ld_bin}.old ${ld_bin}
			rm ${ld_bin}.old -f
		done
		logb "Done."
		cd $OLDPWD
	fi
}

