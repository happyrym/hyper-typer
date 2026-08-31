#!/bin/bash
# HyperTyper.app 번들 생성 — 더블클릭 실행용.
set -e
cd "$(dirname "$0")"

echo "▶ 릴리스 빌드…"
swift build -c release

APP="HyperTyper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/HyperTyper "$APP/Contents/MacOS/HyperTyper"
cp Info.plist "$APP/Contents/Info.plist"
# 앱 아이콘(Info.plist의 CFBundleIconFile=AppIcon 과 짝). make-icon.swift 로 생성.
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# ad-hoc 서명 — 안정 식별자만 지정. 재빌드 시 cdhash가 바뀌어 접근성 권한은 재승인이 필요하다
# (같은 빌드를 다시 실행·재부팅하는 것만으로는 안 풀림 — 오직 재빌드 때만).
codesign --force --deep --sign - --identifier com.eden.hypertyper "$APP" 2>/dev/null || true

echo "✅ 완료: $(pwd)/$APP"
echo "   • 실행: 더블클릭 (또는  open $APP )"
echo "   • 종료: 메뉴바 ✨ 아이콘 → 종료"
