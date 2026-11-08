extends "res://scripts/tactical/square_battle.gd"
## Same combat system; only this mode replaces the authored terrain and projection.
const MAP=preload('res://data/presentation/whiteboard_map.tres')

func _init(test_powers: bool=false):
	super(test_powers)
	ground_basis=Transform2D.IDENTITY
	projection=ground_basis
	# Read the resource at runtime; chained const access can fold authored values.
	var map: Resource=MAP
	bounds=map.values.bounds
	var center: Vector2=bounds.get_center()
	var gap: float=map.values.neutral_width
	enemy_zone=Rect2(bounds.position,Vector2(bounds.size.x,(bounds.size.y-gap)*.5))
	neutral_zone=Rect2(Vector2(bounds.position.x,center.y-gap*.5),Vector2(bounds.size.x,gap))
	deployment=Rect2(Vector2(bounds.position.x,neutral_zone.end.y),enemy_zone.size)
	powers.bounds=bounds
	var none=Rect2(-10000,-10000,1,1)
	terrain=PassTerrain.new(projection,bounds,config.types,{'rocks':[],'SidePass':none,'MainPass':none},true)
	units.clear();next_id=0
	for row in deployment_rows():spawn(row[0],'enemy',Vector2(row[1],center.y*2-row[2]))
	pass_layout_data.CombinedDeployment=deployment
	pass_layout_data.DefenderDeployment=deployment

func deployment_rows() -> Array:
	var rows=formation()
	var shift=bounds.get_center()-Vector2(1050,1050)
	for row in rows:
		row[1]+=shift.x
		row[2]+=shift.y
	return rows

func deploy_combined() -> bool:
	if phase!='deploy' or not alive('ally').is_empty():return false
	for row in deployment_rows():deploy(row[0],Vector2(row[1],row[2]))
	for u in alive('ally'):u.order='hold'
	return true

func camera_focus() -> Vector2:
	return bounds.get_center()+Vector2(0,650)
