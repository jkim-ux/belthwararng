class_name VillageTemplate
extends Resource
## 마을 1곳의 고정 지형 템플릿(공유 데이터). 16×12 칸, 한 칸 48px 초기값.
## terrain_rows / obstacle_rows 는 각 12줄·16글자. 실행 중 상태(개간·건물)는 VillageState 가 갖는다.
##
## 지형 글자: '.' 일반 지면, 'f' 비옥한 땅, '~' 강, '#' 절벽, 'e' 출입구(통행·건설 불가 예약),
##           'p' 중앙 통행로(통행·건설 불가 예약), 'W' 숲 작업 구역(막힘), 'Q' 암반 작업 구역(막힘),
##           'd' 작은 보 부지(강가, 보만 설치), 'x' 경로 복구 현장(고정, 복구 현장만 설치)
## 장애물 글자: '.' 없음, 'b' 덤불(1초, 보상 없음), 't' 작은 나무(2초, 목재 4), 'r' 바위(3초, 석재 3)

const WIDTH := 16
const HEIGHT := 12
const LAYOUT_VERSION := 1
const LEGACY_WIDTH := 32
const LEGACY_HEIGHT := 24
const CELL_PX := 48

@export var site_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var terrain_rows: PackedStringArray = PackedStringArray()
@export var obstacle_rows: PackedStringArray = PackedStringArray()
@export var spawn: Vector2i = Vector2i(7, 10)          ## 플레이어·주민 시작 칸(출입구 안쪽)
@export var dam_outlet: Vector2i = Vector2i(-1, -1)     ## 보의 육지 물 출구 칸
@export var facility_spot: Rect2i = Rect2i(0, 0, 3, 2)  ## 기존 저장 이전 시 특수 시설을 놓는 안전한 자리(회전 0)

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < WIDTH and c.y < HEIGHT

func terrain_at(c: Vector2i) -> String:
	if not in_bounds(c) or c.y >= terrain_rows.size():
		return "#"
	var row := terrain_rows[c.y]
	return row[c.x] if c.x < row.length() else "#"

func obstacle_at(c: Vector2i) -> String:
	if not in_bounds(c) or c.y >= obstacle_rows.size():
		return "."
	var row := obstacle_rows[c.y]
	return row[c.x] if c.x < row.length() else "."

## 장애물 고유 ID(마을 안에서 위치로 고정). 재입장 때 되살아나지 않도록 상태가 정리 목록을 가진다.
static func obstacle_id(c: Vector2i) -> String:
	return "ob_%d_%d" % [c.x, c.y]

static func obstacle_work(ch: String) -> float:
	match ch:
		"b": return 1.0
		"t": return 2.0
		"r": return 3.0
	return 0.0

static func obstacle_name(ch: String) -> String:
	match ch:
		"b": return "덤불"
		"t": return "작은 나무"
		"r": return "바위"
	return ""

## 장애물 제거 보상 {wood, stone}
static func obstacle_reward(ch: String) -> Dictionary:
	match ch:
		"t": return {"wood": 4, "stone": 0}
		"r": return {"wood": 0, "stone": 3}
	return {"wood": 0, "stone": 0}

func is_land(c: Vector2i) -> bool:
	var t := terrain_at(c)
	return t == "." or t == "f"

func is_fertile(c: Vector2i) -> bool:
	return terrain_at(c) == "f"

## 지형만으로 통행 가능한 칸(장애물·건물은 별도)
func is_terrain_walkable(c: Vector2i) -> bool:
	var t := terrain_at(c)
	return t == "." or t == "f" or t == "e" or t == "p"

func is_reserved(c: Vector2i) -> bool:
	var t := terrain_at(c)
	return t == "e" or t == "p"

## 글자 하나로 이루어진 고정 부지의 경계 사각형(없으면 크기 0)
func fixed_rect(ch: String) -> Rect2i:
	var minx := WIDTH
	var miny := HEIGHT
	var maxx := -1
	var maxy := -1
	for y in HEIGHT:
		for x in WIDTH:
			if terrain_at(Vector2i(x, y)) == ch:
				minx = mini(minx, x)
				miny = mini(miny, y)
				maxx = maxi(maxx, x)
				maxy = maxi(maxy, y)
	if maxx < 0:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)

func dam_site() -> Rect2i:
	return fixed_rect("d")

func repair_site() -> Rect2i:
	return fixed_rect("x")

func entrance_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in HEIGHT:
		for x in WIDTH:
			if terrain_at(Vector2i(x, y)) == "e":
				out.append(Vector2i(x, y))
	return out

func all_obstacles() -> Dictionary:
	var out := {}
	for y in HEIGHT:
		for x in WIDTH:
			var ch := obstacle_at(Vector2i(x, y))
			if ch != ".":
				out[obstacle_id(Vector2i(x, y))] = {"cell": Vector2i(x, y), "kind": ch}
	return out

## 정의 검증(테스트·로드 시). 문제 목록을 돌려준다.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if terrain_rows.size() != HEIGHT or obstacle_rows.size() != HEIGHT:
		problems.append("행 수 %d/%d (필요 %d)" % [terrain_rows.size(), obstacle_rows.size(), HEIGHT])
	for y in mini(HEIGHT, terrain_rows.size()):
		if terrain_rows[y].length() != WIDTH:
			problems.append("지형 %d행 길이 %d" % [y, terrain_rows[y].length()])
	for y in mini(HEIGHT, obstacle_rows.size()):
		if obstacle_rows[y].length() != WIDTH:
			problems.append("장애물 %d행 길이 %d" % [y, obstacle_rows[y].length()])
		for x in mini(WIDTH, obstacle_rows[y].length()):
			var ch := obstacle_rows[y][x]
			if ch != "." and not is_land(Vector2i(x, y)):
				problems.append("장애물 (%d,%d) 이 땅 위가 아님" % [x, y])
	if dam_site().size != Vector2i(3, 2):
		problems.append("보 부지가 3×2 가 아님: %s" % str(dam_site()))
	if repair_site().size != Vector2i(2, 2):
		problems.append("복구 현장이 2×2 가 아님: %s" % str(repair_site()))
	if entrance_cells().is_empty():
		problems.append("출입구 없음")
	if not is_land(dam_outlet):
		problems.append("보 출구 %s 가 땅이 아님" % str(dam_outlet))
	if not is_terrain_walkable(spawn) or obstacle_at(spawn) != ".":
		problems.append("시작 칸 %s 통행 불가" % str(spawn))
	return problems
