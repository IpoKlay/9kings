extends Control
const Catalog=preload('res://scripts/data/catalog.gd')
var preset: Dictionary=Catalog.presentation('card_hand')
## Resting hit regions are stable while artwork moves, preventing hover oscillation
## at overlapping edges. The lifted card gets a visual top layer independently.
signal picked(id: String)
signal cue(gesture: String)
signal drag_changed(dragging: bool,ready: bool)
var CARD_SIZE = preset.card_size
var STEP = preset.step
var LEFT = preset.left
var HOVER_SCALE = preset.hover_scale
var LIFT = preset.lift
var slots: Array = []
var active = -1
var locked = false
var allowed: Callable
var input_enabled = true
var dragging = -1
var press_position = Vector2.ZERO
var drag_origin = Vector2.ZERO
var ready_to_play = false

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_window().focus_exited.connect(cancel_drag)
	get_window().mouse_exited.connect(cancel_drag)

func add_card(card: Button,id: String,index: int):
	# The parent builds text and artwork; the hand owns all motion and hit testing.
	card.reparent(self)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.position = Vector2(LEFT+STEP*index,preset.top+(preset.side_drop if index!=1 else 0))
	card.pivot_offset = preset.pivot
	card.rotation = deg_to_rad((index-1)*preset.fan_degrees)
	card.z_index = index+1
	var shadow = ColorRect.new()
	shadow.position = preset.shadow_offset
	shadow.size = CARD_SIZE
	shadow.color = preset.shadow_color
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.show_behind_parent = true
	card.add_child(shadow)
	slots.append({'card':card,'id':id,'index':index,'origin':card.position,'rotation':card.rotation,'shadow':shadow,'tween':null})

func reveal(with_motion: bool):
	if not with_motion: return
	cue.emit('fan')
	for slot in slots:
		var b = slot.card
		b.position = slot.origin+Vector2(0,preset.deal_drop)
		b.scale = Vector2.ONE*preset.rest_scale
		b.modulate.a = 0
		var tween = create_tween()
		slot.tween = tween
		tween.tween_interval(slot.index*preset.deal_delay)
		tween.tween_callback(func():cue.emit('deal'))
		tween.set_parallel(true)
		tween.tween_property(b,'position',slot.origin,preset.deal_seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(b,'scale',Vector2.ONE,preset.deal_seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(b,'modulate:a',1.0,preset.fade_seconds)

func can_interact() -> bool:
	return not locked and input_enabled and (not allowed.is_valid() or allowed.call())

func resting_hit(point: Vector2) -> int:
	# At the small overlapped strip, the right card is visibly above its left neighbour.
	for i in range(slots.size()-1,-1,-1):
		var s = slots[i]
		var pivot = s.card.pivot_offset
		var local = (point-s.origin-pivot).rotated(-s.rotation)+pivot
		if Rect2(Vector2.ZERO,CARD_SIZE).has_point(local): return i
	return -1

func hit_at(point: Vector2) -> int:
	var rest = resting_hit(point)
	if rest!=-1: return rest
	# The lifted portion above the hand remains clickable.
	if active>=0:
		var b = slots[active].card
		if Rect2(Vector2.ZERO,CARD_SIZE).has_point(b.get_transform().affine_inverse()*point): return active
	return -1

func _input(event):
	if not can_interact():
		cancel_drag()
		return
	if dragging>=0 and ((event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE) or (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT)):
		cancel_drag()
		get_viewport().set_input_as_handled()
		return
	var point=Vector2.ZERO
	if event is InputEventMouse: point=get_global_transform_with_canvas().affine_inverse()*event.position
	if event is InputEventMouseMotion:
		if dragging>=0:
			update_drag(point)
			get_viewport().set_input_as_handled()
		else: set_active(hit_at(point))
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			if dragging>=0:
				get_viewport().set_input_as_handled()
				return
			var index = hit_at(point)
			if index<0: return
			begin_drag(index,point)
		elif dragging>=0:
			# Recheck the release position: crossing the threshold and returning cancels.
			update_drag(point)
			if ready_to_play:
				var id=slots[dragging].id
				clear_drag()
				locked=true
				picked.emit(id)
			else: cancel_drag()
		else: return
		get_viewport().set_input_as_handled()

func begin_drag(index: int,point: Vector2):
	set_active(index)
	dragging=index
	press_position=point
	var slot=slots[index]
	drag_origin=slot.card.position
	stop_motion(slot)
	# Position follows the pointer directly; the existing lift scale can finish independently.
	var tween=create_tween().set_parallel(true)
	slot.tween=tween
	tween.tween_property(slot.card,'scale',Vector2.ONE*HOVER_SCALE,preset.hover_seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(slot.card,'rotation',0.0,preset.hover_seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(slot.shadow,'position',preset.hover_shadow,preset.hover_seconds)
	drag_changed.emit(true,false)

func update_drag(point: Vector2):
	var delta=point-press_position
	slots[dragging].card.position=drag_origin+delta.snapped(Vector2.ONE*preset.drag_pixel_step)
	var ready=-delta.y>=preset.drag_threshold and -delta.y>=absf(delta.x)
	if ready==ready_to_play: return
	ready_to_play=ready
	slots[dragging].card.get_node('CardFrame').set_armed(ready)
	drag_changed.emit(true,ready)

func clear_drag():
	if dragging>=0: slots[dragging].card.get_node('CardFrame').set_armed(false)
	dragging=-1
	ready_to_play=false
	drag_changed.emit(false,false)

func cancel_drag():
	if dragging<0: return
	clear_drag()
	set_active(-1)

func _process(_delta):
	if dragging>=0 and not can_interact(): cancel_drag()
	if not locked and active>=0 and allowed.is_valid() and not allowed.call(): set_active(-1,false)

func stop_motion(slot: Dictionary):
	if slot.tween!=null and slot.tween.is_valid(): slot.tween.kill()

func set_active(index: int,with_sound: bool = true):
	if locked: return
	if dragging>=0:
		if index!=-1: return # Keep ownership of the pressed card across its neighbours.
		clear_drag()
	if index==active: return
	var previous = active
	active = index
	for s in slots:
		stop_motion(s)
		var focus = s.index==index
		var b = s.card
		b.z_index = 20 if focus else s.index+1
		b.modulate.a = 1
		var tween = create_tween().set_parallel(true)
		s.tween = tween
		var duration = preset.hover_seconds if focus else preset.return_seconds
		tween.tween_property(b,'position',s.origin-Vector2(0,LIFT) if focus else s.origin,duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(b,'scale',Vector2.ONE*HOVER_SCALE if focus else Vector2.ONE,duration).set_trans(Tween.TRANS_BACK if focus else Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(b,'rotation',0.0 if focus else s.rotation,duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(s.shadow,'position',preset.hover_shadow if focus else preset.shadow_offset,duration)
	if with_sound:
		if index>=0: cue.emit('lift')
		elif previous>=0: cue.emit('return')

func commit(id: String):
	locked = true
	cue.emit('pick')
	var selected = -1
	for s in slots:
		if s.id==id: selected=s.index
	for s in slots:
		stop_motion(s)
		var b = s.card
		var focus = s.index==selected
		b.z_index = 25 if focus else s.index+1
		var tween = create_tween().set_parallel(true)
		s.tween = tween
		tween.tween_property(b,'position',b.position-Vector2(0,preset.pick_lift) if focus else s.origin+Vector2(0,preset.discard_drop),preset.pick_seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(b,'scale',Vector2.ONE*(HOVER_SCALE+preset.pick_scale_extra) if focus else Vector2.ONE*preset.rest_scale,preset.pick_seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(b,'rotation',0.0 if focus else s.rotation,preset.pick_fade_seconds)
		tween.tween_property(b,'modulate:a',1.0 if focus else 0.0,preset.pick_fade_seconds)
	await get_tree().create_timer(preset.pick_wait_seconds).timeout
