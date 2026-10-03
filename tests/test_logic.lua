-- Execute in Hammerspoon with dofile; no shortcuts or system state are changed.
local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)/tests/test_logic.lua$")
local logic = dofile(root .. "/hammerspoon/selection_logic.lua")
local count = 0
local function check(ok, message)
  assert(ok, message); count = count + 1
end
check(logic.trim(" \nhello\t") == "hello", "trim")
check(logic.trim(" \n") == nil, "blank")
check(logic.trim("hello\0") == nil, "null")
check(logic.trim(string.rep("a", 2049)) == nil, "size limit")
check(logic.hasChinese("hello 你好"), "Chinese")
check(not logic.hasChinese("definition"), "English is not Chinese")
check(logic.looksLikeSentence("I love you"), "short sentence without punctuation")
check(logic.looksLikeSentence("Idealists hope to improve the world."), "full sentence")
check(not logic.looksLikeSentence("in response to"), "personal phrase is not a sentence")
check(not logic.looksLikeSentence("idealists"), "word is not a sentence")
check(logic.shorten("你好🙂世界", 3) == "你好🙂…", "UTF-8 shorten")
local wrapped = logic.wrap("hello | 你好🙂世界 and a longwordlongwordlongword", 8)
check(#wrapped > 3, "wrap")
for _, line in ipairs(wrapped) do check(utf8.len(line) ~= nil, "UTF-8 wrap") end
for _, screen in ipairs({{x=0,y=30,w=1920,h=1050},{x=-1470,y=33,w=1470,h=923},
  {x=1920,y=-153,w=846,h=1474},{x=0,y=-1080,w=1920,h=1080}}) do
  local frame = logic.panelFrame({x=screen.x+screen.w-1,y=screen.y+screen.h-1},screen,410,380)
  check(frame.x >= screen.x and frame.y >= screen.y, "top-left contained")
  check(frame.x+frame.w <= screen.x+screen.w and frame.y+frame.h <= screen.y+screen.h, "bottom-right contained")
end
local cache = logic.cache(2, 10)
cache.put("a", 1, 0); cache.put("b", 2, 1)
check(cache.get("a", 2) == 1, "cache hit")
cache.put("c", 3, 3)
check(cache.get("b", 3) == nil, "LRU eviction")
check(cache.get("a", 10) == nil, "TTL boundary")
cache.clear(); check(cache.size() == 0, "cache clear")
print("Logic tests passed: " .. count)
