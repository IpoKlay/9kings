extends Node
## Two native players crossfade; saved playheads let a book/menu detour resume naturally.
const Catalog=preload('res://scripts/data/catalog.gd')
var preset: Dictionary=Catalog.presentation('audio').music
var streams={}
var players: Array[AudioStreamPlayer]=[]
var tracks: Array[String]=['','']
var levels=[0.0,0.0]
var fade_from=[0.0,0.0]
var positions={}
var requested_track=''
var active=-1
var fade_elapsed=0.0
var fade_duration=1.0
var volume=0.0
var target_volume=0.0
var duck=1.0
var target_duck=1.0

func _ready():
	for id in preset.tracks:
		var stream=load(preset.tracks[id].file)
		streams[id]=stream
	for i in 2:
		var player=AudioStreamPlayer.new()
		player.volume_linear=0
		add_child(player)
		players.append(player)

func set_volume(master: float,music: float):
	target_volume=clampf(master,0,1)*clampf(music,0,1)
	if target_volume==0:
		volume=0
		for player in players: player.volume_linear=0

func set_quiet(quiet: bool):
	target_duck=float(preset.quiet_gain) if quiet else 1.0

func play_track(id: String):
	if not streams.has(id) or requested_track==id: return
	requested_track=id
	try_switch()

func try_switch():
	if requested_track=='': return
	if active>=0 and tracks[active]==requested_track: return
	for i in 2:
		if tracks[i]==requested_track and players[i].playing:
			fade_to(i,float(preset.crossfade_seconds))
			return
	for i in 2:
		if levels[i]<=0:
			start_slot(i,requested_track,float(positions.get(requested_track,preset.tracks[requested_track].start)))
			fade_to(i,float(preset.crossfade_seconds))
			return
	# A third scene can arrive mid-fade: release the quieter deck before reusing it.
	fade_to(0 if levels[0]>=levels[1] else 1,float(preset.interrupt_seconds))

func start_slot(index: int,id: String,position: float):
	retire_slot(index)
	tracks[index]=id
	var track=preset.tracks[id]
	if position>=float(track.end)-float(preset.loop_crossfade_seconds): position=float(track.start)
	players[index].stream=streams[id]
	players[index].volume_linear=0
	players[index].play(maxf(float(track.start),position))

func fade_to(index: int,seconds: float):
	active=index
	fade_from=levels.duplicate()
	fade_elapsed=0
	fade_duration=seconds

func retire_slot(index: int):
	var id=tracks[index]
	if id!='' and tracks[1-index]!=id:
		positions[id]=players[index].get_playback_position()
	players[index].stop()
	players[index].stream=null
	tracks[index]=''
	levels[index]=0.0

func _process(delta: float):
	if active<0: return
	volume=lerpf(volume,target_volume,1.0-exp(-delta/float(preset.volume_smoothing_seconds)))
	duck=lerpf(duck,target_duck,1.0-exp(-delta/float(preset.duck_seconds)))
	fade_elapsed=minf(fade_duration,fade_elapsed+delta)
	var progress=fade_elapsed/fade_duration
	for i in 2:
		levels[i]=lerpf(float(fade_from[i]),1.0 if i==active else 0.0,progress)
		if tracks[i]!='':
			players[i].volume_linear=sin(float(levels[i])*PI*.5)*volume*duck*float(preset.tracks[tracks[i]].gain)
	if fade_elapsed<fade_duration: return
	var other=1-active
	if tracks[other]!='': retire_slot(other)
	if tracks[active]!=requested_track:
		try_switch()
		return
	var track=preset.tracks[requested_track]
	# Overlap the original musical ending and opening instead of hard-looping MP3 padding.
	if not players[active].playing or players[active].get_playback_position()>=float(track.end)-float(preset.loop_crossfade_seconds):
		start_slot(other,requested_track,float(track.start))
		fade_to(other,float(preset.loop_crossfade_seconds))

func _exit_tree():
	for player in players:
		player.stop()
		player.stream=null
	streams.clear()
