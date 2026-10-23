extends Node
## Reuses the original edited recordings. A bounded voice pool prevents noisy overlap.
var enabled = true
var volume = .7
var voices = .55
var pool: Array[AudioStreamPlayer] = []
var cache = {}
var last = {}
var rotation = {}
var clock = 0.0
var last_paper = -10.0
var card_player: AudioStreamPlayer
# One fixed recording per action; repeated hover must always sound identical.
const CARD_VARIANTS = {'fan':1,'deal':1,'lift':1,'pick':1}
var card_files = {'card_fan':['card-fan',2], 'card_deal':['card-slide',8], 'card_lift':['card-slide',8], 'card_flex':['cards-pack-take-out',2], 'card_return':['card-place',4], 'card_pick':['card-shove',4], 'card_settle':['card-place',4]}
var variants = {'sword':3,'swing':3,'impact':3,'shield':3,'kill':3,'foot':3,'cry':2}
var gains = {'sword':.82,'swing':.27,'impact':.6,'shield':.82,'kill':1.0,'arrow':.62,'foot':.28,'cry':.7,'horn':.75,'break':.95,'hover':.55,'click':.65,'select':.82,'upgrade':.85,'build':.9,'win':.8,'bad':.8}
var gaps = {'sword':.09,'swing':.10,'impact':.09,'shield':.1,'kill':.12,'foot':.19,'cry':2.5,'arrow':.12,'hover':.08}
func _ready():
	card_player = AudioStreamPlayer.new()
	card_player.max_polyphony = 1
	add_child(card_player)
	# Preload the short normalized samples so first hover doesn't decode on demand.
	for gesture in CARD_VARIANTS:
		for i in CARD_VARIANTS[gesture]:
			var key = '%s-%s'%[gesture,i+1]
			cache[key] = load('res://assets/cards/trimmed/'+key+'.wav')
	for i in 12:
		var p = AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)
	var limiter = AudioEffectLimiter.new()
	AudioServer.add_bus_effect(0,limiter)
func _process(delta): clock += delta
func play(kind: String, strength: float = 1.0):
	if DisplayServer.get_name()=='headless': return
	if not enabled or volume<=0 or clock-last.get(kind,-10.0)<gaps.get(kind,.045): return
	var player = null
	for p in pool:
		if not p.playing:
			player = p
			break
	if player == null:
		if kind not in ['kill','break','cry']: return
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
	player.volume_db = linear_to_db(maxf(.0001,volume*gains.get(kind,.7)*strength*(voices if kind=='cry' else 1)))
	player.pitch_scale = randf_range(.97,1.03) if kind in ['sword','swing','impact','shield','foot'] else 1.0
	player.play()

func stop():
	if is_instance_valid(card_player): card_player.stop()
	last_paper = -10.0
	for p in pool: p.stop()
	last.clear()

func _exit_tree():
	stop()
	if is_instance_valid(card_player): card_player.stream = null
	for p in pool: p.stream = null
	cache.clear()

func play_card(gesture: String):
	if not enabled or volume<=0 or not CARD_VARIANTS.has(gesture): return
	if gesture=='lift' and clock-last_paper<.075: return
	last_paper=clock
	card_player.stop()
	card_player.stream = cache[gesture+'-1']
	card_player.volume_db = linear_to_db(maxf(.0001,volume*.9))
	card_player.pitch_scale = 1.0
	if DisplayServer.get_name()!='headless': card_player.play()
