# Sudowoodo

Linux credential harvesting layer for CSEC 473. Deploys shell wrappers that intercept and log credentials passed to privileged commands, with a Flask collection server that aggregates everything and a watchdog that keeps it all running. Operates independently of Karen.

---

## What It Does

Sudowoodo has three components that work together:

**1. Shell wrappers (`wrappers/`)**
Thin shell scripts placed in `/usr/local/bin/` that shadow system commands (`sudo`, `su`, `ssh`, `passwd`, `useradd`, `userdel`, etc.). Each wrapper captures credentials or relevant arguments, POSTs them to the collection server, then calls the real binary — transparent to the user.

**2. Credential collection server (`cred_collector.py`)**
Flask app listening on port 9001. Receives credential reports from all wrappers across all deployed targets, stores them, and serves them through a local web interface.

**3. Watchdog (`wrappers/bonsly.sh`)**
Monitors the wrappers and collection server. Restarts the Flask server if it goes down, re-deploys missing wrappers, and persists across reboots via a cron job.

---

## Target Map

Sudowoodo deploys to the five Linux targets:

| Hostname | IP | Scored Service |
|---|---|---|
| shellphone | 10.111.1.1 | SMB |
| bottlemail | 10.111.1.2 | SMTP |
| pattyvault | 10.111.1.3 | PostgreSQL |
| thesafe | 10.111.1.4 | Apache |
| krustyfront | 10.111.1.5 | Nginx/WordPress |

---

## Repository Structure

```
Sudowoodo/
├── cred_collector.py             # Flask credential collection server (port 9001)
├── deploy_wrappers.yml           # Ansible: deploy all wrappers to Linux targets
├── REAL_inventory.ini            # Correct Ansible inventory (use this one)
├── inventory.ini                 # Original inventory (may be stale)
├── requirements.txt              # Python deps for cred_collector.py
├── test_wrappers.sh              # Verify wrappers are installed and intercepting
├── tool_doc_sudowoodo_linux.md   # Full operator reference
└── wrappers/
    ├── install_wrappers.sh       # Installs all wrappers to /usr/local/bin/
    ├── bonsly.sh                 # Watchdog — keeps wrappers and server alive
    ├── apt-daily-check           # Cron persistence for bonsly.sh
    ├── sudo_wrapper.sh           # Intercepts sudo credentials
    ├── su_wrapper.sh             # Intercepts su credentials
    ├── ssh_wrapper.sh            # Intercepts SSH credentials/keys/commands
    ├── passwd_wrapper.sh         # Intercepts password changes
    ├── useradd_wrapper.sh        # Logs user additions
    ├── userdel_wrapper.sh        # Logs user deletions
    ├── usermod_wrapper.sh        # Logs user modifications
    ├── adduser_wrapper.sh        # Logs adduser invocations
    ├── deluser_wrapper.sh        # Logs deluser invocations
    ├── visudo_wrapper.sh         # Intercepts sudoers edits
    ├── systemctl_wrapper.sh      # Logs service start/stop/enable/disable
    ├── iptables_wrapper.sh       # Logs firewall rule changes
    ├── iptables-save_wrapper.sh  # Logs iptables-save invocations
    ├── ufw_wrapper.sh            # Logs ufw rule changes
    ├── kill_wrapper.sh           # Logs kill signals
    ├── killall_wrapper.sh        # Logs killall invocations
    ├── pkill_wrapper.sh          # Logs pkill invocations
    ├── ls_wrapper.sh             # Logs sensitive directory listings
    ├── cat_wrapper.sh            # Logs reads of sensitive files
    ├── less_wrapper.sh           # Logs less on sensitive files
    ├── more_wrapper.sh           # Logs more on sensitive files
    ├── grep_wrapper.sh           # Logs grep on sensitive files
    ├── find_wrapper.sh           # Logs find with sensitive patterns
    ├── diff_wrapper.sh           # Logs diff on sensitive files
    ├── file_wrapper.sh           # Logs file command on sensitive paths
    ├── strings_wrapper.sh        # Logs strings on sensitive paths
    ├── stat_wrapper.sh           # Logs stat on sensitive files
    ├── md5sum_wrapper.sh         # Logs hash checks on sensitive files
    ├── sha256sum_wrapper.sh      # Logs hash checks on sensitive files
    ├── which_wrapper.sh          # Logs which lookups for interesting binaries
    ├── cp_wrapper.sh             # Logs copies involving sensitive paths
    ├── mv_wrapper.sh             # Logs moves involving sensitive paths
    ├── rm_wrapper.sh             # Logs deletions of sensitive files
    ├── chmod_wrapper.sh          # Logs permission changes
    ├── chown_wrapper.sh          # Logs ownership changes
    ├── ps_wrapper.sh             # Logs process listing (snapshot)
    └── setup_linux_testbox.sh    # Local test environment setup (not used in deployment)
```

---

## Credential Collection Server

`cred_collector.py` receives POST requests from wrappers on all targets and stores them.

**Start it (runs on the red team machine):**
```bash
pip install -r requirements.txt
python cred_collector.py
```

**Access:** `http://127.0.0.1:9001`

The server aggregates by target hostname, command intercepted, and timestamp. View collected credentials through the web interface.

---

## Deploying Wrappers

Requires Ansible on the control machine and SSH access to Linux targets.

```bash
ansible-playbook -i REAL_inventory.ini deploy_wrappers.yml
```

This pushes all wrapper scripts to each target's `/usr/local/bin/`, sets them executable, installs `bonsly.sh` as the watchdog, and sets up the cron persistence entry (`apt-daily-check`).

**Verify deployment:**
```bash
bash test_wrappers.sh
```

---

## How Wrappers Work

Each wrapper follows the same pattern:

1. Capture arguments and any stdin credentials before the real binary runs
2. POST the data to `cred_collector.py` on the collection server
3. Execute the real binary (at its original path, e.g. `/bin/sudo`) with all original arguments and stdin passed through
4. Exit with the real binary's exit code

The wrappers are transparent — the command succeeds exactly as it would without them. The blue team sees normal command behavior; only the collection server receives the intercepted data.

The wrappers live in `/usr/local/bin/` which takes precedence over `/usr/bin/` and `/bin/` in the default `$PATH`, so they shadow the real binaries without replacing them.

---

## Persistence (bonsly.sh)

`bonsly.sh` runs from cron every minute (via `apt-daily-check`). It:

- Checks that the collection server is reachable and restarts it if not
- Verifies each wrapper is present in `/usr/local/bin/` and re-installs missing ones
- Checks that `apt-daily-check` is still in cron and re-adds it if removed

The cron entry is named to blend with legitimate apt maintenance jobs.

---

## Competition Rules Compliance

- **Rule 6:** Wrappers are non-destructive — they pass all commands through to the real binary unchanged.
- **Never touched:** RustDesk ports 21115–21119 TCP, 21116 UDP. RDP port 3389. Karen backdoor port 8443.
- Sudowoodo is entirely independent of Karen — the two tools share an inventory file format but have no runtime dependency on each other.

---

## Full Operator Reference

See `tool_doc_sudowoodo_linux.md` for detection indicators and manual removal steps.
