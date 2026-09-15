#!/usr/bin/env bash
# 훅 분기 검사. bash tests/test_hooks.sh 로 실행. 네트워크 안 씀.
set -u
S="$(cd "$(dirname "$0")/.." && pwd)/scripts/telegram-alarm.sh"
export TMPDIR=$(mktemp -d) HOME=$(mktemp -d) TELEGRAM_BOT_TOKEN=x TELEGRAM_CHAT_ID=1 CLAUDE_CODE_SESSION_ID=test-session
MARK="$TMPDIR/telegram-alarm/test-session"
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$3] got [$2]"; fail=1; fi; }

echo '{"session_id":"test-session","stop_hook_active":false}' | bash "$S" stop 2>"$TMPDIR/err.txt"; rc=$?
check "stop blocks when not sent (exit 2)" "$rc" 2
check "block reason mentions send" "$(grep -c "send" "$TMPDIR/err.txt")" 1

echo '{"session_id":"test-session","stop_hook_active":true}' | bash "$S" stop; check "stop passes when already continuing" "$?" 0

mkdir -p "$(dirname "$MARK")"; : > "$MARK"
echo '{"stop_hook_active":false}' | bash "$S" stop; check "stop passes after send (marker)" "$?" 0
echo '{}' | bash "$S" prompt; check "prompt removes marker" "$([ -f "$MARK" ] && echo present || echo gone)" gone
echo '{"stop_hook_active":false}' | bash "$S" stop 2>/dev/null; check "stop blocks again next turn" "$?" 2

echo '{"stop_hook_active":false}' | env -u TELEGRAM_BOT_TOKEN bash "$S" stop; check "silent pass without config" "$?" 0
env -u TELEGRAM_BOT_TOKEN bash "$S" send x 2>/dev/null; check "send errors without config" "$?" 1

out=$(echo '{}' | bash "$S" session-start)
check "session-start instruction has send command" "$(grep -c "telegram-alarm.sh send" <<<"$out")" 1
check "session-start instruction forbids meta summary" "$(grep -c "메타 서술 금지" <<<"$out")" 1

cd "$TMPDIR"; echo " my-proj " > .claude-project-id
mkdir -p "$HOME/.claude"; echo "yss" > "$HOME/.claude/server-id"
check "prefix uses override files" "$(bash "$S" prefix)" "[yss][my-proj]"
rm .claude-project-id "$HOME/.claude/server-id"; cd "$HOME"
check "prefix is global in HOME" "$(env -u TELEGRAM_BOT_TOKEN bash "$S" prefix)" "[$(hostname -s)][global]"

exit $fail
