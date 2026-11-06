extends SceneTree
const Battle=preload('res://scripts/tactical/pass_battle.gd')
const DT=1./60
var failed:=0
func check(ok:bool,note:String):
	if not ok:
		failed+=1
		push_error(note)
func _initialize():
	var r=Battle.new()
	r.units.clear()
	r.spawn('legion','enemy',Vector2(2200,825))
	r.spawn('cavalry','ally',Vector2(1750,820))
	r.spawn('cavalry','ally',Vector2(1750,880))
	var b=r.units[0]
	b.order='hold'
	r.start()
	var first_hp:float=b.hp
	var first_morale:float=b.morale
	for i in [1,2]:
		var a=r.units[i]
		var j=2+5*(i-1)
		var dir:=Vector2.RIGHT
		a.heading=r.ground_basis.affine_inverse().basis_xform(dir).normalized()
		a.pace=1.82;a.charge=true;a.charge_target=b.id;a.charge_id=1
		var hit={'attacker':a.id,'target':b.id,'charge_id':1,'sector':'side','dir':dir,'direction':a.heading,
			'rider':r.contact_profiles.cavalry.feet[7],'entry':r.contact_profiles.legion.feet[j],
			'defender_slot':j,'pos':b.pos,'speed':253.,'time':0.0}
		var e=r.deal_blow(a,b,17.,hit)
		check(not e.is_empty() and e.mounted_contact,'Each independent rider group has one impact')
		check(r.deal_blow(a,b,17.,hit).is_empty(),'Duplicate receipt ignored')
	var damage:float=first_hp-b.hp
	var morale_spent:float=first_morale-b.morale
	check(is_equal_approx(damage,2*17.*3.5*1.2),'Two groups, two damage budgets')
	check(is_equal_approx(morale_spent,damage/b.max_hp*(106 if b.general else 125)+6),'Morale charged once per group')
	for tick in 20:
		r.elapsed+=DT
		for a in [r.units[1],r.units[2]]:r.Contact.advance_passage(r,a,b,DT)
	check(b.slot_states.has(2) and b.slot_states.has(7),'Both contact bands survive overlapping times')
	check(first_hp-b.hp==damage and first_morale-b.morale==morale_spent,'No damage or morale spent on per-slot motion')
	var sample:Dictionary=r.units[1]
	r.command([sample.id],'hold',sample.pos)
	check(not sample.has('penetration') and not sample.has('follow_goal'),'New order cancels residual travel')
	b.hp=0
	r.step(DT)
	check(not r.units[2].has('penetration'),'Dead target ends passage')
	var spear={'kind':'spear','order':'hold','stun':0.,'petrified':0.,'last_stride':1.}
	check(not r.Contact.braced_pikes(spear,1.1) and r.Contact.braced_pikes(spear,1.3),'Recently moving pikes need time to brace')
	for wall:Rect2 in r.terrain.ROCKS:
		var foot=wall.position+Vector2(-9,8)
		b.pos=r.projection.affine_inverse()*(foot-r.contact_profiles.legion.feet[0])
		var shift=r.Contact.clip_shift(r,b,0,Vector2(60,0))
		check(shift.x>=0 and shift.x<9,'Displaced boot stays on approach side of rock')
	var boundary=r.bounds.end-Vector2(1,1)
	b.pos=boundary-r.ground_basis.affine_inverse().basis_xform(r.contact_profiles.legion.feet[0])
	var clipped=r.Contact.clip_shift(r,b,0,r.ground_basis.basis_xform(Vector2(150,50)))
	check(r.bounds.has_point(boundary+r.ground_basis.affine_inverse().basis_xform(clipped)),'Boot stays inside battle bounds')
	print('Formation passage regressions: ',failed,' failures')
	quit(1 if failed else 0)
