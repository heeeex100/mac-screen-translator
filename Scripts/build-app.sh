#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
APP_NAME="MacScreenTranslator"
OUTPUT_DIR="${1:-${PROJECT_DIR}/dist}"
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

# Keep a stable signing identity so rebuilt apps can retain privacy permissions.
# Override this value when building with a different development/distribution identity.
CODESIGN_IDENTITY=${CODESIGN_IDENTITY:-"Apple Development: 1061004002@qq.com (UVH685N9HW)"}
if [[ "${CODESIGN_IDENTITY}" == "-" ]]; then
    echo "Ad-hoc signing cannot preserve a stable app identity. Set CODESIGN_IDENTITY to a certificate." >&2
    exit 1
fi
IDENTITIES=$(security find-identity -v -p codesigning)
if ! print -r -- "${IDENTITIES}" | grep -Fq -- "${CODESIGN_IDENTITY}"; then
    echo "Signing identity unavailable: ${CODESIGN_IDENTITY}" >&2
    echo "Install the certificate and private key, or set CODESIGN_IDENTITY to an available identity." >&2
    exit 1
fi

swift build -c release --package-path "${PROJECT_DIR}"
BIN_DIR=$(swift build -c release --package-path "${PROJECT_DIR}" --show-bin-path)

mkdir -p "${MACOS_DIR}"
cp "${BIN_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
cp "${PROJECT_DIR}/Packaging/Info.plist" "${CONTENTS_DIR}/Info.plist"
chmod 755 "${MACOS_DIR}/${APP_NAME}"

codesign --force --sign "${CODESIGN_IDENTITY}" "${APP_BUNDLE}"
codesign --verify --strict --verbose=2 "${APP_BUNDLE}"

echo "Built ${APP_BUNDLE}"
