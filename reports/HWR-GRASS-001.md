# HWR-GRASS-001 완료 보고 — Tripo 풀밭 경량화·타일 정리·바람 미리보기

- 읽은 지시서: [TO_CLAUDE_GRASS.md](../TO_CLAUDE_GRASS.md), [CLAUDE.md](../CLAUDE.md), [reports/README.md](README.md), [docs/ENVIRONMENT_ASSET_KIT.md](../docs/ENVIRONMENT_ASSET_KIT.md)
- 시작: 2026-09-14 14:45 KST (05:45 UTC) / 완료: 2026-09-14 16:00 KST (07:00 UTC)
- 상태: **완료** (플레이 감각·실제 화면에서의 이음새 판단은 사용자 확인 항목)
- 작업 브랜치: `claude/hwr-grass-001` (구현 브랜치 `claude/magical-bohr-2eljuj`의 `a166113`에서 `origin/main` `04cc5be`를 병합한 `4add888`에서 분기)
- 지시서가 요구한 기준 확인: 승인된 정령·곧은 나무·작은 마을(16×12)·측면 카메라·자유로운 밭 설치는 건드리지 않았다. 전투·경제·저장 데이터 변경 없음.

## 1. 엔진과 실행 환경

| 항목 | 값 |
|---|---|
| 엔진 | Godot 4.7.2 stable (`4.7.2.stable.official.ed1daf0bf`), macOS, **GL Compatibility** (프로젝트 설정 그대로) |
| 기기 | MacBook (Apple M4, 16 GB), macOS 26.6.2, 창 1280×720 (프로젝트 해상도), 실제 GPU·창 사용 |
| 제작 도구 | Blender 5.2.1 LTS (`brew install --cask blender`, 헤드리스 EEVEE), Python 3.12.9 + numpy 2.5.2 + Pillow 12.2.0, ffmpeg 9.0.1, glTF 검증 `@gltf-transform/cli validate` |
| 이번 세션에서 설치한 것 | Godot 4.7.2, Blender 5.2.1, ffmpeg (Homebrew). 저장소 밖 설정만 바꿨다. |

## 2. 원본 확인 (지시서 1장)

`source_assets/environments/tiles/grass block 3d model.glb` — LFS 실물을 받아 검사했다.

| 항목 | 측정값 | 지시서 값과 비교 |
|---|---|---|
| 크기 | 60,363,036 bytes | 일치 |
| SHA-256 | `2f9003c54d01f66b76af992fb2eb5f48449dfeac78a16e9c95b9c207beee7363` | 일치 |
| 헤더 / 버전 | `glTF`, 2 (generator Tripo) | 일치 |
| 메시/재질/노드 | 1 / 1 / 1, POSITION·NORMAL·TEXCOORD_0, uint32 인덱스 | 일치 |
| 정점 / 삼각형 | 1,053,084 / 1,929,690 | 일치 |
| 경계 상자 | x ±0.4887, y 0~0.1454, z ±0.4902 | 일치 |
| 텍스처 | JPEG 4096² 3장 (basecolor, metallic/roughness, normal) | 일치 |
| 열린 변 / 비다양체 변 / 퇴화 삼각형 / 뒤집힌 법선 | 172,364 / 0 / 0 / 7 | 풀잎이 열린 껍질(닫힌 부피가 아님) |
| 바닥면 (y < 0.01) | 104,094 삼각형, 면적 0.89 (거의 전체 발자국) | 보이지 않는 면에 5% 예산이 들어가 있음 |
| 흙 옆벽 | y 0~0.058, x·z 약 ±0.455~0.466 (완전 직사각이 아니고 뒤쪽 둔덕이 0.012 더 안쪽) | 타일 규격으로 가정하지 않음 |
| 풀층 | y 0.06~0.145, 흙 윗면(풀 사이로 보이는 흙)은 0.078~0.107 | |
| RM 텍스처 | roughness 0.92 ± 0.04, metallic ≈ 0.03 (거의 상수) | ORM 텍스처를 따로 내보내지 않고 재질 상수로 대체 |

풀과 흙은 한 재질이다. 색(R>G면 흙)·높이·법선으로 영역을 나눴고 Tripo Segmentation은 쓰지 않았다. 같은 조명·카메라의 기준 이미지는 Blender(관찰용)와 Godot(제출용, 아래 4장)에서 각각 확보했다. 함께 올라온 나무·다른 물체 원본은 건드리지 않았다.

## 3. 결정: 단순 감면 대신 재구성 + 베이크

Blender Collapse Decimate로 40k → 20k → 10k 후보를 만들어 같은 카메라로 비교했다(스크래치 렌더, 게임 파일과 분리, 저장소에 넣지 않음).

- 40k에서 이미 Tripo 아틀라스의 UV 섬이 서로 무너지며 **흰 이음새 줄**이 앞면 전체에 생기고, 풀끝이 사라진 채 울퉁불퉁한 껍질만 남았다. 20k/10k는 더 심했다.
- 원본 텍스처를 그대로 연결할 수 없는 상태라 지시서 B-3의 "흙 바닥 + 낮은 풀 표면 + 실루엣 풀잎 묶음" 재구성으로 전환하고, 새 UV에 맞춰 원본에서 **다시 베이크**했다.

재구성 결과(타일 하나):

| 부품 | 형상 | 삼각형 | 역할 |
|---|---|---:|---|
| 풀 표면 | 128×64 높이장(2.0 × 0.9 world) | 16,384 | 큰 굴곡·둔덕 실루엣, 베이크된 BaseColor/Normal이 잔 잎·클로버를 담당 |
| 흙 옆벽 | 4면 띠, 윗변을 풀 표면 가장자리에 용접, 아래 −0.2 | 768 | 고정(바람 마스크 0), 이웃과 붙여도 틈·빛샘 없음 |
| 풀끝 카드 | 앞·뒤 변에 alpha scissor 카드 2장 | 4 | 정면 실루엣(원본 앞 0.07 띠를 투명 배경으로 렌더) |
| 합계 LOD0 | | **17,156** | 예산 10~20k 안 |
| 바닥면·풀 아래 흙 윗면 | 만들지 않음 | 0 | 보이지 않는 면 |

- 원본은 x/y/z **균등** 2.1978배(흙 벽 폭 0.91 → 2.0)로 쓰고 깊이는 0.9(=0.4095 원본 단위) 띠만 잘라 쓴다. 풀을 늘리지 않는다. 변형 a는 뒤쪽 띠, b는 앞쪽 띠 → 180° 회전까지 4가지 모습, 인스턴스마다 ±4.5% 밝기 변화.
- 텍스처: 변형마다 2048×1536 아틀라스 2장(sRGB BaseColor+alpha, tangent-space Normal). 위 1024행 풀 윗면, 256행 흙 벽(세로 2회 반복 띠, 가로 타일링), 256행 풀끝 카드. 4K는 필요 없었다(마을 카메라에서 칸 하나가 약 170×26 px).
- 접합: 네 변의 바깥 3.5%(x)·5%(z) 띠의 **높이·색·법선을 하나의 대칭 공유 패치로 크로스페이드**해 어떤 타일(회전 포함)끼리 붙여도 높이 단차·텍스처 끊김이 없다. 4×4·16×12 배치에서 직선 틈·z-fighting·빛샘은 없었다. 위에서 내려다보면 접합 띠가 거울 대칭으로 보이는 것이 남은 흔적이다(아래 한계).
- 피벗: 타일 중심, **y=0 = 가장 낮은 풀/흙 지점(마을 바닥면)**, 풀 평균 +0.10, 풀끝 +0.19, 옆벽 −0.2(수로 −0.12보다 아래). 발자국 2.0×0.9 = `VillageStage3D.CELL_W × CELL_D`. manifest에 기록.
- 바람 마스크: `TEXCOORD_1.x` (흙 벽·뿌리 0 → 풀끝 1, 높이와 영역을 결합), `.y` 부품 ID. COLOR_0을 쓰지 않은 이유: glTF 뷰어와 Godot 기본 재질이 정점색을 BaseColor에 곱해 단순 가져오기가 붉게 물든다(직접 확인).
- 법선: 베이크한 세계 법선을 각 텍셀의 높이장 접선 프레임으로 변환했다. 뒤집힌(아래를 보는) 잎 법선은 뒤집어 보정. Godot 가져오기에서 tangent 생성(`ensure_tangents`) 유지.
- 베이크 방식: 정사 투영 emission 렌더(조명 없음)라 cage/ray 거리로 옆 잎·흙 색이 잘못 찍히는 문제는 없다. 대신 위에서 안 보이는 잎 옆면은 위 잎 색을 물려받는다.

## 4. 제출물

| 파일 | 내용 |
|---|---|
| `game/assets/environment/grass/grass_tile_a.glb` / `_b.glb` | 최종 텍스처 포함 GLB. 7,826,956 / 7,960,584 bytes, SHA-256 `af3f0cea8fc3d7d0…` / `557e0d945ada05f2…` (전체 값은 manifest). Git LFS(`*.glb` 규칙). glTF 검증: 오류 0, 경고 0, 정보 2(NPOT 2048×1536 — Godot는 문제 없음). |
| `game/assets/environment/grass/grass_tile_{a,b}.glb.import` | `generate_lods=true`, `ensure_tangents=true`, 텍스처 **Basis Universal 내장**(`embedded_image_handling=2`, wind_spirit와 같은 방식) → 가져온 장면 6.03 MB, PNG 추출 파일 없음 |
| `grass_manifest.json` | 원본/결과 해시·용량·정점·삼각형·텍스처·단위·피벗·고정 영역·LOD·출처(사용자 제공 Tripo 모델)·도구 버전 |
| `grass_wind.gdshader` | 바람 정점 셰이더 + 베이크 재질 (아래 5장) |
| `grass_tile.gd` (`GrassTile`) | 변형별 메시·ShaderMaterial 1회 로드·공유, 바람 uniform 일괄 설정, LOD 삼각형 조회 |
| `grass_field.gd` (`GrassField`) | 칸 목록 → (4×4 칸 지역 × 변형)별 MultiMesh, 회전·색 변화, 건물 밑 타일 숨김(변환 0 스케일), 그림자 토글 |
| `grass_review.tscn` / `grass_review.gd` | 단독 검토 장면: 1·2×2·4×4·마을 칸(150)·전체(192) 배치, 마을/근접/위/전경 카메라, 바람 ON/OFF·세기, 원본(193만) 나란히 표시, 그림자·vsync 토글, 프레임 시간·draw call·삼각형·VRAM 표시 |
| `game/scripts/village/village_stage_3d.gd` | 실제 마을 연결: `.`·`W`(숲 바닥)·`e`(입구) 칸에 풀, 물·길·밭·암반·공사터 제외. 설치·공사 중 건물 발자국 밑 타일 숨김(미리보기는 풀 위에 반투명). 좌표 계약·클릭 판정(Y=0 평면)·길찾기 변경 없음 |
| `game/tests/run_grass_tests.gd` | 헤드리스 57개 검사 (아래 7장) |
| `game/tests/shoot_grass.gd`, `shoot_grass_village.gd` | 캡처·성능표·영상 프레임, 실제 게임 마을 캡처 |
| `tools/environment/grass/run.sh`, `bake_grass_views.py`, `build_grass_tile.py`, `README.md` | **명령 한 번 재생성** (`tools/environment/grass/run.sh` → Blender 약 10초 + numpy 약 9초, 이후 `godot --headless --path game --import`) |

Godot 가져오기 LOD(엔진 생성, 두 변형 동일): **17,156 → 4,289 → 2,144 → 1,072 → 536 → 268** 삼각형. 지시서 표의 LOD1(2,000~5,000)·LOD2(100~500) 구간이 모두 포함된다. 직교 카메라라 줌 단계별로 고정 선택되며 MultiMesh는 지역(4×4 칸) 단위로 LOD가 정해진다.

## 5. 바람

`grass_wind.gdshader` (spatial, `cull_disabled`, alpha scissor 0.5, roughness 0.92, metallic 0).

- 위상 = 세계 좌표·시간 함수(`k·(dot(xz, dir) − speed·t)`, 파장 5, 속도 1.6, 2차 고조파, 느린 돌풍 변조). 타일·회전 인스턴스가 같은 파동을 이어 받는다(`MODEL_MATRIX` 역변환으로 모델 공간에 적용). 인스턴스별 색은 MultiMesh custom data.
- 변위 = `wind_amplitude(0.012) × strength × mask × (0.35 + sway)`: 세기 1에서 풀 높이 0.19의 약 6~10%. 세기 0이면 정확히 원래 자세. 흙 벽 아래는 mask 0, 윗변은 용접된 풀 가장자리와 같은 마스크(그렇지 않으면 바람에 벽 윗변이 벌어져 검은 틈이 생기는 것을 확인하고 고쳤다).
- `wind_sheen`(0.07): 같은 위상으로 밝기를 살짝 흔들어 마을 줌(칸 26 px)에서도 바람이 읽힌다. 변위만으로는 1 px 남짓이다.
- 컬링: `extra_cull_margin 0.35`로 변위·카드가 화면 가장자리에서 잘리지 않는다. 그림자 패스도 같은 정점 셰이더를 지나므로 그림자가 제자리에 고정되는 문제는 없다. 법선은 바람에 따라 회전시키지 않는다(변위가 작아 눈에 띄는 조명 오류 없음).
- 풀끝 카드는 조각 셰이더에서 법선을 항상 위로 둔다(뒷면을 볼 때 Godot가 법선을 뒤집어 카드가 검게 되던 것을 고침). 카드는 앞·뒤 변에만 있다. 좌·우 변 카드는 측면 카메라에서 정확히 옆으로 보여 칸마다 세로 줄이 생기는 것을 확인하고 뺐다.
- 영상: `reports/HWR-GRASS-001_wind.mp4` (실제 Godot 창, 4×4 근접 카메라, 960×540, 24 fps, 7초, 2.1 MB; 3.5초 지점에서 세기 1.2 → 2.5). 정지 이미지 `_wind_off_close.png` / `_wind_on_close.png` / `_wind_strong_close.png`.

## 6. 성능 (실측, Godot 4.7.2 GL Compatibility, Apple M4, 1280×720, vsync OFF, 그림자 ON, 워밍업 30프레임 후 240프레임)

카메라는 마을과 같은 직교 20° 측면 카메라(크기 8.5), 그래서 화면에 들어오는 칸은 가로 약 7.5칸 × 세로 12칸 ≈ 90칸이다. `frame ms`는 `Time.get_ticks_usec` 차이의 평균/95백분위(엔진 FPS 카운터는 1초 단위 갱신이라 참고값). 삼각형·draw call은 그림자 패스를 포함한 엔진 모니터 값.

| 구성 | 타일 | 평균 ms | p95 ms | draw call | 삼각형/프레임 | VRAM |
|---|---:|---:|---:|---:|---:|---:|
| **원본 1개** (193만, 마을 카메라) | 1 | **3.64** | 5.22 | 4 | 3,877,608 | 307.5 MB |
| 결과 1개 | 1 | **0.84** | 1.03 | 2 | 17,692 | 77.4 MB |
| 16개 바람 OFF | 16 | 1.53 | 2.09 | 4 | 35,384 | 77.4 MB |
| 16개 바람 ON | 16 | 1.58 | 2.03 | 4 | 35,384 | 77.4 MB |
| 마을 칸 150개 바람 OFF | 150 | 5.46 | 6.76 | 38 | 302,908 | 77.4 MB |
| 마을 칸 150개 바람 ON | 150 | 5.41 | 6.49 | 38 | 302,908 | 77.4 MB |
| 192개 바람 OFF | 192 | 5.35 | 6.54 | 30 | 215,520 | 77.4 MB |
| 192개 바람 ON | 192 | **5.29** | 6.50 | 30 | 215,520 | 77.4 MB |
| 192개 바람 ON, 그림자 OFF | 192 | 3.55 | 4.69 | 12 | 205,872 | 77.4 MB |

- 원본 1개(3.6 ms, VRAM 307 MB)보다 결과 1개(0.8 ms, 77 MB)가 가볍고, 192개를 깔아도 5.3 ms(약 190 fps)로 16.7 ms 안이다. 바람 셰이더는 측정 오차 안(±0.1 ms). 그림자 패스가 약 1.8 ms를 차지한다(그림자를 끄면 `GrassField.set_cast_shadows(false)`).
- VRAM 77.4 MB는 검토 장면 전체(빈 장면 기준값을 따로 재지 않음). 풀 텍스처는 Basis Universal → GPU 압축 포맷으로 올라간다.
- 192개의 삼각형 수가 150개보다 적은 것은 화면 밖 지역 MultiMesh가 컬링되고 원거리 지역에 LOD가 선택되기 때문이다.
- 한계: Mac M4 한 대의 값이며 Windows/다른 GPU·실제 마을(정령·건물·UI 포함) 프레임은 재지 않았다. 실제 마을 화면은 캡처만 했다.

원본 데이터 `reports/HWR-GRASS-001_perf.json`.

## 7. 검증

실행한 것과 결과:

```sh
cd game
godot --headless --path . -s tests/run_grass_tests.gd          # 57 passed, 0 failed
godot --headless --path . -s tests/run_village_tests.gd        # COMPACT VILLAGE: 101 passed, 0 failed
godot --headless --path . -s tests/run_village_entry_tests.gd  # Village entry: 28 passed, 0 failed
godot --headless --path . -s tests/run_garden_art_tests.gd     # GARDEN ART: 170 passed, 0 failed
godot --headless --path . -s tests/run_tree_art_tests.gd       # TREE ART: 28 passed, 0 failed
godot --headless --path . -s tests/run_spirit_model_tests.gd   # SPIRIT MODEL: 17 passed, 0 failed
godot --path . -s tests/shoot_grass.gd                         # 캡처 18장 + perf.json (실제 창)
godot --path . --fixed-fps 24 -s tests/shoot_grass.gd -- --movie=/tmp/grass_frames && ffmpeg -framerate 24 -i /tmp/grass_frames/f_%04d.jpg -c:v libx264 -pix_fmt yuv420p -crf 23 ../reports/HWR-GRASS-001_wind.mp4
godot --path . -s tests/shoot_grass_village.gd                 # 실제 게임 마을 캡처 4장 (테스트 저장만 사용 후 삭제)
npx @gltf-transform/cli validate game/assets/environment/grass/grass_tile_a.glb   # errors 0, warnings 0
```

`run_grass_tests.gd`가 확인하는 것: GLB 실물(헤더 `glTF`, 25,000,000 bytes 이하), 가져오기 성공·서피스 1개, LOD0 10k~25k, 엔진 LOD에 2k~5k와 100~500 구간 존재, 발자국 2.0×0.9·피벗 중심·벽 −0.2·풀끝 높이, UV2/tangent/normal 존재, 벽 아래 정점 마스크 0·풀끝 정점 마스크 ≈1, 아틀라스 2048×1536·재질 텍스처 연결, 셰이더 uniform 노출과 바인딩, 192칸 MultiMesh 인스턴스·지역 묶음(12~24개)·칸 중심 원점·회전 혼합·숨김 상태 추적·공유 바람 uniform, 실제 `VillageStage3D`가 ch1 농촌에서 150칸(`.`139+`W`9+`e`2)에만 풀을 만들고 강·길 칸에는 만들지 않음. 헤드리스 더미 렌더러는 MultiMesh 인스턴스 변환을 되읽지 못하므로 숨김은 상태 추적으로 검사했다.

캡처(모두 실제 Godot 창, 1280×720, 마을과 같은 조명·배경색):

| 파일 | 내용 |
|---|---|
| `HWR-GRASS-001_compare_single_village_cam.png` / `_close.png` / `_top.png` | 왼쪽 원본(193만 삼각형, 같은 배율·오프셋) ↔ 오른쪽 결과 1개, 마을 카메라·근접·위 |
| `_seam_2x2_close.png` / `_seam_2x2_top.png` | 2×2 접합(변형 a/b·회전 혼합) — 틈·단차·z-fighting 없음, 위에서 보면 접합 띠의 거울 대칭이 보임 |
| `_tiles_16_village_cam.png` / `_tiles_16_top.png` | 4×4 반복 무늬 검사 |
| `_tiles_150_village_cam.png` / `_tiles_150_overview.png` | 실제 마을 칸 집합(강·길·밭·공사터 제외) |
| `_tiles_192_village_cam.png` / `_tiles_192_overview.png` | 상한 192개 |
| `_wind_off_close.png` / `_wind_on_close.png` / `_wind_strong_close.png`, `_wind.mp4` | 바람 |
| `_village_game_enter.png` / `_overview.png` / `_stand_4_4.png` / `_stand_11_9.png` | **실제 게임**(새 게임 → 농촌 출정 승리 → 마을 입장)에서 풀·길·나무·울타리·정령·플레이어 발 위치 |

직접 본 결과: 마을 카메라에서 풀은 연속된 평평한 땅으로 읽히고 각 칸이 화분처럼 분리되지 않는다. 원본과 같은 황록색·클로버 잎이 남아 있고, 정면 가장자리(맵 앞줄·길 옆)에 흙 벽과 풀끝 실루엣이 나온다. 발은 풀 속에 잠기고 정강이가 보인다(풀 평균 0.10). 길 줄(`p`)은 풀보다 낮아 눌린 길처럼 보인다.

## 8. 품질 손실과 남은 한계

- 풀 표면은 높이장이라 원본처럼 잎이 겹쳐 뻗는 실루엣은 정면 카드에만 남고, 근접 카메라에서는 뾰족한 둔덕(70백분위 풀링)으로 보인다. 마을 줌에서는 구분되지 않는다. 지시서의 "잎 묶음" 대신 카드 2장으로 정면 실루엣을 대신했고, 좌·우 변에는 실루엣이 없다.
- 위에서 내려다보는 카메라에서 접합 띠(3.5%/5%)가 거울 대칭 무늬로 보인다. 측면 20° 카메라에서는 확인되지 않았다. 변형 2개 + 회전으로 4가지 모습이라 16×12에서 같은 배치가 반복되는 느낌은 남는다. 변형을 더 늘리면 텍스처 메모리가 변형당 약 25 MB(비압축 기준) 늘어난다.
- 결과 타일이 같은 조명에서 원본보다 조금 밝고 노란 쪽이다(표면이 평평해져 정면광을 더 받음). 색 바램·번쩍임은 아니지만 톤 조정이 필요하면 `grass_wind.gdshader`의 albedo 곱 또는 재베이크에서 조정할 수 있다.
- 마을 줌에서 바람 변위는 1 px 수준이고 밝기 잔물결이 대부분의 인상을 만든다. 정령 돌풍·발 밟힘 반응은 지시대로 후속.
- 명시적으로 만든 LOD 메시 대신 Godot 가져오기 LOD를 쓴다. 직교 카메라라 줌 단계별로 사실상 고정이고, 근접 검토 카메라에서만 LOD0 전체가 쓰인다.
- 길·물·밭 칸과 풀 칸의 경계에서는 풀 타일 옆벽(흙)이 0~0.1 정도 드러난다. 의도한 모습이지만 길 줄이 눌려 보이는 정도는 사용자 판단이 필요하다.
- 숲 칸(`W`)에도 풀을 깔았다(나무 밑 바닥). 원치 않으면 `VillageStage3D.GRASS_TERRAIN`에서 빼면 된다.
- 건물 밑 타일 숨김은 설치·공사 중 건물만 대상이고 미리보기 상태는 풀 위에 반투명으로 겹친다. 설치 클릭·미리보기·주민 발 위치·가림 로직은 변경하지 않았고 마을 회귀 검사(101+28)가 통과했다.
- 성능은 Mac M4 한 대에서만 쟀다.

## 9. 사용자가 직접 확인할 항목

1. 실제 화면 크기에서 마을을 걸어 다니며 칸 경계·반복 무늬가 눈에 띄는지, 풀 높이(발이 잠기는 정도)가 원하는 느낌인지.
2. `grass_review.tscn`(F6)에서 `W`·`-`/`=`로 바람 세기, `O`로 원본과 나란히 비교, `S`로 그림자 유무의 차이.
3. 길 줄이 풀보다 낮아 보이는 것을 유지할지, 길·밭용 타일을 별도로 만들지.
4. 숲 바닥·입구 칸의 풀 여부, 건물 미리보기 밑 풀 표시.

## 10. 커밋과 원격 반영

- 작업 기준 커밋: `a166113` (원본 업로드) + `04cc5be` (지시서, main) → 병합 `4add888`. 새 브랜치 `claude/hwr-grass-001`에서 작업.
- 작업 중 사용자가 같은 브랜치에 새 원본(`fence.glb`, `rock.glb`, `stone well.glb`, `plant.glb`, `seedling.glb`, `streetlamp wood.glb`, `signpost.glb`, `warehouse.glb`, `greenhouse.glb`, 작업대 등)을 `bab0e00`·`6d4b071`·`5544f88`·`ed0f95c`로 커밋했다. 이 커밋들은 그대로 두었고 원본 파일도 건드리지 않았다.
  - `5544f88`(other objects)·`ed0f95c`(work in progress)에는 제작 중이던 스크래치 폴더 `tools/environment/grass/build/`(베이크 .npy 등 약 227 MB)가 함께 들어갔다. 사용자 요청으로 브랜치 이력을 정리했다: 두 커밋을 `build/`만 뺀 같은 내용으로 다시 만들고 그 위에 작업 커밋 하나를 올려 `--force-with-lease`로 다시 푸시했다(정리 전 마지막 커밋 `80000e2`는 로컬 reflog에 남아 있다). `.gitignore`에 `build/`를 추가했다.
- 이 보고를 포함한 커밋이 실제 구현 전체다(해시는 git 로그 참조). 원격 `origin/claude/hwr-grass-001`에 푸시하고 main으로 PR을 열었다. 게임용 GLB는 `.gitattributes`의 `*.glb` 규칙에 따라 LFS로 올라간다.
