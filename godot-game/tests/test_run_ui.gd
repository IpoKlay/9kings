extends SceneTree
var app
var view:SubViewport
var checks=0
var failures=0
const OUT='res://../output/expedition-save-recovery/'
const PATH='/private/tmp/eagle-run-ui.cfg'
func _init():call_deferred('run')
func check(ok,msg):
	checks+=1
	if not ok:failures+=1;printerr('FAIL: ',msg)
func click(node):
	var p=node.get_global_rect().get_center()
	for down in [true,false]:
		var ev=InputEventMouseButton.new();ev.position=p;ev.global_position=p;ev.button_index=MOUSE_BUTTON_LEFT;ev.pressed=down;view.push_input(ev,true)
	await process_frame
func capture(name):
	await create_timer(.75).timeout
	await process_frame;RenderingServer.force_draw();view.get_texture().get_image().save_png(OUT+name+'.png')
func boot():
	app=load('res://scenes/main.tscn').instantiate();app.settings_path=PATH;app.run_path_override=PATH+'.run';view.add_child(app);app.set_process(false);app.sound.enabled=false
	app.language='zh';app.render_ui();await process_frame
func reboot():
	app.sound.stop();app.queue_free();await process_frame;await process_frame;await boot()
func run():
	for suffix in ['.run','.run.bak','.run.tmp']:DirAccess.remove_absolute(PATH+suffix)
	var host=Window.new();root.add_child(host);view=SubViewport.new();view.size=Vector2i(1280,720)
	view.size_2d_override=Vector2i(1920,1080);view.size_2d_override_stretch=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;host.add_child(view)
	await boot();await click(app.menu_view.get_node('StartGame'))
	check(app.has_run and not app.save_error,'Fresh run saved')
	var id=app.expedition.destinations()[0];app.travel_to(id)
	check(app.campaign.g.phase=='battle' and not app.save_error,'Battle checkpoint saved')
	await reboot();check(app.has_run and app.main_menu,'Cold launch finds run')
	await click(app.menu_view.get_node('ResumeGame'))
	check(app.expedition.can_travel(id) and app.campaign.g.phase=='prepare','Cold resume before same battle')
	app.travel_to(id);app.campaign.finish(false);app.advance()
	check(app.expedition.state.mode=='camp','Loss opens camp')
	await capture('01-defeat-regroup')
	await click(app.ui.get_node('RecoveryOrder'))
	check(app.campaign.g.reward_context=='recovery','Recovery card hand')
	await capture('02-temporary-orders')
	await reboot();await click(app.menu_view.get_node('ResumeGame'))
	check(app.campaign.g.reward_context=='recovery' and app.card_hand!=null,'Recovery choice resumes')
	# Exercise the same upward gesture used by ordinary cards.
	await create_timer(.4).timeout
	var hand=app.card_hand;var p=hand.slots[0].origin+Vector2(120,130)
	for down in [true,false]:
		if not down:p.y-=hand.preset.drag_threshold+20
		var motion=InputEventMouseMotion.new();motion.position=p;motion.global_position=p;motion.button_mask=MOUSE_BUTTON_MASK_LEFT if not down else 0;view.push_input(motion,true)
		var ev=InputEventMouseButton.new();ev.position=p;ev.global_position=p;ev.button_index=MOUSE_BUTTON_LEFT;ev.pressed=down;view.push_input(ev,true)
	await create_timer(.5).timeout
	check(app.campaign.order_rank('shield')==1 and app.campaign.rank('shield')==0,'Swipe claims temporary order')
	await reboot();await click(app.menu_view.get_node('ResumeGame'))
	check(app.campaign.order_rank('shield')==1 and not app.expedition.can_reorganize(),'Temporary order and limit persist')
	# Explicit victory fixture tests elite reward UI, not balance.
	app.campaign.reset(23);app.expedition.reset(1);app.expedition.state.opening='done';app.expedition.state.current='246369'
	app.expedition.state.visited=['423025','148127','246349','246369'];app.travel_to('265883');app.campaign.finish(true);app.advance()
	check(app.campaign.g.reward_context=='elite','Elite reward context')
	await capture('03-elite-reward')
	app.language='en';app.render_ui();await capture('04-elite-reward-en')
	var hint=app.ui.get_children().filter(func(n):return n is Label and n.text.begins_with('Elite spoils:'))[0]
	check(hint.get_line_count()*hint.get_line_height()<=hint.size.y,'English reward hint fits')
	app.language='zh';app.render_ui()
	await click(app.ui.get_node('EliteReroll'));var offers=app.campaign.offers()
	check(app.campaign.g.reward_rerolls==0,'Click consumes redraw')
	await reboot();await click(app.menu_view.get_node('ResumeGame'))
	check(app.campaign.offers()==offers and not app.ui.has_node('EliteReroll'),'Cold resume cannot repeat redraw')
	app.return_to_menu();await click(app.menu_view.get_node('StartGame'))
	check(app.dialog_kind=='new_run','Replacing a saved run asks in-game')
	app.close_dialog();check(app.campaign.offers()==offers,'Cancel retains run')
	app.sound.stop();print(checks,' native save/recovery checks, ',failures,' failures');quit(1 if failures else 0)
