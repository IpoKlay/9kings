extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture():
	var r=Battle.new();r.units.clear();r.spawn('legion','ally',Vector2(1000,1200));r.spawn('legion','enemy',Vector2(1800,200))
	for u in r.units:u.order='hold'
	r.start();return r
func run():
	var r=fixture();var u=r.units[0];var ids=r.Soldiers.group_members([u]);var people=r.Soldiers.members(r,ids)
	var plan=r.Soldiers.movement_paths(r,people,u.pos)
	check(plan.all(func(p):return absf(p.path.back().distance_to(u.pos)-9.5)<.001),'Inside-selection targets form the actual input handler9.5-radius ring')
	plan=r.Soldiers.movement_paths(r,people,Vector2(1000,900))
	var furthest=0.
	for p in plan:furthest=maxf(furthest,p.path.back().distance_to(Vector2(1000,900)))
	check(absf(furthest-19.*sqrt(10.)*1.5)<.001,'Outside selection compresses excessive spread to the reference limit')
	var no_waypoints: Array[Vector2]=[]
	check(r.Soldiers.command(r,ids,'move',u.pos,-1,-1,no_waypoints,false) and r.move_batch_serial==0,'Route preview does not allocate a live batch')
	check(r.command([u.id],'move',u.pos),'Actual regiment command accepts internal gathering')
	var batch=u.soldiers[0].move_batch
	check(u.soldiers.all(func(a):return a.move_batch.id==batch.id) and absf(batch.radius-9.*sqrt(10.)*2.5)<.001,'One accepted selection receives one serial and the mean-size settlement radius')
	for frame in 360:
		r.step(1./60)
		if u.order=='idle':break
	check(u.soldiers.all(func(a):return a.personal_order=='idle') and u.soldiers.any(func(a):return a.get('settled_by_sibling',false)),'Gathered soldiers settle successively instead of all seeking an occupied point')
	check(u.soldiers.all(func(a):return a.settled_position.distance_to(batch.center)<=batch.radius),'Every stop decision occurred inside its batch region, before later physical displacement')
	var state=u.soldiers.duplicate(true);var serial=r.move_batch_serial
	check(not r.command([u.id],'move',Vector2(-100,-100)) and state==u.soldiers and serial==r.move_batch_serial,'Invalid command preserves orders and serial')
	r.command([u.id],'hold',Vector2.ZERO)
	check(u.soldiers.all(func(a):return a.personal_order=='hold' and a.move_batch.id==batch.id),'H retains native batch membership while holding position')
	r.command([u.id],'move',Vector2(1000,900))
	check(u.soldiers.all(func(a):return a.move_batch.id!=batch.id and not a.has('settled_by_sibling')),'Replacement movement allocates a fresh batch and clears old completion flags')
	var actor={'hp':100.,'position':Vector2(100,100),'personal_order':'move','move_batch':{'id':7,'center':Vector2(100,100),'radius':50.}}
	var other={'hp':100.,'personal_order':'idle','target_id':-1,'move_batch':{'id':7}}
	var neighbour={'unit':{'id':2,'side':'ally','soldiers':[other]},'slot':0,'radius':9.,'point':Vector2(123,100)}
	var row={'unit':{'id':1,'side':'ally','soldiers':[actor]},'slot':0,'radius':9.,'point':actor.position,'neighbours':[neighbour]}
	check(r.Soldiers.sibling_settled(row),'Same-team idle sibling within9+9+0.6*9 permits settlement')
	neighbour.point.x=124.
	check(not r.Soldiers.sibling_settled(row),'Neighbour outside the native23.4 threshold cannot settle the mover')
	neighbour.radius=13.;neighbour.point.x=129.
	check(r.Soldiers.sibling_settled(row),'Mixed body sizes use the larger radius for the0.6 term')
	other.personal_order='move';check(not r.Soldiers.sibling_settled(row),'A still-moving sibling cannot seed settlement')
	other.personal_order='idle';other.target_id=42;check(not r.Soldiers.sibling_settled(row),'An actively pursuing idle-command unit is not a native idle state')
	other.personal_order='hold';check(r.Soldiers.sibling_settled(row),'Explicit holding is an eligible settled state')
	other.move_batch.id=8;check(not r.Soldiers.sibling_settled(row),'A different order batch cannot settle this mover')
	other.move_batch.id=7;neighbour.unit.side='enemy';check(not r.Soldiers.sibling_settled(row),'An enemy cannot settle the batch')
	neighbour.unit.side='ally';actor.position=Vector2(151,100);check(not r.Soldiers.sibling_settled(row),'Mover outside its own gather radius cannot stop at a nearby sibling')
	actor.position=Vector2(100,100);other.hp=0.;check(not r.Soldiers.sibling_settled(row),'Dead members cannot seed settlement')
	print('Move batches: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
