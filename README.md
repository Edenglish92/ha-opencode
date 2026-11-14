# OpenCode VS Code Tunnel

Home Assistant app (add-on) that runs, in a single container:

- an **OpenCode server** (managed service, API and web UI), reachable locally and, optionally, through Cloudflare;
- a **VS Code tunnel** (`code tunnel`, GitHub authentication), usable from `vscode.dev` or VS Code Desktop;
- a **shared workspace** (`/share/opencode`) so that the OpenCode extension and the server see the same paths.

Built for Home Assistant OS on `aarch64` (Raspberry Pi 4/5). The container has no access to the host, to Docker, or to systemd.

## Features

- Managed OpenCode service with a watchdog; service logs are mirrored to the app log.
- VS Code tunnel started in the background and restarted automatically.
- Password required for the OpenCode API (Basic auth, user `opencode`).
- Optional remote MCP server (`ha-mcp`) configured from an app option.
- `opencode-pair` helper: generates a pairing link and QR code without relying on the background service.
- `/config` mounted read-write by default for direct Home Assistant configuration work (see Security).

## Requirements

- Home Assistant OS, `aarch64` (an `amd64` build is planned).
- A GitHub (or Microsoft) account for the VS Code tunnel.
- Outbound HTTPS (443).

## Installation

1. In Home Assistant: **Settings → Apps → App store → ⋮ → Repositories**.
2. Add `https://github.com/Edenglish92/ha-opencode`.
3. Install **OpenCode VS Code Tunnel**.
4. Set `opencode_password` (required) and start the app.
5. On first start, the log shows a `https://github.com/login/device` URL and a code. Enter the code with your GitHub account.
6. Open `https://vscode.dev/tunnel/<tunnel_name>/share/opencode`.

## Configuration

See [opencode_vscode/DOCS.md](opencode_vscode/DOCS.md) for the full option reference, paths, pairing, MCP setup, maintenance and troubleshooting.

## Security

- The OpenCode API uses a **single shared password** (no MFA, no per-user accounts). Use a long random value.
- If you expose the app through a tunnel, add **rate limiting** on the authentication paths.
- The public hostname is discoverable through certificate transparency logs; treat it as public.
- The container is isolated from the host, but `/config` is mounted read-write by default: every change must be approved. Set `read_only: true` on the `homeassistant_config` entry in `config.yaml` for a stricter setup.

## License

MIT. Third-party components: OpenCode (MIT); the VS Code CLI/server is downloaded at runtime and subject to Microsoft's license terms.
