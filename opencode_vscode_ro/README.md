# OpenCode VS Code Tunnel (read-only)

Same image and same version as **OpenCode VS Code Tunnel**, with one difference: `/config` is mounted **read-only** for the whole container.

| | Standard app | This app |
|---|---|---|
| `/share/opencode` | read-write | read-write |
| `/config` | read-write | **read-only** |
| Default tunnel name | `opencode` | `opencode-ro` |
| Options | 14 | identical |

## What changes

- **For the agent**: it can still read the Home Assistant configuration and act through the API and HA-MCP (automations, scripts, dashboards, helpers, apps, backups). It cannot modify `configuration.yaml`, `esphome/`, `custom_components/`, `custom_templates/` or `www/`.
- **For you**: VS Code and its terminal cannot write to `/config` either. To edit files, use Samba, File Editor, Studio Code Server — or install the standard app.
- It protects the **integrity** of your configuration, not its confidentiality: the agent can still read `/config`, including through the gaps described in [Security](../README.md#-security).

This app is for **reading and acting through the API**, not for remote VS Code editing of the configuration. Want manual editing from VS Code? Use the [standard app](../opencode_vscode/README.md) with `hardening_deny_secrets`.

## Install

[![Open your Home Assistant instance and show the add app repository dialog with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FEdenglish92%2Fha-opencode)

1. Add the repository with the button above, or in Home Assistant: *Settings → Apps → App store → ⋮ → Repositories* → `https://github.com/Edenglish92/ha-opencode`.
2. Install **OpenCode VS Code Tunnel (read-only)**.
3. Set **`opencode_password`** — at least 16 characters — then start and follow the GitHub device login in the **Log** tab.
4. Open `https://vscode.dev/tunnel/opencode-ro/share/opencode`.

Both apps can be installed side by side: each has its own `/data` (and session history) and a different default tunnel name.

## Documentation

Options, architecture, pairing, HA-MCP, hardening and troubleshooting: [DOCS.md](DOCS.md). Shared reference: [opencode_vscode/DOCS.md](../opencode_vscode/DOCS.md).
