#!/bin/bash
# Copyright 2015 Axel Etcheverry
# Distributed under the terms of the MIT

BUILD_DIR=$(pwd)/build

source func.sh

while true ; do
    case "$1" in
        -h|--help) usage;
            exit 0;;
        --enable-compilation) enable_feature "compilation";
            shift;;
        --) shift; break;;
        *) break;;
    esac
done

if [ -z "$1" ]; then
    TAG_NAME="gentoo"
else
    TAG_NAME=$1
fi

einfo "Tag name: $TAG_NAME"

if [ ! -z "$CONTAINER_FEATURES" ]; then
    einfo "Features: $CONTAINER_FEATURES"
fi

DATA_DIR=$(pwd)/data
LOGGER=$(pwd)/create.log

check_command wget
check_command docker
#check_command bzcat
check_command bunzip2
check_command xz

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

SRC="http://distfiles.gentoo.org/releases/amd64/autobuilds/$STAGE3/stage3-amd64-$STAGE3.tar.bz2"

if [ ! -f "$STAGE3_FILE" ]; then
    ebegin "Download stage3-amd64-$STAGE3.tar.bz2"
    wget -N "$SRC" -O "$STAGE3_FILE" > /dev/null 1> /dev/null 2> /dev/null
    eend $?
fi

if [ ! -f "$BUILD_DIR/stage3-amd64.tar.xz" ]; then
    ebegin "Transforming bz2 tarball to xz (golang bug)."
    bunzip2 -c "$STAGE3_FILE" | xz -z > "$BUILD_DIR/stage3-amd64.tar.xz"
    eend $?
fi

if [ -f "$BUILD_DIR/Dockerfile" ]; then
    ebegin "Clean Dockerfile"
    rm -f "$BUILD_DIR/Dockerfile"
    eend $?
fi

ebegin "Generate Dockerfile"
dockerfile "FROM scratch"
dockerfile "MAINTAINER Axel Etcheverry"
dockerfile "# This one should be present by running the build.sh script"
dockerfile "ADD stage3-amd64.tar.xz /"
dockerfile "# Setup the (virtually) current runlevel"
dockerfile "RUN echo \"default\" > /run/openrc/softlevel"
dockerfile "# Setup the rc_sys"
dockerfile "RUN sed -e 's/#rc_sys=\"\"/rc_sys=\"lxc\"/g' -i /etc/rc.conf"
dockerfile "# Setup the net.lo runlevel"
dockerfile "RUN ln -s /etc/init.d/net.lo /run/openrc/started/net.lo"
dockerfile "# Setup the net.eth0 runlevel"
dockerfile "RUN ln -s /etc/init.d/net.lo /etc/init.d/net.eth0"
dockerfile "RUN ln -s /etc/init.d/net.eth0 /run/openrc/started/net.eth0"
dockerfile "# By default, UTC system"
dockerfile "RUN echo 'UTC' > /etc/timezone"
dockerfile "# Used when this image is the base of another"
dockerfile "#"
dockerfile "# Setup the portage directory and permissions"
dockerfile "ONBUILD RUN mkdir -p /usr/portage/{distfiles,metadata,packages}"
dockerfile "ONBUILD RUN chown -R portage:portage /usr/portage"
dockerfile "ONBUILD RUN echo \"masters = gentoo\" > /usr/portage/metadata/layout.conf"
dockerfile "# Sync portage"
dockerfile "ONBUILD RUN emerge-webrsync -q"
dockerfile "# Display some news items"
dockerfile "ONBUILD RUN eselect news read new"
dockerfile "# Finalization"
dockerfile "ONBUILD RUN env-update"

if [[ $(has_feature "compilation") -eq 0 ]]; then
    dockerfile "ONBUILD RUN emerge -C editor ssh man man-pages openrc e2fsprogs texinfo service-manager"
else
    # emerge -C autotools gcc al
    dockerfile "ONBUILD RUN emerge -C editor ssh man man-pages openrc e2fsprogs texinfo service-manager"
fi

eend 0

ebegin "Build container"
docker build -t "$TAG_NAME" build/ >> $LOGGER 2>> $LOGGER
eend $?
