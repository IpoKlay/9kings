extends SceneTree
## Import generated sources onto the fixed game pixel grid; no painted rescaling.
func _init():
	for type in ['siege','medic']:
		for level in range(1,4):
			var filename='%s_%d.png'%[type,level]
			var image=Image.load_from_file(ProjectSettings.globalize_path('res://../output/legions-v1/source-art/'+filename))
			assert(image!=null and not image.is_empty())
			image.resize(96,96,Image.INTERPOLATE_NEAREST)
			assert(image.save_png('res://assets/facilities/'+filename)==OK)
	quit()
