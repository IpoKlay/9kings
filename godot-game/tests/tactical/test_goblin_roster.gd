extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
const CASES=[['runt','legion',40.,8.,110.,23.,false,false,160,.45],['brat','legion',50.,10.,100.,25.,false,true,129,.45],['spiker','spear',65.,18.,95.,33.,true,true,136,.45],['stabber','guard',70.,16.,100.,27.,true,true,129,.45],['archer','archer',45.,10.,120.,350.,false,false,4,.25],['slinger','archer',40.,8.,130.,300.,false,false,36,.25],['wolf_rider','cavalry',100.,22.,182.,32.,true,false,210,.45],['wolf_skirmisher','cavalry',80.,12.,175.,380.,false,false,84,.25],['troll','guard',350.,55.,55.,33.,false,false,130,.35],['shaman','archer',60.,5.,80.,250.,false,false,36,.25]]
var checks=0
var failures=0
func check(ok:bool,note:String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture(kind:String,variant:String):
	var r=Battle.new();r.units.clear();r.spawn(kind,'ally',Vector2(1000,1200),variant);r.spawn('guard','enemy',Vector2(1000,1175));r.spawn('legion','ally',Vector2(1200,1200))
	for u in r.units:
		u.order='hold'
		for i in u.soldiers.size():r.Charges.detach(r,u,i);u.soldiers[i].position=u.pos+Vector2(i*150,0);u.soldiers[i].cooldown=999.
	r.start();r.enemy_director.active=false
	return r
func run():
	for c in CASES:
		var name='goblin_'+c[0];var r=fixture(c[1],name);var u=r.units[0];var v=r.units[1];var a=u.soldiers[0];var st=r.Soldiers.individual(r,u);var ids=[Vector2i(u.id,0)]
		check(u.archetype==name and u.art==name and a.max_hp==c[2] and u.hp==c[2]*u.soldiers.size(),name+' personal health and art')
		check(st.damage==c[3] and st.speed==c[4] and st.range==c[5] and st.role_bits==c[8],name+' independent stats/roles')
		check(r.Charges.ready(r,u,a)==c[6],name+' C eligibility')
		check((not r.Walls.layout(r,ids,Vector2(950,1200),Vector2(1050,1200)).is_empty())==c[7],name+' F eligibility')
		check(not r.Volley.capable(r,{'unit':u,'actor':a}) and r.Blink.ready(r,ids).is_empty(),name+' no inherited V/B')
		var release=.8*(1.-c[9]);a.target_id=v.id;a.target_slot=0;a.attack_pending=true;a.attack_age=release-.002
		var hp:float=v.soldiers[0].hp;r.Soldiers.fire_actor(r,u,0)
		check(v.soldiers[0].hp==hp and r.volleys.is_empty(),name+' no premature hit')
		a.attack_age=release;r.Soldiers.fire_actor(r,u,0)
		if c[0] in ['archer','slinger','wolf_skirmisher']:
			check(r.volleys.size()==1 and is_equal_approx(r.volleys[0].flight,r.volleys[0].origin.distance_to(r.volleys[0].pos)/400.) and v.soldiers[0].hp==hp,name+' real projectile flight before hit')
			check((r.volleys[0].projectile_art=='sling_stone')==(c[0]=='slinger'),name+' correct stone or arrow appearance')
			r.advance_volleys(1.)
		var expected=0. if c[0]=='shaman' else c[3]*(1.-.6*25./80.) if c[0]=='troll' else c[3]
		check(is_equal_approx(v.soldiers[0].hp,hp-expected),name+' shared release uses actual special or direct damage')
		r.Soldiers.fire_actor(r,u,0);r.advance_volleys(1.);check(is_equal_approx(v.soldiers[0].hp,hp-expected),name+' no double attack')
		check(r.Soldiers.mounted_ranged(u)==(c[0]=='wolf_skirmisher'),name+' only wolf skirmisher uses moving archery')
		var deploy=Battle.new();deploy.set(c[1]+'_variant',name);deploy.deploy_combined();check(deploy.alive('ally').any(func(a):return a.get('archetype','')==name),name+' real combined deployment')
		check(deploy.alive('enemy').all(func(a):return a.get('archetype','')==''),name+' preserves default enemies')
		check(u.get('visual_scale',1.)==(1.5 if c[0]=='troll' else 1.),name+' only giant has enlarged presentation')
	slam_checks();heal_checks()
	print('Goblin roster: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
func slam_checks():
	var r=fixture('guard','goblin_troll');var u=r.units[0];var v=r.units[1];var a=u.soldiers[0];var p:Vector2=a.position
	var offsets=[Vector2.ZERO,Vector2(40,0),Vector2(80,0),Vector2(80.01,0),Vector2(-40,0)]
	for i in offsets.size():v.soldiers[i].position=p+offsets[i]
	v.soldiers[1].impulse=Vector2(10,0);v.soldiers[5].position=p+Vector2(10,0);v.soldiers[5].hp=0;r.Soldiers.total(v)
	r.units[2].soldiers[0].position=p+Vector2(20,0)
	a.target_id=v.id;a.target_slot=0;a.attack_pending=true;a.attack_age=.52;r.Soldiers.fire_actor(r,u,0)
	check(v.soldiers[0].hp==75 and is_equal_approx(v.soldiers[1].hp,91.5) and is_equal_approx(v.soldiers[2].hp,108.),'Slam center/half/edge damage55/38.5/22')
	check(v.soldiers[3].hp==130 and v.soldiers[4].hp==91.5,'Slam hits behind caster but not beyond80 radius')
	check(v.soldiers[5].hp==0 and r.units[2].hp==r.units[2].max_hp,'Slam excludes dead and friendly units')
	check(v.soldiers[0].get('impulse',Vector2.ZERO)==Vector2.ZERO and v.soldiers[1].impulse.is_equal_approx(Vector2(220,0)) and v.soldiers[2].impulse.is_equal_approx(Vector2(120,0)),'Slam adds distance-scaled radial impulse; coincident victim no arbitrary axis')
	v.soldiers[1].hp=130;v.soldiers[1].shield_wall=true;v.soldiers[1].heading=Vector2.LEFT;v.soldiers[1].wall_heading=Vector2.LEFT;v.soldiers[1].impulse=Vector2.ZERO;r.Soldiers.total(v)
	a.attack_pending=true;r.Soldiers.fire_actor(r,u,0)
	check(is_equal_approx(v.soldiers[1].hp,114.6) and v.soldiers[1].impulse==Vector2(210,0),'F reduces slam damage60 percent but not independent push impulse')
	check(v.soldiers[1].last_attacker==Vector2i(u.id,0),'Slam retains real attacker for retaliation')
	var before=v.soldiers[1].position;r.terrain.ROCKS=[r.projection*Rect2(before+Vector2(12,-50),Vector2(25,100))]
	var nav=r.Soldiers.navigator(r,v.kind,v);r.terrain.clearances.erase(nav);r.terrain.extents.erase(nav)
	r.Soldiers.Physics.integrate(r,[{'unit':v,'slot':1,'point':before}],.2)
	check(v.soldiers[1].position.x<before.x+12,'Slam displacement respects authored rock sweep')
func heal_checks():
	var r=fixture('archer','goblin_shaman');var u=r.units[0];var v=r.units[1];var ally=r.units[2];var a=u.soldiers[0];var p:Vector2=a.position
	a.hp=20;u.soldiers[1].hp=25;u.soldiers[1].position=p+Vector2(10,0);r.Soldiers.total(u)
	for i in 4:ally.soldiers[i].position=p+Vector2([100,120,120.01,40][i],0);ally.soldiers[i].hp=[30,95,20,0][i]
	r.Soldiers.total(ally);var enemy_hp=v.hp
	a.target_id=v.id;a.target_slot=0;a.attack_pending=true;a.attack_age=.6;r.Soldiers.fire_actor(r,u,0)
	check(a.hp==20 and u.soldiers[1].hp==40,'Shaman heals another shaman but excludes itself')
	check(ally.soldiers[0].hp==45 and ally.soldiers[1].hp==100 and ally.soldiers[2].hp==20 and ally.soldiers[3].hp==0,'Heal15 caps at max, includes120 boundary, excludes outside and dead')
	check(v.hp==enemy_hp and r.volleys.is_empty(),'Shaman cast deals no nominal5 damage and creates no projectile')
	check(is_equal_approx(ally.hp,ally.soldiers.reduce(func(sum,a):return sum+a.hp,0.)),'Healed personal HP synchronizes squad total without redistributing')
	check(r.events.filter(func(e):return e.kind=='shaman_heal').size()==3,'Only the three actually healed people emit feedback')
	var before=ally.hp;v.soldiers[0].hp=0;r.Soldiers.total(v);a.attack_pending=true;r.Soldiers.fire_actor(r,u,0)
	check(ally.hp>before,'Registered zero-HP primary target still permits the due heal release')
	var hp=ally.hp;v.soldiers[0].hp=0;v.soldiers[0].death_state=1;r.Soldiers.total(v);a.attack_pending=true;r.Soldiers.fire_actor(r,u,0)
	check(ally.hp==hp,'Main target unregistered before release cancels heal cast')
	a.target_id=-1;a.attack_pending=true;r.Soldiers.fire_actor(r,u,0);check(ally.hp==hp,'Shaman is not an out-of-combat automatic medic')
