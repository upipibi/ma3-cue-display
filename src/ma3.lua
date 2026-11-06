-- The ONLY module that touches the grandMA3 object model. Deliberately thin:
-- MA's own docs warn that plugins may need rewriting on a software upgrade, so
-- when that happens this is the single file to revisit.
--
-- Every console call is wrapped in pcall. A property that disappears in a future
-- MA3 version must degrade the display, not crash the plugin mid-service.
--
-- Console globals used here: DataPool (sequences) and ObjectList (timecode slots).
local M = {}

local EMPTY = "--"

-- MA3 stores cue numbers scaled by 1000 (cue 12.5 is 12500) and allows three
-- decimal places. cue.index truncates to whole numbers and must not be used.
function M.format_cue_number(no)
  local n = tonumber(no)
  if not n then return EMPTY end
  local s = string.format("%.3f", n / 1000)
  s = s:gsub("0+$", "")
  s = s:gsub("%.$", "")
  return s
end

-- A TimecodeSlot's TIME property is seconds scaled by 2^24 (read on a grandMA3
-- light, 2.5.1.1: 120870893431 while the slot showed 2h00m04:14).
local TIME_UNITS_PER_SECOND = 16777216

function M.new(api)
  api = api or {}
  return {
    api = {
      sequences = api.sequences or function() return DataPool().Sequences:Children() end,
      -- ObjectList is how the console resolves an address to an object.
      slot = api.slot or function(n) return ObjectList("TimecodeSlot " .. n)[1] end,
    },
    fades = {},   -- sequence id -> { key = raw cue number, fade = seconds or nil }
    slots = {},   -- timecode slot number -> its object, looked up once
  }
end

local function try(fn)
  local ok, value = pcall(fn)
  if ok then return value end
  return nil
end

-- The cue's fade lives on its part 0, the cue's first child.
local function read_fade(cue)
  local part = try(function() return cue:Ptr(1) end)
  if not part then return nil end
  return tonumber(try(function() return part:Get("CUEINFADE") end))
end

function M.snapshot(self)
  local out = {}
  -- Rebuilt every scan, so a sequence that stops drops out of the cache and
  -- its fade is read fresh when it starts again.
  local fades = {}
  local previous = self.fades or {}
  self.fades = fades
  local seqs = try(self.api.sequences)
  if type(seqs) ~= "table" then return out end

  for _, seq in ipairs(seqs) do
    local playing = try(function() return seq:HasActivePlayback() end)
    if playing then
      local cue = try(function() return seq:CurrentChild() end)
      if cue then
        local no = try(function() return cue.No end)
        if no ~= nil then
          local name = tostring(try(function() return seq.name end) or "?")
          -- seq.No mirrors how the cue number is read; Get("NO") is the form the
          -- MA3 MCP plugin reads on this console, kept as a fallback.
          local number = tonumber(try(function() return seq.No end))
            or tonumber(try(function() return seq:Get("NO") end))
          -- The fade is read when the cue changes, not on every scan: the scan
          -- runs five times a second on the console's UI thread.
          local id = number or name
          local cached = previous[id]
          if not cached or cached.key ~= no then
            cached = { key = no, fade = read_fade(cue) }
          end
          fades[id] = cached
          out[#out + 1] = {
            name = name,
            number = number,
            cueNumber = M.format_cue_number(no),
            cueName = tostring(try(function() return cue.name end) or ""),
            cueKey = no,
            fade = cached.fade,
          }
        end
      end
    end
  end
  return out
end

-- One sample per timecode slot: { { slot = 1, seconds = 7204.47 }, ... }.
-- seconds is nil when the slot cannot be read; the handle is then dropped so
-- the next call looks it up again.
function M.timecode(self, slots)
  local out = {}
  for i, n in ipairs(slots or {}) do
    local handle = self.slots[n]
    if handle == nil then
      handle = try(function() return self.api.slot(n) end)
      self.slots[n] = handle
    end
    local raw = handle and try(function() return handle:Get("TIME") end)
    local seconds = (type(raw) == "number" or type(raw) == "string") and tonumber(raw) or nil
    if seconds then
      seconds = seconds / TIME_UNITS_PER_SECOND
    else
      self.slots[n] = nil
    end
    out[i] = { slot = n, seconds = seconds }
  end
  return out
end

return M
