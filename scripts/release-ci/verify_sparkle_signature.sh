#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  verify_sparkle_signature.sh --zip MiaoYan_Vx.y.z.zip --signature SIGNATURE [--public-key SUPublicEDKey]

Verifies a Sparkle Ed25519 signature against the ZIP bytes and the app's
embedded SUPublicEDKey. If --public-key is omitted, the key is read from the
MiaoYan.app inside the ZIP.
EOF
}

die() {
  echo "$1" >&2
  exit 1
}

ZIP_PATH=""
SIGNATURE=""
PUBLIC_KEY=""
APP_NAME="${APP_NAME:-MiaoYan}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --zip)
      ZIP_PATH="${2:-}"
      shift 2
      ;;
    --signature)
      SIGNATURE="${2:-}"
      shift 2
      ;;
    --public-key)
      PUBLIC_KEY="${2:-}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$ZIP_PATH" ]] || die "--zip is required."
[[ -f "$ZIP_PATH" ]] || die "ZIP not found: $ZIP_PATH"
[[ -n "$SIGNATURE" ]] || die "--signature is required."

SIGNATURE="${SIGNATURE#sparkle:edSignature=}"
SIGNATURE="${SIGNATURE#\"}"
SIGNATURE="${SIGNATURE%\"}"

TEMP_DIR=""
cleanup() {
  [[ -z "$TEMP_DIR" ]] || rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

if [[ -z "$PUBLIC_KEY" ]]; then
  TEMP_DIR="$(mktemp -d)"
  /usr/bin/ditto -x -k "$ZIP_PATH" "$TEMP_DIR"
  APP_PATH="$(find "$TEMP_DIR" -name "${APP_NAME}.app" -type d -print -quit)"
  [[ -n "$APP_PATH" ]] || die "${APP_NAME}.app not found inside ZIP."
  INFO_PLIST="$APP_PATH/Contents/Info.plist"
  [[ -f "$INFO_PLIST" ]] || die "Info.plist not found inside app bundle."
  PUBLIC_KEY="$(plutil -extract SUPublicEDKey raw -o - "$INFO_PLIST")"
fi

[[ -n "$PUBLIC_KEY" ]] || die "SUPublicEDKey is empty."

/usr/bin/swift - "$ZIP_PATH" "$SIGNATURE" "$PUBLIC_KEY" <<'SWIFT'
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 4 else {
    fail("Expected ZIP path, signature, and public key.")
}

let zipURL = URL(fileURLWithPath: CommandLine.arguments[1])
let signatureString = CommandLine.arguments[2]
let publicKeyString = CommandLine.arguments[3]

guard let signature = Data(base64Encoded: signatureString) else {
    fail("Sparkle signature is not valid base64.")
}

guard let publicKeyData = Data(base64Encoded: publicKeyString) else {
    fail("SUPublicEDKey is not valid base64.")
}

do {
    let archive = try Data(contentsOf: zipURL)
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)

    guard publicKey.isValidSignature(signature, for: archive) else {
        fail("Sparkle signature does not match ZIP bytes and SUPublicEDKey.")
    }

    print("Sparkle signature verified for \(zipURL.lastPathComponent).")
} catch {
    fail("Sparkle signature verification failed: \(error.localizedDescription)")
}
SWIFT
