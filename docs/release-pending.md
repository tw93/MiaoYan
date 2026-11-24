# Release pending

Work an earlier session left for the next release. The release reads this before drafting notes, does each item, and deletes its entry in the release commit, or writes in the entry why it waits for a later release. MiaoYan-Pro merges this repository's `main`, so its App Store release reads the same file.

- V4.12.0 (2026-11-24): the release commit is 3e6b1767 and its notes cover up to it. Commits after it on `main` (the MiaoYanCore line kinds and block inserts for the iPhone insert bar) belong to the next version, so the `V4.12.0` tag goes on 3e6b1767 and `scripts/build.sh` runs from a detached worktree at that commit, not from `main`. Delete this entry once V4.12.0 is published.
