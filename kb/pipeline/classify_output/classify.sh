#!/usr/bin/env bash
# Classe une transcription et son original en arborescence miroir :
#   tmp_output/<nom>/*   -> docs/refs/for_agents/<nom>/ (version agents)
#   <original d'inbox/>  -> docs/refs/for_human/<nom>/ (version humains)
# usage : classify.sh <nom> <original> [original...]
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
name="${1:?usage : classify.sh <nom> <original...>}"; shift
[ $# -ge 1 ] || { echo "usage : classify.sh <nom> <original...>" >&2; exit 1; }

src="$root/tmp_output/$name"
dest="$root/docs/refs/for_agents/$name"
human="$root/docs/refs/for_human/$name"
[ -d "$src" ] || { echo "introuvable : $src" >&2; exit 1; }
[ -e "$dest" ] && { echo "existe déjà : $dest" >&2; exit 1; }

mkdir -p "$(dirname "$dest")" "$human"
mv "$src" "$dest"
rmdir "$root/tmp_output" 2>/dev/null || true

for orig in "$@"; do
  base="$(basename "$orig")"
  mv "$orig" "$human/$base"
  rm -f "$orig:Zone.Identifier"
  # les références « inbox/<fichier> » des transcriptions pointent désormais vers le miroir humain
  find "$dest" -name '*.md' -exec sed -i "s|inbox/$base|../../for_human/$name/$base|g" {} +
done

echo "agents  : $dest"
echo "humains : $human"
