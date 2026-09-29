# 이미지 출처

| 파일 | 용도 | 출처 |
| --- | --- | --- |
| [cover.png](cover.png) | README 소개 이미지 | Codex 내장 imagegen 도구로 생성, 2026-09-29 |
| [app-icon.png](app-icon.png) | 앱 아이콘 원본 | Codex 내장 imagegen 도구로 생성, 2026-09-29, 투명 배경 |

실제 화면 캡처가 아닙니다. 사용량과 계정은 가상 예시이며 개인 이메일, 인증 정보, OpenAI/Apple 로고를 사용하지 않았습니다. 소개 이미지의 배치와 크기는 제품 콘셉트 표현용입니다. 두 이미지는 이 프로젝트용으로 새로 생성했으며 참고 저장소에서 복사하지 않았습니다.

아이콘은 빌드 시 macOS의 `sips`로 크기별 PNG를 만들고 `iconutil`로 ICNS에 묶습니다. PNG의 투명도는 유지합니다. 생성 원본은 이 폴더에 보관하며, 빌드된 ICNS는 `build/` 아래에만 둡니다. 저장소의 [MIT 라이선스](../../LICENSE)를 적용합니다.

## 소개 이미지 생성 프롬프트

```text
Use case: ads-marketing
Asset type: a wide GitHub README cover image for the open-source macOS app "oh-my-usage".
Primary request: a restrained, beautifully crafted developer-tool product illustration, not a screenshot. Wide 2:1 composition at approximately 2048x1024 pixels.
Scene: quiet deep graphite background with subtle warm light and ample negative space. On the right, one small floating horizontal macOS-inspired dark menu bar fragment contains a compact three-line account usage stack. The first row has a warm yellow rounded highlight and black monospaced text, other rows use soft white monospaced text. This compact vertical stack, rather than a dashboard, is the entire product concept.
Typography: left side, large crisp lowercase title exactly "oh-my-usage"; below it smaller understated text exactly "Your Codex accounts. One menu bar." Use a refined modern sans-serif. On the three menu-bar rows, show exactly "58% Pro $200", "27% Pro $100", and "84% Plus". No other text.
Style: premium editorial product artwork, nearly flat with a subtle sense of depth, precision and simplicity. Yellow is the only accent. Native Mac spirit without an Apple logo or OpenAI logo. No browser windows, no charts, no extra cards, no icons grid, no people, no watermarks, no real account details. Keep all type sharp and readable. This is openly an illustrative cover using fictional usage figures, not a claim to be a real screenshot.
```

## 앱 아이콘 생성 프롬프트

```text
Use case: logo-brand
Asset type: a production macOS application icon for the open-source app oh-my-usage, 1024 by 1024 pixels.
Primary request: one precise, minimal rounded-square graphite tile with three horizontal usage rows stacked vertically, the top row warm yellow and the two lower rows soft white. The rows are small, simple horizontal pill silhouettes with clearly varying lengths, left aligned; each row has a tiny circular account dot at its left. It should instantly evoke three accounts in a menu bar. No letters, numbers, words, percentages or brand logos.
Style: polished native Mac utility icon, almost flat, very subtle surface shading, restrained and timeless, excellent legibility at 16px. The graphite rounded-square occupies roughly 80 percent of the canvas and has generous transparent padding outside its corners. Nothing extends beyond the tile. The only accent is warm yellow matching a selected account highlight.
Background: genuinely transparent outside the icon tile. One centered icon only, no presentation board, no mockup, no external drop shadow, no watermarks.
```
