# 설치 절차 (상세)

## 1) 사전 준비
- 운영체제: 리눅스
- 권한: 루트 필요(예: `sudo`)
- 필수 도구: `curl`, `jq`, `unzip`, `docker`, `docker compose`(v2)
- 네트워크: GitHub 릴리즈 다운로드 및 컨테이너 이미지 가져오기 가능해야 함

## 2) 파일 권한 부여
```bash
chmod +x setup.sh
```

## 3) 실행
이 프로젝트는 `setup.sh` 하나만으로 실행할 수 있다.
```bash
sudo ./setup.sh
```

## 4) 입력 프롬프트 안내
`setup.sh`에서 아래 값을 입력한다.
- `기본 도메인`: 예) `example.com`
- `Let's Encrypt 이메일`: 인증서 발급용 이메일
- `Postgres DB 이름`: 기본값 `mdk_postgres_db`
- `Postgres 사용자`: 기본값 `mdk`
- `DB 비밀번호`: DB 비밀번호
- `API 이미지 이름`: 예) `ghcr.io/<org>/mdk-nest-server`
- `API 이미지 태그`: 태그 값(미지정 시 `latest`)
- `CORS 허용 Origin`: 예) `https://console.example.com`

## 5) 생성 결과물
`output/docker` 아래에 아래 파일이 생성된다.
- `docker-compose.yml`
- `Caddyfile`
- `server.env`
- `db.env`

## 6) 서비스 실행
```bash
cd output/docker
docker compose up -d
```

## 7) 접속 경로
- 콘솔: `https://console.<your-domain>`
- API 주소: `https://api.<your-domain>`

## 8) 자동 실행 옵션
설치 직후 바로 실행하려면:
```bash
sudo ./setup.sh --run
```

## 9) 환경 변수로 입력값 주입
프롬프트를 줄이고 싶다면 아래 변수를 미리 export한다.
- `WEB_REPO_OWNER`, `WEB_REPO_NAME`: 웹 콘솔 릴리즈 저장소
- `API_IMAGE`: API 이미지 경로
- `API_TAG`: API 이미지 태그(미지정 시 `latest`)
- `OUTPUT_DIR`, `TEMPLATES_DIR`: 출력/템플릿 경로
- `CONSOLE_HOST`, `API_HOST`, `API_PORT`, `CORS_ORIGIN`
- `GITHUB_TOKEN`: 프라이빗 레포 접근 시 필요

예시:
```bash
export WEB_REPO_OWNER="poeticDev"
export WEB_REPO_NAME="mdk_web_dashboard"
export API_IMAGE="ghcr.io/poeticDev/mdk-nest-server"
sudo ./setup.sh
```

## 10) 문제 해결 팁
- 컨테이너 상태 확인: `docker compose ps`
- 로그 확인: `docker compose logs -f caddy`
- API 로그 확인: `docker compose logs -f dashboard-api`
- Caddy가 인증서를 못 받는다면 80/443 포트 개방 여부를 확인한다.
