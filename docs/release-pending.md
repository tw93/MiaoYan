# Release pending

Work an earlier session left for the next release. The release reads this before drafting notes, does each item, and deletes its entry in the release commit, or writes in the entry why it waits for a later release. MiaoYan-Pro merges this repository's `main`, so its App Store release reads the same file.

- 2026-11-15: #578 (local images blank in the App Store Mac build only, because its sandboxed preview could not read the notes folder over `file://`; fixed in 5ea57d0b) ships in V4.10.0; the App Store builds were being uploaded on 2026-11-15 and are not yet in review. The GitHub build never had the bug. Reply and close once the App Store Mac version 4.10.0 is live, naming that version.
