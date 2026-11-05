extends SceneTree
const Atlas=preload('res://scripts/tactical/pixelfx_atlas.gd')
func _initialize():
	var atlas=Atlas.new()
	for id in atlas.sheets:
		var sheet: Dictionary=atlas.sheets[id]
		var texture: Texture2D=sheet.texture
		assert(texture!=null)
		var bounds=Rect2(Vector2.ZERO,texture.get_size())
		for rect in sheet.regions:assert(bounds.encloses(rect))
		assert(atlas.frame_index(id,-.001)==-1)
		assert(atlas.frame_index(id,0)==0)
		assert(atlas.frame_index(id,atlas.duration(id))==-1)
		assert(atlas.frame_index(id,atlas.duration(id)-.001)==sheet.regions.size()-1)
		var image=texture.get_image()
		# New library effects may retain faint debris; the field explicitly fades their last .35 seconds.
		if id in ['ground-slam','lightning-strike']:assert(image.get_region(sheet.regions.back()).is_invisible())
	var strike=atlas.sheets['lightning-strike']
	assert(atlas.frame_index('lightning-strike',23/30.0)==23)
	assert(not strike.texture.get_image().get_region(strike.regions[23]).is_invisible())
	print('PIXELFX: textures, frame bounds, timing, impact frame and empty endings PASS')
	quit()
