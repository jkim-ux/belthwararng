# HWR-GRASS-001 R3 완료 보고 — 정적 잔디·흙길 지면과 작은 풀 묶음

- 읽은 지시서: [TO_CLAUDE_GRASS.md](../TO_CLAUDE_GRASS.md) (R3), [docs/VILLAGE_GROUND_IMPLEMENTATION.md](../docs/VILLAGE_GROUND_IMPLEMENTATION.md), [TO_CLAUDE.md](../TO_CLAUDE.md), [CLAUDE.md](../CLAUDE.md), [reports/README.md](README.md)
- 시작: 2026-09-14 17:02 KST (08:02 UTC) / 완료: 2026-09-14 17:45 KST (08:45 UTC)
- 상태: **완료(지면 교체·풀 묶음·마을 연결·실제 화면 검수·성능 기록)**. 지시서 기준으로 **합본 미술 검수는 별도**다: 나무·우물·울타리는 아직 HWR-ENV-001의 새 모델이 아니라 기존 garden_v1 절차 아트이므로, 환경 9종이 들어온 뒤 같은 stage에서 다시 캡처해야 한다.
- 작업 브랜치: `claude/hwr-grass-001`. 기준 커밋 `6e57ed9`(PR #3 병합 후 main, R2 결과 `baf8687` + R3 지시 `3ae8905` 포함). 지시서가 검토한 `80000e2`는 이력 정리 과정에서 `baf8687`로 squash된 같은 내용이다.
- 코드·에셋 커밋: `c19cb81` (이 보고와 캡처는 다음 커밋).
- R2 보고 [HWR-GRASS-001.md](HWR-GRASS-001.md)는 수정하지 않았다. 옛 타일·바람 셰이더·검토 장면은 폴더에 남겼고 마을은 더 이상 참조하지 않는다.

## 1. 엔진과 실행 환경

| 항목 | 값 |
|---|---|
| 엔진 | Godot 4.7.2 stable, macOS, **GL Compatibility**, 창 1280×720 (프로젝트 설정 그대로) |
| 기기 | Apple M4 MacBook, macOS 26.6.2, 실제 GPU·창 사용 (headless는 테스트에만) |
| 제작 도구 | Python 3.12 + numpy 2.5.2 + Pillow 12.2.0 (텍스처·묶음 생성), Blender 5.2.1 LTS 베이크는 R2의 `build/*.npy`를 재사용, ffmpeg 9 (클립) |
| 이번 세션 설치 | 없음 |

## 2. 무엇을 바꿨나 (지시 1~5항)

| 지시 | 구현 |
|---|---|
| 1. 기존 불투명 바닥 메시 위에 낮은 대비의 잔디·흙 텍스처를 연속 좌표로 | `_build_terrain()`의 지형 메시(칸당 2삼각형)에 공유 `ShaderMaterial`([village_ground.gdshader](../game/assets/environment/grass/village_ground.gdshader)). 잔디(3.0 유닛/반복)·흙(2.0 유닛/반복)을 **월드 XZ**로 샘플링. 칸별 체크무늬 명암·랜덤 색 제거. displacement·normal 없음. |
| 2. 실제 길/입구/완공 도로를 지면 재질의 혼합 마스크로 | [village_ground.gd](../game/assets/environment/grass/village_ground.gd)가 512×384(칸당 32px) RGBA 데이터 텍스처를 만든다. R = 흙(템플릿 `p`·`e` + **완공된** road/repair 건물), G = 고정색 유지(`f ~ # Q d x`), B = 숲 그늘(`W`, 10%). 길 중심은 흙, 가장자리 0.14 유닛만 사인 잡음(±0.05)으로 불규칙하게 섞이고 잔디가 길 안쪽 0.05까지만 파고든다. 강·절벽·부지 칸에는 번지지 않는다. 마스크는 길 집합이 바뀔 때만 재생성(초기 79 ms, 매 프레임 아님). |
| 3. 작은 잎 묶음 3종을 가장자리에 드문드문 | [grass_clumps.glb](../game/assets/environment/grass/ground/grass_clumps.glb): 짧은 풀잎 묶음(112 tris, 높이 0.10), 클로버 묶음(161 tris, 0.076), 가장자리 풀 묶음(144 tris, 0.20). 불투명 메시, 공유 재질 1개, 뿌리 y=0. [grass_clumps.gd](../game/assets/environment/grass/grass_clumps.gd)가 길가·숲 밑·울타리 아래(0행)·물가·암반 옆 칸에만 2~4개 군집(확률 0.7, 빈 칸 섞임)을 고정 seed로 놓는다. 칸 내부는 비운다. 전체 마을 149개(화면당 60~80개), 지역별 MultiMesh 34개. |
| 4. 시간 의존 정점 이동·밝기 진동 제거 | 지면 셰이더에 `TIME`·정점 변형 없음. 묶음은 `StandardMaterial3D`. 테스트가 셰이더 소스와 stage 소스에서 wind/TIME/GrassField 부재를 검사한다. |
| 5. 실제 측면 카메라 한 화면에서 함께 검수 후 확장 | [shoot_grass_village.gd](../game/tests/shoot_grass_village.gd)가 실제 main.tscn → 새 게임 → 마을 진입 후 **실제 배치 규칙**으로 우물(5,4)·농장(2,5)·길(5,7)(6,7)을 놓고 정령이 공사를 끝낸 뒤 같은 카메라(직교 20°, 8.5, 1280×720)로 전/후를 찍는다. 대표 화면(3,9)에 흙길 경계·숲 나무·우물·농장·울타리 줄·정령 3이 들어온다. 같은 규칙이 전체 마을(overview)에 적용돼 있다. |

추가로 한 것

- **배경판 이어 붙임**: 지도 밖 초원 판(`_build_backdrop`의 큰 box)에 같은 지면 재질을 적용했다(마스크 밖 = 순수 잔디). 이전에는 지도가 배경보다 밝은 직사각형으로 떠 보였다. 먼 언덕·정원 숲·울타리·화분은 그대로다.
- **남쪽 흙 스커트**: 지면(y=0)과 배경판(y=−0.14) 사이 턱을 흙 텍스처 단면(0.26 깊이)으로 가렸다. R2의 흙 벽이 하던 역할이다.
- `sync_buildings()`가 footprint뿐 아니라 **문 앞 칸(work_cell)** 도 묶음 숨김에 넣고, 완공 여부에 따라 길 마스크를 갱신한다. 공사 중 길은 아직 흙이 아니다.

바꾸지 않은 것: 템플릿·길찾기·클릭 판정·설치 조건·저장·정령·전투·경제. 묶음이 있는 칸에도 건물은 그대로 놓인다(테스트 `farm still placeable on decorated edge cells`).

## 3. 텍스처와 묶음은 어떻게 만들었나

지시서가 요구한 대로 tint 조정이 아니라 새 텍스처·새 모델이다. [build_ground_kit.py](../tools/environment/grass/build_ground_kit.py), 한 줄 재생성 [run_ground.sh](../tools/environment/grass/run_ground.sh).

| 산출물 | 원본 | 방법 |
|---|---|---|
| `ground_grass.png` 1024² sRGB, 1,354,593 B | Tripo 풀 블록의 위에서 본 색 베이크 2장(R2 `build/top_{a,b}_color.npy`) | 회전·반전한 패치 1,400개를 토러스 캔버스에 뿌려 이음새 없고 방향성 없는 텍스처를 만든 뒤, 밝은 잎끝 이상치를 tanh로 눌러 3유닛마다 반복되던 노란 점을 없애고, 평균을 세이지 알베도 (0.47, 0.515, 0.385)로 옮기며 대비를 낮췄다(sRGB std 0.045). |
| `ground_dirt.png` 1024² sRGB, 1,528,263 B | 같은 원본의 흙 벽 띠(앞면 베이크의 아래 0.045 유닛) | 작은 패치 26,000개 + 3.5% 부드러운 얼룩. 평균 (0.60, 0.52, 0.40), std 0.03. |
| `ground_variation.png` 256² 선형 회색 | 절차 코사인 10개 | 9유닛 주기 ±5% 밝기 얼룩. 지시서의 "넓은 색 변화"를 작은 질감과 분리한 것. |
| `grass_clumps.glb` 35,692 B | 휘어진 잎 스트립·둥근 잎 부채꼴을 코드로 생성, 잎 색 그라데이션은 위 잔디와 같은 원본 색 재매핑 | 3 메시 1 재질, 256² 텍스처 내장, LOD 생성 끔(실루엣 유지). 개별 잎 추출 대신 재구성한 이유: 193만면 원본에서 잎 하나를 깨끗이 떼어내는 것보다 지시서가 허용한 "간단한 휘어진 잎 메시 + 새 공유 텍스처"가 예산 안에서 실루엣이 분명하다. |
| `ground_manifest.json` | — | 각 파일 바이트·SHA-256·방법·팔레트, 원본 해시 `2f9003c5…` 유지 확인, 참고용으로 남긴 옛 자원 목록. |

알베도를 어둡게 잡은 이유: 마을 조명(태양 0.9 + 주변광 0.6)이 배경판 `94a576`을 화면에서 (242,255,174)까지 끌어올린다. 첫 시도(알베도 0.585/0.65/0.44)는 화면에서 (255,254,175)의 창백한 연노랑이었다. 조명·노출은 건드리지 말라는 지시에 따라 알베도만 낮춰 화면에서 잔디 (198,210,143), 길 (244,205,144)이 나오게 했다. 팔레트 상수는 빌더 상단에 있고 재생성은 바이트 단위로 동일하다(확인함).

## 4. 실행 방법

```sh
tools/environment/grass/run_ground.sh                 # 텍스처·묶음 재생성(베이크 없으면 Blender로 먼저)
cd game && godot --headless --path . --import
godot --headless --path . -s tests/run_grass_tests.gd   # 126 검사
godot --path . -s tests/shoot_grass_village.gd -- --tag after [--movie <dir>]   # 실제 마을 캡처·프레임 통계
```

게임에서는 마을 진입만 하면 된다. 검토 키·바람 UI는 없다.

## 5. 실제 수행한 검증

### 5.1 같은 카메라 전/후 (후처리 없음, 1280×720)

| 장면 | 전(R2, `6e57ed9`) | 후(R3) |
|---|---|---|
| 대표 화면, (3,9)에서 | [before_stand_3_9](HWR-GRASS-001_R3_before_stand_3_9.png) | [after_stand_3_9](HWR-GRASS-001_R3_after_stand_3_9.png) |
| 오른쪽(강·보 부지·암반·창고), (11,9) | [before_stand_11_9](HWR-GRASS-001_R3_before_stand_11_9.png) | [after_stand_11_9](HWR-GRASS-001_R3_after_stand_11_9.png) |
| 전체 보기(건물 있음) | [before_overview_built](HWR-GRASS-001_R3_before_overview_built.png) | [after_overview_built](HWR-GRASS-001_R3_after_overview_built.png) |
| 진입 직후 / 전체 보기 | [before_enter](HWR-GRASS-001_R3_before_enter.png), [before_overview](HWR-GRASS-001_R3_before_overview.png) | [after_enter](HWR-GRASS-001_R3_after_enter.png), [after_overview](HWR-GRASS-001_R3_after_overview.png) |
| 길·우물 철거 후 | [before_…_demolished](HWR-GRASS-001_R3_before_stand_3_9_demolished.png) | [after_…_demolished](HWR-GRASS-001_R3_after_stand_3_9_demolished.png) |
| 걷기 클립(오른쪽 2.2초·정지·왼쪽 2.2초, 640×360 실시간) | — | [HWR-GRASS-001_R3_walk.mp4](HWR-GRASS-001_R3_walk.mp4) — 정지 풀·지면의 밝기/위치가 시간에 따라 출렁이지 않는지 확인용 |

직접 본 것: 잔디는 차분한 올리브·세이지 한 면으로 이어지고 칸 경계·네모 반복이 보이지 않는다. 흙길은 베이지 띠로 읽히고 가장자리가 불규칙하다. 묶음은 길가·나무 밑·울타리 아래에 작은 군집으로 보이며 정령 발이 파묻히지 않는다. 우물·농장 footprint와 문 앞 칸의 묶음이 사라지고 철거 후 같은 자리에 돌아온다. 강·보 부지·암반·복구 현장의 고정색이 유지된다. 지도 밖 초원이 지면과 이어진다.

### 5.2 헤드리스 검사

| 스위트 | 결과 |
|---|---|
| `run_grass_tests.gd` (R3용으로 재작성) | **126 통과, 0 실패** — 파일·manifest 해시·25 MB 한도·원본 해시 불변·텍스처 1024²·이음새(wrap 차이 ≤ 내부 차이×1.6)·저대비·색 우세·묶음 3종 예산 100~400/높이/피벗/공유 재질·마스크 좌표(길·입구·강·암반·보·복구·숲·번짐 폭·강 번짐 없음)·길 집합 변경 시에만 재생성·범위 밖 무시·배치 결정성·금지 지형 0·내부 0·길 여백 0.12·군집과 빈 칸 혼재·숨김/복원 동일 변환·stage 연결(회전 1 주택 footprint+문 앞(2,4) 숨김·공사 중 길은 흙 아님·완공 후 흙·철거 후 잔디와 묶음 복원·설치 규칙 불변)·셰이더 TIME/wind 부재·옛 GLB 가져오기 유지 |
| `run_village_tests.gd` | 101 통과 |
| `run_village_entry_tests.gd` | 28 통과 |
| `run_garden_art_tests.gd` / `run_tree_art_tests.gd` / `run_spirit_model_tests.gd` | 170 / 28 / 17 통과 |
| `run_tests.gd` (전투) | 290 통과 |

옛 검사 중 폐기한 것(지시서 6장): 타일당 LOD0 10k 이상, 150/192 고정 타일, 벽 깊이, UV2 바람 마스크, wind uniform.

### 5.3 성능 — 실제 마을(정령·건물·UI 포함), 같은 장면·카메라·그림자, vsync 끔, 240 프레임

| 장면 | 전(R2) 평균 / p95 | 후(R3) 평균 / p95 | 드로우 | 프리미티브 | VRAM |
|---|---|---|---|---|---|
| 진입 직후(건물 0, 정령 3) | 10.38 / 12.58 ms | **5.37 / 6.53 ms** | 281 → 291 | 1.81M → 1.44M | 134.0 → 125.9 MB |
| 대표 화면(우물·농장·길 2, 정령 3) | 10.09 / 11.38 ms | **6.16 / 7.45 ms** | 271 → 283 | 2.69M → 2.40M | 135.7 → 127.4 MB |

원시 값: [before_perf.json](HWR-GRASS-001_R3_before_perf.json), [after_perf.json](HWR-GRASS-001_R3_after_perf.json). 이 수치는 M4·GL Compatibility·1280×720의 전체 게임 프레임이며, R2 보고의 풀 단독 5.3 ms와는 다른 측정이다. 남은 프리미티브의 대부분은 나무·건물 아트다.

## 6. 미수행 검증과 이유

- **환경 9종과의 합본 미술 검수**: HWR-ENV-001 결과가 아직 main에 없다(로컬에 해당 worktree/브랜치 없음). 캡처의 나무·우물·울타리는 기존 garden_v1 아트다. 새 모델이 들어오면 같은 stage·같은 스크립트로 다시 찍어야 한다.
- **실제 마우스 클릭 흐름**(건설 버튼 → 미리보기 → 클릭 설치): 캡처는 컨트롤러 API(`village_place`, 실제 규칙·정령 공사)로 놓았다. 클릭 판정 자체는 바꾸지 않았고 `run_village_entry_tests`가 통과하지만 미리보기 반투명 위의 묶음 모습은 직접 보지 않았다.
- **ch1_store 템플릿의 시각 확인**: 논리 검사는 두 사이트 모두 통과하나 화면은 ch1_farm만 찍었다.
- **다른 GPU/해상도**: M4 한 대에서만 측정.

## 7. 남은 차이·한계

- 먼 언덕(`a8bbb1`, `b5c6bb`)이 어두워진 초원 위에서 이전보다 더 밝게 떠 보인다. 배경 색은 지시대로 유지했으므로 사용자 판단 항목으로 남긴다.
- 흙 텍스처는 원본에서 쓸 수 있는 흙이 앞면 0.045 유닛 띠뿐이라 큰 덩어리 무늬 없이 입자와 얼룩만 있다.
- 숲 칸(`W`) 밑의 클로버는 나무 아트 위치와 독립적으로(칸 기준 고정 seed) 놓인다. 일부는 나무 밑동에서 조금 떨어져 있을 수 있다.
- 마스크 재생성은 완공된 길이 바뀔 때 약 80 ms(GDScript 픽셀 루프). 눈에 띄면 변경 칸 주변만 갱신하도록 좁힐 수 있다.
- 묶음 3종·정적 배치 규칙 하나뿐이다. 꽃·바구니 등 콘셉트 장식은 지시대로 이번 범위가 아니다.

## 8. 사용자가 직접 확인할 항목

1. 잔디 밝기·색(화면 약 198/210/143)과 길 색(244/205/144)이 원하는 세이지·베이지인지. 조정은 `build_ground_kit.py` 상단 `GRASS_TARGET`/`DIRT_TARGET`(알베도) 또는 셰이더 uniform `grass_tint`/`dirt_tint`.
2. 묶음 밀도(마을 149개)·크기(0.10/0.076/0.20)·길 여백 0.12가 정령 발과 이동 공간 기준으로 적당한지. `GrassClumps.CLUSTER_CHANCE`, `INSET_MIN/MAX`.
3. 흙길 가장자리 폭 0.14·불규칙성이 과하거나 부족한지. `VillageGround.EDGE_OUT/EDGE_IN/EDGE_NOISE`.
4. 3유닛 잔디 반복이 실제 플레이 중 눈에 띄는지(걷기 클립·전체 보기).
5. 먼 언덕과 초원의 대비, 남쪽 흙 스커트의 두께.

## 9. 커밋과 원격 반영

- 코드·에셋: `c19cb81` `feat(HWR-GRASS-001 R3)` — `claude/hwr-grass-001`.
- 이 보고와 전/후 캡처·클립: 다음 커밋(`docs(HWR-GRASS-001 R3)`).
- 원격: `origin/claude/hwr-grass-001`에 일반 푸시(강제 푸시 없음). main 병합은 PR로 진행한다.
