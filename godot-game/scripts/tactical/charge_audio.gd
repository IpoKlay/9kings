extends RefCounted
## Collect only the current render frame. Rejected hits are discarded, never queued.
const PRIORITY={'main':3,'landing':2,'melee':1,'hoof':0}
var pending: Dictionary={}
var last: Dictionary={}
var last_main=-100.

func clear():
	pending.clear();last.clear();last_main=-100.

func request(layer: String,sample: String,point: Vector2,gain: float) -> bool:
	var bus='hoof' if layer=='hoof' else 'collision'
	var cue={'layer':layer,'sample':sample,'pos':point,'gain':gain,'bus':bus,'priority':PRIORITY[layer]}
	var previous: Dictionary=pending.get(bus,{})
	if not previous.is_empty() and (previous.priority>cue.priority or previous.priority==cue.priority and previous.gain>=gain):return false
	pending[bus]=cue
	return true

func drain(now: float) -> Array:
	var result: Array=[]
	# Resolve the collision first so hooves can duck on this very frame.
	for bus in ['collision','hoof']:
		if not pending.has(bus):continue
		var cue: Dictionary=pending[bus]
		var old: Dictionary=last.get(bus,{'time':-100.,'priority':-1})
		var interval=.12 if cue.layer=='main' else .14 if bus=='collision' else .10
		if now-old.time<interval and cue.priority<=old.priority:continue
		if cue.layer in ['landing','melee'] and now-last_main<.20:continue
		if cue.layer=='main':
			cue.sample='charge_hit'+str(int(cue.sample.trim_prefix('impact'))%3)
			last_main=now
		elif cue.layer=='landing':cue.sample='charge_land';cue.gain*=.65
		elif cue.layer=='melee':cue.sample='charge_hit0';cue.gain*=.7
		elif now-last_main<.20:cue.gain*=.45
		last[bus]={'time':now,'priority':cue.priority}
		result.append(cue)
	pending.clear()
	return result
