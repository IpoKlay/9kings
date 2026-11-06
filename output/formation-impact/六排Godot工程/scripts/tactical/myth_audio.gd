extends Node
signal cue_played(character: String, stage: String)
const BUS='EagleMythFX'
var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://data/presentation/myth_audio.json'))
var clips: Dictionary={}
var voices: Array=[]
var pending: Array=[]
var last: Dictionary={}
var clock=0.0
var enabled=true
var paused=false
var master_volume=.7

func _ready():
	if AudioServer.get_bus_index(BUS)<0:
		AudioServer.add_bus()
		var index=AudioServer.bus_count-1
		AudioServer.set_bus_name(index,BUS)
		AudioServer.set_bus_send(index,'Master')
		var limiter=AudioEffectLimiter.new()
		limiter.ceiling_db=-1.0
		AudioServer.add_bus_effect(index,limiter)
	for id in config.characters:
		for stage in ['cast','impact']:
			clips[id+'_'+stage]=load(config.characters[id][stage].file)
	for i in int(config.voice_limit):
		var player=AudioStreamPlayer.new()
		player.bus=BUS
		player.max_polyphony=1
		add_child(player)
		voices.append({'player':player,'id':'','stage':'','started':-1.0,'gain':1.0,'remaining':0.0})

func advance(dt: float, is_paused: bool, sound_enabled: bool, volume: float):
	paused=is_paused
	master_volume=clampf(volume,0,1)
	var active=sound_enabled and master_volume>0
	if not active and enabled:stop_all()
	enabled=active
	for voice in voices:
		voice.player.stream_paused=paused
		voice.player.volume_linear=master_volume*float(config.mix_gain)*float(voice.gain)
	if paused or not enabled:return
	clock+=dt
	for voice in voices:
		voice.remaining=maxf(0,voice.remaining-dt)
		if voice.remaining==0:voice.player.stop()
	var ready: Array=[]
	for cue in pending:
		cue.delay-=dt
		if cue.delay<=0:ready.append(cue)
	for cue in ready:
		pending.erase(cue)
		play_cue(cue.id,'impact')

func play_cue(id: String, stage: String) -> bool:
	if not enabled or paused or not config.characters.has(id) or stage not in ['cast','impact']:return false
	var key=id+'_'+stage
	if clock-float(last.get(key,-10))<float(config.min_gap):return false
	var same=voices.filter(func(v):return v.remaining>0 and v.id==id)
	var chosen: Dictionary={}
	if same.size()>=int(config.per_character_limit):
		same.sort_custom(func(a,b):return a.started<b.started)
		chosen=same[0]
	else:
		for voice in voices:
			if voice.remaining==0:
				chosen=voice
				break
	if chosen.is_empty():
		chosen=voices[0]
		for voice in voices:
			if voice.started<chosen.started:chosen=voice
	var player: AudioStreamPlayer=chosen.player
	player.stop()
	player.stream=clips[key]
	chosen.id=id
	chosen.stage=stage
	chosen.started=clock
	chosen.gain=float(config.characters[id][stage].gain)
	chosen.remaining=player.stream.get_length()
	player.pitch_scale=1.0
	player.volume_linear=master_volume*float(config.mix_gain)*float(chosen.gain)
	player.stream_paused=false
	player.play()
	last[key]=clock
	cue_played.emit(id,stage)
	return true

func handle_event(event: Dictionary) -> bool:
	if event.kind in ['lightning','sea_wave','myth_cast']:
		var id: String=event.character
		var played=play_cue(id,'cast')
		if event.kind=='lightning':play_cue(id,'impact')
		elif event.kind=='sea_wave' and played:
			# Keep the earliest surge audible even when the test button is spammed.
			if pending.size()<2:
				pending.append({'id':id,'delay':float(config.characters[id].impact_delay)})
		return true
	if event.kind=='power_contact':
		# Charging attacks get their impact cue from first actual contact, not the launch.
		if event.power not in ['achilles','minotaur']:play_cue(event.power,'impact')
		return true
	if event.kind=='power_impact':
		play_cue(event.power,'impact')
		return true
	return false

func stop_all():
	for voice in voices:
		voice.player.stop()
		voice.remaining=0.0
	pending.clear()
	last.clear()
	clock=0.0

func _exit_tree():
	stop_all()
