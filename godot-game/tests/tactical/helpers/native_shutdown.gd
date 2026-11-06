extends RefCounted
## Test teardown only: queue_free runs on the main thread, while stopped audio
## playbacks retire on the mixer thread. Fixed-FPS tests may run many simulation
## frames before one real audio mix, so use wall time rather than frame counts.
static func settle(tree: SceneTree):
	await tree.process_frame
	var deadline=Time.get_ticks_msec()+300
	while Time.get_ticks_msec()<deadline:
		await tree.process_frame
