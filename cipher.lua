-- cipher.lua
-- feedback network that speaks in morse code
-- telegraph sequencer + no-input mixer garden
--
-- K1+E1: change page
-- E1/E2/E3: context-dependent (see footer)
-- K2: play/stop
-- K3: randomize (context-dependent)
--
-- v1.0.0 @semi

engine.name = "Cipher"

local Core = include("cipher/lib/core")
local UI   = include("cipher/lib/ui")

local clocks = {}
local screen_dirty = true
local g = nil  -- grid device
local grid_page = 1
local grid_dirty = true
local k2_time = 0

-- ============ GRID ============

local function grid_connect()
  g = grid.connect()
  if g then
    g.key = function(x, y, z)
      if z ~= 1 then return end
      if grid_page == 1 then
        -- MATRIX: 4x4 routing toggle/increment
        if x <= 4 and y <= 4 then
          local src = y - 1
          local dst = x - 1
          local v = Core.matrix[src][dst]
          if v > 0.01 then
            v = 0  -- toggle off
          else
            v = 0.3 + math.random() * 0.3  -- random level
          end
          Core.matrix[src][dst] = v
          engine.route(src, dst, v)
          grid_dirty = true
        -- col 5: node mute toggle
        elseif x == 5 and y <= 4 then
          local nd = Core.nodes[y]
          nd.lvl = nd.lvl > 0.01 and 0 or 0.5
          engine.node_lvl(y - 1, nd.lvl)
          params:set("n"..y.."_lvl", nd.lvl)
          grid_dirty = true
        -- col 6-8: preset-style node levels (low/med/hi)
        elseif x >= 6 and x <= 8 and y <= 4 then
          local levels = {0.25, 0.5, 0.8}
          local nd = Core.nodes[y]
          nd.lvl = levels[x - 5]
          engine.node_lvl(y - 1, nd.lvl)
          params:set("n"..y.."_lvl", nd.lvl)
          grid_dirty = true
        -- row 5-6: trigger nodes manually
        elseif y == 5 and x <= 4 then
          local nd = Core.nodes[x]
          engine.trig(x - 1, nd.freq, 0.1, 0.8, nd.imp_type)
          Core.anim.last_trig[x] = 8
          grid_dirty = true
        -- row 6: randomize nodes
        elseif y == 6 and x <= 4 then
          Core.randomize_node(x)
          grid_dirty = true
        -- row 7: clear / random matrix
        elseif y == 7 then
          if x == 1 then Core.clear_matrix()
          elseif x == 2 then Core.randomize_matrix()
          elseif x == 3 then Core.mutate()
          elseif x == 4 then Core.toggle_play()
          end
          grid_dirty = true
        -- row 8: grid page select
        elseif y == 8 and x <= 3 then
          grid_page = x
          grid_dirty = true
        end
      elseif grid_page == 2 then
        -- STEP: morse pattern editor (8 steps x 4 nodes)
        if x <= 8 and y <= 4 then
          -- manual trigger sequence
          local nd = Core.nodes[y]
          engine.trig(y - 1, nd.freq, 0.08, 0.7, nd.imp_type)
          Core.anim.last_trig[y] = 6
          grid_dirty = true
        end
      elseif grid_page == 3 then
        -- PERFORM: macro triggers
        if y <= 4 and x <= 4 then
          -- trigger combos: trigger multiple nodes based on position
          for n = 1, 4 do
            if math.random(100) < (25 * x) then
              local nd = Core.nodes[n]
              engine.trig(n - 1, nd.freq * (1 + y * 0.1), 0.05 + y * 0.03, 0.6, nd.imp_type)
              Core.anim.last_trig[n] = 6
            end
          end
          grid_dirty = true
        elseif y == 5 then
          -- chaos levels
          if x <= 4 then
            local chaos = x * 0.25
            for i = 0, 3 do
              for j = 0, 3 do
                if i ~= j and math.random(100) < chaos * 80 then
                  local v = math.random() * chaos * 0.6
                  Core.matrix[i][j] = v
                  engine.route(i, j, v)
                end
              end
            end
            grid_dirty = true
          end
        end
      end
      screen_dirty = true
    end
  end
end

local function grid_redraw()
  if not g then return end
  g:all(0)
  if grid_page == 1 then
    -- matrix 4x4
    for i = 0, 3 do
      for j = 0, 3 do
        local v = Core.matrix[i][j]
        g:led(j + 1, i + 1, math.floor(v * 14) + 1)
      end
    end
    -- node mutes col 5
    for i = 1, 4 do
      g:led(5, i, Core.nodes[i].lvl > 0.01 and 10 or 2)
    end
    -- node level cols 6-8
    for i = 1, 4 do
      local lvl = Core.nodes[i].lvl
      for x = 6, 8 do
        local thresh = ({0.25, 0.5, 0.8})[x - 5]
        g:led(x, i, lvl >= thresh and 8 or 2)
      end
    end
    -- trigger row 5
    for i = 1, 4 do
      g:led(i, 5, Core.anim.last_trig[i] > 0 and 15 or 4)
    end
    -- randomize row 6
    for i = 1, 4 do g:led(i, 6, 3) end
    -- actions row 7
    g:led(1, 7, 4)  -- clear
    g:led(2, 7, 6)  -- random matrix
    g:led(3, 7, 6)  -- mutate
    g:led(4, 7, Core.is_running() and 12 or 4)  -- play
    -- page select row 8
    for i = 1, 3 do
      g:led(i, 8, i == grid_page and 12 or 3)
    end
  elseif grid_page == 2 then
    -- step trigger pads
    for y = 1, 4 do
      for x = 1, 8 do
        local a = Core.anim.amps[y]
        g:led(x, y, math.floor(a * 10) + 2)
      end
    end
    -- page select
    for i = 1, 3 do g:led(i, 8, i == grid_page and 12 or 3) end
  elseif grid_page == 3 then
    -- perform pads
    for y = 1, 4 do
      for x = 1, 4 do
        g:led(x, y, 4 + x)
      end
    end
    -- chaos row
    for x = 1, 4 do g:led(x, 5, 2 + x * 2) end
    -- page select
    for i = 1, 3 do g:led(i, 8, i == grid_page and 12 or 3) end
  end
  g:refresh()
end

-- ============ POLLS ============

local function setup_polls()
  local p = poll.set("node_amps")
  if p then
    p.callback = function(val)
      -- val is a string "a,b,c,d"
      local s = tostring(val)
      local vals = {}
      for v in s:gmatch("[^,]+") do
        vals[#vals + 1] = tonumber(v) or 0
      end
      for i = 1, math.min(4, #vals) do
        Core.anim.amps[i] = vals[i]
      end
    end
    p.time = 1 / 15
    p:start()
  end
end

-- ============ CLOCK LOOPS ============

local function seq_loop()
  while true do
    clock.sleep(1 / 60)  -- 60Hz sequencer resolution
    local ok, err = pcall(Core.seq_tick, 1 / 60)
    if ok and err then
      Core.fire_morse(err)
      screen_dirty = true
      grid_dirty = true
    elseif not ok then
      print("cipher seq error: " .. tostring(err))
    end
    pcall(Core.update_garden)
  end
end

local function screen_loop()
  while true do
    clock.sleep(1 / 15)
    -- skip drawing when norns system menu is showing
    local menu_active = _menu and _menu.mode
    if screen_dirty and not menu_active then
      local ok, err = pcall(UI.draw, screen)
      if not ok then print("cipher draw error: " .. tostring(err)) end
      screen_dirty = false
    end
    if grid_dirty and g then
      pcall(grid_redraw)
      grid_dirty = false
    end
  end
end

-- ============ NORNS CALLBACKS ============

function init()
  print("CIPHER: init...")
  Core.init_params()
  params:default()
  UI.init(Core)
  grid_connect()

  -- send initial state to engine
  Core.send_all()

  -- start clocks
  clocks.seq = clock.run(seq_loop)
  clocks.screen = clock.run(screen_loop)

  -- polls
  setup_polls()

  screen_dirty = true
  print("CIPHER: ready")
end

local page_acc = 0
local k2_held = false

function enc(n, d)
  if k2_held then
    -- K2+E1: page change
    if n == 1 then
      page_acc = page_acc + d
      if math.abs(page_acc) >= 3 then
        if page_acc > 0 then Core.next_page() else Core.prev_page() end
        page_acc = 0
        screen_dirty = true
      end
      return
    end
  end
  Core.enc(n, d)
  screen_dirty = true
end

function key(n, z)
  -- K1: don't intercept, let norns handle menu
  if n == 2 then
    if z == 1 then
      k2_held = true
      k2_time = util.time()
    else
      k2_held = false
      page_acc = 0
      -- short press = play/stop (only if not used for page change)
      if util.time() - (k2_time or 0) < 0.3 then
        Core.toggle_play()
      end
    end
    screen_dirty = true
    grid_dirty = true
    return
  end
  if n == 3 and z == 1 then
    Core.key(3, 1)
    screen_dirty = true
    grid_dirty = true
  end
end

function cleanup()
  for _, id in pairs(clocks) do
    pcall(function() clock.cancel(id) end)
  end
  if g then g:all(0); g:refresh() end
  print("CIPHER: shutdown")
end
