#!/bin/bash

set -euo pipefail

# ============================================================
# 출력 색상 설정
# ============================================================
# 색상 출력 기본값
NO_COLOR=''
RED=''
CYAN=''
GREEN=''

# 터미널 색상 지원 여부 확인 https://unix.stackexchange.com/a/10065/642181
if [ -t 1 ]; then
    total_colors=$(tput colors)
    if [[ -n "$total_colors" && $total_colors -ge 8 ]]; then
        # 색상 코드 설정 https://stackoverflow.com/a/28938235/18954618
        NO_COLOR='\033[0m'
        RED='\033[0;31m'
        CYAN='\033[0;36m'
        GREEN='\033[0;32m'
    fi
fi

# ============================================================
# 공통 로그/에러 처리
# ============================================================
# 로그/에러 처리 함수
error_log() { echo -e "${RED}오류: $1${NO_COLOR}"; }
info_log() { echo -e "${CYAN}안내: $1${NO_COLOR}"; }
error_exit() {
    error_log "$*"
    exit 1
}

# ============================================================
# 실행 환경 유틸리티
# ============================================================
# CPU 아키텍처 감지
detect_arch() {
    case $(uname -m) in
    x86_64) echo "amd64" ;;
    aarch64 | arm64) echo "arm64" ;;
    armv7l) echo "arm" ;;
    i686 | i386) echo "386" ;;
    *) echo "err" ;;
    esac
}

# OS 감지 https://stackoverflow.com/a/18434831/18954618
detect_os() {
    case $(uname | tr '[:upper:]' '[:lower:]') in
    linux*) echo "linux" ;;
    darwin*) echo "darwin" ;;
    *) echo "err" ;;
    esac
}

# ============================================================
# 1) 사전 점검 유틸리티
# ============================================================
# 필수 명령어 존재 여부 확인
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || error_exit "필수 명령어가 없습니다: $1"
}

# 필수 도구와 docker compose v2 지원 확인
preflight_check() {
  need_cmd curl
  need_cmd jq
  need_cmd unzip
  need_cmd docker

  if docker compose version >/dev/null 2>&1; then
    echo " - docker compose 사용 가능"
  else
    error_exit "docker compose를 찾을 수 없습니다. Docker Compose v2를 설치하세요."
  fi

  echo " - 사전 점검 완료"
}

# ============================================================
# 2) 최신 릴리즈 가져오기 유틸리티
# ============================================================
# ISO 8601 타임스탬프 생성(리눅스/맥 호환)
iso_timestamp() {
  if date -Iseconds >/dev/null 2>&1; then
    date -Iseconds
  else
    date -u +"%Y-%m-%dT%H:%M:%S%z"
  fi
}

# 이미지 이름 소문자 변환(Docker 규칙)
to_lowercase() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

# 최신 릴리즈 태그 조회
get_latest_release_tag() {
  local owner="$1"
  local repo="$2"
  local token="${3:-}"
  local release_json
  local tag

  release_json=$(github_api \
    "https://api.github.com/repos/${owner}/${repo}/releases/latest" \
    "$token")

  tag=$(echo "$release_json" | jq -r '.tag_name')

  if [[ -z "$tag" || "$tag" == "null" ]]; then
    error_exit "최신 릴리즈 태그를 가져오지 못했습니다: ${owner}/${repo}"
  fi

  echo "$tag"
}

# GHCR 로그인 상태 확인 및 필요 시 토큰 로그인
ensure_ghcr_login() {
  local require_token="${1:-false}"
  local docker_config
  local config_path
  local ghcr_username
  local ghcr_token
  local is_logged_in="false"

  docker_config="${DOCKER_CONFIG:-$HOME/.docker}"
  config_path="${docker_config}/config.json"

  if [[ -f "$config_path" ]]; then
    if jq -e '.auths["ghcr.io"]' "$config_path" >/dev/null 2>&1; then
      is_logged_in="true"
    fi
  fi

  if [[ "$is_logged_in" == "true" ]]; then
    echo " - GHCR 로그인 확인됨"
    if [[ "$require_token" == "true" && -z "${GHCR_TOKEN:-}" ]]; then
      prompt GHCR_TOKEN "GHCR 토큰" "" "true"
    fi
    return 0
  fi

  info_log "GHCR 로그인 필요"

  ghcr_username="${GHCR_USERNAME:-${GITHUB_USERNAME:-${GITHUB_ACTOR:-}}}"
  if [[ -z "$ghcr_username" ]]; then
    prompt GHCR_USERNAME "GHCR 사용자 이름" ""
    ghcr_username="$GHCR_USERNAME"
  fi

  ghcr_token="${GHCR_TOKEN:-${GITHUB_TOKEN:-}}"
  if [[ -z "$ghcr_token" ]]; then
    prompt GHCR_TOKEN "GHCR 토큰" "" "true"
    ghcr_token="$GHCR_TOKEN"
  fi

  echo "$ghcr_token" | docker login ghcr.io -u "$ghcr_username" --password-stdin >/dev/null 2>&1 \
    || error_exit "GHCR 로그인에 실패했습니다. 사용자 이름/토큰 권한을 확인하세요."

  echo " - GHCR 로그인 완료"
}

# GitHub API 호출(토큰 선택)
github_api() {
  local url="$1"
  local token="${2:-}"
  if [[ -z "$token" ]]; then
    token="${GITHUB_TOKEN:-}"
  fi
  if [[ -n "$token" ]]; then
    curl -sSL \
      -H "Authorization: Bearer $token" \
      -H "Accept: application/vnd.github+json" \
      "$url"
  else
    curl -sSL \
      -H "Accept: application/vnd.github+json" \
      "$url"
  fi
}

# 최신 웹 릴리즈 다운로드
fetch_web_release() {
  local web_token
  local release_json
  local tag
  local asset_name
  local asset_url
  local console_dir
  local tmp_zip

  console_dir="$OUTPUT_DIR/console"

  web_token="${GITHUB_TOKEN:-}"
  WEB_RELEASE_TAG="$(get_latest_release_tag "$WEB_REPO_OWNER" "$WEB_REPO_NAME" "$web_token")"
  echo " - 최신 웹 릴리즈 태그: $WEB_RELEASE_TAG"

  asset_name="mdk_web_dashboard_${WEB_RELEASE_TAG}.zip"
  release_json=$(github_api \
    "https://api.github.com/repos/${WEB_REPO_OWNER}/${WEB_REPO_NAME}/releases/latest" \
    "$web_token")
  asset_url=$(echo "$release_json" \
    | jq -r --arg NAME "$asset_name" \
      '.assets[] | select(.name == $NAME) | .browser_download_url')

  if [[ -z "$asset_url" || "$asset_url" == "null" ]]; then
    error_exit "웹 아티팩트를 찾을 수 없습니다: $asset_name"
  fi

  echo " - 웹 아티팩트 다운로드 중: $asset_name"
  mkdir -p "$console_dir"
  tmp_zip="$(mktemp)"
  curl -L "$asset_url" -o "$tmp_zip"

  echo " - 웹 아티팩트 압축 해제 중..."
  rm -rf "$console_dir"/*
  unzip -q "$tmp_zip" -d "$console_dir"
  rm "$tmp_zip"
}

# API 이미지 가져오기
pull_api_image() {
  if [[ -z "${API_TAG:-}" ]]; then
    API_TAG="latest"
  fi

  ensure_ghcr_login

  echo " - API 이미지 가져오는 중: ${API_IMAGE}:${API_TAG}"
  if ! docker pull "${API_IMAGE}:${API_TAG}"; then
    error_exit "API 이미지 다운로드 실패: ${API_IMAGE}:${API_TAG}"
  fi
}

# 릴리즈 메타데이터 기록
write_release_meta() {
  local meta_file

  meta_file="$OUTPUT_DIR/release-meta.json"
  jq -n \
    --arg web_tag "${WEB_RELEASE_TAG:-}" \
    --arg web_repo "${WEB_REPO_OWNER}/${WEB_REPO_NAME}" \
    --arg api_image "${API_IMAGE}:${API_TAG}" \
    --arg api_tag "${API_TAG}" \
    --arg installed_at "$(iso_timestamp)" \
    '{
      web: {
        repository: $web_repo,
        tag: $web_tag
      },
      api: {
        image: $api_image,
        tag: $api_tag
      },
      installed_at: $installed_at
    }' > "$meta_file"

  echo " - 릴리즈 메타데이터 기록 완료: $meta_file"
}

# ============================================================
# 3) 템플릿 생성 유틸리티
# ============================================================
# 입력값 프롬프트
prompt() {
  local var_name="$1"
  local message="$2"
  local default="${3:-}"
  local secret="${4:-false}"
  local value=""

  if [[ "$secret" == "true" ]]; then
    if [[ -n "$default" ]]; then
      read -r -s -p "$message (기본값 숨김): " value
      echo
      value="${value:-$default}"
    else
      read -r -s -p "$message: " value
      echo
    fi
  else
    if [[ -n "$default" ]]; then
      read -r -p "$message [$default]: " value
      value="${value:-$default}"
    else
      read -r -p "$message: " value
    fi
  fi

  if [[ -z "$value" ]]; then
    error_exit "$var_name 값이 필요합니다."
  fi

  printf -v "$var_name" '%s' "$value"
}

# 배포 설정 파일 생성(Caddy/Compose/Env)
render_templates() {
  local docker_out_dir
  local console_dir
  local db_name_default
  local db_user_default
  local cors_origin_default

  docker_out_dir="$OUTPUT_DIR/docker"
  console_dir="$OUTPUT_DIR/console"

  mkdir -p "$docker_out_dir"

  if [[ ! -f "$console_dir/index.html" ]]; then
    error_exit "웹 콘솔 파일을 찾을 수 없습니다: $console_dir"
  fi

  # LAN IP 감지 (Linux/macOS)
  detected_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || ipconfig getifaddr en0 2>/dev/null || echo "")
  prompt LAN_IP "서버 LAN IP (다른 기기 접속용)" "$detected_ip"

  db_name_default="${POSTGRES_DB:-mdk_postgres_db}"
  db_user_default="${POSTGRES_USER:-mdk}"
  prompt POSTGRES_DB "Postgres DB 이름" "$db_name_default"
  prompt POSTGRES_USER "Postgres 사용자" "$db_user_default"
  prompt POSTGRES_PASSWORD "DB 비밀번호" "${POSTGRES_PASSWORD:-}"

  if [[ -z "${API_IMAGE:-}" ]]; then
    prompt API_IMAGE "API 이미지 이름 (예: ghcr.io/org/dashboard-api)"
  fi
  if [[ -z "${API_TAG:-}" ]]; then
    API_TAG="latest"
  fi

  cors_origin_default="https://${LAN_IP}"
  prompt CORS_ORIGIN "CORS 허용 Origin (대시보드 접속 주소)" "$cors_origin_default"

  API_PORT="${API_PORT:-3000}"


  cat > "$docker_out_dir/db.env" <<EOF
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
EOF

  cat > "$docker_out_dir/server.env" <<EOF
NODE_ENV=production
PORT=${API_PORT}

## 공통 DB 설정 ##
DB_TARGET=local
POSTGRES_HOST_LOCAL=db
POSTGRES_PORT_LOCAL=5432
POSTGRES_DB_LOCAL=${POSTGRES_DB}
# Drizzle 및 백엔드에서 공용으로 사용할 URL
DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:5432/${POSTGRES_DB}
DATABASE_URL_LOCAL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:5432/${POSTGRES_DB}
CORS_ORIGIN=${CORS_ORIGIN}
EOF

  cat > "$docker_out_dir/Caddyfile" <<EOF
{
  # 로컬/내부망 사용을 위한 글로벌 설정
  local_certs
  skip_install_trust
  # SNI가 없을 경우 기본적으로 사용할 호스트 설정 (외부 기기 IP 접속 대응)
  default_sni ${LAN_IP}
}

# 메인 접속 블록 (LAN IP, localhost 및 모든 :443 요청 대응)
${LAN_IP}, localhost, :443 {
  tls internal
  encode gzip

  root * /srv/console
  file_server

  # API 프록시 설정 (경로 기반)
  @api path /api/*
  reverse_proxy @api dashboard-api:${API_PORT}
}
EOF

  cat > "$docker_out_dir/docker-compose.yml" <<EOF
services:
  caddy:
    image: caddy:latest
    container_name: dashboard_caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ../console:/srv/console:ro
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      dashboard-api:
        condition: service_healthy

  dashboard-api:
    image: ${API_IMAGE}:${API_TAG}
    restart: unless-stopped
    container_name: dashboard-api
    env_file:
      - ./server.env
    expose:
      - "${API_PORT}"
    healthcheck:
      # Alpine 기반 이미지에서도 동작하도록 wget 사용 (curl 부재 대비)
      # /api/v1/health는 내부 DB 상태에 따라 503을 뱉을 수 있으므로, 앱 가동 자체만 체크하는 /api/v1으로 변경
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:${API_PORT}/api/v1 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 30s
    depends_on:
      - db

  db:
    image: postgres:17
    container_name: ${POSTGRES_DB}
    restart: unless-stopped
    env_file:
      - ./db.env
    volumes:
      - postgres_data:/var/lib/postgresql/data
    expose:
      - "5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 5s
      timeout: 3s
      retries: 20

volumes:
  caddy_data:
  caddy_config:
  postgres_data:
EOF

  echo " - 생성 완료"
  echo " - $docker_out_dir/docker-compose.yml"
  echo " - $docker_out_dir/Caddyfile"
  echo " - $docker_out_dir/server.env"
  echo " - $docker_out_dir/db.env"
}

# ============================================================
# 실행 환경 및 인자 처리
# ============================================================
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$ROOT_DIR/installer.env" ]]; then
  set -a
  source "$ROOT_DIR/installer.env"
  set +a
fi

OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/output}"
TEMPLATES_DIR="${TEMPLATES_DIR:-$ROOT_DIR/templates}"

RUN_AFTER=false

usage() {
  cat <<EOF
사용법: ./setup.sh [--run]

옵션:
  --run   설정 파일 생성 후 docker compose up -d 자동 실행
EOF
}


for arg in "$@"; do
  case "$arg" in
    --run) RUN_AFTER=true ;;
    -h|--help) usage; exit 0 ;;
    *) error_log "알 수 없는 옵션: $arg"; usage; exit 1 ;;
  esac
done

info_log "대시보드 설치 도우미 시작"

# 루트 권한 확인 https://stackoverflow.com/a/18216122/18954618
if [ "$EUID" -ne 0 ]; then error_exit "이 스크립트는 루트 사용자로 실행해야 합니다"; fi


os="$(detect_os)"
arch="$(detect_arch)"

if [[ "$os" == "err" ]]; then error_exit "지원하지 않는 운영체제입니다"; fi
if [[ "$arch" == "err" ]]; then error_exit "지원하지 않는 CPU 아키텍처입니다"; fi

if [[ "$os" == "linux" ]]; then
  if [ "$EUID" -ne 0 ]; then
    info_log "루트 권한 없이 실행합니다. Docker 권한이 없으면 sudo로 실행하세요."
  fi
fi

if [[ "$os" == "darwin" ]]; then
  if [ "$EUID" -eq 0 ]; then
    info_log "macOS에서는 루트 실행 시 Docker 접근이 제한될 수 있습니다. 일반 사용자로 실행하세요."
  fi
fi

info_log "단계 0/4: 경로 정보"
echo " - 루트: $ROOT_DIR"
echo " - 출력: $OUTPUT_DIR"

mkdir -p "$OUTPUT_DIR"

# ============================================================
# 단계 1: 사전 점검
# ============================================================
info_log "단계 1/4: 사전 점검"
preflight_check

# ============================================================
# 단계 2: 최신 릴리즈 자산 가져오기
# ============================================================
info_log "단계 2/4: 최신 릴리즈 자산 가져오기"
# 최신 릴리즈 가져오기는 환경변수를 필요로 함
# - WEB_REPO_OWNER, WEB_REPO_NAME
# - API_IMAGE (이미지 가져오기)
# - API_TAG (지정하지 않으면 latest 사용)

WEB_REPO_OWNER="poeticDev"
WEB_REPO_NAME="mdk_web_dashboard"


if [[ -z "${WEB_REPO_OWNER:-}" ]]; then
  read -r -p "웹 저장소 소유자/조직 (예: your-org): " WEB_REPO_OWNER
fi
if [[ -z "${WEB_REPO_NAME:-}" ]]; then
  read -r -p "웹 저장소 이름 (예: dashboard-web): " WEB_REPO_NAME
fi

if [[ -z "${API_IMAGE:-}" ]]; then
  web_repo_owner_lower="$(to_lowercase "$WEB_REPO_OWNER")"
  API_IMAGE="ghcr.io/$web_repo_owner_lower/mdk-nest-server"
fi

api_image_lower="$(to_lowercase "$API_IMAGE")"
if [[ "$API_IMAGE" != "$api_image_lower" ]]; then
  info_log "API 이미지 이름에 대문자가 있어 소문자로 변환합니다."
  API_IMAGE="$api_image_lower"
fi


fetch_web_release
pull_api_image
write_release_meta

# ============================================================
# 단계 3: 템플릿 생성 (환경값 + Caddy 설정)
# ============================================================
info_log "단계 3/4: 템플릿 생성"
render_templates

# ============================================================
# 단계 4: 안내 또는 실행
# ============================================================
DOCKER_OUT_DIR="$OUTPUT_DIR/docker"

info_log "단계 4/4: 설치 안내"
cat <<EOF

✅ 설치 파일 생성 완료

다음 단계:
  cd "$DOCKER_OUT_DIR"
  docker compose up -d

접속:
  - 콘솔: https://console.<your-domain>
  - API 주소: https://api.<your-domain>

팁:
  - 컨테이너 상태: docker compose ps
  - 로그 확인:     docker compose logs -f caddy
                  docker compose logs -f dashboard-api
EOF

if [[ "$RUN_AFTER" == "true" ]]; then
  info_log "추가 실행: docker compose up -d"
  (cd "$DOCKER_OUT_DIR" && docker compose up -d)
  echo " - 실행 완료"
fi
