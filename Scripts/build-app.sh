#!/bin/zsh
set -euo pipefail

mode="${1:-debug}"
if [[ "$mode" != "debug" && "$mode" != "release" ]]; then
  echo "Usage: Scripts/build-app.sh [debug|release]" >&2
  exit 64
fi

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
cd "$project_dir"

swift build -c "$mode"
binary_path="$(swift build -c "$mode" --show-bin-path)/Haken"
app_path="$project_dir/.build/app/Haken.app"
contents="$app_path/Contents"

rm -rf "$app_path"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$binary_path" "$contents/MacOS/Haken"
cp AppResources/Info.plist "$contents/Info.plist"
cp AppResources/AppIcon.svg "$contents/Resources/AppIcon.svg"
cp -R AppResources/AppIcon.iconset "$contents/Resources/AppIcon.iconset"

identity="${HAKEN_CODE_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -n 1 || true)"
fi
if [[ -n "$identity" ]]; then
  echo "Signing with Apple Development certificate."
  codesign --force --options runtime --sign "$identity" "$app_path"
else
  echo "warning: Apple Development certificate unavailable; using ad-hoc signing. Accessibility permission may need to be granted again after rebuilds." >&2
  codesign --force --sign - "$app_path"
fi

echo "$app_path"
