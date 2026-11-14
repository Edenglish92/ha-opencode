# Changelog

## 0.6.1

- README, LICENSE (MIT) and CI workflows.
- `DOCS.md`: managed service wording (no more `opencode serve`).

## 0.6.0

- Name without the "POC" suffix.
- Managed OpenCode service (`0.0.0.0:4096`) with watchdog and log mirroring.
- `opencode-pair` helper (API-based pairing) and hardened client wrapper.
- UTF-8 locale, `OPENCODE_PASSWORD` exported for CLI commands.
- VS Code machine settings created on first start (no automatic port forwarding).

## 0.5.0

- `/config` mounted read-write.

## 0.4.0

- Optional `ha_mcp_url` (remote MCP) with targeted merge into the OpenCode config.
- `public_url` option for pairing links.

## 0.3.0

- `opencode_password` option (required), `DOCS.md`.

## 0.2.0

- OpenCode server added alongside the VS Code tunnel.

## 0.1.0

- Initial POC: VS Code tunnel only.
