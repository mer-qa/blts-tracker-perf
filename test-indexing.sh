#!/bin/bash
#
# blts-tracker-perf - tracker performance test suite
#
# Copyright (C) 2013 Jolla Ltd.
# Contact: Martin Kampas <martin.kampas@jollamobile.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

. $(dirname $0)/common.sh

TRACKER_CONF_PREFIX="/org/freedesktop/tracker"
MINER_FS_CONF_PREFIX="${TRACKER_CONF_PREFIX}/miner/files"
SAVED_TRACKER_CONF="/tmp/blts-tracker-perf.saved-tracker-settings.xml"
TIME_FILE="/tmp/blts-tracker-perf.time"
TEST_DATA_DIR="$(pwd)/blts-tracker-perf.data"

TEST_DATA_SRC_DIR="/usr/share/tracker-tests/test-extraction-data"
[[ -d ${TEST_DATA_SRC_DIR} ]] || { cat >&2; exit 1; } <<END
FIXME: required tracker's test data not found on expected path:
  ${TEST_DATA_SRC_DIR}
END

# Wipes out current tracker configuration, storing it so it can be restored
# later with tracker_config_restore()
tracker_config_wipe_out()
{
    gconftool-2 --dump ${TRACKER_CONF_PREFIX} |tee ${SAVED_TRACKER_CONF} |gconftool-2 --unload -
}

# Restores tracker configuration to the state before tracker_config_wipe_out()
# was called
tracker_config_restore()
{
    gconftool-2 --dump ${TRACKER_CONF_PREFIX} |gconftool-2 --unload -
    gconftool-2 --load ${SAVED_TRACKER_CONF}
}

tracker_config_set_string_list()
{
    gconftool-2 --set "${MINER_FS_CONF_PREFIX}/${1?}" --type list --list-type string "${2?}"
}

test_data_dir_disk_usage()
{
    UNIT=${1?}

    if [[ ! -e ${TEST_DATA_DIR} ]]
    then
        echo 0
        return
    fi

    du --summarize --block-size=1${UNIT} ${TEST_DATA_DIR} |awk '{ print $1 }'
}

# Copies test data installed by tracker-tests package into test data directory
test_data_dir_init()
{
    REQUIRED_DISK_USAGE=${1}

    REQUIRED_DISK_USAGE_=${REQUIRED_DISK_USAGE:0:((${#REQUIRED_DISK_USAGE} - 1))} # bash v3 compat
    UNIT=${REQUIRED_DISK_USAGE: -1}

    SRC_FILES=($(find ${TEST_DATA_SRC_DIR} -type f -a ! -name '*.expected'))

    rm -rf "${TEST_DATA_DIR}"

    i=0
    while [[ $(test_data_dir_disk_usage ${UNIT}) -lt ${REQUIRED_DISK_USAGE_} ]]
    do
        src_file=${SRC_FILES[i]}
        src_dir=$(dirname ${src_file})
        file_name=$(basename ${src_file})
        file_name_base=${file_name%.*}
        file_name_ext=${file_name##*.}
        dst_dir=${TEST_DATA_DIR}${src_dir}
        dst_idx=$(shopt -s nullglob; echo ${dst_dir}/${file_name_base}.*.${file_name_ext} |wc -w)
        dst_file=${dst_dir}/${file_name_base}.${dst_idx}.${file_name_ext}

        install -D --no-target-directory ${src_file} ${dst_file}

        i=$(( (i + 1) % ${#SRC_FILES[*]} ))
    done
}

test_data_dir_wipe_out()
{
    rm -rf "${TEST_DATA_DIR}"
}

# Queries the number of files under the test data directory (including the
# directory itself) currently indexed by tracker
test_data_dir_indexed_files_count()
{
    tracker-sparql --query '
        SELECT count(?s)
        WHERE {
            ?s nie:url ?p
            FILTER(regex(str(?p), "^file://'${TEST_DATA_DIR}'(/|$)"))
        }
        ' |tr -dc '0-9'
}

# Queries the number of files under the test data directory (including the
# directory itself)
test_data_dir_files_count()
{
    find ${TEST_DATA_DIR} |wc -l
}

print_help()
{
    cat >&2 <<END
Usage: $(basename $0) -o output_file TEST_DATA_SIZE{k|m|g}

Builds a test data set of given size by making copies of test data available
in tracker-tests package and meassures the time necessary to index that data.

Testing is done in a subdirectory of current working directory.

OPTIONS

    -o output_file
        Write meassured times in format accepted by \`testrunner-lite' into
        this file.

END
}

while [[ ${OPTIND:-0} -le ${#*} ]]
do
    if getopts "ho:" OPTNAME "${@}"
    then
        case "${OPTNAME}" in
            h)
                print_help
                exit 1
                ;;
            o)
                OUTPUT_FILE="${OPTARG}"
                ;;
        esac
    else
        eval NON_SWITCH=\$${OPTIND}
        if [[ ! ( ${NON_SWITCH} =~ ^[1-9][0-9]*[kKmMgG]$ ) || -n ${TEST_DATA_SIZE} ]]
        then
            print_help
            exit 1
        fi

        TEST_DATA_SIZE=${NON_SWITCH}

        let OPTIND++
    fi
done

[[ -n ${OUTPUT_FILE} ]] || { print_help; exit 1; }
[[ -n ${TEST_DATA_SIZE} ]] || { print_help; exit 1; }

set -o errexit
trap cleanup EXIT INT TERM

: > ${OUTPUT_FILE}

cleanup_push rm -f ${TIME_FILE}

INFO "Shutting down running tracker instance"

tracker-control -t && sleep 2 && cleanup_push tracker-control -s

INFO "Configuring tracker to only index our test data directory"

tracker_config_wipe_out && cleanup_push tracker_config_restore
tracker_config_set_string_list index-single-directories "[]"
tracker_config_set_string_list index-recursive-directories "[${TEST_DATA_DIR}]"

INFO "Preparing test data directory"

test_data_dir_init ${TEST_DATA_SIZE} && cleanup_push test_data_dir_wipe_out

INFO "Starting sandboxed tracker store"

sandbox_init && cleanup_push sandbox_wipe_out
store_start && cleanup_push store_shutdown

INFO "Starting the miner now"

command time -p --output=${TIME_FILE} /usr/libexec/tracker-miner-fs -v 0 --no-daemon

INFO "Indexing finished"

# Verify all test data has been indexed
indexed=$(test_data_dir_indexed_files_count)
current=$(test_data_dir_files_count)
if [[ ${indexed} -ne ${current} ]]
then
    INFO "Indexed test data dir files count (${indexed}) differs from the " \
        "current (${current}) files count!"
fi

INFO "Shutting down sandboxed tracker store"

cleanup_pop store_shutdown

INFO "Cleaning up"

cleanup_pop sandbox_wipe_out
cleanup_pop test_data_dir_wipe_out

INFO "Restoring original tracker configuration"

cleanup_pop tracker_config_restore

INFO "Restarting tracker"

cleanup_pop tracker-control -s

INFO "Results times:"
INFO < <(column -t ${TIME_FILE} |sed 's/^/\t/')

time2testrunner <${TIME_FILE} >${OUTPUT_FILE}

cleanup_pop rm -f ${TIME_FILE}

trap - EXIT INT TERM
