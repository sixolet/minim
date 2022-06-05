Engine_FormAndVoid : CroneEngine {
    var <timbres, <bus, <eoc, <lfoGroup, <lfos, <lfoBusses, <noteGroup;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}
	
	alloc {
	    bus = Bus.audio(Server.default, 2);
	    lfoGroup = Group.new;
	    noteGroup = Group.after(lfoGroup);
	    lfoBusses = 4.collect {Bus.control(Server.default, 1)};
	    lfos = 4.collect { |i|
	        { |lfoFreq|
	            Out.kr(lfoBusses[i], SinOsc.kr(lfoFreq));
	        }.play(target: lfoGroup);
	    };
	    timbres = 4.collect { |i|
	      ( instrument: \form, freq: 440, amp: 1, pan: 0, out: bus, group: noteGroup,
	        a1: 0.1, d1: 0.3, s1: 0.5, r1: 0.4,
	        a2: 0.3, d2: 0.5, s2: 0.8, r2: 0.4,
	        f0Amp: 0.5,
	        lfoBus: lfoBusses[i],
	        f1: 450, f1Amp: 0.5, f1Res: 0.6, 
	        f2: 1000, f2Amp: 0.0, f2Res: 0.1,
	        e1F0Amp: 0, e1F1: 0.5, e1F1Amp: 0, e1F2: 0, e1F2Amp: 0.5,
	        e2F0Amp: 0, e2F1: 0.3, e2F1Amp: 0, e2F2: 1, e2F2Amp: 0,
	        lfoF0Amp: 0, lfoF1:  -0.2, lfoF1Amp: 0, lfoF2: 0, lfoF2Amp: 0)
	    };
	    
        SynthDef(\form, { |out, freq=440, amp=1, gate=1, pan=0,
	        a1=0.1, d1=0.3, s1=0.5, r1=0.4,
	        a2=0.3, d2=0.5, s2=0.8, r2=0.4,
        	lfoBus,	
	        f0Amp=0.5, 
	        f1=450, f1Amp=0.5, f1Res=0.6, 
	        f2=1000, f2Amp=0.0, f2Res=0.1,
	        e1F0Amp=0, e1F1= 0.5, e1F1Amp=0, e1F2=0, e1F2Amp=0.5,
	        e2F0Amp=0, e2F1=0.3, e2F1Amp=0, e2F2=1, e2F2Amp=0,
	        lfoF0Amp=0, lfoF1= -0.2, lfoF1Amp=0, lfoF2=0, lfoF2Amp=0|
	
        	var env1 = EnvGen.kr(Env.adsr(a1, d1, s1, r1), gate, doneAction: Done.freeSelf);
	        var env2 = EnvGen.kr(Env.adsr(a2, d2, s2, r2), gate, doneAction: Done.none);
	        var lfo = In.kr(lfoBus);
	
	        var f0AmpMod = f0Amp + (e1F0Amp*env1) + (e2F0Amp*env2) + (lfoF0Amp*lfo);

	        var f1AmpMod = f1Amp + (e1F1Amp*env1) + (e2F1Amp*env2) + (lfoF1Amp*lfo);
	        var f1Mod = f1 + (f1*e1F1*env1) + (f1*e2F1*env2) + (f1*lfoF1*lfo);

	        var f2AmpMod = f2Amp + (e1F2Amp*env1) + (e2F2Amp*env2) + (lfoF2Amp*lfo);
	        var f2Mod = f2 + (f2*e1F2*env1) + (f2*e2F2*env2) + (f2*lfoF2*lfo);

	        var fundamental = f0AmpMod*SinOsc.ar(freq);
	        var imp = Impulse.ar(freq);
	        var formant1 = f1AmpMod*SinGrain.ar(imp, f1Res*freq.reciprocal, f1Mod);
	        var formant2 = f2AmpMod*SinGrain.ar(imp, f2Res*freq.reciprocal, f2Mod);
	        var snd = (fundamental+formant1+formant2);
	        Out.ar(out, Pan2.ar(0.3*amp*env1*snd, pan));
        }).add;
        
        this.addCommand(\play, "ifff", { |msg|
            var timbre = msg[1].asInteger;
            var freq = msg[2].asFloat;
            var amp = msg[3].asFloat;
            var dur = msg[4].asFloat;
            var proto = timbres[timbre];
            var event = Event.new(proto: proto);
            event.freq = freq;
            event.amp = amp;
            event.duration = dur;
            event.postln;
            event.play;
        });
		this.addCommand("tempo_sync", "ff", { arg msg;
			var beats = msg[1].asFloat;
			var tempo = msg[2].asFloat;
			var beatDifference = beats - TempoClock.default.beats;
			var nudge = beatDifference % 4;
			if (nudge > 2, {nudge = nudge - 4});
			if ( (tempo != TempoClock.default.tempo) || (nudge.abs > 1), {
				TempoClock.default.beats = TempoClock.default.beats + nudge;
				TempoClock.default.tempo = tempo;
			}, {
				TempoClock.default.beats = TempoClock.default.beats + (0.05 * nudge);
			});
			// Set M to be the duration of a beat.
			// beatDurBus.set(1/tempo);
		});        
        
        this.addCommand(\set, "isf", { |msg|
            var timbre = msg[1].asInteger;
            var key = msg[2].asString.asSymbol;
            var val = msg[3].asFloat;
            if (key == \lfoFreq, {
                lfos[timbre].set(key, val);
            }, {
                timbres[timbre][key] = val;
            });
        });
        
        eoc = {
            var snd = In.ar(bus, 2);
            snd = 0.5*snd;
            snd.tanh;
        }.play(addAction: \addAfter, target: noteGroup);
    }
    
    free {
        lfoGroup.free;
        noteGroup.free;
        eoc.free;
        bus.free;
        lfoBusses.do { |b| b.free }
    }
	
}