extends SceneTree
## Movie Maker, default zoom, 1x. Only the input rig and evidence capture live here.
const DT=1./60
var t
var r
var errors=0
func _initialize():call_deferred('run')
func check(ok: bool,note: String):
	if not ok:errors+=1;push_error(note)
func world(p: Vector2) -> Vector2:return r.terrain.inverse*p
func spawn(kind: String,side: String,p: Vector2) -> Dictionary:
	r.spawn(kind,side,world(p))
	var u: Dictionary=r.units.back()
	u.order='hold'
	return u
func run():
	var args=OS.get_cmdline_user_args()
	var gate=args[0]=='pass'
	var trace=FileAccess.open(args[1],FileAccess.WRITE)
	AudioServer.set_bus_mute(0,true)
	var app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/tmp/eagle-mounted-run.cfg'
	root.add_child(app)
	app.menu_view.get_node('TacticalTrial').pressed.emit()
	t=app.active_trial
	t.set_process(false)
	var scenery=t.field.environment.preset.duplicate(true)
	scenery.drift_count=0
	t.field.environment.preset=scenery
	r=t.rules
	r.units.clear()
	var target=spawn('guard','enemy',Vector2(1700,890) if gate else Vector2(2110,900))
	var horse=spawn('cavalry','ally',Vector2(570,755) if gate else Vector2(1220,990))
	var shield=spawn('guard','ally',Vector2(610,645) if gate else Vector2(2150,1135))
	var shield_goal=world(Vector2(1440,690) if gate else Vector2(2118,942))
	target.heading=target.pos.direction_to(shield_goal)
	horse.heading=Vector2.DOWN
	t.set_camera(Vector2(200,330) if gate else Vector2(700,330))
	t.refresh()
	t.start_button.pressed.emit()
	var via: Array[Vector2]=[]
	if gate:via.append(world(Vector2(800,890)))
	var old=horse.pos
	var hit=false
	var peak=0.
	var exit_gate=false
	var visited_gate=false
	var after_exit=0.
	var gait_before=''
	var sprint=-1
	trace.store_line('frame,x,y,speed,gait,run,ready,gate,post_gate,hoof_distance,shield_speed,hit')
	for frame in (680 if gate else 510):
		if frame==18:
			check(r.command([shield.id],'move',shield_goal),'Shield march')
			check(r.march_route(horse.id,via,target.pos if gate else world(Vector2(1620,950))),'Mounted route')
		if not gate and frame==130:check(r.command([horse.id],'attack',target.pos,target.id),'Focus order during transit')
		var last_shield: Vector2=shield.pos
		t._process(DT)
		var dist: float=horse.pos.distance_to(old)
		var inside: bool=r.terrain.touches_gate('cavalry',horse.pos)
		if inside:
			visited_gate=true
			check(not horse.charge and horse.clear_run==0 and horse.pace<=1.01,'Narrow file suppresses charge')
		elif visited_gate:
			exit_gate=true
			after_exit+=dist
		var impact=''
		for e in t.field.effects:
			if e.age==0 and e.get('attacker',-1)==horse.id and e.get('target',-1)==target.id:
				impact=e.kind
				if e.get('mounted_contact',false):hit=true
		t.field.effects.clear() # No event particles, dust or hit overlays in the recorded frame.
		peak=maxf(peak,dist/DT)
		if horse.gait!=gait_before:
			print(frame,' ',horse.gait,' speed=',snappedf(dist/DT,.1),' run=',snappedf(horse.clear_run,.1),' postgate=',snappedf(after_exit,.1))
			gait_before=horse.gait
		if horse.gait=='sprint' and sprint<0:sprint=frame
		trace.store_line('%d,%.3f,%.3f,%.3f,%s,%.3f,%d,%d,%.3f,%.3f,%.3f,%s'%[frame,horse.pos.x,horse.pos.y,dist/DT,horse.gait,horse.clear_run,int(horse.charge),int(inside),after_exit,horse.march_distance,last_shield.distance_to(shield.pos)/DT,impact])
		old=horse.pos
		await process_frame
	trace.close()
	check(not gate or exit_gate,'Whole regiment cleared the historical side gate')
	check(hit and peak>r.config.types.cavalry.speed*1.6,'Natural charge after actual run-up')
	print('CAVALRY RUN ',args[0],' peak=',peak,' failures=',errors)
	quit(1 if errors else 0)
