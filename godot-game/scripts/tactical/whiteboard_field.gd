@tool
extends Node2D
var map: Resource=preload('res://data/presentation/whiteboard_map.tres')
var trial
var landscape_rect: Rect2:
	get:return map.values.bounds.grow(map.values.camera_margin)

func advance(_delta: float):
	queue_redraw()

func _draw():
	var area: Rect2=map.values.bounds
	var zoom: float=trial.zoom if trial!=null else 1.0
	draw_rect(area.grow(area.size.x*2),Color('#e4e4e4'))
	draw_rect(area,Color.WHITE)
	draw_rect(area,Color('#666666'),false,2.0/zoom)
	if trial==null or trial.rules.phase!='deploy':return
	var r=trial.rules
	for y in [r.neutral_zone.position.y,r.neutral_zone.end.y]:
		draw_dashed_line(Vector2(area.position.x,y),Vector2(area.end.x,y),Color('#858585'),2.0/zoom,14.0/zoom)
	var font=trial.hint.get_theme_font('font')
	var font_size=roundi(22.0/zoom)
	for row in [[r.neutral_zone.position.y-30.0/zoom,trial.words('敌军部署区','ENEMY DEPLOYMENT')],
		[r.neutral_zone.end.y+34.0/zoom,trial.words('我军部署区','YOUR DEPLOYMENT')]]:
		var left=maxf(area.position.x,trial.camera_offset.x)+24.0/zoom
		draw_string(font,Vector2(left,row[0]),row[1],HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color('#666666'))
