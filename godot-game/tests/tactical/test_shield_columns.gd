extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture():
	var r=Battle.new();r.units.clear()
	r.spawn('legion','ally',Vector2(1000,1300));r.spawn('legion','enemy',Vector2(1800,200))
	for u in r.units:u.order='hold'
	r.start();return r
func tick(r,n):
	for i in n:r.step(1./60)
func run():
	var r=fixture();var u=r.units[0]
	var layout=r.shield_layout([u.id],Vector2(980,1100),Vector2(1020,1100))
	check(layout.size()==10 and layout.values().filter(func(s):return s.rank==0).size()==3 and layout.values().any(func(s):return s.rank==3),'Short F drag creates three columns and four ranks from ten people')
	check(r.command_shield_line([u.id],Vector2(980,1100),Vector2(1020,1100)),'Short shield grid is accepted instead of rejected as too narrow')
	tick(r,900)
	var close=true;var max_distance=0.
	for s in u.soldiers:max_distance=maxf(max_distance,s.position.distance_to(s.wall_slot));close=close and s.position.distance_to(s.wall_slot)<3.
	print('compact grid maximum slot error=',max_distance)
	check(close,'Compact wall reaches assigned slots without friendly collision deadlock')
	var normal: Vector2=u.soldiers[0].wall_heading
	var slots={}
	for key in r.shield_walls[0].targets:slots[key]=r.shield_walls[0].targets[key]
	check(r.command([u.id],'move',Vector2(1000,900)),'Right-click exact wall selection accepts a shield march')
	check(u.shield_wall and u.soldiers.all(func(s):return s.shield_wall and s.wall_heading==normal),'Wall march retains every shield and its original facing')
	tick(r,600)
	check(u.soldiers.all(func(s):return s.personal_order=='hold' and s.position.distance_to(s.wall_slot)<3.),'Free shield march reaches each translated wall slot')
	var state=u.soldiers.duplicate(true)
	check(not r.command([u.id],'move',Vector2(-50,-50)) and state==u.soldiers,'Invalid wall march changes no member, target or stance')
	var displaced=u.soldiers.filter(func(s):return s.wall_rank==3)[0]
	displaced.position-=normal*45.;var bumped: Vector2=displaced.position
	tick(r,20)
	check(displaced.position==bumped,'Displaced shield waits before attempting to return to its held slot')
	tick(r,180)
	check(displaced.position.distance_to(displaced.wall_slot)<3.,'Displaced shield walks back to its slot after the half-second delay')
	r.command([u.id],'hold',Vector2.ZERO)
	var held=u.soldiers.duplicate(true);tick(r,1)
	check(u.soldiers.all(func(s):return s.shield_wall and not s.has('wall_slot')),'H preserves shields but removes forced return slots')
	check(u.soldiers.all(func(s):return not s.has('wall_id')), 'H releases old wall movement authority')
	var paused=r.shield_walls.duplicate(true);var actors=u.soldiers.duplicate(true);r.step(0.)
	check(paused==r.shield_walls and actors==u.soldiers,'Pause freezes wall locks and individual settlement state')
	# Source column propagation depends on a dot product with the wall normal, not screen axes.
	for angle in [0.,PI/2,PI/4]:column_case(angle)
	r.command([u.id],'attack_move',Vector2(1000,700));tick(r,1)
	check(not u.get('shield_wall',false) and r.shield_walls.is_empty(),'Replacement X clears the abandoned wall and its locks')
	var moving=fixture();var squad=moving.units[0]
	moving.command_shield_line([squad.id],Vector2(900,900),Vector2(1160,900))
	for actor in squad.soldiers:actor.position=actor.wall_slot;actor.personal_order='hold';actor.path=[]
	moving.Soldiers.update_center(moving,squad,0.)
	moving.command([squad.id],'move',Vector2(1030,1200))
	check(moving.shield_walls[0].marching,'Fixture has an active wall march')
	moving.command([squad.id],'hold',Vector2.ZERO)
	moving.Walls.advance(moving)
	check(squad.soldiers.all(func(a):return a.personal_order=='hold' and a.path.is_empty() and not a.has('wall_slot')),'H cannot be overwritten by the previous wall march')
	print('Shield columns: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
func column_case(angle: float):
	var r=fixture();var u=r.units[0];var enemy=r.units[1]
	var center=Vector2(1000,1100);var axis=Vector2.RIGHT.rotated(angle);var normal=axis.orthogonal()
	r.command_shield_line([u.id],center-axis*65.,center+axis*65.)
	# Start assembled to isolate column contact from initial marching and assignment.
	for actor in u.soldiers:actor.position=actor.wall_slot;actor.personal_order='hold';actor.path=[]
	r.Soldiers.update_center(r,u,0.)
	for actor in enemy.soldiers:actor.hp=0.
	enemy.soldiers[0].hp=100000.;enemy.soldiers[0].max_hp=100000.;r.Soldiers.total(enemy)
	var lead=u.soldiers.filter(func(s):return s.wall_column==0)[0]
	r.Charges.detach(r,enemy,0);enemy.soldiers[0].position=lead.position+normal*24.;enemy.soldiers[0].personal_order='hold';enemy.soldiers[0].cooldown=100.;enemy.soldiers[0].shield_wall=true;enemy.soldiers[0].wall_heading=-normal
	r.command([u.id],'move',center+normal*180.)
	var wall=r.shield_walls[0];r.Walls.advance(r)
	check(wall.locks.has(0),'First contact column locks from actual nearby enemy, rotated '+str(angle))
	var targets=[]
	for row in r.Walls.living(r,wall):targets.append([row.actor.wall_column,row.actor.wall_slot.dot(normal)])
	targets.sort_custom(func(a,b):return a[0]<b[0])
	var bounded=true
	for i in range(1,targets.size()):bounded=bounded and absf(targets[i][1]-targets[i-1][1])<=4.501
	check(bounded and targets[-1][1]>targets[0][1]+20.,'Adjacent columns advance by at most4.5, while free wing can still move')
	var blocked=lead.position
	tick(r,80)
	check(absf((lead.position-blocked).dot(normal))<1. and u.soldiers.any(func(s):return (s.position-center).dot(normal)>5.),'Contact end holds while the free end actually advances')
	enemy.soldiers[0].position+=normal*500.;r.Walls.advance(r)
	check(wall.locks.is_empty() and wall.marching,'Enemy departure releases column locks and resumes original destinations')
