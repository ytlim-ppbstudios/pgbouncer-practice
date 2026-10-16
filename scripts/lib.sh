# 공통: docker가 없으면 podman compose 사용
cd "$(dirname "$0")/.."
if command -v docker >/dev/null 2>&1; then
  compose() { docker compose "$@"; }
else
  compose() { PODMAN_COMPOSE_WARNING_LOGS=false podman compose "$@"; }
fi
