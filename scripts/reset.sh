#!/bin/sh
# 실습 초기화: pg-old LOGIN 복구, PgBouncer 대상을 pg-old로 되돌림
set -eu
. "$(dirname "$0")/lib.sh"

compose exec -T pg-old psql -U postgres -d appdb -q -c "ALTER ROLE app LOGIN;"
compose run --rm -T -e DB_HOST=pg-old pgbouncer-config
compose exec -T -e PGPASSWORD=admin pgbouncer \
  psql -h 127.0.0.1 -p 6432 -U admin -d pgbouncer -q -c "RESUME;" -c "RELOAD;" 2>/dev/null || \
compose exec -T -e PGPASSWORD=admin pgbouncer \
  psql -h 127.0.0.1 -p 6432 -U admin -d pgbouncer -q -c "RELOAD;"
echo "reset: pg-old LOGIN, PgBouncer → pg-old"
