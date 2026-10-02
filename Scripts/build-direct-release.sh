#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd "${script_directory}/.." && pwd)"
output_directory="${project_directory}/build/release"
app_path="${output_directory}/Haken.app"
build_number="${BUILD_NUMBER:-}"
signing_identity="${SIGNING_IDENTITY:-}"
marketing_version="${MARKETING_VERSION:-}"

if [[ ! "${build_number}" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: BUILD_NUMBER must be a positive integer" >&2
  exit 64
fi
if [[ ! "${marketing_version}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "error: MARKETING_VERSION must use numeric dot notation (for example 1.2.3)" >&2
  exit 64
fi
if [[ "${signing_identity}" != "Developer ID Application:"* ]]; then
  echo "error: SIGNING_IDENTITY must be a Developer ID Application identity" >&2
  exit 64
fi

if [[ -e "${output_directory}" ]]; then
  echo "error: output directory already exists: ${output_directory}" >&2
  exit 73
fi
mkdir -p "${app_path}/Contents/MacOS" "${app_path}/Contents/Helpers" "${app_path}/Contents/Resources"

build_architecture() {
  local architecture="$1"
  local triple="${architecture}-apple-macosx15.0"
  local scratch_path="${output_directory}/${architecture}"

  swift build --package-path "${project_directory}" --configuration release \
    --scratch-path "${scratch_path}" --triple "${triple}" --product Haken >&2
  swift build --package-path "${project_directory}" --configuration release \
    --scratch-path "${scratch_path}" --triple "${triple}" --product haken-cli >&2
  local bin_path
  bin_path="$(swift build --package-path "${project_directory}" --configuration release \
    --scratch-path "${scratch_path}" --triple "${triple}" --show-bin-path)"
  printf '%s\n' "${bin_path}"
}

arm64_bin="$(build_architecture arm64)"
x86_64_bin="$(build_architecture x86_64)"

lipo -create "${arm64_bin}/Haken" "${x86_64_bin}/Haken" -output "${app_path}/Contents/MacOS/Haken"
lipo -create "${arm64_bin}/haken-cli" "${x86_64_bin}/haken-cli" -output "${app_path}/Contents/Helpers/haken"
cp "${project_directory}/AppResources/Info.plist" "${app_path}/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "${marketing_version}" "${app_path}/Contents/Info.plist"
plutil -replace CFBundleVersion -string "${build_number}" "${app_path}/Contents/Info.plist"
cp "${project_directory}/AppResources/AppIcon.svg" "${app_path}/Contents/Resources/AppIcon.svg"
cp -R "${project_directory}/AppResources/AppIcon.iconset" "${app_path}/Contents/Resources/AppIcon.iconset"
iconutil -c icns "${project_directory}/AppResources/AppIcon.iconset" \
  -o "${app_path}/Contents/Resources/AppIcon.icns"
mkdir -p "${app_path}/Contents/Resources/Skills"
cp -R "${project_directory}/.agents/skills/haken-control" \
  "${app_path}/Contents/Resources/Skills/haken-control"

for executable in "${app_path}/Contents/Helpers/haken" "${app_path}/Contents/MacOS/Haken"; do
  architectures="$(lipo -archs "${executable}")"
  if [[ " ${architectures} " != *" arm64 "* || " ${architectures} " != *" x86_64 "* ]]; then
    echo "error: ${executable} is not Universal: ${architectures}" >&2
    exit 1
  fi
done

# Sign nested code first so the app bundle seals the already-signed CLI.
codesign --force --sign "${signing_identity}" --identifier com.haken.app.haken \
  --options runtime --timestamp --verbose "${app_path}/Contents/Helpers/haken"
codesign --force --sign "${signing_identity}" --identifier com.haken.app \
  --options runtime --timestamp --verbose "${app_path}"
codesign --verify --strict --verbose=2 "${app_path}/Contents/Helpers/haken"
codesign --verify --deep --strict --verbose=2 "${app_path}"
codesign --display --verbose=4 "${app_path}"

"${script_directory}/package-direct-release.sh"
echo "Created ${output_directory}/Haken-macos-universal.dmg"
