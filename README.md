# hyper-typer

An AI agent assistant that predicts your next prompt. Built for Orca / terminal-based Claude Code.

Orca 터미널 위에 떠서, 직전 대화를 읽어 **"다음에 보낼 프롬프트 후보 5개"**를 제안하고
복사 버튼으로 클립보드에 넣어 붙여넣게 하는 네이티브 macOS 플로팅 패널.
**API 키·결제 없이** 로컬 `claude` CLI로 생성한다. 자동 주입이 없어 Secure Input·HID·AX 문제를 회피한다.

## 동작 방식

1. **트리거** — 내가 프롬프트를 **엔터로 제출**하면(Shift+Enter는 제출이 아니라 제외됨) 감지.
2. **세션 스코핑** — `~/.claude/projects`의 transcript 중 *가장 최근 새 user 발화*가 있는 세션(= 방금 제출한 터미널)을 고른다. 백그라운드 에이전트는 못 가로챈다.
3. **생성** — `claude -p --model haiku`(print 모드)로 직전 교환을 근거로 후보 5개 생성. 키 불필요.
4. **표시·복사** — 포커스된 Orca 창 위 플로팅 패널에 5줄 + 복사 버튼. 붙여넣기는 수동.

## 빌드 / 실행

```bash
swift build              # 개발 빌드
./build-app.sh           # HyperTyper.app 번들 생성 (더블클릭 실행용)
open HyperTyper.app      # 실행 — 메뉴바 ✨ 아이콘에서 종료
```

에이전트 앱(`LSUIElement`)이라 Dock 아이콘이 없고 포커스를 뺏지 않는다.
`.app`을 `/Applications`로 옮기고 로그인 항목에 추가하면 부팅 시 자동 실행.

## 구성

- `Sources/HyperTyper/` — SwiftUI 앱
  - `FloatingPanel` — non-activating 오버레이 패널 (포커스 창 추종, 드래그 위치 유지)
  - `OrcaWindowTracker` — CGWindowList로 포커스된 Orca 창 프레임 취득 (권한 0)
  - `TranscriptReader` — transcript에서 마지막 교환 추출 (end_turn 필터, 세션 스코핑)
  - `TranscriptWatcher` — FSEvents로 변경 감지 (디바운스)
  - `CandidateGenerator` — `claude` CLI 호출로 후보 5개 생성
  - `CandidateStore` / `PanelView` / `StatusBarController`
- `on-stop.sh` — (선택) Claude Code Stop hook. 세션 정밀 매칭용.
- `docs/` — 컨셉·설계·MVP 1pager, 프로젝트 노트

## Secret

이 앱은 **API 키 등 secret이 필요 없다** — 로그인된 `claude` CLI 인증을 그대로 사용한다.
따라서 코드에 하드코딩된 secret이 없다. 향후 직접 API 모드를 추가할 경우
키는 `~/.hyper-typer/anthropic-key`(repo 밖) 또는 환경변수로만 두고, 절대 커밋하지 않는다.
`.gitignore`가 로컬 설정·빌드 산출물을 제외한다.
