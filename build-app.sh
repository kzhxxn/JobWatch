#!/bin/bash
# JobWatch 를 빌드해서 실행 가능한 .app 번들로 패키징한다.
# 사용법:  ./build-app.sh   (결과: ./JobWatch.app)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="JobWatch"
BUNDLE_ID="com.mark.jobwatch"
APP="${APP_NAME}.app"

echo "▶︎ swift build (release)…"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"

echo "▶︎ .app 번들 조립…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
# 헤드리스 러너도 번들에 포함 (앱이 실행 시 안정 경로로 설치)
cp "$BIN_DIR/jobwatch-runner" "$APP/Contents/MacOS/jobwatch-runner"

# SPM 리소스 번들(다국어 .strings)을 실행파일 옆 + Resources 양쪽에 복사 → Bundle.module 확실히 인식
for b in "$BIN_DIR"/*.bundle; do
  [ -e "$b" ] || continue
  cp -R "$b" "$APP/Contents/MacOS/"
  cp -R "$b" "$APP/Contents/Resources/"
done

# 앱 아이콘
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>        <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>         <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>         <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>            <string>1.0</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleIconFile</key>           <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>     <string>14.0</string>
    <key>LSUIElement</key>                <true/>
    <key>CFBundleDevelopmentRegion</key>  <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>ko</string>
        <string>ja</string>
        <string>zh-Hans</string>
    </array>
</dict>
</plist>
PLIST

# 로컬 실행용 ad-hoc 서명 (미서명이면 Gatekeeper가 막을 수 있음)
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "✅ 완료: $APP"
echo "   실행:  open ./$APP     (메뉴바 상단에 시계 아이콘)"
echo "   종료:  메뉴바 아이콘 → 종료"
