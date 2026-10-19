#!/bin/bash
# Host test for sources/charge-mode.sh under busybox ash in bwrap: fake /sys, FIFO key nodes and
# an fbv stub that logs what it draws. Needs bwrap + busybox (the richese Lima VM).
#   test/run.sh [quick]   quick skips the blank/wake case (about 65 s)
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$T"' EXIT
cp "$HERE/sources/charge-mode.sh" "$T/charge-mode.sh"   # a frozen copy: ash reads scripts as it runs
fails=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fails=$((fails + 1)); }

setup() {
  rm -rf "$T/root"; mkdir -p "$T/root"; cd "$T/root" || exit 1
  mkdir -p sys/class/power_supply/{ac,usb,battery} sys/class/graphics/fb0 \
    sys/devices/system/cpu/cpufreq/policy0 devinput storage flash frames bin
  echo 0 > sys/class/power_supply/ac/online; echo 1 > sys/class/power_supply/usb/online
  echo 42 > sys/class/power_supply/battery/capacity
  echo 0 > sys/class/graphics/fb0/blank
  for l in 0 1 2 3 4; do mkdir -p "sys/class/leds/led-$l"; echo 0 > "sys/class/leds/led-$l/brightness"; done
  echo schedutil > sys/devices/system/cpu/cpufreq/policy0/scaling_governor
  i=0
  for name in "rk805 pwrkey" "rockchip-rk817 Headset" gpio-keys pixel2_joypad; do
    mkdir -p "sys/class/input/event$i/device"; echo "$name" > "sys/class/input/event$i/device/name"
    mkfifo "devinput/event$i"; i=$((i + 1))
  done
  for l in $(seq 0 5 100); do : > "frames/level-$(printf %03d "$l").bmp"; done
  : > flash/logo.bmp
  printf '#!/bin/sh\necho "$*" >> /storage/fbv.log\n' > bin/fbv; chmod +x bin/fbv
  # a plug-in power-on (rk808's probe line) on a cold boot (boot-mode register 0)
  mkdir -p fake; echo "[    1.52] rk808 0-0020: source: on=0x40, off=0x08" > fake/dmesg
  echo 0x00000000 > fake/devmem
  printf '#!/bin/sh\ncat /fake/dmesg\n' > bin/dmesg
  printf '#!/bin/sh\n[ "$1 $2" = "0xff010200 32" ] && [ -s /fake/devmem ] && cat /fake/devmem\n' > bin/devmem
  chmod +x bin/dmesg bin/devmem
  for a in sh cat cut wc dd tr kill rm usleep sleep sed tail mv; do ln -s /usr/bin/busybox "bin/$a"; done
}

# ev FIFO TYPE CODE VALUE: one 64-bit struct input_event (zero time) into an open FIFO fd.
ev() { printf "$(printf '\\x%02x' 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 $(($2 & 255)) $(($2 >> 8)) \
  $(($3 & 255)) $(($3 >> 8)) $(($4 & 255)) 0 0 0)" >&"$1"; }
press() { ev "$1" 1 "$2" 1; ev "$1" 0 0 0; ev "$1" 1 "$2" 0; ev "$1" 0 0 0; }

start() {
  bwrap --unshare-all --die-with-parent --new-session \
    --ro-bind /usr/lib /usr/lib --symlink usr/lib /lib --ro-bind /usr/bin/busybox /usr/bin/busybox \
    --proc /proc --dev /dev --tmpfs /tmp \
    --bind "$T/root/sys" /sys --bind "$T/root/devinput" /dev/input --bind "$T/root/storage" /storage \
    --bind "$T/root/flash" /flash --bind "$T/root/frames" /frames --bind "$T/root/bin" /bin \
    --ro-bind "$T/root/fake" /fake \
    --ro-bind "$T/root/bin/fbv" /usr/bin/fbv --ro-bind "$T/charge-mode.sh" /charge-mode.sh \
    --setenv PATH /bin --setenv CHARGE_MODE_LOG /storage/charge.log \
    /bin/sh /charge-mode.sh /frames &
  PID=$!
  # read-write opens never block, even if the sandbox failed to start
  exec 3<>"$T/root/devinput/event0" 4<>"$T/root/devinput/event2" 5<>"$T/root/devinput/event3"
}
finish() { exec 3>&- 4>&- 5>&-; }
waitrc() { local n=0; while kill -0 "$PID" 2>/dev/null && [ $n -lt "$1" ]; do sleep 0.25; n=$((n + 1)); done
  if kill -0 "$PID" 2>/dev/null; then kill "$PID"; wait "$PID" 2>/dev/null; RC=timeout; else wait "$PID"; RC=$?; fi; }
S() { cat "$T/root/$1" 2>/dev/null; }
L() { for l in 0 1 2 3 4; do printf %s "$(S sys/class/leds/led-$l/brightness)"; done; }
LS() { for _ in 1 2 3 4 5 6 7 8; do L; echo; sleep 0.3; done | sort -u | tr '\n' ' '; }   # distinct states, 2.4 s

# 1: lit screen, power key boots: level frame first, splash last, governor restored.
setup; start; sleep 2
press 3 116; waitrc 20; finish
[ "$RC" = 0 ] && ok "power key -> exit 0" || bad "power key -> rc $RC"
[ "$(head -1 storage/fbv.log)" = "-c -i -y /frames/level-040.bmp" ] && ok "first frame level-040" || bad "first frame: $(head -1 storage/fbv.log)"
[ "$(tail -1 storage/fbv.log)" = "-c -i -y /flash/logo.bmp" ] && ok "splash after power" || bad "last frame: $(tail -1 storage/fbv.log)"
[ "$(S sys/devices/system/cpu/cpufreq/policy0/scaling_governor)" = schedutil ] && ok "governor restored" || bad "governor $(S sys/devices/system/cpu/cpufreq/policy0/scaling_governor)"
grep -q "power key /dev/input/event0, pads /dev/input/event2 /dev/input/event3" storage/charge.log && ok "key nodes found by name" || bad "nodes: $(head -1 storage/charge.log)"

# 2: a pad press while lit does not boot; a level change redraws; charger gone 3 s -> exit 2.
setup; start; sleep 2
press 5 304; sleep 1
echo 47 > sys/class/power_supply/battery/capacity; sleep 1
[ "$(tail -1 storage/fbv.log)" = "-c -i -y /frames/level-045.bmp" ] && ok "redraw on level change" || bad "after level change: $(tail -1 storage/fbv.log)"
kill -0 "$PID" 2>/dev/null && ok "pad press while lit keeps charging" || bad "exited on a pad press"
echo 0 > sys/class/power_supply/usb/online; sleep 1.5
kill -0 "$PID" 2>/dev/null && ok "still up 1.5 s after unplug" || bad "powered off too early"
waitrc 20; finish
[ "$RC" = 2 ] && ok "charger gone -> exit 2" || bad "charger gone -> rc $RC"
grep -q "charger removed at 47%" storage/charge.log && ok "logged removal" || bad "log: $(tail -1 storage/charge.log)"

# 3: blip of the charger shorter than 3 s is ignored.
setup; start; sleep 2
echo 0 > sys/class/power_supply/usb/online; sleep 1; echo 1 > sys/class/power_supply/usb/online; sleep 3
kill -0 "$PID" 2>/dev/null && ok "1 s charger blip ignored" || bad "exited on a blip"
press 3 116; waitrc 20; finish; [ "$RC" = 0 ] && ok "then power -> exit 0" || bad "rc $RC"

# 4: ac online alone counts as a charger; no frames -> boot at once.
setup; echo 1 > sys/class/power_supply/ac/online; echo 0 > sys/class/power_supply/usb/online
start; sleep 4; kill -0 "$PID" 2>/dev/null && ok "ac online counts" || bad "exited with ac online"
press 3 116; waitrc 20; finish
setup; rm -f frames/*; start; waitrc 20; finish
[ "$RC" = 0 ] && ok "no frames -> exit 0" || bad "no frames -> rc $RC"

# 6: only a cold plug-in power-on enters: not the power key, a reboot, or unread values.
for c in "power key:0x80:0x00000000" "key and plug:0xc0:0x00000000" "warm reboot:0x40:0x5242C300" \
         "panic reboot:0x40:0x5242C307" "no source line::0x00000000" "devmem unread:0x40:"; do
  IFS=: read -r what on mode <<< "$c"
  setup; [ -n "$on" ] && echo "[ 1.5] rk808 0-0020: source: on=$on, off=0x08" > fake/dmesg || : > fake/dmesg
  echo "$mode" > fake/devmem; [ -n "$mode" ] || : > fake/devmem
  start; waitrc 8; finish
  [ "$RC" = 0 ] && [ ! -s storage/fbv.log ] && ok "$what -> boot, nothing drawn" || bad "$what -> rc $RC, drew $(wc -l < storage/fbv.log 2>/dev/null)"
  grep -q "not a charger power-on" storage/charge.log && ok "$what logged" || bad "$what log: $(cat storage/charge.log)"
done
setup; echo "[ 1.5] rk808 0-0020: source: on=0x80, off=0x08" > fake/dmesg
for i in $(seq 1 1500); do echo "old line $i of the boot log, padded to grow past the cap"; done > storage/charge.log
start; waitrc 8; finish
[ "$(wc -l < storage/charge.log)" -le 201 ] && tail -1 storage/charge.log | grep -q "power-on" \
  && ok "log over 64 KB cut to its last 200 lines" || bad "log now $(wc -lc < storage/charge.log)"
setup; start; sleep 1; grep -q "on=0x40 boot-mode=0x00000000: charger power-on" storage/charge.log \
  && ok "cold plug-in logged" || bad "log: $(cat storage/charge.log)"
press 3 116; waitrc 20; finish

# 5: dark after 30 s; a pad press (BTN_SOUTH) or the power key while dark only wakes; power then boots.
if [ "${1:-}" != quick ]; then
  setup; start; sleep 2
  [ "$(L)" = 00000 ] && ok "LEDs off while lit" || bad "LEDs lit: $(L)"
  sleep 30
  [ "$(S sys/class/graphics/fb0/blank)" = 4 ] && ok "blank after 30 s" || bad "blank=$(S sys/class/graphics/fb0/blank)"
  st=$(LS)
  [ "$st" = "01000 01100 " ] && ok "42%: green 1 solid, green 2 blinks" || bad "42% LED states: $st"
  press 5 304; sleep 1
  [ "$(S sys/class/graphics/fb0/blank)" = 0 ] && ok "pad press wakes" || bad "after pad: blank=$(S sys/class/graphics/fb0/blank)"
  [ "$(L)" = 00000 ] && ok "LEDs off on wake" || bad "LEDs after wake: $(L)"
  [ "$(tail -1 storage/fbv.log)" = "-c -i -y /frames/level-040.bmp" ] && ok "frame redrawn on wake" || bad "after wake: $(tail -1 storage/fbv.log)"
  echo 100 > sys/class/power_supply/battery/capacity
  sleep 31
  [ "$(S sys/class/graphics/fb0/blank)" = 4 ] && ok "dark again" || bad "blank=$(S sys/class/graphics/fb0/blank)"
  st=$(LS)
  [ "$st" = "01111 " ] && ok "100%: four green solid" || bad "100% LED states: $st"
  press 3 116; sleep 1
  kill -0 "$PID" 2>/dev/null && ok "power while dark only wakes" || bad "booted from dark"
  [ "$(S sys/class/graphics/fb0/blank)" = 0 ] && ok "unblanked" || bad "blank=$(S sys/class/graphics/fb0/blank)"
  press 3 116; waitrc 20; finish; [ "$RC" = 0 ] && ok "power while lit -> exit 0" || bad "rc $RC"
  [ "$(L)" = 00000 ] && ok "LEDs off when booting" || bad "LEDs at boot: $(L)"
fi

pgrep -f charge-mode.sh >/dev/null && bad "a charge-mode.sh process is left over" || ok "no leftover processes"
echo "$fails failure(s)"; exit $((fails > 0))
