extends RefCounted
## Pure layout: unit IDs remain stable; teams are logical groups, never HP pools.
static func rows(count: int) -> Array:
	var result=[]
	var n=ceili(count/5.0)
	for i in n:result.append(count/n+(1 if i<count%n else 0))
	return result

static func offsets(count: int,form: String,spacing: float) -> Array:
	var result=[]
	var cursor=0
	var rank=0
	while cursor<count:
		# Filled triangular ranks: 1, 2, 3, 4, 5, 6 = 21 soldiers.
		var width=mini(rank+1,count-cursor) if form=='wedge' else mini(7,count-cursor)
		for col in width:
			var gap=spacing*(1.8 if form=='scatter' else .8 if form in ['dense','testudo'] else 1.)
			var p=Vector2((col-(width-1)*.5)*gap,rank*gap)
			if form=='scatter':p.x+=(.25 if rank%2 else -.25)*gap
			if form=='ring':p=Vector2.from_angle(TAU*cursor/maxi(count,1))*maxf(spacing,spacing*count/TAU)
			result.append(p)
			cursor+=1
		rank+=1
	return result

static func plan(r,selected: Array,destination: Vector2,via: Array,flexible: bool=true) -> Array:
	var groups={};var center=Vector2.ZERO
	for row in selected:
		var type: String=row.unit.get('unit_type',row.unit.kind)
		if not groups.has(type):groups[type]=[]
		groups[type].append(row)
		center+=r.Soldiers.ground_position(r,row.unit,row.slot)
	center/=maxi(1,selected.size())
	var forward=center.direction_to(destination)
	if forward.is_zero_approx():forward=selected[0].actor.heading
	var lateral=Vector2(-forward.y,forward.x)
	var priority=['light_cavalry','elite_cavalry','shield','spear','archer','engineer','villager','wolf','ram','tower','ballista','catapult']
	var output={};var depth=0.;var team_number=0;var reserved=[]
	for type in priority:
		if not groups.has(type):continue
		var people: Array=groups[type];var votes={}
		for row in people:
			var form: String=row.actor.get('formation','default')
			votes[form]=votes.get(form,0)+1
		var winner='default';var best=0
		for form in r.strategy.formations:
			if votes.get(form,0)>best:best=votes[form];winner=form
		var teams=ceili(people.size()/21.0);var cursor=0
		var spacing: float=r.strategy.spacing
		var width=0.
		var local_offsets=offsets(21,winner,spacing)
		var low=0.;var high=0.;var left=0.;var right=0.
		for p in local_offsets:low=minf(low,p.y);high=maxf(high,p.y);left=minf(left,p.x);right=maxf(right,p.x)
		width=right-left
		var height=high-low
		for count in rows(teams):
			for col in count:
				var size=mini(21,people.size()-cursor)
				var formation_offsets=offsets(size,winner,spacing)
				var team_center=destination+lateral*((col-(count-1)*.5)*(width+r.strategy.team_gap))-forward*(depth-low)
				for j in size:
					var row: Dictionary=people[cursor];cursor+=1
					var offset: Vector2=lateral*formation_offsets[j].x-forward*formation_offsets[j].y
					var goal=team_center+offset
					var start: Vector2=r.Soldiers.ground_position(r,row.unit,row.slot)
					var path: Array[Vector2]=[];var stops: Array[Vector2]=[]
					for stop in via+[destination]:
						var next: Vector2=stop+goal-destination
						var nav=r.Soldiers.navigator(r,row.unit.kind,row.unit)
						var leg=r.terrain.leg(nav,start,next)
						if flexible and via.is_empty() and (leg.is_empty() or not same_wall_side(r,destination,next) or not r.terrain.clear_segment(nav,destination,next) or reserved.any(func(point):return point.distance_squared_to(next)<pow(spacing*.65,2))):
							var replacement=nearby_slot(r,nav,start,next,destination,reserved,spacing)
							if replacement.is_empty():return []
							next=replacement.goal;leg=replacement.path
						if leg.is_empty():return []
						path.append_array(leg);stops.append(next);start=next
					reserved.append(start)
					output[Vector2i(row.unit.id,row.slot)]={'path':path,'stops':stops,'batch':{},'team':team_number,'formation':winner,'heading':offset.normalized() if winner=='ring' else forward}
				team_number+=1
			depth+=height+r.strategy.team_gap
	var result=[]
	for row in selected:result.append(output[Vector2i(row.unit.id,row.slot)])
	return result

static func nearby_slot(r,nav: String,start: Vector2,goal: Vector2,anchor: Vector2,reserved: Array,spacing: float) -> Dictionary:
	# The clicked destination itself must remain reachable (closed gates still block orders).
	if r.terrain.leg(nav,start,anchor).is_empty():return {}
	var center=goal.clamp(r.bounds.position+Vector2.ONE*24,r.bounds.end-Vector2.ONE*24)
	for ring in range(1,13):
		for i in 16:
			var candidate=center+Vector2.from_angle(TAU*i/16.)*(ring*spacing)
			if reserved.any(func(point):return point.distance_squared_to(candidate)<pow(spacing*.8,2)):continue
			if not same_wall_side(r,anchor,candidate) or not r.terrain.clear_segment(nav,anchor,candidate):continue
			var path=r.terrain.leg(nav,start,candidate)
			if not path.is_empty():return {'goal':candidate,'path':path}
	return {}

static func same_wall_side(r,anchor: Vector2,point: Vector2) -> bool:
	# Keep a destination outside the starting fort outside, rather than filling the doorway.
	var center: Vector2=r.world.CENTER;var radius: float=r.world.WALL_RADIUS
	for edge in 8:
		var normal=Vector2.from_angle(edge*PI/4.)
		if normal.dot(anchor-center)>radius and normal.dot(point-center)<radius+40.:return false
	return true
