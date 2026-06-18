---
name: release
description: Prepare, validate, and publish a MiaoYan direct-download GitHub Release. Not for App Store builds.
version: 1.4.0
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Edit
disable-model-invocation: true
---

# MiaoYan Release Workflow

Use this skill only when the maintainer explicitly asks for a GitHub Release.

## Version Rules

- Release tags use uppercase `Vx.y.z`.
- `MARKETING_VERSION` in `MiaoYan.xcodeproj/project.pbxproj` must match the tag without the leading `V`.
- `CURRENT_PROJECT_VERSION` must equal `MARKETING_VERSION`. Sparkle compares `sparkle:version` in appcast.xml against the app's `CFBundleVersion` (which maps to `CURRENT_PROJECT_VERSION`). If they diverge, users get an infinite update prompt loop (see V3.5.1 incident, #524).
- Release notes should be prepared before tagging.
- Signing, notarization, and Sparkle credentials are maintainer-managed. Do not commit credential paths, private key filenames, passwords, or secret values.
- Sparkle signing must use the MiaoYan release key. Do not rely on the default Sparkle Keychain account because it may belong to another app.

## Preflight

```bash
git diff --quiet && git diff --cached --quiet
grep "MARKETING_VERSION" MiaoYan.xcodeproj/project.pbxproj | head -1
grep "CURRENT_PROJECT_VERSION" MiaoYan.xcodeproj/project.pbxproj | head -1
gh release list --limit 10
gh run list --limit 10
```

Stop if:
- The working tree is dirty.
- The version is unclear.
- `CURRENT_PROJECT_VERSION` does not equal `MARKETING_VERSION` (hard stop, fix before proceeding).
- The intended tag already exists and recovery has not been discussed.

## Build And Publish

Use the repository's release scripts for the actual build, packaging, signing, notarization, and appcast update. The tracked workflows currently maintain sponsor assets only; do not assume a `release.yml` workflow exists.

When a local release script is required, confirm these before running it:

- Required signing identities are available on the maintainer machine.
- Required secrets are available through the intended channel.
- The generated DMG, ZIP, and Sparkle metadata point to the same version.
- The ZIP used by the appcast is the file that was signed for Sparkle.

## Verification

```bash
gh release view Vx.y.z
gh run list --limit 5
```

After publication, confirm that the release assets exist, the appcast points at the intended ZIP, and the Sparkle signature metadata matches the published ZIP.
Use `scripts/release-ci/verify_sparkle_signature.sh --zip <zip> --signature <signature>` to verify the appcast signature against the ZIP bytes and the app's embedded `SUPublicEDKey` before pushing appcast changes.

## Safety Rules

- Never tag, upload assets, update appcast, or publish a release without explicit maintainer confirmation.
- Never commit local credential paths or secret filenames.
- If notarization or signing fails, report the exact failure and stop before changing credentials.
