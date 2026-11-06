extends SceneTree
var t
var r
var app
func _initialize():call_deferred('run')
func click(p:Vector2,button:MouseButton):
	for down in [true,false]:
		var e=InputEventMouseButton.new()
		e.button_index=button;e.pressed=down;e.position=p;e.global_position=p
		root.push_input(e,true)
func run():
	var args=OS.get_cmdline_user_args()
	var scenario=args[0]
	var out=args[1]
	var fps=int(args[2]) if args.size()>2 else 30
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/tmp/eagle-breach-film.cfg'
	root.add_child(app)
	app.menu_view.get_node('TacticalTrial').pressed.emit()
	t=app.active_trial;t.set_process(false);r=t.rules
	r.units.clear()
	var mid=Vector2(2170,800)
	var axis:=Vector2(.85,-.52).normalized()
	var dir:Vector2=r.ground_basis.affine_inverse().basis_xform(axis).normalized()
	var shield=scenario=='wall'
	var enemy_pos=mid+dir*395
	var start=mid-dir*395
	if shield:
		axis=Vector2.DOWN
		dir=r.ground_basis.affine_inverse().basis_xform(axis).normalized()
		enemy_pos=mid+dir*270
		start=mid-dir*270+r.ground_basis.affine_inverse().basis_xform(Vector2(-112,0))
	r.spawn('spear' if scenario=='pikes' else 'guard' if shield else 'legion','enemy',enemy_pos)
	r.spawn('guard' if shield else 'cavalry','ally',start)
	var b=r.units[0];var a=r.units[1]
	b.heading=dir.orthogonal() if scenario=='flank' else -dir
	b.order='hold';a.heading=dir;a.order='hold'
	t.set_camera(r.projection*mid-Vector2(960,556))
	t.start_button.pressed.emit()
	for node in t.get_children():
		if node is Control and not node is TextureRect:node.hide()
	app.sound.enabled=false
	if 'clean_capture' in t.field:t.field.clean_capture=true
	var passage:Dictionary={}
	var trace=FileAccess.open(out,FileAccess.WRITE)
	for f in range(fps*(9 if not shield else 12)):
		if f==roundi(.2*fps):click(r.projection*a.pos-t.camera_offset-Vector2(0,35),MOUSE_BUTTON_LEFT)
		if f==roundi(.4*fps):
			if shield:r.command([a.id],'move',b.pos+r.ground_basis.affine_inverse().basis_xform(Vector2(-112,0))+dir*85)
			else:r.command([a.id],'attack',b.pos,b.id)
		t._process(1./fps)
		for node in t.get_children():
			if node is Control and not (node is TextureRect and node.texture is ViewportTexture):node.hide()
		var affected={}
		var attacker_slots={}
		for j in 60:
			var v:Vector2=r.Contact.body_shift(b,j,r.elapsed)
			if v.length()>1:affected[j]=[snappedf(v.x,.1),snappedf(v.y,.1)]
		for j in int(r.config.types[a.kind].soldiers):
			var v:Vector2=r.Contact.body_shift(a,j,r.elapsed)
			if v.length()>1:attacker_slots[j]=[snappedf(v.x,.1),snappedf(v.y,.1)]
		var pos:Vector2=r.projection*a.pos
		var row={'frame':f,'time':r.elapsed,'pos':[pos.x,pos.y],'hp':b.hp,'gait':a.get('gait',''),'pace':a.get('pace',0),'affected':affected,'riders':attacker_slots,'events':[]}
		for e in t.field.effects:
			if e.age==0 and e.get('attacker',-1)==a.id:
				row.events.append([e.kind,e.get('damage',0),e.get('contact',{}).get('speed',a.get('pace',0)*139)])
		if a.has('penetration'):passage=a.penetration
		if not passage.is_empty():
			var lead: int=r.contact_profiles.cavalry.feet.find(passage.rider)
			var feet: Vector2=r.projection*a.pos+r.contact_profiles.cavalry.feet[lead]+r.Contact.body_shift(a,lead,r.elapsed)
			var origin: Vector2=passage.origin+passage.rider
			row.lane={'front':passage.travel,'entry_slot':r.contact_profiles[b.kind].feet.find(passage.entry-r.projection*b.pos),
				'lead_slot':lead,'lead_progress':(feet-origin).dot(passage.axis),'screen':[(feet.x-t.camera_offset.x)/1920.,(feet.y-t.camera_offset.y)/1080.],
				'centre_progress':(r.projection*a.pos-passage.origin).dot(passage.axis),'active':a.has('penetration'),'parts':passage.dislodged.keys()}
		if a.has('penetration'):row.travel=a.penetration.travel
		trace.store_line(JSON.stringify(row))
		await process_frame
	trace.close()
	t.closed.emit();app.queue_free()
	await process_frame
	print("Captured ",scenario," ",a.order)
	quit()
