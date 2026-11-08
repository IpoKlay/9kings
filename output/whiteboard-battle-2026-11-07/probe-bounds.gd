extends SceneTree
const Battle=preload('res://scripts/tactical/whiteboard_battle.gd')
func _initialize():
	var preset: Resource=Battle.MAP
	var original: Rect2=preset.values.bounds
	preset.values.bounds=Rect2(0,0,4000,4000)
	print('PRESET_AFTER_WRITE ',preset.values, ' same=',preset==Battle.MAP)
	var b=Battle.new()
	print('BOUNDS_PROBE bounds=',b.bounds,' deployment=',b.deployment,' formation=',b.formation(),' rows=',b.deployment_rows(),' resource=',Battle.MAP.values.bounds)
	preset.values.bounds=original
	quit()
