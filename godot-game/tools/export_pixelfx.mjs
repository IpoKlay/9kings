// Run with Node: tools/export_pixelfx.mjs /path/to/pixelfx
import { execFileSync } from 'node:child_process';
import { copyFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { resolve, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const source = resolve(process.argv[2] ?? '../../pixelfx');
const revision = 'a84159688af3ca37a4be05a0d422b94451b2e24e';
if (execFileSync('git', ['rev-parse', 'HEAD'], { cwd: source, encoding: 'utf8' }).trim() !== revision)
  throw new Error('Use the pinned PixelFX revision: ' + revision);
const output = resolve(dirname(fileURLToPath(import.meta.url)), '../assets/fx/pixelfx');
const effects = {
  'impacts/ground-slam': { palette: ['#172e32', '#384b3d', '#716541', '#a68b55', '#c5b17a', '#dfca8d', '#f0dfb3'], stone: '#7b7152', reach: 64, light: 0, seed: 5 },
  'lightning/lightning-strike': { palette: ['#172e32', '#344941', '#716541', '#a68b55', '#c89c51', '#dfca8d', '#f4d98c', '#fff1be'], sparks: ['#716541', '#c89c51', '#dfca8d', '#fff1be'], light: 0, seed: 5 },
};
const gold = ['#172e32','#394b43','#706442','#a68b55','#c89c51','#dfca8d','#f4d98c','#fff1be'];
const earth = ['#182d30','#34443d','#555b45','#7b7152','#a18b60','#bdaa78','#d3c299','#ece1bb'];
const water = ['#112f42','#174859','#20677b','#328a98','#55a9ae','#83c4c2','#b6ded1','#e4efda'];
for (const [id,palette] of [
  ['water/wave-crash',water],['holy/divine-shield',gold],['moves/arrow-shot',gold],
  ['fire/flame-pillar',['#241e28','#512b2c','#813c30','#aa5034','#cf783c','#e6a65a','#efcf8d','#fff1be']],
  ['nature/root-snare',earth],['melee/thrust',gold],['shadow/hex-sigil',gold],
  ['melee/hammer-smash',earth],['impacts/heavy-landing',earth],['impacts/blunt-hit',earth],
  ['nature/boulder',earth],['explosions/dirt-explosion',earth],
  ['nature/acid-splash',['#192d30','#34483b','#536d43','#7c924b','#a9b760','#d0cf83','#e4dfad','#f0ebcb']],
  ['nature/poison-cloud',['#192d30','#34483b','#536d43','#7c924b','#a9b760','#d0cf83','#e4dfad','#f0ebcb']],
  ['holy/feather-burst',earth],['nature/leaf-storm',earth]
]) effects[id]={palette, light:0, seed:5};
mkdirSync(output, { recursive: true });
for (const [id, options] of Object.entries(effects)) {
  execFileSync(process.execPath, ['tools/render.mjs', id, '--sheet', '--no-actor', '--fps', '30', '--opts', JSON.stringify(options)], { cwd: source, stdio: 'inherit' });
  for (const ext of ['png', 'json']) copyFileSync(resolve(source, 'records', id, basename(id) + '.' + ext), resolve(output, basename(id) + '.' + ext));
}
for (const file of ['LICENSE', 'NOTICE.md']) copyFileSync(resolve(source, file), resolve(output, file));
writeFileSync(resolve(output, 'source.json'), JSON.stringify({ repository: 'https://github.com/patch-gg/pixelfx', revision, fps: 30, actor: false, effects }, null, 2) + '\n');
