
const req=$json;
let text;
if(req.alias && req.rememberedStation){
  text=`got it — ill treat ${req.rememberedStation} as your ${req.alias} dock in this conversation.`;
}else if(req.rememberedStation){
  text=`got it — ill remember ${req.rememberedStation} as one of your usual docks in this conversation.`;
}else{
  text=`got it. if you tell me the exact citibike station name and what you call it, like "my school dock is e 17 st & broadway", ill remember it for this chat.`;
}
const spokenText = req.rememberedStation
  ? (req.alias ? `got it, ${req.rememberedStation} is your ${req.alias} dock.` : `got it, ill remember ${req.rememberedStation}.`)
  : text;
return [{json:{text,spokenText}}];
