#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
host_uid=$(id -u)
host_gid=$(id -g)

docker run --rm \
    -e HOST_UID="$host_uid" \
    -e HOST_GID="$host_gid" \
    -v "$repo_dir/qpkg:/workspace" \
    ubuntu:22.04 \
    sh -c '
        set -eu
        apt-get update >/dev/null
        DEBIAN_FRONTEND=noninteractive apt-get install -y \
            build-essential bsdmainutils ca-certificates git rsync >/dev/null
        git clone --depth 1 --branch v2.3.11 \
            https://github.com/qnap-dev/QDK.git /tmp/QDK >/dev/null
        make -C /tmp/QDK/src >/dev/null
        cp -a /tmp/QDK/shared /usr/share/QDK
        mkdir -p /etc/config
        sed -e "2d" /usr/share/QDK/qdk.conf > /etc/config/qdk.conf
        sed -i "2iQDK_PATH_P=/usr/share" /etc/config/qdk.conf
        cd /workspace
        chmod 755 shared/QNAP-PWM.sh
        PATH="/usr/share/QDK/bin:$PATH" qbuild --strict --verbose
        chown -R "$HOST_UID:$HOST_GID" build
    '

echo "Built: $repo_dir/qpkg/build/QNAP-PWM_1.0.0.qpkg"
