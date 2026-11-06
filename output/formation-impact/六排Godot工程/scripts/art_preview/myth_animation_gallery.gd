extends Control
## Art review scene: six native frames per one-second action, no combat rules.
const MANIFEST_PATH = 'res://assets/mythology/animated_oblique/source.json'
var entries: Array = []
var sprites: Array[AnimatedSprite2D] = []
var content: Control
var group_label: Label
var elapsed := 0.0
var cycle_elapsed := 0.0
var category := 'god'
var capture_mode := false
var groups := ['god', 'hero', 'monster']
var group_names := ['神明', '英雄', '怪物']

func _ready():
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	theme = load('res://assets/fonts/game_pixel_theme.tres')
	entries = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH)).characters
	capture_mode = '--capture-gallery' in OS.get_cmdline_user_args()
	var bg = ColorRect.new()
	bg.color = Color('#20353b')
	bg.size = Vector2(1920,1080)
	add_child(bg)
	add_label('鹰旗之下 · 斜俯视残影动作', Vector2(42,20), 38)
	add_label('素材预览 · 每次6帧 / 1秒 · 两次之间停顿0.6秒', Vector2(42,70), 26)
	group_label = add_label('', Vector2(1480,24), 34)
	for i in groups.size():
		var button = Button.new()
		button.text = group_names[i]
		button.position = Vector2(1080+i*180,72)
		button.size = Vector2(160,54)
		button.pressed.connect(show_group.bind(groups[i]))
		add_child(button)
	var replay = Button.new()
	replay.text = '重播 / 空格'
	replay.position = Vector2(1620,72)
	replay.size = Vector2(240,54)
	replay.pressed.connect(replay_all)
	add_child(replay)
	content = Control.new()
	add_child(content)
	show_group('god')

func add_label(text: String, pos: Vector2, font_size: int) -> Label:
	var label = Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override('font_size', font_size)
	label.add_theme_color_override('font_color', Color('#e2d2a2'))
	add_child(label)
	return label

func show_group(next_category: String):
	category = next_category
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	sprites.clear()
	group_label.text = group_names[groups.find(category)]
	var selected = entries.filter(func(entry): return entry.category == category)
	for i in selected.size():
		var entry: Dictionary = selected[i]
		var pos = Vector2(30+(i%3)*630,158+int(i/3.0)*440)
		var panel = ColorRect.new()
		panel.position = pos
		panel.size = Vector2(600,420)
		panel.color = Color('#617568')
		content.add_child(panel)
		var sprite = AnimatedSprite2D.new()
		sprite.sprite_frames = load(entry.sprite_frames)
		sprite.position = pos+Vector2(300,200)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.scale = Vector2.ONE*0.75
		content.add_child(sprite)
		sprites.append(sprite)
		var label = Label.new()
		label.text = entry.name
		label.position = pos+Vector2(24,364)
		label.add_theme_font_size_override('font_size', 30)
		label.add_theme_color_override('font_color', Color('#ead7a0'))
		content.add_child(label)
	replay_all()

func replay_all():
	cycle_elapsed = 0.0
	for sprite in sprites:
		sprite.stop()
		sprite.play('action')

func _process(delta: float):
	elapsed += delta
	if capture_mode:
		var page = mini(2,int(elapsed/3.2))
		if category != groups[page]: show_group(groups[page])
	cycle_elapsed += delta
	if cycle_elapsed >= 1.6: replay_all()
	if capture_mode and elapsed >= 9.6: get_tree().quit()

func _unhandled_key_input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE: replay_all()
