--[[--
Region-limited screen update for KOReader on Android.

koreader-base's framebuffer_android:_updateWindow() copies the whole shadow
blitbuffer into the native window on every refresh, whatever the region.
On a 3200x2400 panel that is ~30 MB per call, which makes a drawing loop
lag by seconds. Android's ANativeWindow_lock() accepts dirty bounds and
copies the untouched area back from the previously posted buffer itself,
so a stroke only needs its own small rectangle blitted.

This is a stopgap until koreader-base's _updateWindow() takes a rect.
It only touches what it is given; everything else still goes through
KOReader's normal refresh path.
--]]

local M = {}

-- Returns a function refresh(x, y, w, h) in logical screen coordinates,
-- or nil when not on Android / something needed is missing.
function M.install(Screen, logger)
    local ok_android, android = pcall(require, "android")
    if not ok_android or type(android) ~= "table" or not android.lib then
        return nil
    end
    if not (android.getEinkConstants and android.isEinkFull and android.app) then
        return nil
    end
    local ffi = require("ffi")
    local C = ffi.C
    local BB = require("ffi/blitbuffer")
    -- Missing cdefs raise on access; probe them safely.
    local ok_cdef = pcall(function() return C.WINDOW_FORMAT_RGBA_8888, C.WINDOW_FORMAT_RGBX_8888, C.WINDOW_FORMAT_RGB_565 end)
    if not ok_cdef or not Screen._updatePartial then
        return nil
    end

    local _full, _partial, _full_ui, _partial_ui, fast, _delay_page, _delay_ui, delay_fast = android.getEinkConstants()
    local eink_full = android.isEinkFull()
    local buffer = ffi.new("ANativeWindow_Buffer[1]")
    local dirty = ffi.new("ARect[1]")

    local function refresh(x, y, w, h)
        local ext_bb = Screen.full_bb or Screen.bb
        x, y, w, h = ext_bb:getBoundedRect(x, y, w, h)
        if not w or w <= 0 or h <= 0 then return end
        local px, py, pw, ph = ext_bb:getPhysicalRect(x, y, w, h)

        local window = android.app.window
        if window == nil then return end

        dirty[0].left = px
        dirty[0].top = py
        dirty[0].right = px + pw
        dirty[0].bottom = py + ph
        if android.lib.ANativeWindow_lock(window, buffer, dirty) < 0 then
            return
        end

        local b = buffer[0]
        local bb
        if b.format == C.WINDOW_FORMAT_RGBA_8888 or b.format == C.WINDOW_FORMAT_RGBX_8888 then
            bb = BB.new(b.width, b.height, BB.TYPE_BBRGB32, b.bits, b.stride * 4, b.stride)
        elseif b.format == C.WINDOW_FORMAT_RGB_565 then
            bb = BB.new(b.width, b.height, BB.TYPE_BBRGB16, b.bits, b.stride * 2, b.stride)
        end

        if bb then
            -- The system may have widened the dirty bounds (e.g. when it
            -- could not copy the rest back); honour what it returns.
            local d = dirty[0]
            local dx, dy = d.left, d.top
            local dw, dh = d.right - d.left, d.bottom - d.top
            -- Blit in physical space: window buffer is unrotated, so drop the
            -- shadow buffer's rotation for the duration of the copy.
            local rot = ext_bb:getRotation()
            local inv = ext_bb:getInverse()
            ext_bb:setRotation(0)
            if inv == 1 and bb:getType() == ext_bb:getType() then
                bb:invertblitFrom(ext_bb, dx, dy, dx, dy, dw, dh)
            else
                bb:blitFrom(ext_bb, dx, dy, dx, dy, dw, dh)
                if inv == 1 then
                    bb:invertRect(dx, dy, dw, dh)
                end
            end
            ext_bb:setRotation(rot)
        end

        android.lib.ANativeWindow_unlockAndPost(window)

        if eink_full then
            Screen:_updatePartial(fast, delay_fast, x, y, w, h)
        end
    end

    if logger then logger.info("Pencil: Android region refresh installed") end
    return refresh
end

return M
