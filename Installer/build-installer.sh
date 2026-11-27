#!/bin/bash
# Builds dist/EMU3Editor-<version>.pkg (current user only, no administrator password), which installs
#   ~/Applications/Rhyno Audio/EMU3Editor.app
#   ~/Library/Application Support/EMU3 Editor/Add Ons/Emu_Imager.app   (listed in the editor's Tools menu)
# Emu_Imager is built from its own project, next to this one. IMAGER_DIR=<folder> says where else it is;
# IMAGER_DIR=none builds the installer without it.
# The installer first moves every other installed copy of these apps to the Trash (see remove-old-installs.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="Applications/Rhyno Audio"
APP_ID="com.rhynoaudio.emu3editor"
ID="com.rhynoaudio.emu3editor.app"
IMAGER_ID="net.rhyno-audio.emuimager.addon"
IMAGER_APP_ID="net-rhyno-audio.emuimager"
IMAGER_DIR="${IMAGER_DIR:-$PWD/../Emu_Imager}"
if [ "$IMAGER_DIR" != none ] && [ ! -x "$IMAGER_DIR/Installer/build-installer.sh" ]; then
  echo "Emu_Imager not found in $IMAGER_DIR. Set IMAGER_DIR to its folder, or IMAGER_DIR=none to build without it." >&2
  exit 1
fi
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

[ -d EMU3Editor.xcodeproj ] || xcodegen generate
xcodebuild -project EMU3Editor.xcodeproj -scheme EMU3Editor -configuration Release -derivedDataPath "$W/dd" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO -quiet build
APP="$W/dd/Build/Products/Release/EMU3Editor.app"
codesign --verify --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")

mkdir -p "$W/root" "$W/res" "$W/scripts" dist
ditto "$APP" "$W/root/EMU3Editor.app"
pkgbuild --analyze --root "$W/root" "$W/components.plist" >/dev/null
# Not relocatable: the installer must not update some other copy of the app it finds.
# Not version checked: the old copy is removed first, so reinstalling an older version must still copy the app.
for key in BundleIsRelocatable BundleIsVersionChecked; do
  /usr/libexec/PlistBuddy -c "Add :0:$key bool false" "$W/components.plist" 2>/dev/null ||
    /usr/libexec/PlistBuddy -c "Set :0:$key false" "$W/components.plist"
done
ALSO=""; [ "$IMAGER_DIR" = none ] || ALSO="$IMAGER_APP_ID"
sed -e "s/@BUNDLE_ID@/$APP_ID/" -e "s/@OLD_RECEIPTS@//" -e "s/@ALSO_CHECK@/$ALSO/" Installer/preinstall >"$W/scripts/preinstall"
cp Installer/remove-old-installs.sh "$W/scripts/"
chmod +x "$W/scripts/"*
pkgbuild --root "$W/root" --component-plist "$W/components.plist" --identifier "$ID" --version "$VERSION" \
  --scripts "$W/scripts" \
  --install-location "/$DEST" "$W/component.pkg" >/dev/null

IMAGER_REFS=""; IMAGER_CHOICE=""; IMAGER_TEXT=""
if [ "$IMAGER_DIR" != none ]; then
  "$IMAGER_DIR/Installer/build-installer.sh" component "$W/imager.pkg"
  pkgutil --expand "$W/imager.pkg" "$W/imager"
  IMAGER_VERSION=$(xmllint --xpath 'string(/pkg-info/@version)' "$W/imager/PackageInfo")
  IMAGER_CHOICE="<pkg-ref id=\"$IMAGER_ID\"/>"
  IMAGER_REFS="<pkg-ref id=\"$IMAGER_ID\" version=\"$IMAGER_VERSION\">imager.pkg</pkg-ref>
  <pkg-ref id=\"$IMAGER_ID\"><must-close><app id=\"$IMAGER_APP_ID\"/></must-close></pkg-ref>"
  IMAGER_TEXT="
Emu_Imager $IMAGER_VERSION is included. It prepares disk images and SD cards; open it from the editor's Tools menu.
It is installed in ~/Library/Application Support/EMU3 Editor/Add Ons.
"
fi

cp LICENSE "$W/res/LICENSE.txt"
cat > "$W/res/welcome.txt" <<TXT
EMU3 Editor $VERSION

Edits the banks, presets and samples of E-mu EOS samplers. Work in progress: keep copies of your banks and disk images.

It is installed for your user account only, in
~/$DEST
$IMAGER_TEXT
To remove an app, move it from its folder to the Trash.

Before installing, the installer looks for other copies of the apps it installs in /Applications, your own
Applications folder and the Add Ons folder, including renamed copies and zip files of an app, and moves them
to the Trash. Your banks, backups and settings are not touched. Quit the apps first.
TXT
cat > "$W/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>EMU3 Editor</title>
  <welcome file="welcome.txt" mime-type="text/plain"/>
  <license file="LICENSE.txt" mime-type="text/plain"/>
  <domains enable_anywhere="false" enable_currentUserHome="true" enable_localSystem="false"/>
  <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
  <volume-check><allowed-os-versions><os-version min="12.0"/></allowed-os-versions></volume-check>
  <choices-outline><line choice="app"/></choices-outline>
  <choice id="app" title="EMU3 Editor"><pkg-ref id="$ID"/>$IMAGER_CHOICE</choice>
  <pkg-ref id="$ID" version="$VERSION">component.pkg</pkg-ref>
  <pkg-ref id="$ID"><must-close><app id="$APP_ID"/></must-close></pkg-ref>
  $IMAGER_REFS
</installer-gui-script>
XML
OUT="dist/EMU3Editor-$VERSION.pkg"
productbuild --distribution "$W/distribution.xml" --resources "$W/res" --package-path "$W" "$OUT" >/dev/null
echo "Built $PWD/$OUT"
