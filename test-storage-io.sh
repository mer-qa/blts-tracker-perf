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

IMPORT_TIME_FILE="/tmp/blts-tracker-perf.import-time"
QUERY_TIME_FILE="/tmp/blts-tracker-perf.import-query"
TEST_DATA_DIR="$(pwd)/blts-tracker-perf.data"

TEST_DATA_GENERATOR="/opt/tests/tracker/bin/generate"
[[ -f ${TEST_DATA_GENERATOR} ]] || { cat >&2; exit 1; } <<END
FIXME: required tracker's test data generator not found on expected path:
  ${TEST_DATA_GENERATOR}
END

# Uses tracker's test data generator to populate test data directory
test_data_dir_init()
{
    rm -rf "${TEST_DATA_DIR}"
    mkdir -p ${TEST_DATA_DIR}
    ( cd ${TEST_DATA_DIR} && mkdir ttl && ${TEST_DATA_GENERATOR} ${CONFIG_FILE} )
}

test_data_dir_wipe_out()
{
    rm -rf "${TEST_DATA_DIR}"
}

print_help()
{
    cat >&2 <<END
Usage: $(basename $0) -c config_file -o output_file

Invokes the \`tracker-import' utility to meassure how tracker performs on
inserting data. Then executes a SPARQL query to meassure how tracker performs
on quering data.

Test data is generated with tools available in tracker-tests package.

Testing is done in a subdirectory of current working directory, i.e., both
test data and tracker database are stored under current working directory.

OPTIONS

    -c config_file
        Configuration file to pass to ${TEST_DATA_GENERATOR}.

    -o output_file
        Write meassured times in format accepted by \`testrunner-lite' into
        this file.

END
}

while [[ ${OPTIND:-0} -le ${#*} ]]
do
    if getopts "hc:o:" OPTNAME "${@}"
    then
        case "${OPTNAME}" in
            h)
                print_help
                exit 1
                ;;
            c)
                CONFIG_FILE="${OPTARG}"
                ;;
            o)
                OUTPUT_FILE="${OPTARG}"
                ;;
        esac
    else
        print_help
        exit 1
    fi
done

[[ -n ${CONFIG_FILE} ]] || { print_help; exit 1; }
[[ -n ${OUTPUT_FILE} ]] || { print_help; exit 1; }

set -o errexit
trap cleanup EXIT INT TERM

: > ${OUTPUT_FILE}

cleanup_push rm -f ${IMPORT_TIME_FILE}
cleanup_push rm -f ${QUERY_TIME_FILE}

INFO "Preparing test data directory"

test_data_dir_init && cleanup_push test_data_dir_wipe_out

INFO "Starting sandboxed tracker store"

sandbox_init && cleanup_push sandbox_wipe_out
store_start && cleanup_push store_shutdown

INFO "Begining data import now"

command time -p --output=${IMPORT_TIME_FILE} tracker-import ${TEST_DATA_DIR}/ttl/*.ttl

INFO "Restarting tracker store before executing query"

cleanup_pop store_shutdown
store_start && cleanup_push store_shutdown

INFO "Begining data query now"

command time -p --output=${QUERY_TIME_FILE} tracker-sparql --query \
    'SELECT ?s { ?s rdf:type rdfs:Resource }' \
    |INFO "Found $(($(wc -l) - 1)) resources"

INFO "Shutting down sandboxed tracker store"

cleanup_pop store_shutdown

INFO "Cleaning up"

cleanup_pop sandbox_wipe_out
cleanup_pop test_data_dir_wipe_out

INFO "Results times - import:"
INFO < <(column -t ${IMPORT_TIME_FILE} |sed 's/^/\t/')
INFO "Results times - query:"
INFO < <(column -t ${QUERY_TIME_FILE} |sed 's/^/\t/')

{
  time2testrunner import <${IMPORT_TIME_FILE}
  time2testrunner query <${QUERY_TIME_FILE}
} >${OUTPUT_FILE}

cleanup_pop rm -f ${QUERY_TIME_FILE}
cleanup_pop rm -f ${IMPORT_TIME_FILE}

trap - EXIT INT TERM
