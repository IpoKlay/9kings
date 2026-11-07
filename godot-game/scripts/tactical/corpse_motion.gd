extends RefCounted
## Visual-only Verlet rig. Numerical topology is separate from our pixel artwork.
const DURATION=3.0
static var definitions: Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://data/presentation/corpse_rigs.json'))
var age=0.0
var x=PackedFloat32Array()
var y=PackedFloat32Array()
var old_x=PackedFloat32Array()
var old_y=PackedFloat32Array()
var rest=PackedVector2Array()
var frozen=PackedByteArray()
var links: Array=[]
var angles: Array=[]
var equipment: Dictionary={}
var blood: Array=[]
var burst: Array=[]
var scatter=false
var pool_radius=0.0
var direction=Vector2.ZERO
var random=RandomNumberGenerator.new()

func point(i:int) -> Vector2:return Vector2(x[i],y[i])
func set_point(i:int,p:Vector2):x[i]=p.x;y[i]=p.y
func add(p:Vector2):x.append(p.x);y.append(p.y)

func setup(reference:String,facing:Vector2,velocity:Vector2,attacker_delta,radius:float,random_seed:int):
	random.seed=random_seed
	var type:int=definitions.types.get(reference,-1)
	var mounted=type in [6,12,13,26,27,45]
	scatter=type in [41,42,45]
	pool_radius=0. if scatter or type==43 else radius*.4
	direction=attacker_delta.normalized() if attacker_delta is Vector2 else velocity.normalized() if velocity.length_squared()>1. else Vector2.from_angle(random.randf()*TAU)
	var impulse=140. if mounted else 95.
	var aim=facing.normalized()
	var lateral=Vector2(aim.y,-aim.x)
	var size=.65 if type>=20 and type<=27 else 1.4 if type==28 else 1.
	var rig='mounted' if mounted else 'quadruped' if type==46 else 'foot'
	if type!=43:
		if rig=='quadruped':
			var shoulder=aim*5+Vector2(0,-10);var haunch=-aim*5+Vector2(0,-9);var neck=shoulder+aim*3+Vector2(0,-3)
			for p in [neck+aim*5+Vector2(0,-2),neck,shoulder,haunch,shoulder+lateral*3+Vector2(0,2),shoulder-lateral*3+Vector2(0,2),haunch+lateral*3+Vector2(0,2),haunch-lateral*3+Vector2(0,2)]:add(p)
		else:
			var torso=Vector2(0,-42 if mounted else -14*size)
			var s=1. if mounted else size
			var elbow=5. if mounted else 6.*s;var hand=3. if mounted else 4.*s
			var le=torso+lateral*elbow+Vector2(0,2*s);var re=torso-lateral*elbow+Vector2(0,2*s)
			for p in [torso+Vector2(0,-8*s),torso+Vector2(0,-5*s),torso,le,le+lateral*hand+Vector2(0,5 if mounted else 6*s),re,re-lateral*hand+Vector2(0,5 if mounted else 6*s),Vector2(-3*s,-30 if mounted else -4*s),Vector2(3*s,-30 if mounted else -4*s),Vector2(-4 if mounted else -3*s,-24 if mounted else 0),Vector2(4 if mounted else 3*s,-24 if mounted else 0)]:add(p)
			if mounted:
				var front=aim*10+Vector2(0,-16);var rear=-aim*10+Vector2(0,-14)
				for p in [front+aim*10+Vector2(0,-4),front,rear,front+Vector2(-5,0),front+Vector2(5,2),rear+Vector2(0,2)]:add(p)
		if not scatter:
			links=definitions[rig].links.duplicate(true);angles=definitions[rig].angles
			if rig=='foot':
				for link in links:link[2]*=size
		for i in x.size():rest.append(point(i))
		frozen.resize(x.size());frozen.fill(0)
		old_x=x.duplicate();old_y=y.duplicate()
		# The reference consumes these rider RNG draws, then replaces their old positions.
		if mounted:
			for i in 11:random.randf_range(.5,1.5)
		if scatter:
			for i in x.size():
				var spread=Vector2(random.randf_range(-1,1),random.randf_range(-1,1))
				var v=(direction+spread).normalized()*impulse*random.randf_range(.6,1.6)+velocity*.3
				old_x[i]=x[i]-v.x*.016;old_y[i]=y[i]-v.y*.016
		else:
			for iteration in 4:constrain()
			var v=direction*impulse+velocity*.5
			for i in x.size():old_x[i]=x[i]-v.x*.016;old_y[i]=y[i]-v.y*.016
	if type==43:
		for i in 40:
			var p=Vector2(random.randf_range(-8,8),random.randf_range(-16,2))
			var d=(direction*.3+Vector2(random.randf_range(-1,1),random.randf_range(-1,1))).normalized();var speed=random.randf_range(30,90)
			burst.append({'point':p,'velocity':Vector2(d.x*speed+random.randf_range(-15,15),-absf(d.y*speed)-random.randf_range(20,50)),'size':random.randf_range(2,5)})
	elif not scatter:
		for i in 12:
			var d=(direction+Vector2(random.randf_range(-.5,.5),random.randf_range(-.5,.5))).normalized();var speed=random.randf_range(70,200)
			var p=Vector2(random.randf_range(-6,6),random.randf_range(-10,2))
			blood.append({'point':p,'old':p-d*speed*.016,'radius':random.randf_range(.5,1.5),'color':mini(2,int(random.randf()*3))})
	# Even types without a visible weapon consume the reference weapon random draws.
	var weapon_angle=aim.angle()+random.randf_range(-.3,.3)
	var weapon_dir=(direction+Vector2(random.randf_range(-.4,.4),random.randf_range(-.4,.4))).normalized()
	var weapon_speed=impulse*random.randf_range(1.4,2.2)
	var has_weapon=type in [0,10,40,1,9,24,41,2,11,42,3,28,4,5,12,13,26,45,6,27,7,43]
	if has_weapon:equipment.weapon=piece(point(6) if x.size()>6 else Vector2(0,-12),weapon_dir*weapon_speed,weapon_angle)
	if type in [0,2,40,42]:
		var angle=aim.angle()+random.randf_range(-.5,.5)
		var d=(direction+Vector2(random.randf_range(-.5,.5),random.randf_range(-.5,.5))).normalized();var speed=impulse*random.randf_range(1.2,1.8)
		equipment.shield=piece(point(4),d*speed,angle)

func piece(p:Vector2,v:Vector2,angle:float) -> Dictionary:
	return {'point':p,'old':p-v*.016,'origin':p,'angle':angle,'initial_angle':angle}

func constrain():
	for link in links:
		var a=int(link[0]);var b=int(link[1]);var dx=float(x[b])-float(x[a]);var dy=float(y[b])-float(y[a]);var distance=sqrt(dx*dx+dy*dy)
		if distance<.001 or (frozen[a] and frozen[b]):continue
		var factor=(float(link[2])-distance)/distance*.5;var ox=dx*factor;var oy=dy*factor
		if not frozen[a]:x[a]-=ox*(2 if frozen[b] else 1);y[a]-=oy*(2 if frozen[b] else 1)
		if not frozen[b]:x[b]+=ox*(2 if frozen[a] else 1);y[b]+=oy*(2 if frozen[a] else 1)
	for joint in angles:
		var a=int(joint[0]);var b=int(joint[1]);var c=int(joint[2])
		if frozen[a] and frozen[c]:continue
		var ax=float(x[a])-float(x[b]);var ay=float(y[a])-float(y[b]);var cx=float(x[c])-float(x[b]);var cy=float(y[c])-float(y[b])
		var cross=ax*cy-ay*cx;var angle=atan2(absf(cross),ax*cx+ay*cy);var minimum=deg_to_rad(float(joint[3]))
		if angle>=minimum:continue
		var half=(minimum-angle)*.15;var cosine=cos(half);var sine=sin(half)*(1. if cross>=0 else -1.)
		if not frozen[a]:x[a]=x[b]+ax*cosine-ay*sine;y[a]=y[b]+ax*sine+ay*cosine
		if not frozen[c]:x[c]=x[b]+cx*cosine+cy*sine;y[c]=y[b]-cx*sine+cy*cosine

func advance(dt:float):
	if dt<=0:return
	age+=dt
	if age>=DURATION:return
	# Original visual drag is per callback, not per second. Keep it out of combat physics.
	var drag=.94 if age<.4 else .85
	for i in x.size():
		if frozen[i]:continue
		var vx=(float(x[i])-float(old_x[i]))*drag;var vy=(float(y[i])-float(old_y[i]))*drag
		old_x[i]=x[i];old_y[i]=y[i];x[i]+=vx;y[i]+=vy
		if age>.4 and absf(vx)<.4 and absf(vy)<.4:frozen[i]=1
	var before_x=x.duplicate();var before_y=y.duplicate()
	for iteration in 6:constrain()
	for i in x.size():old_x[i]+=float(x[i])-float(before_x[i]);old_y[i]+=float(y[i])-float(before_y[i])
	for drop in blood:
		var v:Vector2=(drop.point-drop.old)*drag;drop.old=drop.point;drop.point+=v
	for name in equipment:
		var e:Dictionary=equipment[name];var v:Vector2=(e.point-e.old)*drag;e.old=e.point;e.point+=v
		e.angle+=(v.x+v.y)*.02 if name=='weapon' else (v.x-v.y)*.015
	for b in burst:b.point+=b.velocity*dt;b.velocity*=.96

func opacity() -> float:
	return clampf(age/.12 if age<.12 else 1. if age<1.35 else (3.-age)/1.65,0.,1.)
