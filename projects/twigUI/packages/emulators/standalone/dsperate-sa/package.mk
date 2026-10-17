# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="dsperate-sa"
PKG_VERSION="3.0.4"
PKG_SHA256="27f98e007837bdf31b3ba51dc8ca447e862ea05aa09163ef584d6a217be1acf9"
PKG_LICENSE="GPL-3.0-or-later"
PKG_SITE="https://github.com/beebono/DSperate"
PKG_URL="${PKG_SITE}/releases/download/v${PKG_VERSION}/dsperate-v${PKG_VERSION}-linux-${TARGET_ARCH}.tar.gz"
PKG_SOURCE_DIR="dsperate-v${PKG_VERSION}-linux-${TARGET_ARCH}"
PKG_DEPENDS_TARGET="toolchain SDL2"
PKG_LONGDESC="A Nintendo DS emulator reimplementing DraStic's JIT and NEON rendering with melonDS accuracy."
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  :
}