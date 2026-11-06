// Generates ONLY expedition textures; never reimports the existing Godot assets.
const fs=require('fs'),path=require('path');
const {createCanvas}=require(process.env.EAGLE_CANVAS_MODULE||'@napi-rs/canvas');
const root=path.resolve(__dirname,'..');const data=require('./data_source.cjs').expedition();
// The historical backdrop retains its original anchors. Runtime routes use the
// new geographic atlas (build_expedition_atlas.cjs); this retains legacy assets.
const geometry=require('./map-source/geometry.json');
const anchors=data.nodes.filter(n=>geometry.coords[n.id]);
const art=require('./map-source/art.cjs')({createCanvas,d3:require('./map-source/d3.cjs'),mapRules:{nodes:anchors},mapData:geometry});
const save=(name,c)=>fs.writeFileSync(path.join(root,'assets/expedition',name+'.png'),c.toBuffer('image/png'));
save('mediterranean',art.canvas);
fs.writeFileSync(path.join(root,'data/generated/legacy_map_positions.json'),JSON.stringify(art.positions,null,2));
for(const kind of ['home','port','event','battle','elite','boss','final'])for(const state of ['idle','visited','current']){const c=createCanvas(64,50);art.town(c,kind,state==='current',state==='visited');save(kind+'_'+state,c);}
for(const [name,base,light,dark] of [['panel','#243852','#95a393','#12283e'],['button','#354b5c','#849589','#172b40'],['gold','#8d4939','#d2af74','#552e30']]){const c=createCanvas(48,48),g=c.getContext('2d');g.fillStyle=base;g.fillRect(0,0,48,48);for(let y=2;y<46;y++)for(let x=2;x<46;x++)if((x*17+y*13)%11<3){g.fillStyle=(x+y)%3?'#ffffff08':'#00000010';g.fillRect(x,y,1,1);}g.fillStyle=light;g.fillRect(0,0,48,2);g.fillRect(0,0,2,48);g.fillStyle=dark;g.fillRect(2,46,46,2);g.fillRect(46,2,2,46);g.fillStyle='#68838d';g.fillRect(3,3,42,1);g.fillRect(3,3,1,42);save(name,c);}
console.log('Native expedition textures and positions generated. Existing terrain, troops and audio untouched.');
