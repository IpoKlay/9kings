extends SceneTree
## Card face rendering and real pointer selection through the native viewport.
var app
var checks=0
var failures=0
func _init(): call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1;printerr('FAIL: '+message)
func capture(name: String):
	if DisplayServer.get_name()=='headless': return
	await process_frame
	RenderingServer.force_draw()
	var image=root.get_texture().get_image()
	image.save_png('res://../output/card-face-v1/'+name+'.png')
	if name=='hover-zh':
		image.get_region(Rect2i(580,540,770,540)).save_png('res://../output/card-face-v1/card-preview.png')
func move_pointer(pos: Vector2):
	root.warp_mouse(pos)
	await process_frame
	var event=InputEventMouseMotion.new()
	event.position=pos;event.global_position=pos
	root.push_input(event,true)
	await process_frame
func run():
	if DisplayServer.get_name()=='headless':
		printerr('Card pointer/render verification requires the native renderer.');quit(1);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://../output/card-face-v1'))
	root.size=Vector2i(1920,1080)
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/private/tmp/eagle-card-face-test.cfg'
	root.add_child(app);current_scene=app
	app.sound.enabled=false
	app.set_process(false)
	app.restart_expedition(1)
	app.travel_to(app.expedition.destinations()[0]);app.campaign.finish(true);app.advance()
	var opening_offers=app.campaign.offers().duplicate()
	var authored=app.campaign.cards.duplicate(true)
	for lang in ['zh','en']:
		app.language=lang;app.world.language=lang
		# Show one existing card from each type; no new cards or effects are introduced.
		app.campaign.g.offered=['spear','fireArrows','testudo']
		app.render_ui()
		var hand=app.card_hand
		hand.input_enabled=false
		await create_timer(.5).timeout
		for slot in hand.slots:
			var card=slot.card
			var data=app.campaign.cards[slot.id]
			var copy=app.campaign.card_copy(slot.id,lang)
			check(card.get_node('CardTitle').text==copy.name,'Original card name '+slot.id+' '+lang)
			check(card.get_node('CardDescription').text==copy.text,'Complete original effect description '+slot.id+' '+lang)
			check(card.get_node('CardImpact').text==copy.impact,'Original numerical effect '+slot.id+' '+lang)
			check(card.get_node('CardKind').text.contains('I'),'Card type includes level '+slot.id+' '+lang)
			for child in card.get_children():
				if child is TextureRect:
					check(child.texture==app.world.tex('card_'+slot.id),'Original Roman illustration '+slot.id)
					check(child.size==child.texture.get_size()*2,'Illustration uses 2x source pixels')
			var frame=card.get_node('CardFrame')
			check(not frame.is_processing() and frame.material==null,'Static frame has no per-frame script or shader')
			check(frame.mouse_filter==Control.MOUSE_FILTER_IGNORE,'Decorative frame cannot intercept the pointer')
		await capture('cards-'+lang)
		hand.set_active(1,false)
		await create_timer(.3).timeout
		await capture('hover-'+lang)
	app.campaign.g.offered=opening_offers
	app.render_ui()
	await create_timer(.4).timeout
	var hand=app.card_hand
	var pos=hand.slots[0].origin+Vector2(120,140)
	await move_pointer(pos)
	check(hand.active==0,'Real pointer movement raises the first card')
	for down in [true,false]:
		if not down:
			pos.y-=hand.preset.drag_threshold+12
			await move_pointer(pos)
		var event=InputEventMouseButton.new()
		event.position=pos;event.global_position=pos
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
		root.push_input(event,true)
	await create_timer(.3).timeout
	check(app.campaign.g.chosen==opening_offers[0],'Real upward drag and release awards the original card')
	var next_phase='place' if app.campaign.types.has(opening_offers[0]) else 'prepare'
	check(app.campaign.g.phase==next_phase and not app.input_locked,'Victory reward proceeds to placement or camp according to the selected card')
	check(app.campaign.cards==authored,'Rendering leaves all card definitions unchanged')
	app.sound.stop()
	print('%d card face/content/native-pointer checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
