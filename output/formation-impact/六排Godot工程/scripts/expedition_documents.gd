extends RefCounted
const RPGUI=preload('res://scripts/rpg_ui.gd')
var app
var archive_city=''
var archive_region=0
var archive_page=0
var event_city=''
var event_recovered=0
var page_turn: Control

func cancel_turn():
	if is_instance_valid(page_turn): page_turn.finish()
	page_turn=null
	app.sound.stop_page_turn()

func refresh_archive(direction: int):
	cancel_turn()
	if RPGUI.reduced_motion():
		app.open_dialog('archive')
		app.sound.play_page_turn()
		return
	var turn=preload('res://scripts/book_page_turn.gd').new()
	app.add_child(turn)
	turn.begin(app.modal.get_child(1),app.theme,direction)
	app.open_dialog('archive')
	page_turn=turn
	turn.play(app.modal.get_child(1),app.theme,app.ui_preset)
	app.sound.play_page_turn()

func paper_button(parent: Control,caption: String,pos: Vector2,size: Vector2,action: Callable,selected: bool=false) -> Button:
	var b=app.button(parent,caption,pos,size,action)
	RPGUI.button(b,'strip',selected)
	b.focus_mode=Control.FOCUS_ALL
	return b

func open_archive(id: String):
	if app.input_locked or app.dialog_kind!='' or not app.expedition.nodes.has(id): return
	archive_city=id
	archive_region=0
	archive_page=0
	app.open_dialog('archive')

func archive_ids() -> Array:
	var ids=[]
	for node in app.expedition.data.nodes:
		if archive_region==0 or int(node.act)==archive_region: ids.append(node.id)
	return ids

func pages_for(text: String) -> Array[String]:
	var chunks: Array=[]
	if app.language=='zh':
		for character in text: chunks.append(character)
	else:
		for word in text.split(' ',false): chunks.append(word+' ')
	var pages: Array[String]=[]
	var page=''
	for chunk in chunks:
		var candidate=page+chunk
		if not page.is_empty() and app.font.get_multiline_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,396,24).y>260:
			pages.append(page.strip_edges())
			page=chunk
		else: page=candidate
	pages.append(page.strip_edges())
	return pages

func turn_page(direction: int):
	var pages=pages_for(app.expedition.node_text(archive_city,'history'))
	var next=archive_page+direction
	if next>=0 and next<pages.size(): archive_page=next
	else:
		var ids=archive_ids()
		var index=ids.find(archive_city)+direction
		if index<0 or index>=ids.size(): return
		archive_city=ids[index]
		archive_page=0 if direction>0 else pages_for(app.expedition.node_text(archive_city,'history')).size()-1
	refresh_archive(direction)

func select_region(region: int):
	if region==archive_region: return
	var direction=1 if region>archive_region else -1
	archive_region=region
	var ids=archive_ids()
	if not archive_city in ids: archive_city=ids[0]
	archive_page=0
	refresh_archive(direction)

func centered_label(panel: Control,text: String,center_x: float,y: float,height: float,font_size: int,color: Color) -> Label:
	var label=app.label(panel,text,Vector2(center_x-198,y),Vector2(396,height),font_size,color)
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	return label

func bare_button(panel: Control,text: String,pos: Vector2,button_size: Vector2,action: Callable) -> Button:
	var button=app.button(panel,text,pos,button_size,action)
	for state in ['normal','hover','pressed','disabled','focus']:
		button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	button.add_theme_color_override('font_color',app.ui_preset.rpg_ink)
	for state in ['font_hover_color','font_pressed_color','font_focus_color']:
		button.add_theme_color_override(state,Color('#9e4431'))
	button.focus_mode=Control.FOCUS_ALL
	button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	return button

func archive_content(panel: Control):
	app.expedition_map.history_open=true
	panel.name='ArchiveBook'
	panel.size=RPGUI.texture('book').get_size()
	panel.position=(Vector2(1920,1080)-panel.size)*.5
	panel.add_theme_stylebox_override('panel',StyleBoxEmpty.new())
	RPGUI.picture(panel,'book',Vector2.ZERO)
	var ink: Color=app.ui_preset.rpg_ink
	var secondary: Color=app.ui_preset.rpg_secondary_ink
	var exp=app.expedition
	var left_page: Rect2=RPGUI.BOOK_PAGES[0]
	var right_page: Rect2=RPGUI.BOOK_PAGES[1]
	var left_x=left_page.get_center().x
	var right_x=right_page.get_center().x
	var title=centered_label(panel,exp.node_text(archive_city),left_x,64,64,32,ink)
	title.name='ArchiveCity'
	centered_label(panel,exp.nodes[archive_city].latin,left_x,132,32,21,secondary)
	var position=app.Catalog.data('generated/atlas_positions')[archive_city]
	var anchor=Vector2(position[0],position[1])*.5
	var region=Rect2(Vector2(clampf(anchor.x-96,0,2880-192),clampf(anchor.y-56,0,1260-112)),Vector2(192,112))
	var crop=AtlasTexture.new()
	crop.atlas=app.expedition_map.tex('atlas');crop.region=region
	var illustration=TextureRect.new()
	illustration.name='ArchiveLocation'
	illustration.texture=crop
	illustration.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	illustration.position=Vector2(left_x-192,180);illustration.size=Vector2(384,224)
	illustration.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.add_child(illustration)
	var mark=ColorRect.new();mark.size=Vector2(8,8)
	mark.position=(anchor-region.position)*2-mark.size*.5
	mark.color=Color('#9e4431');mark.mouse_filter=Control.MOUSE_FILTER_IGNORE
	illustration.add_child(mark)
	centered_label(panel,app.loc('documents.reference_date'),left_x,420,32,22,secondary)
	centered_label(panel,app.loc('documents.context_note'),left_x,464,56,20,secondary)
	var pages=pages_for(exp.node_text(archive_city,'history'))
	archive_page=clampi(archive_page,0,pages.size()-1)
	var body_height=ceilf(app.font.get_multiline_string_size(pages[archive_page],HORIZONTAL_ALIGNMENT_CENTER,396,24).y)+4
	var text_top=title.get_rect().get_center().y-24
	centered_label(panel,app.loc('expedition_map.history'),right_x,text_top,48,30,ink)
	centered_label(panel,app.loc('expedition_map.visited') if archive_city in exp.state.visited else app.loc('documents.unvisited'),right_x,text_top+56,32,21,secondary)
	var body=centered_label(panel,pages[archive_page],right_x,text_top+108,body_height,24,ink)
	body.name='HistoryText'
	var ids=archive_ids()
	var index=ids.find(archive_city)
	centered_label(panel,app.loc('documents.page_count')%[index+1,ids.size(),archive_page+1,pages.size()],right_x,520,28,21,secondary).name='ArchivePageCount'
	for direction in [-1,1]:
		var edge=bare_button(panel,'',Vector2(left_page.position.x if direction<0 else right_page.end.x-48,80),Vector2(48,456),func():turn_page(direction))
		edge.name='ArchivePrevious' if direction<0 else 'ArchiveNext'
		edge.tooltip_text=app.loc('documents.previous') if direction<0 else app.loc('documents.next')
		edge.disabled=(index==0 and archive_page==0) if direction<0 else (index==ids.size()-1 and archive_page==pages.size()-1)
		var focus=StyleBoxFlat.new();focus.bg_color=Color.TRANSPARENT;focus.border_color=Color('#9e4431')
		focus.set_border_width(SIDE_LEFT if direction<0 else SIDE_RIGHT,4)
		edge.add_theme_stylebox_override('focus',focus)
	for region_id in range(4):
		var tab=paper_button(panel,app.loc('documents.region_'+str(region_id)),Vector2(1050,90+region_id*68),Vector2(132,56),func():select_region(region_id),archive_region==region_id)
		tab.name='ArchiveRegion_'+str(region_id)
		tab.add_theme_font_size_override('font_size',21)
	var close=bare_button(panel,'×',Vector2(20,12),Vector2(48,48),app.close_dialog)
	close.name='ArchiveClose'
	close.tooltip_text=app.tr_text('Close')
	for child in panel.get_children():
		if child is Button: child.z_index=20 # Controls stay above the turning sheet.

func event_content(panel: Control):
	panel.name='EventPaper'
	panel.size=Vector2(680,520)
	panel.position=(Vector2(1920,1080)-panel.size)*.5
	panel.add_theme_stylebox_override('panel',RPGUI.box('paper'))
	var exp=app.expedition
	var ink: Color=app.ui_preset.rpg_ink
	app.label(panel,exp.node_text(event_city,'title'),Vector2(52,42),Vector2(530,46),32,ink)
	app.label(panel,exp.node_text(event_city),Vector2(52,99),Vector2(570,34),23,app.ui_preset.rpg_secondary_ink)
	app.label(panel,exp.node_text(event_city,'history'),Vector2(52,156),Vector2(576,136),23,ink)
	app.label(panel,app.loc('documents.supplies_ready'),Vector2(52,305),Vector2(576,34),27,ink)
	var effect=app.loc('documents.supplies_effect')%[event_recovered,app.campaign.g.defense,app.campaign.camp.max_lives]
	app.label(panel,effect,Vector2(52,348),Vector2(576,62),23,ink)
	var confirm=paper_button(panel,app.loc('documents.choose_supply'),Vector2(175,430),Vector2(330,58),app.close_dialog,true)
	confirm.name='EventConfirm'
	confirm.grab_focus()
	var close=paper_button(panel,'×',Vector2(584,36),Vector2(48,48),app.close_dialog)
	close.tooltip_text=app.tr_text('Close')
