extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture() -> Dictionary:
	var r=Battle.new();r.units.clear()
	var center=Vector2(1050,900)
	var approach=Vector2(-.94,-.342).normalized()
	r.spawn('legion','enemy',center)
	r.spawn('cavalry','ally',center-approach*800)
	var b=r.units[0];var a=r.units[1]
	b.heading=Vector2.UP;b.formation_heading=b.heading;b.order='hold'
	a.heading=approach;a.formation_heading=approach;a.order='hold'
	r.start();r.command([a.id],'attack',b.pos,b.id)
	for frame in 600:
		r.step(1./60)
		if a.has('penetration'):break
	return {'r':r,'a':a,'b':b}
func passage(fps: int,rock: bool) -> Dictionary:
	var f=fixture();var r=f.r;var a=f.a;var b=f.b
	check(a.has('penetration'),'Qualified charge creates individual riders')
	if not a.has('penetration'):return {}
	var p: Dictionary=a.penetration
	check(p.contacts.size()==1 and is_equal_approx(p.contacts.values()[0],p.start),'Leading rider reacts in the same simulation step as impact')
	var outside=-1
	for i in p.riders:
		if is_zero_approx(p.riders[i].lane):outside=i;break
	check(outside>=0,'Control contains a horse outside the breakthrough lane')
	if rock:
		var point: Vector2=p.riders[outside].point+p.axis*6
		r.terrain.ROCKS.append(Rect2(point-Vector2(2,2),Vector2(4,4)))
	var hp: float=b.hp;var morale: float=b.morale
	for frame in fps*2:
		r.elapsed+=1./fps
		if not r.Contact.advance_passage(r,a,b,1./fps):break
	check(b.hp==hp and b.morale==morale,'Individual contacts never spend another damage/morale budget')
	var distances={}
	for i in p.riders:distances[i]=p.riders[i].travel
	return {'distances':distances,'outside':outside,'contacts':p.contacts.duplicate(),'rock':rock,'fps':fps}
func run():
	var via: Array[Vector2]=[]
	var control=passage(60,false)
	var blocked=passage(60,true)
	var slot: int=blocked.outside
	check(control.distances[slot]>10 and blocked.distances[slot]<6,'Only obstructed horse stops at the new rock')
	var unaffected=0
	for i in control.distances:
		if i!=slot and absf(control.distances[i]-blocked.distances[i])<.01 and control.distances[i]>10:unaffected+=1
	check(unaffected>=2,'At least two clear neighbours retain their own forward progress')
	for fps in [30,120]:
		var sample=passage(fps,true)
		check(sample.distances[slot]<6,'Rock sweep cannot tunnel at '+str(fps)+' FPS')
		for i in control.distances:
			check(absf(sample.distances[i]-blocked.distances[i])<4,'Per-rider stop varies by less than four pixels at '+str(fps)+' FPS')
	# Every accepted order interrupts momentum, even a repeated attack on the same target.
	for order in ['hold','auto','move','attack','route']:
		var f=fixture();var r=f.r;var a=f.a
		var accepted=r.march_route(a.id,via,a.pos+Vector2(0,80)) if order=='route' else r.command([a.id],order,a.pos+Vector2(0,80),f.b.id)
		check(accepted,'Replacement order accepted: '+order)
		check(not a.has('penetration') and not a.charge and a.charge_target==-1,'Replacement discards all active charge motion: '+order)
		check(a.recover_until>=r.elapsed+r.config.regiment_impact.recovery_seconds-.001,'Replacement applies charge recovery: '+order)
		var recovery: float=a.recover_until
		r.command([a.id],'hold',a.pos)
		check(a.recover_until==recovery,'Repeated non-charge input does not extend recovery')
	var f=fixture();var r=f.r;var a=f.a
	var recovery: float=a.recover_until
	check(not r.march_route(a.id,via,Vector2(-1,-1)),'Invalid route rejected')
	check(a.has('penetration') and a.recover_until==recovery,'Invalid route leaves the committed charge intact')
	# A second impact must start from existing displaced feet, not teleport to home.
	r.Contact.set_slot(r,a,0,Vector2(0,12),0.,2.,.5)
	var contact=r.Contact.locate(r,a,f.b,r.Contact.count(f.b,r.config.types[f.b.kind]))
	var before={}
	for i in r.Contact.feet(r,a).size():before[i]=r.projection*a.pos+r.Contact.feet(r,a)[i]+r.Contact.body_shift(a,i,r.elapsed)
	r.Contact.begin_passage(r,a,f.b,contact,true,false)
	for i in before:check(a.penetration.riders[i].point.distance_to(before[i])<.01,'New passage preserves current rider foot '+str(i))
	print('RIDER CONTROL ',JSON.stringify(control))
	print('RIDER OBSTACLE ',JSON.stringify(blocked))
	print('Independent riders: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
