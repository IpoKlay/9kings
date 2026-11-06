extends SceneTree
## Inject a single long, qualified movement segment through a moving regiment.
## Native movies separately test earning this state from rest using a player command.
const Pass=preload('res://scripts/tactical/pass_battle.gd')
var checks=0
var errors=0
func check(ok: bool,what: String):
	checks+=1
	if not ok:errors+=1;push_error(what)

func _initialize():
	var r=Pass.new();r.units.clear()
	r.spawn('legion','enemy',Vector2(2100,700))
	r.spawn('cavalry','ally',Vector2(1250,700))
	var b=r.units[0];var a=r.units[1]
	b.order='hold';b.heading=Vector2.DOWN
	a.heading=Vector2.RIGHT;a.moving=true
	r.start()
	var pa=r.Sweep.pose(r,a)
	var pb=r.Sweep.pose(r,b)
	check(r.Sweep.earliest(r,a,b,pa,pb,0).is_empty(),'No opaque contact at segment start')
	b.pos+=Vector2(-65,35)
	a.pos=Vector2(2910,700)
	a.charge=true;a.charge_id=3;a.charge_target=b.id;a.clear_run=1820.
	a.march_distance=1660.;a.pace=1.82;a.order='attack';a.target_id=b.id
	r.elapsed=.25
	check(r.Sweep.earliest(r,a,b,r.Sweep.pose(r,a),r.Sweep.pose(r,b),0).is_empty(),'Disjoint again at the far endpoint')
	var hp: float=b.hp
	r.sweep_legion_charges({a.id:pa,b.id:pb},.25)
	check(a.has('last_contact'),'Continuous sweep catches complete pass-through')
	if not a.has('last_contact'):quit(1);return
	var c: Dictionary=a.last_contact
	check(c.fraction>0 and c.fraction<1 and c.speed>6000,'Time of impact and measured speed')
	check(c.attacker==a.id and c.target==b.id and c.charge_id==3 and c.direction.is_equal_approx(Vector2.RIGHT),'Immutable charge identity')
	check(r.events.size()==1 and is_same(c,r.events[0].contact) and hp-b.hp>0,'One hit event for many visible riders')
	check(is_same(b.contact_motion.contact,c) and b.contact_motion.offsets.has(c.defender_slot),'Reaction starts on the exact defender')
	var after: float=b.hp
	for i in 32:r.deal_blow(a,b,17,c)
	check(after==b.hp and r.events.size()==1,'Duplicate record deliveries spend zero extra damage')
	# Leave a hole at the first edge and repeat the geometry against that same path.
	r.spawn('legion','enemy',pb.pos)
	var depleted=r.units.back()
	depleted.heading=b.heading
	var slots=r.contact_profiles.legion.feet.size()
	depleted.hp=depleted.max_hp*(slots-1)/slots
	depleted.slot_priority={}
	for i in slots:depleted.slot_priority[i]=i
	depleted.slot_priority[c.defender_slot]=slots-1
	depleted.slot_priority[slots-1]=c.defender_slot
	var old_b=r.Sweep.pose(r,depleted)
	depleted.pos=b.pos
	a.pos=Vector2(2910,700)
	var next=r.Sweep.earliest(r,a,depleted,pa,old_b,.25)
	check(not next.is_empty() and next.defender_slot!=c.defender_slot,'Missing soldier cannot be the first edge')
	print('Swept legion: ',checks,' checks, ',errors,' failures')
	quit(1 if errors else 0)
