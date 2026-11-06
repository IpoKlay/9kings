extends SceneTree
func _init():
	var validator=preload('res://scripts/data/validator.gd').new()
	var errors=validator.validate()
	for error in errors: printerr('DATA ERROR: '+error)
	print('%d data validation checks, %d failures'%[validator.checks,errors.size()])
	quit(0 if errors.is_empty() else 1)
