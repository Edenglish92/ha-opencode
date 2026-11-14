# OpenCode VS Code Tunnel

App Home Assistant (HAOS) qui exécute, dans un conteneur unique :

- un **serveur OpenCode** (service managé, API + interface web), accessible en local et, en option, via Cloudflare ;
- un **tunnel VS Code** (`code tunnel`, authentification GitHub), utilisable depuis `vscode.dev` ou VS Code Desktop ;
- un **espace de travail partagé** (`/share/opencode`) pour que l'extension OpenCode et le serveur voient les mêmes chemins.

Conçu pour aarch64 (Raspberry Pi 4/5) ; le runtime détecte aussi x86_64, pour une image amd64 à venir. Le conteneur n'a ni accès à l'hôte, ni Docker, ni systemd.

## Architecture

```
Client (vscode.dev / VS Code Desktop) ──► tunnel Microsoft ──► code tunnel (conteneur)
Client (app OpenCode / navigateur)     ──► Cloudflare        ──► service OpenCode :4096
                                                                   │
                                          /share/opencode (workspace, rw)
                                          /config         (config HA, rw)
                                          /data           (état privé de l'app)
```

Deux processus supervisés dans le conteneur :

- `code tunnel` (tâche de fond, relancé automatiquement) ;
- le **service managé OpenCode** (`opencode service`), surveillé toutes les 30 s et relancé si le port ne répond plus. Les logs du service sont recopiés dans le journal de l'app.

## Prérequis

- Home Assistant OS, architecture **aarch64**.
- Un compte **GitHub** (ou Microsoft) pour le tunnel VS Code.
- Un accès Internet sortant en 443.
- Optionnel : un domaine chez Cloudflare pour l'accès mobile, et une clé API d'un fournisseur de modèle.

## Installation

1. Copier le dossier de l'app dans `/local_apps/opencode_vscode/` (partage Samba `local_apps`, ou File Editor).
2. HA → Paramètres → Apps → **Vérifier les mises à jour** pour que l'app locale apparaisse.
3. Installer, renseigner les options, démarrer.
4. Au premier démarrage, le journal affiche une URL `https://github.com/login/device` et un code. Saisir le code avec le compte GitHub : le tunnel prend le nom défini dans `tunnel_name`.
5. Ouvrir `https://vscode.dev/tunnel/<tunnel_name>/share/opencode`.

## Options

| Option | Type | Défaut | Description |
| --- | --- | --- | --- |
| `tunnel_name` | texte | `rpi-opencode` | Nom du tunnel VS Code. L'URL devient `https://vscode.dev/tunnel/<nom>`. |
| `accept_license` | booléen | `true` | Accepte les termes de licence du serveur VS Code (`--accept-server-license-terms`). |
| `opencode_password` | mot de passe | vide | **Obligatoire.** Mot de passe Basic auth de l'API OpenCode (utilisateur : `opencode`). Vide = l'app refuse de démarrer. |
| `public_url` | texte | — | URL publique utilisée par `opencode-pair` pour construire les liens de pairing (ex. `https://opencode.example.com`). |
| `opencode_version` | texte | `2.3.0` | Version d'OpenCode à installer. `latest` interroge l'API GitHub au démarrage. |
| `ha_mcp_url` | mot de passe | vide | URL complète du serveur MCP `ha-mcp` distant (contient un jeton). Vide = la clé `ha-mcp` est retirée de la configuration OpenCode. |

Le mot de passe et l'URL MCP ne sont jamais affichés dans les journaux.

## Emplacements

| Chemin | Contenu | Exposé |
| --- | --- | --- |
| `/data` | État privé de l'app : binaires téléchargés, `HOME`, config OpenCode, base des sessions, authentification du tunnel | non |
| `/data/home/.config/opencode/opencode.json` | Config OpenCode : agent et modèle par défaut, serveurs MCP | non |
| `/data/home/.local/share/opencode/` | Base `opencode.db`, logs, identifiants des fournisseurs | non |
| `/data/home/.vscode-server/` | Serveur VS Code, extensions, réglages machine | non |
| `/data/bin/` | `code`, `opencode`, wrappers `opencode-client` / `opencode-pair` | non |
| `/share/opencode` | Espace de travail (fichiers du projet, `AGENTS.md`, skills) | Samba `share` |
| `/config` | Configuration Home Assistant | en écriture |

## Utilisation

### VS Code

- Web : `https://vscode.dev/tunnel/<tunnel_name>/share/opencode`
- Desktop : Remote Tunnels → `<tunnel_name>` → ouvrir `/share/opencode`
- Le fichier `opencode.code-workspace` (à la racine du workspace) contient le dossier et les réglages de l'extension.

Réglages machine écrits au premier démarrage (s'ils n'existent pas) :

```json
{
  "opencode.serverUrl": "http://127.0.0.1:4096",
  "opencode.command": "/data/bin/opencode-client",
  "remote.autoForwardPorts": false,
  "remote.otherPortsAttributes": { "onAutoForward": "ignore" }
}
```

### Terminal et CLI

```bash
opencode service status        # http://0.0.0.0:4096
opencode mcp list              # doit afficher ha-mcp connecté
opencode-client                # TUI connecté au serveur (wrapper, force --server)
opencode-pair                  # lien de pairing + QR (valide 5 min, usage unique)
```

Les wrappers se trouvent dans `/data/bin` et sont liés dans `/usr/local/bin`.

### App mobile

L'URL publique doit pointer vers `http://<hostname-du-conteneur>:4096` (le conteneur est joignable par son nom sur le réseau Docker `hassio`), ou vers l'IP de l'hôte si le port est publié.

Pairing : exécuter `opencode-pair` dans un terminal du conteneur, puis scanner le QR ou coller le lien dans l'app. Chaque code est **à usage unique** et expire en 5 minutes : ne pas ouvrir le lien d'abord dans un navigateur, ni le transmettre par une messagerie (l'aperçu consomme le code).

### API

```bash
. /data/home/.opencode-client.env
curl -s -u "opencode:$OPENCODE_SERVER_PASSWORD" http://127.0.0.1:4096/api/info
```

## MCP Home Assistant

Renseigner `ha_mcp_url` avec l'URL complète du serveur MCP (elle contient un jeton). Au démarrage, l'app fusionne la clé dans `opencode.json` sans toucher à `default_agent` ni `model`, puis écrit le fichier en `600`.

Si l'option est vidée, la clé `ha-mcp` est retirée de la configuration.

Les serveurs MCP sont résolus **par répertoire** : le panneau MCP ne montre que ceux du dossier courant. Un premier appel peut renvoyer une liste vide, puis se remplir.

## Sécurité

- L'API OpenCode est protégée par **Basic auth** (un seul compte, mot de passe partagé). Il n'y a pas de MFA ni de comptes séparés.
- Le tunnel VS Code est lié au compte GitHub/Microsoft utilisé au pairing ; les ports forwardés restent privés.
- L'exposition via Cloudflare doit être accompagnée d'un **rate limiting** sur les chemins d'authentification (période minimale 10 s sur le plan Free).
- `https://<votre-domaine>` est public et visible dans les journaux de transparence des certificats.
- L'agent tourne dans le conteneur : pas d'accès à l'hôte, à Docker ou à systemd.
- `/config` est monté en **écriture** par défaut : l'agent peut modifier la configuration Home Assistant. Chaque modification doit être approuvée explicitement. Pour un usage plus prudent, mettre `read_only: true` sur l'entrée `homeassistant_config` dans `config.yaml`, puis reconstruire.
- Ne jamais publier les options `opencode_password` / `ha_mcp_url`, ni l'URL MCP complète.

## Maintenance

- **Mise à jour d'OpenCode** : option `opencode_version` (`2.3.0` par défaut, ou `latest`). Un changement de valeur déclenche le téléchargement au prochain démarrage ; `Reconstruire` n'est pas nécessaire tant que le code ne change pas.
- **CLI VS Code** : téléchargé dans `/data/bin` et comparé au commit stable à chaque démarrage ; il est remplacé si le commit change. Le serveur VS Code se met à jour seul.
- **Mise à jour de l'app** : après une modification de `config.yaml`, `Vérifier les mises à jour` puis `Mettre à jour`. Pour un changement de code sans changement de version, `Reconstruire`.
- **Sauvegardes** : les sauvegardes HA incluent les données de l'app (`/data`), donc sessions et configuration OpenCode.

## Dépannage

| Symptôme | Cause / action |
| --- | --- |
| L'app ne démarre pas | `opencode_password` vide : renseigner l'option. |
| `opencode mcp list` : « No MCP servers configured » | `ha_mcp_url` vide, ou service non redémarré après la modification de l'option. |
| MCP absent dans l'app | Résolution par répertoire : vérifier le dossier de la session. |
| Caractères accentués illisibles | Vérifier la locale du terminal. À l'export/import de sessions, éviter de capturer la sortie d'un CLI UTF-8 avec PowerShell 5.1 en CP437 : rediriger via `cmd /c` ou forcer `[Console]::OutputEncoding` en UTF-8. |
| Notifications de ports forwardés | `remote.autoForwardPorts: false` dans les réglages machine de la machine distante, puis recharger la fenêtre. |
| `worktree discovery failed` dans les logs | Le workspace n'est pas un dépôt git : `git init /share/opencode` (facultatif). |
| Service à 49374 | Ancien service fantôme : `opencode service stop`. Le service managé doit être sur `0.0.0.0:4096`. |
| Tunnel déconnecté | Vérifier les logs de l'app, puis redémarrer l'app ; le compte GitHub doit toujours avoir accès. |
| Lenteur du terminal via le tunnel | Le relais Microsoft peut être éloigné ; préférer l'interface web OpenCode ou l'app mobile pour interagir. |

Journal : onglet **Journal** de l'app. Les logs du service OpenCode y sont recopiés.

## Limites connues

- Architecture publiée : **aarch64** (amd64 prévu ; le runtime détecte l'architecture).
- Un seul mot de passe partagé, sans MFA.
- `code tunnel` est un service Microsoft : accepter les termes du serveur VS Code et utiliser un compte GitHub/Microsoft.
- OpenCode est épinglé : une montée de version nécessite un rebuild.
- Pas de terminal intégré dans l'interface de l'app : les commandes se lancent via le terminal VS Code ou un accès SSH.

## Désinstallation

Désinstaller l'app depuis Home Assistant. Le volume `/data` est supprimé ; `/share/opencode` et `/config` ne sont pas modifiés.

Penser à supprimer le hostname public Cloudflare et, si besoin, à révoquer le tunnel (`code tunnel unregister`) côté compte GitHub.
