
// called by the ios shortcut arrival automation. returns one short sentence for speak text.
// where to look: set by "arrival place", or by "save place" when the address had to be looked up
const p = $('save place').isExecuted ? $('save place').first().json : $('arrival place').first().json;
const info = $('arrival station information').first().json;
const status = $('arrival station status').first().json;

const place = p.place;
const usualDock = p.usualDock;
const useDest = Boolean(p.useDest);
const centerLat = p.lat, centerLon = p.lon;
const fromWhere = useDest ? place : 'you';

if (p.failed || !Number.isFinite(centerLat) || !Number.isFinite(centerLon)) {
  const text = p.failed || 'no location from your phone.';
  return [{json:{text,spokenText:text}}];
}
// the first time an address is looked up, say what we found so the rider can catch a wrong match during setup
const found = p.isNew && p.label ? `${place} is ${p.label}. ` : '';

function meters(lat1,lon1,lat2,lon2) {
  const R=6371000, r=x=>x*Math.PI/180;
  const dLat=r(lat2-lat1), dLon=r(lon2-lon1);
  const a=Math.sin(dLat/2)**2+Math.cos(r(lat1))*Math.cos(r(lat2))*Math.sin(dLon/2)**2;
  return 2*R*Math.asin(Math.sqrt(a));
}
function norm(s) {
  return String(s ?? '').toLowerCase()
    .replace(/&/g,' and ')
    .replace(/\bstreet\b/g,' st ')
    .replace(/\bavenue\b/g,' ave ')
    .replace(/[^a-z0-9]+/g,' ')
    .replace(/\s+/g,' ').trim();
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
function howFar(m) {
  if (m < 75) return useDest ? `right next to ${place}` : 'right there';
  return useDest ? `${Math.round(m/50)*50} meters from ${place}` : `${Math.round(m/50)*50} meters away`;
}
const docks = n => `${n} ${n===1?'dock':'docks'} open`;

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
    isReturning:l.is_returning === undefined ? true : Boolean(l.is_returning),
    isInstalled:l.is_installed === undefined ? true : Boolean(l.is_installed),
    distanceMeters:Math.round(meters(centerLat,centerLon,lat,lon))
  };
}).filter(s=>Number.isFinite(s.lat)&&Number.isFinite(s.lon));

const canReturn = s => s && s.isInstalled && s.isReturning && s.openDocks >= 2;
const good = stations.filter(s=>s.distanceMeters<=1200 && canReturn(s))
  .sort((a,b)=>a.distanceMeters-b.distanceMeters || b.openDocks-a.openDocks);

let usual = null;
if (usualDock) {
  const ranked = stations.map(s=>({s,score:matchScore(s.name,usualDock)})).sort((a,b)=>b.score-a.score);
  if (ranked.length && ranked[0].score >= 250) usual = ranked[0].s;
}

let text, selected = null;
if (usual && canReturn(usual)) {
  selected = usual;
  text = `your usual dock has ${docks(usual.openDocks)}.`;
} else {
  let lead = '';
  if (usual) {
    const problem = !usual.isInstalled || !usual.isReturning ? 'is closed'
      : usual.openDocks === 0 ? 'is full' : 'is almost full';
    lead = `your usual dock ${problem}. `;
  }
  selected = good.find(s=>!usual || s.stationId!==usual.stationId) ?? null;
  text = selected
    ? (lead ? `${lead}go to ${selected.name}, ${selected.openDocks} docks, ${howFar(selected.distanceMeters)}.`
            : `${selected.name} has ${docks(selected.openDocks)}, ${howFar(selected.distanceMeters)}.`)
    : `${lead}no docks with space near ${fromWhere}.`;
}

return [{json:{
  text: found + text,
  spokenText: found + text,
  selectedStation:selected,
  usualMatched:usual ? usual.name : null,
  centeredOn:useDest ? 'destination' : 'current location',
  matchedPlace:p.label ?? null,
  lastUpdated:status?.last_updated ?? null
}}];
