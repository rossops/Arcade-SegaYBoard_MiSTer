-- Probe a game's hiscore table from MAME, for hiscore.dat work.
--
--   HS_ADDR=0xff846e HS_LEN=8 [HS_POKE=1] [HS_CPU=:mainpcb:maincpu] \
--     mame <set> -autoboot_script tools/mame_hiscore_probe.lua -autoboot_delay 0 \
--          -video none -sound none -nothrottle -seconds_to_run 45 -nvram_directory <dir>
--
-- Prints HS_LEN bytes at HS_ADDR at frames 30, 300 and 1300 (CPU byte order,
-- so the start/end check values for a hiscore.dat line come straight off the
-- print). With HS_POKE=1 it overwrites the bytes with A0.. at frame 900 and
-- prints them again at 1300: run once with the poke, once more without it
-- on the same nvram directory, and you know whether the game keeps a foreign
-- table across a power cycle or wipes it at boot (After Burner and Racing
-- Hero wipe). With HS_TAP=1 it instead counts the game's own writes into
-- [HS_ADDR, HS_ADDR+HS_LEN) over the first 600 frames and shows the first
-- few, which tells you when the wipe happens.
--
-- Keep the subscriptions global: a local one is garbage-collected after the
-- first frame and MAME then runs on with no exit (looks hung).
local addr = tonumber(os.getenv("HS_ADDR"))
local len  = tonumber(os.getenv("HS_LEN") or "8")
local poke = os.getenv("HS_POKE") == "1"
local tap  = os.getenv("HS_TAP") == "1"
local cpu  = os.getenv("HS_CPU") or ":mainpcb:maincpu"
local frames, nwr, shown = 0, 0, 0
local function space() return manager.machine.devices[cpu].spaces["program"] end
local function dump(tag)
  local sp, s = space(), {}
  for i = 0, len - 1 do s[#s+1] = string.format("%02X", sp:read_u8(addr + i)) end
  print(string.format("HS %s f%d %06X: %s", tag, frames, addr, table.concat(s, " ")))
end
if tap then
  hs_tap = space():install_write_tap(addr & ~0xfff, (addr + len - 1) | 0xfff, "hs", function(offset, data, mask)
    if offset >= addr and offset < addr + len then
      nwr = nwr + 1
      if shown < 12 then shown = shown + 1; print(string.format("HS write f%d %06X data %04X mask %04X", frames, offset, data, mask)) end
    end
  end)
end
hs_sub = emu.add_machine_frame_notifier(function()
  frames = frames + 1
  if not tap and (frames == 30 or frames == 300 or frames == 1300) then dump("read") end
  if poke and frames == 900 then
    local sp = space()
    for i = 0, len - 1 do sp:write_u8(addr + i, 0xA0 + i) end
    dump("poked")
  end
  if tap and frames == 600 then
    print(string.format("HS total writes in [%06X,+%d) during 600 frames: %d", addr, len, nwr))
    manager.machine:exit()
  end
  if frames == 1400 then manager.machine:exit() end
end)
