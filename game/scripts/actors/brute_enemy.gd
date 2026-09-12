class_name BruteEnemy
extends EnemyBase
## 강인병(brute). 체력 180, 피해 24, 이동 100/80. 큰 몸(반폭 32/반깊이 14/높이 94).
## 피격: 피해·섬광·피해 숫자는 정상이지만 일반 경직·밀림·띄우기·다운·피격 타격 정지(0)가 없다. 무적/피해 감소가 아니다.
## 유일한 제어 예외: 방어깨기(Q, AttackData.guard_break)가 맞으면 현재 공격을 취소하고 '자세 무너짐' 1초. 연장·갱신 없음.
## 패턴(교대): 0 전방 2연격(준비 0.7 → 베기 0.1 → 간격 0.25 → 베기 0.1 → 회복 0.9, 각 타 hit_index 0/1, 반격 가능)
##            1 주변 내려찍기(준비 0.95 → 타원 x110/y45·높이 0~90 타격 0.1 → 회복 1.1, 반격 불가)
## 접근하여 발 간격 x90/y8 안에서 근접 공격 허가(2)를 얻은 뒤 방향·기준 위치를 고정하고 준비한다. 준비 뒤에는 표적을 추적하지 않는다.
## 상태: idle, approach, telegraph, attack, recover, stagger, dead (hitstun/launched/down 은 들어가지 않는다)

var target: BattleActor
var combo_hit: AttackData
var slam: AttackData
var next_pattern: int = 0          ## 다음에 쓸 패턴(0 2연격, 1 내려찍기). 준비 시작 때 교대한다
var current_pattern: int = 0
var flinch_ticks: int = 0          ## 피격 표시용(경직 아님)
var waiting_for_slot: bool = false
var attacks_started: int = 0       ## 실제로 준비를 시작한 패턴 수(난도 보고용)
var hits_created: int = 0          ## 만든 타격 판정 수
var staggers: int = 0              ## Q 로 무너진 횟수
var hint_shown: bool = false

func _init() -> void:
	team = &"enemy"
	display_name = "강인병"
	body_color = Color(0.45, 0.28, 0.5)
	can_be_launched = false
	knockback_enabled = false

func configure(p_tuning: CombatTuning, p_battle: Node, start: Vector2, p_target: BattleActor) -> void:
	setup(p_tuning, p_battle, start)
	target = p_target
	max_hp = tuning.brute_max_hp
	hp = max_hp
	half_width = tuning.brute_half_width
	half_depth = tuning.brute_half_depth
	body_height = tuning.brute_height
	combo_hit = AttackData.new()
	combo_hit.id = &"brute_combo"
	combo_hit.display_name = "전방 2연격"
	combo_hit.startup_ms = 0.0
	combo_hit.active_ms = tuning.brute_combo_hit_ms
	combo_hit.recovery_ms = 0.0
	combo_hit.strong = true
	combo_hit.hitstun_ms = tuning.player_hitstun_ms
	combo_hit.knockback = 55.0
	combo_hit.parryable = true
	combo_hit.reach_forward = tuning.brute_combo_reach
	combo_hit.reach_back = tuning.brute_combo_reach_back
	combo_hit.depth_tolerance = tuning.brute_combo_depth
	combo_hit.z_min = -10.0
	combo_hit.z_max = tuning.brute_combo_z_max
	slam = AttackData.new()
	slam.id = &"brute_slam"
	slam.display_name = "주변 내려찍기"
	slam.startup_ms = 0.0
	slam.active_ms = tuning.brute_slam_active_ms
	slam.recovery_ms = 0.0
	slam.strong = true
	slam.hitstun_ms = tuning.player_hitstun_ms
	slam.knockback = 70.0
	slam.parryable = false
	slam.shape_ellipse = true
	slam.ellipse_rx = tuning.brute_slam_radius_x
	slam.ellipse_ry = tuning.brute_slam_radius_y
	slam.z_min = 0.0
	slam.z_max = tuning.brute_slam_z_max
	facing = -1 if (p_target != null and start.x > p_target.floor_pos.x) else 1
	change_state(&"idle")

func is_stagger_immune() -> bool:
	return true

func in_pattern() -> bool:
	return state == &"telegraph" or state == &"attack" or state == &"recover"

# ---------------------------------------------------------------- 피격

## 피격 대상 쪽 타격 정지는 항상 0: 반복 피격 중에도 준비/타격 시계가 실제로 진행한다.
func _victim_hitstop(_info: HitInfo) -> int:
	return 0

## 경직·밀림·띄우기·다운 없음. Q(guard_break)만 전용 무너짐. 이미 무너진 중이면 갱신/연장하지 않는다.
func _on_hit(info: HitInfo) -> void:
	flinch_ticks = 4
	if info.attack.guard_break and state != &"stagger":
		_enter_stagger()

func _enter_stagger() -> void:
	end_hitboxes()
	velocity = Vector2.ZERO
	staggers += 1
	change_state(&"stagger")   # _on_state_entered 가 허가를 반환한다

func stagger_remaining_ticks() -> int:
	if state != &"stagger":
		return 0
	return maxi(0, Ticks.from_ms(tuning.brute_stagger_ms) - state_ticks)

# ---------------------------------------------------------------- 상태

func _step_state() -> void:
	if flinch_ticks > 0:
		flinch_ticks -= 1
	match state:
		&"idle":
			_step_idle()
		&"approach":
			_step_approach()
		&"telegraph":
			_step_telegraph()
		&"attack":
			_step_attack()
		&"recover":
			_step_recover()
		&"stagger":
			_step_stagger()
		&"dead":
			pass

func _target_valid() -> bool:
	return target != null and is_instance_valid(target) and target.alive

## 근접병과 같은 거리 점수(|dx| + 1.5|dy|). 동률이면 기존 대상, 이어 생성 순서(alive_allies 순).
func _pick_target() -> void:
	if battle == null or not battle.has_method("alive_allies"):
		return
	var best: BattleActor = null
	var best_d := INF
	for a in battle.alive_allies():
		var d: float = absf(a.floor_pos.x - floor_pos.x) + absf(a.floor_pos.y - floor_pos.y) * 1.5
		if d < best_d:
			best_d = d
			best = a
	if best == null:
		return
	if _target_valid():
		var cur: float = absf(target.floor_pos.x - floor_pos.x) + absf(target.floor_pos.y - floor_pos.y) * 1.5
		if is_equal_approx(cur, best_d):
			return
	target = best

func _release_slot() -> void:
	waiting_for_slot = false
	if battle != null and battle.has_method("release_attack_slot"):
		battle.release_attack_slot(self)

func _step_idle() -> void:
	approach_velocity(Vector2.ZERO)
	move_by_velocity()
	if state_ticks >= Ticks.from_ms(tuning.brute_idle_ms):
		_pick_target()
		if _target_valid():
			change_state(&"approach")

func _step_approach() -> void:
	_pick_target()
	if not _target_valid():
		change_state(&"idle")
		return
	facing = 1 if target.floor_pos.x >= floor_pos.x else -1
	var dx := target.floor_pos.x - floor_pos.x
	var dy := target.floor_pos.y - floor_pos.y
	var want := tuning.brute_engage_x - 20.0
	var desired_x := target.floor_pos.x - facing * want
	var ddx := desired_x - floor_pos.x
	var t := Vector2.ZERO
	if absf(dy) > 4.0:
		t.y = signf(dy) * tuning.brute_speed_y
	if absf(dx) > tuning.brute_engage_x - 4.0 or absf(ddx) > 6.0 and absf(dx) < 40.0:
		t.x = signf(ddx) * tuning.brute_speed_x
	velocity = t
	var stepv := velocity * Ticks.DT
	if absf(stepv.x) > absf(ddx):
		stepv.x = ddx
	if absf(stepv.y) > absf(dy):
		stepv.y = dy
	floor_pos += stepv
	dx = target.floor_pos.x - floor_pos.x
	dy = target.floor_pos.y - floor_pos.y
	if absf(dx) <= tuning.brute_engage_x and absf(dy) <= tuning.brute_engage_y:
		velocity = Vector2.ZERO
		var allowed := true
		if battle != null and battle.has_method("request_attack_slot"):
			allowed = battle.request_attack_slot(self)
		waiting_for_slot = not allowed
		if allowed:
			# 준비 시작: 방향·기준 위치·패턴 고정. 이후 표적을 추적하지 않는다(헛쳐도 끝까지 진행).
			facing = 1 if target.floor_pos.x >= floor_pos.x else -1
			current_pattern = next_pattern
			next_pattern = 1 - next_pattern
			attacks_started += 1
			change_state(&"telegraph")

func _telegraph_ticks() -> int:
	return Ticks.from_ms(tuning.brute_combo_telegraph_ms if current_pattern == 0 else tuning.brute_slam_telegraph_ms)

func _recover_ticks() -> int:
	return Ticks.from_ms(tuning.brute_combo_recover_ms if current_pattern == 0 else tuning.brute_slam_recover_ms)

func _step_telegraph() -> void:
	if state_ticks >= _telegraph_ticks():
		change_state(&"attack")

## 2연격: t0 첫 베기(hit_index 0) → 간격 → 두 번째 베기(hit_index 1). 내려찍기: t0 한 번.
## 상태 시계는 자신의 공격자 타격 정지에만 멈춘다(피격 타격 정지는 0).
func _step_attack() -> void:
	var t := state_ticks - 1
	if current_pattern == 0:
		var hit := combo_hit.active_ticks()
		var gap := Ticks.from_ms(tuning.brute_combo_gap_ms)
		if t == 0:
			_begin(combo_hit, 0)
		elif t == hit:
			end_hitboxes()
		elif t == hit + gap:
			_begin(combo_hit, 1)
		elif t >= hit + gap + hit:
			end_hitboxes()
			change_state(&"recover")
	else:
		if t == 0:
			_begin(slam, 0)
		elif t >= slam.active_ticks():
			end_hitboxes()
			change_state(&"recover")

func _begin(atk: AttackData, index: int) -> void:
	begin_hitbox(atk, float(tuning.brute_attack_damage), index)
	hits_created += 1

## 2연격 진행 표시: 0 준비, 1 첫 타 이후(두 번째 준비), 2 완료
func combo_stage() -> int:
	if current_pattern != 0 or not in_pattern():
		return 0
	if state == &"telegraph":
		return 0
	if state == &"attack" and state_ticks - 1 < combo_hit.active_ticks() + Ticks.from_ms(tuning.brute_combo_gap_ms):
		return 1
	return 2

func _step_recover() -> void:
	approach_velocity(Vector2.ZERO)
	move_by_velocity()
	if state_ticks >= _recover_ticks():
		change_state(&"idle")

func _step_stagger() -> void:
	approach_velocity(Vector2.ZERO)
	move_by_velocity()
	if state_ticks >= Ticks.from_ms(tuning.brute_stagger_ms):
		change_state(&"idle")

func _on_state_entered(new_state: StringName) -> void:
	if new_state != &"attack":
		end_hitboxes()
	if new_state != &"telegraph" and new_state != &"attack" and new_state != &"recover":
		_release_slot()

# ---------------------------------------------------------------- 그리기

func _draw() -> void:
	if alive and (state == &"telegraph" or state == &"attack"):
		var progress := 1.0
		if state == &"telegraph":
			progress = clampf(float(state_ticks) / float(maxi(1, _telegraph_ticks())), 0.0, 1.0)
		var f := UiFont.FONT
		if current_pattern == 0:
			var col := Color(1.0, 0.3, 0.1, 0.22 + 0.45 * progress)
			if state == &"attack":
				col = Color(1.0, 0.9, 0.2, 0.75)
			var x0 := -combo_hit.reach_back if facing > 0 else -combo_hit.reach_forward
			var w := combo_hit.reach_forward + combo_hit.reach_back
			var d := combo_hit.depth_tolerance
			draw_rect(Rect2(x0, -d, w, d * 2.0), col)
			draw_rect(Rect2(x0, -d, w, d * 2.0), Color(1.0, 0.4, 0.1, 0.9), false, 2.0)
			# 2연격 표식: 화살촉 2개와 단계 문구
			var stage := combo_stage()
			for i in 2:
				var ax := (x0 + w * (0.45 + 0.25 * i)) if facing > 0 else (x0 + w * (0.55 - 0.25 * i))
				var done := i < stage
				draw_line(Vector2(ax - 8.0 * facing, -8.0), Vector2(ax, 0.0), Color(1, 1, 1, 0.95 if not done else 0.4), 2.0)
				draw_line(Vector2(ax - 8.0 * facing, 8.0), Vector2(ax, 0.0), Color(1, 1, 1, 0.95 if not done else 0.4), 2.0)
			var label := "2연격 1/2" if stage < 1 else ("2연격 2/2" if stage == 1 else "2연격")
			draw_string(f, Vector2(x0 + 6.0, -d - 6.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.85, 0.6))
		else:
			# 내려찍기: 바닥 타원(판정과 같은 반경) + '회피' 표식. 반격 불가.
			var col := Color(0.85, 0.15, 0.35, 0.2 + 0.45 * progress)
			if state == &"attack":
				col = Color(1.0, 0.8, 0.3, 0.75)
			var pts := PackedVector2Array()
			for i in 36:
				var an := TAU * float(i) / 36.0
				pts.append(Vector2(cos(an) * slam.ellipse_rx, sin(an) * slam.ellipse_ry))
			draw_colored_polygon(pts, col)
			pts.append(pts[0])
			draw_polyline(pts, Color(1.0, 0.3, 0.5, 0.95), 2.0)
			# X 표식(반격 불가)
			draw_line(Vector2(-10, -10), Vector2(10, 10), Color(1, 1, 1, 0.9), 2.0)
			draw_line(Vector2(-10, 10), Vector2(10, -10), Color(1, 1, 1, 0.9), 2.0)
			draw_string(f, Vector2(-30.0, -slam.ellipse_ry - 6.0), "회피 (반격 불가)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.75, 0.8))
	super()

func _draw_body() -> void:
	var saved := body_color
	if flinch_ticks > 0 and alive:
		body_color = body_color.lightened(0.35)
	if state == &"stagger" and alive:
		# 자세 무너짐: 몸을 기울이고 남은 시간 막대
		draw_set_transform(Vector2(0, 0), deg_to_rad(-14.0 * facing), Vector2.ONE)
		super()
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		body_color = saved
		var top := -body_height - 22.0
		var frac := float(stagger_remaining_ticks()) / float(maxi(1, Ticks.from_ms(tuning.brute_stagger_ms)))
		draw_rect(Rect2(-half_width, top, half_width * 2.0, 5.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-half_width, top, half_width * 2.0 * frac, 5.0), Color(0.5, 0.85, 1.0))
		draw_string(UiFont.FONT, Vector2(-half_width, top - 4.0), "자세 무너짐", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.9, 1.0))
		_draw_gear()
		return
	super()
	body_color = saved
	if not alive:
		return
	_draw_gear()

## 어깨·큰 무기·'강인' 표식
func _draw_gear() -> void:
	var top := -height - body_height
	draw_rect(Rect2(-half_width - 8.0, top + 8.0, half_width * 2.0 + 16.0, 14.0), Color(0.3, 0.2, 0.32))
	draw_string(UiFont.FONT, Vector2(-14.0, top - 16.0), "강인", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.8, 1.0))
	# 무기(몽둥이): 준비 중에는 뒤로/위로 들어 올린다
	var hand := Vector2(float(facing) * (half_width - 4.0), top + 34.0)
	var tip := hand + Vector2(float(facing) * 28.0, 18.0)
	if state == &"telegraph":
		tip = hand + Vector2(-float(facing) * 16.0, -40.0) if current_pattern == 0 else hand + Vector2(0.0, -48.0)
	elif state == &"attack":
		tip = hand + Vector2(float(facing) * 46.0, 4.0) if current_pattern == 0 else hand + Vector2(float(facing) * 24.0, 44.0)
	draw_line(hand, tip, Color(0.35, 0.25, 0.15), 8.0)
	draw_circle(tip, 7.0, Color(0.5, 0.5, 0.55))
