# 승인된 오목눈이 정령 — 게임 적용본

사용자가 제공한 Tripo 모델의 몸통·꼬리 수정본을 마을 NPC에 적용했다. 원본 수정 GLB는 별도 전달 파일로 보존하며, 이 폴더에는 게임용 파생 모델을 둔다.

- 원본 1,779,308 삼각형 → 게임용 64,000 삼각형, 39,376 정점, 약 4.6MB.
- 4K 색상·금속성/거칠기·노멀 JPEG 3장 바이트를 보존했다. 뒤쪽 복구 표면의 버텍스 색도 유지한다.
- Body, Head, WingLeft, WingRight, Tail의 5본 스킨. 앞면 +Z, 발바닥 Y=0. `SpiritActor3D`가 게임의 +X 방향으로 회전·중심 보정한다.
- 날개는 원본의 붙어 있는 표면을 연속 가중치로 변형한다. 어깨를 잘라 분리하지 않는다. 꼬리는 중앙 한 묶음이다.
- 걷기·대기·바람 작업·수확·물 부족·길 막힘은 기존 VillageSim 상태에 연결된다. 애니메이션은 `SpiritActor3D.update_anim`이 구동하며 GLB에 별도 AnimationPlayer 클립은 없다.
- 모든 NPC가 메시와 텍스처를 공유하고, Skeleton3D 포즈는 개체마다 분리한다. 기존 농사·저장 데이터의 마이그레이션은 필요 없다.
- 마을 LDR 조명에서 흰 몸이 포화되지 않도록 재질의 선형 baseColorFactor를 0.55로 조정했다. 이미지 자체는 바꾸지 않았다. 실제 털 지오메트리를 추가하지 않았다.
- Godot import 설정은 내장 이미지를 씬 리소스에 포함하고 LOD·tangent·shadow mesh를 생성한다. 별도의 텍스처 파일을 수동 복사할 필요가 없다.

## 재생성

Python 3, numpy, scipy, Pillow, pymeshlab 2025.7을 준비한 뒤:

```sh
python source/build_runtime.py /path/to/cute-bird-repaired.glb spirit.glb
```

이 스크립트는 승인한 모델의 좌표에 맞춘 변환이며 범용 자동 리깅 도구가 아니다. `source_sha256`와 경량화 결과는 `spirit.json`에 기록한다. Godot 4.7.2에서 실행 검증했다.

PyMeshLab의 [UV 보존 단순화](https://pymeshlab.readthedocs.io/en/latest/filter_list.html#meshing-decimation-quadric-edge-collapse-with-texture)를 사용했다. `gltf-validation.json`에는 glTF 검증 결과를 기록했다. tangent 생성 경고 2개는 Godot의 `meshes/ensure_tangents=true` 설정으로 처리한다.

## 확인

```sh
godot --headless --path game --editor --import
godot --headless --path game -s tests/run_spirit_model_tests.gd
godot --headless --path game -s tests/run_village_entry_tests.gd
godot --path game -- --village-test
```

시작 화면의 **마을 바로 테스트** 버튼으로도 확인할 수 있다. 첫 로딩에는 Godot 에셋 import 시간이 필요하다.
