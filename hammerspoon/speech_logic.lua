local M = {}

function M.preferences(value)
  value = type(value) == "table" and value or {}
  local warning
  local accent = value.englishAccent or "en-US"
  if accent ~= "en-US" and accent ~= "en-GB" then accent = "en-US"; warning = "口音设置无效，暂用美音。" end
  local rate = tonumber(value.rate) or 0.5
  if rate < 0.35 or rate > 0.65 then rate = 0.5; warning = "语速设置无效，已暂用正常语速。" end
  local voices = {}
  for _,language in ipairs({"en-US", "en-GB", "zh-CN"}) do
    local id = type(value.voiceByLanguage) == "table" and value.voiceByLanguage[language]
    if type(id) == "string" and #id <= 200 and id:find("^com%.apple%.") then voices[language] = id end
  end
  return {schemaVersion=1, englishAccent=accent, voiceByLanguage=voices, rate=rate,
    slowRate=0.43, userConfirmed=value.userConfirmed == true}, warning
end

function M.isEnglishAmbiguous(text)
  local word = text:lower():gsub("^%p+", ""):gsub("%p+$", "")
  return word == "read" or word == "record" or word == "live"
end

-- This queue owns logical requests; adapters own process I/O. Text stays only
-- in these short-lived request objects and is never copied to status metadata.
function M.queue(adapter)
  local current, active, pending
  local phase, generation, disposed = "stopped", 0, false
  local details = {engine="AVSpeechSynthesizer", phase="stopped"}
  local obj = {}
  local launchPending
  local function publish(state, fields)
    phase = state
    details.phase = state
    for key,value in pairs(fields or {}) do details[key] = value end
    if adapter.status then adapter.status(details) end
  end
  local function valid(request) return not disposed and current == request and request.generation == generation end
  launchPending = function()
    if disposed or active or not pending then return end
    local request = pending; pending = nil
    if not valid(request) then return end
    local process = {request=request, stopping=false}
    active = process
    process.handle = adapter.launch(request, function(event)
      if event.requestId ~= request.requestId or not valid(request) or process.stopping then return end
      if event.event == "resolved" then
        publish("waiting", {actualVoice=event.voice, requestedVoice=event.requestedVoice or "automatic",
          fallbackReason=event.fallbackReason or "", rate=event.rate})
        if event.fallbackReason and adapter.notice then adapter.notice(event.fallbackReason) end
      elseif event.event == "started" then
        publish("playing", {actualVoice=event.voice, rate=event.rate, startMs=event.elapsedMs,
          fallbackReason=event.fallbackReason or ""})
        if event.fallbackReason and adapter.notice then adapter.notice(event.fallbackReason) end
      elseif event.event == "finished" or event.event == "cancelled" then
        publish("stopped", {terminal=event.event, elapsedMs=event.elapsedMs})
        current = nil
      elseif event.event == "error" then
        publish("error", {error=event.error or "synthesisFailed"})
        current = nil
      end
    end, function(exitCode)
      if active ~= process then return end
      active = nil
      if valid(request) and phase ~= "stopped" and phase ~= "error" then
        publish("error", {error=exitCode == 0 and "missingCompletion" or "helperExit"})
        current = nil
      end
      launchPending()
    end)
    if not process.handle then
      active = nil
      if valid(request) then publish("error", {error="helperLaunch"}); current=nil end
    end
  end
  function obj.stop(reason)
    generation = generation + 1
    current, pending = nil, nil
    if active and not active.stopping then
      active.stopping = true
      if adapter.cancel(active.handle)==false then
        publish("error",{error="stopFailed"});return false
      end
    end
    publish("stopped", {terminal=reason or "cancelled"})
  end
  function obj.submit(text, config)
    if disposed then return false, "disposed" end
    if current and (phase == "waiting" or phase == "playing") and current.text == text then
      obj.stop("sameSelectionStopped"); return true, "stopped"
    end
    generation = generation + 1
    local request = {requestId=adapter.id(), generation=generation, text=text,
      language=config.language, voiceIdentifier=config.voiceIdentifier, rate=config.rate}
    current, pending = request, request
    details = {engine="AVSpeechSynthesizer", requestId=request.requestId, phase="waiting",
      language=request.language, requestedVoice=request.voiceIdentifier or "automatic", rate=request.rate,
      contextSensitive=M.isEnglishAmbiguous(text), fallbackReason=""}
    publish("waiting")
    if active and not active.stopping then
      active.stopping = true; adapter.cancel(active.handle)
    end
    launchPending()
    return true, "waiting"
  end
  function obj.dispose()
    obj.stop("moduleStopped"); disposed = true
  end
  function obj.status()
    local copy = {}; for k,v in pairs(details) do copy[k]=v end
    copy.awaitingOldProcess = active ~= nil and active.stopping or false
    return copy
  end
  return obj
end

return M
