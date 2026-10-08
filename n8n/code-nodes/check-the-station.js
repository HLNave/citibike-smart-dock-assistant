
const req = $('request fields').first().json;
const info = $('station information').first().json;
const status = $('station live status').first().json;
const query = String(req.stationQuery ?? '').trim();

function norm(s) {
  return String(s ?? '').toLowerCase()
    .replace(/&/g,' and ')
    .replace(/\bstreet\b/g,' st ')
    .replace(/\bavenue\b/g,' ave ')
    .replace(/\broad\b/g,' rd ')
    .replace(/\bboulevard\b/g,' blvd ')
    .replace(/[^a-z0-9]+/g,' ')
    .replace(/\s+/g,' ').trim();
}
function score(name, q, id) {
  if (String(q) === String(id)) return 100000;
  const a = norm(name), b = norm(q);
  if (!a || !b) return -999;
  if (a === b) return 10000;
  let s = 0;
  if (a.includes(b) || b.includes(a)) s += 2000;
  const A = new Set(a.split(' ')), B = new Set(b.split(' '));
  let overlap = 0;
  for (const t of B) if (A.has(t)) overlap++;
  s += (overlap / Math.max(B.size,1)) * 1200;
  s -= Math.abs(a.length-b.length);
  return s;
}
function meters(lat1,lon1,lat2,lon2) {
  const R=6371000, r=x=>x*Math.PI/180;
  const dLat=r(lat2-lat1), dLon=r(lon2-lon1);
  const a=Math.sin(dLat/2)**2+Math.cos(r(lat1))*Math.cos(r(lat2))*Math.sin(dLon/2)**2;
  return 2*R*Math.asin(Math.sqrt(a));
}

const infos = info?.data?.stations ?? [];
const statuses = status?.data?.stations ?? [];
const byId = new Map(statuses.map(s=>[String(s.station_id),s]));

const ranked = infos.map(s=>({s,score:score(s.name,query,s.station_id)})).sort((a,b)=>b.score-a.score);

if (!ranked.length || ranked[0].score < 250) {
  const matches = ranked.slice(0,5).map(x=>x.s.name);
  const text = `i couldnt confidently match "${query}" to a citibike station. closest matches: ${matches.join(', ')}.`;
  return [{json:{text,spokenText:`couldnt find a station called ${query}.`}}];
}

const i = ranked[0].s;
const live = byId.get(String(i.station_id)) ?? {};
const target = {
  stationId:String(i.station_id),
  name:String(i.name),
  lat:Number(i.lat),
  lon:Number(i.lon),
  openDocks:Number(live.num_docks_available ?? 0),
  bikesAvailable:Number(live.num_vehicles_available ?? live.num_bikes_available ?? 0),
  isReturning:live.is_returning === undefined ? true : Boolean(live.is_returning),
  isInstalled:live.is_installed === undefined ? true : Boolean(live.is_installed)
};
const canReturn = s => s && s.isInstalled && s.isReturning && s.openDocks >= 2;

const alternatives = infos.map(s=>{
  const l=byId.get(String(s.station_id)) ?? {};
  return {
    stationId:String(s.station_id),
    name:String(s.name),
    lat:Number(s.lat),
    lon:Number(s.lon),
    openDocks:Number(l.num_docks_available ?? 0),
    bikesAvailable:Number(l.num_vehicles_available ?? l.num_bikes_available ?? 0),
    isReturning:l.is_returning === undefined ? true : Boolean(l.is_returning),
    isInstalled:l.is_installed === undefined ? true : Boolean(l.is_installed),
    distanceMeters:Math.round(meters(target.lat,target.lon,Number(s.lat),Number(s.lon)))
  };
}).filter(s=>s.stationId!==target.stationId && s.distanceMeters<=1200 && canReturn(s))
  .sort((a,b)=>a.distanceMeters-b.distanceMeters || b.openDocks-a.openDocks);

let selected = target;
let text, spokenText;
const away = m => m < 75 ? 'right there' : `${Math.round(m/50)*50} meters away`;
const problem = s => !s.isInstalled || !s.isReturning ? 'is closed' : s.openDocks === 0 ? 'is full' : s.openDocks === 1 ? 'is almost full' : 'is too far';

if (canReturn(target)) {
  text = `${target.name} has ${target.openDocks} open docks right now, so youre good to return there. it also has ${target.bikesAvailable} bikes available.`;
  spokenText = `${target.name} has ${target.openDocks} docks open.`;
} else if (alternatives.length) {
  selected = alternatives[0];
  const url = `https://www.google.com/maps/dir/?api=1&destination=${selected.lat},${selected.lon}&travelmode=bicycling`;
  text = `${target.name} only has ${target.openDocks} open docks right now or isnt accepting returns. head to ${selected.name} instead — it has ${selected.openDocks} open docks and is about ${selected.distanceMeters} meters away.\n\ndirections: ${url}`;
  spokenText = `${target.name} ${problem(target)}. go to ${selected.name}, ${selected.openDocks} docks, ${away(selected.distanceMeters)}.`;
} else {
  text = `${target.name} only has ${target.openDocks} open docks right now or isnt accepting returns, and i couldnt find another station within about 1.2 kilometers with at least 2 open docks.`;
  spokenText = `${target.name} ${problem(target)}, and nothing nearby has space.`;
}

return [{json:{
  text,
  spokenText,
  selectedStation:selected,
  alternatives:alternatives.slice(0,4),
  lastUpdated:status?.last_updated ?? null
}}];
