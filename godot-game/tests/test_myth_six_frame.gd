extends SceneTree
var seen = {}
var completed = {}
var elapsed = 0.0
var sprites = {}
var failures: Array[String] = []
func check(condition: bool, message: String):
	if not condition: failures.append(message)
func _initialize(): call_deferred('run')
func run():
	var data = JSON.parse_string(FileAccess.get_file_as_string('res://assets/mythology/animated_oblique/source.json'))
	check(data.characters.size()==14,'Roster must contain 14 characters')
	for entry in data.characters:
		var frames: SpriteFrames = load(entry.sprite_frames)
		check(frames!=null,entry.id+' missing resource')
		check(frames.get_frame_count('action')==6,entry.id+' must have six frames')
		check(frames.get_animation_speed('action')==6,entry.id+' must play at six fps')
		check(not frames.get_animation_loop('action'),entry.id+' must finish once')
		var duration=0.0
		for i in 6:
			duration+=frames.get_frame_duration('action',i)/frames.get_animation_speed('action')
			var texture=frames.get_frame_texture('action',i)
			check(texture is AtlasTexture,entry.id+' expected atlas frame')
			check(texture.region.size==Vector2(512,512),entry.id+' unexpected source cell')
			check(texture.get_size()==Vector2(768,768),entry.id+' canvas changes between frames')
		check(absf(duration-1.0)<0.00001,entry.id+' duration is not one second')
		var sprite=AnimatedSprite2D.new();sprite.sprite_frames=frames;root.add_child(sprite)
		seen[entry.id]={0:true};sprites[entry.id]=sprite
		sprite.frame_changed.connect(func():seen[entry.id][sprite.frame]=true)
		sprite.animation_finished.connect(func():completed[entry.id]=elapsed)
	for sprite in sprites.values():sprite.play('action')
	while elapsed<1.22:
		await process_frame
		elapsed+=root.get_process_delta_time()
	for entry in data.characters:
		check(seen[entry.id].size()==6,entry.id+' did not visit all six native frames')
		check(completed.has(entry.id),entry.id+' never finished')
		if completed.has(entry.id):check(absf(completed[entry.id]-1.0)<0.09,entry.id+' native playback duration differs from one second')
		check(not sprites[entry.id].is_playing(),entry.id+' unexpectedly loops')
		sprites[entry.id].queue_free()
	var gallery=load('res://scenes/myth_animation_gallery.tscn').instantiate()
	root.add_child(gallery)
	check(gallery.sprites.size()==6,'God tab count')
	gallery.show_group('hero');check(gallery.sprites.size()==3,'Hero tab count')
	gallery.show_group('monster');check(gallery.sprites.size()==5,'Monster tab count')
	gallery.replay_all()
	for sprite in gallery.sprites:check(sprite.frame==0 and sprite.is_playing(),'Replay must restart native animation at frame zero')
	gallery.queue_free();await process_frame
	if failures.is_empty():
		print('PASS: 14 resources, 84 atlas frames, six fps/one second, all native frames visited, non-looping completion, 3 gallery tabs and replay.')
		print('NATIVE COMPLETION TIMES: ',JSON.stringify(completed))
	else:
		for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
