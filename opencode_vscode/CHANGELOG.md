# Changelog

## 0.8.6

- New option `hardening_deny_paths`: a list of absolute paths refused in read
  and write, for secrets that live outside `secrets.yaml` — a Zigbee2MQTT
  `configuration.yaml`, an ESPHome `secrets.yaml`. Each path gets `read`/`edit`
  denies in `permissions`, the matching non-overridable `tool.use` policies, and
  a shell pattern on the literal path. Non-absolute entries are reported and
  ignored.
- The app records the paths it applied in `.ha-opencode-extra-paths.json`
  (mode `600`, under `/data`), so removing a path from the option also removes
  its rules at the next start. Without that memory the old denies would stay
  active and invisible, silently blocking a file the option no longer mentions.
- Docs: the option, why it complements moving a secret out of `/config` rather
  than replacing it, and its limits (a shell path relative to `cd`, a glob, or a
  symlink still bypasses the literal shell pattern).

## 0.8.5

- Security: the downloaded binaries are verified before extraction. OpenCode is
  checked against the `sha256` digest GitHub publishes for its release asset,
  and the VS Code CLI against the `sha256hash` of the VS Code update API. A
  mismatch rejects the archive and keeps the installed binary; on a first
  install it stops the app. Archives are no longer extracted unverified as
  root.
- CI: every GitHub Action is pinned by commit SHA instead of a mutable tag
  (Dependabot still updates them).
- Startup: the service is probed for up to 30 seconds instead of a fixed 3, so
  a slow start no longer races with the `serve` fallback on the same port.
- Logs: the app log mirror starts at `tail -n 0`, so a restart no longer
  replays the whole `opencode.log` history into the app log. The full history
  stays in the file.
- Docs: integrity checks, the new log behaviour, and troubleshooting rows.

## 0.8.4

- Security: the critical denies are now written twice — as `permissions` for the
  interactive `ask`, and as **`policies`** (`tool.use`) for the hard `deny`.
  Policies are evaluated after every other rule and after saved approvals, and
  they can never grant, so a project-level `opencode.json` written by the
  assistant can no longer widen them.
- Security: `grep` is denied under `hardening_deny_secrets`. Its permission
  resource is the search pattern, not the path, so a path-based rule never
  applied and the tool could pull `secrets.yaml` values into the model context.
- Security: an invalid `opencode.json` is no longer ignored. It is kept as
  `opencode.json.invalide.<date>` and replaced by a clean file; a failed rewrite
  now stops the app instead of running without rules.
- Security: the app log mirror is filtered on the fly (API password and MCP
  URL), not only cleaned at start; `jq` receives the password and the MCP URL
  through a mode-600 file instead of the process command line; a malformed
  `ha_mcp_url` is rejected before it can reach the logs; a failed
  `service start` is reported instead of being swallowed.
- Docs: **new "What these rules do not protect" section**. Permissions are a
  guardrail against accidents, not a confidentiality boundary: a symlink in the
  workspace reads through a `deny`, `glob` lists names, `shell` rules are
  substring filters, and the read-only app protects integrity only. A secret
  that reached the model must be rotated.

## 0.8.3

- CI: the monthly refresh now triggers the release chain explicitly. A commit
  pushed with `GITHUB_TOKEN` does not start workflows, so the version bump used
  to leave the Supervisor offering a version whose image was never published.
  The chain is now bump → Lint → Build on the same commit; a manual Build run
  is accepted only for a commit that already has a successful Lint run, and a
  final job fails if the version tag is missing from the registry.
- Security: `opencode_password` must now be at least 16 characters long; the
  app refuses to start otherwise. **Breaking** for an existing shorter value.
- Security: `hardening_deny_secrets` now denies **reading** `secrets.yaml` and
  `.storage/*` (it only asked for confirmation before) and denies reading
  `/data`, which holds the API password, the MCP token and the tunnel
  authentication. Shell commands aimed at the app's credential files
  (`~/.config/opencode`, `~/.local/share/opencode`, `~/.vscode/cli`,
  `~/.copilot`, `~/.git-credentials`, `~/.opencode-client.env`,
  `~/.bash_history`, `/data/options.json`) are denied too. `~/.opencode/plan`
  stays readable so the Plan agent can reload its own plan.
- Docs: pairing window of the VS Code tunnel device code, updated permission
  list, and the real release chain.

## 0.8.2

- Security: the API password is no longer passed as a CLI argument, so it is
  no longer written to `opencode.log`. The service configuration is written
  directly to `service.json` (mode `600`), and historical occurrences of the
  password in the service log are redacted at start.
- New option `install_opencode_extension` (default `true`): install the OpenCode
  V2 VS Code extension into the server on first start if missing.
- Docs: password handling, extension installation and troubleshooting.

## 0.8.1

- `hardening_deny_secrets` also denies shell commands that mention
  `secrets.yaml` or `.storage` (targeted and best-effort; `/data` stays
  covered by the `edit` tool only, since the OpenCode binary lives there).
- Docs: permissions are per tool; what the shell rules do and do not cover.
- App icons (`icon.png`, `logo.png`).

## 0.8.0

- Second app `opencode_vscode_ro`: same image and version, `/config` mounted
  read-only. Both apps can be installed side by side.
- New options: `default_agent`, `default_model`, `hardening_deny_secrets`,
  `hardening_ask_config_edit`, `hardening_ask_shell`, `seed_agents_md`.
- `run.sh`: managed OpenCode permission rules rewritten at every start
  (rules targeting other actions or paths are preserved), optional `AGENTS.md`
  seeding when the file is missing, default agent/model merged without
  overwriting other keys.
- Docs: four-layer hardening model, profiles table, managed permissions,
  HA-MCP pointer, explicit note that `AGENTS.md` is advisory.
- CI: lint both apps and check that versions match; the monthly refresh bumps
  both `config.yaml` files.

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
