extends SceneTree
func _initialize():call_deferred('run')
func run():
	var sound=load('res://scripts/sound.gd').new()
	root.add_child(sound)
	await process_frame
	for kind in ['impact','arrow','cry']:
		for i in sound.variants[kind]:
			var stream=sound.cache[kind+str(i)] as AudioStreamWAV
			assert(stream!=null and stream.get_length()>.1)
			assert(stream.resource_path.begins_with('res://assets/combat_audio/'))
			sound.clock+=5
			sound.play(kind)
			assert(sound.pool.any(func(p):return p.playing and p.stream==stream))
			await create_timer(.12).timeout
			sound.stop()
	var quake=load('res://assets/combat_audio/earthquake.wav') as AudioStreamWAV
	assert(quake.get_length()>2 and quake.get_length()<3.2)
	for side in ['ally','enemy']:
		for mode in ['idle','walk','attack','testudo','testudo_walk','testudo_attack']:
			var tex=load('res://assets/unit_cavalry_'+side+'_'+mode+'.png') as Texture2D
			assert(tex.get_size()==Vector2(1024,64))
			var img=tex.get_image()
			var unique={}
			for frame in 16:
				var crop=img.get_region(Rect2i(frame*64,0,64,64))
				assert(not crop.is_invisible())
				unique[hash(crop.get_data())]=true
				assert(crop.get_region(Rect2i(0,0,64,1)).is_invisible())
				assert(crop.get_region(Rect2i(0,63,64,1)).is_invisible())
			if mode.contains('walk'):assert(unique.size()>=8)
	sound.enabled=false
	sound.clock+=5
	sound.play('impact')
	assert(sound.pool.all(func(p):return not p.playing))
	sound.queue_free()
	await process_frame
	print('COMBAT ASSETS: native sound routing, variations, mute and 12 cavalry sheets PASS')
	quit()
