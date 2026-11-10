extends SceneTree
const Battle=preload('res://scripts/strategy/battle.gd')
func _init():
	var r=Battle.new(false)
	var grace_ok=true
	for i in 12600:
		r.step(1./60)
		r.events.clear();r.advance_casualties(1./60)
		if i==10700:grace_ok=r.waves_sent==0 and r.alive('enemy').all(func(u):return u.order=='hold')
	var moved=r.alive('enemy').any(func(u):return u.order=='auto' and u.pos.y>1000.)
	print('STRATEGY LIVE elapsed=',r.elapsed,' phase=',r.phase,' allies=',r.alive('ally').size(),' raids=',r.waves_sent,' grace_ok=',grace_ok,' enemy_moved=',moved)
	quit(0 if grace_ok and moved else 1)
