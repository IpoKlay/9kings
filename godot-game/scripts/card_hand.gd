extends Control
## Resting hit regions are stable while artwork moves, preventing hover oscillation
## at overlapping edges. The lifted card gets a visual top layer independently.
signal picked(id: String)
signal cue(gesture: String)
const CARD_SIZE = Vector2(240,334)
const STEP = 222.0
const LEFT = 618.0
const HOVER_SCALE = 1.40
const LIFT = 58.0
var slots: Array = []
var active = -1
var locked = false
var allowed: Callable
var input_enabled = true

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func add_card(card: Button,id: String,index: int):
	# The parent builds text and artwork; the hand owns all motion and hit testing.
	card.reparent(self)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.position = Vector2(LEFT+STEP*index,731+(7 if index!=1 else 0))
	card.pivot_offset = Vector2(120,300)
	card.rotation = deg_to_rad((index-1)*1.4)
	card.z_index = index+1
	var shadow = ColorRect.new()
	shadow.position = Vector2(6,8)
	shadow.size = CARD_SIZE
	shadow.color = Color(0.025,.035,.02,.32)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.show_behind_parent = true
	card.add_child(shadow)
	slots.append({'card':card,'id':id,'index':index,'origin':card.position,'rotation':card.rotation,'shadow':shadow,'tween':null})

func reveal(with_motion: bool):
	if not with_motion: return
	cue.emit('fan')
	for slot in slots:
		var b = slot.card
		b.position = slot.origin+Vector2(0,38)
		b.scale = Vector2(.97,.97)
		b.modulate.a = 0
		var tween = create_tween()
		slot.tween = tween
		tween.tween_interval(slot.index*.065)
		tween.tween_callback(func():cue.emit('deal'))
		tween.set_parallel(true)
		tween.tween_property(b,'position',slot.origin,.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(b,'scale',Vector2.ONE,.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(b,'modulate:a',1.0,.12)

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
	if not can_interact(): return
	if event is InputEventMouseMotion:
		set_active(hit_at(get_local_mouse_position()))
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		var index = hit_at(get_local_mouse_position())
		if index>=0:
			get_viewport().set_input_as_handled()
			picked.emit(slots[index].id)

func _process(_delta):
	if not locked and active>=0 and allowed.is_valid() and not allowed.call(): set_active(-1,false)

func stop_motion(slot: Dictionary):
	if slot.tween!=null and slot.tween.is_valid(): slot.tween.kill()

func set_active(index: int,with_sound: bool = true):
	if locked or index==active: return
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
		var duration = .19 if focus else .22
		tween.tween_property(b,'position',s.origin-Vector2(0,LIFT) if focus else s.origin,duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(b,'scale',Vector2.ONE*HOVER_SCALE if focus else Vector2.ONE,duration).set_trans(Tween.TRANS_BACK if focus else Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(b,'rotation',0.0 if focus else s.rotation,duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(s.shadow,'position',Vector2(12,19) if focus else Vector2(6,8),duration)
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
		tween.tween_property(b,'position',s.origin-Vector2(0,88) if focus else s.origin+Vector2(0,26),.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(b,'scale',Vector2.ONE*(HOVER_SCALE+.04) if focus else Vector2(.97,.97),.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(b,'rotation',0.0 if focus else s.rotation,.16)
		tween.tween_property(b,'modulate:a',1.0 if focus else 0.0,.16)
	await get_tree().create_timer(.22).timeout
