extends Control
## Card/inspection art uses the actual soldiers, so counts and proportions stay honest.
const Formation=preload('res://scripts/formation.gd')
var troop_type='legion'
var level=1
var sprite: Texture2D

func _ready():
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	sprite=load('res://assets/unit_'+troop_type+'_ally_idle.png')
	queue_redraw()

func _draw():
	if sprite==null:return
	var count=Formation.count(troop_type,level)
	var points=[]
	for i in count:
		var p=Formation.offset(troop_type,i,count)
		points.append(Vector2(.76*p.x-.68*p.y,.27*p.x+.4*p.y))
	points.sort_custom(func(a,b):return a.y<b.y)
	var zoom=2.0 if size.x>=180 else 1.0
	for p in points:
		var origin=(size*.5+Vector2(0,20)*zoom+p*zoom).round()
		draw_texture_rect_region(sprite,Rect2(origin-Vector2(32,52)*zoom,Vector2(64,64)*zoom),Rect2(0,0,64,64))
