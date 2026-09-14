# HWR-006 — 승인한 Tripo 오목눈이 정령 적용

기준: `claude/magical-bohr-2eljuj`의 `43f174f`. 사용자 승인 모델을 실제 마을 NPC로 교체했다.

## 결과

- 구·상자로 생성하던 정령을 승인한 모델의 게임용 GLB로 교체했다. 모델은 64,000 삼각형, 약 4.6MB이며 내장 4K 텍스처 3장은 그대로 보존했다.
- 5본 스킨을 추가해 호흡, 통통 뛰는 이동, 날갯짓, 꼬리 흔들림, 수확 기쁨, 휴식·길 막힘 상태를 기존 VillageSim에 연결했다. 작업 중 날개가 펼쳐지고 기존 바람 효과가 함께 나온다.
- 정령마다 스켈레톤 포즈를 따로 두고 메시·텍스처는 공유한다. 저장 구조·동료 전투·캠페인 규칙은 변경하지 않았다.
- 마을 조명에서 흰 몸이 포화되지 않도록 모델 재질 밝기를 조정했다. 털은 기존 텍스처·노멀 표현이며 별도의 털 시스템은 없다.
- Node2D 아래의 마을 HUD가 상위 Control의 한글 글꼴을 상속받지 못하는 문제도 고쳤다. Label과 Button에 기존 GothicA1을 명시했다.

## 검증

- Godot 4.7.2 import: 스크립트·모델 오류 없음. 내장 이미지를 캐시 씬에 포함하므로 GLB와 import 설정만 있으면 된다.
- `run_spirit_model_tests.gd`: **17 통과, 0 실패**. 리깅, 메시 공유, 포즈 분리, 텍스처, 이동·작업·바람 효과·실제 식량 수확과 저장 분리 확인. 실제 OpenGL Compatibility 렌더에서도 같은 17개 검증 통과.
- `run_village_entry_tests.gd`: **28 통과, 0 실패**. 마을 바로 테스트 UI, 건설 저장, 재입장, 일반 캠페인 잠금 보존 확인.
- 경량화 결과: 위치 기준 열린 모서리 0, 비다양체 모서리 0. glTF Validator 오류 0, tangent 생성 경고 2. Godot import에서 tangent 생성 설정 활성화.
- 렌더는 Linux llvmpipe 소프트웨어 GPU에서 검증했으며 사용자 Mac의 실측 FPS를 측정한 것은 아니다.

## 실행

Godot에서 `game/project.godot`를 열고 실행한 뒤 **마을 바로 테스트 (전투 없이 · 별도 저장)** 를 누른다. CLI는 `godot --path game -- --village-test`.

[마을 실제 화면](spirit-model/village.jpg) · [정령 확대 화면](spirit-model/closeup.jpg) · [작업 동작 영상](spirit-model/work-animation.mp4)

확대 화면·영상은 같은 마을 장면에서 확인용 카메라로 촬영했다. 영상은 작물이 얼굴을 가리지 않도록 길 위의 정령에 동일한 작업 포즈를 재생한 것이다. 기본 카메라 변경은 테스트 코드 안에서만 수행한다. 농사 기능은 별도로 실제 시뮬레이션에서 검증했다.

큰 원본 GLB는 저장소에 중복 추가하지 않았다. 파생 모델의 재생성 방법과 원본 해시는 `game/assets/wind_spirit/README.md`, `spirit.json`에 있다. 스킨은 짧은 제자리 동작용으로 조정했으며 큰 폭의 비행 애니메이션은 추가 작업이 필요하다.
