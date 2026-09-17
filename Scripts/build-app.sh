#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
APP_NAME="MacScreenTranslator"
OUTPUT_DIR="${1:-${PROJECT_DIR}/dist}"
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

swift build -c release --package-path "${PROJECT_DIR}"
BIN_DIR=$(swift build -c release --package-path "${PROJECT_DIR}" --show-bin-path)

mkdir -p "${MACOS_DIR}"
cp "${BIN_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
cp "${PROJECT_DIR}/Packaging/Info.plist" "${CONTENTS_DIR}/Info.plist"
chmod 755 "${MACOS_DIR}/${APP_NAME}"

# Ad-hoc signing is sufficient for local use. Set CODESIGN_IDENTITY to use
# an Apple Development or Developer ID certificate instead.
CODESIGN_IDENTITY=${CODESIGN_IDENTITY:--}
codesign --force --deep --sign "${CODESIGN_IDENTITY}" "${APP_BUNDLE}"

echo "Built ${APP_BUNDLE}"
