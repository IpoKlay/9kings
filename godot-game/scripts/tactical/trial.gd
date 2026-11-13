extends Control
signal closed
signal resolved
var pilot=false
var result_recorded=false
const Paper=preload('res://scripts/rpg_ui.gd')
const INK=Color('#382f25')
const PassBattle=preload('res://scripts/tactical/pass_battle.gd')
const SquareBattle=preload('res://scripts/tactical/square_battle.gd')
const WhiteboardBattle=preload('res://scripts/tactical/whiteboard_battle.gd')
const SiegeBattle=preload('res://scripts/tactical/siege_battle.gd')
@onready var siege_button: Button=$BattleHUD/DeploymentActions/SiegeButton
@onready var cavalry_variant_button: Button=$BattleHUD/DeploymentActions/CavalryVariantButton
@onready var archer_variant_button: Button=$BattleHUD/DeploymentActions/ArcherVariantButton
@onready var legion_variant_button: Button=$BattleHUD/DeploymentActions/LegionVariantButton
@onready var guard_variant_button: Button=$BattleHUD/DeploymentActions/GuardVariantButton
@onready var spear_variant_button: Button=$BattleHUD/DeploymentActions/SpearVariantButton
var loadout_buttons={}
@onready var blink_button: Button=$BattleHUD/BattleActions/BlinkButton
@onready var volley_button: Button=$BattleHUD/BattleActions/VolleyButton
@onready var defender_button: Button=$BattleHUD/DeploymentActions/DefenderButton
@onready var replay_button: Button=$BattleHUD/Results/ReplayButton
@onready var assault_button: Button=$BattleHUD/BattleActions/AssaultButton
@onready var flag_alert: Label=$BattleHUD/StatusGroup/FlagAlert
@onready var strength_bar: ColorRect=$BattleHUD/TopActions/StrengthBar
@onready var ally_bar: ColorRect=$BattleHUD/TopActions/StrengthBar/AllyBar
@onready var pace_button: Button=$BattleHUD/TopActions/SpeedButton
@onready var overview_button: Button=$BattleHUD/TopActions/OverviewButton
var slow=false
var oil_index=-1
var roster: Array=[]
const Field=preload('res://scripts/tactical/trial_field.gd')
var rules=PassBattle.new()
var app
var field
var pointer=Vector2(-1000,-1000)
var squad_ids: Array=[]
var soldier_ids: Array=[]
var type_gesture=false
var regiment_gesture=false
var camera_offset=Vector2.ZERO
var zoom=1.0
var detail_view: Dictionary={}
var drag_select=false
var drag_origin=Vector2.ZERO
var drag_end=Vector2.ZERO
var gesture=false
var placing_rank=false
var drawing_wall=false
var rank_dragged=false
var rank_start=Vector2.ZERO
var rank_end=Vector2.ZERO
var rank_screen_start=Vector2.ZERO
@onready var setup_button: Button=$BattleHUD/DeploymentActions/VanguardButton
@onready var combined_button: Button=$BattleHUD/DeploymentActions/CombinedButton
var box_gesture=false
var dragged=false
var camera_at_press=Vector2.ZERO
@onready var controls: Label=$BattleHUD/HelpGroup/Controls
var draft_waypoints: Array[Vector2]=[]
var selected='legion':
	set(value):
		draft_waypoints.clear()
		selected=value
var paused=false
@onready var status: Label=$BattleHUD/StatusGroup/Status
@onready var hint: Label=$BattleHUD/StatusGroup/Hint
var buttons={}
@onready var character_picker: OptionButton=$BattleHUD/TopActions/CharacterPicker
var character_ids: Array[String]=[]
@onready var power_note: Label=$BattleHUD/HelpGroup/PowerNote
var portrait_id=''
@onready var portrait: TextureRect=$BattleHUD/TopActions/Portrait
@onready var start_button: Button=$BattleHUD/BattleActions/StartButton
@onready var result: Label=$BattleHUD/Results/Result
@onready var recap: Label=$BattleHUD/Results/Recap
@onready var order_strip: Label=$BattleHUD/BattleActions/OrderStrip
var journal_cursor=0
var rout_alerts: Array[Dictionary]=[]
var rout_notice_left=0.0
var accumulator=0.0
## Catch-up budget. One step stays authoritative (1/60 s); the ceiling only bounds how many
## steps a single frame may buy, so a slow step cannot multiply into an unbounded frame.
## Two steps still keeps real time on a 30 Hz display; below that the simulation runs in
## deliberate slow motion instead of freezing the frame. Unaffordable whole steps are dropped
## rather than carried, which stops the loop from locking at the maximum forever.
const SIM_STEP=1.0/60
const MAX_SIM_STEPS_PER_FRAME=2
## Once a single step costs more than a frame, buying two of them only stretches the frame.
## The measured step cost therefore drops the allowance back to one step.
const EXPENSIVE_STEP_MS=22.0
## Opt-in diagnostic: dropping backlog changes real-time simulation speed.
var bounded_catchup=false
var last_step_ms=0.0
var notice=''
var notice_seconds=0.0
var myth_audio=preload('res://scripts/tactical/myth_audio.gd').new()
func words(zh: String,en: String) -> String:
	return zh if app==null or app.language=='zh' else en
func skill_text(zh: String, en: String) -> String:
	var values=rules.power_config().duplicate()
	values.reduction_percent=roundi(float(values.get('reduction',0))*100)
	values.bonus_percent=roundi((float(values.get('archer_bonus',1))-1)*100)
	values.slow_percent=roundi((1-float(values.get('slow',1)))*100)
	return words(zh,en).format(values)
func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	theme=preload('res://assets/fonts/game_pixel_theme.tres')
	var viewport=SubViewport.new()
	viewport.size=Vector2i(960,540)
	viewport.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	field=Field.new()
	field.trial=self
	field.scale=Vector2(.5,.5)
	viewport.add_child(field)
	var screen=TextureRect.new()
	screen.texture=viewport.get_texture()
	screen.size=Vector2(1920,1080)
	screen.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	move_child(screen,0)
	$BattleHUD/TopActions/HelpButton.pressed.connect(func():
		controls.visible=not controls.visible
		power_note.visible=controls.visible)
	overview_button.pressed.connect(toggle_overview)
	var pause_button: Button=$BattleHUD/TopActions/PauseButton
	pause_button.text=words('暂停','Pause')
	pause_button.pressed.connect(func():paused=not paused)
	var menu_button: Button=$BattleHUD/TopActions/MenuButton
	menu_button.text=words('返回','Back') if pilot else words('菜单','Menu')
	menu_button.pressed.connect(closed.emit)
	character_picker.get_popup().add_theme_stylebox_override('panel',Paper.box('paper'))
	character_picker.get_popup().add_theme_stylebox_override('hover',Paper.box('toolbar','selected'))
	character_picker.get_popup().add_theme_color_override('font_color',INK)
	character_picker.get_popup().add_theme_color_override('font_hover_color',Color('#fff0c5'))
	character_picker.get_popup().add_theme_color_override('font_separator_color',INK)
	character_picker.get_popup().add_theme_font_size_override('font_size',22)
	character_picker.clear()
	var last_category=''
	for row in rules.characters:
		if row.category!=last_category:
			character_picker.add_separator(words(row.category,{'神明':'Gods','英雄':'Heroes','怪物':'Creatures'}[row.category]))
			character_ids.append('')
			last_category=row.category
		character_picker.add_item(words(row.name,row.name_en))
		character_ids.append(row.id)
	character_picker.item_selected.connect(func(index):choose_deity(character_ids[index]))
	for kind in ['legion','archer','cavalry','spear','guard','medic','siege']:
		var reserve_button: Button=$BattleHUD/ReserveActions.get_node(kind.capitalize()+'Button')
		buttons[kind]=reserve_button
		reserve_button.pressed.connect(arm_reserve.bind(kind))
	loadout_buttons={'legion':legion_variant_button,'guard':guard_variant_button,'spear':spear_variant_button,'archer':archer_variant_button,'cavalry':cavalry_variant_button}
	for kind in loadout_buttons:loadout_buttons[kind].pressed.connect(cycle_loadout.bind(kind))
	blink_button.pressed.connect(arm_blink)
	volley_button.pressed.connect(arm_volley)
	combined_button.text=words('七兵种布阵','All seven arms')
	combined_button.pressed.connect(func():
		if rules.deploy_combined():
			rules.defender_preset=false
			selected=''
			reset_camera())
	setup_button.text=words('标准布阵','Vanguard')
	setup_button.pressed.connect(func():
		if rules.deploy_vanguard():
			rules.defender_preset=false
			selected='')
	setup_button.tooltip_text=words('步兵在前，弓兵在后，骑兵守侧翼。各留一队弓兵和骑兵。','Infantry front, archers behind, cavalry on the wing. Keep one archer and one cavalry in reserve.')
	defender_button.text=words('山口守卫战','Hold the Pass')
	siege_button.text=words('攻城演练','Siege drill')
	siege_button.pressed.connect(func():
		rules=SiegeBattle.new(false)
		field.effects.clear();field.load_battlefield()
		squad_ids.clear();soldier_ids.clear();selected=''
		reset_camera();refresh())
	defender_button.pressed.connect(func():
		if rules is SquareBattle:
			rules=PassBattle.new(false)
			field.load_battlefield()
			reset_camera()
		if rules.deploy_defenders():
			selected=''
			set_camera(Vector2(-120,110)))
	defender_button.tooltip_text=words('盾兵列阵，弓兵点油，预备骑兵听令救援。可在开战前调整阵位。','Form the shield line, ignite oil with archers and keep cavalry in reserve. Reposition before starting.')
	replay_button.text=words('再战山口','Replay pass')
	replay_button.pressed.connect(func():
		retry()
		defender_button.pressed.emit()
		refresh())
	pace_button.text='1×'
	pace_button.pressed.connect(func():slow=not slow)
	assault_button.text=words('全军进攻','All attack')
	assault_button.pressed.connect(func():
		if selected=='route':selected=''
		rules.command(rules.alive('ally').map(func(u):return u.id),'auto',Vector2.ZERO))
	buttons.lightning=$BattleHUD/BattleActions/PowerButton
	buttons.lightning.pressed.connect(arm_power)
	start_button.pressed.connect(start_or_hold)
	add_child(myth_audio)
	reset_camera()
	refresh()
func start_or_hold():
	match rules.phase:
		'deploy':
			if rules.start():
				oil_index=-1
				placing_rank=false
				selected=''
				if app!=null:app.sound.play_rally()
		'battle':
			if selected in ['route','personal_route']:selected=''
			command_selection('hold',Vector2.ZERO)
		'victory','defeat','timeout':
			if pilot:closed.emit()
			else:retry()

func select_regiment(index: int):
	var army=rules.units.filter(func(u):return u.side=='ally')
	$BattleHUD/RegimentRoster.visible=not army.is_empty() and rules.phase in ['battle','deploy']
	if index<army.size() and not army[index].escaped and army[index].hp>0:
		soldier_ids.clear()
		squad_ids=[army[index].id]
		selected='route' if rules.phase=='battle' and not army[index].routing else ''

func arm_blink():
	if rules.phase=='battle' and not rules.Blink.ready(rules,selected_people()).is_empty():selected='blink'
	refresh()

func arm_volley():
	if rules.phase!='battle':return
	if not rules.Volley.ready(rules,selected_people()).is_empty():selected='volley'
	else:notice=words('需要已就绪的长弓兵','Select ready longbowmen');notice_seconds=2

func cycle_loadout(kind: String):
	rules.cycle_variant(kind);refresh()

func loadout_name(kind: String,base: String,compact: bool=false) -> String:
	var variant: Dictionary=rules.config.unit_variants.get(rules.selected_variant(kind),{})
	if variant.is_empty():return base
	return words(variant.name_short,variant.name_short_en) if compact else words(variant.name,variant.name_en)

func unit_name(u: Dictionary) -> String:
	var variant: Dictionary=rules.config.unit_variants.get(u.get('archetype',''),{})
	if not variant.is_empty():return words(variant.name,variant.name_en)
	return words(rules.config.types[u.kind].get('name',u.kind),u.kind)

func arm_reserve(kind: String):
	if rules.reserve.get(kind,0)<=0:return
	selected=kind
	squad_ids.clear()
	soldier_ids.clear()
	placing_rank=false

func rank_slots() -> Dictionary:
	return rules.layout_positions(squad_ids,rank_start,rank_end,rank_dragged)

func displayed_order(u: Dictionary) -> String:
	var living=u.soldiers.filter(func(s):return s.hp>0)
	if living.is_empty() or not rules.Soldiers.independent(u):return u.order
	if living.any(func(s):return s.has('charge_run')):return 'charge'
	var order: String=living[0].personal_order
	return order if living.all(func(s):return s.personal_order==order) else 'mixed'

func order_text(u: Dictionary) -> String:
	if u.routing:return words('失去指挥','No command')
	if u.soldiers.any(func(s):return s.hp>0) and u.soldiers.all(func(s):return s.hp<=0 or s.get('shield_wall',false)):return words('盾墙','Shield wall')
	if u.obstruction=='contact':return words('行军','March')
	match displayed_order(u):
		'charge':return words('冲锋','Charge')
		'mixed':return words('分队执行','Split orders')
		'move':return words('行军','March')
		'attack_move':return words('攻击移动','Attack move')
		'hold':return words('坚守','Hold')
		'idle':return words('待机','Idle')
		'attack':return words('集火','Focus fire')
	return words('自动','Auto')

func state_text(u: Dictionary) -> String:
	if u.hp<=0:return words('阵亡','Lost')
	if u.routing:return words('溃退','Routing')
	var order=displayed_order(u)
	if order=='charge':return words('冲锋中','Charging')
	if order=='mixed':return words('各兵执行当前军令','Soldiers following individual orders')
	if order=='attack_move':return words('交战 · 随后继续前进','Engaged · Resume march afterward') if u.engaged else words('搜索前进','Advancing and searching')
	if u.obstruction=='contact':return words('受阻 · 已接敌','Blocked · Engaged')
	if u.obstruction=='queue':return words('受阻 · 等待前队','Blocked · Queued')
	if u.stun>0 or u.petrified>0 or (order=='move' and u.rooted>0):return words('受阻 · 无法行动','Blocked · Immobilized')
	if order=='move':
		var goal: Vector2=u.destination if u.waypoints.is_empty() else u.waypoints.back()
		if not rules.inside_flag(u) and goal.distance_to(rules.flag_center)<=rules.flag_radius:return words('回防军旗','Returning to flag')
		return words('行军','Marching')
	if u.engaged:return words('救治','Healing') if u.kind=='medic' else words('交战','Engaged')
	if order=='hold':return words('守住阵位','Holding position')
	if order=='idle':return words('警戒附近敌人','Watching nearby enemies')
	if order=='attack':return words('接近目标','Closing on target')
	if u.moving:return words('行军','Marching')
	return words('待敌','Ready')

func event_text(e: Dictionary) -> String:
	match e.kind:
		'captured':
			var who=words('敌军','Enemy')
			var action=words('累计独占',' held the flag for a total of ') if e.contested else words('连续独占',' held the flag uninterrupted for ')
			return who+action+str(e.seconds).trim_suffix('.0')+words(' 秒',' s')+(words('，侧道敌骑参与夺旗',' · flank cavalry present') if e.flank else '')
		'relieved':return words('敌军离开旗区，%.1f 秒夺旗进度清零','Enemy left the flag zone, clearing %.1f s of capture')%e.seconds
		'general_rout':return words('我军将领方阵溃退','Our command regiment routed') if e.side=='ally' else words('敌方将领方阵溃退','Enemy command regiment routed')
		'last_regiment':
			var army=words('敌军最后一队','Last enemy regiment') if e.side=='enemy' else words('守军最后一队','Last defending regiment')
			return army+(words('溃退',' routed') if e.routed else words('被击破',' destroyed'))
		'held_line':return words('守城到时仍有 %d 支守军方阵','%d defending regiments stood when time expired')%e.count
		'flag_contested':return words('守军入圈，夺旗进度停在 %.1f 秒','Defenders contested the flag at %.1f s of capture')%e.seconds
		'rear_archers':return words('我军骑兵从背面冲击敌弓兵，造成 %.1f 点伤害','Our cavalry charged the archers from behind for %.1f damage')%e.damage
		'flank_through':return words('敌骑穿过侧道','Enemy cavalry broke through the side pass')
		'flank_divert':return words('敌骑转攻正面','Enemy cavalry diverted to the main pass')
		'flag_threat':return words('敌军进入旗区','Enemy entered the flag zone')
		'flank_signal':return words('侧道敌骑集结','Enemy cavalry assembled at the side pass')
		'deployed':return words('守军以 %d 支方阵开战','Defenders opened with %d regiments')%e.count
	return ''

func refresh():
	var character=rules.characters.filter(func(c):return c.id==rules.deity)[0]
	if portrait_id!=rules.deity:
		portrait_id=rules.deity
		var frame: AtlasTexture=field.animations[rules.deity].get_frame_texture('action',2)
		var cropped=AtlasTexture.new()
		cropped.atlas=frame.atlas
		var used=frame.atlas.get_image().get_region(Rect2i(frame.region)).get_used_rect()
		cropped.region=Rect2(frame.region.position+Vector2(used.position),Vector2(used.size))
		portrait.texture=cropped
		character_picker.select(character_ids.find(rules.deity))
	character_picker.disabled=rules.phase!='deploy' and not (rules.phase=='battle' and rules.unlimited_powers)
	power_note.text=words(character.power,character.power_en)+'\n'+skill_text(character.summary,character.summary_en)
	character_picker.tooltip_text=skill_text(character.description,character.description_en)
	buttons.lightning.tooltip_text=character_picker.tooltip_text
	status.text='%02d:%02d   '%[int(rules.elapsed)/60,int(rules.elapsed)%60]+words('我军 %d · 敌军 %d','Allies %d · Foes %d')%[rules.alive('ally').size(),rules.alive('enemy').size()]
	hint.text=words('在虚线区点击部署','Click inside the marked zone to deploy') if rules.phase=='deploy' else ''
	if selected=='lightning' and rules.phase=='battle':
		hint.text=words(character.power,character.power_en)+words(' · 点击落点',' · Choose a target')
	setup_button.visible=not pilot and rules.phase=='deploy' and rules.alive('ally').is_empty()
	combined_button.visible=setup_button.visible
	if rules is SquareBattle:setup_button.visible=false
	defender_button.visible=not pilot and rules.phase=='deploy' and rules.alive('ally').is_empty()
	siege_button.visible=defender_button.visible and rules is SquareBattle
	if rules.phase=='deploy' and not squad_ids.is_empty():
		hint.text=words('右键移动 · 右拖拉出阵线 · R 收回','Right click to reposition · Right drag a line · R to reserve')
	elif rules.phase=='deploy' and not setup_button.visible:
		hint.text=words('点选或 Shift 框选已部署部队，可重新布阵','Select or Shift-box deployed squads to reposition')
	if paused:hint.text=words('已暂停 · 空格继续','PAUSED · Space to resume')
	var names={'legion':words('步兵','Infantry'),'archer':words('弓兵','Archers'),'cavalry':words('骑兵','Cavalry'),'spear':words('长矛兵','Spears'),'guard':words('重盾卫','Guards'),'medic':words('军医','Medics'),'siege':words('投石机','Onagers')}
	for kind in loadout_buttons:
		var button: Button=loadout_buttons[kind]
		button.visible=not pilot and rules.phase=='deploy' and rules.reserve.get(kind,0)>0
		button.text=names[kind]+words('配置：',': ')+loadout_name(kind,names[kind])
		button.tooltip_text=words('点击切换下次部署的兵种；已部署部队保留原配置','Cycle the next deployment; already deployed squads keep their loadout')
	var blink_people=rules.Soldiers.members(rules,selected_people())
	var blink_ready=rules.Blink.ready(rules,selected_people()).size()
	blink_button.visible=rules.phase=='battle' and not blink_people.is_empty() and blink_people.all(func(row):return rules.Blink.capable(rules,row))
	blink_button.disabled=blink_ready==0
	blink_button.text=words('B 闪现','B Blink')+' %d/%d'%[blink_ready,blink_people.size()]
	if blink_button.visible and blink_ready==0:
		var remaining=8.
		for row in blink_people:remaining=minf(remaining,row.actor.get('blink_cooldown',0.))
		blink_button.text+=' %ds'%ceili(remaining)
	var volley_people=rules.Soldiers.members(rules,selected_people()).filter(func(row):return rules.Volley.capable(rules,row))
	var volley_ready=rules.Volley.ready(rules,selected_people()).size()
	volley_button.visible=rules.phase=='battle' and not volley_people.is_empty()
	volley_button.disabled=volley_ready==0
	volley_button.text=words('V 齐射','V Volley')+' %d/%d'%[volley_ready,volley_people.size()]
	if volley_ready==0 and not volley_people.is_empty():
		var cooldown_left=INF
		for row in volley_people:cooldown_left=minf(cooldown_left,row.actor.get('volley_cooldown',0.))
		volley_button.text+=' %ds'%ceili(cooldown_left)
	for kind in names:
		var active: bool=selected==kind
		if buttons[kind].get_meta('active',false)!=active:
			buttons[kind].theme_type_variation=&"HudSelected" if active else &""
			buttons[kind].set_meta('active',active)
		buttons[kind].text=loadout_name(kind,names[kind],true)+' ×'+str(int(rules.reserve.get(kind,0)))
		buttons[kind].visible=rules.phase in ['deploy','battle']
		buttons[kind].disabled=rules.reserve.get(kind,0)<=0
	var aiming=selected=='lightning'
	if buttons.lightning.get_meta('active',false)!=aiming:
		buttons.lightning.theme_type_variation=&"HudSelected" if aiming else &""
		buttons.lightning.set_meta('active',aiming)
	buttons.lightning.text=words('神力','Cast')+(' ∞' if rules.unlimited_powers else ' ×'+str(rules.charges)+(' %ds'%ceili(rules.cooldown) if rules.cooldown>0 else ''))
	buttons.lightning.visible=rules.phase in ['deploy','battle']
	if rules.phase=='deploy':start_button.text=words('开战','Begin')
	start_button.disabled=rules.phase=='deploy' and rules.alive('ally').is_empty()
	controls.text=words('左拖移图 · Shift 拖框选队 · 右键移动或集火\nX 攻击移动 · F 划盾墙 · C 冲锋 · V 齐射 · B 闪现 · H 坚守 · A 自动 · 方向键／中键移镜','Drag to pan · Shift-drag select · RMB move / focus\nX attack move · F shield line · C charge · V volley · B blink · H hold · A auto · Arrows / MMB pan')
	overview_button.visible=rules is SquareBattle
	overview_button.text=words('总览 Tab','Map · Tab') if zoom>.65 else words('返回 Tab','Back · Tab')
	if rules is SquareBattle:controls.text+=words(' · Tab 总览',' · Tab map view')
	if rules.phase=='battle':
		start_button.tooltip_text=words('短三角为阵面。盾兵坚守时保持当前朝向。','The triangle marks the front. Holding shield infantry keep their heading.')
		start_button.text=words('坚守','Hold')+' ×'+str(squad_ids.size())
		start_button.disabled=squad_ids.is_empty()
	result.visible=rules.phase in ['victory','defeat','timeout']
	recap.visible=result.visible
	replay_button.visible=not pilot and result.visible and rules.defender_preset
	if result.visible:
		hint.text=''
		var event: Dictionary=rules.key_event()
		recap.visible=not event.is_empty()
		if recap.visible:
			recap.text='%02d:%02d   '%[int(event.time)/60,int(event.time)%60]+event_text(event)
		match rules.outcome:
			'enemy_routed':result.text=words('敌军已被击溃 · 胜利','Victory · Enemy army routed')
			'time_held':result.text=words('守城时间已到 · 军旗守住了','Victory · Standard held until time expired')
			'flag_lost':result.text=words('罗马军旗失守 · 战败','Defeat · The Roman standard fell')
			'defenders_routed':result.text=words('守军溃败 · 战败','Defeat · Defenders routed')
		start_button.disabled=false
		start_button.text=words('远征战报','Report') if pilot else words('重新布阵','Redeploy')
		if pilot and not result_recorded:
			result_recorded=true
			resolved.emit()
	assault_button.visible=rules.phase=='battle'
	pace_button.text='0.5×' if slow else '1×'
	var strength=rules.strength('ally')
	ally_bar.anchor_right=strength/maxf(1,strength+rules.strength('enemy'))
	var army=rules.units.filter(func(u):return u.side=='ally')
	var short_en={'legion':'Inf','archer':'Bow','cavalry':'Cav','spear':'Spr','guard':'Grd','medic':'Med','siege':'Siege'}
	while roster.size()<army.size():
		var row: HBoxContainer=$BattleHUD/RegimentRoster/RegimentRow
		var tab: Button=row.get_node('RegimentButton') if roster.is_empty() else row.get_node('RegimentButton').duplicate(0)
		if not roster.is_empty():row.add_child(tab)
		tab.pressed.connect(select_regiment.bind(roster.size()))
		roster.append(tab)
	for i in roster.size():
		var tab: Button=roster[i]
		tab.visible=i<army.size() and rules.phase in ['battle','deploy']
		if not tab.visible:continue
		var u=army[i]
		tab.disabled=u.escaped or u.hp<=0
		var tag=unit_name(u) if u.get('archetype','')!='' else words(names[u.kind],short_en[u.kind])
		if u.routing or u.hp<=0:tag=state_text(u)
		tab.text=str(i+1)+' '+tag
		if tab.get_meta('chosen',false)!=(u.id in squad_ids):
			tab.set_meta('chosen',u.id in squad_ids)
			tab.theme_type_variation=&"HudSelected" if u.id in squad_ids else &""
		tab.tooltip_text=(words('军营随征队 · ','Camp escort · ') if u.get('escort',false) else '')+(unit_name(u) if u.get('archetype','')!='' else names[u.kind])+' · '+order_text(u)+' · '+state_text(u)+' · '+words('士气 %d','Morale %d')%ceili(u.morale)
	var chosen=army.filter(func(u):return u.id in squad_ids)
	order_strip.visible=rules.phase=='battle' and not chosen.is_empty()
	if order_strip.visible:
		var u=chosen[0]
		var name=str(army.find(u)+1)+' '+(unit_name(u) if u.get('archetype','')!='' else names[u.kind])+(words(' · 随征',' · Escort') if u.get('escort',false) else '')
		var detail=state_text(u)
		if paused and u.order=='move' and u.obstruction=='' and not u.routing:detail=words('暂停 · 继续后行军','Paused · March on resume')
		elif paused:detail=words('暂停 · ','Paused · ')+detail
		order_strip.text=name+'   '+words('军令：','Order: ')+order_text(u)+'   '+detail
		if chosen.size()>1:order_strip.text+='  +%d'%(chosen.size()-1)
		var ready=chosen.filter(func(unit):return unit.hp>0 and not unit.routing)
		start_button.disabled=ready.is_empty()
		start_button.text=words('坚守','Hold')+' ×'+str(ready.size())
	if rules.phase=='battle' and not soldier_ids.is_empty():
		order_strip.visible=true;start_button.disabled=false
		start_button.text=words('坚守','Hold')+' ×'+str(soldier_ids.size())
		order_strip.text=words('已选 %d 名士兵 · 双击或下方队签选整队','%d soldiers selected · Double-click or use roster for regiment')%soldier_ids.size()
	if notice_seconds<=0 and not paused and selected!='lightning':
		if rules.phase=='deploy' and squad_ids.is_empty() and not rules.defender_preset:
			hint.text=words('保护鹰旗 · 敌军独占 %s 秒即失守 · 选择布阵或手动部署','Guard the standard · Enemy captures in %s s · Choose a formation or deploy')%str(rules.capture_seconds).trim_suffix('.0')
		elif rules.phase=='deploy' and rules.defender_preset and squad_ids.is_empty():
			hint.text=words('守旗三分钟 · 右键布置油桶 · 听号后封侧道或回防','Hold for 3 min · Right-click oil to place it · At the horn, block the side pass or fall back')
		elif rules.phase=='battle':
			hint.text=words('守住军旗三分钟或击溃敌军 · 右键油桶发射火箭','Guard the standard for 3 min or rout the enemy · Right-click oil for fire arrows')
	if rules is SquareBattle and notice_seconds<=0 and not paused and selected!='lightning':
		hint.text=words('下方 1/3 布阵 · 中间不可部署 · 开战后敌军主动进攻','Deploy in the bottom third · Neutral ground cannot be deployed into · Enemy attacks on Begin') if rules.phase=='deploy' else words('击溃敌军取得胜利 · 全军进攻或选择部队下令','Rout the enemy to win · All attack or select squads to give orders')
		if rules is SiegeBattle:hint.text=words('选中投石机，右键轰击墙段 · 五次命中打开缺口，再令步兵通过','Select catapults, right-click a wall · Five impacts open a breach for infantry')
		if rules is WhiteboardBattle and rules.phase=='deploy':hint.text=words('下方虚线内布阵 · 中央缓冲带不可部署 · Tab 全览 / 返回','Deploy below the lower dashed line · Central strip excludes deployment · Tab overview / return')
	flag_alert.visible=rules.flag_state!='secure' and rules.phase=='battle'
	if flag_alert.visible:
		var state=words('军旗告急','Flag threatened') if rules.flag_state=='capturing' else words('旗区争夺','Contested')
		flag_alert.text=state+'  %.1f / %s s'%[floorf((rules.capture_time+1e-8)*10)/10,str(rules.capture_seconds).trim_suffix('.0')]
		flag_alert.modulate=Color('#ffd294') if rules.flag_state=='contested' else Color('#ffac88')
	if selected in ['route','personal_route'] and rules.phase=='battle' and notice_seconds<=0:
		hint.text=words('Shift＋点击添加途经点 · 左键确认终点 · Esc 取消','Shift-click for waypoints · Click to march · Esc to cancel')
		if paused:hint.text=words('已暂停 · ','Paused · ')+hint.text
	if selected=='attack_move' and rules.phase=='battle':hint.text=words('攻击移动 · 点击终点，接敌作战后继续前进 · Esc 取消','Attack move · Click destination; fight on the way, then resume · Esc cancels')
	if selected=='blink' and rules.phase=='battle':hint.text=words('怨灵闪现 · 点击落点 · 单人最多 200 · 8 秒冷却 · Esc 取消','Wraith blink · Click destination · 200 per caster · 8 s cooldown · Esc cancels')
	if selected=='volley' and rules.phase=='battle':hint.text=words('长弓齐射 · 点击落点 · 15 秒冷却 · Esc 取消','Longbow volley · Click landing point · 15 s cooldown · Esc cancels')
	if selected=='charge' and rules.phase=='battle':hint.text=words('冲锋 · 点击目标方向 · 每人独立命中与冷却 · Esc 取消','Charge · Click a destination · Individual hits and cooldowns · Esc cancels')
	if selected=='shield_line' and rules.phase=='battle':hint.text=words('盾墙 · 左键拖出阵线，箭头为正面 · Esc 取消','Shield wall · LMB-drag the line; arrow shows facing · Esc cancels')
	if rules.phase=='battle' and selected in ['','route','personal_route','charge'] and notice_seconds<=0:
		var chargeable=rules.Soldiers.members(rules,selected_people()).filter(func(row):return rules.Soldiers.individual(rules,row.unit).get('can_charge',false))
		if not chargeable.is_empty():
			var ready_count=chargeable.filter(func(row):return rules.Charges.ready(rules,row.unit,row.actor)).size()
			var remaining=0.
			for row in chargeable:remaining=maxf(remaining,row.actor.get('charge_cooldown',0.))
			hint.text+=words(' · 冲锋就绪 %d/%d',' · Charge ready %d/%d')%[ready_count,chargeable.size()]
			if remaining>0:hint.text+=' %.1fs'%remaining
	if rules.phase=='battle' and rules.flank_state=='warning' and rules.flag_state=='secure':
		flag_alert.visible=true
		flag_alert.modulate=Color('#ffd294')
		flag_alert.text=words('侧道敌骑','Flank cavalry')+'  %d s'%ceili(maxf(0,rules.signal_time+rules.assault.warning_seconds-rules.elapsed))

	while journal_cursor<rules.journal.size():
		var entry=rules.journal[journal_cursor]
		journal_cursor+=1
		if entry.kind=='general_rout':rout_alerts.append(entry)
	if rules.phase=='battle' and not rout_alerts.is_empty():
		if rout_notice_left<=0:rout_notice_left=3
		hint.text=event_text(rout_alerts[0])
	# A rejected command must remain readable above mode instructions, including pause.
	if notice_seconds>0:hint.text=(words('已暂停 · ','Paused · ') if paused else '')+notice

func retry():
	for voice in impact_voices.values():voice.stop()
	voice_times.clear()
	charge_audio.clear();audio_clock=0.
	myth_audio.stop_all()
	var deity=rules.deity
	rules=WhiteboardBattle.new(rules.unlimited_powers) if rules is WhiteboardBattle else SiegeBattle.new(rules.unlimited_powers) if rules is SiegeBattle else SquareBattle.new(rules.unlimited_powers) if rules is SquareBattle else PassBattle.new(rules.unlimited_powers)
	field.load_battlefield()
	slow=false
	oil_index=-1
	rules.select_deity(deity)
	field.effects.clear()
	squad_ids.clear()
	soldier_ids.clear()
	gesture=false
	placing_rank=false
	drawing_wall=false
	drag_select=false
	reset_camera()
	selected='legion'
	paused=false
	accumulator=0
	result.text=''
	journal_cursor=0
	rout_alerts.clear()
	rout_notice_left=0
	notice_seconds=0
	notice=''
	start_button.text=words('开战','Begin')
	refresh()
signal contact_audio_started(contact: Dictionary)
signal sound_cue(cue: Dictionary)

var impact_voices: Dictionary={}
var voice_times: Dictionary={}
var audio_clock=0.
var charge_audio=preload('res://scripts/tactical/charge_audio.gd').new()
const CHARGE_CLIPS={
	'charge_hit0':preload('res://assets/combat_audio/charge/charge-hit-0.wav'),
	'charge_hit1':preload('res://assets/combat_audio/charge/charge-hit-1.wav'),
	'charge_hit2':preload('res://assets/combat_audio/charge/charge-hit-2.wav'),
	'charge_land':preload('res://assets/combat_audio/charge/charge-land.wav')}

func local_sound(layer: String, sample_name: String, ground: Vector2, gain: float, interval: float) -> bool:
	if app==null or not app.sound.enabled or app.sound.volume<=0:return false
	if layer in charge_audio.PRIORITY:return charge_audio.request(layer,sample_name,ground,gain)
	return start_local_sound(layer,sample_name,ground,gain,interval)

func flush_charge_audio():
	for cue in charge_audio.drain(audio_clock):
		start_local_sound(cue.layer,cue.sample,cue.pos,cue.gain,0.,cue.bus,CHARGE_CLIPS.get(cue.sample),1.)

func start_local_sound(layer: String,sample_name: String,ground: Vector2,gain: float,interval: float,bus: String='',clip: AudioStream=null,pitch: float=-1.) -> bool:
	if app==null or not app.sound.enabled or app.sound.volume<=0:return false
	if bus.is_empty():bus=layer
	if audio_clock-float(voice_times.get(bus,-10.))<interval:return false
	if not impact_voices.has(bus):
		var player:=AudioStreamPlayer2D.new()
		player.attenuation=0.
		player.max_distance=4000
		add_child(player)
		impact_voices[bus]=player
	var voice: AudioStreamPlayer2D=impact_voices[bus]
	voice_times[bus]=audio_clock
	voice.stop()
	voice.stream=clip if clip!=null else app.sound.cache[sample_name]
	voice.position=(field.project(ground)-camera_offset)*zoom
	voice.set_meta('gain',gain)
	voice.volume_linear=app.sound.volume*gain
	voice.pitch_scale=(pitch if pitch>0. else 1.)*(.78 if slow else 1.)
	voice.stream_paused=false
	voice.play()
	sound_cue.emit({'time':audio_clock,'file':voice.stream.resource_path,'gain':voice.volume_linear,'pitch':voice.pitch_scale,'layer':layer,'voice':bus})
	return true

func play_contact_audio(contact: Dictionary):
	if local_sound('main','impact'+str(int(contact.charge_id)%3),contact.pos,.94,.085):
		contact_audio_started.emit(contact)

func _process(dt: float):
	if not paused:audio_clock+=minf(dt,.1)
	for voice in impact_voices.values():
		voice.stream_paused=paused
		voice.volume_linear=app.sound.volume*voice.get_meta('gain',1.) if app!=null and app.sound.enabled else 0.
	notice_seconds=maxf(0,notice_seconds-dt)
	if rout_notice_left>0:
		rout_notice_left=maxf(0,rout_notice_left-dt)
		if rout_notice_left==0 and not rout_alerts.is_empty():rout_alerts.pop_front()
	var pan=Vector2(Input.get_axis('ui_left','ui_right'),Input.get_axis('ui_up','ui_down'))
	if pan!=Vector2.ZERO and not character_picker.get_popup().visible:
		set_camera(camera_offset+pan.normalized()*920*dt/zoom)
	pointer=field.unproject(field_point(get_local_mouse_position()))
	if paused:field.queue_redraw()
	if not squad_ids.is_empty():
		# One liveness pass per frame replaces the nested closure scan over every unit per id.
		var live={}
		for unit in rules.units:
			if unit.hp>0 and not unit.get('escaped',false):live[unit.id]=true
		var kept=[]
		for id in squad_ids:
			if live.has(id):kept.append(id)
		squad_ids=kept
		if selected=='route' and squad_at_id().is_empty():selected=''
	if not soldier_ids.is_empty():
		var kept_people=[]
		for row in rules.Soldiers.members(rules,soldier_ids):kept_people.append(Vector2i(row.unit.id,row.slot))
		soldier_ids=kept_people
		if soldier_ids.is_empty() and selected=='personal_route':selected=''
	myth_audio.advance(minf(dt,.1),paused,bool(app.prefs.enabled) if app!=null else true,float(app.prefs.volume) if app!=null else .7)
	if not paused:
		var battle_dt=minf(dt,.1)*(.5 if slow else 1.0)
		accumulator+=battle_dt
		var budget=(1 if last_step_ms>EXPENSIVE_STEP_MS else MAX_SIM_STEPS_PER_FRAME) if bounded_catchup else 2147483647
		var steps=0
		var clock=Time.get_ticks_usec()
		while accumulator>=SIM_STEP and steps<budget:
			rules.step(SIM_STEP)
			accumulator-=SIM_STEP
			steps+=1
		if steps>0:last_step_ms=(Time.get_ticks_usec()-clock)/float(steps)/1000.
		if steps>=budget and accumulator>=SIM_STEP:accumulator=fmod(accumulator,SIM_STEP)
		field.advance(battle_dt)
		for event in rules.events:
			if event.kind=='flank_signal':
				if app!=null:app.sound.play('horn',.85)
				continue
			if event.kind not in ['charge_tail','rider_contact','launch'] and not event.has('volley'):field.effect(event)
			if event.kind=='hoof_dust':
				local_sound('hoof','foot'+str(int(rules.elapsed*8)%3),event.pos,.27,.105)
				continue
			if event.kind in ['rider_contact','charge_tail']:
				# The shield clips are wooden-haft knocks, not metal armor.
				# Keep the primary collision sound without this extra clacking layer.
				continue
			if event.get('volley',false):
				local_sound('volley' if event.get('ability','')=='volley' else 'arrows','arrow0',event.get('from',event.pos),.54,.06 if event.get('ability','')=='volley' else .075)
				continue
			if event.kind=='arrow_impact':
				local_sound('arrow_hit','shield0' if event.get('blocked',false) else 'impact0',event.pos,.25,.075);continue
			if event.kind=='troll_slam':
				local_sound('slam','impact2',event.pos,.8,.16);continue
			if event.kind=='shaman_cast':
				local_sound('heal','impact0',event.pos,.16,.15);continue
			if event.kind=='shaman_heal':continue
			if event.kind in ['blink','scythe']:
				local_sound('spectral','impact0',event.pos,.20,.08)
				continue
			if event.kind=='launch':continue
			if event.kind=='stone_impact':
				local_sound('stone','impact2',event.pos,.80,.16)
				continue
			if myth_audio.handle_event(event):continue
			if event.has('contact'):
				play_contact_audio(event.contact)
				continue
			if (event.get('mounted_contact',false) or event.get('personal_charge',false)) and app!=null:
				local_sound('main','impact1',event.pos,.94,.085)
				continue
			if event.has('attacker_slot'):
				local_sound('melee','impact0',event.pos,.42,.065)
				continue
			if app!=null and event.kind!='heal':app.sound.play('arrow' if event.kind=='arrow' else 'impact',.5)
		rules.events.clear()
		flush_charge_audio()
	refresh()
func reset_camera():
	detail_view.clear()
	if rules is SquareBattle:
		zoom=field.Terrain.VIEW.default_zoom
		# Keep the deployment and the approach ahead visible at the original figure size.
		var focus=Vector2(1050,1180) if rules is SiegeBattle else rules.deployment.get_center()
		if rules is WhiteboardBattle:focus=rules.camera_focus()
		set_camera(rules.projection*focus-Vector2(960,530)/zoom)
	else:
		zoom=1.0
		set_camera(Vector2.ZERO)

func toggle_overview():
	if not rules is SquareBattle:return
	if rules is WhiteboardBattle:
		if detail_view.is_empty():
			detail_view={'zoom':zoom,'offset':camera_offset}
			zoom=overview_zoom()
			set_camera(rules.bounds.get_center()-Vector2(960,530)/zoom)
		else:
			zoom=detail_view.zoom
			set_camera(detail_view.offset)
			detail_view.clear()
		refresh()
		return
	if zoom>.65:
		detail_view={'zoom':zoom,'offset':camera_offset}
		zoom=.55
		set_camera(rules.projection*rules.bounds.get_center()-Vector2(960,530)/zoom)
	elif not detail_view.is_empty():
		zoom=detail_view.zoom
		set_camera(detail_view.offset)
		detail_view.clear()
	else:reset_camera()
	refresh()

func overview_zoom() -> float:
	var area: Rect2=rules.projection*rules.bounds
	return minf(1760.0/area.size.x,760.0/area.size.y)

func field_point(screen: Vector2) -> Vector2:
	return camera_offset+screen/zoom

func set_camera(offset: Vector2):
	var surface_rect: Rect2=field.LANDSCAPE
	var maximum=surface_rect.end-Vector2(1920,1080)/zoom
	camera_offset=offset
	for axis in 2:
		camera_offset[axis]=clampf(offset[axis],surface_rect.position[axis],maximum[axis]) if maximum[axis]>=surface_rect.position[axis] else (surface_rect.position[axis]+maximum[axis])*.5
	camera_offset=camera_offset.snapped(Vector2(2,2))
	field.get_viewport().canvas_transform=Transform2D(0,Vector2.ONE*zoom,0,-camera_offset*.5*zoom)
	field.queue_redraw()
	if is_instance_valid(field.pass_layout):field.pass_layout.queue_redraw()

func squad_at(screen: Vector2, side: String, centers_only: bool=false) -> Dictionary:
	var found: Dictionary={}
	var best=INF
	for unit in rules.alive(side):
		var feet: Vector2=(field.project(unit.pos)-camera_offset)*zoom
		var local=(screen-feet)/zoom
		var distance=Vector2(local.x,(local.y+35)*1.3).length()
		if (not centers_only or distance<90) and field.regiment_contains(unit,local) and distance<best:
			found=unit
			best=distance
	return found

func select_squads(screen: Vector2, additive: bool):
	selected=''
	if rules.phase=='battle':
		if not additive:soldier_ids.clear();squad_ids.clear()
		else:
			for u in rules.alive('ally'):
				if u.id not in squad_ids:continue
				for slot in u.soldiers.size():
					if u.soldiers[slot].hp>0 and Vector2i(u.id,slot) not in soldier_ids:soldier_ids.append(Vector2i(u.id,slot))
			squad_ids.clear()
		var hit=soldier_at(screen,'ally')
		if regiment_gesture and not hit.is_empty():
			soldier_ids.clear();squad_ids=[hit.unit.id];selected='route'
		else:
			var box=Rect2(drag_origin,screen-drag_origin).abs()
			for u in rules.alive('ally'):
				for slot in u.soldiers.size():
					if u.soldiers[slot].hp<=0:continue
					var point=(rules.Soldiers.point(rules,u,slot)-Vector2(0,20)-camera_offset)*zoom
					var chosen=box.has_point(point) if drag_select else (not hit.is_empty() and (u.get('unit_type',u.kind)==hit.unit.get('unit_type',hit.unit.kind) if type_gesture else u.id==hit.unit.id and slot==hit.slot))
					if chosen and Vector2i(u.id,slot) not in soldier_ids:soldier_ids.append(Vector2i(u.id,slot))
			if not soldier_ids.is_empty():selected='personal_route'
		field.queue_redraw();return
	if not additive:squad_ids.clear()
	if drag_select:
		var box=Rect2(drag_origin,screen-drag_origin).abs()
		for squad in rules.alive('ally'):
			if box.has_point((field.project(squad.pos)-Vector2(0,35)-camera_offset)*zoom) and squad.id not in squad_ids:
				squad_ids.append(squad.id)
	else:
		var squad=squad_at(screen,'ally')
		if not squad.is_empty():
			if squad.id not in squad_ids:squad_ids.append(squad.id)
			if rules.phase=='battle' and not additive:
				selected='route'
				notice_seconds=0
	field.queue_redraw()

func soldier_at(screen: Vector2,side: String) -> Dictionary:
	var found={};var best=INF
	for u in rules.alive(side):
		if rules.has_method('unit_visible') and not rules.unit_visible(u):continue
		var scale: float=rules.contact_profiles[u.kind].scale
		for slot in u.soldiers.size():
			if u.soldiers[slot].hp<=0:continue
			var foot: Vector2=rules.Soldiers.point(rules,u,slot)
			var local=screen/zoom+camera_offset-foot
			if not Rect2(-Vector2(18,46)*scale,Vector2(36,52)*scale).has_point(local):continue
			var distance=(local+Vector2(0,20)*scale).length_squared()
			if distance<best:best=distance;found={'unit':u,'slot':slot}
	return found

func selected_people() -> Array:
	if not soldier_ids.is_empty():return soldier_ids
	var ids=[]
	for u in rules.alive('ally'):
		if u.id in squad_ids:
			for slot in u.soldiers.size():
				if u.soldiers[slot].hp>0:ids.append(Vector2i(u.id,slot))
	return ids

func command_selection(order: String,point: Vector2,target_id: int=-1,target_slot: int=-1) -> bool:
	if not soldier_ids.is_empty():return rules.Soldiers.command(rules,soldier_ids,order,point,target_id,target_slot)
	return rules.command(squad_ids,order,point,target_id)

func personal_route_valid(goal: Vector2) -> bool:
	return rules.Soldiers.command(rules,soldier_ids,'move',goal,-1,-1,draft_waypoints,false)

func wall_preview(commit: bool=false) -> Dictionary:
	if not soldier_ids.is_empty():return rules.Soldiers.shield_line(rules,soldier_ids,rank_start,rank_end,commit)
	if commit:return {'ok':true} if rules.command_shield_line(squad_ids,rank_start,rank_end) else {}
	return rules.shield_layout(squad_ids,rank_start,rank_end)

func _notification(what):
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		placing_rank=false
		drawing_wall=false
		gesture=false
		drag_select=false

func _input(event):
	if drawing_wall:
		if event is InputEventKey and event.pressed and event.physical_keycode==KEY_ESCAPE:
			drawing_wall=false;selected='';get_viewport().set_input_as_handled();return
		if event is InputEventMouseMotion or (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed):
			var screen: Vector2=get_global_transform_with_canvas().affine_inverse()*event.position
			rank_end=field.unproject(field_point(screen))
			if event is InputEventMouseButton:
				if not wall_preview(true).is_empty():selected=''
				else:notice=words('阵线太短或无法到达 · 原命令继续','Line too short or blocked · Previous order retained');notice_seconds=2
				drawing_wall=false
			field.queue_redraw();get_viewport().set_input_as_handled()
		return
	if placing_rank:
		if event is InputEventMouseMotion or (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and not event.pressed):
			var screen: Vector2=get_global_transform_with_canvas().affine_inverse()*event.position
			rank_end=field.unproject(field_point(screen))
			rank_dragged=rank_dragged or screen.distance_to(rank_screen_start)>7
			if event is InputEventMouseButton:
				if not rules.place_layout(rank_slots()):
					notice=words('阵位重叠或超出部署区','Formation overlaps or leaves the zone')
					notice_seconds=2
				placing_rank=false
			field.queue_redraw()
			get_viewport().set_input_as_handled()
		return
	if not gesture:return
	if event is InputEventMouseMotion or (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed):
		var screen: Vector2=get_global_transform_with_canvas().affine_inverse()*event.position
		drag_end=screen
		var delta=screen-drag_origin
		dragged=dragged or delta.length()>7
		drag_select=dragged and box_gesture
		if dragged and not box_gesture:
			set_camera(camera_at_press-delta/zoom)
		if event is InputEventMouseButton:
			gesture=false
			if drag_select:select_squads(screen,false)
			elif not dragged:click_ground(screen,box_gesture)
			drag_select=false
		field.queue_redraw()
		get_viewport().set_input_as_handled()

func squad_at_id() -> Dictionary:
	for u in rules.alive('ally'):
		if u.id in squad_ids:return u
	return {}

func click_ground(screen: Vector2, additive: bool):
	pointer=field.unproject(field_point(screen))
	if rules.phase not in ['battle','deploy']:return
	if type_gesture or regiment_gesture:
		select_squads(screen,additive);return
	if oil_index>=0 and rules.phase=='deploy':
		if rules.move_oil(oil_index,pointer):oil_index=-1
		else:
			notice=words('请在标记区域内分开布置两组油桶','Place oil inside the marked strip, apart from other oil')
			notice_seconds=2
		return
	if selected=='blink':
		if paused:return
		if rules.Blink.issue(rules,selected_people(),pointer):selected=''
		else:notice=words('超出闪现指令范围，或怨灵未就绪','Outside blink command range, or wraiths not ready');notice_seconds=2
	elif selected=='volley':
		if paused:return
		if rules.Volley.issue(rules,selected_people(),pointer):selected=''
		else:notice=words('超出齐射距离，或长弓兵未就绪','Outside volley range, or longbowmen not ready');notice_seconds=2
	elif selected=='charge':
		if rules.Charges.issue(rules,selected_people(),pointer):selected=''
		else:notice=words('没有就绪的近战士兵或目标超出战场','No melee soldiers ready, or destination outside field');notice_seconds=2
	elif selected=='attack_move':
		if command_selection('attack_move',pointer):selected=''
		else:
			notice=words('无法到达 · 原命令继续','Cannot reach · Previous order retained');notice_seconds=2
	elif selected=='personal_route' and soldier_at(screen,'ally').is_empty():
		if additive and personal_route_valid(pointer):
			draft_waypoints.append(pointer);notice_seconds=0
		elif not additive and rules.Soldiers.command(rules,soldier_ids,'move',pointer,-1,-1,draft_waypoints):
			selected='';notice_seconds=0
		else:notice=words('无法到达 · 原命令继续','Cannot reach · Previous order retained');notice_seconds=2
	elif selected=='lightning':
		if paused:return
		if rules.strike(pointer):notice=words('神力已施放','Power released')
		else:
			notice=power_block_reason()
			if notice=='':notice=words('请选择战场内的目标','Aim inside the battlefield')
		notice_seconds=2
	elif selected=='route' and squad_at(screen,'ally',true).is_empty():
		var squad=squad_at_id()
		if squad.is_empty():return
		if not rules.bounds.has_point(pointer):
			notice=words('请选择战场边界内的行军落点','Choose a destination inside the battlefield')
			notice_seconds=2
		elif additive and rules.plan_route(squad,draft_waypoints,pointer).ok:
			draft_waypoints.append(pointer)
			notice_seconds=0
		elif not additive and squad_ids.size()==1 and rules.march_route(squad_ids[0],draft_waypoints,pointer):
			selected=''
			notice_seconds=0
		else:
			notice=words('此处无法通过 · 请换一个落点','Formation cannot pass · Choose another point')
			notice_seconds=2
	elif selected in ['','route','personal_route'] or not squad_at(screen,'ally').is_empty():
		select_squads(screen,additive)
	elif not paused and rules.deploy(selected,pointer):
		if app!=null:app.sound.play('horn',.5)
		if rules.phase=='battle':selected=''
	else:
		notice=words('在部署区的空地投入部队','Deploy on open ground inside the marked zone')
		notice_seconds=2

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		var code=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		match code:
			KEY_TAB:toggle_overview()
			KEY_1:arm_reserve('legion')
			KEY_2:arm_reserve('archer')
			KEY_3:arm_reserve('cavalry')
			KEY_4:arm_reserve('spear')
			KEY_5:arm_reserve('guard')
			KEY_6:arm_reserve('medic')
			KEY_7:arm_reserve('siege')
			KEY_R:
				if rules.phase=='deploy':
					rules.reserve_squads(squad_ids)
					squad_ids.clear()
					placing_rank=false
			KEY_Q:arm_power()
			KEY_X:
				if rules.phase=='battle' and (not squad_ids.is_empty() or not soldier_ids.is_empty()):selected='attack_move'
			KEY_V:arm_volley()
			KEY_B:arm_blink()
			KEY_C:
				if rules.phase=='battle':
					if rules.Soldiers.members(rules,selected_people()).any(func(row):return rules.Charges.ready(rules,row.unit,row.actor)):selected='charge'
					else:notice=words('冲锋冷却中，或所选兵种不能冲锋','Charge cooling down, or selected units cannot charge');notice_seconds=2
			KEY_F:
				if rules.phase=='battle' and rules.alive('ally').any(func(u):return u.id in squad_ids and rules.Soldiers.individual(rules,u).get('can_shield_wall',false)):selected='shield_line'
				elif rules.phase=='battle' and rules.Soldiers.members(rules,soldier_ids).any(func(row):return rules.Soldiers.individual(rules,row.unit).get('can_shield_wall',false)):selected='shield_line'
			KEY_H,KEY_A:
				if selected in ['route','personal_route','attack_move','shield_line','charge','volley','blink']:selected=''
				command_selection('hold' if code==KEY_H else 'auto',Vector2.ZERO)
			KEY_ESCAPE:
				if selected in ['route','personal_route','attack_move','shield_line','charge','volley','blink']:
					selected=''
					notice_seconds=0
				else:paused=not paused
			KEY_SPACE:paused=not paused
	if event is InputEventMouseMotion and event.button_mask&MOUSE_BUTTON_MASK_MIDDLE:
		set_camera(camera_offset-get_global_transform_with_canvas().basis_xform_inv(event.relative)/zoom)
	if not event is InputEventMouseButton or not event.pressed:return
	var screen: Vector2=get_global_transform_with_canvas().affine_inverse()*event.position
	pointer=field.unproject(field_point(screen))
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var anchor=field_point(screen)
		zoom=clampf(zoom+(.25 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -.25),overview_zoom() if rules is WhiteboardBattle else .5,5.0/3.0)
		set_camera(anchor-screen/zoom)
		return
	if event.button_index==MOUSE_BUTTON_LEFT:
		type_gesture=event.ctrl_pressed;regiment_gesture=event.double_click
		if selected=='shield_line' and rules.phase=='battle':
			drawing_wall=true;rank_start=pointer;rank_end=pointer;field.queue_redraw();return
		gesture=true
		dragged=false
		drag_select=false
		box_gesture=rules.phase in ['deploy','battle'] and event.shift_pressed
		camera_at_press=camera_offset
		drag_origin=screen
		drag_end=screen
		return
	if rules.phase not in ['battle','deploy']:return
	if event.button_index==MOUSE_BUTTON_RIGHT:
		if selected=='lightning':
			selected=''
			return
		if selected in ['route','personal_route']:selected=''
		if rules.phase=='deploy':
			var oil=rules.barrel_at(pointer)
			oil_index=rules.barrels.find(oil)
			if oil_index>=0:
				selected=''
				return
		if rules.phase=='battle':
			var section=rules.Structures.pick(rules,pointer)
			if not section.is_empty():
				var accepted=rules.Structures.order(rules,selected_people(),section)
				notice=words('投石机向选中墙段开火','Catapults bombard the selected wall') if accepted else words('选中投石机后右键轰击城墙','Select catapults and right-click a wall')
				notice_seconds=2.;selected='';return
			var barrel=rules.barrel_at(pointer)
			if not barrel.is_empty():
				var lit=not paused and rules.ignite(barrel)
				notice=words('火箭已发射','Fire arrow away') if lit else words('需要未暂停且射程内有弓兵','Resume with archers in range')
				notice_seconds=2
				return
		if selected!='':
			selected=''
			if rules.phase=='battle':return
		if rules.phase=='deploy':
			if not squad_ids.is_empty():
				placing_rank=true
				rank_dragged=false
				rank_screen_start=screen
				rank_start=pointer
				rank_end=pointer
				return
			var squad=squad_at(screen,'ally')
			if not squad.is_empty():
				rules.reserve_squads([squad.id])
		elif not soldier_ids.is_empty():
			var enemy=soldier_at(screen,'enemy')
			if not enemy.is_empty():command_selection('attack',pointer,enemy.unit.id,enemy.slot)
			elif not command_selection('move',pointer):notice=words('无法到达 · 原命令继续','Cannot reach · Previous order retained');notice_seconds=2
		elif not squad_ids.is_empty():
			var enemy=squad_at(screen,'enemy')
			if not enemy.is_empty():rules.command(squad_ids,'attack',enemy.pos,enemy.id)
			elif rules.bounds.has_point(pointer) and not rules.command(squad_ids,'move',pointer):
				notice=words('队形无法到达 · 原命令继续','Formation cannot reach · Previous orders retained')
				notice_seconds=2
	field.queue_redraw()


func choose_deity(id: String):
	if not rules.select_deity(id):return
	if rules.phase=='battle':arm_power()
	else:
		notice=words('已选择角色。部署部队并开战后，按 Q 或点击技能，再点击战场释放。','Character selected. Deploy and begin, then press Q and click the battlefield.')
		notice_seconds=4
	refresh()

func power_block_reason() -> String:
	if paused:return words('当前已暂停，请先继续战斗。','Paused. Resume the battle first.')
	if rules.phase=='deploy':return words('先部署至少一队并点击「开战」，随后才能施放神力。','Deploy a squad and press Begin before using divine power.')
	if rules.phase!='battle':return words('战斗已经结束。','Battle has ended.')
	if not rules.unlimited_powers and rules.charges<=0:return words('本场神力次数已用完。','No divine charges remain.')
	if not rules.unlimited_powers and rules.cooldown>0:return words('神力冷却中，还需 %d 秒。','Power recharging: %d seconds remaining.')%ceili(rules.cooldown)
	return ''

func arm_power():
	notice=power_block_reason()
	if notice=='':
		selected='lightning'
		var character=rules.characters.filter(func(c):return c.id==rules.deity)[0]
		notice=skill_text(character.summary,character.summary_en)+words(' · 点击落点释放',' · Click a target location')
	notice_seconds=4
