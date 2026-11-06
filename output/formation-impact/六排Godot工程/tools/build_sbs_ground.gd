extends SceneTree
## Reproducible, offline native bake. The running game loads only the resulting PNG.
const OUTPUT='res://assets/environments/sbs/iberia-ground.png'
func _init():call_deferred('run')
func run():
	if DisplayServer.get_name()=='headless':
		printerr('Ground bake requires the native renderer.');quit(1);return
	var viewport=SubViewport.new()
	viewport.size=Vector2i(960,540)
	viewport.transparent_bg=true
	viewport.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var image=TextureRect.new()
	image.texture=ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path('res://assets/environments/sbs/terrain-source.png')))
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	image.size=Vector2(960,540)
	image.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var material=ShaderMaterial.new()
	material.shader=load('res://shaders/sbs_ground_bake.gdshader')
	material.set_shader_parameter('source_atlas',image.texture)
	var field=preload('res://scripts/data/catalog.gd').presentation('field')
	material.set_shader_parameter('projection',Vector4(field.projection_x[0],field.projection_x[1],field.projection_y[0],field.projection_y[1]))
	material.set_shader_parameter('screen_origin',field.screen_origin)
	material.set_shader_parameter('world_origin',field.world_origin)
	image.material=material;viewport.add_child(image)
	await process_frame;await process_frame
	RenderingServer.force_draw()
	var ground=viewport.get_texture().get_image()
	var colors={};var opaque=0
	for y in ground.get_height():
		for x in ground.get_width():
			var c=ground.get_pixel(x,y)
			if c.a>.5: colors[c.to_html()]=true;opaque+=1
	if opaque<=100000 or opaque>=400000 or colors.size()>14:
		printerr('Invalid bake: %d opaque pixels / %d colors'%[opaque,colors.size()]);quit(1);return
	assert(ground.save_png(OUTPUT)==OK)
	print('Baked native ground: %s, %d opaque pixels, %d colors, no runtime shader.'%[ground.get_size(),opaque,colors.size()])
	quit()
