# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="gametank-lr"
PKG_LICENSE="MIT"
PKG_VERSION="7f1afbdcec6529ad1fe0c3c2ca5a19ced05679f4"
PKG_SITE="https://github.com/SundownerSport/gametank-libretro"
PKG_URL="${PKG_SITE}.git"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="A libretro core for the GameTank, built from Clyde Shaffer's GameTankEmulator"
PKG_TOOLCHAIN="make"

makeinstall_target() {
  ${STRIP} "${PKG_BUILD}"/gametank_libretro.so
}