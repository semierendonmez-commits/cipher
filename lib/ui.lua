-- lib/ui.lua
-- cipher: 4-page norns screen UI

local UI = {}
local Core = nil

-- garden animation state
local G = {
  petals = {},
  particles = {},
  time = 0,
  wilt = 0,
}

-- init garden particles
for i = 1, 12 do
  G.petals[i] = {
    x = 64 + math.random(-20, 20),
    y = 32 + math.random(-15, 15),
    r = 3 + math.random() * 5,
    phase = math.random() * 6.28,
    speed = 0.3 + math.random() * 0.7,
  }
end
for i = 1, 20 do
  G.particles[i] = {
    x = math.random(128), y = math.random(50),
    vx = (math.random() - 0.5) * 0.5,
    vy = (math.random() - 0.5) * 0.3,
    life = math.random(),
  }
end

function UI.init(core_ref)
  Core = core_ref
end

function UI.draw(scr)
  scr.clear()
  scr.aa(0)
  scr.font_face(1)
  scr.font_size(8)

  -- header
  local pname = Core.PAGE_NAMES[Core.page] or "?"
  scr.level(2)
  scr.move(1, 7)
  scr.text(pname)
  -- page dots
  for i = 1, Core.NUM_PAGES do
    scr.level(i == Core.page and 10 or 2)
    scr.rect(50 + (i-1)*6, 2, 3, 3)
    scr.fill()
  end
  -- play indicator
  scr.level(Core.is_running() and 12 or 2)
  scr.move(128, 7)
  scr.text_right(Core.is_running() and ">" or ".")
  -- morse symbol flash
  if Core.anim.morse_sym ~= "" then
    scr.level(15)
    scr.move(118, 7)
    scr.text_right(Core.anim.morse_sym == "." and "*" or "---")
  end

  -- page content
  if Core.page == 1 then
    UI.draw_garden(scr)
  elseif Core.page == 2 then
    UI.draw_morse(scr)
  elseif Core.page == 3 then
    UI.draw_network(scr)
  elseif Core.page == 4 then
    UI.draw_nodes(scr)
  end

  -- footer
  scr.level(1)
  scr.move(1, 63)
  if Core.page == 1 then
    scr.text("E1:spd E2:dens E3:dur")
  elseif Core.page == 2 then
    scr.text("E1:TM E2:prob E3:lsys")
  elseif Core.page == 3 then
    scr.text("E1:sel E2/3:lvl K3:rnd")
  elseif Core.page == 4 then
    scr.text("E1:node E2:prm E3:adj")
  end

  scr.update()
end

-- ============ PAGE 1: GARDEN ============

function UI.draw_garden(scr)
  G.time = G.time + 0.05
  local health = Core.anim.garden_health
  local amps = Core.anim.amps
  local total_amp = 0
  for i = 1, 4 do total_amp = total_amp + amps[i] end

  -- background: subtle noise field when unhealthy
  if health < 0.3 then
    local n = math.floor((1 - health) * 8)
    for _ = 1, n do
      scr.level(1)
      scr.pixel(math.random(128), math.random(10, 54))
      scr.fill()
    end
  end

  -- central organism
  local cx, cy = 64, 32
  local base_r = 5 + health * 12
  local pulse = 1 + total_amp * 3

  -- petals: bloom when healthy, collapse when not
  for i, p in ipairs(G.petals) do
    local node_idx = ((i - 1) % 4) + 1
    local a = amps[node_idx] or 0
    local bloom = health * 0.7 + a * 0.3
    local angle = p.phase + G.time * p.speed * (0.3 + health * 0.7)
    local dist = base_r * pulse * bloom
    local px = cx + math.cos(angle) * dist
    local py = cy + math.sin(angle) * dist * 0.7
    local pr = p.r * bloom * pulse

    if pr > 0.5 then
      scr.level(math.floor(2 + bloom * 10))
      -- open petals when healthy, closed dots when wilting
      if health > 0.5 then
        -- petal shape: small circle
        local segs = 5
        for s = 0, segs do
          local sa = (s / segs) * 6.28
          local sx = px + math.cos(sa) * pr
          local sy = py + math.sin(sa) * pr * 0.6
          if s == 0 then scr.move(math.floor(sx), math.floor(sy))
          else scr.line(math.floor(sx), math.floor(sy)) end
        end
        scr.stroke()
      else
        scr.pixel(math.floor(px), math.floor(py))
        scr.fill()
      end
    end
  end

  -- center dot
  scr.level(math.floor(4 + health * 11))
  local cr = math.floor(2 + health * 3 + total_amp * 2)
  for dy = -cr, cr do
    for dx = -cr, cr do
      if dx*dx + dy*dy <= cr*cr then
        scr.pixel(cx + dx, cy + dy)
      end
    end
  end
  scr.fill()

  -- floating particles (spores/signals)
  for _, pt in ipairs(G.particles) do
    pt.x = pt.x + pt.vx * (1 + total_amp * 2)
    pt.y = pt.y + pt.vy * (1 + total_amp)
    pt.life = pt.life - 0.005
    if pt.life <= 0 or pt.x < 0 or pt.x > 128 or pt.y < 8 or pt.y > 56 then
      pt.x = cx + (math.random() - 0.5) * 30
      pt.y = cy + (math.random() - 0.5) * 20
      pt.vx = (math.random() - 0.5) * 0.8
      pt.vy = (math.random() - 0.5) * 0.5
      pt.life = 0.5 + math.random() * 0.5
    end
    scr.level(math.floor(pt.life * 6))
    scr.pixel(math.floor(pt.x), math.floor(pt.y))
    scr.fill()
  end

  -- node amplitude indicators at bottom
  for i = 1, 4 do
    local bx = 14 + (i-1) * 30
    local bh = math.floor(amps[i] * 20)
    scr.level(Core.anim.last_trig[i] > 0 and 15 or 4)
    scr.rect(bx, 55 - bh, 8, bh)
    scr.fill()
    scr.level(2)
    scr.move(bx + 4, 62)
    scr.text_center(tostring(i))
  end
end

-- ============ PAGE 2: MORSE ============

function UI.draw_morse(scr)
  -- decoded message tape
  local msg = Core.get_decoded_str()
  scr.level(8)
  scr.move(2, 18)
  -- show last ~20 chars that fit
  local show = msg
  if #show > 20 then show = show:sub(#show - 19) end
  scr.text(show)

  -- blinking cursor
  if Core.is_running() and (G.time * 4) % 2 < 1 then
    local cx = 2 + #show * 5
    if cx < 126 then
      scr.level(12)
      scr.rect(cx + 1, 11, 4, 8)
      scr.fill()
    end
  end

  -- morse visualization: dots and dashes
  scr.level(3)
  scr.move(0, 24); scr.line(128, 24); scr.stroke()

  -- TM register as bit pattern
  local reg = Core.get_tm_register()
  local tl = Core.get_tm_len()
  local bw = math.floor(120 / math.max(tl, 1))
  for i = 1, math.min(tl, 16) do
    local bit = (reg >> (i-1)) & 1
    scr.level(bit == 1 and 10 or 2)
    scr.rect(4 + (i-1)*bw, 27, bw-1, 3)
    scr.fill()
  end

  -- L-system info
  scr.level(4)
  scr.move(2, 38)
  scr.text("TM:" .. tl .. " P:" .. params:get("tm_prob") .. "%")
  scr.move(128, 38)
  scr.text_right("LS:" .. params:string("lsys_preset"))

  -- density and speed info
  scr.level(5)
  scr.move(2, 46)
  local d = params:get("density")
  scr.text("D:" .. string.format("%.0f%%", d * 100))
  scr.move(40, 46)
  scr.text("S:" .. string.format("%.1f", params:get("speed")))

  -- signal strength meter
  local total = 0
  for i = 1, 4 do total = total + Core.anim.amps[i] end
  local bars = math.floor(total * 20)
  for b = 0, 11 do
    scr.level(b < bars and 8 or 1)
    scr.rect(4 + b * 10, 50, 8, 4)
    scr.fill()
  end
end

-- ============ PAGE 3: NETWORK ============

function UI.draw_network(scr)
  -- 4x4 matrix grid
  local ox, oy = 8, 12
  local cs = 10  -- cell size

  -- labels
  scr.level(4)
  for i = 0, 3 do
    scr.move(ox + i * cs + cs/2, oy - 2)
    scr.text_center(tostring(i+1))
    scr.move(ox - 5, oy + i * cs + cs/2 + 3)
    scr.text_center(tostring(i+1))
  end

  -- matrix cells
  local sel_idx = Core.param_idx
  local sel_src = math.floor((sel_idx - 1) / 4)
  local sel_dst = (sel_idx - 1) % 4

  for i = 0, 3 do
    for j = 0, 3 do
      local v = Core.matrix[i][j]
      local x = ox + j * cs
      local y = oy + i * cs
      local is_sel = (i == sel_src and j == sel_dst)

      -- cell background
      if v > 0.01 then
        scr.level(math.floor(v * 12) + 1)
        scr.rect(x + 1, y + 1, cs - 2, cs - 2)
        scr.fill()
      end

      -- selection border
      if is_sel then
        scr.level(15)
        scr.rect(x, y, cs, cs)
        scr.stroke()
      else
        scr.level(2)
        scr.rect(x, y, cs, cs)
        scr.stroke()
      end
    end
  end

  -- selected route info
  scr.level(8)
  scr.move(55, 18)
  scr.text("from " .. (sel_src+1))
  scr.move(55, 27)
  scr.text("to   " .. (sel_dst+1))
  scr.move(55, 36)
  local sv = Core.matrix[sel_src][sel_dst]
  scr.text("lvl  " .. string.format("%.2f", sv))

  -- node status on right side
  for i = 1, 4 do
    local a = Core.anim.amps[i]
    local bx = 100
    local by = 12 + (i-1) * 11
    local bw = math.floor(a * 24)

    scr.level(Core.anim.last_trig[i] > 0 and 12 or 4)
    scr.move(bx - 2, by + 6)
    scr.text(tostring(i))
    scr.level(math.floor(a * 12) + 1)
    scr.rect(bx + 6, by, bw, 6)
    scr.fill()
    scr.level(2)
    scr.rect(bx + 6, by, 24, 6)
    scr.stroke()
  end

  -- matrix hint
  scr.level(3)
  scr.move(55, 50)
  scr.text("K3:random")
end

-- ============ PAGE 4: NODES ============

function UI.draw_nodes(scr)
  local n = Core.node_sel
  local nd = Core.nodes[n]

  -- node selector tabs
  for i = 1, 4 do
    scr.level(i == n and 12 or 3)
    scr.rect((i-1)*32, 10, 30, 9)
    if i == n then scr.fill() else scr.stroke() end
    scr.level(i == n and 0 or 6)
    scr.move((i-1)*32 + 15, 17)
    scr.text_center("N" .. i)
  end

  -- parameter list
  local start = math.max(1, Core.param_idx - 3)
  local visible = math.min(Core.NUM_NODE_PARAMS, start + 5)
  for row = start, visible do
    local y = 24 + (row - start) * 8
    local is_sel = (row == Core.param_idx)
    scr.level(is_sel and 15 or 4)
    scr.move(4, y)
    scr.text(Core.get_node_param_name(row))
    scr.move(55, y)
    scr.text(Core.get_node_param_val(n, row))

    -- value bar for numeric params
    local pname = ({"freq","filt","res","ftype","dly","dfb","drv","lvl","pan","imp_type"})[row]
    if pname and pname ~= "ftype" and pname ~= "imp_type" then
      local raw = 0
      local pid = "n"..n.."_"..pname
      if pname == "imp_type" then pid = "n"..n.."_imp" end
      pcall(function() raw = params:get_raw(pid) or 0 end)
      scr.level(is_sel and 6 or 2)
      scr.rect(85, y - 6, math.floor(raw * 40), 4)
      scr.fill()
    end
  end

  -- node amplitude
  local a = Core.anim.amps[n]
  scr.level(Core.anim.last_trig[n] > 0 and 15 or 6)
  scr.move(128, 24)
  scr.text_right(string.format("%.1f", a))
end

return UI
