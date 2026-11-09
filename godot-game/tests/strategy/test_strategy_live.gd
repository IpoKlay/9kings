extends SceneTree
const Battle=preload('res://scripts/strategy/battle.gd')
func _init():
	var r=Battle.new(false);r.start()
	var start: Vector2=r.alive('enemy')[0].pos
	for i in 1800:
		r.step(1./60)
		r.events.clear();r.advance_casualties(1./60)
	var enemies=r.alive('enemy')
	var moved=enemies.is_empty() or enemies[0].pos.distance_to(start)>100.
	print('STRATEGY LIVE elapsed=',r.elapsed,' phase=',r.phase,' allies=',r.alive('ally').size(),' enemies=',enemies.size(),' enemy_moved=',moved)
	if not moved:push_error('Enemy army did not advance')
	quit(0 if moved else 1)
