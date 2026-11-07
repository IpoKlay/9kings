extends SceneTree
const OUT='res://../output/sword-banner-reference/human-roster/runtime/'
const ARMY=[['guard','heavy',450.,1350.],['spear','veteran_spearman',1050.,1350.],['legion','noble_son',1650.,1350.],['legion','peasant',450.,1700.],['archer','crossbow',1050.,1700.],['cavalry','knight',1650.,1700.]]
var failures=0
func _initialize():call_deferred('run')
func click(p: Vector2,button: MouseButton=MOUSE_BUTTON_LEFT):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=button;e.pressed=down;root.push_input(e,true)
func snap(name: String):root.get_texture().get_image().save_png(OUT+name+'.png')
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-human-capture.cfg';root.add_child(app)
	await RenderingServer.frame_post_draw
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	for kind in ['legion','guard','spear','archer','archer','cavalry','cavalry']:click(t.loadout_buttons[kind].get_global_rect().get_center())
	for frame in 30:await RenderingServer.frame_post_draw
	snap('loadout-zh');app.language='en';t.refresh();await RenderingServer.frame_post_draw;snap('loadout-en');app.language='zh';t.refresh()
	click(t.combined_button.get_global_rect().get_center());await RenderingServer.frame_post_draw;snap('normal-deployment')
	var r=t.rules;r.units.clear()
	for side in ['ally','enemy']:
		for row in ARMY:r.spawn(row[0],side,Vector2(row[2],row[3] if side=='ally' else 2100.-row[3]),row[1])
	for u in r.units:u.order='hold'
	t.set_camera(r.projection*Vector2(1050,1050)-Vector2(960,540)/t.zoom)
	t.refresh();click(t.start_button.get_global_rect().get_center());t.refresh()
	var strikes={};var charge_contacts=0;var arrows=0;var knight=r.units[5]
	var trace=FileAccess.open(OUT+'frames.jsonl',FileAccess.WRITE)
	for frame in 900:
		if frame==60:click(t.assault_button.get_global_rect().get_center())
		if frame==180:
			click(t.roster[5].get_global_rect().get_center());var e=InputEventKey.new();e.physical_keycode=KEY_C;e.pressed=true;root.push_input(e,true)
			click((r.projection*Vector2(1650,650)-t.camera_offset)*t.zoom)
			if not knight.soldiers.any(func(s):return s.has('charge_run')):failures+=1;push_error('Knight C input failed')
		if frame==181:root.gui_disable_input=true;t.set_process_input(false);t.set_process_unhandled_input(false)
		t._process(1./60)
		# Volleys are rendered directly, not copied into field effects. Count each new projectile once.
		for projectile in r.volleys:
			if projectile.age==0.:arrows+=1
		for event in t.field.effects:
			if event.age!=0:continue
			if event.get('personal_charge',false):charge_contacts+=1
			if event.get('damage',0.)>0:
				var u=r.units.filter(func(u):return u.id==event.get('attacker',-1))
				if not u.is_empty():strikes[u[0].archetype]=strikes.get(u[0].archetype,0)+1
		if frame%15==0:trace.store_line(JSON.stringify({'frame':frame,'time':r.elapsed,'phase':r.phase,'units':r.units.map(func(u):return {'id':u.id,'type':u.archetype,'hp':u.hp,'pos':u.pos})}))
		await RenderingServer.frame_post_draw
		if frame in [30,240,480,720,899]:snap('frame-%04d'%frame)
	trace.close()
	if arrows==0 or charge_contacts==0:failures+=1;push_error('Missing actual crossbow shots or knight charge contacts')
	t.retry();t.refresh();for frame in 30:await RenderingServer.frame_post_draw
	var clean=t.loadout_buttons.keys().all(func(k):return t.rules.selected_variant(k)=='') and t.rules.casualties.is_empty()
	if not clean:failures+=1
	FileAccess.open(OUT+'report.json',FileAccess.WRITE).store_string(JSON.stringify({'failures':failures,'fixture':'Normal menu/loadout controls/deployment preview, then controlled six-variant mirror armies; enemy strategic AI active; actual All Attack and knight C inputs.','normal_speed':true,'quiet':true,'melee_strikes':strikes,'arrows':arrows,'charge_contacts':charge_contacts,'retry_clean':clean,'expected_movie_frames':965},'\t'))
	print('Human capture: strikes=',strikes,' arrows=',arrows,' charges=',charge_contacts,' failures=',failures)
	t.closed.emit();app.queue_free();await RenderingServer.frame_post_draw;quit(1 if failures else 0)
