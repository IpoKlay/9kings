extends Control
## Screen-space fasteners: the paper and controls are already visible and interactive.
const Catalog=preload('res://scripts/data/catalog.gd')
const HEAD=[
	'....1111....',
	'..11222211..',
	'.1234444321.',
	'123455443321',
	'123444433321',
	'123444333321',
	'123433333321',
	'.1233333321.',
	'..12222221..',
	'...111111...'
]
var preset=Catalog.presentation('ui').map_pins
var sound
var age=0.0
var pose_time=0.0
var landed=[true,true,true,true]
var finished=true
var reduced=false

func _ready():
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	z_index=5
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
	set_process(false)

func duration() -> float:
	return preset.drop_seconds+3*preset.stagger_seconds+preset.impact_seconds

func centers() -> Array[Vector2]:
	var inset=preset.inset
	return [Vector2(inset,inset),Vector2(size.x-inset,inset),Vector2(inset,size.y-inset),size-Vector2.ONE*inset]

func begin(player,reduce_motion: bool):
	sound=player
	sound.stop_map_entry()
	sound.play_map_paper()
	reduced=reduce_motion
	age=0;pose_time=0
	landed=[false,false,false,false]
	finished=false
	if reduced: settle();return
	queue_redraw()
	set_process(true)

func settle():
	finished=true
	landed=[true,true,true,true]
	age=duration();pose_time=age
	set_process(false)
	queue_redraw()

func _process(delta):
	advance(delta)

func advance(delta):
	if finished: return
	age=minf(age+delta,duration())
	var next_pose=floorf(age*preset.fps)/preset.fps
	for i in 4:
		if not landed[i] and next_pose>=i*preset.stagger_seconds+preset.drop_seconds:
			landed[i]=true
			if is_instance_valid(sound): sound.play_map_pin()
	if age>=duration(): settle();return
	if next_pose!=pose_time:
		pose_time=next_pose
		queue_redraw()

func offset_for(index: int) -> Vector2:
	if finished: return Vector2.ZERO
	var progress=clampf((pose_time-index*preset.stagger_seconds)/preset.drop_seconds,0,1)
	return Vector2(0,-preset.drop_height*(1-progress)).snapped(Vector2.ONE*preset.pixel_step)

func _draw():
	var grid=float(preset.pixel_step)
	var spots=centers()
	for i in 4:
		var local_time=pose_time-i*preset.stagger_seconds
		if not finished and local_time<0:continue
		var spot=spots[i].snapped(Vector2.ONE*grid)
		var offset=offset_for(i)
		# Two flat pixel tones, without a soft blur or a moving 3D reflection.
		draw_rect(Rect2(spot+Vector2(-4,3)*grid,Vector2(9,3)*grid),preset.shadow)
		var head=spot+offset-Vector2(6,5)*grid
		if not landed[i]:draw_rect(Rect2(head+Vector2(5,8)*grid,Vector2(2,5)*grid),preset.palette[1])
		for y in HEAD.size():
			for x in HEAD[y].length():
				var pigment=HEAD[y][x]
				if pigment!='.':draw_rect(Rect2(head+Vector2(x,y)*grid,Vector2.ONE*grid),preset.palette[int(pigment)])
		if landed[i] and not finished and local_time<preset.drop_seconds+preset.impact_seconds:
			for side in [-1,1]:
				draw_rect(Rect2(spot+Vector2(side*8-1,2)*grid,Vector2(2,1)*grid),preset.palette[2])
