--[[
MIT License

Copyright (c) 2024 C.Cords

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Email: mail@clemens-cords.com
GitHub: https://github.com/clemapfel/love_profiler
]]--

--[[
-- ### USAGE

profiler = require "love_profiler.profiler"
profiler.push("zone_name")
-- profiled code here
profiler.pop()
print(profiler.report())

-- note that the profiler needs to run for a few seconds in order to get accurate results
]]--

local profiler = {}

profiler._jit = require("jit.profile")
profiler._run_i = 1
profiler._is_running = false

profiler._data = {}
profiler.n_samples = 0

profiler._zone_name_to_index = {}
profiler._zone_index_to_name = {}
profiler._zone_index = 1
profiler._current_zone_stack = {}
profiler._n_zones = 0
profiler._zone_to_start_time = {}
profiler._zone_to_duration = {}
profiler._start_date = nil

do
    local _infinity = 1 / 0
    local _format = "f @ plZ;" -- <function_name> @ <file>:<line>;
    profiler._sampling_callback = function(thread, n_samples, vmstate)
        if profiler._n_zones > 0 then
            local zones = {}
            for i = 1, profiler._n_zones do
                table.insert(zones, profiler._current_zone_stack[i])
            end

            local data = {}
            for _ = 1, n_samples do
                data.callstack = profiler._jit.dumpstack(thread, _format, _infinity)
                data.zones = zones
                data.vmstate = vmstate
            end

            local splits = {}
            if data.vmstate == "N" or data.vmstate == "J" or data.vmstate == "C" then
                -- split into individual function names
                for split in string.gmatch(data.callstack, "([^;]+)") do
                    table.insert(splits, split)
                end
            end

            for _, zone_i in pairs(data.zones) do
                local zone_name = profiler._zone_index_to_name[zone_i]
                local zone = profiler._data[zone_name]

                if data.vmstate == "N" then
                    zone.n_compiled_samples = zone.n_compiled_samples + n_samples
                elseif data.vmstate == "I" then
                    zone.n_interpreted_samples = zone.n_interpreted_samples + n_samples
                elseif data.vmstate == "C" then
                    zone.n_c_code_samples = zone.n_c_code_samples + n_samples
                elseif data.vmstate == "J" then
                    zone.n_jit_samples = zone.n_jit_samples + n_samples
                elseif data.vmstate == "G" then
                    zone.n_gc_samples = zone.n_gc_samples + n_samples
                else
                    error("In profiler._callback: unhandled vmstate `" .. data.vmstate .. "`")
                end

                for _, split in pairs(splits) do
                    if zone.function_to_count[split] == nil then
                        zone.function_to_count[split] = n_samples
                    else
                        zone.function_to_count[split] = zone.function_to_count[split] + n_samples
                    end
                end

                zone.n_samples = zone.n_samples + 1
            end

            profiler.n_samples = profiler.n_samples + n_samples
        end
    end
end

--- @brief add a zone to the current stack, if the stack was empty, this starts the profiler
--- @param name string (optional) name of the new zone stack element
function profiler.push(name)
    if name == nil then
        name = "Run #" .. profiler._run_i
        profiler._run_i = profiler._run_i + 1
    end

    assert(type(name) == "string")
    local zone_index = profiler._zone_name_to_index[name]
    if zone_index ~= nil then
        for _, zone in pairs(profiler._current_zone_stack) do
            if zone == zone_index then
                error("In profiler.push: Zone `" .. name .. "` is already active, each zone name has to be unique. Use `push()` for a unique name to be chosen automatically")
            end
        end
    end

    if zone_index == nil then
        zone_index = profiler._zone_index
        profiler._zone_index = profiler._zone_index + 1

        profiler._zone_name_to_index[name] = zone_index
        profiler._zone_index_to_name[zone_index] = name
    end

    table.insert(profiler._current_zone_stack, zone_index)
    profiler._n_zones = profiler._n_zones + 1

    if profiler._is_running == false then
        profiler._is_running = true
        profiler._jit.start("i0", profiler._sampling_callback) -- i0 = highest possible frequency architecture allows
        profiler._start_date = os.date("%c")
    end

    if profiler._zone_to_start_time[name] == nil then
        profiler._zone_to_start_time[name] = os.time()
    end

    if profiler._zone_to_duration[name] == nil then
        profiler._zone_to_duration[name] = 0
    end

    if profiler._data[name] == nil then
        profiler._data[name] = {
            function_to_count = {},
            function_to_percentage = {},
            n_samples = 0,
            n_gc_samples = 0,
            n_jit_samples = 0,
            n_interpreted_samples = 0,
            n_compiled_samples = 0,
            n_c_code_samples = 0
        }
    end
end

--- @brief remove the last pushed zone from the stack. If the stack reaches size 0, the profiler stops
function profiler.pop()
    if profiler._n_zones >= 1 then
        local last_zone = profiler._zone_index_to_name[profiler._current_zone_stack[#profiler._current_zone_stack]]
        table.remove(profiler._current_zone_stack, profiler._n_zones)
        profiler._n_zones = profiler._n_zones - 1

        local now = os.time()
        profiler._zone_to_duration[last_zone] = profiler._zone_to_duration[last_zone] + (now - profiler._zone_to_start_time[last_zone])
        profiler._zone_to_start_time[last_zone] = nil
    else
        error("In profiler.pop: Trying to pop, but no zone is active")
    end
end

do
    local function _format_percentage(fraction)
        local value = math.floor(fraction * 10e3) / 10e3 * 100
        if value < 0 then
            value = 0
        elseif value > 100 then
            value = 100
        end
        return value
    end

    --- @brief get state of the profiling data pretty-printed
    function profiler.report()
        for zone_name, entry in pairs(profiler._data) do
            local names_in_order = {}
            for name, count in pairs(entry.function_to_count) do
                entry.function_to_percentage[name] = _format_percentage(count / entry.n_samples)
                local function_count = entry.function_to_count[name]

                -- percentage may be > if function name occurs twice in same callstack
                if function_count < 0 then
                    function_count = 0
                elseif function_count > entry.n_samples then
                    function_count = entry.n_samples
                end

                entry.function_to_count[name] = function_count

                table.insert(names_in_order, name)
            end

            table.sort(names_in_order, function(a, b)
                return entry.function_to_count[a] > entry.function_to_count[b]
            end)

            local cutoff_n = 0
            local cutoff_sample_count = 0
            for _, name in pairs(names_in_order) do
                if entry.function_to_percentage[name] >= 0.1 then
                    cutoff_n = cutoff_n + 1
                else
                    cutoff_sample_count = cutoff_sample_count + entry.function_to_count[name]
                end
            end

            local col_width = {}
            local columns = {
                {"Percentage (%)", entry.function_to_percentage },
                {"# Samples", entry.function_to_count },
                {"Name", names_in_order },
            }

            local col_lengths = {}
            for i, _ in ipairs(columns) do col_lengths[i] = #columns[i][1] end

            local n_columns = 0
            for col_i, column in ipairs(columns) do
                for i, value in ipairs(column[2]) do
                    col_lengths[col_i] = math.max(col_lengths[col_i],  #tostring(value))
                end
                n_columns = n_columns + 1
            end
            col_lengths[2] = math.max(col_lengths[2], #tostring(cutoff_sample_count))

            local header = {" | "}
            local sub_header = {" |-"}
            for col_i, col in ipairs(columns) do
                table.insert(header, col[1] .. string.rep(" ", col_lengths[col_i] - #col[1]))
                table.insert(sub_header, string.rep("-", col_lengths[col_i]))
                if col_i < n_columns then
                    table.insert(header, " | ")
                    table.insert(sub_header, "-|-")
                end
            end

            table.insert(header, " |")
            table.insert(sub_header, "-|")

            local gc_percentage = _format_percentage(entry.n_gc_samples / entry.n_samples)
            local jit_percentage = _format_percentage(entry.n_jit_samples / entry.n_samples)
            local c_percentage = _format_percentage(entry.n_c_code_samples / (entry.n_interpreted_samples + entry.n_compiled_samples + entry.n_c_code_samples))
            local interpreted_percentage = _format_percentage(entry.n_interpreted_samples / (entry.n_interpreted_samples + entry.n_compiled_samples))

            local duration = math.floor(profiler._zone_to_duration[zone_name] * 10e5) / 10e5
            local samples_per_second = math.floor(entry.n_samples / duration)

            local str = {
                " | Zone `" .. zone_name .. "` (" .. entry.n_samples .. " samples | " .. samples_per_second .. " samples/s)\n",
                " | Ran for " .. duration .. "s on `" .. profiler._start_date .. "`\n",
                " | GC  : " .. gc_percentage .. " % (" .. entry.n_gc_samples .. ")\n",
                " | JIT : " .. jit_percentage .. " % (" .. entry.n_jit_samples .. ")\n",
                --" | Compiled / Interpreted Ratio : " .. interpreted_percentage / 100 .. " (" .. entry.n_compiled_samples  .. " / " .. entry.n_interpreted_samples .. ")\n",
                " |\n",
                table.concat(header, "") .. "\n",
                table.concat(sub_header, "") .. "\n"
            }

            local rows_printed = 0
            for _, name in pairs(names_in_order) do
                if rows_printed < cutoff_n then
                    for col_i = 1, n_columns do
                        local value
                        if col_i == 3 then
                            value = name
                        else
                            value = tostring(columns[col_i][2][name])
                        end
                        value = value .. string.rep(" ", col_lengths[col_i] - #value)
                        table.insert(str, " | " .. value)
                    end
                    table.insert(str, " |\n")
                else
                    local last_row_percentage = "< 0.1"
                    local last_row = {" | "}
                    table.insert(last_row,  last_row_percentage .. string.rep(" ", col_lengths[1] - #last_row_percentage) .. " | ")
                    table.insert(last_row,tostring(cutoff_sample_count) .. string.rep(" ", col_lengths[2] - #tostring(cutoff_sample_count)) .. " | ")
                    table.insert(last_row, "..." .. string.rep(" ", col_lengths[3] - #("...")) .. " |")
                    table.insert(str, table.concat(last_row, ""))
                    break
                end

                rows_printed = rows_printed + 1
            end

            return table.concat(str, "") .. "\n"
        end
        return ""
    end
end -- do-end

return profiler
