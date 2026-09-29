# oh-my-usage

Swift + AppKit으로 만든 Apple Silicon용 메뉴바 앱. 외부 패키지 없음.

macOS 14 이상과 Apple Silicon, 빌드에는 Xcode Command Line Tools가 필요하다.

- 최대 3개 계정의 **주간 잔여량**을 세로 표시
- 요금제 표시: `Pro $100`, `Pro $200`, `Plus`, `Free`, `Go`, `Business`, `Enterprise`, `Edu`
- 메뉴의 각 계정 행에 **남은 초기화권 개수**를 `↻ 1`처럼 표시 (조회되지 않으면 `↻ —`)
- 메인 계정은 노란 배경과 검은 굵은 글씨
- 클릭/우클릭하면 macOS 기본 메뉴
- 계정 행 클릭으로 전환, 계정 추가·삭제
- 60초 간격 갱신
- 메뉴에서 **로그인 시 자동 실행** 켜기·끄기 (macOS 기본 로그인 항목, 기본 꺼짐)

## 실행

```sh
sh build.sh
open build/oh-my-usage.app
```

메뉴에서 **현재 Codex 계정 추가**로 현재 로그인을 등록하거나 **다른 계정 추가…**로 브라우저에서 로그인한다. 한 번에 최대 3개. 계정 행의 체크가 현재 선택 계정이며 마우스를 올리면 초기화 시각/오류를 볼 수 있다.

**로그인 시 자동 실행**을 켜면 다음 macOS 로그인부터 실행한다. 승인이 필요한 경우 시스템 설정의 로그인 항목 화면이 열린다. 메뉴의 체크는 macOS에 등록된 실제 상태를 표시한다.

계정 전환은 `~/.codex/auth.json`을 교체하고 Codex 앱을 **정상 종료 후 재실행**한다. **진행 중인 작업을 마친 뒤 전환한다.** Codex가 종료를 거부하면 계정을 교체하지 않는다. 강제 종료는 하지 않는다. 같은 인증 저장소를 쓰는 CLI에도 계정 변경이 적용된다.

계정 삭제는 이 앱에 저장된 로그인만 제거한다. Codex 로그아웃이나 구독 취소가 아니다. 등록 정보는 `~/Library/Application Support/oh-my-usage/`에 저장하며 로그인 파일 권한은 `0600`, 계정 폴더는 `0700`이다. Codex와 동일한 파일 기반 인증을 사용한다. 토큰을 별도 서버에 보내지 않는다.

## DMG 만들기

```sh
sh build-dmg.sh
```

`build/oh-my-usage-0.1-arm64.dmg`를 열어 앱을 **Applications** 폴더로 드래그한다. 계정 정보는 DMG에 포함하지 않는다.

현재는 ad-hoc 서명된 개인용 빌드다. 다른 Mac에 배포할 때 Gatekeeper 경고 없이 설치하려면 Apple Developer ID 서명과 공증이 필요하다.

## 범위

macOS 14 이상, Apple Silicon. 설치된 Codex(`com.openai.codex`)와 ChatGPT 파일 기반 로그인이 필요하다. Keychain 전용 인증/사용자 지정 CODEX_HOME은 지원하지 않는다. 3계정일 때 실제 메뉴바 높이에 맞춰 최대 32pt 높이·9pt 글씨를 사용한다. 높이가 22pt인 화면에서는 더 작은 글씨로 표시한다.

현재 앱 `26.924.22138`, CLI `0.158.0-alpha.2.1`을 기준으로 구현했다. 사용량은 공식 app-server 프로토콜로 조회한다. Pro 표시는 `prolite → Pro $100`, `pro → Pro $200`으로 구분하며, 금액은 요금제 식별용 미국 달러 기준 가격이다. 그 외 요금제도 표시하며 서버가 주간 한도를 제공하지 않으면 잔여량은 `—`로 표시한다. 계정 전환 이후에는 파일의 계정 일치 여부를 확인하며, 앱 내부 화면의 로그인 상태까지 조회하는 공개 API는 사용하지 않는다.

## 검사

```sh
mkdir -p build
xcrun swiftc -swift-version 5 Core.swift Tests.swift -o build/core-tests
build/core-tests
```

테스트는 가짜 계정 데이터만 사용하며 실제 로그인 정보나 네트워크를 사용하지 않는다.

근거: [OpenAI App Server](https://learn.chatgpt.com/docs/app-server), [Codex 인증](https://learn.chatgpt.com/docs/auth).
