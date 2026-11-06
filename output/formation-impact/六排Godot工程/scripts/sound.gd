extends Node
const Catalog=preload('res://scripts/data/catalog.gd')
var preset: Dictionary=Catalog.presentation('audio')
## Reuses the original edited recordings. A bounded voice pool prevents noisy overlap.
var enabled = Catalog.data('defaults/settings').enabled
var volume = Catalog.data('defaults/settings').volume
var voices = Catalog.data('defaults/settings').voices
var pool: Array[AudioStreamPlayer] = []
var cache = {}
var last = {}
var rotation = {}
var clock = 0.0
var last_paper = -10.0
var card_player: AudioStreamPlayer
var menu_player: AudioStreamPlayer
var page_player: AudioStreamPlayer
var map_paper_player: AudioStreamPlayer
var map_pin_player: AudioStreamPlayer
var ambience_players = {}
var ambience_levels = {}
var ambience_target = ''
var ambience_quiet = false
# One fixed recording per action; repeated hover must always sound identical.
var CARD_VARIANTS = preset.card_variants
var card_files = preset.card_files
var variants = preset.variants
var gains = preset.gains
var gaps = preset.gaps
func _ready():
	menu_player = AudioStreamPlayer.new()
	menu_player.stream = load(preset.menu_move.file)
	menu_player.max_polyphony = 1
	add_child(menu_player)
	page_player = AudioStreamPlayer.new()
	page_player.stream = load(preset.page_turn.file)
	page_player.max_polyphony = 1
	add_child(page_player)
	map_paper_player=AudioStreamPlayer.new()
	map_paper_player.stream=load(preset.map_paper.file)
	map_paper_player.max_polyphony=1
	add_child(map_paper_player)
	map_pin_player=AudioStreamPlayer.new()
	map_pin_player.stream=load(preset.map_pin.file)
	map_pin_player.max_polyphony=4
	add_child(map_pin_player)
	card_player = AudioStreamPlayer.new()
	card_player.max_polyphony = 1
	add_child(card_player)
	# Preload the short normalized samples so first hover doesn't decode on demand.
	for gesture in CARD_VARIANTS:
		for i in CARD_VARIANTS[gesture]:
			var key = '%s-%s'%[gesture,i+1]
			cache[key] = load('res://assets/cards/trimmed/'+key+'.wav')
	for kind in preset.effect_files:
		for i in preset.effect_files[kind].size():
			cache[kind+str(i)] = load(preset.effect_files[kind][i])
	for id in preset.ambience.tracks:
		var p = AudioStreamPlayer.new()
		var stream = load(preset.ambience.tracks[id].file).duplicate() as AudioStreamWAV
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = roundi(stream.get_length()*stream.mix_rate)
		p.stream = stream
		p.volume_linear = 0
		add_child(p)
		ambience_players[id] = p
		ambience_levels[id] = 0.0
	for i in int(preset.voice_pool_size):
		var p = AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)
	var limiter = AudioEffectLimiter.new()
	AudioServer.add_bus_effect(0,limiter)
func set_ambience(id: String, quiet: bool = false):
	ambience_target = id
	ambience_quiet = quiet

func _process(delta):
	clock += delta
	for id in ambience_players:
		var p: AudioStreamPlayer = ambience_players[id]
		var target = 1.0 if id==ambience_target and enabled and volume>0 else 0.0
		if ambience_quiet: target *= float(preset.ambience.quiet_gain)
		ambience_levels[id] = move_toward(float(ambience_levels[id]),target,delta/float(preset.ambience.fade_seconds))
		if not enabled or volume<=0: ambience_levels[id] = 0.0
		p.volume_linear = float(ambience_levels[id])*volume*float(preset.ambience.tracks[id].gain)
		if ambience_levels[id]<=0:
			p.stop()
		elif not p.playing and DisplayServer.get_name()!='headless':
			p.play()
func play(kind: String, strength: float = 1.0):
	if DisplayServer.get_name()=='headless': return
	if not enabled or volume<=0 or clock-last.get(kind,-10.0)<gaps.get(kind,preset.default_gap): return
	var player = null
	for p in pool:
		if not p.playing:
			player = p
			break
	if player == null:
		if kind not in preset.priority_kinds: return
		player = pool[0]
		player.stop()
	var index = (rotation.get(kind,-1)+1)%variants.get(kind,1)
	var key = kind+str(index)
	if not cache.has(key):
		var file = 'res://assets/'+key+'.wav'
		if not ResourceLoader.exists(file): return
		cache[key] = load(file)
	rotation[kind] = index
	last[kind] = clock
	player.stream = cache[key]
	player.volume_db = linear_to_db(maxf(.0001,volume*gains.get(kind,preset.default_gain)*strength*(voices if kind=='cry' else 1)))
	player.pitch_scale = randf_range(preset.pitch_range[0],preset.pitch_range[1]) if kind in preset.pitch_kinds else 1.0
	player.play()

func play_rally():
	# A confirmed departure gets one call, even after skipping the previous journey.
	# Retire its old tail rather than stacking horns over a rapid port visit.
	for p in pool:
		if p.playing and p.stream in [cache.get('horn0'),cache.get('cry0'),cache.get('cry1')]: p.stop()
	for kind in ['horn','cry','equip']: last.erase(kind)
	play('horn',.65)
	play('cry')
	play('equip',.7)

func stop():
	stop_map_entry()
	if is_instance_valid(menu_player): menu_player.stop()
	stop_page_turn()
	if is_instance_valid(card_player): card_player.stop()
	last_paper = -10.0
	for p in pool: p.stop()
	for id in ambience_players:
		ambience_players[id].stop()
		ambience_players[id].volume_linear = 0
		ambience_levels[id] = 0.0
	last.clear()

func _exit_tree():
	stop()
	if is_instance_valid(menu_player): menu_player.stream = null
	if is_instance_valid(page_player): page_player.stream = null
	if is_instance_valid(map_paper_player): map_paper_player.stream=null
	if is_instance_valid(map_pin_player): map_pin_player.stream=null
	if is_instance_valid(card_player): card_player.stream = null
	for p in pool: p.stream = null
	for p in ambience_players.values(): p.stream = null
	cache.clear()

func play_menu_move():
	if not enabled or volume<=0: return
	# One original clip per selection change; rapid navigation restarts its tail.
	menu_player.stop()
	menu_player.volume_db = linear_to_db(maxf(.0001,volume*preset.menu_move.gain))
	menu_player.pitch_scale = 1.0
	if DisplayServer.get_name()!='headless': menu_player.play()

func stop_page_turn():
	if is_instance_valid(page_player): page_player.stop()

func play_page_turn():
	if not enabled or volume<=0: return
	page_player.stop()
	page_player.volume_db = linear_to_db(maxf(.0001,volume*preset.page_turn.gain))
	page_player.pitch_scale = 1.0 # The supplied recording is already rendered at 1.2x.
	if DisplayServer.get_name()!='headless': page_player.play()

func stop_map_entry():
	if is_instance_valid(map_paper_player):map_paper_player.stop()
	if is_instance_valid(map_pin_player):map_pin_player.stop()

func play_map_paper():
	map_paper_player.stop()
	if not enabled or volume<=0:return
	map_paper_player.volume_linear=volume*preset.map_paper.gain
	if DisplayServer.get_name()!='headless':map_paper_player.play()

func play_map_pin():
	if not enabled or volume<=0:return
	map_pin_player.volume_linear=volume*preset.map_pin.gain
	if DisplayServer.get_name()!='headless':map_pin_player.play()

func play_card(gesture: String):
	if not enabled or volume<=0 or not CARD_VARIANTS.has(gesture): return
	if gesture=='lift' and clock-last_paper<preset.card_lift_gap: return
	last_paper=clock
	card_player.stop()
	card_player.stream = cache[gesture+'-1']
	card_player.volume_db = linear_to_db(maxf(.0001,volume*preset.card_gain))
	card_player.pitch_scale = 1.0
	if DisplayServer.get_name()!='headless': card_player.play()
