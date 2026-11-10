extends SceneTree
const Strategy=preload('res://scripts/strategy/battle.gd')
## Input regression: a rejected route must not poison the draft or replace a live order.
const OUT='res://../output/audited-sync/route/'
const Whiteboard=preload('res://scripts/tactical/whiteboard_battle.gd')
var checks=[]
var failures=0
var evidence='after'
func _initialize():call_deferred('run')
func check(ok: bool,note: String):
	checks.append({'pass':ok,'check':note})
	if not ok:failures+=1;push_error(note)
func click(p: Vector2,shift=false,button=MOUSE_BUTTON_LEFT,double=false):
	for down in [true,false]:
		var e=InputEventMouseButton.new()
		e.position=p;e.global_position=p;e.button_index=button;e.pressed=down;e.shift_pressed=shift;e.double_click=double
		root.push_input(e,true)
func key(code: Key):
	for down in [true,false]:
		var e=InputEventKey.new();e.physical_keycode=code;e.pressed=down;root.push_input(e,true)
func screen(t,p: Vector2) -> Vector2:return (t.field.project(p)-t.camera_offset)*t.zoom
func select_person(t,u,slot: int=0):
	click((t.rules.Soldiers.point(t.rules,u,slot)-Vector2(0,20)-t.camera_offset)*t.zoom)
func snapshot(t,name: String):
	if DisplayServer.get_name()=='headless':return
	t.refresh();t.field.queue_redraw()
	for frame in 3:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+evidence+'-'+name+'.png')
func run():
	if '--before' in OS.get_cmdline_user_args():evidence='before'
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	seed(71)
	var app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/tmp/eagle-command-route.cfg'
	root.add_child(app);app.sound.enabled=false;app.language='zh'
	await process_frame
	click(app.menu_view.get_node('%TacticalTrial').get_global_rect().get_center())
	var t=app.active_trial
	check(is_instance_valid(t),'Real menu click opens the current battle')
	if not is_instance_valid(t):quit(1);return
	check(t.rules is Strategy,'Production menu preserves the strategy entry')
	t.closed.emit();await process_frame
	# Exercise legacy route controls in their own scene, not the strategy UI.
	t=load('res://scenes/tactical_trial.tscn').instantiate();t.rules=Whiteboard.new(false);t.app=app;root.add_child(t);app.hide()
	t.set_process(false)
	click(t.combined_button.get_global_rect().get_center());t.refresh()
	click(t.start_button.get_global_rect().get_center());key(KEY_SPACE)
	check(t.rules is Whiteboard and t.rules.units.size()==14 and t.paused and t.rules.phase=='battle','Seven-arm deployment, start and pause use normal input')
	# Separate controlled movement fixture: enemies remain out of reach during route planning.
	var r=t.rules;r.units.clear()
	r.spawn('legion','ally',Vector2(1400,2300));r.spawn('cavalry','ally',Vector2(1900,2500));r.spawn('legion','enemy',Vector2(2900,300))
	for unit in r.units:unit.order='hold'
	var u=r.units[0];var horse=r.units[1]
	select_person(t,u)
	check(t.soldier_ids==[Vector2i(u.id,0)] and t.selected=='personal_route','Click selects an actual soldier')
	var old_goal=Vector2(1500,2450)
	click(screen(t,old_goal),false,MOUSE_BUTTON_RIGHT)
	check(u.soldiers[0].personal_order=='move','Right click starts a personal movement order while paused')
	select_person(t,u);key(KEY_TAB)
	var initial=u.soldiers.duplicate(true)
	var neighbour: Vector2=r.Soldiers.ground_position(r,u,1)
	var first=Vector2(1400,2500);var second=Vector2(1200,2500);var finish=Vector2(1200,2300)
	click(screen(t,first),true)
	check(t.draft_waypoints==[first] and u.soldiers==initial,'First waypoint stages without replacing any live order')
	var outside=Vector2(-80,2500)
	click(screen(t,outside),true);t.refresh()
	check(t.draft_waypoints==[first] and u.soldiers==initial,'Outside Shift-click is rejected without poisoning the valid draft')
	check(t.notice_seconds>0 and t.hint.text.contains(t.notice) and not t.notice.is_empty(),'Rejected waypoint remains visible while paused')
	await snapshot(t,'rejected-waypoint')
	click(screen(t,outside));t.refresh()
	check(t.draft_waypoints==[first] and u.soldiers==initial and t.selected=='personal_route','Rejected endpoint preserves draft and old movement')
	check(t.hint.text.contains(t.notice) and t.notice_seconds>0,'Personal-route instructions cannot hide an unreachable notice')
	app.language='en';click(screen(t,outside));t.refresh()
	check(t.hint.text.begins_with('Paused · Cannot reach'),'English paused error is visible as well')
	app.language='zh'
	# Do not let a baseline failure cascade into the rest of the independent checks.
	if t.draft_waypoints!=[first]:t.draft_waypoints.assign([first])
	click(screen(t,second),true)
	check(t.draft_waypoints==[first,second] and u.soldiers==initial,'A corrected waypoint extends the valid plan')
	check(t.notice_seconds==0,'A valid correction clears the stale error')
	key(KEY_TAB);key(KEY_TAB)
	check(t.draft_waypoints==[first,second] and t.paused,'Overview toggles preserve the draft and pause')
	key(KEY_TAB);t.pointer=finish;await snapshot(t,'route-plan');key(KEY_TAB)
	click(screen(t,finish))
	check(t.selected=='' and t.draft_waypoints.is_empty() and u.soldiers[0].route_stops==[first,second,finish],'Confirm commits exactly the authored route')
	t._process(.1)
	check(u.soldiers[0].position==initial[0].position,'Paused planning never advances the soldier')
	key(KEY_SPACE)
	var visited=[false,false];var turned=false
	for frame in 1000:
		t._process(1./60)
		for i in 2:visited[i]=visited[i] or u.soldiers[0].position.distance_to([first,second][i])<.05
		turned=turned or u.soldiers[0].heading.x<-.8
		if frame%60==0:await process_frame
		if u.soldiers[0].personal_order=='idle':break
	check(visited==[true,true] and turned,'Soldier physically reaches both turns and changes facing')
	check(u.soldiers[0].position.distance_to(finish)<17. and u.soldiers[0].path.is_empty(),'Soldier settles at final goal')
	check(r.Soldiers.ground_position(r,u,1)==neighbour,'Unselected neighbour keeps its position')
	key(KEY_SPACE);select_person(t,u)
	click(screen(t,Vector2(1600,2300)),false,MOUSE_BUTTON_RIGHT)
	select_person(t,u);click(screen(t,Vector2(1400,2400)),true)
	var queued=u.soldiers[0].duplicate(true)
	key(KEY_ESCAPE)
	check(t.selected=='' and t.draft_waypoints.is_empty() and t.paused and u.soldiers[0]==queued,'Esc cancels only the draft and preserves the live order')
	select_person(t,u)
	click((r.Soldiers.point(r,u,1)-Vector2(0,20)-t.camera_offset)*t.zoom,true)
	check(t.soldier_ids.size()==2,'Shift click adds a second actual soldier')
	click(screen(t,first),true)
	var subset=u.soldiers.duplicate(true)
	click(screen(t,Vector2(20,2500)),true)
	check(t.draft_waypoints==[first] and u.soldiers==subset,'An inside-map cursor is rejected if any selected soldier would end outside')
	key(KEY_ESCAPE)
	# A blocked point is rejected as well as an out-of-map point.
	select_person(t,u)
	var blocked=Vector2(1350,2350)
	r.terrain.replace_rocks([Rect2(blocked-Vector2(20,20),Vector2(40,40))])
	click(screen(t,blocked),true)
	check(t.draft_waypoints.is_empty() and u.soldiers[0]==queued,'Rock occupancy rejects a staged waypoint without changing orders')
	r.terrain.replace_rocks([])
	key(KEY_ESCAPE)
	# Whole-regiment route and mid-march replacement still use the same actual feet.
	click(screen(t,horse.pos),false,MOUSE_BUTTON_LEFT,true)
	check(t.squad_ids==[horse.id] and t.soldier_ids.is_empty(),'Double-click selects the complete horse regiment')
	click(screen(t,Vector2(1900,2300)),true);click(screen(t,Vector2(2100,2300)))
	key(KEY_SPACE)
	for frame in 30:t._process(1./60)
	key(KEY_SPACE)
	var feet=horse.soldiers.map(func(a):return a.position)
	var replacement=Vector2(2100,2600)
	click(screen(t,replacement),false,MOUSE_BUTTON_RIGHT)
	check(horse.soldiers.map(func(a):return a.position)==feet and horse.soldiers.all(func(a):return a.route_stops.size()==1),'Mid-march replacement discards old turns without teleporting anyone')
	key(KEY_SPACE)
	for frame in 500:
		t._process(1./60)
		if frame%60==0:await process_frame
		if horse.order=='idle':break
	check(horse.order=='idle' and horse.pos.distance_to(replacement)<25.,'All riders settle at the replacement destination')
	key(KEY_H)
	check(horse.soldiers.all(func(a):return a.personal_order=='hold'),'H holds the selected regiment at its actual positions')
	t.paused=true;await snapshot(t,'arrived')
	t.retry()
	check(t.rules.phase=='deploy' and t.soldier_ids.is_empty() and t.squad_ids.is_empty() and t.draft_waypoints.is_empty() and not t.paused,'Retry removes selection, drafts and pause')
	FileAccess.open(OUT+evidence+'-checks.json',FileAccess.WRITE).store_string(JSON.stringify({'checks':checks,'failures':failures,'renderer':DisplayServer.get_name()},'\t'))
	t.queue_free();app.queue_free();await process_frame;await create_timer(.15).timeout
	print('Command route input: ',checks.size(),' checks, ',failures,' failures')
	quit(1 if failures else 0)
