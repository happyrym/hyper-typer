#!/bin/bash
# HyperTyper.app 번들 생성 — 더블클릭 실행용.
set -e
cd "$(dirname "$0")"

echo "▶ 릴리즈 빌드…"
swift build -c release

APP="HyperTyper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/HyperTyper "$APP/Contents/MacOS/HyperTyper"
cp Info.plist "$APP/Contents/Info.plist"

# ad-hoc 서명 — 접근성 권한이 좀 더 안정적으로 붙게. 안정 식별자 지정.
codesign --force --deep --sign - --identifier com.eden.hypertyper "$APP" 2>/dev/null || true

echo "✅ 완료: $(pwd)/$APP"
echo "   • 실행: 더블클릭 (또는  open $APP )"
echo "   • 종료: 메뉴바 ✨ 아이콘 → 종료"
echo "   • 상시 사용: $APP 를 /Applications 로 드래그, 로그인 항목에 추가하면 부팅 시 자동 실행"
