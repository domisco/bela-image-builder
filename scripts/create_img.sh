#!/bin/bash -e
[ -z "$DIR" ] && { echo "undefined variable: \$DIR"; exit 1; }
[ -z "$targetdir" ] && { echo "undefined variable: \$targetdir"; exit 1; }

cd ${DIR}
rm -rf bela.img

echo "creating Bela SD image"

echo Create empty 4gb disk image
dd if=/dev/zero of=${DIR}/bela.img bs=100 count=38671483

# partition it
sudo sfdisk ${DIR}/bela.img < ${DIR}/bela.sfdisk

# mount it
LOOP=`losetup -f`
LOOP=`echo $LOOP | sed "s/\/dev\///"`
#sudo losetup /dev/$LOOP
# -s makes sure the operation is applied before continuing
sudo kpartx -s -av ${DIR}/bela.img
sudo mkfs.vfat /dev/mapper/${LOOP}p1
sudo dosfslabel /dev/mapper/${LOOP}p1 BELABOOT
sudo mkfs.ext4 /dev/mapper/${LOOP}p2
sudo e2label /dev/mapper/${LOOP}p2 BELAROOTFS

mkdir -p /mnt/bela/boot
mkdir -p /mnt/bela/root
sudo mount /dev/mapper/${LOOP}p1 /mnt/bela/boot
sudo mount /dev/mapper/${LOOP}p2 /mnt/bela/root

# copy bootloader and dtb
# To boot properly MLO and u-boot.img have to be the first things copied onto the partition.
# We enforce this by `sync`ing to disk after every copy
sudo cp -v ${DIR}/boot/MLO /mnt/bela/boot/
sync
sudo cp -v ${DIR}/boot/u-boot.img /mnt/bela/boot/
sync
sudo cp -v $targetdir/opt/Bela/am335x-bone-bela*.dtb /mnt/bela/boot/
sync
# copying static extras to boot partition
sudo cp -rv ${DIR}/misc/boot/* /mnt/bela/boot/
sync

# complete and copy uEnv.txt for SD
cp ${DIR}/boot/uEnv.txt ${DIR}/boot/uEnv.tmp
echo "uname_r=`cat ${DIR}/kernel/kernel_version`" >> ${DIR}/boot/uEnv.tmp
echo "mmcid=0" >> ${DIR}/boot/uEnv.tmp
sudo cp -v ${DIR}/boot/uEnv.tmp /mnt/bela/boot/uEnv.txt
rm ${DIR}/boot/uEnv.tmp

# copy rootfs
sudo cp -a ${DIR}/rootfs/* /mnt/bela/root/

# create uEnv.txt for emmc
cp ${DIR}/boot/uEnv.txt ${DIR}/boot/uEnv.tmp
echo "uname_r=`cat ${DIR}/kernel/kernel_version`" >> ${DIR}/boot/uEnv.tmp
echo "mmcid=1" >> ${DIR}/boot/uEnv.tmp
sudo cp -v ${DIR}/boot/uEnv.tmp /mnt/bela/root/opt/Bela/uEnv-emmc.txt
rm ${DIR}/boot/uEnv.tmp

printf "BELA_IMAGE_VERSION=\"$DESCRIPTION\"\n" | sudo tee /mnt/bela/boot/bela.version

# seal off the motd with current tag and commit hash
APPEND_TO_MOTD="sudo tee -a /mnt/bela/root/etc/motd"
DESCRIPTION=`git -C ${DIR} describe --tags --dirty`
printf "Bela image, $DESCRIPTION, `date "+%e %B %Y"`\n\n" | ${APPEND_TO_MOTD}
printf "More info at https://github.com/BelaPlatform/bela-image-builder/releases\n\n" | ${APPEND_TO_MOTD}
printf "Built with bela-image-builder `git -C ${DIR} branch | grep '\*' | sed 's/\*\s//g'`@`git -C ${DIR} rev-parse HEAD`\non `date`\n\n" | ${APPEND_TO_MOTD}

# unmount
sudo umount /mnt/bela/boot
sudo umount /mnt/bela/root
sudo kpartx -d /dev/${LOOP}
sudo losetup -d /dev/${LOOP}
sudo chown $SUDO_USER ${DIR}/bela.img

echo "bela.img created"
echo
GIT_TAG=`git -C ${DIR} describe --tags --dirty`
# Are we on a tag? Try to list tags with the names above, if we get 0 lines, then we are not.
[ "`git tag -l \"$GIT_TAG\" | wc -l`" -eq 0 ] && echo "You do not seem to be on a git tag or your working tree is dirty. Are you sure you want to use this image for release?" >&2
