extends SceneTree
const Audio=preload('res://scripts/tactical/charge_audio.gd')
const Visuals=preload('res://scripts/tactical/charge_visuals.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func run():
	var audio=Audio.new()
	for i in 64:
		audio.request('landing','impact0',Vector2(i,0),.42)
		audio.request('main','impact1',Vector2(i,0),.94)
		audio.request('melee','impact0',Vector2(i,0),.42)
	var batch=audio.drain(1.)
	check(batch.size()==1 and batch[0].layer=='main' and batch[0].sample=='charge_hit1','A dense same-frame collision plays one short priority hit')
	check(audio.pending.is_empty() and audio.drain(2.).is_empty(),'No backlog survives into a later frame')
	audio.request('main','impact1',Vector2.ZERO,.94)
	check(audio.drain(1.03).is_empty(),'Immediate repeated collision is discarded')
	check(audio.drain(1.3).is_empty(),'Rejected collision cannot become delayed sound')
	audio.request('landing','impact0',Vector2.ZERO,.42)
	check(audio.drain(1.1).is_empty(),'Landing cannot cover the primary impact')
	audio.request('landing','impact0',Vector2.ZERO,.42)
	batch=audio.drain(1.46)
	check(batch.size()==1 and batch[0].sample=='charge_land','Actual landing uses a dull short thud instead of a second metal clash')
	audio.request('main','impact2',Vector2.ZERO,.94)
	audio.request('hoof','foot0',Vector2.ZERO,.3)
	batch=audio.drain(1.47)
	check(batch.size()==2 and batch[0].layer=='main' and batch[1].gain<.15,'Fresh charge preempts landing and ducks hoof layer')
	audio.clear();var hits=[]
	for frame in 120:
		for i in 24:audio.request('main','impact1',Vector2.ZERO,.94)
		if not audio.drain(float(frame)/60.).is_empty():hits.append(float(frame)/60.)
	check(hits.size()<=17,'Continuous crowd impacts obey the shared rate budget')
	check(audio.drain(2.5).is_empty(),'Silence follows the last physical request without delayed replay')
	audio.request('main','impact0',Vector2.ZERO,.94);audio.clear()
	check(audio.drain(0.).is_empty() and audio.last.is_empty(),'Retry clears both pending requests and rate-limit history')
	for name in ['charge-hit-0','charge-hit-1','charge-hit-2','charge-land']:
		var clip: AudioStream=load('res://assets/combat_audio/charge/'+name+'.wav')
		check(clip.get_length()<=.201,'Bounded sample tail: '+name)
	var fx=Visuals.new()
	fx.emit_impact(Vector2(100,100),Vector2.RIGHT)
	check(fx.puffs.size()==2 and fx.chips.size()==6,'One collision creates a compact two-cloud and six-fragment burst')
	for i in 50:fx.emit_impact(Vector2(100,100),Vector2.RIGHT)
	check(fx.chips.size()==6,'Nearby simultaneous contacts merge their particle burst')
	var fake={'units':[],'casualties':[],'projection':Transform2D.IDENTITY}
	var old=fx.chips.duplicate(true);fx.advance(fake,0.)
	check(fx.chips==old,'Pause freezes particles')
	for i in 40:fx.emit_impact(Vector2(i*40,300),Vector2.RIGHT)
	check(fx.chips.size()==Visuals.MAX_CHIPS and fx.puffs.size()<=Visuals.MAX_PUFFS,'Dense impacts stay within fixed particle budgets')
	fx.advance(fake,.8)
	check(fx.puffs.is_empty() and fx.chips.is_empty() and fx.burst_cells.is_empty(),'All transient particles and coalescing cells expire')
	fx.emit_impact(Vector2.ZERO,Vector2.RIGHT);fx.clear()
	check(fx.chips.is_empty() and fx.puffs.is_empty(),'Retry removes every transient particle')
	print('Charge audio and particles: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
