#!/usr/bin/env bash
#
# release.sh — Bump the LaTraceMapSDK version constant, commit, and tag.
#
# Usage:
#   ./scripts/release.sh X.Y.Z
#
# Behavior:
#   - Validates semver (X.Y.Z, digits only).
#   - Requires a clean working tree.
#   - Requires the current branch to be 'main' (override: RELEASE_ALLOW_NON_MAIN=1).
#   - Rewrites the `version` constant in Sources/LaTraceMapSDK/LaTraceMapSDK.swift.
#   - Commits the change with a release message.
#   - Creates an annotated tag vX.Y.Z.
#   - Does NOT push. Prints the two push commands for manual execution.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

VERSION_FILE="Sources/LaTraceMapSDK/LaTraceMapSDK.swift"

err() {
  echo "error: $*" >&2
  exit 1
}

# 1. Argument check + semver validation
if [ "$#" -ne 1 ]; then
  err "usage: $0 X.Y.Z"
fi

NEW_VERSION="$1"

if ! [[ "${NEW_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  err "invalid semver '${NEW_VERSION}'. Expected format: X.Y.Z (digits only, e.g. 0.1.0)."
fi

# 2. Working tree must be clean
if ! git diff --quiet || ! git diff --cached --quiet; then
  err "working tree is dirty. Commit or stash your changes before releasing."
fi

# 3. Must be on main (unless overridden)
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "${CURRENT_BRANCH}" != "main" ]; then
  if [ "${RELEASE_ALLOW_NON_MAIN:-0}" != "1" ]; then
    err "current branch is '${CURRENT_BRANCH}', expected 'main'. Set RELEASE_ALLOW_NON_MAIN=1 to override."
  else
    echo "warning: releasing from '${CURRENT_BRANCH}' (RELEASE_ALLOW_NON_MAIN=1)."
  fi
fi

# 4. Tag must not already exist
TAG="v${NEW_VERSION}"
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  err "tag '${TAG}' already exists."
fi

# 5. Version file must exist
if [ ! -f "${VERSION_FILE}" ]; then
  err "version file not found: ${VERSION_FILE}"
fi

# 6. Rewrite the version constant (Linux + macOS compatible sed)
SED_EXPR='s|\(public static let version = \)"[^"]*"|\1"'"${NEW_VERSION}"'"|'

if [ "$(uname)" = "Darwin" ]; then
  sed -i '' "${SED_EXPR}" "${VERSION_FILE}"
else
  sed -i "${SED_EXPR}" "${VERSION_FILE}"
fi

# 7. Confirm the replacement happened
if ! grep -q "public static let version = \"${NEW_VERSION}\"" "${VERSION_FILE}"; then
  err "failed to update version constant in ${VERSION_FILE}. Manual fix required."
fi

echo "Updated ${VERSION_FILE} -> version ${NEW_VERSION}"

# 8. Commit
git add "${VERSION_FILE}"
git commit -m "$(cat <<EOF
release: v${NEW_VERSION}

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"

# 9. Tag
git tag -a "${TAG}" -m "Release ${TAG}"

# 10. Final report — do not push
echo
echo "Release ${TAG} prepared locally."
echo
echo "Next steps (run manually):"
echo "  git push origin main"
echo "  git push origin ${TAG}"
echo
