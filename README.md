# The Thai

태국 마사지샵 운영을 위한 Flutter 안드로이드 앱입니다. 고객 관리, 방문 기록, 쿠폰 잔액 관리, 전화 수신 연동, 예약 관리를 하나의 앱에서 처리합니다.

## 현재 범위

- 고객 목록 조회, 검색, 신규 등록
- 고객 상세 조회, 메모 수정, 방문 기록 추가
- 회원 유형별 서비스 가격표 기반 쿠폰 차감/충전
- 전화 수신 시 고객 조회, 오버레이/알림 표시
- 통화 종료 후 예약 등록 유도
- 날짜별 예약 조회, 등록, 취소, 노쇼 처리

## 기술 스택

- Flutter / Dart 3.11+
- Supabase (PostgreSQL)
- Android 네이티브 BroadcastReceiver + MethodChannel
- `phone_state`, `overlay_support`, `flutter_local_notifications`

## 문서

- [프로젝트 분석](./docs/project-analysis.md)
- [구조도 및 흐름도](./docs/architecture.md)
- [기존 구현 메모](./research.md)

## 개발 메모

- 이 저장소의 텍스트 파일은 UTF-8 기준으로 관리합니다.
- Windows PowerShell 출력에서 한글이 깨져 보이면 파일이 손상된 것이 아니라 터미널 코드페이지 문제일 수 있습니다.
- `flutter analyze`
- `flutter test`
