#!/usr/bin/env bash

# We need to make our own Profiles. This makes anaconda think we are a Kinoite Install
. /etc/os-release
if [[ "$ID_LIKE" =~ rhel ]]; then
    echo 'VARIANT_ID="kinoite"' >>/usr/lib/os-release
else
    sed -i "s/^VARIANT_ID=.*/VARIANT_ID=kinoite/" /usr/lib/os-release
fi
sed -i "s/^ID=.*/ID=fedora/" /usr/lib/os-release

dnf install -y anaconda-core anaconda-dracut anaconda-gui anaconda-liveinst

if [[ "${HIDE_SPOKE:-}" ]]; then
    # Hide Root Spoke
    cat <<EOF >>/etc/anaconda/conf.d/anaconda.conf
[User Interface]
hidden_spokes =
    PasswordSpoke
EOF
fi

tee /etc/anaconda/profile.d/horizon.conf <<'EOF'
# Anaconda configuration file for Bluefin LTS

[Profile]
# Define the profile.
profile_id = horizon

[Profile Detection]
# Match os-release values
os_id = horizon

[Network]
default_on_boot = FIRST_WIRED_WITH_LINK

[Bootloader]
efi_dir = centos
menu_auto_hide = True

[Storage]
file_system_type = xfs
default_partitioning =
    /     (min 5 GiB, max 70 GiB)
    /var  (min 5 GiB)

[User Interface]
custom_stylesheet = /usr/share/anaconda/pixmaps/redhat.css
hidden_spokes =
    NetworkSpoke
    PasswordSpoke
    UserSpoke
	SubscriptionSpoke
hidden_webui_pages =
    anaconda-screen-accounts

[Localization]
use_geolocation = False
EOF

sed -i 's/^ID=.*/ID=horizon/' /usr/lib/os-release

# Variables
imageref="$(jq -r '."image-ref"' </usr/share/ublue-os/image-info.json)"
imageref="${imageref##*://}"
imagetag="$(jq -r 'if ."image-branch" then ."image-branch" else ."image-tag" end' </usr/share/ublue-os/image-info.json)"
sbkey='https://github.com/ublue-os/akmods/raw/main/certs/public_key.der'

# Secureboot Key Fetch
mkdir -p /run/install/repo
curl -Lo /run/install/repo/sb_pubkey.der "$sbkey"

# Default Kickstart
cat <<EOF >>/usr/share/anaconda/interactive-defaults.ks
ostreecontainer --url=$imageref:$imagetag --transport=containers-storage --no-signature-verification
%include /usr/share/anaconda/post-scripts/install-configure-upgrade.ks
%include /usr/share/anaconda/post-scripts/disable-fedora-flatpak.ks
%include /usr/share/anaconda/post-scripts/install-flatpaks.ks
%include /usr/share/anaconda/post-scripts/secureboot-enroll-key.ks
EOF

# Signed Images
cat <<EOF >>/usr/share/anaconda/post-scripts/install-configure-upgrade.ks
%post --erroronfail
bootc switch --mutate-in-place --enforce-container-sigpolicy --transport registry $imageref:$imagetag
%end
EOF

# Enroll Secureboot Key
cat <<EOF >>/usr/share/anaconda/post-scripts/secureboot-enroll-key.ks
%post --erroronfail --nochroot
set -oue pipefail

readonly ENROLLMENT_PASSWORD="universalblue"
readonly SECUREBOOT_KEY="/run/install/repo/sb_pubkey.der"

if [[ ! -d "/sys/firmware/efi" ]]; then
	echo "EFI mode not detected. Skipping key enrollment."
	exit 0
fi

if [[ ! -f "\$SECUREBOOT_KEY" ]]; then
	echo "Secure boot key not provided: \$SECUREBOOT_KEY"
	exit 0
fi

SYS_ID="\$(cat /sys/devices/virtual/dmi/id/product_name)"
if [[ ":Jupiter:Galileo:" =~ ":\$SYS_ID:" ]]; then
	echo "Steam Deck hardware detected. Skipping key enrollment."
	exit 0
fi

mokutil --timeout -1 || :
echo -e "\$ENROLLMENT_PASSWORD\n\$ENROLLMENT_PASSWORD" | mokutil --import "\$SECUREBOOT_KEY" || :
%end
EOF

# Install Flatpaks
cat <<'EOF' >>/usr/share/anaconda/post-scripts/install-flatpaks.ks
%post --erroronfail --nochroot
deployment="$(ostree rev-parse --repo=/mnt/sysimage/ostree/repo ostree/0/1/0)"
target="/mnt/sysimage/ostree/deploy/default/deploy/$deployment.0/var/lib/"
mkdir -p "$target"
rsync -aAXUHKP /var/lib/flatpak "$target"
%end
EOF

# Disable Fedora Flatpak Repo
cat <<EOF >>/usr/share/anaconda/post-scripts/disable-fedora-flatpak.ks
%post --erroronfail
systemctl disable flatpak-add-fedora-repos.service
%end
EOF

# Set Anaconda Payload to use flathub
cat <<EOF >>/etc/anaconda/conf.d/anaconda.conf
[Payload]
flatpak_remote = flathub https://dl.flathub.org/repo/
EOF
