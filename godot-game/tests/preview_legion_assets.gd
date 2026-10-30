extends SceneTree
const FontFace=preload('res://assets/fonts/game_pixel_font.tres')
func _init():call_deferred('run')
func label(parent,text,pos,extent,font_size=24):
	var l=Label.new();l.text=text;l.position=pos;l.size=extent
	l.add_theme_font_override('font',FontFace);l.add_theme_font_size_override('font_size',font_size)
	l.add_theme_color_override('font_color',Color('#dfcfaa'));parent.add_child(l)
func run():
	var view=SubViewport.new();view.size=Vector2i(1440,1200)
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var canvas=Control.new();view.add_child(canvas)
	var bg=ColorRect.new();bg.size=Vector2(1920,1600);bg.color=Color('#172b2a');canvas.add_child(bg)
	label(canvas,'鹰旗之下 · 三级军团与建筑',Vector2(60,32),Vector2(1200,54),40)
	label(canvas,'同一格位升级 · 人物 1.0 比例 · 下图为素材放大对照',Vector2(60,92),Vector2(1200,40),23)
	for col in 3:label(canvas,['I · 初建','II · 扩充','III · 完备'][col],Vector2(350+col*340,150),Vector2(300,40),30)
	for row in 5:
		var type=['legion','archer','cavalry','siege','medic'][row]
		var y=200+row*192
		label(canvas,['军团步兵','弓箭手','骑兵','攻城营','医疗营'][row],Vector2(60,y+66),Vector2(220,42),30)
		for col in 3:
			var x=350+col*340
			if row<3:
				var art=preload('res://scripts/squad_art.gd').new()
				art.troop_type=type;art.level=col+1;art.position=Vector2(x,y-12);art.size=Vector2(192,160);canvas.add_child(art)
				label(canvas,str(preload('res://scripts/formation.gd').count(type,col+1))+(' 骑' if row==2 else ' 人'),Vector2(x+75,y+145),Vector2(180,32),24)
			else:
				var image=TextureRect.new();image.texture=load('res://assets/facilities/%s_%d.png'%[type,col+1])
				image.position=Vector2(x,y-8);image.size=Vector2(192,192);image.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;canvas.add_child(image)
	await process_frame;await process_frame;RenderingServer.force_draw()
	view.get_texture().get_image().save_png('res://../output/legions-v1/upgrade-guide.png')
	quit()
