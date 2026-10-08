
const data=$json;
const stations=data?.data?.stations ?? [];
let bikes=0,docks=0,full=0,oneDock=0,accepting=0,active=0;

for(const s of stations){
  const b=Number(s.num_vehicles_available ?? s.num_bikes_available ?? 0);
  const d=Number(s.num_docks_available ?? 0);
  const installed=s.is_installed===undefined ? true : Boolean(s.is_installed);
  const returning=s.is_returning===undefined ? true : Boolean(s.is_returning);
  bikes+=Number.isFinite(b)?b:0;
  docks+=Number.isFinite(d)?d:0;
  if(installed) active++;
  if(installed&&returning) accepting++;
  if(installed&&returning&&d===0) full++;
  if(installed&&returning&&d===1) oneDock++;
}
const text=`right now the live feed shows ${bikes.toLocaleString()} bikes available and ${docks.toLocaleString()} open docks across ${active.toLocaleString()} active stations. ${full.toLocaleString()} stations are full and ${oneDock.toLocaleString()} more only have 1 open dock.`;
const spokenText=`${bikes.toLocaleString()} bikes and ${docks.toLocaleString()} open docks citywide. ${full.toLocaleString()} stations are full.`;
return [{json:{text,spokenText,lastUpdated:data?.last_updated ?? null}}];
