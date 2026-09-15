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
GPT_MODEL="xai.grok-4.20-non-reasoning"
INTERVAL="0.2"
STABLE_AFTER="0.6"
OCR_LINES="2"
```

Zoom CC 팝아웃 창은 너무 작게 두기보다 자막 2-3줄이 또렷하게 보일 정도로 적절히 크게 조절하는 것을 권장합니다. 창이 너무 작으면 글자가 작아지거나 줄바꿈이 자주 생겨 번역 품질이 떨어질 수 있습니다.

설정 가이드:

- `INTERVAL`: 자막 영역을 읽는 주기입니다. 기본값은 `0.2`초이며, CPU 사용량을 줄이려면 `0.4-0.8` 정도로 늘릴 수 있습니다. 한 번의 수집이 끝난 뒤 다음 수집을 시작합니다.
- `STABLE_AFTER`: 같은 번역 대상이 유지된 뒤 요청을 보내기까지의 대기 시간입니다. 기본값은 `0.6`초입니다. 완성된 문장은 뒤에 말이 붙어도 먼저 처리하며, 계속 바뀌는 자막은 최대 `2`초 후 현재 내용으로 요청합니다. 이 값을 `2`보다 크게 설정하면 해당 값이 최대 대기 시간이 됩니다. API 응답 시간은 별도입니다.
- `OCR_LINES`: 화면 아래쪽에서 읽을 최신 자막 줄 수입니다. 기본값은 `2`이며, `2-3`줄이 또렷하게 보이도록 조절하는 것을 권장합니다. 화면이 스크롤되어도 겹치는 텍스트를 연결해 현재 문장 전체를 모읍니다. 앞선 자막 최대 3개를 참고 문맥으로 함께 보냅니다.

기본 모델은 Grok 4.20 Non-Reasoning입니다. 기본 Responses 방식에서는 도착한 번역부터 표시합니다.

같은 문장에 내용이 추가되면 앞부분을 포함해 번역을 갱신합니다. 이때 이미 표시한 문장이 첫 단어부터 다시 지워지지 않도록 기존 번역을 유지하다가 이어진 결과로 교체합니다. 같은 문장의 중간 버전은 중복 문맥으로 넣지 않습니다. 마침표 없이 화면에서 사라진 자막도 다음 자막의 참고 문맥에는 남겨 대명사와 용어 해석에 사용합니다. 이전 번역문이 아닌 원문을 참고하며, 화면에 없는 내용은 추측해서 보충하지 않도록 지시합니다.

실행:

```sh
./run-with-oci.sh
```

처음 실행하면 화면에서 Zoom 자막 영역을 드래그로 선택합니다. 번역 오버레이는 마우스로 드래그해 이동할 수 있습니다.

다른 설정 파일을 쓰려면:

```sh
OCI_TRANSLATOR_CONFIG=/path/to/oci-translator.env ./run-with-oci.sh
```

처리 단계별 소요 시간을 확인하려면:

```sh
./run-with-oci.sh --debug
```

`--debug` 로그에는 수집 시간, 자막 안정화 대기, 번역 대기열, 첫 응답 및 완료 시간이 각각 표시됩니다. 화면에서 처음 감지한 시점 기준이며, Zoom 자체의 음성 인식 지연은 포함하지 않습니다. `stable caption`과 `translation` 로그의 같은 `id`를 비교하면 원문과 번역을 대조할 수 있습니다. 로그 공유 시 회의 내용이 포함되어 있는지 확인하세요.

## 퍼미션

macOS 권한이 필요합니다.

- System Settings > Privacy & Security > Screen Recording에서 터미널 앱 허용
- System Settings > Privacy & Security > Accessibility에서 터미널 앱 허용

권한 변경 후에는 실행 중인 프로세스를 재시작해야 합니다.
