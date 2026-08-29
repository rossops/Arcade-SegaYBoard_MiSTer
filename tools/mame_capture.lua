-- MAME autoboot script: at frame YB_FRAME dump the Y Board video RAMs and
-- take a screenshot, then exit. Configure through environment variables
-- YB_FRAME (frame number) and YB_OUT (output directory).
local frame_target = tonumber(os.getenv("YB_FRAME") or "300")
local outdir = os.getenv("YB_OUT") or "."
local frame = 0
local done = false

local function dump(space, base, words, path)
    local f = io.open(path, "wb")
    for i = 0, words - 1 do
        local w = space:read_u16(base + i * 2)
        f:write(string.char(w & 0xff, (w >> 8) & 0xff))
    end
    f:close()
end

local test_mode = os.getenv("YB_TEST") == "1"
local test_from = tonumber(os.getenv("YB_TEST_FRAME") or "1")   -- the game wants an edge during the attract
local test_field = nil
-- optional presses, for captures of the game in play (verif/board +coin/+start)
local coin_frame = tonumber(os.getenv("YB_COIN") or "-1")
local start_frame = tonumber(os.getenv("YB_START") or "-1")
local coin_field, start_field = nil, nil
local suby_space = nil
local rot_tap = nil

emu.register_frame_done(function()
    frame = frame + 1
    if rot_tap == nil then
        -- a read of 198000 swaps the rotation RAM with the buffer the
        -- scan-out uses; keep the RAM as it is right after each swap (the
        -- previous buffer) so the pairing can be checked either way
        suby_space = manager.machine.devices[":suby"].spaces["program"]
        rot_tap = suby_space:install_read_tap(0x198000, 0x19ffff, "yb_rotswap", function(offset, data, mask)
            if not done then dump(suby_space, 0x180000, 0x400, outdir .. "/rotateram_swap.bin") end
        end)
    end
    if coin_field == nil then
        local port = manager.machine.ioport.ports[":GENERAL"]
        coin_field = port and port.fields["Coin 1"] or false
        start_field = port and port.fields["1 Player Start"] or false
    end
    if coin_field and coin_frame >= 0 then
        if frame >= coin_frame and frame < coin_frame + 4 then coin_field:set_value(1) end
        if frame == coin_frame + 4 then coin_field:set_value(0) end
    end
    if start_field and start_frame >= 0 then
        if frame >= start_frame and frame < start_frame + 4 then start_field:set_value(1) end
        if frame == start_frame + 4 then start_field:set_value(0) end
    end
    if test_mode then
        if test_field == nil then
            local f = io.open(outdir .. "/ports.txt", "w")
            for tag, port in pairs(manager.machine.ioport.ports) do
                for name, field in pairs(port.fields) do
                    f:write(tag .. " | " .. name .. " | mask=" .. tostring(field.mask) .. "\n")
                    if name == "Service Mode" then test_field = field end
                end
            end
            f:close()
            if test_field == nil then test_field = false end
        end
        -- held from YB_TEST_FRAME on. set_value(1) is "pressed" whatever the
        -- field's active level; the game only reacts to an edge after its boot,
        -- so a level held from frame 1 does nothing (the X Board's finding)
        if test_field and frame >= test_from then test_field:set_value(tonumber(os.getenv("YB_TEST_VAL") or "1")) end
    end
    if done or frame < frame_target then return end
    done = true
    local subx = manager.machine.devices[":subx"].spaces["program"]
    dump(subx, 0x180000, 0x8000, outdir .. "/yspriteram.bin")
    dump(suby_space, 0x180000, 0x400, outdir .. "/rotateram.bin")
    dump(suby_space, 0x188000, 0x800, outdir .. "/bspriteram.bin")
    dump(suby_space, 0x190000, 0x2000, outdir .. "/paletteram.bin")
    local f = io.open(outdir .. "/frame.txt", "w"); f:write(tostring(frame) .. "\n"); f:close()
    -- the screen device alone: the video manager's snapshot composes the
    -- layout artwork on top (Power Drift's gear shifter), which is not video
    manager.machine.screens[":screen"]:snapshot()
    manager.machine:exit()
end)
