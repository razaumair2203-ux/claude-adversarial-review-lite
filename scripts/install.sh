#!/usr/bin/env bash
set -euo pipefail
name=claude-adversarial-review-lite
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
skills_root=${CODEX_HOME:+$CODEX_HOME/skills}
skills_root=${skills_root:-$HOME/.codex/skills}
source_dir="$repo/skills/$name"
dest="$skills_root/$name"
[[ -f "$source_dir/SKILL.md" ]] || { echo "Incomplete checkout: SKILL.md not found." >&2; exit 1; }
rm -rf -- "$dest"
mkdir -p -- "$dest"
cp -R "$source_dir/." "$dest/"
printf 'Installed %s to %s\n' "$name" "$dest"

