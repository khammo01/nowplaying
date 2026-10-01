var location, document, navigator, window;
let count=0;
function check(host,durations,expected,tag='VIDEO',paused=false,path='/article') {
 location={hostname:host,href:'https://'+host+path,pathname:path,origin:'https://'+host};
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
for(const host of ['google.com','www.google.com']) {
 check(host,[30],false);
 check(host,[30],false,'AUDIO');
 check(host,[],false);
}
for(const host of ['example.com','notnytimes.com','nytimes.com.example.org','youtube.com'])check(host,[3],true);
check('youtube.com',[30],false,'VIDEO',false,'/');
check('nextdoor.com',[30],false);
check('www.nextdoor.com',[30],false);

// Safari can retain ytInitialPlayerResponse and description DOM from the
// previous watch page while movie_player already points at the new video.
// Never publish that stale description or summary for the current video.
location={hostname:'www.youtube.com',href:'https://www.youtube.com/watch?v=current123',pathname:'/watch',origin:'https://www.youtube.com'};
URL=function(u){
 const m=String(u).match(/^https?:\/\/([^/]+)(\/[^?]*)?(?:\?(.*))?$/);
 this.hostname=m?.[1]||'';
 this.pathname=m?.[2]||'/';
 const params=new Map((m?.[3]||'').split('&').filter(Boolean).map(x=>x.split('=')));
 this.searchParams={get:k=>params.get(k)||null};
};
const currentPlayer={
 getPlayerState:()=>2,
 getVideoData:()=>({video_id:'current123',title:'Current video',author:'Current channel',shortDescription:''}),
 getCurrentTime:()=>15,
 getDuration:()=>120,
 getPlaybackRate:()=>1,
 className:'paused-mode'
};
const staleNode={textContent:'Wrong old-video description and AI summary',getAttribute:()=> 'Wrong old-video metadata'};
document={
 querySelectorAll:()=>[],
 querySelector:s=>s.includes('description')||s.includes('video-summary')?staleNode:null,
 getElementById:id=>id==='movie_player'?currentPlayer:null,
 hasFocus:()=>true,
 visibilityState:'visible',
 title:'Current video - YouTube'
};
navigator={mediaSession:{playbackState:'paused',metadata:null}};
window={ytInitialPlayerResponse:{videoDetails:{videoId:'old456',title:'Old video',shortDescription:'Wrong old-video description'}}};
const staleResult=JSON.parse(eval(expressions[1]));
if(staleResult.video_id!=='current123'||staleResult.description!==''||staleResult.summary!=='')
 throw Error(JSON.stringify({case:'stale-youtube-metadata',result:staleResult}));
count++;
console.log('Passed '+count+' playback checks across both JavaScript paths.');
