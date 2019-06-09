#!/bin/sh -xe

# This file is part of PrawnOS (http://www.prawnos.com)
# Copyright (c) 2018 Hal Emmerich <hal@halemmerich.com>

# PrawnOS is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2
# as published by the Free Software Foundation.

# PrawnOS is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with PrawnOS.  If not, see <https://www.gnu.org/licenses/>.

if [ -z "$1" ]
then
    echo "No kernel version supplied"
    exit 1
fi
KVER=$1

if [ -z "$2" ]
then
    echo "No image filesystem image supplied"
    exit 1
fi
outmnt=$(mktemp -d -p `pwd`)
outdev=/dev/loop7

build_resources=resources/BuildResources

cryptsetup_mapper_name=poscryptroot

#A hacky way to ensure the loops are properly unmounted and the temp files are properly deleted.
#Without this, a reboot is sometimes required to properly clean the loop devices and ensure a clean build 
cleanup() {
    set +e

    umount -R -l $outmnt > /dev/null 2>&1
    cryptsetup close $cryptsetup_mapper_name || true
    rmdir $outmnt > /dev/null 2>&1
    losetup -d $outdev > /dev/null 2>&1

    set +e

    umount -R -l $outmnt > /dev/null 2>&1
    cryptsetup close $cryptsetup_mapper_name || true
    rmdir $outmnt > /dev/null 2>&1
    losetup -d $outdev > /dev/null 2>&1
}

trap cleanup INT TERM EXIT

#Mount the build filesystem image

losetup -P $outdev $2

if [ -z "$PRAWNOS_LUKS" ]
then
    mount -o noatime ${outdev}p2 $outmnt
else
    # mount using cryptsetup
    cryptsetup open ${outdev}p3 $cryptsetup_mapper_name
    mount -o noatime /dev/mapper/$cryptsetup_mapper_name $outmnt
    mount -o noatime ${outdev}p2 $outmnt/boot
fi

# put modules in /lib/modules and AR9271 and firmware in /lib/firmware
make -C build/linux-$KVER ARCH=arm INSTALL_MOD_PATH=$outmnt modules_install
rm -f $outmnt/lib/modules/3.14.0/{build,source}
install -D -m 644 build/open-ath9k-htc-firmware/target_firmware/htc_9271.fw $outmnt/lib/firmware/ath9k_htc/htc_9271-1.4.0.fw

# rebuilding kernel image requires modules, must be after installing modules in /lib/modules
if [ ! -z "$PRAWNOS_LUKS" ]
then
    root_uuid=$(lsblk -n -o NAME,UUID ${outdev}p3 | grep -v $cryptsetup_mapper_name | awk '{print $2}')
    cp build/linux-$KVER/arch/arm/boot/dts/rk3288-veyron-speedy.dtb $outmnt/boot/rk3288-veyron-speedy.dtb
    cp build/linux-$KVER/arch/arm/boot/zImage $outmnt/boot/vmlinuz-$KVER
    cat $build_resources/kernel_efs.its | sed "s/SED_KVER/$KVER/g" > $outmnt/boot/kernel_efs.its
    cat $build_resources/cmdline_efs | sed "s/SED_KVER/$KVER/g; s/SED_ROOT_UUID/$root_uuid/g; s/SED_MAPPER_NAME/$cryptsetup_mapper_name/g" > $outmnt/boot/cmdline_efs
    chroot $outmnt mkinitramfs -v -o /boot/initrd.img-$KVER $KVER
    chroot $outmnt mkimage -f /boot/kernel_efs.its /boot/vmlinux.uimg
    dd if=/dev/zero of=$outmnt/boot/bootloader.bin bs=512 count=1
    chroot $outmnt vbutil_kernel \
        --pack /boot/vmlinux.kpart \
        --version 1 \
        --vmlinuz /boot/vmlinux.uimg \
        --arch arm \
        --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
        --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
        --config /boot/cmdline_efs \
        --bootloader /boot/bootloader.bin
    cp $outmnt/boot/vmlinux.kpart build/linux-$KVER/vmlinux.kpart
fi

# put the kernel in the kernel partition
dd if=$build_resources/blank_kernel of=${outdev}p1 conv=notrunc
dd if=build/linux-$KVER/vmlinux.kpart of=${outdev}p1 conv=notrunc

umount -R -l $outmnt > /dev/null 2>&1
cryptsetup close $cryptsetup_mapper_name || true
rmdir $outmnt > /dev/null 2>&1
losetup -d $outdev > /dev/null 2>&1
echo "DONE!"
trap - INT TERM EXIT
