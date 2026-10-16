#!/bin/sh
# 템플릿의 ${DB_HOST}를 치환해서 공유 볼륨(/etc/pgbouncer)에 쓴다
set -eu
: "${DB_HOST:?DB_HOST is required}"

sed "s/\${DB_HOST}/${DB_HOST}/g" /templates/pgbouncer.ini.tmpl > /etc/pgbouncer/pgbouncer.ini.tmp
mv /etc/pgbouncer/pgbouncer.ini.tmp /etc/pgbouncer/pgbouncer.ini
cp /templates/userlist.txt /etc/pgbouncer/userlist.txt
chmod 644 /etc/pgbouncer/pgbouncer.ini /etc/pgbouncer/userlist.txt

echo "rendered pgbouncer.ini (DB_HOST=${DB_HOST})"
grep '^appdb' /etc/pgbouncer/pgbouncer.ini
