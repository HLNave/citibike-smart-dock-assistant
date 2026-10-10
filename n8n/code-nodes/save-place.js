// remember looked-up addresses so each one is only looked up once.
// n8n only keeps this on successful runs of the published workflow.
const p = $json;
if (p.isNew && p.key && Number.isFinite(p.lat) && Number.isFinite(p.lon)) {
  const data = $getWorkflowStaticData('global');
  data.places = data.places ?? {};
  data.places[p.key] = { lat:p.lat, lon:p.lon, label:p.label };
}
return [{json:p}];
