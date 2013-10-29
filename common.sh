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

SANDBOX_DIR="$(pwd)/blts-tracker-perf.sandbox"

INFO()
{
    TAG="== $(basename $0) == : "

    sed "s/^/${TAG}/" <<<"${*:-$(cat)}" >&2
}

sandbox_init()
{
    rm -rf "${SANDBOX_DIR}"
    mkdir -p ${SANDBOX_DIR}

    XDG_CACHE_HOME__old=${XDG_CACHE_HOME}
    export XDG_CACHE_HOME=${SANDBOX_DIR}
    XDG_CONFIG_HOME__old=${XDG_CONFIG_HOME}
    export XDG_CONFIG_HOME=${SANDBOX_DIR}
    XDG_DATA_HOME__old=${XDG_DATA_HOME}
    export XDG_DATA_HOME=${SANDBOX_DIR}
    XDG_RUNTIME_DIR__old=${XDG_RUNTIME_DIR}
    export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-${SANDBOX_DIR}}

    DBUS_SESSION_BUS_ADDRESS__old=${DBUS_SESSION_BUS_ADDRESS}
}

sandbox_wipe_out()
{
    kill ${DBUS_SESSION_BUS_PID}
    export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS__old}

    export XDG_CACHE_HOME=${XDG_CACHE_HOME__old}
    export XDG_CONFIG_HOME=${XDG_CONFIG_HOME__old}
    export XDG_DATA_HOME=${XDG_DATA_HOME__old}
    export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR__old}

    rm -rf "${SANDBOX_DIR}"
}

store_start()
{
    /usr/libexec/tracker-store &
    sleep 1
    TRACKER_STORE_PID=$!
}

store_shutdown()
{
    kill ${TRACKER_STORE_PID} && wait ${TRACKER_STORE_PID}
}

# Converts output produced by `time -p' so it is suitable for testrunner
time2testrunner()
{
    EXTRA="${1:+${1}.}"
    awk '{ printf "'${EXTRA}'elapsed.%s;%g;ms;\n", $1, $2 * 1000; }'
}

cleanup_push()
{
    CLEANUP=("${*?}" "${CLEANUP[@]}")
}

cleanup_pop()
{
    DO_SOMETHING="${*?}"
    if [[ ${DO_SOMETHING} != ${CLEANUP[0]} ]]
    then
        INFO "ERROR: cleanup: attempt to pop out of order: '${DO_SOMETHING}'"
        exit 1
    fi

    ${DO_SOMETHING}
    unset CLEANUP[0]
    CLEANUP=("${CLEANUP[@]}")
}

cleanup()
{
    trap - EXIT INT TERM

    for do_something in "${CLEANUP[@]}"
    do
        INFO "cleanup: ${do_something}..."
        ${do_something}
    done

    exit 1
}
