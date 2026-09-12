class_name AttackData
extends Resource
## 평타·스킬 한 동작의 정의 데이터. 실행 중 상태(남은 틱, 적중 기록)는 여기 두지 않는다.
## 시간은 ms 단위로 적고 실행 시 Ticks.from_ms 로 양자화한다.

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("구간 (ms)")
@export var startup_ms: float = 80.0      ## 준비
@export var active_ms: float = 50.0       ## 타격
@export var recovery_ms: float = 160.0    ## 회복
## 다음 평타·스킬로 연결할 수 있는 구간. 동작 종료 전 마지막 N ms.
@export var chain_window_ms: float = 100.0
## 이동·회피로 넘어갈 수 있는 구간(스킬용). 회복 구간 마지막 N ms. 0이면 종료 후에만.
@export var move_cancel_ms: float = 0.0
## 타격 구간이 끝난 뒤 회피 허용 (평타용)
@export var dodge_after_active: bool = true

@export_group("피해")
@export var damage_mult: float = 1.0       ## 공격력 계수 (1.2 = 120%)
@export var strong: bool = false           ## true면 강공격 타격 정지(60 ms) 사용
@export var hitstun_ms: float = 300.0      ## 맞은 대상의 경직
@export var knockback: float = 40.0        ## 대상이 밀리는 거리(px), 타격 정지 후 경직 동안 감속하며 이동
@export var launch: bool = false           ## 일반 적을 짧게 띄움
@export var launch_velocity: float = 520.0 ## 띄우기 초기 상승 속도 (px/s)

@export_group("판정 범위 (바닥 좌표 기준, 공격자 발 위치 기준)")
@export var reach_forward: float = 90.0    ## 바라보는 방향으로의 도달 거리
@export var reach_back: float = 10.0       ## 뒤쪽 여유
@export var depth_tolerance: float = 22.0  ## 허용 깊이 차이(±y)
@export var z_min: float = -10.0           ## 공격자 발 높이 기준 아래 한계
@export var z_max: float = 90.0            ## 공격자 발 높이 기준 위 한계

@export_group("이동")
@export var dash_distance: float = 0.0     ## 타격 구간 동안 전진하는 거리 (비연참)
@export var self_launch: bool = false      ## 사용자가 직접 점프하는 동작(현재 미사용)

func startup_ticks() -> int:
	return Ticks.from_ms(startup_ms)

func active_ticks() -> int:
	return Ticks.from_ms(active_ms)

func recovery_ticks() -> int:
	return Ticks.from_ms(recovery_ms)

func total_ticks() -> int:
	return startup_ticks() + active_ticks() + recovery_ticks()

func chain_window_ticks() -> int:
	return Ticks.from_ms(chain_window_ms)

func move_cancel_ticks() -> int:
	return Ticks.from_ms(move_cancel_ms)
