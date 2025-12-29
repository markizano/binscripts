#!/bin/bash -x
# Usage:
# ROOTFS=/media/newos init.rc.sh

. /usr/local/bin/common.sh

[ "$UID" -eq 0 ] || { log_error_msg "Need to be invited to the party, dood..." >&2 && exit 1; }
# Reset home directory because I often don't reset the sudo env in my personal setups.
export HOME=/root

#@TODO: I want to get around this by checking mount paths and attempting to mount if necessary.
log_warn_msg "I assume you have already partitioned your drives and mounted the root and boot filesystems."

test -z "$ROOTFS" && read -p 'What is the root of the filesystem I would be acting against? ' ROOTFS
test -d "$ROOTFS" || {
  #@TODO: Like above: Attempt to create the workspace and mount it.
  log_fail_msg "$ROOTFS does not appear to be a directory." >&2
  exit 1
}

set -e

MIRROR=${MIRROR:-http://deb.devuan.org/merged/}
DISTRO=${DISTRO:-excalibur}
BOOTSTRAP_TGZ=${BOOTSTRAP_TGZ:-"/media/tank/software/linux/debootstrap-devuan-$DISTRO.tgz"}

# Pipeline to replace this text if it gets out of order or too long of a line:
# echo $(echo ${INIT_PKGS} | perl -pe 's/,/\n/g' | sort | grep -vP $whitespace) | fold -w90 -s | while read line; do test -z "$first" && { eq='='; first=1; } || { eq='+='; }; echo "INIT_PKGS${eq}',${line}'"; done | perl -pe 's/ /,/g' | clip
INIT_PKGS='bash-completion,ca-certificates,command-not-found,coreutils,cryptsetup,curl,dirmngr'
INIT_PKGS+=',file,gpg,gpg-agent,ifupdown,locales,lsof,lvm2,pinentry-curses,plocate,nano,ncdu,openssl'
INIT_PKGS+=',python3,syslog-ng,tar,tree,wget'

# If we are just generating the tarball, exit early to avoid trying to install the rest of the system since
# debootstrap will wipe the directory clean afterwards.
function onlyMakeTarball() {
  bootstrap_dir="`dirname $BOOTSTRAP_TGZ`"
  test -d "$bootstrap_dir" || mkdir -p "$bootstrap_dir"
  debootstrap --make-tarball $BOOTSTRAP_TGZ --arch=amd64 --include=$INIT_PKGS --exclude=rsyslog --components="main" "$DISTRO" "$ROOTFS" "$MIRROR"
}
test -z "$ONLY_MAKE_TARBALL" || {
  onlyMakeTarball
  exit $?
}

log_info_msg "Now initializing the system... This make take some time."
test -r "$BOOTSTRAP_TGZ" && bstrap="--unpack-tarball $BOOTSTRAP_TGZ"
debootstrap $bstrap --arch=amd64 --include=$INIT_PKGS --exclude=rsyslog --components="main" "$DISTRO" "$ROOTFS" "$MIRROR"
log_ok_msg "Done installing base system."

# Override some environment variables that are unfortunately copied into the environment.
export HOME=/root
export HISTFILE=/root/.bash_history
export DISPLAY=$DISPLAY
export XAUTHORITY=/root/.Xauthority

chr="chroot $ROOTFS"
aptget='apt-get -oDPkg::Options::=--force-confold -oDPkg::Options::=--force-confdef'

log_info_msg "Let me fix locales right quick..."
perl -i -pe 's/^#\s*(en_US.UTF-8.*).*/\1/' $ROOTFS/etc/locale.gen
$chr locale-gen
log_ok_msg "Locales fixed!"


log_info_msg "Acquiring keys for apt installs..."
APT_KEYS='11EE8C00B693A745' # Opera
APT_KEYS+=' EB3E94ADBE1229CF' # MS VSCode
APT_KEYS+=' 7EA0A9C3F273FCD8' # Docker
APT_KEYS+=' D980A17457F6FB06' # Signal-Desktop
APT_KEYS+=' 7373B12CE03BEB4B' # Runescape
APT_KEYS+=' C6ABDCF64DB9A0B2' # Slack
APT_KEYS+=' 41DE058A4E7DCA05' # MongoDB
APT_KEYS+=' 32EE5355A6BC6E42' # Google-Chrome
$chr gpg --keyserver keyserver.ubuntu.com --recv-keys $APT_KEYS
for key in $APT_KEYS; do
  $chr gpg -a --export $key > $ROOTFS/etc/apt/trusted.gpg.d/$key.asc
done
rm -r $ROOTFS/root/.gnupg
$chr curl -vso /etc/apt/trusted.gpg.d/markizano.net.asc https://apt.markizano.net/key.asc
$chr apt update

log_info_msg "Ok! Let's see about those pretext packages."

$chr dpkg --print-foreign-architectures | grep -q i386 || $chr dpkg --add-architecture i386

log_info_msg "Good. Now let's get those repositories up to date."

echo "deb [arch=amd64] https://download.docker.com/linux/debian trixie stable"              > $ROOTFS/etc/apt/sources.list.d/docker.list
echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main"                  > $ROOTFS/etc/apt/sources.list.d/google-chrome.list
echo "deb [arch=amd64] http://repo.mongodb.org/apt/debian bookworm/mongodb-org/8.0 main"    > $ROOTFS/etc/apt/sources.list.d/mongodb.list
echo "deb [arch=amd64] https://deb.opera.com/opera-stable/ stable non-free"                 > $ROOTFS/etc/apt/sources.list.d/opera-stable.list
echo "deb [arch=amd64] https://apt.markizano.net kernel main"                               > $ROOTFS/etc/apt/sources.list.d/kernel.list

echo "deb [arch=amd64,i386] $MIRROR $DISTRO main contrib non-free non-free-firmware" > $ROOTFS/etc/apt/sources.list
echo "deb [arch=amd64,i386] $MIRROR $DISTRO-security main contrib non-free" >> $ROOTFS/etc/apt/sources.list
echo "deb [arch=amd64,i386] $MIRROR $DISTRO-updates main contrib non-free" >> $ROOTFS/etc/apt/sources.list


log_info_msg "Excellent. Time for one more update."
$chr apt -q update

log_info_msg "Mounting filesystems..."
(
  cd $ROOTFS
  mount -t proc proc proc
  mount -t sysfs sysfs sys
  mount -t devtmpfs -orw,nosuid,relatime,size=8142492k,nr_inodes=2035623,mode=755 udev dev
  mount --rbind /dev/pts dev/pts
)

# System commands
$chr apt install -qy apt-transport-https

log_info_msg -n "Now listing packages.... "

PKGS=''

# Post-Install base packages.
PKGS+='compton debootstrap fluxbox ftp git gnupg2 gparted ipcalc iw lm-sensors'
PKGS+=' nfs-common openssh-client openssh-server pciutils perl pkg-config pluma'
PKGS+=' python3-pip python3-setuptools rdate rsync screen sudo telnet terminator time'
PKGS+=' unzip whois wipe wireless-tools x11-xserver-utils xfsdump xfsprogs zip'

# Remote filesystems and Drivers
PKGS=' sshfs'

# libmesa for compiling kawpowminer
#PKGS+=' mesa-common-dev'

# Shells and tools
PKGS+=' terminator evince'
#PKGS+=' putty-tools'
PKGS+=' adb'
#PKGS+=' rdesktop'
PKGS+=' rar unrar'

# Databases
PKGS+=' mongodb-mongosh docker'

# Chat and Mail
PKGS+=' hexchat transmission-cli transmission-gtk'

# Media
PKGS+=' mpv vlc slim console-setup'

# Favorites / Window manager / games
PKGS+=' google-chrome-stable'

PKGS+=' linux-image-6.6.58 linux-headers-6.6.58 linux-libc-dev=6.6.58-3'
log_ok_msg "Done!"

log_info_msg "Now installing. This may take a while, depending on your network connection, core count, and IOPS available to disk..."
# prevent wireshark from asking about non-root users being able to pkt-capture.
#echo "wireshark-common wireshark-common/group-is-user-group error" | $chr debconf-set-selections
echo "keyboard-configuration keyboard-configuration/layoutcode string us" | $chr debconf-set-selections
$chr env DEBIANFRONTEND=noninteractive $aptget install -y $PKGS

#read -p 'Grub or rEFInd? [grub/refind] ' grubRefind
#echo "$grubRefind" | grep -iP '^g(?:rub)?$' && {
#  $chr $aptget install -y grub2 || true
#}
#echo "$grubRefind" | grep -iP '^r(?:efind)?$' && {
#  # Need to install rEFInd separate since it may fail.
#  $chr $aptget install -y refind || true
#}

$chr $aptget install -y refind

# Perl
yes | $chr cpan CPAN Net::Graphite File::Tail

$chr addgroup --system --gid=200 apps
$chr addgroup --gid=1006 kizano
$chr adduser --gid=1006 --uid=1000 --home=/home/markizano --shell=/bin/bash markizano
for group in apps docker staff wheel disk sudo floppy cdrom audio video plugdev netdev; do
  $chr adduser markizano $group || true;
done
mkdir -m0700 $ROOTFS/root/.ssh

rcscripts=$'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'

echo "$rcscripts" | base64 -d | $chr sudo -H -umarkizano -gkizano tar -C /home/markizano -zxvf-

log_ok_msg Complete.

