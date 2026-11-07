extends SceneTree
const OUT='res://../output/sword-banner-reference/death-lifecycle/runtime/'
var failures=0
func _initialize():call_deferred('run')
func click(point:Vector2):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;root.push_input(e,true)
func snap(name:String):root.get_texture().get_image().save_png(OUT+name+'.png')
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-death-capture.cfg';root.add_child(app)
	await RenderingServer.frame_post_draw
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	for frame in 30:await RenderingServer.frame_post_draw
	click(t.combined_button.get_global_rect().get_center());t.refresh();await RenderingServer.frame_post_draw;snap('normal-deployment')
	var r=t.rules;r.units.clear()
	for kind in ['archer','legion']:
		r.config.types[kind].files=1;r.config.types[kind].hp=r.config.types[kind].individual.hp;r.contact_profiles[kind]=r.Contact.profile(kind,r.config.types[kind],true)
	for kind in r.reserve:r.reserve[kind]=0
	r.spawn('archer','ally',Vector2(650,1100));r.spawn('archer','enemy',Vector2(730,1100));r.spawn('legion','enemy',Vector2(1050,1100));r.spawn('legion','ally',Vector2(650,1700))
	for u in r.units:u.order='hold';r.Charges.detach(r,u,0);u.soldiers[0].position=u.pos;u.soldiers[0].personal_order='hold'
	var shooter=r.units[0];var killer=r.units[1];var target=r.units[2]
	r.hurt(shooter,shooter.hp-1.,'',0.,0)
	t.set_camera(r.projection*Vector2(1050,1200)-Vector2(960,540)/t.zoom);t.refresh();click(t.start_button.get_global_rect().get_center());t.refresh();r.enemy_director.active=false
	var direct:Array[Vector2]=[]
	r.Soldiers.command(r,[Vector2i(shooter.id,0)],'attack',target.pos,target.id,0)
	r.Soldiers.command(r,[Vector2i(killer.id,0)],'attack',shooter.pos,shooter.id,0,direct,true,'enemy')
	target.soldiers[0].shield_wall=true;target.soldiers[0].wall_heading=Vector2.LEFT;target.soldiers[0].heading=Vector2.LEFT
	root.gui_disable_input=true;t.set_process_input(false);t.set_process_unhandled_input(false)
	var trace=FileAccess.open(OUT+'frames.jsonl',FileAccess.WRITE);var death_frame=-1;var impact_frame=-1;var released=0;var unblocked=false;var seen={}
	for frame in 360:
		t._process(1./60)
		for shot in r.volleys:
			if shot.attacker==shooter.id and not seen.has(shot.serial):released+=1;seen[shot.serial]=true
		for effect in t.field.effects:
			if effect.age!=0:continue
			if effect.kind=='arrow_impact' and effect.target==target.id:impact_frame=frame;unblocked=not effect.blocked
		if death_frame<0 and shooter.hp<=0:death_frame=frame
		trace.store_line(JSON.stringify({'frame':frame,'time':r.elapsed,'source_hp':shooter.hp,'source_state':shooter.soldiers[0].death_state,'target_hp':target.hp,'arrows':r.volleys.map(func(p):return {'source':p.attacker,'point':p.point,'target':p.target})}))
		await RenderingServer.frame_post_draw
		if frame in [30,45,60,75,90,120,180,359] or frame==death_frame or frame==impact_frame:snap('frame-%04d'%frame)
	trace.close()
	var expected:float=target.max_hp-shooter.get('combat_stats',r.config.types[shooter.kind]).damage
	if released!=1 or death_frame<0 or impact_frame<=death_frame or not unblocked or not is_equal_approx(target.hp,expected):failures+=1;push_error('Source-death airborne hit evidence missing')
	t.retry();t.refresh();for frame in 30:await RenderingServer.frame_post_draw
	var clean=t.rules.projectile_serial==0 and t.rules.volleys.is_empty() and t.rules.stones.is_empty() and t.rules.units.all(func(u):return u.soldiers.all(func(s):return s.death_state==0))
	if not clean:failures+=1
	FileAccess.open(OUT+'report.json',FileAccess.WRITE).store_string(JSON.stringify({'failures':failures,'fixture':'Normal menu then controlled one-person setup. Ally archer wounded to1HP focuses distant F shield. Nearby enemy archer kills shooter first; released arrow continues and strikes shield after source destruction. Fourth ally keeps battle active. Scripted standard focus commands; real attacks/projectile speed and damage unchanged, normal speed, muted, default zoom.','released':released,'source_death_frame':death_frame,'shield_impact_frame':impact_frame,'shield_unblocked':unblocked,'target_hp':target.hp,'expected_hp':expected,'retry_clean':clean,'expected_movie_frames':424},'\t'))
	print('Death capture: death=',death_frame,' impact=',impact_frame,' failures=',failures)
	t.closed.emit();app.queue_free();await RenderingServer.frame_post_draw;quit(1 if failures else 0)
