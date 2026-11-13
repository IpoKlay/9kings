extends SceneTree
## Tests the expedition around the existing combat scene through the normal menu.
const Journey = preload('res://scripts/cassius/journey.gd')
var app
var screen
var failures = 0
var checks = 0
var save_path = ''
var out = ''

func _initialize():
	call_deferred('run')

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		printerr('FAIL: '+message)

func key(code: int):
	for pressed in [true,false]:
		var event = InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event,true)
	await process_frame

func click(node: Button):
	for pressed in [true,false]:
		var event = InputEventMouseButton.new()
		event.position = node.get_global_rect().get_center()
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
	await process_frame

func named_button(prefix: String) -> Button:
	for node in screen.content.find_children('*','Button',true,false):
		if node.text.begins_with(prefix): return node
	return null

func choose(prefix: String):
	var node = named_button(prefix)
	check(node != null and not node.disabled,'Action available: '+prefix)
	if node != null and not node.disabled:
		var scroll = screen.content.get_parent() as ScrollContainer
		scroll.ensure_control_visible(node)
		await process_frame
		await click(node)

func stop_at(id: String):
	# Fast travel fixture for exercising every interaction. Movement is checked separately.
	screen.landscape.actor = screen.landscape.STOPS[id]
	await key(KEY_F)
	check(screen.mode == id,'F opens '+id+' only at its station')

func shot(id: String):
	if DisplayServer.get_name() == 'headless': return
	await process_frame
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	if image != null: image.save_png(out+'/'+id+'.png')

func run():
	out = ProjectSettings.globalize_path('res://../output/cassius')
	DirAccess.make_dir_recursive_absolute(out)
	save_path = out+'/test-journey.cfg'
	for suffix in ['','.tmp','.bak']:
		if FileAccess.file_exists(save_path+suffix): DirAccess.remove_absolute(save_path+suffix)
	app = load('res://scenes/main.tscn').instantiate()
	app.settings_path = out+'/test-settings.cfg'
	app.cassius_save_path = save_path
	root.add_child(app)
	current_scene = app
	app.sound.enabled = false
	for i in 5: await process_frame
	await click(app.menu_view.get_node('%Cassius'))
	screen = app.cassius
	check(is_instance_valid(screen),'Main menu opens Cassius')
	if not is_instance_valid(screen):quit(1);return
	var journey = screen.journey
	var original = app.expedition.state.duplicate(true)
	await shot('intro')
	for i in 5:
		check(screen.mode=='intro' and journey.state.intro==i,'Intro page %d'%(i+1))
		await choose('继续' if i<4 else '带队出发')
	check(screen.mode=='','Introduction opens walkable road')
	await shot('road')
	var before: Vector2 = screen.landscape.actor
	var event = InputEventKey.new()
	event.keycode=KEY_D;event.physical_keycode=KEY_D;event.pressed=true
	Input.parse_input_event(event)
	for i in 12: await process_frame
	event.pressed=false
	Input.parse_input_event(event)
	check(screen.landscape.actor.x>before.x,'Held movement key advances Cassius')
	screen.landscape.actor=Vector2(570,390)
	await key(KEY_F)
	check(screen.mode=='','F away from a station has no interaction')
	await stop_at('village')
	await choose('接受帮助')
	check(journey.state.choices.south=='promise' and journey.count('food')==13,'Local aid creates a real obligation and goods')
	await key(KEY_ESCAPE)
	await stop_at('shop')
	await shot('shop')
	var food = journey.count('food')
	await choose('干粮三份')
	check(journey.count('food')==food+3 and journey.count('gold')==23,'Shop charges the exact price')
	await choose('交出 皮革')
	check(journey.count('hide')==0 and journey.count('gold')==27,'Sell removes item and credits gold')
	await key(KEY_ESCAPE)
	await stop_at('camp')
	await shot('growth')
	check(named_button('冬粮转运').disabled,'Growth prerequisite is enforced')
	await choose('辎重整备')
	await choose('冬粮转运')
	check(journey.state.growth==['supply','relief'] and journey.count('gold')==17,'Growth buys persist and charge gold')
	await key(KEY_ESCAPE)
	await stop_at('altar')
	await choose('献一头白牛')
	check(journey.count('ox')==0 and screen.busy and screen.landscape.ritual>0.,'Offering pays once and plays ritual')
	await shot('ritual')
	await create_timer(2.5).timeout
	check(screen.mode=='altar' and journey.state.omens.has('south'),'Ritual shows omen')
	await key(KEY_ESCAPE)
	await stop_at('warning')
	await choose('进入军团会战')
	for i in 6:await process_frame
	var trial = app.active_trial
	check(is_instance_valid(trial) and not app.visible,'Warning opens existing RTS scene')
	if is_instance_valid(trial):
		# Inject only the result; this is not a simulated battle victory.
		trial.rules.phase='victory'
		trial.closed.emit()
		await process_frame
	check(app.visible and screen.mode=='warning' and journey.state.battles.get('south')=='won' and journey.count('ivory')==1,'Victory return records loot once')
	var gold = journey.count('gold')
	screen.accept_battle_result('victory')
	check(journey.count('gold')==gold,'Result cannot duplicate rewards')
	await key(KEY_ESCAPE)
	await key(KEY_M)
	check(screen.mode=='map','M opens four-region map')
	await shot('map')
	await key(KEY_ESCAPE)
	await stop_at('fork')
	check(journey.routes().size()==3,'All three foreign regions are reachable from the first fork')
	var routes = screen.content.find_children('*','Button',true,false)
	await click(routes[1])
	check(journey.state.region=='north' and journey.state.visits.size()==2,'Route click pays travel and changes land')
	await stop_at('village')
	await choose('接受帮助')
	await key(KEY_ESCAPE)
	await stop_at('altar')
	await choose('依本地礼仪')
	await create_timer(2.5).timeout
	check(journey.state.choices.north=='kept' and journey.count('relic')==0,'Northern sacrifice fulfills its pledge')
	await key(KEY_ESCAPE)
	await stop_at('fork')
	await choose('出发')
	await stop_at('village')
	await choose('执行征收')
	await key(KEY_ESCAPE)
	await stop_at('warning')
	await choose('绕行')
	check(journey.state.battles.get(journey.state.region)=='detour','Detour resolves warning without starting combat')
	await key(KEY_ESCAPE)
	await stop_at('fork')
	await choose('带现有粮食回援要塞')
	check(screen.mode=='ending' and journey.state.ending=='home' and journey.state.winter_food==journey.count('food')+6,'Ending counts actual supplies and purchased growth')
	await shot('ending')
	await choose('翻阅远征账本')
	check(screen.mode=='ledger' and journey.state.ledger.size()>=12,'Ledger records the journey')
	await shot('ledger')
	await key(KEY_ESCAPE)
	await choose('返回主菜单')
	check(not is_instance_valid(app.cassius) and app.expedition.state==original,'Old expedition stays intact')
	await click(app.menu_view.get_node('%Cassius'))
	screen=app.cassius
	check(screen.mode=='ending' and screen.journey.state.choices.north=='kept','Reopening restores ending and obligations')
	var second = Journey.new()
	second.decide('levy');second.travel('east');second.decide('levy');second.travel('north');second.decide('levy')
	check(second.finish('rite') and second.state.winter_food==second.count('food')+8,'Rite ending pays and computes grain')
	var checkpoint=Journey.new()
	check(checkpoint.load_run(save_path) and checkpoint.state.ended,'Saved journey validates after reload')
	var file=ConfigFile.new();file.set_value('run','state',{'version':1,'region':3});file.save(save_path)
	check(checkpoint.load_run(save_path) and checkpoint.state.visits.size()==3,'Invalid primary save falls back to previous checkpoint')
	print('Cassius journey: %d checks, %d failures'%[checks,failures])
	await app.prepare_shutdown()
	quit(1 if failures else 0)
