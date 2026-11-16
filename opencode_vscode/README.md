# OpenCode VS Code Tunnel

Home Assistant app that runs, in a single container:

- an **OpenCode server** (managed service on port `4096`, Basic auth);
- a **VS Code tunnel** authenticated with GitHub (`code tunnel`);
- a shared workspace at `/share/opencode`;
- optional **read-write access to `/config`**, for you and the assistant.

This is the **read-write** profile. VS Code, its terminal and the OpenCode agent can edit Home Assistant files (`configuration.yaml`, ESPHome, `custom_components`, dashboards, …). Hardening options are available and recommended.

## Install

[![Open your Home Assistant instance and show the add app repository dialog with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FEdenglish92%2Fha-opencode)

1. Add the repository with the button above, or in Home Assistant: *Settings → Apps → App store → ⋮ → Repositories* → `https://github.com/Edenglish92/ha-opencode`.
2. Install **OpenCode VS Code Tunnel**.
3. Set **`opencode_password`** — at least 16 characters. The app refuses to start without it.
4. Start the app and follow the GitHub device login shown in the **Log** tab.
5. Open `https://vscode.dev/tunnel/<tunnel_name>/share/opencode`.

Prefer no file edits at all? Install [OpenCode VS Code Tunnel (read-only)](../opencode_vscode_ro/README.md) instead: same image, same version, `/config` mounted read-only.

## Documentation

Full reference — options, architecture, pairing, HA-MCP, hardening, troubleshooting: **[DOCS.md](DOCS.md)**.

## Security

This app is powerful: it can edit your Home Assistant configuration and, through HA-MCP, change Home Assistant objects. `AGENTS.md` and skills are advisory only. The enforced layers are OpenCode permissions and policies, HA-MCP policies and the `/config` mount. Read [Security](../README.md#-security) before enabling broad access.
