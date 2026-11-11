extends SceneTree
## Approximate ground-space reconstruction of the public browser recording.
## Overlapping feet are estimated from the image; original terrain/RNG are not reproduced.
const FEET=[[290,375],[300,365],[310,371],[309,350],[313,337],[334,327],[382,356],[416,356]]
var failures=0
func check(ok: bool,note: String):
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func run():
	var args=OS.get_cmdline_user_args()
	var fps=int(args[0]) if not args.is_empty() else 60
	var far='far' in args
	var mode='far' if far else 'near'
	var label='after' if 'after' in args else 'current'
	var out='res://../output/reference-contact-2026-11-10/%s/local-%s-%d/'%[label,mode,fps]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/tmp/eagle-reference-brace.cfg';root.add_child(app)
	# Reference fixture uses legacy unit stats independently of the economy menu.
	var t=load('res://scenes/tactical_trial.tscn').instantiate()
	t.rules=t.WhiteboardBattle.new(false);t.app=app;root.add_child(t);app.hide();t.set_process(false);app.sound.enabled=false;t.field.clean_capture=true
	var r=t.rules;r.units.clear();r.next_id=0
	var origin=Vector2(1050,900)
	# Team roles are reversed so defenders use the real player F formation API.
	r.spawn('legion','ally',origin);r.spawn('cavalry','enemy',origin-Vector2(620,0))
	var wall=r.units[0];var horses=r.units[1]
	wall.order='hold';horses.order='hold'
	check(wall.soldiers.size()==10 and horses.soldiers.size()==8,'Fixture must contain exactly ten swordsmen and eight light cavalry')
	for slot in wall.soldiers.size():
		r.Charges.detach(r,wall,slot)
		wall.soldiers[slot].position=origin+Vector2(0,66.-130.*slot/9.)
		wall.soldiers[slot].heading=Vector2.LEFT
	for slot in horses.soldiers.size():
		r.Charges.detach(r,horses,slot)
		horses.soldiers[slot].position=origin+(Vector2(FEET[slot][0],FEET[slot][1])-Vector2(650,360))*2.-Vector2(300 if far else 0,0)
		horses.soldiers[slot].heading=Vector2.RIGHT
	t.refresh();t.start_button.pressed.emit()
	var keys=[]
	for slot in wall.soldiers.size():keys.append(Vector2i(wall.id,slot))
	var plan=r.Walls.layout(r,keys,origin+Vector2(0,66),origin-Vector2(0,64))
	check(plan.size()==10,'F layout accepts all ten defenders')
	r.Walls.place(r,plan)
	for i in 120:t._process(1./60.)
	check(wall.soldiers.all(func(s):return s.shield_wall and s.personal_order=='hold' and s.position.distance_to(s.wall_slot)<3.),'All defenders settle in actual F slots before the charge')
	t.set_camera(r.projection*(origin-Vector2(240,0))-Vector2(960,540)/t.zoom)
	t.refresh();root.gui_disable_input=true;t.set_process_input(false);t.set_process_unhandled_input(false)
	var riders=[];var starts=[];var max_approach=0.
	for slot in horses.soldiers.size():
		riders.append(Vector2i(horses.id,slot));starts.append(horses.soldiers[slot].position)
		max_approach=maxf(max_approach,origin.x-horses.soldiers[slot].position.x)
	check((max_approach<r.config.individual_charge.max_range) != far,'Range preflight distinguishes valid and over-range fixtures')
	var first=-1.;var contacts=[];var crossing=[];var peak_open=0.;var run_start=0.
	var trace=FileAccess.open(out+'frames.jsonl',FileAccess.WRITE)
	for frame in fps*10:
		if frame==fps:
			run_start=r.elapsed
			check(r.Charges.issue(r,riders,origin+Vector2(280,0),'enemy'),'Eight enemy riders accept the normal charge command')
			check(horses.soldiers.all(func(s):return s.has('charge_run')),'Every selected rider starts charging')
		t._process(1./fps)
		for e in t.field.effects:
			if e.get('personal_charge',false) and e.age==0:
				if first<0:first=r.elapsed-run_start
				contacts.append({'seconds':r.elapsed-run_start,'attacker':e.attacker_slot,'target':e.target_slot,'damage':e.damage})
		t.field.effects.clear()
		for slot in horses.soldiers.size():
			if horses.soldiers[slot].position.x>origin.x+10. and not slot in crossing:crossing.append(slot)
		for slot in wall.soldiers.size():peak_open=maxf(peak_open,wall.soldiers[slot].position.distance_to(plan[Vector2i(wall.id,slot)].goal))
		trace.store_line(JSON.stringify({'frame':frame,'time':r.elapsed-run_start,'horses':horses.soldiers,'defenders':wall.soldiers}))
		if not DisplayServer.get_name()=='headless' and frame in [fps-1,fps*3,fps*4,fps*5]:
			RenderingServer.force_draw();root.get_texture().get_image().save_png(out+'frame-%04d.png'%frame)
		RenderingServer.force_draw();await process_frame
	trace.close()
	if not far:
		check(not contacts.is_empty(),'An active charge actually contacts the shield wall')
		check(first<r.config.individual_charge.max_range/r.config.individual_charge.speed,'First hit occurs before the charge duration expires')
		check(not crossing.is_empty(),'At least one rider crosses the original F line, as in the observed public build')
	var ends=[]
	for s in horses.soldiers:ends.append(s.get('charge_end',{}))
	var report={'fps':fps,'mode':mode,'failures':failures,'start_feet':starts,'line':origin,'max_approach':max_approach,'charge_range':r.config.individual_charge.max_range,'first_contact':first,'contact_time_resolution':1./fps,'contacts':contacts,'riders_crossed':crossing,'peak_slot_displacement':peak_open,'ends':ends,'limits':['Screen-picked approximate feet, not original state extraction','Team colors reversed; own art/projection and open local terrain','Original variable-rate screenshot timing is not a simulation trace','Contact times sampled at render-step end;30fps may round a hit up by one60Hz simulation step']}
	FileAccess.open(out+'report.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
	print('Reference brace ',mode,' fps=',fps,' contacts=',contacts.size(),' crossed=',crossing.size(),' failures=',failures)
	t.queue_free();app.queue_free();await process_frame;await create_timer(.15).timeout;quit(1 if failures else 0)
