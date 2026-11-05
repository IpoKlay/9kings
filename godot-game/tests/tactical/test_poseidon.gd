extends SceneTree
const Rules=preload('res://scripts/tactical/trial_rules.gd')
func _initialize():
	var r=Rules.new(false)
	assert(not r.select_deity('unknown'))
	assert(r.select_deity('poseidon'))
	assert(not r.strike(Vector2(1160,545)))
	r.deploy('legion',Vector2(650,420))
	r.start()
	assert(not r.select_deity('zeus'))
	assert(not r.strike(Vector2(-1,-1)))
	assert(r.charges==2)
	var enemy=r.alive('enemy')[1]
	var hp=enemy.hp
	var ally=r.alive('ally')[0]
	var ally_hp=ally.hp
	assert(r.strike(Vector2(1160,545)))
	assert(enemy.hp==hp)
	assert(not r.strike(Vector2(1160,545)))
	r.advance_waves(.7)
	assert(enemy.hp==hp-r.config.sea_wave.damage)
	assert(enemy.push.x>0 and enemy.stun>0)
	r.advance_waves(.1)
	assert(enemy.hp==hp-r.config.sea_wave.damage)
	assert(ally.hp==ally_hp)
	r.advance_waves(.5)
	assert(r.waves.is_empty())
	for dt in [1.0/30,1.0/60,1.0/120]:
		r=Rules.new(false)
		r.select_deity('poseidon')
		for pos in [Vector2(650,420),Vector2(650,650)]:r.deploy('legion',pos)
		for pos in [Vector2(380,420),Vector2(380,650)]:r.deploy('archer',pos)
		r.start()
		var casts=0
		while r.phase=='battle':
			if r.elapsed>20 and r.reserve.cavalry>0:
				r.deploy('cavalry',Vector2(530,310))
				r.deploy('cavalry',Vector2(530,770))
			if r.elapsed>45+casts*45 and casts<2:
				assert(r.strike(Vector2(1150,570)))
				casts+=1
			r.step(dt)
			r.events.clear()
		print('POSEIDON ',1/dt,'Hz ',r.phase,' ',r.elapsed)
		assert(r.elapsed<=180.1)
	print('POSEIDON: selection, travelling hit, single damage, friendly safety, cooldown PASS')
	quit()
