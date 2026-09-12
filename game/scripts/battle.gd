class_name Battle
extends Node2D
## 전투 장면 컨트롤러. 개체 생성, 고정 틱 진행 순서, 적중 판정, 개발용 동작을 맡는다.
## 틱 순서: 플레이어 입력 수집·진행 → 아군 진행 → 적 진행 → 적중 처리.
## mode: "training" (수련장: 허수아비·프로필 비교·F5/F6 허용) / "campaign" (거점 전투: 웨이브·승패, 개발 키 없음)

const TUNING_PATH := "res://data/combat_tuning.tres"
const SKILLS_PATH := "res://data/hwarang_skills.tres"
const AIR_PATH := "res://data/attacks/air_light.tres"
const PROFILE_LEGACY_PATH := "res://data/profiles/m1_legacy.tres"
const PROFILE_R1_PATH := "res://data/profiles/r1_momentum.tres"

signal hit_applied(attacker: BattleActor, target: BattleActor, info: HitInfo)
signal resolved(outcome: StringName, run_id: String)     ## 캠페인 전투 결과(한 run 에 한 번)
signal wave_started(index: int, total: int)

@export var tuning: CombatTuning
@export var manual_step: bool = false        ## true 면 _physics_process 가 진행하지 않는다(테스트용)
@export var debug_visible: bool = true
@export var spawn_dummy: bool = true
@export var spawn_enemy: bool = true
@export var spawn_knockback_dummy: bool = true

var mode: StringName = &"training"
var arena: Arena
var actors_root: Node2D
var fx_root: Node2D
var player: Player
var dummy: Dummy
var knockback_dummy: Dummy
var enemies: Array[EnemyBase] = []
var allies: Array[BattleActor] = []          ## 주인공 외 아군(동료). 판정에는 포함되고 승리 조건에는 세지 않는다.
var tick: int = 0
var paused: bool = false
var hud: Node
var debug_overlay: Node
var event_log: Array[String] = []
var hits_this_run: int = 0
var profiles: Array[CombatProfile] = []
var profile_index: int = 1                   ## 기본은 새 모멘텀 R1
var profile_switch_message: String = ""

# 캠페인 전투
var encounter: SiteDef
var run_id: String = ""
var wave_index: int = 0                      ## 다음에 출현할 묶음 인덱스
var pending_spawns: Array = []               ## [{kind, pos, ticks, marker}]
var result_state: StringName = &"active"     ## active → resolved (committed 는 캠페인 컨트롤러가 처리)
var outcome: StringName = &""
var attack_slot_holders: Array = []          ## 공격 허가를 가진 적
var companion_def: CompanionDef
var companion: BattleActor
var projectiles: Array = []
var kills: int = 0

# 개발용 자동 시연/스크린샷
var _screenshot_path: String = ""
var _demo_script: Array = []
var _frames: int = 0

const PLAYER_START := Vector2(300, 540)
const DUMMY_START := Vector2(700, 540)
const KNOCKBACK_DUMMY_START := Vector2(900, 520)
const ENEMY_START := Vector2(1000, 620)

func _ready() -> void:
	if tuning == null:
		tuning = load(TUNING_PATH)
	profiles = [load(PROFILE_LEGACY_PATH), load(PROFILE_R1_PATH)]
	arena = Arena.new()
	arena.name = "Arena"
	arena.z_index = -10
	add_child(arena)
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
	log_event("적 재생성")

func spawn_melee_enemy(at: Vector2) -> MeleeEnemy:
	var e := MeleeEnemy.new()
	actors_root.add_child(e)
	e.configure(tuning, self, at, player)
	e.died.connect(_on_enemy_died)
	enemies.append(e)
	return e

func spawn_captain(at: Vector2) -> CaptainEnemy:
	var e := CaptainEnemy.new()
	actors_root.add_child(e)
	e.configure(tuning, self, at, player)
	e.died.connect(_on_enemy_died)
	enemies.append(e)
	return e

func spawn_enemy_kind(kind: StringName, at: Vector2) -> EnemyBase:
	# 플레이어와 바로 겹치지 않게 등장 위치를 보정한다.
	var r := arena_rect()
	if absf(at.x - player.floor_pos.x) < 120.0 and absf(at.y - player.floor_pos.y) < 40.0:
		at.x = clampf(at.x + 160.0, r.position.x + 40.0, r.end.x - 40.0)
	at.x = clampf(at.x, r.position.x + 30.0, r.end.x - 30.0)
	at.y = clampf(at.y, r.position.y, r.end.y)
	match kind:
		&"captain":
			return spawn_captain(at)
		_:
			return spawn_melee_enemy(at)

func _on_enemy_died(_actor: BattleActor) -> void:
	kills += 1

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
	player.step_with_input(inp)
	for a in allies:
		if is_instance_valid(a):
			a.step()
	for e in enemies:
		if is_instance_valid(e):
			e.step()
	_step_projectiles()
	_resolve_hits()
	_resolve_projectiles()
	_after_tick()

## 캠페인: 출현 예고·묶음 진행·승패 판정. 한 틱의 이동·공격·투사체·피격 처리가 끝난 뒤 판단한다.
func _after_tick() -> void:
	_clean_attack_slots()
	if mode != &"campaign" or encounter == null:
		return
	_step_spawns()
	# 같은 틱에 주인공 사망과 마지막 적 사망이 함께 확인되면 패배를 우선한다.
	if not player.alive:
		_resolve(&"defeat")
		return
	if required_alive_count() == 0 and pending_spawns.is_empty():
		if wave_index < encounter.waves.size():
			_queue_wave(wave_index)
		else:
			_resolve(&"victory")

func required_alive_count() -> int:
	var n := 0
	for e in enemies:
		if is_instance_valid(e) and e.alive and e.required_for_victory:
			n += 1
	return n

func remaining_waves() -> int:
	return encounter.waves.size() - wave_index if encounter != null else 0

# ---------------------------------------------------------------- 캠페인 전투

## 거점 전투 시작. mode 는 add_child 전에 &"campaign" 으로 두어야 한다.
func start_encounter(site: SiteDef, p_run_id: String, comp: CompanionDef, attack_power: float, max_hp: int) -> void:
	encounter = site
	run_id = p_run_id
	wave_index = 0
	kills = 0
	result_state = &"active"
	outcome = &""
	player.reset_to(site.player_start)
	player.attack_power = attack_power
	player.max_hp = max_hp
	player.hp = max_hp
	companion_def = comp
	if comp != null and comp.implemented:
		_spawn_companion(comp)
	log_event("%s 출정" % site.display_name)
	_queue_wave(0)

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

func _queue_wave(index: int) -> void:
	if encounter == null or index >= encounter.waves.size():
		return
	var w: EncounterWave = encounter.waves[index]
	wave_index = index + 1
	var delay := Ticks.from_ms(w.spawn_delay_ms)
	for i in w.enemy_kinds.size():
		var pos: Vector2 = w.spawn_positions[i] if i < w.spawn_positions.size() else Vector2(1000, 560 + 40 * i)
		var marker := SpawnMarker.new()
		marker.ticks_total = delay
		marker.ticks_left = delay
		marker.position = pos
		fx_root.add_child(marker)
		pending_spawns.append({"kind": w.enemy_kinds[i], "pos": pos, "ticks": delay, "marker": marker})
	wave_started.emit(index + 1, encounter.waves.size())
	log_event("적 묶음 %d/%d 출현 예고" % [index + 1, encounter.waves.size()])

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

## 결과 확정: 한 run 에 한 번. 남은 판정·투사체를 지워 결과 창 뒤에서 피해가 나지 않게 한다.
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
	for sp in pending_spawns:
		if is_instance_valid(sp.marker):
			sp.marker.queue_free()
	pending_spawns.clear()
	player.clear_buffer()
	log_event("승리" if p_outcome == &"victory" else ("패배" if p_outcome == &"defeat" else "출정 포기"))
	resolved.emit(p_outcome, run_id)

## 출정 포기(캠페인). 보상 없이 결과를 확정한다.
func abandon() -> void:
	if mode == &"campaign":
		_resolve(&"abandon")

# ---------------------------------------------------------------- 공격 허가 (근접 적 동시 공격자 제한)

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

# ---------------------------------------------------------------- 투사체

func add_projectile(pr: Projectile) -> void:
	fx_root.add_child(pr)
	projectiles.append(pr)

func _step_projectiles() -> void:
	var r := arena_rect()
	var keep: Array = []
	for pr in projectiles:
		if not is_instance_valid(pr) or not pr.alive:
			continue
		pr.step(r)
		if pr.alive:
			keep.append(pr)
	projectiles = keep

## 투사체 판정: 좌우·깊이·높이를 대상과 비교한다. 아군은 관통, 명중 시 단일 대상 피해 후 제거.
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
				log_event("%s → %s %d" % [pr.shooter.display_name if pr.shooter else "화살", target.display_name, roundi(info.damage)])
				pr.finish()
				break
		if pr.alive:
			keep.append(pr)
	projectiles = keep

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
func _resolve_hits() -> void:
	var actors := all_actors()
	for attacker in actors:
		if attacker.active_hitboxes.is_empty() or not attacker.alive:
			continue
		for hb in attacker.active_hitboxes.duplicate():
			for target in actors:
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

func _on_actor_hit(actor: BattleActor, _info: HitInfo) -> void:
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
