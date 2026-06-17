# Zoom Caption Translator MVP

macOS에서 Zoom 데스크톱 앱의 자막 팝아웃/창 텍스트를 읽고 번역 결과를 always-on-top 오버레이로 보여주는 최소 구현입니다.

이 MVP는 두 가지 입력 경로를 씁니다.

- Vision OCR: 실행 시 자막 영역을 드래그로 선택하거나 `--ocr-region`으로 지정한 화면 영역을 OCR합니다.
- Accessibility API: `USE_ACCESSIBILITY=1` 또는 `--app-name` 기반 실행으로 Zoom 창 안의 텍스트 요소를 읽습니다.

번역 provider는 외부 패키지 없이 `mock`, `oci`, `deepl`을 지원합니다.

기본 추천은 `oci`입니다. DeepL은 있으면 쓰는 선택지일 뿐입니다.

## Build

```sh
./build.sh
```

The project also includes `Package.swift`, so `swift build -c release` should work on a healthy SwiftPM install. `build.sh` exists because some Command Line Tools installs can have a broken SwiftPM manifest linker while direct `swiftc` still works.

## Test

```sh
./test.sh
```

## Run

먼저 mock provider로 오버레이와 자막 수집이 되는지 확인합니다. 이 단계는 번역 API 키가 필요 없습니다.

```sh
.build/release/zoom-caption-translator \
  --provider mock \
  --app-name Zoom \
  --debug
```

OCI Generative AI API key를 설정한 뒤 OCI provider를 실행합니다.

```sh
./run-with-oci.sh
```

실행하면 화면이 어두워지고, Zoom 자막 영역을 드래그해서 지정합니다. Esc를 누르면 취소됩니다.

같은 명령을 직접 쓰면:

```sh
.build/release/zoom-caption-translator \
  --provider oci \
  --target-lang KO \
  --source-lang EN \
  --app-name Zoom \
  --select-ocr-region
```

OCI provider는 `OCI_GENAI_API_KEY`를 Bearer 인증으로 사용합니다. 기본 모델은 `openai.gpt-5.4-nano`입니다.

`run-with-oci.sh`는 기본으로 `oci-translator.env`를 읽습니다.

```sh
./run-with-oci.sh
```

`oci-translator.env` 예시:

```sh
OCI_GENAI_API_KEY="replace-with-your-oci-genai-api-key"
OCI_REGION="us-chicago-1"
GPT_MODEL="openai.gpt-5.4-nano"
INTERVAL="0.4"
STABLE_AFTER="1.2"
OCR_LINES="2"
```

다른 설정 파일을 쓰려면 `OCI_TRANSLATOR_CONFIG=/path/to/file ./run-with-oci.sh`로 지정합니다.

DeepL 키가 있을 때만 DeepL을 사용합니다.

```sh
DEEPL_API_KEY=your_key_here \
.build/release/zoom-caption-translator \
  --provider deepl \
  --target-lang KO \
  --source-lang EN \
  --app-name Zoom
```

OCR만 사용할 때:

```sh
.build/release/zoom-caption-translator \
  --provider mock \
  --force-ocr \
  --ocr-region 300,680,1320,180 \
  --source-lang en
```

`--ocr-region`은 메인 디스플레이 기준 `x,y,width,height`입니다. 자막 팝아웃을 화면 아래에 두고 여러 번 조정해 맞추는 방식이 가장 빠릅니다.

OCR 영역은 자막 글자 주변만 작게 잡는 것이 좋습니다. 영역이 너무 크면 배경 슬라이드, 브라우저 주소, 날짜 같은 텍스트가 같이 번역됩니다.

드래그 선택을 매번 하지 않으려면 실행 중 출력되는 `Selected OCR anchor` 값을 재사용합니다. 이 값은 디스플레이의 안정 ID와 디스플레이 내부 비율 좌표라서, 좌우 배치를 바꾸거나 싱글/듀얼 환경을 오가도 `OCR_DISPLAY`/`OCR_REGION`보다 덜 흔들립니다.

```sh
OCR_ANCHOR=123456789:0.041000,0.240000,0.216000,0.455000 ./run-with-oci.sh
```

debug 모드에서는 최신 OCR 캡처가 `/tmp/zoom-caption-ocr-latest.png`에 저장됩니다. 이 이미지를 보고 실제로 어떤 영역이 읽히는지 확인하세요.

번역 오버레이는 마우스로 드래그해서 옮길 수 있습니다. 마지막 위치는 `/tmp/zoom-caption-overlay-position.txt`에 저장되고 다음 실행 때 재사용됩니다. 위치를 고정하려면 실행할 때 `OVERLAY_X`, `OVERLAY_Y`를 넘기면 됩니다. 마우스 클릭을 아래 앱으로 통과시키려면 `OVERLAY_CLICK_THROUGH="1"`을 씁니다.

듀얼 모니터에서는 선택 오버레이가 각 디스플레이에 별도 창으로 뜹니다. 이전 방식의 `OCR_DISPLAY`/`OCR_REGION`도 계속 동작하지만 새로 저장할 때는 `OCR_ANCHOR`를 권장합니다.

OCR에서 자막 줄 수를 조정하려면:

```sh
OCR_ANCHOR=123456789:0.041000,0.240000,0.216000,0.455000 ./run-with-oci.sh --debug --ocr-lines 2
```

응답 속도를 더 당기려면 안정화 대기와 OCR 주기를 줄입니다.

```sh
OCR_ANCHOR=123456789:0.041000,0.240000,0.216000,0.455000 ./run-with-oci.sh --interval 0.2 --stable-after 0.5 --ocr-lines 1
```

Accessibility 경로를 다시 쓰려면:

```sh
USE_ACCESSIBILITY=1 ./run-with-oci.sh --debug
```

## Debugging Captions

오버레이가 `Waiting for captions...`에서 멈추면 먼저 창 제목 필터 없이 debug 모드로 실행합니다.

```sh
.build/release/zoom-caption-translator \
  --provider mock \
  --app-name Zoom \
  --debug
```

Zoom 창 제목을 확인하려면:

```sh
.build/release/zoom-caption-translator --app-name Zoom --list-windows
```

특정 창만 스캔해야 할 때만 `--window-title`을 추가합니다.

```sh
WINDOW_TITLE="Live Transcript" ./run-with-oci.sh --debug
```

## Permissions

macOS 권한이 필요합니다.

- Accessibility API 경로: System Settings > Privacy & Security > Accessibility에서 터미널 또는 빌드된 실행 파일 허용
- OCR 경로: System Settings > Privacy & Security > Screen Recording에서 터미널 또는 빌드된 실행 파일 허용

권한 변경 후에는 실행 중인 프로세스를 재시작해야 합니다.

## Notes

- 기본 동작은 저장 없이 화면 오버레이만 갱신합니다.
- `oci` provider는 `OCI_GENAI_API_KEY`를 사용합니다. 기본 env 파일에는 API key, region, model, OCR timing 값만 둡니다. 필요하면 `OCI_GENAI_API_MODE`, `OCI_GENAI_API_BASE_URL`, `OCI_GENAI_API_URL`, `OCR_ANCHOR`, `OVERLAY_X`, `OVERLAY_Y`, `OVERLAY_CLICK_THROUGH`를 실행 시 env override로 넘길 수 있습니다.
- Zoom UI 텍스트가 Accessibility로 노출되지 않으면 `--ocr-region` fallback을 사용하세요.
- 회의 자막/음성은 민감 정보일 수 있으니 참가자 동의와 회사 보안 정책을 먼저 확인하세요.
