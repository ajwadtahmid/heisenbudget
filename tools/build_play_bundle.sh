#!/usr/bin/env bash
# Builds the Play Store upload: a release app bundle, obfuscated, with the debug
# symbols kept apart. Run it from anywhere:  tools/build_play_bundle.sh
#
# The bundle is only the upload (about 64 MB). Play hands each phone just its
# own CPU's code, so people download about 22 MB.
#
# Keep build/symbols/<version> for every release you publish: without it, crash
# reports from the Play Console cannot be read back into Dart names.
#
# After the build it reads the merged release manifest (the app's plus every
# plugin's) and fails if it asks for the INTERNET permission: the offline
# promise is checked on what is actually shipped, not only on our own manifest.
#
# iOS: build the same way on a Mac and keep the symbols too:
#   flutter build ipa --release --obfuscate --split-debug-info=build/symbols/<version>
set -euo pipefail

cd "$(dirname "$0")/.."

version=$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -n1 | tr '+' '-')
if [ -z "$version" ]; then
  echo "Could not read the version from pubspec.yaml" >&2
  exit 1
fi
symbols="build/symbols/$version"

if [ ! -f android/key.properties ]; then
  echo "Warning: android/key.properties is missing, so this bundle is signed with" >&2
  echo "the debug key and Play will refuse it. Set up release signing first." >&2
fi

mkdir -p "$symbols"
flutter build appbundle --release --obfuscate --split-debug-info="$symbols"

manifest=$(find build/app/intermediates/merged_manifests/release -name AndroidManifest.xml 2>/dev/null | head -n1)
if [ -z "$manifest" ]; then
  echo "Could not find the merged release manifest to check. Do not upload this bundle." >&2
  exit 1
fi
if grep -q 'android.permission.INTERNET' "$manifest"; then
  echo "The merged release manifest asks for the INTERNET permission ($manifest)." >&2
  echo "Heisenbudget is offline: find the plugin that adds it. Do not upload this bundle." >&2
  exit 1
fi
echo "Manifest check: no INTERNET permission ($manifest)"

bundle=build/app/outputs/bundle/release/app-release.aab
echo
echo "Upload:  $bundle ($(du -h "$bundle" | cut -f1))"
echo "Keep:    $symbols"
