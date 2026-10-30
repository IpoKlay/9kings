extends Control
## Two compact scout slips share the exact encounter and current army data.
const Paper=preload('res://scripts/city_intel_panel.gd')
var map
var choice_buttons={}

func _ready():
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	var exp=map.app.expedition
	var brief=exp.briefing()
	if brief.is_empty(): return
	var options=brief.choices
	var heading='ahead' if brief.ahead else 'now' if options.size()>1 else 'single'
	map.text(self,exp.loc('routeintel.'+heading),Vector2(0,0),Vector2(430,32),20,Color('#ffebbb'))
	for index in options.size():
		var id=options[index]
		if not exp.known(id): continue
		var slip=Paper.new()
		slip.simple=true
		slip.grain=map.paper_texture()
		slip.position=Vector2(0,44+index*188)
		slip.size=Vector2(430,176)
		add_child(slip)
		var button=Button.new()
		button.name='RouteChoice_'+id
		button.size=slip.size
		button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
		for state in ['normal','hover','pressed','focus']:
			var box=StyleBoxFlat.new()
			box.bg_color=Color(1,.86,.48,.14) if state=='hover' else Color.TRANSPARENT
			box.border_color=Color('#e9c781') if state=='focus' or id==map.selected else Color('#8a633f')
			box.set_border_width_all(4 if state=='focus' or id==map.selected else 0)
			box.anti_aliasing=false
			button.add_theme_stylebox_override(state,box)
		button.tooltip_text=exp.loc('routeintel.future' if brief.ahead else 'routeintel.view')
		button.tooltip_text+='\n'+exp.doctrine_text(id,'advice')
		button.accessibility_name=exp.node_text(id)+' · '+exp.doctrine_text(id,'name')
		button.pressed.connect(func():map.select_city(id))
		slip.add_child(button)
		choice_buttons[id]=button
		var prefix=(['A','B'][index]+' · ') if options.size()>1 else ''
		var title=prefix+exp.node_text(id)
		var title_size=24
		while title_size>18 and map.app.font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,title_size).x>390: title_size-=1
		map.text(button,title,Vector2(20,10),Vector2(390,30),title_size,Paper.INK)
		var wave=exp.encounter(id)
		var meta=exp.doctrine_text(id,'name') if wave.is_empty() else exp.loc('routeintel.rounds')%[exp.doctrine_text(id,'name'),wave.waves.size()]
		map.text(button,meta,Vector2(20,40),Vector2(390,26),20,Paper.RED)
		map.text(button,exp.doctrine_text(id,'threat'),Vector2(20,68),Vector2(390,24),18,Paper.MUTED)
		var response=map.text(button,exp.response_text(id),Vector2(20,94),Vector2(390,42),18,Paper.INK)
		response.name='Response'
		response.tooltip_text=exp.doctrine_text(id,'advice')
		var reward_key='elite' if exp.nodes[id].kind=='elite' else 'victory' if exp.nodes[id].kind=='final' else 'recovery' if exp.nodes[id].kind in exp.travel_rules.recovery_kinds else 'reward'
		map.text(button,exp.loc('routeintel.'+reward_key),Vector2(20,140),Vector2(390,24),18,Paper.RED)
	# Bounds match actual papers, for map label placement and pointer routing.
	size=Vector2(430,44+options.size()*188-12)
