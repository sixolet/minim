-- minim


music = require 'musicutil'
er = require 'er'
lattice = require 'lattice'

engine.name="FormAndVoid"

g = grid.connect()


DIVISIONS =    {'sixteenth', 'eigth triplet', 'eighth', 'triplet', 'quarter', 'half', 'whole', 'two whole', 'four whole'}
DIVISION_VAL = {1/16,        1/12,            1/8,      1/6,       1/4,       1/2,    1,        2,           4}
SCALE_NAMES = {}
for i, v in pairs(music.SCALES) do
  SCALE_NAMES[i] = v["name"]
end

function format_chord_option(i, n)
    local scale = music.generate_scale_of_length(params:get("root"), SCALE_NAMES[params:get("scale")], 7)
    local chords = music.chord_types_for_note(scale[i], params:get("root"), SCALE_NAMES[params:get("scale")])
    return chords[util.wrap(n, 1, #chords)]
end

function set_up_triggers(name, magic_number, default_division, default_chord, default_arp)
    local triggers = {}
    -- This is nasty. The three lattice patterns involved here have to interleave with the other triggers in a particular order
    -- First advance, then reset, then play. Luckily lattice evaluates patterns in id order, and ids start at 100.
    -- So we hack it.
    local stored_counter = L.pattern_id_counter
    L.pattern_id_counter = 10 + magic_number
    triggers.advance = L:new_pattern{
        action = function (t)
            if params:get(name .. " advance chord") == 1 then
                chord_section:advance()
            end
            if params:get(name .. " advance arp") == 1 then
                arp_section:advance()
            end               
        end,
    }
    L.pattern_id_counter = 20 + magic_number
    triggers.reset = L:new_pattern{
        action = function (t)
            if params:get(name .. " reset chord") == 1 then
                chord_section:reset()
            end
            if params:get(name .. " reset arp") == 1 then
                arp_section:reset()
            end               
        end,
    }
    L.pattern_id_counter = 30 + magic_number
    triggers.play = L:new_pattern{
        action = function (t)
            if params:get(name .. " play chord") == 1 then
            end
            if params:get(name .. " play arp") == 1 then
                arp_section:play(0.5)
            end            
        end,
    }
    L.pattern_id_counter = stored_counter
    
    params:add_group(name, 8)
    params:add_option(name .. " division", "division", DIVISIONS, default_division)
    params:set_action(name .. " division", function (d)
        local division = DIVISION_VAL[d]
        local exp = 0
        if division > 1 then exp = 1 end
        division = division*((params:get("meter")/4)^exp)
        triggers.advance:set_division(division)
        triggers.reset:set_division(division)
        triggers.play:set_division(division)
    end)    
    params:add_control(name .. " swing", "swing", controlspec.new(40, 90, 'lin', 0, 50))
    params:set_action(name .. " swing", function (s)
        triggers.advance:set_swing(s)
        triggers.reset:set_swing(s)
        triggers.play:set_swing(s)
    end)
    params:add_binary(name .. " advance chord", "advance chord", "toggle", default_chord)
    params:add_binary(name .. " play chord", "play chord", "toggle", default_chord)
    params:add_binary(name .. " reset chord", "reset chord", "toggle", 0)
    params:add_binary(name .. " advance arp", "advance arp", "toggle", default_arp)
    params:add_binary(name .. " play arp", "play arp", "toggle", default_arp)
    params:add_binary(name .. " reset arp", "reset arp", "toggle", default_chord)
    return triggers
end

function set_up_section(sect, play_step, default_chord)
    params:add_separator(sect)
    params:add_number(sect .. " loop pos", sect .. " loop pos", 1, 8, 1)
    params:add_number(sect .. " loop len", sect .. " loop len", 1, 8, 8)
    params:add_number(sect .. " pos", sect .. " pos", 1, 8, 1)
    params:hide(sect .. " pos")
    params:add_group(sect .. " sequence", 8)
    for i=1,8,1 do
        params:add_number(sect .. " step ".. i, sect .. " step ".. i, 1, 7, 1)
        params:add_option(sect .. " vel ".. i, sect .. " vel ".. i, {"mute", "note", "accent"}, 2)
    end
    params:add_group(sect .. " chords", 7)
    for i=1,7,1 do
        local f = function (i)
            return function(n) return format_chord_option(i, n:get()) end
        end 
        params:add_number(sect .. " chord " .. i, sect .. " chord " .. i, 1, 12, default_chord, f(i))
    end
    params:bang()
    local section = {}
    section.loop_key = nil
    function section:advance()
        if self.ignore_advance then return end
        local p = params:get(sect .. " pos")
        local loop_start = params:get(sect .. " loop pos")
        local loop_end = params:get(sect .. " loop len") + loop_start - 1
        if loop_end > 8 then loop_end = 8 end
        if self:in_loop(p) then
            p = util.wrap(p+1, loop_start, loop_end)
        else
            p = util.wrap(p+1, 1, 8)
        end
        params:set(sect .. " pos", p)
        grid_dirty = true        
    end
    function section:reset()
        params:set(sect .. " pos", 1)
        -- ignore any advance within a few ms
        self.ignore_advance = true
        clock.run(function()
            clock.sleep(0.005)
            self.ignore_advance = nil
        end)
    end
    function section:chord(num_notes)
        -- Always get the chord from the chord section
        local i = chord_section:step(chord_section:pos())
        -- But the chord type from this section
        if i == 0 then return nil end
        local n = params:get(sect .. " chord " .. i)
        local chord_type = format_chord_option(i, n)
        local scale = music.generate_scale_of_length(params:get("root"), SCALE_NAMES[params:get("scale")], 7)
        local chord = music.generate_chord(scale[i], chord_type)
        while #chord > num_notes do
            table.remove(chord, 2)
        end
        local i = 1
        while #chord < num_notes do
            table.insert(chord, chord[i] + 12)
            i = i + 1
        end
        return chord
    end
    function section:handle_loop_key(y, z)
        if self.loop_key == nil and z == 1 then
            self.loop_key = y
            print("key", y)
        elseif self.loop_key == y and z == 0 then
            params:set(sect .. " loop pos", y)
            params:set(sect .. " loop len", 1)
            self.loop_key = nil
        elseif z == 1 then
            local pos = math.min(self.loop_key, y)
            local l = math.abs(self.loop_key - y) + 1
            params:set(sect .. " loop pos", pos)
            params:set(sect .. " loop len", l)
            print("pos", pos, "len", l)
            self.loop_key = nil
        end
    end
    function section:stop()
        if section.routine ~= nil then
            clock.cancel(section.routine)
            self.routine = nil
        end
    end
    function section:step(i)
        return params:get(sect .. " step "..i)
    end
    function section:pos()
        return params:get(sect .. " pos")
    end
    function section:in_loop(i)
        local loop_start = params:get(sect .. " loop pos")
        local loop_end = params:get(sect .. " loop len") + loop_start - 1
        if loop_end > 8 then loop_end = 8 end
        return i >= loop_start and i <= loop_end
    end
    return section
end

function grid_redraw()
    g:all(0)
    -- Chord section
    for i=1,7,1 do
        g:led(i, chord_section:pos(), 4)
    end
    for i=1,8,1 do
        local s = chord_section:step(i)
        local brightness = params:get("chord vel "..i)*3
        if arp_section:pos() == i then
            brightness = brightness + 5
        end        
        if s > 0 then
            g:led(s, i, brightness)
        end
    end
    for i=1,8,1 do
        if chord_section:in_loop(i) then
            g:led(8, i, 8)
        else
            g:led(8, i, 4)
        end
    end
    -- Arp section
    for i=10,16,1 do
        g:led(i, arp_section:pos(), 4)
    end
    for i=1,8,1 do
        local s = arp_section:step(i)
        local brightness = params:get("arp vel "..i)*3
        if arp_section:pos() == i then
            brightness = brightness + 5
        end
        if s > 0 then
            g:led(s+9, i, brightness)
        end
    end
    for i=1,8,1 do
        if arp_section:in_loop(i) then
            g:led(9, i, 8)
        else
            g:led(9, i, 4)
        end
    end    
end


function g.key(x, y, z)
    if x < 8 and z == 1 then
        -- chord step
        if x == chord_section:step(y) then
            params:set("chord vel "..y, util.wrap(params:get("chord vel "..y) + 1, 1, 3))
        else
            params:set("chord step ".. y, x)
        end
        grid_dirty = true
    elseif x == 8 then
        -- chord loop
        chord_section:handle_loop_key(y, z)
    elseif x == 9 then
        -- arp loop
        arp_section:handle_loop_key(y, z)
    elseif x > 9 and z == 1 then
        -- arp step
        if x - 9 == arp_section:step(y) then
            params:set("arp vel "..y, util.wrap(params:get("arp vel "..y) + 1, 1, 3))
        else
            params:set("arp step ".. y, x - 9)
        end
        grid_dirty = true
    end
end

function grid_clock()
  while true do -- while it's running...
    clock.sleep(1/30) -- refresh at 30fps.
    if grid_dirty then -- if a redraw is needed...
      grid_redraw() -- redraw...
      grid_dirty = false -- then redraw is no longer needed.
    end
    -- grid_mini_redraw()
    g:refresh()
  end
end

function init()
    L = lattice:new{
        ppqn = 24,
    }
    params:add_number("meter", "meter", 2, 12, 4)
        params:set_action("meter", function (m)
        L:set_meter(m)
    end)
    params:add_option("scale", "scale", SCALE_NAMES, 1)
    params:add_number("root", "root", 36, 60, 48, function(n) return music.note_num_to_name(n:get(), true) end)
    
    chord_section = set_up_section("chord", nil, 1)
    arp_section = set_up_section("arp", nil, 2)
    function arp_section:play(duration)
        local idx = self:step(self:pos())
        if idx == 0 then return end
        local chord = self:chord(7)
        local note = chord[idx]
        engine.play(1, music.note_num_to_freq(note), 0.5, duration)
    end
    params:add_separator("rhythm")
    r1 = set_up_triggers("rhythm 1", 1, 7, 1, 0)
    r2 = set_up_triggers("rhythm 2", 2, 3, 0, 1)    
    r3 = set_up_triggers("rhythm 3", 3, 4, 0, 0)
    params:bang()
    L:start()
    clock.run(grid_clock)
end

function cleanup()
    L:destroy()
end
