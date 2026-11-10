extends SceneTree
const Strategy=preload('res://scripts/strategy/battle.gd')
## Real main-menu entry, input routing and rendered evidence for the whiteboard.
const OUT='res://../output/audited-sync/whiteboard/'
const Battle=preload('res://scripts/tactical/whiteboard_battle.gd')
const Legacy=preload('res://scripts/tactical/square_battle.gd')
var checks=[]
var failures=0
var metrics={}
func _initialize():call_deferred('run')
func check(ok: bool,note: String):
	checks.append({'pass':ok,'check':note})
	if not ok:failures+=1;push_error(note)
func click(p: Vector2,shift=false,button=MOUSE_BUTTON_LEFT,double=false):
	for down in [true,false]:
		var e=InputEventMouseButton.new()
		e.position=p;e.global_position=p;e.button_index=button;e.pressed=down;e.shift_pressed=shift;e.double_click=double
		root.push_input(e,true)
func tab():
	var e=InputEventKey.new();e.physical_keycode=KEY_TAB;e.pressed=true;root.push_input(e,true)
	e=InputEventKey.new();e.physical_keycode=KEY_TAB;e.pressed=false;root.push_input(e,true)
func screen(t,p: Vector2) -> Vector2:return (t.field.project(p)-t.camera_offset)*t.zoom
func snap(label: String,t=null):
	if DisplayServer.get_name()=='headless':return
	if t!=null:t.refresh();t.field.queue_redraw();t.field.pass_layout.queue_redraw()
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT+label+'.png')==OK,'Save visible '+label)
	if t!=null:
		var im: Image=t.field.get_viewport().get_texture().get_image()
		im.save_png(OUT+label+'-field-native.png')
func run():
	seed(71)
	var main=load('res://scenes/main.tscn').instantiate()
	main.settings_path='/tmp/eagle-whiteboard-validation.cfg'
	root.add_child(main);main.sound.enabled=false
	for i in 3:await process_frame
	await snap('menu')
	var entry: Button=main.menu_view.get_node('%TacticalTrial')
	check(entry.is_visible_in_tree(),'Normal main menu exposes legion battle')
	click(entry.get_global_rect().get_center())
	var t=main.active_trial
	check(is_instance_valid(t),'Actual menu mouse click opens battle')
	if not is_instance_valid(t):quit(1);return
	check(t.rules is Strategy,'Production menu keeps strategy rules')
	t.closed.emit();await process_frame
	t=load('res://scenes/tactical_trial.tscn').instantiate();t.rules=Battle.new();t.app=main;root.add_child(t);main.hide()
	t.set_process(false)
	var r=t.rules
	check(r is Battle,'Dedicated fixture loads whiteboard rules')
	check(r.bounds==Rect2(0,0,3200,3200),'Default world is confirmed 3200 square')
	check(r.projection==Transform2D.IDENTITY and r.ground_basis==Transform2D.IDENTITY,'Ground and visual square are uncompressed')
	check(r.terrain.bounds==r.bounds and r.powers.bounds==r.bounds,'Navigation and powers use shared map bounds')
	check(t.field.pass_layout.scene_file_path=='res://scenes/battlefields/whiteboard_battlefield.tscn','Actual whiteboard scene is loaded')
	check(t.field.LANDSCAPE==r.bounds.grow(Battle.MAP.values.camera_margin),'Camera uses shared bounds and margin')
	check(t.field.pass_layout.has_node('Ground') and t.field.environment==null and not t.field.has_node('RomanSiege'),'Grass present without legacy pass environment')
	check(r.terrain.ROCKS.is_empty(),'No legacy rock collision')
	for a in [Vector2(250,250),Vector2(250,2950),Vector2(2950,250)]:
		check(r.terrain.clear_segment('legion',a,Vector2(2950,2950)),'Unobstructed cross-map segment '+str(a))
	check(not r.deploy('legion',r.bounds.get_center()) and not r.deploy('legion',Vector2(1600,400)),'Neutral and enemy deployment rejected')
	check(not r.deployment_valid(Vector2(1600,1901)) and not r.deployment_valid(Vector2(3199,2300)),'Deployment footprint cannot cross zone or map boundary')
	check(r.deployment_valid(Vector2(2700,2800)),'Expanded area beyond old 2100 is deployable')
	t.combined_button.pressed.emit();t.refresh()
	check(r.alive('ally').size()==7 and r.alive('enemy').size()==7,'Seven-arm preset deploys without overlap failures')
	var legacy=Legacy.new()
	for u in r.units:
		check((r.deployment if u.side=='ally' else r.enemy_zone).has_point(u.pos),'Initial unit inside own deployment '+str(u.id))
		check(r.contact_profiles[u.kind].files==legacy.contact_profiles[u.kind].files and r.contact_profiles[u.kind].scale==legacy.contact_profiles[u.kind].scale,'Unit count and scale preserved '+u.kind)
	check(t.zoom==1.,'Normal zoom remains 1.0')
	var frontage=(r.config.types.legion.files-1)*r.terrain.layout('legion',true).x*t.zoom/1920.
	metrics.legion_frontage_screen_fraction=frontage
	check(frontage>.13 and frontage<.16,'Single-row frontage remains about 15 percent')
	await snap('default',t)
	var offset: Vector2=t.camera_offset
	tab()
	check(is_equal_approx(t.zoom,760./3200.),'Tab fits true 3200 square')
	for p in [r.bounds.position,Vector2(3200,0),r.bounds.end,Vector2(0,3200)]:
		check(Rect2(0,80,1920,900).has_point(screen(t,p)),'Overview shows map corner '+str(p))
	await snap('overview',t)
	tab();check(t.zoom==1. and t.camera_offset==offset,'Tab restores exact default camera')
	var motion=InputEventMouseMotion.new();motion.position=Vector2(1000,500);motion.relative=Vector2(80,-40);motion.button_mask=MOUSE_BUTTON_MASK_MIDDLE
	root.push_input(motion,true)
	check(t.camera_offset!=offset,'Middle mouse drag pans')
	var anchor: Vector2=t.field_point(Vector2(1000,500))
	click(Vector2(1000,500),false,MOUSE_BUTTON_WHEEL_UP)
	check(t.zoom>1. and t.field_point(Vector2(1000,500)).distance_to(anchor)<3.,'Wheel zoom preserves cursor anchor')
	t.reset_camera()
	t.start_button.pressed.emit();check(r.phase=='battle','Begin starts real battle')
	t.get_node('BattleHUD/TopActions/PauseButton').pressed.emit()
	check(t.paused,'Pause button pauses')
	var horse=r.alive('ally').filter(func(u):return u.kind=='cavalry')[0]
	click(screen(t,horse.pos),false,MOUSE_BUTTON_LEFT,true)
	check(t.squad_ids==[horse.id],'Double click selects cavalry regiment')
	var first: Vector2=horse.pos+Vector2(-100,-180)
	var goal: Vector2=horse.pos+Vector2(-140,-300)
	click(screen(t,first),true)
	check(t.draft_waypoints.size()==1,'Shift click stages waypoint')
	var ids=t.squad_ids.duplicate();var draft=t.draft_waypoints.duplicate()
	tab();tab()
	check(t.squad_ids==ids and t.draft_waypoints==draft and t.paused,'Overview preserves selection, route draft and pause')
	click(screen(t,goal))
	check(horse.order=='move' and horse.waypoints.size()==1,'Click commits multi-leg route')
	var previous: Vector2=horse.pos
	t._process(.1)
	check(horse.pos==previous and r.elapsed==0,'Paused simulation and movement stay frozen')
	var empty: Array[Vector2]=[]
	check(not r.march_route(horse.id,empty,Vector2(-50,2000)) and not r.march_route(horse.id,empty,Vector2(3250,2000)),'Outside-map movement rejected')
	check(r.terrain.leg('cavalry',horse.pos,Vector2(2800,2800)).size()==1,'Expanded map destination beyond 2100 has direct path')
	t.get_node('BattleHUD/TopActions/PauseButton').pressed.emit()
	for i in 120:t._process(1./60)
	check(horse.pos.distance_to(previous)>20 and r.elapsed>1.9,'Unpaused route actually moves')
	# Fresh normal armies: bounded simulation to first real melee, no performance workload.
	t.retry();t.combined_button.pressed.emit();t.start_button.pressed.emit();t.assault_button.pressed.emit();r=t.rules
	var melee=false
	var reached=false
	for frame in 2100:
		t._process(1./60)
		reached=reached or r.alive('enemy').any(func(u):return r.neutral_zone.has_point(u.pos))
		melee=melee or t.field.effects.any(func(e):return e.has('attacker_slot') and e.get('damage',0)>0 and e.kind!='arrow')
		if frame%120==0:await process_frame
		if melee and r.units.any(func(u):return u.side=='ally' and u.hp<u.max_hp) and r.units.any(func(u):return u.side=='enemy' and u.hp<u.max_hp):break
	metrics.first_melee_seconds=r.elapsed
	check(reached,'Enemies cross neutral strip')
	check(melee,'Real soldier melee produces damage')
	check(r.units.any(func(u):return u.side=='ally' and u.hp<u.max_hp) and r.units.any(func(u):return u.side=='enemy' and u.hp<u.max_hp),'Both sides exchange real damage')
	t.set_camera(r.bounds.get_center()-Vector2(960,530));await snap('combat',t)
	# Outcome branch fixture, explicitly separate from the naturally simulated first contact.
	for u in r.alive('enemy'):r.hurt(u,u.hp)
	for i in 240:
		t._process(1./60)
		if r.phase=='victory':break
	check(r.phase=='victory','Eliminating enemy triggers victory after death lifecycle')
	t.paused=true;t.start_button.pressed.emit()
	check(t.rules is Battle and t.rules.phase=='deploy' and not t.paused and t.rules.alive('ally').is_empty() and t.rules.alive('enemy').size()==7,'Result button retries into clean whiteboard deployment')
	check(t.zoom==1. and t.squad_ids.is_empty() and t.draft_waypoints.is_empty() and t.field.effects.is_empty(),'Retry resets camera, selection, route and effects')
	t.defender_button.pressed.emit()
	check(not t.rules is Legacy and t.rules.defender_preset,'Original pass still available')
	# Exercise scene reload from an authored battlefield back to whiteboard.
	t.rules=Battle.new();t.field.load_battlefield();t.reset_camera()
	check(t.field.pass_layout.scene_file_path.ends_with('whiteboard_battlefield.tscn') and t.field.environment==null,'Whiteboard scene can reload after pass without old environment')
	t.queue_free();main.queue_free();await process_frame
	var preset: Resource=Battle.MAP
	var original: Rect2=preset.values.bounds
	var authored=Rect2(0,0,4000,4000)
	preset.values.bounds=authored
	var enlarged=Battle.new()
	var preview=load('res://scenes/battlefields/whiteboard_battlefield.tscn').instantiate()
	check(enlarged.bounds==authored and enlarged.terrain.bounds==authored and enlarged.powers.bounds==authored,'Changing resource enlarges world, navigation and powers together')
	check(preview.landscape_rect==authored.grow(200),'Editor scene follows same configurable bounds')
	check(enlarged.enemy_zone==Rect2(0,0,4000,1700) and enlarged.neutral_zone==Rect2(0,1700,4000,600) and enlarged.deployment==Rect2(0,2300,4000,1700),'Deployment regions follow authored enlarged bounds')
	check(enlarged.deployment_rows()[0].slice(1)==[1640.,2500.] and enlarged.alive('enemy')[0].pos==Vector2(1640,1500),'Both presets follow enlarged center')
	preset.values.bounds=original;preview.free()
	var restored=Battle.new()
	check(restored.bounds==original and restored.terrain.bounds==original and restored.deployment_rows()[0].slice(1)==[1240.,2100.],'Restoring resource restores default world and preset')
	var f=FileAccess.open(OUT+'engine-validation.json',FileAccess.WRITE)
	f.store_string(JSON.stringify({'checks':checks,'failures':failures,'metrics':metrics,'renderer':DisplayServer.get_name()},'\t'));f.close()
	print('Whiteboard: ',checks.size(),' checks, ',failures,' failures; ',metrics)
	quit(1 if failures else 0)
