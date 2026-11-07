extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture():
	var r=Battle.new();r.units.clear();r.spawn('legion','ally',Vector2(900,1000),'wraith');r.spawn('legion','enemy',Vector2(900,500));r.start()
	for u in r.units:
		for i in u.soldiers.size():r.Charges.detach(r,u,i);u.soldiers[i].personal_order='hold'
	return r
func run():
	var r=fixture();var u=r.units[0];var a=u.soldiers[0];var ids=[Vector2i(u.id,0)]
	check(u.hp==1500 and a.max_hp==150 and u.combat_stats.damage==55 and u.combat_stats.interval==.8,'Wraith independent combat stats')
	check(not r.Soldiers.individual(r,u).can_charge and not r.Soldiers.individual(r,u).can_shield_wall,'Wraith has neither C nor F')
	check(r.Blink.ready(r,ids).size()==1,'Blink starts ready')
	var start: Vector2=a.position;a.velocity=Vector2(20,0);a.personal_order='attack';a.target_id=r.units[1].id;a.target_slot=0;a.focus_id=a.target_id;a.focus_slot=0;a.path=[Vector2(600,600)];a.resume_attack_move=true
	check(not r.Blink.issue(r,ids,start+Vector2(300.01,0)),'Aim beyond 250 times 1.2 rejected')
	check(a.position==start and a.personal_order=='attack' and not a.has('blink_cooldown'),'Rejected blink preserves position, old order and cooldown')
	check(r.Blink.issue(r,ids,start+Vector2(300,0)),'Aim gate is inclusive at 300')
	check(a.position==start+Vector2(200,0) and a.heading==Vector2.RIGHT,'Each caster caps displacement at 200 and faces requested target')
	check(a.personal_order=='idle' and a.target_id==-1 and a.focus_id==-1 and a.path.is_empty() and not a.has('resume_attack_move'),'Blink clears old pursuit and route')
	check(a.velocity==Vector2(20,0) and a.blink_cooldown==8.,'Reference blink preserves velocity and starts 8 second cooldown')
	check(not r.Blink.issue(r,ids,a.position+Vector2(20,0)),'Repeat cannot bypass cooldown')
	var value=a.duplicate(true);r.step(0);check(a==value,'Pause freezes cooldown and position')
	r.Soldiers.advance(u,4.);check(a.blink_cooldown==4.,'Cooldown follows simulation time')
	r.Soldiers.advance(u,4.);check(r.Blink.ready(r,ids).size()==1,'Ready again at eight seconds')
	check(r.Blink.issue(r,ids,a.position),'Zero-distance blink is valid and spends cooldown')
	check(a.heading==Vector2.RIGHT,'Zero offset uses angle zero facing')
	var q=fixture();var w=q.units[0];var x=w.soldiers[0];var y=w.soldiers[1]
	x.position=Vector2(800,900);y.position=Vector2(1000,900);y.blink_cooldown=2.
	var mixed=[Vector2i(w.id,0),Vector2i(w.id,1),Vector2i(q.units[1].id,0)]
	check(q.Blink.issue(q,mixed,Vector2(1100,900)),'Only ready friendly capable casters determine centroid')
	check(x.position==Vector2(1000,900) and y.position==Vector2(1000,900) and y.blink_cooldown==2.,'Cooling caster stays untouched')
	x.blink_cooldown=0;y.blink_cooldown=0;x.position=Vector2(800,900);y.position=Vector2(1000,900)
	check(q.Blink.issue(q,[Vector2i(w.id,0),Vector2i(w.id,1)],Vector2(900,1100)),'Two casters share one destination')
	check(is_equal_approx(x.position.distance_to(Vector2(800,900)),200.) and is_equal_approx(y.position.distance_to(Vector2(1000,900)),200.) and x.position!=y.position,'Distant individual origins produce separate clamped landing points')
	x.hp=0;check(q.Blink.ready(q,[Vector2i(w.id,0)]).is_empty(),'Dead caster excluded')
	var terrain=fixture();var caster=terrain.units[0];var actor=caster.soldiers[0];actor.position=Vector2(900,900)
	terrain.terrain.ROCKS=[Rect2(940,850,30,100)]
	check(terrain.Blink.issue(terrain,[Vector2i(caster.id,0)],Vector2(1050,900)) and actor.position==Vector2(1050,900),'Blink itself skips obstacle path checks, as reference')
	var key=terrain.Soldiers.navigator(terrain,caster.kind,caster)
	var ordinary=terrain.Soldiers.navigator(terrain,caster.kind)
	check(key!=ordinary and terrain.terrain.extents[key].x>terrain.terrain.extents[ordinary].x,'Ordinary navigation uses actual wraith body radius, not base infantry radius')
	var gait=fixture();var ghost=gait.units[0];gait.Contact.track_slots(gait,ghost,0.)
	var distances=ghost.slot_distances.duplicate();var march: float=ghost.march_distance
	var all_ids=gait.Soldiers.group_members([ghost]);var origin=gait.Blink.center(gait,gait.Blink.ready(gait,all_ids))
	gait.Blink.issue(gait,all_ids,origin+Vector2(0,-180));gait.Contact.track_slots(gait,ghost,1./60)
	check(ghost.slot_distances==distances and ghost.march_distance==march,'Teleport distance does not advance walking stride')
	check(ghost.order=='idle' and ghost.pos.is_equal_approx(gait.Blink.center(gait,gait.Soldiers.members(gait,all_ids))),'Whole-regiment blink immediately updates center and idle order label')
	var mixed_allies=fixture();mixed_allies.spawn('legion','ally',Vector2(700,1100))
	var specter=mixed_allies.units[0];var foot=mixed_allies.units[2]
	var ghost_start=mixed_allies.Soldiers.ground_position(mixed_allies,specter,0)
	var foot_start=mixed_allies.Soldiers.ground_position(mixed_allies,foot,0)
	var selection=[Vector2i(specter.id,0),Vector2i(foot.id,0)]
	check(mixed_allies.Blink.issue(mixed_allies,selection,ghost_start+Vector2(0,270)),'Original sandbox comparison: keyboard B accepts mixed friendly selection')
	check(mixed_allies.Soldiers.ground_position(mixed_allies,specter,0).is_equal_approx(ghost_start+Vector2(0,200)),'Original sandbox comparison: 270 target distance truncates to 200')
	check(mixed_allies.Soldiers.ground_position(mixed_allies,foot,0)==foot_start and foot.soldiers[0].get('blink_cooldown',0.)==0.,'Original sandbox comparison: incapable friendly foot remains unmoved and spends no cooldown')
	cleave_checks()
	print('Wraith rules: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
func cleave_checks():
	var r=fixture();var u=r.units[0];var a=u.soldiers[0];var enemy=r.units[1]
	a.position=Vector2(900,900);a.heading=Vector2.RIGHT
	var offsets=[Vector2(30,0),Vector2(40,0),Vector2(30,29),Vector2(30,31),Vector2(-20,0),Vector2(51,0),Vector2(50,0)]
	for i in enemy.soldiers.size():enemy.soldiers[i].position=a.position+(offsets[i] if i<offsets.size() else Vector2(500,i*30));enemy.soldiers[i].heading=Vector2.LEFT
	a.target_id=enemy.id;a.target_slot=0;a.attack_age=.479;a.attack_pending=true
	r.Soldiers.fire_actor(r,u,0);check(enemy.hp==1000,'Scythe does not hit before .8 times .6')
	a.attack_age=.48;r.Soldiers.fire_actor(r,u,0)
	check(enemy.soldiers[0].hp==45,'Main target receives full 55 exactly once')
	check(enemy.soldiers[1].hp==67 and enemy.soldiers[2].hp==67 and enemy.soldiers[6].hp==67,'Splash receives 60 percent within local inclusive radius and just inside 45 degrees')
	check(enemy.soldiers[3].hp==100 and enemy.soldiers[4].hp==100 and enemy.soldiers[5].hp==100,'Outside arc, rear and outside radius untouched')
	check(u.hp==1500,'Allied casters are not cleaved')
	var hp=enemy.hp;r.Soldiers.fire_actor(r,u,0);check(enemy.hp==hp,'Same swing cannot fire twice')
	for i in [0,1]:enemy.soldiers[i].hp=100;enemy.soldiers[i].shield_wall=true;enemy.soldiers[i].wall_heading=Vector2.LEFT
	r.Soldiers.total(enemy);a.attack_pending=true;r.Soldiers.fire_actor(r,u,0)
	check(is_equal_approx(enemy.soldiers[0].hp,78.) and is_equal_approx(enemy.soldiers[1].hp,86.8),'Both primary and splash use actual frontal F reduction')
	check(enemy.soldiers[2].get('last_attacker',Vector2i(-1,-1))==Vector2i(u.id,0),'Splash forwards attacker identity for retaliation')
	a.attack_pending=true;a.target_slot=5;enemy.soldiers[5].hp=0;var before=enemy.hp;r.Soldiers.fire_actor(r,u,0)
	check(enemy.hp<before,'Registered zero-HP primary target still allows the due cleave against neighbours')
	a.attack_pending=true;a.target_slot=5;enemy.soldiers[5].hp=0;enemy.soldiers[5].death_state=1;var saved=enemy.hp;r.Soldiers.fire_actor(r,u,0);check(enemy.hp==saved,'Unregistered primary target prevents whole cleave')
