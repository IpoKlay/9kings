extends SceneTree
## Dispatch real viewport events, including modal and in-game routing boundaries.
var app
var checks=0
var failures=0
var quit_requests=0
func _init(): call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok:
		failures+=1
		printerr('FAIL: '+message)
func key(code: int,physical: int=0,echo: bool=false,ctrl: bool=false):
	var event=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=physical
	event.pressed=true
	event.echo=echo
	event.ctrl_pressed=ctrl
	root.push_input(event,true)
	event=event.duplicate()
	event.pressed=false
	root.push_input(event,true)
	await process_frame
func hover(index: int):
	var event=InputEventMouseMotion.new()
	event.position=app.menu_view.options[index].get_global_rect().get_center()
	event.global_position=event.position
	root.push_input(event,true)
	await process_frame
func click(index: int):
	await hover(index)
	for pressed in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=app.menu_view.options[index].get_global_rect().get_center()
		event.global_position=event.position
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		root.push_input(event,true)
	await process_frame
func capture(name: String):
	if DisplayServer.get_name()=='headless': return
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png('res://../output/menu-four/'+name+'.png')
func run():
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='res://../output/menu-four/test-settings.cfg'
	root.add_child(app)
	current_scene=app
	app.set_process(false)
	app.menu_view.set_process(false)
	app.sound.enabled=false
	var menu=app.menu_view
	for lang in ['zh','en']:
		app.language=lang
		app.has_run=false
		app.main_menu=true
		menu.selected=0
		app.render_ui()
		check(menu.options.size()==4,'Always four menu options '+lang)
		check(menu.options.map(func(b):return str(b.name))==['StartGame','ResumeGame','MenuSettings','QuitGame'],'Original game actions preserved')
		check(not menu.option_available(1),'Continue is unavailable without a run')
		check(menu.cursor.texture.get_size()==Vector2(16,16),'Reference pixel cursor is loaded')
		await key(0,KEY_DOWN)
		check(menu.selected==1,'Physical Down selects the next option')
		menu.set_selected(1,false)
		await key(0,KEY_UP)
		check(menu.selected==0,'Physical Up selects the previous option')
		# Menu selection must also work when native GUI focus owns a button.
		for b in menu.options: b.focus_mode=Control.FOCUS_ALL
		menu.options[0].grab_focus()
		await key(KEY_DOWN)
		check(menu.selected==1,'Down is not consumed by native button focus')
		menu.set_selected(1,false)
		await key(KEY_UP)
		check(menu.selected==0,'Up is not consumed by native button focus')
		menu.options[0].release_focus()
		for b in menu.options: b.focus_mode=Control.FOCUS_NONE
		menu.set_selected(0,false)
		for b in menu.options:
			check(b.get_theme_stylebox('normal') is StyleBoxEmpty,'Text menu has no button panel')
			check(b.size.y>=66,'Menu retains a usable click target')
		await key(KEY_UP)
		check(menu.selected==0,'Upper boundary is clamped')
		await key(KEY_S)
		check(menu.selected==1,'S selects Continue')
		check(menu.selection_hint.text==app.loc('main_menu.no_run'),'Unavailable Continue explains why')
		await key(KEY_ENTER)
		check(app.main_menu and not app.has_run,'Unavailable Continue cannot start or alter a run')
		await key(KEY_DOWN)
		check(menu.selected==2,'Down selects Settings')
		await key(KEY_S,0,true)
		check(menu.selected==2,'Key repeat does not skip options')
		await key(KEY_S,0,false,true)
		check(menu.selected==2,'Control shortcuts do not navigate')
		await key(KEY_S)
		check(menu.selected==3,'S selects Quit')
		await key(KEY_DOWN)
		check(menu.selected==3,'Lower boundary is clamped')
		menu.actions[3]=func():quit_requests+=1
		await key(KEY_ENTER)
		check(quit_requests==1,'Enter dispatches the selected Quit action once')
		await key(KEY_ENTER,0,true)
		check(quit_requests==1,'Holding confirm does not repeat an action')
		quit_requests=0
		await key(KEY_W)
		check(menu.selected==2,'W selects previous option')
		menu._process(.35)
		check(absf(menu.cursor.position.y-(menu.options[2].position.y+13))<=5,'Cursor settles at the selected row within 350ms')
		check(is_zero_approx(fmod(menu.cursor.position.x,3)) and is_zero_approx(fmod(menu.cursor.position.y,3)),'Cursor moves on its native pixel grid')
		await capture('settings-selected-'+lang)
		await key(KEY_SPACE)
		check(app.dialog_kind=='settings','Space opens selected Settings')
		var selected_before=menu.selected
		await key(KEY_W)
		await key(KEY_DOWN)
		await key(KEY_ENTER)
		check(app.dialog_kind=='settings' and menu.selected==selected_before,'Open settings blocks menu navigation and confirmation')
		await key(KEY_ESCAPE)
		check(app.dialog_kind=='' and menu.selected==2,'Escape closes settings and preserves selection')
		await key(KEY_UP)
		check(menu.selected==1,'Up selects Continue')
		await key(0,KEY_W)
		check(menu.selected==0,'Physical W is supported')
		await key(0,KEY_S)
		check(menu.selected==1,'Physical S is supported')
		await hover(3)
		check(menu.selected==3,'Mouse hover moves the same selection')
		await key(KEY_W)
		check(menu.selected==2,'Keyboard takes over from mouse hover')
		await click(2)
		check(app.dialog_kind=='settings','Mouse click activates Settings')
		app.close_dialog()
		menu.set_selected(0,false)
		menu.render()
		await capture('menu-'+lang)
		app.input_locked=true
		await key(KEY_S)
		await key(KEY_ENTER)
		check(menu.selected==0 and app.main_menu,'Input lock blocks navigation and activation')
		app.input_locked=false
		await key(KEY_ENTER)
		check(not app.main_menu and app.has_run and app.expedition_map.visible,'Enter starts the native expedition')
		var state=app.expedition.state.duplicate(true)
		var start_bag=app.starting_theaters.duplicate()
		var game_selection=menu.selected
		await key(KEY_S)
		await key(KEY_DOWN)
		await key(KEY_SPACE)
		check(not app.main_menu and menu.selected==game_selection and app.expedition.state==state,'Menu keys do not leak into expedition play')
		app.return_to_menu()
		check(menu.option_available(1),'Continue becomes available after starting')
		menu.set_selected(0,false)
		await key(KEY_DOWN)
		await key(KEY_KP_ENTER)
		check(not app.main_menu and app.expedition.state==state and app.starting_theaters==start_bag,'Keypad Enter resumes without resetting or rerolling')
		app.return_to_menu()
	app.sound.stop()
	print('%d four-option menu/input checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
