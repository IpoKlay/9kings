extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture(kind='legion',enemy_kind='legion',distance=29.):
	var r=Battle.new();r.units.clear();r.spawn(kind,'ally',Vector2(1000,1200));r.spawn(enemy_kind,'enemy',Vector2(1000,1200-distance))
	for u in r.units:u.order='hold'
	r.start()
	for u in r.units:
		for i in u.soldiers.size():
			u.soldiers[i].hp=u.soldiers[i].max_hp if i==0 else 0.
			r.Charges.detach(r,u,i);u.soldiers[i].position=u.pos;u.soldiers[i].personal_order='hold'
		r.Soldiers.total(u)
	return r
func recoil(r,u,offset: Vector2):
	u.contact_motion={'start':r.elapsed-.1,'rise':.05,'hold':1.,'recover':.5,'offsets':{0:Vector3(offset.x,offset.y,0)}}
func run():
	var r=fixture();var a=r.units[0];var b=r.units[1];var foot: Vector2=b.soldiers[0].position
	recoil(r,b,Vector2(80,-60))
	check(r.Soldiers.ground_position(r,b,0)==foot and r.Soldiers.point(r,b,0).distance_to(r.projection*foot)>90.,'Visual recoil remains visible while the actual ground foot stays fixed')
	check(is_equal_approx(r.Soldiers.nearest(r,a,0,b).distance,29.),'Nearest-enemy distance ignores rendered recoil')
	var before: float=b.hp;strike(r,a,b,0,0)
	check(b.hp<before,'A target physically inside reach remains hittable while its hit drawing recoils outside')
	r=fixture('legion','legion',31.);a=r.units[0];b=r.units[1];recoil(r,b,Vector2(0,15));before=b.hp
	strike(r,a,b,0,0)
	check(b.hp==before and a.soldiers[0].cooldown==0.,'A target physically outside reach cannot be hit merely because its drawing leans closer')
	r=fixture('legion','cavalry',34.);a=r.units[0];b=r.units[1]
	check(r.Soldiers.effective_range(r,a,b)==34.,'Radius13 cavalry increases base30 attack reach by4')
	before=b.hp;strike(r,a,b,0,0)
	check(b.hp<before,'An already chosen cavalry target is attackable at34 ground units')
	a.soldiers[0].target_id=-1;a.soldiers[0].target_slot=-1;a.soldiers[0].cooldown=0.
	check(r.Soldiers.personal_target(r,a,0,a.soldiers[0]).is_empty(),'H still searches only base30 reach rather than automatically acquiring at34')
	r=fixture('legion','siege',41.);a=r.units[0];b=r.units[1]
	check(r.Soldiers.effective_range(r,a,b)==41.,'Radius20 catapult increases base30 attack reach by11')
	r=fixture('archer','cavalry',454.);a=r.units[0];b=r.units[1]
	a.soldiers[0].personal_order='idle'
	check(r.Soldiers.personal_target(r,a,0,a.soldiers[0]).is_empty(),'Player ranged acquisition stays at450 despite the454 effective reach against cavalry')
	r.Soldiers.command(r,[Vector2i(a.id,0)],'attack',b.pos,b.id,0);strike(r,a,b,0,0)
	check(r.volleys.size()==1,'Explicitly focused cavalry can be shot at454')
	r=fixture('archer','legion',300.);a=r.units[0];b=r.units[1]
	strike(r,a,b,0,0)
	var unshifted_origin: Vector2=r.volleys[0].origin
	r=fixture('archer','legion',300.);a=r.units[0];b=r.units[1]
	recoil(r,a,Vector2(-70,45));recoil(r,b,Vector2(90,-45));strike(r,a,b,0,0)
	var arrow=r.volleys[0]
	check(arrow.from==a.soldiers[0].position and arrow.pos==b.soldiers[0].position,'Shooter identity and target aim use ground feet despite opposite visual offsets')
	check(arrow.origin.is_equal_approx(unshifted_origin) and arrow.point==arrow.origin and is_equal_approx(arrow.flight,unshifted_origin.distance_to(arrow.pos)/400.),'Authored weapon origin and initial flight estimate ignore rendered recoil')
	b.soldiers[0].position.x+=25.;r.advance_volleys(.3)
	check(arrow.pos==b.soldiers[0].position,'Homing follows real target movement without following the hit animation')
	r=fixture('legion','legion',20.);a=r.units[0];b=r.units[1]
	b.soldiers[0].shield_wall=true;b.soldiers[0].heading=Vector2.DOWN;b.soldiers[0].wall_heading=Vector2.DOWN
	recoil(r,b,Vector2(150,0));before=b.hp;strike(r,a,b,0,0)
	check(is_equal_approx(before-b.hp,10.),'Frontal shield reduction uses physical incoming direction even with a large sideways visual lean')
	r=fixture('siege','legion',400.);a=r.units[0];b=r.units[1]
	var impact: Vector2=b.soldiers[0].position+Vector2(79,0);recoil(r,b,Vector2(-180,0));before=b.hp
	r.stones.append({'side':'ally','from':a.pos,'pos':impact,'damage':20.,'age':0.,'flight':.1});r.advance_stones(.1)
	check(b.hp<before,'Stone splash includes a real foot at79 even when the sprite recoils beyond radius80')
	impact=b.soldiers[0].position+Vector2(81,0);recoil(r,b,Vector2(80,0));before=b.hp
	r.stones.append({'side':'ally','from':a.pos,'pos':impact,'damage':20.,'age':0.,'flight':.1});r.advance_stones(.1)
	check(b.hp==before,'Stone splash excludes a real foot at81 even when the drawing appears inside')
	r=fixture('cavalry','legion',400.);a=r.units[0];b=r.units[1];foot=a.soldiers[0].position;recoil(r,a,Vector2(90,-30))
	r.Charges.issue(r,[Vector2i(a.id,0)],foot+Vector2(0,-300))
	check(a.soldiers[0].position==foot and a.soldiers[0].charge_run.goal==foot+Vector2(0,-300),'Starting C during visual recoil neither teleports the horse nor shifts its intended destination')
	var snap=a.soldiers[0].position;r.Soldiers.command(r,[Vector2i(a.id,0)],'move',foot+Vector2(200,0))
	check(a.soldiers[0].position==snap,'Replacing an order preserves the physical foot independently of the drawn hit pose')
	r=fixture('cavalry','cavalry',39.);a=r.units[0];b=r.units[1];before=b.hp
	r.Charges.issue(r,[Vector2i(a.id,0)],a.pos+Vector2(0,-300))
	var own={'unit':a,'slot':0,'radius':13.,'point':a.soldiers[0].position}
	var other={'unit':b,'slot':0,'radius':13.,'point':b.soldiers[0].position}
	r.Charges.step(r,own,[own,other],1./60)
	check(b.hp==before and a.soldiers[0].charge_run.hits.is_empty(),'C sweep keeps base37 contact radius and does not inherit the41 normal-attack reach')
	print('Ground combat: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)

func strike(r,a,b,only_slot=-1,target_slot=-1):
	r.Soldiers.attack(r,a,b,only_slot,target_slot)
	for actor in a.soldiers:actor.attack_age+=.61
	r.Soldiers.fire_attacks(r)
