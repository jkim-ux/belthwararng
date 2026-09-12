class_name Ticks
## 고정 시뮬레이션(매초 60회)용 시간 변환 도우미.
## 밀리초로 적힌 기획 수치를 틱 수로 양자화한다. 실제 적용 시간은 ms_applied()로 확인한다.

const TPS: int = 60
const DT: float = 1.0 / float(TPS)

## 밀리초를 틱으로 바꾼다. 반올림하며 최소 1틱을 보장한다(0 ms는 0틱).
static func from_ms(ms: float) -> int:
	if ms <= 0.0:
		return 0
	return maxi(1, roundi(ms / 1000.0 * float(TPS)))

## 틱 수를 실제 적용 밀리초로 바꾼다.
static func to_ms(ticks: int) -> float:
	return float(ticks) * 1000.0 / float(TPS)

## 기획값(ms)과 실제 적용값을 한 줄 문자열로 만든다. 디버그 표시와 보고용.
static func describe(label: String, ms: float) -> String:
	var t := from_ms(ms)
	return "%s: %d ms → %d틱 (%.1f ms)" % [label, roundi(ms), t, to_ms(t)]
