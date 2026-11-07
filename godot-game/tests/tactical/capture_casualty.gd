extends SceneTree
## Supplemental real strike: initial legion HP300 -> one visible casualty on charge.
## -- absolute/output/directory ; Movie Maker 60 FPS,20 seconds.
var t
var r
var failures=0
func _initialize():call_deferred('run')
func check(ok: bool,note: String):
	if not ok:failures+=1;push_error(note)
func click(p: Vector2,button: MouseButton):
	for down in [true,false]:
		var e=InputEventMouseButton.new()
		e.position=p;e.global_position=p;e.button_index=button;e.pressed=down
		root.push_input(e,true)
func screen(u: Dictionary) -> Vector2:return (r.projection*u.pos-t.camera_offset-Vector2(0,20))*t.zoom
func snap(path: String):
	if DisplayServer.get_name()=='headless':return
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(path)
func run():
	var args=OS.get_cmdline_user_args()
	var out=args[0].trim_suffix('/')+'/' if not args.is_empty() else ProjectSettings.globalize_path('res://../output/impact-upgrade/casualty/')
	DirAccess.make_dir_recursive_absolute(out)
	var app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/tmp/eagle-casualty-prefs.cfg'
	root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit()
	t=app.active_trial;t.set_process(false);r=t.rules
	r.units.clear()
	var approach=Vector2(-.94,-.342).normalized()
	var center=Vector2(1050,900)
	r.spawn('legion','enemy',center)
	r.spawn('cavalry','ally',center-approach*800)
	var b=r.units[0];var a=r.units[1]
	b.heading=Vector2.UP;b.formation_heading=b.heading;b.order='hold';b.hp=300.
	# Start wounded; these missing soldiers were not killed during this recorded battle.
	b.visible_slots=range(r.Contact.count(b,r.config.types.legion))
	a.heading=approach;a.formation_heading=approach;a.order='hold'
	t.zoom=1.0;t.set_camera(r.projection*center-Vector2(960,450))
	t.refresh();t.start_button.pressed.emit()
	var trace=FileAccess.open(out+'casualty.jsonl',FileAccess.WRITE)
	var hit=-1
	var corpse={}
	var snapshots={}
	var seen_at_8=false
	var gone_at_12=false
	for frame in 1200:
		var photograph=''
		if frame==12:click(screen(a),MOUSE_BUTTON_LEFT)
		if frame==24:
			click(screen(b),MOUSE_BUTTON_RIGHT)
			check(a.order=='attack','Real focus command issued')
		if hit>=0 and frame==hit+1:
			check(r.command([a.id],'move',Vector2(1800,1300)),'Withdraw after the single strike')
		t._process(1./60)
		for effect in t.field.effects:
			if effect.age==0 and effect.get('mounted_contact',false) and effect.get('attacker',-1)==a.id:
				hit=frame
				check(absf(effect.damage-71.4)<.001 and absf(b.hp-228.6)<.001,'Real unchanged charge budget creates visible loss')
				var bodies=r.casualties.filter(func(body):return body.unit_id==b.id)
				check(bodies.size()==1,'Exactly one visible loss becomes exactly one body')
				if not bodies.is_empty():corpse=bodies[0].duplicate(true)
		if not corpse.is_empty():
			var age: float=r.elapsed-corpse.time
			var still=r.casualties.any(func(body):return body.id==corpse.id)
			if age>=8. and age<8.1:seen_at_8=seen_at_8 or still
			if age>=12.1:gone_at_12=gone_at_12 or not still
			var body=r.casualties.filter(func(record):return record.id==corpse.id)
			if not body.is_empty():check(body[0].foot==corpse.foot,'Ground body anchor remains fixed')
			for timing in [0.,.18,.5,2.,8.,12.2]:
				if age>=timing and not snapshots.has(timing):
					snapshots[timing]=true
					photograph=out+'casualty-%04d.png'%roundi(timing*100)
		trace.store_line(JSON.stringify({'frame':frame,'time':r.elapsed,'target_hp':b.hp,'target_visible':r.Contact.count(b,r.config.types.legion),'bodies':r.casualties}))
		await process_frame
		if not photograph.is_empty():snap(photograph)
	check(hit>=0 and not corpse.is_empty(),'A real charge generated the recorded casualty')
	check(seen_at_8 and gone_at_12,'Body remains for eight seconds and expires after twelve')
	trace.close()
	var summary={'initial_hp':300,'post_charge_hp':228.6,'impact_frame':hit,'body':corpse,'seen_at_8':seen_at_8,'gone_after_12':gone_at_12,'failures':failures}
	FileAccess.open(out+'summary.json',FileAccess.WRITE).store_string(JSON.stringify(summary,'\t'))
	print('Casualty capture: ',summary)
	quit(1 if failures else 0)
