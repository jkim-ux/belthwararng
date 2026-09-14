# 마을 환경 에셋 — Tripo 제작 목록

작성: 2026-09-14 UTC
관련 작업: [풀 HWR-GRASS-001](../TO_CLAUDE_GRASS.md) / [환경 9종 HWR-ENV-001](../TO_CLAUDE_ENVIRONMENT.md)
원본 상세: [파일 경로·SHA-256 목록](ENVIRONMENT_SOURCE_INVENTORY.json)

사용자가 요청한 현재 마을의 환경·시설을 단독 콘셉트 이미지로 제작하는 목록이다. 풀밭과 곧은 줄기 나무 외에 단독 콘셉트 이미지 21종을 제공했다. 콘셉트 이미지 수와 업로드된 3D 모델 수는 다르다. 이는 마을 세계관이나 게임 기능을 추가하는 기획 변경이 아니다.

## 아트와 이미지 사용

- 기준: 기존 구름 온실 원안의 따뜻한 크림/꿀빛 목재, 세이지·올리브 잎, 연보라 포인트, 둥근 모서리와 섬세한 표면.
- 나무는 사용자의 최신 요청대로 곧은 줄기와 간결한 가지를 사용한다. 이전 S자 나무로 되돌리지 않는다. tree/flower_tree의 기존 공유 방식은 실제 적용 시 확인한다.
- 각 이미지는 한 물체 또는 한 시설 조립체를 보여준다. 무지 배경, 전체 외곽이 보이는 사선 시점, 주변 지형과 주민 제외.
- 콘셉트 이미지는 대화에 개별 생성되어 제공된다. 이 문서가 이미지 PNG나 3D 모델을 저장소에 함께 올렸다는 뜻은 아니다.
- 번호/이름은 이미지와 결과 GLB를 맞추기 위한 권장 이름이다. Tripo에 이미지를 한 장씩 각각 새 작업으로 넣는다. 다른 물체를 앞/뒤/옆 멀티뷰로 넣지 않는다.

## 단독 이미지와 기존 에셋 대응

| 파일명 기준 | 대상 | 기존 연결 | 조립 메모 |
|---|---|---|---|
| 01_fence | 울타리 | fence | 한 구간을 반복 배치. 끝 기둥이 이중으로 겹치지 않게 접합. |
| 02_rock | 이끼 바위 | rock | 동일 바위의 회전·비율 변형으로 자연스럽게 묶음 구성. |
| 03_planter | 꽃상자 | planter | 상자·흙 고정. 꽃 흔들림은 후속 마스크 작업. |
| 04_lantern | 가로등 | lantern | 발광·야간 광원은 엔진에서 추가. |
| 05_cloud_sign | 구름 표지판 | cloud_sign / repair 일부 | 구름은 그림 표식. 글자나 신규 안내 기능 없음. |
| 06_basket | 빈 수확 바구니 | basket | 수확물은 별도 기존 작물/열매로 채움. |
| 07_stepping_stone | 디딤돌 | road / repair 일부 | 한 개를 반복 조합. 길 전체를 한 GLB로 생성하지 않음. |
| 08_farm_bed | 빈 밭 | farm_0~3 공통 바닥 | 같은 바닥에 09~11의 작물을 배치. |
| 09_crop_seedling | 새싹 | farm_1 작물 | 기존 성장 규칙의 첫 단계에 연결. |
| 10_crop_growing | 성장 중 작물 | farm_2 작물 | 잎과 크기가 자라난 단계. 생산 수치 유지. |
| 11_crop_ripe | 수확할 작물 | farm_3 작물 | 열매가 있는 성숙 단계. 같은 식물 계열로 크기 보정. |
| 12_well | 돌우물 | well | 모델의 고정된 물 표면은 실제 엔진 물 재질과 구분. |
| 13_canal | 직선 수로 | VillageStage3D의 canal | 기본 틀. 물은 별도 표시하고 모서리/분기는 엔진 접합 부품으로 확장. |
| 14_waterwheel | 물레바퀴 | wheel | 회전축 중심 피벗, 보와 분리해 기존 회전에 연결. |
| 15_cottage | 정령 주택 | cottage / house | 기존 점유 칸·입구 방향 유지. |
| 16_greenhouse | 구름 온실 | greenhouse | 기존 장식/표시 용도. 신규 농업 기능을 자동 추가하지 않음. |
| 17_shed | 보급 창고 | shed / 보급 시설 | 기존 시설 효과·점유 크기 유지. |
| 18_lumber_workshop | 목재 작업장 | lumber | 기존 생산·주민 배정 유지. |
| 19_quarry_workshop | 석재 작업장 | quarry | 기존 생산·주민 배정 유지. |
| 20_training | 수련장 | training | 고정된 수련 장치. 기존 시설 강화 규칙 유지. |
| 21_dam | 작은 보 | dam | 14 물레바퀴와 별도 물 표면을 조합. |

빈 밭에 새싹/성장/성숙 작물을 교체하여 기존 4개 farm 표시를 만든다. road와 repair는 디딤돌 및 표지판 조합을 재사용한다. 따라서 기존 에셋 ID 수와 새로 생성할 이미지 수는 일대일로 같지 않다. 물의 흐름·바람·발광·물레 회전은 별도 엔진 효과이며 이미지에 고정된 특수효과로 굳히지 않는다.

## 실제 원본 폴더와 업로드 현황

사용자가 정한 `source_assets/environments/` 구조를 유지한다. `objects/`는 개별 물체/건물, `tiles/`는 반복 지면이다. 기존 파일을 예시 이름으로 바꾸거나 재업로드할 필요는 없다.

**2026-09-14 원격 확인: 풀 1종 + 환경 9종.**

| 실제 파일명 | 하위 폴더 | 담당/기존 표시 ID | 원본이 확인된 위치 |
|---|---|---|---|
| `fence.glb` | objects | fence | claude/hwr-grass-001 |
| `greenhouse.glb` | objects | greenhouse | claude/hwr-grass-001 |
| `rock.glb` | objects | rock | main |
| `signpost.glb` | objects | cloud_sign | claude/hwr-grass-001 |
| `stone well.glb` | objects | well | main |
| `stone workbench.glb` | objects | quarry | claude/hwr-grass-001 |
| `tree 3d model.glb` | objects | tree / flower_tree | main |
| `warehouse.glb` | objects | shed | main |
| `wood workbench.glb` | objects | lumber | claude/hwr-grass-001 |
| `grass block 3d model.glb` | tiles | 풀 담당 | main |

게임 구현은 main `22a21cf974479cb6fc213fe9c0120e31520db6d1`에 병합됐다. 나머지 5개 원본은 풀 브랜치 `5544f88aa4c17a288f655fffd348ea19e90dce42`에 있으며, 같은 커밋에 풀 셰이더/제작 도구/중간 파일도 있다. 환경 담당은 새 worktree에서 **원본 경로만** 가져온다. 해당 커밋 통째 cherry-pick/병합은 하지 않는다. [환경 작업 지시](../TO_CLAUDE_ENVIRONMENT.md)의 절차를 따른다.

여기서는 Git tree와 LFS 포인터를 확인했다. 실물 다운로드·새 원본의 면수/UV 검사는 담당자가 수행하고 결과를 기록한다. 우물 해시는 대화에서 수정·검수한 투명 물 버전과 일치한다. 해당 물 재질과 수면 아래 깊이를 보존한다.

꽃상자·가로등·바구니·밭/작물·수로·물레·주택·수련장·보 등 표에 없는 원본은 확인 시점에 미업로드다. 기존 표시를 유지하고 실제 새 파일이 들어오면 같은 절차로 입력 목록을 갱신한다. 이미지가 있다는 이유로 GLB도 모두 있다고 가정하지 않는다.

원본은 LFS에 보관하고 경량화 결과만 `game/assets/environment/objects/` 및 풀 담당 폴더에서 사용한다. 입력 파일별 정확한 크기와 해시는 [inventory](ENVIRONMENT_SOURCE_INVENTORY.json)를 참고한다.

## 사용자 제작 순서

1. 울타리·바위·꽃상자·가로등으로 색감과 모델 재현을 먼저 확인한다.
2. 빈 밭·작물 3단계·우물·수로·바구니를 만든다.
3. 주택·온실·창고·생산시설·수련장·보/물레를 만든다.

이 순서는 Tripo에서 모델로 만드는 순서이며 콘셉트 이미지 제공을 미루라는 뜻은 아니다.

## Tripo 설정과 전달

- Image to 3D, 한 이미지/한 작업. 초기에는 Segmentation과 캐릭터 리깅을 사용하지 않는다.
- 단순 목재/석재 물체는 Smart Mesh부터 시험한다. 잎·꽃·직조를 보존하기 어려운 물체는 High Detail 원본을 먼저 확보하고 게임용 감면을 별도로 한다.
- 텍스처 2K부터 시작한다. 확대해 쓰는 큰 건물이나 잎 디테일에 필요하면 4K를 쓴다. 모든 물체를 무조건 최대 면수로 게임에 넣지 않는다.
- GLB와 텍스처 포함으로 내보낸다. 영구적으로 움직일 부품인 물레는 보와 따로 만든다.
- 새 파일명 예: `01_fence_source.glb`, `14_waterwheel_source.glb`. 울타리·물레 등 물체는 `source_assets/environments/objects/`, 지면 타일은 `source_assets/environments/tiles/`에 둔다 (Godot 프로젝트 game 폴더 밖). 기존 나무·풀의 공백 있는 파일명은 그대로 사용할 수 있다.
- 원본은 LFS로 업로드한다. 최종 결과에 원본 hash/출처를 기록한다. 받은 GLB의 면수·UV·재질·구멍·법선·크기를 확인하고 게임용은 별도 출력한다.
- 텍스처에 색과 형태가 보이는 것과 실제 메시가 그만큼 세분된 것은 다르다. 실물 모델의 뒷면·밑면과 옆면을 회전해 확인한다.
- 게임 적용 시 기존 카메라·마을 규모·저장·생산 규칙을 유지한다. 단순해진 건물 때문에 기능을 삭제하거나 새 소품 때문에 신규 기능을 추가하지 않는다.
