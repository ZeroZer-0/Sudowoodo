# Chum Bucket Red Team — Tool Artifacts Reference

Quick reference for team members: where each tool's components live on the targets and how to access them.

---

## Sudowoodo (PATH-Hijack Credential Harvester)

**Targets:** All 5 Linux hosts (shellphone, bottlemail, pattyvault, thesafe, krustyfront)

| Location | What's There | Notes |
|---|---|---|
| `/usr/local/bin/` | 37 shell wrappers + passthrough stubs for every binary in `/usr/bin` and `/usr/sbin` | Wrappers shadow real binaries via PATH precedence. Stubs are `exec "/usr/bin/<name>" "$@"` passthroughs to make the directory look fully populated. |
| `/usr/lib/x86_64-linux-gnu/apt/methods/.d/` | Backup copies of all wrapper source files (`*_wrapper.sh`) | Mode `0700` root-only. Backups have the collector IP pre-baked (no `__ENC__` placeholder). Used by bonsly for restores. |
| `/var/lib/apt/lists/.cache/` | `events` (credential log), `bonsly.sh` (watchdog), `sync.log` (bonsly log) | Mode `0777` so any user's wrapper can write to `events`. |
| `/etc/environment` | `PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"` | Ensures `/usr/local/bin` is first in PATH for all sessions. |
| `/etc/profile.d/local-bin-path.sh` | PATH prepend script | Covers interactive non-login shells that don't read `/etc/environment`. |
| `/etc/cron.d/sudo-cache-clear` | Cron: invalidates sudo timestamp cache every 5 min | Forces password re-entry so wrappers can capture creds. |
| `/etc/cron.d/apt-daily-check` | Cron: restarts bonsly every 5 min if dead, reports `watcher_down` if script missing | Persistence mechanism — blue team killing bonsly doesn't stick. |
| `/usr/local/sbin/apt-daily-check` | Watchdog script for bonsly | Called by the cron above. |

### Credential Collector (C2)

| Item | Value |
|---|---|
| URL | `http://<c2_ip>:9001` |
| Cred endpoint | `POST /log` |
| User sync endpoint | `POST /sync` |
| Format | JSON (`host_ip`, `user`, `event_type`, `timestamp`, `data.password`, `data.command`) |

### Wrapped Commands

`sudo` `passwd` `su` `ssh` `useradd` `adduser` `userdel` `deluser` `usermod` `visudo` `systemctl` `ufw` `iptables` `ip6tables` `rm` `ls` `find` `ps` `kill` `pkill` `killall` `grep` `stat` `chmod` `chown` `mv` `cp` `which` `cat` `less` `more` `file` `strings` `diff` `md5sum` `sha256sum` `iptables-save` `ip6tables-save`

### Gray Team Bypass

Accounts `kingneptune`, `paintythepirate`, `greyteamadmin` pass straight through to real binaries — no interception.
