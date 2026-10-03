local M = {}

local function readJSON(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local raw = file:read(16 * 1024 * 1024 + 1); file:close()
  if #raw > 16 * 1024 * 1024 then return nil end
  local ok, data = pcall(hs.json.decode, raw)
  return ok and data or nil
end

function M.normalize(text)
  return text:lower():gsub("’", "'"):gsub("‘", "'"):gsub("^%s+", "")
    :gsub("%s+$", ""):gsub("%s+", " ")
end

function M.new(directory)
  local indexPath = directory .. "/english-index.json"
  local config = readJSON(directory .. "/english-source.json")
  local index, watcher, task, pending, dirty = readJSON(indexPath), nil, nil, {}, false
  local stopped = false
  local obj = {}
  local function fresh()
    if dirty or not config or not index then return false end
    local a = hs.fs.attributes(config.source)
    return a and index.source == config.source and index.sourceSize == a.size
      and index.sourceMtime == math.floor(a.modification)
  end
  function obj.refresh(callback)
    if callback then pending[#pending+1] = callback end
    if task then return end
    if not config or stopped then
      local callbacks = pending; pending = {}
      for _,fn in ipairs(callbacks) do fn() end
      return
    end
    dirty = true
    task = hs.task.new(config.python, function(code)
      task = nil
      if stopped then return end
      index = code == 0 and readJSON(indexPath) or nil
      dirty = false
      local callbacks = pending; pending = {}
      for _,fn in ipairs(callbacks) do fn() end
    end, {directory .. "/build_english_index.py", "--source", config.source, "--output", indexPath})
    if task then task:start() else
      index, dirty = nil, false
      local callbacks = pending; pending = {}
      for _,fn in ipairs(callbacks) do fn() end
    end
  end
  function obj.ensureFresh(callback)
    if not config or stopped then callback(); return end
    if fresh() then callback(); return end
    obj.refresh(callback)
  end
  function obj.lookup(text)
    if not fresh() or not index or index.schemaVersion ~= 1 then return nil end
    return index.entries[M.normalize(text)]
  end
  function obj.status()
    return {connected = config ~= nil, ready = fresh() and true or false,
      rows = index and index.rows or 0, keys = index and index.keys or 0, refreshing = task ~= nil}
  end
  function obj.stop()
    stopped = true
    if watcher then watcher:stop(); watcher = nil end
    if task then task:setCallback(nil):terminate(); task = nil end
    index, pending = nil, {}
  end
  if config and hs.fs.attributes(config.source) then
    local folder = config.source:match("^(.*)/[^/]+$")
    watcher = hs.pathwatcher.new(folder, function(paths)
      for _,path in ipairs(paths) do
        if path == config.source then dirty = true; obj.refresh(); break end
      end
    end):start()
    if not fresh() then obj.refresh() end
  end
  return obj
end

return M
