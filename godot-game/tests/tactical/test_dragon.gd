extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok:bool,note:String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture():
	var r=Battle.new();r.units.clear();r.spawn('guard','ally',Vector2(1000,1200),'dragon');r.spawn('guard','enemy',Vector2(1100,1200),'dragon');r.spawn('legion','ally',Vector2(1000,1100))
	for u in r.units:
		u.order='hold'
		for i in u.soldiers.size():r.Charges.detach(r,u,i);u.soldiers[i].position=Vector2(3000+i*150,3000);u.soldiers[i].cooldown=999.
	r.units[0].soldiers[0].position=Vector2(1000,1200);r.units[1].soldiers[0].position=Vector2(1100,1200)
	r.start();r.enemy_director.active=false
	return r
func run():
	var r=fixture();var u=r.units[0];var v=r.units[1];var a=u.soldiers[0];var st=r.Soldiers.individual(r,u);var ids=[Vector2i(u.id,0)]
	check(a.max_hp==800 and u.hp==8000 and st.damage==60 and st.interval==2,'Dragon individual800HP/60damage/2s')
	check(st.range==220 and st.speed==300 and st.aggro_range==900 and st.unit_size==24,'Dragon actual default220range/300speed/900aggro/24radius')
	check(st.role_bits==130 and not r.Soldiers.ranged(u) and not r.Soldiers.mounted_ranged(u),'Dragon is shock melee, neither ranged nor mounted')
	check(r.Charges.ready(r,u,a) and st.charge_cooldown==15,'C available with15s cooldown')
	check(r.Walls.layout(r,ids,Vector2(950,1200),Vector2(1050,1200)).is_empty() and not r.Volley.capable(r,{'unit':u,'actor':a}) and r.Blink.ready(r,ids).is_empty(),'No inherited F/V/B')
	check(u.art=='dragon' and u.visual_scale==3.,'Own large dragon presentation')
	a.target_id=v.id;a.target_slot=0;a.attack_pending=true;a.attack_age=.519;r.Soldiers.fire_actor(r,u,0)
	check(v.hp==8000 and r.volleys.is_empty(),'Ordinary hit not released early')
	a.attack_age=.52;r.Soldiers.fire_actor(r,u,0)
	check(v.soldiers[0].hp==740 and v.soldiers[1].hp==800 and r.volleys.is_empty(),'At.52s ordinary60 single-target damage, no invented breath or projectile')
	r.Soldiers.fire_actor(r,u,0);check(v.soldiers[0].hp==740,'Ordinary release once')
	for fraction in [1.,.5]:
		r=fixture();u=r.units[0];v=r.units[1];a=u.soldiers[0]
		var offsets=[Vector2(100,0),Vector2(-120,0),Vector2(220,0),Vector2(220.01,0)]
		var occupied=[]
		for i in offsets.size():
			v.soldiers[i].position=a.position+offsets[i];occupied.append({'unit':v,'slot':i,'point':v.soldiers[i].position})
		r.units[2].soldiers[0].position=a.position+Vector2(30,0);occupied.append({'unit':r.units[2],'slot':0,'point':r.units[2].soldiers[0].position})
		check(r.Charges.issue(r,[Vector2i(u.id,0)],a.position+Vector2(600,0)),'Actual individual C accepted')
		check(a.charge_run.speed==300 and is_equal_approx(a.charge_run.duration,760./300.),'Dragon charge uses own speed and common max range')
		a.charge_run.velocity=Vector2(300*fraction,0)
		r.Charges.step(r,{'unit':u,'slot':0},occupied,1./60)
		for i in 3:check(is_equal_approx(v.soldiers[i].hp,800-150*fraction),'Every in-radius victim takes unattenuated speed-scaled charge, including behind and edge')
		check(v.soldiers[3].hp==800 and r.units[2].soldiers[0].hp==100,'Outside radius and friend excluded')
		check(not a.has('charge_run') and a.charge_end.reason=='hit' and a.charge_cooldown==15,'Dragon leaves charge after same-step area contacts')
		check(a.target_id==v.id and a.target_slot==2,'Last encountered victim becomes pursuit target')
		check(is_equal_approx(v.soldiers[0].impulse.length(),260*fraction),'Dragon uses ordinary knockback, no mounted x3')
		check(a.velocity.x>=300*fraction and a.velocity.x<=300,'Same-step steering still completes after contacts')
		check(not r.Charges.issue(r,[Vector2i(u.id,0)],a.position+Vector2(600,0)),'Immediate repeat C rejected during cooldown')
		check(r.events.filter(func(e):return e.get('personal_charge',false)).size()==3,'One real damage event per simultaneous victim')
	r=fixture();u=r.units[0];a=u.soldiers[0];r.Charges.issue(r,[Vector2i(u.id,0)],a.position+Vector2(600,0));r.Charges.step(r,{'unit':u,'slot':0},[],1./60)
	check(a.has('charge_run') and a.velocity.length()>0,'Empty charge keeps accelerating')
	r.Charges.cancel(r,u,a);check(not a.has('charge_run') and a.charge_cooldown==15,'Replacement command cancels dragon C with cooldown')
	var deploy=Battle.new();deploy.guard_variant='dragon';deploy.deploy_combined()
	check(deploy.alive('ally').any(func(unit):return unit.get('archetype','')=='dragon') and deploy.alive('enemy').all(func(unit):return unit.get('archetype','')==''),'Normal deployment supports dragon and leaves defaults intact')
	r=fixture();u=r.units[0];v=r.units[1];u.soldiers[0].position=Vector2(1000,1200);v.soldiers[0].position=Vector2(1030,1200)
	r.Soldiers.advance_personal(r,1./30)
	check(u.soldiers[0].position.distance_to(v.soldiers[0].position)>30.,'Live personal physics uses24 dragon radius, not guard base radius')
	var paths=r.Soldiers.movement_paths(r,[{'unit':u,'slot':0}],Vector2(1000,1500))
	check(paths.size()==1 and is_equal_approx(paths[0].batch.radius,60.),'Movement batch radius uses actual24 body radius')
	var field=preload('res://scripts/tactical/trial_field.gd')
	check(field.dragon_flame_strength(.119)==0 and field.dragon_flame_strength(.121)>0,'Visual breath starts after .12 attack age')
	check(field.dragon_flame_strength(.52)==1 and field.dragon_flame_strength(.759)>0 and field.dragon_flame_strength(.761)==0,'Visual breath covers damage release and ends .76 without new damage')
	print('Dragon: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
