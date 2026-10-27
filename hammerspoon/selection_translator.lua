local M = {}
local logic = require("selection_logic")
local englishLookup = require("english_lookup")
local speechModule = require("selection_speech")
local personal
local hotkeys, canvas, tap, appWatcher = {}, nil, nil, nil
local helper, helperTask, timeoutTimer, loadingTimer, closeTimer, warmTask
local generation, running, panelData = 0, false, nil
local speech, settingsHotkey
local cache = logic.cache(128, 300)
local last, history = {}, {}
local MODS = { "ctrl", "alt", "cmd" }
local denied = {
  ["com.apple.Terminal"] = true, ["com.googlecode.iterm2"] = true,
  ["com.mitchellh.ghostty"] = true, ["com.agilebits.onepassword7"] = true,
  ["com.1password.1password"] = true, ["com.apple.loginwindow"] = true,
}

local function now() return hs.timer.absoluteTime() / 1e9 end
local function stopTimer(timer) if timer then timer:stop() end end
local function remember(entry)
  last = entry
  history[#history + 1] = entry
  while #history > 40 do table.remove(history, 1) end
end

local function cancelRequest()
  generation = generation + 1
  stopTimer(timeoutTimer); stopTimer(loadingTimer)
  timeoutTimer, loadingTimer = nil, nil
  if helperTask then
    local task = helperTask; helperTask = nil
    task:setCallback(nil):terminate()
  end
end

local function hidePanel()
  stopTimer(closeTimer); closeTimer = nil
  if canvas then canvas:hide(); canvas:delete(); canvas = nil end
  if tap then tap:stop() end
  panelData = nil
end

function M.dismiss()
  cancelRequest(); hidePanel()
end

local function attribute(element, name, deadline)
  if not element or now() >= deadline then return nil end
  element:setTimeout(math.min(0.035, math.max(0.001, deadline - now())))
  local ok, value = pcall(function() return element:attributeValue(name) end)
  return ok and value or nil
end

local function capture()
  if not hs.accessibilityState() then return nil, "permission_missing" end
  if hs.eventtap.isSecureInputEnabled() then return nil, "secure_input" end
  local app = hs.application.frontmostApplication()
  if not app or denied[app:bundleID()] then return nil, "app_denied" end
  local deadline = now() + 0.20
  local appElement = hs.axuielement.applicationElement(app)
  local focused = attribute(appElement, "AXFocusedUIElement", deadline)
  local empty = false
  local function inspect(element)
    for _ = 1, 4 do
      if not element or now() >= deadline then break end
      if attribute(element, "AXSubrole", deadline) == "AXSecureTextField" then
        return nil, "secure_input"
      end
      local selected = attribute(element, "AXSelectedText", deadline)
      if type(selected) == "string" then
        local text = logic.trim(selected)
        if text then return { text = text, app = app, pid = app:pid() } end
        if selected ~= "" and selected:find("%S") then return nil, "invalid_selection" end
        empty = true
      end
      element = attribute(element, "AXParent", deadline)
    end
  end
  local result, err = inspect(focused)
  if result or err then return result, err end
  if now() < deadline then
    appElement:setTimeout(math.min(0.035, deadline - now()))
    local point = hs.mouse.absolutePosition()
    local ok, element = pcall(function() return appElement:elementAtPosition(point) end)
    if ok then
      result, err = inspect(element)
      if result or err then return result, err end
    end
  end
  -- Never read AXValue, inject Copy, select all, or reuse a previous word.
  return nil, empty and "empty_selection" or "selection_unavailable"
end

local errors = {
  permission_missing = "请在系统设置 → 隐私与安全性 → 辅助功能中允许 Hammerspoon。",
  secure_input = "安全输入区域不取词。请在普通阅读区域选中单词。",
  app_denied = "当前应用不支持此取词入口，请在普通阅读应用中使用。",
  empty_selection = "请先用鼠标选中一个英文单词。",
  invalid_selection = "选文过长或包含无效字符，请缩小选区。",
  selection_unavailable = "此应用没有提供可读取的选区。请试用浏览器或文本编辑器。",
}

local function screenAt(point)
  for _, screen in ipairs(hs.screen.allScreens()) do
    local f = screen:fullFrame()
    if point.x >= f.x and point.x < f.x + f.w and point.y >= f.y and point.y < f.y + f.h then
      return screen
    end
  end
  return hs.screen.mainScreen()
end

local function renderPanel()
  if not panelData then return end
  local p = panelData
  local display = {}
  for i = p.offset + 1, math.min(#p.lines, p.offset + p.visibleLines) do
    display[#display + 1] = p.lines[i]
  end
  if canvas then canvas:delete() end
  canvas = hs.canvas.new(p.frame):level(hs.canvas.windowLevels.popUpMenu)
    :behavior({ "canJoinAllSpaces", "fullScreenAuxiliary" }):clickActivating(false)
  canvas:appendElements(
    { type = "rectangle", action = "fill", roundedRectRadii = { xRadius = 14, yRadius = 14 },
      fillColor = { hex = "#152330", alpha = 0.98 }, frame = { x = 0, y = 0, w = p.frame.w, h = p.frame.h } },
    { type = "rectangle", action = "fill", fillColor = { hex = "#62D3B2" },
      frame = { x = 18, y = 20, w = 3, h = 23 } },
    { type = "text", text = logic.shorten(p.title, 27), textFont = ".AppleSystemUIFont",
      textSize = 20, textColor = { hex = "#FFFFFF" }, frame = { x = 32, y = 18, w = p.frame.w - 70, h = 30 } },
    { type = "text", id = "close", text = "×", textSize = 23, textColor = { hex = "#A4B4C4" },
      frame = { x = p.frame.w - 35, y = 17, w = 25, h = 28 }, trackMouseUp = true },
    { type = "text", text = table.concat(display, "\n"), textFont = ".AppleSystemUIFont",
      textSize = 15, textColor = { hex = "#E7EFF6" }, textLineBreak = "clip",
      frame = { x = 20, y = 58, w = p.frame.w - 40, h = p.frame.h - 100 } },
    { type = "text", text = p.footer, textSize = 11, textColor = { hex = "#A1B4C5" },
      frame = { x = 20, y = p.frame.h - 28, w = p.frame.w - 30, h = 20 } }
  )
  canvas:mouseCallback(function(_, message, id)
    if message == "mouseUp" and id == "close" then M.dismiss() end
  end)
  canvas:show()
  if tap then tap:start() end
end

local function show(title, body, engine, mouse)
  hidePanel()
  mouse = mouse or hs.mouse.absolutePosition()
  local screen = screenAt(mouse):frame()
  local width = math.min(410, screen.w - 20)
  local lines = logic.wrap(body, (width - 40) / 15 - 1)
  local count = math.min(#lines, 16, math.max(1, math.floor((screen.h - 125) / 21)))
  local height = math.max(150, 105 + count * 21)
  local footer = engine or "本地取词"
  footer = footer .. (#lines > count and " · 滚动查看更多" or "") .. " · Esc 收起"
  panelData = { title = title, lines = lines, offset = 0, visibleLines = count,
    footer = footer, hasChinese = logic.hasChinese(body), frame = logic.panelFrame(mouse, screen, width, height) }
  renderPanel()
  closeTimer = hs.timer.doAfter(25, M.dismiss)
end

local function fail(err, start)
  remember({ kind = "capture", state = err, elapsedMs = (now() - start) * 1000 })
  show("划词助手", errors[err] or "暂时无法读取选区。", "本地提示")
end

local personalText

local function withPartOfSpeech(body, response, selectedText)
  local parts = response.partsOfSpeech or {}
  if #parts > 0 then
    local label = "词性：" .. table.concat(parts, "／")
    if response.partOfSpeechSource == "system_tag" then label = label .. "（系统识别）" end
    return label .. "\n\n" .. body
  end
  if response.selectionKind == "word" or (selectedText and selectedText:match("^[A-Za-z][A-Za-z'-]*$")) then
    return "词性：暂未确认\n\n" .. body
  end
  return body
end

local function renderResponse(selection, response, start, captureMs, ticket, mouse, cached)
  personal.ensureFresh(function()
    if ticket ~= generation then return end
    local app = hs.application.frontmostApplication()
    if not app or app:pid() ~= selection.pid then return end
    local entries
    if not selection.forceSentence then
      entries = personal.lookup(selection.text)
      if not entries and response.lookupTerm then entries = personal.lookup(response.lookupTerm) end
    end
    local metric = {kind = "translation", state = response.ok and "ok" or response.error,
      captureMs = captureMs, resultMs = (now() - start) * 1000,
      engineMs = response.durationMs, engine = response.engine, cached = cached,
      partOfSpeechAvailable = #(response.partsOfSpeech or {}) > 0}
    if entries and #entries > 0 then
      show(selection.text, withPartOfSpeech(personalText(entries), response, selection.text),
        "我的英语库 · " .. #entries .. " 个语境", mouse)
      metric.state, metric.engine, metric.matches = "ok", "personal_english", #entries
    elseif response.ok and type(response.result) == "string" then
      show(selection.text, withPartOfSpeech(response.result, response, selection.text),
        response.engine == "apple_dictionary" and "苹果英汉词典 · 离线" or "整句翻译 · 离线", mouse)
    else
      show(selection.text, response.message or "本地词典未收录此词。", "本地提示", mouse)
    end
    metric.resultMs = (now() - start) * 1000
    remember(metric)
  end)
end

local function translateOffline(selection, start, captureMs, ticket, mouse)
  local cacheKey = (selection.forceSentence and "sentence\0" or "lookup\0") .. selection.text
  local cached = cache.get(cacheKey, now())
  if cached then
    renderResponse(selection, cached, start, captureMs, ticket, mouse, true)
    return true
  end
  loadingTimer = hs.timer.doAfter(0.08, function()
    if ticket == generation then show(selection.text, "正在查询本地词典…", "本地查询", mouse) end
  end)
  local task
  task = hs.task.new(helper, function(code, stdout)
    if ticket ~= generation then return end
    helperTask = nil; stopTimer(timeoutTimer); stopTimer(loadingTimer)
    timeoutTimer, loadingTimer = nil, nil
    local app = hs.application.frontmostApplication()
    if not app or app:pid() ~= selection.pid then M.dismiss(); return end
    local ok, response = pcall(hs.json.decode, stdout)
    if code ~= 0 or not ok or type(response) ~= "table" then
      show(selection.text, "本地词典进程未能完成查询，请重试。", "本地提示", mouse)
      remember({kind = "translation", state = "helper_failed", resultMs = (now() - start) * 1000})
      return
    end
    if response.ok then cache.put(cacheKey, response, now()) end
    renderResponse(selection, response, start, captureMs, ticket, mouse, false)
  end)
  if not task then
    stopTimer(loadingTimer); show("划词助手", "本地词典程序无法启动。", "本地提示"); return false
  end
  helperTask = task
  task:setInput(hs.json.encode({text = selection.text, forceSentence = selection.forceSentence})):start()
  timeoutTimer = hs.timer.doAfter(15, function()
    if ticket ~= generation then return end
    cancelRequest()
    show(selection.text, "本地查询超时，请缩小选区后重试。", "本地提示", mouse)
    remember({kind = "translation", state = "timeout", resultMs = (now() - start) * 1000})
  end)
  return true
end

personalText = function(entries)
  local sections = {}
  local function plain(text)
    return (text or ""):gsub("\\n", "\n"):gsub("`", "")
  end
  for i = 1, math.min(#entries, 4) do
    local entry = entries[i]
    local lines = { (#entries > 1 and "语境 " .. i .. "\n" or "") .. plain(entry.meaning) }
    if entry.usage ~= "" then lines[#lines+1] = "用法\n" .. plain(entry.usage) end
    if entry.source_sentence ~= "" then lines[#lines+1] = "库内原句\n" .. plain(entry.source_sentence) end
    if entry.review_note ~= "" and entry.review_note ~= entry.usage then
      lines[#lines+1] = "复习备注\n" .. plain(entry.review_note)
    end
    lines[#lines+1] = "词条 " .. entry.id
    sections[#sections+1] = table.concat(lines, "\n")
  end
  if #entries > 4 then sections[#sections+1] = "本词共有 " .. #entries .. " 条记录，当前显示最近的 4 条。" end
  return table.concat(sections, "\n\n")
end

function M.translate()
  if not running then return false end
  local start = now()
  M.dismiss()
  local selection, err = capture()
  if not selection then fail(err, start); return false end
  local captureMs = (now() - start) * 1000
  local ticket, mouse = generation, hs.mouse.absolutePosition()
  personal.ensureFresh(function()
    if ticket ~= generation then return end
    local app = hs.application.frontmostApplication()
    if not app or app:pid() ~= selection.pid then return end
    local exact = personal.lookup(selection.text)
    local knownPhrase = exact and #exact > 0
    if exact then
      for _,entry in ipairs(exact) do if entry.type ~= "词组" then knownPhrase = false; break end end
    end
    selection.forceSentence = logic.looksLikeSentence(selection.text) and not knownPhrase
    translateOffline(selection, start, captureMs, ticket, mouse)
  end)
  return true
end

function M.read()
  if not running then return false end
  local start = now()
  local selection, err = capture()
  if not selection then fail(err, start); return false end
  -- Use the selection itself, never the dictionary's canonical lookup term.
  return speech.toggle(selection.text)
end

function M.openSpeechSettings()
  return speech and speech.openSettings() or false
end

function M.speechPreferences(value)
  if not speech then return false end
  if value then return speech.setPreferences(value) end
  return speech.status().preferences
end

function M.stopSpeech()
  if speech then speech.stopAudio() end
end

function M.status()
  local out = {running = running, popupVisible = canvas ~= nil, cacheEntries = cache.size(),
    last = last, recent = history, helperAvailable = helper and hs.fs.attributes(helper) ~= nil or false}
  if personal then out.englishLibrary = personal.status() end
  if speech then out.speech = speech.status() end
  out.speechSettingsShortcut = settingsHotkey ~= nil and "Ctrl+Option+Command+S" or nil
  if panelData then
    out.panel = {frame = panelData.frame, hasChinese = panelData.hasChinese,
      lines = #panelData.lines, offset = panelData.offset, visibleLines = panelData.visibleLines}
  end
  return out
end

function M.start(options)
  if running then return true end
  options = options or {}
  helper = options.helper or (hs.configdir .. "/mac-selection-translator/dictionary-helper")
  if not hs.fs.attributes(helper) then return false, "helper_missing" end
  if not hs.accessibilityState() then return false, "permission_missing" end
  for _, key in ipairs({"t", "r"}) do
    for _, bound in ipairs(hs.hotkey.getHotkeys()) do
      local idx = bound.idx
      if idx:sub(-1) == key:upper() and idx:find("⌘", 1, true) and idx:find("⌥", 1, true)
        and idx:find("⌃", 1, true) and not idx:find("⇧", 1, true) then
        return false, "hotkey_already_in_use_" .. key
      end
    end
    if not hs.hotkey.assignable(MODS, key) then return false, "hotkey_unavailable_" .. key end
  end
  for _, entry in ipairs({{"t", M.translate}, {"r", M.read}}) do
    local key = hs.hotkey.new(MODS, entry[1], entry[2])
    if not key or not key:enable() then M.stop(); return false, "hotkey_registration_failed" end
    hotkeys[#hotkeys + 1] = key
  end
  speech = speechModule.new({directory=hs.configdir .. "/mac-selection-translator",
    onStatus=function(state)
      remember({kind="speech",state=state.phase,engine=state.engine,requestId=state.requestId,
        voice=state.actualVoice,rate=state.rate,speechStartMs=state.startMs,error=state.error,
        fallbackReason=state.fallbackReason})
    end,
    notice=function(message)
      local screen=speechModule.workScreen()
      if screen then hs.alert.show(message,{textSize=15},screen,5) end
    end})
  local settingsAvailable=hs.hotkey.assignable(MODS,"s")
  for _,bound in ipairs(hs.hotkey.getHotkeys()) do
    local idx=bound.idx
    if idx:sub(-1)=="S" and idx:find("⌘",1,true) and idx:find("⌃",1,true)
      and idx:find("⌥",1,true) and not idx:find("⇧",1,true) then settingsAvailable=false end
  end
  if settingsAvailable then
    local key=hs.hotkey.new(MODS,"s",M.openSpeechSettings)
    if key and key:enable() then settingsHotkey=key elseif key then key:delete() end
  end
  tap = hs.eventtap.new({hs.eventtap.event.types.keyDown, hs.eventtap.event.types.leftMouseDown,
    hs.eventtap.event.types.rightMouseDown, hs.eventtap.event.types.scrollWheel}, function(event)
    if not canvas or not panelData then return false end
    local kind = event:getType()
    if kind == hs.eventtap.event.types.keyDown then
      if event:getKeyCode() == hs.keycodes.map.escape then M.dismiss(); return true end
      return false
    end
    local point, f = hs.mouse.absolutePosition(), panelData.frame
    local inside = point.x >= f.x and point.x <= f.x + f.w and point.y >= f.y and point.y <= f.y + f.h
    if kind == hs.eventtap.event.types.scrollWheel then
      if not inside then return false end
      local delta = event:getProperty(hs.eventtap.event.properties.scrollWheelEventDeltaAxis1)
      if delta ~= 0 then
        panelData.offset = math.max(0, math.min(#panelData.lines - panelData.visibleLines,
          panelData.offset + (delta < 0 and 3 or -3)))
        renderPanel()
      end
      return true
    end
    if not inside then M.dismiss() end
    return false
  end)
  appWatcher = hs.application.watcher.new(function(_, event)
    if event == hs.application.watcher.activated then M.dismiss() end
  end):start()
  personal = englishLookup.new(hs.configdir .. "/mac-selection-translator")
  running = true
  -- Warm framework pages using synthetic text; no speech and no user selection.
  warmTask = hs.task.new(helper, function() warmTask = nil end)
  if warmTask then warmTask:setInput(hs.json.encode({text = "hello"})):start() end
  return true
end

function M.stop()
  running = false
  M.dismiss()
  for _, key in ipairs(hotkeys) do key:delete() end
  hotkeys = {}
  if appWatcher then appWatcher:stop(); appWatcher = nil end
  if tap then tap:stop(); tap = nil end
  if speech then speech.dispose(); speech = nil end
  if settingsHotkey then settingsHotkey:delete(); settingsHotkey=nil end
  if warmTask then warmTask:setCallback(nil):terminate(); warmTask = nil end
  if personal then personal.stop(); personal = nil end
  cache.clear()
end

return M
