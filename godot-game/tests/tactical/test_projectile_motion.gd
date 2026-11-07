extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok:bool,note:String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture(kind='archer'):
	var r=Battle.new();r.units.clear();r.spawn(kind,'ally',Vector2(1000,1000));r.spawn('legion','enemy',Vector2(1400,1000))
	for u in r.units:
		u.order='hold'
		for i in u.soldiers.size():r.Charges.detach(r,u,i);u.soldiers[i].position=u.pos+Vector2(0,i*150);u.soldiers[i].cooldown=999.
	r.start();r.enemy_director.active=false;return r
func shoot(r):
	var a=r.units[0];var b=r.units[1];var p=r.deal_blow(a,b,20.,{}, {'attacker_slot':0,'target_slot':0,'release_delay':0.})
	# Zero muzzle offset isolates kinematics from our independently authored art.
	p.origin=a.soldiers[0].position;p.point=p.origin;p.flight=p.origin.distance_to(b.soldiers[0].position)/p.speed
	return p
func run():
	var r=fixture();var p=shoot(r);var b=r.units[1];var hp=b.hp
	r.advance_volleys(.25);check(p.point.is_equal_approx(Vector2(1100,1000)),'400 speed travels100 in.25 seconds')
	b.soldiers[0].position=Vector2(1500,1000)
	r.advance_volleys(.75);check(p.point.is_equal_approx(Vector2(1400,1000)) and b.hp==hp and r.volleys.size()==1,'Retreating target postpones hit beyond initial one-second estimate')
	r.advance_volleys(.25);check(p.point==Vector2(1500,1000) and b.hp==hp-20 and r.volleys.is_empty(),'Remaining distance determines actual impact')
	r.advance_volleys(2.);check(b.hp==hp-20,'One projectile damages exactly once')
	r=fixture();p=shoot(r);b=r.units[1];r.advance_volleys(.25);var before:Vector2=p.point;b.soldiers[0].position=Vector2(1100,1400)
	r.advance_volleys(.25);check(p.point.is_equal_approx(before+Vector2(0,100)) and p.direction==Vector2.DOWN,'Turn follows current target from previous projectile point, with constant speed')
	b.soldiers[0].position=p.point+Vector2(10,0);r.advance_volleys(.025);check(b.hp==b.max_hp-20 and r.volleys.is_empty(),'Approaching target arrives earlier and exact step-distance is inclusive')
	r=fixture();p=shoot(r);b=r.units[1];r.hurt(b,1000.,'',0.,0);hp=b.hp;r.advance_volleys(.001)
	check(r.volleys.is_empty() and b.hp==hp,'Dead individual target deletes projectile immediately, despite living regiment')
	check(not r.events.any(func(e):return e.kind=='arrow_impact'),'Cancelled shot has no hit effect')
	r=fixture();p=shoot(r);r.units.remove_at(1);r.advance_volleys(.001);check(r.volleys.is_empty(),'Missing target deletes projectile')
	r=fixture();p=shoot(r);p.target_slot=100;r.advance_volleys(.001);check(r.volleys.is_empty(),'Invalid slot cannot hit another soldier')
	r=fixture();p=shoot(r);var snapshot=r.volleys.duplicate(true);r.advance_volleys(0.);check(r.volleys==snapshot,'Pause preserves position and timing')
	r=fixture();p=shoot(r);p.release_delay=.23;r.advance_volleys(.20);check(p.point==p.origin,'Legacy delayed shot stays at launch point until release')
	r.advance_volleys(.05);check(p.point.is_equal_approx(p.origin+Vector2(8,0)),'Only post-release fraction of crossing step moves the projectile')
	shield_checks();stone_checks();anchor_checks()
	print('Projectile motion: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
func shield_checks():
	for mode in ['front','moved_behind','destroyed','removed','coincident','sixty_degrees']:
		var r=fixture();var p=shoot(r);var a=r.units[0];var b=r.units[1];var victim=b.soldiers[0];victim.shield_wall=true;victim.wall_heading=Vector2.LEFT
		match mode:
			'moved_behind':a.soldiers[0].position=Vector2(1500,1000)
			'destroyed':r.hurt(a,1000.,'',0.,0);a.soldiers[0].death_state=2
			'removed':r.units.erase(a)
			'coincident':a.soldiers[0].position=victim.position
			'sixty_degrees':a.soldiers[0].position=victim.position+Vector2.LEFT.rotated(PI/3)*100
		r.advance_volleys(2.)
		var blocked=mode in ['front','sixty_degrees'];check(is_equal_approx(victim.hp,96. if blocked else 80.),'Impact shield uses current live source and .34 threshold: '+mode)
		check(r.events.any(func(e):return e.kind=='arrow_impact' and e.blocked==blocked),'Correct impact/block feedback: '+mode)
		if mode in ['destroyed','removed']:check(not victim.has('last_attacker'),'Destroyed source leaves no ghost retaliation identity')
	var r=fixture();var p=shoot(r);var b=r.units[1];b.soldiers[0].hp=10;r.Soldiers.total(b);shoot(r);r.advance_volleys(2.)
	check(b.soldiers[0].hp==0 and b.soldiers[1].hp==100 and r.events.filter(func(e):return e.kind=='arrow_impact').size()==1,'First shot kills target, later shot disappears without spillover')
func stone_checks():
	for distance in [150.,400.,2000.]:
		var r=fixture('siege');var a=r.units[0];var b=r.units[1];b.soldiers[0].position=a.soldiers[0].position+Vector2(distance,0)
		var actor=a.soldiers[0];actor.target_id=b.id;actor.target_slot=0;actor.attack_pending=true;actor.attack_age=.56;r.Soldiers.fire_actor(r,a,0)
		check(r.stones.size()==1,'Stone accepts release at or beyond150: '+str(distance))
		var stone=r.stones[0];var d:float=stone.from.distance_to(stone.pos)
		check(is_equal_approx(stone.flight,clampf(d/350.,.8,2.5)) and is_equal_approx(stone.peak,clampf(d*.25,80.,250.)),'Stone clamps actual muzzle-to-fixed-point flight and peak')
		var landing:Vector2=stone.pos;b.soldiers[0].position+=Vector2(500,0);r.advance_stones(.1);check(stone.pos==landing,'Stone keeps ground target after enemy moves')
	var r=fixture('siege');var a=r.units[0];var b=r.units[1];b.soldiers[0].position=a.soldiers[0].position+Vector2(149.99,0)
	a.soldiers[0].target_id=b.id;a.soldiers[0].target_slot=0;a.soldiers[0].attack_pending=true;a.soldiers[0].attack_age=.56;r.Soldiers.fire_actor(r,a,0)
	check(r.stones.is_empty(),'Target entering minimum range during windup cancels stone at release')
	r=fixture('siege');a=r.units[0];b=r.units[1];a.soldiers[1].position=b.soldiers[0].position+Vector2(30,0)
	r.stones.append({'side':'ally','attacker':a.id,'attacker_slot':0,'from':a.soldiers[0].position,'pos':b.soldiers[0].position,'damage':20.,'age':0.,'flight':.8})
	r.hurt(a,10000.,'',0.,0);a.soldiers[0].death_state=2;r.advance_stones(.8)
	check(b.soldiers[0].hp==80 and a.soldiers[1].hp==a.soldiers[1].max_hp-20,'Source destroyed: fixed-area stone follows original all-team fallback')
func anchor_checks():
	var r=fixture();var a=r.units[0];var actor=a.soldiers[0];actor.attack_age=.6
	var origins=[]
	for direction in 8:
		actor.heading=Vector2.DOWN.rotated(-direction*PI/4);var point=r.Projectiles.origin(r,a,0)
		check(point.is_finite() and point!=actor.position,'Authored weapon origin exists for bearing '+str(direction));origins.append(point)
	check(origins[0]!=origins[4],'Opposing directions use different weapon anchors')
	var shot=r.deal_blow(a,r.units[1],20.,{}, {'attacker_slot':0,'target_slot':0,'release_delay':0.})
	check(shot.point==r.Projectiles.origin(r,a,0) and shot.origin==shot.point,'Visible launch and simulation share authored weapon point')
	check(is_equal_approx(shot.flight,shot.origin.distance_to(shot.pos)/shot.speed),'Initial estimate uses actual weapon-to-target distance')
