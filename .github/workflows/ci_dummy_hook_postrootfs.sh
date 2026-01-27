#!/usr/bin/env bash

dnf install -y git
dnf install -y glib2-devel gnome-desktop4-devel gtk4-devel libgweather-devel libadwaita-devel https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Everything/$(uname -m)/os/Packages/v/vte291-gtk4-devel-0.82.2-2.fc44.$(uname -m).rpm
git clone https://gitlab.gnome.org/p3732/os-installer.git /tmp/os-installer
cd /tmp/os-installer
meson build
cd build
ninja install
cd /
dnf remove -y glib2-devel gnome-desktop4-devel gtk4-devel libgweather-devel libadwaita-devel vte291-gtk4-devel
git clone https://github.com/horizonlinux/os-installer-config.git /tmp/osi-config
mv /tmp/osi-config /etc/os-installer
