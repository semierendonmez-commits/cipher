// lib/Engine_Cipher.sc
// cipher: 4-node feedback network + morse impulse generator
// routing matrix via NamedControl (avoids arg count limit)
// vanilla UGens only - no sc3-plugins

Engine_Cipher : CroneEngine {
  var synth;
  var nodeBuses;
  var ampBus;
  var routeBus;

  *new { |context, doneCallback| ^super.new(context, doneCallback) }

  alloc {
    var s, out_bus, in_bus;
    s = context.server;

    // norns bus access: type varies between norns versions
    // out_b = single 2ch Bus, in_b = Array of 2 mono Buses (or vice versa)
    out_bus = if(context.out_b.isKindOf(Array),
      { context.out_b[0].index }, { context.out_b.index });
    in_bus = if(context.in_b.isKindOf(Array),
      { context.in_b[0].index }, { context.in_b.index });

    nodeBuses = Array.fill(4, { Bus.audio(s, 1) });
    ampBus = Bus.control(s, 4);
    routeBus = Bus.control(s, 16);

    // init route bus to zeros
    routeBus.setn(Array.fill(16, { 0 }));

    // -- morse impulse --
    SynthDef(\cipher_imp, {
      arg imp_bus, freq=440, dur=0.05, amp=0.8, type=0;
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
      Out.ar(imp_bus, sig);
    }).add;

    // -- main feedback network --
    SynthDef(\cipher_net, {
      arg net_out, ext_in,
          nb0, nb1, nb2, nb3,
          filt0=2000, filt1=3000, filt2=1200, filt3=600,
          res0=0.4, res1=0.5, res2=0.6, res3=0.3,
          ft0=0, ft1=1, ft2=0, ft3=2,
          dt0=0.12, dt1=0.19, dt2=0.25, dt3=0.37,
          fb0=0.4, fb1=0.3, fb2=0.5, fb3=0.2,
          dv0=1.0, dv1=1.2, dv2=0.8, dv3=1.5,
          lv0=0.5, lv1=0.5, lv2=0.5, lv3=0.5,
          pn0=(-0.6), pn1=0.6, pn2=(-0.2), pn3=0.2,
          ext_lvl=0, amp=0.5,
          poll_bus, route_bus;

      // read routing matrix from control bus
      var r;
      var prev;
      var i0, i1, i2, i3;
      var m0, m1, m2, m3;
      var fo0, fo1, fo2, fo3;
      var dl0, dl1, dl2, dl3;
      var o0, o1, o2, o3;
      var ei, sig;
      var amps;

      r = In.kr(route_bus, 16);
      prev = LocalIn.ar(4);

      i0 = InFeedback.ar(nb0);
      i1 = InFeedback.ar(nb1);
      i2 = InFeedback.ar(nb2);
      i3 = InFeedback.ar(nb3);

      ei = SoundIn.ar(0) * ext_lvl;

      // matrix mix: r[row*4 + col] = from row to col
      m0 = i0 + (prev[0]*r[0])  + (prev[1]*r[4])  + (prev[2]*r[8])  + (prev[3]*r[12]) + ei;
      m1 = i1 + (prev[0]*r[1])  + (prev[1]*r[5])  + (prev[2]*r[9])  + (prev[3]*r[13]) + ei;
      m2 = i2 + (prev[0]*r[2])  + (prev[1]*r[6])  + (prev[2]*r[10]) + (prev[3]*r[14]) + ei;
      m3 = i3 + (prev[0]*r[3])  + (prev[1]*r[7])  + (prev[2]*r[11]) + (prev[3]*r[15]) + ei;

      // node 0
      fo0 = Select.ar(ft0, [
        RLPF.ar(m0, filt0.clip(20,20000), res0.clip(0.05,1)),
        BPF.ar(m0, filt0.clip(20,20000), res0.clip(0.05,1)),
        RHPF.ar(m0, filt0.clip(20,20000), res0.clip(0.05,1))
      ]);
      dl0 = CombC.ar(fo0, 2.0, dt0.clip(0.001,2.0), fb0 * 5);
      o0 = (dl0 * dv0).tanh * lv0;

      // node 1
      fo1 = Select.ar(ft1, [
        RLPF.ar(m1, filt1.clip(20,20000), res1.clip(0.05,1)),
        BPF.ar(m1, filt1.clip(20,20000), res1.clip(0.05,1)),
        RHPF.ar(m1, filt1.clip(20,20000), res1.clip(0.05,1))
      ]);
      dl1 = CombC.ar(fo1, 2.0, dt1.clip(0.001,2.0), fb1 * 5);
      o1 = (dl1 * dv1).tanh * lv1;

      // node 2
      fo2 = Select.ar(ft2, [
        RLPF.ar(m2, filt2.clip(20,20000), res2.clip(0.05,1)),
        BPF.ar(m2, filt2.clip(20,20000), res2.clip(0.05,1)),
        RHPF.ar(m2, filt2.clip(20,20000), res2.clip(0.05,1))
      ]);
      dl2 = CombC.ar(fo2, 2.0, dt2.clip(0.001,2.0), fb2 * 5);
      o2 = (dl2 * dv2).tanh * lv2;

      // node 3
      fo3 = Select.ar(ft3, [
        RLPF.ar(m3, filt3.clip(20,20000), res3.clip(0.05,1)),
        BPF.ar(m3, filt3.clip(20,20000), res3.clip(0.05,1)),
        RHPF.ar(m3, filt3.clip(20,20000), res3.clip(0.05,1))
      ]);
      dl3 = CombC.ar(fo3, 2.0, dt3.clip(0.001,2.0), fb3 * 5);
      o3 = (dl3 * dv3).tanh * lv3;

      LocalOut.ar([o0, o1, o2, o3]);

      sig = Pan2.ar(o0, pn0) + Pan2.ar(o1, pn1)
          + Pan2.ar(o2, pn2) + Pan2.ar(o3, pn3);
      sig = Limiter.ar(sig * amp, 0.95);
      Out.ar(net_out, sig);

      amps = [
        Amplitude.ar(o0, 0.01, 0.1),
        Amplitude.ar(o1, 0.01, 0.1),
        Amplitude.ar(o2, 0.01, 0.1),
        Amplitude.ar(o3, 0.01, 0.1)
      ];
      Out.kr(poll_bus, amps);
    }).add;

    context.server.sync;

    synth = Synth(\cipher_net, [
      \net_out, out_bus,
      \ext_in, in_bus,
      \nb0, nodeBuses[0].index,
      \nb1, nodeBuses[1].index,
      \nb2, nodeBuses[2].index,
      \nb3, nodeBuses[3].index,
      \poll_bus, ampBus.index,
      \route_bus, routeBus.index
    ], context.xg);

    // -- commands --
    this.addCommand("trig", "ifffi", { arg msg;
      var node, freq, dur, a, tp;
      node = msg[1].asInteger.clip(0, 3);
      freq = msg[2].asFloat;
      dur  = msg[3].asFloat;
      a    = msg[4].asFloat;
      tp   = msg[5].asInteger.clip(0, 3);
      Synth(\cipher_imp, [
        \imp_bus, nodeBuses[node].index,
        \freq, freq, \dur, dur, \amp, a, \type, tp
      ], context.xg);
    });

    this.addCommand("node_filt", "if", { arg msg;
      synth.set(("filt" ++ msg[1].asInteger).asSymbol, msg[2].asFloat);
    });
    this.addCommand("node_res", "if", { arg msg;
      synth.set(("res" ++ msg[1].asInteger).asSymbol, msg[2].asFloat);
    });
    this.addCommand("node_ftype", "ii", { arg msg;
      synth.set(("ft" ++ msg[1].asInteger).asSymbol, msg[2].asInteger);
    });
    this.addCommand("node_dly", "if", { arg msg;
      synth.set(("dt" ++ msg[1].asInteger).asSymbol, msg[2].asFloat);
    });
    this.addCommand("node_dfb", "if", { arg msg;
      synth.set(("fb" ++ msg[1].asInteger).asSymbol, msg[2].asFloat);
    });
    this.addCommand("node_drv", "if", { arg msg;
      synth.set(("dv" ++ msg[1].asInteger).asSymbol, msg[2].asFloat);
    });
    this.addCommand("node_lvl", "if", { arg msg;
      synth.set(("lv" ++ msg[1].asInteger).asSymbol, msg[2].asFloat);
    });
    this.addCommand("node_pan", "if", { arg msg;
      synth.set(("pn" ++ msg[1].asInteger).asSymbol, msg[2].asFloat);
    });
    // routing: write directly to control bus
    this.addCommand("route", "iif", { arg msg;
      var row, col, idx;
      row = msg[1].asInteger.clip(0, 3);
      col = msg[2].asInteger.clip(0, 3);
      idx = row * 4 + col;
      routeBus.setAt(idx, msg[3].asFloat.clip(0, 0.95));
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
    routeBus.free;
  }
}
