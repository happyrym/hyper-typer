# hyper-typer

**당신의 다음 프롬프트를 예측하는 AI 보조 입력 도구.** Orca 터미널 위에 떠서, 직전 대화를 읽어
"다음에 보낼 만한 프롬프트 후보"를 최대 6개 제안하고, 복사 버튼이나 핫키(⌃⌥⌘)로 바로 입력하게 하는 네이티브 macOS 플로팅 패널.

*An AI assistant that predicts your next prompt. A floating macOS panel over Orca terminals.*

📄 **[프로젝트 개요 1pager 보기](https://htmlpreview.github.io/?https://github.com/happyrym/hyper-typer/blob/main/docs/overview.html)** — 한 페이지로 훑어보기

---

## 빠른 설치 (프롬프트 복붙)

아래 블록을 통째로 복사해 **Orca 터미널의 Claude Code에 붙여넣으면** 알아서 설치·실행합니다.
(전체 프롬프트·설명은 [`SETUP-PROMPT.md`](SETUP-PROMPT.md) 참고)

````text
하이퍼 타이퍼(hyper-typer)를 내 Mac에 설치하고 실행해줘. Orca 터미널에서 Claude Code로 작업할 때,
포커스된 터미널 위에 "다음에 보낼 프롬프트 후보(최대 6개)"를 띄워주는 보조 도구야. 순서대로 진행하고 막히면 고쳐줘.

1. 사전 점검: macOS 13+, `swift --version`(안 되면 xcode-select --install), `claude --version`(로그인·키 불필요), Orca 터미널 사용 여부
2. 설치: ~/hyper-typer 없으면 `git clone https://github.com/happyrym/hyper-typer.git ~/hyper-typer`, 있으면 `cd ~/hyper-typer && git pull`
3. 빌드·실행: `cd ~/hyper-typer && ./build-app.sh && open ~/hyper-typer/HyperTyper.app`
4. 확인: 메뉴바 ✨ 아이콘 + Orca 위 후보 패널이 뜨는지 (엔터를 치면 앞 3개가 뜨고, Claude 답변 후 뒤 3개가 추가되는지)
5. (선택) 핫키 주입(⌃⌥⌘1~6)을 쓰려면 시스템 설정 › 손쉬운 사용에서 HyperTyper 켜기 — 메뉴바 ✨ › "손쉬운 사용 권한 열기"로 바로 이동 가능
6. (선택) HyperTyper.app 을 /Applications 로 옮기고 로그인 항목에 추가해 자동 실행

완료되면 실행 상태(pid)와 메뉴바 아이콘 확인 결과만 짧게 알려줘.
````

---

## 컨셉

- **무엇** — 프롬프트를 칠 때마다 "다음에 보낼 만한 말" 최대 6개를 옆에 띄워 주는 보조 입력기. 고르면 복사되고, 붙여넣기만 하면 된다.
- **왜** — LLM 코딩에서 "빈 입력창을 마주하고 뭘 칠지 고민하는 시간"이 숨은 병목. 그 다음 한 수를 미리 깔아 준다.
- **어떻게** — **API 키·결제 없이** 로컬 `claude` CLI로 생성. 자동 키 주입이 없어 Secure Input·접근성 권한 문제를 통째로 회피한다.
- **터미널별** — 여러 Orca 터미널을 오갈 때, **지금 포커스된 터미널**의 세션을 읽어 그 맥락의 후보를 보여준다. 터미널마다 후보를 따로 캐시해 전환은 즉각적이다.

## 요구사항

- **macOS 13+**
- **Xcode Command Line Tools** (`xcode-select --install`) — `swift` 빌드용
- **[Orca](https://orca.computer) 터미널** — 이 앱은 Orca의 로컬 상태로 포커스된 터미널·세션을 읽는다 (Orca 전용)
- **`claude` CLI 로그인 완료** — 후보 생성에 사용. `claude` 명령이 되면 OK (별도 API 키 불필요)
- **(선택) 손쉬운 사용 권한** — 핫키(⌃⌥⌘) 직접 주입에만 필요. 복사 버튼만 쓰면 없어도 된다.

## 설치 & 실행

```bash
git clone https://github.com/happyrym/hyper-typer.git
cd hyper-typer
./build-app.sh          # 릴리즈 빌드 → HyperTyper.app 번들 생성
open HyperTyper.app     # 실행
```

- 실행하면 **메뉴바에 ✨ 아이콘**이 뜬다. 종료·새로고침은 여기서.
- Dock 아이콘 없는 에이전트 앱(`LSUIElement`)이라 포커스를 뺏지 않는다.
- 상시 사용: `HyperTyper.app`을 `/Applications`로 옮기고 **시스템 설정 › 로그인 항목**에 추가하면 부팅 시 자동 실행.
- 개발 중에는 `swift build` 후 `./.build/debug/HyperTyper` 로 바로 실행 가능.

## 사용법

1. Orca 터미널에서 Claude Code로 작업한다.
2. 포커스된 터미널 위 패널에 **후보가 최대 6개** 뜬다 (헤더 `📟 프로젝트 · 상태 · 직전 프롬프트`).
   - **1~3번 (early)** — 프롬프트를 보내는 순간, 답변을 기다리지 않고 먼저 뜬다.
   - **4~6번 (answer)** — Claude가 답변을 마치면 아래에 덧붙는다 ("후보 더 생성 중…" 표시 후).
   - 두 묶음은 각각 독립 캐시·병렬 생성. 다른 터미널로 옮기면 그 터미널 후보로 바뀌고, 돌아오면 캐시로 **즉시** 표시.
3. 후보를 입력창에 넣는 두 가지:
   - **복사 버튼** → 클립보드 → 붙여넣기(⌘V), 또는
   - **핫키** → Orca 입력창에 **바로 주입**(무클릭, 아래 표).
4. 패널은 드래그로 원하는 위치에 두면 유지된다.

### 단축키 (Hyper = ⌃⌥⌘)

| 키 | 동작 |
|---|---|
| **⌃⌥⌘1 ~ 6** | 생성된 후보 1~6번을 바로 주입 |
| **⌃⌥⌘0 · 7 · 8 · 9** | 고정 문구 주입 (기본 0=`deck으로 정리`, 9=`1pager로 정리`, 7·8 빈칸) |

> ⌘·⌘⌥+숫자는 Orca가 선점해 겹치므로 세 모디파이어(Hyper)를 쓴다.

### 메뉴바 (✨)

- **지금 후보 새로고침** — 강제 재생성
- **글씨 크기** — 5단계 (선택값 고정 저장)
- **고정 문구 편집…** — 0·7·8·9 문구 수정 (자동 저장, 빈칸이면 그 키는 무동작)
- **손쉬운 사용 권한 열기** — 주입에 필요한 접근성 설정으로 바로 이동
- **종료**

> ⚠️ **핫키 주입엔 손쉬운 사용(접근성) 권한이 필요하다.** 첫 실행 시 메뉴바 › "손쉬운 사용 권한 열기"로 켜면 되고, 한 번 켜면 실행·재부팅에도 유지된다. (재빌드로 업데이트하면 한 번 다시 켜야 함 — 복사 버튼만 쓰면 권한 불필요.)

## 동작 원리

| 구성 | 역할 |
|---|---|
| `OrcaWindowTracker` | `CGWindowList`로 **포커스된 Orca 창** 위치 취득 → 패널 앵커링 (권한 0) |
| `OrcaState` | `orca-data.json`(activeTabId+activeLeafId) + `agent-hooks/last-status.json` → **포커스된 pane의 세션**(cwd·상태·직전 프롬프트·답변) |
| `CandidateGenerator` | `claude -p --model haiku` (print 모드)로 후보 N개 생성(count 지정). 격리된 scratch cwd에서 실행해 자기 트리거 방지 |
| `CandidateStore` | **pane별 2-스트림 캐시**(early=프롬프트만·즉시 3 / answer=답변 기반 3) — 전환 무지연, 각 스트림 독립 병렬 생성, 완료 역전·중복 가드. 복사 처리 |
| `HotkeyManager` | Carbon `RegisterEventHotKey`로 **⌃⌥⌘1~6 전역 핫키** 등록 (핫키 감지엔 권한 불필요) |
| `TextInjector` | 선택 후보를 `CGEvent` 유니코드로 **Orca 입력창에 직접 주입** (접근성 권한 사용, 클립보드 우회) |
| `TranscriptWatcher` | FSEvents로 Orca 상태 변경 감지 (포커스 전환·턴 이벤트) |
| `FloatingPanel` / `PanelView` / `StatusBarController` | non-activating 오버레이 패널 · SwiftUI · 메뉴바 |

> Orca 내부 상태 파일 포맷에 의존한다 — Orca 버전이 바뀌면 `OrcaState`(어댑터)만 고치면 된다.

## 제약 / 로드맵

- **Orca 전용** (포커스·세션 매핑이 Orca 상태 파일 기반).
- **첫 생성 지연 ~9~64초** — `claude -p` 콜드 스타트. 이미 본 터미널은 캐시로 즉시. 지연 제거는 로드맵의 "워밍 세션"으로.
- 로드맵·설계·컨셉 탐색은 `docs/` 참고 (`hyper-typer-ideas-deck-1.html`, `hyper-typer-design-1.html`, `hyper-typer-concepts-1.html`).

## Secret

이 앱은 **API 키 등 secret이 필요 없다** — 로그인된 `claude` CLI 인증을 그대로 쓴다.
코드에 하드코딩된 secret이 없고, `.gitignore`가 로컬 설정·빌드 산출물을 제외한다.
