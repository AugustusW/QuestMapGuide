-- 把 SavedVariables（QuestMapGuide.lua）轉成 JSON 印到 stdout
-- 用法：luajit tools/sv2json.lua <QuestMapGuide.lua>
local path = assert(arg[1], "usage: sv2json.lua <SavedVariables.lua>")
local env = {}
local chunk = assert(loadfile(path))
setfenv(chunk, env)
chunk()

local function isArray(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" then return false end
    n = n + 1
  end
  return n == #t
end

local enc
local function str(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
    return map[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end
enc = function(v)
  local t = type(v)
  if t == "table" then
    local parts = {}
    if isArray(v) and #v > 0 then
      for _, x in ipairs(v) do parts[#parts + 1] = enc(x) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do parts[#parts + 1] = str(tostring(k)) .. ":" .. enc(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif t == "string" then return str(v)
  elseif t == "number" then return tostring(v)
  elseif t == "boolean" then return tostring(v)
  else return "null" end
end

io.write(enc(env.QuestMapGuideDB or {}), "\n")
