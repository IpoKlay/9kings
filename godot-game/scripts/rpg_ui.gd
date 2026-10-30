extends RefCounted
const Catalog=preload('res://scripts/data/catalog.gd')
# Full paper bounds in the existing 4x book sprite; the cover and spine stay still.
const BOOK_PAGES=[Rect2(20,0,492,584),Rect2(552,0,492,584)]
static var textures: Dictionary={}
static var styles: Dictionary={}

static func reduced_motion() -> bool:
	return DisplayServer.get_name()!='headless' and DisplayServer.accessibility_should_reduce_animation()>0

static func texture(id: String) -> Texture2D:
	if textures.has(id): return textures[id]
	var preset=Catalog.presentation('ui')
	var source: Texture2D=load(preset.rpg_sheet)
	var image=source.get_image().get_region(Rect2i(preset.rpg_regions[id]))
	var scale=int(preset.rpg_scales[id])
	image.resize(image.get_width()*scale,image.get_height()*scale,Image.INTERPOLATE_NEAREST)
	textures[id]=ImageTexture.create_from_image(image)
	return textures[id]

static func box(id: String,tone: String='paper') -> StyleBoxTexture:
	var key=id+':'+tone
	if styles.has(key): return styles[key]
	var preset=Catalog.presentation('ui')
	var result=StyleBoxTexture.new()
	var source_id='button' if id=='toolbar' else id
	result.texture=texture(source_id)
	result.modulate_color=preset.rpg_tints[tone]
	var margins: Vector4=preset.rpg_margins[source_id]*int(preset.rpg_scales[source_id])
	if id=='toolbar': result.axis_stretch_horizontal=StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		result.set_texture_margin(side,margins[side])
		result.set_content_margin(side,12)
	styles[key]=result
	return result

static func button(control: Button,id: String='strip',selected: bool=false):
	var preset=Catalog.presentation('ui')
	control.add_theme_stylebox_override('normal',box(id,'selected' if selected else 'paper'))
	control.add_theme_stylebox_override('hover',box(id,'hover'))
	control.add_theme_stylebox_override('pressed',box(id,'pressed'))
	control.add_theme_stylebox_override('disabled',box(id,'disabled'))
	var focus=StyleBoxFlat.new()
	focus.bg_color=Color.TRANSPARENT
	focus.border_color=Color('#e9c781')
	focus.set_border_width_all(2)
	control.add_theme_stylebox_override('focus',focus)
	control.add_theme_color_override('font_color',Color('#fff0c5') if selected else preset.rpg_ink)
	control.add_theme_color_override('font_hover_color',preset.rpg_ink)
	control.add_theme_color_override('font_pressed_color',Color('#fff0c5'))
	control.add_theme_color_override('font_disabled_color',Color('#43483d'))

static func picture(parent: Control,id: String,pos: Vector2,tone: String='paper') -> TextureRect:
	var control=TextureRect.new()
	control.texture=texture(id)
	control.position=pos
	control.size=control.texture.get_size()
	control.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	control.self_modulate=Catalog.presentation('ui').rpg_tints[tone]
	control.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(control)
	return control
