#!/usr/bin/env bash
set -e
set -x
IMG_DIR="images"
IMG_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-armv7-latest.tar.gz"
IMG_NAME=${IMG_URL##*/}
IMG_PATH=${IMG_DIR}/${IMG_NAME}
TARGET_IMAGE=$(basename -s .tar.gz "$IMG_NAME").img
TARGET_ZIP=$(basename -s .tar.gz "$IMG_NAME").zip
TARGET_ZIP_MD5=${TARGET_ZIP}.md5
MD5_URL=${IMG_URL}.md5
MD5_NAME=${MD5_URL##*/}
losetup /dev/loop10 && exit 1 || true
## Check cache and maybe download
mkdir -p $IMG_DIR
pushd $IMG_DIR
wget -q -N "${MD5_URL}"
if md5sum -c "${MD5_NAME}" ; then
  echo "Cached ${IMG_NAME} already downloaded!"
else
  echo "Cached ${IMG_NAME} did not match MD5 of latest image, downloading"
  wget -q -N "${IMG_URL}"
  # Double check the new version matches
  md5sum -c "${MD5_NAME}"
fi
popd
# Set up image file
truncate -s 1900M "${TARGET_IMAGE}"
losetup /dev/loop10 "${TARGET_IMAGE}"
parted -s /dev/loop10 mklabel msdos
parted -s /dev/loop10 mkpart primary fat32 -a optimal -- 0% 100MB
parted -s /dev/loop10 set 1 boot on
parted -s /dev/loop10 unit mb mkpart primary ext2 -a optimal -- 100MB 100%
parted -s /dev/loop10 print
mkfs.vfat -I -n SYSTEM /dev/loop10p1
mkfs.ext4 -F -L root -b 4096 -E stride=4,stripe_width=1024 /dev/loop10p2
# Mount image
mkdir -p root
mount /dev/loop10p2 root
# Copy image contents over
bsdtar xfz "${IMG_PATH}" -C root
mv root/boot root/boot-temp
mkdir -p root/boot
mount /dev/loop10p1 root/boot
mv root/boot-temp/* root/boot/
rm -rf root/boot-temp
# Install qemu for chroot
sudo apt-get install -y qemu-user-static
cp /usr/bin/qemu-arm-static root/usr/bin/
# Remove bloat via chroot
mount --bind /proc root/proc
mount --bind /sys root/sys
mount --bind /dev root/dev
chroot root /bin/bash -c "pacman -Qi | grep 'Name\|Installed Size' | paste - - || true"
umount root/proc root/sys root/dev
rm root/usr/bin/qemu-arm-static
# Turn off access time
sed -i "s/ defaults / defaults,noatime /" root/etc/fstab
# Cleanup
umount root/boot root
e2fsck -f /dev/loop10p2
resize2fs -M /dev/loop10p2
losetup -d /dev/loop10
# Truncate image file to actual size
PART_END=$(parted -s "${TARGET_IMAGE}" unit B print | grep "^ 2" | awk '{print $3}' | tr -d B)
truncate -s $((PART_END + 1)) "${TARGET_IMAGE}"
rm -rf root
# Zip img
zip -r9 --display-dots "${TARGET_ZIP}" "${TARGET_IMAGE}"
# Generate MD5
md5sum "${TARGET_ZIP}" > "${TARGET_ZIP_MD5}"
# Taken from https://gist.github.com/larsch/4ae5499023a3c5e22552
