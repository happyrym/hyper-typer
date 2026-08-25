# 빠른 설치 — 프롬프트 복붙

아래 블록을 통째로 복사해서 **Orca 터미널의 Claude Code에 붙여넣으면** 알아서 설치·실행합니다.

````text
하이퍼 타이퍼(hyper-typer)를 내 Mac에 설치하고 실행해줘.
Orca 터미널에서 Claude Code로 작업할 때, 포커스된 터미널 위에 "다음에 보낼 프롬프트 후보 5개"를
띄워주는 보조 입력 도구야. 아래를 순서대로 진행하고, 막히면 원인을 찾아 고쳐줘.

1. 사전 점검
   - macOS 13 이상인지, `swift --version` 되는지 (안 되면 `xcode-select --install` 안내)
   - `claude --version` 되는지 — 후보 생성에 쓰고 별도 API 키는 필요 없음
   - Orca 터미널(com.stablyai.orca)을 쓰는지 — 이 도구는 Orca 전용

2. 설치
   - `~/hyper-typer` 없으면: git clone https://github.com/happyrym/hyper-typer.git ~/hyper-typer
   - 있으면: cd ~/hyper-typer && git pull

3. 빌드 & 실행
   - cd ~/hyper-typer && ./build-app.sh
   - open ~/hyper-typer/HyperTyper.app

4. 확인
   - 메뉴바 오른쪽에 ✨ 아이콘이 떴는지 (여기서 종료·글씨크기·새로고침)
   - Orca 터미널 위에 후보 패널이 뜨는지 (안 뜨면 Orca 창을 앞으로)
   - 프롬프트를 엔터로 제출하면 후보가 갱신되는지

5. (선택) 상시 사용
   - HyperTyper.app 을 /Applications 로 옮기고, 시스템 설정 › 일반 › 로그인 항목에 추가해 부팅 시 자동 실행

완료되면 실행 상태(pid)와 메뉴바 아이콘 확인 결과만 짧게 알려줘.
````

## 처음 쓰는 사람용 최소 요구사항

- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`)
- [Orca](https://orca.computer) 터미널
- `claude` CLI 로그인 완료 (별도 API 키 불필요)

> 아직 GitHub에 올라가기 전이라면 clone 대신 로컬 경로에서 `./build-app.sh` 로 바로 빌드하면 됩니다.
