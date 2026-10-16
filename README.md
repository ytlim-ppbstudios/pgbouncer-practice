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

### 정리

```bash
docker compose down -v
```
