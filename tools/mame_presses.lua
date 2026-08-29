-- Press Coin 1 at frame YB_COIN and 1 Player Start at each frame in YB_STARTS
-- (comma-separated), four frames each. Used by mame_trace.py next to the
-- debugger's trace so a traced run can reach a screen behind inputs.
local frame = 0
local coin = tonumber(os.getenv("YB_COIN") or "-1")
local starts = {}
for s in string.gmatch(os.getenv("YB_STARTS") or "", "[^,]+") do starts[#starts + 1] = tonumber(s) end
local function press(field, on)
  local p = manager.machine.ioport.ports[":GENERAL"]; local f = p.fields[field]; if f then f:set_value(on and 1 or 0) end
end
emu.register_frame_done(function()
  frame = frame + 1
  if frame == coin then press("Coin 1", true) end
  if frame == coin + 4 then press("Coin 1", false) end
  for _, s in ipairs(starts) do
    if frame == s then press("1 Player Start", true) end
    if frame == s + 4 then press("1 Player Start", false) end
  end
end)
