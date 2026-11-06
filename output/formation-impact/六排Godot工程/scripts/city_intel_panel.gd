extends Panel
## A static pixel paper surface; the map keeps its existing RPG material and font.
const INK=Color('#32382b')
const MUTED=Color('#66513a')
const RED=Color('#743e2d')
const PAPER=Color('#dfcba0')
var grain: Texture2D
var show_stats=false
var simple=false

class CloseButton extends Button:
	func _draw():
		var ink=Color('#8a462f') if is_hovered() else Color('#66513a')
		var center=(size*.5).floor()-Vector2.ONE
		for i in range(-6,7,2):
			draw_rect(Rect2(center+Vector2(i,i),Vector2(2,2)),ink)
			draw_rect(Rect2(center+Vector2(i,-i),Vector2(2,2)),ink)

func _init():
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter=Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override('panel',StyleBoxEmpty.new())

func stepped(rect: Rect2,color: Color,inset: float=4):
	draw_rect(Rect2(rect.position+Vector2(inset,0),rect.size-Vector2(inset*2,0)),color)
	draw_rect(Rect2(rect.position+Vector2(0,inset),rect.size-Vector2(0,inset*2)),color)

func _draw():
	stepped(Rect2(Vector2(4,6),size),Color(0.07,.10,.08,.28),6)
	stepped(Rect2(Vector2.ZERO,size),Color('#826442'),6)
	stepped(Rect2(Vector2(2,2),size-Vector2(4,4)),Color('#c0a170'),4)
	stepped(Rect2(Vector2(4,4),size-Vector2(8,8)),PAPER,4)
	if grain!=null:
		draw_texture_rect_region(grain,Rect2(8,8,size.x-16,size.y-16),Rect2(24,12,(size.x-16)*.5,(size.y-16)*.5),Color(1,1,1,.12))
	# Short edge fibres and two ink rules; decoration stays outside the reading column.
	draw_line(Vector2(12,8),Vector2(size.x-12,8),Color('#eddbb3'),2)
	draw_line(Vector2(12,size.y-8),Vector2(size.x-12,size.y-8),Color('#b59969'),2)
	for y in range(24,int(size.y)-20,28):
		var length=4+(int(y/28)%3)*2
		draw_rect(Rect2(6,y,length,2),Color('#c3ab7b'))
		draw_rect(Rect2(size.x-6-length,y+10,length,2),Color('#c3ab7b'))
	if simple: return
	draw_rect(Rect2(24,24,4,16),RED)
	for y in [134,294]:
		draw_rect(Rect2(24,y,size.x-48,1),Color('#b59a68'))
		draw_rect(Rect2(24,y+1,size.x-48,1),Color('#ecd9ad'))
		draw_rect(Rect2(size.x*.5-2,y-1,4,4),Color('#9c7748'))
	if show_stats: draw_rect(Rect2(24,256,size.x-48,28),Color(.43,.32,.18,.09))

static func button(control: Button,primary: bool=false,close: bool=false):
	control.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	for state in ['normal','hover','pressed','disabled']:
		var box=StyleBoxFlat.new()
		box.anti_aliasing=false
		box.bg_color=Color.TRANSPARENT if close else (RED if primary else Color('#d6bf90'))
		box.border_color=Color('#a98c5c') if not primary else Color('#532f26')
		if state=='hover':box.bg_color=Color('#e8d5ac') if not primary else Color('#874b34')
		elif state=='pressed':box.bg_color=Color('#c4a873') if not primary else Color('#5e3429')
		elif state=='disabled':box.bg_color=Color('#c9b58b');box.border_color=Color('#b09a70')
		box.set_border_width_all(0 if close else 2)
		box.set_content_margin(SIDE_LEFT,12);box.set_content_margin(SIDE_RIGHT,12)
		control.add_theme_stylebox_override(state,box)
	var focus=StyleBoxFlat.new()
	focus.bg_color=Color.TRANSPARENT;focus.border_color=INK;focus.set_border_width_all(2);focus.anti_aliasing=false
	focus.expand_margin_left=2;focus.expand_margin_right=2;focus.expand_margin_top=2;focus.expand_margin_bottom=2
	control.add_theme_stylebox_override('focus',focus)
	for state in ['font_color','font_hover_color','font_pressed_color']:
		control.add_theme_color_override(state,Color('#fff0c8') if primary else INK)
	control.add_theme_color_override('font_disabled_color',Color('#746549'))
