extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
const Director=preload('res://scripts/tactical/enemy_director.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture(personality=.5):
	var r=Battle.new();r.units.clear();r.config.enemy_director={'personality':personality}
	r.spawn('legion','ally',Vector2(1000,1500));r.spawn('archer','ally',Vector2(1000,1800))
	r.spawn('legion','enemy',Vector2(850,700));r.spawn('spear','enemy',Vector2(1150,700))
	r.spawn('archer','enemy',Vector2(1000,450));r.spawn('cavalry','enemy',Vector2(500,500));r.spawn('guard','enemy',Vector2(1500,500))
	for u in r.units:
		if u.side=='ally':u.order='hold'
	r.start();return r
func review(r,dt=.5):
	r.elapsed+=dt;r.enemy_director.advance(r,dt)
func group(r,task):
	return r.enemy_director.cohorts.filter(func(g):return g.task==task)[0]
func run():
	check(Director.primary(210)==16 and Director.primary(131)==2 and Director.primary(137)==1,'Role precedence sends light cavalry to flank, veteran sword to shock, spear to front')
	check(Director.primary(84)==4,'Mounted ranged role takes priority over mobility')
	var r=fixture();var d=r.enemy_director
	check(d.active and d.orders.is_empty() and r.units[2].soldiers.all(func(s):return s.personal_order=='idle'),'Official battle activates director while units wait for first evaluation')
	review(r,.49);check(d.orders.is_empty(),'No strategic orders before0.5seconds')
	review(r,.01)
	check(d.cohorts.size()==4 and group(r,'front').members.size()==20,'Same-role sword and spear soldiers form one shared cohort')
	check(d.orders.size()==4 and is_equal_approx(d.orders[0].time,.5),'First strategic order is issued at0.5seconds')
	check(r.units[5].soldiers.all(func(s):return s.personal_order=='attack_move' and not s.has('charge_run')),'Mobile light cavalry receive a flank route instead of an automatic charge')
	var flank=d.orders.filter(func(o):return o.task=='flank')[0]
	var player=Director.center(d.people(r,'ally'));var front=Director.center(d.people(r,'enemy').filter(func(row):return row.unit.kind in ['legion','spear']))
	check(is_equal_approx(flank.goal.distance_to(player),500.) and absf((flank.goal-player).dot(player-front))<.1,'Flank destination is500units perpendicular to forward direction')
	var support=d.orders.filter(func(o):return o.task=='support')[0]
	check(support.goal.is_equal_approx(front+player.direction_to(front)*180.),'Ranged support destination stays180behind the frontline centroid')
	var front_goal=d.orders.filter(func(o):return o.task=='front')[0].goal
	check(r.units[2].soldiers.all(func(s):return s.path.back().distance_to(front_goal)<=120.01),'Frontline orders cap existing individual offsets at120')
	var count=d.orders.size();review(r,1.5)
	check(d.orders.size()==count,'Task evaluation at2seconds does not bypass3second order cooldown')
	review(r,1.5);check(d.orders.size()==count*2 and is_equal_approx(d.orders[-1].time,3.5),'Next strategic commands occur at3.5seconds')
	var frozen=d.until_review;r.step(0.);check(d.until_review==frozen,'Pause freezes strategic evaluation')
	var id=Vector2i(r.units[2].id,0)
	check(not r.Soldiers.command(r,[id],'move',Vector2(1100,800)),'Player command path still cannot control enemy soldiers')
	var wounded=r.units[2]
	for i in 9:r.hurt(wounded,10000.,'test',0.,i)
	check(wounded.hp>0 and not wounded.routing and r.alive('enemy').has(wounded),'Standalone survivors remain combatants instead of inheriting aggregate regiment morale rout')
	r=fixture(0.)
	for i in 3:r.spawn('legion','ally',Vector2(700+i*300,1800));r.units.back().order='hold'
	review(r);d=r.enemy_director
	check(group(r,'wall').members.size()==20 and r.units[2].soldiers.all(func(s):return s.shield_wall and s.has('wall_slot')),'Cautious shield-capable front forms real individual holding slots')
	var slots=[]
	for u in [r.units[2],r.units[3]]:
		for s in u.soldiers:slots.append(s.wall_slot)
	var nearest=INF
	for i in slots.size():
		for j in range(i+1,slots.size()):nearest=minf(nearest,slots[i].distance_to(slots[j]))
	check(is_equal_approx(nearest,28.),'AI wall uses28unit spacing instead of player drag width')
	var wall_center=Director.center(d.people(r,'enemy').filter(func(row):return row.unit.kind in ['legion','spear']))
	r.units[2].soldiers[0].hit_age=0.;r.units[2].soldiers[0].attack_engaged=Vector2i(r.units[0].id,0);review(r,3.)
	var wall_order=d.orders.filter(func(o):return o.task=='wall')[-1]
	# One call is one director review; the order remains on cooldown until the next review.
	review(r,1.5);wall_order=d.orders.filter(func(o):return o.task=='wall')[-1]
	check(is_equal_approx(wall_order.goal.distance_to(wall_center),60.),'Shield hold attack is not pursuit-attack state and does not suppress60unit under-fire advance')
	r=fixture();review(r);d=r.enemy_director
	var support_group=group(r,'support');var live={}
	for row in d.people(r,'enemy'):live[row.id]=row
	var support_rows=Director.rows_for(support_group,live);var support_center=Director.center(support_rows)
	var chosen_front=support_center+Vector2(0,180)
	d.issue(r,support_group,0,support_rows,d.people(r,'ally'),chosen_front,Vector2(1000,1500))
	check(r.units[4].soldiers.all(func(s):return s.personal_order=='attack' and s.focus_id==r.units[1].id),'Settled ranged support focuses an exposed ranged individual over healthier nearby melee')
	r=fixture();r.spawn('cavalry','ally',Vector2(1000,500));review(r)
	check(group(r,'intercept').members.size()==20 and group(r,'intercept').target.x==r.units.back().id,'Nearby mounted threat redirects eligible mixed frontline cohort to intercept')
	var intercepted=group(r,'intercept');var target_slot: int=intercepted.target.y
	r.hurt(r.units.back(),10000.,'test',0.,target_slot);review(r,3.);review(r,1.5)
	check(intercepted.task=='front' and intercepted.target==Vector2i(-1,-1),'Dead interception target returns that cohort to frontline task')
	r=fixture();review(r);d=r.enemy_director
	for u in r.alive('enemy'):
		for i in u.soldiers.size():
			if u.kind!='cavalry' or i>0:r.hurt(u,10000.,'test',0.,i)
		u.routing=false
	review(r,1.5)
	check(d.cohorts.all(func(g):return g.task=='retreat'),'Below30percent remaining combatants all surviving cohorts retreat')
	review(r,1.5)
	check(r.units[5].soldiers[0].personal_order=='move' and r.units[5].soldiers[0].path.back().is_equal_approx(r.enemy_zone.get_center()),'Retreat is an ordinary movement command toward original deployment zone')
	check(d.losses==d.initial_enemy-1 and d.aggression<d.personality,'Individual casualty count feeds aggression and is not based on regiment count')
	var casualties=d.losses;review(r,1.5);check(d.losses==casualties,'One dead soldier is counted once across director evaluations')
	r=fixture();review(r);d=r.enemy_director;var groups=d.cohorts.size()
	r.spawn('archer','enemy',Vector2(1200,400));review(r,1.5)
	check(d.cohorts.size()==groups+1 and r.units.back().soldiers.all(func(s):return s.director_owned),'New reinforcements create their own role cohort')
	var pass_rules=load('res://scripts/tactical/pass_battle.gd').new();pass_rules.deploy_defenders();pass_rules.start()
	check(not pass_rules.enemy_director.active,'Authored expedition pass retains objective/lane control as an explicit project extension')
	print('Enemy director: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
