extends SceneTree
const DT=1./60
var failures=0
func _initialize():call_deferred('run')
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)

func run():
	var main=load('res://scenes/main.tscn').instantiate()
	main.settings_path='/tmp/eagle-impact-test.cfg'
	root.add_child(main)
	main.menu_view.get_node('TacticalTrial').pressed.emit()
	var t=main.active_trial
	t.set_process(false)
	var r=t.rules
	r.units.clear()
	var goal=Vector2(1980,750)
	r.spawn('guard','enemy',goal)
	r.spawn('cavalry','ally',goal+Vector2(250,530))
	var wall=r.units[0]
	var horse=r.units[1]
	wall.heading=Vector2.LEFT
	wall.order='hold'
	r.select_deity('minotaur')
	t.refresh()
	t.start_button.pressed.emit()
	r.command([horse.id],'attack',goal,wall.id)
	for tick in 350:
		t._process(DT)
		if horse.gait=='impact':break
	check(t.field.effects.any(func(e):return e.get('mounted_contact',false) and e.sector=='side'),'Mounted cue from flank contact')
	check(horse.has('follow_goal'),'Moving cavalry continues past first contact')
	for i in 12:t._process(DT)
	var time: float=r.elapsed
	var pos: Vector2=horse.pos
	var feet=r.Contact.body_shift(wall,wall.contact_motion.offsets.keys()[0],time)
	t.paused=true
	for i in 30:t._process(DT)
	check(time==r.elapsed and pos==horse.pos and feet==r.Contact.body_shift(wall,wall.contact_motion.offsets.keys()[0],r.elapsed),'Pause freezes ranks and follow-through')
	t.paused=false
	t.slow=true
	for i in 30:t._process(DT)
	check(absf(r.elapsed-time-.25)<.001 and pos!=horse.pos,'Half speed advances 15 battle ticks')
	var count=r.Contact.count(wall,r.config.types.guard)
	var displaced=0
	for slot in 60:
		if r.Contact.present(wall,slot,count) and r.Contact.body_shift(wall,slot,r.elapsed).length()>4:displaced+=1
	check(displaced>=4 and displaced<count/2,'Only the contacted files part')
	var width: float=t.field.regiment_bounds(wall).size.x/1920.
	check(width>.14 and width<.17 and width*5./3>.24 and width*5./3<.27,'Infantry footprint at default and closest zoom')
	for stats in r.config.types.values():check(int(stats.files)>0,'Seven valid formations')
	check(r.config.types.guard.files==10 and r.config.types.guard.soldiers==60,'Full guard block is 10 by 6')
	t.field.effects.clear()
	# Real oil ignition and real myth collision use their own producers.
	r.barrels[0].state='arrow'
	r.barrels[0].age=.4
	t._process(2*DT)
	check(t.field.effects.any(func(e):return e.kind=='charge' and not e.has('attacker')),'Oil explosion still resolves')
	check(t.field.effects.all(func(e):return not e.get('mounted_contact',false) and e.kind!='hoof_marks'),'Oil cannot make a mounted breach')
	var before=wall.contact_motion.start
	check(r.strike(wall.pos),'Cast minotaur through the normal skill API')
	var myth_hit=false
	for tick in 100:
		t._process(2*DT)
		if t.field.effects.any(func(e):return e.kind=='power_impact' and e.power=='minotaur'):
			myth_hit=true
			break
	check(myth_hit,'Myth wave reached a living enemy')
	check(wall.contact_motion.start==before and t.field.effects.all(func(e):return e.kind!='hoof_marks'),'Myth impact cannot make a mounted breach')
	for kind in r.config.types:
		var atlas: Texture2D=t.field.regiments[kind].ally
		check(atlas.get_height()==8*64 and atlas.get_width()%64==0,'Original eight-direction sheet '+kind)
	t.closed.emit()
	main.queue_free()
	await process_frame
	print('Regiment contact failures: ',failures)
	quit(1 if failures else 0)
