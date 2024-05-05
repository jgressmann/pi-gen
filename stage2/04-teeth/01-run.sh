#!/usr/bin/env bash

set -eu

log "TEETH: Install packages required for C build"
# install tools required to build
apt-get -y update
apt-get -y install --no-install-recommends \
	crossbuild-essential-arm64 \
	cmake \
	git
rm -rf /var/lib/apt/lists/*

# /pi-gen/stage2/04-teeth
work_dir=$PWD

log "TEETH: Cloning git repo"
git clone https://github.com/jgressmann/teeth.git

log "TEETH: Building and installing daemon"
# C parts
build_dir=/tmp/teeth/build
mkdir -p "$build_dir" && cd "/tmp/teeth/build"
CC=aarch64-linux-gnu-gcc cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX="${ROOTFS_DIR}/usr/local" "${work_dir}/teeth"
cmake --build .
cmake --install .
cd "${work_dir}"
rm -rf "${build_dir}"

log "TEETH: Installing REST service"
# Python parts
service_dir=${ROOTFS_DIR}/opt/teeth
mkdir -p "${service_dir}"
install -m 644 teeth/rest/teeth.py "${service_dir}"
install -m 644 teeth/rest/requirements.txt "${service_dir}"
install -m 644 files/config.yaml "${service_dir}"

on_chroot << EOF
	cd /opt/teeth
	python3 -m venv .
	. bin/activate
	pip install -r requirements.txt
EOF

log "TEETH: System configuration"
install -m 0644 "files/eth0.network" "${ROOTFS_DIR}/etc/systemd/network/eth0.network"
install -m 0644 "files/99-teeth.rules" "${ROOTFS_DIR}/etc/udev/rules.d"
install -m 0755 "files/teethd-start" "${ROOTFS_DIR}/usr/local/bin"

mkdir -p "${ROOTFS_DIR}/usr/local/lib/systemd/system"
install -m 0644 "files/teeth-device@.service" "${ROOTFS_DIR}/usr/local/lib/systemd/system"
install -m 0644 "files/teeth-rest.service" "${ROOTFS_DIR}/usr/local/lib/systemd/system"

# don't wait for online (AutoIP)
sed -i "s/#WAIT_ONLINE_METHOD=ifup/WAIT_ONLINE_METHOD=none/" "${ROOTFS_DIR}/etc/default/networking"

on_chroot << EOF
	systemctl mask NetworkManager.service
	systemctl mask ModemManager.service
	systemctl mask avahi-daemon.service
	systemctl mask bluetooth.service
	systemctl mask wpa_supplicant.service
	systemctl enable systemd-networkd
	systemctl enable teeth-rest.service
EOF



