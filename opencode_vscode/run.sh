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
INSTALL_OC_EXT="$(jq -r 'if .install_opencode_extension == false then "false" else "true" end' "$OPTIONS")"
ASSIST_AGENT="$(jq -r 'if .assist_agent_enabled == false then "false" else "true" end' "$OPTIONS")"
# Chemins sensibles propres a l'installation (fichiers de secrets d'autres
# add-ons, par exemple) : refuses en lecture et en ecriture. Seuls les chemins
# absolus sont acceptes ; les autres sont signales et ignores.
EXTRA_DENY_PATHS="$(jq -c '[ (.hardening_deny_paths // [])[] | select(type == "string" and startswith("/")) ]' "$OPTIONS")"
EXTRA_DENY_DROPPED="$(jq -c '[ (.hardening_deny_paths // [])[] | select(type != "string" or (startswith("/") | not)) ]' "$OPTIONS")"

if [ -z "$PASSWORD" ]; then
  echo "[erreur] Renseigne 'opencode_password' dans la configuration de l'app, puis redemarre."
  exit 1
fi

# Un mot de passe partage protege une API qui peut lire /config et piloter
# Home Assistant : refuser les valeurs courtes plutot que de les tolerer.
MIN_PASSWORD_LENGTH=16
if [ "${#PASSWORD}" -lt "$MIN_PASSWORD_LENGTH" ]; then
  echo "[erreur] 'opencode_password' doit comporter au moins ${MIN_PASSWORD_LENGTH} caracteres (${#PASSWORD} actuellement)."
  exit 1
fi

export HOME=/data/home
# Pas d'export de OPENCODE_PASSWORD : l'environnement de run.sh est herite par le
# service puis par le shell des outils, ou la variable serait lisible. Le client
# interne et `opencode-pair` lisent ~/.opencode-client.env, le serveur lit
# service.json : rien ne depend de cet export.
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
mkdir -p "$HOME" /share/opencode /data/bin

# Marqueur de version : distingue l'image reellement installee du depot, et
# evite d'affirmer « je suis en X » en lisant config.yaml alors que l'app tourne
# sur une version anterieure. Alimente scripts/etat.sh.
if [ -r /app.version ]; then
  cp /app.version "$HOME/.app-version" 2>/dev/null || true
fi

# Architecture (binaires telecharges au premier demarrage)
case "$(uname -m)" in
  aarch64|arm64) ARCH=arm64 ;;
  x86_64|amd64)  ARCH=x64 ;;
  *) echo "[erreur] architecture non supportee : $(uname -m)"; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Verification d'integrite des binaires telecharges
# 0 = somme verifiee, 1 = ecart OU somme absente (installation refusee)
# ---------------------------------------------------------------------------
verify_sha256() {
  local file="$1" expected="$2" label="$3" actual
  if [ -z "$expected" ]; then
    echo "[erreur] $label : aucune somme SHA256 publiee, installation refusee."
    return 1
  fi
  actual="$(sha256sum "$file" | awk '{print $1}')"
  if [ "$actual" != "$expected" ]; then
    echo "[erreur] $label : SHA256 inattendu (attendu ${expected}, obtenu ${actual})."
    return 1
  fi
  echo "[opencode] $label : SHA256 verifie."
  return 0
}

# ---------------------------------------------------------------------------
# CLI VS Code (non embarque dans l'image ; rafraichi si le commit change)
# L'API de mise a jour publie le commit ET la somme SHA256 de l'archive :
# on s'en sert pour decider du rafraichissement et pour verifier le fichier.
# ---------------------------------------------------------------------------
CLI=/data/bin/code
CLI_META_URL="https://update.code.visualstudio.com/api/update/cli-alpine-${ARCH}/stable/latest"
CLI_META="$(curl -fsSL --max-time 20 "$CLI_META_URL" 2>/dev/null || true)"
REMOTE_COMMIT="$(printf '%s' "$CLI_META" | jq -r '.version // empty' 2>/dev/null || true)"
CLI_SHA="$(printf '%s' "$CLI_META" | jq -r '.sha256hash // empty' 2>/dev/null || true)"
CLI_URL="$(printf '%s' "$CLI_META" | jq -r '.url // empty' 2>/dev/null || true)"
if [ -z "$CLI_URL" ]; then
  # Plus de repli sans somme : l'API de mise a jour est la seule source qui
  # publie le SHA256, et une archive non verifiable n'est plus acceptee.
  if [ -x "$CLI" ]; then
    echo "[avertissement] metadonnees du CLI VS Code indisponibles : on conserve la version installee."
  else
    echo "[erreur] CLI VS Code introuvable et metadonnees indisponibles : arret."
    exit 1
  fi
fi
LOCAL_COMMIT="$(cat /data/bin/code.commit 2>/dev/null || true)"

if [ -n "$CLI_URL" ] && { [ ! -x "$CLI" ] || { [ -n "$REMOTE_COMMIT" ] && [ "$REMOTE_COMMIT" != "$LOCAL_COMMIT" ]; }; }; then
  echo "[opencode] telechargement du CLI VS Code (${ARCH})..."
  if [ -z "$CLI_SHA" ]; then
    if [ -x "$CLI" ]; then
      echo "[avertissement] aucune somme publiee pour le CLI VS Code : mise a jour ignoree."
    else
      echo "[erreur] aucune somme publiee pour le CLI VS Code : installation refusee."
      exit 1
    fi
  elif curl -fsSL --max-time 300 "$CLI_URL" -o /tmp/vscode-cli.tgz; then
    rc=0
    verify_sha256 /tmp/vscode-cli.tgz "$CLI_SHA" "CLI VS Code" || rc=$?
    if [ "$rc" -eq 1 ]; then
      rm -f /tmp/vscode-cli.tgz
      if [ -x "$CLI" ]; then
        echo "[avertissement] archive rejetee : on conserve le CLI installe."
      else
        echo "[erreur] archive du CLI VS Code rejetee (somme incorrecte) : arret."
        exit 1
      fi
    else
      tar -xzf /tmp/vscode-cli.tgz -C /data/bin
      chmod +x "$CLI"
      rm -f /tmp/vscode-cli.tgz
      if [ -n "$REMOTE_COMMIT" ]; then
        printf '%s\n' "$REMOTE_COMMIT" > /data/bin/code.commit
      fi
    fi
  else
    rm -f /tmp/vscode-cli.tgz
    if [ -x "$CLI" ]; then
      echo "[avertissement] telechargement du CLI VS Code echoue : on conserve la version installee."
    else
      echo "[erreur] CLI VS Code indisponible : arret."
      exit 1
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Extension VS Code OpenCode V2 (installee si absente, jamais imposee)
# ---------------------------------------------------------------------------
if [ "$INSTALL_OC_EXT" = "true" ]; then
  EXT_DIR="$HOME/.vscode-server/extensions"
  if ! compgen -G "$EXT_DIR/opencode-v2-maker.opencode-v2-vscode-*" >/dev/null; then
    echo "[opencode] installation de l'extension VS Code OpenCode V2..."
    if ! timeout 90 "$CLI" --install-extension opencode-v2-maker.opencode-v2-vscode --force >/dev/null 2>&1; then
      echo "[avertissement] extension OpenCode non installee (marketplace indisponible ?)"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# OpenCode (binaire linux-${ARCH}, version configurable)
# ---------------------------------------------------------------------------
OC_BIN=/data/bin/opencode
OC_VERSION="$OC_VERSION_OPT"
OC_API="https://api.github.com/repos/anomalyco/opencode/releases"
RELEASE_JSON=""
if [ "$OC_VERSION" = "latest" ]; then
  RELEASE_JSON="$(curl -fsSL --max-time 20 "$OC_API/latest" 2>/dev/null || true)"
  OC_VERSION="$(printf '%s' "$RELEASE_JSON" | jq -r '.tag_name // empty' 2>/dev/null | sed 's/^v//' || true)"
fi
if [ -z "$OC_VERSION" ]; then
  echo "[erreur] impossible de determiner la version d'OpenCode."
  exit 1
fi

INSTALLED_VERSION="$(cat /data/bin/opencode.version 2>/dev/null || true)"
if [ ! -x "$OC_BIN" ] || [ "$INSTALLED_VERSION" != "$OC_VERSION" ]; then
  echo "[opencode] telechargement d'OpenCode v${OC_VERSION} (linux-${ARCH})..."
  OC_ASSET="opencode-linux-${ARCH}.tar.gz"
  # GitHub publie un digest sha256 par asset de release : on compare.
  if [ -z "$RELEASE_JSON" ]; then
    RELEASE_JSON="$(curl -fsSL --max-time 20 "$OC_API/tags/v${OC_VERSION}" 2>/dev/null || true)"
  fi
  OC_SHA="$(printf '%s' "$RELEASE_JSON" | jq -r --arg n "$OC_ASSET" \
    '.assets[]? | select(.name == $n) | .digest // empty' 2>/dev/null | sed 's/^sha256://' || true)"
  if [ -z "$OC_SHA" ]; then
    if [ -x "$OC_BIN" ]; then
      echo "[avertissement] aucune somme publiee pour OpenCode ${OC_VERSION} : mise a jour ignoree."
    else
      echo "[erreur] aucune somme publiee pour OpenCode ${OC_VERSION} : installation refusee."
      exit 1
    fi
  elif curl -fsSL --max-time 300 \
      "https://github.com/anomalyco/opencode/releases/download/v${OC_VERSION}/${OC_ASSET}" \
      -o /tmp/opencode.tgz; then
    rc=0
    verify_sha256 /tmp/opencode.tgz "$OC_SHA" "OpenCode ${OC_VERSION}" || rc=$?
    if [ "$rc" -eq 1 ]; then
      rm -f /tmp/opencode.tgz
      if [ -x "$OC_BIN" ]; then
        echo "[avertissement] archive rejetee : on conserve OpenCode installe."
      else
        echo "[erreur] archive d'OpenCode rejetee (somme incorrecte) : arret."
        exit 1
      fi
    else
      tar -xzf /tmp/opencode.tgz -C /data/bin
      chmod +x "$OC_BIN"
      rm -f /tmp/opencode.tgz
      printf '%s\n' "$OC_VERSION" > /data/bin/opencode.version
    fi
  else
    rm -f /tmp/opencode.tgz
    if [ -x "$OC_BIN" ]; then
      echo "[avertissement] telechargement d'OpenCode echoue : on conserve la version installee."
    else
      echo "[erreur] OpenCode indisponible : arret."
      exit 1
    fi
  fi
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

# Memoire des chemins refuses au demarrage precedent : sans elle, retirer un
# chemin de l'option laisserait ses regles en place indefiniment.
EXTRA_STATE="$HOME/.config/opencode/.ha-opencode-extra-paths.json"
if [ -f "$EXTRA_STATE" ] && jq -e . "$EXTRA_STATE" >/dev/null 2>&1; then
  EXTRA_DENY_PREVIOUS="$(jq -c '[ .[] | select(type == "string") ]' "$EXTRA_STATE")"
else
  EXTRA_DENY_PREVIOUS='[]'
fi
EXTRA_COUNT="$(printf '%s' "$EXTRA_DENY_PATHS" | jq 'length')"
PREV_COUNT="$(printf '%s' "$EXTRA_DENY_PREVIOUS" | jq 'length')"
DROPPED_COUNT="$(printf '%s' "$EXTRA_DENY_DROPPED" | jq 'length')"
if [ "$DROPPED_COUNT" -gt 0 ]; then
  echo "[avertissement] 'hardening_deny_paths' ignore ${DROPPED_COUNT} entree(s) non absolue(s) : $(printf '%s' "$EXTRA_DENY_DROPPED" | jq -r 'join(", ")')"
fi

# Un JSON invalide ne doit pas etre ignore : demarrer sans les regles gerees
# reviendrait a desactiver le durcissement en silence. On conserve l'original
# puis on repart d'une base vide, que les blocs suivants reecrivent.
ensure_valid_config() {
  if [ ! -f "$CFG" ]; then
    echo '{}' > "$CFG"
    return 0
  fi
  if jq -e . "$CFG" >/dev/null 2>&1; then
    return 0
  fi
  local backup
  backup="$CFG.invalide.$(date +%Y%m%d-%H%M%S)"
  mv "$CFG" "$backup"
  echo '{}' > "$CFG"
  echo "[avertissement] $CFG n'etait pas un JSON valide : conserve dans $backup, configuration reinitialisee."
}
ensure_valid_config

# L'URL contient le jeton : on valide sa forme sans jamais l'afficher, et une
# valeur invalide est traitee comme absente (la cle MCP obsolete est retiree).
if [ -n "$MCP_URL" ]; then
  case "$MCP_URL" in
    http://*|https://*) ;;
    *)
      echo "[erreur] 'ha_mcp_url' doit commencer par http:// ou https:// (valeur non affichee) : MCP non configure."
      MCP_URL=""
      ;;
  esac
fi

if [ -n "$MCP_URL" ]; then
  # Le jeton passe par un fichier 600 plutot que par la ligne de commande de
  # jq, ou /proc/<pid>/cmdline le rendrait visible.
  MCP_URL_FILE="$(mktemp)"
  printf '%s' "$MCP_URL" > "$MCP_URL_FILE"
  if jq --rawfile u "$MCP_URL_FILE" \
      '.mcp.servers["ha-mcp"] = {type:"remote",url:$u,oauth:false,protocol:"auto"}' \
      "$CFG" > "$CFG.tmp"; then
    mv "$CFG.tmp" "$CFG"
    chmod 600 "$CFG"
    echo "[opencode] MCP ha-mcp configure"
  else
    rm -f "$CFG.tmp"
    echo "[erreur] echec de la fusion MCP (jq)."
  fi
  rm -f "$MCP_URL_FILE"
else
  # Option vide (ou invalide) : retirer une eventuelle configuration obsolete
  if jq 'del(.mcp.servers["ha-mcp"])' "$CFG" > "$CFG.tmp"; then
    mv "$CFG.tmp" "$CFG"
    chmod 600 "$CFG"
    echo "[opencode] MCP ha-mcp retire (option vide)"
  else
    rm -f "$CFG.tmp"
  fi
fi

# ---------------------------------------------------------------------------
# Configuration OpenCode : agent et modele par defaut, permissions et policies
# gerees. Les regles gerees sont reecrites a chaque demarrage (l'option fait
# foi) ; les regles portant sur d'autres actions ou chemins sont conservees.
#
# Deux niveaux, volontairement :
#   permissions -> `ask` / `deny`, surchargeables (config de projet, agent) ;
#   policies    -> `deny` uniquement, evalue apres tout le reste et jamais
#                  surchargeable. C'est la couche qui tient face a un
#                  opencode.json de projet ecrit par l'agent lui-meme.
# ---------------------------------------------------------------------------
if [ -n "$DEFAULT_AGENT_OPT$DEFAULT_MODEL_OPT" ] \
   || [ "$HARDEN_DENY_SECRETS" = "true" ] \
   || [ "$HARDEN_ASK_CONFIG" = "true" ] \
   || [ "$HARDEN_ASK_SHELL" = "true" ] \
   || [ "$EXTRA_COUNT" -gt 0 ] \
   || [ "$PREV_COUNT" -gt 0 ] \
   || [ "$ASSIST_AGENT" = "true" ] \
   || { [ -f "$CFG" ] && jq -e '.agents.assist' "$CFG" >/dev/null 2>&1; }; then
  if jq \
      --arg agent "$DEFAULT_AGENT_OPT" \
      --arg model "$DEFAULT_MODEL_OPT" \
      --argjson deny_secrets "$HARDEN_DENY_SECRETS" \
      --argjson ask_config "$HARDEN_ASK_CONFIG" \
      --argjson ask_shell "$HARDEN_ASK_SHELL" \
      --argjson extra_paths "$EXTRA_DENY_PATHS" \
      --argjson previous_paths "$EXTRA_DENY_PREVIOUS" \
      --argjson assist "$ASSIST_AGENT" \
      --slurpfile assistfile /etc/assist-agent.json '
        def items($v): ($v // []) | if type == "array" then .[] else empty end;
        def managed_rules:
          [ {action:"shell", resource:"*"},
            {action:"shell", resource:"*secrets.yaml*"},
            {action:"shell", resource:"*/.storage*"},
            {action:"shell", resource:"*/.config/opencode/*"},
            {action:"shell", resource:"*/.local/share/opencode/*"},
            {action:"shell", resource:"*/.vscode/cli/*"},
            {action:"shell", resource:"*/.copilot/*"},
            {action:"shell", resource:"*/.git-credentials*"},
            {action:"shell", resource:"*/.opencode-client.env*"},
            {action:"shell", resource:"*/.bash_history*"},
            {action:"shell", resource:"*/data/options.json*"},
            {action:"edit",  resource:"/config/*"},
            {action:"edit",  resource:"/config/secrets.yaml"},
            {action:"edit",  resource:"/config/.storage/*"},
            {action:"edit",  resource:"/data/*"},
            {action:"read",  resource:"/config/secrets.yaml"},
            {action:"read",  resource:"/config/.storage/*"},
            {action:"read",  resource:"/data/*"},
            {action:"read",  resource:"/data/home/.opencode/plan/*"},
            {action:"read",  resource:"/share/opencode/opencode.json"},
            {action:"edit",  resource:"/share/opencode/opencode.json"},
            {action:"read",  resource:"/share/opencode/opencode.jsonc"},
            {action:"edit",  resource:"/share/opencode/opencode.jsonc"},
            {action:"read",  resource:"/share/opencode/.opencode/*"},
            {action:"edit",  resource:"/share/opencode/.opencode/*"},
            {action:"shell", resource:"*/share/opencode/opencode.json*"},
            {action:"shell", resource:"*/share/opencode/.opencode/*"},
            # Forme relative : pour une session ouverte DANS /share/opencode, la
            # ressource de fichier interne est relative a la Location. Sans ces
            # regles, les denies en absolu ci-dessus ne s appliquent pas (0.9.1).
            {action:"read",  resource:"opencode.json"},
            {action:"edit",  resource:"opencode.json"},
            {action:"read",  resource:"opencode.jsonc"},
            {action:"edit",  resource:"opencode.jsonc"},
            {action:"read",  resource:".opencode/*"},
            {action:"edit",  resource:".opencode/*"},
            {action:"shell", resource:"*opencode.json*"},
            {action:"shell", resource:"*.opencode*"},
            {action:"shell", resource:"*/share/opencode/.opencode/*"},
            # Motif 0.9.1, conserve pour le nettoyage uniquement : le prune le
            # supprime et il n est plus emis (le motif sans slash le couvre).
            {action:"shell", resource:"*.opencode/*"} ];
        def is_managed($r):
          any(managed_rules[]; .action == $r.action and .resource == $r.resource);

        def managed_policies:
          [ {action:"tool.use", resource:"read:/config/secrets.yaml"},
            {action:"tool.use", resource:"edit:/config/secrets.yaml"},
            {action:"tool.use", resource:"read:/config/.storage/*"},
            {action:"tool.use", resource:"edit:/config/.storage/*"},
            {action:"tool.use", resource:"read:/data/options.json"},
            {action:"tool.use", resource:"edit:/data/options.json"},
            {action:"tool.use", resource:"read:/data/home/.config/opencode/*"},
            {action:"tool.use", resource:"edit:/data/home/.config/opencode/*"},
            {action:"tool.use", resource:"read:/data/home/.local/share/opencode/*"},
            {action:"tool.use", resource:"edit:/data/home/.local/share/opencode/*"},
            {action:"tool.use", resource:"read:/data/home/.vscode/cli/*"},
            {action:"tool.use", resource:"edit:/data/home/.vscode/cli/*"},
            {action:"tool.use", resource:"read:/data/home/.copilot/*"},
            {action:"tool.use", resource:"edit:/data/home/.copilot/*"},
            {action:"tool.use", resource:"read:/data/home/.git-credentials"},
            {action:"tool.use", resource:"edit:/data/home/.git-credentials"},
            {action:"tool.use", resource:"read:/data/home/.opencode-client.env"},
            {action:"tool.use", resource:"edit:/data/home/.opencode-client.env"},
            {action:"tool.use", resource:"read:/data/home/.bash_history"},
            {action:"tool.use", resource:"edit:/data/home/.bash_history"},
            {action:"tool.use", resource:"shell:*secrets.yaml*"},
            {action:"tool.use", resource:"shell:*/.storage*"},
            {action:"tool.use", resource:"shell:*/.config/opencode/*"},
            {action:"tool.use", resource:"shell:*/.local/share/opencode/*"},
            {action:"tool.use", resource:"shell:*/.vscode/cli/*"},
            {action:"tool.use", resource:"shell:*/.copilot/*"},
            {action:"tool.use", resource:"shell:*/.git-credentials*"},
            {action:"tool.use", resource:"shell:*/.opencode-client.env*"},
            {action:"tool.use", resource:"shell:*/.bash_history*"},
            {action:"tool.use", resource:"shell:*/data/options.json*"},
            {action:"tool.use", resource:"read:/share/opencode/opencode.json"},
            {action:"tool.use", resource:"edit:/share/opencode/opencode.json"},
            {action:"tool.use", resource:"read:/share/opencode/opencode.jsonc"},
            {action:"tool.use", resource:"edit:/share/opencode/opencode.jsonc"},
            {action:"tool.use", resource:"shell:*/share/opencode/opencode.json*"},
            {action:"tool.use", resource:"read:/share/opencode/.opencode/*"},
            {action:"tool.use", resource:"edit:/share/opencode/.opencode/*"},
            {action:"tool.use", resource:"shell:*/share/opencode/.opencode/*"},
            {action:"tool.use", resource:"read:opencode.json"},
            {action:"tool.use", resource:"edit:opencode.json"},
            {action:"tool.use", resource:"read:opencode.jsonc"},
            {action:"tool.use", resource:"edit:opencode.jsonc"},
            {action:"tool.use", resource:"read:.opencode/*"},
            {action:"tool.use", resource:"edit:.opencode/*"},
            {action:"tool.use", resource:"shell:*opencode.json*"},
            {action:"tool.use", resource:"shell:*.opencode*"},
            {action:"tool.use", resource:"grep:*"} ];
        def legacy_policies:
          [ {action:"tool.use", resource:"shell:*.opencode/*"},
            {action:"tool.use", resource:"shell:*/share/opencode/.opencode/*"} ];
        def is_managed_policy($p):
          any(managed_policies[]; .action == $p.action and .resource == $p.resource);

        # Chemins ajoutes via hardening_deny_paths
        def extra_perms($paths):
          [ $paths[] as $p
            | {action:"read", resource:$p, effect:"deny"},
              {action:"edit", resource:$p, effect:"deny"} ];
        def extra_policies($paths):
          [ $paths[] as $p
            | {action:"tool.use", resource:("read:" + $p), effect:"deny"},
              {action:"tool.use", resource:("edit:" + $p), effect:"deny"},
              {action:"tool.use", resource:("shell:*" + $p + "*"), effect:"deny"} ];
        def in_list($r; $list):
          any($list[]; .action == $r.action and .resource == $r.resource);

        . as $cfg
        | ([ items($cfg.permissions)
             | select((is_managed(.) or in_list(.; extra_perms($previous_paths))) | not) ]
           + (if $ask_shell then [{action:"shell", resource:"*", effect:"ask"}] else [] end)
           + (if $ask_config then [{action:"edit", resource:"/config/*", effect:"ask"}] else [] end)
           + (if $deny_secrets then [
                {action:"edit", resource:"/config/secrets.yaml", effect:"deny"},
                {action:"edit", resource:"/config/.storage/*", effect:"deny"},
                {action:"edit", resource:"/data/*", effect:"deny"},
                {action:"read", resource:"/config/secrets.yaml", effect:"deny"},
                {action:"read", resource:"/config/.storage/*", effect:"deny"},
                {action:"read", resource:"/data/*", effect:"deny"},
                {action:"read", resource:"/data/home/.opencode/plan/*", effect:"allow"},
                {action:"shell", resource:"*secrets.yaml*", effect:"deny"},
                {action:"shell", resource:"*/.storage*", effect:"deny"},
                {action:"shell", resource:"*/.config/opencode/*", effect:"deny"},
                {action:"shell", resource:"*/.local/share/opencode/*", effect:"deny"},
                {action:"shell", resource:"*/.vscode/cli/*", effect:"deny"},
                {action:"shell", resource:"*/.copilot/*", effect:"deny"},
                {action:"shell", resource:"*/.git-credentials*", effect:"deny"},
                {action:"shell", resource:"*/.opencode-client.env*", effect:"deny"},
                {action:"shell", resource:"*/.bash_history*", effect:"deny"},
                {action:"shell", resource:"*/data/options.json*", effect:"deny"},
                {action:"read", resource:"/share/opencode/opencode.json", effect:"deny"},
                {action:"edit", resource:"/share/opencode/opencode.json", effect:"deny"},
                {action:"read", resource:"/share/opencode/opencode.jsonc", effect:"deny"},
                {action:"edit", resource:"/share/opencode/opencode.jsonc", effect:"deny"},
                {action:"shell", resource:"*/share/opencode/opencode.json*", effect:"deny"},
                {action:"read", resource:"/share/opencode/.opencode/*", effect:"deny"},
                {action:"edit", resource:"/share/opencode/.opencode/*", effect:"deny"},
                {action:"shell", resource:"*/share/opencode/.opencode/*", effect:"deny"},
                {action:"read", resource:"opencode.json", effect:"deny"},
                {action:"edit", resource:"opencode.json", effect:"deny"},
                {action:"read", resource:"opencode.jsonc", effect:"deny"},
                {action:"edit", resource:"opencode.jsonc", effect:"deny"},
                {action:"read", resource:".opencode/*", effect:"deny"},
                {action:"edit", resource:".opencode/*", effect:"deny"},
                {action:"shell", resource:"*opencode.json*", effect:"deny"},
                {action:"shell", resource:"*.opencode*", effect:"deny"}
              ] else [] end)
           + extra_perms($extra_paths)) as $rules
        | ([ items($cfg.policies)
             | select((is_managed_policy(.) or in_list(.; legacy_policies) or in_list(.; extra_policies($previous_paths))) | not) ]
           + (if $deny_secrets then [ managed_policies[] | .effect = "deny" ] else [] end)
           + extra_policies($extra_paths)) as $pol
        | (if ($rules | length) > 0 then .permissions = $rules else del(.permissions) end)
        | (if ($pol | length) > 0 then .policies = $pol else del(.policies) end)
        | (if $agent != "" then .default_agent = $agent else . end)
        | (if $model != "" then .model = $model else . end)
        | (if $assist and ($assistfile | length) > 0 then
             .agents.assist = ($assistfile[0] | if $model != "" then .model = $model else . end)
           else del(.agents.assist) end)
        | (if (.agents // {}) == {} then del(.agents) else . end)
      ' "$CFG" > "$CFG.tmp"; then
      mv "$CFG.tmp" "$CFG"
      chmod 600 "$CFG"
      echo "[opencode] agent/modele, permissions et policies mis a jour"
      # Memoire des chemins appliques, pour pouvoir les retirer proprement.
      if [ "$EXTRA_COUNT" -gt 0 ]; then
        printf '%s' "$EXTRA_DENY_PATHS" > "$EXTRA_STATE"
        chmod 600 "$EXTRA_STATE"
        echo "[opencode] ${EXTRA_COUNT} chemin(s) supplementaire(s) refuse(s)"
      else
        rm -f "$EXTRA_STATE"
      fi
    else
      rm -f "$CFG.tmp"
      echo "[erreur] echec de la fusion agent/permissions (jq) : arret pour ne pas demarrer sans regles."
      exit 1
    fi
fi

# ---------------------------------------------------------------------------
# AGENTS.md : modele seme uniquement s'il est absent (jamais ecrase)
# ---------------------------------------------------------------------------
if [ "$SEED_AGENTS_MD" = "true" ] && [ ! -f /share/opencode/AGENTS.md ]; then
  cat > /share/opencode/AGENTS.md <<'EOF'
# Regles du projet

## Avant d'agir

- L'etat du projet se lit dans `PLAN-ADDON.md` (§1 fait, §5 a faire) : ne jamais
  affirmer un etat sans l'avoir lu.
- Toute action sur un secret se lit dans `ROTATION-SECRETS.md` (§2 inventaire,
  §3 fiches) avant d'etre entreprise.
- Une version ne se bump qu'avec sa section `CHANGELOG` : le job `release` en
  tire ses notes et la CI compare la premiere section au `version` des apps.
- Le `CHANGELOG.md` racine de `ha-opencode` est la source ; les deux copies se
  mettent a jour par copie, jamais a la main.
- Une decision structurante se note dans `PLAN-ADDON.md` §2.x le jour meme.
- `scripts/etat.sh` donne l'instantane (version installee vs depot, coherence
  des CHANGELOG, compteurs de regles).

## Regles

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

Ce fichier est consultatif : les permissions OpenCode, les policies et le
montage de `/config` restent les seules barrieres appliquees par le runtime.
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
# service.json est écrit directement : passer le mot de passe en argument au
# CLI le ferait journaliser en clair dans opencode.log.
SVC="$HOME/.config/opencode/service.json"
mkdir -p "$(dirname "$SVC")"
if [ -f "$SVC" ] && jq -e . "$SVC" >/dev/null 2>&1; then
  SVC_BASE="$(cat "$SVC")"
else
  SVC_BASE='{}'
fi
# Le mot de passe passe par un fichier 600 plutot que par la ligne de commande
# de jq, ou /proc/<pid>/cmdline le rendrait visible le temps de l'appel.
PASSWORD_FILE="$(mktemp)"
printf '%s' "$PASSWORD" > "$PASSWORD_FILE"
if printf '%s' "$SVC_BASE" | jq --rawfile p "$PASSWORD_FILE" \
     '.hostname = "0.0.0.0" | .port = 4096 | .password = $p' > "$SVC.tmp"; then
  mv "$SVC.tmp" "$SVC"
  chmod 600 "$SVC"
else
  rm -f "$SVC.tmp"
  echo "[erreur] impossible d'écrire $SVC : mot de passe non configuré."
  rm -f "$PASSWORD_FILE"
  exit 1
fi
rm -f "$PASSWORD_FILE"

# ---------------------------------------------------------------------------
# Journal du service : expurgation a la source, puis miroir filtre
# L'historique est nettoye au demarrage, et le flux continu est filtre avant
# d'arriver au journal de l'app (visible par tout administrateur HA).
# ---------------------------------------------------------------------------
LOG="$HOME/.local/share/opencode/log/opencode.log"
mkdir -p "$(dirname "$LOG")"

escape_sed() {
  local value
  value="$(printf '%s' "$1" | sed 's/[][\\.*^$/&]/\\&/g')"
  printf '%s' "${value//$'\n'/\\n}"
}

REDACT_SCRIPT="$(mktemp)"
{
  printf '%s\n' 's/args="\[[^]]*password[^]]*\]"/args="[redacted]"/g'
  if [ -n "$PASSWORD" ]; then
    printf 's/%s/[redacted]/g\n' "$(escape_sed "$PASSWORD")"
  fi
  if [ -n "$MCP_URL" ]; then
    printf 's/%s/[redacted]/g\n' "$(escape_sed "$MCP_URL")"
  fi
} > "$REDACT_SCRIPT"
chmod 600 "$REDACT_SCRIPT"

if [ -f "$LOG" ]; then
  sed -i -f "$REDACT_SCRIPT" "$LOG" || true
fi

echo "[opencode] demarrage du service OpenCode"
if ! "$OC_BIN" service start; then
  echo "[avertissement] 'service start' a echoue : on tente le demarrage direct."
fi

# Le service peut mettre plus de trois secondes sur un Pi : sonder jusqu'a
# 30 s avant de conclure, sinon le repli 'serve' tente de binder le meme port
# qu'un service simplement lent.
attempt=0
ready=""
while [ "$attempt" -lt 30 ]; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 http://127.0.0.1:4096/api/info || true)
  if [ -n "$code" ] && [ "$code" != "000" ]; then
    ready=1
    break
  fi
  attempt=$((attempt + 1))
  sleep 1
done
if [ -z "$ready" ]; then
  echo "[opencode] service manage indisponible apres 30 s : repli sur 'serve'"
  exec "$OC_BIN" serve --hostname 0.0.0.0 --port 4096
fi

# Miroir des logs du service vers le journal de l'app, filtre en continu.
# -n 0 : seules les nouvelles lignes, sinon chaque demarrage rejoue tout
# l'historique de opencode.log dans le journal de l'app.
touch "$LOG"
tail -n 0 -F "$LOG" | sed -u -f "$REDACT_SCRIPT" &
# sed a lu le script au demarrage : on supprime le fichier pour ne pas laisser
# le mot de passe sur disque.
sleep 1
rm -f "$REDACT_SCRIPT"

# Surveillance : relance le service si le port ne repond plus
while true; do
  sleep 30
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:4096/api/info || true)
  if [ -z "$code" ] || [ "$code" = "000" ]; then
    echo "[opencode] serveur injoignable, redemarrage du service"
    "$OC_BIN" service start || true
  fi
done
