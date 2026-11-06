extends SceneTree
const Audio=preload('res://scripts/tactical/myth_audio.gd')
var failures=0
var cues=[]
func _initialize():call_deferred('run')
func check(ok: bool, message: String):
	if not ok:
		failures+=1
		push_error(message)
func run():
	var a=Audio.new();root.add_child(a)
	a.cue_played.connect(func(id,stage):cues.append(id+'_'+stage))
	check(a.clips.size()==28,'28 clips must preload')
	for id in a.config.characters:
		for stage in ['cast','impact']:
			check(a.clips[id+'_'+stage].get_length()>.1,id+' empty clip')
			a.stop_all();check(a.play_cue(id,stage),id+' did not play')
	a.stop_all()
	a.handle_event({'kind':'sea_wave','character':'poseidon'})
	a.advance(.5,false,true,.7)
	var remaining=a.pending[0].delay
	a.advance(5,true,true,.7)
	check(a.pending[0].delay==remaining,'Pause advanced delayed sea')
	check(a.voices[0].player.stream_paused,'Pause did not pause audio')
	a.advance(.7,false,true,.7)
	check(a.pending.is_empty() and cues.back()=='poseidon_impact','Sea impact missing')
	a.stop_all();cues.clear()
	for i in 30:
		a.handle_event({'kind':'sea_wave','character':'poseidon'})
		a.advance(.13,false,true,.7)
		check(a.pending.size()<=2,'Unbounded sea queue')
	check('poseidon_impact' in cues,'Spam starved sea impact')
	for id in a.config.characters:
		a.play_cue(id,'cast');a.play_cue(id,'impact')
	check(a.voices.filter(func(v):return v.remaining>0).size()<=6,'Voice cap')
	for id in a.config.characters:
		check(a.voices.filter(func(v):return v.remaining>0 and v.id==id).size()<=2,'Per-character cap')
	a.advance(.01,false,true,.25)
	for v in a.voices:
		check(is_equal_approx(v.player.volume_linear,.25*.6*v.gain),'Live volume did not update')
	a.advance(.01,false,false,.7)
	check(a.pending.is_empty() and a.voices.all(func(v):return v.remaining==0),'Mute leaked voices')
	check(not a.play_cue('zeus','impact'),'Muted cast played')
	a.advance(.01,false,true,.7)
	a.stop_all();cues.clear()
	a.handle_event({'kind':'power_contact','power':'achilles'})
	check(cues.is_empty(),'Charge launch incorrectly sounded as hit')
	a.handle_event({'kind':'power_impact','power':'achilles'})
	check(cues==['achilles_impact'],'Charge collision did not sound')
	var buses=AudioServer.bus_count
	a.queue_free();await process_frame
	a=Audio.new();root.add_child(a)
	check(AudioServer.bus_count==buses,'Reentry duplicated audio bus')
	a.queue_free();await process_frame
	await create_timer(.25).timeout
	print('MYTH AUDIO: ',failures,' failures — clips, timing, pause, mute, volume, spam, collision, reentry')
	quit(1 if failures else 0)
