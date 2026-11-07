extends SceneTree
const OUT='res://../output/sword-banner-reference/wraith/runtime/'
var failures=0
func _initialize():call_deferred('run')
func click(p):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;root.push_input(e,true)
func key(code):
	var e=InputEventKey.new();e.physical_keycode=code;e.pressed=true;root.push_input(e,true)
func snap(name):root.get_texture().get_image().save_png(OUT+name+'.png')
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-wraith-capture.cfg';root.add_child(app);await RenderingServer.frame_post_draw
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	for i in 3:click(t.legion_variant_button.get_global_rect().get_center())
	for frame in 30:await RenderingServer.frame_post_draw
	snap('deployment');click(t.combined_button.get_global_rect().get_center());await RenderingServer.frame_post_draw;snap('normal-deployment')
	var r=t.rules;r.units.clear();r.spawn('legion','ally',Vector2(1050,1200),'wraith');r.spawn('guard','enemy',Vector2(1050,900));r.spawn('legion','enemy',Vector2(1900,200))
	for u in r.units:u.order='hold'
	var w=r.units[0];t.set_camera(r.projection*Vector2(1050,1050)-Vector2(960,540)/t.zoom)
	t.refresh();click(t.start_button.get_global_rect().get_center());r.enemy_director.active=false;t.refresh()
	var blinks=[];var cleaves=0;var cooldown=0.;var trace=FileAccess.open(OUT+'frames.jsonl',FileAccess.WRITE)
	for frame in 780:
		if frame==30:click(t.roster[0].get_global_rect().get_center())
		if frame==60:key(KEY_B)
		if frame==75:
			click((r.projection*Vector2(1050,970)-t.camera_offset)*t.zoom)
			if not w.soldiers.all(func(a):return a.get('blink_cooldown',0.)==8.):failures+=1
		if frame==330:click(t.get_node('BattleHUD/TopActions/PauseButton').get_global_rect().get_center());cooldown=w.soldiers[0].blink_cooldown
		if frame==360:
			if w.soldiers[0].blink_cooldown!=cooldown:failures+=1
			click(t.get_node('BattleHUD/TopActions/PauseButton').get_global_rect().get_center())
		if frame==600:key(KEY_H)
		if frame==630:
			key(KEY_B);var origin=r.Blink.center(r,r.Blink.ready(r,t.selected_people()))
			click((r.projection*(origin+Vector2(0,180))-t.camera_offset)*t.zoom)
			if not w.soldiers.any(func(a):return a.hp>0 and a.blink_cooldown==8.):failures+=1
		if frame==631:root.gui_disable_input=true;t.set_process_input(false);t.set_process_unhandled_input(false)
		t._process(1./60)
		for effect in t.field.effects:
			if t.paused or effect.age!=0.:continue
			if effect.kind=='blink':blinks.append({'frame':frame,'slot':effect.attacker_slot,'from':effect.from,'to':effect.pos})
			if effect.kind=='scythe':cleaves+=1
		trace.store_line(JSON.stringify({'frame':frame,'time':r.elapsed,'paused':t.paused,'people':w.soldiers,'enemy_hp':r.units[1].hp}))
		await RenderingServer.frame_post_draw
		if frame in [60,74,75,85,180,300,340,629,630,645,779]:snap('frame-%04d'%frame)
	trace.close()
	if blinks.size()<10 or cleaves==0 or r.units[1].hp==r.units[1].max_hp:failures+=1
	t.retry();t.refresh();for frame in 30:await RenderingServer.frame_post_draw
	var clean=t.rules.selected_variant('legion')=='' and t.field.effects.is_empty() and t.rules.units.all(func(u):return u.soldiers.all(func(a):return a.get('blink_cooldown',0.)==0.))
	if not clean:failures+=1
	FileAccess.open(OUT+'report.json',FileAccess.WRITE).store_string(JSON.stringify({'failures':failures,'fixture':'Normal menu/loadout/combined preview, then ten wraiths against holding veteran swordsmen with distant reserve; enemy director disabled, attacks active. Actual roster/B/left-click/pause/H inputs.','blinks':blinks,'cleaves':cleaves,'retry_clean':clean,'pause_seconds':.5,'normal_speed':true,'quiet':true},'\t'))
	print('Wraith capture: blinks=',blinks.size(),' cleaves=',cleaves,' failures=',failures)
	t.closed.emit();app.queue_free();await RenderingServer.frame_post_draw;quit(1 if failures else 0)
