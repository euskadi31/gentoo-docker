#!/bin/bash
# Copyright 2015 Axel Etcheverry
# Distributed under the terms of the MIT


GENTOO_FUNC=${PORTAGE_BIN_PATH:-/usr/lib/portage/bin}/isolated-functions.sh
DATA_DIR=$(pwd)/data
IMAGE_NAME="gentoo-base"
LOGGER=$(pwd)/create.log

if [ ! -f $GENTOO_FUNC ]; then
    source eapi.sh
else
    source "${GENTOO_FUNC}"
fi

check_command() {
    which $1 > /dev/null

    if [[ $? -eq 1 ]]; then
        eerror "Please install $1"
        exit 1
    fi
}

check_command wget
check_command docker
check_command bzcat

if [ ! -d $DATA_DIR ]; then
    mkdir -p $DATA_DIR
fi


if [[ -z $STAGE3 ]]
then
    ebegin "Fetch latest stage3"
    STAGE3=$(wget -O - http://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64.txt 2> /dev/null | sed -n 3p | awk -F'/' '{ print $1}')
    eend $?
fi

einfo "Release: ${STAGE3:0:4}-${STAGE3:4:2}-${STAGE3:6}"

STAGE3_FILE="$DATA_DIR/stage3-amd64-$STAGE3.tar.bz2"

SRC="http://distfiles.gentoo.org/releases/amd64/autobuilds/$STAGE3/stage3-amd64-$STAGE3.tar.bz2"

if [ ! -f "$STAGE3_FILE" ]; then
    ebegin "Download stage3-amd64-$STAGE3.tar.bz2"
    wget -N "$SRC" -O "$STAGE3_FILE" > /dev/null 1> /dev/null 2> /dev/null
    eend $?
fi

ebegin "Import stage3 in docker"
bzcat "$STAGE3_FILE" | docker import - "$IMAGE_NAME" 2>> $LOGGER
eend $?

if [ $? ]; then
    exit 1
fi


