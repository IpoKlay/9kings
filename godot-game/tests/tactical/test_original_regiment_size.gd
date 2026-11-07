extends SceneTree
const Square=preload('res://scripts/tactical/square_battle.gd')
const Pass=preload('res://scripts/tactical/pass_battle.gd')
var checks=0
var failures=0

func _initialize():call_deferred('run')

func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)

func run():
	var square=Square.new()
	var pass_battle=Pass.new()
	square.units.clear();pass_battle.units.clear()
	var field: Rect2=square.projection*square.bounds
	for kind in square.config.types:
		var restored: Dictionary=square.contact_profiles[kind]
		var original: Dictionary=pass_battle.contact_profiles[kind]
		check(restored==original,kind+' restores original sprite size, spacing and body contact')
		var half: Vector2=square.terrain.extents[kind]
		var inset=half+Vector2(2,2)
		var points=[Vector2(inset.x,field.get_center().y),Vector2(field.end.x-inset.x,field.get_center().y),
			Vector2(field.get_center().x,inset.y),Vector2(field.get_center().x,field.end.y-inset.y)]
		square.spawn(kind,'ally',Vector2.ZERO)
		var squad: Dictionary=square.units.back()
		var boot_half=Vector2(9,5)*restored.scale
		for point in points:
			squad.pos=square.projection.affine_inverse()*point
			check(square.terrain.clear_segment(kind,squad.pos,squad.pos),kind+' fits at safe map margin')
			for direction in 8:
				var heading=Vector2.RIGHT.rotated(direction*PI/4)
				for foot in square.Contact.feet(square,squad,heading):
					check(field.encloses(Rect2(point+foot-boot_half,boot_half*2)),kind+' rotated boots stay inside map')
		var outside=square.projection.affine_inverse()*Vector2(half.x-2,field.get_center().y)
		check(not square.terrain.clear_segment(kind,outside,outside),kind+' rejects endpoint whose row crosses map edge')
		# Original-size formations must still pass the authored mountain side lane.
		pass_battle.spawn(kind,'ally',pass_battle.terrain.inverse*Vector2(790,900))
		var mountain: Dictionary=pass_battle.units.back()
		var goal: Vector2=pass_battle.terrain.inverse*Vector2(1340,900)
		var route: Array=pass_battle.terrain.leg(kind,mountain.pos,goal)
		check(not route.is_empty(),kind+' has a valid original-width side-lane route')
		var previous: Vector2=mountain.pos
		for vertex in route:
			var heading=previous.direction_to(vertex)
			for sample in 21:
				mountain.pos=previous.lerp(vertex,sample/20.)
				for foot in pass_battle.Contact.feet(pass_battle,mountain,heading):
					var boots=Rect2(pass_battle.projection*mountain.pos+foot-boot_half,boot_half*2)
					for rock in pass_battle.terrain.ROCKS:
						check(not boots.intersects(rock),kind+' original boots clear the side-lane rocks')
			previous=vertex
	var preset=Square.new()
	preset.deploy_combined()
	check(preset.alive('ally').size()==7,'Original-size preset deploys all seven arms')
	for u in preset.units:
		var zone: Rect2=preset.projection*(preset.deployment if u.side=='ally' else preset.enemy_zone)
		var half: Vector2=preset.terrain.extents[u.kind]
		check(zone.encloses(Rect2(preset.projection*u.pos-half,half*2)),'Entire preset row stays inside its deployment third')
	print('Original regiment size: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
