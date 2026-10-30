// Data texture only. Leaves the approved atlas and all route coordinates intact.
const fs=require('fs'),path=require('path');
const {createCanvas,loadImage}=require(process.env.EAGLE_CANVAS_MODULE||'@napi-rs/canvas');
const d3=require('./map-source/d3.cjs'),geometry=require('./map-source/geometry.json');
async function buildShore(){
 const root=path.resolve(__dirname,'..');
 const source=await loadImage(path.join(root,'assets/expedition/atlas.png'));
 const {width:w,height:h}=source,canvas=createCanvas(w,h),g=canvas.getContext('2d');
 g.drawImage(source,0,0);
 const pixels=g.getImageData(0,0,w,h).data,wet=new Uint8Array(w*h),dist=new Float32Array(w*h);
 const landContext=createCanvas(w,h).getContext('2d');
 landContext.scale(.5,.5);
 const projection=d3.geoMercator().fitExtent([[40,28],[w*2-40,h*2-38]],{type:'MultiPoint',coordinates:[[-10,28],[40,46.8]]});
 landContext.beginPath();d3.geoPath(projection,landContext)(geometry.land);landContext.fill();
 const land=landContext.getImageData(0,0,w,h).data;
 for(let i=0;i<wet.length;i++){
  const r=pixels[i*4],green=pixels[i*4+1],b=pixels[i*4+2];
  wet[i]=(land[i*4+3]<=120&&b-r>16&&green-r>12&&b-green>=-16)?1:0;
  dist[i]=wet[i]?64:0;
 }
 // The texture edges are open sea, so only actual dry pixels seed the distance.
 for(let y=1;y<h;y++)for(let x=1;x<w;x++){
  const i=y*w+x;dist[i]=Math.min(dist[i],dist[i-1]+1,dist[i-w]+1,dist[i-w-1]+1.4142);
 }
 for(let y=h-2;y>=0;y--)for(let x=w-2;x>=0;x--){
  const i=y*w+x;dist[i]=Math.min(dist[i],dist[i+1]+1,dist[i+w]+1,dist[i+w+1]+1.4142);
 }
 const out=g.createImageData(w,h);
 for(let i=0;i<wet.length;i++){
  out.data[i*4]=Math.round(Math.min(32,dist[i])/32*255);
  out.data[i*4+1]=wet[i]*255;out.data[i*4+3]=255;
 }
 g.putImageData(out,0,0);
 fs.writeFileSync(path.join(root,'assets/expedition/shore_distance.png'),canvas.toBuffer('image/png'));
 console.log('Built coast distance + water mask at '+w+'×'+h+'; atlas unchanged.');
}
module.exports=buildShore;
if(require.main===module)buildShore().catch(error=>{console.error(error);process.exitCode=1;});
