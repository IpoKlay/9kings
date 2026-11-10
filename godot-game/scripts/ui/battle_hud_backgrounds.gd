extends Control
## Background batching for the fixed, non-overlapping BattleHUD layout.
## Buttons retain their native text, focus, input, tooltips and content margins.

const STATES = [&"normal", &"pressed", &"hover", &"disabled", &"hover_pressed"]
var batching_enabled := true
var _items: Array[Dictionary] = []

func _ready() -> void:
	_collect(self)
	_apply_overrides()

func _collect(node: Node) -> void:
	# Keep clips native. Overview overlaps the flag alert: both must retain
	# their original painter order, including their backgrounds.
	if node is ScrollContainer or (node is Control and node.clip_contents):
		return
	if node.name in [&"FlagAlert", &"OverviewButton"]:
		return
	if node is Button or (node is Label and node.theme_type_variation == &"PaperLabel"):
		var keys: Array = STATES if node is Button else [&"normal"]
		var original: StringName = node.theme_type_variation
		var names: Array[StringName] = [original]
		if node is Button:
			for variant in [&"", &"HudSelected"]:
				if variant not in names:
					names.append(variant)
		var overrides := {}
		for key in keys:
			if node.has_theme_stylebox_override(key):
				overrides[key] = node.get_theme_stylebox(key)
		var variants := {}
		for variant in names:
			node.theme_type_variation = variant
			var styles := {}
			for key in keys:
				var lookup = &"pressed" if node is OptionButton and key == &"hover_pressed" else key
				styles[key] = node.get_theme_stylebox(lookup)
			variants[variant] = styles
		node.theme_type_variation = original
		var empty := {}
		for key in keys:
			var blank := StyleBoxEmpty.new()
			for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				blank.set_content_margin(side, variants[original][key].get_content_margin(side))
			empty[key] = blank
		_items.append({"control": node, "variants": variants, "overrides": overrides,
			"empty": empty})
		node.draw.connect(_on_control_redraw)
		node.item_rect_changed.connect(queue_redraw)
		node.visibility_changed.connect(queue_redraw)
		if node is Button:
			node.mouse_entered.connect(queue_redraw)
			node.mouse_exited.connect(queue_redraw)
			node.button_down.connect(queue_redraw)
			node.button_up.connect(queue_redraw)
	for child in node.get_children():
		_collect(child)

func _apply_overrides() -> void:
	for item in _items:
		for key in item.empty:
			if batching_enabled:
				item.control.add_theme_stylebox_override(key, item.empty[key])
			elif key in item.overrides:
				item.control.add_theme_stylebox_override(key, item.overrides[key])
			else:
				item.control.remove_theme_stylebox_override(key)
	queue_redraw()

func set_batching_enabled(enabled: bool) -> void:
	if batching_enabled == enabled:
		return
	batching_enabled = enabled
	_apply_overrides()

func _on_control_redraw() -> void:
	# Native controls invalidate themselves for disabled, theme, text and input
	# changes. Queueing our draw during the same flush avoids a per-frame scan.
	if batching_enabled:
		queue_redraw()

func _draw() -> void:
	if not batching_enabled:
		return
	for item in _items:
		var control: Control = item.control
		if not control.is_visible_in_tree():
			continue
		var state: int = control.get_draw_mode() if control is Button else 0
		draw_set_transform_matrix(get_global_transform().affine_inverse() * control.get_global_transform())
		draw_style_box(item.variants[control.theme_type_variation][STATES[state]], Rect2(Vector2.ZERO, control.size))
	draw_set_transform(Vector2.ZERO)
