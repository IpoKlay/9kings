extends SceneTree
var app
var baseline=false
var failures=0
var count=0
func _init():
	baseline='--baseline' in OS.get_cmdline_user_args()
	call_deferred('run')
func capture(id: String):
	if is_instance_valid(app.card_hand):
		for slot in app.card_hand.slots:
			if slot.tween!=null and slot.tween.is_valid(): slot.tween.custom_step(10)
	if is_instance_valid(app.expedition_map.atlas): app.expedition_map.atlas.set_process(false)
	app.world.clock=0;app.world.environment.clock=0;app.world.queue_redraw()
	app.expedition_map.sea.clock=1.0
	if app.expedition_map.sea.material!=null: app.expedition_map.sea.material.set_shader_parameter('sea_time',1.0)
	await process_frame
	RenderingServer.force_draw()
	var image=root.get_texture().get_image()
	var folder=ProjectSettings.globalize_path('res://../output/data-organization/')
	image.save_png(folder+('baseline/' if baseline else 'after/')+id+'.png')
	if not baseline:
		var previous=Image.load_from_file(folder+'baseline/'+id+'.png')
		if image.get_size()!=previous.get_size() or image.get_data()!=previous.get_data():
			failures+=1;printerr('FAIL: visual changed '+id)
	count+=1
func run():
	if DisplayServer.get_name()=='headless': quit(1);return
	app=load('res://scenes/main.tscn').instantiate()
	root.add_child(app);current_scene=app;app.set_process(false);app.sound.enabled=false
	for language in ['zh','en']:
		app.language=language;app.main_menu=true;app.has_run=false;app.render_ui()
		await capture('menu-'+language)
		app.open_dialog('settings');await capture('settings-'+language);app.close_dialog()
		for act in [1,2,3]:
			app.campaign.reset(12345);app.expedition.reset(act);app.main_menu=false;app.has_run=true
			app.open_map();app.expedition_map.atlas.focus_act(act)
			await capture('map-'+language+'-'+str(act))
			app.travel_to(app.expedition.destinations()[0])
			app.campaign.g.offered=['legion','shieldDrill','volley'];app.campaign.g.offerYear=app.campaign.g.round
			app.dealt_year=-1;app.render_ui()
			await capture('cards-'+language+'-'+str(act))
			app.campaign.g.phase='prepare';app.expedition.state.opening='done';app.expedition.state.reward_due=false;app.expedition.state.mode='battle'
			app.campaign.start();app.render_ui()
			await capture('battle-'+language+'-'+str(act))
	app.sound.stop()
	print('%d visual snapshots, %d differences, baseline=%s'%[count,failures,baseline])
	quit(1 if failures else 0)
