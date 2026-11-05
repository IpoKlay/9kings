extends SceneTree
## Native scene contract, independent of battle simulation and animation assets.
## godot --headless --path godot-game --script res://tests/tactical/test_battle_hud_layout.gd
var failures=0
var checks=0

class BattlefieldProbe extends Control:
	var clicks=0
	func _unhandled_input(event):
		if event is InputEventMouseButton and event.pressed:clicks+=1

func _initialize():call_deferred('run')

func check(ok: bool, description: String):
	checks+=1
	if not ok:
		failures+=1
		push_error(description)

func click(point: Vector2):
	for down in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=point
		event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=down
		root.push_input(event,true)
	await process_frame

func run():
	root.size=Vector2i(1920,1080)
	var probe=BattlefieldProbe.new()
	probe.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root.add_child(probe)
	var hud=load('res://scenes/ui/battle_hud.tscn').instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame
	var start: Button=hud.get_node('BattleActions/StartButton')
	check(start.is_visible_in_tree() and start.text=='开战','Actual start control is visible without _ready or a controller')
	check(start.get_global_rect()==Rect2(1738,1006,164,56),'Authored start rectangle at logical 1920 x 1080')
	check(not start.get_parent() is Container,'Start position is independent of containers')
	check(hud.get_node('ReserveActions').get_child_count()==7,'Seven real reserve buttons in the scene')
	check(hud.get_node('RegimentRoster').get_child_count()==10,'Current ten reserve slots have editable roster controls')
	check(hud.get_node('HelpGroup/ControlsLabel').text!='','Help has authored preview content')
	check(hud.get_node('ResultGroup/ResultLabel').text!='','Result has authored preview content')
	for control in hud.find_children('*','Control',true,false):
		# PopupMenu internals legitimately capture input while their window is open.
		if control.owner!=hud:continue
		if control is BaseButton:
			check(control.mouse_filter==Control.MOUSE_FILTER_STOP,control.name+' consumes only its own rectangle')
		else:
			check(control.mouse_filter==Control.MOUSE_FILTER_IGNORE,control.name+' passes empty space to the field')
	var style=start.get_theme_stylebox('normal')
	check(style is StyleBoxTexture,'Editor and runtime use a textured paper StyleBox')
	check(style.texture.get_size()==Vector2(201,111),'Existing toolbar crop with nearest-neighbour 3x scale')
	check(style.modulate_color.is_equal_approx(Color(.92,.84,.69,1)),'Original map paper tint')
	start.theme_type_variation=&'SelectedBattleButton'
	check(start.get_theme_stylebox('normal').modulate_color.is_equal_approx(Color(.68,.40,.28,1)),'Selected tint comes from the same theme')
	start.theme_type_variation=&''
	var calls={'count':0}
	start.pressed.connect(func():calls.count+=1)
	var before=probe.clicks
	await click(start.get_global_rect().get_center())
	check(calls.count==1 and probe.clicks==before,'A button click invokes once and does not reach the battlefield')
	await click(Vector2(1200,1034))
	check(probe.clicks==before+1,'Bottom transparent gap reaches battlefield input')
	await click(Vector2(680,966))
	check(probe.clicks==before+2,'Deployment-row transparent gap reaches battlefield input')
	# Save an actual edited PackedScene, reload it, and check the authored offset.
	var initial=start.position
	start.offset_left-=96
	start.offset_right-=96
	var packed=PackedScene.new()
	check(packed.pack(hud)==OK,'Pack edited HUD')
	check(ResourceSaver.save(packed,'user://battle-hud-layout-check.tscn')==OK,'Save edited HUD')
	hud.queue_free()
	await process_frame
	var moved=load('user://battle-hud-layout-check.tscn').instantiate()
	root.add_child(moved)
	await process_frame
	await process_frame
	check(moved.get_node('BattleActions/StartButton').position==initial-Vector2(96,0),'Saved button position survives scene reload')
	moved.queue_free()
	probe.queue_free()
	DirAccess.remove_absolute('user://battle-hud-layout-check.tscn')
	await process_frame
	print('BATTLE HUD LAYOUT: %d checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
