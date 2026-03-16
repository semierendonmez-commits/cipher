# cipher

*a feedback network that speaks in morse code.*

four nodes. sixteen possible connections. a turing machine composes messages that no one asked for. an l-system decides when to transmit. the network resonates, feeds back, blooms — or collapses.

telegraph meets no-input mixer. the garden grows from the noise.

## requirements

- norns (shield compatible)
- grid 64 (optional, recommended)

## install

```
;install https://github.com/yourusername/cipher
```

after install: **SYSTEM > RESTART** (new SC engine).

## concept

cipher combines two ideas:

**telegraph** — a generative morse code sequencer. a 16-bit turing machine selects characters (A-Z, 0-9). an l-system determines phrasing — when to transmit, when to rest. each dot and dash becomes a sonic impulse.

**feedback garden** — four processing nodes (filter + delay + saturation) connected by a routing matrix. signal flows between nodes, feeding back, resonating, evolving. impossible topologies that would destroy hardware — here they bloom under soft clipping.

the morse sequencer injects energy into the feedback network. which nodes receive each impulse depends on the turing machine register. the network transforms morse rhythm into living texture.

when the network finds balance, the garden on screen blooms. when feedback overloads, it wilts.

## controls

```
K1 + E1    change page
K2         play / stop
K3         randomize (context)
```

### page 1: GARDEN

the main view. organic visual responds to network state.

```
E1    morse speed
E2    density (transmission probability)
E3    dot duration (affects all timing)
K3    full randomize (nodes + matrix + sequencer)
```

blooming = balanced feedback, moderate levels. wilting = silence or overload. four amplitude bars at bottom show each node.

### page 2: MORSE

transmission display. decoded characters scroll across the top. turing machine register shown as bit pattern. l-system and density info below.

```
E1    TM register length (2-16)
E2    TM bit-flip probability
E3    L-system preset
K3    mutate (new TM seed + L-system)
```

### page 3: NETWORK

4x4 routing matrix visualization. brightness = connection level. selected cell highlighted.

```
E1    scroll through matrix cells
E2/E3 adjust selected route level
K3    randomize matrix
```

### page 4: NODES

per-node parameter editing. tabs at top show selected node.

```
E1    scroll parameters
E2    adjust selected parameter
E3    select node (1-4)
K3    randomize selected node
```

node parameters: freq, filter, resonance, filter type (LP/BP/HP), delay time, delay feedback, drive, level, pan, impulse type (sine/pulse/noise/click).

## grid (64-key)

three grid pages, selected from row 8.

### grid page 1: MATRIX

```
rows 1-4, cols 1-4    routing matrix (tap to toggle)
col 5                  node mute toggle
cols 6-8               node level (low/med/high)
row 5                  trigger nodes manually
row 6                  randomize individual nodes
row 7                  [clear] [random] [mutate] [play]
row 8                  page select
```

### grid page 2: STEP

```
rows 1-4, cols 1-8    trigger pads (4 nodes x 8 columns)
                       LED brightness = node amplitude
```

### grid page 3: PERFORM

```
rows 1-4, cols 1-4    probability triggers (more right = more nodes)
row 5                  chaos presets (1=calm ... 4=overload)
```

## signal flow

```
TURING MACHINE (16-bit)
  selects character → A-Z, 0-9
L-SYSTEM (5 presets)
  determines phrasing → transmit or rest

         ↓ morse dot/dash impulses

    ┌─── NODE A (filter→delay→clip) ───┐
    │    NODE B (filter→delay→clip)     │
    │    NODE C (filter→delay→clip)     │
    └─── NODE D (filter→delay→clip) ───┘
              ↕ routing matrix 4×4
              ↕ feedback

    LIMITER → STEREO OUT
```

impulse types per node:
- **sine** — clean morse beep, tuned
- **pulse** — hollow, telegraph key character
- **noise** — burst, radio static
- **click** — impulse train, mechanical

## the garden metaphor

the screen's garden page is not decorative — it's a real-time diagnostic. petal bloom radius maps to individual node amplitude. particle drift speed maps to total energy. center organism size maps to overall health (balanced feedback = large, clipping or silence = small).

health = amplitude balance × level sweetspot. when all four nodes contribute equally at moderate levels, the garden thrives. when one node dominates (feedback runaway) or all are silent, it wilts.

## tips

- start with K3 on GARDEN page to randomize everything, then K2 to play
- go to NETWORK page and add 2-3 diagonal routes (node 1→2, 2→3, 3→1)
- increase delay feedback on nodes for longer resonance
- low morse speed + high density = ambient texture
- high speed + low density = rhythmic morse
- drive > 2.0 pushes nodes into saturation — warm but can overload
- use ext input to feed external audio into the network

## architecture

```
cipher/
  cipher.lua                 -- main (185 lines)
  lib/
    Engine_Cipher.sc          -- SC engine (185 lines)
    core.lua                  -- TM + L-sys + morse + params (285 lines)
    ui.lua                    -- 4-page screen (310 lines)
```

engine: 4-node feedback network with LocalIn/LocalOut. morse impulses injected via separate Synth into node audio buses. vanilla UGens only.

## inspiration

- rob hordijk's benjolin / blippoo box (feedback as instrument)
- alvin lucier's "i am sitting in a room" (resonant feedback)
- keith rowe's no-input mixer practice
- numbers stations (shortwave morse aesthetic)

---

*the message was never meant to be understood.*
