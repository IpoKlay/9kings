extends SceneTree
# Bake the existing card recordings into short, equally loud cues. Audio timing
# belongs in the samples, not frame-dependent volume tweens or delayed players.
const OUT = 'res://assets/cards/trimmed/'
const RECIPES = {
	'fan': [.16, 1, [['card-fan',1,0.0,.72]]],
	'deal': [.09, 1, [['card-slide',1,0.0,.55]]],
	'lift': [.105, 1, [['card-slide',1,0.0,.95]]],
	'pick': [.13, 1, [['card-shove',1,0.0,1.0]]]
}
func _init(): call_deferred('run')
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	var rate = int(AudioServer.get_mix_rate())
	var bank = {}
	var highest_crest = 0.0
	for gesture in RECIPES:
		var recipe = RECIPES[gesture]
		var levels = []
		for variant in recipe[1]:
			var frames = PackedVector2Array()
			frames.resize(int(rate*recipe[0]))
			for layer in recipe[2]:
				var file = 'res://assets/cards/%s-%s.ogg'%[layer[0],variant%layer[1]+1]
				var stream = load(file)
				var playback = stream.instantiate_playback()
				playback.start()
				var offset = int(layer[2]*rate)
				var decoded = playback.mix_audio(1.0,int(ceil(stream.get_length()*rate)))
				playback.stop()
				var source_peak = 0.0
				for frame in decoded: source_peak=maxf(source_peak,maxf(absf(frame.x),absf(frame.y)))
				var onset = 0
				for i in decoded.size():
					if maxf(absf(decoded[i].x),absf(decoded[i].y))>source_peak*.08:
						onset=maxi(0,i-int(rate*.002))
						break
				for i in mini(frames.size()-offset,decoded.size()-onset): frames[i+offset] += decoded[i+onset]*layer[3]
			var power = 0.0
			var peak = 0.0
			for i in frames.size():
				var fade = minf(1.0,float(frames.size()-1-i)/(rate*.018))
				frames[i] *= fade*minf(1.0,float(i)/(rate*.001))
				power += frames[i].length_squared()
				peak = maxf(peak,maxf(absf(frames[i].x),absf(frames[i].y)))
			var rms = sqrt(power/(frames.size()*2))
			assert(rms>0.00001,'Card cue is silent: '+gesture)
			levels.append(linear_to_db(rms))
			highest_crest = maxf(highest_crest,peak/rms)
			bank['%s-%s'%[gesture,variant+1]] = {'frames':frames,'rms':rms}
		print('%s source RMS range: %.1f to %.1f dB'%[gesture,levels.min(),levels.max()])
	# One target across the whole bank; no per-file peak clamp causing quiet variants.
	var target = minf(db_to_linear(-28.655),.70/highest_crest)
	for key in bank:
		var entry = bank[key]
		var gain = target/entry.rms
		var pcm = PackedByteArray()
		pcm.resize(entry.frames.size()*4)
		for i in entry.frames.size():
			pcm.encode_s16(i*4,roundi(entry.frames[i].x*gain*32767))
			pcm.encode_s16(i*4+2,roundi(entry.frames[i].y*gain*32767))
		var wav = AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.stereo = true
		wav.mix_rate = rate
		wav.data = pcm
		assert(wav.save_to_wav(OUT+key+'.wav')==OK)
	print('Prepared %s original-recording cues, matched RMS %.2f dB, peak <= -3.1 dB'%[bank.size(),linear_to_db(target)])
	quit()
