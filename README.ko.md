# 🚀 JobWatch

[English](README.md) · **한국어**

macOS 메뉴바에서 돌아가는 로컬 우선 **launchd 잡 관측(observability)** 앱 —
예약 잡과 백그라운드 에이전트가 *실제로 무엇을 했는지*를 작은 픽셀 발사 기지로 보여줍니다.

클라우드·계정·텔레메트리 없음. 의존성 0 (시스템 SQLite만 사용).

---

## 무엇을 하나

- `~/Library/LaunchAgents` + `/Library/LaunchAgents`를 **스캔**하고 실시간
  `launchctl` 상태(로드 여부 / PID / 마지막 종료코드)를 병합합니다.
- **발사 기지 씬**(픽셀 아트): 예약 잡이 발사대에 대기하다 카운트다운에 맞춰 발사되고,
  발사된 잡·상시 데몬은 상단 궤도를 돕니다. 실패한 잡은 상승 중 흩어집니다.
- 트리거 **종류별 그룹**(자주 동작 / 상시 실행 / 변경 감지 / 로그인 시 / 수동) +
  실제 실패만 모으는 상단 **문제** 섹션.
- 잡별 **상세**: 설명(스크립트 헤더 주석이 있으면 그걸 사용), 스케줄, 마지막 종료코드,
  그리고 **정밀 실행 이력**(시작 / 소요 / 종료 + 캡처된 출력).
- **미션 컨트롤 콘솔**: CPU · MEM · DISK · 실행 중 JOB 게이지.
- **실패 알림**, **로그인 시 자동 시작**, 자연어 **AI 잡 생성**(claude/codex),
  **4개 언어**(en / ko / ja / zh).

정밀 이력은 번들된 `jobwatch-runner`를 거친 잡에 대해 정확합니다. 그 외 잡은
로그 파일 수정 시각 기반의 *추정* 마지막 실행을 보여줍니다.

> App Store 배포는 불가합니다(샌드박스가 `launchctl` 접근을 막음). 직접 배포·오픈소스용 앱입니다.

## 설치

### Homebrew (권장)

```bash
brew install --cask kzhxxn/tap/jobwatch
```

Homebrew가 체크섬을 검증합니다. 아직 공증(notarize) 전이라 Gatekeeper가 적용되므로,
**첫 실행 시** `/Applications`에서 앱을 **우클릭 → 열기**(한 번) 하거나, 격리를 건너뛰고 설치하세요:

```bash
brew install --cask --no-quarantine kzhxxn/tap/jobwatch
```

그다음 메뉴바에서 궤도 아이콘을 찾으세요.

### DMG 다운로드

[Releases](https://github.com/kzhxxn/JobWatch/releases)에서 최신 `.dmg`를 받으세요.
릴리스 빌드는 ad-hoc 서명(공증 안 됨)이라 첫 실행 시 **우클릭 → 열기**(한 번) 하거나
`xattr -dr com.apple.quarantine JobWatch.app` 를 실행하면 됩니다.

## 요구사항

- macOS 14 (Sonoma) 이상
- 소스에서 빌드하려면: Xcode 또는 Swift 6 툴체인 (`swift --version`)

## 빌드 & 실행

```bash
./build-app.sh       # 빌드 + JobWatch.app 패키징 (ad-hoc 서명)
open ./JobWatch.app  # 메뉴바에 아이콘이 나타남
```

**로그인 시 자동 시작**을 켜기 전에 `JobWatch.app`을 `/Applications`로 옮기세요.
공증 DMG는 Apple 개발자 계정이 필요합니다 — [docs/NOTARIZATION.md](docs/NOTARIZATION.md) 참고.

## 의존성

**없음.** SQLite는 macOS에 내장된 시스템 `libsqlite3`이며, 서드파티 Swift 패키지가 없습니다.
이력 데이터베이스는 `~/Library/Application Support/JobWatch/jobwatch.sqlite`에 자동 생성됩니다.

## 프로젝트 구조

```
Sources/JobWatch/          메뉴바 앱 (SwiftUI)
  App.swift                진입점 + 메뉴바 아이콘
  ContentView.swift        헤더, 그룹 목록, 드릴인 상세, 콘솔
  LaunchPadView.swift      발사 기지 씬
  Store.swift              @Observable 상태 (스캔 / 이력 / 지표 / 설정)
  Launchd.swift            plist 스캔 + launchctl 어댑터
  RunStore.swift           정밀 실행 이력 조회 (SQLite)
  Inference.swift          규칙 기반 이름/설명/카테고리 추론
  SystemVitals.swift       CPU / 메모리 / 디스크 샘플링
Sources/jobwatch-runner/   헤드리스 러너: 잡 실행을 감싸 SQLite에 기록
```

## 라이선스

MIT © Jihun Kang
