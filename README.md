# 컨트롤 서버 자동 설치 도구

## 목적
- 대시보드 콘솔(웹)과 API 서버를 배포하기 위한 설치/설정 자동화 스크립트 제공.
- 최신 웹 릴리즈 다운로드, API 도커 이미지 가져오기, 배포용 설정 파일 생성.

## 사용조건
- 운영체제: 리눅스 전용
- 권한: 루트 필요(`sudo`)
- 필수 도구: `curl`, `jq`, `unzip`, `docker`, `docker compose`(v2)

## 설치 지침
자세한 절차는 [INSTALL.md](INSTALL.md)를 참고한다.
이 프로젝트는 `setup.sh` 하나만으로 실행할 수 있다.

1) `setup.sh` 파일에 실행 권한 부여
```bash
chmod +x setup.sh
```

2) 스크립트 실행
```bash
sudo ./setup.sh
```

3) 생성된 배포 파일 확인 및 실행
```bash
cd output/docker
docker compose up -d
```

## 연계 프로젝트와 의존성
- 웹 콘솔 릴리즈 저장소: `WEB_REPO_OWNER/WEB_REPO_NAME` (기본값: `poeticDev/mdk_web_dashboard`)
- API 이미지: `API_IMAGE` (예: `ghcr.io/<org>/mdk-nest-server`)
- API 태그: `API_TAG` (미지정 시 `latest`)
- GitHub 릴리즈 API: `https://api.github.com/repos/<owner>/<repo>/releases/latest`

## 참고
- 실행 시 입력값과 출력 파일은 `output/` 하위에 생성된다.
- 입력 프롬프트는 `setup.sh`에서 진행된다.
