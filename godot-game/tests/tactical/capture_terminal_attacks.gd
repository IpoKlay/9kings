extends SceneTree
var OUT='/Users/ip/Documents/ChatGPT/9kings/output/sword-banner-reference/terminal-attacks/runtime/'
var before_version=false
var failures=0
func _initialize():call_deferred('run')
func click(point:Vector2):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;root.push_input(e,true)
func snap(name:String):RenderingServer.force_draw();root.get_texture().get_image().save_png(OUT+name+'.png')
func run():
	before_version='before' in OS.get_cmdline_user_args()
	if before_version:OUT=OUT.replace('/runtime/','/before-runtime/')
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-terminal-capture.cfg';root.add_child(app)
	await process_frame
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	for frame in 30:await process_frame
	click(t.combined_button.get_global_rect().get_center());t.refresh();await process_frame;snap('normal-deployment')
	var r=t.rules;r.units.clear()
	for kind in ['archer','legion']:
		r.config.types[kind].files=1;r.config.types[kind].hp=r.config.types[kind].individual.hp;r.contact_profiles[kind]=r.Contact.profile(kind,r.config.types[kind],true)
	for kind in r.reserve:r.reserve[kind]=0
	r.spawn('legion','enemy',Vector2(621,1100));r.spawn('archer','ally',Vector2(650,1100));r.spawn('legion','enemy',Vector2(1050,1100));r.spawn('legion','ally',Vector2(650,1700))
	for u in r.units:u.order='hold';r.Charges.detach(r,u,0);u.soldiers[0].position=u.pos;u.soldiers[0].personal_order='hold'
	var shooter=r.units[1];var killer=r.units[0];var target=r.units[2]
	r.hurt(shooter,shooter.hp-1.,'',0.,0)
	t.set_camera(r.projection*Vector2(1050,1200)-Vector2(960,540)/t.zoom);t.refresh();click(t.start_button.get_global_rect().get_center());t.refresh();r.enemy_director.active=false
	for u in r.units:u.soldiers[0].cooldown=999.
	for pair in [[killer,shooter,-.16],[shooter,target,0.]]:
		var actor=pair[0].soldiers[0];actor.target_id=pair[1].id;actor.target_slot=0;actor.attack_age=pair[2];actor.attack_pending=true;actor.heading=actor.position.direction_to(pair[1].soldiers[0].position)
	target.soldiers[0].shield_wall=true;target.soldiers[0].wall_heading=Vector2.LEFT;target.soldiers[0].heading=Vector2.LEFT
	root.gui_disable_input=true;t.set_process_input(false);t.set_process_unhandled_input(false)
	var trace=FileAccess.open(OUT+'frames.jsonl',FileAccess.WRITE);var death_frame=-1;var impact_frame=-1;var released=0;var unblocked=false;var seen={};var release_frame=-1
	for frame in 360:
		t._process(1./60)
		for shot in r.volleys:
			if shot.attacker==shooter.id and not seen.has(shot.serial):released+=1;seen[shot.serial]=true;release_frame=frame
		for effect in t.field.effects:
			if effect.age!=0:continue
			if effect.kind=='arrow_impact' and effect.target==target.id:impact_frame=frame;unblocked=not effect.blocked
		if death_frame<0 and shooter.hp<=0:death_frame=frame
		trace.store_line(JSON.stringify({'frame':frame,'time':r.elapsed,'source_hp':shooter.hp,'source_state':shooter.soldiers[0].death_state,'target_hp':target.hp,'arrows':r.volleys.map(func(p):return {'source':p.attacker,'point':p.point,'target':p.target})}))
		RenderingServer.force_draw()
		await process_frame
		if frame in [30,45,60,75,90,120,180,359] or frame==death_frame or frame==impact_frame:snap('frame-%04d'%frame)
	trace.close()
	var expected:float=target.max_hp-(0. if before_version else shooter.get('combat_stats',r.config.types[shooter.kind]).damage)
	var matched=(released==0 and impact_frame<0) if before_version else (released==1 and release_frame==death_frame and impact_frame>death_frame and unblocked)
	if not matched or death_frame<0 or not is_equal_approx(target.hp,expected):failures+=1;push_error('Terminal release comparison evidence missing')
	t.retry();t.refresh();for frame in 30:await process_frame
	var clean=t.rules.projectile_serial==0 and t.rules.volleys.is_empty() and t.rules.stones.is_empty() and t.rules.units.all(func(u):return u.soldiers.all(func(s):return s.death_state==0))
	if not clean:failures+=1
	FileAccess.open(OUT+'report.json',FileAccess.WRITE).store_string(JSON.stringify({'failures':failures,'fixture':'Normal menu then controlled one-person fixture. Enemy legion is visited before1HP ally archer. Pending melee and bow windups are seeded to reach release on the same simulation step; all later cooldowns999 isolate this single event. Normal damage, speed, default zoom, muted. Original pre-change source suppresses bow; changed source emits once. This is instrumented local runtime, not original-game footage.','before_version':before_version,'release_frame':release_frame,'released':released,'source_death_frame':death_frame,'shield_impact_frame':impact_frame,'shield_unblocked':unblocked,'target_hp':target.hp,'expected_hp':expected,'retry_clean':clean,'expected_movie_frames':423},'\t'))
	print('Terminal capture: death=',death_frame,' impact=',impact_frame,' failures=',failures)
	t.closed.emit();app.queue_free();await process_frame;quit(1 if failures else 0)
