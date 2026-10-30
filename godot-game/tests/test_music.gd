extends SceneTree
const Store=preload('res://scripts/data/settings_store.gd')
const OUT='res://../output/music-integration/'
const SETTINGS=OUT+'test-settings.cfg'
var app
var music
var checks=0
var failures=0
var capture: AudioEffectCapture
var recording=PackedVector2Array()
var capturing=false
func _init(): call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1;printerr('FAIL: '+message)
func _process(_delta):
	if capturing and capture!=null:
		recording.append_array(capture.get_buffer(capture.get_frames_available()))
	return false
func player() -> AudioStreamPlayer: return music.players[music.active]
func wait_fade(): await create_timer(float(music.preset.crossfade_seconds)+.2).timeout
func screenshot(name: String):
	if DisplayServer.get_name()=='headless': return
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(OUT+name+'.png')
func click(control: Control):
	for down in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=control.get_global_rect().get_center();event.global_position=event.position
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
		root.push_input(event,true)
	await process_frame
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	for suffix in ['','.bak','.tmp']:
		if FileAccess.file_exists(SETTINGS+suffix):DirAccess.remove_absolute(SETTINGS+suffix)
	var legacy=ConfigFile.new()
	legacy.set_value('settings','volume',.7);legacy.set_value('settings','enabled',false);legacy.save(SETTINGS)
	var migrated=Store.read_settings(SETTINGS)
	check(is_equal_approx(migrated.music_volume,.45) and migrated.volume==.7 and not migrated.enabled,'Old settings gain music without changing SFX preferences')
	for invalid in [INF,NAN,true,'loud',null,[]]:
		check(is_equal_approx(Store.normalized({'music_volume':invalid}).music_volume,.45),'Invalid music setting falls back: '+str(invalid))
	check(Store.normalized({'music_volume':-1}).music_volume==0 and Store.normalized({'music_volume':2}).music_volume==1,'Music volume clamps safely')
	root.size=Vector2i(1280,720)
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path=SETTINGS
	root.add_child(app);current_scene=app;app.set_process(false)
	music=app.music
	AudioServer.add_bus()
	var bus=AudioServer.bus_count-1
	AudioServer.set_bus_name(bus,'MusicTestCapture')
	capture=AudioEffectCapture.new();capture.buffer_length=2
	AudioServer.add_bus_effect(bus,capture)
	for p in music.players:p.bus='MusicTestCapture'
	capturing=true
	for id in music.preset.tracks:
		var stream=music.streams[id]
		check(stream is AudioStreamMP3 and stream.get_length()>100,'Complete native recording loads: '+id)
	check(music.requested_track=='menu','Main menu selects The Pyre')
	await wait_fade()
	check(player().playing and player().get_playback_position()>3,'Actual native audio clock advances from the trimmed intro')
	check(not app.sound.enabled and player().volume_linear>0,'Sound-effects switch does not disable music')
	app.open_dialog('settings')
	var before=player().get_playback_position()
	await create_timer(.3).timeout
	check(player().get_playback_position()>before and music.target_duck<1,'Settings lower music without restarting it')
	for language in ['zh','en']:
		app.set_language(language)
		var panel=app.modal.get_child(1)
		var slider=panel.get_node('Volume_music_volume')
		slider.value=.6
		check(is_equal_approx(app.prefs.music_volume,.6) and is_equal_approx(Store.read_settings(SETTINGS).music_volume,.6),'Music slider is saved independently in '+language)
		check(is_equal_approx(app.sound.volume,.7),'Music slider preserves effect gain')
		slider.grab_focus()
		var key=InputEventKey.new();key.pressed=true;key.keycode=KEY_LEFT
		root.push_input(key,true);await process_frame
		check(is_equal_approx(app.prefs.music_volume,.55),'Music slider works with keyboard in '+language)
		check(Rect2(Vector2.ZERO,Vector2(1920,1080)).encloses(panel.get_global_rect()),'Settings fit viewport in '+language)
		await screenshot('settings-'+language)
	await click(app.modal.get_child(1).get_node('MusicCredits'))
	var credits=app.modal.get_child(1).get_node('MusicAttribution')
	for id in music.preset.tracks:check(credits.text.contains(music.preset.tracks[id].title) and credits.text.contains(music.preset.tracks[id].source),'Visible credit and source: '+id)
	check(credits.text.contains('Kevin MacLeod') and credits.text.contains('Scott Buckley') and credits.text.contains('creativecommons.org/licenses/by/4.0/'),'Credits include both authors and license link')
	await screenshot('credits-en')
	await click(app.modal.get_child(1).get_node('BackToSettings'))
	check(app.dialog_kind=='settings','Credits return to settings')
	app.close_dialog()
	app.restart_expedition(1)
	check(music.requested_track=='map' and music.preset.tracks.map.title=='The Great Sea','Map selects The Great Sea')
	await create_timer(.7).timeout
	check(music.players[0].volume_linear>0 and music.players[1].volume_linear>0,'Scene transition overlaps both recordings')
	await wait_fade()
	var camp_position=player().get_playback_position()
	app.documents.open_archive(app.documents.archive_ids()[0])
	check(music.requested_track=='archive','History book selects Ancient Rite')
	await wait_fade()
	before=player().get_playback_position()
	app.documents.turn_page(1)
	await create_timer(.25).timeout
	check(music.requested_track=='archive' and player().get_playback_position()>before,'Page turns preserve the archive playhead')
	app.close_dialog();await wait_fade()
	check(music.requested_track=='map' and player().get_playback_position()>camp_position,'Returning from the book resumes the map recording')
	check(preload('res://tests/expedition_test_support.gd').deploy(app),'Real destination/card/deployment flow enters battle')
	check(music.requested_track=='battle','Ordinary city selects Crusade')
	await wait_fade()
	var battle_player=player()
	before=battle_player.get_playback_position()
	for wave in 2:
		for unit in app.campaign.g.battle.units:
			if unit.side=='enemy':unit.hp=0
		app.campaign.step(.1);app.render_ui()
		check(app.campaign.g.battle.rest_remaining>0 and player()==battle_player,'Wave rest retains the same music player')
		for i in 181: app.campaign.step(1.0/60)
		app.play_events(app.campaign.g.battle.events);app.render_ui()
		await create_timer(.15).timeout
		check(app.campaign.g.battle.wave_index==wave+1 and player()==battle_player and player().get_playback_position()>before,'Next wave continues the same playhead')
	app.open_map();app.open_dialog('settings')
	check(music.requested_track=='battle','Battle map and settings keep the battle cue')
	await screenshot('map-settings-en')
	app.prefs.music_volume=0;app.apply_prefs()
	check(music.players.all(func(p):return p.volume_linear==0),'Music zero mutes immediately')
	before=battle_player.get_playback_position()
	await create_timer(.2).timeout
	check(battle_player.get_playback_position()>before,'Muted music retains a continuous playhead')
	app.prefs.music_volume=.45;app.apply_prefs();app.save_prefs()
	app.close_dialog();app.show_camp();app.toggle_pause();app.change_speed()
	check(music.requested_track=='battle' and player()==battle_player and player().pitch_scale==1,'Pause and game speed do not restart or speed up music')
	app.toggle_pause()
	# Ten real waves at a boss destination; force clears so the test isolates music routing.
	var boss=''
	for id in app.expedition.nodes:
		if app.expedition.nodes[id].kind=='boss':boss=id;break
	app.campaign.g.phase='prepare';app.campaign.g.expedition_wave=app.expedition.encounter(boss)
	app.expedition.state.target=boss;app.expedition.state.mode='battle'
	app.campaign.start();app.begin_battle_feedback();await wait_fade()
	check(music.requested_track=='boss' and music.preset.tracks.boss.title.begins_with('Legionnaire') and app.campaign.g.battle.waves.size()==10,'Boss city selects Legionnaire for all ten waves')
	var boss_player=player()
	for wave in 10:
		for unit in app.campaign.g.battle.units:
			if unit.side=='enemy':unit.hp=0
		app.campaign.step(.1)
		for i in 181:app.campaign.step(1.0/60)
		app.render_ui()
		check(player()==boss_player and music.requested_track=='boss','Boss music persists through wave '+str(wave+1))
	check(app.campaign.g.phase=='result','Ten waves produce one report')
	app.open_dialog('result');await create_timer(.3).timeout
	check(player()==boss_player and music.target_duck<1,'Report keeps a quieter musical ending')
	app.close_dialog()
	# Exercise native loop handoff near the actual end of every file.
	for id in music.preset.tracks:
		music.play_track(id);await wait_fade()
		var old=player()
		old.seek(float(music.preset.tracks[id].end)-float(music.preset.loop_crossfade_seconds)-.15)
		await create_timer(.45).timeout
		check(player()!=old and player().playing and old.playing,'Loop overlaps the original ending and opening: '+id)
		await wait_fade()
		check(player().get_playback_position()<float(music.preset.tracks[id].start)+5 and not old.playing,'Loop retires the tail without leaking a voice: '+id)
	# Latest scene wins even with three or more changes during one crossfade.
	for id in ['menu','camp','archive','battle','boss','camp']:
		music.play_track(id);await create_timer(.12).timeout
	await create_timer(3.0).timeout
	check(music.tracks[music.active]=='camp' and music.players.filter(func(p):return p.playing).size()==1,'Rapid scene changes settle on the latest track with one active voice')
	capturing=false
	if not recording.is_empty():
		var peak=0.0
		for frame in recording:peak=maxf(peak,maxf(absf(frame.x),absf(frame.y)))
		check(peak>.01 and peak<.9,'Captured game music is audible with mixing headroom')
		var pcm=PackedByteArray();pcm.resize(recording.size()*4)
		for i in recording.size():
			pcm.encode_s16(i*4,roundi(clampf(recording[i].x,-1,1)*32767))
			pcm.encode_s16(i*4+2,roundi(clampf(recording[i].y,-1,1)*32767))
		var wav=AudioStreamWAV.new();wav.format=AudioStreamWAV.FORMAT_16_BITS;wav.stereo=true;wav.mix_rate=int(AudioServer.get_mix_rate());wav.data=pcm
		wav.save_to_wav(OUT+'native-music-transitions.wav')
		print('Captured ',recording.size()/float(wav.mix_rate),' seconds; peak ',peak)
	else:check(false,'Native mixer returned audio samples')
	app.free();await process_frame
	AudioServer.remove_bus(bus)
	check(is_equal_approx(Store.read_settings(SETTINGS).music_volume,.45),'Saved music volume survives shutdown')
	print('%d music checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
