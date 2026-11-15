# OpenCode VS Code Tunnel

App Home Assistant (HAOS) qui exécute, dans un conteneur unique :

- un **serveur OpenCode** (service managé, API + interface web), accessible en local et, en option, via Cloudflare ;
- un **tunnel VS Code** (`code tunnel`, authentification GitHub), utilisable depuis `vscode.dev` ou VS Code Desktop ;
- un **espace de travail partagé** (`/share/opencode`) pour que l'extension OpenCode et le serveur voient les mêmes chemins.

Le dépôt publie **deux apps construites depuis la même image** :

| App | `/config` | Usage |
| --- | --- | --- |
| **OpenCode VS Code Tunnel** | écriture | Accès complet : toi (VS Code, terminal) **et** l'agent pouvez modifier les fichiers, y compris `configuration.yaml`, ESPHome et composants custom. **Recommandé**, avec les options de hardening. |
| **OpenCode VS Code Tunnel (read-only)** | **lecture seule** | Aucune édition de fichier, ni par l'agent ni par toi. Tout passe par l'API et le MCP. |

Le montage en lecture seule s'applique au **conteneur entier** : VS Code, son terminal et les scripts voient le même `/config` en ro. L'app read-only n'est donc pas « la même app avec des garde-fous pour l'IA » : elle empêche aussi l'édition manuelle depuis VS Code. Elle convient à la consultation et aux actions par l'API ; les fichiers se modifient alors depuis Samba, File Editor ou Studio Code Server.

Conséquence pour un composant Home Assistant (futur `opencode_assist`, §2.11) : le copier dans `/config/custom_components` **depuis l'app** exige l'app en écriture. Avec l'app read-only, l'installation se fait par Samba ou File Editor ; une fois installé, le composant fonctionne avec les deux apps puisqu'il parle à l'app en HTTP.

Conçu pour aarch64 (Raspberry Pi 4/5) et x86_64 : le runtime détecte l'architecture. Le conteneur n'a ni accès à l'hôte, ni Docker, ni systemd.

## Architecture

```
Client (vscode.dev / VS Code Desktop) ──► tunnel Microsoft ──► code tunnel (conteneur)
Client (app OpenCode / navigateur)     ──► Cloudflare        ──► service OpenCode :4096
                                                                   │
                                          /share/opencode (workspace, rw)
                                          /config         (config HA, rw ou ro selon l'app)
                                          /data           (état privé de l'app)
```

Deux processus supervisés dans le conteneur :

- `code tunnel` (tâche de fond, relancé automatiquement) ;
- le **service managé OpenCode** (`opencode service`), surveillé toutes les 30 s et relancé si le port ne répond plus. Les logs du service sont recopiés dans le journal de l'app.

## Prérequis

- Home Assistant OS, architecture **aarch64** (Raspberry Pi 4/5) ou **amd64**.
- Un compte **GitHub** (ou Microsoft) pour le tunnel VS Code.
- Un accès Internet sortant en 443.
- Optionnel : un domaine chez Cloudflare pour l'accès mobile, et une clé API d'un fournisseur de modèle.

## Installation

1. HA → Paramètres → Apps → **Store** → ⋮ → **Dépôts** : ajouter `https://github.com/Edenglish92/ha-opencode`.
2. Installer **OpenCode VS Code Tunnel** (écriture) ou **OpenCode VS Code Tunnel (read-only)**.
3. Renseigner les options (au minimum `opencode_password`), démarrer.
4. Au premier démarrage, le journal affiche une URL `https://github.com/login/device` et un code. Saisir le code avec le compte GitHub : le tunnel prend le nom défini dans `tunnel_name`.
5. Ouvrir `https://vscode.dev/tunnel/<tunnel_name>/share/opencode`.

Les deux apps peuvent cohabiter : elles ont leur propre `/data`, et des noms de tunnel par défaut différents (`opencode` et `opencode-ro`).

## Options

| Option | Type | Défaut | Description |
| --- | --- | --- | --- |
| `tunnel_name` | texte | `opencode` | Nom du tunnel VS Code. L'URL devient `https://vscode.dev/tunnel/<nom>`. Défaut `opencode-ro` dans l'app read-only. |
| `accept_license` | booléen | `true` | Accepte les termes de licence du serveur VS Code (`--accept-server-license-terms`). |
| `opencode_password` | mot de passe | vide | **Obligatoire.** Mot de passe Basic auth de l'API OpenCode (utilisateur : `opencode`). Vide = l'app refuse de démarrer. |
| `public_url` | texte | — | URL publique utilisée par `opencode-pair` pour construire les liens de pairing (ex. `https://opencode.example.com`). |
| `ha_mcp_url` | mot de passe | vide | URL complète du serveur MCP `ha-mcp` distant (contient un jeton). Vide = la clé `ha-mcp` est retirée de la configuration OpenCode. |
| `opencode_version` | texte | `2.3.0` | Version d'OpenCode à installer. `latest` interroge l'API GitHub au démarrage. |
| `default_agent` | texte | `plan` | Agent par défaut écrit dans `opencode.json`. Vide = clé inchangée. |
| `default_model` | texte | vide | Modèle par défaut, au format `fournisseur/modèle` (ex. `opencode-go/deepseek-v4.1-flash`). Vide = clé inchangée. |
| `hardening_deny_secrets` | booléen | `true` | Interdit à l'**outil d'édition** d'écrire dans `/config/secrets.yaml`, `/config/.storage/*` et `/data/*` ; demande confirmation avant de lire `secrets.yaml` ; bloque aussi, côté shell, les commandes qui citent `secrets.yaml` ou `.storage`. |
| `hardening_ask_config_edit` | booléen | `false` | Demande confirmation avant toute édition sous `/config`. |
| `hardening_ask_shell` | booléen | `false` | Demande confirmation avant toute commande shell. |
| `seed_agents_md` | booléen | `true` | Crée `/share/opencode/AGENTS.md` au premier démarrage **s'il est absent** ; ne l'écrase jamais. |
| `install_opencode_extension` | booléen | `true` | Installe l'extension VS Code **OpenCode V2** dans le serveur au premier démarrage si elle manque. |

Le mot de passe et l'URL MCP ne sont jamais affichés dans les journaux.

## Durcissement

Quatre couches, de la plus souple à la plus dure :

| Couche | Ce qu'elle fait | Appliquée par |
| --- | --- | --- |
| `AGENTS.md` et skills | demandent l'accord, interdisent certains gestes | ❌ le prompt seulement (consultatif) |
| Permissions OpenCode | `deny` / `ask` avant l'exécution d'un outil | ✅ le runtime OpenCode |
| Policies HA-MCP | lecture seule, approbation par outil, endpoint `/readonly` | ✅ le serveur HA-MCP |
| Montage `/config` | l'écriture échoue au niveau du système de fichiers | ✅ le noyau |

`AGENTS.md` n'est **pas une frontière de sécurité** : une erreur du modèle ou une injection de prompt peut le contourner. Les permissions, les policies HA-MCP et le montage en lecture seule sont les seules barrières réellement appliquées.

### Profils

| HA-MCP | `/config` | Ce que l'agent peut faire |
| --- | --- | --- |
| complet | écriture *(app par défaut)* + hardening | Tout, y compris `configuration.yaml`, ESPHome, composants custom. **Recommandé.** |
| complet | lecture seule | Tout via l'API et le MCP ; aucune édition de fichier. Plus sûr, mais VS Code ne peut plus éditer `/config` non plus. |
| lecture seule | écriture | Uniquement les fichiers ; aucune écriture via le MCP. |
| lecture seule | lecture seule | Lecture intégrale, aucun changement. |

Le profil read-only est le plus strict, mais il change aussi **ton** usage : dans cette app, VS Code ne peut plus modifier la configuration Home Assistant. Si tu veux garder l'édition manuelle dans VS Code, reste sur l'app en écriture avec `hardening_deny_secrets`.

### Permissions gérées

Quand une option `hardening_*` est active, l'app écrit les règles correspondantes dans `/data/home/.config/opencode/opencode.json` **à chaque démarrage** :

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

Ces règles appartiennent à l'app : les supprimer ou les modifier à la main n'a pas d'effet durable, elles réapparaissent au redémarrage. Pour les changer, utiliser les options de l'app. Les règles portant sur d'autres actions ou chemins sont conservées.

Les permissions filtrent **par outil**. Les deux règles `shell` ci-dessus couvrent les formes simples (`cat`, `sed -i`, `echo >`, `cp`, `grep`, y compris après un `cd /config/.storage`) et **ne bloquent pas** le reste des commandes. Elles restent **best-effort** : un chemin construit (`F=…; cat $F`) ou un outil détourné peut passer. Une édition faite par toi dans VS Code n'est pas concernée non plus. Pour un contrôle plus large, activer `hardening_ask_shell` ; pour une barrière absolue, utiliser l'app read-only.

### Côté HA-MCP

Ce que l'agent peut modifier **via le MCP** se règle dans HA-MCP, pas dans cette app :

- activer le **Read Only Mode** ;
- définir des policies d'approbation par outil (`ha_manage_security_policy`) ;
- ou pointer `ha_mcp_url` vers l'endpoint **`/readonly`** du serveur.

L'app ne peut pas modifier ces réglages.

## Emplacements

| Chemin | Contenu | Exposé |
| --- | --- | --- |
| `/data` | État privé de l'app : binaires téléchargés, `HOME`, config OpenCode, base des sessions, authentification du tunnel | non |
| `/data/home/.config/opencode/opencode.json` | Config OpenCode : agent et modèle par défaut, permissions, serveurs MCP | non |
| `/data/home/.local/share/opencode/` | Base `opencode.db`, logs, identifiants des fournisseurs | non |
| `/data/home/.vscode-server/` | Serveur VS Code, extensions, réglages machine | non |
| `/data/bin/` | `code`, `opencode`, wrappers `opencode-client` / `opencode-pair` | non |
| `/share/opencode` | Espace de travail (fichiers du projet, `AGENTS.md`, skills) | Samba `share` |
| `/config` | Configuration Home Assistant | écriture (app standard) ou lecture seule (app read-only) |

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

L'extension **OpenCode V2** est installée automatiquement au démarrage si elle manque (`install_opencode_extension`). Pour la poser à la main dans un tunnel existant :

```bash
/data/bin/code --install-extension opencode-v2-maker.opencode-v2-vscode --force
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

Renseigner `ha_mcp_url` avec l'URL complète du serveur MCP (elle contient un jeton). Au démarrage, l'app fusionne la clé dans `opencode.json` sans toucher aux autres clés (`default_agent`, `model`, permissions), puis écrit le fichier en `600`.

Si l'option est vidée, la clé `ha-mcp` est retirée de la configuration.

Les serveurs MCP sont résolus **par répertoire** : le panneau MCP ne montre que ceux du dossier courant. Un premier appel peut renvoyer une liste vide, puis se remplir.

## Sécurité

- L'API OpenCode est protégée par **Basic auth** (un seul compte, mot de passe partagé). Il n'y a pas de MFA ni de comptes séparés.
- Le mot de passe n'est **jamais écrit dans les journaux** : la configuration du service est écrite directement (`service.json`, mode `600`) et les éventuelles occurrences historiques dans le log du service sont expurgées au démarrage.
- Le tunnel VS Code est lié au compte GitHub/Microsoft utilisé au pairing ; les ports forwardés restent privés.
- L'exposition via Cloudflare doit être accompagnée d'un **rate limiting** sur les chemins d'authentification (période minimale 10 s sur le plan Free).
- `https://<votre-domaine>` est public et visible dans les journaux de transparence des certificats.
- L'agent tourne dans le conteneur : pas d'accès à l'hôte, à Docker ou à systemd.
- L'app **read-only** monte `/config` en lecture seule : l'écriture y est impossible, quel que soit l'outil, **y compris VS Code et son terminal**.
- Ne jamais publier les options `opencode_password` / `ha_mcp_url`, ni l'URL MCP complète.

## Maintenance

- **Mise à jour d'OpenCode** : option `opencode_version` (`2.3.0` par défaut, ou `latest`). Un changement de valeur déclenche le téléchargement au prochain démarrage ; `Reconstruire` n'est pas nécessaire tant que le code ne change pas.
- **CLI VS Code** : téléchargé dans `/data/bin` et comparé au commit stable à chaque démarrage ; il est remplacé si le commit change. Le serveur VS Code se met à jour seul.
- **Mise à jour de l'app** : après une modification de `config.yaml`, `Vérifier les mises à jour` puis `Mettre à jour`. Pour un changement de code sans changement de version, `Reconstruire`.
- **Versions** : les deux apps partagent la même image et la même version ; le workflow mensuel met à jour les deux `config.yaml`.
- **Sauvegardes** : les sauvegardes HA incluent les données de l'app (`/data`), donc sessions et configuration OpenCode.

## Dépannage

| Symptôme | Cause / action |
| --- | --- |
| L'app ne démarre pas | `opencode_password` vide : renseigner l'option. |
| Extension OpenCode absente dans VS Code | `install_opencode_extension` désactivé, ou marketplace injoignable au démarrage : lancer `/data/bin/code --install-extension opencode-v2-maker.opencode-v2-vscode --force`. |
| `opencode mcp list` : « No MCP servers configured » | `ha_mcp_url` vide, ou service non redémarré après la modification de l'option. |
| MCP absent dans l'app | Résolution par répertoire : vérifier le dossier de la session. |
| Une édition est refusée sans demande | Règle `deny` de `hardening_deny_secrets` : c'est le comportement attendu pour `secrets.yaml`, `.storage` et `/data`. |
| Une permission personnalisée disparaît | Elle cible un motif géré par l'app : passer par les options `hardening_*`. |
| Caractères accentués illisibles | Vérifier la locale du terminal. À l'export/import de sessions, éviter de capturer la sortie d'un CLI UTF-8 avec PowerShell 5.1 en CP437 : rediriger via `cmd /c` ou forcer `[Console]::OutputEncoding` en UTF-8. |
| Notifications de ports forwardés | `remote.autoForwardPorts: false` dans les réglages machine de la machine distante, puis recharger la fenêtre. |
| `worktree discovery failed` dans les logs | Le workspace n'est pas un dépôt git : `git init /share/opencode` (facultatif). |
| Service à 49374 | Ancien service fantôme : `opencode service stop`. Le service managé doit être sur `0.0.0.0:4096`. |
| Tunnel déconnecté | Vérifier les logs de l'app, puis redémarrer l'app ; le compte GitHub doit toujours avoir accès. |
| Lenteur du terminal via le tunnel | Le relais Microsoft peut être éloigné ; préférer l'interface web OpenCode ou l'app mobile pour interagir. |

Journal : onglet **Journal** de l'app. Les logs du service OpenCode y sont recopiés.

## Limites connues

- Architectures publiées : **aarch64** et **amd64**.
- Un seul mot de passe partagé, sans MFA.
- `code tunnel` est un service Microsoft : accepter les termes du serveur VS Code et utiliser un compte GitHub/Microsoft.
- OpenCode est épinglé : une montée de version nécessite un rebuild.
- Pas de terminal intégré dans l'interface de l'app : les commandes se lancent via le terminal VS Code ou un accès SSH.
- En app read-only, le workspace `/share/opencode` reste accessible en écriture (sessions, dépôts, notes) ; seul `/config` est protégé.

## Désinstallation

Désinstaller l'app depuis Home Assistant. Le volume `/data` est supprimé ; `/share/opencode` et `/config` ne sont pas modifiés.

Penser à supprimer le hostname public Cloudflare et, si besoin, à révoquer le tunnel (`code tunnel unregister`) côté compte GitHub.
