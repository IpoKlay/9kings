extends SceneTree
const Campaign=preload('res://scripts/campaign.gd')
const Field=preload('res://scripts/battlefield.gd')
var checks=0
var failures=0
func _init():call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;printerr('FAIL: '+message)
func hit(id: int,side: String,guard: bool=false,broken: bool=false) -> Dictionary:
	return {'kind':'hit','id':id,'side':side,'x':500.0,'y':0.0,'damage':0.0 if guard else 14.0,'absorbed':6.0 if guard else 0.0,'broken':broken}
func run():
	root.size=Vector2i(1280,720)
	var game=Campaign.new(23);game.skip();game.start()
	var field=Field.new();field.game=game;root.add_child(field)
	var enemy=game.g.battle.units.filter(func(u):return u.side=='enemy')[0]
	var ally=game.g.battle.units.filter(func(u):return u.side=='ally')[0]
	var original=game.g.duplicate(true)
	field.events([hit(enemy.id,'enemy')])
	check(field.impact_marks.size()==1 and field.impact_marks[0].kind=='hit','Immediate normal hit marker')
	check(field.recoil_offset(enemy.id).x>0,'Enemy recoils away from allied front')
	check(field.hit_tint(enemy.id)!=Color.WHITE,'Hit flash starts in event frame')
	check(field.shake==0,'Routine hit never shakes whole battlefield')
	field.events([hit(enemy.id,'enemy')])
	check(field.impact_marks.size()==1,'Same-frame hits merge rather than flooding particles')
	field.events([hit(enemy.id,'enemy',true,true)])
	check(field.impact_marks[-1].kind=='break','Shield break overrides recent routine hit feedback')
	field.events([hit(ally.id,'ally',true,true)])
	check(field.impact_marks[-1].kind=='break','Shield break has its own marker')
	check(field.recoil_offset(ally.id).x<0,'Ally recoil direction is mirrored')
	check(field.hit_tint(ally.id)==field.feedback.guard_flash_color,'Shield flash uses steel color')
	field.tick(.06,.06)
	check(field.hit_tint(enemy.id)==Color.WHITE,'Flash ends without permanent tint')
	check(field.recoil_offset(enemy.id).length()<=6,'Recoil remains a few logical pixels')
	field.tick(.3,.3)
	check(field.hit_reactions.is_empty() and field.impact_marks.is_empty(),'Visual reactions expire')
	for rate in [30,60,120]:
		for speed in [1,2,4]:
			field.clear_battle();field.events([hit(enemy.id,'enemy')])
			for i in ceili(.18*rate):field.tick(float(speed)/rate,1.0/rate)
			check(field.hit_reactions.is_empty() and field.impact_marks.is_empty(),'Real-time feedback expires at %d FPS / %dx'%[rate,speed])
	for i in 70:field.add_impact(Vector2(i*2,0),'hit',1)
	check(field.impact_marks.size()==field.feedback.impact_mark_limit,'Impact list stays bounded under dense hits')
	field.events([{'kind':'blast','side':'ally','x':500.0,'y':0.0}])
	check(field.impact_marks[-1].kind=='blast','Blast uses a ground impact mark')
	var first=field.camera_offset()
	check(first!=Vector2.ZERO and first==field.camera_offset(),'Camera does not randomize on repeated draw calls')
	var punch_started=field.shake_started
	field.tick(.02,.02);field.kick(6,1)
	check(field.shake_started==punch_started,'Decaying amplitude cannot bypass repeated-punch cooldown')
	for i in 30:
		field.tick(1.0/120,1.0/120)
		var offset=field.camera_offset()
		check(offset==offset.snapped(Vector2(2,2)) and offset.length()<=7,'Camera remains on pixel grid and within amplitude budget')
	check(field.camera_offset()==Vector2.ZERO,'Camera punch returns to rest')
	field.impact=false;field.kick(6,1);field.events([hit(enemy.id,'enemy')])
	check(field.recoil_offset(enemy.id)==Vector2.ZERO and field.camera_offset()==Vector2.ZERO,'Impact toggle disables motion feedback')
	field.events([{'kind':'wave_start'}])
	check(field.hit_reactions.is_empty() and field.impact_marks.is_empty() and field.shake==0,'Wave transition clears effects and reused unit IDs')
	check(game.g==original,'Visual updates never mutate battle state, health, position or cooldowns')
	field.queue_free()
	var app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/private/tmp/eagle-combat-feel-test.cfg';root.add_child(app);app.set_process(false)
	app.sound.enabled=false;app.prefs.music_volume=0;app.apply_prefs();app.sound.enabled=false
	app.starting_theaters.assign([1]);app.start_game();app.expedition_map.settle_entry()
	check(preload('res://tests/expedition_test_support.gd').deploy(app),'Existing destination/card/deployment still enters combat')
	app.hit_stop=app.feedback.hit_stop_seconds
	var sim_time: float=app.campaign.g.battle.time
	var pose_time: float=app.world.clock
	var fx_time: float=app.world.feedback_clock
	app._process(1.0/60)
	check(app.campaign.g.battle.time==sim_time and app.world.clock==pose_time,'Hit-stop pauses simulation and attack poses together')
	check(app.world.feedback_clock>fx_time,'Short spark and recoil feedback uses unscaled real time')
	for i in 5:app._process(1.0/60)
	check(app.campaign.g.battle.time>sim_time,'Existing hit-stop always resumes combat')
	app.paused=true;fx_time=app.world.feedback_clock;app._process(.1)
	check(app.world.feedback_clock==fx_time,'Pause also pauses visual feedback')
	app.paused=false;app.open_map();app._process(.1)
	check(app.world.feedback_clock==fx_time,'Map does not keep updating hidden battle effects')
	app.show_camp();app._process(1.0/60)
	check(app.world.feedback_clock>fx_time,'Returning from map resumes feedback')
	if DisplayServer.get_name()!='headless':
		for i in 900:
			app._process(1.0/60)
			if not app.world.impact_marks.is_empty():
				# The world's SubViewport is visibility-driven; allow it to become visible and render.
				for frame in 4:
					await process_frame;RenderingServer.force_draw()
				root.get_texture().get_image().save_png('res://../output/combat-feel-v1/full-game-native.png')
				break
	app.sound.stop()
	app.music.set_process(false)
	for i in 2:app.music.retire_slot(i)
	# Let the native audio thread release a stopped MP3 before disposing its owner.
	await create_timer(.1).timeout
	app.queue_free()
	await process_frame
	await process_frame
	print('%d combat feedback checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
