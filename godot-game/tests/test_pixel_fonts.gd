extends SceneTree
## Font coverage and actual shaped-text bounds, including Chinese fallback runs.
var app
var checks=0
var failures=0
var characters={}
func _init(): call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok:
		failures+=1
		printerr('FAIL: '+message)
func collect_text(value):
	if value is String:
		for c in value:
			if c.unicode_at(0)>=32: characters[c]=true
	elif value is Dictionary:
		for child in value.values(): collect_text(child)
	elif value is Array:
		for child in value: collect_text(child)
func check_controls(node: Node):
	if node is Label or node is Button:
		check(node.get_theme_font('font')==app.font,'Shared font reaches '+str(node.get_path()))
		collect_text(node.text)
		collect_text(node.tooltip_text)
		if node is Button and not node.text.is_empty():
			var face=node.get_theme_stylebox('normal')
			var available=node.size.x-face.get_content_margin(SIDE_LEFT)-face.get_content_margin(SIDE_RIGHT)
			check(app.font.get_string_size(node.text,HORIZONTAL_ALIGNMENT_LEFT,-1,node.get_theme_font_size('font_size')).x<=available+.1,'Button text fits '+node.text)
	for child in node.get_children(): check_controls(child)
func capture(name: String):
	if DisplayServer.get_name()=='headless': return
	await process_frame
	RenderingServer.force_draw() # Deterministic capture even when the OS occludes this test window.
	root.get_texture().get_image().save_png('res://tests/font-'+name+'.png')
func run():
	app=load('res://scenes/main.tscn').instantiate()
	root.add_child(app)
	current_scene=app
	app.set_process(false)
	app.sound.enabled=false
	collect_text(app.campaign.rules)
	collect_text(app.expedition.original_data)
	for key in app.Catalog.data('localization/interface'):
		for lang in ['zh','en']: collect_text(app.Catalog.text(key,lang))
	collect_text('⚔ ♥ ⚑ ✓ ◆ ◇ ♠ ♣ ▾ ▸ → − × Ⅰ Ⅱ Ⅲ')
	check(app.world.world_font==app.font,'World labels use the same font as controls')
	check(ThemeDB.get_project_theme().default_font==app.font,'Popup/tooltips inherit the project font')
	for language in ['zh','en']:
		app.language=language
		app.world.language=language
		app.return_to_menu()
		check_controls(app.menu_view)
		await capture('menu-'+language)
		app.open_dialog('settings')
		check_controls(app.modal)
		await capture('settings-'+language)
		app.close_dialog()
		app.restart_expedition(1)
		app.travel_to(app.expedition.destinations()[0]);app.campaign.finish(true);app.advance()
		app.campaign.g.offered=['legion','testudo','medic']
		app.render_ui()
		await capture('cards-'+language)
		for id in app.campaign.cards:
			app.card_hand=null
			app.remove_children(app.ui)
			app.card_button(id,0)
			await process_frame
			var card=app.ui.get_child(0)
			check_controls(card)
			for child in card.get_children():
				if child is Label:
					check(child.position.x+child.size.x<=240.1,'Card text width '+id+' '+language)
					var bottom=child.position.y+child.size.y
					var region: Rect2=app.CardFace.TEXT_RECTS[String(child.name)]
					check(bottom<=region.end.y+.1,'Card text overlaps next row '+id+' '+language+' '+child.text)
		app.render_ui()
		app.open_map()
		check_controls(app.expedition_map)
		await capture('map-'+language)
		for n in app.expedition.data.nodes:
			app.expedition_map.select_city(n.id)
			await process_frame
			var panel=app.expedition_map.info
			check_controls(panel)
			for child in panel.get_children():
				if child is Label:
					check(child.position.x+child.size.x<=430.1,'City text fits width '+n.id+' '+language)
			app.documents.open_archive(n.id)
			await process_frame
			check_controls(app.modal)
			var book=app.modal.get_child(1)
			var history=book.get_node('HistoryText')
			check(history.position.y+history.size.y<=book.get_node('ArchivePageCount').position.y-16,'History stays above the page count '+n.id+' '+language)
			var pages=app.documents.pages_for(app.expedition.node_text(n.id,'history'))
			for page in pages:
				check(app.font.get_multiline_string_size(page,HORIZONTAL_ALIGNMENT_LEFT,396,24).y<=260,'Every history page fits '+n.id+' '+language)
			check(''.join(pages).replace(' ','')==app.expedition.node_text(n.id,'history').replace(' ',''),'Pagination preserves complete history '+n.id+' '+language)
			app.close_dialog()
		app.expedition_map.select_city('246349')
		app.documents.open_archive('246349')
		await capture('history-'+language)
		app.close_dialog()
	for c in characters:
		check(app.font.has_char(c.unicode_at(0)),'Missing visible character '+c)
	app.sound.stop()
	print('%d pixel-font coverage/layout checks, %d unique characters, %d failures'%[checks,characters.size(),failures])
	quit(1 if failures else 0)
