# 패키징과 수동 배포

GitHub Actions와 CI는 사용하지 않습니다. 패키지 생성과 GitHub 게시를 분리하며 모든 검사는 로컬에서 수행합니다.

## 패키지 만들기

1. `build.sh`의 `CFBundleShortVersionString`과 `CFBundleVersion`을 올립니다. app-server의 클라이언트 버전은 앱 번들에서 읽습니다.
2. `CHANGELOG.md`의 미배포 변경을 날짜와 버전 아래로 옮깁니다.
3. `make check`와 변경에 필요한 수동 검사를 실행합니다.
4. `make package`로 DMG와 SHA-256 파일을 만듭니다.

예를 들어 0.1.0에서는 아래 파일을 만듭니다.

```text
build/oh-my-usage.app
build/oh-my-usage-0.1.0-arm64.dmg
build/oh-my-usage-0.1.0-arm64.dmg.sha256
```

DMG는 앱과 `/Applications` 심볼릭 링크만 담습니다. 앱에는 실행 파일, Info.plist, 아이콘, MIT 라이선스와 코드 서명이 들어갑니다. 계정 폴더와 인증 파일은 패키징 대상이 아닙니다. `build/`는 Git에서 제외합니다.

```sh
codesign --verify --strict build/oh-my-usage.app
hdiutil verify build/oh-my-usage-0.1.0-arm64.dmg
(cd build && shasum -a 256 -c oh-my-usage-0.1.0-arm64.dmg.sha256)
```

DMG를 마운트해서 예상한 두 항목만 있는지 확인하고, 임시 위치로 앱을 복사해 서명과 파일 일치를 확인하세요. 실제 계정 정보가 보이는 화면이나 로그는 배포 자료에 넣지 않습니다.

## GitHub에 게시

소스와 문서를 커밋·푸시한 뒤 그 커밋에 버전 태그를 붙입니다. 공개 버전의 태그나 파일을 덮어쓰지 말고 수정 버전을 올립니다. 아래는 첫 릴리스 예시이며 이후에는 버전을 바꿉니다.

```sh
git tag v0.1.0
git push origin main v0.1.0
gh release create v0.1.0 \
  build/oh-my-usage-0.1.0-arm64.dmg \
  build/oh-my-usage-0.1.0-arm64.dmg.sha256 \
  --verify-tag --draft --title 'v0.1.0' --notes-file build/release-notes.md
```

`build/release-notes.md`에는 해당 버전의 변경, 설치 방법, 지원 플랫폼, 서명 상태, 실제 수행한 검사와 미확인 항목을 작성합니다. 초안의 파일과 설명을 확인한 뒤 게시합니다.

```sh
gh release edit v0.1.0 --draft=false --latest
```

게시 후 업로드된 DMG를 다시 내려받아 체크섬이 로컬 산출물과 같은지 확인합니다. 사용자 컴퓨터에 설치할 때는 기존 유틸리티를 종료하고 앱을 `/Applications/oh-my-usage.app`으로 복사해 실행합니다. Application Support의 계정 폴더는 건드리지 않습니다.

## 서명과 검증 한계

현재 스크립트는 ad-hoc 서명만 합니다. Developer ID 서명과 Apple 공증을 하지 않으므로 다운로드한 앱은 Gatekeeper 승인이 필요할 수 있습니다. 체크섬은 파일 일치 확인용이며 개발자 신원을 보증하지 않습니다.

Developer ID 배포를 도입할 경우 서명·공증에 성공한 결과만 그렇게 표기하고 인증서나 자격 증명을 저장소에 넣지 마세요. 실제로 검사하지 않은 macOS 버전이나 계정 전환·로그인 자동 실행을 검증 완료로 기록하지 않습니다.
