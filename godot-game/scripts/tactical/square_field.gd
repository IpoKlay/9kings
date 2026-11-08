@tool
extends Node2D
## Layout lives in square_battlefield.tscn. Gameplay continues to own map bounds.
var trial
@export var landscape_rect := Rect2(-300,-240,2700,2085)
const Scenery=preload('res://scripts/battle_environment.gd')
var environment=Scenery.new() if not Engine.is_editor_hint() else null
var animated_scenery: Array[Node]=[]

func _ready():
	$EditorGuides.visible=Engine.is_editor_hint()
	$DeploymentGuides.draw.connect(_draw_deployment_overlay)
	for child in find_children('*','Marker2D',true,false):
		if child.has_method('animate_scenery'):animated_scenery.append(child)

func advance(delta: float):
	environment.tick(delta)
	for child in animated_scenery:child.animate_scenery(environment)
	$DeploymentGuides.queue_redraw()

func _draw_deployment_overlay():
	if trial!=null and trial.rules.phase=='deploy':draw_deployment(trial.rules)

func _draw():
	# Camera/zoom changes request a map redraw without advancing simulation.
	if has_node('DeploymentGuides'):$DeploymentGuides.queue_redraw()

func draw_deployment(r):
	for y in [r.SIZE/3,r.SIZE*2/3]:
		var a: Vector2=r.projection*Vector2(0,y)
		var b: Vector2=r.projection*Vector2(r.SIZE,y)
		$DeploymentGuides.draw_dashed_line(a,b,Color('#d2c79899'),2,20)
	var font=trial.hint.get_theme_font('font')
	for row in [[105.,trial.words('敌军部署区','ENEMY DEPLOYMENT')],
		[1045.,trial.words('交战区 · 不可部署','BATTLEFIELD · NO DEPLOYMENT')],
		[1920. if trial.zoom<.75 else 2040.,trial.words('我军部署区','YOUR DEPLOYMENT')]]:
		var font_size=roundi(24.0/trial.zoom)
		var width=font.get_string_size(row[1],HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
		var p: Vector2=r.projection*Vector2((r.SIZE-width)/2,row[0])
		var screen: Vector2=(p-trial.camera_offset)*trial.zoom
		if screen.y<120 or screen.y>900:continue
		$DeploymentGuides.draw_string(font,p+Vector2(2,2),row[1],HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color('#263727'))
		$DeploymentGuides.draw_string(font,p,row[1],HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color('#dbcfaa'))
