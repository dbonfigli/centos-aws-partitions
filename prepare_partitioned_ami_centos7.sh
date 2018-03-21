#/bin/bash

# 1) launch a centos7 instance with an additional volume mounted in sdb (xvdb)
# 2) run this script to prepare the additional volume
# 3) halt the vm, detach the original volume and mount the additional one as sda1

yum install -y parted

# cloudinit default config grows the root partition so that it will overwrite and corrupt
# the partitions ofter the root one, we must disable "growpart" and "resizefs" modules
sed -i "s/ - growpart/# - growpart/" /etc/cloud/cloud.cfg
sed -i "s/ - resizefs/# - resizefs/" /etc/cloud/cloud.cfg

# create and format partitions
dd if=/dev/zero of=/dev/xvdb bs=512 count=1
parted -s -a opt /dev/xvdb mklabel msdos
parted -s -a opt /dev/xvdb mkpart primary 0% 3% 
parted -s -a opt /dev/xvdb set 1 boot on
parted -s -a opt /dev/xvdb mkpart extended 3% 100%
parted -s -a opt /dev/xvdb mkpart logical xfs 3% 30% #root 5
parted -s -a opt /dev/xvdb mkpart logical xfs 30% 40% #var 6
parted -s -a opt /dev/xvdb mkpart logical xfs 40% 60% #varlog 7
parted -s -a opt /dev/xvdb mkpart logical xfs 60% 70% #varlogaudit 8
parted -s -a opt /dev/xvdb mkpart logical xfs 70% 90% #home 9
parted -s -a opt /dev/xvdb mkpart logical xfs 90% 94% #tmp 10
parted -s -a opt /dev/xvdb mkpart logical linux-swap 94% 100% #swap 11
for i in 1 `seq 5 10` ; do mkfs.xfs -f /dev/xvdb$i ; done
mkswap /dev/xvdb11

# create mount points
mkdir -p /mnt
mount /dev/xvdb5 /mnt
mkdir -p /mnt/var
mount /dev/xvdb6 /mnt/var
mkdir -p /mnt/var/log
mount /dev/xvdb7 /mnt/var/log
mkdir -p /mnt/var/log/audit
mount /dev/xvdb8 /mnt/var/log/audit
mkdir -p /mnt/home
mount /dev/xvdb9 /mnt/home
mkdir -p /mnt/tmp
mount /dev/xvdb10 /mnt/tmp
mkdir -p /mnt/boot
mount /dev/xvdb1 /mnt/boot

# copy the whole file system to the new disk
# please note: AX flags are very important if you use selinux!
rsync -avAX --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/media/*","/lost+found","/mnt"}  / /mnt

# create fstab for new vm
boot_uid=`blkid | grep "xvdb1:" | grep -o "UUID.*" | sed 's/ TYPE.*//' | sed 's/\"//g'`
root_uid=`blkid | grep "xvdb5:" | grep -o "UUID.*" | sed 's/ TYPE.*//' | sed 's/\"//g'`
var_uid=`blkid | grep "xvdb6:" | grep -o "UUID.*" | sed 's/ TYPE.*//' | sed 's/\"//g'`
var_log_uid=`blkid | grep "xvdb7:" | grep -o "UUID.*" | sed 's/ TYPE.*//' | sed 's/\"//g'`
var_log_audit_uid=`blkid | grep "xvdb8:" | grep -o "UUID.*" | sed 's/ TYPE.*//' | sed 's/\"//g'`
home_uid=`blkid | grep "xvdb9:" | grep -o "UUID.*" | sed 's/ TYPE.*//' | sed 's/\"//g'`
tmp_uid=`blkid | grep "xvdb10:" | grep -o "UUID.*" | sed 's/ TYPE.*//' | sed 's/\"//g'`
swap_uid=`blkid | grep "xvdb11:" | grep -o "UUID.*" | sed 's/ TYPE.*//' | sed 's/\"//g'`
cat > /mnt/etc/fstab << EOF
$root_uid		/		xfs	defaults			0 0
$boot_uid		/boot		xfs	defaults			0 0
$var_uid		/var		xfs	defaults			0 0
$var_log_uid		/var/log	xfs	defaults			0 0
$var_log_audit_uid	/var/log/audit	xfs	defaults			0 0
$tmp_uid		/tmp		xfs	nodev,nosuid,noexec		0 0
$home_uid		/home		xfs	nodev				0 0
$swap_uid		swap		swap	defaults			0 0
none			/dev/shm	tmpfs	nodev,nosuid,noexec,size=8G	0 0
/tmp			/var/tmp	none	bind				0 0
EOF

# install bootloader
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys
chroot /mnt
mv /boot/grub2/device.map   /boot/grub2/device.map.old
grub2-mkconfig -o /boot/grub2/grub.cfg
grub2-install /dev/xvdb
exit

# sync and unmount the new partitions before the shutting down the vm
sync
umount /mnt/boot
umount /mnt/tmp
umount /mnt/home
umount /mnt/var/log/audit
umount /mnt/var/log
umount /mnt/var
umount /mnt/dev
umount /mnt/proc
umount /mnt/sys
umount /mnt



