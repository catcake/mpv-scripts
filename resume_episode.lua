-- resume_episode.lua
-- https://github.com/catcake/mpv-scripts
-- Version: 0.0.1

-- TODO:
-- resume_data_directory: Option to specify a directory where all resume.json's are stored (forces dynamic_filename?)
-- exclude_directories: Option to specify directories where calls to save() will be ignored
-- include_directories: Option to where calls to save() may be honored (overrides exclude_directories)
-- preserve_later_save: Option to preserve a save if save() attempts to write an earlier episode

local log = require "mp.msg"
local mp_options = require "mp.options"
local mp_utils = require "mp.utils"

local Cutoff = {
    is_inside_start,
    is_inside_end
}

local Listeners = {
    on_file_loaded,
    on_shutdown,
    on_unload
}

local MessageListeners = {
    on_message_resume,
    on_message_save,
    on_message_save_quit,
    on_message_set_autosave,
    on_message_toggle_autosave
}

local Utils = {
    get_cwd_data,
    get_playing_data,
    new_resume_data
}

local This = {
    -- Fields
    cwd,                -- See: Utils.get_cwd_data(),
    playing_data,       -- See: Utils.get_playing_data(),
    loaded_resume_data, -- See: Utils.new_resume_data("", -1)
    -- Functions
    resume,
    resume_prompt,
    save
}

local REGEX_SPLIT_ON_FILE_EXT = "^(.+)%.(.+)$"
local RESUME_MODE = {
    AUTO = "auto",
    MANUAL = "manual",
    PROMPT = "prompt"
}
local options = { -- Script options
    enabled = true,

    resume_mode = "prompt",

    prompt_duration = 15,
    prompt_default_resume = true,
    prompt_bind_resume = "Y",
    prompt_bind_resume_to = "y",
    prompt_bind_deny = "n",

    autosave = true,
    dynamic_filename = true,

    start_cutoff_dont_resume_to_playback_time = 60,
    end_cutoff_go_to_next = 180,

    osd_saved_msg_duration = 5,
    osd_resumed_msg_duration = 10
}

-- Utils definitions
    Utils.get_cwd_data = function()
        local path = mp_utils.getcwd()
        local files = mp_utils.readdir(path, "files")
        table.sort(files)

        return { path = path, files = files }
    end

    Utils.get_playing_data = function()
        local filename = mp.get_property("filename") or ""

        return {
            filename = filename,
            title = filename:match(REGEX_SPLIT_ON_FILE_EXT),
            duration = mp.get_property_number("duration"),
            playback_time = mp.get_property_number("playback-time")
        }
    end

    Utils.new_resume_data = function(episode_filename, playback_time)
        return {
            filename = episode_filename,
            title = episode_filename:match(REGEX_SPLIT_ON_FILE_EXT),
            playback_time = playback_time
        }
    end
-- Utils definitions end

-- Cutoff definitions
    Cutoff.is_inside_start = function()
        return This.loaded_resume_data.playback_time < options.start_cutoff_dont_resume_to_playback_time
    end

    Cutoff.is_inside_end = function()
        return This.playing_data.duration - options.end_cutoff_go_to_next < This.playing_data.playback_time
    end
-- Cutoff definitions end

-- Listeners definitions
    Listeners.on_file_loaded = function()

        local function late_init()

            local function get_resume_filename()
                local REGEX_MATCH_SAVE_FILE = "^.*%.resume%.json$"
                for _, filename in pairs(This.cwd.files) do
                    if filename:match(REGEX_MATCH_SAVE_FILE) ~= nil then
                        return filename end
                end
                return nil
            end

            local function read_json_file_to_table(filename)
                local file = io.open(filename, "r")
                if file == nil then
                    return nil end

                local json = file:read("*all")
                file:close()
                return mp_utils.parse_json(json)
            end

            --

            if This.loaded_resume_data == nil or This.loaded_resume_data.playback_time ~= -1 then
                return end

            local resume_filename = get_resume_filename()

            if resume_filename == nil then
                This.loaded_resume_data = nil
                return
            end

            This.loaded_resume_data = read_json_file_to_table(resume_filename)
            This.loaded_resume_data.resume_filename = resume_filename
        end

        --

        This.cwd = Utils.get_cwd_data()
        late_init()
        This.playing_data = Utils.get_playing_data()

        if This.loaded_resume_data == nil then
            log.info("function 2:", on_file_loaded)
            mp.unregister_event(on_file_loaded)
            return
        end

        if This.loaded_resume_data.filename == This.playing_data.filename then
            log.info("function 3:", on_file_loaded)
            mp.unregister_event(on_file_loaded)
            if not Cutoff.is_inside_start() then
                mp.commandv("seek", This.loaded_resume_data.playback_time) end
            return
        end

        if options.resume_mode == RESUME_MODE.AUTO then
            resume()
        elseif options.resume_mode == RESUME_MODE.PROMPT then
            show_resume_prompt() end
    end

    Listeners.on_unload = function()
        This.playing_data = Utils.get_playing_data()
    end

    Listeners.on_shutdown = function()
        if options.autosave then
            This.save() end
    end
-- Listeners definitions end

-- MessageListeners definitions
    MessageListeners.on_message_resume = function()
        This.resume()
    end

    MessageListeners.on_message_save = function()
        This.save()
    end

    MessageListeners.on_message_save_quit = function()
        This.save()
        mp.commandv("quit")
    end

    MessageListeners.on_message_set_autosave = function(enable)
        options.autosave = enable == "true" and true or false
    end

    MessageListeners.on_message_toggle_autosave = function()
        options.autosave = not options.autosave
    end
-- MessageListeners definitions end

-- This definitions
    This.resume = function(use_playback_time)

        -- TODO: Use resume data of furthest episode

        if use_playback_time or use_playback_time == nil then
            use_playback_time = true
        else
            use_playback_time = false end

        if not use_playback_time then
            This.loaded_resume_data.playback_time = 0 end

        if This.loaded_resume_data == nil then
            log.error("Attempted resume with no resume file!")
            mp.osd_message("Attempted resume with no resume file!", 10)
            return
        end

        os.remove(This.loaded_resume_data.resume_filename)

        log.info("Resuming to", This.loaded_resume_data.filename)
        mp.osd_message("Resuming to " .. This.loaded_resume_data.title, options.osd_resumed_msg_duration)

        mp.commandv("loadfile", This.loaded_resume_data.filename)
    end

    This.show_resume_prompt = function()
        local BIND_RESUME = "__resume_episode_prompt_resume"
        local BIND_RESUME_TO = "__resume_episode_prompt_resume_to"
        local BIND_DENY = "__resume_episode_prompt_deny"

        local prompt_timer = nil
        local timer_duration = options.prompt_duration

        local function cleanup_prompt()
            timer_duration = 0
            prompt_timer:kill()
            mp.remove_key_binding(BIND_RESUME)
            mp.remove_key_binding(BIND_RESUME_TO)
            mp.remove_key_binding(BIND_DENY)
            mp.osd_message("", 0.001)
        end

        -- Add keybindings
        mp.add_forced_key_binding(options.prompt_bind_resume, BIND_RESUME, function()
                cleanup_prompt()
                resume(false)
            end)

        mp.add_forced_key_binding(options.prompt_bind_resume_to, BIND_RESUME_TO, function()
                cleanup_prompt()
                resume()
            end)

        mp.add_forced_key_binding(options.prompt_bind_deny, BIND_DENY, function()
                cleanup_prompt()
                log.info("function 1:", Listeners.on_file_loaded)
                mp.unregister_event(Listeners.on_file_loaded)
            end)

        -- Start timer
        prompt_timer = mp.add_periodic_timer(0.05, function()
                if timer_duration <= 0 then
                        cleanup_prompt()
                    if options.prompt_default_resume then
                        resume() end
                    return
                end

                timer_duration = timer_duration - 0.05

                mp.osd_message(
                    string.format(
                        "Resume prompt ( %.1f ):\n  filename: %s\n  resume (%s) / resume to: %02i:%02i (%s) / cancel (%s)",
                        timer_duration,
                        This.loaded_resume_data.title,
                        options.prompt_bind_resume,
                        This.loaded_resume_data.playback_time / 60,
                        This.loaded_resume_data.playback_time % 60,
                        options.prompt_bind_resume_to,
                        options.prompt_bind_deny),
                    0.1)
            end) -- Starts automatically
    end

    This.save = function(next_episode)

        -- Returns true when no elements of `files` (other than `filename`) match the extension of `filename`.
        local function is_lone_file(filename, files)
            local target_name, target_ext = filename:match(REGEX_SPLIT_ON_FILE_EXT)
            for _, filename in ipairs(files) do
                local name, ext = filename:match(REGEX_SPLIT_ON_FILE_EXT)
                if target_ext == ext and target_name ~= name then
                    return false end
            end
            return true
        end

        -- Returns the filename for the resume file.
        local function build_resume_filename(episode_filename)
            local base_resume_filename = ".resume.json"

            if not options.dynamic_filename then
                return base_resume_filename end

            return episode_filename:match(REGEX_SPLIT_ON_FILE_EXT) .. base_resume_filename
        end

        -- Returns the next episode's path if inside the end cuttoff otherwise the current episode's path
        -- Returns nil when the current episode is the last
        local function get_next_episode_filename(playing_filename, files)
            local located_current = false
            for _, filename in ipairs(files) do
                if located_current then
                    return filename end
                -- TODO: Ensure extentions match
                if playing_filename == filename then
                    located_current = true end
            end
            return nil
        end

        --

        if mp.get_property_bool("current-tracks/video/image") then
            return end

        if is_lone_file(This.playing_data.filename, This.cwd.files) then
            return end

        local resume_data
        if Cutoff.is_inside_end() then
            local next_episode_filename = get_next_episode_filename(This.playing_data.filename, This.cwd.files)
            if next_episode_filename == nil then
                log.warn("Next episode not found")
                return
            end
            resume_data = Utils.new_resume_data(next_episode_filename, 0)
        else
            resume_data = Utils.new_resume_data(This.playing_data.filename, This.playing_data.playback_time)
        end

        -- TODO: Check if there is resume data for an earlier episode (delete it)
        -- TODO: Check if there is resume data for a later episode (preserve it)

        log.info("Saving episode", resume_data.filename)
        mp.osd_message("Saving episode " .. resume_data.title, options.osd_on_save_duration)

        local json = mp_utils.format_json(resume_data)
        local file = io.open(build_resume_filename(resume_data.filename), "w")
        file:write(json .. "\n")
        file:close()
    end
-- This definitions end

local function main()
    mp_options.read_options(options)
    if not options.enabled then
        log.warn("Not enabled")
        return
    end

    mp.add_hook("on_unload", 50, Listeners.on_unload)

    mp.register_event("file-loaded", Listeners.on_file_loaded)
    mp.register_event("shutdown", Listeners.on_shutdown)

    mp.register_script_message("resume", MessageListeners.on_message_resume)
    mp.register_script_message("save", MessageListeners.on_message_save)
    mp.register_script_message("save-quit", MessageListeners.on_message_save_quit)
    mp.register_script_message("set-autosave", MessageListeners.on_message_set_autosave)
    mp.register_script_message("toggle-autosave", MessageListeners.on_message_toggle_autosave)
end

main()
