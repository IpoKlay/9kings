extends SceneTree
## Local controlled comparison. This is not an extracted original-game state.
const OUT='res://../output/charge-priority-2026-11-07/'
var failures=0
func _initialize():call_deferred('run')
func check(ok: bool,note: String):
	if not ok:failures+=1;push_error(note)
func vec(p: Vector2) -> Array:return [p.x,p.y]
func state(u) -> Array:
	var result=[]
	for slot in u.soldiers.size():
		var s=u.soldiers[slot]
		result.append({'slot':slot,'p':vec(s.position),'hp':s.hp,'heading':vec(s.heading),'order':s.personal_order,'charging':s.has('charge_run'),'wall':s.get('shield_wall',false)})
	return result
func run():
	var args=OS.get_cmdline_user_args()
	var mode=args[0] if args.size()>0 else 'side'
	var fps=int(args[1]) if args.size()>1 else 60
	var angle=deg_to_rad(float(args[2])) if args.size()>2 else 0.
	var name='%s-%d-%d'%[mode,fps,roundi(rad_to_deg(angle))]
	var out=OUT+name+'/'
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-charge-matrix.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit()
	var t=app.active_trial;t.set_process(false);app.sound.enabled=false;t.field.clean_capture=true
	var r=t.rules;r.units.clear();r.next_id=0
	var origin=Vector2(1700,1600);var axis=Vector2.RIGHT.rotated(angle);var across=axis.orthogonal()
	r.spawn('spear' if mode=='pikes' else 'legion','ally',origin)
	r.spawn('cavalry','enemy',origin-axis*440.)
	var wall=r.units[0];var horses=r.units[1]
	for u in r.units:
		u.order='hold'
		for slot in u.soldiers.size():r.Charges.detach(r,u,slot)
	check(wall.soldiers.size()==10 and horses.soldiers.size()==8,'Ten defenders and eight light cavalry')
	var tangent=-axis if mode=='side' else across
	for slot in wall.soldiers.size():
		wall.soldiers[slot].position=origin+tangent*(-130.+260.*slot/9.)
		wall.soldiers[slot].heading=tangent.orthogonal()
	for slot in horses.soldiers.size():
		horses.soldiers[slot].position=origin-axis*440.+across*(float(slot)-3.5)*28.
		horses.soldiers[slot].heading=axis
	t.refresh();t.start_button.pressed.emit()
	var keys=r.Soldiers.group_members([wall]);var plan=r.Walls.layout(r,keys,origin-tangent*130.,origin+tangent*130.)
	check(plan.size()==10 and plan.values().all(func(s):return s.rank==0),'Actual F layout remains a single rank')
	r.Walls.place(r,plan)
	for i in 600:
		t._process(1./60.)
		if wall.soldiers.all(func(s):return s.personal_order=='hold' and s.position.distance_to(s.wall_slot)<3.):break
	check(wall.soldiers.all(func(s):return s.shield_wall and s.personal_order=='hold' and s.position.distance_to(s.wall_slot)<3.),'Every defender is settled before the charge')
	check(wall.hp==wall.max_hp and horses.hp==horses.max_hp,'No uncommanded contact during setup')
	t.set_camera(origin-axis*150.-Vector2(960,540)/t.zoom)
	t.get_node('BattleHUD').hide()
	t.refresh();root.gui_disable_input=true;t.set_process_input(false);t.set_process_unhandled_input(false)
	var riders=r.Soldiers.group_members([horses]);var initial={'horses':state(horses),'defenders':state(wall)}
	var trace=FileAccess.open(out+'frames.jsonl',FileAccess.WRITE)
	var first=-1.;var contacts=[];var crossings={};var after_two={};var starts=0.;var peak=0.
	for frame in fps*8:
		if frame==fps:
			starts=r.elapsed
			check(r.Charges.issue(r,riders,origin+axis*250.,'enemy'),'All eight riders accept C through the shared command API')
			check(horses.soldiers.all(func(s):return s.has('charge_run')),'Every rider begins with an independent charge')
		t._process(1./fps)
		for e in t.field.effects:
			if e.get('personal_charge',false) and e.age==0:
				if first<0:first=r.elapsed-starts
				contacts.append({'time':r.elapsed-starts,'rider':e.attacker_slot,'target':e.target_slot,'damage':e.damage})
		t.field.effects.clear()
		for slot in horses.soldiers.size():
			var p: Vector2=horses.soldiers[slot].position
			if (p-origin).dot(axis)>10. and not crossings.has(slot):crossings[slot]=r.elapsed-starts
		for slot in wall.soldiers.size():peak=maxf(peak,wall.soldiers[slot].position.distance_to(plan[Vector2i(wall.id,slot)].goal))
		var now={'frame':frame,'time':r.elapsed-starts,'horses':state(horses),'defenders':state(wall)}
		trace.store_line(JSON.stringify(now))
		if first>=0 and after_two.is_empty() and r.elapsed-starts>=first+2.:after_two=now
		if DisplayServer.get_name()!='headless':
			await process_frame;await RenderingServer.frame_post_draw
			if frame in [fps-1,3*fps,4*fps,5*fps,7*fps]:root.get_texture().get_image().save_png(out+'frame-%04d.png'%frame)
		elif frame%60==0:await process_frame
	trace.close()
	check(not contacts.is_empty(),'At least one actual charge contact is observed')
	check(horses.soldiers.all(func(s):return not s.has('charge_run')),'All charges end within the finite observation')
	var pairs=[]
	for hit in contacts:
		var pair=Vector2i(hit.rider,hit.target);check(not pair in pairs,'One charge damage per rider and victim');pairs.append(pair)
	var ends=[]
	for s in horses.soldiers:
		var e=s.get('charge_end',{});ends.append({'reason':e.get('reason',''), 'time':e.get('time',0.)-starts,'p':vec(e.get('position',s.position))})
	var report={'scenario':mode,'fps':fps,'angle':rad_to_deg(angle),'zoom':t.zoom,'failures':failures,'initial':initial,'first_contact':first,'contacts':contacts,'crossings':crossings,'peak_slot_distance':peak,'two_seconds_after_hit':after_two,'ends':ends,'final':{'horses':state(horses),'defenders':state(wall)},'limits':['Local deterministic fixture, not an original-game replay','Same rider starts and command; only defender type/facing differs','Crossing is past the centre plane, not proof that a whole formation was pierced','Contact times have render-sampling resolution; physics uses the existing fixed step']}
	FileAccess.open(out+'report.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
	print(name,': ',contacts.size(),' hits, ',crossings.size(),' riders crossed centre, failures=',failures)
	t.closed.emit();app.queue_free();await process_frame;quit(1 if failures else 0)
