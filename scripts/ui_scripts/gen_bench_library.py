#!/usr/bin/env python3
"""Write the library the editor benchmark types into.

    python3 scripts/ui_scripts/gen_bench_library.py <empty folder>

Two notes, both mixed prose (English and Chinese), lists, tasks, tables,
quotes and code: `Medium` stays under 2000 lines, so the editor highlights
it in full, and `Large` holds about a million characters, past every
ceiling, so it gets the simplified highlighting. The text is the same on
every run, so timings compare between builds.
"""

import sys
from pathlib import Path

PROSE = (
    "Writing in Markdown keeps the text plain and the structure visible, so a note opened years later still reads the same. "
    "\u7528 Markdown \u5199\u4e1c\u897f\uff0c\u6587\u5b57\u4fdd\u6301\u7eaf\u6587\u672c\uff0c\u7ed3\u6784\u4e00\u773c\u5c31\u80fd\u770b\u5230\uff0c\u8fc7\u4e86\u5f88\u591a\u5e74\u518d\u6253\u5f00\u4e5f\u8fd8\u662f\u4e00\u6837\u3002"
)


def chapter(n: int) -> str:
    return "\n".join([
        f"## Chapter {n}",
        "",
        PROSE + f" (part {n})",
        "",
        f"- point one of chapter {n} with **bold** and *italic* words",
        "- point two with `inline code` and a [link](https://miaoyan.app)",
        "  - a nested point",
        f"- [ ] task {n}",
        f"- [x] done {n}",
        "",
        "| Item | Count | Note |",
        "| ---- | ----: | ---- |",
        f"| apples | {n} | fresh |",
        f"| \u68a8 | {n * 2} | \u751c |",
        "",
        "> " + PROSE[:120],
        "",
        "```swift",
        f"let chapter = {n}",
        "print(\"chapter \\(chapter)\")",
        "```",
        "",
    ])


def write(path: Path, title: str, target_chars: int, max_lines: int) -> None:
    parts, chars, lines, n = [f"# {title}", ""], 0, 2, 1
    while chars < target_chars:
        block = chapter(n)
        block_lines = block.count("\n") + 1
        if lines + block_lines > max_lines:
            break
        parts.append(block)
        chars += len(block) + 1
        lines += block_lines
        n += 1
    text = "\n".join(parts)
    path.write_text(text, encoding="utf-8")
    print(f"{path.name}: {len(text):,} characters, {text.count(chr(10)) + 1:,} lines")


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    folder = Path(sys.argv[1]) / "Bench"
    folder.mkdir(parents=True, exist_ok=True)
    write(folder / "Medium.md", "Medium", 10**9, 1900)
    write(folder / "Large.md", "Large", 1_000_000, 10**9)
    return 0


if __name__ == "__main__":
    sys.exit(main())
