# Scripted runs

`Helpers/UIScript.swift` drives a Debug build from a script, one command per line, and captures its window without the mouse, the keyboard focus or the screen. `scripts/ui_script.py` launches the build in the background (`open -g -n`) on a fresh copy of a library and waits for it to quit. Taken from quiet-md's harness on 2026-11-21.

```sh
xcodebuild -project MiaoYan.xcodeproj -scheme MiaoYan -configuration Debug \
  PRODUCT_BUNDLE_IDENTIFIER=com.tw93.miaoyan.qa -derivedDataPath build/dd-ui build
python3 scripts/ui_script.py run build/dd-ui/Build/Products/Debug/MiaoYan.app scripts/ui_scripts/smoke.txt
python3 scripts/ui_script.py compare <old MiaoYan.app> <new MiaoYan.app> scripts/ui_scripts/smoke.txt
```

- The commands are listed at the top of `Helpers/UIScript.swift`: `open <title>`, `type`, `key`, `select`, `caret`, `menu <selector>`, `resize`, `scroll`, `shot <name>`, `bench <n> <command>`, `wait`, `quit`.
- `shot` draws the window into a PNG and lays each preview web view's own snapshot over its spot, since a web view draws in another process and a cached bitmap holds it blank.
- `compare` runs one script on two builds and compares every capture pixel by pixel. A change that should not alter the look, such as a refactor or moving the storyboard window's code, must report every capture `identical`. Diffs go to `diff-<name>.png`. Until 2026-11-25 it reported every pair identical whatever had changed, because Pillow's `getbbox()` reads only the alpha band of an RGBA difference; a comparison from before that date proves nothing, and `scripts/test_ui_script.py` now holds it. A capture that shows the note list's times can still differ when the clock passes a minute between the two runs.
- A run never opens the maintainer's library: it copies `scripts/ui_scripts/library` (or `--library`) into a temporary folder and passes it as `-storageUrl`. Version history goes to a temporary folder as in unit tests, since a Debug build otherwise shares the release app's `Application Support/com.tw93.miaoyan/Versions`.
- `run` and `compare` refuse any app whose `CFBundleIdentifier` is not `com.tw93.miaoyan.qa`: a plain Debug build shares `com.tw93.miaoyan` with the daily app, and a scripted run would rewrite its settings. `compare` also fails when either run exits non-zero or captures no PNG.
- The window stays behind the front app, and nothing touches the real clipboard. A script must not use commands that open a panel, a browser or Finder.
- Release builds hold none of this: the code sits behind `#if DEBUG || MIAOYAN_SCRIPT`.

## Editor timings

`bench <n> <command>` runs a command n times, laying out and drawing the window after each, and logs the time per step. Time it on a Release build with the script condition, never a Debug build:

```sh
xcodebuild -project MiaoYan.xcodeproj -scheme MiaoYan -configuration Release \
  PRODUCT_BUNDLE_IDENTIFIER=com.tw93.miaoyan.qa SWIFT_ACTIVE_COMPILATION_CONDITIONS=MIAOYAN_SCRIPT \
  -derivedDataPath build/dd-bench build
python3 scripts/ui_scripts/gen_bench_library.py build/bench-lib
python3 scripts/ui_script.py run build/dd-bench/Build/Products/Release/MiaoYan.app scripts/ui_scripts/bench.txt --library build/bench-lib
```

`Medium` has 54,589 characters in 1,894 lines, under the 2000-line ceiling, so it is highlighted in full. `Large` has 1,000,106 characters in 34,080 lines and gets the simplified highlighting. The times cover the main thread's work for one step: the edit, highlighting, layout and drawing into the window's layers. They leave out what the window server does after that, so a scroll, which only moves layers already drawn, measures about 0.1 ms.

2026-11-21, built from the commit that added this file. Apple M5 Pro, 48 GB, macOS 27.2, window 1280 × 800 pt. Two runs, p50 / p95 in ms:

| Step, 100 times | Medium run 1 | Medium run 2 | Large run 1 | Large run 2 |
|---|---|---|---|---|
| Type a letter | 0.97 / 2.11 | 0.87 / 1.79 | 2.98 / 3.42 | 2.74 / 5.70 |
| Backspace | 0.82 / 0.86 | 0.83 / 1.39 | 2.89 / 3.07 | 2.67 / 5.24 |
| Return | 0.76 / 1.21 | 0.74 / 1.24 | 2.77 / 3.10 | 2.65 / 3.00 |
| Scroll 40 pt | 0.10 / 0.11 | 0.10 / 0.11 | 0.10 / 0.11 | 0.10 / 0.10 |

A 120 Hz display gives each frame 8.3 ms. Compare a change against a run of the build before it on the same machine, not against this table: the p95 moves by a few milliseconds between runs.

Since 2026-11-24 `Large` types into its last prose line, 34,000 lines below the first fence, instead of at offset 400, which sat in a table above every fence and so never paid for a scan from the top of the note. The same machine and window, p50 / p95 in ms, `Medium` unchanged:

| Step in `Large`, 100 times | 23ca09fa | With the list indent read lazily |
|---|---|---|
| Type a letter | 37.12 / 39.49 | 2.97 / 4.32 |
| Backspace | 37.44 / 40.51 | 2.88 / 2.96 |
| Return | 51.44 / 55.18 | 16.17 / 16.66 |

Return there still cost about 16 ms: `ListContinuation.edit` counted lines from the top twice to find the caret's line. Since 2026-11-26 it reads that line alone (`SourceLines.range(around:)`) and checks for a fence only on an item or quote line, reading fences unit by unit; same machine and window, two runs each:

| Return in `Large`, 100 times | Counting lines | Reading the caret's line |
|---|---|---|
| On the last prose line | 15.85 / 16.53 | 2.87 / 3.27, 2.84 / 3.29 |
| At the end of a task item 280 characters from the end | | 2.66 / 3.31 |
