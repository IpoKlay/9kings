extends "res://scripts/tactical/whiteboard_battle.gd"
## Authored 64-person experiment. Production formation defaults are untouched.
var contact_log: Array=[]
var rider_ids: Array=[]
var defender_ids: Array=[]
var initial_feet: Dictionary={}
var axis=Vector2(.8,-.6)
var impact=Vector2(1510,1620)
var comparison="flank"
var exit_orders=true
var exit_pending: Dictionary={}

func setup(mode: String="flank"):
	comparison=mode
	units.clear();next_id=0;shield_walls.clear();wall_serial=0
	contact_log.clear();rider_ids.clear();defender_ids.clear();initial_feet.clear()
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
	if not exit_orders:return
	# An explicit follow-up order for the drill, not extra charge motion or damage.
	# A stopped rider remains in melee; only riders that finished their run clear the lane.
	for key in rider_ids:
		var actor=units[key.x].soldiers[key.y]
		if actor.hp<=0:continue
		if actor.has('charge_end') and not exit_pending.has(key):
			exit_pending[key]=false
			if actor.charge_end.reason in ['through','goal']:
				var goal: Vector2=actor.position+axis*70.
				if Soldiers.command(self,[key],'move',goal,-1,-1,[],true,'enemy'):
					exit_pending[key]=true
		elif exit_pending.get(key,false) and actor.get('path',[]).is_empty():
			# Reacquire from the exit position instead of reversing to a trampled victim.
			actor.personal_order='auto';actor.target_id=-1;actor.target_slot=-1
			exit_pending[key]=false

func deal_blow(attacker: Dictionary,target: Dictionary,damage: float,contact: Dictionary={},strike: Dictionary={}) -> Dictionary:
	var result=super.deal_blow(attacker,target,damage,contact,strike)
	if strike.get('personal_charge',false):
		contact_log.append({'time':elapsed,'rider':[attacker.id,strike.attacker_slot],
			'victim':[target.id,strike.target_slot],'damage':result.get('damage',0.),
			'position':Soldiers.ground_position(self,target,strike.target_slot)})
	return result
