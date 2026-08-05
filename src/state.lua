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
local M = {}

M.EMPTY_CUE_NUMBER = "--"

function M.new()
  return {
    displayed = { sequence = "", cueNumber = M.EMPTY_CUE_NUMBER, cueName = "" },
    seen = {},              -- sequence name -> cue number at the previous scan
    activeSequences = {},
  }
end

function M.update(st, snapshots)
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

function M.payload(st, version, now)
  return {
    sequence = st.displayed.sequence,
    cueNumber = st.displayed.cueNumber,
    cueName = st.displayed.cueName,
    activeSequences = st.activeSequences,
    updatedAt = now,
    version = version,
  }
end

return M
