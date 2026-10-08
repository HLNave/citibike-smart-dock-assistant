
// siri reads "St" as "saint", "id" as "I.D." and spells out links, so tidy the sentence before it gets spoken.
// station names get shortened the way new yorkers say them: "W 15 St & 6 Ave" -> "West 15th and 6th"
function ordinal(n) {
  const v=n%100;
  return n + (v>=11&&v<=13 ? 'th' : ({1:'st',2:'nd',3:'rd'}[n%10] || 'th'));
}
const contractions = {
  i:'I', id:"I'd", ill:"I'll", im:"I'm", ive:"I've",
  youre:"you're", isnt:"isn't", couldnt:"couldn't", didnt:"didn't", cant:"can't", dont:"don't"
};
function forSpeech(s) {
  return String(s ?? '')
    .replace(/https?:\/\/\S+/g,'')
    .replace(/directions:\s*/gi,'')
    .replace(/&/g,' and ')
    .replace(/\bE\b(?=\s+\d)/g,'East')
    .replace(/\bW\b(?=\s+\d)/g,'West')
    .replace(/\b(\d+)\s+(St|Ave)\b/g,(m,n)=>ordinal(Number(n)))
    .replace(/\s+(St|Ave|Pl|Blvd|Rd|Dr)\b(?!\s+[A-Z0-9])/g,'')
    .replace(/\bAve\b/g,'Avenue')
    .replace(/\bPl\b/g,'Place')
    .replace(/\bBlvd\b/g,'Boulevard')
    .replace(/\b(i|id|ill|im|ive|youre|isnt|couldnt|didnt|cant|dont)\b/g,w=>contractions[w])
    .replace(/\s+/g,' ').trim();
}
return [{json:{spokenText:forSpeech($json.spokenText ?? $json.text)}}];
