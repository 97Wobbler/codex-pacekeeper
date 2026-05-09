# Codex Pacekeeper PRD

> **작성일**: 2026-05-09  
> **작성자**: whchoi / Codex  
> **상태**: Draft  
> **버전**: v0.1

---

## 1. 배경 및 문제 정의

Codex를 오래 쓰다 보면 5시간 window와 주간 window의 사용량을 계속 의식해야 한다. 기존에는 cmux 하단 HUD가 `actual used`와 현재 시점의 `recommended pace`를 비교해 보여줬지만, 이 방식은 Codex hook과 cmux pane 생성/갱신 로직에 묶여 prompt 제출 경로에 부담을 줄 수 있다.

Codex Pacekeeper는 이 문제를 macOS 네이티브 앱으로 분리한다. 메뉴바와 화면 위 floating HUD에서 Codex 사용량을 마라톤 pacemaker처럼 조용히 보여주고, 사용자가 현재 페이스를 유지해도 되는지 즉시 판단하게 한다.

핵심 질문은 다음 하나다.

> 지금 내 Codex 사용량은 권장 페이스보다 앞서 있는가, 맞춰 가고 있는가, 여유가 있는가?

제품명 `Pacekeeper`는 기존 `Whiplash`의 강한 압박감을 버리고, 장거리 러닝의 pacer처럼 사용자가 끝까지 안정적으로 완주하도록 돕는 방향을 담는다.

---

## 2. 제품 원칙

- **Pace first**: 단순 잔량보다 현재 시점의 권장 페이스 대비 실제 사용량을 먼저 보여준다.
- **Calm by default**: 평상시에는 작고 조용하며, 위험 구간에서만 강도가 올라간다.
- **Glanceable, then inspectable**: floating HUD는 한눈 판단용이고, 정확한 수치는 hover/click/menu에서 확인한다.
- **No heavy hooks**: Codex prompt 제출 경로에는 무거운 표시, 네트워크, pane 관리 로직을 두지 않는다.
- **No gamification**: 메달, streak, achievement를 만들지 않는다. 목표는 더 쓰게 만드는 것이 아니라 페이스를 지키게 하는 것이다.
- **Pixel-friendly identity**: 16x16, 24x24, 32x16 수준의 간단한 픽셀아트로도 브랜드와 상태를 표현할 수 있어야 한다.

---

## 3. 목표 및 성공 지표

### 목표

- Codex 사용량 확인을 Codex hook critical path에서 분리한다.
- macOS 메뉴바와 화면 위 floating HUD에서 5시간/주간 사용량 상태를 즉시 확인할 수 있게 한다.
- `actual used`와 `recommended pace`를 함께 시각화한다.
- 권장 페이스보다 얼마나 앞서거나 뒤처지는지 `pace delta`로 표현한다.
- 사용량이 빠를 때 불안한 경고가 아니라 pacer-style guidance를 제공한다.

### 성공 지표

| 지표 | 현재 | 목표 | 측정 방법 |
|------|------|------|-----------|
| Codex prompt 제출 지연 | cmux HUD hook이 prompt 흐름과 결합됨 | 사용량 표시로 인한 prompt 제출 지연 0ms | Codex hooks 비활성/경량화 후 비교 |
| pace 인지 | cmux pane 또는 workspace description 확인 필요 | floating HUD에서 1초 안에 판단 | 사용 중 관찰 |
| 데이터 최신성 | 기존 60초 TTL 캐시 | 기본 60초 이내 최신성 | last refreshed 표시 |
| glance 이해도 | `used / pace` 텍스트를 읽어야 함 | ahead / steady / behind 상태를 즉시 인지 | 자체 사용 테스트 |
| 방해도 | HUD pane과 watcher가 작업 흐름에 개입 | overlay는 숨김/드래그/접기 가능 | 사용자 설정 및 관찰 |

---

## 4. 사용자 및 페르소나

### 주요 사용자

- Codex 고빈도 사용자: 여러 프로젝트에서 Codex를 장시간 사용하며 5시간/주간 한도를 의식해야 하는 사용자
- cmux 사용자: 기존 cmux HUD의 페이스 표시 가치는 유지하되 hook 지연을 줄이고 싶은 사용자
- 개인 개발자: 별도 서버나 복잡한 대시보드 없이, 항상 보이는 작은 네이티브 도구를 원하는 사용자

### 사용자 스토리

| 사용자 | 원하는 것 | 이유 |
|--------|-----------|------|
| Codex 고빈도 사용자 | 지금 권장 페이스보다 앞서는지 보고 싶다 | 한도를 너무 빨리 소진하지 않기 위해 |
| Codex 고빈도 사용자 | 5시간 window와 주간 window를 동시에 의식하고 싶다 | 짧은 burst와 장기 quota를 함께 관리하기 위해 |
| Codex 고빈도 사용자 | 화면 위 작은 HUD로 계속 보고 싶다 | 터미널이나 메뉴를 열지 않고 판단하기 위해 |
| cmux 사용자 | 기존 cmux HUD의 `used / pace` 가치를 유지하고 싶다 | 이미 이 방식이 사용 판단에 도움이 되었기 때문에 |
| 개인 개발자 | 간단한 픽셀아트 정체성이 있는 앱을 쓰고 싶다 | 유틸리티지만 애착이 가는 도구로 만들기 위해 |

---

## 5. 핵심 개념

### Usage Windows

- **Current Split**: 5시간 primary window
- **Weekly Race**: 주간 secondary window

UI에서는 필요 이상으로 러닝 용어를 남발하지 않는다. 기본 표시는 `5h`, `week`, `actual`, `pace`, `ahead`, `behind`처럼 명확한 언어를 우선한다.

### Recommended Pace

현재 시점까지 이상적으로 사용했어야 하는 비율이다.

```text
window_start = reset_at - limit_window_seconds
recommended_pace = (now - window_start) / limit_window_seconds * 100
```

### Pace Delta

실제 사용량이 권장 페이스보다 얼마나 앞서거나 뒤처졌는지 나타낸다.

```text
pace_delta = actual_used_percent - recommended_pace_percent
```

예:

- `actual 42% / pace 36%` → `+6%p ahead`
- `actual 12% / pace 37%` → `-25%p behind`

### Pace Ratio

내부 판단에는 ratio도 사용할 수 있다.

```text
pace_ratio = actual_used_percent / recommended_pace_percent
```

예:

- `1.00x`: 정확히 on pace
- `0.80x`: 여유 있음
- `1.25x`: 권장보다 빠름

---

## 6. Pace 상태 모델

| 상태 | 조건 예시 | 의미 | UI 톤 |
|------|-----------|------|-------|
| Easy | delta <= -10%p | 권장보다 여유 있음 | 차분한 파랑/녹색 |
| Steady | -10%p < delta <= +10%p | 적정 페이스 | 기본/녹색 |
| Tempo | +10%p < delta <= +20%p | 조금 빠름 | amber |
| Threshold | +20%p < delta <= +35%p | 위험 구간 | orange/red |
| Redline | delta > +35%p 또는 used >= 90% | 지속 불가능 | red, 알림 가능 |

초기 MVP에서는 조건값을 고정해도 된다. 이후 사용자 설정으로 `strict / normal / relaxed` pacing threshold를 제공할 수 있다.

---

## 7. 기능 요구사항

| 우선순위 | 요구사항 | 사용자 영향 |
|---------|---------|-------------|
| P0 | `~/.codex/auth.json`의 access token을 읽는다 | 기존 Codex 로그인 상태를 재사용한다 |
| P0 | ChatGPT WHAM usage API에서 5시간/주간 사용량과 reset time을 가져온다 | 실제 quota 기준으로 표시한다 |
| P0 | 60초 기본 주기로 usage를 갱신한다 | 과도한 호출 없이 충분히 최신 상태를 유지한다 |
| P0 | floating HUD에 5h actual, recommended pace, delta를 표시한다 | 한눈에 페이스를 판단한다 |
| P0 | 메뉴바에 compact 상태를 표시한다 | HUD를 숨겨도 상태를 볼 수 있다 |
| P0 | API 실패 시 마지막 성공 데이터를 stale 상태로 유지한다 | 일시적 실패가 앱 사용성을 깨지 않는다 |
| P0 | refresh now, pause, hide HUD, quit을 제공한다 | 사용자가 앱 동작을 제어한다 |
| P1 | weekly window도 floating HUD 또는 hover detail에서 표시한다 | 단기/장기 페이스를 함께 본다 |
| P1 | Threshold/Redline 진입 시 macOS notification을 보낸다 | 위험 구간을 놓치지 않는다 |
| P1 | HUD 위치를 드래그하고 화면 모서리/가장자리에 스냅한다 | 작업 화면을 가리지 않는다 |
| P1 | hover 시 애니메이션을 멈추고 정확한 수치를 표시한다 | 움직이는 UI를 읽느라 방해받지 않는다 |
| P1 | 간단한 픽셀 runner/flag/track asset을 지원한다 | 제품 정체성이 생긴다 |
| P2 | pace profiles: Even Pace, Front Load, Back Load, Deadline Push | 개인 작업 리듬에 맞춘다 |
| P2 | 최근 5시간 window history를 split chips로 보여준다 | 사용 패턴을 가볍게 회고한다 |
| P2 | Codex Running/Idle 상태를 optional lightweight hook으로 표시한다 | 에이전트 상태 확장의 기반을 둔다 |

---

## 8. UX 설계

### 메뉴바

기본 후보:

- `PK +6`
- `5h +6`
- `5h +6 | W -2`
- `P1.18`

`+6`은 권장 pace보다 6%p 앞서 있다는 뜻이다. 사용자가 raw percent보다 바로 행동 판단을 할 수 있게 한다.

상태:

- Easy: `PK -12`
- Steady: `PK +2`
- Tempo: `PK +16`
- Threshold: `PK +28`
- Redline: `PK +41`
- API 오류: `PK ?`
- paused: `PK paused`

### Floating HUD

MVP 기본형:

```text
5h  +6 ahead
[ actual dot ] ---- [ pace tick ]
42 actual / 36 pace · reset 1h12m
```

축약형:

```text
5h +6
```

확장형:

```text
5h    actual 42% / pace 36%    +6 ahead    1h12m
week  actual 44% / pace 52%    -8 behind   2d14h
```

### Floating HUD Interaction

- Drag: 위치 이동
- Edge snap: 화면 모서리/가장자리에 붙기
- Click: 5h / week / combined 전환
- Hover: 애니메이션 정지, 정확한 수치 표시
- Right click: pause, hide HUD, refresh, settings, quit
- Screen sharing mode: HUD 자동 숨김 또는 메뉴바 전용 모드

### Guidance Copy

경고보다 pacer의 짧은 조언처럼 말한다.

- `Hold this pace`
- `Room to move`
- `Ease up until 14:20`
- `Back on pace in 27m`
- `Next aid station in 42m`
- `Taper recommended`
- `Short efforts only`

---

## 9. 비주얼 아이덴티티

### 방향

Pacekeeper는 전문적인 개발 도구이지만, 작은 픽셀아트 정체성을 가진다. 목표는 귀여움 자체가 아니라 glanceable signal이다.

### 추천 시각 시스템

#### 1. Ghost Pacer + Track Lane

- 흐릿한 marker 또는 runner: recommended pace
- 진한 marker 또는 runner: actual usage
- 둘의 거리: 현재 pace delta
- 색상: 상태 severity

가장 제품 핵심과 잘 맞는다.

#### 2. Two-Tick Mini Gauge

- 32x16 또는 40px wide bar
- 작은 tick: recommended pace
- dot/fill: actual usage
- excess pixels만 amber/red 처리

가장 구현이 쉽고 읽기 좋다.

#### 3. Tiny Pace Runner

- 24x24 runner sprite
- 2-frame jogging loop
- on pace일 때 중앙, ahead일 때 살짝 앞, behind일 때 뒤

브랜드 애착을 만들기 좋다.

#### 4. Pace Flag

- 메뉴바용 작은 pacer flag
- 색상과 기울기로 상태 표시
- runner보다 덜 산만하다.

#### 5. Pacemaker Balloon

- 마라톤 pacer 풍선
- floating HUD에 잘 어울린다.
- `Pacemaker` 이름을 쓸 경우 특히 강력하지만, `Pacekeeper`에서도 사용 가능하다.

### 픽셀아트 제약

- 기본 sprite 크기: 16x16, 24x24, 32x16
- 애니메이션: 2-4 frame
- 평상시 animation off 또는 아주 느린 pulse
- Threshold 이상에서만 blink/pulse 강화
- 색상만으로 상태를 구분하지 않고 위치, tick, 텍스트를 함께 사용

---

## 10. 기술 고려사항

### 권장 스택

- Swift
- SwiftUI
- `MenuBarExtra`
- `NSPanel` 또는 borderless always-on-top window for floating HUD
- `URLSession`
- `UserNotifications`
- `Codable`
- optional: `ServiceManagement` for launch at login

### 데이터 소스

- Auth file: `~/.codex/auth.json`
- Usage endpoint: `https://chatgpt.com/backend-api/wham/usage`
- Cache: 앱 내부 메모리 + 선택적으로 `~/Library/Application Support/Codex Pacekeeper/usage-cache.json`

### 예상 usage 모델

앱은 API 응답에서 다음 정보를 추출한다.

- `rate_limit.primary_window.used_percent`
- `rate_limit.primary_window.reset_at`
- `rate_limit.primary_window.limit_window_seconds`
- `rate_limit.secondary_window.used_percent`
- `rate_limit.secondary_window.reset_at`
- `rate_limit.secondary_window.limit_window_seconds`

필드명이 변할 수 있으므로 decode 실패 시 graceful degradation한다. Debug log에는 access token을 절대 기록하지 않는다.

### 보안

- access token은 앱 내부에 저장하지 않는다.
- `~/.codex/auth.json`은 읽기 전용으로만 사용한다.
- 캐시에는 usage response와 timestamp만 저장한다.
- 민감한 원문 응답 로그는 기본 비활성화한다.

---

## 11. 알림 정책

### 기본 알림

| 대상 | 조건 | 알림 |
|------|------|------|
| 5h Tempo | delta >= +10%p | 알림 없음, HUD amber |
| 5h Threshold | delta >= +20%p | 선택적 알림 |
| 5h Redline | delta >= +35%p 또는 used >= 90% | 알림 |
| week Threshold | delta >= +20%p | 선택적 알림 |
| week Redline | delta >= +35%p 또는 used >= 90% | 알림 |

### 중복 방지

- 같은 window와 같은 상태 알림은 reset 전까지 1회만 보낸다.
- refresh now로 같은 알림을 반복하지 않는다.
- reset이 지나면 알림 상태를 초기화한다.

### 알림 톤

피해야 할 문구:

- `Limit almost exhausted`
- `Warning`
- `You are overusing Codex`

선호 문구:

- `Ease up to stay on pace`
- `Back on pace in 27m`
- `Redline pace. Short efforts only.`

---

## 12. MVP 범위

### MVP에 포함

- SwiftUI macOS menu bar app scaffold
- floating HUD window
- `~/.codex/auth.json` token 읽기
- WHAM usage API polling
- 5h actual / recommended pace / delta 계산
- week actual / recommended pace / delta 계산
- 메뉴바 compact 상태
- floating HUD two-tick gauge
- stale/error/paused 상태
- refresh now / pause / hide HUD / quit
- Threshold/Redline notification

### MVP에서 제외

- App Store 배포
- launch at login
- custom pace profiles
- recent split history
- Codex Running/Idle hook 연동
- multi-provider Claude/Gemini/OpenCode 지원
- multi-agent dashboard
- 복잡한 analytics report

---

## 13. 마일스톤

| 마일스톤 | 산출물 | 기준 |
|----------|--------|------|
| M1: Project scaffold | SwiftUI menu bar app + floating HUD shell | 앱 실행 시 메뉴바와 작은 HUD 표시 |
| M2: Usage client | auth read + WHAM API client | 실제 5h/week usage 표시 |
| M3: Pace model | recommended pace, delta, status 계산 | 기존 cmux HUD와 계산 결과 일치 |
| M4: HUD visualization | two-tick gauge + compact text | actual vs pace를 한눈에 구분 |
| M5: States | loading/stale/error/paused 처리 | API 실패에도 crash 없음 |
| M6: Notifications | Threshold/Redline 알림 | 중복 알림 제한 |
| M7: Pixel identity | runner/flag/track sprite 적용 | low-distraction 상태 표현 |

---

## 14. 미결 사항

- [ ] 제품명을 `Pacekeeper`, `Codex Pacekeeper`, `PaceLine`, `Pacemaker` 중 무엇으로 확정할지
- [ ] 메뉴바 기본 표시를 `PK +6`, `5h +6`, `P1.18` 중 무엇으로 할지
- [ ] floating HUD 기본값을 항상 표시할지, 메뉴바에서 opt-in할지
- [ ] HUD를 screen sharing/presentation mode에서 자동 숨길지
- [ ] 초기 pixel sprite를 runner, flag, track, balloon 중 무엇으로 할지
- [ ] pace threshold를 고정할지, strict/normal/relaxed preset을 둘지
- [ ] weekly recommended pace를 linear로 둘지, 사용자의 작업 리듬을 반영할지
- [ ] 최소 지원 macOS 버전
- [ ] App Sandbox 사용 여부

---

## 15. 참고 메모

기존 cmux HUD의 핵심 동작:

- 5h primary window와 weekly secondary window를 각각 계산한다.
- `recommended pace = elapsed / window` 방식으로 현재 시점의 권장 사용량을 구한다.
- `used % / pace % / remaining time`을 표시한다.
- 막대에서 recommended pace와 actual used를 함께 시각화한다.

Codex Pacekeeper는 이 핵심 가치를 유지하되, cmux pane과 Codex hook에서 분리해 네이티브 메뉴바/floating HUD로 옮긴다.

---

## 16. 변경 이력

| 날짜 | 버전 | 변경 내용 | 작성자 |
|------|------|-----------|--------|
| 2026-05-09 | v0.1 | Pacekeeper 방향으로 PRD 신규 작성 | whchoi / Codex |
