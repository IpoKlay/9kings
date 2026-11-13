extends Control
const Catalog=preload('res://scripts/data/catalog.gd')
var preset: Dictionary=Catalog.presentation('ui')
## A separate, opaque title screen: never preview a rolled or current theater.
var app
var cloth: ImageTexture
@onready var background: Texture2D=$RomanForum.texture
var options: Array[Button] = []
var actions: Array[Callable] = []
var selected = 0
@onready var cursor: TextureRect=$CursorAnchor/SelectionCursor
@onready var selection_hint: Label=$SelectionHint
var cursor_y = 0.0
var cursor_clock = 0.0
@export var cursor_gap := 16.0
@export var english_title_size := 52
@onready var title_size: int=$Title.get_theme_font_size("font_size")

func _ready():
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

	if app==null:return
	var handlers={'TacticalTrial':app.open_tactical_trial,'ResumeGame':app.resume_game,'StartGame':app.request_new_game,
		'MenuSettings':func():app.open_dialog('settings'),'QuitGame':func():get_tree().quit()}
	for button: Button in $MenuOptions.get_children():
		var index=options.size()
		options.append(button)
		actions.append(handlers[button.name])
		button.mouse_entered.connect(func():
			if can_interact():set_selected(index))
		button.pressed.connect(func():
			if can_interact():
				set_selected(index,false)
				activate_selected())
	$MenuOptions.sort_children.connect(snap_cursor)

func can_interact() -> bool:
	return app!=null and visible and app.main_menu and app.dialog_kind=='' and not app.input_locked

func option_available(index: int) -> bool:
	return options[index].name!='ResumeGame' or app.has_run

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

func option_origin(button: Button) -> Vector2:
	return get_global_transform().affine_inverse()*button.global_position

func snap_cursor():
	if options.is_empty():return
	var button:=options[selected]
	cursor_y=option_origin(button).y+(button.size.y-cursor.size.y)/2
	position_cursor()

func position_cursor():
	var button:=options[selected]
	var width:=button.get_theme_font('font').get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size('font_size')).x
	var x:=option_origin(button).x+(button.size.x-width)/2-cursor.size.x-cursor_gap
	x+=sin(cursor_clock*TAU/preset.menu_cursor_period)*preset.menu_cursor_bob
	$CursorAnchor.position=Vector2(snappedf(x,preset.menu_cursor_grid),snappedf(cursor_y,preset.menu_cursor_grid))

func _process(delta: float):
	if not can_interact() or options.is_empty():return
	cursor_clock+=delta
	var button:=options[selected]
	var target:=option_origin(button).y+(button.size.y-cursor.size.y)/2
	cursor_y=lerpf(cursor_y,target,1.-exp(-preset.menu_cursor_follow_speed*delta))
	position_cursor()

func render():
	$Title.text=app.loc('main_menu.under_the_eagle')
	$Title.add_theme_font_size_override('font_size',title_size if app.language=='zh' else english_title_size)
	$Subtitle.text=app.loc('main_menu.the_mediterranean_campaign')
	%TacticalTrial.text=app.tx('军团会战 · 布阵与交战','Legion Battle · Deploy & Fight')
	%ResumeGame.text=app.tx('继续远征','Continue Expedition')
	%ResumeGame.tooltip_text='' if app.has_run else app.loc('main_menu.no_run')
	%StartGame.text=app.tx('新远征','New Expedition')
	%MenuSettings.text=app.loc('main_menu.settings')
	%QuitGame.text=app.loc('main_menu.quit')
	set_selected(selected,false)
	cursor_clock=0
	snap_cursor()
