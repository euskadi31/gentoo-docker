#!/bin/bash
# Copyright 2015 Axel Etcheverry
# Distributed under the terms of the MIT

GENTOO_FUNC=${PORTAGE_BIN_PATH:-/usr/lib/portage/bin}/isolated-functions.sh

if [ ! -f $GENTOO_FUNC ]; then
    source eapi.sh
else
    source "${GENTOO_FUNC}"
fi

CONTAINER_FEATURES=""

check_command() {
    which $1 > /dev/null

    if [[ $? -eq 1 ]]; then
        eerror "Please install $1"
        exit 1
    fi
}

enable_feature() {
    CONTAINER_FEATURES="$CONTAINER_FEATURES $1"
}

has_feature() {
    if [[ $CONTAINER_FEATURES == *"$1"* ]]; then
        return 0
    fi

    return 1
}

usage() {
    SCRIPT_NAME=$(basename $BASH_SOURCE)
    echo "Usage: $SCRIPT_NAME OPTIONS"
    echo "\t--enable-compilation : Enable package of compilation in container"
}
