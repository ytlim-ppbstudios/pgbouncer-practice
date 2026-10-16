#!/bin/sh
# 따닥: PgBouncer 대상을 pg-old → pg-new로 교체
#   ./scripts/swap.sh          미팅 결론 절차. 순단 구간 요청은 실패
#   ./scripts/swap.sh --pause  PAUSE/RESUME으로 감싸서 순단 구간 요청을 대기시킴
# CDC_WAIT_SEC: CDC 잔여분 반영 대기 시간 흉내 (기본 1초)
set -eu
. "$(dirname "$0")/lib.sh"

MODE=fail
[ "${1:-}" = "--pause" ] && MODE=pause
CDC_WAIT_SEC=${CDC_WAIT_SEC:-1}
DRAIN_TIMEOUT_SEC=${DRAIN_TIMEOUT_SEC:-2}

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
T0=$(now)
step() { printf '[+%6.3fs] %s\n' "$(echo "$(now) - $T0" | bc)" "$*"; }

old_psql() { compose exec -T pg-old psql -U postgres -d appdb -Atq -c "$1"; }
admin() { compose exec -T -e PGPASSWORD=admin pgbouncer psql -h 127.0.0.1 -p 6432 -U admin -d pgbouncer -Atq -c "$1"; }
app_sessions() { old_psql "SELECT count(*) FROM pg_stat_activity WHERE usename = 'app';"; }

step "mode=$MODE, 현재 대상: $(admin 'SHOW DATABASES;' | awk -F'|' '$1=="appdb"{print $2}')"

if [ "$MODE" = pause ]; then
  step "PAUSE appdb (진행 중 트랜잭션 끝나길 기다린 뒤 서버 커넥션 해제, 새 요청은 대기)"
  admin "PAUSE appdb;"
fi

step "1. pg-old: ALTER ROLE app NOLOGIN (새 로그인 거부)"
old_psql "ALTER ROLE app NOLOGIN;"

step "2. pg-old: app 세션 드레인 (현재 $(app_sessions)개)"
old_psql "SELECT count(pg_terminate_backend(pid)) FROM pg_stat_activity WHERE usename = 'app' AND state = 'idle';" >/dev/null
deadline=$(echo "$(now) + $DRAIN_TIMEOUT_SEC" | bc)
while [ "$(app_sessions)" -gt 0 ] && [ "$(echo "$(now) < $deadline" | bc)" -eq 1 ]; do
  old_psql "SELECT count(pg_terminate_backend(pid)) FROM pg_stat_activity WHERE usename = 'app' AND state = 'idle';" >/dev/null
done
old_psql "SELECT count(pg_terminate_backend(pid)) FROM pg_stat_activity WHERE usename = 'app';" >/dev/null
step "   남은 app 세션: $(app_sessions)개"

step "3. CDC 잔여분 반영 대기 (흉내: ${CDC_WAIT_SEC}s)"
sleep "$CDC_WAIT_SEC"

step "4. 사이드카로 공유 볼륨의 pgbouncer.ini 치환 (DB_HOST=pg-new)"
compose run --rm -T -e DB_HOST=pg-new pgbouncer-config >/dev/null

step "5. RELOAD"
admin "RELOAD;"

if [ "$MODE" = pause ]; then
  step "RESUME appdb"
  admin "RESUME appdb;"
fi

step "완료, 현재 대상: $(admin 'SHOW DATABASES;' | awk -F'|' '$1=="appdb"{print $2}')"
