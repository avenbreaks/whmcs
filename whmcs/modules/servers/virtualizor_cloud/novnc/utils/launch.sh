#!/usr/bin/env bash

# Copyright (C) 2018 The noVNC Authors
# Licensed under MPL 2.0 or any later version (see LICENSE.txt)

usage() {
    if [ "$*" ]; then
        echo "$*"
        echo
    fi
    echo "Usage: ${NAME} [--listen PORT] [--vnc VNC_HOST:PORT] [--cert CERT] [--ssl-only]"
    echo
    echo "Starts the WebSockets proxy and a mini-webserver and "
    echo "provides a cut-and-paste URL to go to."
    echo
    echo "    --listen PORT         Port for proxy/webserver to listen on"
    echo "                          Default: 6080"
    echo "    --vnc VNC_HOST:PORT   VNC server host:port proxy target"
    echo "                          Default: localhost:5900"
    echo "    --cert CERT           Path to combined cert/key file, or just"
    echo "                          the cert file if used with --key"
    echo "                          Default: self.pem"
    echo "    --key KEY             Path to key file, when not combined with cert"
    echo "    --web WEB             Path to web files (e.g. vnc.html)"
    echo "                          Default: ./"
    echo "    --ssl-only            Disable non-https connections."
    echo "                                    "
    echo "    --record FILE         Record traffic to FILE.session.js"
    echo "                                    "
    echo "    --syslog SERVER       Can be local socket such as /dev/log, or a UDP host:port pair."
    echo "                                    "
    echo "    --heartbeat SEC       send a ping to the client every SEC seconds"
    echo "    --timeout SEC         after SEC seconds exit when not connected"
    echo "    --idle-timeout SEC    server exits after SEC seconds if there are no"
    echo "                          active connections"
    echo "                                    "
    exit 2
}

NAME="$(basename $0)"
REAL_NAME="$(readlink -f $0)"
HERE="$(cd "$(dirname "$REAL_NAME")" && pwd)"
PORT="6080"
VNC_DEST="localhost:5900"
CERT=""
KEY=""
WEB=""
proxy_pid=""
SSLONLY=""
RECORD_ARG=""
SYSLOG_ARG=""
HEARTBEAT_ARG=""
IDLETIMEOUT_ARG=""
TIMEOUT_ARG=""

die() {
    echo "$*"
    exit 1
}

cleanup() {
    trap - TERM QUIT INT EXIT
    trap "true" CHLD   # Ignore cleanup messages
    echo
    if [ -n "${proxy_pid}" ]; then
        echo "Terminating WebSockets proxy (${proxy_pid})"
        kill ${proxy_pid}
    fi
}

# Process Arguments

# Arguments that only apply to chrooter itself
while [ "$*" ]; do
    param=$1; shift; OPTARG=$1
    case $param in
    --listen)  PORT="${OPTARG}"; shift            ;;
    --vnc)     VNC_DEST="${OPTARG}"; shift        ;;
    --cert)    CERT="${OPTARG}"; shift            ;;
    --key)     KEY="${OPTARG}"; shift             ;;
    --web)     WEB="${OPTARG}"; shift            ;;
    --ssl-only) SSLONLY="--ssl-only"             ;;
    --record) RECORD_ARG="--record ${OPTARG}"; shift ;;
    --syslog) SYSLOG_ARG="--syslog ${OPTARG}"; shift ;;
    --heartbeat) HEARTBEAT_ARG="--heartbeat ${OPTARG}"; shift ;;
    --idle-timeout) IDLETIMEOUT_ARG="--idle-timeout ${OPTARG}"; shift ;;
    --timeout) TIMEOUT_ARG="--timeout ${OPTARG}"; shift ;;
    -h|--help) usage                              ;;
    -*) usage "Unknown chrooter option: ${param}" ;;
    *) break                                      ;;
    esac
done

# Sanity checks
if bash -c "exec 7<>/dev/tcp/localhost/${PORT}" &> /dev/null; then
    exec 7<&-
    exec 7>&-
    die "Port ${PORT} in use. Try --listen PORT"
else
    exec 7<&-
    exec 7>&-
fi

trap "cleanup" TERM QUIT INT EXIT

# Find vnc.html
if [ -n "${WEB}" ]; then
    if [ ! -e "${WEB}/vnc.html" ]; then
        die "Could not find ${WEB}/vnc.html"
    fi
elif [ -e "$(pwd)/vnc.html" ]; then
    WEB=$(pwd)
elif [ -e "${HERE}/../vnc.html" ]; then
    WEB=${HERE}/../
elif [ -e "${HERE}/vnc.html" ]; then
    WEB=${HERE}
elif [ -e "${HERE}/../share/novnc/vnc.html" ]; then
    WEB=${HERE}/../share/novnc/
else
    die "Could not find vnc.html"
fi

# Find self.pem
if [ -n "${CERT}" ]; then
    if [ ! -e "${CERT}" ]; then
        die "Could not find ${CERT}"
    fi
elif [ -e "$(pwd)/self.pem" ]; then
    CERT="$(pwd)/self.pem"
elif [ -e "${HERE}/../self.pem" ]; then
    CERT="${HERE}/../self.pem"
elif [ -e "${HERE}/self.pem" ]; then
    CERT="${HERE}/self.pem"
else
    echo "Warning: could not find self.pem"
fi

# Check key file
if [ -n "${KEY}" ]; then
    if [ ! -e "${KEY}" ]; then
        die "Could not find ${KEY}"
    fi
fi

# try to find websockify (prefer local, try global, then download local)
if [[ -d ${HERE}/websockify ]]; then
    WEBSOCKIFY=${HERE}/websockify/run

    if [[ ! -x $WEBSOCKIFY ]]; then
        echo "The path ${HERE}/websockify exists, but $WEBSOCKIFY either does not exist or is not executable."
        echo "If you intended to use an installed websockify package, please remove ${HERE}/websockify."
        exit 1
    fi

    echo "Using local websockify at $WEBSOCKIFY"
else
    WEBSOCKIFY_FROMSYSTEM=$(which websockify 2>/dev/null)
    WEBSOCKIFY_FROMSNAP=${HERE}/../usr/bin/python2-websockify
    [ -f $WEBSOCKIFY_FROMSYSTEM ] && WEBSOCKIFY=$WEBSOCKIFY_FROMSYSTEM
    [ -f $WEBSOCKIFY_FROMSNAP ] && WEBSOCKIFY=$WEBSOCKIFY_FROMSNAP

    if [ ! -f "$WEBSOCKIFY" ]; then
        echo "No installed websockify, attempting to clone websockify..."
        WEBSOCKIFY=${HERE}/websockify/run
        git clone https://github.com/novnc/websockify ${HERE}/websockify

        if [[ ! -e $WEBSOCKIFY ]]; then
            echo "Unable to locate ${HERE}/websockify/run after downloading"
            exit 1
        fi

        echo "Using local websockify at $WEBSOCKIFY"
    else
        echo "Using installed websockify at $WEBSOCKIFY"
    fi
fi

echo "Starting webserver and WebSockets proxy on port ${PORT}"
#${HERE}/websockify --web ${WEB} ${CERT:+--cert ${CERT}} ${PORT} ${VNC_DEST} &
${WEBSOCKIFY} ${SYSLOG_ARG} ${SSLONLY} --web ${WEB} ${CERT:+--cert ${CERT}} ${KEY:+--key ${KEY}} ${PORT} ${VNC_DEST} ${HEARTBEAT_ARG} ${IDLETIMEOUT_ARG} ${RECORD_ARG} ${TIMEOUT_ARG} &
proxy_pid="$!"
sleep 1
if ! ps -p ${proxy_pid} >/dev/null; then
    proxy_pid=
    echo "Failed to start WebSockets proxy"
    exit 1
fi

echo -e "\n\nNavigate to this URL:\n"
if [ "x$SSLONLY" == "x" ]; then
    echo -e "    http://$(hostname):${PORT}/vnc.html?host=$(hostname)&port=${PORT}\n"
else
    echo -e "    https://$(hostname):${PORT}/vnc.html?host=$(hostname)&port=${PORT}\n"
fi

echo -e "Press Ctrl-C to exit\n\n"

wait ${proxy_pid}
