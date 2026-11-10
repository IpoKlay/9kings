extends "res://scripts/tactical/whiteboard_battle.gd"
## Authored 64-person experiment. Production formation defaults are untouched.
var contact_log: Array=[]
var rider_ids: Array=[]
var defender_ids: Array=[]
var initial_feet: Dictionary={}
var axis=Vector2(.8,-.6)
var impact=Vector2(1610,1670)
var comparison="flank"
var exit_orders=true
var exit_pending: Dictionary={}
var entered_defense: Dictionary={}
var defense_area=Rect2()
var feedback_shock_time=-100.

func setup(mode: String="flank"):
	comparison=mode
	units.clear();next_id=0;shield_walls.clear();wall_serial=0
	contact_log.clear();rider_ids.clear();defender_ids.clear();initial_feet.clear()
	exit_pending.clear();entered_defense.clear()
	if mode!="flank":axis=Vector2.UP;impact=Vector2(1640,1700)
	for rank in 4:
		spawn('spear' if mode=='pikes' else 'legion','ally',Vector2(1640,1700-rank*38))
	for rank in 3:spawn('cavalry','enemy',impact-axis*(360+rank*60))
	for u in units:
		u.order='hold'
		for slot in u.soldiers.size():Charges.detach(self,u,slot)
	start()
	var plan={}
	for rank in 4:
		var u=units[rank]
		for column in 10:
			var key=Vector2i(u.id,column)
			var p=Vector2(1480+column*36,1700-rank*38)
			u.soldiers[column].position=p
			plan[key]={'goal':p,'heading':Vector2.DOWN,'path':[],'column':column,'rank':rank,'spacing':38.,'columns':10}
			defender_ids.append(key);initial_feet[key]=p
	Walls.place(self,plan)
	defense_area=Rect2(initial_feet[defender_ids[0]],Vector2.ZERO)
	for key in defender_ids:defense_area=defense_area.expand(initial_feet[key])
	defense_area=defense_area.grow(18.)
	for key in defender_ids:
		var actor=units[key.x].soldiers[key.y]
		actor.personal_order='hold';actor.path=[];actor.wall_settle=1.
	for rank in 3:
		var u=units[4+rank]
		for column in 8:
			var key=Vector2i(u.id,column)
			var actor=u.soldiers[column]
			actor.position=impact-axis*(360+rank*60)+axis.orthogonal()*(column-3.5)*32
			actor.heading=axis;actor.personal_order='hold';actor.path=[]
			rider_ids.append(key);initial_feet[key]=actor.position
	for u in units:Soldiers.update_center(self,u,0.)

func launch() -> bool:
	return Charges.issue(self,rider_ids,impact+axis*230,'enemy')

func step(dt: float):
	super.step(dt)
	for key in rider_ids:
		var actor=units[key.x].soldiers[key.y]
		if actor.hp<=0:continue
		if actor.has('charge_run') and defense_area.has_point(actor.position):entered_defense[key]=true
		if not exit_orders:continue
		# Finishing a run is not proof of a breakthrough. Reacquire locally instead
		# of sending untouched riders another 70 units into empty ground.
		if actor.has('charge_end') and not exit_pending.has(key):
			exit_pending[key]=true
			if actor.charge_end.reason in ['through','goal']:
				Soldiers.command(self,[key],'auto',actor.position,-1,-1,[],true,'enemy')
				actor.aggro_timer=.1

func deal_blow(attacker: Dictionary,target: Dictionary,damage: float,contact: Dictionary={},strike: Dictionary={}) -> Dictionary:
	var result=super.deal_blow(attacker,target,damage,contact,strike)
	if result.get('damage',0.)>0. and strike.has('target_slot') and strike.has('attacker_slot'):
		var victim: Dictionary=target.soldiers[strike.target_slot]
		var rider: Dictionary=attacker.soldiers[strike.attacker_slot]
		var heavy: bool=strike.get('personal_charge',false)
		if elapsed-victim.get('preview_hit',{}).get('start',-100.)>=.20:
			var direction=Soldiers.ground_position(self,attacker,strike.attacker_slot).direction_to(Soldiers.ground_position(self,target,strike.target_slot))
			victim.preview_hit={'start':elapsed,'heavy':heavy,'direction':direction}
		if elapsed-rider.get('preview_strike',{}).get('start',-100.)>=.20:rider.preview_strike={'start':elapsed,'heavy':heavy}
		if heavy and elapsed-feedback_shock_time>=.45:feedback_shock_time=elapsed
	if strike.get('personal_charge',false):
		contact_log.append({'time':elapsed,'rider':[attacker.id,strike.attacker_slot],
			'victim':[target.id,strike.target_slot],'damage':result.get('damage',0.),
			'position':Soldiers.ground_position(self,target,strike.target_slot)})
	return result
