extends Control
const Catalog=preload('res://scripts/data/catalog.gd')
var preset: Dictionary=Catalog.presentation('ui')
## A separate, opaque title screen: never preview a rolled or current theater.
var app
var cloth: ImageTexture
var background: Texture2D = load(preset.menu_background)
var options: Array[Button] = []
var actions: Array[Callable] = []
var selected = 0
var cursor: TextureRect
var selection_hint: Label
var cursor_y = 0.0
var cursor_clock = 0.0
var cursor_texture: Texture2D = load('res://assets/menu/cursor.png')

func _ready():
	z_index=50
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	# The old cloth remains the map-unroll backing; only the menu uses the artwork.
	# Local, fixed seed keeps the title screen independent of card/map rolls.
	var grain=RandomNumberGenerator.new()
	grain.seed=int(preset.menu_grain_seed)
	var image=Image.create(preset.menu_texture_size.x,preset.menu_texture_size.y,false,Image.FORMAT_RGB8)
	for y in preset.menu_texture_size.y:
		for x in preset.menu_texture_size.x:
			var center=clampf(1.0-Vector2((x-240)/300.0,(y-120)/220.0).length(),0,1)
			var color=Color('#10262c').lerp(Color('#294a4d'),center*.8)
			var weave=(.010 if x%3==0 else -.005)+(.008 if y%2==0 else -.004)
			var light=grain.randf_range(-.016,.016)+weave
			image.set_pixel(x,y,Color(color.r+light,color.g+light,color.b+light,1))
	cloth=ImageTexture.create_from_image(image)

func _draw():
	draw_rect(Rect2(0,0,1920,1080),Color('#30281f'))
	if background!=null:
		var artwork_size=background.get_size()
		var fitted=artwork_size*minf(1920.0/artwork_size.x,1080.0/artwork_size.y)
		draw_texture_rect(background,Rect2((Vector2(1920,1080)-fitted)/2,fitted),false)
	# A UI surface over the untouched painting keeps faces and columns out of the text.
	var center=float(preset.menu_center_x)
	draw_rect(Rect2(center-285,80,570,920),Color(0.12,0.095,0.075,0.84))
	draw_rect(Rect2(center-273,92,546,896),Color('#8a7551'),false,2)
	draw_rect(Rect2(center-180,454,148,2),Color('#998057'))
	draw_rect(Rect2(center+32,454,148,2),Color('#998057'))
	draw_rect(Rect2(center-6,449,12,12),Color('#c4ad76'))

func centered_text(value: String,y: float,width: float,height: float,font_size: int,color: Color) -> Label:
	var text=app.label(self,value,Vector2(preset.menu_center_x-width/2,y),Vector2(width,height),font_size,color)
	text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	text.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	text.add_theme_color_override('font_shadow_color',Color('#0b1b23'))
	text.add_theme_constant_override('shadow_offset_y',3)
	return text

func can_interact() -> bool:
	return visible and app.main_menu and app.dialog_kind=='' and not app.input_locked

func option_available(index: int) -> bool:
	return index!=1 or app.has_run

func menu_button(id: String,value: String,y: float,action: Callable):
	var index=options.size()
	var control=Button.new()
	control.name=id
	control.text=value
	control.position=Vector2(preset.menu_button_left,y)
	control.size=preset.menu_button_size
	control.alignment=HORIZONTAL_ALIGNMENT_CENTER
	control.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	# Selection is shared by mouse and keyboard; native focus must not move twice.
	control.focus_mode=Control.FOCUS_NONE
	control.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	control.add_theme_font_size_override('font_size',int(preset.menu_option_font_size))
	var empty=StyleBoxEmpty.new()
	for state in ['normal','hover','pressed','focus','disabled']:
		control.add_theme_stylebox_override(state,empty)
	control.mouse_entered.connect(func():
		if can_interact(): set_selected(index))
	control.pressed.connect(func():
		if can_interact():
			set_selected(index,false)
			activate_selected())
	if index==1 and not app.has_run:
		control.tooltip_text=app.loc('main_menu.no_run')
	add_child(control)
	options.append(control)
	actions.append(action)

func set_selected(index: int,play_sound: bool=true):
	var next=clampi(index,0,options.size()-1)
	if next!=selected and play_sound: app.sound.play_menu_move()
	selected=next
	for i in options.size():
		var color=Color('#fff1c5') if i==selected else Color('#e0d2b0')
		if not option_available(i): color=Color('#bfb29b') if i==selected else Color('#9f9482')
		for state in ['font_color','font_hover_color','font_pressed_color','font_focus_color']:
			options[i].add_theme_color_override(state,color)
	if is_instance_valid(selection_hint):
		selection_hint.text='' if option_available(selected) else app.loc('main_menu.no_run')

func activate_selected():
	if not can_interact() or options.is_empty(): return
	if not option_available(selected):
		app.sound.play('bad',.3)
		return
	app.sound.play('click')
	# The action may rebuild/free the controls (settings, start and continue).
	var action=actions[selected]
	action.call()

func handle_key(event: InputEventKey) -> bool:
	if not can_interact() or not event.pressed or event.echo: return false
	if event.alt_pressed or event.ctrl_pressed or event.meta_pressed: return false
	if event.keycode in [KEY_UP,KEY_W] or event.physical_keycode in [KEY_UP,KEY_W]:
		set_selected(selected-1)
	elif event.keycode in [KEY_DOWN,KEY_S] or event.physical_keycode in [KEY_DOWN,KEY_S]:
		set_selected(selected+1)
	elif event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE]:
		activate_selected()
	else:
		return false
	return true

func position_cursor():
	# Keep the label centered; the arrow sits outside its independently shaped text.
	var button=options[selected]
	var text_width=button.get_theme_font('font').get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size('font_size')).x
	var x=button.position.x+(button.size.x-text_width)/2-preset.menu_cursor_size.x-preset.menu_cursor_gap
	x+=sin(cursor_clock*TAU/preset.menu_cursor_period)*preset.menu_cursor_bob
	# Keep the original 16px arrow crisp: move on the same grid as its 3x pixels.
	cursor.position=Vector2(snappedf(x,preset.menu_cursor_grid),snappedf(cursor_y,preset.menu_cursor_grid))

func _process(delta: float):
	if not can_interact() or not is_instance_valid(cursor) or options.is_empty(): return
	cursor_clock+=delta
	var target=options[selected].position.y+(options[selected].size.y-preset.menu_cursor_size.y)/2
	cursor_y=lerpf(cursor_y,target,1.0-exp(-preset.menu_cursor_follow_speed*delta))
	position_cursor()

func render():
	app.remove_children(self)
	options.clear()
	actions.clear()
	app.RomanUI.icon(self,'banner',Vector2(preset.menu_center_x-48,118),Vector2(96,96))
	centered_text('S P Q R',228,460,38,23,Color('#c4ad76'))
	centered_text(app.loc('main_menu.under_the_eagle'),282,520,104,80 if app.language=='zh' else 52,Color('#f2deae'))
	centered_text(app.loc('main_menu.the_mediterranean_campaign'),394,520,40,25,Color('#dbc9a6'))
	var labels=[app.loc('main_menu.start_game'),app.loc('main_menu.continue'),app.loc('main_menu.settings'),app.loc('main_menu.quit')]
	menu_button('StartGame',labels[0],preset.menu_start_y,app.request_new_game)
	menu_button('ResumeGame',labels[1],preset.menu_secondary_y,app.resume_game)
	menu_button('MenuSettings',labels[2],preset.menu_secondary_y+preset.menu_button_spacing,func():app.open_dialog('settings'))
	menu_button('QuitGame',labels[3],preset.menu_secondary_y+preset.menu_button_spacing*2,func():get_tree().quit())
	selection_hint=centered_text('',910,520,40,23,Color('#dbc9a6'))
	selection_hint.name='SelectionHint'
	cursor=TextureRect.new()
	cursor.name='SelectionCursor'
	cursor.texture=cursor_texture
	cursor.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	cursor.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	cursor.size=preset.menu_cursor_size
	cursor.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(cursor)
	set_selected(selected,false)
	cursor_clock=0
	cursor_y=options[selected].position.y+(options[selected].size.y-preset.menu_cursor_size.y)/2
	position_cursor()
	queue_redraw()
