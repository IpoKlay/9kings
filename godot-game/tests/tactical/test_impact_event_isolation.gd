extends SceneTree
## Exercise the real oil/myth producers through the native scene's effect/audio consumers.
const DT=1./60
var failures=0
var mounted_audio=[]
var myth_audio=[]
func _initialize():call_deferred('run')
func check(ok: bool,note: String):
	if not ok:failures+=1;push_error(note)
func isolated(t) -> bool:
	return t.field.effects.all(func(e):return not e.get('mounted_contact',false) and e.kind not in ['hoof_marks','wood_chips','rider_contact']) and mounted_audio.is_empty()
func run():
	var app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/tmp/eagle-impact-isolation.cfg'
	root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit()
	var t=app.active_trial;t.set_process(false)
	t.defender_button.pressed.emit()
	t.contact_audio_started.connect(func(contact):mounted_audio.append(contact))
	t.myth_audio.cue_played.connect(func(id,stage):myth_audio.append(id+'_'+stage))
	var r=t.rules;r.units.clear()
	var barrel=r.barrels[0]
	r.spawn('archer','ally',barrel.pos-Vector2(350,0))
	r.spawn('guard','enemy',barrel.pos)
	for u in r.units:u.order='hold'
	t.start_button.pressed.emit()
	check(r.ignite(barrel),'Archer lights oil through the ordinary oil API')
	var oil_hit=false;var oil_safe=true
	for frame in 60:
		t._process(DT)
		oil_hit=oil_hit or t.field.effects.any(func(e):return e.kind=='charge' and not e.has('attacker'))
		oil_safe=oil_safe and isolated(t)
	check(oil_hit and oil_safe and barrel.state=='burn','Oil charge produces fire and no cavalry breach or contact sound')
	for id in ['achilles','minotaur']:
		t.retry();r=t.rules;r.units.clear()
		r.spawn('guard','enemy',Vector2(1980,750))
		r.spawn('legion','ally',Vector2(1100,1100))
		for u in r.units:u.order='hold'
		check(r.select_deity(id),'Select '+id+' before battle')
		t.start_button.pressed.emit()
		myth_audio.clear();mounted_audio.clear()
		check(r.strike(r.units[0].pos),'Cast '+id+' through the ordinary skill API')
		var myth_hit=false;var myth_safe=true
		for frame in 180:
			t._process(DT)
			myth_hit=myth_hit or t.field.effects.any(func(e):return e.kind=='power_impact' and e.power==id)
			myth_safe=myth_safe and isolated(t)
		check(myth_hit and myth_safe,id+' actual collision does not produce mounted visuals or mounted audio')
		check(id+'_cast' in myth_audio and id+'_impact' in myth_audio,id+' retains its own cast and collision sounds')
		check(r.units.all(func(u):return not u.has('penetration') and not u.has('rider_contacts')),id+' does not create rider passage state')
	t.closed.emit();app.queue_free()
	await process_frame
	print('Impact event isolation failures: ',failures)
	quit(1 if failures else 0)
