extends 'res://tests/strategy/test_contextual_ui.gd'
const Art=preload('res://scripts/strategy/static_art.gd')
func action_texture(ui,id: String) -> Texture2D:
	return ui.actions[id].find_children('*','TextureRect',true,false)[0].texture
func image_id(texture: Texture2D) -> String:
	return texture.atlas.resource_path.get_file().get_basename() if texture is AtlasTexture else texture.resource_path.get_file().get_basename()
func run():
	var main=load('res://scenes/main.tscn').instantiate();main.settings_path='/tmp/static-art-ui.cfg'
	root.add_child(main);main.sound.enabled=false
	for i in 4:await process_frame
	click(main.menu_view.get_node('%TacticalTrial').get_global_rect().get_center())
	for i in 4:await process_frame
	var t=main.active_trial;t.set_process(false);var r=t.rules;var ui=t.get_meta('strategy_interface')
	check(r.get_script().resource_path=='res://scripts/strategy/battle.gd','Normal menu enters the current strategy game')
	check(r.projection==Transform2D.IDENTITY,'Camera remains top-down without ground compression')
	check(r.population()==9 and r.stock.food==10000.,'Art integration preserves the opening economy')
	var soldier=r.alive('ally').filter(func(u):return u.unit_type=='shield')[0]
	check(t.field.regiments[soldier.art].ally.get_size().x>64,'Field infantry still has its original multi-frame animation sheet')
	var barracks=r.buildings[1]
	click(point(t,barracks.pos));await process_frame;await process_frame
	check(image_id(action_texture(ui,'train:engineer'))=='U02','Engineer production uses its own art, not the villager or medic')
	check(image_id(action_texture(ui,'train:spear'))=='U03','Level-one spear production uses new level-one art')
	await snap('art-production-level1',t)
	r.level=5;await process_frame;await process_frame
	check(image_id(action_texture(ui,'train:spear'))=='U07','Promotion refreshes the actual production button to level five')
	check(image_id(action_texture(ui,'train:shield'))=='U12','Shield production independently follows the same promotion')
	await snap('art-production-level5',t)
	key(KEY_ESCAPE)
	var worker=r.alive('ally').filter(func(u):return u.unit_type=='villager')[0]
	click(point(t,worker.pos)-Vector2(0,20));await process_frame;await process_frame
	check(image_id(action_texture(ui,'build:town'))=='B01','Construction button uses new town artwork')
	var before_obstacles=r.terrain.ROCKS.duplicate()
	r.town_level=3;await process_frame;await process_frame
	check(image_id(action_texture(ui,'build:town'))=='B03','Construction buttons refresh to available third-tier town art')
	check(r.terrain.ROCKS==before_obstacles,'Visual variants do not resize the existing navigation obstacles')
	await snap('art-buildings-level3',t)
	var art=Art.new();var rect=art.sprite_rect('B07',Vector2.ZERO,102.4)
	check(is_equal_approx(rect.size.x/rect.size.y,192./160.),'Non-square range artwork keeps its aspect ratio')
	check(art.icon('U03').get_size()==Art.REGIONS.U03.size,'Transparent spear margins are cropped for readable icons')
	check(art.unit_id('ram')=='','Unprovided siege animations retain the existing fallback')
	check(art.unit_id('elite_cavalry',5)=='U23','Elite cavalry uses its separate supplied design')
	key(KEY_ESCAPE);t.toggle_overview();await snap('art-overview',t)
	print('STATIC ART CHECKS=',checks,' FAILURES=',failures)
	t.queue_free();main.queue_free();await process_frame;await create_timer(.2).timeout;quit(1 if failures else 0)
