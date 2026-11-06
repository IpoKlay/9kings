extends SceneTree
const OUT='res://../output/route-branches-v1/'
var app
var checks=0
var failures=0
func _init():call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;printerr('FAIL: '+message)
func click(p: Vector2,warp_pointer: bool=true):
	if warp_pointer:Input.warp_mouse(root.get_final_transform()*p)
	await process_frame
	var motion=InputEventMouseMotion.new();motion.position=p;motion.global_position=p
	root.push_input(motion,true)
	for down in [true,false]:
		var event=InputEventMouseButton.new();event.position=p;event.global_position=p
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;root.push_input(event,true)
	await process_frame
func press(control):await click(control.get_global_rect().get_center())
func tile(cell: int) -> Vector2:
	var p=app.world.center(cell);return app.world.project(p.x,p.y)
func capture(name):
	for i in 4:await process_frame;RenderingServer.force_draw()
	root.get_texture().get_image().save_png(OUT+name+'.png')
func swipe_first():
	var point=app.card_hand.slots[0].origin+Vector2(120,130)
	for down in [true,false]:
		if not down:point.y-=app.card_hand.preset.drag_threshold+12
		Input.warp_mouse(root.get_final_transform()*point);await process_frame
		var motion=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
		var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;root.push_input(event,true)
	await create_timer(.4).timeout
func run():
	if DisplayServer.get_name()=='headless':printerr('Native renderer required');quit(1);return
	root.size=Vector2i(1280,720)
	app=load('res://scenes/main.tscn').instantiate();app.settings_path='/private/tmp/eagle-camp-ui.cfg';root.add_child(app)
	app.set_process(false);app.prefs.enabled=false;app.prefs.music_volume=0;app.apply_prefs()
	app.starting_theaters.assign([1]);app.language='zh'
	await process_frame;await press(app.menu_view.get_node('StartGame'));app.expedition_map.settle_entry()
	check(app.expedition.state.mode=='map' and app.campaign.g.buildings.size()==1,'Start opens destination map with infantry only')
	var destination=app.expedition.destinations()[0]
	app.expedition_map.atlas.focus_city(destination);await process_frame
	await press(app.expedition_map.city_buttons[destination]);await press(app.expedition_map.travel_button)
	preload('res://tests/expedition_test_support.gd').finish_departure(app)
	check(app.campaign.g.phase=='battle' and app.card_hand==null,'Actual city clicks enter battle with no starting card')
	check(app.campaign.g.battle.units.filter(func(u):return u.side=='ally').size()==1,'Exactly one infantry squad in the actual game')
	for i in 480:app._process(1.0/60)
	await capture('01-infantry-opening')
	for i in 15000:
		if app.campaign.g.phase!='battle':break
		app._process(1.0/60)
	check(app.campaign.g.battle.report!=null and app.campaign.g.battle.report.won,'Actual process loop wins first city')
	app.advance();await create_timer(.6).timeout
	check(app.campaign.g.phase=='reward' and app.card_hand!=null and app.campaign.g.unlocked_cells.size()==9,'First reward shows a 3x3 camp')
	await capture('02-first-reward-3x3')
	app.campaign.g.offered=['training','archer','medic'];app.campaign.g.offerYear=app.campaign.g.round;app.render_ui();await create_timer(.5).timeout
	await swipe_first()
	check(app.campaign.g.phase=='place','Existing upward card swipe selects a building')
	await click(tile(0));check(app.campaign.g.phase=='place','Clicking locked perimeter cannot place a building')
	await click(tile(11))
	check(app.campaign.building_at(11)!=null and app.campaign.g.phase=='prepare','Unlocked adjacent tile accepts training yard')
	check(is_equal_approx(app.campaign.stats(app.campaign.building_at(12)).attack,17.5),'Training effect is active in the actual campaign')
	await capture('03-adjacent-training')
	await click(tile(11));check(app.dialog_kind=='building','Clicking building opens its details')
	await capture('03b-building-details')
	var move=app.modal.find_child('RepositionBuilding',true,false)
	check(move!=null,'Details expose a reposition button')
	if move==null:quit(1);return
	await press(move);await click(tile(6))
	check(app.camp_action=='' and app.campaign.building_at(6).type=='training','Actual clicks move an existing building')
	check(is_equal_approx(app.campaign.stats(app.campaign.building_at(12)).attack,14),'Moving support diagonally removes its bonus immediately')
	await click(tile(6));await press(app.modal.find_child('RepositionBuilding',true,false));await click(tile(12))
	var swapped=app.campaign.building_at(6)!=null and app.campaign.building_at(12)!=null and app.campaign.building_at(6).type=='legion' and app.campaign.building_at(12).type=='training'
	check(swapped,'Occupied tile click swaps both occupants')
	if not swapped:
		printerr('Swap diagnostic: '+str(app.campaign.g.buildings)+' mouse='+str(app.get_global_mouse_position())+' expected='+str(tile(12)))
		quit(1);return
	# Additional wins are explicit fixtures to isolate reward and expansion UI, not balance claims.
	for i in 2:
		app.continue_expedition();app.travel_to(app.expedition.destinations()[0]);app.campaign.finish(true);app.advance()
		if i==0:app.skip_supply()
	check(app.campaign.g.cities_captured==3 and app.campaign.g.expansion_credits==1,'Third city settlement grants the expansion in actual UI')
	var cards=app.campaign.offers().duplicate()
	var expand=app.ui.find_child('ExpandCamp',true,false)
	check(expand!=null,'Expansion is a separate button alongside card reward')
	if expand==null:quit(1);return
	await press(expand);await capture('04-choose-outer-tile')
	await click(tile(12));check(app.camp_action=='expand' and app.campaign.g.expansion_credits==1,'An already unlocked core tile cannot consume a credit')
	await click(tile(0))
	check(app.campaign.g.unlocked_cells.size()==10 and app.campaign.g.expansion_credits==0,'Selecting an outer corner unlocks one tile')
	check(app.campaign.g.phase=='reward' and app.campaign.offers()==cards and app.card_hand!=null,'Expansion preserves the unchosen card reward')
	app.campaign.g.offered=['archer','legion','medic'];app.render_ui();await create_timer(.5).timeout
	await swipe_first()
	# Leave the OS cursor over the hand: the queued click's own coordinates
	# must select the new corner, even before the hardware pointer catches up.
	await click(tile(0),false)
	check(app.campaign.building_at(0)!=null and app.campaign.building_at(0).type=='archer','The added tile works for actual card placement')
	await capture('05-expanded-camp')
	app.language='en';app.world.language='en';app.render_ui();await capture('06-expanded-camp-english')
	app.open_map();app.show_camp()
	check(app.campaign.g.unlocked_cells.size()==10 and app.campaign.building_at(0)!=null and app.campaign.building_at(0).type=='archer','Map round trip retains the expanded camp')
	if failures:quit(1);return
	# Dense scene is an explicit maximum-capacity fixture, not a claimed playthrough.
	while app.campaign.g.unlocked_cells.size()<25:
		app.campaign.g.expansion_credits=1;app.campaign.expand(app.campaign.expansion_candidates()[0])
	app.campaign.g.buildings=[]
	for cell in 25:
		app.campaign.g.buildings.append({'id':cell+1,'type':['legion','archer','training','medic','spear'][cell%5],'cell':cell,'level':3})
	app.language='zh';app.world.language='zh';app.world.hover_cell=12;app.render_ui()
	await capture('07-full-camp-fixture')
	app.world.selected_cell=13;app.open_dialog('building');await capture('08-hospital-details');app.close_dialog()

	app.starting_theaters.assign([2]);app.start_game();app.expedition_map.settle_entry()
	check(app.campaign.g.unlocked_cells.size()==9 and app.campaign.g.buildings.size()==1 and app.campaign.g.cities_captured==0,'New game resets the run without carrying expansion')
	app.sound.stop();app.music.set_process(false)
	for i in 2:app.music.retire_slot(i)
	await create_timer(.1).timeout;app.queue_free();await process_frame;await process_frame
	print('%d native camp UI checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
