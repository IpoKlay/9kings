extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
const DT=1./60
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture(label: String,angle: float=0.) -> Dictionary:
	var r=Battle.new();r.units.clear()
	var side=label=='side'
	var approach=(Vector2(-.94,-.342).normalized() if side else Vector2.UP).rotated(angle)
	var center=Vector2(1050,900)
	r.spawn('legion' if side else 'guard' if label=='shield' else 'spear','enemy',center)
	r.spawn('cavalry','ally',center-approach*800)
	var b=r.units[0];var a=r.units[1]
	b.heading=(Vector2.UP if side else Vector2.DOWN).rotated(angle);b.formation_heading=b.heading;b.order='hold'
	a.heading=approach;a.formation_heading=approach;a.order='hold'
	r.start();r.command([a.id],'attack',b.pos,b.id)
	return {'r':r,'a':a,'b':b}
func impact(f: Dictionary) -> Dictionary:
	for frame in 600:
		f.r.events.clear();f.r.step(DT)
		for e in f.r.events:
			if e.get('mounted_contact',false) and e.get('attacker',-1)==f.a.id:return e
	return {}
func run():
	var results=[]
	for label in ['side','shield','pikes']:
		for angle in [0.,PI/2]:
			var f=fixture(label,angle)
			var hit=impact(f)
			check(not hit.is_empty(),label+' achieves qualified impact after actual run')
			if hit.is_empty():continue
			var expected={'side':71.4,'shield':42.84,'pikes':17.}[label]
			check(absf(hit.damage-expected)<.001,label+' unchanged damage budget under rotation '+str(angle))
			check(hit.sector==('side' if label=='side' else 'front'),'Relative facing selects sector')
			var r=f.r;var a=f.a;var b=f.b
			var time: float=r.elapsed
			var hp: float=b.hp
			check(r.casualties.filter(func(body):return body.unit_id==b.id).is_empty(),'Full-health first strike does not invent visible deaths')
			var reaction_count=0
			for s in b.get('slot_states',{}).values():
				if s.get('reaction','') in ['charge','brace']:reaction_count+=1
			check(reaction_count>0 and reaction_count<5,'First impact stays local')
			for duplicate in 20:
				if hit.has('contact'):r.deal_blow(a,b,17.,hit.contact)
			check(is_equal_approx(hp,b.hp),'Duplicate contact cannot spend another damage budget')
			var repeats=0
			for frame in 120:
				r.events.clear();r.step(DT)
				for e in r.events:
					if e.get('mounted_contact',false) and e.get('attacker',-1)==a.id:repeats+=1
			check(repeats==0,'Continuous contact does not rearm charge')
			var shifts=[]
			for slot in r.contact_profiles[b.kind].feet.size():shifts.append(r.Contact.body_shift(b,slot,r.elapsed).length())
			var moved=shifts.filter(func(n):return n>4).size()
			var breach_slots=b.get('slot_states',{}).values().filter(func(s):return s.get('persistent',false) and s.get('reaction','')=='charge').size()
			if label=='side':check(breach_slots>0 and breach_slots<=5 and moved<10,'Two seconds later a local breach remains and distant files hold')
			check(a.has('slot_distances') and a.slot_distances.size()==8,'All eight riders track actual foot travel')
			results.append({'case':label,'angle':angle,'time':time,'damage':hit.damage,'morale':b.morale,'moved_after_2s':moved,'breach_slots':breach_slots,'rider_contacts':a.get('rider_contacts',{}).size()})
	# Hold a displaced soldier away while a real living horse occupies the return lane.
	var f=fixture('side');var e=impact(f)
	if not e.is_empty():
		var r=f.r;var a=f.a;var b=f.b
		var slot=-1
		for key in b.get('slot_states',{}):
			if b.slot_states[key].get('reaction','')=='charge':slot=key;break
		check(slot>=0,'Persistent breach state available')
		if slot>=0:
			r.elapsed+=3.
			a.erase('slot_states');a.erase('contact_motion')
			var home: Vector2=r.projection*b.pos+r.Contact.feet(r,b)[slot]
			a.pos=r.projection.affine_inverse()*(home-r.Contact.feet(r,a)[3])
			r.Contact.advance_recovery(r,b,DT)
			check(not b.slot_states[slot].get('returning',false),'Living horse blocks return to original slot')
			a.hp=0
			r.elapsed+=.1
			r.Contact.advance_recovery(r,b,DT)
			check(b.slot_states[slot].get('returning',false),'Clear return lane permits actual recovery')
			for frame in 120:r.elapsed+=DT;r.Contact.advance_recovery(r,b,DT)
			check(r.Contact.body_shift(b,slot,r.elapsed).length()<.01,'Unblocked soldier eventually reaches home')
	# Bodies follow real visible losses, never the number of particles or overlaps.
	var losses=fixture('side');var lr=losses.r;var victim=losses.b
	lr.step(DT)
	lr.hurt(victim,200.)
	lr.step(DT)
	check(lr.casualties.size()==2,'Two actual visible casualties create two bodies')
	var corpse: Dictionary=lr.casualties[0].duplicate(true)
	lr.step(DT)
	check(lr.casualties.size()==2,'Repeated frames do not duplicate bodies')
	var old_pos: Vector2=corpse.foot
	victim.pos+=Vector2(120,0)
	lr.step(DT)
	check(lr.casualties[0].foot==old_pos,'Corpse stays on the ground when survivors move')
	lr.elapsed=corpse.time+8.
	lr.collect_casualties()
	check(lr.casualties.size()==2,'Ground evidence persists at eight seconds')
	lr.elapsed=corpse.time+12.1
	lr.collect_casualties()
	check(lr.casualties.is_empty(),'Old ground evidence clears after twelve seconds')
	# Damage arriving between steps must retain the displaced figure's last ground location.
	var displaced=fixture('side');var dr=displaced.r;var db=displaced.b
	dr.step(DT)
	dr.Contact.set_slot(dr,db,9,Vector2(0,30),.12,2.6,.56)
	db.slot_states[9].merge({'persistent':true,'release_at':dr.elapsed+2.6,'returning':false})
	for frame in 12:dr.step(DT)
	var expected_foot: Vector2=dr.projection*db.pos+dr.Contact.feet(dr,db)[9]+dr.Contact.body_shift(db,9,dr.elapsed)
	dr.hurt(db,100.)
	dr.step(DT)
	var fallen=dr.casualties.filter(func(body):return body.unit_id==db.id and body.slot==9)
	check(fallen.size()==1 and fallen[0].foot.distance_to(expected_foot)<.01,'Between-step death preserves displaced ground contact')
	# A damage tick inside step() also occurs before recovery prunes missing slots.
	var poisoned=fixture('side');var pr=poisoned.r;var pb=poisoned.b
	pb.hp=pb.max_hp*.9+.01
	pr.Contact.set_slot(pr,pb,9,Vector2(0,30),.12,2.6,.56)
	pb.slot_states[9].merge({'persistent':true,'release_at':pr.elapsed+2.6,'returning':false})
	for frame in 12:pr.step(DT)
	var poisoned_foot: Vector2=pr.projection*pb.pos+pr.Contact.feet(pr,pb)[9]+pr.Contact.body_shift(pb,9,pr.elapsed)
	pb.poison=1.
	pr.step(DT)
	var poison_body=pr.casualties.filter(func(body):return body.unit_id==pb.id and body.slot==9)
	check(poison_body.size()==1 and poison_body[0].foot.distance_to(poisoned_foot)<.01,'In-step poison death preserves displaced ground contact')
	# Turning must advance feet/stride even while regiment centre is stationary.
	var turn=fixture('side');var rr=turn.r;var rider=turn.a
	rr.Contact.track_slots(rr,rider,DT)
	var before: float=rider.slot_distances[0]
	rider.heading=rider.heading.rotated(PI/2)
	for frame in 30:rr.Contact.turn(rr,rider,DT);rr.Contact.track_slots(rr,rider,DT)
	check(rider.slot_distances[0]>before+20,'Turning outer horse accumulates actual travel')
	print('IMPACT MATRIX ',JSON.stringify(results))
	print('Impact upgrade: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
