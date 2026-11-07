extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture(kind='legion'):
	var r=Battle.new();r.units.clear();r.spawn('cavalry' if kind=='mounted_archer' else kind,'ally',Vector2(1000,1200),'mounted_archer' if kind=='mounted_archer' else '');r.spawn('archer','enemy',Vector2(1000,900));r.spawn('legion','enemy',Vector2(1300,1000))
	for u in r.units:u.order='hold'
	r.start()
	for u in r.units:
		for i in u.soldiers.size():
			r.Charges.detach(r,u,i);var s=u.soldiers[i];s.hp=s.max_hp if i==0 else 0.;s.position=u.pos;s.personal_order='hold';s.cooldown=60.
		r.Soldiers.total(u)
	return r
func hit(r,amount=1.):
	r.hurt(r.units[0],amount,'archer',0.,0,r.units[1].id,0)
func tick(r,n=1):
	for i in n:r.step(1./60.)
func run():
	for order in ['idle','move','attack_move']:
		var r=fixture();var u=r.units[0];var a=u.soldiers[0]
		r.Soldiers.command(r,[Vector2i(u.id,0)],'move' if order=='idle' else order,Vector2(1500,1200));a.personal_order=order
		var path=a.path.duplicate();hit(r)
		check(a.personal_order=='attack' and a.target_id==r.units[1].id and a.target_slot==0,order+' retaliates against the actual attacking soldier')
		check(a.path==path if order=='attack_move' else a.path.is_empty(),order+' keeps only attack-move navigation for possible resumption')
		var start: Vector2=a.position;tick(r,15)
		check(a.position.y<start.y and a.personal_order=='attack',order+' actually pursues the attacker in simulation')
		if order=='attack_move':
			r.units[1].soldiers[0].hp=0.;r.Soldiers.total(r.units[1]);tick(r)
			check(a.personal_order=='attack_move' and a.path==path,'Attacker dying during pursuit resumes the saved attack-move route')
	var r=fixture();var a=r.units[0].soldiers[0]
	for order in ['hold','attack','charge','flee']:
		a.personal_order=order;a.focus_id=r.units[2].id;a.target_id=-1;hit(r)
		check(a.personal_order==order and a.target_id==-1,order+' does not acquire a different target on damage')
	a.personal_order='move';a.shield_wall=true;hit(r)
	check(a.personal_order=='move' and a.last_attacker==Vector2i(r.units[1].id,0),'Marching shield wall records its attacker without leaving formation')
	a.shield_wall=false;a.personal_order='idle';a.target_id=r.units[2].id;a.target_slot=0;hit(r)
	check(a.target_id==r.units[2].id and a.personal_order=='idle','Already pursuing automatically does not switch to a new attacker')
	r=fixture();a=r.units[0].soldiers[0];a.personal_order='move'
	r.hurt(r.units[0],1.,'archer',0.,0)
	check(a.personal_order=='move' and not a.has('last_attacker'),'Null-source volley/divine damage has no attacker retaliation')
	hit(r,0.)
	check(a.personal_order=='attack','Valid zero-damage hit still triggers original damage callback behavior')
	r=fixture();a=r.units[0].soldiers[0];a.personal_order='move';r.units[1].soldiers[0].hp=0.;r.units[1].soldiers[0].death_state=2;r.Soldiers.total(r.units[1]);hit(r)
	check(a.personal_order=='move','Projectile from a removed dead source does not retarget to a corpse')
	r=fixture();a=r.units[0].soldiers[0];a.personal_order='idle';hit(r,10000.)
	check(a.hp==0. and a.personal_order=='attack','Lethal damage preserves the original registered-target retaliation callback without healing')
	r=fixture();a=r.units[0].soldiers[0];a.personal_order='move'
	r.deal_blow(r.units[1],r.units[0],18.,{},{'attacker_slot':0,'target_slot':0,'release_delay':0.})
	check(a.personal_order=='move','Arrow release alone does not trigger retaliation')
	r.advance_volleys(1.)
	check(a.personal_order=='attack' and a.focus_id==r.units[1].id,'Real ordinary arrow landing carries its live shooter identity')
	r=fixture();a=r.units[0].soldiers[0];a.personal_order='idle'
	r.stones.append({'side':'enemy','from':r.units[1].pos,'pos':a.position,'age':0.,'flight':.1,'damage':10.,'attacker':r.units[1].id,'attacker_slot':0});r.advance_stones(.2)
	check(a.personal_order=='attack' and a.target_id==r.units[1].id,'Stone area hit carries source to every struck eligible actor')
	r=fixture();a=r.units[0].soldiers[0];a.personal_order='move'
	r.deal_blow(r.units[2],r.units[0],1.,{},{'attacker_slot':0,'target_slot':0})
	check(a.personal_order=='attack' and a.target_id==r.units[2].id,'Melee damage follows the same retaliation path')
	r=fixture('mounted_archer');a=r.units[0].soldiers[0]
	r.Soldiers.command(r,[Vector2i(r.units[0].id,0)],'attack_move',Vector2(1500,1200));a.target_id=r.units[2].id;a.target_slot=0;hit(r)
	check(a.personal_order=='attack' and a.target_id==r.units[1].id,'Moving horse archer shot target is not mistaken for an existing pursuit')
	r.Soldiers.command(r,[Vector2i(r.units[0].id,0)],'hold',a.position)
	check(not a.has('resume_attack_move'),'Fresh H command clears interrupted attack-move resumption')
	r=fixture('archer');a=r.units[0].soldiers[0];a.personal_order='move';a.target_id=r.units[2].id;a.target_slot=0
	r.target_reservations=r.Soldiers.ranged_target_counts(r);hit(r)
	check(r.target_reservations.get(Vector2i(r.units[2].id,0),0)==0 and r.target_reservations.get(Vector2i(r.units[1].id,0),0)==1,'Mid-step retaliation transfers ranged reservations for later actors')
	r=fixture();a=r.units[0].soldiers[0]
	r.Soldiers.command(r,[Vector2i(r.units[0].id,0)],'attack_move',Vector2(1500,1200));hit(r);a.attack_engaged=Vector2i(r.units[1].id,0)
	r.units[1].soldiers[0].hp=0.;r.Soldiers.total(r.units[1]);tick(r)
	check(a.personal_order=='idle','Target dying after entering attack state goes idle, matching original state distinction')
	var saved=a.duplicate(true);r.step(0.)
	check(a==saved,'Pause leaves retaliation state unchanged')
	print('Retaliation: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
