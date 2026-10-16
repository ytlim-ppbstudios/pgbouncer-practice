# pgbouncer-practice

PgBouncer 실습 레포. 브랜치를 단계별로 쌓아 두었다 (stacked).

| 단계 | 브랜치 | 내용 |
|---|---|---|
| 1 | `feat/1-basic-pgbouncer` | PG 2개 + PgBouncer 기본 구성, node-pg 클라이언트로 `SELECT 1` |
| 2 | `feat/2-pgbouncer-backend-swap` | PgBouncer 대상 교체(따닥): 설정 치환 → `RELOAD`, `PAUSE`/`RESUME` |

```bash
git switch feat/1-basic-pgbouncer   # 1단계부터
```
