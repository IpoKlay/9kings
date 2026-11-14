extends Control

const Journey = preload('res://scripts/cassius/journey.gd')
const Landscape = preload('res://scripts/cassius/landscape.gd')
const ItemIcon = preload('res://scripts/cassius/item_icon.gd')
const FactionMap = preload('res://scripts/cassius/faction_map.gd')
const COIN = preload('res://assets/expedition/gold.png')
const INTRO_ART = [
	null, preload('res://assets/menu/forum-original.jpg'),
	preload('res://assets/strategy/pixellab-v2/B01.png'),
	preload('res://assets/art_preview/shield_march.png'),
	preload('res://assets/strategy/pixellab-v2/B07.png'),
]
const STATION_NAMES = {'village':'村民代表','shop':'旧道商队','camp':'边境军营','altar':'河岸祭坛','warning':'前方岗哨','fork':'岔路口'}
var app
var journey = Journey.new()
var landscape: Node2D
var header: Label
var hint: Label
var marker_layer: Control
var markers: Dictionary = {}
var overlay: PanelContainer
var content: VBoxContainer
var mode = ''
var busy = false
var save_path = 'user://cassius.cfg'
var save_warning = ''
var foot_clock = 0.0

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = preload('res://assets/fonts/game_pixel_theme.tres')
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	journey.load_run(save_path)
	var viewport = SubViewport.new()
	viewport.size = Vector2i(960,540)
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(viewport)
	landscape = Landscape.new()
	viewport.add_child(landscape)
	var view = TextureRect.new()
	view.texture = viewport.get_texture()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	marker_layer = Control.new()
	marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(marker_layer)
	for id in STATION_NAMES:
		var caption = label(marker_layer,STATION_NAMES[id],20,Color('#fff1ce'))
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.size = Vector2(220,36)
		caption.add_theme_color_override('font_shadow_color',Color('#151621'))
		caption.add_theme_constant_override('shadow_offset_x',2)
		caption.add_theme_constant_override('shadow_offset_y',2)
		markers[id] = caption
	var top = HBoxContainer.new()
	top.position = Vector2(48,12)
	top.size = Vector2(1824,58)
	top.add_theme_constant_override('separation',16)
	add_child(top)
	var coin = TextureRect.new()
	coin.texture = COIN
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.custom_minimum_size = Vector2(38,38)
	top.add_child(coin)
	header = label(top,'',24)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(top,'地图 M',func(): show_panel('map'))
	button(top,'物品 I',func(): show_panel('inventory'))
	button(top,'账本 J',func(): show_panel('ledger'))
	button(top,'菜单',leave)
	hint = label(self,'',24)
	hint.position = Vector2(48,1017)
	hint.size = Vector2(1824,48)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	refresh_land()
	if journey.state.ended: show_panel('ending')
	elif journey.state.intro < journey.spec.intro.size(): show_panel('intro')

func label(parent: Node, value: String, points: int, color: Color = Color('#efe2c3')) -> Label:
	var node = Label.new()
	node.text = value
	node.add_theme_font_size_override('font_size',points)
	node.add_theme_color_override('font_color',color)
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func button(parent: Node, title: String, action: Callable, disabled: bool = false) -> Button:
	var node = Button.new()
	node.text = title
	node.custom_minimum_size = Vector2(120,48)
	node.add_theme_font_size_override('font_size',22)
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.disabled = disabled
	node.pressed.connect(func():
		if busy: return
		if app!=null: app.sound.play('click',.6)
		action.call())
	parent.add_child(node)
	return node

func refresh_land():
	var land = journey.region()
	landscape.land = land.id
	landscape.tint = Color(land.ground)
	landscape.shown_markers = {'village':not journey.state.choices.has(land.id),'warning':not journey.state.battles.has(land.id)}
	header.text = '卡西修斯  /  %s   ·   王印币 %d   口粮 %d   疲惫 %d'%[land.name,journey.count('gold'),journey.count('food'),journey.state.fatigue]

func persist():
	var error = journey.save_run(save_path)
	save_warning = '  ·  存档失败，请检查存储空间' if error != OK else ''
	refresh_land()

func nearest_stop() -> String:
	var best = 103.
	var id = ''
	for key in Landscape.STOPS:
		var distance = landscape.actor.distance_to(Landscape.STOPS[key])
		if distance < best:
			best = distance
			id = key
	return id

func _process(dt: float):
	var direction = Vector2.ZERO
	if mode.is_empty() and not busy and not journey.state.ended:
		direction.x = float(Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))
		direction.y = float(Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	landscape.advance(minf(dt,.05),direction)
	if direction != Vector2.ZERO and app!=null:
		foot_clock -= dt
		if foot_clock<=0.:
			foot_clock=.36
			app.sound.play('foot',.4)
	for id in markers:
		markers[id].position = landscape.point_at(id)*2.-Vector2(110,222)
		markers[id].visible = mode.is_empty()
	var near = nearest_stop() if mode.is_empty() else ''
	hint.text = ('F  交谈 · '+STATION_NAMES[near] if near!='' else 'WASD / 方向键  行走   ·   靠近地点按 F')+save_warning

func _input(event: InputEvent):
	if not is_visible_in_tree() or busy or not event is InputEventKey or not event.pressed or event.echo: return
	if event.alt_pressed or event.meta_pressed or event.ctrl_pressed:return
	if event.keycode == KEY_ESCAPE:
		if mode in ['intro','ending'] or mode.is_empty():leave()
		elif journey.state.ended:show_panel('ending')
		else:close_panel()
	elif mode in ['intro','ending']:return
	elif event.keycode in [KEY_M,KEY_I,KEY_J]:
		var next = {KEY_M:'map',KEY_I:'inventory',KEY_J:'ledger'}[event.keycode]
		if mode==next:
			if journey.state.ended:show_panel('ending')
			else:close_panel()
		else:show_panel(next)
	elif event.keycode==KEY_F and mode.is_empty():
		var id = nearest_stop()
		if id!='':show_panel(id)
	else:return
	get_viewport().set_input_as_handled()

func close_panel():
	if is_instance_valid(overlay):
		remove_child(overlay)
		overlay.queue_free()
	overlay=null
	mode=''

func paragraph(value: String, points: int = 24, color: Color = Color('#efe2c3')) -> Label:
	var node = label(content,value,points,color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node

func show_panel(id: String):
	if busy:return
	if journey.state.ended and id!='ending' and id!='ledger' and id!='inventory':return
	if journey.state.intro<journey.spec.intro.size() and id!='intro':return
	close_panel()
	mode=id
	overlay=PanelContainer.new()
	overlay.position=Vector2(340,116)
	overlay.size=Vector2(1240,850)
	var box = StyleBoxFlat.new()
	box.bg_color=Color('#202229')
	box.border_color=Color('#a38254')
	box.set_border_width_all(2)
	box.content_margin_left=40
	box.content_margin_right=40
	box.content_margin_top=29
	box.content_margin_bottom=29
	overlay.add_theme_stylebox_override('panel',box)
	add_child(overlay)
	var layout=VBoxContainer.new()
	layout.add_theme_constant_override('separation',12)
	overlay.add_child(layout)
	var titles={'intro':'Cassius · 卡西修斯','map':'内海四方','inventory':'随身物品','ledger':'远征账本','ending':'冬粮与承诺'}
	label(layout,titles.get(id,STATION_NAMES.get(id,'')),36,Color('#f3d396'))
	var scroll=ScrollContainer.new()
	scroll.follow_focus=true
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	content=VBoxContainer.new()
	content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override('separation',12)
	scroll.add_child(content)
	match id:
		'intro': render_intro()
		'village': render_village()
		'shop': render_shop()
		'camp': render_growth()
		'altar': render_altar()
		'warning': render_warning()
		'fork': render_routes()
		'map': render_map()
		'inventory': render_inventory()
		'ledger': render_ledger()
		'ending': render_ending()
	if id not in ['intro','ending']:
		button(layout,'返回行军  Esc',func():
			if journey.state.ended:show_panel('ending')
			else:close_panel())
	var buttons=content.find_children('*','Button',true,false)
	for candidate in buttons:
		if not candidate.disabled:
			candidate.grab_focus.call_deferred()
			break

func picture(tex: Texture2D, height: int):
	var node=TextureRect.new()
	node.texture=tex
	node.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.custom_minimum_size.y=height
	node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	content.add_child(node)
	return node

func render_intro():
	var index=int(journey.state.intro)
	var card=journey.spec.intro[index]
	if index == 0: add_faction_map(380)
	else: picture(INTRO_ART[index],380)
	paragraph(card.title,31,Color('#f3d396'))
	paragraph(card.text,26)
	button(content,'继续  %d / %d'%[index+1,journey.spec.intro.size()] if index<journey.spec.intro.size()-1 else '带队出发',func():
		journey.state.intro+=1
		persist()
		if journey.state.intro<journey.spec.intro.size():show_panel('intro')
		else:close_panel())

func goods_text(goods: Dictionary) -> String:
	var parts: Array[String]=[]
	for id in goods:parts.append('%s %d'%[journey.spec.items[id],int(goods[id])])
	return '、'.join(parts)

func render_village():
	var land=journey.region()
	paragraph(land.place+'  /  '+land.need,29,Color(land.color).lightened(.32))
	var choice=journey.state.choices.get(land.id,'')
	if choice!='':
		paragraph({'promise':'这笔承诺仍待兑现。','kept':'这笔承诺已兑现。','levy':'你按征收文书取走了物资。','leave':'你留下了村民的物资。'}[choice])
		return
	paragraph(land.offer+'\n获得 '+goods_text(land.grant)+'。承诺：'+land.promise)
	button(content,'接受帮助并立约',func():
		if journey.decide('promise'):persist();show_panel('village'))
	paragraph('按文书征收可得 '+goods_text(land.levy)+'，并计入一份大祭贡赋。当地人自行承担缺粮。')
	button(content,'执行征收',func():
		if journey.decide('levy'):persist();show_panel('village'))
	paragraph('留下物资。队伍得不到补给，疲惫 +1。')
	button(content,'不取一物',func():
		if journey.decide('leave'):persist();show_panel('village'))

func render_shop():
	paragraph('陈列货品',27,Color('#f3d396'))
	var shelf=HBoxContainer.new()
	shelf.add_theme_constant_override('separation',16)
	content.add_child(shelf)
	for offer in journey.spec.goods:
		var item=VBoxContainer.new()
		item.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		shelf.add_child(item)
		var art_icon=ItemIcon.new()
		art_icon.item=offer.id
		art_icon.custom_minimum_size=Vector2(100,76)
		item.add_child(art_icon)
		button(item,'%s · %d 币'%[offer.name,journey.price(offer)],func():
			if journey.buy(offer):persist();show_panel('shop'),journey.count('gold')<journey.price(offer))
	paragraph('以物易粮',27,Color('#f3d396'))
	for id in journey.spec.sale_prices:
		button(content,'交出 %s（持有 %d） · 换 %d 币'%[journey.spec.items[id],journey.count(id),journey.spec.sale_prices[id]],func():
			if journey.sell(id):persist();show_panel('shop'),journey.count(id)==0)

func render_growth():
	paragraph('把有限的王印币用在能撑过下一程的地方。')
	var grid=GridContainer.new()
	grid.columns=2
	grid.add_theme_constant_override('h_separation',24)
	grid.add_theme_constant_override('v_separation',16)
	content.add_child(grid)
	for node in journey.spec.growth:
		var cell=VBoxContainer.new()
		cell.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
		var owned=node.id in journey.state.growth
		var locked=node.parent!='' and node.parent not in journey.state.growth
		var title='%s · %d 币'%[node.name,node.cost]
		if owned:title=node.name+' · 已完成'
		elif locked:
			for parent in journey.spec.growth:
				if parent.id==node.parent:title=node.name+' · 需'+parent.name
		var b=button(cell,title,func():
			if journey.grow(node):
				persist()
				if app!=null:app.sound.play('upgrade')
				show_panel('camp'),owned or locked or journey.count('gold')<node.cost)
		b.add_theme_color_override('font_disabled_color',Color('#d6b67d') if owned else Color('#98958c'))
		var desc=label(cell,node.description,22)
		desc.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

func render_altar():
	paragraph({'south':'帝国珍惜粮食与服役，承担代价的常是边疆村落。','west':'林中人愿为今日献上种子，也知道明年可能无粮。','north':'先祖祭器和领袖的誓言，比金银更重。','east':'巫庭用知识和记忆换预兆，每次交换都留下一处空白。'}[journey.state.region])
	var known=journey.state.omens.get(journey.state.region,'')
	if known!='':
		paragraph('祭司的话',29,Color('#f3d396'))
		paragraph(known)
		return
	paragraph('祭品会从物品栏扣除。此处一程只求一次兆。')
	button(content,'献一头白牛 · 问前路',func():offer('ox'),journey.count('ox')==0)
	button(content,'献金蛇戒指 · 问代价',func():offer('ring'),journey.count('ring')==0)
	var land=journey.region()
	button(content,'依本地礼仪求兆 · %d %s'%[land.offering_cost,journey.spec.items[land.offering]],func():offer('local'),journey.count(land.offering)<int(land.offering_cost))

func offer(id: String):
	if not journey.omen(id):return
	persist()
	close_panel()
	busy=true
	landscape.ritual=2.4
	if app!=null:
		app.music.play_track('archive')
		app.sound.play('reward',.55)
	await get_tree().create_timer(2.4).timeout
	busy=false
	if app!=null:app.music.play_track('camp')
	show_panel('altar')

func render_warning():
	var result=journey.state.battles.get(journey.state.region,'')
	if result!='':
		paragraph({'won':'岗哨已通过，战利品已记入账本。','lost':'队伍已经撤回，绕道继续行军。','detour':'队伍走了林间小路，已避开岗哨。'}[result])
		return
	paragraph('警示 · 前方有驻军',29,Color('#eca184'))
	paragraph('接战将进入现有军团会战。胜利可得通行文书和战利品，战败增加 2 点疲惫。')
	var omen=journey.state.omens.get(journey.state.region,'')
	if omen!='':paragraph(omen,22,Color('#bfc7db'))
	button(content,'进入军团会战',func():
		if app!=null:
			close_panel()
			app.open_tactical_trial(false,false,accept_battle_result),app==null)
	var cost=2-(1 if 'scout' in journey.state.growth else 0)
	button(content,'绕行 · %d 口粮'%cost,func():
		if journey.avoid_battle():persist();show_panel('warning'),journey.count('food')<cost)

func accept_battle_result(phase: String):
	if phase in ['victory','defeat']:
		journey.battle_result(phase=='victory')
		persist()
	show_panel('warning')

func render_routes():
	if not journey.state.choices.has(journey.state.region):
		paragraph('先与村民代表谈妥这段路的物资。')
		button(content,'返回道路',close_panel)
		return
	var routes=journey.routes()
	if routes.is_empty():
		paragraph('大祭场在前面。帝国等着三份贡赋，沿途的人等着你兑现旧约。')
		paragraph('队伍每积累 2 点疲惫，返程需另用 1 份口粮照料。',22)
		render_promises()
		button(content,'交付大祭 · 当前可交 %d / 3'%journey.tribute_available(),func():end_run('rite'),journey.tribute_available()<3)
		button(content,'带现有粮食回援要塞',func():end_run('home'))
		return
	add_faction_map(320)
	paragraph('已走过 %d / %d 段。缺少的口粮会增加疲惫。'%[journey.state.visits.size(),journey.spec.chapters])
	for land in routes:
		var row=HBoxContainer.new()
		row.add_theme_constant_override('separation',16)
		content.add_child(row)
		var details=VBoxContainer.new()
		details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(details)
		label(details,'%s方 · %s  /  %s'%[land.direction,land.name,land.place],25,Color(land.color).lightened(.3))
		label(details,land.need,21)
		button(row,'出发 · %d 口粮'%journey.travel_cost(land),func():
			if journey.travel(land.id):
				landscape.actor=Vector2(180,405)
				landscape.camera_x=0.
				persist()
				close_panel())

func add_faction_map(height: int):
	var map = FactionMap.new()
	map.journey = journey
	map.custom_minimum_size.y = height
	content.add_child(map)

func render_map():
	add_faction_map(510)
	paragraph('金色虚线：可前往    ·    浅色实线：已走过    ·    中心方点：当前驻地',22)
	if not journey.state.choices.has(journey.state.region):
		paragraph('和当地代表谈妥物资后，地图会标出可前往的路线。',22)

func render_inventory():
	var items=[]
	for id in journey.spec.items:
		if journey.count(id)>0:items.append('%s × %d'%[journey.spec.items[id],journey.count(id)])
	paragraph('   /   '.join(items) if not items.is_empty() else '行囊已空。',27)
	paragraph('口粮用于行军和绕行。白牛与金蛇戒指可以求兆，贵重物品可在商队换成王印币。',22)

func render_promises():
	for land in journey.spec.regions:
		var status=journey.state.choices.get(land.id,'')
		if status not in ['promise','kept']:continue
		paragraph('%s · %s  %s'%[land.name,'已兑现' if status=='kept' else '待兑现',land.promise],22)
		if status=='promise' and not journey.state.ended:
			button(content,'兑现 · 交付 %d %s'%[land.cost,journey.spec.items[land.settle]],func():
				if journey.fulfill(land.id):persist();show_panel(mode),journey.count(land.settle)<int(land.cost))

func render_ledger():
	render_promises()
	if journey.state.ledger.is_empty():paragraph('尚未留下决定。')
	for index in range(journey.state.ledger.size()-1,-1,-1):
		paragraph(journey.state.ledger[index],22)

func end_run(kind: String):
	if journey.finish(kind):
		persist()
		show_panel('ending')

func render_ending():
	picture(INTRO_ART[2] if journey.state.ending=='rite' else INTRO_ART[3],270)
	paragraph('你许诺要守住的东西，守住了吗？',36,Color('#f3d396'))
	paragraph('带回冬粮 %d 份。队伍疲惫 %d。'%[journey.state.winter_food,journey.state.fatigue])
	render_promises()
	button(content,'翻阅远征账本',func():show_panel('ledger'))
	button(content,'返回主菜单',leave)
	button(content,'再走一程',func():
		journey.reset()
		landscape.actor=Vector2(180,405)
		landscape.camera_x=0.
		persist()
		show_panel('intro'))

func leave():
	persist()
	if app!=null:app.close_cassius()
