local source=debug.getinfo(1,"S").source:sub(2)
local root=source:match("^(.*)/tests/test_speech_logic.lua$")
local logic=dofile(root.."/hammerspoon/speech_logic.lua")
local count=0
local function check(value,message) assert(value,message);count=count+1 end
local jobs,states,nextId={}, {},0
local q=logic.queue({
 id=function()nextId=nextId+1;return "speech-"..nextId end,
 launch=function(request,event,exit)
  local job={request=request,event=event,exit=exit,cancelled=false}
  jobs[#jobs+1]=job;return job
 end,
 cancel=function(job)job.cancelled=true end,
 status=function(value)local copy={};for k,v in pairs(value)do copy[k]=v end;states[#states+1]=copy end,
})
local settings={language="en-GB",voiceIdentifier="com.apple.voice.compact.en-GB.Daniel",rate=.5}
q.submit("children",settings)
check(#jobs==1 and jobs[1].request.text=="children","Original plural preserved")
check(q.status().phase=="waiting","Pending synthesis state")
q.submit("children",settings)
check(jobs[1].cancelled and q.status().phase=="stopped","Same selection cancels waiting")
jobs[1].event({requestId=jobs[1].request.requestId,event="started"})
check(q.status().phase=="stopped","Late start ignored after cancellation")
jobs[1].exit(0)
check(#jobs==1,"Cancelled pending request never restarts")
q.submit("went",settings)
check(jobs[2].request.text=="went","Original past form preserved")
q.submit("responses",settings)
check(jobs[2].cancelled and #jobs==2,"Wait for old process before replacement")
q.submit("comfortable",settings)
check(#jobs==2,"Intermediate replacement never starts")
jobs[2].exit(0)
check(#jobs==3 and jobs[3].request.text=="comfortable","Only latest replacement starts")
jobs[2].event({requestId=jobs[2].request.requestId,event="started"})
check(q.status().phase=="waiting","Old callback cannot mark new request playing")
jobs[3].event({requestId=jobs[3].request.requestId,event="started",voice={identifier=settings.voiceIdentifier,language="en-GB"},rate=.5,elapsedMs=25})
check(q.status().phase=="playing","Current request can play")
check(q.status().actualVoice.identifier==settings.voiceIdentifier,"Actual voice in status")
q.submit("comfortable",settings)
check(jobs[3].cancelled and q.status().phase=="stopped","Same selection stops playback")
jobs[3].exit(0)
q.submit("What I enjoy most is learning something new.",settings)
check(jobs[4].request.text=="What I enjoy most is learning something new.","Sentence forwarded intact")
q.dispose()
jobs[4].event({requestId=jobs[4].request.requestId,event="started"})
jobs[4].exit(0)
check(q.status().phase=="stopped" and #jobs==4,"Module stop invalidates late callbacks")
check(q.submit("responses",settings)==false,"Disposed controller cannot restart")
for _,state in ipairs(states)do check(state.text==nil and state.selection==nil,"Status excludes selection text") end
local p,warning=logic.preferences({englishAccent="en-GB",voiceByLanguage={['en-GB']=settings.voiceIdentifier},rate=.5,userConfirmed=true})
check(p.englishAccent=="en-GB" and p.voiceByLanguage['en-GB']==settings.voiceIdentifier and p.userConfirmed,"Explicit preference retained")
local invalid,warning=logic.preferences({rate=185})
check(invalid.rate==.5 and warning~=nil,"NSSpeech rate cannot silently become AV rate")
check(logic.isEnglishAmbiguous("read") and logic.isEnglishAmbiguous("record") and logic.isEnglishAmbiguous("live"),"Context-dependent words marked")
check(not logic.isEnglishAmbiguous("children"),"Inflections do not get unrelated warnings")
print("Speech queue assertions passed: "..count)
