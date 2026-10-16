// PgBouncer(localhost:6432)로 SELECT 1을 반복 실행하고 결과·지연·에러를 찍는다
// CONCURRENCY: 동시에 도는 루프 수, INTERVAL_MS: 루프마다 쿼리 간격
import pg from 'pg';

const CONCURRENCY = Number(process.env.CONCURRENCY ?? 1);
const INTERVAL_MS = Number(process.env.INTERVAL_MS ?? 500);
const HOLD_MS = Number(process.env.HOLD_MS ?? 0); // pg_sleep으로 커넥션 점유 시간

const pool = new pg.Pool({
  host: process.env.PGHOST ?? 'localhost',
  port: Number(process.env.PGPORT ?? 6432),
  user: 'app',
  password: 'app',
  database: 'appdb',
  max: CONCURRENCY,
  connectionTimeoutMillis: 5000,
});
pool.on('error', (err) => console.error(`[pool] ${err.message}`));

const sql =
  HOLD_MS > 0
    ? `SELECT 1 AS ok, current_setting('cluster_name') AS backend, pg_sleep(${HOLD_MS / 1000})`
    : `SELECT 1 AS ok, current_setting('cluster_name') AS backend`;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function loop(id) {
  for (;;) {
    const started = Date.now();
    const ts = new Date().toISOString().slice(11, 23);
    try {
      const { rows } = await pool.query(sql);
      console.log(`${ts} #${id} ok=${rows[0].ok} backend=${rows[0].backend} ${Date.now() - started}ms`);
    } catch (err) {
      console.log(`${ts} #${id} ERROR ${err.code ?? ''} ${err.message} ${Date.now() - started}ms`);
    }
    await sleep(INTERVAL_MS);
  }
}

process.on('SIGINT', async () => {
  await pool.end();
  process.exit(0);
});

console.log(`CONCURRENCY=${CONCURRENCY} INTERVAL_MS=${INTERVAL_MS} HOLD_MS=${HOLD_MS}`);
for (let i = 1; i <= CONCURRENCY; i++) loop(i);
