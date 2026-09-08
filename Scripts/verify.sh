#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
cd "$project_dir"

swift format lint -r Sources Tests
swift test
app_path="$(Scripts/build-app.sh debug | tail -n 1)"
plutil -lint "$app_path/Contents/Info.plist"
test -f AppResources/AppIcon.svg
test -f AppResources/AppIcon.iconset/Contents.json
test -f AppResources/AppIcon.iconset/icon_16x16.png
test -f AppResources/AppIcon.iconset/icon_512x512@2x.png
test -f .agents/skills/haken-control/SKILL.md
test -f "$app_path/Contents/Resources/AppIcon.svg"
test -f "$app_path/Contents/Resources/Skills/haken-control/SKILL.md"
diff -rq .agents/skills/haken-control "$app_path/Contents/Resources/Skills/haken-control"
test -x "$app_path/Contents/MacOS/Haken"
test -x "$app_path/Contents/Helpers/haken"
codesign --verify --strict --verbose=2 "$app_path/Contents/Helpers/haken"
codesign --verify --deep --strict --verbose=2 "$app_path"
echo "Haken verification passed: $app_path"
