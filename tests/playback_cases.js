var location, document, navigator, window;
let count=0;
function check(host,durations,expected,tag='VIDEO',paused=false) {
 location={hostname:host,href:'https://'+host+'/article',pathname:'/article',origin:'https://'+host};
 const media=durations.map(duration=>({tagName:tag,duration,paused,ended:false,readyState:4,currentTime:2,playbackRate:1}));
 document={querySelectorAll:()=>media,querySelector:()=>null,getElementById:()=>null,hasFocus:()=>true,visibilityState:'visible',title:'Article'};
 navigator={mediaSession:{playbackState:'playing',metadata:null}};
 window={};
 for(let i=0;i<expressions.length;i++) {
  const result=eval(expressions[i]);
  const actual=i===0?result.split('|')[1]==='1':JSON.parse(result).playing;
  if(actual!==expected)throw Error(JSON.stringify({host,durations,expected,result,stage:i}));
  count++;
 }
}
for(const host of ['nytimes.com','www.nytimes.com','washingtonpost.com','www.washingtonpost.com']) {
 for(const d of [0,0.5,9,9.999,NaN])check(host,[d],false);
 for(const d of [10,10.1,120,Infinity])check(host,[d],true);
 check(host,[3,60],true);
 check(host,[60],false,'VIDEO',true);
 check(host,[],false);
 check(host,[3],true,'AUDIO');
}
for(const host of ['example.com','notnytimes.com','nytimes.com.example.org','youtube.com'])check(host,[3],host!=='youtube.com');
console.log('Passed '+count+' playback checks across both JavaScript paths.');
