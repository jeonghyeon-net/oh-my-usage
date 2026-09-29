# 코드 구조

Swift 소스 두 개와 작은 빌드 스크립트로 구성합니다. 외부 패키지, 백엔드, 웹 UI는 없습니다.

| 파일 | 역할 |
| --- | --- |
| `App.swift` | AppKit 메뉴바 렌더링, 기본 메뉴, 계정 목록, 전환, 타이머, 로그인 항목 |
| `Core.swift` | 인증 파일 읽기·저장, 요금제와 한도 파싱, Codex app-server 통신 |
| `Tests.swift` | 가짜 데이터로 파싱·권한·원자적 파일 교체 검증 |
| `build.sh` | arm64 실행 파일, 앱 아이콘, Info.plist, MIT 라이선스, ad-hoc 서명 |
| `build-dmg.sh` | 앱과 Applications 링크를 담은 DMG, SHA-256 체크섬 |
| `Makefile` | 로컬 개발 명령 |

## 사용량 조회

앱은 60초마다 직렬 작업 큐에서 계정별 공식 CLI 보조 프로세스를 잠깐 실행합니다. stdin/stdout JSON-RPC의 `account/rateLimits/read`로 읽으며 모델 작업은 시작하지 않습니다. 메인 계정은 기존 Codex 홈을, 나머지는 이 앱의 계정별 홈을 사용합니다. 인증 파일과 응답 계정이 맞는지 검사합니다.

여러 한도 버킷이 있으면 일반 `codex` 버킷만 사용합니다. `windowDurationMins == 10080`인 한도에서 사용한 비율을 남은 비율로 바꾸고 0–100 범위로 제한합니다. 초기화권은 `rateLimitResetCredits.availableCount`를 읽습니다. 누락된 값은 0으로 만들지 않고 `—`로 표시합니다.

## 표시와 전환

`NSStatusItem`에는 AppKit으로 그린 이미지를 넣고 `NSMenu`로 계정을 관리합니다. 시작 중에도 최종 크기의 투명 이미지를 유지하고 준비가 끝나면 내용을 그립니다. 새로운 웹 뷰나 별도 대시보드를 추가하지 않습니다.

계정 전환은 Codex 정상 종료 → 최신 기존 인증 저장 및 백업 → 선택한 인증 원자적 교체 → Codex 재실행 → 파일의 계정 일치 확인 순서입니다. 실패하면 가능한 경우 백업을 복구하며, 이미 Codex가 실행 중이라 안전하게 복구할 수 없으면 백업을 남깁니다. 앱 내부 세션 화면의 동기화까지 검증하는 방식은 아닙니다.

## 검증 범위

`make test`는 실제 인증·네트워크 없이 테스트합니다. 실제 계정 전환, 브라우저 로그인, 로그인 시 자동 실행, 화면별 메뉴바 렌더링은 별도 수동 확인이 필요합니다. CI는 구성하지 않습니다.

프로토콜 참고: [OpenAI App Server](https://learn.chatgpt.com/docs/app-server), [Codex 인증](https://learn.chatgpt.com/docs/auth).
