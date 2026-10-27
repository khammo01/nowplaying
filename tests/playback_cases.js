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
// Reject every playback signal on shopping, news, unknown and lookalike hosts.
for(const host of ['amazon.com','www.amazon.com','amazon.co.uk','nytimes.com',
 'www.nytimes.com','washingtonpost.com','www.washingtonpost.com',
 'google.com','nextdoor.com','example.com','notyoutube.com',
 'youtube.com.example.org','spotify.com.evil.test','notudemy.com','udemy.com.evil.test']) {
 for(const d of [0,3,10,120,Infinity,NaN])check(host,[d],false);
 check(host,[120],false,'AUDIO');
 check(host,[],false); // Media Session alone must not activate playback.
}
const allowed=['youtube.com','youtu.be','netflix.com','hulu.com','disneyplus.com',
 'max.com','hbomax.com','primevideo.com','tv.apple.com','peacocktv.com',
 'paramountplus.com','twitch.tv','vimeo.com','udemy.com','dailymotion.com','crunchyroll.com',
 'tubi.tv','pluto.tv','spotify.com','music.apple.com','music.amazon.com',
 'soundcloud.com','pandora.com','tidal.com','deezer.com','bandcamp.com','app.plex.tv'];
for(const host of allowed){
 check(host,[120],true);
 check('www.'+host,[120],true);
 check(host,[3],true,'AUDIO');
}
check('youtube.com',[30],false,'VIDEO',false,'/');
check('music.youtube.com',[120],true,'AUDIO',false,'/watch');
check('company.udemy.com',[120],true,'VIDEO',false,'/course/example/learn/lecture/1');
// An embedded player on an unlisted top-level site must remain ignored.
check('amazon.com',[120,120],false);

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

// YouTube SPA navigation can update the canonical URL and visible summary
// before ytInitialPlayerResponse. The canonical current-video ID makes that
// visible metadata safe to use.
const currentSummary='A concise current-video AI summary.';
document.querySelector=s=>{
 if(s==='link[rel="canonical"]')return {getAttribute:()=> 'https://www.youtube.com/watch?v=current123'};
 if(s.includes('video-summary'))return {textContent:currentSummary,getAttribute:()=>''};
 return null;
};
const canonicalResult=JSON.parse(eval(expressions[1]));
if(canonicalResult.summary!==currentSummary)
 throw Error(JSON.stringify({case:'canonical-current-youtube-metadata',result:canonicalResult}));
count++;
// Non-YouTube pages supply semantic metadata without copying navigation text.
location={hostname:'company.udemy.com',href:'https://company.udemy.com/course/security/learn/lecture/123#overview',pathname:'/course/security/learn/lecture/123',origin:'https://company.udemy.com'};
const lectureMedia={tagName:'VIDEO',duration:338,paused:false,ended:false,readyState:4,currentTime:321,playbackRate:1};
const node=t=>({textContent:t,innerText:t});
const courseDescription='A basic security course covering phishing, safe browsing, passwords, social engineering and data leakage.';
const descriptionHeading={...node('Description'),tagName:'H2',nextElementSibling:node(courseDescription)};
const learningHeading={...node("What you'll learn"),tagName:'H2',nextElementSibling:node('Spot scam emails and suspicious links.')};
const courseLD={textContent:JSON.stringify({'@context':'https://schema.org','@type':'Course',name:'Security Awareness Training',description:'Short structured course description.',author:{'@type':'Person',name:'Michael Biocchi'}})};
document={
 querySelectorAll:s=>s==='video,audio'?[lectureMedia]:s==='script[type="application/ld+json"]'?[courseLD]:s==='h1,h2,h3,h4'?[descriptionHeading,learningHeading]:[],
 querySelector:s=>s==='[data-purpose="lecture-title"]'?node('5. Introduction to Phishing'):s==='h1'?node('Security Awareness Training'):null,
 getElementById:()=>null,hasFocus:()=>true,visibilityState:'visible',title:'Security Awareness Training'
};
navigator={mediaSession:{playbackState:'playing',metadata:null}};window={};
const courseResult=JSON.parse(eval(expressions[1]));
if(courseResult.title!=='Security Awareness Training · Introduction to Phishing'||courseResult.channel!=='Michael Biocchi'||!courseResult.description.includes(courseDescription)||!courseResult.description.includes('Spot scam emails')||courseResult.video_id!=='')throw Error(JSON.stringify({case:'udemy-course-context',courseResult}));
count++;
// A supported site with only standard page metadata still has a description.
location={hostname:'vimeo.com',href:'https://vimeo.com/123',pathname:'/123',origin:'https://vimeo.com'};
document.querySelectorAll=s=>s==='video,audio'?[lectureMedia]:[];
document.querySelector=s=>s==='meta[property="og:description"]'?{getAttribute:()=> 'An educational video about recognizing suspicious links.'}:null;
const genericResult=JSON.parse(eval(expressions[1]));
if(genericResult.description!=='An educational video about recognizing suspicious links.')throw Error(JSON.stringify({case:'generic-page-description',genericResult}));
count++;
// Malformed structured data is ignored; page metadata remains usable.
document.querySelectorAll=s=>s==='video,audio'?[lectureMedia]:s==='script[type="application/ld+json"]'?[{textContent:'broken JSON'}]:[];
const malformedResult=JSON.parse(eval(expressions[1]));
if(malformedResult.description!==genericResult.description)throw Error('malformed JSON-LD broke metadata fallback');
count++;

console.log('Passed '+count+' playback checks across both JavaScript paths.');
