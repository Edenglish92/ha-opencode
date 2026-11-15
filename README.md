<div align="center">

# 🧠 OpenCode VS Code Tunnel for Home Assistant

**An OpenCode server _and_ a VS Code tunnel, side by side, on your Home Assistant box — Raspberry Pi (aarch64) and x86-64.**

[![Home Assistant App](https://img.shields.io/badge/Home%20Assistant-App-41BDF5?logo=homeassistant&logoColor=white)](https://www.home-assistant.io/)
[![Architecture](https://img.shields.io/badge/arch-aarch64%20%7C%20amd64-blue)](https://github.com/Edenglish92/ha-opencode)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Build](https://github.com/Edenglish92/ha-opencode/actions/workflows/build.yml/badge.svg)](https://github.com/Edenglish92/ha-opencode/actions/workflows/build.yml)
[![Lint](https://github.com/Edenglish92/ha-opencode/actions/workflows/lint.yml/badge.svg)](https://github.com/Edenglish92/ha-opencode/actions/workflows/lint.yml)

</div>

---

## ✨ What it does

| | |
|---|---|
| 🖥️ **VS Code, anywhere** | A `code tunnel` authenticated with your GitHub account: open the workspace from `vscode.dev` or VS Code Desktop. |
| 🤖 **OpenCode server** | The OpenCode managed service runs on `4096`, with a watchdog and its logs mirrored into the app log. |
| 🔗 **Shared workspace** | `/share/opencode` is visible from both sides, so the extension and the server see the same paths. |
| 🔐 **Password protected** | The OpenCode API requires Basic auth (`opencode` + your password). The app refuses to start without it. |
| 🧩 **Home Assistant MCP** | Point `ha_mcp_url` at your `ha-mcp` server and the assistant can drive Home Assistant. |
| 🔌 **Extension included** | The OpenCode V2 extension is installed into the VS Code server on first start (disable with `install_opencode_extension`). |
| 📱 **Companion app ready** | Pair the OpenCode mobile app with `opencode-pair` (link + QR code). |
| 🛠️ **Config access** | Two profiles from one image: `/config` read-write (recommended, with hardening) or **read-only** for API-only use. |

## 🚀 Quick start

1. **Add this repository** in Home Assistant: *Settings → Apps → App store → ⋮ → Repositories*.
2. **Install** `OpenCode VS Code Tunnel` (read-write) or `OpenCode VS Code Tunnel (read-only)` — see [Two profiles](#-two-profiles).
3. Set **`opencode_password`** — a long random value. The app will not start without it.
4. **Start** the app and open the **Log** tab.
5. On first start, the log shows a `https://github.com/login/device` link and a code: enter it with your GitHub account.
6. Open **`https://vscode.dev/tunnel/<tunnel_name>/share/opencode`** and start coding.

> 💡 The VS Code tunnel is account-bound: keep MFA enabled on the GitHub account that owns it.

## 🧩 Two profiles

The repository ships **two apps built from the same image** — same features, different `/config` access:

| App | `/config` | What it means |
|---|---|---|
| **OpenCode VS Code Tunnel** | read-write | You (VS Code, terminal) **and** the assistant can edit Home Assistant files. **Recommended, together with the hardening options.** |
| **OpenCode VS Code Tunnel (read-only)** | **read-only** | No file edits at all. Everything goes through the Home Assistant API and HA-MCP. |

The read-only mount applies to the **whole container**: VS Code, its terminal and every script see the same read-only `/config`. The read-only app is therefore not "the same app with guardrails for the AI" — it also prevents *you* from editing YAML from VS Code. Use it to consult and act through the API only, and edit files from outside (Samba, File Editor, Studio Code Server).

Both can be installed side by side: each has its own `/data` (and therefore its own session history) and a different default tunnel name (`opencode` and `opencode-ro`). The read-only app does not require a rebuild or a fork — it pulls the exact same image and version.

What changes **through HA-MCP** is configured in HA-MCP itself, not in this app: see [Security](#-security).

## ⚙️ Configuration

| Option | Default | Description |
|---|---|---|
| `tunnel_name` | `opencode` | Name of the VS Code tunnel (`vscode.dev/tunnel/<name>`). |
| `opencode_password` | — | **Required.** Basic auth password for the OpenCode API. |
| `public_url` | — | Public URL used by `opencode-pair` to build pairing links. |
| `ha_mcp_url` | — | Full URL of a remote `ha-mcp` server (contains a token, stored privately). |
| `opencode_version` | `2.3.0` | OpenCode version to install, or `latest`. |
| `default_agent` | `plan` | Default agent written to `opencode.json`. Empty leaves the key unchanged. |
| `default_model` | — | Default model id, e.g. `opencode-go/deepseek-v4.1-flash`. Empty leaves the key unchanged. |
| `hardening_deny_secrets` | `true` | Deny **file edits** (the `edit` tool) to `secrets.yaml`, `.storage` and `/data`; ask before reading `secrets.yaml`; deny shell commands that mention `secrets.yaml` or `.storage`. |
| `hardening_ask_config_edit` | `false` | Ask for approval before any edit under `/config`. |
| `hardening_ask_shell` | `false` | Ask for approval before shell commands. |
| `seed_agents_md` | `true` | Create `/share/opencode/AGENTS.md` on first start if missing (never overwritten). |
| `install_opencode_extension` | `true` | Install the OpenCode V2 VS Code extension into the server on first start if missing. |
| `accept_license` | `true` | Accept the VS Code Server license terms. |

📖 Full reference, paths, pairing, MCP and troubleshooting: **[opencode_vscode/DOCS.md](opencode_vscode/DOCS.md)**.

## 🔐 Security

This app is a powerful tool: it can edit your Home Assistant configuration and, through HA-MCP, change Home Assistant objects. Choose the level of power you need.

### Four layers

| Layer | What it does | Enforced by |
|---|---|---|
| `AGENTS.md` and skills | ask for approval, forbid some actions | ❌ the prompt only (advisory) |
| OpenCode **permissions** (`opencode.json`) | `deny` / `ask` before a tool runs | ✅ the OpenCode runtime |
| **HA-MCP** policies | read-only mode, per-tool approvals, `/readonly` endpoint | ✅ the HA-MCP server |
| `/config` **mount** | writes fail at the filesystem level | ✅ the kernel |

`AGENTS.md` is **not a security boundary**: a model mistake or a prompt injection can bypass it. Only permissions, HA-MCP policies and the read-only mount are enforced by the runtime.

### Managed permissions

When a `hardening_*` option is enabled, the app writes the matching rules into `/data/home/.config/opencode/opencode.json` **at every start**:

```jsonc
"permissions": [
  { "action": "edit", "resource": "/config/secrets.yaml", "effect": "deny" },
  { "action": "edit", "resource": "/config/.storage/*", "effect": "deny" },
  { "action": "edit", "resource": "/data/*", "effect": "deny" },
  { "action": "read", "resource": "/config/secrets.yaml", "effect": "ask" },
  { "action": "shell", "resource": "*secrets.yaml*", "effect": "deny" },
  { "action": "shell", "resource": "*/.storage*", "effect": "deny" }
]
```

These rules belong to the app: editing or removing them by hand has no lasting effect — they are rewritten on the next start. Change the app options instead. Rules that target other actions or paths are preserved.

Permissions are **per tool**. The two `shell` rules above catch the obvious forms (`cat`, `sed -i`, `echo >`, `cp`, `grep`, including after a `cd /config/.storage`) and leave every other command alone. They remain **best-effort**: a constructed path (`F=…; cat $F`) or a wrapper tool can slip through, and an edit you make yourself in VS Code is not covered. Enable `hardening_ask_shell` for broader control; use the read-only app for a hard filesystem boundary.

### Home Assistant side (HA-MCP)

What the assistant may change **through HA-MCP** is configured in **HA-MCP**, not in this app:

- enable **Read Only Mode**;
- define per-tool approval policies (`ha_manage_security_policy`);
- or point `ha_mcp_url` at the `/readonly` endpoint of your server.

### Other precautions

- 🔑 One shared password, no per-user accounts: use a **long random value** and rotate it if needed.
- 🙈 The API password is never written to the logs: the service configuration is written directly (`service.json`, mode `600`), and any historical occurrence in the service log is redacted at start.
- 🚦 If you expose the app through a tunnel, add **rate limiting** on the authentication paths.
- 🌍 A public hostname is discoverable through certificate transparency logs: treat it as public.
- 📦 The container has no access to the host, Docker or systemd.
- 🙈 Never share `opencode_password` or `ha_mcp_url`: the MCP URL contains a token.

## 🧭 Architecture

```
Client (app / browser)  ──► Cloudflare / local      ──► OpenCode service :4096
Client (VS Code)        ──► Microsoft dev tunnel    ──► code tunnel

                 /share/opencode  (shared workspace)
                 /config          (Home Assistant configuration)
                 /data            (private app state: sessions, config, auth)
```

## 🛠️ Maintenance

- **OpenCode**: change `opencode_version` and restart; the binary is downloaded only when the version changes.
- **VS Code CLI**: compared with the current stable commit at every start, replaced automatically when it changes.
- **App**: `Check for updates` → `Update` after a `config.yaml` change; `Rebuild` for code changes.
- **Monthly refresh**: a scheduled workflow bumps the patch version of **both apps** on the 1st of each month, which rebuilds and publishes fresh images (Debian base and packages). Dependabot keeps the GitHub Actions up to date.
- **Backups**: Home Assistant backups include the app's `/data` (sessions, configuration, tunnel auth).

## 📄 License

MIT — see [LICENSE](LICENSE).

Third-party components: OpenCode (MIT). The VS Code CLI and server are downloaded at runtime and subject to Microsoft's license terms.

<div align="center"><sub>Built for Home Assistant OS · Made to keep your editor and your assistant in one place.</sub></div>
