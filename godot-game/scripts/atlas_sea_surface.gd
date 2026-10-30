extends TextureRect
## Cache the unchanged sea shader at the actual screen resolution, never upscale a low-res proxy.
var source: TextureRect
var buffer: SubViewport
var sea
var rendered_revision=-1
var direct=false

func setup(atlas_texture: Texture2D,water):
	sea=water
	expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	show_behind_parent=true
	buffer=SubViewport.new()
	buffer.disable_3d=true
	buffer.gui_disable_input=true
	buffer.transparent_bg=true
	buffer.render_target_update_mode=SubViewport.UPDATE_DISABLED
	buffer.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(buffer)
	source=TextureRect.new()
	# The live surface leaves its input-disabled viewport during wind and camera movement.
	source.mouse_filter=Control.MOUSE_FILTER_IGNORE
	source.texture=atlas_texture
	source.material=sea.material
	source.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	source.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	source.show_behind_parent=true
	buffer.add_child(source)
	texture=buffer.get_texture()
	get_viewport().size_changed.connect(refresh)

func refresh():
	# A replaced map can still receive resize before its queued deletion.
	if buffer==null or not is_inside_tree(): return
	var pixel_scale=get_viewport().get_final_transform().get_scale()*get_global_transform_with_canvas().get_scale()
	var dimensions=Vector2i((size*pixel_scale).ceil()).max(Vector2i.ONE)
	if buffer.size!=dimensions: buffer.size=dimensions
	buffer.canvas_transform=Transform2D.IDENTITY.scaled(pixel_scale)
	if not direct: buffer.render_target_update_mode=SubViewport.UPDATE_ONCE
	rendered_revision=sea.revision

func refresh_if_needed(moving_camera: bool=false,paused: bool=false):
	var live=not paused and (moving_camera or not sea.gusts.is_empty())
	if live!=direct:
		direct=live
		source.reparent(get_parent() if direct else buffer,false)
		visible=not direct
		if direct: buffer.render_target_update_mode=SubViewport.UPDATE_DISABLED
		else: refresh()
	if direct: return
	if rendered_revision!=sea.revision: refresh()
