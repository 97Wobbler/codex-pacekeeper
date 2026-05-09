# Codex Whiplash PRD

> **작성일**: 2026-05-09
> **작성자**: whchoi / Codex
> **상태**: Draft
> **버전**: v0.1

---

## 1. 배경 및 문제 정의

Codex TUI에는 사용량을 항상 볼 수 있는 하단 HUD가 없어, 기존에는 cmux 실행 환경에서 Codex hooks를 이용해 하단 분리 pane을 생성하고 사용량 알림을 표시하는 방식을 사용했다. 현재 구현은 `~/.codex/config.toml`에서 hooks 기능을 켜고, `~/.codex/hooks.json`의 `SessionStart`, `UserPromptSubmit`, `Stop` 이벤트가 `~/.codex/scripts/codex-cmux-hud.sh`를 호출하는 구조다.

조사 결과, 이 방식은 사용량 표시가 Codex 실행 경로에 직접 연결되어 있다. 특히 prompt 제출 시 cmux CLI 조회, HUD pane 생성/재사용 확인, 상태 파일 쓰기, 사용량 API 캐시 확인, workspace description 갱신이 함께 수행된다. 로그에서는 같은 workspace/surface에서 `session-start`, `prompt-submit`, `stop` 이벤트가 같은 초에 여러 번 중복 실행된 흔적도 확인되었고, `codex-cmux-hud.sh watch` 프로세스가 여러 개 장시간 살아 있는 상태도 확인되었다.

따라서 기존 cmux HUD는 "사용량을 보이게 한다"는 목적은 달성하지만, Codex 입력/응답 흐름에 표시 로직이 섞여 cmux 사용 시 체감 지연을 만들 수 있다. Codex Whiplash는 이 문제를 해결하기 위해 Codex와 독립적으로 실행되는 macOS 메뉴바 앱으로 사용량 상태를 표시하고, 사용량 페이스를 벗어나면 알림을 제공한다.

제품명 Codex Whiplash는 사용량을 따라갈 수 있게 "채찍질한다"는 비유에서 출발한다. 다만 실제 UX는 방해보다 조용한 감시와 적절한 경고를 우선한다.

---

## 2. 목표 및 성공 지표

**목표:**
- Codex 사용량 확인을 Codex hook critical path에서 분리한다.
- macOS 메뉴바와 화면 위 floating HUD에서 5시간/주간 사용량과 reset 시간을 한눈에 확인할 수 있게 한다.
- 현재 시점의 권장 사용량 pace와 실제 사용량을 함께 시각화해 "지금 너무 빨리 쓰고 있는지" 판단할 수 있게 한다.
- 사용량 페이스가 과하거나 한도에 가까워질 때 적절한 알림을 제공한다.
- 기존 cmux HUD 없이도 Codex 사용량 인지가 가능하게 한다.

**성공 지표:**

| 지표 | 현재 | 목표 | 측정 방법 |
|------|------|------|-----------|
| Codex prompt 제출 시 HUD hook 지연 | cmux hook과 사용량 표시 로직이 동기 실행됨 | 사용량 표시로 인한 prompt 제출 지연 0ms | Codex hooks 비활성/경량화 후 비교 |
| 사용량 확인 접근성 | cmux 하단 pane 또는 workspace description 확인 필요 | 메뉴바 또는 floating HUD에서 즉시 확인 | 사용 중 관찰 |
| pace 인지 | cmux HUD의 `used / pace` 막대를 봐야 함 | 5h/wk 권장 사용량과 실제 사용량을 앱 UI에서 즉시 비교 | 화면 HUD와 메뉴 상세 확인 |
| 사용량 데이터 최신성 | 60초 TTL 캐시 기반 | 기본 60초 이내 최신성 | 앱 내부 last refreshed 표시 |
| 백그라운드 리소스 사용 | cmux watch 프로세스 여러 개 가능 | 단일 메뉴바 앱 프로세스 | Activity Monitor / `ps` 확인 |

---

## 3. 사용자 및 페르소나

**주요 사용자:**
- Codex 고빈도 사용자: 여러 프로젝트에서 Codex를 장시간 사용하며 5시간/주간 한도를 의식해야 하는 사용자
- cmux 사용자: Codex를 cmux에서 실행하지만 HUD hook으로 인한 체감 지연을 줄이고 싶은 사용자

**사용자 스토리:**

| 사용자 | 원하는 것 | 이유 |
|--------|-----------|------|
| Codex 고빈도 사용자 | 메뉴바에서 현재 사용량과 reset 시간을 보고 싶다 | 작업 흐름을 끊지 않고 한도 상태를 파악하기 위해 |
| Codex 고빈도 사용자 | 화면 위 HUD에서 현재 권장 사용량 대비 실제 사용량을 계속 보고 싶다 | 지금 더 써도 되는지, 잠시 아껴야 하는지 즉시 판단하기 위해 |
| Codex 고빈도 사용자 | 사용량 페이스가 빠르면 알림을 받고 싶다 | 한도를 너무 빨리 소진하지 않기 위해 |
| cmux 사용자 | Codex hook에 무거운 표시 로직을 두고 싶지 않다 | prompt 제출과 session start가 느려지는 문제를 피하기 위해 |
| 개인 개발자 | 설치와 실행이 단순한 네이티브 앱을 원한다 | 별도 서버나 cmux 의존성 없이 상시 실행하기 위해 |

---

## 4. 요구사항

### 기능 요구사항

| 우선순위 | 요구사항 | 사용자 영향 |
|---------|---------|-------------|
| P0 | macOS 메뉴바에 Codex 사용량 요약을 표시한다 | 항상 사용량 상태를 볼 수 있다 |
| P0 | ChatGPT WHAM usage API에서 5시간/주간 사용량, reset time을 가져온다 | Codex 사용량 상태를 실제 한도 기준으로 확인한다 |
| P0 | `~/.codex/auth.json`의 access token을 사용해 인증한다 | 기존 Codex 로그인 상태를 재사용한다 |
| P0 | 60초 기본 주기로 사용량을 갱신한다 | 과도한 네트워크 호출 없이 충분히 최신 상태를 유지한다 |
| P0 | API 실패 시 마지막 성공 데이터를 유지하고 오류 상태를 표시한다 | 일시적 실패가 앱 사용성을 깨지 않는다 |
| P0 | 메뉴를 열면 상세 사용량, reset까지 남은 시간, last refreshed를 보여준다 | 수치와 상태를 정확히 확인할 수 있다 |
| P0 | 화면 위 floating HUD에 5시간/주간 `actual used`와 `recommended pace`를 함께 표시한다 | 기존 cmux HUD의 핵심 가치를 네이티브 앱으로 대체한다 |
| P1 | 사용량이 설정한 임계치에 도달하면 macOS notification을 보낸다 | 한도 접근을 놓치지 않는다 |
| P1 | 사용량 페이스를 계산해 현재 사용량이 권장 페이스보다 얼마나 앞서거나 뒤처지는지 표시한다 | 단순 잔량보다 사용 속도를 판단할 수 있다 |
| P1 | 메뉴에서 refresh now, pause, quit을 제공한다 | 사용자가 앱 동작을 직접 제어할 수 있다 |
| P1 | 사용자 설정으로 polling interval과 알림 임계치를 조정한다 | 개인 사용 패턴에 맞출 수 있다 |
| P2 | Codex Running/Idle 상태를 선택적으로 표시한다 | Codex가 현재 작업 중인지 메뉴바에서 파악할 수 있다 |
| P2 | 간단한 애니메이션 또는 색상 변화로 사용량 압박을 표현한다 | RunCat류의 glanceable feedback을 제공한다 |

### Out-of-scope

- Codex 자체의 rate limit 정책 변경
- Codex CLI/TUI 내부 HUD 구현
- cmux pane 자동 생성 기능 유지 또는 확장
- 여러 OpenAI 계정 동시 관리
- 팀 단위 사용량 공유
- App Store 배포 및 결제

### 비기능 요구사항

| 분류 | 요구사항 | 기준 |
|------|----------|------|
| 성능 | 메뉴바 앱은 Codex prompt 제출 경로와 독립적으로 동작해야 한다 | Codex hooks 없이 사용 가능 |
| 리소스 | 백그라운드 CPU 사용량은 낮아야 한다 | idle 상태에서 지속 CPU 사용이 체감되지 않을 것 |
| 네트워크 | 사용량 API 호출은 rate-friendly해야 한다 | 기본 60초 이상 polling interval |
| 보안 | access token은 앱 내부에 별도 저장하지 않는다 | `~/.codex/auth.json`을 읽기 전용으로 사용 |
| 복원력 | API 실패, token 부재, JSON schema 변화에 graceful degradation한다 | 앱 crash 없이 오류 상태 표시 |
| 호환성 | 최신 macOS에서 네이티브 메뉴바 앱으로 동작한다 | SwiftUI `MenuBarExtra` 기반 |

---

## 5. UX 흐름

### 핵심 화면

| 화면 | 설명 | 주요 액션 |
|------|------|-----------|
| 메뉴바 아이템 | 짧은 텍스트 또는 아이콘으로 5시간 사용량 상태를 표시 | glance |
| floating HUD | 화면 위에 작게 떠 있는 패널로 5h/wk 실제 사용량과 권장 pace를 비교 표시 | glance, drag, hide |
| 드롭다운 메뉴 | 5시간/주간 사용량, pace, reset, last refreshed 표시 | refresh, pause, settings, quit |
| 설정 화면 | polling interval, 알림 임계치, 표시 형식 설정 | 저장 |
| 알림 | 임계치 초과 또는 reset 임박 등 이벤트 전달 | 클릭 시 앱 메뉴 또는 설정 열기 |

### 메뉴바 표시 예시

- 기본: `CW 5h 7%`
- 압박 상태: `CW 5h 82%`
- API 오류: `CW ?`
- paused: `CW paused`

색상 기준:
- 정상: 초록 또는 기본 시스템 색상
- 주의: 노랑, 사용량 또는 페이스가 주의 임계치 초과
- 위험: 빨강, 사용량 또는 페이스가 위험 임계치 초과

### Floating HUD 표시 예시

기존 cmux HUD의 핵심 표현을 네이티브 overlay로 옮긴다. 단순 잔량보다 "현재 시점에 이 정도까지 써도 되는가"를 먼저 보여준다.

- `5h actual 12% / pace 37% · 3h08m`
- `wk actual 44% / pace 52% · 2d14h`
- 실제 사용량이 권장 pace보다 10%p 이내면 정상
- 실제 사용량이 권장 pace보다 10-20%p 앞서면 주의
- 실제 사용량이 권장 pace보다 20%p 이상 앞서면 위험

시각화는 막대 하나에 두 값을 함께 표시한다. 권장 pace 지점을 기준선 또는 배경 구간으로 보여주고, 실제 used 값을 전경 진행률로 표시한다.

### 사용자 흐름

초기 실행:
1. 앱 실행
2. `~/.codex/auth.json` 존재 여부 확인
3. token이 있으면 사용량 조회
4. 메뉴바에 요약 표시
5. 메뉴 드롭다운에서 상세 상태 확인

사용량 경고:
1. 백그라운드 poll 실행
2. 5시간 또는 주간 사용량이 설정 임계치 초과
3. 같은 임계치에 대해 중복 알림을 제한
4. macOS notification 표시

API 실패:
1. API 호출 실패
2. 마지막 성공 캐시가 있으면 stale 표시와 함께 유지
3. 캐시도 없으면 `usage unavailable` 표시

---

## 6. 기술 고려사항

### 권장 스택

- Swift
- SwiftUI
- `MenuBarExtra`
- `URLSession`
- `UserNotifications`
- `Codable`
- optional: `ServiceManagement` for launch at login

### 데이터 소스

기본 데이터 소스는 현재 cmux HUD에서 사용하던 API와 동일하게 둔다.

- Auth file: `~/.codex/auth.json`
- Usage endpoint: `https://chatgpt.com/backend-api/wham/usage`
- Cache: 앱 내부 메모리 + 선택적으로 `~/Library/Application Support/Codex Whiplash/usage-cache.json`

### 예상 usage 모델

앱은 API 응답에서 다음 정보를 추출한다.

- `rate_limit.primary_window.used_percent`
- `rate_limit.primary_window.reset_at`
- `rate_limit.primary_window.limit_window_seconds`
- `rate_limit.secondary_window.used_percent`
- `rate_limit.secondary_window.reset_at`
- `rate_limit.secondary_window.limit_window_seconds`

필드명이 변할 수 있으므로 decode 실패 시 원문 일부를 debug log에 남기되 access token은 절대 기록하지 않는다.

### Pace 계산

현재 cmux HUD의 계산 방식을 초기 기준으로 사용한다.

- window start = reset_at - limit_window_seconds
- elapsed percent = `(now - window_start) / limit_window_seconds * 100`
- used percent가 elapsed percent보다 많이 앞서면 과소비 상태로 본다.
- UI label에서는 elapsed percent를 `pace` 또는 `recommended`로 표현한다.
- 5시간 primary window와 주간 secondary window 모두 같은 방식으로 계산한다.
- 기존 `codex-cmux-hud.sh`의 `used % / pace % / remaining time` 표현을 MVP의 동작 기준으로 삼는다.

### 기존 cmux hook과의 관계

Codex Whiplash 도입 후 권장 방향:

1. cmux 하단 split HUD는 비활성화한다.
2. Codex hooks는 가능하면 끈다.
3. Running/Idle 상태 표시가 필요하면 hook은 상태 파일만 쓰는 초경량 모드로 유지한다.

초기 MVP에서는 Codex hook 연동을 포함하지 않는다. 사용량 표시는 독립 앱만으로 완성한다.

---

## 7. 알림 정책

기본 알림 임계치:

| 대상 | 주의 | 위험 |
|------|------|------|
| 5시간 window | used >= 70% 또는 pace + 20%p | used >= 90% |
| 주간 window | used >= 70% 또는 pace + 20%p | used >= 90% |

중복 방지:
- 같은 window와 같은 임계치 알림은 reset 전까지 1회만 보낸다.
- 사용자가 refresh를 눌러도 같은 임계치 알림은 반복하지 않는다.
- reset이 지나면 알림 상태를 초기화한다.

---

## 8. MVP 범위

### MVP에 포함

- SwiftUI 메뉴바 앱 scaffold
- `~/.codex/auth.json` token 읽기
- usage API polling
- 메뉴바 요약 표시
- 화면 위 floating HUD 표시
- 5시간/주간 `actual used`와 `recommended pace` 비교 시각화
- 드롭다운 상세 표시
- stale/error 상태 처리
- 5시간/주간 사용량 임계치 알림
- refresh now / pause / quit

### MVP에서 제외

- launch at login
- 시각적 애니메이션
- Codex Running/Idle hook 연동
- multi-account
- App Store packaging

---

## 9. 마일스톤

| 마일스톤 | 산출물 | 기준 |
|----------|--------|------|
| M1: 프로젝트 생성 | SwiftUI 메뉴바 앱 기본 구조 | 앱 실행 시 메뉴바 아이템 표시 |
| M2: 사용량 조회 | auth 읽기 + usage API client | 실제 5h/wk 사용량 표시 |
| M3: 상태 UX | stale/error/loading/paused 상태 | API 실패에도 crash 없음 |
| M4: 알림 | 임계치 기반 notification | 중복 알림 제한 |
| M5: 기존 hook 정리 가이드 | cmux HUD 비활성화 안내 문서 | Codex hook 지연 제거 방향 명확화 |

---

## 10. 미결 사항

- [ ] 앱 최소 지원 macOS 버전
- [ ] 메뉴바 표시를 텍스트 중심으로 할지, 아이콘/애니메이션 중심으로 할지
- [ ] App Sandbox 사용 여부
- [ ] launch at login을 MVP에 포함할지
- [ ] `~/.codex/auth.json` schema 변경에 대비한 fallback 수준
- [ ] Codex Running/Idle 상태 표시를 향후 hook 경량 모드로 붙일지

---

## 11. 변경 이력

| 날짜 | 버전 | 변경 내용 | 작성자 |
|------|------|-----------|--------|
| 2026-05-09 | v0.1 | 최초 PRD 작성 | whchoi / Codex |
