music = require 'musicutil'

include 'lib/notes'

engine.name="FormAndVoid"

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
    -- global
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
      if params:get("pressure") > 0 then
        for note, freq in pairs(active_notes[d.ch]) do
            engine.setNote(timbre, note, "amp", d.val/127)
        end
      end
  elseif d.type == "channel_pressure" then
      if params:get("pressure") > 0 then
          engine.set(timbre, "amp", d.val/127)
      end
  elseif d.type == "cc" then
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
  else
      print(d.type)
  end
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
    params:add_number("mpe channels", "mpe channels", 1, 8, 6, nil, nil, false)
    params:add_number("bend range", "bend range", 1, 24, 12, nil, nil, false)
    params:add_binary("pressure", "pressure", "toggle", 1)
    set_up_chord_timbre(-1, "timbre")
    params:read(1)
    params:bang()
end