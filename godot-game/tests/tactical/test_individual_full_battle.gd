extends SceneTree
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func digest(r) -> Dictionary:
	var soldiers=[]
	for u in r.units:
		var actors=[]
		for s in u.soldiers:actors.append([snappedf(s.hp,.001),snappedf(s.cooldown,.001)])
		soldiers.append({'id':u.id,'pos':[snappedf(u.pos.x,.001),snappedf(u.pos.y,.001)],'actors':actors,'routing':u.routing})
	return {'time':snappedf(r.elapsed,.001),'phase':r.phase,'soldiers':soldiers}
func run():
	var app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/tmp/eagle-full-individual.cfg'
	root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit()
	var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	var baseline={}
	var results=[]
	for fps in [30,60,120]:
		t.retry();t.combined_button.pressed.emit();t.start_button.pressed.emit()
		var r=t.rules
		check(r.units.size()==14 and r.phase=='battle','Main-menu battle begins with both seven-arm armies')
		r.command(r.alive('ally').map(func(u):return u.id),'auto',Vector2.ZERO)
		t.paused=true
		var frozen=digest(r)
		t._process(1./fps)
		check(digest(r)==frozen,'Pause freezes all individual states')
		t.paused=false;t.slow=true
		for frame in fps*2:t._process(1./fps)
		check(is_equal_approx(r.elapsed,1.),'Half speed advances one simulated second in two seconds')
		t.slow=false
		var timings=[]
		var saw_arrow=false
		var saw_stone=false
		var saw_contact=false
		for frame in fps*179:
			var begin=Time.get_ticks_usec()
			t._process(1./fps)
			timings.append(Time.get_ticks_usec()-begin)
			saw_arrow=saw_arrow or not r.volleys.is_empty()
			saw_stone=saw_stone or not r.stones.is_empty()
			saw_contact=saw_contact or t.field.effects.any(func(e):return e.get('damage',0.)>0 and r.units.any(func(u):return u.kind=='cavalry' and u.id==e.get('attacker',-1)))
			if r.phase!='battle':break
		check(r.phase in ['victory','defeat'],'Unmodified seven-arm battle naturally reaches a result')
		check(saw_arrow and saw_stone and saw_contact,'Full battle includes arrows, stone shots and actual cavalry melee; automatic light cavalry no longer award legacy charge damage')
		var state=digest(r)
		if baseline.is_empty():baseline=state
		else:check(state==baseline,'Same input and simulation produce identical results at '+str(fps)+' render FPS')
		timings.sort()
		var mean=0.
		for value in timings:mean+=value
		var row={'fps':fps,'phase':r.phase,'seconds':r.elapsed,'mean_process_ms':mean/timings.size()/1000.,'p95_process_ms':timings[int(timings.size()*.95)]/1000.,'alive':{'ally':r.strength('ally'),'enemy':r.strength('enemy')}}
		results.append(row);print('FULL BATTLE ',JSON.stringify(row))
		t.start_button.pressed.emit()
		check(t.rules.phase=='deploy' and t.rules.units.size()==7,'Result button creates a clean deployment')
		check(t.rules.casualties.is_empty() and t.rules.volleys.is_empty() and t.rules.stones.is_empty() and t.field.effects.is_empty(),'Retry clears all bodies, projectiles and effects')
		check(t.rules.units.all(func(u):return u.soldiers.all(func(s):return s.hp==s.max_hp and s.cooldown==0.)),'Retry resets every soldier')
	FileAccess.open('res://../output/sword-banner-reference/individual-full-battle.json',FileAccess.WRITE).store_string(JSON.stringify({'checks':checks,'failures':failures,'results':results,'timing_scope':'Headless full trial _process, including UI refresh; excludes GPU rendering. FPS runs perform different simulation steps per frame.'},'\t'))
	t.closed.emit();app.queue_free();await process_frame
	print('Individual full battle: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
