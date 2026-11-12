extends RefCounted
## Gameplay space, discovery memory and neutral encounters share ground coordinates.
const CELL=64.
const CENTER=Vector2(1450,2540)
const WALL_RADIUS=448.
const WALL_CORNER=WALL_RADIUS*(sqrt(2.)-1.)
const RING_TWO=850.
const RING_THREE=1250.
var explored={}
var sight={}
var remembered_buildings={}
var camps=[]
var clock=0.
var rng=RandomNumberGenerator.new()
var enemy_city=Vector2(1600,370)
func ring(point: Vector2) -> int:
	var delta=(point-CENTER).abs()
	var distance=maxf(maxf(delta.x,delta.y),(delta.x+delta.y)/sqrt(2.))
	return 1 if distance<WALL_RADIUS else 2 if distance<RING_TWO else 3 if distance<RING_THREE else 4
func cell(point: Vector2) -> Vector2i:return Vector2i((point/CELL).floor())
func visible(point: Vector2) -> bool:return sight.has(cell(point))
func discovered(point: Vector2) -> bool:return explored.has(cell(point))
func setup(r):
	rng.seed=20261110
	r.add_building('town',CENTER,true)
	r.add_building('barracks',Vector2(1790,2480),true)
	r.add_building('house',Vector2(1210,2730),true)
	for i in 5:r.spawn_person('villager','ally',Vector2(1330+i*32,2410))
	for i in 2:
		r.spawn_person('shield','ally',Vector2(1590+i*35,2410))
		r.spawn_person('spear','ally',Vector2(1590+i*35,2350))
	var corners=wall_vertices()
	for edge in 8:
		var start: Vector2=corners[edge];var finish: Vector2=corners[(edge+1)%8]
		var direction=start.direction_to(finish);var length=start.distance_to(finish)
		var cardinal=edge%2==0;var segments=7 if cardinal else 6
		var cursor=0.
		for slot in segments:
			var gate=cardinal and slot==3
			var span=64. if gate else (length-64.)/6. if cardinal else length/6.
			var b=r.add_building('gate' if gate else 'wall',start+direction*(cursor+span*.5),true)
			b.initial_wall=true;b.wall_angle=direction.angle();b.wall_length=span
			# Conservative bounds of the same rotated stone segment used by rendering.
			b.wall_bounds=direction.abs()*span+direction.orthogonal().abs()*34.
			if gate:b.open=true
			cursor+=span
	r.rebuild_obstacles()
	add_resource(r,'iron',Vector2(1730,2790))
	for i in 3:r.add_building('farm',Vector2(1460+i*72,2730),true)
	for i in 9:add_resource(r,'tree',Vector2(1190+(i%3)*60,2280+(i/3)*60))
	for zone in [2,3,4]:
		var kinds=['berries','sheep','tree','iron'] if zone==2 else ['deer','fruit','iron'] if zone==3 else ['boar','large_iron']
		for kind in kinds:
			for i in 3:
				var point=pick(r,zone)
				if point!=Vector2.INF:add_resource(r,kind,point)
	for zone in [3,4]:
		for i in 2:
			var point=pick(r,zone,170.)
			if point!=Vector2.INF:create_camp(r,point,zone==4)
	for i in 4:
		var point=pick(r,4)
		if point==Vector2.INF:continue
		var wolf=r.spawn_person('wolf','enemy',point)
		wolf.home=point;wolf.wild=true;wolf.order='auto';wolf.soldiers[0].personal_order='auto'
	var town=r.add_building('town',enemy_city,true);town.side='enemy'
	var barracks=r.add_building('barracks',Vector2(1920,460),true);barracks.side='enemy'
	refresh_sight(r)
func wall_vertices() -> Array[Vector2]:
	var a=WALL_CORNER;var b=WALL_RADIUS
	var result: Array[Vector2]=[]
	for offset in [Vector2(-a,-b),Vector2(a,-b),Vector2(b,-a),Vector2(b,a),Vector2(a,b),Vector2(-a,b),Vector2(-b,a),Vector2(-b,-a)]:result.append(CENTER+offset)
	return result
func add_resource(r,kind: String,point: Vector2):
	r.resources.append({'kind':kind,'pos':point,'remaining':5000. if kind=='large_iron' else 1200.,'ring':ring(point)})
func pick(r,zone: int,clearance: float=75.) -> Vector2:
	for attempt in 500:
		var point=Vector2(rng.randf_range(100,r.bounds.end.x-100),rng.randf_range(100,r.bounds.end.y-100))
		if ring(point)!=zone or point.distance_to(enemy_city)<430. or r.river.grow(clearance).has_point(point):continue
		if r.terrain.ROCKS.any(func(rect):return rect.grow(clearance).has_point(point)):continue
		if r.resources.any(func(resource):return resource.pos.distance_to(point)<clearance+50.):continue
		if camps.any(func(camp):return camp.pos.distance_to(point)<380.):continue
		return point
	return Vector2.INF
func create_camp(r,point: Vector2,strong: bool):
	var camp={'pos':point,'strong':strong,'units':[],'towers':[],'claimed':false,'reward_count':0}
	var count=rng.randi_range(20,25) if strong else rng.randi_range(3,8)
	for i in count:
		var type=['shield','spear','archer'][i%3] if strong else ['spear','archer'][i%2]
		var at=point+Vector2((i%5-2)*35,(i/5)*35)
		var u=r.spawn_person(type,'enemy',at)
		u.home=at;u.camp=camps.size();u.order='auto';u.soldiers[0].personal_order='auto'
		if strong:
			u.armor_bonus=2;u.combat_stats.damage*=r.attack_modifiers.strong_camp_damage_multiplier;u.individual_stats.damage=u.combat_stats.damage
			u.max_hp*=1.25;u.soldier_max_hp=u.max_hp;u.soldiers[0].max_hp=u.max_hp;u.soldiers[0].hp=u.max_hp;r.Soldiers.total(u)
		camp.units.append(u.id)
	if strong:
		for dx in [-135,135]:
			var tower=r.add_building('outpost',point+Vector2(dx,-70),true);tower.side='enemy';tower.camp=camps.size();camp.towers.append(tower.id)
	camps.append(camp)
func step(r,dt: float):
	clock+=dt
	if clock>=.2:clock=0.;refresh_sight(r)
	for u in r.units:
		if u.get('wild',false) and u.hp<=0 and not u.get('carcass',false):
			u.carcass=true;add_resource(r,'wolf',u.pos)
		if u.hp>0 and (u.has('camp') or u.get('wild',false)) and u.pos.distance_to(u.home)>600.:
			r.Soldiers.command(r,[Vector2i(u.id,0)],'move',u.home,-1,-1,[],true,'enemy')
		if u.side=='ally' and u.hp>0 and r.town_level>=5 and u.unit_type!='villager' and not r.in_combat(u):r.heal(u,2.*dt)
	for camp in camps:
		if camp.claimed:continue
		if r.units.any(func(u):return u.id in camp.units and u.hp>0):continue
		if camp.towers.any(func(id):return r.buildings[id].hp>0):continue
		camp.claimed=true
		var reward=600 if camp.strong else 100
		for key in r.stock:r.stock[key]+=reward
		if camp.strong:
			camp.reward_count=rng.randi_range(5,8)
			for i in camp.reward_count:
				var type=['shield','spear','archer','light_cavalry'][rng.randi_range(0,3)]
				r.spawn_person(type,'ally',camp.pos+Vector2(i*35-100,0))
		# Liberation rewards may temporarily exceed the cap; further recruitment still checks it.
		r.report='蛮族据点已清除：各资源 +%d%s'%[reward,'，解救 %d 名罗马士兵'%camp.reward_count if camp.strong else '']
func refresh_sight(r):
	sight.clear()
	for u in r.alive('ally'):
		if not u.get('escaped',false):reveal(u.pos,400. if u.unit_type=='villager' else 560.)
	for b in r.buildings:
		if b.side!='ally' or b.hp<=0 or b.remaining>0:continue
		var defensive=b.kind in ['wall','gate','wall_tower','outpost','fortress']
		reveal(b.pos,650. if defensive else 280.,b.get('initial_wall',false))
	for key in sight:explored[key]=true
	for b in r.buildings:
		if visible(b.pos):
			if b.hp>0:remembered_buildings[b.id]=b.duplicate(true)
			else:remembered_buildings.erase(b.id)
func reveal(point: Vector2,radius: float,wall: bool=false):
	var low=cell(point-Vector2.ONE*radius);var high=cell(point+Vector2.ONE*radius)
	for x in range(low.x,high.x+1):
		for y in range(low.y,high.y+1):
			var center=(Vector2(x,y)+Vector2(.5,.5))*CELL
			if center.distance_to(point)<=radius and (not wall or ring(center)<=2):sight[Vector2i(x,y)]=true
func displayed_buildings(r) -> Array:
	var result=[]
	for b in r.buildings:
		if b.side=='ally' or visible(b.pos):result.append(b)
		elif remembered_buildings.has(b.id):result.append(remembered_buildings[b.id])
	return result
