class_name DungeonDef
extends Resource
## 거점 하나의 방 던전 정의(고정 배치). 실행 중 상태(현재 방·정리·상자)는 Battle 이 갖는다.
## 방향은 격자 좌표 차이로 정한다: 동 (+1,0) / 서 (-1,0) / 북 (0,-1) / 남 (0,+1).

const DIRS := {&"east": Vector2i(1, 0), &"west": Vector2i(-1, 0), &"north": Vector2i(0, -1), &"south": Vector2i(0, 1)}

@export var rooms: Array[RoomDef] = []
@export var start_room_id: StringName = &"entry"

@export_group("보스")
@export var boss_display_name: String = "대장"
@export var boss_max_hp: int = 600

@export_group("보물 상자")
@export var chest_heal_ratio: float = 0.2      ## 생존 아군 최대 체력 비율 회복
@export var chest_currency: int = 30           ## 보스 승리 시 합산되는 보류 군자금

func room(id: StringName) -> RoomDef:
	for r in rooms:
		if r.id == id:
			return r
	return null

static func opposite(dir: StringName) -> StringName:
	match dir:
		&"east": return &"west"
		&"west": return &"east"
		&"north": return &"south"
		&"south": return &"north"
	return &""

## a 에서 b 로 가는 문의 방향. 인접하지 않으면 빈 이름.
func direction_between(a: RoomDef, b: RoomDef) -> StringName:
	var d := b.grid - a.grid
	for k in DIRS.keys():
		if DIRS[k] == d:
			return k
	return &""

## 방의 문 목록: [{dir, target_id}]
func doors_of(r: RoomDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if r == null:
		return out
	for cid in r.connections:
		var other := room(cid)
		if other == null:
			continue
		var dir := direction_between(r, other)
		if dir != &"":
			out.append({"dir": dir, "target_id": cid})
	return out

func enemy_count() -> int:
	var n := 0
	for r in rooms:
		if r.kind == &"battle":
			n += r.enemy_count()
	return n

func boss_room() -> RoomDef:
	for r in rooms:
		if r.kind == &"boss":
			return r
	return null

## 정의 검증: 연결 대칭, 인접, 종류별 웨이브 수. 문제 목록을 돌려준다(비어 있으면 정상).
func validate() -> Array[String]:
	var problems: Array[String] = []
	if room(start_room_id) == null:
		problems.append("시작 방 %s 없음" % start_room_id)
	for r in rooms:
		for cid in r.connections:
			var o := room(cid)
			if o == null:
				problems.append("%s → %s: 없는 방" % [r.id, cid])
				continue
			if direction_between(r, o) == &"":
				problems.append("%s → %s: 격자 인접 아님" % [r.id, cid])
			if not o.connections.has(r.id):
				problems.append("%s → %s: 역방향 연결 없음" % [r.id, cid])
		match r.kind:
			&"battle":
				if r.waves.size() != 2:
					problems.append("%s: 일반 방 웨이브 %d (2 필요)" % [r.id, r.waves.size()])
			&"boss":
				if r.waves.size() != 1 or r.waves[0].enemy_kinds != [&"boss"]:
					problems.append("%s: 보스방은 보스 1명 웨이브 1개" % r.id)
			_:
				if not r.waves.is_empty():
					problems.append("%s: 안전한 방에 웨이브" % r.id)
		for w in r.waves:
			if w.enemy_kinds.size() > 5:
				problems.append("%s: 동시 출현 %d (최대 5)" % [r.id, w.enemy_kinds.size()])
	return problems
