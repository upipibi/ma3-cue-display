-- Pure cue-state tracking. Knows nothing about grandMA3 or sockets: it takes a
-- list of active-sequence snapshots and decides which cue to display.
--
-- "Most recently fired" is underdetermined on its own, so three rules make it
-- deterministic:
--   1. If several sequences advance in the same scan and one of them is already
--      displayed, keep it. Otherwise take the first in console iteration order.
--      Without this the display flaps between two simultaneously running stacks.
--   2. Cold start shows the first active sequence that has a cue.
--   3. When the displayed sequence stops playing, keep showing its last cue. A
--      display that blanks itself when a stack goes off is worse than one
--      showing the last cue that ran.
--
-- The grid view adds three more pieces of state, all decided here so the page
-- only draws what it is told:
--   * slots: which sequence sits in which of the fixed grid slots. A running
--     sequence never changes slot, and a start or stop never moves another one.
--     That is the whole point of the grid: the picture must not shuffle.
--   * fire times: when each running sequence's current cue became current, so
--     the page can count the cue's fade down.
--   * timecode: the last sample of each slot and whether it is rolling.
local json = require("json")

local M = {}

M.EMPTY_CUE_NUMBER = "--"

-- A timecode slot counts as rolling while its value changed this recently. One
-- repeated sample must not flash "stopped" on the display.
M.TIMECODE_HOLD_SECONDS = 0.25

function M.new(opts)
  opts = opts or {}
  return {
    displayed = { sequence = "", cueNumber = M.EMPTY_CUE_NUMBER, cueName = "" },
    seen = {},              -- sequence name -> cue number at the previous scan
    activeSequences = {},
    grid = {
      from = opts.grid_from or 1,     -- sequence number range shown in the grid
      to = opts.grid_to or 89,
      count = opts.slots or 8,
      slots = {},     -- slot index -> sequence number, or false when empty
      last = {},      -- sequence number -> the slot it held most recently
      entries = {},   -- sequence number -> its snapshot from the latest scan
      keys = {},      -- sequence number -> cue key at the latest scan
      fired = {},     -- sequence number -> time its current cue became current
      scans = 0,
    },
    timecode = {},        -- slot number -> { seconds, changedAt }
    timecode_order = {},  -- slot numbers in the order they were sampled
  }
end

local function update_grid(g, snapshots, now)
  local running, order = {}, {}
  for _, s in ipairs(snapshots) do
    local n = tonumber(s.number)
    if n and n >= g.from and n <= g.to and running[n] == nil then
      running[n] = s
      order[#order + 1] = n
    end
  end
  table.sort(order)

  -- A sequence that stopped gives its slot back. Nothing else moves.
  for i = 1, g.count do
    local n = g.slots[i]
    if n and not running[n] then g.slots[i] = false end
  end

  -- Fire times. A sequence that was not running at the previous scan has just
  -- fired its cue -- except on the very first scan, where it may have been
  -- sitting on that cue for an hour, so no countdown is invented.
  local keys, fired = {}, {}
  for _, n in ipairs(order) do
    local s = running[n]
    local key = s.cueKey
    if key == nil then key = s.cueNumber end
    keys[n] = key
    if g.keys[n] == nil then
      if g.scans > 0 then fired[n] = now end
    elseif g.keys[n] ~= key then
      fired[n] = now
    else
      fired[n] = g.fired[n]
    end
  end
  g.keys, g.fired, g.entries = keys, fired, running

  -- Place whoever has no slot yet, lowest sequence number first: the slot it
  -- held before if that is empty, else the lowest empty slot, else it waits.
  local placed = {}
  for i = 1, g.count do
    if g.slots[i] then placed[g.slots[i]] = true end
  end
  for _, n in ipairs(order) do
    if not placed[n] then
      local at = nil
      local want = g.last[n]
      if want and want <= g.count and not g.slots[want] then
        at = want
      else
        for i = 1, g.count do
          if not g.slots[i] then at = i break end
        end
      end
      if at then
        g.slots[at] = n
        g.last[n] = at
      end
    end
  end

  g.scans = g.scans + 1
end

-- now is the plugin's wall clock in seconds. It is optional so the single-cue
-- callers and tests that predate the grid keep working; without it no fire
-- times are recorded.
function M.update(st, snapshots, now)
  update_grid(st.grid, snapshots, now)

  local previous = st.seen
  local seen = {}
  local active = {}
  local changed = {}

  for _, s in ipairs(snapshots) do
    seen[s.name] = s.cueNumber
    active[#active + 1] = s.name
    -- A name absent from the previous scan counts as changed. That covers both
    -- cold start and a sequence being re-fired at the cue it was already on.
    if previous[s.name] ~= s.cueNumber then
      changed[#changed + 1] = s
    end
  end

  st.seen = seen
  st.activeSequences = active

  if #changed > 0 then
    local pick = changed[1]
    for _, s in ipairs(changed) do
      if s.name == st.displayed.sequence then
        pick = s
        break
      end
    end
    st.displayed = {
      sequence = pick.name,
      cueNumber = pick.cueNumber,
      cueName = pick.cueName,
    }
  end

  return st
end

-- samples = { { slot = 1, seconds = 7204.47 }, ... }; seconds is nil when the
-- slot could not be read.
function M.update_timecode(st, samples, now)
  local order = {}
  for _, sample in ipairs(samples or {}) do
    local slot = sample.slot
    local entry = st.timecode[slot] or {}
    local seconds = tonumber(sample.seconds)
    if seconds == nil then
      entry.seconds, entry.changedAt = nil, nil
    else
      if entry.seconds ~= nil and seconds ~= entry.seconds then entry.changedAt = now end
      entry.seconds = seconds
    end
    st.timecode[slot] = entry
    order[#order + 1] = slot
  end
  st.timecode_order = order
  return st
end

local function grid_payload(g, now)
  local out = {}
  for i = 1, g.count do
    local n = g.slots[i]
    local s = n and g.entries[n]
    if s then
      local fired = g.fired[n]
      out[i] = {
        number = n,
        name = s.name,
        cueNumber = s.cueNumber,
        cueName = s.cueName,
        fade = tonumber(s.fade) or json.null,
        -- An age, not a timestamp: the console clock and the viewer's clock
        -- never have to agree.
        firedAgo = (fired and now) and math.max(0, now - fired) or json.null,
      }
    else
      out[i] = json.null
    end
  end
  return out
end

local function timecode_payload(st, now)
  local out = {}
  for i, slot in ipairs(st.timecode_order) do
    local entry = st.timecode[slot] or {}
    local running = false
    if entry.seconds ~= nil and entry.changedAt ~= nil and now ~= nil then
      running = (now - entry.changedAt) <= M.TIMECODE_HOLD_SECONDS
    end
    out[i] = { slot = slot, seconds = entry.seconds or json.null, running = running }
  end
  return out
end

function M.payload(st, version, now)
  return {
    sequence = st.displayed.sequence,
    cueNumber = st.displayed.cueNumber,
    cueName = st.displayed.cueName,
    activeSequences = st.activeSequences,
    updatedAt = now,
    version = version,
    grid = grid_payload(st.grid, now),
    timecode = timecode_payload(st, now),
  }
end

return M
