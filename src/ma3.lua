-- The ONLY module that touches the grandMA3 object model. Deliberately thin:
-- MA's own docs warn that plugins may need rewriting on a software upgrade, so
-- when that happens this is the single file to revisit.
--
-- Every console call is wrapped in pcall. A property that disappears in a future
-- MA3 version must degrade the display, not crash the plugin mid-service.
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

function M.new(api)
  return {
    api = api or {
      sequences = function() return DataPool().Sequences:Children() end,
    },
  }
end

local function try(fn)
  local ok, value = pcall(fn)
  if ok then return value end
  return nil
end

function M.snapshot(self)
  local out = {}
  local seqs = try(self.api.sequences)
  if type(seqs) ~= "table" then return out end

  for _, seq in ipairs(seqs) do
    local playing = try(function() return seq:HasActivePlayback() end)
    if playing then
      local cue = try(function() return seq:CurrentChild() end)
      if cue then
        local no = try(function() return cue.No end)
        if no ~= nil then
          out[#out + 1] = {
            name = tostring(try(function() return seq.name end) or "?"),
            cueNumber = M.format_cue_number(no),
            cueName = tostring(try(function() return cue.name end) or ""),
          }
        end
      end
    end
  end
  return out
end

return M
