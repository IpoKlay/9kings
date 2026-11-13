extends SceneTree
const Battle=preload('res://scripts/strategy/battle.gd')
## Normal menu and live StrategyBattle loop; only the small encounter is authored.
const OUT='res://../output/current-rts-functional/'
var failures=[]
var checks=[]
var app
var trial
func _initialize():call_deferred('run')
func check(ok: bool,note: String):
	checks.append({'pass':ok,'note':note})
	if not ok:failures.append(note);push_error(note)
func click(p: Vector2,button=MOUSE_BUTTON_LEFT,ctrl=false):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=button;e.pressed=down;e.ctrl_pressed=ctrl;root.push_input(e,true)
func key(code: int):
	for down in [true,false]:
		var e=InputEventKey.new();e.physical_keycode=code;e.keycode=code;e.pressed=down;root.push_input(e,true)
func point(p: Vector2) -> Vector2:return (trial.field.project(p)-trial.camera_offset)*trial.zoom
func until(condition: Callable,seconds: float) -> bool:
	var end=Time.get_ticks_msec()+int(seconds*1000.)
	while Time.get_ticks_msec()<end:
		if condition.call():return true
		await process_frame
	return condition.call()
func shot(name: String):
	if DisplayServer.get_name()=='headless':return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name+'.png')
func find_button(node: Node,label: String):
	if node is Button and node.text==label:return node
	for child in node.get_children():
		var found=find_button(child,label)
		if found!=null:return found
	return null
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.title='新版 RTS · 选队与冲锋功能验收'
	app=load('res://scenes/main.tscn').instantiate();app.settings_path=OUT+'settings.cfg';root.add_child(app);app.sound.enabled=false
	for i in 4:await process_frame
	click(app.menu_view.get_node('%TacticalTrial').get_global_rect().get_center())
	for i in 4:await process_frame
	trial=app.active_trial
	if trial==null:check(false,'Normal menu opens battle');quit(1);return
	var r=trial.rules;var ui=trial.get_meta('strategy_interface')
	check(r is Battle,'Normal entry uses current StrategyBattle')
	check(not trial.get_node('BattleHUD').is_visible_in_tree(),'Legacy HUD stays hidden')
	check(r.population()==9 and r.buildings.any(func(b):return b.get('initial_wall',false)),'Current nine-person walled opening is retained')
	await shot('01-current-opening')
	var riders=[]
	for i in 4:
		var u=r.spawn_person('light_cavalry','ally',Vector2(450,2460+i*36));riders.append(u)
		var defender=r.spawn_person('shield','enemy',Vector2(800,2460+i*36));defender.soldiers[0].heading=Vector2.LEFT
	var peak=r.units.reduce(func(total,u):return total+u.soldiers.size(),0)
	check(peak<=114,'Authored encounter remains within 114 actual soldiers')
	r.world.refresh_sight(r);trial.zoom=1.;trial.set_camera(Vector2(0,1950))
	for i in 3:await process_frame
	click(point(riders[0].soldiers[0].position)-Vector2(0,20),MOUSE_BUTTON_LEFT,true)
	await process_frame
	check(trial.selected_people().size()==4,'Ctrl-click selects the four current cavalry')
	key(KEY_C);click(point(Vector2(950,2514)))
	check(riders.all(func(u):return u.soldiers[0].has('charge_run')),'C and ground click issue four independent charges')
	await shot('02-charge-start')
	key(KEY_SPACE);var stopped=r.elapsed;await create_timer(.25).timeout
	check(trial.paused and r.elapsed==stopped,'Space pauses the live game')
	key(KEY_SPACE)
	check(await until(func():return riders.any(func(u):return u.soldiers[0].has('rider_contact')),8.),'Live cavalry reach actual enemy contact')
	await shot('03-contact')
	var feedback=trial.field.impact_feedback
	check(feedback!=null and feedback.contact_flash_roles.has('attacker') and feedback.contact_flash_roles.has('victim'),'Formal render flashes both participants on actual charge contact')
	check(await until(func():return riders.all(func(u):return not u.soldiers[0].has('charge_run')),8.),'All charges end into ordinary combat')
	await shot('04-follow-up')
	key(KEY_SPACE)
	click(point(Vector2(620,2650)),MOUSE_BUTTON_RIGHT)
	check(riders.filter(func(u):return u.hp>0).all(func(u):return u.soldiers[0].personal_order=='move'),'Paused right-click replaces cavalry orders')
	key(KEY_SPACE)
	await create_timer(1.).timeout
	key(KEY_H)
	check(riders.filter(func(u):return u.hp>0).all(func(u):return u.soldiers[0].personal_order=='hold'),'H holds the selected cavalry at their current positions')
	# Controlled result branch, not a naturally won full match.
	for b in r.buildings:
		if b.side=='enemy' and b.kind=='town':b.hp=0.
	check(await until(func():return r.phase=='victory' and ui.result_panel.visible,2.),'Current victory UI follows the existing town objective')
	await shot('05-result-fixture')
	var retry=find_button(ui.result_panel,'重新开始')
	check(retry!=null,'Current result panel has a restart button')
	if retry!=null:click(retry.get_global_rect().get_center())
	check(await until(func():return trial.rules!=r and trial.rules.population()==9,2.),'Restart restores the current nine-person opening')
	check(trial.soldier_ids.is_empty() and trial.squad_ids.is_empty() and not trial.paused,'Restart clears selection and pause')
	await shot('06-retry')
	check(trial.field.impact_feedback!=feedback and trial.field.impact_feedback.contact_flash_roles.is_empty(),'Retry replaces contact feedback with clean state')
	FileAccess.open(OUT+'results.json',FileAccess.WRITE).store_string(JSON.stringify({'checks':checks,'failures':failures,'peak_people':peak,'input':'Engine mouse/key events; live engine loop, not system mouse','limits':['Encounter positions and eight soldiers authored after normal entry','Victory is controlled town-death branch, not natural full-match acceptance','No performance acceptance']},'\t'))
	trial.closed.emit();app.queue_free();await process_frame;await create_timer(.15).timeout
	print('Current RTS live input: ',checks.size(),' checks, ',failures.size(),' failures')
	quit(1 if not failures.is_empty() else 0)
