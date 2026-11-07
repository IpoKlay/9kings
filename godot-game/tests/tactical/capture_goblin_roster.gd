extends SceneTree
const OUT='res://../output/sword-banner-reference/goblin-roster/runtime/'
const ARMY=[['legion','goblin_runt',220.,1350.],['legion','goblin_brat',630.,1350.],['spear','goblin_spiker',1040.,1350.],['guard','goblin_stabber',1450.,1350.],['guard','goblin_troll',1860.,1350.],['archer','goblin_archer',220.,1700.],['archer','goblin_slinger',630.,1700.],['cavalry','goblin_wolf_rider',1040.,1700.],['cavalry','goblin_wolf_skirmisher',1450.,1700.],['archer','goblin_shaman',1860.,1470.]]
var failures=0
func _initialize():call_deferred('run')
func click(p: Vector2,button: MouseButton=MOUSE_BUTTON_LEFT):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=button;e.pressed=down;root.push_input(e,true)
func snap(name: String):root.get_texture().get_image().save_png(OUT+name+'.png')
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-goblin-capture.cfg';root.add_child(app)
	await RenderingServer.frame_post_draw
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	for row in ARMY:
		for i in t.rules.config.loadouts[row[0]].size():
			if t.rules.selected_variant(row[0])==row[1]:break
			click(t.loadout_buttons[row[0]].get_global_rect().get_center())
	for frame in 30:await RenderingServer.frame_post_draw
	snap('loadout-zh');app.language='en';t.refresh();await RenderingServer.frame_post_draw;snap('loadout-en');app.language='zh';t.refresh()
	click(t.combined_button.get_global_rect().get_center());t.refresh();await RenderingServer.frame_post_draw;snap('normal-deployment')
	var r=t.rules;r.units.clear()
	for side in ['ally','enemy']:
		for row in ARMY:r.spawn(row[0],side,Vector2(row[2],row[3] if side=='ally' else 2100.-row[3]),row[1])
	for u in r.units:u.order='hold'
	t.set_camera(r.projection*Vector2(1050,1050)-Vector2(960,540)/t.zoom)
	t.refresh();click(t.start_button.get_global_rect().get_center());t.refresh()
	var strikes={};var charge_contacts=0;var arrows=0;var knight=r.units[7]
	var special_counts={'troll_slam':0,'shaman_cast':0,'shaman_heal':0,'sling_stones':0};var frames_rendered=0;var end_frame=-1
	var trace=FileAccess.open(OUT+'frames.jsonl',FileAccess.WRITE)
	for frame in 4200:
		if frame==60:click(t.assault_button.get_global_rect().get_center())
		if frame==178:t.get_node('BattleHUD/RegimentRoster').ensure_control_visible(t.roster[7])
		if frame==180:
			click(t.roster[7].get_global_rect().get_center());var e=InputEventKey.new();e.physical_keycode=KEY_C;e.pressed=true;root.push_input(e,true)
			click((r.projection*Vector2(1040,650)-t.camera_offset)*t.zoom)
			if not knight.soldiers.any(func(s):return s.has('charge_run')):failures+=1;push_error('Wolf rider C input failed')
		if frame==181:root.gui_disable_input=true;t.set_process_input(false);t.set_process_unhandled_input(false);t.get_node('BattleHUD/RegimentRoster').scroll_horizontal=0
		t._process(1./60)
		# Volleys are rendered directly, not copied into field effects. Count each new projectile once.
		for projectile in r.volleys:
			if projectile.age==0.:
				arrows+=1
				if projectile.get('projectile_art','')=='sling_stone':special_counts.sling_stones+=1
		for event in t.field.effects:
			if event.age!=0:continue
			if special_counts.has(event.kind):special_counts[event.kind]+=1
			if event.get('personal_charge',false):charge_contacts+=1
			if event.get('damage',0.)>0:
				var u=r.units.filter(func(u):return u.id==event.get('attacker',-1))
				if not u.is_empty():strikes[u[0].archetype]=strikes.get(u[0].archetype,0)+1
		if frame%15==0:trace.store_line(JSON.stringify({'frame':frame,'time':r.elapsed,'phase':r.phase,'units':r.units.map(func(u):return {'id':u.id,'type':u.archetype,'hp':u.hp,'pos':u.pos})}))
		await RenderingServer.frame_post_draw
		if frame in [30,240,480,720,1200,1800,2400] or frame==end_frame:snap('frame-%04d'%frame)
		frames_rendered+=1
		if r.phase!='battle' and end_frame<0:end_frame=frame+120
		if frame==end_frame:break
	trace.close()
	if arrows==0 or charge_contacts==0:failures+=1;push_error('Missing goblin shots or wolf charge contacts')
	for row in ARMY:
		if row[1] in ['goblin_runt','goblin_brat','goblin_spiker','goblin_stabber','goblin_wolf_rider','goblin_troll'] and not strikes.has(row[1]):failures+=1;push_error('No melee damage from '+row[1])
	for kind in special_counts:
		if special_counts[kind]==0:failures+=1;push_error('Missing '+kind+' real event')
	var outcome={'phase':r.phase,'time':r.elapsed,'allies':r.strength('ally'),'enemies':r.strength('enemy')}
	if r.phase not in ['victory','defeat']:failures+=1;push_error('Battle did not conclude during capture')
	t.retry();t.refresh();for frame in 30:await RenderingServer.frame_post_draw
	var clean=t.loadout_buttons.keys().all(func(k):return t.rules.selected_variant(k)=='') and t.rules.casualties.is_empty()
	if not clean:failures+=1
	FileAccess.open(OUT+'report.json',FileAccess.WRITE).store_string(JSON.stringify({'failures':failures,'fixture':'Normal menu/loadout controls/deployment preview, then controlled ten-goblin mirror armies; enemy strategic AI active; actual All Attack and wolf rider C inputs. Fixture positions kept in source, all individual stats unmodified.','normal_speed':true,'quiet':true,'melee_strikes':strikes,'arrows':arrows,'charge_contacts':charge_contacts,'retry_clean':clean,'outcome':outcome,'special_counts':special_counts,'expected_movie_frames':frames_rendered+65},'\t'))
	print('Goblin capture: strikes=',strikes,' arrows=',arrows,' charges=',charge_contacts,' failures=',failures)
	t.closed.emit();app.queue_free();await RenderingServer.frame_post_draw;quit(1 if failures else 0)
