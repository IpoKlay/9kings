extends "res://scripts/tactical/square_battle.gd"
const Fort=preload('res://scenes/battlefields/roman_siege.tscn')
func _init(test_powers: bool=false):
	super(test_powers)
	units.clear();next_id=0
	deployment=Rect2(0,1100,SIZE,1000)
	pass_layout_data.CombinedDeployment=deployment
	pass_layout_data.DefenderDeployment=deployment
	var layout=Fort.instantiate()
	for section in layout.get_children():
		structures.append({'id':str(section.name),'rect':Rect2(section.position+section.footprint.position,section.footprint.size),
			'hits':0,'limit':section.hits_to_breach,'side':'enemy','last_hit':-1.})
	layout.free()
	structure_base_rocks=terrain.ROCKS.duplicate()
	var obstacles: Array=structure_base_rocks.duplicate()
	for section in structures:obstacles.append(section.rect)
	terrain.replace_rocks(obstacles)
	spawn('legion','enemy',Vector2(1050,600));spawn('archer','enemy',Vector2(800,440))
	for u in units:u.order='hold'
	for row in formation():spawn(row[0],'ally',Vector2(row[1],row[2]))
	for u in alive('ally'):u.order='hold'
	# Place the existing artillery regiment within its normal firing range.
	var engines=alive('ally').filter(func(u):return u.kind=='siege')[0]
	engines.pos=Vector2(1050,1320)
