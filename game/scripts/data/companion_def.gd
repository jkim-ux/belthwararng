class_name CompanionDef
extends Resource
## 동료 정의. 처음에는 궁수만 implemented=true. 능력치는 데이터로 조절한다.

@export var id: StringName = &""
@export var display_name: String = ""
@export var role: String = ""
@export var unlock_chapter_id: StringName = &""
@export var implemented: bool = false
@export_multiline var description: String = ""
@export_multiline var join_text: String = ""

@export_group("전투 (궁수 초기값)")
@export var max_hp: int = 60
@export var attack_damage: float = 7.0
@export var fire_interval_ms: float = 1500.0
@export var aim_ms: float = 250.0
@export var attack_range: float = 360.0
@export var follow_distance: float = 100.0
@export var move_speed_x: float = 260.0
@export var move_speed_y: float = 170.0
@export var projectile_speed: float = 600.0
@export var projectile_max_distance: float = 360.0
@export var projectile_life_ms: float = 600.0
@export var projectile_height: float = 35.0
@export var projectile_half_height: float = 4.0
@export var projectile_half_depth: float = 4.0
