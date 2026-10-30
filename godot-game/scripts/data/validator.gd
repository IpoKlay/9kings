extends RefCounted
## Authoring checks. Does not mutate, repair or silently rebalance content.
const Catalog=preload('res://scripts/data/catalog.gd')
var errors: Array[String]=[]
var checks=0
func require(ok: bool,message: String):
	checks+=1
	if not ok: errors.append(message)
func numeric(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))
func resolve_fields(value,parts: PackedStringArray,path: String,result: Dictionary):
	if parts.is_empty(): result[path]=value;return
	var rest=parts.slice(1)
	if parts[0]=='*':
		for key in value: resolve_fields(value[key],rest,path+'.'+str(key),result)
	elif value is Dictionary and value.has(parts[0]): resolve_fields(value[parts[0]],rest,path+'.'+parts[0],result)
	elif path.ends_with('.training'): return # A drill yard is not a unit.
	else: require(false,'Missing field: '+path+'.'+parts[0])
func validate_field(value,rule: Dictionary,path: String):
	require(numeric(value),path+' must be a finite number')
	if not numeric(value): return
	if rule.type=='integer': require(float(value)==floorf(float(value)),path+' must be an integer')
	if rule.has('min'): require(value>=rule.min,path+' below minimum '+str(rule.min))
	if rule.has('max'): require(value<=rule.max,path+' above supported maximum '+str(rule.max))
func validate() -> Array[String]:
	errors.clear();checks=0
	var manifest=JSON.parse_string(FileAccess.get_file_as_string('res://data/manifest.json'))
	for id in manifest.json:
		var parser=JSON.new()
		var error=parser.parse(FileAccess.get_file_as_string(manifest.json[id]))
		require(error==OK,'Invalid JSON '+manifest.json[id]+': '+parser.get_error_message())
	if not errors.is_empty(): return errors
	for rule in Catalog.data('schema/field_contracts'):
		var parts=rule.path.split('#');var found={}
		resolve_fields(Catalog.data(parts[0]),parts[1].split('.'),parts[0],found)
		for path in found: validate_field(found[path],rule,path)
	if not errors.is_empty(): return errors
	require(preload('res://scripts/data/settings_store.gd').valid_frame_limit(Catalog.data('defaults/settings').fps_limit),'Default frame limit is a supported option')
	var rules=Catalog.rules();var camp=Catalog.data('balance/camp');var route=Catalog.expedition()
	require(camp.max_buildings==camp.columns*camp.rows,'Camp capacity must match grid')
	for type in rules.types:
		require(rules.cards.has(type),'Unit has a build card: '+type)
		if type!='training': require(rules.types[type].role in ['front','middle','rear'],'Known unit role '+type)
		if rules.cards[type].kind=='Troop':
			var counts=rules.types[type].get('formation_counts',[])
			require(counts.size()==3,'Three population levels '+type)
			var previous=0
			for count in counts:
				require(numeric(count) and count==floorf(count) and count>previous and count<=12,'Increasing, tile-sized formation '+type)
				previous=count
		for level in range(1,int(camp.max_building_level)+1): require(ResourceLoader.exists('res://assets/building_%s_%d.png'%[type,level]),'Building art '+type+' level '+str(level))
		if type in ['siege','medic']:
			for level in range(1,4):
				var path='res://assets/facilities/%s_%d.png'%[type,level]
				require(ResourceLoader.exists(path),'Functional building art '+path)
				if ResourceLoader.exists(path):require(load(path).get_size()==Vector2(96,96),'Building uses the fixed 96-pixel asset grid')
	for id in rules.cards:
		var card=rules.cards[id]
		require(card.kind in ['Troop','Building','Permanent','Battle order'],'Known card kind '+id)
		if card.has('max'): require(numeric(card.max) and card.max>=1 and card.max==floorf(card.max),'Positive integer rank cap '+id)
		if not card.get('retired',false):require(card.get('max',0)==3,'Every active card has three levels '+id)
		for type in card.get('requires',[]): require(rules.types.has(type),'Valid required unit '+id+'/'+type)
		if card.has('needs'): require(rules.cards.has(card.needs) and card.needs!=id,'Valid card prerequisite '+id)
		require(ResourceLoader.exists('res://assets/card_'+id+'.png'),'Card art '+id)
		for field in ['name','text','detail','impact','tag']:
			require(card[field] is String and not card[field].contains('{'),'Resolved card copy '+id+'/'+field)
	var ids={};var kinds=['home','port','event','battle','elite','boss','final']
	for n in route.nodes:
		require(not ids.has(n.id),'Unique city id '+n.id);ids[n.id]=n
		require(n.kind in kinds,'Known city kind '+n.id)
		require(n.act>=0 and n.act<=route.acts.size() and n.step>=0 and n.step<=route.steps_per_act,'Valid city progression '+n.id)
		if n.roster!=null:
			require(n.roster is Array and not n.roster.is_empty(),'Nonempty enemy roster '+n.id)
			for type in n.roster: require(rules.enemies.has(type),'Enemy reference '+n.id+'/'+type)
		for field in ['name','name_en','title','title_en','history','history_en']: require(n.get(field,'') is String and not n.get(field,'').is_empty(),'City copy '+n.id+'/'+field)
	require(ids.has(route.start) and ids.has(route.final),'Start and final refer to cities')
	require(route.total_steps==route.steps_per_act*route.acts.size(),'Total route steps match theaters')
	for edge in route.edges:
		require(edge.size()==2 and ids.has(edge[0]) and ids.has(edge[1]) and edge[0]!=edge[1],'Valid edge '+str(edge))
		if ids.has(edge[0]) and ids.has(edge[1]):
			var a=ids[edge[0]];var b=ids[edge[1]]
			require(b.act>a.act or (b.act==a.act and b.step>a.step),'Route must move forward '+str(edge))
	for act in route.acts: require(ids.has(act.goal) and act.steps==route.steps_per_act,'Theater goal and length '+str(act.id))
	var doctrines=Catalog.data('balance/enemy_doctrines')
	require(doctrines.intro_stage==1 and doctrines.intro_last_step==3,'Preserve the infantry introduction')
	for id in doctrines.profiles:
		var profile=doctrines.profiles[id]
		require(profile.roster.size()>=2 and profile.relief.size()>=2,'Doctrine has a core and varied reinforcements '+id)
		for type in profile.roster+profile.relief: require(rules.enemies.has(type),'Doctrine references an enemy '+id+'/'+type)
		for card in profile.answers: require(rules.cards.has(card),'Doctrine advice references a real card '+id+'/'+card)
		for field in ['name','threat','advice']:
			require(Catalog.data('localization/interface').has('routeintel.'+id+'.'+field),'Doctrine has localized scout copy '+id+'/'+field)
	for theater in ['1','2','3']:
		require(doctrines.theaters.has(theater) and not doctrines.theaters[theater].is_empty(),'Theater has tactical profiles '+theater)
		for id in doctrines.theaters[theater]: require(doctrines.profiles.has(id),'Theater profile exists '+id)
	for id in doctrines.sites:
		require(ids.has(id) and ids[id].roster!=null and doctrines.profiles.has(doctrines.sites[id]),'Tactical override references a hostile city '+id)
	var marches=Catalog.data('generated/march_paths')
	for key in marches.edges:
		var pair=key.split('>');var corridor=marches.edges[key]
		require(pair.size()==2 and ids.has(pair[0]) and ids.has(pair[1]),'March references existing locations '+key)
		require(corridor.mode in ['land','sea'] and corridor.points.size()>=2,'March mode and waypoints '+key)
		for p in corridor.points: require(p.size()==2 and p[0]>=0 and p[0]<=5760 and p[1]>=0 and p[1]<=2520,'March waypoint in atlas '+key)
	for edge in route.edges: require(marches.edges.has(edge[0]+'>'+edge[1]),'Every authored edge has a corridor')
	for source in Catalog.data('content/march_choices'):
		var branch=Catalog.data('content/march_choices')[source]
		var tactical_choices=[]
		for id in branch.choices: tactical_choices.append(doctrines.sites.get(id,''))
		require(tactical_choices.size()==2 and tactical_choices[0]!='' and tactical_choices[0]!=tactical_choices[1],'Each fork offers different real tactics '+source)
		require(ids.has(source) and ids.has(branch.merge) and branch.choices.size()==2,'Two local choices and one merge '+source)
		for choice in branch.choices:
			require(ids.has(choice) and [source,choice] in route.edges and [choice,branch.merge] in route.edges,'Branch rejoins the authored route '+choice)
			require(ids[choice].act==ids[source].act and ids[branch.merge].act==ids[source].act,'Branch remains in one theater '+choice)
	var defaults=Catalog.data('defaults/campaign');var cells={};var building_ids={}
	require(defaults.unlocked_cells.size()==9 and defaults.unlocked_cells.map(func(cell):return int(cell))==[6,7,8,11,12,13,16,17,18],'Camp starts with only the central 3 by 3 tiles')
	require(defaults.buildings.size()==1 and defaults.buildings[0].type=='legion' and defaults.buildings[0].level==1,'Only one infantry squad is granted at the start')
	require(defaults.cities_captured==0 and defaults.expansion_credits==0,'New campaigns reset expansion progress')
	require(defaults.defense>0 and defaults.defense<=camp.max_lives,'Default lives within maximum')
	for building in defaults.buildings:
		require(rules.types.has(building.type),'Starting building exists')
		require(building.cell>=0 and building.cell<camp.max_buildings and not cells.has(building.cell),'Starting camp cells valid and unique')
		require(building.cell in defaults.unlocked_cells,'Starting army is on an unlocked tile')
		require(building.level>=1 and building.level<=camp.max_building_level,'Starting building level')
		require(not building_ids.has(building.id) and building.id<defaults.nextId,'Starting building identity')
		cells[building.cell]=true;building_ids[building.id]=true
	var contracts=Catalog.data('schema/contracts');var positions=Catalog.data('generated/atlas_positions')
	require(positions.size()==ids.size(),'Atlas anchor count matches locations')
	for id in ids:
		require(positions.has(id),'Atlas anchor '+id)
		if positions.has(id): require(positions[id][0]>=0 and positions[id][0]<=contracts.map_world_size[0] and positions[id][1]>=0 and positions[id][1]<=contracts.map_world_size[1],'Atlas anchor in bounds '+id)
	var troop_scale=Catalog.presentation('field').get('troop_scale',0)
	require(numeric(troop_scale) and troop_scale>=1 and troop_scale==floorf(troop_scale),'Troop presentation scale is a positive whole number')
	var scene=Catalog.presentation('environment')
	for field in ['backgrounds','ground_overlays','tree_layouts','water_polygons','water_speeds','ripple_strengths','drift_speeds']: require(scene[field].size()==route.acts.size(),'One '+field+' entry per theater')
	for i in route.acts.size():
		require(ResourceLoader.exists('res://assets/'+scene.backgrounds[i]+'.png'),'Theater background exists')
		if not scene.ground_overlays[i].is_empty():require(ResourceLoader.exists('res://assets/'+scene.ground_overlays[i]+'.png'),'Theater ground overlay exists')
		require(scene.water_polygons[i].size()>=3 and scene.water_polygons[i].size()<=contracts.technical_water_polygon_capacity,'Water polygon shader capacity')
		require(scene.water_speeds[i]>0,'Water flows forward')
	var sea=Catalog.presentation('atlas_sea')
	for key in ['lifetime_seconds','drag_per_second','gust_spacing','gust_interval_seconds','animation_fps']: require(sea[key]>0,'Sea positive '+key)
	require(sea.max_water_speed>=0 and sea.pointer_gain>=0,'Sea speeds cannot be negative')
	require(sea.fade_start_seconds>=0 and sea.fade_start_seconds<sea.lifetime_seconds,'Sea fade within lifetime')
	var atlas=Catalog.presentation('atlas')
	require(numeric(atlas.route_ink.branch_lane_offset) and atlas.route_ink.branch_lane_offset>=0,'Branch lanes have a nonnegative display offset')
	var journey=atlas.departure
	for key in ['rally_seconds','march_min_seconds','march_max_seconds','march_pixels_per_second','cover_seconds','covered_seconds','reveal_seconds','reduced_seconds','pose_fps','cloud_fps','soldier_scale','ship_scale']:
		require(numeric(journey[key]) and journey[key]>0,'Departure has positive '+key)
	require(journey.march_min_seconds<=journey.march_max_seconds,'Departure duration bounds are ordered')
	require(journey.cloud_count>=1 and journey.cloud_count<=48 and journey.cloud_count==floorf(journey.cloud_count),'Bounded whole cloud count')
	require(journey.cloud_width.x>0 and journey.cloud_width.y>=journey.cloud_width.x,'Ordered cloud size range')
	require(journey.cloud_drift.x>=0 and journey.cloud_drift.y>=journey.cloud_drift.x,'Ordered cloud drift range')
	require(journey.cloud_size.x>0 and journey.cloud_size.y>0 and int(contracts.viewport_size[0])%journey.cloud_size.x==0 and int(contracts.viewport_size[1])%journey.cloud_size.y==0,'Cloud canvas scales in whole pixels')
	for tone in ['shadow','mid','light','highlight']: require(journey['cloud_'+tone] is Color and journey['cloud_'+tone].a==1,'Opaque cloud palette '+tone)
	require(atlas.min_zoom>0 and atlas.max_zoom>=atlas.min_zoom and atlas.route_colors.size()==route.acts.size(),'Atlas zoom and route colors')
	var boundary=atlas.boundary
	require(boundary.paper_stain_scale>0 and boundary.paper_palette.size()>=3,'Aged paper has a valid stain scale and varied pigments')
	for pigment in boundary.paper_palette: require(pigment is Color and pigment.a==1.0,'Paper pigments are opaque colors')
	require(boundary.pixel_step>0 and boundary.period>=boundary.pixel_step*2,'Pixel border has positive grid and pitch')
	require(boundary.shoulder_steps>=1 and boundary.crest_steps>=1 and boundary.period>boundary.pixel_step*(boundary.shoulder_steps*2+boundary.crest_steps),'Pixel border preserves short shoulders, a flat tip and straight runs')
	if boundary.pixel_step>0:
		require(is_equal_approx(fmod(boundary.period,boundary.pixel_step*2),0.0),'Pixel border pitch has two equal stepped halves')
		require(is_equal_approx(fmod(boundary.corner_size,boundary.pixel_step*4),0.0),'Pixel border corners use four complete steps')
	require(boundary.inset>=boundary.pixel_step and boundary.side_depth>=0 and boundary.horizontal_depth>=0,'Pixel border depths and inset are non-negative')
	require(boundary.ink_width>=boundary.edge_width and boundary.edge_width>0,'Pixel border outline widths are ordered')
	require(boundary.inset+maxf(boundary.side_depth,boundary.horizontal_depth)+boundary.corner_size<minf(contracts.viewport_size[0],contracts.viewport_size[1])*.5,'Pixel border leaves a visible map interior')
	var hand=Catalog.presentation('card_hand')
	require(hand.step>0 and hand.hover_scale>=1 and hand.pick_wait_seconds>=hand.pick_seconds,'Card hit regions and commit timing')
	require(hand.drag_threshold>0 and hand.drag_threshold<hand.card_size.y,'Card use requires a deliberate upward drag')
	require(hand.drag_pixel_step>=1 and hand.drag_pixel_step==floorf(hand.drag_pixel_step),'Card drag uses whole pixel steps')
	for key in ['ink','edge','body','brass','highlight','name_band','title','description','muted']:
		require(hand.face_palette.get(key) is Color,'Card face pigment '+key)
	for kind in ['Building','Permanent','Battle order']:
		require(hand.face_wells.get(kind) is Color,'Card illustration well '+kind)
	var audio=Catalog.presentation('audio')
	var music=audio.music
	for field in ['crossfade_seconds','interrupt_seconds','loop_crossfade_seconds','volume_smoothing_seconds','duck_seconds']:
		require(numeric(music[field]) and music[field]>0,'Positive music timing '+field)
	require(music.quiet_gain>0 and music.quiet_gain<=1,'Music ducks within normal level')
	for id in ['menu','camp','battle','boss','archive','map']:
		var track=music.tracks.get(id,{})
		require(not track.is_empty(),'Music scene '+id)
		if track.is_empty(): continue
		require(ResourceLoader.exists(track.file),'Music recording '+id)
		if ResourceLoader.exists(track.file):
			var stream=load(track.file)
			require(stream is AudioStreamMP3 and not stream.loop,'Crossfade controls the native MP3 loop '+id)
			require(track.start>=0 and track.end>track.start+music.loop_crossfade_seconds*2 and track.end<=stream.get_length()+.01,'Music loop range '+id)
		require(numeric(track.gain) and track.gain>0 and track.gain<=2,'Music gain '+id)
		require((track.source.begins_with('https://incompetech.com/') or track.source.begins_with('https://www.scottbuckley.com.au/')) and not track.title.is_empty() and not track.author.is_empty(),'Visible music attribution '+id)
	for kind in audio.effect_files:
		var files=audio.effect_files[kind]
		require(not files.is_empty() and files.size()==int(audio.variants[kind]),'Selected effect variations '+kind)
		require(audio.gains[kind]>=0 and audio.gains[kind]<=1 and audio.gaps[kind]>0,'Bounded effect level and spacing '+kind)
		for file in files:
			require(ResourceLoader.exists(file),'Selected effect exists '+file)
			if ResourceLoader.exists(file):
				var stream=load(file)
				require(stream is AudioStreamWAV and stream.get_length()>0 and stream.get_length()<5,'Short selected effect '+file)
	require(audio.ambience.fade_seconds>0 and audio.ambience.quiet_gain>0 and audio.ambience.quiet_gain<=1,'Ambient fade and quiet level')
	for id in ['sea','fire']:
		var track=audio.ambience.tracks[id]
		require(ResourceLoader.exists(track.file) and track.gain>0 and track.gain<=1,'Ambient recording and gain '+id)
	require(audio.voice_pool_size>=1 and audio.voice_pool_size==floorf(audio.voice_pool_size),'Audio voice capacity')
	require(ResourceLoader.exists(audio.menu_move.file),'Menu movement recording exists')
	var menu_stream=load(audio.menu_move.file) if ResourceLoader.exists(audio.menu_move.file) else null
	require(menu_stream is AudioStream and menu_stream.get_length()>0,'Menu movement recording decodes')
	require(numeric(audio.menu_move.gain) and audio.menu_move.gain>=0 and audio.menu_move.gain<=1,'Menu movement gain is linear 0–1')
	require(ResourceLoader.exists(audio.page_turn.file),'Book page recording exists')
	var page_stream=load(audio.page_turn.file) if ResourceLoader.exists(audio.page_turn.file) else null
	require(page_stream is AudioStream and page_stream.get_length()>0,'Book page recording decodes')
	require(numeric(audio.page_turn.gain) and audio.page_turn.gain>=0 and audio.page_turn.gain<=1,'Book page gain is linear 0–1')
	for id in ['map_paper','map_pin']:
		var recording=audio[id]
		require(ResourceLoader.exists(recording.file),'Map entry recording exists '+id)
		var stream=load(recording.file) if ResourceLoader.exists(recording.file) else null
		require(stream is AudioStream and stream.get_length()>0,'Map entry recording decodes '+id)
		require(numeric(recording.gain) and recording.gain>=0 and recording.gain<=1,'Map entry gain is linear 0–1 '+id)
	for id in audio.card_variants:
		for i in audio.card_variants[id]: require(ResourceLoader.exists('res://assets/cards/trimmed/%s-%d.wav'%[id,i+1]),'Card recording '+id)
	for id in Catalog.presentation('ui').roman_icons: require(ResourceLoader.exists(Catalog.presentation('ui').roman_icons[id]),'Roman icon '+id)
	var ui=Catalog.presentation('ui')
	for field in ['book_turn_fps','paper_motion_pixel_step']:
		require(numeric(ui[field]) and ui[field]>0,'Positive paper animation parameter '+field)
	require(ui.paper_motion_pixel_step==floorf(ui.paper_motion_pixel_step),'Paper animation uses a whole-pixel grid')
	var pins=ui.map_pins
	for field in ['drop_seconds','impact_seconds','drop_height','fps','pixel_step','inset']:
		require(numeric(pins[field]) and pins[field]>0,'Positive map pin parameter '+field)
	require(pins.stagger_seconds>=0,'Map pin stagger is nonnegative')
	require(pins.drop_seconds+3*pins.stagger_seconds+pins.impact_seconds<=.5,'Map pin entry is brief')
	require(pins.pixel_step==floorf(pins.pixel_step) and fmod(pins.inset,pins.pixel_step)==0,'Map pins use aligned whole pixels')
	require(pins.palette.size()==6,'Map pin palette has six pigments')
	for pigment in pins.palette: require(pigment is Color,'Map pin pigment is a color')
	require(ResourceLoader.exists(ui.rpg_sheet),'RPG UI source sheet exists')
	if ResourceLoader.exists(ui.rpg_sheet):
		var sheet: Texture2D=load(ui.rpg_sheet)
		for id in ui.rpg_regions:
			var region: Rect2=ui.rpg_regions[id]
			require(Rect2(Vector2.ZERO,sheet.get_size()).encloses(region) and region.size.x>0 and region.size.y>0,'RPG slice inside sheet '+id)
			require(ui.rpg_scales[id]>=1 and ui.rpg_scales[id]==floorf(ui.rpg_scales[id]),'Integer RPG pixel scale '+id)
			if ui.rpg_margins.has(id):
				var margins: Vector4=ui.rpg_margins[id]
				require(margins.x+margins.z<region.size.x and margins.y+margins.w<region.size.y,'RPG nine-slice preserves a center '+id)
	var shader=FileAccess.get_file_as_string('res://shaders/atlas_sea.gdshader')
	require(shader.contains('gust_patches[%d]'%int(contracts.technical_gust_capacity)) and shader.contains('gust_flows[%d]'%int(contracts.technical_gust_capacity)),'Sea CPU/GPU gust capacities agree')
	require(contracts.map_world_size[0]==contracts.map_texture_size[0]*2 and contracts.map_world_size[1]==contracts.map_texture_size[1]*2,'Atlas source/logic pixel ratio')
	require(ProjectSettings.get_setting('display/window/size/viewport_width')==contracts.viewport_size[0] and ProjectSettings.get_setting('display/window/size/viewport_height')==contracts.viewport_size[1],'Project logical viewport matches contract')
	for id in Catalog.data('localization/interface'):
		for language in contracts.languages: require(not Catalog.text(id,language).contains('{'),'Resolved localized message '+id+'/'+language)
	return errors
