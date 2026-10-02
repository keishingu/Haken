#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd "${script_directory}/.." && pwd)"
output_directory="${project_directory}/build/release"
app_path="${output_directory}/Haken.app"
disk_image_path="${output_directory}/Haken-macos-universal.dmg"
signing_identity="${SIGNING_IDENTITY:-}"

if [[ "${signing_identity}" != "Developer ID Application:"* ]]; then
  echo "error: SIGNING_IDENTITY must be a Developer ID Application identity" >&2
  exit 64
fi

if [[ ! -d "${app_path}" ]]; then
  echo "error: app to package was not found: ${app_path}" >&2
  exit 1
fi
developer_id_signed() {
  local signature_details
  signature_details="$(codesign --display --verbose=4 "$1" 2>&1)" || return 1
  [[ "${signature_details}" == *'Authority=Developer ID Application:'* ]]
}

for executable in "${app_path}/Contents/Helpers/haken" "${app_path}/Contents/MacOS/Haken"; do
  if [[ ! -x "${executable}" ]]; then
    echo "error: required executable is missing: ${executable}" >&2
    exit 1
  fi
  codesign --verify --strict --verbose=2 "${executable}"
  if ! developer_id_signed "${executable}"; then
    echo "error: executable is not signed with Developer ID: ${executable}" >&2
    exit 1
  fi
done
codesign --verify --deep --strict --verbose=2 "${app_path}"
if ! developer_id_signed "${app_path}"; then
  echo "error: app is not signed with Developer ID: ${app_path}" >&2
  exit 1
fi

staging_directory="$(mktemp -d "${output_directory}/dmg-staging.XXXXXX")"
verification_mount="$(mktemp -d "${output_directory}/dmg-verification.XXXXXX")"
cleanup() {
  hdiutil detach "${verification_mount}" >/dev/null 2>&1 || true
  rmdir "${verification_mount}" >/dev/null 2>&1 || true
  rm -rf "${staging_directory}"
}
trap cleanup EXIT
cp -R "${app_path}" "${staging_directory}/Haken.app"
ln -s /Applications "${staging_directory}/Applications"
if [[ -e "${disk_image_path}" ]]; then
  echo "error: disk image already exists: ${disk_image_path}" >&2
  exit 73
fi
hdiutil create -volname Haken -srcfolder "${staging_directory}" \
  -format UDZO -ov "${disk_image_path}"
hdiutil attach -nobrowse -readonly -mountpoint "${verification_mount}" "${disk_image_path}" >/dev/null
codesign --verify --deep --strict --verbose=2 "${verification_mount}/Haken.app"
codesign --verify --strict --verbose=2 "${verification_mount}/Haken.app/Contents/Helpers/haken"
codesign --verify --strict --verbose=2 "${verification_mount}/Haken.app/Contents/MacOS/Haken"
hdiutil detach "${verification_mount}" >/dev/null
rmdir "${verification_mount}"
codesign --force --sign "${signing_identity}" \
  --timestamp --verbose "${disk_image_path}"
codesign --verify --verbose=2 "${disk_image_path}"
hdiutil verify "${disk_image_path}"
echo "Packaged ${disk_image_path}"
