#!/usr/bin/env bash
set -euo pipefail

OPTIONS=/data/options.json
TUNNEL_NAME="$(jq -r '.tunnel_name // "opencode"' "$OPTIONS")"
ACCEPT="$(jq -r '.accept_license // false' "$OPTIONS")"
PASSWORD="$(jq -r '.opencode_password // ""' "$OPTIONS")"
PUBLIC_URL="$(jq -r '.public_url // ""' "$OPTIONS")"
MCP_URL="$(jq -r '.ha_mcp_url // ""' "$OPTIONS")"
OC_VERSION_OPT="$(jq -r '.opencode_version // "2.3.0"' "$OPTIONS")"
DEFAULT_AGENT_OPT="$(jq -r '.default_agent // ""' "$OPTIONS")"
DEFAULT_MODEL_OPT="$(jq -r '.default_model // ""' "$OPTIONS")"
# jq '//' traite false comme absent : comparer explicitement pour garder le defaut vrai
HARDEN_DENY_SECRETS="$(jq -r 'if .hardening_deny_secrets == false then "false" else "true" end' "$OPTIONS")"
HARDEN_ASK_CONFIG="$(jq -r 'if .hardening_ask_config_edit == true then "true" else "false" end' "$OPTIONS")"
HARDEN_ASK_SHELL="$(jq -r 'if .hardening_ask_shell == true then "true" else "false" end' "$OPTIONS")"
SEED_AGENTS_MD="$(jq -r 'if .seed_agents_md == false then "false" else "true" end' "$OPTIONS")"

if [ -z "$PASSWORD" ]; then
  echo "[erreur] Renseigne 'opencode_password' dans la configuration de l'app, puis redemarre."
  exit 1
fi

export HOME=/data/home
export OPENCODE_PASSWORD="$PASSWORD"
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
mkdir -p "$HOME" /share/opencode /data/bin

# Architecture (binaires telecharges au premier demarrage)
case "$(uname -m)" in
  aarch64|arm64) ARCH=arm64 ;;
  x86_64|amd64)  ARCH=x64 ;;
  *) echo "[erreur] architecture non supportee : $(uname -m)"; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# CLI VS Code (non embarque dans l'image ; rafraichi si le commit change)
# ---------------------------------------------------------------------------
CLI=/data/bin/code
CLI_URL="https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-${ARCH}"
REMOTE_COMMIT="$(curl -sIL -o /dev/null -w '%{url_effective}' "$CLI_URL" 2>/dev/null | sed -n 's|.*/stable/\([0-9a-f]\{40\}\).*|\1|p' || true)"
LOCAL_COMMIT="$(cat /data/bin/code.commit 2>/dev/null || true)"

if [ ! -x "$CLI" ] || { [ -n "$REMOTE_COMMIT" ] && [ "$REMOTE_COMMIT" != "$LOCAL_COMMIT" ]; }; then
  echo "[opencode] telechargement du CLI VS Code (${ARCH})..."
  curl -fsSL "$CLI_URL" -o /tmp/vscode-cli.tgz
  tar -xzf /tmp/vscode-cli.tgz -C /data/bin
  chmod +x "$CLI"
  rm -f /tmp/vscode-cli.tgz
  if [ -n "$REMOTE_COMMIT" ]; then
    printf '%s\n' "$REMOTE_COMMIT" > /data/bin/code.commit
  fi
fi

# ---------------------------------------------------------------------------
# OpenCode (binaire linux-${ARCH}, version configurable)
# ---------------------------------------------------------------------------
OC_BIN=/data/bin/opencode
OC_VERSION="$OC_VERSION_OPT"
if [ "$OC_VERSION" = "latest" ]; then
  OC_VERSION="$(curl -fsSL https://api.github.com/repos/anomalyco/opencode/releases/latest \
    | jq -r '.tag_name // empty' | sed 's/^v//' || true)"
fi
if [ -z "$OC_VERSION" ]; then
  echo "[erreur] impossible de determiner la version d'OpenCode."
  exit 1
fi

INSTALLED_VERSION="$(cat /data/bin/opencode.version 2>/dev/null || true)"
if [ ! -x "$OC_BIN" ] || [ "$INSTALLED_VERSION" != "$OC_VERSION" ]; then
  echo "[opencode] telechargement d'OpenCode v${OC_VERSION} (linux-${ARCH})..."
  curl -fsSL "https://github.com/anomalyco/opencode/releases/download/v${OC_VERSION}/opencode-linux-${ARCH}.tar.gz" -o /tmp/opencode.tgz
  tar -xzf /tmp/opencode.tgz -C /data/bin
  chmod +x "$OC_BIN"
  rm -f /tmp/opencode.tgz
  printf '%s\n' "$OC_VERSION" > /data/bin/opencode.version
fi
ln -sf "$OC_BIN" /usr/local/bin/opencode

# ---------------------------------------------------------------------------
# Secrets cote client (jamais dans les reglages VS Code)
# ---------------------------------------------------------------------------
umask 077
PASSWORD_ESC="$(printf '%s' "$PASSWORD" | sed "s/'/'\\\\''/g")"
PUBLIC_URL_ESC="$(printf '%s' "$PUBLIC_URL" | sed "s/'/'\\\\''/g")"
cat > "$HOME/.opencode-client.env" <<EOF
OPENCODE_SERVER_USERNAME=opencode
OPENCODE_SERVER_PASSWORD='${PASSWORD_ESC}'
OPENCODE_PASSWORD='${PASSWORD_ESC}'
OPENCODE_PUBLIC_URL='${PUBLIC_URL_ESC}'
EOF
chmod 600 "$HOME/.opencode-client.env"

# Wrapper durci : force --server si absent (jamais de service fantome)
cat > /data/bin/opencode-client <<'EOF'
#!/bin/sh
. /data/home/.opencode-client.env
case " $* " in
  *" --server "*) exec /data/bin/opencode "$@" ;;
  *)              exec /data/bin/opencode --server http://127.0.0.1:4096 "$@" ;;
esac
EOF
chmod 700 /data/bin/opencode-client

# Helper de pairing : passe par l'API du serveur 4096 (pair ne sait pas cibler --server)
cat > /data/bin/opencode-pair <<'EOF'
#!/bin/sh
. /data/home/.opencode-client.env
URL="${OPENCODE_PUBLIC_URL:-}"
URL="${URL%/}"
if [ -z "$URL" ]; then
  echo "[erreur] renseigne l'option 'public_url' (ex. https://opencode.example.com)" >&2
  exit 1
fi
code=$(/data/bin/opencode api --server http://127.0.0.1:4096 post /api/pair | jq -r '.code // empty')
if [ -z "$code" ]; then
  echo "[erreur] impossible de generer un code de pairing" >&2
  exit 1
fi
link="$URL/auth/connect/$code"
echo ""
echo "Lien de pairing (valide 5 min, usage unique) :"
echo "  $link"
echo ""
if command -v qrencode >/dev/null 2>&1; then
  qrencode -t ANSIUTF8 "$link"
fi
EOF
chmod 700 /data/bin/opencode-pair
ln -sf /data/bin/opencode-client /usr/local/bin/opencode-client
ln -sf /data/bin/opencode-pair /usr/local/bin/opencode-pair

# ---------------------------------------------------------------------------
# MCP ha-mcp (jeton fourni par l'option, jamais affiche)
# Fusion ciblee : preserve default_agent / model / autres cles
# ---------------------------------------------------------------------------
CFG="$HOME/.config/opencode/opencode.json"
mkdir -p "$(dirname "$CFG")"
if [ -n "$MCP_URL" ]; then
  if [ ! -f "$CFG" ]; then
    echo '{}' > "$CFG"
  fi
  if jq -e . "$CFG" >/dev/null 2>&1; then
    if jq --arg u "$MCP_URL" \
        '.mcp.servers["ha-mcp"] = {type:"remote",url:$u,oauth:false,protocol:"auto"}' \
        "$CFG" > "$CFG.tmp"; then
      mv "$CFG.tmp" "$CFG"
      chmod 600 "$CFG"
      echo "[opencode] MCP ha-mcp configure"
    else
      rm -f "$CFG.tmp"
      echo "[erreur] echec de la fusion MCP (jq)."
    fi
  else
    echo "[erreur] $CFG n'est pas un JSON valide : MCP non configure."
  fi
else
  # Option vide : retirer une eventuelle configuration MCP obsolete
  if [ -f "$CFG" ] && jq -e . "$CFG" >/dev/null 2>&1; then
    if jq 'del(.mcp.servers["ha-mcp"])' "$CFG" > "$CFG.tmp"; then
      mv "$CFG.tmp" "$CFG"
      chmod 600 "$CFG"
      echo "[opencode] MCP ha-mcp retire (option vide)"
    else
      rm -f "$CFG.tmp"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Configuration OpenCode : agent et modele par defaut, permissions gerees
# Les regles gerees sont reecrites a chaque demarrage (l'option fait foi) ;
# les regles portant sur d'autres actions ou chemins sont conservees.
# ---------------------------------------------------------------------------
if [ -n "$DEFAULT_AGENT_OPT$DEFAULT_MODEL_OPT" ] \
   || [ "$HARDEN_DENY_SECRETS" = "true" ] \
   || [ "$HARDEN_ASK_CONFIG" = "true" ] \
   || [ "$HARDEN_ASK_SHELL" = "true" ]; then
  if [ ! -f "$CFG" ]; then
    echo '{}' > "$CFG"
  fi
  if jq -e . "$CFG" >/dev/null 2>&1; then
    if jq \
        --arg agent "$DEFAULT_AGENT_OPT" \
        --arg model "$DEFAULT_MODEL_OPT" \
        --argjson deny_secrets "$HARDEN_DENY_SECRETS" \
        --argjson ask_config "$HARDEN_ASK_CONFIG" \
        --argjson ask_shell "$HARDEN_ASK_SHELL" '
          def managed_rules:
            [ {action:"shell", resource:"*"},
              {action:"shell", resource:"*secrets.yaml*"},
              {action:"shell", resource:"*/.storage*"},
              {action:"edit",  resource:"/config/*"},
              {action:"edit",  resource:"/config/secrets.yaml"},
              {action:"edit",  resource:"/config/.storage/*"},
              {action:"edit",  resource:"/data/*"},
              {action:"read",  resource:"/config/secrets.yaml"} ];
          def is_managed($r):
            any(managed_rules[]; .action == $r.action and .resource == $r.resource);

          . as $cfg
          | ([ ($cfg.permissions // [])[] | select(is_managed(.) | not) ]
             + (if $ask_shell then [{action:"shell", resource:"*", effect:"ask"}] else [] end)
             + (if $ask_config then [{action:"edit", resource:"/config/*", effect:"ask"}] else [] end)
             + (if $deny_secrets then [
                  {action:"edit", resource:"/config/secrets.yaml", effect:"deny"},
                  {action:"edit", resource:"/config/.storage/*", effect:"deny"},
                  {action:"edit", resource:"/data/*", effect:"deny"},
                  {action:"read", resource:"/config/secrets.yaml", effect:"ask"},
                  {action:"shell", resource:"*secrets.yaml*", effect:"deny"},
                  {action:"shell", resource:"*/.storage*", effect:"deny"}
                ] else [] end)) as $rules
          | (if ($rules | length) > 0 then .permissions = $rules else del(.permissions) end)
          | (if $agent != "" then .default_agent = $agent else . end)
          | (if $model != "" then .model = $model else . end)
        ' "$CFG" > "$CFG.tmp"; then
      mv "$CFG.tmp" "$CFG"
      chmod 600 "$CFG"
      echo "[opencode] agent/modele et permissions mis a jour"
    else
      rm -f "$CFG.tmp"
      echo "[erreur] echec de la fusion agent/permissions (jq)."
    fi
  else
    echo "[erreur] $CFG n'est pas un JSON valide : agent/permissions non configurees."
  fi
fi

# ---------------------------------------------------------------------------
# AGENTS.md : modele seme uniquement s'il est absent (jamais ecrase)
# ---------------------------------------------------------------------------
if [ "$SEED_AGENTS_MD" = "true" ] && [ ! -f /share/opencode/AGENTS.md ]; then
  cat > /share/opencode/AGENTS.md <<'EOF'
# Regles du projet

- Lecture seule par defaut : demander avant toute modification.
- Ne jamais afficher, copier ou committer un secret, un jeton ou un mot de passe.
- Ne jamais editer `secrets.yaml` ni `.storage` a la main.
- Pour Home Assistant : charger `home-assistant-workflow` si present, puis
  `home-assistant-best-practices` (MCP) avant toute ecriture.
- Avant une modification : cible, changement, effet attendu, retour arriere ;
  attendre l'accord explicite.
- Apres une modification : verifier par une lecture ou un controle de sante.
- `/share/opencode` = espace de travail, `/config` = configuration Home Assistant,
  `/data` = etat prive de l'app.

Ce fichier est consultatif : les permissions OpenCode et le montage de `/config`
restent les seules barrieres appliquees par le runtime.
EOF
  chmod 644 /share/opencode/AGENTS.md
  echo "[opencode] AGENTS.md cree (modele par defaut)"
fi

# ---------------------------------------------------------------------------
# Reglages VS Code (machine) : extension -> serveur local, sans secret
# ---------------------------------------------------------------------------
MACHINE_SETTINGS="$HOME/.vscode-server/data/Machine/settings.json"
if [ ! -f "$MACHINE_SETTINGS" ]; then
  mkdir -p "$(dirname "$MACHINE_SETTINGS")"
  cat > "$MACHINE_SETTINGS" <<'EOF'
{
  "opencode.serverUrl": "http://127.0.0.1:4096",
  "opencode.command": "/data/bin/opencode-client",
  "remote.autoForwardPorts": false,
  "remote.otherPortsAttributes": {
    "onAutoForward": "ignore"
  }
}
EOF
fi

# ---------------------------------------------------------------------------
# Tunnel VS Code en tache de fond (relance automatique)
# ---------------------------------------------------------------------------
echo "[opencode] demarrage du tunnel: $TUNNEL_NAME"
(
  while true; do
    ARGS=(tunnel --name "$TUNNEL_NAME" --disable-telemetry)
    if [ "$ACCEPT" = "true" ]; then
      ARGS+=(--accept-server-license-terms)
    fi
    "$CLI" "${ARGS[@]}" || true
    sleep 5
  done
) &

# ---------------------------------------------------------------------------
# Serveur OpenCode : service managé (un seul serveur, decouvrable par le CLI)
# ---------------------------------------------------------------------------
cd /share/opencode

echo "[opencode] configuration du service OpenCode"
"$OC_BIN" service set hostname 0.0.0.0 || true
"$OC_BIN" service set port 4096 || true
"$OC_BIN" service set password "$PASSWORD" || true
"$OC_BIN" service set remote false || true

echo "[opencode] demarrage du service OpenCode"
"$OC_BIN" service start || true

# Laisse au service le temps de demarrer avant de verifier
sleep 3
code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:4096/api/info || true)
if [ -z "$code" ] || [ "$code" = "000" ]; then
  echo "[opencode] service manage indisponible : repli sur 'serve'"
  exec "$OC_BIN" serve --hostname 0.0.0.0 --port 4096
fi

# Miroir des logs du service vers le journal de l'app
LOG="$HOME/.local/share/opencode/log/opencode.log"
mkdir -p "$(dirname "$LOG")"
touch "$LOG"
tail -n +1 -F "$LOG" &

# Surveillance : relance le service si le port ne repond plus
while true; do
  sleep 30
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:4096/api/info || true)
  if [ -z "$code" ] || [ "$code" = "000" ]; then
    echo "[opencode] serveur injoignable, redemarrage du service"
    "$OC_BIN" service start || true
  fi
done
