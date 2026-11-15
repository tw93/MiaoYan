# Release pending

Work an earlier session left for the next release. The release reads this before drafting notes, does each item, and deletes its entry in the release commit, or writes in the entry why it waits for a later release. MiaoYan-Pro merges this repository's `main`, so its App Store release reads the same file.

- 2026-11-15: #579 (the Move menu lists folders as the sidebar nests and orders them, b4e55349) is on `main`, unreleased and unanswered. Carry it in the next GitHub release and the App Store release, then reply to the reporter and close it, naming the version.
- 2026-11-15: #578 (local images blank in the App Store Mac build only, because its sandboxed preview could not read the notes folder over `file://`; fixed in 5ea57d0b) is on `main`, unanswered. The GitHub build never had the bug. Reply and close only once the App Store Mac version with the fix is live, naming that version.
- Both wait on the maintainer's release timing (decide 1114-17); do not tag for them alone.
