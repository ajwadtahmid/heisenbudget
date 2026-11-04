# Local picker cache containment

Source: android_file_picker 2.1.2 from pub.dev; upstream LICENSE retained.
PickerPaths.cachedFile validates canonical directory identities for the app cache,
file_picker root, stamped pick directory and file parent. This rejects sibling
prefixes, traversal between picks, nested display names and symlink escapes.
Pure JVM tests exercise these boundaries and retain normal filename coverage.
No provider-level device exploit is claimed; native provider/device checks remain
necessary. The workspace-resolution setting is removed for the local package and
trailing whitespace normalized. Keep this patch until upstream containment is equivalent.
The existing fixed diagnostic uses debugPrint rather than print to satisfy host lint rules; no exception payload is logged.
No new plugin or permission is introduced.
