FROM docker.io/library/alpine:3.20
RUN apk add --no-cache pgbouncer postgresql16-client \
 && adduser -D -H -s /sbin/nologin pgbouncer
USER pgbouncer
EXPOSE 6432
CMD ["pgbouncer", "/etc/pgbouncer/pgbouncer.ini"]
