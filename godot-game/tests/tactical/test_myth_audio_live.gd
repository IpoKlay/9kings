extends SceneTree
var failures=0
var cues=[]
var recording=PackedVector2Array()
var out='res://../output/myth-audio/'
func _initialize():call_deferred('run')
func check(ok: bool,message: String):
	if not ok:
		failures+=1;push_error(message)
func run():
	create_timer(75).timeout.connect(func():push_error('AUDIO LIVE TIMEOUT');quit(1))
	var main=load('res://scenes/main.tscn').instantiate()
	main.run_path_override='user://myth-audio-verification-absent.json'
	root.add_child(main);await process_frame
	var before=main.campaign.g.duplicate(true)
	var prefs=main.prefs.duplicate(true)
	main.prefs.enabled=true;main.prefs.volume=.7
	main.open_tactical_trial();await process_frame
	var trial=root.get_child(root.get_child_count()-1)
	trial.myth_audio.cue_played.connect(func(id,stage):cues.append(id+'_'+stage))
	var bus=AudioServer.get_bus_index('EagleMythFX')
	var capture=AudioEffectCapture.new();capture.buffer_length=5
	AudioServer.add_bus_effect(bus,capture)
	var listing=[]
	for row in trial.rules.characters:
		trial.retry();await create_timer(.1).timeout
		capture.clear_buffer();cues.clear()
		trial.rules.deploy('legion',Vector2(650,500))
		trial.rules.deploy('archer',Vector2(380,650))
		trial.start_button.pressed.emit()
		trial.character_picker.item_selected.emit(trial.character_ids.find(row.id))
		var pos=Vector2(650,500) if row.id=='athena' else Vector2(1160,545)
		var e=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=true
		e.position=trial.field.project(pos);e.global_position=e.position
		root.push_input(e,true)
		e=e.duplicate();e.pressed=false;root.push_input(e,true)
		await create_timer(2.8).timeout
		check(row.id+'_cast' in cues,row.id+' cast missing via real input')
		check(row.id+'_impact' in cues,row.id+' impact missing via actual rules')
		var samples=capture.get_buffer(capture.get_frames_available())
		var peak=0.0
		var energy=0.0
		for s in samples:
			peak=maxf(peak,maxf(absf(s.x),absf(s.y)));energy+=s.length_squared()
		check(peak>.005,row.id+' silent on rendered audio bus')
		check(peak<1,row.id+' clipped bus')
		check(capture.get_discarded_frames()==0,'Capture overflow')
		listing.append({'id':row.id,'name':row.name,'start_seconds':float(recording.size())/AudioServer.get_mix_rate(),'peak':peak,'rms':sqrt(energy/maxi(1,samples.size()*2)),'cues':cues.duplicate()})
		recording.append_array(samples)
		print('NATIVE AUDIO PASS ',row.id,' peak=',peak,' cues=',cues)
	trial.paused=true;await create_timer(.08).timeout
	check(trial.myth_audio.paused,'Trial pause not passed to sound')
	trial.retry()
	check(trial.myth_audio.pending.is_empty() and trial.myth_audio.voices.all(func(v):return v.remaining==0),'Retry leaked audio')
	AudioServer.remove_bus_effect(bus,AudioServer.get_bus_effect_count(bus)-1)
	trial.closed.emit();await process_frame
	check(main.campaign.g==before,'Campaign state changed')
	main.prefs=prefs;main.queue_free();await process_frame
	var bytes=PackedByteArray();bytes.resize(recording.size()*4)
	for i in recording.size():
		bytes.encode_s16(i*4,roundi(clampf(recording[i].x,-1,1)*32767))
		bytes.encode_s16(i*4+2,roundi(clampf(recording[i].y,-1,1)*32767))
	var wav=AudioStreamWAV.new();wav.format=AudioStreamWAV.FORMAT_16_BITS;wav.stereo=true
	wav.mix_rate=AudioServer.get_mix_rate();wav.data=bytes
	wav.save_to_wav(out+'14-characters-native-audio.wav')
	var file=FileAccess.open(out+'native-audio-results.json',FileAccess.WRITE)
	file.store_string(JSON.stringify({'failures':failures,'characters':listing},'\t'));file.close()
	await create_timer(.25).timeout
	print('NATIVE MYTH AUDIO: ',failures,' failures')
	quit(1 if failures else 0)
