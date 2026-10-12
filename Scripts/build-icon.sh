#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
SOURCE_IMAGE="${PROJECT_DIR}/Packaging/AppIcon.png"
OUTPUT_ICON="${PROJECT_DIR}/Packaging/AppIcon.icns"
ICON_WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/duoduo-icon.XXXXXX")
trap 'rm -rf "${ICON_WORK_DIR}"' EXIT
ICONSET_DIR="${ICON_WORK_DIR}/AppIcon.iconset"
mkdir -p "${ICONSET_DIR}"

for size in 16 32 128 256 512; do
    sips -z "${size}" "${size}" "${SOURCE_IMAGE}" \
        --out "${ICONSET_DIR}/icon_${size}x${size}.png" >/dev/null
    double_size=$((size * 2))
    sips -z "${double_size}" "${double_size}" "${SOURCE_IMAGE}" \
        --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "${ICONSET_DIR}" -o "${OUTPUT_ICON}"
sips -z 18 18 "${PROJECT_DIR}/Packaging/StatusIcon-source.png" \
    --out "${PROJECT_DIR}/Packaging/StatusIcon.png" >/dev/null
sips -z 36 36 "${PROJECT_DIR}/Packaging/StatusIcon-source.png" \
    --out "${PROJECT_DIR}/Packaging/StatusIcon@2x.png" >/dev/null
echo "Built ${OUTPUT_ICON}"
