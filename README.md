# JobWatch

macOS 메뉴바에서 **launchd 잡(=예약 작업/크론)** 을 한눈에 보고 관리하는 개인용 유틸리티.
세션이 끝나거나 재부팅한 뒤에도 "무슨 잡이 왜 돌고 있는지 / 정상인지"를 즉시 확인하려고 만들었다.

## 무엇을 하나

- `~/Library/LaunchAgents` (사용자) + `/Library/LaunchAgents` (시스템)의 모든 `.plist`를 스캔
- `launchctl list`의 실시간 상태와 병합해서 **로드 여부 · PID · 마지막 종료코드**를 초록/빨강으로 표시
- 스케줄을 사람이 읽는 문장으로 변환 (예: "매주 일요일 03:00", "6시간마다")
- 각 잡을 즉시 **실행 / 로드·언로드 / 로그 열기 / plist 위치 보기**
- 상단에 디스크 사용량 게이지
- 다국어 지원: 시스템 언어에 맞춰 **영어 · 한국어 · 일본어 · 중국어(간체)** 자동 전환

> App Store 배포는 불가(샌드박스가 launchctl 접근을 막음). 개인용/직접배포 전용.

## 요구사항

- macOS 14 (Sonoma) 이상
- Xcode 또는 Swift 6 툴체인 (`swift --version`으로 확인)

## 빌드 & 실행

```bash
./build-app.sh      # 빌드 + JobWatch.app 패키징 (ad-hoc 서명 포함)
open ./JobWatch.app # 메뉴바 상단에 시계 아이콘 등장
```

종료는 메뉴바 아이콘 → "종료".

## 로그인 시 자동 시작 (선택)

JobWatch 자체를 항상 떠 있게 하려면, 앱을 `/Applications`로 옮긴 뒤
시스템 설정 → 일반 → 로그인 항목에 추가하면 된다.

## 다른 Mac에서 쓰기

이 저장소는 **소스코드**다. 다른 Mac에서:

```bash
git clone <repo> && cd JobWatch
./build-app.sh      # 그 Mac에서 한 번 빌드하면 JobWatch.app 생성
open ./JobWatch.app
```

빌드된 `JobWatch.app`을 직접 복사해 가도 실행되지만, ad-hoc 서명이라 Gatekeeper가
경고할 수 있다. 그 경우 앱을 **우클릭 → 열기** 하거나
`xattr -dr com.apple.quarantine JobWatch.app` 로 격리 속성을 제거하면 된다.

## 다국어 문자열 추가/수정

`Sources/JobWatch/Resources/<lang>.lproj/Localizable.strings` 를 편집.
언어를 추가하려면 새 `.lproj` 폴더를 만들고 `Package.swift`는 그대로 두면 된다
(`.process("Resources")`가 자동 인식). 표시 이름 목록은 `build-app.sh`의
`CFBundleLocalizations`에도 추가.

## 구조

```
Sources/JobWatch/
  App.swift          진입점 (MenuBarExtra, Dock 아이콘 숨김)
  ContentView.swift  메뉴바 팝오버 UI
  Store.swift        상태 (@Observable, 5초 자동 갱신 + 액션)
  Launchd.swift      plist 스캔 + launchctl 조작 (순수 함수)
  Model.swift        LaunchJob / DiskInfo
  L10n.swift         다국어 조회 헬퍼
  Resources/*.lproj  언어별 문자열
```

## 로드맵 (아이디어)

- [ ] 앱 안에서 새 잡 생성 (스케줄 폼 → plist 자동 생성)
- [ ] MCP 서버 연동 → Claude가 태그·설명 붙여 잡 등록
- [ ] 잡별 최근 로그 미리보기 인라인 표시
