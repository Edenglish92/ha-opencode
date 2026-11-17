#!/usr/bin/env bash
# Deploy the OpenCode Assist custom component into Home Assistant.
# Run inside the OpenCode app container, which has /config mounted read-write.
set -euo pipefail

SRC="${SRC:-/share/ha-opencode/integrations/opencode_assist}"
DST="${DST:-/config/custom_components/opencode_assist}"

usage() {
  cat <<'EOF'
Usage: install-assist.sh [install|--check|--uninstall]

  install       copy the component into /config/custom_components/opencode_assist
  --check       compare the installed copy with the repository source
  --uninstall   remove the installed component

Override SRC / DST with environment variables if needed.
After install or uninstall, restart Home Assistant before using or removing the
integration.
EOF
}

case "${1:-install}" in
  install|--install)
    if [ ! -d "$SRC" ]; then
      echo "[erreur] source introuvable : $SRC" >&2
      exit 1
    fi
    if [ ! -d /config/custom_components ]; then
      echo "[erreur] /config/custom_components est absent : lancer ce script dans l'app OpenCode (profil rw)." >&2
      exit 1
    fi
    mkdir -p "$DST"
    cp -a "$SRC/." "$DST/"
    rm -rf "$DST/__pycache__"
    echo "[ok] composant installé dans $DST"
    echo "[suite] redémarrer Home Assistant, puis ajouter l'intégration « OpenCode Assist »."
    ;;
  --check)
    if [ ! -d "$DST" ]; then
      echo "[etat] non installé : $DST"
      exit 1
    fi
    if diff -r --exclude='__pycache__' "$SRC" "$DST"; then
      echo "[ok] la copie installée est identique à la source."
    else
      echo "[etat] des différences existent entre $SRC et $DST." >&2
      exit 1
    fi
    ;;
  --uninstall)
    rm -rf "$DST"
    echo "[ok] composant supprimé : $DST"
    echo "[suite] redémarrer Home Assistant ; l'entrée d'intégration peut être supprimée dans l'UI."
    ;;
  --help|-h)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
