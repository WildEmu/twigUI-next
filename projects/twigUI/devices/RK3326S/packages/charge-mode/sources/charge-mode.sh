#!/bin/sh
# Charge screen for the GKD Pixel 2 (the oakMOSS model), run by the initramfs (init: charge_mode)
# with initramfs tools only: battery level, dark after 30 s (LEDs show it), any key wakes, power boots.
#   charge-mode.sh [FRAMES-DIR]   (default /sysroot/usr/share/charge-mode)
#   exit 0: not a charger power-on, or power key while lit: carry on booting
#   exit 2: charger gone for 3 s, power off (the caller unmounts and powers off)

FRAMES=${1:-/sysroot/usr/share/charge-mode}
FBV=/usr/bin/fbv
FBSYS=/sys/class/graphics/fb0
PS=/sys/class/power_supply
GOV=/sys/devices/system/cpu/cpufreq/policy0/scaling_governor
LOG=${CHARGE_MODE_LOG:-/storage/.charge-mode.log}
BLANK_AFTER=30
BOOT_MODE_REG=0xff010200    # PX30 PMU_GRF_OS_REG0: the kernel's reboot-mode magic, 0 on a cold boot

log() { echo "$(cut -d' ' -f1 /proc/uptime) charge-mode: $*" >> "$LOG" 2>/dev/null; }

[ $(( $( { wc -c < "$LOG"; } 2>/dev/null || echo 0) )) -gt 65536 ] &&
    tail -n 200 "$LOG" > "$LOG.new" 2>/dev/null && mv "$LOG.new" "$LOG"

# Powered on by plugging in: the RK817 on-source (rk808 logs it; bit 6 plug-in, bit 7 power key)
# on a cold boot. Anything unread counts as a normal boot.
on=$(dmesg 2>/dev/null | sed -n 's/.*source: on=0x\([0-9a-fA-F][0-9a-fA-F]*\),.*/\1/p' | tail -n 1)
mode=$(devmem $BOOT_MODE_REG 32 2>/dev/null)
if [ -z "$on" ] || [ -z "$mode" ] || [ $((0x$on & 0xc0)) -ne $((0x40)) ] || [ $((mode)) -ne 0 ]; then
    log "on=0x${on:-?} boot-mode=${mode:-?}: not a charger power-on"
    exit 0
fi
log "on=0x$on boot-mode=$mode: charger power-on"

online() {
    [ "$(cat $PS/ac/online 2>/dev/null)" = 1 ] || [ "$(cat $PS/usb/online 2>/dev/null)" = 1 ]
}

level() {
    c=$(cat $PS/battery/capacity 2>/dev/null)
    case "$c" in ''|*[!0-9]*) c=0 ;; esac
    echo "$c"
}

level_frame() {
    c=$(( ($(level) + 2) / 5 * 5 )); [ "$c" -gt 100 ] && c=100
    printf '%s/level-%03d.bmp' "$FRAMES" "$c"
}

# Same call as the init's splash: no clear, no info, no tty wait; it returns once drawn.
show() { "$FBV" -c -i -y "$1" > /dev/null 2>&1; }

# The five LEDs while the panel is dark, ROCKNIX's Pixel 2 charging pattern: led-0 red, led-1..4
# green bottom to top (active-low in the DTS, so 1 = on); solid to the level, the next one blinks.
LEDS=/sys/class/leds
leds() {
    [ "$*" = "$led_state" ] && return; led_state="$*"; _i=0
    for _v in "$@"; do echo "$_v" > "$LEDS/led-$_i/brightness" 2>/dev/null; _i=$((_i + 1)); done
}
leds_level() {
    c=$(level); b=$1
    if [ "$c" -ge 100 ] || [ "$(cat $PS/battery/status 2>/dev/null)" = Full ]; then leds 0 1 1 1 1
    elif [ "$c" -le 10 ]; then leds 1 "$b" 0 0 0
    elif [ "$c" -le 25 ]; then leds "$b" 1 0 0 0
    elif [ "$c" -le 50 ]; then leds 0 1 "$b" 0 0
    elif [ "$c" -le 75 ]; then leds 0 1 1 "$b" 0
    else leds 0 1 1 1 "$b"; fi
}

[ -x "$FBV" ] && [ -f "$FRAMES/level-100.bmp" ] || { log "no frames in $FRAMES, booting"; exit 0; }

gov=$(cat "$GOV" 2>/dev/null)
echo powersave > "$GOV" 2>/dev/null
echo 0 > "$FBSYS/blank" 2>/dev/null
frame=$(level_frame); show "$frame"

# Key nodes by name (no /dev/input/by-path in the initramfs). The joypad may register late.
pek=""; pads=""; n=0
while :; do
    pek=""; pads=""
    for d in /sys/class/input/event*; do
        case "$(cat "$d/device/name" 2>/dev/null)" in
            "rk805 pwrkey") pek=/dev/input/${d##*/} ;;
            gpio-keys|pixel2_joypad) pads="$pads /dev/input/${d##*/}" ;;
        esac
    done
    case "$pads" in *" "*" "*) [ -n "$pek" ] && break ;; esac
    [ "$n" -ge 20 ] && break
    usleep 250000; n=$((n + 1))
done
log "charging at $(level)% (governor $gov -> powersave), power key ${pek:-none}, pads${pads:- none}"

# A reader per node appends the raw 24-byte input_events to a file, so a press is told from
# its release and none is missed between ticks.
PEK_LOG=/tmp/charge-pek; PAD_LOG=/tmp/charge-pad
: > "$PEK_LOG"; : > "$PAD_LOG"
pids=""
[ -n "$pek" ] && { cat "$pek" >> "$PEK_LOG" & pids="$pids $!"; }
for p in $pads; do cat "$p" >> "$PAD_LOG" & pids="$pids $!"; done
pek_off=0; pad_off=0

# key_down FILE OFFSET: true if a whole event after OFFSET is a key going down (type EV_KEY 1,
# value 1); NEXT is the new offset. There is no od/hexdump here, so the type, code and value
# bytes (16..23 of a 64-bit input_event) go through tr: 00 -> z, 01 -> o, then a pattern match.
key_down() {
    _sz=$(( $(wc -c < "$1") )); _o=$2; _d=1
    while [ $((_o + 24)) -le "$_sz" ]; do
        _e=$(dd if="$1" bs=1 skip=$((_o + 16)) count=8 2>/dev/null | tr '\000\001' 'zo')
        case "$_e" in oz??ozzz) _d=0 ;; esac
        _o=$((_o + 24))
    done
    NEXT=$_o
    return $_d
}

stop_readers() {
    for p in $pids; do kill "$p" 2>/dev/null; done
    rm -f "$PEK_LOG" "$PAD_LOG"
}

# 4 ticks a second. The charger counts as gone only after 3 s offline (oakMOSS saw a fresh
# charger read offline once on a flat cell).
TICKS=$((BLANK_AFTER * 4)); lit=$TICKS; offline=0; tick=0
leds 0 0 0 0 0
while :; do
    tick=$((tick + 1))
    if online; then offline=0; else offline=$((offline + 1)); fi
    if [ "$offline" -ge 12 ]; then
        log "charger removed at $(level)%; powering off"
        stop_readers; leds 0 0 0 0 0
        exit 2
    fi
    power=1; other=1
    key_down "$PEK_LOG" "$pek_off" && power=0; pek_off=$NEXT
    key_down "$PAD_LOG" "$pad_off" && other=0; pad_off=$NEXT
    [ "$power" = 0 ] && [ "$lit" -gt 0 ] && break
    if [ "$power" = 0 ] || [ "$other" = 0 ]; then
        if [ "$lit" -eq 0 ]; then
            echo 0 > "$FBSYS/blank" 2>/dev/null
            frame=$(level_frame); show "$frame"
            log "woken at $(level)%"; leds 0 0 0 0 0
        fi
        lit=$TICKS
    fi
    if [ "$lit" -gt 0 ]; then
        new=$(level_frame)
        [ "$new" != "$frame" ] && { frame=$new; show "$frame"; }
        lit=$((lit - 1))
        [ "$lit" -eq 0 ] && echo 4 > "$FBSYS/blank" 2>/dev/null
    fi
    [ "$lit" -eq 0 ] && leds_level $((tick / 2 % 2))
    usleep 250000
done

stop_readers; leds 0 0 0 0 0
log "power key at $(level)%; booting"
echo 0 > "$FBSYS/blank" 2>/dev/null
[ -f /flash/logo.bmp ] && show /flash/logo.bmp
[ -n "$gov" ] && echo "$gov" > "$GOV" 2>/dev/null
exit 0
