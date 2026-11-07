extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
# Reference resource values, plus behavior tests through the shared combat entry points.
const CASES=[['draugr','guard',120.,28.,65.,30.,true,true,129,.45,10.],['skeleton_archer','archer',40.,16.,75.,250.,false,false,4,.25,8.],['skeleton_spearman','spear',90.,22.,60.,35.,false,true,137,.45,9.],['gravewalker','legion',40.,8.,55.,28.,false,false,160,.45,8.],['death_rider','cavalry',90.,22.,130.,35.,true,false,210,.45,16.],['fell_hound','legion',30.,14.,150.,25.,false,false,144,.4,7.]]
var checks=0
var failures=0
func check(ok:bool,note:String):
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
		var u=r.units[0];var v=r.units[1];var a=u.soldiers[0];var st=r.Soldiers.individual(r,u);var ids=[Vector2i(u.id,0)]
		check(u.archetype==c[0] and u.art==c[0] and a.max_hp==c[2] and u.hp==c[2]*u.soldiers.size(),c[0]+' actual per-person health and art')
		check(u.combat_stats.damage==c[3] and st.speed==c[4] and st.range==c[5] and st.role_bits==c[8] and st.unit_size==c[10],c[0]+' independent weapon, speed, roles and body')
		check(r.Charges.ready(r,u,a)==c[6],c[0]+' C permission')
		check((not r.Walls.layout(r,ids,Vector2(950,1200),Vector2(1050,1200)).is_empty())==c[7],c[0]+' F permission')
		check(not r.Volley.capable(r,{'unit':u,'actor':a}) and r.Blink.ready(r,ids).is_empty(),c[0]+' cannot inherit V or B')
		var release=.8*(1.-c[9]);a.target_id=v.id;a.target_slot=0;a.attack_pending=true;a.attack_age=release-.002
		var hp:float=v.soldiers[0].hp;r.Soldiers.fire_actor(r,u,0)
		check(v.soldiers[0].hp==hp and r.volleys.is_empty(),c[0]+' no damage or projectile before release')
		a.attack_age=release;r.Soldiers.fire_actor(r,u,0)
		if c[0]=='skeleton_archer':
			check(r.volleys.size()==1 and is_equal_approx(r.volleys[0].flight,r.volleys[0].origin.distance_to(r.volleys[0].pos)/380.) and v.soldiers[0].hp==hp,'Skeleton arrow has actual 380 flight speed and delayed damage')
			r.advance_volleys(1.)
		check(is_equal_approx(v.soldiers[0].hp,hp-c[3]),c[0]+' real hit at own fire fraction')
		r.Soldiers.fire_actor(r,u,0);r.advance_volleys(1.)
		check(is_equal_approx(v.soldiers[0].hp,hp-c[3]),c[0]+' no duplicate release damage')
		var nav=r.Soldiers.navigator(r,u.kind,u)
		check(r.terrain.extents.has(nav),c[0]+' actual body radius registered with terrain navigation')
		r.spawn(c[1],'enemy',Vector2(1500,800),c[0]);check(r.units.back().soldiers[0].max_hp==c[2],c[0]+' opposing faction stats')
		var deploy=Battle.new();deploy.set(c[1]+'_variant',c[0]);deploy.deploy_combined()
		check(deploy.alive('ally').any(func(a):return a.get('archetype','')==c[0]),c[0]+' normal combined deployment')
		check(deploy.alive('enemy').all(func(a):return a.get('archetype','')==''),c[0]+' does not overwrite default enemies')
	# Hound mobility is not a mounted role: anti-cavalry targeting must not reward it.
	var r=Battle.new();r.units.clear();r.spawn('spear','ally',Vector2(1000,1000));r.spawn('legion','enemy',Vector2(1000,900),'fell_hound');r.spawn('cavalry','enemy',Vector2(1000,900),'death_rider')
	r.start()
	for u in r.units:
		for i in u.soldiers.size():
			r.Charges.detach(r,u,i);u.soldiers[i].position=u.pos if i==0 else Vector2(1800,1800+i*30)
	var actor=r.units[0].soldiers[0];actor.personal_order='idle'
	var chosen=r.Soldiers.personal_target(r,r.units[0],0,actor)
	check(not chosen.is_empty() and chosen.unit.id==r.units[2].id,'Anti-cavalry acquisition prefers equally distant death rider over fast unmounted hound')
	print('Undead roster: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
