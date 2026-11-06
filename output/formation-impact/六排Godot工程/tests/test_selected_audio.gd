extends SceneTree
const OUT='res://../output/camp-expansion-v1/'
var app
var sound
var checks=0
var failures=0
var capture: AudioEffectCapture
var recording=PackedVector2Array()
func _init(): call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1;printerr('FAIL: '+message)
func _process(_delta):
	if capture!=null: recording.append_array(capture.get_buffer(capture.get_frames_available()))
	return false
func run():
	if DisplayServer.get_name()=='headless':
		printerr('Selected audio checks require the native mixer');quit(1);return
	root.size=Vector2i(1280,720)
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path=OUT+'test-settings.cfg'
	root.add_child(app);current_scene=app;app.set_process(false)
	sound=app.sound
	app.prefs.volume=.7;app.prefs.enabled=true;app.prefs.music_volume=0;app.apply_prefs()
	AudioServer.add_bus()
	var bus=AudioServer.bus_count-1
	AudioServer.set_bus_name(bus,'SelectedAudioCapture')
	capture=AudioEffectCapture.new();capture.buffer_length=2
	AudioServer.add_bus_effect(bus,capture)
	for p in sound.pool+sound.ambience_players.values():p.bus='SelectedAudioCapture'
	var manifest=JSON.parse_string(FileAccess.get_file_as_string('res://assets/selected_audio/SOURCES.json'))
	var sources={}
	for clip in manifest:
		sources[clip.selection]=true
		var stream=load('res://assets/selected_audio/'+clip.file)
		var playback=stream.instantiate_playback();playback.start()
		var frames=playback.mix_audio(1,roundi(stream.get_length()*AudioServer.get_mix_rate()))
		playback.stop()
		var peak=0.0
		for frame in frames:peak=maxf(peak,maxf(absf(frame.x),absf(frame.y)))
		check(peak>.01 and peak<.73,'Selected recording decodes with headroom: '+clip.file)
		check(clip.source.begins_with('https://') and clip.license=='CC0 1.0','Source and CC0 attribution: '+clip.file)
	check(sources.size()==8,'All eight selected SFX sources represented')
	for id in sound.ambience_players:
		var stream=sound.ambience_players[id].stream
		check(stream.loop_mode==AudioStreamWAV.LOOP_FORWARD and stream.loop_end>0,'Native ambient loop: '+id)
	for kind in sound.preset.effect_files:
		sound.stop()
		for i in sound.variants[kind]:
			sound.clock+=5
			sound.play(kind)
			check(sound.rotation[kind]==i,'Cycles selected variation '+kind+str(i))
			check(sound.pool.any(func(p):return p.playing and p.stream==sound.cache[kind+str(i)]),'Native player starts '+kind+str(i))
			await create_timer(.08).timeout
		var before=sound.last[kind]
		sound.play(kind)
		# Audio clock has advanced during playback; reset to the original event to isolate cooldown.
		sound.clock=before
		var rotation=sound.rotation[kind]
		sound.play(kind)
		check(sound.rotation[kind]==rotation,'Repeated frame cannot retrigger '+kind)
	sound.stop()
	app.restart_expedition(1);app.expedition_map.settle_entry()
	check(app.music.requested_track=='map' and sound.ambience_target=='sea','Map routes The Great Sea and waves')
	await create_timer(1.6).timeout
	check(sound.ambience_players.sea.playing and sound.ambience_levels.sea==1,'Sea fades fully in')
	var before=sound.ambience_players.sea.get_playback_position()
	app.render_ui();await create_timer(.15).timeout
	check(sound.ambience_players.sea.get_playback_position()>before,'Map redraw does not restart ambience')
	app.open_dialog('settings');await create_timer(.8).timeout
	check(sound.ambience_levels.sea<.6,'Settings soften ambience smoothly')
	app.close_dialog()
	app.documents.open_archive(app.documents.archive_ids()[0]);await create_timer(1.6).timeout
	check(not sound.ambience_players.sea.playing,'History book fades out map ambience')
	app.close_dialog()
	# First destination enters battle; use a victory fixture to inspect camp ambience.
	var target=app.expedition.destinations().filter(func(id):return app.expedition.can_travel(id))[0]
	app.travel_to(target);check(app.campaign.g.phase=='battle','Bare opening starts battle immediately')
	app.campaign.finish(true);app.advance();await create_timer(1.6).timeout
	check(app.music.requested_track=='camp' and sound.ambience_players.fire.playing,'Deployment keeps camp music and fire')
	check(not sound.ambience_players.sea.playing,'Only the active environment remains after fading')
	app.prefs.enabled=false;app.apply_prefs()
	check(sound.ambience_players.values().all(func(p):return not p.playing),'Effects mute stops ambience immediately')
	app.prefs.enabled=true;app.apply_prefs();await create_timer(.2).timeout
	check(sound.ambience_players.fire.playing and sound.ambience_levels.fire<.3,'Unmute gently fades ambience back')
	app.prefs.volume=0;app.apply_prefs()
	check(sound.ambience_players.values().all(func(p):return p.volume_linear==0 and not p.playing),'Master zero silences the running environment')
	app.prefs.volume=.7;app.apply_prefs()
	app.skip_supply();app.continue_expedition();app.travel_to(app.expedition.destinations()[0])
	check(app.campaign.g.phase=='battle','Next destination starts battle after earned supplies')
	check(sound.last.has('horn') and sound.last.has('equip'),'Opening battle plays the selected horn and equipment')
	for i in 12:
		app._process(.04);await create_timer(.04).timeout
	check(sound.last.has('foot'),'Moving troops produce quiet footsteps')
	var foot_time=sound.last.get('foot',-1)
	app.toggle_pause()
	for i in 8:app._process(.04);await create_timer(.04).timeout
	check(sound.last.get('foot',-1)==foot_time,'Paused troops do not trigger footsteps')
	app.toggle_pause()
	await create_timer(1.6).timeout
	check(sound.ambience_players.values().all(func(p):return not p.playing),'Battle has no leftover camp or map loop')
	# Complete the real multiwave battle, then claim exactly one reward.
	for wave in app.campaign.g.battle.waves.size():
		for u in app.campaign.g.battle.units:
			if u.side=='enemy':u.hp=0
		for i in 400:app.campaign.step(1.0/60)
	check(app.has_battle_report(),'Real battle reaches one result')
	sound.clock+=5;app.advance()
	check(sound.last.has('reward'),'Claiming victory uses the selected coins')
	var reward_time=sound.last.get('reward',-1)
	sound.clock+=5;app.advance()
	check(sound.last.get('reward',-1)==reward_time,'Repeated claim cannot duplicate coins')
	app.return_to_menu();await create_timer(1.6).timeout
	check(sound.ambience_target=='' and sound.ambience_players.values().all(func(p):return not p.playing),'Return to menu clears all environment loops')
	check(sound.pool.size()==12,'Sound voice pool stays bounded')
	var peak=0.0
	for frame in recording:peak=maxf(peak,maxf(absf(frame.x),absf(frame.y)))
	check(peak>.03 and peak<.95,'Captured effects are audible without clipping')
	var bytes=PackedByteArray();bytes.resize(recording.size()*4)
	for i in recording.size():
		bytes.encode_s16(i*4,roundi(clampf(recording[i].x,-1,1)*32767))
		bytes.encode_s16(i*4+2,roundi(clampf(recording[i].y,-1,1)*32767))
	var wav=AudioStreamWAV.new();wav.format=AudioStreamWAV.FORMAT_16_BITS;wav.stereo=true;wav.mix_rate=int(AudioServer.get_mix_rate());wav.data=bytes
	wav.save_to_wav(OUT+'native-effects-validation.wav')
	print('Captured ',recording.size()/float(wav.mix_rate),' seconds; peak ',peak)
	capture=null;app.free();await process_frame;AudioServer.remove_bus(bus)
	print('%d selected audio checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
