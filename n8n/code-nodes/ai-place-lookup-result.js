// second try: the model's street address, looked up in openstreetmap
const req = $('arrival place').first().json;
const hit = $json;
const lat = Number(hit.lat), lon = Number(hit.lon);
if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
  return [{json:{...req, route:'ready',
    failed:`couldnt find ${req.address} in new york city. open the dock arrival shortcut and change the address at the top.`}}];
}
const a = hit.address ?? {};
const street = [a.house_number, a.road].filter(Boolean).join(' ');
// include the borough so a rider can tell a brooklyn match from a manhattan one
const borough = a.suburb || a.city_district || a.borough || '';
const spot = hit.name && street && hit.name !== street ? `${hit.name}, ${street}` : (street || hit.name || req.address);
const label = borough && !spot.includes(borough) ? `${spot}, ${borough}` : spot;
return [{json:{...req, route:'ready', lat, lon, useDest:true, label, isNew:true}}];
