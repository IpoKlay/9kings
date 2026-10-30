extends SceneTree
const OUT='res://../output/cloud-scatter-v2/'
var app
var checks=0
var failures=0
var frames=0
func _init():call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;printerr('FAIL: '+message)
func capture(name: String):
	for i in 2:await process_frame;RenderingServer.force_draw()
	root.get_texture().get_image().save_png(OUT+name+'.png')
func click(control):
	var p=control.get_global_rect().get_center()
	for down in [true,false]:
		var event=InputEventMouseButton.new();event.position=p;event.global_position=p;event.pressed=down;event.button_index=MOUSE_BUTTON_LEFT;root.push_input(event,true)
	await process_frame
func key(code):
	var event=InputEventKey.new();event.keycode=code;event.pressed=true;root.push_input(event,true)
func setup(source: String,act: int=1):
	if is_instance_valid(app.departure):app.departure.cancel()
	app.close_dialog();app.campaign.reset(23);app.expedition.reset(act)
	app.main_menu=false;app.has_run=true
	if source!='':
		app.expedition.state.current=source;app.expedition.state.visited=[app.expedition.data.start,source];app.expedition.state.opening='done'
	app.expedition.state.mode='map';app.expedition_map.selected='';app.render_ui();app.expedition_map.settle_entry()
func start(id: String):
	app.expedition_map.select_city(id)
	await click(app.expedition_map.travel_button)
	check(is_instance_valid(app.departure),'Real Battle/Visit click starts the journey')
	if not is_instance_valid(app.departure):quit(1);return null
	app.departure.set_process(false)
	return app.departure
func run():
	if DisplayServer.get_name()=='headless':printerr('Native renderer required');quit(1);return
	root.size=Vector2i(1280,720);AudioServer.set_bus_mute(0,true)
	app=load('res://scenes/main.tscn').instantiate();app.settings_path='/private/tmp/eagle-departure-test.cfg';root.add_child(app)
	app.set_process(false);app.prefs.music_volume=0;app.apply_prefs();app.sound.enabled=false
	for scenario in [{'name':'land','source':'246349','target':'246369'},{'name':'sea','source':'246369','target':'265883'}]:
		setup(scenario.source)
		var before=app.expedition.state.duplicate(true);var army=app.campaign.g.buildings.duplicate(true);var rng=app.campaign.g.rng
		app.expedition_map.select_city(scenario.target)
		check(app.departure==null and app.expedition.state==before,'Previewing intel never starts travel')
		var journey=await start(scenario.target)
		check(app.input_locked and app.campaign.g.phase=='prepare','Rally holds input without starting combat')
		app.depart_to(app.expedition.destinations()[0]);app.travel_to(scenario.target)
		check(app.departure==journey and app.expedition.state==before,'Repeated departure cannot commit or replace destination')
		var camera=app.expedition_map.atlas.center
		var scroll=InputEventMouseButton.new();scroll.position=Vector2(700,400);scroll.button_index=MOUSE_BUTTON_WHEEL_UP;scroll.pressed=true;root.push_input(scroll,true)
		await click(app.expedition_map.content.get_node('SettingsButton'))
		check(app.dialog_kind=='' and app.expedition_map.atlas.center==camera,'Journey blocks underlying settings and map gestures')
		journey.step(.22);await capture(scenario.name+'-rally')
		var saw_sail=false;var saw_march=false;var saw_cover=false;var saw_reveal=false
		for frame in 70:
			if journey.finished:break
			journey.step(1.0/15)
			if journey.finished:break
			app._process(1.0/60)
			if app.campaign.g.phase=='battle':check(is_zero_approx(app.campaign.g.battle.time),'Combat clock frozen until cloud reveal completes')
			if journey.phase=='march':
				saw_sail=saw_sail or journey.sailing;saw_march=true
				if frame==15:await capture(scenario.name+'-moving')
			if journey.phase=='covered' and not saw_cover:
				saw_cover=true;await capture(scenario.name+'-covered')
				var cloud=journey.cloud_view.get_texture().get_image();var opaque=true
				for y in range(0,cloud.get_height(),8):
					for x in range(0,cloud.get_width(),8):opaque=opaque and cloud.get_pixel(x,y).a>.99
				check(opaque and not journey.committed,'Full opaque cloud frame exists before state change')
			if journey.phase=='reveal' and journey.age>.10 and not saw_reveal:
				saw_reveal=true;await capture(scenario.name+'-reveal')
			if scenario.name=='sea':
				await capture('frames/sea-%03d'%frames);frames+=1
		check(journey.finished and app.departure==null and not app.input_locked,'Journey completes and releases input')
		check(saw_march and saw_cover and saw_reveal,'All animation stages executed')
		check(saw_sail==(scenario.name=='sea'),'Transport matches land versus sea route')
		check(app.expedition.state.target==scenario.target and app.campaign.g.buildings==army,'Correct encounter starts with unchanged army')
		check(app.campaign.g.rng==rng,'Travel art consumes no campaign random numbers')
		app._process(.1);check(app.campaign.g.battle.time>0,'Combat starts only after reveal')
		await capture(scenario.name+'-battle')
	# All random starts include home -> departure port -> first actual destination.
	for act in [1,2,3]:
		setup('',act);var target=app.expedition.destinations()[0];var j=await start(target)
		check(j.legs.size()==2,'Opening includes the departure harbor for theater '+str(act))
		key(KEY_SPACE)
		check(j.finished and app.expedition.state.target==target and app.campaign.g.phase=='battle','Space skips once into the intended first battle')
		check(app.expedition.state.visited.size()==2,'Opening transit is recorded exactly once')
		j.finish_immediately();check(app.expedition.state.visited.size()==2,'Repeated skip cannot duplicate transit')
	# Non-combat destination: same march, one supply event, no battle cloud.
	setup('256177');var j=await start('462503');check(not j.battle and j.legs[0].sea,'Cross-region harbor uses the sea route')
	j.step(j.preset.rally_seconds);j.step(j.march_seconds)
	check(j.finished and app.campaign.g.phase=='reward' and app.dialog_kind=='event','Harbor arrival opens its original one-time event')
	check(app.expedition.state.visited.count('462503')==1,'Harbor reward arrives only once')
	# Menu cancellation before arrival never commits the target; no delayed callback fires.
	setup('246369');var before=app.expedition.state.duplicate(true);j=await start('265883')
	app.return_to_menu();check(app.departure==null and not app.input_locked and app.main_menu,'Menu cancels presentation safely')
	check(app.expedition.state==before,'Cancelled journey leaves the run unchanged')
	# Reduced-motion branch uses a static opacity curtain and still waits before combat.
	setup('246349');j=await start('246369');j.reduced=true;j.advance_phase('cover')
	j.step(.1);check(j.cloud_field.gentle,'Reduced motion selects static cloud fade')
	j.step(.1);j.step(.1);check(app.campaign.g.battle.time==0,'Reduced-motion reveal also freezes combat')
	j.step(.21);check(j.finished,'Reduced motion releases control')
	# Native audio pool: every confirmed rally plays once, respects silence and vocal gain.
	app.sound.stop();app.sound.enabled=false;app.sound.play_rally();check(app.sound.last.is_empty(),'Sound disabled suppresses rally')
	app.sound.enabled=true;app.sound.volume=.4;app.sound.voices=.3;app.sound.play_rally()
	check(app.sound.last.has('horn') and app.sound.last.has('cry'),'Rally plays existing horn and group vocals')
	var voice=app.sound.pool.filter(func(p):return p.playing and p.stream==app.sound.cache.get('cry0'))
	check(voice.size()==1 and is_equal_approx(db_to_linear(voice[0].volume_db),.4*.3*.7),'Voice volume remains independent')
	app.sound.play_rally();check(app.sound.pool.filter(func(p):return p.playing and p.stream==app.sound.cache.get('horn0')).size()==1,'Rapid next rally replaces the previous horn tail')
	app.sound.stop();app.sound.enabled=false
	# One uninterrupted real-time run proves automatic _process integration as well.
	setup('246349');app.expedition_map.select_city('246369');await click(app.expedition_map.travel_button)
	var deadline=Time.get_ticks_msec()+6000
	while is_instance_valid(app.departure) and Time.get_ticks_msec()<deadline:await process_frame
	check(app.departure==null and app.campaign.g.phase=='battle','Real-time native animation completes without test stepping')
	app.sound.stop();app.music.set_process(false)
	for i in 2:app.music.retire_slot(i)
	app.queue_free();await process_frame;await process_frame
	print('%d departure/cloud checks, %d failures; %d animation frames'%[checks,failures,frames]);quit(1 if failures else 0)
