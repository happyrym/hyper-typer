#!/bin/bash
# HyperTyper Stop hook — 턴 종료 시 '방금 답한 세션'의 transcript 경로를 기록.
# 패널이 이 파일을 보고 정확한 세션의 직전 답변으로 후보를 생성한다.
# 기존 Orca/pipeline Stop hook과 나란히(추가로) 실행된다.
dir="$HOME/.hyper-typer"
mkdir -p "$dir"
input=$(cat)
printf '%s' "$input" | jq -c \
  --arg pane "${ORCA_PANE_KEY:-}" \
  --arg ts "$(date +%s)" \
  '{transcript_path, session_id, cwd, pane: $pane, ts: ($ts|tonumber)}' \
  > "$dir/last-turn.json" 2>/dev/null
# Claude Code에 무해한 빈 출력 반환.
printf '{}\n'
exit 0
