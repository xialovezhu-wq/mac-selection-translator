local M = {}

function M.trim(text)
  if type(text) ~= "string" then return nil end
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" or text:find("%z") then return nil end
  local count = utf8.len(text)
  if not count or count > 2048 then return nil end
  return text
end

function M.hasChinese(text)
  for _, c in utf8.codes(text or "") do
    if c >= 0x3400 and c <= 0x9fff then return true end
  end
  return false
end

function M.shorten(text, length)
  if (utf8.len(text) or 0) <= length then return text end
  return text:sub(1, utf8.offset(text, length + 1) - 1) .. "…"
end

-- Approximate display cells, preserving UTF-8 boundaries and word boundaries.
function M.wrap(text, cells)
  cells = math.max(1, cells)
  local lines, line, width = {}, "", 0
  local function append(token)
    local n = 0
    for _, cp in utf8.codes(token) do n = n + (cp < 0x3000 and 0.55 or 1) end
    if n > cells then
      for _, cp in utf8.codes(token) do append(utf8.char(cp)) end
    else
      if width + n > cells and line ~= "" then
        lines[#lines + 1] = line:gsub("%s+$", "")
        line, width = "", 0
      end
      if line ~= "" or token ~= " " then line, width = line .. token, width + n end
    end
  end
  text = text:gsub(" %| ", "\n")
  for paragraph in (text .. "\n"):gmatch("(.-)\n") do
    for token in paragraph:gmatch("%S+%s*") do append(token) end
    lines[#lines + 1] = line:gsub("%s+$", "")
    line, width = "", 0
  end
  return lines
end

function M.panelFrame(mouse, screen, width, height)
  width, height = math.min(width, screen.w - 20), math.min(height, screen.h - 20)
  local x, y = mouse.x + 12, mouse.y + 18
  if y + height > screen.y + screen.h - 10 then y = mouse.y - height - 12 end
  x = math.max(screen.x + 10, math.min(x, screen.x + screen.w - width - 10))
  y = math.max(screen.y + 10, math.min(y, screen.y + screen.h - height - 10))
  return { x = x, y = y, w = width, h = height }
end

function M.cache(capacity, ttl)
  local entries, order = {}, {}
  local function remove(key)
    entries[key] = nil
    for i, k in ipairs(order) do if k == key then table.remove(order, i); break end end
  end
  local cache = {}
  function cache.get(key, now)
    local entry = entries[key]
    if not entry then return nil end
    if now - entry.time >= ttl then remove(key); return nil end
    local value, time = entry.value, entry.time
    remove(key); entries[key] = {value = value, time = time}; order[#order + 1] = key
    return value
  end
  function cache.put(key, value, now)
    remove(key); entries[key] = {value = value, time = now}; order[#order + 1] = key
    while #order > capacity do remove(order[1]) end
  end
  function cache.clear() entries, order = {}, {} end
  function cache.size() return #order end
  return cache
end

return M
