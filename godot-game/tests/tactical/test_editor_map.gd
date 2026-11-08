extends SceneTree
## Preserved authored-map edits must survive save/reload and the shared battle UI.
const MAP=preload('res://scenes/battlefields/square_battlefield.tscn')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func run():
	var map=MAP.instantiate()
	check(map.get_node('Trees').get_child_count()==42,'All original trees are authored nodes')
	check(map.get_node('Borders/RockBanks').get_child_count()==12,'All original rock banks are authored polygons')
	check(map.get_node('Camps/Ally/MedicalTent') is Sprite2D,'Camp art is a native editable sprite')
	check(map.get_node('Roads/Track') is Polygon2D,'Road outline and UVs are editable')
	var tree=map.get_node('Trees/Oak01')
	var old: Vector2=tree.position
	tree.position+=Vector2(36,18);tree.canopy_size=230
	map.get_node('Roads/Track').position+=Vector2(12,0)
	var pack=PackedScene.new()
	check(pack.pack(map)==OK,'Edited map can be packed')
	var path='user://editor-map-roundtrip.tscn'
	check(ResourceSaver.save(pack,path)==OK,'Edited map saves to disk')
	var restored=load(path).instantiate()
	check(restored.get_node('Trees/Oak01').position==old+Vector2(36,18),'Saved tree placement survives reload')
	check(restored.get_node('Trees/Oak01').canopy_size==230,'Saved canopy size survives reload')
	check(restored.get_node('Roads/Track').position==map.get_node('Roads/Track').position,'Road edits survive reload')
	restored.free();map.free();DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-editor-map-test.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit()
	var t=app.active_trial;t.set_process(false)
	# Legacy authored-map fixture; default menu coverage lives in test_whiteboard_battle.gd.
	t.rules=t.SquareBattle.new();t.field.load_battlefield();t.reset_camera()
	app.sound.enabled=false
	var r=t.rules
	check(not t.field.pass_layout.get_node('EditorGuides').visible,'Editor-only zone guides stay out of live gameplay')
	check(t.field.pass_layout.scene_file_path==MAP.resource_path,'Legacy fixture loads authored scene')
	check(r.bounds==Rect2(0,0,2100,2100),'Battle bounds stay square and unchanged')
	check(r.deployment==Rect2(0,1400,2100,700),'Player still deploys only in bottom third')
	check(t.field.LANDSCAPE==Rect2(-300,-240,2700,2085),'Camera bounds preserved')
	t.combined_button.pressed.emit();t.start_button.pressed.emit()
	check(r.units.size()==14 and r.phase=='battle','Both seven-arm armies can begin combat')
	var scenery=t.field.pass_layout
	var clock: float=scenery.environment.clock
	t.paused=true;t._process(.05)
	check(scenery.environment.clock==clock,'Pause freezes scenery with simulation')
	t.paused=false;t._process(.05)
	check(scenery.environment.clock>clock,'Scenery resumes with simulation')
	check(scenery.get_node('Camps/Ally/Flag1').clock==scenery.environment.clock,'Flags share the original scenery clock')
	check(scenery.get_node('Trees/Oak01').environment==scenery.environment,'Trees share the original wind profiles')
	var zoom: float=t.zoom;var offset: Vector2=t.camera_offset
	t.toggle_overview();t.toggle_overview()
	check(t.zoom==zoom and t.camera_offset==offset,'Overview restores the original camera')
	t.retry()
	check(t.field.pass_layout.get_node('Trees/Oak01').position==old,'Retry reloads authored defaults, no runtime layout regeneration')
	t.closed.emit();app.queue_free();await process_frame
	print('Editor map: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
