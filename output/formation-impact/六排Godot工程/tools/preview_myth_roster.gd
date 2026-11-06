extends SceneTree
func _initialize():call_deferred('run')
func run():
	var folder=ProjectSettings.globalize_path('res://../output/myth-roster')
	var entries=JSON.parse_string(FileAccess.get_file_as_string(folder+'/briefs.json'))
	entries.insert(1,{'id':'poseidon','name':'波塞冬','category':'god'})
	var viewport=SubViewport.new()
	viewport.size=Vector2i(1536,1696)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	var canvas=Control.new()
	canvas.theme=load('res://assets/fonts/game_pixel_theme.tres')
	viewport.add_child(canvas)
	var bg=ColorRect.new()
	bg.color=Color('#172e36');bg.size=Vector2(viewport.size);canvas.add_child(bg)
	var title=Label.new()
	title.text='鹰旗之下 · 神话角色';title.position=Vector2(28,20)
	title.add_theme_font_size_override('font_size',38);title.add_theme_color_override('font_color',Color('#ead7a0'));canvas.add_child(title)
	for i in entries.size():
		var entry=entries[i]
		var pos=Vector2(24+(i%4)*378,100+int(i/4.0)*390)
		var card=ColorRect.new();card.position=pos;card.size=Vector2(354,370);card.color=Color('#a69873');canvas.add_child(card)
		var picture=TextureRect.new();picture.position=pos+Vector2(10,10);picture.size=Vector2(334,308)
		picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if entry.id=='poseidon':
			var atlas=AtlasTexture.new();atlas.atlas=load('res://assets/gods/poseidon_ocean_cast.png');atlas.region=Rect2(1024,528,512,496);picture.texture=atlas
		else:picture.texture=ImageTexture.create_from_image(Image.load_from_file(folder+'/final/'+entry.id+'.png'))
		canvas.add_child(picture)
		var label=Label.new();label.text=entry.name;label.position=pos+Vector2(0,322);label.size=Vector2(354,44)
		label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.add_theme_font_size_override('font_size',28);label.add_theme_color_override('font_color',Color('#172e36'));canvas.add_child(label)
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(folder+'/roster-overview.png')
	print('MYTH ROSTER: 14 character preview rendered with native Godot alpha compositing')
	viewport.queue_free()
	await process_frame
	quit()
