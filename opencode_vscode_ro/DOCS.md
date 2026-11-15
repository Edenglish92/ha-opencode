# OpenCode VS Code Tunnel (read-only)

Variante de **OpenCode VS Code Tunnel** construite depuis la **même image** et la **même version**, avec une seule différence : `/config` est monté en **lecture seule**.

| | App standard | Cette app |
| --- | --- | --- |
| `/share/opencode` | écriture | écriture |
| `/config` | écriture | **lecture seule** |
| Tunnel par défaut | `opencode` | `opencode-ro` |
| Options | 12 | identiques |

## Ce que ça change

- L'agent peut toujours **lire** la configuration Home Assistant et agir via l'API et le MCP (automatisations, scripts, dashboards, helpers, apps, sauvegardes).
- Il ne peut **pas** modifier `configuration.yaml`, `esphome/`, `custom_components/`, `custom_templates/` ni `www/`. Pour ces fichiers, demander un diff et l'appliquer avec File Editor, Studio Code Server ou Samba.
- Un dashboard déclaré en YAML ne peut pas être édité ; les dashboards en mode *storage* passent par l'API et restent modifiables.

## Installation

1. HA → Paramètres → Apps → **Store** → ⋮ → **Dépôts** : `https://github.com/Edenglish92/ha-opencode`.
2. Installer **OpenCode VS Code Tunnel (read-only)**.
3. Renseigner `opencode_password`, démarrer, puis suivre l'authentification du tunnel dans le journal.

Les deux apps peuvent cohabiter : `/data` est distinct et les noms de tunnel par défaut diffèrent.

## Durcissement

Les options `hardening_*` restent disponibles. En lecture seule, `hardening_ask_config_edit` devient sans effet (l'écriture échoue de toute façon), et `hardening_deny_secrets` continue de protéger `secrets.yaml`, `.storage` et `/data`.

Le durcissement des écritures **via le MCP** se règle dans HA-MCP : *Read Only Mode*, policies par outil (`ha_manage_security_policy`) ou endpoint `/readonly`.

## Documentation complète

Options, architecture, pairing, MCP, dépannage : [`opencode_vscode/DOCS.md`](https://github.com/Edenglish92/ha-opencode/blob/main/opencode_vscode/DOCS.md).
