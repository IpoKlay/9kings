extends RefCounted
## Individual role cohorts issue ordinary commands; terrain and combat remain authoritative.
var active=false
var personality=.5
var aggression=.5
var until_review=.5
var home=Vector2.ZERO
var initial_enemy=0
var kills=0
var losses=0
var known={'ally':{},'enemy':{}}
var assigned={}
var cohorts=[]
var orders=[]

static func primary(bits: int) -> int:
	for flag in [4,16,2,1,32]:
		if bits&flag:return flag
	return 128

func people(r,side: String) -> Array:
	var result=[]
	for u in r.alive(side):
		if u.get('escaped',false) or not r.config.types[u.kind].has('individual'):continue
		for i in u.soldiers.size():
			if u.soldiers[i].hp<=0:continue
			result.append({'id':Vector2i(u.id,i),'unit':u,'actor':u.soldiers[i],
				'point':r.Soldiers.ground_position(r,u,i),'roles':int(r.Soldiers.individual(r,u).role_bits)})
	return result

static func center(rows: Array,fallback=Vector2.ZERO) -> Vector2:
	var sum=Vector2.ZERO
	for row in rows:sum+=row.point
	return sum/rows.size() if not rows.is_empty() else fallback

func begin(r):
	active=true
	personality=float(r.config.get('enemy_director',{}).get('personality',.5))
	aggression=personality
	var enemies=people(r,'enemy')
	initial_enemy=enemies.size()
	home=r.enemy_zone.get_center()
	for side in ['ally','enemy']:
		for row in people(r,side):known[side][row.id]=true
	prepare(r,enemies)

func prepare(r,rows: Array):
	for row in rows:
		if row.unit.order!='auto' or row.actor.get('director_owned',false):continue
		r.Soldiers.automate(r,row.unit)
		row.actor.director_owned=true;row.actor.personal_order='idle'

func advance(r,dt: float):
	if not active or dt<=0:return
	var allies=people(r,'ally');var enemies=people(r,'enemy')
	prepare(r,enemies)
	for side in ['ally','enemy']:
		var live={}
		for row in allies if side=='ally' else enemies:live[row.id]=true
		for id in known[side]:
			if known[side][id] and not live.has(id):
				if side=='ally':kills+=1
				else:losses+=1
				known[side][id]=false
		for id in live:known[side][id]=true
	until_review-=dt
	if until_review>.000001:return
	until_review=1.5
	aggression=clampf(personality+clampf((float(enemies.size())/maxi(1,allies.size())-1.)*.25,-.15,.25)+clampf((kills-losses)*.05,-.1,.15)-clampf(float(losses)/maxi(1,initial_enemy)*.4,0.,.3),0.,1.)
	var live={}
	for row in enemies:live[row.id]=row
	for group in cohorts:group.members=group.members.filter(func(id):return live.has(id))
	cohorts=cohorts.filter(func(group):return not group.members.is_empty())
	var newcomers={}
	for row in enemies:
		if not row.actor.get('director_owned',false) or assigned.has(row.id):continue
		var role=primary(row.roles)
		if not newcomers.has(role):newcomers[role]=[]
		newcomers[role].append(row.id);assigned[row.id]=true
	for role in newcomers:
		cohorts.append({'members':newcomers[role],'role':role,'task':{4:'support',16:'flank',2:'shock'}.get(role,'front'),'cooldown':0.,'target':Vector2i(-1,-1)})
	if float(enemies.size())/maxi(1,initial_enemy)<.3:
		for group in cohorts:group.task='retreat'
	else:
		for group in cohorts:
			if group.task!='support':continue
			var point=center(rows_for(group,live))
			for target in allies:
				if target.roles&64 and point.distance_to(target.point)<400.:
					for reserve in cohorts:
						if reserve.task in ['front','idle'] and rows_for(reserve,live).any(func(row):return row.roles&8):
							reserve.task='intercept';reserve.target=target.id;break
					break
		for group in cohorts:
			if aggression<.25 and group.task=='front' and rows_for(group,live).all(func(row):return row.roles&1):group.task='wall'
	var front=[]
	for group in cohorts:
		if group.task in ['front','wall']:front.append_array(rows_for(group,live))
	var front_center=center(front,center(enemies,home));var player_center=center(allies)
	for index in cohorts.size():
		var group=cohorts[index];group.cooldown-=1.5
		if group.cooldown>0:continue
		group.cooldown=3.
		issue(r,group,index,rows_for(group,live),allies,front_center,player_center)

static func rows_for(group: Dictionary,live: Dictionary) -> Array:
	var rows=[]
	for id in group.members:rows.append(live[id])
	return rows

func issue(r,group: Dictionary,index: int,rows: Array,allies: Array,front: Vector2,player: Vector2):
	var middle=center(rows);var goal=player;var order='attack_move';var focus={}
	match group.task:
		'support':
			goal=front+player.direction_to(front)*180.
			if middle.distance_to(goal)<100.:
				var score=-INF
				for target in allies:
					var value=(200. if target.roles&4 else 0.)-front.distance_to(target.point)*.1+(1.-target.actor.hp/target.actor.max_hp)*50.
					if value>score:score=value;focus=target
				if not focus.is_empty():order='attack'
		'flank':
			var forward=front.direction_to(player)
			goal=player+Vector2(-forward.y,forward.x)*500.*(1. if index%2==0 else -1.)
		'shock':
			if middle.distance_to(player)<760. and aggression>.5:order='shock'
		'intercept':
			for target in allies:
				if target.id==group.target:focus=target;break
			if focus.is_empty():group.task='front';group.target=Vector2i(-1,-1);return
			order='attack'
		'retreat':goal=home;order='move'
		'wall':
			var heading=middle.direction_to(player)
			var fighting=rows.any(func(row):return row.actor.has('attack_engaged') and not row.actor.get('shield_wall',false) and row.actor.personal_order!='hold')
			if rows.any(func(row):return row.actor.hit_age<3.) and not fighting:middle+=heading*60.
			var across=Vector2(-heading.y,heading.x);var vacant=[]
			for i in rows.size():vacant.append(middle+across*(i-(rows.size()-1)*.5)*28.)
			for row in rows:
				var chosen=0
				for i in vacant.size():
					if row.point.distance_squared_to(vacant[i])<row.point.distance_squared_to(vacant[chosen]):chosen=i
				var destination: Vector2=vacant.pop_at(chosen)
				if send(r,row,'move',destination):
					row.actor.shield_wall=true;row.actor.wall_heading=heading;row.actor.heading=heading
					r.Walls.assign(row.actor,destination,row.actor.path)
			orders.append({'time':r.elapsed,'task':group.task,'count':rows.size(),'goal':middle});return
	for row in rows:
		var destination=goal+(row.point-middle).limit_length(120.)
		if order=='attack':send(r,row,order,focus.point,focus.id)
		elif order=='shock':
			if row.roles&64:r.Charges.issue(r,[row.id],player,'enemy')
			else:send(r,row,'attack_move',player)
		elif group.task=='retreat':send(r,row,'move',home)
		else:send(r,row,order,destination)
	orders.append({'time':r.elapsed,'task':group.task,'count':rows.size(),'goal':goal,'focus':focus.get('id',Vector2i(-1,-1))})

func send(r,row: Dictionary,order: String,goal: Vector2,focus=Vector2i(-1,-1)) -> bool:
	if row.unit.get('routing',false):return false
	# Editable map bounds and rock paths are project constraints, not a second navigation system.
	var radius: float=r.Soldiers.individual(r,row.unit).unit_size
	goal=goal.clamp(r.bounds.position+Vector2.ONE*radius,r.bounds.end-Vector2.ONE*radius)
	var via: Array[Vector2]=[]
	return r.Soldiers.command(r,[row.id],order,goal,focus.x,focus.y,via,true,'enemy')
