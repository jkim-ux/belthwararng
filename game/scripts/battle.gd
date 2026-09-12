class_name Battle
extends Node2D
## 전투 장면 컨트롤러. 개체 생성, 고정 틱 진행 순서, 적중 판정, 개발용 동작을 맡는다.
## 틱 순서: (전이 중이면 정지) → 상호작용 → 플레이어 입력 수집·진행 → 아군 진행 → 적 진행 → 항아리 → 투사체 이동
##          → 근접 적중 → 투사체 적중 → 바닥 불 → 출현·방 정리·승패 판정.
## mode: "training" (수련장: 허수아비·프로필 비교·F5/F6 허용) / "campaign" (거점 던전: 방 이동·웨이브·승패, 개발 키 없음)
## HWR-003: 거점 1회 출정(run_id 1개)은 입구 → 일반 전투방 3개 → 보스방의 던전이다. 일반 방 전멸은 room_cleared 이고,
## 보스 처치만 거점 승리(resolved victory)다. 방 이동은 체력·대기시간·동료 생존을 보존하고 공격/투사체/불은 넘기지 않는다.

const TUNING_PATH := "res://data/combat_tuning.tres"
const SKILLS_PATH := "res://data/hwarang_skills.tres"
const AIR_PATH := "res://data/attacks/air_light.tres"
const PROFILE_LEGACY_PATH := "res://data/profiles/m1_legacy.tres"
const PROFILE_R1_PATH := "res://data/profiles/r1_momentum.tres"

signal hit_applied(attacker: BattleActor, target: BattleActor, info: HitInfo)
signal resolved(outcome: StringName, run_id: String)     ## 캠페인 출정 결과(한 run 에 한 번). victory 는 보스 처치.
signal wave_started(index: int, total: int)
signal room_entered(room_id: StringName)
signal room_cleared(room_id: StringName)
signal chest_opened_signal(heal_total: int, currency: int)

@export var tuning: CombatTuning
@export var manual_step: bool = false        ## true 면 _physics_process 가 진행하지 않는다(테스트용)
@export var debug_visible: bool = true
@export var spawn_dummy: bool = true
@export var spawn_enemy: bool = true
@export var spawn_knockback_dummy: bool = true

var mode: StringName = &"training"
var arena: Arena
var actors_root: Node2D
var ground_fx_root: Node2D                   ## 바닥 불·문 표시(개체 아래)
var fx_root: Node2D                          ## 출현 예고·투사체·피해 숫자(개체 위)
var player: Player
var dummy: Dummy
var knockback_dummy: Dummy
var enemies: Array[EnemyBase] = []
var allies: Array[BattleActor] = []          ## 주인공 외 아군(동료). 판정에는 포함되고 승리 조건에는 세지 않는다.
var tick: int = 0
var paused: bool = false
var hud: Node
var debug_overlay: Node
var decor: RoomDecor
var event_log: Array[String] = []
var hits_this_run: int = 0
var parries_this_run: int = 0
var profiles: Array[CombatProfile] = []
var profile_index: int = 1                   ## 기본은 새 모멘텀 R1
var profile_switch_message: String = ""

# 캠페인 출정(run) 상태 — 새 출정에서만 초기화한다
var encounter: SiteDef
var dungeon: DungeonDef
var run_id: String = ""
var result_state: StringName = &"active"     ## active → resolved (committed 는 캠페인 컨트롤러가 처리)
var outcome: StringName = &""
var companion_def: CompanionDef
var companion: BattleActor
var kills: int = 0
var room_states: Dictionary = {}             ## room_id -> {visited, cleared}
var chest_opened: bool = false
var chest_heal_total: int = 0
var pending_currency: int = 0                ## 상자 보류 군자금. 보스 승리 시 한 번 합산, 패배/포기 시 소멸.
var run_stats: Dictionary = {}               ## room_id -> {combat_ticks, damage_taken, kills}

# 현재 방 상태 — 방 진입마다 초기화한다
var room: RoomDef
var doors_locked: bool = false
var wave_index: int = 0                      ## 다음에 출현할 웨이브 인덱스
var wave_gap_ticks: int = 0                  ## 웨이브 전멸 후 다음 예고까지 남은 틱
var pending_spawns: Array = []               ## [{kind, pos, ticks, marker}]
var transition_ticks: int = 0                ## 방 전이(판정·입력·대기시간 정지)
var pending_room_combat: bool = false        ## 전이가 끝나면 문을 잠그고 1웨이브 예고
var attack_slot_holders: Array = []          ## 근접 공격 허가를 가진 적
var ranged_slot_holders: Array = []          ## 원거리 예고/발사 허가(궁수·투척병 공유)
var projectiles: Array = []
var fires: Array = []                        ## FireZone
var pots: Array = []                         ## FirePot (비행 중 예약 화염)
var fire_clocks: Dictionary = {}             ## 대상 instance id -> 다음 피해 예정 틱
var chest: TreasureChest
var interact_prev: bool = false
var room_message: String = ""
var room_message_ticks: int = 0
var brute_hint_shown: bool = false           ## 첫 강인병 안내(출정당 1회)

# 개발용 자동 시연/스크린샷
var _screenshot_path: String = ""
var _demo_script: Array = []
var _frames: int = 0

const PLAYER_START := Vector2(300, 540)
const DUMMY_START := Vector2(700, 540)
const KNOCKBACK_DUMMY_START := Vector2(900, 520)
const ENEMY_START := Vector2(1000, 620)
const BRUTE_START := Vector2(1150, 480)      ## 수련장 강인병 표적(실제 강인병: 접근·2패턴·Q 무너짐 시험)
const CHEST_POS := Vector2(640, 545)
const DOOR_Y := 545.0

func _ready() -> void:
	if tuning == null:
		tuning = load(TUNING_PATH)
	profiles = [load(PROFILE_LEGACY_PATH), load(PROFILE_R1_PATH)]
	arena = Arena.new()
	arena.name = "Arena"
	arena.z_index = -10
	add_child(arena)
	ground_fx_root = Node2D.new()
	ground_fx_root.name = "GroundFx"
	ground_fx_root.z_index = -5
	add_child(ground_fx_root)
	decor = RoomDecor.new()
	decor.name = "RoomDecor"
	decor.battle = self
	ground_fx_root.add_child(decor)
	actors_root = Node2D.new()
	actors_root.name = "Actors"
	actors_root.y_sort_enabled = true
	add_child(actors_root)
	fx_root = Node2D.new()
	fx_root.name = "Fx"
	fx_root.z_index = 50
	add_child(fx_root)
	_spawn_player()
	if mode == &"training":
		respawn_enemies()
	hud = get_node_or_null("HUDLayer/HUD")
	debug_overlay = get_node_or_null("DebugOverlay")
	if debug_overlay != null:
		debug_overlay.visible = debug_visible
	_parse_user_args()

func arena_rect() -> Rect2:
	return arena.rect

func current_profile() -> CombatProfile:
	return profiles[profile_index]

func _spawn_player() -> void:
	var air: AttackData = load(AIR_PATH)
	var skills: SkillSet = load(SKILLS_PATH)
	player = Player.new()
	player.name = "Player"
	actors_root.add_child(player)
	player.configure(tuning, self, PLAYER_START, current_profile().light_attacks, air, skills)
	player.apply_profile(current_profile())
	player.hit_taken.connect(_on_actor_hit)

## 수련장 전용: 프로필 전환. 행동이 끝난 상태(지상 대기·사망)에서만 적용된다.
func set_profile(index: int) -> bool:
	if mode != &"training":
		return false
	index = clampi(index, 0, profiles.size() - 1)
	if player.state != &"ground" and player.state != &"dead":
		profile_switch_message = "행동이 끝난 뒤 전환됩니다"
		return false
	profile_index = index
	player.apply_profile(current_profile())
	profile_switch_message = ""
	log_event("프로필: %s" % current_profile().display_name)
	return true

func toggle_profile() -> bool:
	return set_profile((profile_index + 1) % profiles.size())

## 수련장 전용: 허수아비와 적을 다시 생성한다 (F5).
func respawn_enemies() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	if is_instance_valid(dummy):
		dummy.queue_free()
	dummy = null
	if is_instance_valid(knockback_dummy):
		knockback_dummy.queue_free()
	knockback_dummy = null
	if spawn_dummy:
		dummy = Dummy.new()
		dummy.name = "Dummy"
		actors_root.add_child(dummy)
		dummy.configure(tuning, self, DUMMY_START)
		enemies.append(dummy)
	if spawn_knockback_dummy:
		knockback_dummy = Dummy.new()
		knockback_dummy.name = "KnockbackDummy"
		actors_root.add_child(knockback_dummy)
		knockback_dummy.configure(tuning, self, KNOCKBACK_DUMMY_START, true)
		enemies.append(knockback_dummy)
	if spawn_enemy:
		spawn_melee_enemy(ENEMY_START)
		spawn_brute_enemy(BRUTE_START)
	log_event("적 재생성")

func spawn_melee_enemy(at: Vector2) -> MeleeEnemy:
	var e := MeleeEnemy.new()
	actors_root.add_child(e)
	e.configure(tuning, self, at, player)
	e.died.connect(_on_enemy_died)
	enemies.append(e)
	return e

func spawn_captain(at: Vector2, boss_name: String = "", boss_hp: int = 0) -> CaptainEnemy:
	var e := CaptainEnemy.new()
	actors_root.add_child(e)
	e.configure(tuning, self, at, player, boss_name, boss_hp)
	e.died.connect(_on_enemy_died)
	enemies.append(e)
	return e

func spawn_brute_enemy(at: Vector2) -> BruteEnemy:
	var e := BruteEnemy.new()
	actors_root.add_child(e)
	e.configure(tuning, self, at, player)
	e.died.connect(_on_enemy_died)
	enemies.append(e)
	if mode == &"campaign" and not brute_hint_shown:
		# 첫 강인병 등장 안내(출정당 1회). 입력을 잠그거나 장면을 멈추지 않는다.
		brute_hint_shown = true
		room_message = "큰 적은 공격을 받아도 버틴다. Q로 자세를 무너뜨리거나 공격을 피하라"
		room_message_ticks = 270
		log_event("강인병 등장")
	return e

func spawn_archer_enemy(at: Vector2) -> ArcherEnemy:
	var e := ArcherEnemy.new()
	actors_root.add_child(e)
	e.configure(tuning, self, at, player)
	e.died.connect(_on_enemy_died)
	enemies.append(e)
	return e

func spawn_thrower_enemy(at: Vector2) -> ThrowerEnemy:
	var e := ThrowerEnemy.new()
	actors_root.add_child(e)
	e.configure(tuning, self, at, player)
	e.died.connect(_on_enemy_died)
	enemies.append(e)
	return e

## 데이터의 종류 이름으로 적을 생성한다. &"melee" / &"brute" / &"archer" / &"thrower" / &"boss"(거점 던전의 대장) / &"captain"(기본 대장)
func spawn_enemy_kind(kind: StringName, at: Vector2) -> EnemyBase:
	# 플레이어와 바로 겹치지 않게 등장 위치를 보정한다.
	var r := arena_rect()
	if absf(at.x - player.floor_pos.x) < 120.0 and absf(at.y - player.floor_pos.y) < 40.0:
		at.x = clampf(at.x + 160.0, r.position.x + 40.0, r.end.x - 40.0)
	at.x = clampf(at.x, r.position.x + 30.0, r.end.x - 30.0)
	at.y = clampf(at.y, r.position.y, r.end.y)
	match kind:
		&"boss":
			if dungeon != null:
				return spawn_captain(at, dungeon.boss_display_name, dungeon.boss_max_hp)
			return spawn_captain(at)
		&"captain":
			return spawn_captain(at)
		&"archer":
			return spawn_archer_enemy(at)
		&"thrower":
			return spawn_thrower_enemy(at)
		&"brute":
			return spawn_brute_enemy(at)
		&"melee":
			return spawn_melee_enemy(at)
		_:
			push_warning("알 수 없는 적 종류 %s → 근접병으로 대체" % kind)
			return spawn_melee_enemy(at)

func _on_enemy_died(_actor: BattleActor) -> void:
	kills += 1
	if room != null and run_stats.has(room.id):
		run_stats[room.id].kills += 1

## 수련장 전용: 플레이어 위치·체력 초기화 (F6).
func reset_player() -> void:
	player.reset_to(PLAYER_START)
	log_event("초기화")

func _physics_process(_delta: float) -> void:
	if manual_step:
		return
	_handle_dev_input()
	if paused:
		return
	var inp: PlayerInput
	if not _demo_script.is_empty():
		inp = _next_demo_input()
	else:
		inp = PlayerInput.from_input()
	step(inp)

func _handle_dev_input() -> void:
	if Input.is_action_just_pressed(&"pause"):
		paused = not paused
	if Input.is_action_just_pressed(&"dev_screenshot"):
		_save_screenshot("user://screenshot_%d.png" % Time.get_ticks_msec())
	if Input.is_action_just_pressed(&"dev_toggle_debug") and debug_overlay != null:
		debug_overlay.visible = not debug_overlay.visible
	if mode != &"training":
		return
	if Input.is_action_just_pressed(&"dev_toggle_profile"):
		toggle_profile()
	if Input.is_action_just_pressed(&"dev_respawn_enemies"):
		respawn_enemies()
	if Input.is_action_just_pressed(&"dev_reset_player"):
		reset_player()

## 한 틱 진행. 테스트는 이 함수를 직접 호출한다.
func step(inp: PlayerInput) -> void:
	if result_state != &"active":
		return
	tick += 1
	if transition_ticks > 0:
		# 방 전이: 판정·입력·대기시간이 멈춘다(플레이어 step 을 호출하지 않으므로 대기시간도 흐르지 않는다).
		transition_ticks -= 1
		interact_prev = inp.interact
		if transition_ticks == 0:
			_finish_transition()
		return
	_handle_interact(inp)
	if transition_ticks > 0:
		return   # 이번 틱에 문 이동이 시작됨: 새 방에서는 전이가 끝날 때까지 아무도 진행하지 않는다
	player.step_with_input(inp)
	for a in allies:
		if is_instance_valid(a):
			a.step()
	for e in enemies:
		if is_instance_valid(e):
			e.step()
	_step_pots()
	_step_projectiles()
	_resolve_hits()
	_resolve_projectiles()
	_step_fires()
	_after_tick()

## 캠페인: 출현 예고·웨이브 진행·방 정리·승패 판정. 한 틱의 이동·공격·투사체·불 처리가 끝난 뒤 판단한다.
func _after_tick() -> void:
	_clean_attack_slots()
	_clean_ranged_slots()
	if mode != &"campaign" or dungeon == null or room == null:
		return
	if room_message_ticks > 0:
		room_message_ticks -= 1
	_step_spawns()
	# 같은 틱에 주인공 사망과 마지막 적(보스 포함) 사망이 함께 확인되면 패배를 우선한다.
	if not player.alive:
		_resolve(&"defeat")
		return
	if not doors_locked:
		return
	if run_stats.has(room.id):
		run_stats[room.id].combat_ticks += 1
	# 살아 있는 필수 적뿐 아니라 예정 웨이브와 출현 예고 중인 적도 확인한다.
	if required_alive_count() > 0 or not pending_spawns.is_empty():
		return
	if wave_index < room.waves.size():
		wave_gap_ticks -= 1
		if wave_gap_ticks <= 0:
			_queue_wave(wave_index)
		return
	if room.kind == &"boss":
		_resolve(&"victory")          # dungeon_completed: 살아서 보스를 처치 → 거점 승리 후보
	else:
		_clear_current_room()

func required_alive_count() -> int:
	var n := 0
	for e in enemies:
		if is_instance_valid(e) and e.alive and e.required_for_victory:
			n += 1
	return n

## 현재 방에 남은(아직 예고하지 않은) 웨이브 수
func remaining_waves() -> int:
	return room.waves.size() - wave_index if room != null else 0

func total_waves() -> int:
	return room.waves.size() if room != null else 0

func boss_enemy() -> CaptainEnemy:
	for e in enemies:
		if e is CaptainEnemy and is_instance_valid(e):
			return e
	return null

# ---------------------------------------------------------------- 캠페인 출정과 방

## 거점 출정 시작(새 run). mode 는 add_child 전에 &"campaign" 으로 두어야 한다.
## 체력·대기시간·동료 회복은 여기(새 출정)에서만 처리하고, 방 진입은 _enter_room 이 공통으로 맡는다.
func start_encounter(site: SiteDef, p_run_id: String, comp: CompanionDef, attack_power: float, max_hp: int) -> void:
	encounter = site
	dungeon = site.dungeon
	run_id = p_run_id
	kills = 0
	result_state = &"active"
	outcome = &""
	room_states.clear()
	run_stats.clear()
	for r in dungeon.rooms:
		room_states[r.id] = {"visited": false, "cleared": false}
		run_stats[r.id] = {"combat_ticks": 0, "damage_taken": 0, "kills": 0}
	chest_opened = false
	chest_heal_total = 0
	pending_currency = 0
	brute_hint_shown = false
	player.reset_to(site.player_start)
	player.attack_power = attack_power
	player.max_hp = max_hp
	player.hp = max_hp
	companion_def = comp
	if comp != null and comp.implemented:
		_spawn_companion(comp)
	log_event("%s 출정" % site.display_name)
	_enter_room(dungeon.start_room_id, &"", site.player_start)

func _spawn_companion(comp: CompanionDef) -> void:
	if comp.id != &"aya":
		return
	var c := ArcherCompanion.new()
	c.name = "Companion"
	actors_root.add_child(c)
	c.configure(tuning, self, player.floor_pos + Vector2(-comp.follow_distance, 20.0), comp, player)
	c.hit_taken.connect(_on_actor_hit)
	allies.append(c)
	companion = c

func room_state(room_id: StringName) -> Dictionary:
	return room_states.get(room_id, {"visited": false, "cleared": false})

func is_room_cleared(room_id: StringName) -> bool:
	return bool(room_state(room_id).cleared)

## 방 진입(새 출정의 첫 방과 문 이동이 같은 함수). 체력·대기시간·동료 생존은 건드리지 않는다.
## from_dir: 새 방에서 들어온 문의 방향(빈 값이면 explicit_start 위치 사용).
func _enter_room(room_id: StringName, from_dir: StringName, explicit_start: Vector2 = Vector2.INF) -> void:
	var next := dungeon.room(room_id)
	if next == null:
		push_error("없는 방 %s" % room_id)
		return
	_clear_room_transients()
	room = next
	var rs: Dictionary = room_states[room.id]
	rs.visited = true
	doors_locked = false
	wave_index = 0
	wave_gap_ticks = 0
	pending_room_combat = room.is_combat() and not rs.cleared
	# 플레이어: 반대편 문 안쪽 안전 지점. 이동량·보관 입력·공격 판정만 정리하고 체력·대기시간은 유지.
	var start := explicit_start
	if start == Vector2.INF:
		start = entry_point(from_dir)
	player.floor_pos = start
	player.velocity = Vector2.ZERO
	player.knockback_remaining = 0.0
	player.clear_buffer()
	player.end_hitboxes()
	if player.alive and player.state != &"ground":
		player.change_state(&"ground")
	if from_dir == &"west":
		player.facing = 1
	elif from_dir == &"east":
		player.facing = -1
	player.position = player.floor_pos
	if companion != null and is_instance_valid(companion) and companion.alive:
		companion.floor_pos = player.floor_pos + Vector2(-float(player.facing) * 70.0, 20.0)
		companion.velocity = Vector2.ZERO
		companion.knockback_remaining = 0.0
		companion.end_hitboxes()
		if companion.has_method("reset_for_room"):
			companion.reset_for_room()
		companion.position = companion.floor_pos
	# 보물방 상자(개봉 상태는 출정 상태에서 읽는다)
	if room.kind == &"treasure":
		chest = TreasureChest.new()
		chest.name = "Chest"
		actors_root.add_child(chest)
		chest.setup(CHEST_POS, chest_opened)
	transition_ticks = Ticks.from_ms(tuning.room_transition_ms)
	room_message = "%s" % room.display_name
	room_message_ticks = 120
	log_event("%s 진입" % room.display_name)
	room_entered.emit(room.id)

## 방을 떠날 때 정리: 적·투사체·항아리·불·예고·허가·피해 시계. 다음 방으로 넘어가지 않는다.
func _clear_room_transients() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	for pr in projectiles:
		if is_instance_valid(pr):
			pr.finish()
	projectiles.clear()
	for pot in pots:
		if is_instance_valid(pot):
			pot.finish()
	pots.clear()
	for fz in fires:
		if is_instance_valid(fz):
			fz.finish()
	fires.clear()
	fire_clocks.clear()
	for sp in pending_spawns:
		if is_instance_valid(sp.marker):
			sp.marker.queue_free()
	pending_spawns.clear()
	attack_slot_holders.clear()
	ranged_slot_holders.clear()
	if chest != null and is_instance_valid(chest):
		chest.queue_free()
	chest = null

func _finish_transition() -> void:
	if pending_room_combat:
		pending_room_combat = false
		doors_locked = true
		_queue_wave(0)

## 일반 방 정리: 문 개방, 남은 적 투사체·항아리·불 제거. 거점 보상·결과 화면을 만들지 않는다.
func _clear_current_room() -> void:
	var rs: Dictionary = room_states[room.id]
	rs.cleared = true
	doors_locked = false
	for pr in projectiles:
		if is_instance_valid(pr) and pr.team == &"enemy":
			pr.finish()
	projectiles = projectiles.filter(func(p): return is_instance_valid(p) and p.alive)
	for pot in pots:
		if is_instance_valid(pot):
			pot.finish()
	pots.clear()
	for fz in fires:
		if is_instance_valid(fz):
			fz.finish()
	fires.clear()
	fire_clocks.clear()
	ranged_slot_holders.clear()
	room_message = "방 정리 — 문이 열렸다"
	room_message_ticks = 150
	log_event("%s 정리" % room.display_name)
	room_cleared.emit(room.id)

# ---- 문 기하: 그림(RoomDecor)과 판정이 같은 함수를 쓴다

func door_point(dir: StringName) -> Vector2:
	var r := arena_rect()
	match dir:
		&"east": return Vector2(r.end.x, DOOR_Y)
		&"west": return Vector2(r.position.x, DOOR_Y)
		&"north": return Vector2(640.0, r.position.y)
		&"south": return Vector2(640.0, r.end.y)
	return r.get_center()

func door_zone(dir: StringName) -> Rect2:
	var r := arena_rect()
	match dir:
		&"east": return Rect2(r.end.x - 90.0, DOOR_Y - 55.0, 90.0, 110.0)
		&"west": return Rect2(r.position.x, DOOR_Y - 55.0, 90.0, 110.0)
		&"north": return Rect2(580.0, r.position.y, 120.0, 40.0)
		&"south": return Rect2(580.0, r.end.y - 40.0, 120.0, 40.0)
	return Rect2()

## dir 방향의 문으로 들어왔을 때 놓이는 안전 지점(문 구역 밖, 안쪽)
func entry_point(dir: StringName) -> Vector2:
	var r := arena_rect()
	match dir:
		&"west": return Vector2(r.position.x + 130.0, DOOR_Y)
		&"east": return Vector2(r.end.x - 130.0, DOOR_Y)
		&"north": return Vector2(640.0, r.position.y + 50.0)
		&"south": return Vector2(640.0, r.end.y - 60.0)
	return Vector2(r.position.x + 130.0, DOOR_Y)

## 플레이어가 서 있는 문 {dir, target_id} 또는 빈 사전
func door_at_player() -> Dictionary:
	if dungeon == null or room == null:
		return {}
	for door in dungeon.doors_of(room):
		if door_zone(door.dir).has_point(player.floor_pos):
			return door
	return {}

func _player_can_interact() -> bool:
	return player.alive and player.state == &"ground" and player.height <= 0.0 and player.hitstop_ticks <= 0

## HUD/문 표시용 안내 문구
func interact_prompt() -> String:
	if mode != &"campaign" or room == null or result_state != &"active" or transition_ticks > 0:
		return ""
	var door := door_at_player()
	if not door.is_empty():
		var target := dungeon.room(door.target_id)
		var name := target.display_name if target else String(door.target_id)
		if doors_locked:
			return "문이 잠겼다 — 적을 모두 처치"
		if not _player_can_interact():
			return "%s (지상에서 Enter)" % name
		return "Enter: %s 로 이동" % name
	if chest != null and is_instance_valid(chest) and chest.near(player.floor_pos):
		return "상자를 이미 열었다" if chest_opened else "Enter: 상자 열기"
	return ""

## 새 누름만 받는다(길게 누르기로 왕복하지 않도록). 지상 대기/이동 중에만 가능.
func _handle_interact(inp: PlayerInput) -> void:
	var pressed := inp.interact and not interact_prev
	interact_prev = inp.interact
	if not pressed or mode != &"campaign" or room == null:
		return
	if not _player_can_interact():
		return
	var door := door_at_player()
	if not door.is_empty():
		if doors_locked:
			room_message = "문이 잠겼다 — 적을 모두 처치하라"
			room_message_ticks = 90
			return
		use_door(door.dir)
		return
	if chest != null and is_instance_valid(chest) and chest.near(player.floor_pos):
		open_chest()

## 문 이동. 열린 문이어야 하며 성공하면 true.
func use_door(dir: StringName) -> bool:
	if dungeon == null or room == null or doors_locked or transition_ticks > 0 or result_state != &"active":
		return false
	for door in dungeon.doors_of(room):
		if door.dir == dir:
			_enter_room(door.target_id, DungeonDef.opposite(dir))
			return true
	return false

## 보물 상자: run 당 1회. 생존 아군 최대 체력 20% 회복(초과 없음·부활 없음), 군자금 30 보류.
func open_chest() -> Dictionary:
	if chest_opened or room == null or room.kind != &"treasure" or dungeon == null:
		return {"ok": false, "reason": "이미 열었거나 상자 없음"}
	chest_opened = true
	var healed := 0
	for a in alive_allies():
		var amount := int(round(float(a.max_hp) * dungeon.chest_heal_ratio))
		var before := a.hp
		a.hp = mini(a.max_hp, a.hp + amount)
		healed += a.hp - before
	chest_heal_total = healed
	pending_currency += dungeon.chest_currency
	if chest != null and is_instance_valid(chest):
		chest.opened = true
	room_message = "상자 개봉: 체력 +%d, 군자금 %d 은 보스 승리 시 획득" % [healed, dungeon.chest_currency]
	room_message_ticks = 240
	log_event("상자 개봉 (+%d 회복, 보류 %d)" % [healed, dungeon.chest_currency])
	chest_opened_signal.emit(healed, dungeon.chest_currency)
	return {"ok": true, "healed": healed, "currency": dungeon.chest_currency}

func _queue_wave(index: int) -> void:
	if room == null or index >= room.waves.size():
		return
	var w: EncounterWave = room.waves[index]
	wave_index = index + 1
	wave_gap_ticks = Ticks.from_ms(tuning.room_wave_gap_ms)
	var delay := Ticks.from_ms(w.spawn_delay_ms)
	for i in w.enemy_kinds.size():
		var pos: Vector2 = w.spawn_positions[i] if i < w.spawn_positions.size() else Vector2(1000, 560 + 40 * i)
		var marker := SpawnMarker.new()
		marker.ticks_total = delay
		marker.ticks_left = delay
		marker.position = pos
		fx_root.add_child(marker)
		pending_spawns.append({"kind": w.enemy_kinds[i], "pos": pos, "ticks": delay, "marker": marker})
	wave_started.emit(index + 1, room.waves.size())
	log_event("%s 웨이브 %d/%d 출현 예고" % [room.display_name, index + 1, room.waves.size()])

func _step_spawns() -> void:
	var remaining: Array = []
	for sp in pending_spawns:
		sp.ticks -= 1
		if is_instance_valid(sp.marker):
			sp.marker.ticks_left = sp.ticks
		if sp.ticks <= 0:
			if is_instance_valid(sp.marker):
				sp.marker.queue_free()
			spawn_enemy_kind(sp.kind, sp.pos)
		else:
			remaining.append(sp)
	pending_spawns = remaining

## 결과 확정: 한 run 에 한 번. 남은 판정·투사체·불을 지워 결과 창 뒤에서 피해가 나지 않게 한다.
func _resolve(p_outcome: StringName) -> void:
	if result_state != &"active":
		return
	result_state = &"resolved"
	outcome = p_outcome
	for a in all_actors():
		a.end_hitboxes()
	for pr in projectiles:
		if is_instance_valid(pr):
			pr.finish()
	projectiles.clear()
	for pot in pots:
		if is_instance_valid(pot):
			pot.finish()
	pots.clear()
	for fz in fires:
		if is_instance_valid(fz):
			fz.finish()
	fires.clear()
	fire_clocks.clear()
	for sp in pending_spawns:
		if is_instance_valid(sp.marker):
			sp.marker.queue_free()
	pending_spawns.clear()
	player.clear_buffer()
	log_event("승리" if p_outcome == &"victory" else ("패배" if p_outcome == &"defeat" else "출정 포기"))
	resolved.emit(p_outcome, run_id)

## 출정 포기(캠페인). 보상(상자 보류 포함) 없이 결과를 확정한다.
func abandon() -> void:
	if mode == &"campaign":
		_resolve(&"abandon")

# ---------------------------------------------------------------- 공격 허가 (근접 2 / 원거리 1)

func request_attack_slot(e: BattleActor) -> bool:
	_clean_attack_slots()
	if attack_slot_holders.has(e):
		return true
	if attack_slot_holders.size() >= tuning.max_concurrent_attackers:
		return false
	attack_slot_holders.append(e)
	return true

func release_attack_slot(e: BattleActor) -> void:
	attack_slot_holders.erase(e)

func _clean_attack_slots() -> void:
	var keep: Array = []
	for e in attack_slot_holders:
		if is_instance_valid(e) and e.alive:
			keep.append(e)
	attack_slot_holders = keep

## 원거리 예고/발사 허가(궁수·투척병 공유). 아야(아군)는 소모하지 않는다.
func request_ranged_slot(e: BattleActor) -> bool:
	_clean_ranged_slots()
	if ranged_slot_holders.has(e):
		return true
	if ranged_slot_holders.size() >= tuning.max_ranged_attackers:
		return false
	ranged_slot_holders.append(e)
	return true

func release_ranged_slot(e: BattleActor) -> void:
	ranged_slot_holders.erase(e)

func _clean_ranged_slots() -> void:
	var keep: Array = []
	for e in ranged_slot_holders:
		if is_instance_valid(e) and e.alive:
			keep.append(e)
	ranged_slot_holders = keep

# ---------------------------------------------------------------- 투사체

func add_projectile(pr: Projectile) -> void:
	fx_root.add_child(pr)
	projectiles.append(pr)

func _step_projectiles() -> void:
	var r := arena_rect()
	for pr in projectiles:
		if is_instance_valid(pr) and pr.alive:
			pr.step(r)

## 투사체 판정: 이전 위치~현재 위치의 이동 구간·깊이·높이를 대상과 비교한다(빠른 화살이 대상을 뚫고 지나가지 않게).
## 같은 팀은 관통, 명중 시 단일 대상 피해 후 제거. 최대 사거리·수명이 끝난 마지막 구간도 판정한 뒤 제거한다.
func _resolve_projectiles() -> void:
	var actors := all_actors()
	var keep: Array = []
	for pr in projectiles:
		if not is_instance_valid(pr) or not pr.alive:
			continue
		for target in actors:
			if target.team == pr.team or not target.can_be_hit():
				continue
			if not _ranges_overlap(pr.x_range(), target.hurt_x_range()):
				continue
			if not _ranges_overlap(pr.y_range(), target.hurt_y_range()):
				continue
			if not _ranges_overlap(pr.z_range(), target.hurt_z_range()):
				continue
			var info := HitInfo.new()
			info.attacker = pr.shooter
			info.attack = pr.attack
			info.damage = pr.damage
			info.hitstop_ticks = 0
			info.direction = pr.facing
			if target.receive_hit(info):
				hits_this_run += 1
				hit_applied.emit(pr.shooter, target, info)
				_spawn_damage_number(target, info)
				_spawn_hit_flash(target, info)
				var shooter_name: String = pr.shooter.display_name if (pr.shooter != null and is_instance_valid(pr.shooter)) else "화살"
				log_event("%s → %s %d" % [shooter_name, target.display_name, roundi(info.damage)])
				pr.finish()
				break
		if pr.alive and pr.expiring:
			pr.finish()
		if pr.alive:
			keep.append(pr)
	projectiles = keep

# ---------------------------------------------------------------- 항아리와 바닥 불

## 활성 화염 + 비행 중 예약 화염이 방당 최대치 미만인가
func fire_slot_available() -> bool:
	return fires.size() + pots.size() < tuning.max_fire_zones

func fire_slots_used() -> int:
	return fires.size() + pots.size()

## 착탄 가능한 지점인가: 방 안의 바닥이고 문 진입/출현 안전 지점이 아니어야 한다.
func valid_fire_target(p: Vector2) -> bool:
	var r := arena_rect().grow(-20.0)
	if not r.has_point(p):
		return false
	for dir in [&"east", &"west", &"north", &"south"]:
		if p.distance_to(entry_point(dir)) < 80.0:
			return false
	for sp in pending_spawns:
		if p.distance_to(sp.pos) < 60.0:
			return false
	return true

## 항아리 던지기(예약 화염 1개 소모). 자리가 없으면 false.
func throw_fire_pot(from: Vector2, target: Vector2) -> FirePot:
	if not fire_slot_available():
		return null
	var pot := FirePot.new()
	pot.setup(from, target, Ticks.from_ms(tuning.thrower_flight_ms), tuning.fire_radius_x, tuning.fire_radius_y, arena_rect())
	fx_root.add_child(pot)
	pots.append(pot)
	return pot

func _step_pots() -> void:
	var keep: Array = []
	for pot in pots:
		if not is_instance_valid(pot) or not pot.alive:
			continue
		if pot.step():
			_spawn_fire(pot.target)
			pot.finish()
		else:
			keep.append(pot)
	pots = keep

func _spawn_fire(at: Vector2) -> FireZone:
	var fz := FireZone.new()
	fz.setup(at, tuning.fire_radius_x, tuning.fire_radius_y, Ticks.from_ms(tuning.fire_duration_ms), arena_rect())
	ground_fx_root.add_child(fz)
	fires.append(fz)
	log_event("불 착탄 (%.0f, %.0f)" % [at.x, at.y])
	return fz

func fire_at(p: Vector2) -> FireZone:
	for fz in fires:
		if is_instance_valid(fz) and fz.alive and fz.contains(p):
			return fz
	return null

func is_in_fire(p: Vector2) -> bool:
	return fire_at(p) != null

## 대상이 불에 노출된 상태인가(발 위치 안, 높이 이하, 살아 있음)
func _exposed_to_fire(a: BattleActor) -> bool:
	return a.alive and a.height <= tuning.fire_max_height and is_in_fire(a.floor_pos)

## 불 피해: 대상별 시계로 0.5초마다. 첫 노출 때 0.5초 뒤를 예약하고, 예정 틱에 불 밖/공중/무적이면 건너뛴다(몰아 넣지 않음).
## 겹친 불 위에서도 대상당 주기는 하나다. 경직·밀림·히트스톱을 주지 않고 체력·무적·사망만 처리한다.
## 수명 마지막 틱의 판정을 마친 뒤 불을 제거한다. 시계는 방에 불이 하나도 없으면 정리한다.
func _step_fires() -> void:
	if fires.is_empty():
		if not fire_clocks.is_empty():
			fire_clocks.clear()
		return
	var period := Ticks.from_ms(tuning.fire_tick_ms)
	var targets: Array[BattleActor] = []
	if player.alive:
		targets.append(player)
	for a in allies:
		if is_instance_valid(a) and a.alive:
			targets.append(a)
	for a in targets:
		var key := a.get_instance_id()
		if not fire_clocks.has(key):
			if _exposed_to_fire(a):
				fire_clocks[key] = tick + period
			continue
		if tick < int(fire_clocks[key]):
			continue
		fire_clocks[key] = int(fire_clocks[key]) + period
		if _exposed_to_fire(a) and a.can_be_hit():
			_apply_burn(a, tuning.fire_damage)
	# 수명: 이번 틱 판정을 마친 뒤 나이를 올리고 만료된 불을 제거한다.
	var keep: Array = []
	for fz in fires:
		if not is_instance_valid(fz) or not fz.alive:
			continue
		fz.age += 1
		if fz.expired():
			fz.finish()
		else:
			keep.append(fz)
	fires = keep
	if fires.is_empty():
		fire_clocks.clear()

func _apply_burn(a: BattleActor, dmg: int) -> void:
	var applied := a.receive_burn(dmg)
	if applied <= 0:
		return
	if a == player and room != null and run_stats.has(room.id):
		run_stats[room.id].damage_taken += applied
	if fx_root != null:
		var dn := DamageNumber.new()
		dn.text = str(applied)
		dn.color = Color(1.0, 0.6, 0.2)
		dn.position = a.floor_pos + Vector2(randf_range(-8, 8), -a.height - a.body_height - 6)
		fx_root.add_child(dn)
	log_event("불 → %s %d" % [a.display_name, applied])

func all_actors() -> Array[BattleActor]:
	var out: Array[BattleActor] = [player]
	for a in allies:
		if is_instance_valid(a):
			out.append(a)
	for e in enemies:
		if is_instance_valid(e):
			out.append(e)
	return out

## 살아 있는 아군(주인공 포함). 적의 대상 선택에 쓴다.
func alive_allies() -> Array[BattleActor]:
	var out: Array[BattleActor] = []
	if player.alive:
		out.append(player)
	for a in allies:
		if is_instance_valid(a) and a.alive:
			out.append(a)
	return out

func alive_enemies() -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	for e in enemies:
		if is_instance_valid(e) and e.alive:
			out.append(e)
	return out

## 적중 판정: 좌우 거리, 깊이 차이, 높이 범위를 모두 확인한다.
## 같은 공격 인스턴스와 대상 조합에는 한 번만 피해를 준다. 같은 팀끼리는 피해가 없다.
## HWR-004: 대상마다 처리 전에 소유자 생존·판정 취소 여부를 다시 확인한다(같은 틱에 Q·경직·사망으로 거둔 판정의 복사본이
## 다음 대상에게 잔여 피해를 주지 않게). 주인공의 흘려받기(guard)는 receive_hit 이전 바깥 판정 계층에서 처리한다.
func _resolve_hits() -> void:
	var actors := all_actors()
	for attacker in actors:
		if attacker.active_hitboxes.is_empty() or not attacker.alive:
			continue
		for hb in attacker.active_hitboxes.duplicate():
			for target in actors:
				if not attacker.alive or hb.cancelled or not attacker.active_hitboxes.has(hb):
					break
				if target == attacker or target.team == attacker.team:
					continue
				if hb.already_hit(target):
					continue
				if not target.can_be_hit():
					continue
				if not _overlaps(hb, attacker, target):
					continue
				var info := HitInfo.new()
				info.attacker = attacker
				info.attack = hb.attack
				info.damage = hb.damage
				info.hitstop_ticks = hb.hitstop_ticks
				info.direction = 1 if target.floor_pos.x >= attacker.floor_pos.x else -1
				info.knockback = hb.knockback
				info.hit_index = hb.hit_index
				info.action_id = hb.action_id
				info.source_pos = attacker.floor_pos
				info.attacker_facing = hb.facing
				if target is Player and target.try_parry(info):
					# 방어 성공: 이 타격·대상은 처리 완료로 기록(다음 활성 틱 재피해 없음). 피해·경직·타격 정지 없음.
					hb.mark_hit(target)
					parries_this_run += 1
					_spawn_parry_flash(target)
					log_event("%s 가 %s 의 %s 을 흘려받음" % [target.display_name, attacker.display_name, hb.attack.display_name])
					continue
				if target.receive_hit(info):
					hb.mark_hit(target)
					attacker.on_hit_confirmed(hb.hitstop_ticks)
					hits_this_run += 1
					hit_applied.emit(attacker, target, info)
					_spawn_damage_number(target, info)
					_spawn_hit_flash(target, info)
					log_event("%s → %s %d" % [attacker.display_name, target.display_name, roundi(info.damage)])

static func _ranges_overlap(a: Vector2, b: Vector2) -> bool:
	return a.x <= b.y and b.x <= a.y

func _overlaps(hb: HitBox, attacker: BattleActor, target: BattleActor) -> bool:
	if hb.ellipse:
		# 바닥 타원(공격자 발 중심) 안의 대상 발 위치 + 높이 겹침. 예고 타원과 같은 반경을 쓴다.
		if not hb.in_ellipse(attacker.floor_pos, target.floor_pos):
			return false
		return _ranges_overlap(hb.world_z_range(attacker.height), target.hurt_z_range())
	var xr := hb.world_x_range(attacker.floor_pos)
	if not _ranges_overlap(xr, target.hurt_x_range()):
		return false
	var yr := hb.world_y_range(attacker.floor_pos)
	if not _ranges_overlap(yr, target.hurt_y_range()):
		return false
	var zr := hb.world_z_range(attacker.height)
	if not _ranges_overlap(zr, target.hurt_z_range()):
		return false
	return true

func _spawn_damage_number(target: BattleActor, info: HitInfo) -> void:
	if fx_root == null:
		return
	var dn := DamageNumber.new()
	dn.text = str(roundi(info.damage))
	dn.color = Color(1.0, 0.95, 0.5) if target.team == &"enemy" else Color(1.0, 0.4, 0.4)
	dn.position = target.floor_pos + Vector2(randf_range(-10, 10), -target.height - target.body_height - 10)
	fx_root.add_child(dn)

## 흘려받기 성공 표시: 피해 숫자 없이 푸른 섬광과 문구
func _spawn_parry_flash(target: BattleActor) -> void:
	if fx_root == null:
		return
	var fl := HitFlash.new()
	fl.strong = false
	fl.life = 0.18
	fl.color = Color(0.5, 0.85, 1.0)
	fl.position = target.floor_pos + Vector2(float(target.facing) * 30.0, -target.height - target.body_height * 0.55)
	fx_root.add_child(fl)
	var dn := DamageNumber.new()
	dn.text = "흘려받기"
	dn.color = Color(0.6, 0.9, 1.0)
	dn.position = target.floor_pos + Vector2(0, -target.height - target.body_height - 10)
	fx_root.add_child(dn)

func _spawn_hit_flash(target: BattleActor, info: HitInfo) -> void:
	if fx_root == null:
		return
	var fl := HitFlash.new()
	fl.strong = info.attack.strong
	if info.hitstop_ticks <= 0:
		fl.life = 0.1
		fl.color = Color(0.85, 0.95, 1.0)
	fl.position = target.floor_pos + Vector2(0, -target.height - target.body_height * 0.55)
	fx_root.add_child(fl)

func _on_actor_hit(actor: BattleActor, info: HitInfo) -> void:
	if actor == player and room != null and run_stats.has(room.id):
		run_stats[room.id].damage_taken += maxi(1, roundi(info.damage))
	if actor == player and not player.alive:
		log_event("쓰러짐" + (" (F6 초기화)" if mode == &"training" else ""))

func log_event(s: String) -> void:
	event_log.append("[%d] %s" % [tick, s])
	if event_log.size() > 8:
		event_log.pop_front()

# ---------------------------------------------------------------- 개발용 자동 시연
func _parse_user_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshot="):
			_screenshot_path = a.trim_prefix("--screenshot=")
		elif a == "--demo":
			_demo_script = _build_demo_script()

## 스크린샷·검증용 입력 대본: [틱 수, 이동 벡터, 눌린 행동들]
func _build_demo_script() -> Array:
	return [
		[62, Vector2(1, 0), []],
		[8, Vector2(1, 0.4), []],
		[1, Vector2.ZERO, ["attack_light"]],
		[12, Vector2.ZERO, []],
		[1, Vector2.ZERO, ["attack_light"]],
		[12, Vector2.ZERO, []],
		[1, Vector2.ZERO, ["attack_light"]],
		[8, Vector2.ZERO, []],
	]

func _next_demo_input() -> PlayerInput:
	var entry: Array = _demo_script[0]
	var inp := PlayerInput.make(entry[1], entry[2])
	entry[0] -= 1
	if entry[0] <= 0:
		_demo_script.pop_front()
	# 대본 소진 뒤에는 입력 없음
	return inp

func _process(_delta: float) -> void:
	_frames += 1
	if _screenshot_path != "" and _demo_script.is_empty() and _frames > 5:
		var p := _screenshot_path
		_screenshot_path = ""
		await _save_screenshot(p)
		get_tree().quit()

func _save_screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	log_event("스크린샷 %s (%d)" % [path, err])
	print("screenshot saved: ", path, " err=", err)
