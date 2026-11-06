extends RefCounted
## One pilot pairing. Geometry is in projected field pixels, before camera zoom.
const Contact=preload('res://scripts/tactical/regiment_contact.gd')
const Terrain=preload('res://scripts/tactical/pass_terrain.gd')
static var sheets={}
static var masks={}

# Coalesce identical opaque horizontal runs on consecutive atlas rows.
# Transparent parts of the 64x64 canvas never become colliders.
static func mask(kind: String,side: String,bearing: int,cell: int) -> Dictionary:
	var name=kind+'_'+side
	var key='%s/%d/%d'%[name,bearing,cell]
	if masks.has(key):return masks[key]
	if not sheets.has(name):
		var texture: Texture2D=load('res://assets/rts-armies/'+name+'.png')
		sheets[name]=texture.get_image()
	var img: Image=sheets[name]
	var rects: Array[Rect2]=[]
	var previous={}
	var scale=Terrain.layout(kind).z
	for y in 64:
		var current={}
		var x=0
		while x<64:
			if img.get_pixel(cell*64+x,bearing*64+y).a<.5:
				x+=1
				continue
			var start=x
			x+=1
			while x<64 and img.get_pixel(cell*64+x,bearing*64+y).a>=.5:x+=1
			var span=Vector2i(start,x)
			var index: int=previous.get(span,-1)
			if index<0:
				index=rects.size()
				rects.append(Rect2(Vector2(start,y)*scale,Vector2(x-start,1)*scale))
			else:rects[index].size.y+=scale
			current[span]=index
		previous=current
	var bounds=rects[0]
	for rect in rects:bounds=bounds.merge(rect)
	masks[key]={'bounds':bounds,'rects':rects}
	return masks[key]

static func pose(r,u: Dictionary) -> Dictionary:
	var h: Vector2=r.ground_basis.basis_xform(u.heading)
	var angle=atan2(h.x,h.y)
	var bearing=Contact.bearing(u,angle,r.config.regiment_impact.bearing_hysteresis_degrees)
	var action: bool=u.attack_age<.55 and u.hp>0 and (u.kind!='cavalry' or not u.moving or u.gait=='impact')
	var frame=clampi(int(u.attack_age/.55*8),0,7) if action else floori(8*u.march_distance/r.config.types[u.kind].stride)
	return {'bearing':bearing,'frame':frame,'action':action,'walk':u.moving,'pos':u.pos}

# First overlap of translating opaque rectangles, by intersecting the X/Y time intervals.
static func entering(a: Rect2,b: Rect2,v: Vector2,limit: float) -> float:
	var first=0.
	var last=limit
	for axis in 2:
		if absf(v[axis])<.00001:
			if a.end[axis]<b.position[axis] or b.end[axis]<a.position[axis]:return INF
		else:
			var lo=(b.position[axis]-a.end[axis])/v[axis]
			var hi=(b.end[axis]-a.position[axis])/v[axis]
			first=maxf(first,minf(lo,hi))
			last=minf(last,maxf(lo,hi))
			if first>last:return INF
	return first

# The field is drawn at half resolution. A crossing of two transparent holes,
# or an overlap too thin to cover an actual field texel, must not trigger a hit.
static func texel_time(strip: Rect2,edge: Rect2,va: Vector2,vb: Vector2,p: Vector2,lo: float,hi: float) -> float:
	for axis in 2:
		for who in 2:
			var rect=strip if who==0 else edge
			var v=va[axis] if who==0 else vb[axis]
			var left=rect.position[axis]
			var right=rect.end[axis]-.00001
			if absf(v)<.00001:
				if p[axis]<left or p[axis]>right:return INF
			else:
				var t0=(p[axis]-right)/v
				var t1=(p[axis]-left)/v
				lo=maxf(lo,minf(t0,t1))
				hi=minf(hi,maxf(t0,t1))
				if lo>hi:return INF
	return lo

static func swept_bounds(rect: Rect2,delta: Vector2) -> Rect2:
	var end=rect
	end.position+=delta
	return rect.merge(end)

static func figures(r,u: Dictionary,pose_data: Dictionary,finish: Vector2,start_time: float,end_time: float) -> Array:
	var stats: Dictionary=r.config.types[u.kind]
	var count=Contact.count(u,stats)
	var anchor=Vector2(32,54)*Terrain.layout(u.kind).z
	var figures_out=[]
	for slot in int(stats.files):
		if not Contact.present(u,slot,count):continue
		var feet: Vector2=r.contact_profiles[u.kind].feet[slot]
		var old_shift=Contact.body_shift(u,slot,start_time)
		var new_shift=Contact.body_shift(u,slot,end_time)
		var origin: Vector2=(r.projection*pose_data.pos+feet+old_shift-anchor).round()
		var dest: Vector2=(r.projection*finish+feet+new_shift-anchor).round()
		var phase=(slot%int(stats.files)+3*(slot/int(stats.files)))%4
		var cell=Contact.cell_index(pose_data.action,pose_data.walk,pose_data.frame,phase)
		var shape=mask(u.kind,'stone' if u.petrified>0 else u.side,pose_data.bearing,cell)
		var box: Rect2=shape.bounds
		box.position+=origin
		var delta=dest-origin
		figures_out.append({'slot':slot,'feet':feet,'origin':origin,'delta':delta,'box':box,'rects':shape.rects,'cell':cell})
	return figures_out

static func earliest(r,a: Dictionary,b: Dictionary,pa: Dictionary,pb: Dictionary,dt: float,min_fraction: float=0.) -> Dictionary:
	var riders=figures(r,a,pa,a.pos,r.elapsed-dt,r.elapsed)
	var soldiers=figures(r,b,pb,b.pos,r.elapsed-dt,r.elapsed)
	var best=INF
	var result={}
	for rider in riders:
		for soldier in soldiers:
			var v: Vector2=rider.delta-soldier.delta
			var limit=minf(1,best)
			if entering(rider.box,soldier.box,v,limit)==INF:continue
			for strip: Rect2 in rider.rects:
				strip.position+=rider.origin
				if entering(strip,soldier.box,v,limit)==INF:continue
				for edge: Rect2 in soldier.rects:
					edge.position+=soldier.origin
					var t=entering(strip,edge,v,limit)
					if t==INF or t>=best:continue
					var region=swept_bounds(strip,rider.delta).intersection(swept_bounds(edge,soldier.delta))
					var start=Vector2i(((region.position-Vector2.ONE)/2).ceil())*2+Vector2i.ONE
					for y in range(start.y,ceili(region.end.y),2):
						for x in range(start.x,ceili(region.end.x),2):
							var pixel=Vector2(x,y)
							var toi=texel_time(strip,edge,rider.delta,soldier.delta,pixel,maxf(t,min_fraction),limit)
							if toi>=best:continue
							best=toi
							limit=toi
							result={'fraction':toi,'pos':r.projection.affine_inverse()*pixel,'rider_slot':rider.slot,'defender_slot':soldier.slot,
								'rider':rider.feet,'entry':soldier.feet,'rider_cell':rider.cell,'defender_cell':soldier.cell,
								'rider_bearing':pa.bearing,'defender_bearing':pb.bearing}
	return result
