# zoomcc-translate-genai

## 소개

zoomcc-translate-genai는 Zoom CC에 대한 실시간 번역 기능을 지원하는 macOS용 오버레이 도구입니다. 자막 팝아웃/창 텍스트를 읽어 OCI Generative AI 서비스 기반으로 번역하고, 번역 결과를 always-on-top 오버레이로 표시합니다.

## 설치

```sh
git clone https://github.com/cdh3063/zoomcc-translate-genai.git
cd zoomcc-translate-genai
./build.sh
cp oci-translator.env.example oci-translator.env
```

## 설정 및 사용법

`oci-translator.env`를 열어 OCI Generative AI API key와 실행 설정을 입력합니다.

```sh
OCI_GENAI_API_KEY="replace-with-your-oci-genai-api-key"
OCI_REGION="us-chicago-1"
GPT_MODEL="openai.gpt-5.4-nano"
INTERVAL="0.4"
STABLE_AFTER="1.2"
OCR_LINES="2"
```

실행:

```sh
./run-with-oci.sh
```

처음 실행하면 화면에서 Zoom 자막 영역을 드래그로 선택합니다. 번역 오버레이는 마우스로 드래그해 이동할 수 있습니다.

다른 설정 파일을 쓰려면:

```sh
OCI_TRANSLATOR_CONFIG=/path/to/oci-translator.env ./run-with-oci.sh
```

## 퍼미션

macOS 권한이 필요합니다.

- System Settings > Privacy & Security > Screen Recording에서 터미널 앱 허용
- System Settings > Privacy & Security > Accessibility에서 터미널 앱 허용

권한 변경 후에는 실행 중인 프로세스를 재시작해야 합니다.
