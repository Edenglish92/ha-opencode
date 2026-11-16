<div align="center">

# 🧠 OpenCode VS Code Tunnel for Home Assistant

**An OpenCode server _and_ a VS Code tunnel, side by side, on your Home Assistant box — Raspberry Pi (aarch64) and x86-64.**

[![Home Assistant App](https://img.shields.io/badge/Home%20Assistant-App-41BDF5?logo=homeassistant&logoColor=white)](https://www.home-assistant.io/)
[![Add repository to Home Assistant](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FEdenglish92%2Fha-opencode)
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

1. **Add this repository** with [one click](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FEdenglish92%2Fha-opencode), or in Home Assistant: *Settings → Apps → App store → ⋮ → Repositories* and paste `https://github.com/Edenglish92/ha-opencode`.
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
| **[OpenCode VS Code Tunnel](opencode_vscode/README.md)** | read-write | You (VS Code, terminal) **and** the assistant can edit Home Assistant files. **Recommended, together with the hardening options.** |
| **[OpenCode VS Code Tunnel (read-only)](opencode_vscode_ro/README.md)** | **read-only** | No file edits at all. Everything goes through the Home Assistant API and HA-MCP. |

The read-only mount applies to the **whole container**: VS Code, its terminal and every script see the same read-only `/config`. The read-only app is therefore not "the same app with guardrails for the AI" — it also prevents *you* from editing YAML from VS Code. Use it to consult and act through the API only, and edit files from outside (Samba, File Editor, Studio Code Server). It protects the **integrity** of your configuration, not its confidentiality: the assistant can still read `/config`, including through the permission gaps listed under [What these rules do not protect](#what-these-rules-do-not-protect).

Both can be installed side by side: each has its own `/data` (and therefore its own session history) and a different default tunnel name (`opencode` and `opencode-ro`). The read-only app does not require a rebuild or a fork — it pulls the exact same image and version.

What changes **through HA-MCP** is configured in HA-MCP itself, not in this app: see [Security](#-security).

## ⚙️ Configuration

| Option | Default | Description |
|---|---|---|
| `tunnel_name` | `opencode` | Name of the VS Code tunnel (`vscode.dev/tunnel/<name>`). |
| `opencode_password` | — | **Required.** Basic auth password for the OpenCode API, at least 16 characters. |
| `public_url` | — | Public URL used by `opencode-pair` to build pairing links. |
| `ha_mcp_url` | — | Full URL of a remote `ha-mcp` server (contains a token, stored privately). |
| `opencode_version` | `2.3.0` | OpenCode version to install, or `latest`. |
| `default_agent` | `plan` | Default agent written to `opencode.json`. Empty leaves the key unchanged. |
| `default_model` | — | Default model id, e.g. `opencode-go/deepseek-v4.1-flash`. Empty leaves the key unchanged. |
| `hardening_deny_secrets` | `true` | Deny reading and editing `secrets.yaml`, `.storage` and `/data`; deny shell commands that mention those paths or the app's credential files (`~/.config/opencode`, `~/.local/share/opencode`, `~/.vscode/cli`, `~/.copilot`, `~/.git-credentials`, `~/.opencode-client.env`); disable the `grep` tool. The critical ones are also written as non-overridable policies. |
| `hardening_ask_config_edit` | `false` | Ask for approval before any edit under `/config`. |
| `hardening_ask_shell` | `false` | Ask for approval before shell commands. |
| `hardening_deny_paths` | `[]` | Absolute paths refused in read and write, for secrets that live outside `secrets.yaml` (e.g. `/config/zigbee2mqtt/configuration.yaml`, `/config/esphome/secrets.yaml`). Applied through non-overridable policies; removing a path cleans its rules up at the next start. |
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
| OpenCode **policies** (`opencode.json`) | hard `deny` evaluated after every other rule, never overridable | ✅ the OpenCode runtime |
| **HA-MCP** policies | read-only mode, per-tool approvals, `/readonly` endpoint | ✅ the HA-MCP server |
| `/config` **mount** | writes fail at the filesystem level | ✅ the kernel |

`AGENTS.md` is **not a security boundary**: a model mistake or a prompt injection can bypass it. Only permissions, policies, HA-MCP policies and the read-only mount are enforced by the runtime.

### Managed permissions

When a `hardening_*` option is enabled, the app writes the matching rules into `/data/home/.config/opencode/opencode.json` **at every start**: an `permissions` array for `ask`/`deny`, and a `policies` array for the hard denies.

```jsonc
"policies": [
  { "action": "tool.use", "resource": "read:/config/secrets.yaml", "effect": "deny" },
  { "action": "tool.use", "resource": "edit:/config/secrets.yaml", "effect": "deny" },
  { "action": "tool.use", "resource": "read:/config/.storage/*", "effect": "deny" },
  { "action": "tool.use", "resource": "read:/data/options.json", "effect": "deny" },
  { "action": "tool.use", "resource": "shell:*secrets.yaml*", "effect": "deny" },
  { "action": "tool.use", "resource": "grep:*", "effect": "deny" }
]
```

Policies are evaluated after the permission rules, after agent rules and after saved approvals, and they can only deny — never grant. That is what makes them hold when a project-level `opencode.json` (which the assistant is able to write in `/share/opencode`) tries to widen the rules.

`grep` is denied under `hardening_deny_secrets` because its permission resource is the search **pattern**, not the path: a path-based rule is never consulted, so the tool could quietly pull secret values into the model context. Use the shell (`rg`) when you need a search; `hardening_ask_shell` is the real control there.

`hardening_deny_paths` covers the secrets that live outside `secrets.yaml`: a Zigbee2MQTT `configuration.yaml`, an ESPHome `secrets.yaml`, anything readable under `/config`. Each absolute path gets `read`/`edit` denies, the matching non-overridable `tool.use` policies, and a shell pattern on the literal path. The app keeps a record of the paths it applied (`.ha-opencode-extra-paths.json`, mode `600`, under `/data`) so that **removing a path from the option also removes its rules** at the next start — otherwise they would stay active, invisible, and you would keep being denied a file you thought you had released.

If a policy cannot be applied at start (invalid JSON), the app backs the file up as `opencode.json.invalide.<date>` and rewrites a clean one rather than running without rules; a failed rewrite stops the app instead of leaving it unprotected.

### What these rules do not protect

Stated plainly, because the alternative is a false sense of safety:

- **Permissions are a guardrail against accidents, not a confidentiality boundary.** A symlink created inside the workspace (`ln -s /config/secrets.yaml /share/opencode/x.yaml`) is read as a workspace path; the `deny` on `/config/secrets.yaml` is not consulted. This was measured, not assumed.
- **`glob` is gated by its pattern too**, so it can list names under `/config/.storage`. It never returns file contents, which is why it stays enabled.
- **The `shell` rules are substring filters.** A glob (`wc -l /config/secret*.yaml`), a variable (`F=…; cat $F`) or a wrapper evades them. `hardening_ask_shell` is the only broad control.
- **The read-only app protects integrity, not confidentiality**: it makes writes impossible, it does not hide a single byte.

If a secret was ever displayed to the model, no permission change makes it safe again — rotate it. Treat anything the assistant could read as disclosed.

### Home Assistant side (HA-MCP)

What the assistant may change **through HA-MCP** is configured in **HA-MCP**, not in this app:

- enable **Read Only Mode**;
- define per-tool approval policies (`ha_manage_security_policy`);
- or point `ha_mcp_url` at the `/readonly` endpoint of your server.

### Other precautions

- 🔑 One shared password, no per-user accounts: at least 16 characters, long and random — the app refuses to start with a shorter one. Rotate it if needed.
- 🙈 The API password is never written to the logs: the service configuration is written directly (`service.json`, mode `600`), and any historical occurrence in the service log is redacted at start.
- 🔗 **Pair the tunnel immediately.** Until the GitHub account is confirmed, `code tunnel` prints a device code (`https://github.com/login/device`) in the app log. Anyone who can read that log and reach GitHub before you can claim the tunnel name — and a claimed tunnel is a shell in this container. Complete the pairing right after the first start, and re-check the tunnel list on your account (`code tunnel list`) if you ever suspect a takeover.
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
- **Download integrity**: both binaries are verified against the `sha256` published by their vendor (the GitHub release asset digest for OpenCode, the VS Code update API for the CLI) before extraction. A mismatch rejects the archive and keeps the installed binary; a first install with a mismatch stops the app.
- **App**: `Check for updates` → `Update` after a `config.yaml` change; `Rebuild` for code changes.
- **Monthly refresh**: a scheduled workflow bumps the patch version of **both apps** on the 1st of each month, then publishes fresh images (Debian base and packages). Dependabot keeps the GitHub Actions up to date, and every action is pinned by commit SHA.

  The chain is explicit, because a commit pushed with `GITHUB_TOKEN` does **not** trigger workflows: the refresh job dispatches Lint on the new commit, Lint must pass, and only then does Build publish the image for `amd64` and `aarch64`. A manual Build run is accepted only for a commit that already has a successful Lint run, and a final job fails if the version tag is missing from the registry. To re-run after a failure: `gh workflow run lint.yml --ref main` (or re-run the failed Build job from the Actions tab).
- **Changelog**: `CHANGELOG.md` is mirrored into each app folder, because the Home Assistant update dialog reads it there. CI fails if the copies diverge.
- **Backups**: Home Assistant backups include the app's `/data` (sessions, configuration, tunnel auth).

## 📄 License

MIT — see [LICENSE](LICENSE).

Third-party components: OpenCode (MIT). The VS Code CLI and server are downloaded at runtime and subject to Microsoft's license terms.

<div align="center"><sub>Built for Home Assistant OS · Made to keep your editor and your assistant in one place.</sub></div>
