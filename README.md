<div align="center">

# 🧠 OpenCode VS Code Tunnel for Home Assistant

**An OpenCode server _and_ a VS Code tunnel, side by side, on your Home Assistant box — Raspberry Pi (aarch64) and x86-64.**

[![Home Assistant App](https://img.shields.io/badge/Home%20Assistant-App-41BDF5?logo=homeassistant&logoColor=white)](https://www.home-assistant.io/)
[![Architecture](https://img.shields.io/badge/arch-aarch64-blue)](https://github.com/Edenglish92/ha-opencode)
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
| 📱 **Companion app ready** | Pair the OpenCode mobile app with `opencode-pair` (link + QR code). |
| 🛠️ **Config access** | `/config` is mounted read-write by default, so the assistant can work on your YAML — with approval rules. |

## 🚀 Quick start

1. **Add this repository** in Home Assistant: *Settings → Apps → App store → ⋮ → Repositories*.
2. **Install** `OpenCode VS Code Tunnel`.
3. Set **`opencode_password`** — a long random value. The app will not start without it.
4. **Start** the app and open the **Log** tab.
5. On first start, the log shows a `https://github.com/login/device` link and a code: enter it with your GitHub account.
6. Open **`https://vscode.dev/tunnel/<tunnel_name>/share/opencode`** and start coding.

> 💡 The VS Code tunnel is account-bound: keep MFA enabled on the GitHub account that owns it.

## ⚙️ Configuration

| Option | Default | Description |
|---|---|---|
| `tunnel_name` | `opencode` | Name of the VS Code tunnel (`vscode.dev/tunnel/<name>`). |
| `opencode_password` | — | **Required.** Basic auth password for the OpenCode API. |
| `public_url` | — | Public URL used by `opencode-pair` to build pairing links. |
| `ha_mcp_url` | — | Full URL of a remote `ha-mcp` server (contains a token, stored privately). |
| `opencode_version` | `2.3.0` | OpenCode version to install, or `latest`. |
| `accept_license` | `true` | Accept the VS Code Server license terms. |

📖 Full reference, paths, pairing, MCP and troubleshooting: **[opencode_vscode/DOCS.md](opencode_vscode/DOCS.md)**.

## 🔐 Security

- 🔑 One shared password, no per-user accounts: use a **long random value** and rotate it if needed.
- 🚦 If you expose the app through a tunnel, add **rate limiting** on the authentication paths.
- 🌍 A public hostname is discoverable through certificate transparency logs: treat it as public.
- 📁 `/config` is mounted **read-write** by default. Every change must be approved; set `read_only: true` in `config.yaml` for a stricter setup.
- 📦 The container has no access to the host, Docker or systemd.

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
- **Monthly refresh**: a scheduled workflow bumps the patch version on the 1st of each month, which rebuilds and publishes fresh images (Debian base and packages). Dependabot keeps the GitHub Actions up to date.
- **Backups**: Home Assistant backups include the app's `/data` (sessions, configuration, tunnel auth).

## 📄 License

MIT — see [LICENSE](LICENSE).

Third-party components: OpenCode (MIT). The VS Code CLI and server are downloaded at runtime and subject to Microsoft's license terms.

<div align="center"><sub>Built for Home Assistant OS · Made to keep your editor and your assistant in one place.</sub></div>
