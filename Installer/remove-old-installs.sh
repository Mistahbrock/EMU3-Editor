#!/bin/bash
# Moves earlier installs of one app to the Trash:
#   - every app bundle with its bundle identifier in the given folders, renamed copies included
#   - zip files in those folders that hold nothing but such an app
# Apps are recognised by identifier, never by name alone. Nothing is removed while one of the copies is running.
#
# usage: remove-old-installs.sh [--list | --check] <bundle-id> <home> <folder>...
#   --list    only print what would be removed
#   --check   only fail if one of the copies is running
MODE=remove; case "${1:-}" in --list) MODE=list; shift ;; --check) MODE=check; shift ;; esac
ID="${1:-}"; H="${2:-}"
[ -n "$ID" ] && [ -d "$H" ] && [ "$H" != "/" ] || { echo "remove-old-installs: bad arguments" >&2; exit 2; }
shift 2

T=$(mktemp -d) || exit 1; trap 'rm -rf "$T"' EXIT
bundle_id() { /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1" 2>/dev/null; }

apps=(); zips=()
for folder in "$@"; do
  [ -d "$folder" ] || continue
  while IFS= read -r -d '' plist; do
    app=${plist%/Contents/Info.plist}
    case "$app" in */Contents/*) continue ;; esac          # part of another app: leave it
    [ "$(bundle_id "$plist")" = "$ID" ] && apps+=("$app")
  done < <(find "$folder" -maxdepth 5 -type f -path '*/Contents/Info.plist' -print0 2>/dev/null)

  while IFS= read -r -d '' zip; do
    case "$zip" in */Contents/*) continue ;; esac
    names=$(unzip -Z1 "$zip" 2>/dev/null) || continue
    plist=$(grep -E '^[^/]+\.app/Contents/Info\.plist$' <<<"$names")
    [ -n "$plist" ] && [ "$(wc -l <<<"$plist")" -eq 1 ] || continue
    # only the app (and macOS's own __MACOSX entries) may be inside
    TOP="${plist%%/*}/" awk 'index($0, ENVIRON["TOP"]) != 1 && index($0, "__MACOSX/") != 1 { other = 1 } END { exit other }' <<<"$names" || continue
    unzip -p "$zip" "$plist" >"$T/Info.plist" 2>/dev/null || continue
    [ "$(bundle_id "$T/Info.plist")" = "$ID" ] && zips+=("$zip")
  done < <(find "$folder" -maxdepth 3 -type f -iname '*.zip' -print0 2>/dev/null)
done

found=("${apps[@]+"${apps[@]}"}" "${zips[@]+"${zips[@]}"}")
if [ "$MODE" = list ]; then
  for item in "${found[@]}"; do [ -n "$item" ] && echo "$item"; done
  exit 0
fi

for app in "${apps[@]+"${apps[@]}"}"; do
  if ps -axo comm= | EXE="$app/Contents/MacOS/" awk 'index($0, ENVIRON["EXE"]) == 1 { run = 1 } END { exit !run }'; then
    echo "$app is running. Quit it and run the installer again. Nothing was removed." >&2
    exit 1
  fi
done
[ "$MODE" = check ] && exit 0

STAMP=$(date +%Y%m%d-%H%M%S)
for item in "${found[@]}"; do
  [ -n "$item" ] || continue
  name=$(basename "$item"); stem=${name%.*}; ext=${name##*.}
  dest="$H/.Trash/$stem (old install $STAMP).$ext"; n=1
  while [ -e "$dest" ]; do n=$((n + 1)); dest="$H/.Trash/$stem (old install $STAMP $n).$ext"; done
  mkdir -p "$H/.Trash" 2>/dev/null
  if mv "$item" "$dest"; then echo "Moved to Trash: $item"; else echo "Could not remove: $item" >&2; fi
done
exit 0
