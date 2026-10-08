
const req = $('request fields').first().json;
const geoRaw = $('geocode destination').first().json;
const info = $('nearby station information').first().json;
const status = $('nearby station status').first().json;

let geo = geoRaw;
if (Array.isArray(geoRaw)) geo = geoRaw[0];

// "find me a dock near me" from siri: no destination, so search around the riders gps instead
const hasGps = req.currentLat !== 0 && req.currentLon !== 0;
const nearMe = !String(req.placeQuery ?? '').trim() && hasGps;
const destLat = nearMe ? req.currentLat : Number(geo?.lat);
const destLon = nearMe ? req.currentLon : Number(geo?.lon);
const placeLabel = nearMe ? 'you' : req.placeQuery;

if (!Number.isFinite(destLat) || !Number.isFinite(destLon)) {
  const text = `i couldnt confidently find "${req.placeQuery}" on the map. try giving me a street address, intersection, or a more specific landmark.`;
  return [{json:{text,spokenText:`couldnt find ${req.placeQuery} on the map.`}}];
}

function meters(lat1,lon1,lat2,lon2) {
  const R=6371000, r=x=>x*Math.PI/180;
  const dLat=r(lat2-lat1), dLon=r(lon2-lon1);
  const a=Math.sin(dLat/2)**2+Math.cos(r(lat1))*Math.cos(r(lat2))*Math.sin(dLon/2)**2;
  return 2*R*Math.asin(Math.sqrt(a));
}
function norm(s) {
  return String(s ?? '').toLowerCase().replace(/&/g,' and ').replace(/[^a-z0-9]+/g,' ').replace(/\s+/g,' ').trim();
}
function matchScore(name,q) {
  const a=norm(name), b=norm(q);
  if(!a||!b) return -999;
  if(a===b) return 10000;
  let s=0;
  if(a.includes(b)||b.includes(a)) s+=1800;
  const A=new Set(a.split(' ')), B=new Set(b.split(' '));
  let overlap=0;
  for(const t of B) if(A.has(t)) overlap++;
  s+=(overlap/Math.max(B.size,1))*1000;
  return s-Math.abs(a.length-b.length);
}

const statuses = status?.data?.stations ?? [];
const byId = new Map(statuses.map(s=>[String(s.station_id),s]));

const stations = (info?.data?.stations ?? []).map(s=>{
  const l=byId.get(String(s.station_id)) ?? {};
  const lat=Number(s.lat), lon=Number(s.lon);
  return {
    stationId:String(s.station_id),
    name:String(s.name),
    lat,lon,
    openDocks:Number(l.num_docks_available ?? 0),
    bikesAvailable:Number(l.num_vehicles_available ?? l.num_bikes_available ?? 0),
    isReturning:l.is_returning === undefined ? true : Boolean(l.is_returning),
    isInstalled:l.is_installed === undefined ? true : Boolean(l.is_installed),
    distanceFromDestinationMeters:Math.round(meters(destLat,destLon,lat,lon))
  };
}).filter(s=>Number.isFinite(s.lat)&&Number.isFinite(s.lon));

const canReturn=s=>s&&s.isInstalled&&s.isReturning&&s.openDocks>=2;
const problem = s => !s.isInstalled || !s.isReturning ? 'is closed' : s.openDocks === 0 ? 'is full' : s.openDocks === 1 ? 'is almost full' : 'is too far';
const nearby=stations.filter(s=>s.distanceFromDestinationMeters<=1200)
  .sort((a,b)=>a.distanceFromDestinationMeters-b.distanceFromDestinationMeters || b.openDocks-a.openDocks);
const good=nearby.filter(canReturn);

let usual=null;
if(req.usualStation){
  const ranked=stations.map(s=>({s,score:matchScore(s.name,req.usualStation)})).sort((a,b)=>b.score-a.score);
  if(ranked.length&&ranked[0].score>=250) usual=ranked[0].s;
}

let selected=null;
let reason='nearest good dock';
if(usual && usual.distanceFromDestinationMeters<=1200 && canReturn(usual)){
  selected=usual;
  reason='usual dock is good';
}else if(good.length){
  selected=good[0];
  reason=usual ? 'usual dock needs a reroute' : 'best nearby dock';
}

let prefix='';
if(req.intent==='gps' && hasGps && !nearMe){
  const distance=Math.round(meters(req.currentLat,req.currentLon,destLat,destLon));
  prefix=`youre about ${distance} meters from ${req.placeQuery}. `;
}

if(!selected){
  const text=`${prefix}i couldnt find a station within about 1.2 kilometers of ${placeLabel} that currently has at least 2 open docks.`;
  return [{json:{text,spokenText:`no docks with space near ${placeLabel}.`,matchedPlace:nearMe ? 'current location' : (geo?.display_name ?? req.placeQuery)}}];
}

const url=`https://www.google.com/maps/dir/?api=1&destination=${selected.lat},${selected.lon}&travelmode=bicycling`;
const fromWhere = nearMe ? 'you' : 'the destination';

let text, spokenText;
const d = selected.distanceFromDestinationMeters;
const where = nearMe ? (d < 75 ? 'right there' : `${Math.round(d/50)*50} meters away`)
  : (d < 75 ? `right at ${req.placeQuery}` : `${Math.round(d/50)*50} meters from ${req.placeQuery}`);
if(reason==='usual dock is good'){
  text=`${prefix}your usual dock at ${selected.name} has ${selected.openDocks} open docks right now, so id keep using it.\n\ndirections: ${url}`;
  spokenText=`your usual dock has ${selected.openDocks} docks open.`;
}else if(reason==='usual dock needs a reroute'){
  text=`${prefix}your usual dock isnt the best return option right now. head to ${selected.name} instead — it has ${selected.openDocks} open docks and is about ${selected.distanceFromDestinationMeters} meters from ${placeLabel}.\n\ndirections: ${url}`;
  spokenText=`your usual dock ${problem(usual)}. go to ${selected.name}, ${selected.openDocks} docks, ${where}.`;
}else{
  text=`${prefix}${selected.name} looks like the best return option near ${placeLabel}. it has ${selected.openDocks} open docks and is about ${selected.distanceFromDestinationMeters} meters from ${fromWhere}.\n\ndirections: ${url}`;
  spokenText=`${selected.name} has ${selected.openDocks} docks open, ${where}.`;
}

return [{json:{
  text,
  spokenText,
  matchedPlace:nearMe ? 'current location' : (geo?.display_name ?? req.placeQuery),
  selectedStation:selected,
  alternatives:good.filter(s=>s.stationId!==selected.stationId).slice(0,4),
  lastUpdated:status?.last_updated ?? null
}}];
