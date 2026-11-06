extends SceneTree
var failures = 0
var checks = 0
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		printerr(label)
func _init(): call_deferred('run')
func run():
	var sound = load('res://scripts/sound.gd').new()
	root.add_child(sound)
	var levels = []
	for gesture in sound.CARD_VARIANTS:
		for i in sound.CARD_VARIANTS[gesture]:
			var clip = sound.cache['%s-%s'%[gesture,i+1]]
			# Godot may import WAV as compressed QOA; inspect decoded output.
			var playback = clip.instantiate_playback()
			playback.start()
			var frames = playback.mix_audio(1.0,roundi(clip.get_length()*AudioServer.get_mix_rate()))
			playback.stop()
			var power = 0.0
			var peak = 0.0
			for frame in frames:
				power += frame.length_squared()
				peak = maxf(peak,maxf(absf(frame.x),absf(frame.y)))
			levels.append(linear_to_db(sqrt(power/(frames.size()*2))))
			check(peak<.701,'No clipping in '+gesture)
			check(clip.get_length()<=.161,'Short cue retained: '+gesture)
	check(levels.max()-levels.min()<.1,'All recorded variants match within 0.1 dB RMS')
	for i in 80:
		sound.clock += .08
		sound.play_card('lift')
		check(sound.card_player.stream==sound.cache['lift-1'],'Every hover uses the identical recording')
		check(is_equal_approx(sound.card_player.volume_db,linear_to_db(.7*.9)),'Hover gain must not inherit an old fade')
		var hovered = sound.card_player.stream
		sound.clock += .08
		sound.play_card('return')
		check(sound.card_player.stream==hovered,'Leaving a card must not introduce a second sound')
		sound.clock += .08
		sound.play_card('pick')
		check(sound.card_player.stream==sound.cache['pick-1'],'Every selection uses the identical recording')
	check(sound.card_player.max_polyphony==1,'Card gestures cannot accumulate voices')
	for p in sound.pool: check(p.stream==null,'Card sounds do not enter battle voice pool')
	sound.volume = .35
	sound.clock += .08
	sound.play_card('pick')
	check(is_equal_approx(sound.card_player.volume_db,linear_to_db(.35*.9)),'Master volume scales cards consistently')
	var before = sound.card_player.stream
	sound.enabled = false
	sound.clock += .08
	sound.play_card('lift')
	check(sound.card_player.stream==before,'Muted gestures do not trigger')
	sound.stop()
	sound.queue_free()
	await process_frame
	print('%s card audio checks, %s failures; normalized spread %.3f dB'%[checks,failures,levels.max()-levels.min()])
	quit(1 if failures else 0)
