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
	r.spawn('legion','ally',Vector2(950,900))
	r.spawn('legion','enemy',Vector2(1195,920))
	var a=r.units[0];var b=r.units[1]
	for u in [a,b]:u.heading=Vector2.UP;u.formation_heading=u.heading;u.order='hold'
	r.start()
	return {'r':r,'a':a,'b':b}
func run():
	var f=fixture();var r=f.r;var a=f.a;var b=f.b
	check(a.soldiers.size()==10 and a.hp==1000,'Ten independent swordsmen use the official 100 health per person')
	var before: float=b.hp
	strike(r,a,b)
	var actors=a.soldiers.filter(func(s):return s.attack_age<.8)
	check(actors.size()>0 and actors.size()<4,'Only the overlapping end of the line attacks')
	check(a.soldiers[9].attack_age>10. and a.soldiers[9].cooldown==0.,'Uncontacted flank neither attacks nor spends cooldown')
	var wounded=b.soldiers.filter(func(s):return s.hp<s.max_hp)
	check(wounded.size()>0 and wounded.size()<4,'Damage lands on specific opposing soldiers')
	check(is_equal_approx(before-b.hp,25.*actors.size()),'Ordinary H does not grant explicit F shield-wall damage reduction')
	check(r.Contact.count(b,r.config.types.legion)==10,'Wounds do not delete an unrelated visible figure')
	var hurt_slot=0
	for i in b.soldiers.size():
		if b.soldiers[i].hp<b.soldiers[i].max_hp:hurt_slot=i;break
	var previous: float=b.hp
	var health: float=b.soldiers[hurt_slot].hp
	r.hurt(b,1000.,'legion',0.,hurt_slot)
	check(is_equal_approx(previous-b.hp,health),'Excess damage to one person does not teleport to distant soldiers')
	check(not r.Contact.present(b,hurt_slot,10) and r.Contact.count(b,r.config.types.legion)==9,'The actual victim leaves a permanent vacancy')
	r.step(1./60)
	var body=r.casualties.filter(func(c):return c.unit_id==b.id and c.slot==hurt_slot)
	check(body.size()==1,'Exactly one body is left at the killed slot')
	r.heal(b,1000.)
	check(b.soldiers[hurt_slot].hp==0 and r.Contact.count(b,r.config.types.legion)==9,'Medic healing cannot resurrect a fallen soldier')
	check(is_equal_approx(b.hp,900.),'Only surviving wounded soldiers can be healed')
	# Two soldiers can be on different cooldowns despite belonging to one regiment.
	var g=fixture();var q=g.r;var x=g.a;var y=g.b
	strike(q,x,y)
	var spent=y.hp
	strike(q,x,y)
	check(y.hp==spent,'Immediate repeat cannot reuse an individual attack')
	for actor in x.soldiers:actor.cooldown=10.
	x.soldiers[0].cooldown=0.
	strike(q,x,y)
	check(y.hp<spent and x.soldiers[1].cooldown==10.,'One ready soldier can strike while a neighbour is recovering')
	var snapshot=x.soldiers.duplicate(true)
	q.step(0.)
	check(x.soldiers==snapshot,'Paused simulation preserves individual cooldowns and wounds')
	# Arrow target identity survives flight and cannot damage a replacement slot.
	var v=fixture();var vr=v.r;vr.units.clear()
	vr.spawn('archer','ally',Vector2(900,1000));vr.spawn('legion','enemy',Vector2(900,750))
	var ar=vr.units[0];var victim=vr.units[1]
	strike(vr,ar,victim)
	check(vr.volleys.size()==10 and vr.volleys.all(func(arrow):return arrow.has('target_slot')),'Each living archer releases an individually targeted arrow')
	var target_slot: int=vr.volleys[0].target_slot
	vr.hurt(victim,1000.,'',0.,target_slot)
	var living_hp: float=victim.hp
	vr.volleys=vr.volleys.filter(func(arrow):return arrow.target_slot==target_slot)
	vr.advance_volleys(1.)
	check(victim.hp==living_hp,'Arrows aimed at a dead soldier cannot silently select another victim')
	# Defeating all actual soldiers still reaches the normal result screen state.
	for i in y.soldiers.size():q.hurt(y,10000.,'',0.,i)
	q.step(1./60)
	check(q.phase=='victory','Individual deaths drive the existing battle result')
	var escort=fixture();var er=escort.r;var ea=escort.a;var eb=escort.b
	ea.combat_stats=er.config.types.legion.duplicate()
	ea.combat_stats.damage=50.;ea.combat_stats.interval=.4
	var enemy_hp: float=eb.hp
	strike(er,ea,eb)
	var attackers=ea.soldiers.filter(func(s):return s.attack_age<.8)
	check(is_equal_approx(enemy_hp-eb.hp,50.*attackers.size()) and attackers.all(func(s):return s.cooldown==.4),'Per-unit damage and attack-speed bonuses reach individual attacks without passive H protection')
	print('Individual combat: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)

func strike(r,a,b,only_slot=-1,target_slot=-1):
	r.Soldiers.attack(r,a,b,only_slot,target_slot)
	for actor in a.soldiers:actor.attack_age+=.61
	r.Soldiers.fire_attacks(r)
