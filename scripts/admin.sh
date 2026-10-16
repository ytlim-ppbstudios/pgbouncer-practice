#!/bin/sh
# PgBouncer 관리 콘솔 실행. 예) ./scripts/admin.sh "SHOW POOLS;"
set -eu
. "$(dirname "$0")/lib.sh"
compose exec -T -e PGPASSWORD=admin pgbouncer \
  psql -h 127.0.0.1 -p 6432 -U admin -d pgbouncer -c "${1:-SHOW POOLS;}"
