extends RefCounted
## Authored F slots and column pressure share each soldier's actual ground position.
const BLOCK_RADIUS=28.0
const COLUMN_OFFSET=.25

static func living(r,wall: Dictionary) -> Array:
	return r.Soldiers.members(r,wall.members).filter(func(row):return row.actor.get('shield_wall',false) and row.actor.get('wall_id',-1)==wall.id and not row.unit.get('routing',false))

static func layout(r,ids: Array,start: Vector2,finish: Vector2) -> Dictionary:
	if r.phase!='battle' or start.distance_to(finish)<1.:return {}
	var people=r.Soldiers.members(r,ids).filter(func(row):return r.Soldiers.individual(r,row.unit).get('can_shield_wall',false))
	if people.is_empty():return {}
	var radius=0.
	for row in people:radius=maxf(radius,r.Soldiers.individual(r,row.unit).unit_size)
	var spacing=radius*2.-5.
	var width=start.distance_to(finish);var axis=start.direction_to(finish)
	var columns=maxi(1,roundi(width/spacing));var rows=ceili(float(people.size())/columns)
	var across=width/maxi(1,columns-1) if columns>1 else 0.
	var normal=axis.orthogonal();var remaining=people.duplicate();var result={}
	for rank in rows:
		var count=mini(columns,remaining.size())
		var indent=(width-(count-1)*across)*.5 if count<columns and columns>1 else 0.
		for column in count:
			var goal=start+axis*(indent+column*across)-normal*(rank*spacing)
			var nearest=0;var distance=INF
			for i in remaining.size():
				var row=remaining[i]
				var foot: Vector2=r.Soldiers.ground_position(r,row.unit,row.slot)
				if foot.distance_squared_to(goal)<distance:distance=foot.distance_squared_to(goal);nearest=i
			var person=remaining.pop_at(nearest)
			var nav=r.Soldiers.navigator(r,person.unit.kind,person.unit)
			var extent: Vector2=r.terrain.extents[nav]
			if not r.bounds.has_point(goal):return {}
			for rock: Rect2 in r.terrain.ROCKS:
				if Rect2(rock.position-extent,rock.size+extent*2).has_point(r.projection*goal):return {}
			var from: Vector2=r.Soldiers.ground_position(r,person.unit,person.slot)
			var path=r.terrain.leg(nav,from,goal)
			if path.is_empty():return {}
			result[Vector2i(person.unit.id,person.slot)]={'goal':goal,'heading':normal,'path':path,'column':column,'rank':rank,'spacing':spacing,'columns':mini(columns,people.size())}
	return result

static func place(r,plan: Dictionary):
	var id: int=r.wall_serial;r.wall_serial+=1
	var wall={'id':id,'members':plan.keys(),'original_count':plan.size(),'cells':[],'slots':{},'targets':{},'front_keys':{},'locks':{},'columns':0,'normal':Vector2.ZERO,'marching':false}
	for row in r.Soldiers.members(r,plan.keys()):
		var key=Vector2i(row.unit.id,row.slot);var slot=plan[key]
		r.Soldiers.command(r,[key],'hold',Vector2.ZERO)
		row.actor.wall_id=id;row.actor.wall_column=slot.column;row.actor.wall_rank=slot.rank
		row.actor.wall_spacing=slot.spacing;row.actor.shield_wall=true;row.actor.wall_heading=slot.heading;row.actor.heading=slot.heading
		wall.slots[key]=slot.goal;wall.targets[key]=slot.goal;wall.columns=slot.columns;wall.normal=slot.heading
		wall.cells.append({'member':key,'goal':slot.goal,'column':slot.column,'rank':slot.rank})
		if slot.rank==0:wall.front_keys[slot.column]=key
		assign(row.actor,slot.goal,slot.path)
	wall.cells.sort_custom(func(a,b):return a.rank<b.rank or a.rank==b.rank and a.column<b.column)
	r.shield_walls.append(wall)

static func assign(actor: Dictionary,goal: Vector2,path: Array):
	actor.erase('move_batch');actor.erase('settled_by_sibling')
	actor.personal_order='move';actor.path=path;actor.wall_slot=goal;actor.wall_settle=0.
	actor.target_id=-1;actor.target_slot=-1;actor.next_scan=0.;actor.erase('steer_path');actor.erase('steer_goal')

# Only an exact selection of the remaining wall members retains the wall on right-click.
static func march(r,ids: Array,destination: Vector2,commit: bool) -> Dictionary:
	for wall in r.shield_walls:
		var people=living(r,wall)
		if people.is_empty() or people.size()!=ids.size():continue
		if not people.all(func(row):return Vector2i(row.unit.id,row.slot) in ids):continue
		var center=Vector2.ZERO
		for cell in wall.cells:center+=cell.goal
		center/=wall.cells.size()
		var delta=destination-center;var planned={}
		for row in people:
			var key=Vector2i(row.unit.id,row.slot);var goal: Vector2=wall.targets[key]+delta
			var path=r.terrain.leg(r.Soldiers.navigator(r,row.unit.kind,row.unit),row.actor.position,goal)
			if path.is_empty():return {'accepted':false}
			planned[key]={'goal':goal,'path':path}
		if commit:
			for key in wall.targets:wall.targets[key]+=delta
			for cell in wall.cells:cell.goal+=delta
			wall.locks.clear();wall.marching=true
			for row in people:
				var key=Vector2i(row.unit.id,row.slot)
				wall.slots[key]=planned[key].goal
				assign(row.actor,planned[key].goal,planned[key].path)
		return {'accepted':true}
	return {}

static func maintain(r,wall: Dictionary,people: Array) -> bool:
	# The public build releases the wall at half its original membership.
	if people.size()*2<=wall.original_count:
		for row in people:
			r.Soldiers.command(r,[Vector2i(row.unit.id,row.slot)],'hold',Vector2.ZERO)
			row.actor.shield_wall=false;row.actor.erase('wall_id');row.actor.erase('wall_slot')
			row.actor.personal_order='idle';row.actor.velocity=Vector2.ZERO
			if not row.unit.soldiers.any(func(s):return s.hp>0 and s.get('shield_wall',false)):
				row.unit.erase('shield_wall');row.unit.erase('wall_heading')
		return false
	var available={}
	for row in people:available[Vector2i(row.unit.id,row.slot)]=row
	for cell in wall.cells:
		if not available.has(cell.member):cell.member=Vector2i(-1,-1)
	for cell in wall.cells:
		if available.has(cell.member):continue
		var nearest={};var distance=INF;var path: Array=[]
		for rear in wall.cells:
			if rear.rank<=cell.rank or not available.has(rear.member):continue
			var row: Dictionary=available[rear.member]
			var squared: float=row.actor.position.distance_squared_to(cell.goal)
			if squared>=distance:continue
			var leg=r.terrain.leg(r.Soldiers.navigator(r,row.unit.kind,row.unit),row.actor.position,cell.goal)
			if leg.is_empty():continue
			nearest=rear;distance=squared;path=leg
		if nearest.is_empty():continue
		var key: Vector2i=nearest.member;var actor: Dictionary=available[key].actor
		cell.member=key;nearest.member=Vector2i(-1,-1)
		actor.wall_rank=cell.rank;actor.wall_column=cell.column
		wall.slots[key]=cell.goal;wall.targets[key]=cell.goal
		assign(actor,cell.goal,path)
	wall.front_keys.clear()
	for cell in wall.cells:
		if available.has(cell.member) and not wall.front_keys.has(cell.column):wall.front_keys[cell.column]=cell.member
	return true

static func advance(r):
	for wall in r.shield_walls:
		var people=living(r,wall)
		if not maintain(r,wall,people):continue
		if not wall.marching:continue
		var fronts={};var advances={};var goals={};var allowance=0.
		for row in people:
			var actor=row.actor;var column: int=actor.wall_column
			if not fronts.has(column) or actor.wall_rank<fronts[column].actor.wall_rank:fronts[column]=row
			if allowance==0.:allowance=r.Soldiers.individual(r,row.unit).unit_size*2.*COLUMN_OFFSET
		for column in fronts:
			var row=fronts[column];var actor=row.actor;var blocked=false
			for enemy in r.alive('enemy'):
				for slot in enemy.soldiers.size():
					if enemy.soldiers[slot].hp<=0:continue
					var enemy_position: Vector2=r.Soldiers.ground_position(r,enemy,slot)
					var offset: Vector2=enemy_position-actor.position
					if offset.dot(wall.normal)>=-5. and offset.length_squared()<BLOCK_RADIUS*BLOCK_RADIUS:blocked=true;break
				if blocked:break
			if blocked:
				if not wall.locks.has(column):wall.locks[column]=actor.position.dot(wall.normal)
			else:wall.locks.erase(column)
			goals[column]=wall.targets[wall.front_keys[column]].dot(wall.normal)
			advances[column]=wall.locks.get(column,goals[column])
		var columns=fronts.keys();columns.sort()
		for i in range(1,columns.size()):advances[columns[i]]=minf(advances[columns[i]],advances[columns[i-1]]+allowance*(columns[i]-columns[i-1]))
		for i in range(columns.size()-2,-1,-1):advances[columns[i]]=minf(advances[columns[i]],advances[columns[i+1]]+allowance*(columns[i+1]-columns[i]))
		var active=false
		for row in people:
			var key=Vector2i(row.unit.id,row.slot);var column: int=row.actor.wall_column
			var shift=minf(0.,advances[column]-goals[column])
			var next: Vector2=wall.targets[key]+wall.normal*shift
			if next.distance_squared_to(wall.slots[key])>4.:
				var path=r.terrain.leg(r.Soldiers.navigator(r,row.unit.kind,row.unit),row.actor.position,next)
				if not path.is_empty():wall.slots[key]=next;assign(row.actor,next,path)
			active=active or absf(shift)>=.5 or row.actor.position.distance_squared_to(next)>100.
		wall.marching=active
	r.shield_walls=r.shield_walls.filter(func(wall):return not living(r,wall).is_empty())
