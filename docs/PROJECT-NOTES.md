# 하이퍼 타이퍼 (Hyper Typer)

## 개요

프롬프트 입력 가속 보조 도구. **현재 빌드 중인 것 = v0 MVP**: Orca 터미널 위에 떠서
"다음에 보낼 프롬프트 후보 5개"를 보여주고, 복사 버튼으로 클립보드에 넣어 붙여넣기만 하게 하는
네이티브 macOS 플로팅 패널. **API 키·결제 없이** 로컬 `claude` CLI로 후보를 생성한다.

## 현재 컨셉 (v0 MVP) — 확정

- 형태: 네이티브 macOS 앱(SwiftUI), 에이전트 앱(`.accessory` — Dock 없음, 포커스 안 뺏음)
- UX: **Orca 창 위 오버레이 플로팅 패널.** 드래그로 위치 조정(그 자리 유지), Orca가 움직이면 이동량만큼만 따라감.
- 후보 생성: **`claude` CLI print 모드**(`claude -p --model haiku --output-format text`). 로그인된 Claude Code 인증 사용 → **키/결제 불필요**(사용량은 소모).
- 읽기: Claude Code **transcript JSONL**(`~/.claude/projects/<enc-cwd>/<uuid>.jsonl`). **FSEvents 감시 → 새 답변마다 자동 재생성.** `subagents/` 제외, `message.id` 그룹핑으로 마지막 text 턴 추출.
- 복사: 각 후보 복사 버튼 → 클립보드 → Orca에 **수동 붙여넣기**(자동 주입 없음 → Secure Input·HID·AX 문제 전부 회피).

## 아키텍처 (구현됨)

- `OrcaWindowTracker` — CGWindowList(권한 0)로 Orca 창 프레임 취득, 0.4s 폴링, Cocoa 좌표 변환 + 듀얼모니터 클램프
- `TranscriptReader` — 최신 jsonl에서 직전 assistant text 턴 추출(subagents 제외·id 그룹핑)
- `TranscriptWatcher` — FSEvents로 `~/.claude/projects` 감시, 0.8s 디바운스
- `CandidateGenerator` — claude CLI 호출(`zsh -lc`, HT_PROMPT env, cwd `/tmp`, 45s 워치독), JSON 배열 파싱, 실패 시 정적 fallback
- `CandidateStore`(@MainActor) — 상태·복사·"바뀐 경우만 재생성"
- `FloatingPanel`(NSPanel nonactivating, 드래그-유지) + `PanelView`(SwiftUI)

## 관련 경로/파일

- 앱: `HyperTyper/` (SwiftPM). 빌드 `swift build`, 실행 `./.build/debug/HyperTyper &`, 끄기 `killall HyperTyper`
- 현재 컨셉 1pager: `hyper-typer-mvp-1.html`
- 초기 탐색(히스토리): `hyper-typer-concepts-1.html`(10컨셉), `hyper-typer-design-1.html`(4컨셉 HID 통합설계 — **파킹됨**)

## 파킹된 큰 그림 (나중)

- 원래 채택 4개(다음수예측·SeamLayer·ChordTap·LeaderKey)의 **HID 엔진(Karabiner-DriverKit) 통합은 뒤로.** MVP로 "AI 후속 프롬프트가 실제로 도움되나"를 먼저 싸게 검증.
- MVP의 플로팅 패널이 곧 **"다음 수 예측"의 복사-붙여넣기 실용 버전** — 인라인 고스트·자동 주입의 하드 리스크를 통째로 우회한 형태.

## 메모 / 다음 단계

- 현재 v0 동작: 빌드·실행·Orca 앵커링·자동갱신·claude CLI 후보·복사 ✓ (2026-08-24)
- 다음 후보: 후보 품질/톤 다듬기, 위치/크기 취향, (옵션) 마지막 위치 기억(frameAutosave)·단축키 토글, 생성 지연(~5-10s) 개선(캐시/워밍)
- 프라이버시: transcript·후보 전부 로컬. claude CLI는 사용자 Claude 사용량을 소모.
