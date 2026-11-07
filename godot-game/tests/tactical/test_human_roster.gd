extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
const CASES=[['heavy','guard',150.,50.,80.,28.,true,false,130,.35],['crossbow','archer',75.,30.,120.,500.,false,false,4,.30],['peasant','legion',60.,15.,90.,33.,false,false,160,.45],['veteran_spearman','spear',140.,35.,75.,43.,true,true,137,.45],['knight','cavalry',180.,45.,182.,37.,true,false,210,.45],['noble_son','legion',80.,20.,85.,30.,true,true,129,.45]]
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func run():
	for c in CASES:
		var r=Battle.new();r.units.clear();r.spawn(c[1],'ally',Vector2(1000,1200),c[0]);r.spawn('guard','enemy',Vector2(1000,1175))
		for u in r.units:
			u.order='hold'
			for i in u.soldiers.size():r.Charges.detach(r,u,i);u.soldiers[i].position=u.pos+Vector2(i*35,0);u.soldiers[i].cooldown=999.
		r.start();r.enemy_director.active=false
		var a=r.units[0];var target=r.units[1];var s=a.soldiers[0];var stats=r.Soldiers.individual(r,a);var id=[Vector2i(a.id,0)]
		check(a.archetype==c[0] and a.art==c[0] and s.max_hp==c[2] and a.hp==c[2]*a.soldiers.size(),c[0]+' creates correct per-person health and dedicated art')
		check(a.combat_stats.damage==c[3] and a.combat_stats.speed==c[4] and stats.range==c[5] and stats.role_bits==c[8],c[0]+' uses independent combat stats and strategic roles')
		check(is_equal_approx(stats.fire_fraction,c[9]),c[0]+' uses the correct remaining animation release fraction')
		check(r.Charges.ready(r,a,s)==c[6],c[0]+' charge capability is not inherited from base slot')
		check((not r.Walls.layout(r,id,Vector2(950,1200),Vector2(1050,1200)).is_empty())==c[7],c[0]+' shield capability is not inherited from base slot')
		check(not r.Volley.capable(r,{'unit':a,'actor':s}),c[0]+' does not inherit longbow volley')
		s.target_id=target.id;s.target_slot=0;s.attack_pending=true;s.attack_age=.8*(1.-c[9])+.001
		var hp: float=target.soldiers[0].hp;r.Soldiers.fire_actor(r,a,0)
		if c[0]=='crossbow':
			check(r.volleys.size()==1 and r.volleys[0].damage==30. and is_equal_approx(r.volleys[0].flight,r.volleys[0].origin.distance_to(r.volleys[0].pos)/400.),'Crossbow launches one actual bolt with30 damage and400 speed')
			r.advance_volleys(1.)
		check(is_equal_approx(target.soldiers[0].hp,hp-c[3]),c[0]+' ordinary attack applies its own damage; plain H grants no shield-wall reduction')
		r.Soldiers.fire_actor(r,a,0);r.advance_volleys(1.)
		check(is_equal_approx(target.soldiers[0].hp,hp-c[3]),c[0]+' release cannot award duplicate damage')
		r.spawn(c[1],'enemy',Vector2(1500,800),c[0]);var e=r.units.back()
		check(e.archetype==c[0] and e.soldiers[0].max_hp==c[2] and r.Soldiers.individual(r,e).role_bits==c[8],c[0]+' also works on the enemy side')
		var deploy=Battle.new();deploy.set(c[1]+'_variant',c[0]);deploy.deploy_combined()
		check(deploy.alive('ally').any(func(u):return u.get('archetype','')==c[0]),c[0]+' is reachable through normal combined deployment')
		check(deploy.alive('enemy').all(func(u):return u.get('archetype','')==''),c[0]+' player selection does not rewrite the default enemy roster')
	var r=Battle.new();r.units.clear();r.spawn('guard','ally',Vector2(1000,1200));r.spawn('guard','ally',Vector2(1250,1200),'heavy');r.spawn('legion','enemy',Vector2(1000,900));r.start()
	var ids=[Vector2i(r.units[0].id,0),Vector2i(r.units[1].id,0)]
	var plan=r.Walls.layout(r,ids,Vector2(900,1200),Vector2(1100,1200))
	check(plan.size()==1 and plan.has(ids[0]) and not plan.has(ids[1]),'Mixed F selection includes eligible shield bearer and excludes two-handed heavy')
	var victim=r.units[0];var attacker=r.units[2];r.Charges.detach(r,victim,0);r.Charges.detach(r,attacker,0);victim.soldiers[0].position=Vector2(1000,1200);attacker.soldiers[0].position=Vector2(1000,1170);victim.soldiers[0].heading=Vector2.UP;victim.soldiers[0].shield_wall=true
	var hp: float=victim.hp;r.deal_blow(attacker,victim,25.,{},{'attacker_slot':0,'target_slot':0})
	check(is_equal_approx(victim.hp,hp-10.),'Actual F shield wall still reduces frontal melee by60 percent')
	print('Human roster: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
