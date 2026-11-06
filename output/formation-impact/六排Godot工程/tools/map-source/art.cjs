// Approved map art, retained as an offline texture generator only.
module.exports=function({createCanvas,d3,mapRules,mapData,mapSize=[1920,840]}){
const canvas=createCanvas(960,420);const document={createElement:()=>createCanvas(1,1)};
const select=s=>s==='.map-scene'?{clientWidth:mapSize[0],clientHeight:mapSize[1]}:canvas;
 const X=mapRules,D=mapData;
 const nodes=X.nodes.map(n=>({...n,coords:D.coords[n.id]})),byId=Object.fromEntries(nodes.map(n=>[n.id,n])),land=D.land;
 const $=select;
 function rng(x,y,s=1){let t=Math.imul(x+7919,s*374761393)^Math.imul(y+104729,668265263);t=Math.imul(t^(t>>>13),1274126177);return((t^(t>>>16))>>>0)/4294967295;}
 function noise(x,y,s=1){const a=Math.floor(x),b=Math.floor(y),u=x-a,v=y-b,k=u*u*(3-2*u),l=v*v*(3-2*v);return(1-l)*((1-k)*rng(a,b,s)+k*rng(a+1,b,s))+l*((1-k)*rng(a,b+1,s)+k*rng(a+1,b+1,s));}
 function smoothstep(a,b,v){const t=Math.max(0,Math.min(1,(v-a)/(b-a)));return t*t*(3-2*t);}
 function mixColor(a,b,t){return a.map((v,i)=>Math.round(v+(b[i]-v)*t));}
 // One continuous moisture field drives both the soil and its vegetation.
 // Coherent variation breaks up the old straight latitude/longitude seams.
 function aridity(x,y,lon,lat){
  const localLat=lat+(noise(x/130,y/130,21)-.5)*1.3+(noise(x/48,y/48,22)-.5)*.5;
  const localLon=lon+(noise(x/105,y/105,25)-.5)*1.2;
  const south=1-smoothstep(33.5,36.9,localLat);
  const west=(1-smoothstep(-3.2,1.2,localLon))*(1-smoothstep(37.2,40.8,localLat));
  const east=smoothstep(26.8,31.2,localLon)*(1-smoothstep(37.2,40.8,localLat));
  const dry=1-(1-south)*(1-west)*(1-east);
  return Math.max(0,Math.min(1,dry+(noise(x/27,y/27,23)-.5)*.28*4*dry*(1-dry)));
 }
 function rect(g,x,y,w,h,c){g.fillStyle=c;g.fillRect(Math.round(x),Math.round(y),w,h);}
 function town(canvas,kind,current,seen){const g=canvas.getContext('2d');g.clearRect(0,0,64,50);const r=(x,y,w,h,c)=>rect(g,x,y,w,h,c);
  // Roof planes, arcades, walls and a harbour are drawn on an integer pixel grid.
  r(6,37,53,5,'#18334288');r(9,35,47,5,'#8c8768');r(10,33,44,3,'#d8c797');
  const house=(x,y,w,h)=>{r(x,y,w,h,'#b7ab83');r(x+w-4,y,4,h,'#827e66');r(x,y-2,w,3,'#8e4636');r(x+2,y-4,w-4,2,'#be6a43');r(x+4,y-5,w-8,1,'#e29156');r(x+2,y+3,2,3,'#4c5148');r(x+w-7,y+h-5,3,5,'#575146');};
  house(10,25,13,11);house(40,24,14,12);house(29,18,16,15);house(17,19,16,15);
  r(22,18,19,17,'#d7c99e');r(36,18,5,17,'#9c987c');r(20,16,23,3,'#864433');r(23,13,17,3,'#b96742');r(27,11,9,2,'#db8f53');
  for(const x of [24,29,34]){r(x,21,2,11,'#f3e0ad');r(x+2,22,1,10,'#9d9677');}r(21,32,22,2,'#ead6a0');r(20,34,24,2,'#beae80');
  if(['boss','final','elite'].includes(kind)){for(const x of [7,49]){r(x,23,7,15,'#8b8c77');r(x,21,2,4,'#ded0a3');r(x+5,21,2,4,'#ded0a3');r(x+1,25,3,11,'#c3b98f');r(x+3,28,2,4,'#555d55');}r(14,35,35,3,'#c2b38b');}
  if(kind==='port'){r(48,38,13,2,'#775a40');r(59,36,2,9,'#bca16e');r(54,43,9,2,'#79523c');r(57,32,1,12,'#bda875');r(58,33,5,7,'#f2e3b5');}
  if(current||seen){r(31,1,1,12,'#efd38b');r(32,2,9,7,current?'#b94c3c':'#aa9254');r(34,3,2,3,'#f6dc8d');}
 }
 let bridge,projection,W=1280,H=700,pxScale=2,lastSize='',selected=null;
 function tree(g,x,y,palm=false){if(palm){rect(g,x,y,1,6,'#7d623c');rect(g,x-3,y,7,1,'#3e6b43');rect(g,x-2,y-1,5,1,'#668a4b');rect(g,x-4,y+1,2,2,'#305d3e');rect(g,x+3,y+1,2,2,'#305d3e');return;}rect(g,x+1,y+3,1,4,'#5c5136');rect(g,x-2,y+3,7,2,'#244d3a');rect(g,x-3,y,8,3,'#355e3b');rect(g,x-1,y-2,5,3,'#4c7441');rect(g,x,y-1,3,1,'#7c984c');}
 function mountain(g,x,y,size,snow){for(let a=0;a<size;a++){const w=Math.floor(a*.9)+1;rect(g,x-w,y+a,w+2,1,a<size*.2&&snow?'#d6d8bd':'#a5a17e');rect(g,x+2,y+a,w*.8,1,a<size*.2&&snow?'#acb7a5':'#67796a');if(a>3&&a%3===0)rect(g,x-w+2,y+a,w*.8,1,'#b5ae87');}rect(g,x-size*.9,y+size,size*1.8,1,'#4e6b49');}
function drawWorld(){const map=$('.map-scene');W=map.clientWidth;H=map.clientHeight;if(!W)return;projection=d3.geoMercator().fitExtent([[40,28],[W-40,H-38]],{type:'MultiPoint',coordinates:[[-10,28],[40,46.8]]});const canvas=$('.map-world'),w=canvas.width=Math.ceil(W/pxScale),h=canvas.height=Math.ceil(H/pxScale),g=canvas.getContext('2d');const mask=document.createElement('canvas');mask.width=w;mask.height=h;const m=mask.getContext('2d');m.scale(1/pxScale,1/pxScale);m.beginPath();d3.geoPath(projection,m)(land);m.fill();const bits=m.getImageData(0,0,w,h).data;const isLand=new Uint8Array(w*h),dist=new Float32Array(w*h);for(let i=0;i<w*h;i++){isLand[i]=bits[i*4+3]>120?1:0;dist[i]=999;}for(let y=1;y<h-1;y++)for(let x=1;x<w-1;x++){const i=y*w+x;if(isLand[i]!==isLand[i-1]||isLand[i]!==isLand[i+1]||isLand[i]!==isLand[i-w]||isLand[i]!==isLand[i+w])dist[i]=0;}for(let y=1;y<h;y++)for(let x=1;x<w;x++){const i=y*w+x;dist[i]=Math.min(dist[i],dist[i-1]+1,dist[i-w]+1,dist[i-w-1]+1.4);}for(let y=h-2;y>=0;y--)for(let x=w-2;x>=0;x--){const i=y*w+x;dist[i]=Math.min(dist[i],dist[i+1]+1,dist[i+w]+1,dist[i+w+1]+1.4);}
const img=g.createImageData(w,h),pal={deep:['#174365','#1b4b70','#1e5279','#225c80'],shallow:['#347e92','#469898','#68aaa0'],grass:['#547a46','#63894b','#77964f','#8da65b','#a3af65'],dry:['#b79d59','#c0a963','#d0b978','#ddc78c','#b49f62']};
const rgb=c=>c.match(/\w\w/g).map(x=>parseInt(x,16));
const converted=Object.fromEntries(Object.entries(pal).map(([k,v])=>[k,v.map(c=>rgb(c.slice(1)))]));
const dryness=new Float32Array(w*h);
for(let y=0;y<h;y++)for(let x=0;x<w;x++){
 const i=y*w+x,geo=projection.invert([x*pxScale,y*pxScale]),lon=geo[0],lat=geo[1],v=noise(x/18,y/18,7)*.65+noise(x/6,y/6,3)*.35;
 let c;
 if(!isLand[i]){
  c=dist[i]<2?rgb('93beb0'):dist[i]<5?converted.shallow[2]:dist[i]<9?converted.shallow[1]:dist[i]<14?converted.shallow[0]:converted.deep[Math.min(3,Math.floor(v*4))];
  if(dist[i]>10&&rng(x,y,4)>.996)c=rgb('3b7392');
 }else{
  const dry=dryness[i]=aridity(x,y,lon,lat),shade=Math.min(4,Math.floor(v*5));
  // Limited intermediate shades and light pixel dithering, never blur the atlas.
  const blend=Math.max(0,Math.min(12,Math.round(dry*12+(rng(x,y,24)-.5)*.65)))/12;
  c=mixColor(converted.grass[shade],converted.dry[shade],blend);
  if(dist[i]<1.5)c=rgb('e8d398');
  else if(dist[i]<3)c=rgb('c5b677');
  else if(rng(x,y,9)>.97)c=mixColor(rgb('98b568'),rgb('e1cc90'),blend);
 }
 img.data.set([...c,255],i*4);
}
g.putImageData(img,0,0);
// All decoration is clipped to land; it is illustrative rather than elevation data.
const closeToCity=(x,y)=>nodes.some(n=>{const p=projection(n.coords);return Math.hypot(x-p[0]/pxScale,y-p[1]/pxScale)<17;});
for(let y=8;y<h-8;y+=5)for(let x=6;x<w-6;x+=5){
 const xx=x+Math.floor(rng(x,y)*5),yy=y+Math.floor(rng(y,x)*4),i=yy*w+xx;
 if(!isLand[i]||dist[i]<7||closeToCity(xx,yy))continue;
 const dry=dryness[i],cluster=noise(xx/24,yy/24,5),roll=rng(x,y,6);
 if(cluster>.48+.16*dry&&roll>1-.40*Math.pow(1-dry,1.5)){
  tree(g,xx,yy);
 }else if(dry>.92&&dist[i]<18&&roll>.7){
  tree(g,xx,yy,true);
 }else if(dry>.08&&dry<.96&&cluster>.38&&rng(x,y,27)<.20*Math.sin(dry*Math.PI)){
  // Low scrub replaces the thinning tree canopy before giving way to bare sand.
  rect(g,xx,yy+2,4,1,'#8a8550');
  rect(g,xx+1,yy,2,2,dry>.6?'#929551':'#6e8549');
  rect(g,xx-1,yy+1,2,1,dry>.6?'#b0a461':'#8e9e58');
 }
}
const ranges=[[[6,45],[8,46],[10,46.4],[12,46.5],[14,46.5]],[[0,42.7],[1.5,42.6],[3,42.5]],[[10.5,43.5],[12,42.5],[13.2,41.5],[15.4,39.6]],[[20,40.5],[21,39.5],[22,38.5]],[[29,40],[31,40],[33,40.4],[35,40]], [[-7,31.5],[-5,32.8],[-3,33.5],[0,34.5],[3,35.3]]];for(let r=0;r<ranges.length;r++)for(const [lon,lat]of (mapSize[0]>1920 ? ranges[r].flatMap((p,i,a)=>i===a.length-1?[p]:Array.from({length:5},(_,j)=>[p[0]+(a[i+1][0]-p[0])*j/5,p[1]+(a[i+1][1]-p[1])*j/5])) : ranges[r])){const [sx,sy]=projection([lon,lat]);const x=Math.round(sx/pxScale),y=Math.round(sy/pxScale);if(x<8||x>=w-9||y<7||y>=h-14||!isLand[y*w+x]||closeToCity(x,y))continue;mountain(g,x,y-5,9+(r===0?3:0),r===0);}
// Discrete wave crests retain the logical pixel grid.
for(let y=7;y<h-3;y+=11)for(let x=6;x<w-10;x+=19){const yy=y+Math.floor(rng(x,y,8)*5),i=yy*w+x;if(!isLand[i]&&dist[i]>5&&rng(x,y,2)>.4){rect(g,x,yy,5,1,'#477f98');rect(g,x+5,yy-1,3,1,'#376e8c');}}
render();}

function render(){}
drawWorld();return {canvas,town,positions:Object.fromEntries(nodes.map(n=>[n.id,projection(n.coords)]))};
};
