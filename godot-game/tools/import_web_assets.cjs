// Archived migration source. Native Godot data/art are authoritative.
throw new Error('Legacy web import disabled: it overwrites current native assets and fixtures. Use the scoped Godot tools instead.');
/* Rebuild native assets from the existing game's own Canvas drawing functions.
   No browser runtime is required by the resulting Godot game. */
const fs=require('fs'),path=require('path'),vm=require('vm');
const {createCanvas}=require(process.env.EAGLE_CANVAS_MODULE||'@napi-rs/canvas');
const root=path.resolve(__dirname,'..'),src=path.resolve(root,'../eagle-standard-demo/dist');
const ctx={window:{},document:{createElement:()=>{const c=createCanvas(64,64);c.setAttribute=()=>{};return c;}}};ctx.globalThis=ctx.window;vm.createContext(ctx);
for(const f of ['engine','i18n','isometric','unit-data','unit-art','battle-view','audio-bank'])vm.runInContext(fs.readFileSync(path.join(src,f+'.js'),'utf8'),ctx);
const W=ctx.window,E=W.Eagle,I=W.EagleIso;
const app=fs.readFileSync(path.join(src,'app.js'),'utf8');
vm.runInContext('const E=window.Eagle,I=window.EagleIso;'+app.slice(app.indexOf('  const pixels ='),app.indexOf('  function soldier('))+'\nwindow.makeIcon=makeIcon;',ctx);
function png(name,c){fs.writeFileSync(path.join(root,'assets',name+'.png'),c.toBuffer('image/png'));}
function json(name,v){fs.writeFileSync(path.join(root,'data',name+'.json'),JSON.stringify(v,null,2));}
json('rules',{types:E.TYPES,cards:E.CARDS,enemies:E.ENEMIES,zh:W.EagleI18n.zh,woodland:I.woodland});
const terrain=createCanvas(960,540);require('./forest_floor.cjs')(terrain,I.woodland);png('terrain',terrain);
for(const id of Object.keys(E.CARDS))png('card_'+id,W.makeIcon(id));
for(const id of Object.keys(E.TYPES))for(let level=1;level<=3;level++)png('building_'+id+'_'+level,W.makeIcon(id,level));
for(const [i,[x,y,size,kind,variant]]of I.woodland.entries()){
 const c=createCanvas(160,180),g=c.getContext('2d'),p=I.unproject(x,y);g.translate(80-x,170-y);I.tree(g,p.x,p.y,size,kind,variant);png('tree_'+i,c);
}
for(const live of [false,true]){const c=createCanvas(96,80),g=c.getContext('2d'),p=I.project(0,0);g.translate(48-p.x,70-p.y);I.lifeShield(g,0,0,live);png('life_'+Number(live),c);}
for(const type of ['legion','spear','guard','cavalry','archer','medic','enemy'])for(const enemy of [false,true])for(const mode of ['idle','walk','attack','testudo','testudo_walk','testudo_attack']){
 const c=createCanvas(64*16,64),g=c.getContext('2d');
 for(let f=0;f<16;f++){
  g.save();g.beginPath();g.rect(f*64,0,64,64);g.clip();
  const walk=mode.includes('walk'),attack=mode.includes('attack'),pose=W.EagleBattleView.pose(walk?f/16*2*Math.PI/13:0,0,walk,attack?f/16*.48:10);
  W.EagleUnitArt.draw(g,f*64+32,52,type,1,pose,false,{enemy,raised:mode.startsWith('testudo'),edge:true});g.restore();
 }png('unit_'+type+'_'+(enemy?'enemy':'ally')+'_'+mode,c);
}
const siege=createCanvas(80*16,80),sg=siege.getContext('2d');for(let f=0;f<16;f++){sg.save();sg.translate(f*80+8,12);I.catapult(sg,f/16*.75);sg.restore();}png('catapult',siege);
for(const [id,b64]of Object.entries(W.EagleAudioBank.samples)){
 const pcm=Buffer.from(b64,'base64'),b=Buffer.alloc(44+pcm.length),rate=W.EagleAudioBank.rate;
 b.write('RIFF');b.writeUInt32LE(36+pcm.length,4);b.write('WAVEfmt ',8);b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(rate,24);b.writeUInt32LE(rate*2,28);b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(pcm.length,40);pcm.copy(b,44);fs.writeFileSync(path.join(root,'assets',id+'.wav'),b);
}
fs.copyFileSync(path.join(src,'AUDIO-CREDITS.txt'),path.join(root,'assets','AUDIO-CREDITS.txt'));
fs.appendFileSync(path.join(root,'assets','AUDIO-CREDITS.txt'),'\n\nGodot card-hand foley: Kenney Casino Audio v1.1\nSource: https://kenney.nl/assets/casino-audio\nLicense: CC0 1.0 Universal; see cards/License.txt.\n');
const fixtures=[];
for(const year of [1,2,3,4,6,8,10,16,24])for(const combo of [false,true]){
 const g=E.createGame(123);g.round=year;if(combo){g.buildings=['guard','legion','spear','archer','archer','siege','medic'].map((type,i)=>({type,id:i+1,cell:i,level:1}));g.upgrades={fireArrows:1,oilShots:1,pinning:1,shieldDrill:2,fieldMedicine:1,crossfire:1,combinedArms:1};}
 const initial=JSON.parse(JSON.stringify(g));g.phase='prepare';E.start(g);while(g.phase==='battle')E.step(g,1/60);fixtures.push({initial,report:g.battle.report,time:g.battle.time});
}
json('combat_reference',fixtures);
const draws=[];for(const seed of [1,5,42,123,4294967295]){const g=E.createGame(seed),years=[];for(let y=1;y<=20;y++){g.round=y;years.push(E.offers(g));}draws.push({seed,years});}json('draw_reference',draws);
console.log('Imported 24 cards, all troop animation sheets, scenery, PCM audio and JS parity fixtures.');
for(const [name,base,colors,border]of [['paper','#bcb18c',['#b1a47d','#cec4a1','#c0b48e'],'#6c6044'],['wood','#303a31',['#45513c','#222e29','#596046'],'#89906b'],['gold','#8f7346',['#a58a54','#c1a569','#685132'],'#ead79a']]){
 const c=createCanvas(128,128),g=c.getContext('2d');g.fillStyle=base;g.fillRect(0,0,128,128);let seed=73;const rand=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
 for(let i=0;i<1000;i++){g.fillStyle=colors[i%3];g.fillRect(4+Math.floor(rand()*118),4+Math.floor(rand()*118),name==='wood'?2+Math.floor(rand()*11):2,2);}
 g.strokeStyle='#182b23';g.lineWidth=4;g.strokeRect(2,2,124,124);g.strokeStyle=border;g.lineWidth=2;g.strokeRect(5,5,118,118);png('panel_'+name,c);
}
