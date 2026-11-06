extends RefCounted
## Six approved UI sprites. Originals remain intact; palette is applied at display time.
const Catalog=preload('res://scripts/data/catalog.gd')
static var preset: Dictionary=Catalog.presentation('ui')
static var FILES=preset.roman_icons
const PALETTE=preload('res://shaders/roman_ui.gdshader')
static var material: ShaderMaterial

static func icon(parent: Node,id: String,pos: Vector2,dimensions: Vector2) -> TextureRect:
	if material==null:
		material=ShaderMaterial.new()
		material.shader=PALETTE
	var image=TextureRect.new()
	image.name='Roman_'+id
	image.texture=load(FILES[id])
	image.position=pos
	image.size=dimensions
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	image.mouse_filter=Control.MOUSE_FILTER_IGNORE
	image.material=material
	parent.add_child(image)
	return image

static func on_button(button: Button,id: String,side: float=-1.0,with_text: bool=false) -> TextureRect:
	if side<0: side=preset.icon_side
	var pos=Vector2(preset.icon_text_left,(button.size.y-side)/2) if with_text else (button.size-Vector2.ONE*side)/2
	var image=icon(button,id,pos.round(),Vector2.ONE*side)
	if with_text:
		for state in ['normal','hover','pressed','disabled']:
			var box=button.get_theme_stylebox(state).duplicate()
			box.set_content_margin(SIDE_LEFT,side+preset.icon_margin_left)
			box.set_content_margin(SIDE_RIGHT,preset.icon_margin_right)
			button.add_theme_stylebox_override(state,box)
	return image
