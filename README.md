# Clem's Löve Profiler

A profiler is a program that runs in the background of your project, tracking performance data for optimization purposes. Traditional Lua profilers using `debug.sethook` do not work with Löve because it uses LuaJIT, which is not guaranteed to invoke these hooks, and profilers using this method come with great performance overhead. Additionally, the [LuaJIT-provided profiler](https://luajit.org/ext_profiler.html) is incompatible with Löve, as it requires running the profiler executable directly on a lua script, whereas Löve projects use their own executable. 

Clem's Löve Profiler offers the following advantages over other profilers:

+ Requires only one line to install and three lines to include and use in your project
+ Has no performance overhead, ensuring your program runs at its usual speed without skewing data
+ Presents the data in a well-formatted manner

> **NOTE:** This project requires LuaJIT and will not work with regular Lua. 

# Installation

In a git-managed project, run:

```bash
git clone https://github.com/clemapfel/love_profiler
```

Alternatively, download the project manually from [this link](https://github.com/Clemapfel/love_profiler/archive/refs/heads/main.zip), and add it to your project using your operating system's file explorer. Using git is the recommended method to install this library. 

Ensure the `love_profiler` folder is in the root of your game directory. Then, in Lua, add:

```lua
profiler = require "love_profiler.profiler"
```

# Usage

A statistical profiler samples the program at regular intervals rather than noting every function call. These intervals are frequent enough that it's statistically unlikely to miss anything significant, but it's not impossible. To improve accuracy, the profiler should run for at least a few seconds; 5 seconds or more is recommended. If profiling a short piece of code, loop through it often enough to spend at least 5 seconds executing it.

The profiler uses a "zone stack" to track active zones. Use `profiler.push("zone_name")` to add a zone to the stack and `profiler.pop()` to remove the last pushed zone. After sufficient time has passed, use `print(profiler.report())` to get a nicely formatted report.

For example, if your game has been experiencing FPS drops and you want to identify the problematic part of `love.draw`, you can do:

```lua
-- in main.lua
profiler = require "love_profiler.profiler"

love.draw = function()
    profiler.push("draw") -- start "draw" zone
    -- (...) your draw code here
    profiler.pop() -- end "draw" zone
end

love.keypressed = function(which)
    if which == "space" then
        print(profiler.report()) -- print results to console at any time 
    end
end
```

Here, the "draw" zone is opened and closed during each frame, so the profiler only collects data from within this zone. A callback allows you to press the space bar at any time to trigger reporting. 

Let the game run for about 30 seconds; the longer it runs, the more accurate the results. Press space to get the report printed to the console:

```
| Zone `draw` (1754 samples | 466 samples/s) | Ran for 3.764198s on `Fri Oct 4 00:10:11 2024` | GC : 0 % (0) | JIT : 0.17 % (3) |
| Percentage (%) | # Samples | Name |
|----------------|-----------|-----------------------------------------------------------|
| 76.96 | 1350 | xpcall @ [builtin#21] |
| 38.48 | 675 | [love "boot.lua"]:423 @ [love "boot.lua"]:456 |
| 38.48 | 675 | draw @ main.lua:86 |
| 38.48 | 675 | _run @ common/game_state.lua:305 |
| 38.48 | 675 | main.lua:96 @ main.lua:97 |
| 38.48 | 675 | [love "boot.lua"]:434 @ [love "boot.lua"]:447 |
| 37.91 | 665 | _draw @ common/game_state.lua:465 |
| 14.08 | 247 | draw @ menu/inventory_scene.lua:380 |
| 12.48 | 219 | draw @ menu/tab_bar.lua:190 |
| 12.08 | 212 | draw @ common/shape_rectangle.lua:29 |
| 9.97 | 175 | draw @ menu/inventory_scene.lua:382 |
| 8.43 | 148 | draw @ common/label.lua:64 |
| 7.69 | 135 | draw @ common/glyph.lua:272 |
| 7.69 | 135 | _draw_glyph @ common/glyph.lua:237 |
| 6.72 | 118 | draw @ common/vertex_shape.lua:199 |
| 6.49 | 114 | draw @ common/sprite.lua:65 |
| 4.9 | 86 | draw @ menu/inventory_scene.lua:368 |
| 4.61 | 81 | _bind_stencil @ common/frame.lua:65 |
| 4.5 | 79 | draw @ common/frame.lua:83 |
(...)
| 0.11 | 2 | draw @ common/control_indicator.lua:200 |
| 0.11 | 2 | draw @ common/sprite.lua:67 |
| < 0.1 | 16 | ... |
```

The (...) indicates omitted rows for brevity in this `README` only. The actual output may be longer.

Interpreting these results, first look at the header:

```
| Zone `draw` (1754 samples 
| 466 samples/s) 
| Ran for 3.764198s on `Fri Oct 4 00:10:11 2024` 
| GC : 0 % (0) 
| JIT : 0.17 % (3) 
|
```

We are in zone draw, and over the approximately 30 seconds our game ran, 3.76 seconds were spent in this zone. We collected 1754 samples, indicating how many times the profiler collected data. `GC` shows the percentage of samples spent on garbage collection; since we are in draw, a `GC` of 0% is expected. `JIT` shows the time spent on JIT (just-in-time) compilation, which is 0.17%, or 3 out of 1754 samples.

Next, examine the list of function names. The first column shows the percentage of samples collected, the second column is the absolute number of samples, and the last column is the function name, formatted as `<function_name> @ <file_name>:<line_number>`.

```
| Percentage (%) | # Samples | Name |
|----------------|-----------|-----------------------------------------------------------|
| 76.96 | 1350 | xpcall @ [builtin#21] |
| 38.48 | 675 | [love "boot.lua"]:423 @ [love "boot.lua"]:456 |
| 38.48 | 675 | draw @ main.lua:86 |
| 38.48 | 675 | main.lua:96 @ main.lua:97 |
| 38.48 | 675 | [love "boot.lua"]:434 @ [love "boot.lua"]:447 |
| 37.91 | 665 | _draw @ common/game_state.lua:465 |
| 14.08 | 247 | draw @ menu/inventory_scene.lua:380 |
| 12.48 | 219 | draw @ menu/tab_bar.lua:190 |
| 12.08 | 212 | draw @ common/shape_rectangle.lua:29 |
```

Most of the time was spent in `xpcall`, love's `boot.lua`, and `love.draw`. These results are expected, as our zone was inside those functions. In general, the first few lines often don't provide any useful information, as they usually not our functions and we have no control over them. The first interesting lines are:

```
| 37.91 | 665 | _draw @ common/game_state.lua:465 |
| 14.08 | 247 | draw @ menu/inventory_scene.lua:380 |
| 12.48 | 219 | draw @ menu/tab_bar.lua:190 |
| 12.08 | 212 | draw @ common/shape_rectangle.lua:29 |
```

Here, 40% of the draw time was spent in the `_draw` function of our game state. Within those 40%, the `draw` methods of various objects are included. For example, 12% of the overall time was spent on drawing `tab_bar`, which could indicate a performance issue or that `tab_bar` is a particularly common or complex object. These results can guide performance optimization, or you may want to examine less common functions further down the list.

Note that these results do not indicate that `tab_bar:draw` was called 219 times. Instead, during the statistical process of periodically checking which function we are currently in, 219 times, we happened to be in `tab_bar:draw`. This allows us to deduce with reasonable accuracy that about 219 / 1754 = 12.48% of runtime was spent in that function. The more total samples collected, the higher the likelihood of accurate results.

At the bottom of the table, we have:

```
| 0.11 | 2 | draw @ common/control_indicator.lua:200 |
| 0.11 | 2 | draw @ common/sprite.lua:67 |
| < 0.1 | 16 | ... |
```

Any function taking less than 0.1% of collected samples is abbreviated, and the total sum of samples of these functions is printed in the last column. We see that 16 samples were taken up by these negligible functions.

Lastly, eagle-eyed readers may notice that the total sample count and percentage of all the rows do not add up to 1754, or 100%, respectively. This is because function calls are **nested**. For example, if function `A` calls function `B`, which calls function `C`, like this:

```lua
function C()
    -- our sample is here
end

function B() 
    C() 
end

function A() 
    B() 
end

profiler.push()
A()
profiler.pop()
```

Then if the profiler indicates the current sample is in `C`, we know that the sample is also necessarily in `B` and `A`. Thus, `A`, `B`, and `C` will each get a sample, adding to their percentage and sample count. In our example, this is seen with `xpcall`, which calls `boot.lua`, which calls `love.draw`, which then calls our functions. This is why those three functions had the highest percentage, as most functions were nested calls of them.

# Credits

This library was written and designed by [Clem Cords](clemens-cords.com). Consider donating via GitHub Sponsor to reward past work and help with the continued development of this and other Löve-related projects. If you need assistance or want to hire me for freelance work (on your game or other projects), feel free to reach out via email or Discord, username `clemapfel`. Thank you for your consideration.

# License

This library is licensed under the MIT License, meaning it is available for free without restrictions in both commercial and non-commercial projects.