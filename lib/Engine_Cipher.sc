// lib/Engine_Cipher.sc
// cipher: 4-node feedback network + morse impulse generator
// routing matrix determines topology
// vanilla UGens only - no sc3-plugins

Engine_Cipher : CroneEngine {
  var synth;
  var nodeBuses;
  var ampBus;

  *new { |context, doneCallback| ^super.new(context, doneCallback) }

  alloc {
    var s;
    s = context.server;

    nodeBuses = Array.fill(4, { Bus.audio(s, 1) });
    ampBus = Bus.control(s, 4);

    // -- morse impulse: short tone injected into a node bus --
    SynthDef(\cipher_imp, {
      arg out_bus, freq=440, dur=0.05, amp=0.8, type=0;
      var sig, env;
      env = EnvGen.ar(Env.linen(0.002, dur, dur * 0.5, 1, -4),
        doneAction: Done.freeSelf);
      sig = Select.ar(type, [
        SinOsc.ar(freq),
        LFPulse.ar(freq, 0, 0.5) * 2 - 1,
        BPF.ar(WhiteNoise.ar, freq, 0.3) * 3,
        Impulse.ar(freq * 8) * 0.5
      ]);
      sig = sig * env * amp;
      Out.ar(out_bus, sig);
    }).add;

    // -- main feedback network --
    SynthDef(\cipher_net, {
      arg out_bus, ext_in_bus,
          in_bus_0, in_bus_1, in_bus_2, in_bus_3,
          // node filter cutoff
          filt_0=2000, filt_1=3000, filt_2=1200, filt_3=600,
          // node filter resonance (0.05 - 1.0)
          res_0=0.4, res_1=0.5, res_2=0.6, res_3=0.3,
          // node filter type (0=LP, 1=BP, 2=HP)
          ftype_0=0, ftype_1=1, ftype_2=0, ftype_3=2,
          // node delay time
          dly_0=0.12, dly_1=0.19, dly_2=0.25, dly_3=0.37,
          // node delay feedback
          dfb_0=0.4, dfb_1=0.3, dfb_2=0.5, dfb_3=0.2,
          // node saturation drive
          drv_0=1.0, drv_1=1.2, drv_2=0.8, drv_3=1.5,
          // node level
          lvl_0=0.5, lvl_1=0.5, lvl_2=0.5, lvl_3=0.5,
          // node pan (-1 to 1)
          pan_0=(-0.6), pan_1=0.6, pan_2=(-0.2), pan_3=0.2,
          // routing matrix (r_IJ = from node I to node J input)
          r_00=0, r_01=0, r_02=0, r_03=0,
          r_10=0, r_11=0, r_12=0, r_13=0,
          r_20=0, r_21=0, r_22=0, r_23=0,
          r_30=0, r_31=0, r_32=0, r_33=0,
          // external input
          ext_lvl=0,
          // master
          amp=0.5,
          // poll bus
          amp_bus;

      // -- all var declarations at top --
      var fb;
      var inp_0, inp_1, inp_2, inp_3;
      var mix_0, mix_1, mix_2, mix_3;
      var f_0, f_1, f_2, f_3;
      var d_0, d_1, d_2, d_3;
      var out_0, out_1, out_2, out_3;
      var ext_in, sig_out;
      var n_amps;

      // previous frame feedback
      fb = LocalIn.ar(4);

      // morse impulse inputs from buses
      inp_0 = InFeedback.ar(in_bus_0);
      inp_1 = InFeedback.ar(in_bus_1);
      inp_2 = InFeedback.ar(in_bus_2);
      inp_3 = InFeedback.ar(in_bus_3);

      // external audio
      ext_in = SoundIn.ar(0) * ext_lvl;

      // -- mix: impulse + matrix feedback + ext --
      mix_0 = inp_0 + (fb[0]*r_00) + (fb[1]*r_10) + (fb[2]*r_20) + (fb[3]*r_30) + ext_in;
      mix_1 = inp_1 + (fb[0]*r_01) + (fb[1]*r_11) + (fb[2]*r_21) + (fb[3]*r_31) + ext_in;
      mix_2 = inp_2 + (fb[0]*r_02) + (fb[1]*r_12) + (fb[2]*r_22) + (fb[3]*r_32) + ext_in;
      mix_3 = inp_3 + (fb[0]*r_03) + (fb[1]*r_13) + (fb[2]*r_23) + (fb[3]*r_33) + ext_in;

      // -- node 0: filter -> delay -> clip --
      f_0 = Select.ar(ftype_0, [
        RLPF.ar(mix_0, filt_0.clip(20,20000), res_0.clip(0.05,1)),
        BPF.ar(mix_0, filt_0.clip(20,20000), res_0.clip(0.05,1)),
        RHPF.ar(mix_0, filt_0.clip(20,20000), res_0.clip(0.05,1))
      ]);
      d_0 = CombC.ar(f_0, 2.0, dly_0.clip(0.001,2.0), dfb_0 * 5);
      out_0 = (d_0 * drv_0).tanh * lvl_0;

      // -- node 1 --
      f_1 = Select.ar(ftype_1, [
        RLPF.ar(mix_1, filt_1.clip(20,20000), res_1.clip(0.05,1)),
        BPF.ar(mix_1, filt_1.clip(20,20000), res_1.clip(0.05,1)),
        RHPF.ar(mix_1, filt_1.clip(20,20000), res_1.clip(0.05,1))
      ]);
      d_1 = CombC.ar(f_1, 2.0, dly_1.clip(0.001,2.0), dfb_1 * 5);
      out_1 = (d_1 * drv_1).tanh * lvl_1;

      // -- node 2 --
      f_2 = Select.ar(ftype_2, [
        RLPF.ar(mix_2, filt_2.clip(20,20000), res_2.clip(0.05,1)),
        BPF.ar(mix_2, filt_2.clip(20,20000), res_2.clip(0.05,1)),
        RHPF.ar(mix_2, filt_2.clip(20,20000), res_2.clip(0.05,1))
      ]);
      d_2 = CombC.ar(f_2, 2.0, dly_2.clip(0.001,2.0), dfb_2 * 5);
      out_2 = (d_2 * drv_2).tanh * lvl_2;

      // -- node 3 --
      f_3 = Select.ar(ftype_3, [
        RLPF.ar(mix_3, filt_3.clip(20,20000), res_3.clip(0.05,1)),
        BPF.ar(mix_3, filt_3.clip(20,20000), res_3.clip(0.05,1)),
        RHPF.ar(mix_3, filt_3.clip(20,20000), res_3.clip(0.05,1))
      ]);
      d_3 = CombC.ar(f_3, 2.0, dly_3.clip(0.001,2.0), dfb_3 * 5);
      out_3 = (d_3 * drv_3).tanh * lvl_3;

      // -- feedback --
      LocalOut.ar([out_0, out_1, out_2, out_3]);

      // -- stereo mix --
      sig_out = Pan2.ar(out_0, pan_0) + Pan2.ar(out_1, pan_1)
              + Pan2.ar(out_2, pan_2) + Pan2.ar(out_3, pan_3);
      sig_out = Limiter.ar(sig_out * amp, 0.95);
      Out.ar(out_bus, sig_out);

      // -- amplitude polls --
      n_amps = [
        Amplitude.ar(out_0, 0.01, 0.1),
        Amplitude.ar(out_1, 0.01, 0.1),
        Amplitude.ar(out_2, 0.01, 0.1),
        Amplitude.ar(out_3, 0.01, 0.1)
      ];
      Out.kr(amp_bus, n_amps);
    }).add;

    context.server.sync;

    synth = Synth(\cipher_net, [
      \out_bus, context.out_b.index,
      \ext_in_bus, context.in_b.index,
      \in_bus_0, nodeBuses[0].index,
      \in_bus_1, nodeBuses[1].index,
      \in_bus_2, nodeBuses[2].index,
      \in_bus_3, nodeBuses[3].index,
      \amp_bus, ampBus.index
    ], context.xg);

    // -- commands --

    // trig: inject morse impulse into node
    // args: node(int 0-3), freq(float), dur(float), amp(float), type(int 0-3)
    this.addCommand("trig", "ifffi", { arg msg;
      var node, freq, dur, a, tp;
      node = msg[1].asInteger.clip(0, 3);
      freq = msg[2].asFloat;
      dur  = msg[3].asFloat;
      a    = msg[4].asFloat;
      tp   = msg[5].asInteger.clip(0, 3);
      Synth(\cipher_imp, [
        \out_bus, nodeBuses[node].index,
        \freq, freq, \dur, dur, \amp, a, \type, tp
      ], context.xg);
    });

    // set network params
    this.addCommand("node_filt", "if", { arg msg;
      synth.set(("filt_" ++ msg[1].asInteger).asSymbol, msg[2].asFloat);
    });
    this.addCommand("node_res", "if", { arg msg;
      synth.set(("res_" ++ msg[1].asInteger).asSymbol, msg[2].asFloat);
    });
    this.addCommand("node_ftype", "ii", { arg msg;
      synth.set(("ftype_" ++ msg[1].asInteger).asSymbol, msg[2].asInteger);
    });
    this.addCommand("node_dly", "if", { arg msg;
      synth.set(("dly_" ++ msg[1].asInteger).asSymbol, msg[2].asFloat);
    });
    this.addCommand("node_dfb", "if", { arg msg;
      synth.set(("dfb_" ++ msg[1].asInteger).asSymbol, msg[2].asFloat);
    });
    this.addCommand("node_drv", "if", { arg msg;
      synth.set(("drv_" ++ msg[1].asInteger).asSymbol, msg[2].asFloat);
    });
    this.addCommand("node_lvl", "if", { arg msg;
      synth.set(("lvl_" ++ msg[1].asInteger).asSymbol, msg[2].asFloat);
    });
    this.addCommand("node_pan", "if", { arg msg;
      synth.set(("pan_" ++ msg[1].asInteger).asSymbol, msg[2].asFloat);
    });
    // routing matrix: row, col, value
    this.addCommand("route", "iif", { arg msg;
      var key;
      key = ("r_" ++ msg[1].asInteger ++ msg[2].asInteger).asSymbol;
      synth.set(key, msg[3].asFloat.clip(0, 0.95));
    });
    this.addCommand("ext_lvl", "f", { arg msg;
      synth.set(\ext_lvl, msg[1].asFloat);
    });
    this.addCommand("amp", "f", { arg msg;
      synth.set(\amp, msg[1].asFloat);
    });

    // -- polls --
    this.addPoll("node_amps", {
      var vals;
      vals = ampBus.getnSynchronous(4);
      vals[0].asString ++ "," ++ vals[1].asString ++ ","
      ++ vals[2].asString ++ "," ++ vals[3].asString;
    });
  }

  free {
    synth.free;
    nodeBuses.do({ |b| b.free });
    ampBus.free;
  }
}
