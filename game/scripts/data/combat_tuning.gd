class_name CombatTuning
extends Resource
## 전투 감각 조정값. data/combat_tuning.tres 를 에디터에서 고쳐 쓴다.
## 시간값은 ms 로 적으며 60틱 고정 시뮬레이션에 맞춰 양자화된다(디버그 패널에 적용값 표시).

@export_group("지상 이동")
@export var move_speed_x: float = 300.0     ## 좌우 px/s
@export var move_speed_y: float = 200.0     ## 깊이 px/s
@export var accel_ms: float = 50.0          ## 정지→목표 속도
@export var decel_ms: float = 40.0          ## 목표 속도→정지

@export_group("입력")
@export var input_buffer_ms: float = 120.0  ## 최근 유효 행동 1개 보관 시간

@export_group("타격 정지")
@export var hitstop_light_ms: float = 35.0
@export var hitstop_strong_ms: float = 60.0

@export_group("회피")
@export var dodge_ms: float = 180.0
@export var dodge_invuln_ms: float = 100.0  ## 회피 시작부터
@export var dodge_cooldown_ms: float = 900.0
@export var dodge_distance: float = 210.0   ## 좌우 기준 이동 거리(px). 깊이는 y/x 속도비를 곱함

@export_group("점프")
@export var jump_velocity: float = 620.0    ## px/s (높이 z)
@export var gravity: float = 2500.0         ## px/s²

@export_group("플레이어")
@export var player_max_hp: int = 100
@export var player_attack: float = 20.0     ## 피해 계수 100% 기준값
@export var player_hitstun_ms: float = 300.0
@export var player_half_width: float = 22.0
@export var player_half_depth: float = 10.0
@export var player_height: float = 70.0

@export_group("적")
@export var enemy_max_hp: int = 65          ## 근접 적. 같은 깊이 평타 1세트(20+20+28=68)로 처치
@export var enemy_attack_damage: int = 10
@export var enemy_speed_x: float = 150.0
@export var enemy_speed_y: float = 110.0
@export var enemy_telegraph_ms: float = 500.0
@export var enemy_attack_active_ms: float = 100.0
@export var enemy_recover_ms: float = 800.0
@export var enemy_idle_ms: float = 400.0
@export var enemy_attack_reach: float = 80.0
@export var enemy_down_ms: float = 600.0
@export var enemy_getup_protect_ms: float = 500.0   ## 기상 보호(무적) 시간

@export_group("거점 전투")
@export var max_concurrent_attackers: int = 2      ## 근접 적 최대 동시 공격자(예고~회복 동안 허가 유지)
@export var max_ranged_attackers: int = 1          ## 궁수·투척병이 공유하는 원거리 예고/발사 허가 수
@export var max_fire_zones: int = 2                ## 방당 활성 화염 + 비행 중 예약 화염 최대
@export var room_wave_gap_ms: float = 1000.0       ## 웨이브 전멸 후 다음 웨이브 예고까지 간격
@export var room_transition_ms: float = 300.0      ## 방 이동 전이(판정·입력·대기시간 정지)

@export_group("적 궁수")
@export var archer_max_hp: int = 55
@export var archer_damage: int = 8
@export var archer_telegraph_ms: float = 650.0     ## 사격선 예고(방향·깊이 고정)
@export var archer_interval_ms: float = 2200.0     ## 발사 간격 최소
@export var archer_range: float = 560.0
@export var archer_recover_ms: float = 300.0       ## 발사 후 회복(허가 반환 시점)
@export var archer_retreat_distance: float = 100.0 ## 근접 시 후퇴 최대 거리
@export var archer_retreat_ms: float = 400.0
@export var archer_retreat_trigger: float = 130.0  ## 이 거리 안이면 후퇴 시도
@export var archer_preferred_distance: float = 380.0
@export var archer_speed_x: float = 150.0
@export var archer_speed_y: float = 110.0
@export var archer_projectile_speed: float = 650.0
@export var archer_projectile_height: float = 35.0
@export var archer_projectile_half_height: float = 4.0
@export var archer_projectile_half_depth: float = 8.0

@export_group("화염 투척병")
@export var thrower_max_hp: int = 60
@export var thrower_interval_ms: float = 4000.0    ## 투척 간격 최소
@export var thrower_range: float = 460.0
@export var thrower_windup_ms: float = 650.0       ## 준비(착탄점 고정·표시)
@export var thrower_flight_ms: float = 500.0       ## 항아리 비행(시각 연출, 착탄점 불변)
@export var thrower_recover_ms: float = 500.0
@export var thrower_preferred_distance: float = 300.0
@export var thrower_speed_x: float = 120.0
@export var thrower_speed_y: float = 100.0

@export_group("바닥 불")
@export var fire_radius_x: float = 56.0
@export var fire_radius_y: float = 28.0
@export var fire_duration_ms: float = 4000.0
@export var fire_tick_ms: float = 500.0            ## 대상별 피해 주기(첫 피해도 노출 0.5초 뒤)
@export var fire_damage: int = 3
@export var fire_max_height: float = 12.0          ## 이 높이 이하일 때만 피해

@export_group("초소 대장")
@export var captain_max_hp: int = 600
@export var captain_attack_damage: int = 12
@export var captain_slash_telegraph_ms: float = 600.0
@export var captain_slash_active_ms: float = 100.0
@export var captain_slash_recover_ms: float = 800.0
@export var captain_slash_reach: float = 110.0
@export var captain_charge_telegraph_ms: float = 800.0
@export var captain_charge_active_ms: float = 300.0   ## 이동 타격 구간
@export var captain_charge_recover_ms: float = 1000.0
@export var captain_charge_distance: float = 300.0
@export var captain_flinch_ms: float = 120.0          ## 대기·접근 중 피격 시 짧은 경직
@export var captain_speed_x: float = 120.0
@export var captain_speed_y: float = 90.0
