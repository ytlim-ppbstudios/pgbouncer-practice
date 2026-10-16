# pgbouncer-practice

PgBouncer 실습 레포. 브랜치를 단계별로 쌓아 두었다 (stacked).

| 단계 | 브랜치 | 내용 |
|---|---|---|
| 1 | `feat/1-basic-pgbouncer` | PG 2개 + PgBouncer 기본 구성, node-pg 클라이언트로 `SELECT 1` |
| 2 | `feat/2-pgbouncer-backend-swap` | PgBouncer 대상 교체(따닥): 설정 치환 → `RELOAD`, `PAUSE`/`RESUME` |

## 1단계: 기본 PgBouncer

```
client(node-pg) ──▶ pgbouncer:6432 ──▶ pg-old:5432   (pg-new는 아직 아무도 안 붙음)
                       ▲
     공유 볼륨 /etc/pgbouncer (pgbouncer.ini, userlist.txt)
                       ▲
     pgbouncer-config (템플릿 렌더링 후 종료)
```

- `pg-old`: 이관 전 DB(7계정 역할), `pg-new`: 이관 대상 DB(2계정 역할). `cluster_name`으로 구분
- `pgbouncer-config`: ECS 사이드카처럼 `config/pgbouncer.ini.tmpl`의 `${DB_HOST}`를 치환해 공유 볼륨에 쓰고 종료. `pgbouncer`는 이 컨테이너가 성공 종료된 뒤 기동(`service_completed_successfully`, ECS의 `dependsOn: SUCCESS`와 같은 자리)
- 풀 모드 `transaction`, `default_pool_size = 5`

### 실행

```bash
docker compose up -d --build        # podman이면 podman compose
cd client && npm install && npm start
# 09:21:10.167 #1 ok=1 backend=pg-old 3ms
```

클라이언트 옵션(환경변수)

| 변수 | 기본값 | 설명 |
|---|---|---|
| `CONCURRENCY` | 1 | 동시에 도는 쿼리 루프 수 (= node-pg 풀 크기) |
| `INTERVAL_MS` | 500 | 루프마다 쿼리 간격 |
| `HOLD_MS` | 0 | `pg_sleep`으로 서버 커넥션을 붙잡는 시간 |

### 해볼 것

1. 관리 콘솔 보기
   ```bash
   ./scripts/admin.sh "SHOW POOLS;"
   ./scripts/admin.sh "SHOW SERVERS;"   # 실제 PG 커넥션 (pg-old 쪽)
   ./scripts/admin.sh "SHOW CLIENTS;"
   ```
2. 풀보다 많은 클라이언트 붙이기 → 대기 관찰
   ```bash
   CONCURRENCY=8 HOLD_MS=500 INTERVAL_MS=0 npm start
   ./scripts/admin.sh "SHOW POOLS;"    # cl_active 5, cl_waiting 3, sv_active 5
   ```
   PG 커넥션은 5개로 고정되고, 나머지 클라이언트는 PgBouncer에서 줄을 선다. 지연이 `HOLD_MS`보다 길게 찍히는 게 대기 시간
3. PG 쪽에서 실제 세션 수 확인
   ```bash
   docker compose exec pg-old psql -U postgres -d appdb \
     -c "SELECT usename, client_addr, state FROM pg_stat_activity WHERE usename = 'app';"
   ```

## 2단계: 따닥 (PgBouncer 대상 교체)

DB 이관(7계정 → 2계정) 전환 미팅 결론을 그대로 흉내 낸다. 앱은 PgBouncer에만 붙어 있고, 어느 DB로 갈지는 PgBouncer 설정이 정한다. CNAME처럼 DNS 반영을 기다릴 필요가 없다.

```
전: client ──▶ pgbouncer ──▶ pg-old        후: client ──▶ pgbouncer ──▶ pg-new
```

`./scripts/swap.sh` 절차

1. pg-old `ALTER ROLE app NOLOGIN`: 새 로그인 거부, 기존 세션은 유지
2. pg-old app 세션 드레인: 유휴 세션부터 종료, `DRAIN_TIMEOUT_SEC`(2초) 넘으면 전부 종료 → PgBouncer의 pg-old 재연결 실패
3. CDC 잔여분 반영 대기: `CDC_WAIT_SEC`(1초) sleep으로 흉내
4. 사이드카(`pgbouncer-config`)를 `DB_HOST=pg-new`로 다시 돌려 공유 볼륨의 `pgbouncer.ini` 치환
5. `RELOAD` → PgBouncer가 pg-new로 새 서버 커넥션을 맺음

2~5가 순단 구간. pg-new 쪽은 교체 전까지 연결 자체가 없어서 `NOLOGIN` 토글이 필요 없다.

### 해볼 것

터미널 두 개를 띄운다.

```bash
# 터미널 A
cd client && CONCURRENCY=3 INTERVAL_MS=100 npm start

# 터미널 B
./scripts/swap.sh            # 실패 모드
./scripts/reset.sh           # pg-old로 되돌리기
./scripts/swap.sh --pause    # 대기 모드
./scripts/reset.sh
```

로컬(podman) 실측 예시

| 모드 | 순단 중 요청 | 클라이언트에서 보이는 것 |
|---|---|---|
| `swap.sh` | 바로 실패 | `28000 role "app" is not permitted to log in` → `08P01 server login has been failing` 약 2.3초 동안 63건, 이후 `backend=pg-new` |
| `swap.sh --pause` | PgBouncer에서 대기 | 에러 0건, 쿼리 하나가 약 3.1초 걸린 뒤 `backend=pg-new` |

- 시간은 대부분 `compose exec`/`run` 오버헤드(호출당 0.4초 안팎)와 `CDC_WAIT_SEC`. 실제 교체(`RELOAD`) 자체는 순간
- `--pause`: `PAUSE appdb`가 진행 중 트랜잭션이 끝나길 기다린 뒤 서버 커넥션을 놓고, 그동안 들어온 요청은 `RESUME`까지 줄을 선다. 클라이언트의 `connectionTimeoutMillis`(5초)나 PgBouncer `query_wait_timeout`(기본 120초)보다 길어지면 그때 실패

### 함정: `server_login_retry`

PgBouncer는 서버 로그인이 한 번 실패하면 `server_login_retry`(기본 15초) 동안 재시도하지 않고 클라이언트에 `server login has been failing`을 돌려준다. 1번 `NOLOGIN` 때문에 로그인이 실패한 상태에서 대상을 바꾸면, `RELOAD`를 해도 이 시간이 지나야 pg-new에 붙는다. 기본값이면 순단이 15초까지 늘어난다.

그래서 `config/pgbouncer.ini.tmpl`에 `server_login_retry = 1`을 넣어 두었다. 이 줄을 지우고 `docker compose up -d --force-recreate`로 다시 띄운 뒤 `swap.sh`를 돌려 보면 차이가 보인다. 운영 전환에서도 같이 챙겨야 하는 값.

### 정리

```bash
docker compose down -v
```
