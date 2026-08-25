#!/bin/bash
# 생성 CLI 신뢰도·지연 편차 측정. 앱이 실제로 쓰는 호출을 N회 반복.
N=${1:-6}
sys='너는 개발자가 AI와 나누는 대화를 돕는다. 직전 내 프롬프트와 어시스턴트 답변을 보고 다음에 보낼 짧은 한국어 메시지 5개를 제안하라. 각 40자 이내. 출력은 정확히 5줄, 한 줄에 하나. 번호·불릿·따옴표·설명·빈줄 금지.'
prompt='[직전 내 프롬프트]
자동 갱신이 안정적인지 테스트해줄래?

[어시스턴트 답변]
로깅을 심고 CLI를 반복 호출해 신뢰도와 지연 편차를 측정한다.'

ok=0
mind=999999; maxd=0; sumd=0
for i in $(seq 1 "$N"); do
  out=$(cd /tmp && claude -p "$prompt" --model haiku --output-format json --strict-mcp-config --setting-sources '' --system-prompt "$sys" 2>/dev/null)
  dur=$(printf '%s' "$out" | jq -r '.duration_ms // 0')
  err=$(printf '%s' "$out" | jq -r '.is_error // "?"')
  lines=$(printf '%s' "$out" | jq -r '.result // ""' | grep -c .)
  echo "run $i: dur=${dur}ms is_error=$err lines=$lines"
  if [ "$err" = "false" ] && [ "$lines" -ge 5 ]; then ok=$((ok+1)); fi
  sumd=$((sumd+dur)); [ "$dur" -lt "$mind" ] && mind=$dur; [ "$dur" -gt "$maxd" ] && maxd=$dur
done
echo "----"
echo "성공 $ok/$N | 지연 min=${mind}ms max=${maxd}ms avg=$((sumd/N))ms"
