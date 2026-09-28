on escape_json(s)
	if s is missing value then return ""
	set s to s as string
	set s to my replace_chars(s, "\\", "\\\\")
	set s to my replace_chars(s, "\"", "\\\"")
	set s to my replace_chars(s, return, "")
	set s to my replace_chars(s, linefeed, "")
	return s
end escape_json


on replace_chars(this_text, search_string, replacement_string)
	set oldTID to AppleScript's text item delimiters
	set AppleScript's text item delimiters to search_string
	set item_list to every text item of this_text
	set AppleScript's text item delimiters to replacement_string
	set this_text to item_list as string
	set AppleScript's text item delimiters to oldTID
	return this_text
end replace_chars


with timeout of 8 seconds
	tell application "Safari"
		
		if not (exists front window) then
			return "{\"playing\":false}"
		end if
		
		
		-- ============================================================
		-- LIGHTWEIGHT PLAYBACK PROBE
		--
		-- Used to decide which Safari tab is actually playing.
		--
		-- YouTube rules:
		--
		--   /watch
		--   /shorts
		--   /embed
		--   /live
		--   youtu.be/<id>
		--
		-- may use either the YouTube player API or real HTML5 playback.
		--
		-- Other YouTube pages, including the homepage/subscription feeds,
		-- do NOT count HTML5 playback by itself because mouse-over
		-- thumbnail previews create playing <video> elements.
		--
		-- However, if YouTube's actual movie_player reports state=1,
		-- it IS counted. This preserves genuine mini-player playback.
		--
		-- Media Session is deliberately NOT trusted for YouTube because
		-- Safari/YouTube may leave it reporting "playing" after playback
		-- has stopped.
		--
		-- Generic sites:
		--   HTML5 video/audio OR Media Session can indicate playback.
		-- ============================================================
		
		set probeJS to "(() => {" & linefeed & ¬
			"try {" & linefeed & ¬
			" const url=location.href||'';" & linefeed & ¬
			" const host=location.hostname||'';" & linefeed & ¬
			" const path=location.pathname||'';" & linefeed & ¬
			"" & linefeed & ¬
			" const yt=/(^|\\.)youtube\\.com$/.test(host)||/(^|\\.)youtu\\.be$/.test(host);" & linefeed & ¬
			"" & linefeed & ¬
			" const ytPlaybackPage=yt&&(" & linefeed & ¬
			"   host==='youtu.be'||" & linefeed & ¬
			"   path==='/watch'||" & linefeed & ¬
			"   path.startsWith('/shorts/')||" & linefeed & ¬
			"   path.startsWith('/embed/')||" & linefeed & ¬
			"   path.startsWith('/live/')" & linefeed & ¬
			" );" & linefeed & ¬
			"" & linefeed & ¬
			" const mp=yt?document.getElementById('movie_player'):null;" & linefeed & ¬
			"" & linefeed & ¬
			" const ps=(mp&&typeof mp.getPlayerState==='function')" & linefeed & ¬
			"   ?mp.getPlayerState()" & linefeed & ¬
			"   :null;" & linefeed & ¬
			"" & linefeed & ¬
			" // News-page autoplay clips must be at least 10 seconds long." & linefeed & ¬
			" const newsSite=/(^|\\.)(nytimes\\.com|washingtonpost\\.com)$/.test(host);" & linefeed & ¬
			" const eligibleMedia=v=>!newsSite||v.tagName!=='VIDEO'||v.duration>=10;" & linefeed & ¬
			" const media=[...document.querySelectorAll('video,audio')].filter(eligibleMedia);" & linefeed & ¬
			"" & linefeed & ¬
			" const htmlPlaying=media.some(v=>" & linefeed & ¬
			"   !v.paused&&" & linefeed & ¬
			"   !v.ended&&" & linefeed & ¬
			"   v.readyState>2" & linefeed & ¬
			" );" & linefeed & ¬
			"" & linefeed & ¬
			" const msPlaying=!!navigator.mediaSession&&" & linefeed & ¬
			"   navigator.mediaSession.playbackState==='playing';" & linefeed & ¬
			"" & linefeed & ¬
			" const youtubePlayerPlaying=ps===1;" & linefeed & ¬
			"" & linefeed & ¬
			" const playing=yt" & linefeed & ¬
			"   ?(youtubePlayerPlaying||(ytPlaybackPage&&htmlPlaying))" & linefeed & ¬
			"   :(htmlPlaying||(!newsSite&&msPlaying));" & linefeed & ¬
			"" & linefeed & ¬
			" const fs=" & linefeed & ¬
			"   !!(document.fullscreenElement||document.webkitFullscreenElement)||" & linefeed & ¬
			"   media.some(v=>" & linefeed & ¬
			"     v.webkitDisplayingFullscreen||" & linefeed & ¬
			"     v.webkitPresentationMode==='fullscreen'" & linefeed & ¬
			"   );" & linefeed & ¬
			"" & linefeed & ¬
			" const pip=!!(" & linefeed & ¬
			"   document.pictureInPictureElement||" & linefeed & ¬
			"   document.webkitPictureInPictureElement" & linefeed & ¬
			" );" & linefeed & ¬
			"" & linefeed & ¬
			" const focused=document.hasFocus();" & linefeed & ¬
			" const visible=document.visibilityState==='visible';" & linefeed & ¬
			"" & linefeed & ¬
			" let score=0;" & linefeed & ¬
			"" & linefeed & ¬
			" if(playing){" & linefeed & ¬
			"   if(fs)score=1000;" & linefeed & ¬
			"   else if(pip)score=900;" & linefeed & ¬
			"   else if(focused)score=300;" & linefeed & ¬
			"   else if(visible)score=200;" & linefeed & ¬
			"   else score=100;" & linefeed & ¬
			" }" & linefeed & ¬
			"" & linefeed & ¬
			" return [" & linefeed & ¬
			"   score," & linefeed & ¬
			"   playing?1:0," & linefeed & ¬
			"   fs?1:0," & linefeed & ¬
			"   focused?1:0," & linefeed & ¬
			"   visible?1:0," & linefeed & ¬
			"   ps===null?'null':ps" & linefeed & ¬
			" ].join('|');" & linefeed & ¬
			"" & linefeed & ¬
			"}catch(e){" & linefeed & ¬
			" return '0|0|0|0|0|null';" & linefeed & ¬
			"}" & linefeed & ¬
			"})()"
		
		
		-- ============================================================
		-- FIND BEST PLAYING TAB
		--
		-- Ranking:
		--   fullscreen  1000
		--   PiP          900
		--   focused      300
		--   visible      200
		--   background   100
		--
		-- This scans all Safari windows/tabs so background playback
		-- isn't missed.
		-- ============================================================
		
		set selectedWindowIndex to 0
		set selectedTabIndex to 0
		set selectedScore to 0
		
		set safariWindowCount to count of windows
		
		repeat with wi from 1 to safariWindowCount
			
			try
				set w to window wi
				set tabCount to count of tabs of w
				
				repeat with ti from 1 to tabCount
					
					try
						set t to tab ti of w
						
						set candidateURL to ""
						
						try
							set candidateURL to URL of t
						end try
						
						if candidateURL starts with "http://" or candidateURL starts with "https://" then
							
							set probeResult to ""
							
							try
								set probeResult to do JavaScript probeJS in t
							end try
							
							if probeResult is not "" then
								
								set oldTID to AppleScript's text item delimiters
								set AppleScript's text item delimiters to "|"
								set probeParts to text items of probeResult
								set AppleScript's text item delimiters to oldTID
								
								try
									set candidateScore to item 1 of probeParts as integer
								on error
									set candidateScore to 0
								end try
								
								if candidateScore > selectedScore then
									set selectedScore to candidateScore
									set selectedWindowIndex to wi
									set selectedTabIndex to ti
								end if
								
								-- Fullscreen is the highest possible score.
								if candidateScore ≥ 1000 then exit repeat
								
							end if
						end if
						
					end try
					
				end repeat
				
				if selectedScore ≥ 1000 then exit repeat
				
			end try
			
		end repeat
		
		
		-- ============================================================
		-- TARGET TAB
		--
		-- If something is playing, inspect that tab.
		-- Otherwise inspect Safari's current tab and return playing=false.
		-- ============================================================
		
		if selectedWindowIndex > 0 and selectedTabIndex > 0 then
			set targetTab to tab selectedTabIndex of window selectedWindowIndex
		else
			set targetTab to current tab of front window
		end if
		
		
		set theURL to ""
		
		try
			set theURL to URL of targetTab
		end try
		
		
		-- ============================================================
		-- FULL METADATA EXTRACTION
		--
		-- Sources:
		--   YouTube player API
		--   HTML5 video/audio
		--   Media Session
		--   NYT/VHS
		--   OpenGraph
		--   normal DOM metadata
		-- ============================================================
		
		set js to "(() => {" & linefeed & ¬
			"try {" & linefeed & ¬
			"" & linefeed & ¬
			" const url=location.href||'';" & linefeed & ¬
			" const host=location.hostname||'';" & linefeed & ¬
			" const path=location.pathname||'';" & linefeed & ¬
			"" & linefeed & ¬
			" const isYoutube=" & linefeed & ¬
			"   /(^|\\.)youtube\\.com$/.test(host)||" & linefeed & ¬
			"   /(^|\\.)youtu\\.be$/.test(host);" & linefeed & ¬
			"" & linefeed & ¬
			" const isYoutubePlaybackPage=isYoutube&&(" & linefeed & ¬
			"   host==='youtu.be'||" & linefeed & ¬
			"   path==='/watch'||" & linefeed & ¬
			"   path.startsWith('/shorts/')||" & linefeed & ¬
			"   path.startsWith('/embed/')||" & linefeed & ¬
			"   path.startsWith('/live/')" & linefeed & ¬
			" );" & linefeed & ¬
			"" & linefeed & ¬
			" const isShorts=isYoutube&&path.startsWith('/shorts/');" & linefeed & ¬
			"" & linefeed & ¬
			" const text=s=>" & linefeed & ¬
			"   document.querySelector(s)?.textContent?.trim()||'';" & linefeed & ¬
			"" & linefeed & ¬
			" const meta=(s,a='content')=>" & linefeed & ¬
			"   document.querySelector(s)?.getAttribute(a)||'';" & linefeed & ¬
			"" & linefeed & ¬
			" const finite=n=>" & linefeed & ¬
			"   typeof n==='number'&&Number.isFinite(n);" & linefeed & ¬
			"" & linefeed & ¬
			" const parseVideoId=u=>{" & linefeed & ¬
			"   try{" & linefeed & ¬
			"     const x=new URL(u,location.origin);" & linefeed & ¬
			"" & linefeed & ¬
			"     if(x.hostname==='youtu.be')" & linefeed & ¬
			"       return x.pathname.replace(/^\\/+/, '').split(/[?#&]/)[0]||'';" & linefeed & ¬
			"" & linefeed & ¬
			"     if(x.pathname.startsWith('/shorts/'))" & linefeed & ¬
			"       return (x.pathname.split('/')[2]||'').split(/[?#&]/)[0];" & linefeed & ¬
			"" & linefeed & ¬
			"     if(x.pathname==='/watch')" & linefeed & ¬
			"       return x.searchParams.get('v')||'';" & linefeed & ¬
			"" & linefeed & ¬
			"     if(x.pathname.startsWith('/embed/'))" & linefeed & ¬
			"       return (x.pathname.split('/')[2]||'').split(/[?#&]/)[0];" & linefeed & ¬
			"" & linefeed & ¬
			"     if(x.pathname.startsWith('/live/'))" & linefeed & ¬
			"       return (x.pathname.split('/')[2]||'').split(/[?#&]/)[0];" & linefeed & ¬
			"" & linefeed & ¬
			"     return '';" & linefeed & ¬
			"   }catch(e){" & linefeed & ¬
			"     return '';" & linefeed & ¬
			"   }" & linefeed & ¬
			" };" & linefeed & ¬
			"" & linefeed & ¬
			" const mp=isYoutube" & linefeed & ¬
			"   ?document.getElementById('movie_player')" & linefeed & ¬
			"   :null;" & linefeed & ¬
			"" & linefeed & ¬
			" // News-page autoplay clips must be at least 10 seconds long." & linefeed & ¬
			" const newsSite=/(^|\\.)(nytimes\\.com|washingtonpost\\.com)$/.test(host);" & linefeed & ¬
			" const eligibleMedia=v=>!newsSite||v.tagName!=='VIDEO'||v.duration>=10;" & linefeed & ¬
			" const media=[...document.querySelectorAll('video,audio')].filter(eligibleMedia);" & linefeed & ¬
			" const videos=media.filter(x=>x.tagName==='VIDEO');" & linefeed & ¬
			"" & linefeed & ¬
			" const playerState=" & linefeed & ¬
			"   (mp&&typeof mp.getPlayerState==='function')" & linefeed & ¬
			"     ?mp.getPlayerState()" & linefeed & ¬
			"     :null;" & linefeed & ¬
			"" & linefeed & ¬
			" const activeMedia=media.find(v=>" & linefeed & ¬
			"   !v.paused&&" & linefeed & ¬
			"   !v.ended&&" & linefeed & ¬
			"   v.readyState>2" & linefeed & ¬
			" )||null;" & linefeed & ¬
			"" & linefeed & ¬
			" const usableMedia=" & linefeed & ¬
			"   activeMedia||" & linefeed & ¬
			"   media.find(v=>v.readyState>0)||" & linefeed & ¬
			"   media[0]||null;" & linefeed & ¬
			"" & linefeed & ¬
			" const ms=navigator.mediaSession||null;" & linefeed & ¬
			"" & linefeed & ¬
			" const mediaSessionPlaying=" & linefeed & ¬
			"   !!ms&&ms.playbackState==='playing';" & linefeed & ¬
			"" & linefeed & ¬
			" const msMeta=ms?.metadata||null;" & linefeed & ¬
			"" & linefeed & ¬
			" let vhs=null;" & linefeed & ¬
			" let vhsState=null;" & linefeed & ¬
			"" & linefeed & ¬
			" try{" & linefeed & ¬
			"   const V=window.VHS||window.__VHS__;" & linefeed & ¬
			"" & linefeed & ¬
			"   if(V&&V.instances){" & linefeed & ¬
			"     const instances=Array.isArray(V.instances)" & linefeed & ¬
			"       ?V.instances" & linefeed & ¬
			"       :Object.values(V.instances);" & linefeed & ¬
			"" & linefeed & ¬
			"     vhs=instances.find(Boolean)||null;" & linefeed & ¬
			"" & linefeed & ¬
			"     if(vhs?.store&&typeof vhs.store.getState==='function')" & linefeed & ¬
			"       vhsState=vhs.store.getState();" & linefeed & ¬
			"   }" & linefeed & ¬
			" }catch(e){}" & linefeed & ¬
			"" & linefeed & ¬
			" const vd=" & linefeed & ¬
			"   (mp&&typeof mp.getVideoData==='function')" & linefeed & ¬
			"     ?(mp.getVideoData()||{})" & linefeed & ¬
			"     :{};" & linefeed & ¬
			"" & linefeed & ¬
			" const video_id=isYoutube" & linefeed & ¬
			"   ?(vd.video_id||vd.videoId||parseVideoId(url)||'')" & linefeed & ¬
			"   :'';" & linefeed & ¬
			"" & linefeed & ¬
			" const media_id=isYoutube" & linefeed & ¬
			"   ?video_id" & linefeed & ¬
			"   :(vhsState?.player?.media?.id||'');" & linefeed & ¬
			"" & linefeed & ¬
			" const title=" & linefeed & ¬
			"   vd.title||" & linefeed & ¬
			"   msMeta?.title||" & linefeed & ¬
			"   vhsState?.player?.media?.headline||" & linefeed & ¬
			"   meta('meta[name=\"title\"]')||" & linefeed & ¬
			"   meta('meta[property=\"og:title\"]')||" & linefeed & ¬
			"   meta('meta[name=\"twitter:title\"]')||" & linefeed & ¬
			"   text('h1.ytd-watch-metadata')||" & linefeed & ¬
			"   text('h1')||" & linefeed & ¬
			"   (document.title||'')" & linefeed & ¬
			"     .replace(/\\s*-\\s*YouTube\\s*$/,'')" & linefeed & ¬
			"     .trim();" & linefeed & ¬
			"" & linefeed & ¬
			" const initialPlayerAuthor=" & linefeed & ¬
			"   window?.ytInitialPlayerResponse?.videoDetails?.author||'';" & linefeed & ¬
			"" & linefeed & ¬
			" const initialDataChannel=" & linefeed & ¬
			"   window?.ytInitialData?.metadata?.channelMetadataRenderer?.title||" & linefeed & ¬
			"   window?.ytInitialData?.contents?.twoColumnWatchNextResults?.results?.results?.contents?.find(x=>x.videoSecondaryInfoRenderer)?.videoSecondaryInfoRenderer?.owner?.videoOwnerRenderer?.title?.runs?.[0]?.text||" & linefeed & ¬
			"   '';" & linefeed & ¬
			"" & linefeed & ¬
			" const channel=" & linefeed & ¬
			"   vd.author||" & linefeed & ¬
			"   vd.channelName||" & linefeed & ¬
			"   msMeta?.artist||" & linefeed & ¬
			"   initialPlayerAuthor||" & linefeed & ¬
			"   initialDataChannel||" & linefeed & ¬
			"   meta('meta[name=\"author\"]')||" & linefeed & ¬
			"   meta('meta[property=\"article:author\"]')||" & linefeed & ¬
			"   text('#channel-name a')||" & linefeed & ¬
			"   text('ytd-channel-name a')||" & linefeed & ¬
			"   text('a[href^=\"/@\"]')||" & linefeed & ¬
			"   host;" & linefeed & ¬
			"" & linefeed & ¬
			" const playerVideoId=" & linefeed & ¬
			"   window?.ytInitialPlayerResponse?.videoDetails?.videoId||'';" & linefeed & ¬
			"" & linefeed & ¬
			" const initialDesc=" & linefeed & ¬
			"   (playerVideoId&&playerVideoId===video_id)" & linefeed & ¬
			"     ?(window?.ytInitialPlayerResponse?.videoDetails?.shortDescription||'')" & linefeed & ¬
			"     :'';" & linefeed & ¬
			"" & linefeed & ¬
			" let jsonLdDescription='';" & linefeed & ¬
			"" & linefeed & ¬
			" try{" & linefeed & ¬
			"   const ld=[...document.querySelectorAll('script[type=\"application/ld+json\"]')];" & linefeed & ¬
			"" & linefeed & ¬
			"   for(const s of ld){" & linefeed & ¬
			"     const txt=s.textContent||'';" & linefeed & ¬
			"     if(!txt.trim())continue;" & linefeed & ¬
			"" & linefeed & ¬
			"     const obj=JSON.parse(txt);" & linefeed & ¬
			"     const arr=Array.isArray(obj)?obj:[obj];" & linefeed & ¬
			"" & linefeed & ¬
			"     const found=arr.find(x=>{" & linefeed & ¬
			"       if(!x)return false;" & linefeed & ¬
			"       const t=x['@type'];" & linefeed & ¬
			"" & linefeed & ¬
			"       return t==='VideoObject'||" & linefeed & ¬
			"              t==='AudioObject'||" & linefeed & ¬
			"              t==='PodcastEpisode'||" & linefeed & ¬
			"              (Array.isArray(t)&&(" & linefeed & ¬
			"                t.includes('VideoObject')||" & linefeed & ¬
			"                t.includes('AudioObject')||" & linefeed & ¬
			"                t.includes('PodcastEpisode')" & linefeed & ¬
			"              ));" & linefeed & ¬
			"     });" & linefeed & ¬
			"" & linefeed & ¬
			"     if(found?.description){" & linefeed & ¬
			"       jsonLdDescription=found.description;" & linefeed & ¬
			"       break;" & linefeed & ¬
			"     }" & linefeed & ¬
			"   }" & linefeed & ¬
			" }catch(e){}" & linefeed & ¬
			"" & linefeed & ¬
			" const rawDomDesc=" & linefeed & ¬
			"   text('#description-inline-expander yt-attributed-string')||" & linefeed & ¬
			"   text('#description-inline-expander-inline-content')||" & linefeed & ¬
			"   text('#description yt-attributed-string')||'';" & linefeed & ¬
			"" & linefeed & ¬
			" const domDesc=rawDomDesc" & linefeed & ¬
			"   .split('…more')[0]" & linefeed & ¬
			"   .split('...more')[0]" & linefeed & ¬
			"   .split('AI-generated video summary')[0]" & linefeed & ¬
			"   .split('Transcript')[0]" & linefeed & ¬
			"   .split('Show transcript')[0]" & linefeed & ¬
			"   .split('Ask questions')[0]" & linefeed & ¬
			"   .replace(/\\s+/g,' ')" & linefeed & ¬
			"   .trim();" & linefeed & ¬
			"" & linefeed & ¬
			" const description=" & linefeed & ¬
			"   vd.shortDescription||" & linefeed & ¬
			"   initialDesc||" & linefeed & ¬
			"   domDesc||" & linefeed & ¬
			"   jsonLdDescription||" & linefeed & ¬
			"   meta('meta[name=\"description\"]')||" & linefeed & ¬
			"   meta('meta[property=\"og:description\"]')||" & linefeed & ¬
			"   meta('meta[name=\"twitter:description\"]')||'';" & linefeed & ¬
			"" & linefeed & ¬
			" let currentTime=0;" & linefeed & ¬
			"" & linefeed & ¬
			" if(activeMedia&&finite(activeMedia.currentTime))" & linefeed & ¬
			"   currentTime=Math.floor(activeMedia.currentTime);" & linefeed & ¬
			" else if(mp&&typeof mp.getCurrentTime==='function'){" & linefeed & ¬
			"   const n=mp.getCurrentTime();" & linefeed & ¬
			"   if(finite(n))currentTime=Math.floor(n);" & linefeed & ¬
			" }" & linefeed & ¬
			" else if(vhs&&typeof vhs.getCurrentTime==='function'){" & linefeed & ¬
			"   try{" & linefeed & ¬
			"     const n=vhs.getCurrentTime();" & linefeed & ¬
			"     if(finite(n)&&n>0)currentTime=Math.floor(n);" & linefeed & ¬
			"   }catch(e){}" & linefeed & ¬
			" }" & linefeed & ¬
			"" & linefeed & ¬
			" let duration=0;" & linefeed & ¬
			"" & linefeed & ¬
			" if(activeMedia&&finite(activeMedia.duration))" & linefeed & ¬
			"   duration=Math.floor(activeMedia.duration);" & linefeed & ¬
			" else if(mp&&typeof mp.getDuration==='function'){" & linefeed & ¬
			"   const n=mp.getDuration();" & linefeed & ¬
			"   if(finite(n))duration=Math.floor(n);" & linefeed & ¬
			" }" & linefeed & ¬
			"" & linefeed & ¬
			" if(!duration&&vhs&&typeof vhs.getDuration==='function'){" & linefeed & ¬
			"   try{" & linefeed & ¬
			"     const n=vhs.getDuration();" & linefeed & ¬
			"     if(finite(n))duration=Math.floor(n);" & linefeed & ¬
			"   }catch(e){}" & linefeed & ¬
			" }" & linefeed & ¬
			"" & linefeed & ¬
			" if(!duration&&finite(vhsState?.player?.media?.duration))" & linefeed & ¬
			"   duration=Math.floor(vhsState.player.media.duration);" & linefeed & ¬
			"" & linefeed & ¬
			" if(!duration&&finite(usableMedia?.duration))" & linefeed & ¬
			"   duration=Math.floor(usableMedia.duration);" & linefeed & ¬
			"" & linefeed & ¬
			" let playbackRate=1;" & linefeed & ¬
			"" & linefeed & ¬
			" if(activeMedia&&finite(activeMedia.playbackRate))" & linefeed & ¬
			"   playbackRate=activeMedia.playbackRate;" & linefeed & ¬
			" else if(mp&&typeof mp.getPlaybackRate==='function'){" & linefeed & ¬
			"   const n=mp.getPlaybackRate();" & linefeed & ¬
			"   if(finite(n))playbackRate=n;" & linefeed & ¬
			" }" & linefeed & ¬
			" else if(usableMedia&&finite(usableMedia.playbackRate))" & linefeed & ¬
			"   playbackRate=usableMedia.playbackRate;" & linefeed & ¬
			"" & linefeed & ¬
			" let thumbnail='';" & linefeed & ¬
			"" & linefeed & ¬
			" if(isYoutube&&video_id)" & linefeed & ¬
			"   thumbnail=`https://img.youtube.com/vi/${video_id}/maxresdefault.jpg`;" & linefeed & ¬
			" else" & linefeed & ¬
			"   thumbnail=" & linefeed & ¬
			"     msMeta?.artwork?.slice(-1)?.[0]?.src||" & linefeed & ¬
			"     meta('meta[property=\"og:image\"]')||" & linefeed & ¬
			"     meta('meta[name=\"twitter:image\"]')||" & linefeed & ¬
			"     vhsState?.player?.media?.posterUrl||'';" & linefeed & ¬
			"" & linefeed & ¬
			" const nativeFullscreen=media.some(v=>" & linefeed & ¬
			"   v.webkitDisplayingFullscreen||" & linefeed & ¬
			"   v.webkitPresentationMode==='fullscreen'" & linefeed & ¬
			" );" & linefeed & ¬
			"" & linefeed & ¬
			" const domFullscreen=!!(" & linefeed & ¬
			"   document.fullscreenElement||" & linefeed & ¬
			"   document.webkitFullscreenElement" & linefeed & ¬
			" );" & linefeed & ¬
			"" & linefeed & ¬
			" const fullscreenish=nativeFullscreen||domFullscreen;" & linefeed & ¬
			"" & linefeed & ¬
			" const html5Playing=media.some(v=>" & linefeed & ¬
			"   !v.paused&&" & linefeed & ¬
			"   !v.ended&&" & linefeed & ¬
			"   v.readyState>2" & linefeed & ¬
			" );" & linefeed & ¬
			"" & linefeed & ¬
			" const youtubeActuallyPlaying=playerState===1;" & linefeed & ¬
			"" & linefeed & ¬
			" const playing=isYoutube" & linefeed & ¬
			"   ?(" & linefeed & ¬
			"      youtubeActuallyPlaying||" & linefeed & ¬
			"      (isYoutubePlaybackPage&&html5Playing)" & linefeed & ¬
			"    )" & linefeed & ¬
			"   :(html5Playing||(!newsSite&&mediaSessionPlaying));" & linefeed & ¬
			"" & linefeed & ¬
			" const playerClasses=mp?.className||'';" & linefeed & ¬
			"" & linefeed & ¬
			" return JSON.stringify({" & linefeed & ¬
			"   playing," & linefeed & ¬
			"   url," & linefeed & ¬
			"   video_id," & linefeed & ¬
			"   media_id," & linefeed & ¬
			"   title," & linefeed & ¬
			"   channel," & linefeed & ¬
			"   description," & linefeed & ¬
			"   currentTime," & linefeed & ¬
			"   duration," & linefeed & ¬
			"   playbackRate," & linefeed & ¬
			"   thumbnail," & linefeed & ¬
			"   fullscreenish," & linefeed & ¬
			"   playerState," & linefeed & ¬
			"   youtubePlayingMode:/\\bplaying-mode\\b/.test(playerClasses)," & linefeed & ¬
			"   youtubePausedMode:/\\bpaused-mode\\b/.test(playerClasses)," & linefeed & ¬
			"   mediaSessionPlaying," & linefeed & ¬
			"   isShorts," & linefeed & ¬
			"   isYoutubePlaybackPage" & linefeed & ¬
			" });" & linefeed & ¬
			"" & linefeed & ¬
			"}catch(e){" & linefeed & ¬
			" return JSON.stringify({" & linefeed & ¬
			"   playing:false," & linefeed & ¬
			"   error:String(e)," & linefeed & ¬
			"   url:location.href||''" & linefeed & ¬
			" });" & linefeed & ¬
			"}" & linefeed & ¬
			"})()"
		
		
		set raw to ""
		
		try
			set raw to do JavaScript js in targetTab
		on error errMsg number errNum
			return "{\"playing\":false,\"error\":\"" & my escape_json(errMsg) & "\",\"error_number\":" & errNum & ",\"url\":\"" & my escape_json(theURL) & "\"}"
		end try
		
		
		if raw is missing value or raw = "" then
			return "{\"playing\":false,\"error\":\"Safari returned missing value\",\"url\":\"" & my escape_json(theURL) & "\"}"
		end if
		
		
		return raw
		
	end tell
end timeout

