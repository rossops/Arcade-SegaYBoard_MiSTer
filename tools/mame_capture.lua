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
local test_field = nil
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
        if test_field then test_field:set_value(1) end
    end
    if done or frame < frame_target then return end
    done = true
    local subx = manager.machine.devices[":subx"].spaces["program"]
    dump(subx, 0x180000, 0x8000, outdir .. "/yspriteram.bin")
    dump(suby_space, 0x180000, 0x400, outdir .. "/rotateram.bin")
    dump(suby_space, 0x188000, 0x800, outdir .. "/bspriteram.bin")
    dump(suby_space, 0x190000, 0x2000, outdir .. "/paletteram.bin")
    local f = io.open(outdir .. "/frame.txt", "w"); f:write(tostring(frame) .. "\n"); f:close()
    manager.machine.video:snapshot()
    manager.machine:exit()
end)
