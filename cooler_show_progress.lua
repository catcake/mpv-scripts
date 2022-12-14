-- cooler_show_progress.lua
-- https://github.com/catcake/mpv-scripts
--
-- This mpv script implements the functionality from mpv's show-progress command (minus the progress bar),
-- but allows users to control how long it is displayed, seperate from --osd-duration.
--
-- The progress bar is not show because I could not find a way to display it
-- for any duration other than what is specified by --osd-duration.
--
-- input.conf usage:
-- [keybind] script-message-to cooler_show_progress show-progress [duration in milliseconds]
--
-- Practical example:
-- Wheel_Right no-osd seek 1; script-message-to cooler_show_progress show-progress 500
--
-- There are no user-configurable options here, only the duration parameter passed the command.

local log = require "mp.msg"

-- 50ms is the highest supported timer resolution (mpv 0.35.0-33), which is fine.
local TIMER_PERIOD = 0.05
-- The messages need to overlap (their duration > TIMER_PERIOD), otherwise they will flicker.
local OSD_DURATION = TIMER_PERIOD * 2

local state = {
    duration_remaining = 0,
    osd_symbol = "",  -- play/pause/forward/backward symbol
    timer = nil
}

-- These two are simple but make the code more clear.
local function ms_to_seconds(ms) return ms / 1000 end
local function osd_clear() mp.osd_message("", 0.001) end

-- Get and assemble the progress info.
local function get_progress_string()
    local position = mp.get_property_osd("playback-time")
    local position_percent = mp.get_property_osd("percent-pos")
    local duration = mp.get_property_osd("duration")
    return state.osd_symbol .." ".. position .." / ".. duration .." (".. position_percent .."%)"
end

-- Post OSD messages containing the progress info at each timer period
-- until `state.duration_remaining` is depleated.
local function on_timer_period()
    if TIMER_PERIOD > state.duration_remaining then
        state.timer:kill()
        osd_clear()
        return
    end
    mp.osd_message(get_progress_string(), OSD_DURATION)
    state.duration_remaining = state.duration_remaining - TIMER_PERIOD
end

-- Seems to be convention in mpv for user-facing options/parameters to be in ms ¯\_(ツ)_/¯
local function on_message_show_progress(duration_ms)
    state.osd_symbol = mp.get_property_osd("osd-sym-cc")

    if duration_ms == nil then
        duration_ms = mp.get_property_number("osd-duration")
        log.warn("No duration given (using --osd-duration)")
    end
    state.duration_remaining = ms_to_seconds(duration_ms)
    state.timer:resume()
end

state.timer = mp.add_periodic_timer(TIMER_PERIOD, on_timer_period)
mp.register_script_message("show-progress", on_message_show_progress)
