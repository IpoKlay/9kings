extends SceneTree
const Battle=preload('res://scripts/tactical/siege_battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture(y: float=1320.) -> Dictionary:
	var r=Battle.new()
	var engine=r.alive('ally').filter(func(u):return u.kind=='siege')[0]
	r.units=r.units.filter(func(u):return u.id==engine.id or u.side=='enemy')
	engine.pos=Vector2(1050,y)
	for u in r.alive('enemy'):u.pos.y=100.
	r.start();r.enemy_director.active=false
	var ids=r.Soldiers.group_members([engine])
	r.Soldiers.command(r,ids,'hold',Vector2.ZERO)
	return {'r':r,'engine':engine,'ids':ids,'wall':r.structures[3]}
func step(f: Dictionary,count: int):
	for i in count:f.r.step(1./60.)
func run():
	for y in [1000.,1850.]:
		var f=fixture(y)
		check(f.r.Structures.order(f.r,f.ids,f.wall),'Out-of-range engines accept bombard order')
		step(f,30)
		check(f.r.stones.is_empty() and f.wall.hits==0,'No shell releases outside the firing annulus')
		var first=-1.;var launch_positions=[]
		for i in 1800:
			f.r.step(1./60.)
			for shot in f.r.stones:
				if not shot.has('range_checked'):
					shot.range_checked=true
					launch_positions.append(f.r.Soldiers.ground_position(f.r,f.engine,shot.attacker_slot))
			if f.wall.hits>0:first=f.r.elapsed;break
		check(first>0.,'Engine walks into range and actually hits wall from '+str(y))
		check(not launch_positions.is_empty() and launch_positions.all(func(p):return p.distance_to(Vector2(1050,900))>=150. and p.distance_to(Vector2(1050,900))<=700.),'Actual release feet lie within min/max range')
	var f=fixture()
	f.r.Structures.order(f.r,f.ids,f.wall);step(f,2)
	check(f.engine.soldiers.all(func(s):return s.get('attack_pending',false)),'Windup begins before interruption')
	f.r.Soldiers.command(f.r,f.ids,'move',Vector2(1300,1400));step(f,150)
	check(f.r.stones.is_empty() and f.wall.hits==0,'Movement during windup cancels wall shot')
	f=fixture();f.r.Structures.order(f.r,f.ids,f.wall);step(f,42)
	check(f.r.stones.size()==3,'All three ordinary engines release actual shells')
	f.r.Soldiers.command(f.r,f.ids,'hold',Vector2.ZERO);step(f,180)
	check(f.wall.hits==3,'Changing order after release preserves the three in-flight hits')
	f=fixture();f.r.Structures.order(f.r,f.ids,f.wall);step(f,2)
	for i in 5:f.r.Structures.impact(f.r,{'pos':Vector2(1050,900),'side':'ally'})
	step(f,60)
	check(f.engine.soldiers.all(func(s):return s.personal_order=='hold' and not s.get('attack_pending',false)) and f.r.stones.is_empty(),'Target breached during windup cancels pending shots and settles engines')
	f=fixture();f.r.Structures.order(f.r,f.ids,f.wall);step(f,42)
	for i in 5:f.r.Structures.impact(f.r,{'pos':Vector2(1050,900),'side':'ally'})
	step(f,180)
	check(f.wall.hits==5 and f.r.stones.is_empty(),'Shells already airborne land harmlessly at an existing breach without extra wall hits')
	check(not f.r.Structures.order(f.r,[Vector2i(f.r.alive('enemy')[0].id,0)],f.r.structures[2]),'Enemy infantry cannot receive player bombard order')
	print('Siege orders: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
