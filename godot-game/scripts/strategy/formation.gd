extends RefCounted
## Pure layout: unit IDs remain stable; teams are logical groups, never HP pools.
static func rows(count: int) -> Array:
	var result=[]
	var n=ceili(count/5.0)
	for i in n:result.append(count/n+(1 if i<count%n else 0))
	return result

static func offsets(count: int,form: String,spacing: float) -> Array:
	var result=[]
	for i in count:
		var p=Vector2((i%7-3)*spacing,(i/7)*spacing)
		if form=='scatter':p*=1.8
		elif form=='dense':p*=.8
		elif form=='ring':p=Vector2.from_angle(TAU*i/maxi(count,1))*maxf(spacing,spacing*count/TAU)
		elif form=='wedge':
			var rank=ceili(i/2.0)
			p=Vector2(rank*spacing*(1 if i%2==1 else -1),rank*spacing*.65)
		if count<7 and form not in ['ring','wedge']:p.x+=(7-count)*spacing*.5*(1.8 if form=='scatter' else .8 if form=='dense' else 1.)
		result.append(p)
	return result

static func plan(r,selected: Array,destination: Vector2,via: Array) -> Array:
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
	var priority=['light_cavalry','elite_cavalry','shield','spear','archer','engineer','villager','ram','tower','ballista','catapult']
	var output={};var depth=0.;var team_number=0
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
						var leg=r.terrain.leg(r.Soldiers.navigator(r,row.unit.kind,row.unit),start,next)
						if leg.is_empty():return []
						path.append_array(leg);stops.append(next);start=next
					output[Vector2i(row.unit.id,row.slot)]={'path':path,'stops':stops,'batch':{},'team':team_number,'formation':winner,'heading':forward}
				team_number+=1
			depth+=height+r.strategy.team_gap
	var result=[]
	for row in selected:result.append(output[Vector2i(row.unit.id,row.slot)])
	return result
