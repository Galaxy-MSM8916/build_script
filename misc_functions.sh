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

function acquire_build_lock {

    local lock_name="android_build_lock"
    local lock="/var/lock/${lock_name}"

    exec 200>${lock}

    echoTextBlue "Attempting to acquire lock $lock..."

    # loop if we can't get the lock
    while true; do
        flock -n 200
        if [ $? -eq 0 ]; then
            break
        else
            printf "%c" "."
            sleep 5
        fi
    done

    # set the pid
    pid=$$
    echo ${pid} 1>&200

    echoTextBlue "Lock ${lock} acquired. PID is ${pid}"
}

function remove_build_lock {
    echoText "Removing lock..."
    exec 200>&-
}

function save_build_state {
    # save build state in the event a build terminates and another is enqueued
    if [ -n "${JOB_NAME}" ] && [ "x${BUILD_TARGET}" != "x" ] && [ "x${BUILD_VARIANT}" != "x" ]; then
        BUILD_STATE_FILE=$(mktemp -p ${SAVED_BUILD_JOBS_DIR})
        echoTextBlue "Saving build job name: \n${JOB_NAME}"

        # saves a file with the exact arguments used to launch the build
        echo ${JOB_NAME} > ${BUILD_STATE_FILE}
    fi
}

function restore_saved_build_state {
    local SSH="ssh ${SYNC_HOST} -p 53801 -o StrictHostKeyChecking=no"
    build_error=0
    if [ -z "${RESTORED_BUILD_STATE}" ] && [ "x${BUILD_TARGET}" != "x" ] && [ "x${BUILD_VARIANT}" != "x" ]; then
        seen_job_names=${JOB_NAME}
        for state_file in `find ${SAVED_BUILD_JOBS_DIR} -type f 2>/dev/null`; do
            launch_count=1
            target_job_name=$(cat $state_file)

            while [ -f "$state_file" ] && [ $launch_count -le $BUILD_RETRY_COUNT ]; do
                matched=0
                for i in $seen_job_names; do
                    if [ "$i" == "$target_job_name" ]; then
                        echoText "Job $target_job_name previously run or same as current job."
                        rm -f $state_file
                        matched=1
                        break
                    fi
                done
                if [ "$matched" -eq 0 ]; then
                    remove_build_lock
                    echoText "[${launch_count}/${BUILD_RETRY_COUNT}] Starting previously terminated build from saved build info.."
                    ${SSH} build ${target_job_name} -s -v \
                       -p "\"EXTRA_ARGS=--restored-state --node=$NODE_NAME\"" 1>/dev/null && rm -f $state_file
                    acquire_build_lock
                fi
                build_error=$?

                # increment counter
                launch_count=$((launch_count+1))
            done

            seen_job_names+=" $target_job_name"

            if [ "$build_error" -gt 0 ]; then
                echoTextRed "Failed to launch terminated build."
            fi
            rm -f $state_file
        done
    fi

    if [ -n "$TARGET_NODE" ] && [ "$TARGET_NODE" != "$NODE_NAME" ]; then
        if [ -n "$NODE_UNAVAILABLE_COUNT" ] && [ "$NODE_UNAVAILABLE_COUNT" -lt $BUILD_RETRY_COUNT ]; then
            echoTextRed "Build not running on same node as it was originally. Relaunching..."
            ${SSH} build ${JOB_NAME} -w \
                 -p "\"EXTRA_ARGS=--restored-state --node-unavail-count=$((NODE_UNAVAILABLE_COUNT+1)) --node=$TARGET_NODE\"" && rm -f $BUILD_STATE_FILE
            ${SSH} set-build-description ${JOB_NAME} $JOB_BUILD_NUMBER "\"Cancelled build to try running on node $TARGET_NODE.\""
            ${SSH} set-build-description ${JOB_NAME} $((JOB_BUILD_NUMBER+1)) "\"Cancelled build  #${JOB_BUILD_NUMBER} to try running on node $TARGET_NODE.\""
            remove_temp_dir
            exit 1
        else
            echoTextRed "Build failed to run on target node. Using current node..."
        fi
    fi
}

function clean_out {
    cd ${ANDROID_BUILD_TOP}/
    if [ "x${CLEAN_TARGET_OUT}" != "x" ] && [ ${CLEAN_TARGET_OUT} -eq 1 ]; then
        echoText "Cleaning build dir..."
        if [ "x$BUILD_TARGET" == "xotapackage" ]; then
            rm -rf out
        fi
    fi
}

function clean_target {
    echoText "Removing saved build state info.."
    rm -f ${BUILD_STATE_FILE}
    rmdir --ignore-fail-on-non-empty ${SAVED_BUILD_JOBS_DIR}

}

function remove_temp_dir {
    #start cleaning up
    echoText "Removing temp dir..."
    rm -rf $BUILD_TEMP
}

function exit_on_failure {
    echoTextBlue "Running command: $@"
    $@
    exit_error $?
}


function exit_error {
    if [ "x$1" != "x0" ]; then
        echoText "Error encountered, aborting..."
        if [ "x$SILENT" != "x1" ]; then
            END_TIME=$( date +%s )
            buildTime="%0A%0ABuild time: $(format_time ${END_TIME} ${BUILD_START_TIME})"
            totalTime="%0ATotal time: $(format_time ${END_TIME} ${START_TIME})"

            if [ "x$JOB_DESCRIPTION" != "x" ]; then
                textStr="$JOB_DESCRIPTION, build %23${JOB_BUILD_NUMBER}"
            else
                textStr="${distroTxt} ${ver} ${BUILD_TARGET} for the ${DEVICE_NAME}"
            fi

            textStr+=" aborted."

            textStr+="%0A%0AThis build was running on ${USER}@${HOSTNAME}."

            if [ "x${JOB_URL}" != "x" ]; then
                textStr+="%0A%0AYou can see the build log at:"
                textStr+="%0A${JOB_URL}/console"
            fi

            textStr+="${buildTime}${totalTime}"

            if [ "x$PRINT_VIA_PROXY" != "x" ] && [ "x$SYNC_HOST" != "x" ]; then
                timeout -s 9 20 ssh $SYNC_HOST wget \'"https://api.telegram.org/bot${BUILD_TELEGRAM_TOKEN}/sendMessage?chat_id=${BUILD_TELEGRAM_CHATID}&text=$textStr"\' -O - > /dev/null 2>/dev/null
            else

                timeout -s 9 10 wget "https://api.telegram.org/bot${BUILD_TELEGRAM_TOKEN}/sendMessage?chat_id=${BUILD_TELEGRAM_CHATID}&text=$textStr" -O - > /dev/null 2>/dev/null
            fi
        fi
        remove_temp_dir
        remove_build_lock
        exit 1
    fi
}

# PRINTS A FORMATTED HEADER TO POINT OUT WHAT IS BEING DONE TO THE USER
function echoText() {
    echoTextRed "$@"
}

function echoTextRed() {
    echo -e ${RED}
    echo -e "====$( for i in $( seq 1 `echo $@ | wc -c | sed s/[0-9]../100/g` ); do echo -e "=\c"; done )===="
    echo -e "==  ${@}  =="
    echo -e "====$( for i in $( seq 1 `echo $@ | wc -c | sed s/[0-9]../100/g` ); do echo -e "=\c"; done )===="
    echo -e ${RESTORE}
}

function echoTextBlue() {
    echo -e ${BLUE}
    echo -e "====$( for i in $( seq 1 `echo $@ | wc -c | sed s/[0-9]../100/g` ); do echo -e "=\c"; done )===="
    echo -e "==  ${@}  =="
    echo -e "====$( for i in $( seq 1 `echo $@ | wc -c | sed s/[0-9]../100/g` ); do echo -e "=\c"; done )===="
    echo -e ${RESTORE}
}

function echoTextGreen() {
    echo -e ${GREEN}
    echo -e "====$( for i in $( seq 1 `echo $@ | wc -c | sed s/[0-9]../100/g` ); do echo -e "=\c"; done )===="
    echo -e "==  ${@}  =="
    echo -e "====$( for i in $( seq 1 `echo $@ | wc -c | sed s/[0-9]../100/g` ); do echo -e "=\c"; done )===="
    echo -e ${RESTORE}
}

function echoTextBold() {
    echo -e ${BOLD}
    echo -e "====$( for i in $( seq 1 `echo $@ | wc -c | sed s/[0-9]../100/g` ); do echo -e "=\c"; done )===="
    echo -e "==  ${@}  =="
    echo -e "====$( for i in $( seq 1 `echo $@ | wc -c | sed s/[0-9]../100/g` ); do echo -e "=\c"; done )===="
    echo -e ${RESTORE}
}

# FORMATS THE TIME
function format_time() {
    MINS=$(((${1}-${2})/60))
    SECS=$(((${1}-${2})%60))
    if [[ ${MINS} -ge 60 ]]; then
        HOURS=$((${MINS}/60))
        MINS=$((${MINS}%60))
    fi

    if [[ ${HOURS} -eq 1 ]]; then
        TIME_STRING+="1 hour, "
    elif [[ ${HOURS} -ge 2 ]]; then
        TIME_STRING+="${HOURS} hours, "
    fi

    if [[ ${MINS} -eq 1 ]]; then
        TIME_STRING+="1 minute"
    else
        TIME_STRING+="${MINS} minutes"
    fi

    if [[ ${SECS} -eq 1 && -n ${HOURS} ]]; then
        TIME_STRING+=", and 1 second"
    elif [[ ${SECS} -eq 1 && -z ${HOURS} ]]; then
        TIME_STRING+=" and 1 second"
    elif [[ ${SECS} -ne 1 && -n ${HOURS} ]]; then
        TIME_STRING+=", and ${SECS} seconds"
    elif [[ ${SECS} -ne 1 && -z ${HOURS} ]]; then
        TIME_STRING+=" and ${SECS} seconds"
    fi

    echo ${TIME_STRING}
}

# CREATES A NEW LINE IN TERMINAL
function newLine() {
    echo -e ""
}

# PRINTS AN ERROR IN BOLD RED
function reportError() {
    RED="\033[01;31m"
    RESTORE="\033[0m"

    echo -e ""
    echo -e ${RED}"${1}"${RESTORE}
    if [[ -z ${2} ]]; then
        echo -e ""
    fi
}

