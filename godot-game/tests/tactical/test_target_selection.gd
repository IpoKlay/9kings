extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture(kind='legion'):
	var r=Battle.new();r.units.clear()
	r.spawn(kind,'ally',Vector2(900,1200));r.spawn('legion','enemy',Vector2(900,1000));r.spawn('cavalry','enemy',Vector2(900,700))
	for u in r.units:u.order='hold'
	r.start()
	for u in r.units:
		for i in u.soldiers.size():
			u.soldiers[i].position=Vector2(900,1200);u.soldiers[i].hp=0. if i>0 else u.soldiers[i].max_hp
		r.Soldiers.total(u)
	r.units[0].soldiers[0].personal_order='idle'
	r.units[1].soldiers[0].position=Vector2(900,1100)
	r.units[2].soldiers[0].position=Vector2(900,700)
	return r
func choose(r):
	var u=r.units[0];var a=u.soldiers[0];a.target_id=-1;a.target_slot=-1;a.next_scan=0.
	return r.Soldiers.personal_target(r,u,0,a)
func retarget(r):
	var u=r.units[0];var a=u.soldiers[0];a.retarget_timer=0.
	var old=r.Soldiers.identified_target(r,u,0,a.target_id,a.target_slot)
	return r.Soldiers.retarget_pursuit(r,u,0,a,old,r.Soldiers.ranged_target_counts(r),1./60.)
func run():
	var r=fixture();var a=r.units[0];var foot=r.units[1];var horse=r.units[2]
	check(choose(r).unit.id==foot.id,'Ordinary infantry selects the nearer healthy opponent')
	foot.soldiers[1].hp=10.;foot.soldiers[1].position=Vector2(900,1080);r.Soldiers.total(foot)
	check(choose(r).near.slot==1,'A wounded individual can outrank the closest healthy soldier in the same regiment')
	foot.soldiers[1].position=Vector2(900,800)
	check(choose(r).near.slot==0,'Injury preference does not outweigh a large distance penalty')
	r=fixture('spear');a=r.units[0];foot=r.units[1];horse=r.units[2]
	check(choose(r).unit.id==horse.id,'Idle spearman prioritizes eligible cavalry at500 over infantry at100')
	for u in r.units:
		for s in u.soldiers:s.position=Vector2(900,1200)+(s.position-Vector2(900,1200)).rotated(PI/3.)
	check(choose(r).unit.id==horse.id,'Rotating the entire encounter preserves ground-distance target scoring')
	horse.soldiers[0].position=Vector2(900,599)
	check(choose(r).unit.id==foot.id,'Anti-cavalry preference cannot select outside the600 aggro radius')
	horse.soldiers[0].position=Vector2(900,1165);foot.soldiers[0].position=Vector2(900,1180)
	a.soldiers[0].personal_order='hold'
	check(choose(r).unit.id==foot.id,'Holding spearman attacks the nearest within weapon reach without role scoring')
	a.soldiers[0].personal_order='idle';a.soldiers[0].shield_wall=true
	check(choose(r).unit.id==foot.id,'Shield stance also keeps nearest-in-reach selection')
	r=fixture('archer');a=r.units[0];foot=r.units[1];horse=r.units[2]
	for s in a.soldiers:s.hp=s.max_hp;s.personal_order='idle'
	for i in foot.soldiers.size():foot.soldiers[i].hp=foot.soldiers[i].max_hp;foot.soldiers[i].position=Vector2(900,1000)
	r.Soldiers.total(a);r.Soldiers.total(foot)
	var counts=r.Soldiers.ranged_target_counts(r);var targets={}
	for i in a.soldiers.size():
		var selected=r.Soldiers.personal_target(r,a,i,a.soldiers[i],counts);targets[Vector2i(selected.unit.id,selected.near.slot)]=true
	check(targets.size()==10,'Ten equal-distance archers distribute aim across ten living enemies during one decision pass')
	check(counts==r.Soldiers.ranged_target_counts(r),'Incremental reservations match the living-actor target ledger')
	for s in a.soldiers:s.personal_order='attack';s.focus_id=foot.id;s.focus_slot=0;s.target_id=-1;s.target_slot=-1
	counts=r.Soldiers.ranged_target_counts(r)
	for i in a.soldiers.size():r.Soldiers.personal_target(r,a,i,a.soldiers[i],counts)
	check(a.soldiers.all(func(s):return s.target_id==foot.id and s.target_slot==0),'Explicit individual focus overrides ranged spread for every archer')
	check(counts.get(Vector2i(foot.id,0),0)==10 and counts.values().reduce(func(sum,v):return sum+v,0)==10,'Changing focus transfers reservations without accumulating duplicate claims')
	foot.soldiers[0].hp=0.;r.Soldiers.total(foot)
	for i in a.soldiers.size():r.Soldiers.personal_target(r,a,i,a.soldiers[i],counts)
	check(a.soldiers.all(func(s):return s.target_id==-1) and counts.values().reduce(func(sum,v):return sum+v,0)==0,'Death of an explicitly focused individual clears aim without silently selecting another')
	r=fixture('archer');a=r.units[0];foot=r.units[1];horse=r.units[2]
	foot.soldiers[0].position=Vector2(900,1000);foot.soldiers[1].hp=foot.soldiers[1].max_hp;foot.soldiers[1].position=Vector2(900,990);r.Soldiers.total(foot)
	a.soldiers[1].hp=a.soldiers[1].max_hp;a.soldiers[1].target_id=foot.id;a.soldiers[1].target_slot=0;r.Soldiers.total(a)
	check(choose(r).near.slot==1,'A slightly farther unclaimed enemy beats an already aimed-at healthy target')
	a.soldiers[1].hp=0.;r.Soldiers.total(a)
	check(choose(r).near.slot==0,'A dead shooter no longer reserves its previous target')
	foot.soldiers[0].position=Vector2(900,749);foot.soldiers[1].hp=0.;r.Soldiers.total(foot)
	check(choose(r).is_empty(),'Player archers do not acquire outside actual450 weapon range')
	r=fixture();a=r.units[0];foot=r.units[1];horse=r.units[2]
	a.soldiers[0].target_id=horse.id;a.soldiers[0].target_slot=0;foot.soldiers[0].position=Vector2(900,1130)
	var selected=retarget(r)
	check(selected.unit.id==foot.id,'Pursuit beyond twice weapon reach can switch to an enemy within eight body radii')
	foot.soldiers[0].position=Vector2(900,1127);a.soldiers[0].target_id=horse.id;a.soldiers[0].target_slot=0;a.soldiers[0].next_scan=0.
	check(retarget(r).unit.id==horse.id,'A closer enemy outside the72 retarget neighbourhood does not replace the pursuit target')
	r=fixture('archer');a=r.units[0];foot=r.units[1];horse=r.units[2]
	# Short-range fixture isolates the squared-distance retarget penalty from acquisition scoring.
	r.config.types.archer.individual.range=30.
	foot.soldiers[0].position=Vector2(900,1130);horse.soldiers[0].position=Vector2(900,1160)
	for i in 5:
		a.soldiers[i].hp=a.soldiers[i].max_hp;a.soldiers[i].target_id=horse.id;a.soldiers[i].target_slot=0
	r.Soldiers.total(a);a.soldiers[0].target_id=foot.id
	check(retarget(r).unit.id==foot.id,'Retargeting retains a70-distance target when four shooters already claim the40-distance alternative')
	a.soldiers[4].hp=0.;r.Soldiers.total(a);a.soldiers[0].next_scan=0.
	check(retarget(r).unit.id==horse.id,'With only three claims, retargeting switches using1500 squared-distance penalty per shooter, including self on current target')
	var saved=a.soldiers.duplicate(true);r.step(0.)
	check(a.soldiers==saved,'Paused simulation freezes target selection and scan timers')
	print('Target selection: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
