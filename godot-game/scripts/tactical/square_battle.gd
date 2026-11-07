extends "res://scripts/tactical/pass_battle.gd"
## Standalone pitched battle; the expedition continues to use the authored pass.
const SIZE=2100.0
var enemy_zone=Rect2(0,0,SIZE,SIZE/3)
var neutral_zone=Rect2(0,SIZE/3,SIZE,SIZE/3)

func _init(test_powers: bool=false):
	super(test_powers)
	square_battle=true
	for kind in config.types:contact_profiles[kind]=Contact.profile(kind,config.types[kind],true)
	ground_basis=Transform2D(Vector2.RIGHT,Vector2(0,PassTerrain.VIEW.ground_y),Vector2.ZERO)
	projection=ground_basis
	bounds=Rect2(0,0,SIZE,SIZE)
	deployment=Rect2(0,SIZE*2/3,SIZE,SIZE/3)
	powers.bounds=bounds
	units.clear()
	next_id=0
	barrels.clear()
	combined_arms=true
	flag_center=Vector2(-10000,-10000)
	flank_state='ended'
	var none=Rect2(-10000,-10000,1,1)
	terrain=PassTerrain.new(projection,bounds,config.types,{'rocks':[],'SidePass':none,'MainPass':none},true)
	for kind in reserve:reserve[kind]=1
	for row in formation():spawn(row[0],'enemy',Vector2(row[1],SIZE-row[2]))
	pass_layout_data.CombinedDeployment=deployment
	pass_layout_data.DefenderDeployment=deployment

func formation() -> Array:
	return [['guard',690.,1550.],['legion',1050.,1550.],['spear',1410.,1550.],
		['cavalry',340.,1770.],['archer',1050.,1840.],['medic',720.,1950.],['siege',1410.,1950.]]

func spawn(kind: String,side: String,pos: Vector2,variant: String=''):
	super(kind,side,pos,variant)
	units.back().heading=Vector2.UP if side=='ally' else Vector2.DOWN
	units.back().formation_heading=units.back().heading

func deploy_combined() -> bool:
	if phase!='deploy' or not alive('ally').is_empty():return false
	for row in formation():deploy(row[0],Vector2(row[1],row[2]))
	for u in alive('ally'):u.order='hold'
	return true

func deploy_vanguard() -> bool:
	return deploy_combined()

func deployment_valid(pos: Vector2,kind: String='legion') -> bool:
	if not super(pos,kind):return false
	var half: Vector2=terrain.extents[kind]
	var footprint=Rect2(projection*pos-half,half*2)
	if not (projection*deployment).encloses(footprint):return false
	for other in alive('ally'):
		var extent: Vector2=terrain.extents[other.kind]
		if footprint.intersects(Rect2(projection*other.pos-extent,extent*2)):return false
	return true

func layout_valid(slots: Dictionary) -> bool:
	if not super(slots):return false
	for u in alive('ally'):
		if not slots.has(u.id):continue
		var half: Vector2=terrain.extents[u.kind]
		if not (projection*deployment).encloses(Rect2(projection*slots[u.id]-half,half*2)):return false
	return true

func update_flank():pass

func combat_target(u: Dictionary) -> Dictionary:
	return powers.select_target(self,u)

func advance_objective(_u: Dictionary,_target: Dictionary,_dt: float) -> bool:
	return false

func resolve_battle(_dt: float):
	if not alive('enemy').any(func(u):return u.kind!='medic') and not Soldiers.pending_deaths(self,'enemy'):
		outcome='enemy_routed'
		phase='victory'
	elif not alive('ally').any(func(u):return u.kind!='medic') and not Soldiers.pending_deaths(self,'ally') and not reserve.keys().any(func(kind):return kind!='medic' and reserve[kind]>0):
		outcome='defenders_routed'
		phase='defeat'

func inside_flag(_unit: Dictionary) -> bool:return false
