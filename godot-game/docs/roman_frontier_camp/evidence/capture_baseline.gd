extends SceneTree
## Stage 1: render existing assets in an isolated fixture; never write player state.
const OUT = 'res://docs/roman_frontier_camp/evidence/'
const Campaign = preload('res://scripts/campaign.gd')
const Field = preload('res://scripts/battlefield.gd')
var view: SubViewport
var field
var game
func _init(): call_deferred('run')
func capture(name: String):
	field.refresh()
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	var pixels = view.get_texture().get_image()
	assert(pixels.get_size() == Vector2i(960, 540))
	assert(pixels.save_png(OUT + name + '.png') == OK)
func run():
	var host = Window.new()
	root.add_child(host)
	view = SubViewport.new()
	view.size = Vector2i(960, 540)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	host.add_child(view)
	game = Campaign.new(23)
	game.skip()
	field = Field.new()
	field.game = game
	field.translated = game.rules.zh
	field.scale = Vector2(0.5, 0.5)
	view.add_child(field)
	await capture('baseline-iberia-native-960')
	game.g.buildings.clear()
	var types = ['legion','archer','spear','guard','cavalry','medic','siege','legion','archer','spear','guard','legion']
	for cell in types.size():
		game.g.buildings.append({'id':cell+1,'cell':cell,'type':types[cell],'level':3})
	await capture('baseline-dense-fixture-960')
	print('Stage 1: two existing-field renders captured at 960x540; dense layout is an audit fixture, not a new playable camp.')
	quit()
