# telegram-alarm

Claude Code 작업이 끝나면 Claude가 직접 쓴 결과 요약을 텔레그램으로 보낸다.
권한 승인을 기다리며 멈춰 있을 때도 알림을 보낸다.
모든 메시지 앞에 `[server][project]` 프리픽스가 붙어 어느 서버의 어느 레포에서 온 알림인지 알 수 있다.

```
[yss][myapp] 빌드 스크립트 수정 완료. 테스트 12개 통과. 배포는 아직 안 함.
[yss][myapp] 🔔 Claude needs your permission to use Bash
```

필요한 것은 bash와 curl뿐이다.

## 동작 방식

| 시점 | 훅 | 하는 일 |
|---|---|---|
| 세션 시작 / 재개 / compact | SessionStart | "작업 완료 시 반드시 `send`로 요약 전송" 지시문을 컨텍스트에 주입 |
| 프롬프트 입력 | UserPromptSubmit | 이번 턴의 전송 마커 삭제 |
| 응답 종료 | Stop | 이번 턴에 전송이 없었으면 종료를 막고 전송을 요구. 한 번만 강제하고 무한루프는 막음 |
| 권한 승인 대기 | Notification (`permission_prompt`) | Claude 개입 없이 스크립트가 바로 알림 전송 |

요약 본문은 Claude가 작성한다. 훅은 transcript를 자르지 않는다.
`TELEGRAM_BOT_TOKEN`이 없으면 모든 훅이 조용히 통과한다.

## 프리픽스 규칙

| 항목 | 우선순위 |
|---|---|
| server | `~/.claude/server-id` 파일 내용 → 없으면 `hostname -s` |
| project | `./.claude-project-id` 파일 내용 → git 루트 디렉토리명 → HOME이면 `global` → 현재 디렉토리명 |

현재 위치에서 어떤 프리픽스가 붙는지 확인:

```sh
bash scripts/telegram-alarm.sh prefix
```

## 설치

### 1. 봇 만들기 (한 번만)

1. 텔레그램에서 [@BotFather](https://t.me/BotFather)에게 `/newbot` → 토큰을 받는다.
2. 만든 봇에게 아무 메시지나 보낸다.
3. chat_id 확인:
   ```sh
   curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates" | grep -o '"chat":{"id":[0-9-]*' | head -1
   ```

### 2. 서버마다 환경변수 설정

셸 프로파일(`~/.zshrc`, `~/.bashrc`)에:

```sh
export TELEGRAM_BOT_TOKEN="123456:ABC..."
export TELEGRAM_CHAT_ID="987654321"
```

또는 `~/.claude/settings.json`의 `env` 블록에 넣어도 된다.
서버 별칭을 쓰려면 `echo yss > ~/.claude/server-id`.

### 3. 플러그인 설치

```sh
claude plugin marketplace add LaMelD/telegram-alarm
claude plugin install telegram-alarm@telegram-alarm
```

로컬에서 개발 중이면:

```sh
claude --plugin-dir /path/to/telegram-alarm
```

### 4. 전송 확인

```sh
bash scripts/telegram-alarm.sh send "테스트"
```

## 테스트

```sh
bash tests/test_hooks.sh
```

## 파일

```
.claude-plugin/plugin.json       플러그인 매니페스트
.claude-plugin/marketplace.json  GitHub 마켓플레이스 정의
hooks/hooks.json                 4개 훅 등록
scripts/telegram-alarm.sh        전송 + 훅 처리 (bash, curl)
tests/test_hooks.sh              훅 분기 테스트 (네트워크 불필요)
```
