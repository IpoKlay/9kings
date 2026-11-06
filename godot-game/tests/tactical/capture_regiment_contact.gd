extends SceneTree
## Use --write-movie with --fixed-fps 60. Frame numbers in the trace start at command setup.
const STEP=1.0/60
var app
var trial
var trace: FileAccess
var scenario: String
var attacker: Dictionary
var defender: Dictionary

func _initialize():call_deferred('run')

func run():
	var args=OS.get_cmdline_user_args()
	scenario=args[0]
	trace=FileAccess.open(args[1],FileAccess.WRITE)
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/tmp/eagle-impact-prefs.cfg'
	root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit()
	trial=app.active_trial
	trial.set_process(false)
	var r=trial.rules
	r.units.clear()
	var center=Vector2(1980,750)
	r.spawn('guard' if scenario=='flank' else 'spear' if scenario=='pikes' else 'guard','enemy',center)
	defender=r.units.back()
	defender.order='hold'
	defender.heading=Vector2.LEFT
	if scenario=='flank':
		r.spawn('guard','ally',center-Vector2(386,0))
		r.units.back().order='auto'
	var start=center+Vector2(250,530) if scenario=='flank' else center-Vector2(530,0)
	r.spawn('guard' if scenario=='shield' else 'cavalry','ally',start)
	attacker=r.units.back()
	attacker.heading=Vector2.RIGHT
	attacker.order='hold'
	trial.set_camera(r.projection*center-Vector2(1100,500))
	trial.refresh()
	trial.start_button.pressed.emit()
	if scenario=='flank':r.command([r.units[1].id],'move',center)
	trial.selected=''
	print('FILM ',scenario,' frame origin ',Engine.get_frames_drawn(),' zoom ',trial.zoom,' slow ',trial.slow)
	var hit_count=0
	for frame in 720 if scenario=='shield' else 530:
		if frame==10:
			click(trial.field.project(attacker.pos)-trial.camera_offset-Vector2(0,35),MOUSE_BUTTON_LEFT)
			if trial.squad_ids!=[attacker.id]:push_error('Selection missed');quit(1);return
		if frame==30:
			click(trial.field.project(center)-trial.camera_offset-Vector2(0,35),MOUSE_BUTTON_RIGHT)
			if attacker.order!='attack' or attacker.target_id!=defender.id:push_error('Focus missed');quit(1);return
		trial._process(STEP)
		var events=[]
		for effect in trial.field.effects:
			if effect.age==0 and effect.get('attacker',-1)==attacker.id and effect.get('target',-1)==defender.id:
				events.append(effect.kind)
				hit_count+=1
		trace.store_line(JSON.stringify({'f':frame,'a':unit_sample(attacker),'d':unit_sample(defender),'events':events}))
		await process_frame
	trace.close()
	print('FILM completed, actual hits ',hit_count)
	quit(0 if hit_count else 1)

func click(pos: Vector2,button: MouseButton):
	for down in [true,false]:
		var e=InputEventMouseButton.new()
		e.position=pos
		e.global_position=pos
		e.button_index=button
		e.pressed=down
		root.push_input(e,true)

func unit_sample(u: Dictionary) -> Dictionary:
	var p: Vector2=trial.field.project(u.pos)-trial.camera_offset
	var h: Vector2=trial.rules.ground_basis.basis_xform(u.heading)
	var bearing=posmod(roundi(atan2(h.x,h.y)/(PI/4)),8)
	if u.kind=='cavalry' and trial.field.has_method('mounted_bearing'):
		bearing=trial.field.mounted_bearing(u,atan2(h.x,h.y))
	var stats: Dictionary=trial.rules.config.types[u.kind]
	var slots=int(stats.soldiers)
	var layout=preload('res://scripts/tactical/pass_terrain.gd').layout(u.kind)
	var offsets={}
	if 'contact_profiles' in trial.rules:
		slots=trial.rules.contact_profiles[u.kind].feet.size()
		for slot in slots:
			var shift: Vector2=trial.rules.Contact.body_shift(u,slot,trial.rules.elapsed)
			if shift!=Vector2.ZERO:offsets[slot]=[shift.x,shift.y]
	var formation=[int(stats.files),ceili(float(slots)/int(stats.files)),layout.x,layout.y,layout.z]
	return {'formation':formation,'offsets':offsets,'priority':u.get('slot_priority',{}),'kind':u.kind,'p':[p.x,p.y],'dir':bearing,
		'hp':u.hp,'max':u.max_hp,'attack':u.attack_age,'hit':u.hit_age,'walk':u.moving,'march':u.march_distance,
		'pace':u.get('pace',0)}
