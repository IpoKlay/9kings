extends Control
const RPGUI=preload('res://scripts/rpg_ui.gd')
## Two one-shot GPU page snapshots; no screenshot readback or live offscreen redraw.
var previous: Texture2D
var next: Texture2D
var direction=1
var progress=0.0
var motion: Tween
var grid=4.0
# Width fraction, lifted corner, paper bow: eight poses held at the configured frame rate.
const POSES=[Vector3(1,0,0),Vector3(.93,28,16),Vector3(.69,64,32),Vector3(.28,88,48),Vector3(.21,88,48),Vector3(.60,60,36),Vector3(.91,24,20),Vector3(1,0,0)]
var pose_index=-1

func snapshot(panel: Control,book_theme: Theme) -> Texture2D:
	var buffer=SubViewport.new()
	buffer.size=Vector2i(panel.size)
	buffer.disable_3d=true
	buffer.gui_disable_input=true
	buffer.transparent_bg=true
	buffer.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	buffer.render_target_update_mode=SubViewport.UPDATE_ONCE
	add_child(buffer)
	var page=panel.duplicate(0)
	page.position=Vector2.ZERO
	page.theme=book_theme
	page.process_mode=Node.PROCESS_MODE_DISABLED
	for child in page.get_children():
		if child is Button: child.hide()
	buffer.add_child(page)
	return buffer.get_texture()

func begin(old_page: Control,book_theme: Theme,turn_direction: int):
	name='BookPageTurn'
	position=old_page.position;size=old_page.size
	z_index=110
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	direction=turn_direction
	previous=snapshot(old_page,book_theme)

func play(new_page: Control,book_theme: Theme,preset: Dictionary):
	next=snapshot(new_page,book_theme)
	grid=preset.paper_motion_pixel_step
	motion=create_tween()
	motion.tween_method(set_progress,0.0,1.0,POSES.size()/preset.book_turn_fps)
	motion.finished.connect(finish)
	queue_redraw()

func set_progress(value: float):
	progress=value
	var index=mini(int(value*POSES.size()),POSES.size()-1)
	if index==pose_index: return
	pose_index=index
	queue_redraw()

func finish():
	if motion!=null and motion.is_valid(): motion.kill()
	if is_inside_tree(): get_parent().remove_child(self)
	queue_free()

func page(texture: Texture2D,left: bool,pose: Vector3):
	var half=size.x*.5
	var source: Rect2=RPGUI.BOOK_PAGES[0 if left else 1]
	var width=snappedf(source.size.x*pose.x,grid)
	var full_gap=half-source.end.x if left else source.position.x-half
	var gap=snappedf(full_gap*pose.x,grid)
	if pose.y==0:
		draw_texture_rect_region(texture,Rect2(half-gap-width if left else half+gap,source.position.y,width,source.size.y),source)
		return
	var strips=int(ceil(width/(grid*2)))
	var top_edge=PackedVector2Array()
	var bottom_edge=PackedVector2Array()
	var previous_top=Vector2.ZERO
	var previous_bottom=Vector2.ZERO
	for i in range(strips+1):
		var u=float(i)/strips
		var x=half+(-1 if left else 1)*(gap+snappedf(width*u,grid))
		var rise=pose.y*u
		var bow=pose.z*sin(PI*u)
		var top=Vector2(x,source.position.y-snappedf(rise*.6+bow,grid))
		var bottom=Vector2(x,source.end.y-snappedf(rise*.2-bow*.25,grid))
		if i>0:
			var last_u=float(i-1)/strips
			var a=source.position.x+source.size.x*(1-last_u if left else last_u)
			var b=source.position.x+source.size.x*(1-u if left else u)
			var uv=PackedVector2Array([Vector2(a,source.position.y)/size,Vector2(b,source.position.y)/size,Vector2(b,source.end.y)/size,Vector2(a,source.end.y)/size])
			draw_polygon(PackedVector2Array([previous_top,top,bottom,previous_bottom]),PackedColorArray([Color.WHITE]),uv,texture)
			top_edge.append(Vector2(top.x,previous_top.y))
			bottom_edge.append(Vector2(bottom.x,previous_bottom.y))
		top_edge.append(top);bottom_edge.append(bottom)
		previous_top=top;previous_bottom=bottom
	draw_polyline(top_edge,Color('#b49a5e'),grid,false)
	draw_polyline(bottom_edge,Color('#9b7b48'),grid,false)
	draw_line(previous_top,previous_bottom,Color('#9b7b48'),grid,false)

func _draw():
	if previous==null or next==null: return
	var forward=direction>0
	page(previous,forward,POSES[0])
	var index=maxi(0,pose_index)
	var first_half=index<POSES.size()/2
	page(previous if first_half else next,not forward if first_half else forward,POSES[index])
