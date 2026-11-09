---
paths:
  - "MiaoYanTests/**"
  - "Packages/MiaoYanCore/Tests/**"
  - "scripts/add_tests_target.rb"
---

# Unit tests

Unit tests live under `MiaoYanTests/`. Coverage targets pure-logic surfaces
(`ImageLinkParser`, `WikilinkIndex.updateNote`, `String+`, etc.). UI flows are
verified by manual smoke after build, not by XCUITest.

Add a new test:

1. Create `MiaoYanTests/<Subject>Tests.swift` (XCTest, `@MainActor` on the
   test methods if they touch `@MainActor`-isolated types; `setUp()` overrides
   cannot be `@MainActor`, construct isolated objects inside the tests).
2. Register the file manually at the same 4 pbxproj sites as an app source,
   but into the `MiaoYanTests` group and the `MiaoYanTests` target's
   `PBXSourcesBuildPhase`. Mimic the `NoteFrontmatterTests.swift` sibling
   entries. `scripts/add_tests_target.rb` is a no-op once the target exists
   (it only bootstraps the target after a pbxproj reset), and the `xcodeproj`
   gem it needs is not installed on this machine anyway.
3. Run `xcodebuild test ...` locally, then push.

A green exit code does not prove a new test ran. Check that `Executed N tests`
grew and that the new test's `Test Case ... passed` line is in the log: a
method-level `-only-testing:` that matches nothing exits 0 having run zero
tests, and a test appended to the end of a file holding two `XCTestCase`
classes lands in the second one. For a regression test, red-run it once on
the old code and see it fail.

`CODE_SIGNING_ALLOWED=NO` is required on the local test command because
the dev signing identity used for `MiaoYan.app` and the per-developer
identity used for `MiaoYanTests.xctest` end up with different Team IDs,
which makes dyld refuse to load the test bundle into the host app. `ci.yml`
passes the same flag on every xcodebuild invocation, so it is not a
local-only workaround.

While `/Applications/MiaoYan.app` is running, which on the maintainer's Mac
is always, the test host shares its bundle id and `xcodebuild test` ends with
"The test runner hung before establishing connection". Add
`PRODUCT_BUNDLE_IDENTIFIER=com.tw93.miaoyan.qa` to the local command; never
quit the running app for a test.
