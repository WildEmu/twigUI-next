# SPDX-License-Identifier: GPL-2.0

PKG_NAME="charge-mode"
PKG_VERSION=""
PKG_LICENSE="GPL"
PKG_SITE=""
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Charge screen for the GKD Pixel 2: plugged in while off, the battery level until the power key"
PKG_TOOLCHAIN="manual"

# The initramfs runs these from the mounted SYSTEM (/sysroot) when U-Boot booted for the
# charger (init: charge_mode); frames come from make-frames.py.
makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/charge-mode ${INSTALL}/usr/share/charge-mode
  cp ${PKG_BUILD}/charge-mode.sh ${INSTALL}/usr/lib/charge-mode/
  chmod 0755 ${INSTALL}/usr/lib/charge-mode/charge-mode.sh
  for f in ${PKG_BUILD}/frames/*.bmp.gz; do
    gzip -dc "${f}" > ${INSTALL}/usr/share/charge-mode/$(basename "${f}" .gz)
  done
}
