extends SceneTree
const Battle=preload('res://scripts/strategy/battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _init():
	var r=Battle.new(false)
	var soldier=r.alive('ally').filter(func(u):return u.unit_type=='spear')[0]
	check(r.Soldiers.command(r,[Vector2i(soldier.id,0)],'move',Vector2(1450,1930)),'Army can path through initial gate')
	for i in 720:r.step(1./60);r.events.clear()
	check(soldier.pos.distance_to(Vector2(1450,1930))<25.,'Army physically exits the walled city')
	var wolf=r.spawn_person('wolf','enemy',Vector2(1270,2400));wolf.wild=true;wolf.home=wolf.pos;wolf.order='auto';wolf.soldiers[0].personal_order='auto'
	var villager=r.alive('ally').filter(func(u):return u.unit_type=='villager')[0]
	var health: float=villager.hp
	for i in 240:r.step(1./60);r.events.clear()
	check(villager.hp<health,'Hostile wolf actually attacks a nearby villager')
	wolf.hp=0;wolf.soldiers[0].hp=0;r.world.step(r,.2)
	check(r.resources.any(func(v):return v.kind=='wolf' and v.pos.distance_to(wolf.pos)<1),'Killed wolf becomes harvestable food')
	# Fog remembers the visited gate exit after the scout returns.
	r.Soldiers.command(r,[Vector2i(soldier.id,0)],'move',Vector2(1450,2350))
	for i in 720:r.step(1./60);r.events.clear()
	check(soldier.pos.distance_to(Vector2(1450,2350))<25.,'Return trip through gate succeeds')
	print('EXPANSION LIVE CHECKS=',checks,' FAILURES=',failures)
	quit(1 if failures else 0)
