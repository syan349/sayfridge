#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Match the Flutter/Dart version used for this project's local checks.
readonly flutter_version="3.44.8"
readonly flutter_revision="058e0af2c2b57e369d905a03ac9748b0ebf543c6"
api_base_url="${API_BASE_URL:-/api/v1}"

if [[ "$api_base_url" == "/api/v1" ]]; then
  echo "API_BASE_URL is not configured: deploying the interface only."
  echo "Set the HTTPS backend URL (ending in /api/v1) and rebuild to enable online features."
elif [[ ! "$api_base_url" =~ ^https://[^/?\#[:space:]]+/api/v1/?$ ]]; then
  echo "API_BASE_URL must be an HTTPS backend URL ending in /api/v1." >&2
  exit 1
fi

# Render's static-site build image does not bundle Flutter. Keep the SDK outside
# build/web so that neither its sources nor its tools become public site files.
sdk_directory="$(mktemp -d "${TMPDIR:-/tmp}/sayfridge-flutter.XXXXXXXX")"
git clone --depth 1 --branch "$flutter_version" \
  https://github.com/flutter/flutter.git "$sdk_directory"

if [[ "$(git -C "$sdk_directory" rev-parse HEAD)" != "$flutter_revision" ]]; then
  echo "The Flutter checkout does not match the expected revision." >&2
  exit 1
fi

export PATH="$sdk_directory/bin:$PATH"
export CI=true
flutter --suppress-analytics --version
flutter --suppress-analytics precache --web
flutter --suppress-analytics pub get --enforce-lockfile
flutter --suppress-analytics build web --release --no-pub \
  --no-web-resources-cdn --no-wasm-dry-run \
  --target lib/main.dart --dart-define="API_BASE_URL=$api_base_url"

test -f build/web/index.html
echo "Flutter Web build ready: build/web"
