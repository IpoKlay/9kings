extends SceneTree
## Movie Maker --fixed-fps 60; use a separate 'mark' run for the audit photograph.
const OUT='res://../output/first-contact/'
const DT=1./60
var t
var r
var cues=[]
var failed=0
func _initialize():call_deferred('run')
func check(ok: bool,note: String):
	if not ok:failed+=1;push_error(note)
func click(p: Vector2,button: MouseButton):
	for down in [true,false]:
		var e=InputEventMouseButton.new()
		e.position=p;e.global_position=p;e.button_index=button;e.pressed=down
		root.push_input(e,true)
func screen(u: Dictionary) -> Vector2:return r.projection*u.pos-t.camera_offset-Vector2(0,35)
func sample(u: Dictionary) -> Dictionary:
	var p: Vector2=r.projection*u.pos-t.camera_offset
	var pose=r.Sweep.pose(r,u)
	var motion: Dictionary=u.get('contact_motion',{})
	var profile: Dictionary=r.contact_profiles[u.kind]
	var layout=preload('res://scripts/tactical/pass_terrain.gd').layout(u.kind)
	var formation=[profile.files,ceili(float(profile.feet.size())/profile.files),layout.x,layout.y,layout.z]
	var offsets={}
	for slot in profile.feet.size():
		var shift: Vector2=r.Contact.body_shift(u,slot,r.elapsed)
		if shift!=Vector2.ZERO:offsets[slot]=[shift.x,shift.y]
	return {'formation':formation,'p':[p.x,p.y],'dir':pose.bearing,'frame':pose.frame,'action':pose.action,'walk':pose.walk,'hp':u.hp,'max':u.max_hp,
		'priority':u.get('slot_priority',{}),'offsets':offsets,'shown':motion.get('old_count',0) if r.elapsed-motion.get('start',-2)<.1 else 0}

func run():
	var args=OS.get_cmdline_user_args()
	var label=args[0]
	var directory=(args[1].trim_suffix('/')+'/') if args.size()>1 and args[1].is_absolute_path() else OUT
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var mark='mark' in args
	var fps=15 if 'slow-render' in args else 60
	var app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/tmp/eagle-sweep-prefs.cfg'
	root.add_child(app)
	app.menu_view.get_node('TacticalTrial').pressed.emit()
	t=app.active_trial;t.set_process(false);r=t.rules
	r.units.clear()
	var directions={'east':Vector2.RIGHT,'west':Vector2.LEFT,'north_east':Vector2(.85,-.52),'north_west':Vector2(-.83,-.55)}
	var dir: Vector2=r.ground_basis.affine_inverse().basis_xform(directions[label]).normalized()
	var mid=Vector2(2170,800)
	r.spawn('legion','enemy',mid+dir*395)
	r.spawn('cavalry','ally',mid-dir*395)
	var b=r.units[0];var a=r.units[1]
	b.heading=dir.orthogonal();b.order='hold';a.heading=dir;a.order='hold'
	t.field.debug_first_contact=mark
	t.set_camera(r.projection*mid-Vector2(960,556))
	t.contact_audio_started.connect(func(c):cues.append(c))
	t.refresh();t.start_button.pressed.emit()
	var trace=FileAccess.open(directory+label+('-15' if fps==15 else '-audit' if mark else '')+'.jsonl',FileAccess.WRITE)
	if trace==null:push_error('Could not create contact trace');quit(1);return
	var hits=0
	var hit_frame=-1
	for f in int(7.5*fps):
		if f==int(.2*fps):click(screen(a),MOUSE_BUTTON_LEFT)
		if f==int(.4*fps):
			click(screen(b),MOUSE_BUTTON_RIGHT)
			check(a.order=='attack' and a.target_id==b.id,'Player focus order')
		var old_hp: float=b.hp
		t._process(1./fps)
		var row={'f':f,'a':sample(a),'b':sample(b)}
		for e in t.field.effects:
			if e.age!=0 or not e.has('contact'):continue
			hits+=1
			var c: Dictionary=e.contact
			var p: Vector2=r.projection*c.pos-t.camera_offset
			check(c.attacker==a.id and c.target==b.id and c.charge_id>0 and c.speed>200,'Qualified, identified contact')
			check(is_same(c,a.last_contact) and is_same(c,b.contact_motion.contact) and cues.size()==1 and is_same(c,cues[0]),'One shared contact for reaction and main audio')
			check(is_equal_approx(old_hp-b.hp,e.damage),'Single budget equals HP delta')
			row.hit={'rider':c.rider_slot,'soldier':c.defender_slot,'p':[p.x,p.y],'fraction':c.fraction,'speed':c.speed,
				'charge_id':c.charge_id,'attacker':c.attacker,'target':c.target,'dir':[c.direction.x,c.direction.y],
				'rider_bearing':c.rider_bearing,'defender_bearing':c.defender_bearing,'rider_cell':c.rider_cell,'defender_cell':c.defender_cell,
				'damage':e.damage,'time':c.time,'audio':cues.size()}
			hit_frame=f
			print('CONTACT ',label,' display frame ',f,' ',row.hit)
			if mark:
				t.field.queue_redraw()
				await process_frame
				RenderingServer.force_draw()
				root.get_texture().get_image().save_png(OUT+label+'-point.png')
		trace.store_line(JSON.stringify(row))
		await process_frame
	trace.close()
	check(hits==1 and cues.size()==1 and hit_frame>=0,'One charge budget and one primary sound')
	print('First contact failures: ',failed)
	quit(1 if failed else 0)
