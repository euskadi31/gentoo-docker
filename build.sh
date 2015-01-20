#!/bin/bash
# Copyright 2015 Axel Etcheverry
# Distributed under the terms of the MIT

source func.sh

check_command wget
check_command docker
check_command bzcat
check_command gzip

LOGGER="$(pwd)/build.log"

if [ -z "$1" ]; then
    IMAGE_NAME="gentoo"
else
    IMAGE_NAME=$1
fi

einfo "Image name: $IMAGE_NAME"

if [[ -z $STAGE3 ]]
then
    ebegin "Fetch latest stage3"
    STAGE3=$(wget -O - http://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64.txt 2> /dev/null | sed -n 3p | awk -F'/' '{ print $1}')
    eend_exit $?
fi

CONTAINER_TMP_NAME="$IMAGE_NAME-tmp"
CONTAINER_FILE="$IMAGE_NAME-$STAGE3.tgz"
DATA_DIR=$(pwd)/data

if [ ! -d $DATA_DIR ]; then
    mkdir -p $DATA_DIR
fi

einfo "Release: ${STAGE3:0:4}-${STAGE3:4:2}-${STAGE3:6}"

SRC="http://distfiles.gentoo.org/releases/amd64/autobuilds/$STAGE3/stage3-amd64-$STAGE3.tar.bz2"
STAGE3_FILE="stage3-amd64-$STAGE3.tar.bz2"

if [ ! -f "$STAGE3_FILE" ]; then
    ebegin "Download $STAGE3_FILE"
    wget -N "$SRC" -O "$STAGE3_FILE" > /dev/null 1> /dev/null 2> /dev/null
    eend_exit $?
fi

ebegin "Download portage"
wget -N "http://distfiles.gentoo.org/releases/snapshots/current/portage-latest.tar.xz" -O "$DATA_DIR/portage-latest.tar.xz" > /dev/null 1> /dev/null 2> $LOGGER
eend_exit $?

ebegin "Extract portage"
cd $DATA_DIR && tar -xf "portage-latest.tar.xz" && cd ../ 2>> $LOGGER
eend_exit $?

ebegin "Change permission"
chmod -R 0777 data/
eend $?

ebegin "Remove old Gentoo container"
docker rm -f "$CONTAINER_TMP_NAME" > /dev/null 2>> $LOGGER || true
eend $?

ebegin "Import stage3 in docker"
bzcat "$STAGE3_FILE" | docker import - "$IMAGE_NAME" > /dev/null 2>> $LOGGER
eend_exit $?

ebegin "Running Gentoo"
docker run --privileged=true -d -t -v $(pwd)/provision:/media/provision -v $(pwd)/data/portage:/usr/portage:rw --name "$CONTAINER_TMP_NAME" "$IMAGE_NAME" /bin/bash >> $LOGGER
eend_exit $?

ebegin "Install detect-cpu"
docker exec -t "$CONTAINER_TMP_NAME" cp /media/provision/etc/init.d/detect-cpu /etc/init.d/detect-cpu >> $LOGGER
eend_exit $?

ebegin "Config make.conf"
docker exec -t "$CONTAINER_TMP_NAME" cp /media/provision/etc/portage/make.conf /etc/portage/make.conf >> $LOGGER
eend_exit $?

ebegin "Config cpu.conf"
docker exec -t "$CONTAINER_TMP_NAME" cp /media/provision/etc/portage/cpu.conf /etc/portage/cpu.conf >> $LOGGER
eend_exit $?

ebegin "Config eix-sync"
docker exec -t "$CONTAINER_TMP_NAME" cp /media/provision/etc/eix-sync.conf /etc/eix-sync.conf >> $LOGGER
eend_exit $?

ebegin "Config eixrc"
docker exec -t "$CONTAINER_TMP_NAME" cp /media/provision/etc/eixrc /etc/eixrc >> $LOGGER
eend_exit $?

ebegin "Config nopurge"
docker exec -t "$CONTAINER_TMP_NAME" cp /media/provision/etc/locale.nopurge /etc/locale.nopurge >> $LOGGER
eend_exit $?

ebegin "Config openrc softlevel"
docker exec -t "$CONTAINER_TMP_NAME" cp /media/provision/run/openrc/softlevel /run/openrc/softlevel >> $LOGGER
eend_exit $?

ebegin "Config the rc_sys"
docker exec -t "$CONTAINER_TMP_NAME" sed -e 's/#rc_sys=""/rc_sys="lxc"/g' -i /etc/rc.conf >> $LOGGER
eend_exit $?

ebegin "Config the net.lo runlevel"
docker exec -t "$CONTAINER_TMP_NAME" ln -s /etc/init.d/net.lo /run/openrc/started/net.lo >> $LOGGER
eend_exit $?

ebegin "Config the net.eth0"
docker exec -t "$CONTAINER_TMP_NAME" ln -s /etc/init.d/net.lo /etc/init.d/net.eth0 >> $LOGGER
eend_exit $?

ebegin "Config the net.eth0 runlevel"
docker exec -t "$CONTAINER_TMP_NAME" ln -s /etc/init.d/net.eth0 /run/openrc/started/net.eth0 >> $LOGGER
eend_exit $?

ebegin "Config timezon"
docker exec -t "$CONTAINER_TMP_NAME" cp /media/provision/etc/timezone /etc/timezone >> $LOGGER
eend_exit $?

ebegin "Remove doc"
docker exec -t "$CONTAINER_TMP_NAME" rm -rf /usr/share/doc >> $LOGGER
eend_exit $?

ebegin "Remove info"
docker exec -t "$CONTAINER_TMP_NAME" rm -rf /usr/share/info >> $LOGGER
eend_exit $?

ebegin "Remove man"
docker exec -t "$CONTAINER_TMP_NAME" rm -rf /usr/share/man >> $LOGGER
eend_exit $?

ebegin "Remove gtk-doc"
docker exec -t "$CONTAINER_TMP_NAME" rm -rf /usr/share/gtk-doc >> $LOGGER
eend_exit $?

ebegin "Update env"
docker exec -t "$CONTAINER_TMP_NAME" env-update >> $LOGGER
eend_exit $?

ebegin "Install localepurge"
docker exec -t "$CONTAINER_TMP_NAME" emerge localepurge >> $LOGGER
eend_exit $?

ebegin "Run localepurge"
docker exec -t "$CONTAINER_TMP_NAME" localepurge >> $LOGGER
eend_exit $?

ebegin "Config portage bashrc"
docker exec -t "$CONTAINER_TMP_NAME" cp /media/provision/etc/portage/bashrc /etc/portage/bashrc >> $LOGGER
eend_exit $?

ebegin "Add detect-cpu to boot"
docker exec -t "$CONTAINER_TMP_NAME" rc-update add detect-cpu default >> $LOGGER
eend_exit $?

ebegin "Start detect-cpu"
docker exec -t "$CONTAINER_TMP_NAME" /etc/init.d/detect-cpu start >> $LOGGER
eend_exit $?

ebegin "Remove packages"
docker exec -t "$CONTAINER_TMP_NAME" emerge -C virtual/editor virtual/ssh sys-apps/openrc sys-fs/e2fsprogs virtual/service-manager >> $LOGGER
eend_exit $?

ebegin "Install default packages"
docker exec -t "$CONTAINER_TMP_NAME" emerge app-editors/vim dev-vcs/git net-misc/curl >> $LOGGER
eend_exit $?

ebegin "Clean dep"
docker exec -t "$CONTAINER_TMP_NAME" emerge --depclean >> $LOGGER
eend_exit $?

ebegin "Export container"
docker export "$CONTAINER_TMP_NAME" | gzip -c > "$CONTAINER_FILE"
eend_exit $?

ebegin "Remove $STAGE3_FILE"
rm -rf $STAGE3_FILE
eend $?

ebegin "Remove portage"
rm -rf data/
eend $?
