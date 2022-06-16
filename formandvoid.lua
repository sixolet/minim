music = require 'musicutil'

include 'lib/notes'

engine.name="FormAndVoid"

PRESSURE_OPTIONS = {"none", "amp", "cc 1", "cc 1 + amp"}

active_notes = {}
for i=1,16,1 do
    active_notes[i] = {}
end


function midi_target(x)
  midi_device[target].event = nil
  target = x
  midi_device[target].event = process_midi
end

-- To do MPE:
-- * Keep track of which channels are MPE
-- * When we recieve a CC on an MPE channel, we look in the bindings for the main channel
-- * We see if that parameter has a set_mpe method, and call it for the appropriate voice.

count = 0
function process_midi(data)
  local d = midi.to_msg(data)
  local timbre = d.ch - params:get("first channel")
  if d.ch == params:get("main channel") then
      timbre = 0
  end
  if timbre < 0 or timbre > (params:get("mpe channels") - 1) then
      return
  end
  if d.type == "note_on" then
    -- This is a guard against stuck notes. If we see more than one note on the same
    -- channel and it isn't the main channel, and other channels are empty, it must be stuck.
    
    -- This is because MPE says to use an empty channel for new notes if such exists.
    
    if next(active_notes[d.ch]) ~= nil and d.ch ~= params:get("main channel") then
        local first = params:get("first channel")
        for i=first,first+params:get("mpe channels")-1,1 do
            if i ~= d.ch and next(active_notes[i]) == nil then
                for note, freq in pairs(active_notes[d.ch]) do
                    engine.noteOff(timbre, note)
                    count = count - 1
                    print("stuck off", timbre, note)
                end
                break
            end
        end
    end
    
    active_notes[d.ch][d.note] = music.note_num_to_freq(d.note)
    engine.noteOn(timbre, d.note, music.note_num_to_freq(d.note), d.vel/127)
    count = count + 1
    print("on", timbre, d.note, count)
  elseif d.type == "note_off" then
    active_notes[d.ch][d.note] = nil
    engine.noteOff(timbre, d.note)
    count = count - 1
    print("off", timbre, d.note, count)
  elseif d.type == "pitchbend" then
    local bend_st = (util.round(d.val / 2)) / 8192 * 2 -1 -- Convert to -1 to 1
    for note, freq in pairs(active_notes[d.ch]) do
        local new_freq = music.note_num_to_freq(note + bend_st*params:get("bend range"))
        engine.setNote(timbre, note, "freq", new_freq)
    end
  elseif d.type == "key_pressure" then
      if params:get("pressure") == 2 or params:get("pressure") == 4 then
        for note, freq in pairs(active_notes[d.ch]) do
            engine.setNote(timbre, note, "amp", d.val/127)
        end
      end
      if params:get("pressure") == 4 or params:get("pressure") == 3 then
          d.cc = 1
      end
  elseif d.type == "channel_pressure" then
      if params:get("pressure") == 2 or params:get("pressure") == 3 then
          engine.set(timbre, "amp", d.val/127)
      end
      if params:get("pressure") == 4 or params:get("pressure") == 3 then
          d.cc = 1
      end      
  elseif d.type == "cc" then
      -- pass handled next
  else
      print(d.type)      
  end
  if d.type == "cc" or d.cc == 1 then
      local r = norns.pmap.rev[target][params:get("main channel")][d.cc]
      local v = d.val
      if r ~= nil and d.ch ~= params:get("main channel") then
        -- This code is borrowed and adapted from the parameter mapping code itself.
        local dd = norns.pmap.data[r]
        local t = params:t(r)
        local s = util.clamp(v, dd.in_lo, dd.in_hi)
        s = util.linlin(dd.in_lo, dd.in_hi, dd.out_lo, dd.out_hi, s)     
        local p = params:lookup_param(r)
        -- print("it is mapped for channel", params:get("main channel"))
        -- tab.print(p)
        if p ~= nil and p.set_mpe ~= nil then
            if t == params.tCONTROL or t == params.tTAPER then
                s = p:map_value(s)
                p:set_mpe(timbre, s)
            elseif t == params.tNUMBER or t == params.tOPTION then
                s = util.round(s)
                p:set_mpe(timbre, s)
            end
        end
      end
  end
end

function shape()
    local f1 = params:get("the formant 1")
    local f1_mod = params:get("the formant 1 modulator")
    local f1_index = params:get("the formant 1 index")
    local f2 = params:get("the formant 2")
    local len1 = params:get("the formant 1 waves")/f1
    local len2 = params:get("the formant 2 waves")/f2
    local window_len = math.max(len1, len2)
    local amp1 = (
        params:get("the formant 1 amp") + 
        params:get("the sustain 1")*params:get("the env 1 to formant 1 amp") + 
        params:get("the sustain 2")*params:get("the env 2 to formant 1 amp"))
    local amp2 = params:get("the formant 2 gain")*(
        params:get("the formant 2 amp") + 
        params:get("the sustain 1")*params:get("the env 1 to formant 2 amp") + 
        params:get("the sustain 2")*params:get("the env 2 to formant 2 amp"))
    local one = function(t)
        if t >= 0 and t <= len1 then
            local modulator = math.sin(2*math.pi*f1_mod*t)
            local window = (math.sin(math.pi*t/len1))^2
            return window*math.sin(2*math.pi*f1*t + 2*math.pi*f1_index*modulator)
        else
            return 0
        end
    end
    local two = function(t)
        if t >= 0 and t <= len2 then
            local window = (math.sin(math.pi*t/len2))^2
            return window*math.sin(2*math.pi*f2*t)
        else
            return 0
        end
    end
    local ret = {}
    local highest = -1000
    local lowest = 1000
    for i=0,128,1 do
        local t = window_len*(i-1)/128
        ret[i] = amp1*one(t) + amp2*two(t)
        if ret[i] > highest then highest = ret[i] end
        if ret[i] < lowest then lowest = ret[i] end
    end
    for i=0,128,1 do
        ret[i] = util.linlin(lowest, highest, 1, 63, ret[i])
    end
    ret.window_len = window_len
    return ret
end

function redraw()
    screen.clear()
    local s = shape()
    screen.aa(1)
    screen.level(16)
    screen.move(0,s[0])
    for j=1,128,1 do
        screen.line(j, s[j])
    end
    screen.stroke()
    screen.move(105, 10)
    screen.text(util.round(s.window_len*1000).. " ms")
    screen.update()
end

k1 = 0
k2 = 0
k3 = 0

function key(n,z)
    if n == 1 then
        k1 = z
    elseif n == 2 then
        k2 = z
    elseif n == 3 then
        k3 = z
    end
end

function enc(n,d)
    local f = n - 1
    if k2 == 0 and k3 == 0 then
        local name = "the formant "..f
        local formant = params:get(name)
        formant = formant*(1 + 0.01*d)
        params:set(name, formant)
    elseif k2 == 1 and k3 == 0 then
        local name = "the formant "..f.." amp"
        local amp = params:get(name)
        params:set(name, amp + d/100)
    elseif k2 == 0 and k3 == 1 then
        local name = "the formant "..f.." waves"
        local waves = params:get(name)
        params:set(name, waves + d/10)
    end
    screen_dirty = true  
end

function init()
    midi_device = {} -- container for connected midi devices
    midi_device_names = {}
    target = 1

    for i = 1,#midi.vports do -- query all ports
        midi_device[i] = midi.connect(i) -- connect each device
        local full_name = 
        table.insert(midi_device_names,"port "..i..": "..util.trim_string_to_width(midi_device[i].name,40)) -- register its name
    end
  
    params:add_option("midi target", "midi target",midi_device_names,1,false)
    params:set_action("midi target", midi_target)  
    params:add_number("main channel", "main channel", 1, 15, 1, nil, nil, false)
    params:add_number("first channel", "first channel", 1, 15, 2, nil, nil, false)
    params:add_number("mpe channels", "mpe channels", 1, 8, 7, nil, nil, false)
    params:add_number("bend range", "bend range", 1, 24, 12, nil, nil, false)
    params:add_option("pressure", "pressure", PRESSURE_OPTIONS, 2)
    set_up_chord_timbre(-1, "the")
    params:read(1)
    params:bang()
    screen_redraw_clock = clock.run(
    function()
      while true do
        clock.sleep(1/10) 
        if screen_dirty == true then
          redraw()
          screen_dirty = false
        end
      end
    end
    )
    screen_dirty = true
end