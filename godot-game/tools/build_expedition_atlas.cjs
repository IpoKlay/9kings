// Offline geography-only asset build. Does not modify battle art or route rules.
const fs=require('fs'),path=require('path');
const {createCanvas}=require(process.env.EAGLE_CANVAS_MODULE||'@napi-rs/canvas');
const data=require('./data_source.cjs').expedition(),geometry=require('./map-source/geometry.json');
const coords=Object.fromEntries(data.nodes.map(n=>[n.id,n.longitude!==undefined?[n.longitude,n.latitude]:geometry.coords[n.id]]));
const art=require('./map-source/art.cjs')({createCanvas,d3:require('./map-source/d3.cjs'),mapRules:data,mapData:{...geometry,coords},mapSize:require('../data/schema/contracts.json').map_world_size});
const root=path.resolve(__dirname,'..');
fs.writeFileSync(path.join(root,'assets/expedition/atlas.png'),art.canvas.toBuffer('image/png'));
fs.writeFileSync(path.join(root,'data/generated/atlas_positions.json'),JSON.stringify(art.positions,null,2)+'\n');
// Sparse offshore highlights; sample the generated water palette and stay away
// from cities. These coordinates animate only sea pixels in the native scene.
const ctx=art.canvas.getContext('2d'),water=[];
for(let y=40;y<1220;y+=95)for(let x=45;x<2840;x+=123){
 const xx=x+((y*7)%57),yy=y+((x*3)%43),c=ctx.getImageData(xx,yy,1,1).data;
 if(c[2]>c[0]+45 && c[1]>c[0]+20 && !Object.values(art.positions).some(p=>Math.hypot(p[0]-xx*2,p[1]-yy*2)<120))water.push([xx*2,yy*2]);
}
fs.writeFileSync(path.join(root,'data/generated/legacy_water_points.json'),JSON.stringify(water)+'\n');
console.log('Atlas: 2880 × 1260 pixel texture, 55 geographic anchors, 5760 × 2520 logical world.');
require('./build_atlas_shore.cjs')().catch(error=>{console.error(error);process.exitCode=1;});
