<div align="center">
  <a href="https://miaoyan.app/" target="_blank"><img src="https://raw.githubusercontent.com/tw93/MiaoYan/main/Resources/app.icon/Assets/43.png" width="138" /></a>
  <h1>MiaoYan</h1>
  <p><b>로컬 마크다운 노트를 위한 네이티브 Mac 앱</b></p>
  <p><a href="README.md">English</a> · <a href="README_CN.md">中文</a> · <a href="README_TW.md">繁體</a> · <a href="README_JA.md">日本語</a> · 한국어 · <a href="README_DE.md">Deutsch</a> · <a href="README_FR.md">Français</a></p>
  <a href="https://twitter.com/HiTw93" target="_blank"><img alt="Twitter Follow" src="https://img.shields.io/badge/follow-Tw93-red?style=flat-square&logo=Twitter"></a>
  <a href="https://t.me/+9f9gf4ZrFSQ2OWVl" target="_blank"><img alt="Telegram" src="https://img.shields.io/badge/chat-Telegram-blueviolet?style=flat-square&logo=Telegram"></a>
  <a href="https://github.com/tw93/MiaoYan/releases" target="_blank"><img alt="GitHub Downloads" src="https://img.shields.io/github/downloads/tw93/MiaoYan/total.svg?style=flat-square"></a>
  <a href="https://github.com/tw93/MiaoYan/commits" target="_blank"><img alt="GitHub Commit Activity" src="https://img.shields.io/github/commit-activity/m/tw93/MiaoYan?style=flat-square"></a>
  <a href="https://github.com/tw93/MiaoYan/issues?q=is%3Aissue+is%3Aclosed" target="_blank"><img alt="GitHub Closed Issues" src="https://img.shields.io/github/issues-closed/tw93/MiaoYan.svg?style=flat-square"></a>
  <img alt="macOS 12.0+" src="https://img.shields.io/badge/macOS-12.0%2B-orange?style=flat-square">
</div>

<img src="https://raw.githubusercontent.com/tw93/static/main/miaoyan/miaoyan.gif" width="900px" />

## 특징

- **로컬 우선**: 노트는 직접 고른 폴더 안의 마크다운 파일, 데이터 수집 없음, 기기 간 동기화는 iCloud Drive나 Nutstore로
- **집중**: 폴더, 노트 목록, 편집기로 나뉜 3단 구성, 다크 모드 지원, 관리할 플러그인 시스템 없음
- **네이티브**: Swift 6으로 만들어 웹 래퍼보다 가볍고, 분할 미리보기는 60fps 양방향 스크롤 동기화
- **충분한 기능**: 양방향 링크, LaTeX 수식, Mermaid 다이어그램, 버전 기록, 자동 서식, PPT 프레젠테이션 내장

## 설치

1. **Mac App Store** (유료, 자동 업데이트, iPhone 및 iPad 앱 포함):

   <a href="https://apps.apple.com/app/miaoyan/id6759252269"><img src="https://cdn.tw93.fun/uPic/C3Renh.png" width="160" alt="Download on the Mac App Store" /></a>

2. **Homebrew**:
   ```bash
   brew install --cask miaoyan
   ```

3. **GitHub Releases**: [GitHub Releases](https://github.com/tw93/MiaoYan/releases/latest)에서 최신 DMG 다운로드 (macOS 12.0+)

Homebrew 및 GitHub Releases는 버그 수정만 제공되는 오픈소스 버전을 설치합니다. Mac App Store 에디션은 별도로 개발되며 신기능은 그쪽에 추가됩니다.

## Nutstore 및 기타 클라우드 드라이브 동기화

MiaoYan은 WebDAV나 클라우드 계정에 로그인하지 않고 지정된 마크다운 폴더만 읽고 씁니다. 설치 후 iCloud Drive, Nutstore 데스크톱 클라이언트의 동기화 폴더 또는 원하는 위치에 `MiaoYan` 폴더를 만들고 환경설정(⌘,)에서 저장 위치로 지정하면 바로 쓸 수 있습니다. 기기 간 동기화는 iCloud Drive, Nutstore, Dropbox 등의 클라우드 클라이언트가 담당합니다.

- **iPhone**: 시스템 파일 앱에서 동일한 클라우드 드라이브 폴더를 선택하고, 쓰기 가능한 폴더를 지원하지 않는 경우 iCloud Drive를 사용하거나 해당 앱에서 오프라인 사용 가능으로 설정 후 선택
- **경로 확인**: 폴더 전환 전 읽기/쓰기 권한을 확인하고, 접근할 수 없으면 기존 경로를 유지하며 오류를 앱 자체 동기화 실패로 표시하지 않음

## CLI 도구

```bash
# 설치
curl -fsSL https://raw.githubusercontent.com/tw93/MiaoYan/main/scripts/install.sh | bash

# 사용법
miao open <제목|경로>     # 노트 또는 폴더 열기
miao new <제목> [내용]    # 새 노트 생성
miao search <검색어>      # 터미널에서 노트 검색
miao list [폴더]        # 최상위 폴더 또는 폴더 내 마크다운 목록
miao cat <제목|경로>      # 노트 내용 출력
miao update              # CLI 업데이트
```

## 분할 편집 및 미리보기 모드

편집 영역과 미리보기를 나란히 배치합니다. `⌘\` 키로 분할 모드를 전환하거나 환경설정의 General에서 Editor Mode를 Split Mode로 설정할 수 있습니다. 왜 Typora처럼 WYSIWYG로 만들지 않았을까요? 마크다운 원문을 보면서 쓰기를 바라기 때문입니다. Swift로 네이티브 WYSIWYG를 만들면 무겁고 안정적으로 유지하기도 어렵습니다. 분할 모드에서는 글쓰기에 집중하면서 바로 옆에서 실시간 미리보기를 볼 수 있습니다.

<img src="https://raw.githubusercontent.com/tw93/MiaoYan/main/assets/split-preview.png" width="100%" alt="분할 편집 및 미리보기 모드" />

## 문서

- [MiaoYan 소개](Resources/Initial/Introduction%20to%20MiaoYan.md) - 사용 가이드와 단축키
- [마크다운 문법 가이드](Resources/Initial/MiaoYan%20Markdown%20Syntax%20Guide.md) - 수식과 다이어그램을 포함한 문법 레퍼런스
- [PPT 프레젠테이션 모드](Resources/Initial/MiaoYan%20PPT.md) - `---` 슬라이드 구분선을 활용한 발표 가이드
- [MiaoYan Agent Skill](skills/miaoyan) - 에이전트에게 MiaoYan 문법, 첨부파일, PPT 및 CLI 워크플로 학습

`npx skills add tw93/MiaoYan/skills/miaoyan -g` 명령어로 공식 Skill을 설치할 수 있습니다.

## 후원

- 제가 만든 유료 Mac 정리 앱 [Mole for Mac](https://mole.fit)을 이용해 주시는 것이 가장 직접적인 후원입니다
- MiaoYan이 유용했다면 Star를 누르거나, [공유](https://twitter.com/intent/tweet?url=https://github.com/tw93/MiaoYan&text=MiaoYan%20-%20%EB%A1%9C%EC%BB%AC%20%EB%A7%88%ED%81%AC%EB%8B%A4%EC%9A%B4%20%EB%85%B8%ED%8A%B8%EB%A5%BC%20%EC%9C%84%ED%95%9C%20%EB%84%A4%EC%9D%B4%ED%8B%B0%EB%B8%8C%20Mac%20%EC%95%B1)하거나, 이슈 및 PR을 남겨주세요
- 탕위안(TangYuan)과 콜라(Coke)라는 두 마리의 고양이를 키우고 있습니다. MiaoYan이 즐거움을 주었다면 <a href="https://cats.tw93.fun?name=MiaoYan" target="_blank">캔 간식 🥩</a>을 후원해 주세요

<details>
<summary>후원해 주신 분들 🐱</summary>
<br/>
<a href="https://cats.tw93.fun?name=MiaoYan"><img src="https://cdn.jsdelivr.net/gh/tw93/sponsors@main/assets/sponsors.svg" width="1000" loading="lazy" /></a>
</details>

## 감사의 글

- [glushchenko/fsnotes](https://github.com/glushchenko/fsnotes) - 초기 프로젝트 구조 참고
- [stackotter/swift-cmark-gfm](https://github.com/stackotter/swift-cmark-gfm) - Swift 마크다운 파서
- [simonbs/Prettier](https://github.com/simonbs/Prettier) - 마크다운 포맷팅 유틸리티
- [raspu/Highlightr](https://github.com/raspu/Highlightr) - 구문 강조
- [hakimel/reveal.js](https://github.com/hakimel/reveal.js) - PPT 프레젠테이션 프레임워크

## 라이선스

MIT License
