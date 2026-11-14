#!/usr/bin/env bash
set -euo pipefail

OPTIONS=/data/options.json
TUNNEL_NAME="$(jq -r '.tunnel_name // "rpi-opencode"' "$OPTIONS")"
ACCEPT="$(jq -r '.accept_license // false' "$OPTIONS")"
PASSWORD="$(jq -r '.opencode_password // ""' "$OPTIONS")"
PUBLIC_URL="$(jq -r '.public_url // "https://opencode.orcel.org"' "$OPTIONS")"
MCP_URL="$(jq -r '.ha_mcp_url // ""' "$OPTIONS")"

if [ -z "$PASSWORD" ]; then
  echo "[erreur] Renseigne 'opencode_password' dans la configuration de l'app, puis redemarre."
  exit 1
fi

export HOME=/data/home
export OPENCODE_PASSWORD="$PASSWORD"
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
mkdir -p "$HOME" /share/opencode /data/bin

# ---------------------------------------------------------------------------
# CLI VS Code (non embarque dans l'image : telecharge au premier demarrage)
# ---------------------------------------------------------------------------
CLI=/data/bin/code
if [ ! -x "$CLI" ]; then
  echo "[poc] telechargement du CLI VS Code (alpine-arm64)..."
  curl -fsSL "https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-arm64" -o /tmp/vscode-cli.tgz
  tar -xzf /tmp/vscode-cli.tgz -C /data/bin
  chmod +x "$CLI"
  rm -f /tmp/vscode-cli.tgz
fi

# ---------------------------------------------------------------------------
# OpenCode (binaire linux-arm64, version epinglee)
# ---------------------------------------------------------------------------
OC_BIN=/data/bin/opencode
OC_VERSION=2.3.0
if [ ! -x "$OC_BIN" ]; then
  echo "[poc] telechargement d'OpenCode v${OC_VERSION} (linux-arm64)..."
  curl -fsSL "https://github.com/anomalyco/opencode/releases/download/v${OC_VERSION}/opencode-linux-arm64.tar.gz" -o /tmp/opencode.tgz
  tar -xzf /tmp/opencode.tgz -C /data/bin
  chmod +x "$OC_BIN"
  rm -f /tmp/opencode.tgz
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
URL="${OPENCODE_PUBLIC_URL:-https://opencode.orcel.org}"
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
      echo "[poc] MCP ha-mcp configure"
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
      echo "[poc] MCP ha-mcp retire (option vide)"
    else
      rm -f "$CFG.tmp"
    fi
  fi
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
echo "[poc] demarrage du tunnel: $TUNNEL_NAME"
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

echo "[poc] configuration du service OpenCode"
"$OC_BIN" service set hostname 0.0.0.0 || true
"$OC_BIN" service set port 4096 || true
"$OC_BIN" service set password "$PASSWORD" || true
"$OC_BIN" service set remote false || true

echo "[poc] demarrage du service OpenCode"
"$OC_BIN" service start || true

# Laisse au service le temps de demarrer avant de verifier
sleep 3
code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:4096/api/info || true)
if [ -z "$code" ] || [ "$code" = "000" ]; then
  echo "[poc] service manage indisponible : repli sur 'serve'"
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
    echo "[poc] serveur injoignable, redemarrage du service"
    "$OC_BIN" service start || true
  fi
done
