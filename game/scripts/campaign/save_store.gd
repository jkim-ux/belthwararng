class_name SaveStore
extends RefCounted
## 로컬 저장 1슬롯(JSON). 흐름: 임시 파일 기록 → 다시 읽어 완전성 확인 → 이전 정상 저장을 .bak 으로 보존 → 교체.
## 손상 저장은 .bak 을 시도한다. 쓰기 실패는 원본을 건드리지 않는다.
## 테스트와 수련장은 다른 경로(또는 무저장)로 실행해 사용자 저장을 변경하지 않는다.

var path: String
var fail_next_write: bool = false        ## 테스트용 실패 주입
var last_error: String = ""

func _init(p_path: String = "user://campaign_save.json") -> void:
	path = p_path

func backup_path() -> String:
	return path + ".bak"

func tmp_path() -> String:
	return path + ".tmp"

func exists() -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(backup_path())

## 저장 데이터를 기록한다. 성공하면 OK. 실패 시 기존 파일은 그대로 남는다.
func write(data: Dictionary) -> Error:
	last_error = ""
	if fail_next_write:
		fail_next_write = false
		last_error = "쓰기 실패 (테스트 주입)"
		return ERR_FILE_CANT_WRITE
	var text := JSON.stringify(data, "\t")
	var dir_path := path.get_base_dir()
	if dir_path != "" and not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var f := FileAccess.open(tmp_path(), FileAccess.WRITE)
	if f == null:
		last_error = "임시 파일을 열 수 없음: %s" % error_string(FileAccess.get_open_error())
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	# 완전성 확인: 다시 읽어 파싱하고 내용이 같은지 본다.
	var back := _read_file(tmp_path())
	# JSON 은 정수를 실수로 읽으므로 원문을 다시 파싱한 결과와 비교한다.
	if not back.ok or JSON.stringify(back.data) != JSON.stringify(JSON.parse_string(text)):
		DirAccess.remove_absolute(tmp_path())
		last_error = "임시 파일 확인 실패: %s" % back.error
		return ERR_FILE_CORRUPT
	# 이전 정상 저장 보존
	if FileAccess.file_exists(path):
		var prev := _read_file(path)
		if prev.ok:
			var cerr := DirAccess.copy_absolute(path, backup_path())
			if cerr != OK:
				last_error = "백업 실패: %s" % error_string(cerr)
				DirAccess.remove_absolute(tmp_path())
				return cerr
	var rerr := DirAccess.rename_absolute(tmp_path(), path)
	if rerr != OK:
		last_error = "교체 실패: %s" % error_string(rerr)
		DirAccess.remove_absolute(tmp_path())
		return rerr
	return OK

## 읽기. {ok, data, error, recovered_from_backup}
func read() -> Dictionary:
	var main := _read_file(path)
	if main.ok:
		main["recovered_from_backup"] = false
		return main
	var bak := _read_file(backup_path())
	if bak.ok:
		bak["recovered_from_backup"] = true
		bak["error"] = "주 저장 손상(%s) → 백업에서 복구" % main.error
		return bak
	return {"ok": false, "data": {}, "error": "저장 읽기 실패: %s / 백업: %s" % [main.error, bak.error], "recovered_from_backup": false}

func _read_file(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {"ok": false, "data": {}, "error": "파일 없음"}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {"ok": false, "data": {}, "error": "열기 실패 %s" % error_string(FileAccess.get_open_error())}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "data": {}, "error": "JSON 파싱 실패 (%d행: %s)" % [json.get_error_line(), json.get_error_message()]}
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "data": {}, "error": "JSON 최상위가 객체가 아님"}
	return {"ok": true, "data": parsed, "error": ""}

## 현재 정상 저장을 별도 이름(path + suffix)으로 한 번 보존한다(형식 이전용). 이미 있으면 덮어쓰지 않는다. 보존 경로 또는 "".
func preserve_copy(suffix: String) -> String:
	var dst := path + suffix
	if not FileAccess.file_exists(path):
		return ""
	if FileAccess.file_exists(dst):
		return dst
	return dst if DirAccess.copy_absolute(path, dst) == OK else ""

func delete_all() -> void:
	for p in [path, backup_path(), tmp_path(), path + ".v1.bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
