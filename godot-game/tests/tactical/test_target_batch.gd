extends SceneTree
const Trial=preload('res://scripts/tactical/trial_rules.gd')
const Square=preload('res://scripts/tactical/square_battle.gd')
const Pass=preload('res://scripts/tactical/pass_battle.gd')
const Original=preload('res://scripts/tactical/myth_powers.gd')
var checks=0
var failures=0
var cases=[]
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func same(r,u: Dictionary,label: String):
	# Both selectors are pure. Compare BEFORE performing the next mutation once.
	var fast: Dictionary=r.powers.select_target(r,u)
	var original=Original.new();original.config=r.powers.config;original.decoys=r.powers.decoys
	var slow: Dictionary=original._select_target_live(r,u)
	check((fast.is_empty() and slow.is_empty()) or is_same(fast,slow),label)
	cases.append(label)
	return fast
func fixture(script):
	var r=script.new();r.units.clear();r.next_id=0
	r.spawn('legion','ally',Vector2(900,1000))
	r.spawn('legion','enemy',Vector2(1000,1000))
	r.spawn('archer','enemy',Vector2(800,1000))
	r.phase='battle';r.targeting_random.seed=9183;r.volley_random.seed=9183
	return r
func _initialize():call_deferred('run')
func run():
	for script in [Trial,Square,Pass]:
		var r=fixture(script);var u=r.units[0];var a=r.units[1];var b=r.units[2]
		r.powers.begin_target_batch()
		check(is_same(same(r,u,'normal/tie'),a),'first input wins tie')
		for i in 10:same(r,u,'same regiment actor '+str(i))
		u.kind='cavalry';check(is_same(same(r,u,'cavalry archer preference'),b),'cavalry scores archers first')
		u.kind='archer';r.powers.resolve(r,{'character':'artemis','pos':a.pos});same(r,u,'marked power invalidation')
		u.kind='legion';u.order='hold';same(r,u,'hold live reach')
		for actor in a.soldiers:actor.position=u.pos+Vector2(1,0)
		same(r,u,'hold individual position changed without center change')
		u.order='auto';same(r,u,'source order change')
		r.hurt(a,a.hp);same(r,u,'target killed between actors')
		check(a.hp==0,'lethal damage actually reached zero')
		r.heal(a,99999);same(r,u,'heal without resurrection');check(a.hp==0,'healing does not resurrect')
		r.hurt(b,1);same(r,u,'nonlethal damage')
		r.heal(b,1);same(r,u,'living heal')
		if r is Pass:
			b.morale=.001;r.hurt(b,1);same(r,u,'live routing through hurt override')
			if not r.square_battle:check(b.routing,'pass fixture actually routes')
		u.pos+=Vector2(23,7);same(r,u,'source position guard')
		u.side='enemy';same(r,u,'source side guard');u.side='ally'
		r.spawn('guard','enemy',u.pos+Vector2(2,0));same(r,u,'spawn invalidates active scope')
		# Explicit invalidation contract for future editor/in-loop mutation writers.
		b.side='ally';r.powers.invalidate_target_batch();same(r,u,'explicit invalidation target side')
		b.side='enemy';b.pos=u.pos+Vector2(1,0);r.powers.invalidate_target_batch();same(r,u,'explicit invalidation target position')
		r.units.reverse();r.powers.invalidate_target_batch();same(r,u,'explicit invalidation input reorder')
		r.powers.end_target_batch()
		# Raw editor/test writes have no synchronous production writer inside the pass.
		# They must begin a fresh scope (as real commands between ticks do).
		b.routing=false;b.side='ally';same(r,u,'outside batch side changed')
		b.side='enemy';b.pos=Vector2(750,1000);r.units.reverse();same(r,u,'outside batch position and input order changed')
		r.units.append(b);r.powers.begin_target_batch();same(r,u,'duplicate dictionary reference')
		r.powers.end_target_batch();r.units.clear();r.powers.begin_target_batch();same(r,u,'empty candidates');r.powers.end_target_batch()
		var q=fixture(script);var enemy=q.units[1]
		q.powers.resolve(q,{'character':'odysseus','pos':enemy.pos})
		q.powers.begin_target_batch();var decoy=same(q,enemy,'decoy range preference')
		check(decoy.get('kind','')=='decoy','in-range decoy chosen')
		q.hurt(decoy,decoy.hp);same(q,enemy,'decoy killed mid-pass')
		q.powers.advance(q,100.);same(q,enemy,'decoy expiration')
		q.powers.clear(q);check(not q.powers._target_batch.active,'power clear ends batch')
		q.hurt(q.units[0],q.units[0].hp);q.powers.begin_target_batch();same(q,enemy,'all enemies dead');q.powers.end_target_batch()
	mutation_checks()
	if not OS.get_cmdline_user_args().is_empty():FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({'checks':checks,'failures':failures,'cases':cases},'\t'))
	print('Target batch: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
func mutation_checks():
	var r=fixture(Square);var u=r.units[0];var enemy=r.units[1]
	# Actual blink updates the regiment center immediately, even during an exposed scope.
	r.spawn('legion','ally',Vector2(1100,1000),'wraith');var ghost=r.units.back()
	var ids=r.Soldiers.group_members([ghost]);r.powers.begin_target_batch();same(r,enemy,'before blink')
	check(r.Blink.issue(r,ids,Vector2(1100,800)),'blink issued');same(r,enemy,'after blink/center write-through')
	r.powers.end_target_batch();r.command([u.id],'auto',Vector2.ZERO)
	var actor=u.soldiers[0]
	r.powers.begin_target_batch();same(r,u,'before charge command')
	check(r.Charges.issue(r,[Vector2i(u.id,0)],actor.position+Vector2(0,-100)),'charge issued')
	r.command([u.id],'hold',Vector2.ZERO);same(r,u,'hold command midcharge')
	r.command([u.id],'auto',Vector2.ZERO);same(r,u,'auto command midcharge')
	u.stun=1.;u.petrified=1.;same(r,u,'frozen unit selection stays live')
	r.powers.end_target_batch()
	# Zero-HP target remains registered until death collection; selection still excludes HP=0.
	r.powers.begin_target_batch();same(r,u,'before actual fire actor')
	actor.target_id=enemy.id;actor.target_slot=0;actor.attack_pending=true;actor.attack_age=.6
	for victim in enemy.soldiers:victim.hp=1.
	r.Soldiers.total(enemy);r.powers.invalidate_target_batch()
	u.stun=0.;u.petrified=0.;r.Soldiers.fire_actor(r,u,0)
	same(r,u,'after actual release damage');check(enemy.soldiers[0].hp==0.,'fire_actor killed a real soldier')
	check(enemy.soldiers[0].get('death_state',0)==0,'HP zero precedes death registration')
	r.spawn('legion','ally',u.pos);var patient=r.units.back()
	r.hurt(patient,50.,'',0.,0);same(r,enemy,'before shaman living heal')
	var previous=patient.hp;r.Specials.heal_nearby(r,u,0)
	check(patient.hp>previous,'shaman actually healed living ally')
	same(r,enemy,'shaman direct HP and total write invalidation')
	r.powers.end_target_batch()
	# No personalized branch and retry/clear must not leave any scope or dictionary refs.
	var q=fixture(Square);q.powers.begin_target_batch();same(q,q.units[0],'stale scope before no-personal pass')
	q.Soldiers.advance_personal(q,1./60.);check(not q.powers._target_batch.active and q.powers._target_batch.unit.is_empty(),'no-personal cleanup')
	q.powers.begin_target_batch();q.powers.clear(q);check(not q.powers._target_batch.active,'clear/menu scope cleanup')
