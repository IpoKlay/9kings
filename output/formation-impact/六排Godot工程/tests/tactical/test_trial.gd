extends SceneTree
const Rules=preload('res://scripts/tactical/trial_rules.gd')
func _initialize():
	var r=Rules.new(false)
	assert(not r.start())
	assert(not r.deploy('legion',Vector2(1400,400)))
	assert(r.deploy('legion',Vector2(650,430)))
	assert(not r.deploy('legion',Vector2(650,430)))
	assert(r.reserve.legion==1)
	assert(r.start())
	assert(r.deploy('archer',Vector2(380,430)))
	assert(r.strike(Vector2(1160,450)))
	assert(not r.strike(Vector2(1160,450)))
	assert(r.charges==1)
	for variant in 3:
		r=Rules.new(false)
		# Replay the original six-squad scenario with its historical reserve roster.
		r.reserve={'legion':2,'archer':2,'cavalry':2}
		r.deploy('legion',Vector2(650,420))
		r.deploy('legion',Vector2(650,650))
		r.deploy('archer',Vector2(380,420))
		r.deploy('archer',Vector2(380,650))
		if variant==0:
			r.deploy('cavalry',Vector2(530,310))
			r.deploy('cavalry',Vector2(530,770))
		r.start()
		var first=false
		var second=false
		for i in 10801:
			if variant>0 and r.elapsed>20 and r.reserve.cavalry>0:
				r.deploy('cavalry',Vector2(530,310))
				r.deploy('cavalry',Vector2(530,770))
			if variant!=2 and r.elapsed>45 and not first:
				r.strike(r.alive('enemy')[0].pos)
				first=true
			if variant!=2 and r.elapsed>90 and not second and not r.alive('enemy').is_empty():
				r.strike(r.alive('enemy')[0].pos)
				second=true
			r.step(1.0/60)
			r.events.clear()
			if r.phase!='battle':break
		print('PLAN ',variant,' ',r.phase,' seconds=',r.elapsed,' allies=',r.alive('ally').size(),' enemies=',r.alive('enemy').size())
		assert(r.phase=='victory' if variant<2 else r.phase=='defeat')
		if variant==0:assert(r.elapsed>75 and r.elapsed<=180) # Full vanguard now closes faster.
		if variant==1:assert(r.elapsed>120 and r.elapsed<=180)
	assert(r.elapsed<=180.1)
	r=Rules.new(false)
	r.deploy('legion',Vector2(650,420))
	r.start()
	r.elapsed=179.99
	r.step(.02)
	assert(r.phase=='timeout')
	assert(not r.deploy('archer',Vector2(380,650)))
	assert(not r.strike(Vector2(1160,450)))
	var frozen=r.elapsed
	r.step(1)
	assert(r.elapsed==frozen)
	print('TACTICAL RULE CHECKS PASSED')
	quit()
