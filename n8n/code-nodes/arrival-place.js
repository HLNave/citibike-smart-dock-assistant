// works out where to look for docks: coordinates the phone sent, an address we've already looked up,
// or an address that still needs looking up (route "lookup")
const body = $json.body ?? {};
const num = v => { const n = Number(v); return Number.isFinite(n) && n !== 0 ? n : null; };
const base = {
  place: String(body.place ?? '').trim() || 'your destination',
  usualDock: String(body.usualDock ?? '').trim(),
  address: String(body.address ?? '').trim(),
};
const destLat = num(body.destLat), destLon = num(body.destLon), lat = num(body.lat), lon = num(body.lon);

if (destLat !== null && destLon !== null) {
  return [{json:{...base, route:'ready', lat:destLat, lon:destLon, useDest:true}}];
}
if (base.address) {
  const key = base.address.toLowerCase().replace(/\s+/g,' ');
  const cached = ($getWorkflowStaticData('global').places ?? {})[key];
  if (cached) return [{json:{...base, route:'ready', lat:cached.lat, lon:cached.lon, useDest:true, label:cached.label}}];
  return [{json:{...base, route:'lookup', key}}];
}
if (lat !== null && lon !== null) {
  return [{json:{...base, route:'ready', lat, lon, useDest:false}}];
}
return [{json:{...base, route:'ready', failed:'no location from your phone.'}}];
