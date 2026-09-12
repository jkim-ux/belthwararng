class_name MotionCurve
## 고정 틱에서 총 거리 D 를 N 틱에 걸쳐 감속 곡선으로 나누는 도우미.
## 누적 곡선 C(u) = 1 - (1 - u)^2 (u: 0~1). k 번째 진행 틱의 이동량은 D × (C((k+1)/N) - C(k/N)) 이다.
## 이른 틱에 크게 나가고 끝에서 감속하며, 모든 틱의 합은 정확히 D 가 된다.
## 평타 전진과 적 피격 밀림이 같은 곡선을 쓴다.

static func cumulative(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return 1.0 - (1.0 - u) * (1.0 - u)

## total: 총 거리, k: 0부터 시작하는 진행 틱 인덱스, n: 전체 틱 수(최소 1)
static func ease_out_step(total: float, k: int, n: int) -> float:
	n = maxi(1, n)
	if k < 0 or k >= n:
		return 0.0
	return total * (cumulative(float(k + 1) / float(n)) - cumulative(float(k) / float(n)))
