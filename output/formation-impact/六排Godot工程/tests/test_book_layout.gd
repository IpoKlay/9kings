extends SceneTree
const RPGUI=preload('res://scripts/rpg_ui.gd')
var app
var checks=0
var failures=0
func _init(): call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1;printerr('FAIL: '+message)
func press(keycode: Key):
	var key=InputEventKey.new();key.keycode=keycode;key.pressed=true
	root.push_input(key,true)
	await process_frame
func click(control: Control):
	var pos=control.get_global_rect().get_center()
	for down in [true,false]:
		var event=InputEventMouseButton.new();event.position=pos;event.global_position=pos
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;root.push_input(event,true)
	await process_frame
func capture(name: String) -> Image:
	await process_frame
	if DisplayServer.get_name()=='headless': return null
	RenderingServer.force_draw()
	var image=root.get_texture().get_image()
	image.save_png('res://../output/book-layout-v3/'+name+'.png')
	return image
func run():
	root.size=Vector2i(1920,1080)
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/private/tmp/eagle-book-layout-v3.cfg'
	root.add_child(app);current_scene=app;app.sound.enabled=false
	app.restart_expedition(1)
	var state=app.expedition.state.duplicate(true)
	var city=''
	for node in app.expedition.data.nodes:
		if node.latin=='Oea': city=node.id
	check(city!='','Reference city exists')
	for language in ['zh','en']:
		app.language=language
		app.documents.open_archive(city)
		await process_frame
		var book=app.modal.get_child(1)
		var close=book.get_node('ArchiveClose')
		check(close.text=='×' and close.position.x<70 and close.position.y<30,'Only close cross is at the upper left')
		for style in ['normal','hover','pressed','focus']:
			check(close.get_theme_stylebox(style) is StyleBoxEmpty,'Close has no square background: '+style)
		for name in ['ArchivePrevious','ArchiveNext']:
			var edge=book.get_node(name)
			check(edge.text=='' and edge.icon==null and edge.get_theme_stylebox('normal') is StyleBoxEmpty,'Page edges contain no visible arrow UI')
		for child in book.get_children():
			if child is Label:
				var page: Rect2=RPGUI.BOOK_PAGES[0 if child.position.x<532 else 1]
				check(absf(child.get_rect().get_center().x-page.get_center().x)<1,'Text centered within its page: '+child.text)
				check(child.horizontal_alignment==HORIZONTAL_ALIGNMENT_CENTER,'Text uses centered alignment')
			if child is Button: check(child.text!=app.loc('documents.return_to_map'),'Return-to-map button removed')
		var art=book.get_node('ArchiveLocation')
		check(art.get_rect().get_center()==RPGUI.BOOK_PAGES[0].get_center(),'Map illustration is at the exact page center')
		var before=await capture('book-'+language)
		var book_position=book.position
		app.documents.turn_page(1)
		var turn=app.documents.page_turn
		turn.motion.pause();turn.set_progress(0)
		var flat=await capture('full-page-start-'+language)
		if before!=null:
			# The footer used to switch early because the old 472px crop excluded it.
			var footer=Rect2i(Vector2i(book_position)+Vector2i(600,516),Vector2i(396,36))
			var different=0
			for y in range(footer.position.y,footer.end.y):
				for x in range(footer.position.x,footer.end.x):
					var a=before.get_pixel(x,y);var b=flat.get_pixel(x,y)
					if maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))>1.1/255.0: different+=1
			check(different==0,'Entire footer belongs to the turning page, with no early next-page content')
		for value in [.25,.5,.75]:
			turn.set_progress(value);await capture('turn-'+language+'-'+str(value))
		app.documents.cancel_turn()
		app.modal.get_child(1).get_node('ArchiveClose').grab_focus()
		await press(KEY_LEFT)
		check(app.documents.archive_city==city,'Left key turns back even with a control focused')
		app.documents.cancel_turn()
		await click(app.modal.get_child(1).get_node('ArchiveNext'))
		check(app.documents.archive_city!=city,'Right page edge turns a page')
		await press(KEY_PAGEUP)
		check(app.documents.archive_city==city,'Page Up turns back')
		await click(app.modal.get_child(1).get_node('ArchiveClose'))
		check(app.dialog_kind=='' and not is_instance_valid(app.documents.page_turn),'Top-left cross closes during animation')
		check(app.expedition.state==state,'Archive reading preserves campaign state')
	app.sound.stop()
	print('%d book layout checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
