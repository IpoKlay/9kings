extends SceneTree
const OUT='res://../output/sword-banner-reference/projectile-motion/runtime/'
var failures=0
func _initialize():call_deferred('run')
func click(point:Vector2):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;root.push_input(e,true)
func snap(name:String):root.get_texture().get_image().save_png(OUT+name+'.png')
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-projectile-capture.cfg';root.add_child(app)
	await RenderingServer.frame_post_draw
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	for frame in 30:await RenderingServer.frame_post_draw
	click(t.combined_button.get_global_rect().get_center());t.refresh();await RenderingServer.frame_post_draw;snap('normal-deployment')
	var r=t.rules;r.units.clear()
	for kind in r.config.types:
		if not r.config.types[kind].has('individual'):continue
		r.config.types[kind].files=1;r.config.types[kind].hp=r.config.types[kind].individual.hp
		r.contact_profiles[kind]=r.Contact.profile(kind,r.config.types[kind],true)
	for kind in r.reserve:r.reserve[kind]=0
	r.spawn('archer','ally',Vector2(650,750));r.spawn('cavalry','enemy',Vector2(950,750))
	r.spawn('archer','ally',Vector2(650,1200));r.spawn('archer','ally',Vector2(900,1200));r.spawn('legion','enemy',Vector2(1000,1200))
	r.spawn('siege','ally',Vector2(650,1650));r.spawn('cavalry','enemy',Vector2(1050,1650))
	for u in r.units:u.order='hold'
	var runner=r.units[1];var victim=r.units[4];var dodger=r.units[6]
	r.hurt(victim,85.,'',0.,0)
	t.set_camera(r.projection*Vector2(1050,1200)-Vector2(960,540)/t.zoom);t.refresh();click(t.start_button.get_global_rect().get_center());t.refresh();r.enemy_director.active=false
	root.gui_disable_input=true;t.set_process_input(false);t.set_process_unhandled_input(false)
	var launched=0;var cancelled=0;var impacts=0;var stone_impacts=0;var active={};var sample=[]
	var trace=FileAccess.open(OUT+'frames.jsonl',FileAccess.WRITE)
	var direct: Array[Vector2]=[]
	for frame in 600:
		if frame==12:r.Soldiers.command(r,[Vector2i(runner.id,0)],'move',Vector2(1400,650),-1,-1,direct,true,'enemy')
		if frame==45:r.Soldiers.command(r,[Vector2i(dodger.id,0)],'move',Vector2(1800,1650),-1,-1,direct,true,'enemy')
		t._process(1./60)
		var current={}
		for shot in r.volleys:
			if not shot.has('capture_id'):launched+=1;shot.capture_id=launched
			current[shot.capture_id]=shot
		for id in active:
			if current.has(id):continue
			var shot:Dictionary=active[id]
			if shot.target==victim.id and victim.hp<=0 and not shot.point.is_equal_approx(shot.pos):cancelled+=1
		active=current
		for event in t.field.effects:
			if event.age!=0:continue
			if event.kind=='arrow_impact':impacts+=1
			if event.kind=='stone_impact':stone_impacts+=1
		var row={'frame':frame,'time':r.elapsed,'arrows':r.volleys.map(func(s):return {'id':s.capture_id,'point':[s.point.x,s.point.y],'target':[s.pos.x,s.pos.y],'speed':s.speed}),'stones':r.stones.map(func(s):return {'age':s.age,'flight':s.flight,'origin':s.from,'landing':s.pos}),'runner_hp':runner.hp,'victim_hp':victim.hp,'dodger_hp':dodger.hp}
		trace.store_line(JSON.stringify(row))
		await RenderingServer.frame_post_draw
		if frame in [30,60,90,120,180,300,599]:snap('frame-%04d'%frame)
	trace.close()
	if launched<3 or cancelled<1 or impacts<1 or stone_impacts<1 or dodger.hp!=dodger.max_hp:failures+=1;push_error('Missing actual tracking/cancel/stone miss evidence')
	t.retry();t.refresh();for frame in 30:await RenderingServer.frame_post_draw
	var clean=t.rules.volleys.is_empty() and t.rules.stones.is_empty() and t.rules.config.types.archer.files==10
	if not clean:failures+=1
	FileAccess.open(OUT+'report.json',FileAccess.WRITE).store_string(JSON.stringify({'failures':failures,'fixture':'Normal menu/deployment preview then one-person controlled lanes: top moving cavalry target; middle wounded15HP target hit by near archer before far arrow; bottom cavalry leaves fixed stone landing. Scripted standard movement commands, enemy strategic AI disabled, per-person stats unchanged except middle wound. Normal speed, silent, default camera.','launched':launched,'cancelled_after_other_hit':cancelled,'arrow_impacts':impacts,'stone_impacts':stone_impacts,'dodger_hp':dodger.hp,'retry_clean':clean,'expected_movie_frames':664},'\t'))
	print('Projectile capture: ',launched,' launched, ',cancelled,' cancelled, ',stone_impacts,' stones, failures=',failures)
	t.closed.emit();app.queue_free();await RenderingServer.frame_post_draw;quit(1 if failures else 0)
