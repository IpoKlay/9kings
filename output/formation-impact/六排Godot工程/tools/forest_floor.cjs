/* Native game's pixel forest clearing. Kept separate so re-importing web assets
   preserves the Godot terrain direction. No external images or runtime dependency. */
function drawForestFloor(canvas, woodland = []) {
  const g=canvas.getContext('2d'),w=canvas.width,h=canvas.height;
  let seed=92741;
  const rand=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
  const hash=(x,y)=>{let n=Math.imul(x,374761393)^Math.imul(y,668265263)^4817;n=Math.imul(n^(n>>>13),1274126177);return((n^(n>>>16))>>>0)/4294967296;};
  const smooth=t=>t*t*(3-2*t);
  function noise(x,y,size){const px=x/size,py=y/size,ix=Math.floor(px),iy=Math.floor(py),tx=smooth(px-ix),ty=smooth(py-iy);return(hash(ix,iy)*(1-tx)+hash(ix+1,iy)*tx)*(1-ty)+(hash(ix,iy+1)*(1-tx)+hash(ix+1,iy+1)*tx)*ty;}
  const dirt=['#514e43','#595548','#615b4d','#686051','#6e6655','#756b59'];
  const forest=['#3d4836','#46503b','#50563e','#5a5b43'];
  // Bare mineral soil throughout the clearing; moss gathers irregularly at the tree line.
  for(let y=0;y<h;y+=2)for(let x=0;x<w;x+=2){
    const broad=noise(x,y,80),middle=noise(x,y,21),grain=noise(x,y,6);
    const edge=Math.max(Math.abs((x-w*.51)/(w*.56)),Math.abs((y-h*.52)/(h*.52)));
    const moss=edge>.72+(broad-.5)*.38&&middle>.39&&grain>.35;
    const palette=moss?forest:dirt;
    const shade=Math.max(0,Math.min(palette.length-1,Math.floor((broad*.44+middle*.37+grain*.19)*palette.length)));
    g.fillStyle=palette[shade];g.fillRect(x,y,2,2);
  }
  // Fine dry clods, leaf fragments and moist soil, all on the same pixel grid.
  for(let i=0;i<16000;i++){
    const x=Math.floor(rand()*w),y=Math.floor(rand()*h);
    g.fillStyle=['#81735d','#4e4b40','#756c57','#5b5849','#89806a'][i%5];
    g.globalAlpha=.22+rand()*.25;g.fillRect(x,y,1+Math.floor(rand()*3),1+(i%7===0?1:0));
  }
  g.globalAlpha=1;
  // Root shadows, moss and fallen leaves place the existing trees in forest soil.
  for(const tree of woodland){
    const cx=tree[0]/2,cy=tree[1]/2;
    for(let i=0;i<65;i++){
      const a=rand()*Math.PI*2,r=Math.sqrt(rand())*25;
      const x=Math.round(cx+Math.cos(a)*r),y=Math.round(cy+Math.sin(a)*r*.4);
      g.fillStyle=['#424b34','#50573b','#666248','#7c7052','#394536'][i%5];
      g.fillRect(x,y,1+Math.floor(rand()*4),1+Math.floor(rand()*2));
    }
  }
  // Broken, overlapping boot impressions: no continuous road or large flat zones.
  for(let i=0;i<250;i++){
    const t=rand(),x=210+t*555+rand()*80,y=170+t*150+(rand()-.5)*110;
    if(rand()>.68)continue;
    g.fillStyle=i%3?'#514e43':'#7a705d';g.globalAlpha=.38;
    g.fillRect(Math.round(x),Math.round(y),3,1);g.fillRect(Math.round(x+1),Math.round(y+1),2,1);
    g.fillRect(Math.round(x+5),Math.round(y+4),3,1);
  }
  g.globalAlpha=1;
  // Sparse small stones add relief without competing with the units.
  for(let i=0;i<75;i++){
    const x=Math.floor(rand()*w),y=Math.floor(rand()*h),size=2+Math.floor(rand()*3);
    g.fillStyle='#494a40';g.fillRect(x,y+1,size+2,2);
    g.fillStyle='#7b7c6a';g.fillRect(x,y,size,2);
    g.fillStyle='#a2a08a';g.fillRect(x,y,Math.max(1,size-1),1);
  }
}
module.exports=drawForestFloor;
if(require.main===module){
  const fs=require('fs'),path=require('path');
  const {createCanvas}=require(process.env.EAGLE_CANVAS_MODULE||'@napi-rs/canvas');
  const root=path.resolve(__dirname,'..'),woodland=JSON.parse(fs.readFileSync(path.join(root,'data/sources/legacy_woodland.json'))),c=createCanvas(960,540);
  drawForestFloor(c,woodland);fs.writeFileSync(path.join(root,'assets/terrain.png'),c.toBuffer('image/png'));
  console.log('Updated forest clearing: cool bare earth, root moss, leaf litter and boot impressions.');
}
