extends SceneTree
const Battle=preload('res://scripts/tactical/whiteboard_battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture(width: float=65.):
	var r=Battle.new();r.units.clear();r.spawn('legion','ally',Vector2(1600,1600));r.spawn('legion','enemy',Vector2(2800,300))
	for u in r.units:u.order='hold'
	r.start();var u=r.units[0];var ids=r.Soldiers.group_members([u])
	var plan=r.Walls.layout(r,ids,Vector2(1600,1600),Vector2(1600+width,1600))
	r.Walls.place(r,plan)
	for key in plan:
		var s=u.soldiers[key.y];s.position=plan[key].goal;s.path=[];s.personal_order='hold'
	return r
func kill(r,u,slot: int):
	u.soldiers[slot].hp=0.;r.Soldiers.total(u)
func run():
	var r=fixture();var u=r.units[0];var wall=r.shield_walls[0]
	var front=u.soldiers.find_custom(func(s):return s.wall_rank==0 and s.wall_column==2)
	var rear=u.soldiers.find_custom(func(s):return s.wall_rank==1 and s.wall_column==2)
	var gap: Vector2=u.soldiers[front].wall_slot;var old: Vector2=u.soldiers[rear].position
	kill(r,u,front);r.Walls.advance(r)
	check(u.soldiers[rear].wall_slot==gap and u.soldiers[rear].wall_rank==0,'Closest rear soldier receives the vacant front slot')
	check(u.soldiers[rear].position==old and u.soldiers[rear].personal_order=='move','Replacement walks from its actual foot, without teleporting')
	check(wall.front_keys[2]==Vector2i(u.id,rear),'Marching front tracks the replacement rather than the casualty')
	for i in 150:r.step(1./60.)
	check(u.soldiers[rear].position.distance_to(gap)<3.,'Replacement physically reaches the gap')
	var survivors=r.Walls.living(r,wall).map(func(row):return Vector2i(row.unit.id,row.slot))
	check(r.Walls.march(r,survivors,Vector2(1650,1450),true).get('accepted',false),'Surviving wall can still receive a whole-wall march')
	for i in 240:r.step(1./60.)
	check(u.soldiers[rear].position.distance_to(wall.targets[Vector2i(u.id,rear)])<3.,'Replacement marches in its new column')
	# Six committed members retain the wall; exactly half dissolve it.
	r=fixture();u=r.units[0]
	for slot in 4:kill(r,u,slot)
	r.Walls.advance(r)
	check(r.shield_walls.size()==1 and r.Walls.living(r,r.shield_walls[0]).size()==6,'Six of ten retain their formation')
	kill(r,u,4);var before=u.soldiers.map(func(s):return s.position)
	r.Walls.advance(r)
	check(r.shield_walls.is_empty(),'Five of ten dissolve the shield wall')
	check(u.soldiers.filter(func(s):return s.hp>0).all(func(s):return not s.get('shield_wall',false) and not s.has('wall_id') and not s.has('wall_slot') and s.personal_order=='idle'),'Survivors lose wall orders and protection, remaining available for new commands')
	check(u.soldiers.map(func(s):return s.position)==before,'Dissolving a wall never moves the bodies')
	# Single-row casualties stay vacant; there is no imaginary rear rank.
	r=fixture(260.);u=r.units[0];kill(r,u,3)
	before=u.soldiers.map(func(s):return s.position);r.Walls.advance(r)
	check(u.soldiers.map(func(s):return s.position)==before and u.soldiers.filter(func(s):return s.hp>0).all(func(s):return s.wall_slot==s.position),'Single-row losses do not slide the whole line sideways')
	# Reassigned people count as departed and keep their replacement order.
	var departed=[]
	for slot in [0,1,2,4,5]:departed.append(Vector2i(u.id,slot))
	r.Soldiers.command(r,departed,'move',Vector2(1800,1800));r.Walls.advance(r)
	check(r.shield_walls.is_empty() and departed.all(func(k):return u.soldiers[k.y].personal_order=='move'),'Departed members retain their new move when the old wall dissolves')
	# A blocked replacement destination never teleports a rear soldier into terrain.
	r=fixture();u=r.units[0]
	front=u.soldiers.find_custom(func(s):return s.wall_rank==0 and s.wall_column==2)
	rear=u.soldiers.find_custom(func(s):return s.wall_rank==1 and s.wall_column==2)
	gap=u.soldiers[front].wall_slot;old=u.soldiers[rear].position
	r.terrain.replace_rocks([Rect2(gap-Vector2(2,2),Vector2(4,4))])
	kill(r,u,front);r.Walls.advance(r)
	check(u.soldiers[rear].wall_slot==old and u.soldiers[rear].position==old,'Blocked gap leaves the rear rank in place')
	r.terrain.replace_rocks([]);r.Walls.advance(r)
	check(u.soldiers[rear].wall_slot==gap and u.soldiers[rear].position==old,'Removing the obstacle permits a walking replacement')
	for slot in u.soldiers.size():kill(r,u,slot)
	r.Walls.advance(r)
	check(r.shield_walls.is_empty(),'A wiped wall leaves no active formation record')
	print('Wall casualties: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
