extends Node2D

const Scenery=preload('res://scripts/battle_environment.gd')
var environment=Scenery.new()
@onready var landscape: Sprite2D=$Landscape

func _ready():
	$Gameplay/Areas.hide()
	environment.landscape_texture=landscape.texture
	environment.landscape_size=landscape.texture.get_size()*landscape.scale
	environment.shore_origin=Vector2(0,1080)
	for tree: Sprite2D in $Decoration/Trees.get_children():
		if tree.visible:
			var foot:=to_local(tree.global_position)-landscape.position
			environment.landscape_trees.append(Vector3(foot.x,foot.y,tree.texture.get_width()*tree.scale.x))
	$Decoration/Trees.hide()
	environment.attach(self,landscape)
	landscape.show_behind_parent=true

func tex(id: String) -> Texture2D:
	return load('res://assets/'+id+'.png')

func advance(delta: float):
	environment.tick(delta)
	for flag in $Decoration/Flags.get_children():
		flag.clock=environment.clock
		flag.queue_redraw()
	queue_redraw()

func _draw():
	if not is_node_ready():return
	draw_set_transform(landscape.position)
	environment.draw(self,1,landscape.position)

# This also works on an instantiated scene outside the tree for headless rules.
func settings(projection: Transform2D) -> Dictionary:
	var inverse:=projection.affine_inverse()
	var data: Dictionary={}
	for area: Line2D in $Gameplay/Areas.get_children():
		var box:=Rect2(inverse*(area.global_transform*area.points[0]),Vector2.ZERO)
		for point in area.points:
			box=box.expand(inverse*(area.global_transform*point))
		data[str(area.name)]=Rect2(box.position.snapped(Vector2.ONE*0.001),box.size.snapped(Vector2.ONE*0.001))
	data.rocks=[]
	for rock: Control in $Gameplay/RockWalls.get_children():
		data.rocks.append(rock.get_global_transform()*Rect2(Vector2.ZERO,rock.size))
	for name_id in ['MainPass','SidePass']:
		var gate: Control=$Gameplay.get_node(name_id)
		data[name_id]=gate.get_global_transform()*Rect2(Vector2.ZERO,gate.size)
	data.flag=(inverse*$Gameplay/EagleStandard.global_position).snapped(Vector2.ONE*0.001)
	data.escort=(inverse*$Spawns/CampEscort.global_position).snapped(Vector2.ONE*0.001)
	for group in $Spawns.get_children():
		if group is Marker2D:continue
		var rows: Array=[]
		for mark: Marker2D in group.get_children():
			var world: Vector2=(inverse*mark.global_position).snapped(Vector2.ONE*0.001)
			if mark.has_meta('kind'):rows.append([mark.get_meta('kind'),world])
			else:rows.append(world)
		data[str(group.name)]=rows
	return data
