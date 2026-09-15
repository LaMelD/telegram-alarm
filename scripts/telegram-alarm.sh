#!/usr/bin/env bash
# telegram-alarm: Claude Code 작업 완료·권한 대기 알림을 텔레그램으로 보낸다.
#
#   telegram-alarm.sh send "요약"     Claude가 호출. [server][project] 프리픽스를 붙여 전송
#   telegram-alarm.sh session-start  SessionStart 훅. 전송 지시문을 컨텍스트에 주입
#   telegram-alarm.sh prompt         UserPromptSubmit 훅. 이번 턴 전송 마커 삭제
#   telegram-alarm.sh stop           Stop 훅. 미전송이면 종료를 막고 전송을 요구
#   telegram-alarm.sh notify         Notification 훅. 권한 대기 메시지를 바로 전송
#   telegram-alarm.sh prefix         이 서버·디렉토리에서 붙을 프리픽스 출력
#
# 필요: bash, curl. 환경변수 TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID.
# 프리픽스 덮어쓰기: ~/.claude/server-id (server), ./.claude-project-id (project)
set -u
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARK="${TMPDIR:-/tmp}/telegram-alarm/${CLAUDE_CODE_SESSION_ID:-default}"
CMD="${1:-}"
case "$CMD" in
  send|session-start|prompt|stop|notify|prefix) ;;
  *) sed -n '2,12p' "$0" >&2; exit 1 ;;
esac

prefix() {
  local server project top
  if [ -f ~/.claude/server-id ]; then server=$(tr -d '[:space:]' < ~/.claude/server-id)
  else server=$(hostname -s); fi
  if [ -f .claude-project-id ]; then project=$(tr -d '[:space:]' < .claude-project-id)
  elif top=$(git rev-parse --show-toplevel 2>/dev/null); then project=$(basename "$top")
  elif [ "$PWD" = "$HOME" ]; then project=global
  else project=$(basename "$PWD"); fi
  echo "[$server][$project]"
}

send() {
  local body res
  body="$(prefix) $1"
  body="${body:0:4096}"  # 텔레그램 메시지 길이 상한
  res=$(curl -sS --max-time 15 --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
        --data-urlencode "text=$body" "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage") \
    || { echo "telegram-alarm: 전송 실패 (curl)" >&2; return 1; }
  case "$res" in
    *'"ok":true'*) return 0 ;;
    *) echo "telegram-alarm: 전송 실패: $res" >&2; return 1 ;;
  esac
}

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
  case "$CMD" in
    send) echo "telegram-alarm: TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID 가 설정되지 않았다" >&2; exit 1 ;;
    prefix) ;;
    *) exit 0 ;;  # 훅은 조용히 통과
  esac
fi

case "$CMD" in
  send)
    shift; text="$*"
    [ -z "$text" ] && text=$(cat)
    [ -z "$text" ] && { echo "telegram-alarm: 보낼 내용이 없다" >&2; exit 1; }
    send "$text" || exit 1
    mkdir -p "$(dirname "$MARK")" && : > "$MARK"
    echo "telegram-alarm: 전송 완료"
    ;;
  session-start)
    cat <<CTX
# telegram-alarm (필수)
- 사용자의 요청에 대한 작업이 완료되면, 최종 응답을 하기 전에 반드시 아래 명령으로 결과를 텔레그램에 전송한다. 선택이 아니라 필수다.
- 전송 없이 작업 완료를 보고하지 마라. 전송하지 않으면 Stop 훅이 종료를 막는다.
- 명령: bash $SELF send "<내용>"
- 내용은 사용자가 터미널을 보지 않아도 결과를 알 수 있게 쓴다. "답변함", "완료함" 같은 메타 서술 금지. 답변·결과의 핵심 내용 자체를 담는다.
- 질문에 답한 경우: 답의 핵심을 3~5줄로 요약한다.
- 작업한 경우: 무엇을 바꿨고 결과가 무엇인지, 실패·미완료·사용자 확인이 필요한 사항을 쓴다.
- 한국어로 쓴다. [server][project] 프리픽스는 스크립트가 붙이므로 쓰지 않는다.
CTX
    ;;
  prefix)
    prefix
    ;;
  prompt)
    rm -f "$MARK"
    ;;
  stop)
    [ -f "$MARK" ] && exit 0
    grep -Eq '"stop_hook_active": *true' && exit 0  # 이미 훅 때문에 이어가는 중이면 무한루프 방지
    echo "텔레그램 요약을 아직 보내지 않았다. 지금 bash $SELF send \"<요약>\" 을 실행한 뒤 종료하라." >&2
    exit 2
    ;;
  notify)
    msg=$(sed -n 's/.*"message":"\([^"]*\)".*/\1/p')
    send "🔔 ${msg:-권한 승인 대기 중}"
    ;;
esac
