#!/bin/bash
# Copyright 2015 Axel Etcheverry
# Distributed under the terms of the MIT


GENTOO_FUNC=${PORTAGE_BIN_PATH:-/usr/lib/portage/bin}/isolated-functions.sh
DATA_DIR=$(pwd)/data
LOGGER=$(pwd)/create.log
BUILD_DIR=$(pwd)/build

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

if [ ! -d $BUILD_DIR ]; then
    mkdir -p $BUILD_DIR
fi

if [[ -z $STAGE3 ]]
then
    ebegin "Fetch latest stage3"
    STAGE3=$(wget -O - http://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64.txt 2> /dev/null | sed -n 3p | awk -F'/' '{ print $1}')
    eend $?
fi

einfo "Release: ${STAGE3:0:4}-${STAGE3:4:2}-${STAGE3:6}"

STAGE3_FILE="$DATA_DIR/stage3-amd64-$STAGE3.tar.bz2"

IMAGE_NAME="gentoo-temp:stage3-amd64-$STAGE3"
CONTAINER_NAME="gentoo-temp-stage3-amd64-$STAGE3"
CONTAINER_FILE="$BUILD_DIR/gentoo-base.tar.xz"

SRC="http://distfiles.gentoo.org/releases/amd64/autobuilds/$STAGE3/stage3-amd64-$STAGE3.tar.bz2"

if [ ! -f "$STAGE3_FILE" ]; then
    ebegin "Download stage3-amd64-$STAGE3.tar.bz2"
    wget -N "$SRC" -O "$STAGE3_FILE" > /dev/null 1> /dev/null 2> /dev/null
    eend $?
fi

ebegin "Import stage3 in docker"
bzcat "$STAGE3_FILE" | docker import - "$IMAGE_NAME" > /dev/null 2>> $LOGGER
eend $?

if [ $? ]; then
    exit 1
fi

ebegin "Remove old Gentoo container"
docker rm -f "$CONTAINER_NAME" > /dev/null 2>> $LOGGER || true
eend $?

ebegin "Configure Gentoo"
docker run -t -v /usr/portage:/usr/portage:ro --name "$CONTAINER_NAME" "$IMAGE_NAME" bash -exc $'
    export MAKEOPTS="-j$(nproc)"
    pythonTarget="$(emerge --info | sed -n \'s/.*PYTHON_TARGETS="\\([^"]*\\)".*/\\1/p\')"
    pythonTarget="${pythonTarget##* }"
    echo \'PYTHON_TARGETS="\'$pythonTarget\'"\' >> /etc/portage/make.conf
    echo \'PYTHON_SINGLE_TARGET="\'$pythonTarget\'"\' >> /etc/portage/make.conf
    emerge --newuse --deep --with-bdeps=y @system @world
    emerge -C editor ssh man man-pages openrc e2fsprogs texinfo service-manager
    emerge --depclean
' >> $LOGGER
eend $?

ebegin "Export container"
docker export "$CONTAINER_NAME" | xz -9 > "$CONTAINER_FILE" >> $LOGGER
eend $?

ebegin "Remove container"
docker rm "$CONTAINER_NAME" >> $LOGGER
eend $?

ebegin "Remove image"
docker rmi "$IMAGE_NAME" >> $LOGGER
eend $?

echo 'FROM scratch' > $BUILD_DIR/Dockerfile
echo "ADD $CONTAINER_FILE /" >> $BUILD_DIR/Dockerfile
echo 'CMD ["/bin/bash"]' >> $BUILD_DIR/Dockerfile

ebegin "Fetch username"
DOCKER_USER=$(docker info | awk '/^Username:/ { print $2 }')
if [ -z "$DOCKER_USER" ]; then
    eend 1
    exit $?
else
    eend 0
fi

ebegin "Build container"
docker build -t "$DOCKER_USER/gentoo-base" . >> $LOGGER
eend $?

