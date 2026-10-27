local logic = require("speech_logic")
local selectionLogic = require("selection_logic")
local M = {}
local SAMPLE = "Hello. Comfortable. Development. Opportunity. Children. Went. Responses. I usually go to the gym in the morning. What I enjoy most is learning something new."

local function readJSON(path)
  local file=io.open(path,"r"); if not file then return nil end
  local data=file:read(65537);file:close()
  if not data or #data>65536 then return nil end
  local ok,value=pcall(hs.json.decode,data)
  return ok and value or nil
end

local function writeJSON(path,data)
  local temporary=path..".tmp"
  local file=io.open(temporary,"w"); if not file then return false end
  file:write(hs.json.encode(data));file:close()
  return os.rename(temporary,path) ~= nil
end

function M.workScreen()
  local best
  for _,screen in ipairs(hs.screen.allScreens()) do
    local name=(screen:name() or ""):lower()
    local virtual=name:find("ipad",1,true) or name:find("opendisplay",1,true)
      or name:find("sidecar",1,true) or name:find("airplay",1,true)
      or name:find("virtual",1,true) or name:find("dummy",1,true)
    if not virtual and (not best or screen:fullFrame().x < best:fullFrame().x) then best=screen end
  end
  return best
end

function M.new(options)
  options=options or {}
  local directory=options.directory or hs.configdir.."/mac-selection-translator"
  local helper=directory.."/SpeechHelper.app/Contents/MacOS/SpeechHelper"
  local preferencesPath=directory.."/speech-preferences.json"
  local statusPath=directory.."/speech-status.json"
  local commandPath=directory.."/speech-command.json"
  local progressPath=directory.."/speech-progress.json"
  local preferences,preferenceWarning=logic.preferences(readJSON(preferencesPath))
  local watcher,settingsTask,catalogTask
  local catalog,closed,commandID,lastWarning={},false,(readJSON(commandPath) or {}).id,nil
  local obj,queue={},nil
  local signalTasks={}

  local function stopTask(task)
    if not task or not task:isRunning() then return true end
    local pid=task:pid()
    -- Signal only the known helper PID. Never signal PID 0/a process group,
    -- and do not rely on NSTask's process-group termination behavior.
    if type(pid)~="number" or pid<=1 or pid==hs.processInfo.processID then return false end
    local signalTask
    signalTask=hs.task.new("/bin/kill",function()signalTasks[pid]=nil end,{"-TERM",tostring(pid)})
    if not signalTask then return false end
    signalTasks[pid]=signalTask
    return signalTask:start()~=false
  end

  local function notice(message)
    if message==lastWarning then return end
    lastWarning=message
    if options.notice then options.notice(message) end
  end
  local function publish(data)
    if closed then return end
    local state={};for k,v in pairs(data) do state[k]=v end
    state.preferences=preferences
    state.preferenceWarning=preferenceWarning or ""
    state.availableVoiceCount=#catalog
    writeJSON(statusPath,state)
    if options.onStatus then options.onStatus(state) end
    if state.phase=="error" then notice("朗读未完成，请打开朗读设置检查声音。错误："..tostring(state.error)) end
  end

  local function launch(request,onEvent,onExit)
    local seen,pollTimer={},nil
    local function consume(line)
      local ok,event=pcall(hs.json.decode,line)
      if ok and type(event)=="table" then
        local key=tostring(event.requestId)..":"..tostring(event.event)
        if not seen[key] then seen[key]=true;onEvent(event) end
      end
    end
    local task=hs.task.new(helper,function(code,stdout)
      if pollTimer then pollTimer:stop();pollTimer=nil end
      for line in (stdout or ""):gmatch("[^\n]+") do consume(line) end
      onExit(code)
    end,{"--speak"})
    if not task then return nil end
    -- Text is one JSON field on stdin. No shell, text normalization, or file cache.
    task:setInput(hs.json.encode({requestId=request.requestId,text=request.text,
      language=request.language,voiceIdentifier=request.voiceIdentifier,rate=request.rate,
      progressPath=progressPath}).."\n")
    if not task:start() then return nil end
    -- Use the stable one-shot hs.task path. Poll a single metadata snapshot only
    -- while this process is active; do not stream audio or persist query text.
    pollTimer=hs.timer.doEvery(.04,function()
      local event=readJSON(progressPath)
      if event and event.requestId==request.requestId then consume(hs.json.encode(event)) end
    end)
    return task
  end

  queue=logic.queue({id=hs.host.uuid,launch=launch,cancel=stopTask,status=publish,notice=notice})

  function obj.refreshVoices()
    if closed then return end
    if catalogTask then catalogTask:setCallback(nil);stopTask(catalogTask) end
    catalogTask=hs.task.new(helper,function(code,output)
      catalogTask=nil
      if closed then return end
      local ok,value=pcall(hs.json.decode,output)
      if code==0 and ok and type(value)=="table" then catalog=value end
      publish(queue.status())
    end,{"--catalog"})
    if catalogTask then catalogTask:start() end
  end

  function obj.toggle(text)
    if closed then return false end
    if not hs.fs.attributes(helper) then notice("朗读程序尚未安装，请运行项目安装脚本。");return false end
    local language=selectionLogic.hasChinese(text) and "zh-CN" or preferences.englishAccent
    return queue.submit(text,{language=language,voiceIdentifier=preferences.voiceByLanguage[language],rate=preferences.rate})
  end
  function obj.stopAudio() queue.stop("userStopped") end
  function obj.preview(language,voiceIdentifier,rate)
    if closed or (language~="en-US" and language~="en-GB") then return false end
    rate=tonumber(rate)
    if not rate or rate<0.35 or rate>0.65 then return false end
    queue.stop("newPreview")
    return queue.submit(SAMPLE,{language=language,voiceIdentifier=voiceIdentifier,rate=rate})
  end
  function obj.setPreferences(value)
    local validated,warning=logic.preferences(value)
    if warning then return false,warning end
    if not writeJSON(preferencesPath,validated) then return false,"preferenceWriteFailed" end
    queue.stop("settingsChanged")
    preferences,preferenceWarning=validated,nil
    publish(queue.status()); return true
  end
  function obj.openSettings()
    if closed then return false end
    local screen=M.workScreen()
    if not screen then notice("无法确认左侧实体工作屏，设置窗口未打开。");return false end
    if settingsTask and settingsTask:isRunning() then return true end
    settingsTask=hs.task.new(helper,function()settingsTask=nil end,
      {"--settings","--preferences",preferencesPath,"--screen-id",tostring(screen:id())})
    return settingsTask and settingsTask:start()~=nil or false
  end
  function obj.status()
    local state=queue.status();state.preferences=preferences;state.availableVoiceCount=#catalog
    state.preferenceWarning=preferenceWarning or ""
    state.settingsOpen=settingsTask and settingsTask:isRunning() or false
    state.settingsPID=state.settingsOpen and settingsTask:pid() or nil
    return state
  end
  function obj.dispose()
    queue.dispose()
    closed=true
    if watcher then watcher:stop();watcher=nil end
    if settingsTask then settingsTask:setCallback(nil);stopTask(settingsTask);settingsTask=nil end
    if catalogTask then catalogTask:setCallback(nil);stopTask(catalogTask);catalogTask=nil end
  end

  watcher=hs.pathwatcher.new(directory,function(paths)
    if closed then return end
    for _,path in ipairs(paths) do
      if path==preferencesPath then
        local nextPreferences,warning=logic.preferences(readJSON(preferencesPath))
        if hs.json.encode(nextPreferences)~=hs.json.encode(preferences) then queue.stop("settingsChanged") end
        preferences,preferenceWarning=nextPreferences,warning
        if warning then notice(warning) end
        publish(queue.status())
      elseif path==commandPath then
        local command=readJSON(commandPath)
        if command and command.id~=commandID then
          commandID=command.id
          if command.action=="preview" then obj.preview(command.language,command.voiceIdentifier,command.rate)
          elseif command.action=="stop" then obj.stopAudio()
          elseif command.action=="refresh" then obj.refreshVoices() end
        end
      end
    end
  end):start()
  publish(queue.status()); obj.refreshVoices()
  if preferenceWarning then notice(preferenceWarning) end
  return obj
end

return M
