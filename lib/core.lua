-- lib/core.lua
-- cipher: params, turing machine, l-system, morse encoder

local Core = {}

-- morse alphabet
local MORSE = {
  A=".-", B="-...", C="-.-.", D="-..", E=".", F="..-.",
  G="--.", H="....", I="..", J=".---", K="-.-", L=".-..",
  M="--", N="-.", O="---", P=".--.", Q="--.-", R=".-.",
  S="...", T="-", U="..-", V="...-", W=".--", X="-..-",
  Y="-.--", Z="--..",
  ["0"]="-----", ["1"]=".----", ["2"]="..---", ["3"]="...--",
  ["4"]="....-", ["5"]=".....", ["6"]="-....", ["7"]="--...",
  ["8"]="---..", ["9"]="----.",
}
local ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

-- turing machine
local TM = { reg=0xACE1, len=8, prob=50, step=0, out=0 }

-- l-system
local LSYS_PRESETS = {
  {name="Fibonacci", axiom="F", rule="F[+F]F[-F]F"},
  {name="Branching", axiom="F", rule="FF+[+F-F-F]-[-F+F+F]"},
  {name="Koch",      axiom="F", rule="F+F-F-F+F"},
  {name="Dragon",    axiom="FX", rule="X:X+YF|Y:FX-Y"},
  {name="Sparse",    axiom="F", rule="F-[[F]+F]+F[+FF]-F"},
}
local LS = { sentence="F", ptr=1, pitch=0, stack={}, preset=1, gens=4 }

-- morse state
local MS = {
  queue = {},       -- queue of {sym, char} tuples
  active = nil,     -- current symbol being transmitted
  timer = 0,        -- countdown for current symbol
  decoded = {},     -- last N decoded characters
  max_decoded = 16,
  word_timer = 0,
  is_transmitting = false,
}

-- sequencer state
local SEQ = {
  running = false,
  tick_acc = 0,
  speed = 1.0,      -- dots per second (WPM related)
  dot_dur = 0.06,   -- seconds
  dash_dur = 0.18,  -- seconds
  gap_dur = 0.08,   -- inter-element gap
  char_gap = 0.2,   -- inter-character gap
  word_gap = 0.5,   -- inter-word gap
  auto_gen = true,
  density = 0.7,    -- probability of emitting vs resting
}

-- node animation data
Core.anim = {
  amps = {0, 0, 0, 0},
  last_trig = {0, 0, 0, 0},
  morse_sym = "",
  garden_health = 0.5,
}

-- routing matrix (4x4)
Core.matrix = {}
for i = 0, 3 do
  Core.matrix[i] = {}
  for j = 0, 3 do Core.matrix[i][j] = 0 end
end

-- node params cache
Core.nodes = {}
for i = 1, 4 do
  Core.nodes[i] = {
    freq = ({440, 330, 550, 220})[i],
    filt = ({2000, 3000, 1200, 600})[i],
    res = ({0.4, 0.5, 0.6, 0.3})[i],
    ftype = 0,
    dly = ({0.12, 0.19, 0.25, 0.37})[i],
    dfb = ({0.4, 0.3, 0.5, 0.2})[i],
    drv = ({1.0, 1.2, 0.8, 1.5})[i],
    lvl = 0.5,
    pan = ({-0.6, 0.6, -0.2, 0.2})[i],
    imp_type = (i - 1) % 4,
  }
end

-- page/param navigation
Core.page = 1
Core.NUM_PAGES = 4
Core.PAGE_NAMES = {"GARDEN", "MORSE", "NETWORK", "NODES"}

Core.node_sel = 1  -- selected node for NODES page
Core.param_idx = 1 -- scroll position within page

local NODE_PARAMS = {
  "freq", "filt", "res", "ftype", "dly", "dfb", "drv", "lvl", "pan", "imp_type"
}
local NODE_PARAM_NAMES = {
  "freq", "filter", "reso", "f.type", "delay", "d.fb", "drive", "level", "pan", "impulse"
}
Core.NUM_NODE_PARAMS = #NODE_PARAMS

-- ============ TURING MACHINE ============

local function tm_tick()
  TM.step = (TM.step % TM.len) + 1
  if math.random(100) <= TM.prob then
    TM.reg = TM.reg ~ 1  -- flip LSB
  end
  local lsb = TM.reg & 1
  TM.reg = (TM.reg >> 1) | (lsb << 15)
  TM.out = TM.reg & 0x1F  -- 5 bits = 0-31
  return TM.out
end

-- ============ L-SYSTEM ============

local function lsys_generate()
  local pr = LSYS_PRESETS[LS.preset]
  local rules = {}
  if pr.rule:find("|") then
    for seg in pr.rule:gmatch("[^|]+") do
      local sym, rep = seg:match("^(%a):(.+)$")
      if sym then rules[sym] = rep end
    end
  else rules["F"] = pr.rule end
  local cur = pr.axiom
  for _ = 1, LS.gens do
    local nxt = {}
    for i = 1, #cur do
      local c = cur:sub(i, i)
      nxt[#nxt + 1] = rules[c] or c
    end
    cur = table.concat(nxt)
    if #cur > 2048 then cur = cur:sub(1, 2048); break end
  end
  LS.sentence = cur; LS.ptr = 1; LS.pitch = 0; LS.stack = {}
end

local function lsys_tick()
  if #LS.sentence == 0 then return false end
  local c = LS.sentence:sub(LS.ptr, LS.ptr)
  if     c == "+" then LS.pitch = (LS.pitch + 1) % 12
  elseif c == "-" then LS.pitch = (LS.pitch - 1 + 12) % 12
  elseif c == "[" then LS.stack[#LS.stack + 1] = LS.pitch
  elseif c == "]" then
    LS.pitch = LS.stack[#LS.stack] or 0
    LS.stack[#LS.stack] = nil
  end
  LS.ptr = (LS.ptr % #LS.sentence) + 1
  return (c == "F")
end

-- ============ MORSE ENCODER ============

local function enqueue_character(char_idx)
  local ch = ALPHA:sub(char_idx, char_idx)
  local code = MORSE[ch]
  if not code then return end
  for i = 1, #code do
    local s = code:sub(i, i)
    MS.queue[#MS.queue + 1] = { sym = s, char = (i == 1) and ch or nil }
  end
  -- inter-character gap
  MS.queue[#MS.queue + 1] = { sym = " ", char = nil }
end

local function enqueue_word_gap()
  MS.queue[#MS.queue + 1] = { sym = "W", char = " " }
end

-- ============ SEQUENCER TICK ============

function Core.seq_tick(dt)
  if not SEQ.running then return nil end
  SEQ.tick_acc = SEQ.tick_acc + dt * SEQ.speed

  -- generate new characters when queue is low
  if #MS.queue < 8 and SEQ.auto_gen then
    local tm_val = tm_tick()
    local ls_emit = lsys_tick()
    if ls_emit then
      -- TM determines character, L-system determines phrasing
      local idx = (tm_val % #ALPHA) + 1
      enqueue_character(idx)
      -- occasional word gap based on L-system pitch
      if LS.pitch > 8 and math.random(100) < 30 then
        enqueue_word_gap()
      end
    else
      -- L-system says rest: maybe insert gap
      if math.random(100) < math.floor(SEQ.density * 40) then
        local idx = (tm_val % #ALPHA) + 1
        enqueue_character(idx)
      end
    end
  end

  -- process current symbol timing
  if MS.timer > 0 then
    MS.timer = MS.timer - dt
    return nil  -- still playing current symbol
  end

  -- advance to next symbol
  if #MS.queue == 0 then
    MS.is_transmitting = false
    Core.anim.morse_sym = ""
    return nil
  end

  local item = table.remove(MS.queue, 1)
  MS.active = item
  MS.is_transmitting = true

  if item.char and item.char ~= " " then
    MS.decoded[#MS.decoded + 1] = item.char
    if #MS.decoded > MS.max_decoded then
      table.remove(MS.decoded, 1)
    end
  elseif item.char == " " then
    MS.decoded[#MS.decoded + 1] = " "
    if #MS.decoded > MS.max_decoded then
      table.remove(MS.decoded, 1)
    end
  end

  if item.sym == "." then
    Core.anim.morse_sym = "."
    MS.timer = SEQ.dot_dur
    return { type = "dot", dur = SEQ.dot_dur }
  elseif item.sym == "-" then
    Core.anim.morse_sym = "-"
    MS.timer = SEQ.dash_dur
    return { type = "dash", dur = SEQ.dash_dur }
  elseif item.sym == " " then
    Core.anim.morse_sym = ""
    MS.timer = SEQ.char_gap
    return nil
  elseif item.sym == "W" then
    Core.anim.morse_sym = ""
    MS.timer = SEQ.word_gap
    return nil
  end
  return nil
end

function Core.get_decoded_str()
  return table.concat(MS.decoded)
end

function Core.get_tm_register() return TM.reg end
function Core.get_tm_len() return TM.len end
function Core.is_running() return SEQ.running end

-- ============ ACTIONS ============

function Core.toggle_play()
  SEQ.running = not SEQ.running
  if SEQ.running then
    MS.queue = {}; MS.timer = 0; SEQ.tick_acc = 0
  end
  return SEQ.running
end

function Core.mutate()
  TM.reg = math.random(1, 65535)
  TM.len = math.random(4, 16)
  TM.step = 0
  LS.preset = math.random(1, #LSYS_PRESETS)
  LS.gens = math.random(3, 5)
  lsys_generate()
  MS.queue = {}
  MS.decoded = {}
end

function Core.randomize_matrix()
  for i = 0, 3 do
    for j = 0, 3 do
      local v = 0
      if i ~= j and math.random(100) < 40 then
        v = math.random() * 0.6
      end
      Core.matrix[i][j] = v
      engine.route(i, j, v)
    end
  end
end

function Core.clear_matrix()
  for i = 0, 3 do
    for j = 0, 3 do
      Core.matrix[i][j] = 0
      engine.route(i, j, 0)
    end
  end
end

function Core.randomize_node(n)
  local nd = Core.nodes[n]
  nd.freq = 50 + math.random() * 1500
  nd.filt = 100 + math.random() * 8000
  nd.res = 0.1 + math.random() * 0.8
  nd.ftype = math.random(0, 2)
  nd.dly = 0.01 + math.random() * 0.8
  nd.dfb = 0.1 + math.random() * 0.7
  nd.drv = 0.5 + math.random() * 2.0
  nd.imp_type = math.random(0, 3)
  Core.send_node(n)
end

function Core.send_node(n)
  local nd = Core.nodes[n]
  local i = n - 1
  engine.node_filt(i, nd.filt)
  engine.node_res(i, nd.res)
  engine.node_ftype(i, math.floor(nd.ftype))
  engine.node_dly(i, nd.dly)
  engine.node_dfb(i, nd.dfb)
  engine.node_drv(i, nd.drv)
  engine.node_lvl(i, nd.lvl)
  engine.node_pan(i, nd.pan)
end

function Core.send_all()
  for n = 1, 4 do Core.send_node(n) end
  for i = 0, 3 do
    for j = 0, 3 do
      engine.route(i, j, Core.matrix[i][j])
    end
  end
  engine.amp(params:get("amp"))
  engine.ext_lvl(params:get("ext_lvl"))
end

-- trigger a morse event into the network
function Core.fire_morse(evt)
  if not evt then return end
  local dur = evt.dur or 0.05
  -- which nodes to trigger: based on TM register bits
  local bits = TM.reg & 0xF
  for n = 0, 3 do
    if (bits >> n) & 1 == 1 then
      local nd = Core.nodes[n + 1]
      local freq = nd.freq * (1 + LS.pitch * 0.05)
      local tp = nd.imp_type
      if evt.type == "dash" then
        dur = dur * 1.5
        freq = freq * 0.8  -- dashes are lower
      end
      engine.trig(n, freq, dur, 0.7, tp)
      Core.anim.last_trig[n + 1] = 8  -- visual flash frames
    end
  end
end

-- compute garden health from amplitude balance
function Core.update_garden()
  local a = Core.anim.amps
  local sum = 0
  local max_a = 0
  for i = 1, 4 do
    sum = sum + a[i]
    if a[i] > max_a then max_a = a[i] end
  end
  -- health: balanced, moderate levels = blooming
  -- clipping or silent = wilting
  local avg = sum / 4
  local balance = 0
  if max_a > 0.001 then
    balance = 1 - (max_a - avg) / max_a  -- 1 = balanced, 0 = one node dominates
  end
  local level_health = 1 - math.abs(avg - 0.3) * 3  -- sweet spot around 0.3
  level_health = math.max(0, math.min(1, level_health))
  Core.anim.garden_health = balance * 0.5 + level_health * 0.5

  -- decay trig flash
  for i = 1, 4 do
    if Core.anim.last_trig[i] > 0 then
      Core.anim.last_trig[i] = Core.anim.last_trig[i] - 1
    end
  end
end

-- ============ PARAMS ============

function Core.init_params()
  params:add_separator("CIPHER")

  -- sequencer
  params:add_separator("sequencer")
  params:add_control("speed", "morse speed",
    controlspec.new(0.1, 5.0, "lin", 0.05, 1.0))
  params:set_action("speed", function(v) SEQ.speed = v end)

  params:add_control("dot_dur", "dot duration",
    controlspec.new(0.01, 0.3, "lin", 0.005, 0.06))
  params:set_action("dot_dur", function(v)
    SEQ.dot_dur = v; SEQ.dash_dur = v * 3
    SEQ.gap_dur = v * 1.2; SEQ.char_gap = v * 3.5
    SEQ.word_gap = v * 7
  end)

  params:add_control("density", "density",
    controlspec.new(0.0, 1.0, "lin", 0.01, 0.7))
  params:set_action("density", function(v) SEQ.density = v end)

  params:add_number("tm_length", "TM length", 2, 16, 8)
  params:set_action("tm_length", function(v) TM.len = v end)

  params:add_number("tm_prob", "TM probability", 0, 100, 50)
  params:set_action("tm_prob", function(v) TM.prob = v end)

  local lnames = {}
  for _, l in ipairs(LSYS_PRESETS) do lnames[#lnames + 1] = l.name end
  params:add_option("lsys_preset", "L-system", lnames, 1)
  params:set_action("lsys_preset", function(v)
    LS.preset = v; lsys_generate()
  end)

  -- nodes
  for n = 1, 4 do
    params:add_separator("node " .. n)
    local nd = Core.nodes[n]

    params:add_control("n"..n.."_freq", "n"..n.." freq",
      controlspec.new(20, 4000, "exp", 0.1, nd.freq))
    params:set_action("n"..n.."_freq", function(v)
      nd.freq = v; engine.node_filt(n-1, nd.filt) -- freq is for impulse, no SC cmd needed
    end)

    params:add_control("n"..n.."_filt", "n"..n.." filter",
      controlspec.new(20, 18000, "exp", 1, nd.filt))
    params:set_action("n"..n.."_filt", function(v)
      nd.filt = v; engine.node_filt(n-1, v)
    end)

    params:add_control("n"..n.."_res", "n"..n.." reso",
      controlspec.new(0.05, 1.0, "lin", 0.01, nd.res))
    params:set_action("n"..n.."_res", function(v)
      nd.res = v; engine.node_res(n-1, v)
    end)

    params:add_option("n"..n.."_ftype", "n"..n.." filt type", {"LP","BP","HP"}, nd.ftype+1)
    params:set_action("n"..n.."_ftype", function(v)
      nd.ftype = v-1; engine.node_ftype(n-1, v-1)
    end)

    params:add_control("n"..n.."_dly", "n"..n.." delay",
      controlspec.new(0.001, 1.5, "exp", 0.001, nd.dly))
    params:set_action("n"..n.."_dly", function(v)
      nd.dly = v; engine.node_dly(n-1, v)
    end)

    params:add_control("n"..n.."_dfb", "n"..n.." delay fb",
      controlspec.new(0, 0.95, "lin", 0.01, nd.dfb))
    params:set_action("n"..n.."_dfb", function(v)
      nd.dfb = v; engine.node_dfb(n-1, v)
    end)

    params:add_control("n"..n.."_drv", "n"..n.." drive",
      controlspec.new(0.1, 4.0, "lin", 0.05, nd.drv))
    params:set_action("n"..n.."_drv", function(v)
      nd.drv = v; engine.node_drv(n-1, v)
    end)

    params:add_control("n"..n.."_lvl", "n"..n.." level",
      controlspec.new(0, 1, "lin", 0.01, nd.lvl))
    params:set_action("n"..n.."_lvl", function(v)
      nd.lvl = v; engine.node_lvl(n-1, v)
    end)

    params:add_control("n"..n.."_pan", "n"..n.." pan",
      controlspec.new(-1, 1, "lin", 0.01, nd.pan))
    params:set_action("n"..n.."_pan", function(v)
      nd.pan = v; engine.node_pan(n-1, v)
    end)

    params:add_option("n"..n.."_imp", "n"..n.." impulse", {"sine","pulse","noise","click"}, nd.imp_type+1)
    params:set_action("n"..n.."_imp", function(v) nd.imp_type = v-1 end)
  end

  -- master
  params:add_separator("master")
  params:add_control("amp", "amplitude",
    controlspec.new(0, 1, "lin", 0.01, 0.5))
  params:set_action("amp", function(v) engine.amp(v) end)

  params:add_control("ext_lvl", "ext input",
    controlspec.new(0, 1, "lin", 0.01, 0))
  params:set_action("ext_lvl", function(v) engine.ext_lvl(v) end)

  print("Cipher: params registered")
  math.randomseed(os.time())
  lsys_generate()
end

-- ============ ENCODER / KEY HELPERS ============

function Core.enc(n, d)
  if Core.page == 1 then
    -- GARDEN: E1=speed, E2=density, E3=dot_dur
    if n == 1 then params:delta("speed", d * 0.1)
    elseif n == 2 then params:delta("density", d * 0.02)
    elseif n == 3 then params:delta("dot_dur", d * 0.005)
    end
  elseif Core.page == 2 then
    -- MORSE: E1=tm_length, E2=tm_prob, E3=lsys_preset
    if n == 1 then params:delta("tm_length", d)
    elseif n == 2 then params:delta("tm_prob", d)
    elseif n == 3 then params:delta("lsys_preset", d)
    end
  elseif Core.page == 3 then
    -- NETWORK: E1=scroll matrix, E2/E3=adjust selected route
    -- simplified: E1=source node, E2=dest node, E3=level
    if n == 1 then
      Core.param_idx = util.clamp(Core.param_idx + d, 1, 16)
    elseif n == 2 or n == 3 then
      local idx = Core.param_idx
      local src = math.floor((idx - 1) / 4)
      local dst = (idx - 1) % 4
      local v = Core.matrix[src][dst] + d * 0.02
      v = util.clamp(v, 0, 0.95)
      Core.matrix[src][dst] = v
      engine.route(src, dst, v)
    end
  elseif Core.page == 4 then
    -- NODES: E1=scroll params, E2=adjust, E3=select node
    if n == 1 then
      Core.param_idx = util.clamp(Core.param_idx + d, 1, #NODE_PARAMS)
    elseif n == 2 then
      local pname = NODE_PARAMS[Core.param_idx]
      local pid = "n" .. Core.node_sel .. "_" .. pname
      if pname == "ftype" or pname == "imp_type" then
        local key = pname == "ftype" and ("n"..Core.node_sel.."_ftype") or ("n"..Core.node_sel.."_imp")
        params:delta(key, d)
      else
        params:delta(pid, d)
      end
    elseif n == 3 then
      Core.node_sel = util.clamp(Core.node_sel + d, 1, 4)
      Core.param_idx = 1
    end
  end
end

function Core.key(n, z)
  if z ~= 1 then return end
  if n == 2 then
    Core.toggle_play()
  elseif n == 3 then
    if Core.page == 2 then
      Core.mutate()
    elseif Core.page == 3 then
      Core.randomize_matrix()
    elseif Core.page == 4 then
      Core.randomize_node(Core.node_sel)
    else
      -- garden page: randomize everything
      Core.mutate()
      Core.randomize_matrix()
      for i = 1, 4 do Core.randomize_node(i) end
    end
  end
end

function Core.next_page()
  Core.page = (Core.page % Core.NUM_PAGES) + 1
  Core.param_idx = 1
end
function Core.prev_page()
  Core.page = ((Core.page - 2) % Core.NUM_PAGES) + 1
  Core.param_idx = 1
end

function Core.get_node_param_name(idx)
  return NODE_PARAM_NAMES[idx] or "?"
end
function Core.get_node_param_val(n, idx)
  local pname = NODE_PARAMS[idx]
  if not pname then return "" end
  local nd = Core.nodes[n]
  local v = nd[pname]
  if pname == "ftype" then
    return ({"LP","BP","HP"})[v+1] or "?"
  elseif pname == "imp_type" then
    return ({"sin","pls","noi","clk"})[v+1] or "?"
  elseif pname == "freq" or pname == "filt" then
    return string.format("%.0f", v)
  else
    return string.format("%.2f", v)
  end
end

return Core
