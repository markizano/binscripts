#!/bin/bash

[ "$UID" -eq 0 ] || { echo "Need to be invited to the party, dood..." >&2 && exit 1; }

echo "I assume you have already partitioned your drives and mounted the root and boot filesystems."

test -z "$ROOTFS" && read -p 'What is the root of the filesystem I would be acting against? ' ROOTFS
test -d "$ROOTFS" || {
  echo "$ROOTFS does not appear to be a directory." >&2
  exit 1
}

set -e

MIRROR=${MIRROR:-http://deb.devuan.org/merged/}
DISTRO=${DISTRO:-chimaera}
COMPONENTS=${COMPONENTS:-main,contrib,non-free}

KERNEL_DEB_DIR=/home/media/software/linux/kernel/5.10.15
BOOTSTRAP_TGZ=/home/media/software/linux/debootstrap-devuan-chimaera.tgz

INIT_PKGS='at,bash-completion,bind9-host,build-essential,colordiff,cmake,coreutils,curl,command-not-found'
INIT_PKGS+=',cryptsetup,file,fluxbox,ftp,git,gnupg2,gparted,ifupdown,lm-sensors,lsof,locales,lvm2,mlocate,nano,ncdu,nfs-common'
INIT_PKGS+=',ncdu,openssh-client,openssh-server,openssl,perl,pkg-config,python3,python3-pip,python3-setuptools,rdate,rsync,screen,sudo,syslog-ng'
INIT_PKGS+=',telnet,terminator,time,tree,whois,wireless-tools,iw,wipe,wget,xfsdump,xfsprogs,x11-xserver-utils'


echo "Now initializing the system... This make take some time."
#debootstrap --unpack-tarball $BOOTSTRAP_TGZ --arch=amd64 --include=$INIT_PKGS --exclude=rsyslog --components="$COMPONENTS" "$DISTRO" "$ROOTFS" "$MIRROR"
debootstrap --arch=amd64 --include=$INIT_PKGS --exclude=rsyslog,libsystemd0 --components="$COMPONENTS" "$DISTRO" "$ROOTFS" "$MIRROR"
echo "Done installing base system."

export HOME=/root
export HISTFILE=/root/.bash_history
export DISPLAY=$DISPLAY
export XAUTHORITY=/root/.Xauthority

chr="chroot $ROOTFS"

echo "Let me fix locales right quick..."
perl -i -pe 's/^#\s*(en_US.UTF-8.*).*/\1/' $ROOTFS/etc/locale.gen
$chr locale-gen

echo -e "Acquiring keys for apt installs..."
APT_KEYS='DD3C368A8DE1B7A0' # Opera
APT_KEYS+=' EB3E94ADBE1229CF' # MS VSCode
APT_KEYS+=' 7EA0A9C3F273FCD8' # Docker
APT_KEYS+=' D980A17457F6FB06' # Signal-Desktop
APT_KEYS+=' 7373B12CE03BEB4B' # Runescape
APT_KEYS+=' C6ABDCF64DB9A0B2' # Slack
APT_KEYS+=' 4B7C549A058F8B6B' # MongoDB
APT_KEYS+=' 78BD65473CB3BD13' # Google-Chrome
APT_KEYS+=' 8E61C2AB9A6D1557' # pkgcloud Ookla SpeedTest
$chr apt-key adv --keyserver keyserver.ubuntu.com --recv-keys $APT_KEYS
curl -Lqso- 'https://packagecloud.io/ookla/speedtest-cli/gpgkey' | apt-key add -
$chr apt -q update
echo "Ok! Let's see about those pretext packages."

$chr dpkg --print-foreign-architectures | grep -q i386 || $chr dpkg --add-architecture i386

echo "Good. Now let's get those repositories up to date."

echo "deb [arch=amd64] https://download.docker.com/linux/debian buster edge"                > $ROOTFS/etc/apt/sources.list.d/docker.list
echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main"                  > $ROOTFS/etc/apt/sources.list.d/google-chrome.list
echo "deb [arch=amd64] http://repo.mongodb.org/apt/debian buster/mongodb-org/4.2 main"      > $ROOTFS/etc/apt/sources.list.d/mongodb.list
echo "deb [arch=amd64] https://packagecloud.io/ookla/speedtest-cli/debian/ buster main"     > $ROOTFS/etc/apt/sources.list.d/speedtest.list
echo "deb [arch=amd64] https://deb.opera.com/opera-stable/ stable non-free"                 > $ROOTFS/etc/apt/sources.list.d/opera-stable.list

echo "deb [arch=amd64,i386] $MIRROR $DISTRO ${COMPONENTS//,/ }" > $ROOTFS/etc/apt/sources.list
echo "deb [arch=amd64,i386] $MIRROR $DISTRO-security ${COMPONENTS//,/ }" >> $ROOTFS/etc/apt/sources.list
echo "deb [arch=amd64,i386] $MIRROR $DISTRO-updates ${COMPONENTS//,/ }" >> $ROOTFS/etc/apt/sources.list


echo "Excellent. Time for one more update."
$chr apt -q update

echo "Mounting filesystems..."
(
  cd $ROOTFS
  mount -t proc proc proc
  mount -t sysfs sysfs sys
  mount -t devtmpfs -orw,nosuid,relatime,size=8142492k,nr_inodes=2035623,mode=755 udev dev
  mount --rbind /dev/pts dev/pts
)

# System commands
$chr apt install -qy software-properties-common apt-transport-https

echo -n "Now listing packages.... "

PKGS=''
# Remote filesystems and Drivers
PKGS=' sshfs cryptsetup lvm2'

# libmesa for compiling kawpowminer
#PKGS+=' mesa-common-dev'

# Shells and tools
PKGS+=' terminator evince'
PKGS+=' putty-tools'
PKGS+=' android-tools-adb android-system-dev android-tools-fastboot android-tools-fsutils'
#PKGS+=' rdesktop'
#PKGS+=' wireshark speedtest-cli'

# Xorg packages that are helpful utilities.
PKGS+='xbacklight xclip xinput xdotool xautomation xdg-utils x11-xserver-utils'

# Databases
PKGS+=' mongodb-org-shell mongodb-org-tools'

# Chat and Mail
PKGS+=' xchat transmission-cli transmission-gtk'

# Media
PKGS+=' mpv vlc slim console-setup'

# Favorites / Window manager / games
PKGS+=' google-chrome-stable libpam-google-authenticator python3-setuptools'

echo -e "Done!\nNow installing. This may take a while, depending on your network connection, core count, and IOPS available to disk..."

# prevent wireshark from asking about non-root users being able to pkt-capture.
echo "wireshark-common wireshark-common/group-is-user-group error" | $chr debconf-set-selections
echo "keyboard-configuration keyboard-configuration/layoutcode string us" | $chr debconf-set-selections
$chr env DEBIANFRONTEND=noninteractive apt-get -oDPkg::Options::=--force-confold -oDPkg::Options::=--force-confdef install -y $PKGS

# Need to install rEFInd separate since it may fail.
$chr apt -oDPkg::Options::=--force-confold -oDPkg::Options::=--force-confdef install -y refind || true

echo "Installing the kernel..."
mkdir $ROOTFS/tmp/kernel
cp -v $KERNEL_DEB_DIR/*.deb $ROOTFS/tmp/kernel/
$chr /bin/bash -c "dpkg -i /tmp/kernel/*.deb"
rm -r $ROOTFS/tmp/kernel/
echo "Done installing kernel."

# Perl
echo yes | $chr cpan CPAN Net::Graphite File::Tail

$chr addgroup --system --gid=200 apps
$chr addgroup --gid=1006 kizano
$chr adduser --gid=1006 --uid=1000 --home=/home/markizano --shell=/bin/bash markizano
for group in apps docker staff wheel disk sudo floppy cdrom audio video plugdev netdev; do $chr adduser markizano $group || true; done

rcscripts=$'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'

echo "$rcscripts" | base64 -d | $chr sudo -H -umarkizano -gkizano tar -C /home/markizano -zxvf-

echo Complete.

