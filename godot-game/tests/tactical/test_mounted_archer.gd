extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture(kind='cavalry',variant='mounted_archer'):
	var r=Battle.new();r.units.clear()
	r.spawn(kind,'ally',Vector2(600,1200),variant)
	r.spawn('legion','enemy',Vector2(850,900))
	for u in r.units:
		u.order='hold'
		for i in u.soldiers.size():
			r.Charges.detach(r,u,i);u.soldiers[i].cooldown=999.
			if i>0:u.soldiers[i].hp=0.
		r.Soldiers.total(u);u.soldiers[0].position=u.pos
	r.units[0].soldiers[0].cooldown=0.;r.start();return r
func tick(r,n: int):
	for i in n:r.step(1./60)
func run():
	var r=fixture();var a=r.units[0];var b=r.units[1];var actor=a.soldiers[0];var ids=[Vector2i(a.id,0)]
	check(actor.max_hp==100. and a.combat_stats.damage==18. and a.combat_stats.speed==182.,'Horse archers use independent mounted-ranged stats')
	check(r.Soldiers.ranged(a) and r.Soldiers.mounted_ranged(a),'Mounted and ranged roles coexist')
	check(not r.Charges.issue(r,ids,Vector2(1200,1200)),'Horse archers cannot use melee charge')
	check(not r.Volley.issue(r,ids,b.pos),'Horse archers do not inherit longbow volley')
	check(r.Walls.layout(r,ids,Vector2(600,1200),Vector2(800,1200)).is_empty(),'Horse archers cannot form a shield wall')
	check(r.Soldiers.command(r,ids,'move',Vector2(1400,1200)),'Ordinary movement accepts horse archer')
	tick(r,35);var before: Vector2=actor.position
	tick(r,3)
	check(actor.position.x-before.x>8. and actor.velocity.x>180.,'Horse retains full forward movement through arrow release')
	check(not r.volleys.is_empty() and r.volleys[0].kind=='arrow','Moving horse releases actual ranged projectile')
	if not r.volleys.is_empty():
		check(r.volleys[0].from.x>690. and r.volleys[0].damage==18.,'Arrow originates at current release position, not order origin')
		check(is_equal_approx(r.volleys[0].flight,r.volleys[0].origin.distance_to(r.volleys[0].pos)/400.),'Horse arrow uses distance over 400 flight time')
	check(actor.personal_order=='move' and not actor.has('attack_engaged'),'Firing does not convert a move into stationary engagement')
	tick(r,65);check(b.hp<b.soldiers[0].max_hp,'Arrow deals real individual damage while horse continues its route')
	var foot=fixture('archer','');foot.Soldiers.command(foot,[Vector2i(foot.units[0].id,0)],'move',Vector2(1400,1200));tick(foot,100)
	check(foot.volleys.is_empty() and foot.units[1].hp==foot.units[1].soldiers[0].max_hp,'Ordinary moving foot archers do not shoot')
	var attack_move=fixture();var ma=attack_move.units[0];attack_move.Soldiers.command(attack_move,[Vector2i(ma.id,0)],'attack_move',Vector2(1400,1200));tick(attack_move,100)
	check(ma.soldiers[0].position.x>880. and ma.soldiers[0].personal_order=='attack_move' and attack_move.units[1].hp<attack_move.units[1].soldiers[0].max_hp,'Attack-move horse keeps route while dealing ranged damage')
	var stop=fixture('archer','');var sa=stop.units[0];stop.Soldiers.command(stop,[Vector2i(sa.id,0)],'attack_move',Vector2(1400,1200));tick(stop,100)
	check(sa.soldiers[0].position.x<750. and sa.soldiers[0].velocity.length()<5.,'Foot attack-move stops to shoot at the same target')
	var hold=fixture();var ha=hold.units[0];tick(hold,100)
	check(ha.soldiers[0].position==Vector2(600,1200) and hold.units[1].hp<hold.units[1].soldiers[0].max_hp,'H keeps horse stationary while its bow attacks')
	var pursue=fixture();var pa=pursue.units[0];pursue.Soldiers.command(pursue,[Vector2i(pa.id,0)],'attack',Vector2.ZERO,pursue.units[1].id,0);tick(pursue,60)
	check(pa.soldiers[0].position.distance_to(Vector2(600,1200))>165. and pa.soldiers[0].velocity.length()>180.,'Explicit pursuit does not stop merely on entering ranged distance')
	check(not pa.soldiers[0].has('attack_engaged'),'Pursuing mounted archer remains mobile')
	var idle=fixture();var ia=idle.units[0];var isoldier=ia.soldiers[0];isoldier.personal_order='idle';isoldier.cooldown=.4;isoldier.attack_age=.3;isoldier.aggro_timer=.1;idle.simulation_step=int(isoldier.scan_slot)%6
	idle.Soldiers.step_personal(idle,{'unit':ia,'slot':0},[],{},.01)
	check(isoldier.cooldown==1. and isoldier.attack_age==0. and isoldier.personal_order=='idle','Public idle acquisition restarts mounted shot without changing idle state, even during cooldown')
	var search=fixture();var sh=search.units[0];var si=sh.soldiers[0]
	search.spawn('archer','enemy',Vector2(700,1200));var close=search.units.back();for j in close.soldiers.size():search.Charges.detach(search,close,j);close.soldiers[j].position=Vector2(700+j*30,1200)
	si.target_id=search.units[1].id;si.target_slot=0
	search.Soldiers.mounted_fire(search,sh,0,si,{})
	check(si.target_id==search.units[1].id,'An existing living target inside base range is retained over a closer enemy')
	si.cooldown=0.;search.units[1].soldiers[0].position=Vector2(600,500)
	search.Soldiers.mounted_fire(search,sh,0,si,{})
	check(si.target_id==close.id and si.target_slot==0,'Out-of-range target is replaced by nearest enemy inside base range')
	var idle_range=fixture();var ir=idle_range.units[0];var iactor=ir.soldiers[0];var outside=idle_range.units[1]
	outside.soldiers[0].position=Vector2(600,700);outside.soldiers[0].hp=1.;idle_range.Soldiers.total(outside)
	idle_range.spawn('legion','enemy',Vector2(600,750));var inside=idle_range.units.back()
	for j in inside.soldiers.size():idle_range.Charges.detach(idle_range,inside,j);inside.soldiers[j].position=Vector2(600,750);inside.soldiers[j].hp=inside.soldiers[j].max_hp if j==0 else 0.
	idle_range.Soldiers.total(inside);iactor.personal_order='idle'
	check(idle_range.Soldiers.personal_target(idle_range,ir,0,iactor,{},true,true).unit.id==inside.id,'Player mounted idle acquisition uses weapon range470, not configured enemy aggro850')
	var dead=fixture();var da=dead.units[0];dead.Soldiers.command(dead,[Vector2i(da.id,0)],'attack',Vector2.ZERO,dead.units[1].id,0);tick(dead,5)
	dead.units[1].soldiers[0].hp=0.;dead.Soldiers.total(dead.units[1]);dead.Soldiers.step_personal(dead,{'unit':da,'slot':0},[],{},1./60)
	check(da.soldiers[0].personal_order=='idle' and da.soldiers[0].target_id==-1,'Dead pursued target clears pursuit without remote melee damage')
	var director=Battle.new();director.units.clear();director.spawn('cavalry','enemy',Vector2(1000,400),'mounted_archer');director.spawn('legion','ally',Vector2(1000,1500));director.start();tick(director,31)
	check(director.enemy_director.cohorts[0].role==4 and director.enemy_director.cohorts[0].task=='support','Enemy mounted archers enter ranged support task, not melee flank charge')
	var deploy=Battle.new();deploy.cavalry_variant='mounted_archer';deploy.deploy_combined();var horse=deploy.alive('ally').filter(func(u):return u.kind=='cavalry')[0]
	check(horse.soldiers.size()==8 and horse.hp==800. and horse.art=='mounted_archer','Normal combined deployment creates eight horse archers with dedicated art')
	check(deploy.alive('enemy').filter(func(u):return u.kind=='cavalry')[0].get('archetype','')=='','Player loadout preserves normal enemy cavalry')
	var spear=fixture();var horse_target=spear.units[0]
	spear.spawn('spear','enemy',Vector2(600,1230));var lance=spear.units.back();spear.Charges.detach(spear,lance,0);lance.soldiers[0].position=Vector2(600,1230)
	var attacker=lance.soldiers[0];attacker.target_id=horse_target.id;attacker.target_slot=0;attacker.attack_age=.6;attacker.attack_pending=true
	var hp: float=horse_target.hp;spear.Soldiers.fire_actor(spear,lance,0)
	check(is_equal_approx(horse_target.hp,hp-spear.config.types.spear.damage),'Ordinary spear hit uses base damage against horse archers; anti-cavalry role affects targeting, not a hidden multiplier')
	var terrain=fixture();var rider=terrain.units[0];var stone=Rect2(terrain.projection*Vector2(900,1130),Vector2(50,100))
	terrain.terrain.ROCKS.append(stone);terrain.Soldiers.command(terrain,[Vector2i(rider.id,0)],'move',Vector2(1400,1200))
	var clipped=false
	for frame in 300:
		terrain.step(1./60)
		if stone.has_point(terrain.projection*rider.soldiers[0].position):clipped=true
	check(not clipped and rider.soldiers[0].position.x>950.,'Moving and firing horse uses the same authored obstacle clearance and detour')
	print('Mounted archer: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
