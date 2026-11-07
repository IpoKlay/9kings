extends SceneTree
var OUT='res://../output/sword-banner-reference/dragon/runtime/'
var rush=false
var failures=0
var rendered=0
func _initialize():
	rush='rush' in OS.get_cmdline_user_args()
	if rush:OUT='res://../output/sword-banner-reference/dragon/rush/'
	call_deferred('run')
func click(p:Vector2):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;root.push_input(e,true)
func snap(name:String):root.get_texture().get_image().save_png(OUT+name+'.png')
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-dragon-capture.cfg';root.add_child(app)
	await RenderingServer.frame_post_draw
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	for i in t.rules.config.loadouts.guard.size():
		if t.rules.guard_variant=='dragon':break
		click(t.loadout_buttons.guard.get_global_rect().get_center())
	for frame in 30:await RenderingServer.frame_post_draw
	snap('loadout-zh');app.language='en';t.refresh();await RenderingServer.frame_post_draw;snap('loadout-en');app.language='zh';t.refresh()
	click(t.combined_button.get_global_rect().get_center());t.refresh();await RenderingServer.frame_post_draw;snap('normal-deployment')
	var r=t.rules;r.units.clear();r.config.types.guard.files=1;r.config.unit_variants.dragon.hp=800.
	r.contact_profiles.guard=r.Contact.profile('guard',r.config.types.guard,true)
	for kind in r.reserve:r.reserve[kind]=0
	r.spawn('guard','ally',Vector2(1050,1450),'dragon');r.spawn('legion','enemy',Vector2(1050,800));r.spawn('archer','enemy',Vector2(1050,500))
	for u in r.units:u.order='hold' if u.side=='ally' else 'auto'
	t.set_camera(r.projection*Vector2(1050,1050)-Vector2(960,540)/t.zoom);t.refresh();click(t.start_button.get_global_rect().get_center());t.refresh()
	var dragon=r.units[0];var strikes=0;var contacts=[];var arrows=0;var end_frame=-1;var ai_cohorts=0;var breath_frame=-1
	var trace=FileAccess.open(OUT+'frames.jsonl',FileAccess.WRITE)
	for frame in 6000:
		if frame==60 and not rush:click(t.assault_button.get_global_rect().get_center())
		if frame==(60 if rush else 240):
			click(t.roster[0].get_global_rect().get_center());var e=InputEventKey.new();e.physical_keycode=KEY_C;e.pressed=true;root.push_input(e,true)
			click((r.projection*Vector2(1050,500)-t.camera_offset)*t.zoom)
			if not dragon.soldiers[0].has('charge_run'):failures+=1;push_error('Dragon C input did not create a charge')
		if frame==(61 if rush else 241):root.gui_disable_input=true;t.set_process_input(false);t.set_process_unhandled_input(false)
		t._process(1./60);ai_cohorts=maxi(ai_cohorts,r.enemy_director.cohorts.size())
		for volley in r.volleys:
			if volley.age==0:arrows+=1
		for event in t.field.effects:
			if event.age!=0 or event.get('attacker',-1)!=dragon.id or event.get('damage',0.)<=0:continue
			if event.get('personal_charge',false):contacts.append({'frame':frame,'target':event.target,'slot':event.target_slot,'damage':event.damage})
			else:strikes+=1
		if frame%15==0:trace.store_line(JSON.stringify({'frame':frame,'time':r.elapsed,'phase':r.phase,'dragon':dragon.soldiers[0],'enemy_hp':r.units.slice(1).map(func(u):return u.hp)}));trace.flush()
		await RenderingServer.frame_post_draw
		if breath_frame<0 and t.field.dragon_flame_strength(dragon.soldiers[0].attack_age)>.8:
			breath_frame=frame;snap('breath')
		if frame in [30,180,239,240,241,300,480,720,1200,1800] or frame==end_frame:snap('frame-%04d'%frame)
		rendered+=1
		if r.phase!='battle' and end_frame<0:end_frame=frame+120
		if frame==end_frame:break
	trace.close()
	if contacts.is_empty() or strikes==0 or arrows==0 or ai_cohorts==0 or breath_frame<0:failures+=1;push_error('Missing real dragon attack, charge or enemy arrows')
	var outcome={'phase':r.phase,'time':r.elapsed,'allies':r.strength('ally'),'enemies':r.strength('enemy')}
	if r.phase not in ['victory','defeat']:failures+=1;push_error('Dragon battle did not conclude')
	t.retry();t.refresh();for frame in 30:await RenderingServer.frame_post_draw
	var clean=t.rules.guard_variant=='' and t.rules.config.types.guard.files==10 and t.rules.casualties.is_empty()
	if not clean:failures+=1
	FileAccess.open(OUT+'report.json',FileAccess.WRITE).store_string(JSON.stringify({'failures':failures,'fixture':'Normal menu/config/deployment preview, then one800HP dragon vs ten swordsmen and ten archers. Only guard visual count/aggregate HP adjusted for one-person fixture; per-unit stats unchanged, enemy strategic AI active. Actual C input; delayed scenario also uses All Attack. Reserves zeroed for settlement.','breath_frame':breath_frame,'charge_order_frame':60 if rush else 240,'ai_cohorts':ai_cohorts,'strikes':strikes,'charge_contacts':contacts,'enemy_arrows':arrows,'outcome':outcome,'retry_clean':clean,'expected_movie_frames':rendered+65,'normal_speed':true,'quiet':true},'\t'))
	print('Dragon capture: ',strikes,' ordinary hits, ',contacts.size(),' charge contacts, failures=',failures)
	t.closed.emit();app.queue_free();await RenderingServer.frame_post_draw;quit(1 if failures else 0)
