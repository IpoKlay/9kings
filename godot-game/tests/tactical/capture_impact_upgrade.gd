extends SceneTree
## Fixed inputs; works against the archived package and the current project.
## -- scenario absolute/output/directory [near] [quiet]
const DT=1./60
var t
var r
var failures=0
func _initialize():call_deferred('run')
func check(ok: bool,note: String):
	if not ok:failures+=1;push_error(note)
func click(p: Vector2,button: MouseButton,double: bool=false):
	for down in [true,false]:
		var e=InputEventMouseButton.new()
		e.position=p;e.global_position=p;e.button_index=button;e.pressed=down;e.double_click=double
		root.push_input(e,true)
func screen(u: Dictionary) -> Vector2:
	return (r.projection*u.pos-t.camera_offset-Vector2(0,20))*t.zoom
func point(v: Vector2) -> Array:return [v.x,v.y]
func sample(u: Dictionary) -> Dictionary:
	var slots=[]
	var feet=r.Contact.feet(r,u)
	for i in feet.size():
		var shift: Vector2=r.Contact.body_shift(u,i,r.elapsed)
		slots.append({'id':i,'foot':point(r.projection*u.pos+feet[i]+shift),'shift':point(shift),
			'present':r.Contact.present(u,i,r.Contact.count(u,r.config.types[u.kind]))})
	return {'id':u.id,'kind':u.kind,'pos':point(u.pos),'heading':point(u.heading),'hp':u.hp,'morale':u.morale,
		'pace':u.get('pace',0),'gait':u.get('gait',''),'slots':slots,'states':u.get('slot_states',{}),
		'penetration':u.get('penetration',{}),'rider_contacts':u.get('rider_contacts',{}),'slot_distance':u.get('slot_distances',{})}
func photograph(path: String):
	if DisplayServer.get_name()=='headless':return
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(path)
func run():
	var args=OS.get_cmdline_user_args()
	var label=args[0] if not args.is_empty() else 'side'
	var out=args[1].trim_suffix('/')+'/' if args.size()>1 else ProjectSettings.globalize_path('res://../output/impact-upgrade/')
	DirAccess.make_dir_recursive_absolute(out)
	var app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/tmp/eagle-impact-upgrade-prefs.cfg'
	root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit()
	t=app.active_trial;t.set_process(false);r=t.rules
	r.units.clear()
	var side=label=='side'
	var approach=Vector2(-.94,-.342).normalized() if side else Vector2.UP
	var center=Vector2(1050,900)
	r.spawn('legion' if side else 'guard' if label=='shield' else 'spear','enemy',center)
	r.spawn('cavalry','ally',center-approach*800)
	var b=r.units[0];var a=r.units[1]
	b.heading=Vector2.UP if side else Vector2.DOWN;b.formation_heading=b.heading;b.order='hold'
	a.heading=approach;a.formation_heading=approach;a.order='hold'
	t.reset_camera()
	# The square battlefield opens over deployment; fixtures engage farther north.
	t.set_camera(r.projection*(center-approach*230)-Vector2(960,540)/t.zoom)
	if 'near' in args:
		t.zoom=1.0
		t.set_camera(r.projection*(center-approach*150)-Vector2(960,540))
	if 'quiet' in args:
		app.sound.enabled=false
		t.field.clean_capture=true
	t.refresh();t.start_button.pressed.emit()
	var trace=FileAccess.open(out+label+'.jsonl',FileAccess.WRITE)
	var hit_frame=-1
	var hit_count=0
	var hit_summary={}
	for frame in 600:
		if frame==12:click(screen(a),MOUSE_BUTTON_LEFT,true)
		if frame==24:
			click(screen(b),MOUSE_BUTTON_RIGHT)
			check(a.order=='attack' and a.target_id==b.id,'Real focus command reaches selected cavalry')
		var hp: float=b.hp
		t._process(DT)
		var row={'frame':frame,'time':r.elapsed,'a':sample(a),'b':sample(b),'zoom':t.zoom}
		for e in t.field.effects:
			if e.age==0 and e.get('mounted_contact',false) and e.get('attacker',-1)==a.id:
				hit_count+=1
				hit_frame=frame
				hit_summary={'frame':frame,'time':r.elapsed,'damage':hp-b.hp,'morale':b.morale,
					'sector':e.sector,'speed':e.get('contact',{}).get('speed',0),'point':point(e.pos)}
				row.hit=hit_summary
				print('IMPACT ',label,' ',JSON.stringify(hit_summary))
		if 'quiet' in args:t.field.effects.clear()
		trace.store_line(JSON.stringify(row))
		await process_frame
		if frame==30:photograph(out+label+'-approach.png')
		if hit_frame>=0 and frame in [hit_frame,hit_frame+8,hit_frame+30,hit_frame+120,hit_frame+240]:
			photograph(out+label+'-after-%03d.png'%(frame-hit_frame))
	trace.close()
	check(hit_count==1 and hit_frame>=0,'Exactly one mounted first strike')
	var summary={'scenario':label,'hit':hit_summary,'hits':hit_count,'failures':failures,'default_zoom':t.zoom,'simulation_seconds':r.elapsed}
	FileAccess.open(out+label+'-summary.json',FileAccess.WRITE).store_string(JSON.stringify(summary,'\t'))
	print('Impact capture complete: ',summary)
	quit(1 if failures else 0)
