# 지점별 빌드 가이드

## 개요

이 프로젝트는 같은 코드베이스로 1호점과 2호점 앱을 각각 빌드할 수 있습니다.

구분 방식:
- Android flavor
  - `branch1`
  - `branch2`
- `dart-define`
  - `BRANCH_CODE`
  - `BRANCH_NAME`
  - `APP_TITLE`
  - `CONTACT_PREFIX`
  - `SUPABASE_URL`
  - `SUPABASE_ANON_KEY`

## 기본값

별도 값을 주지 않으면 1호점 기준으로 동작합니다.

- 기본 지점 코드: `branch1`
- 기본 지점명: `1호점`
- 기본 고객명 접두어: `강서`

`branch2`로 빌드하면 고객명 접두어는 자동으로 `미인`이 됩니다.

## 1호점 빌드 예시

```bash
flutter build apk \
  --flavor branch1 \
  --dart-define=BRANCH_CODE=branch1 \
  --dart-define=BRANCH_NAME=1호점 \
  --dart-define=APP_TITLE=The Thai 1호점 \
  --dart-define=CONTACT_PREFIX=강서 \
  --dart-define=SUPABASE_URL=https://YOUR_BRANCH1_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_BRANCH1_ANON_KEY
```

## 2호점 빌드 예시

```bash
flutter build apk \
  --flavor branch2 \
  --dart-define=BRANCH_CODE=branch2 \
  --dart-define=BRANCH_NAME=2호점 \
  --dart-define=APP_TITLE=The Thai 2호점 \
  --dart-define=CONTACT_PREFIX=미인 \
  --dart-define=SUPABASE_URL=https://utwhwrrwjfijmavsrcpx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV0d2h3cnJ3amZpam1hdnNyY3B4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMzOTM4MjksImV4cCI6MjA4ODk2OTgyOX0.bJao0iNwxohcNEAtR7VOHza2KfMdRfj7pEMKOQ5f7r0
```

## 접두어 규칙

- 1호점 예시: `강서New마통(0)(0)1234`
- 2호점 예시: `미인New마통(0)(0)1234`

필요하면 `CONTACT_PREFIX`를 별도로 넘겨 접두어를 직접 바꿀 수 있습니다.
