extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture():
	var r=Battle.new();r.units.clear()
	r.spawn('archer','ally',Vector2(1000,1400),'longbowman')
	r.spawn('legion','enemy',Vector2(1000,800))
	for u in r.units:
		u.order='hold'
		for i in u.soldiers.size():r.Charges.detach(r,u,i);u.soldiers[i].cooldown=999.
	r.start();return r
func run():
	var r=fixture();var a=r.units[0];var b=r.units[1]
	var ids=r.Soldiers.group_members([a]);var target=Vector2(1000,800)
	check(a.hp==850. and a.soldiers[0].max_hp==85.,'Longbow variant has actual 85 HP per soldier')
	check(r.Soldiers.individual(r,a).range==550. and a.combat_stats.speed==120. and a.combat_stats.damage==18. and a.combat_stats.interval==1.,'Longbow normal combat uses its own stats')
	r.spawn('archer','ally',Vector2(700,1400));var ordinary=r.units.back()
	check(ordinary.hp==800. and r.Soldiers.individual(r,ordinary).range==450. and not ordinary.has('combat_stats'),'Ordinary archers retain their original stats')
	check(not r.Volley.issue(r,r.Soldiers.group_members([ordinary]),target),'Ordinary archers have no V ability')
	check(not r.Volley.issue(r,ids,Vector2(1000,200)) and r.volleys.is_empty(),'Beyond 1080 ground units rejects without spending cooldown')
	check(r.Volley.issue(r,ids,target),'Ready longbow group fires')
	check(r.volleys.size()==30 and a.soldiers.all(func(s):return s.volley_cooldown==15.),'Ten actors emit thirty arrows and each owns a fifteen-second cooldown')
	check(r.volleys.all(func(v):return v.pos.distance_to(target)<=r.Volley.radius(10)*.4*sqrt(2.) and v.damage==18.),'Scatter is square-bounded and arrows use leader attack damage')
	check(r.volleys.all(func(v):return v.age<=0. and v.age>=-.4 and is_equal_approx(v.flight,clampf(v.from.distance_to(v.pos)/500.,.6,2.))),'Launch stagger and distance-based flight time follow the reference')
	check(is_equal_approx(r.Volley.radius(9),62.),'Radius grows with square root of group size')
	check(not r.Volley.issue(r,ids,target) and r.volleys.size()==30,'Cooldown prevents immediate repetition')
	var before=r.volleys.duplicate(true);r.step(0.)
	check(before==r.volleys and a.soldiers[0].volley_cooldown==15.,'Zero-time pause freezes arrows and cooldown')
	var fixed_landing: Vector2=r.volleys[0].pos;b.soldiers[0].position+=Vector2(300,0)
	r.advance_volleys(.1)
	check(r.volleys[0].pos==fixed_landing,'Arrows do not home on moving targets')
	for i in 40:r.advance_volleys(.1)
	check(r.volleys.is_empty() and r.ability_sounds.is_empty(),'Finished arrows and all scheduled sound cues are removed')
	check(r.events.filter(func(e):return e.get('volley',false)).size()==6,'Ten archers emit at most six scheduled bow cues')
	a.soldiers[0].volley_cooldown=0.;a.soldiers[1].hp=0.;r.Soldiers.total(a)
	check(r.Volley.issue(r,ids,target) and r.volleys.size()==3,'Only ready living selected actors participate')
	check(a.soldiers[2].volley_cooldown==15.,'Unready actors do not have their cooldown restarted')
	var hit=fixture();var victim=hit.units[1];var position=Vector2(1000,800)
	for i in victim.soldiers.size():victim.soldiers[i].position=position+Vector2(i*30,0)
	var arrow={'from':Vector2(1000,1400),'pos':position,'damage':18.,'side':'ally'}
	var hp: float=victim.hp;hit.Volley.land(hit,arrow)
	check(victim.hp==hp-18. and victim.soldiers[1].hp==victim.soldiers[1].max_hp,'One landing damages exactly one nearest enemy, not the splash area')
	victim.soldiers[0].shield_wall=true;hp=victim.hp;hit.Volley.land(hit,arrow)
	check(victim.hp==hp-18.,'Ability damage with no attacker bypasses directional shield reduction')
	arrow.pos=position-Vector2(20.9,0);hp=victim.hp;hit.Volley.land(hit,arrow)
	check(victim.hp==hp-18.,'Public implementation accepts a nearest enemy less than twenty-one units away')
	arrow.pos=position-Vector2(21,0);hp=victim.hp;hit.Volley.land(hit,arrow)
	check(victim.hp==hp,'Exactly twenty-one units is outside the strict nearest-hit threshold')
	arrow.pos=hit.Soldiers.ground_position(hit,hit.units[0],0);hp=hit.units[0].hp;hit.Volley.land(hit,arrow)
	check(hit.units[0].hp==hp,'Landing cannot damage the firing side')
	var dead=fixture();var da=dead.units[0];var db=dead.units[1]
	dead.Volley.issue(dead,dead.Soldiers.group_members([da]),target)
	for s in da.soldiers:s.hp=0.
	dead.Soldiers.total(da);hp=db.hp
	for i in 150:dead.advance_volleys(1./60)
	check(db.hp<hp and dead.volleys.is_empty(),'Arrows already released still land after their shooters die')
	var range_test=fixture();var ra=range_test.units[0]
	for s in ra.soldiers:s.position=Vector2(1000,1400)
	check(range_test.Volley.issue(range_test,range_test.Soldiers.group_members([ra]),Vector2(1000,320)),'Reference twenty-percent range tolerance accepts exact 1080 distance')
	var deployment=Battle.new();deployment.archer_variant='longbowman';deployment.deploy_combined()
	check(deployment.alive('ally').filter(func(u):return u.kind=='archer')[0].get('archetype','')=='longbowman','Normal combined deployment uses selected longbow loadout')
	check(deployment.alive('enemy').filter(func(u):return u.kind=='archer')[0].get('archetype','')=='','Player loadout does not change enemy archers')
	print('Longbow volley: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
