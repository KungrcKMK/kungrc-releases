local toolName = "TNS|SPRC Air Wiz|TNE"

---- #########################################################################
---- # TeamSPRC Air -- drone / plane / delta / heli on stick radios.          #
---- # Pocket, TX15, TX16S, TX16S MK3. Every default comes from a model the   #
---- # team already runs: MOBULA8, F-22, A1, DELTA and Goosky S1. A separate  #
---- # tool so the robot wizard, which drives a weapon, is never touched.     #
---- # Not for the MT12: it has no Ail/Ele/Rud sticks.                        #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html                #
---- #                                                                       #
---- # WARNING: applying overwrites ALL inputs and mixes of the CURRENT       #
---- #          model, and a heli also rewrites curves CV1 to CV6. Always run #
---- #          it on a fresh/empty model slot.                               #
---- #          Failsafe is NOT configured here. With CRSF/ELRS the radio     #
---- #          never sends failsafe -- set it on the RECEIVER, or in         #
---- #          Betaflight on a drone.                                        #
---- #########################################################################

local REPLACE = 2                       -- MixerMultiplex: ADD, MULTIPLY, REPLACE
local CURVE_CUSTOM = 3                  -- CurveRefType: DIFF, EXPO, FUNC, CUSTOM
local UP, MID, DOWN = 1, 2, 3

local T_DRONE, T_PLANE, T_DELTA, T_HELI = 0, 1, 2, 3
local NTYPES = 4
local TYPE_NAME = { [0]="Drone", [1]="Plane", [2]="Delta", [3]="Heli" }

local vtype, page, cursor, pageCount = T_DRONE, 1, 0, 1
local edit, done = false, false
local plan, clashSw = nil, nil
local curvesFailed = false

-- getFieldInfo resolves a switch by name on any radio ("sa".."sz"), so ask the
-- radio once, at load, what it actually has. EdgeTX 2.12 also says how each one
-- is set up, and type 0 is a switch that is turned off.
local SW, SW0, SWSRC, FIRST = {}, { "No" }, {}, nil
if getFieldInfo ~= nil then
  for i = 0, 25 do
    local key = "s" .. string.char(97 + i)
    local fi = getFieldInfo(key)
    local si = nil
    if fi ~= nil and fi.id ~= nil then FIRST = FIRST or fi.id end   -- kept even if SA is off
    if fi ~= nil and fi.id ~= nil and getSwitchInfo ~= nil then si = getSwitchInfo(fi.id) end
    if fi ~= nil and fi.id ~= nil and (si == nil or si.type ~= 0) then
      local nm = string.upper(key)
      SW[#SW + 1]   = nm
      SW0[#SW0 + 1] = nm
      SWSRC[nm]     = fi.id
    end
  end
end
if #SW == 0 then SW[1] = "n/a" end

-- A mix line's switch is a position, not a switch: three numbers per switch
-- from SA up = 1, the same on 2.10 and 2.12. It is how EdgeTX's own heli wizard
-- writes them. A switch sits the same distance from SA in both lists.
local function swPos(nm, where)
  return 3 * (SWSRC[nm] - FIRST) + where
end

local POT = getFieldInfo ~= nil and (getFieldInfo("s1") or getFieldInfo("p1")) or nil
local POTS = { "No" }
if POT ~= nil then POTS[2] = "S1" end

local function at(list, name)
  for i, nm in ipairs(list) do
    if nm == name then return i end
  end
  return 1
end

local YN = { "No", "Yes" }

local function swRow(key, txt, name)
  return { key=key, txt=txt, v=at(SW0, name), list=SW0 }
end

local function numRow(key, txt, val)
  return { key=key, txt=txt, num=true, val=val, min=-100, max=100 }
end

-- `sec` is the page a row sits on; no section may be longer than one screen.
local function section(sec, rows)
  for _, r in ipairs(rows) do r.sec = sec end
  return rows
end

local function joined(...)
  local t = {}
  for _, rows in ipairs({ ... }) do
    for _, r in ipairs(rows) do t[#t + 1] = r end
  end
  return t
end

-- Same five points the team's Goosky S1 flies: a pitch curve is the stick's
-- position 1 to 5, so a row per point is the whole curve.
local function pitch(sec, key, y)
  local rows = {}
  for i, v in ipairs(y) do rows[i] = numRow(key .. i, "Point " .. i, v) end
  return section(sec, rows)
end

local OPTS = {
  -- No rate or expo: on a drone those live in Betaflight.
  [T_DRONE] = section("Switches", {
    swRow("ch5", "CH5 sw", "SA"), swRow("ch6", "CH6 sw", "SB"), swRow("ch7", "CH7 sw", "SC"),
    swRow("ch8", "CH8 sw", "SD"), swRow("ch9", "CH9 sw", "SE"),
    { key="ch10", txt="CH10 pot", v=#POTS, list=POTS },
  }),
  [T_PLANE] = section("Setup", {
    { key="ail2", txt="2nd aileron", v=1, list=YN },
    swRow("flap", "Flap sw", "No"),
    { key="vtail", txt="V-tail", v=1, list=YN },
    swRow("cut", "Thr cut", "SA"),
  }),
  [T_DELTA] = section("Setup", {
    { key="revL", txt="L elevon rev", v=1, list=YN },
    { key="revR", txt="R elevon rev", v=1, list=YN },
    swRow("cut", "Thr cut", "SA"),
  }),
  [T_HELI] = joined(
    section("Switches", {
      -- no "No" here: a heli without throttle hold is not a setup to offer
      { key="hold", txt="Hold sw", v=at(SW, "SA"), list=SW },
      swRow("idle", "Idle sw", "SC"),
      swRow("mode", "Mode sw", "SD"),
    }),
    section("Throttle", { numRow("th0", "Normal", 55), numRow("th1", "Idle 1", 60), numRow("th2", "Idle 2", 70) }),
    pitch("Pitch", "pn", { -3, 0, 14, 45, 100 }),
    pitch("Pitch idle", "pi", { -100, -50, 5, 50, 100 })
  ),
}

-- A clash is two jobs on one switch. CH5..CH9 of a drone are not listed: the team's
-- own F-22 sends one switch to two channels on purpose.
local CLASH = { [T_PLANE] = { "cut", "flap" }, [T_DELTA] = {}, [T_HELI] = { "hold", "idle", "mode" }, [T_DRONE] = {} }

local function fields() return OPTS[vtype] end

local function fieldOf(key)
  for _, f in ipairs(fields()) do
    if f.key == key then return f end
  end
  return nil
end

local function O(key)
  local f = fieldOf(key)
  return f.list[f.v]
end

local function num(key) return fieldOf(key).val end

local function yes(key) return O(key) == "Yes" end

local function findClash()
  local seen = {}
  for _, key in ipairs(CLASH[vtype]) do
    local nm = O(key)
    if nm ~= "No" then
      if seen[nm] then return "SW CLASH: " .. nm end
      seen[nm] = true
    end
  end
  return nil
end

-- ---------------------------------------------------------------- build plan
-- src is a stick's input name, or a switch or pot's source id.
local function line(src, weight, name, more)
  local l = more or {}
  l.src, l.weight, l.name = src, weight, name
  return l
end

-- The last line of CH3, and REPLACE means it beats everything above it.
local function cutLine(name)
  return line(getFieldInfo("max").id, -100, "Cut", { multiplex=REPLACE, switch=swPos(name, DOWN) })
end

local function throttle(lines)
  if O("cut") ~= "No" then lines[#lines + 1] = cutLine(O("cut")) end
  return lines
end

local function droneChannels(ch)
  ch(1, { line("Ail", 100, "Ail") })
  ch(2, { line("Ele", 100, "Ele") })
  ch(3, { line("Thr", 100, "Thr") })
  ch(4, { line("Rud", 100, "Rud") })
  for i = 5, 9 do
    local nm = O("ch" .. i)
    if nm ~= "No" then ch(i, { line(SWSRC[nm], 100, "CH" .. i) }) end
  end
  if O("ch10") ~= "No" then ch(10, { line(POT.id, 100, "CH10") }) end
end

local function planeChannels(ch)
  ch(1, { line("Ail", 100, "Ail") })
  ch(3, throttle({ line("Thr", 100, "Thr") }))
  if yes("vtail") then
    ch(2, { line("Ele", 50, "VtL"), line("Rud", 50, "VtL") })
    ch(4, { line("Ele", 50, "VtR"), line("Rud", -50, "VtR") })
  else
    ch(2, { line("Ele", 100, "Ele") })
    ch(4, { line("Rud", 100, "Rud") })
  end
  if O("flap") ~= "No" then ch(5, { line(SWSRC[O("flap")], 100, "Flap") }) end
  if yes("ail2") then ch(6, { line("Ail", -100, "Ail2") }) end
end

local function deltaChannels(ch)
  local sL = yes("revL") and -1 or 1
  local sR = yes("revR") and -1 or 1
  ch(1, { line("Ele", sL * 50, "ElvL"), line("Ail", sL * 50, "ElvL") })
  ch(2, { line("Ele", sR * 50, "ElvR"), line("Ail", -sR * 50, "ElvR") })
  ch(3, throttle({ line("Thr", 100, "Thr") }))
end

-- Flybarless: the controller on the heli does the swash, so the radio only sends
-- sticks, a throttle curve and a pitch curve. Normal is the plain line, so a radio
-- with no idle switch can only ever sit on it, and Hold comes last on CH3 to beat
-- every curve above it. Curve numbers are 1-based here: CV1 = 1.
local function heliChannels(ch)
  local idle = O("idle")
  local function up(lines, name1, curve1, name2, curve2)
    if idle ~= "No" then
      lines[#lines + 1] = line("Thr", 100, name1, { curve=curve1, multiplex=REPLACE, switch=swPos(idle, MID) })
      lines[#lines + 1] = line("Thr", 100, name2, { curve=curve2, multiplex=REPLACE, switch=swPos(idle, DOWN) })
    end
    return lines
  end
  ch(1, { line("Ail", 100, "Ail") })
  ch(2, { line("Ele", 100, "Ele") })
  local th = up({ line("Thr", 100, "Th0", { curve=1 }) }, "Th1", 2, "Th2", 3)
  th[#th + 1] = line("Thr", 100, "Hld", { curve=4, multiplex=REPLACE, switch=swPos(O("hold"), DOWN) })
  ch(3, th)
  ch(4, { line("Rud", 100, "Rud") })
  if O("mode") ~= "No" then ch(5, { line(SWSRC[O("mode")], 100, "Mode") }) end
  ch(6, up({ line("Thr", 100, "Pch", { curve=5 }) }, "Pi1", 6, "Pi2", 6))
end

local BUILD = { [T_DRONE]=droneChannels, [T_PLANE]=planeChannels, [T_DELTA]=deltaChannels, [T_HELI]=heliChannels }

local function buildPlan()
  local p = {}
  BUILD[vtype](function(num, lines) p[#p + 1] = { num = num, lines = lines } end)
  clashSw = findClash()
  return p
end

-- Locate the input line EdgeTX built for a named stick ("Ele", "Ail", ...).
local function findInput(want)
  for i = 0, 15 do
    local inp = model.getInput(i, 0)
    if inp ~= nil then
      local nm = inp.inputName
      if nm == nil or nm == "" then nm = inp.name end
      if nm == want then return i end
    end
  end
  error("No " .. want .. " input on this radio")
end

local function points(key)
  local y = {}
  for i = 1, 5 do y[i] = num(key .. i) end
  return y
end

-- A heli line pointing at a curve that did not store would not fly as shown, so
-- this runs before anything else and a failure stops the whole apply.
local function setHeliCurves()
  local a, b, c = num("th0"), num("th1"), num("th2")
  local curves = {
    { name="TC0", y={ -100, a, a, a, a } },
    { name="TC1", y={ b, b, b } },
    { name="TC2", y={ c, c, c } },
    { name="THD", y={ -100, -100, -100 } },
    { name="PC0", y=points("pn") },
    { name="PC1", y=points("pi") },
  }
  for i, c1 in ipairs(curves) do
    if model.setCurve(i - 1, c1) ~= 0 then return false end
  end
  return true
end

local function applyPlan()
  if vtype == T_HELI and not setHeliCurves() then
    curvesFailed = true
    return
  end
  model.defaultInputs()
  -- every source is found before the old mixes go, so a surprise leaves them alone
  local out = {}
  for _, c in ipairs(plan) do
    for j, l in ipairs(c.lines) do
      local src = l.src
      if type(src) == "string" then src = MIXSRC_FIRST_INPUT + findInput(src) end
      local mix = { source = src, weight = l.weight, name = l.name }
      if l.multiplex ~= nil then mix.multiplex = l.multiplex end
      if l.switch ~= nil then mix.switch = l.switch end
      if l.curve ~= nil then
        mix.curveType, mix.curveValue = CURVE_CUSTOM, l.curve
      end
      out[#out + 1] = { c.num - 1, j - 1, mix }
    end
  end
  model.deleteMixes()
  for _, m in ipairs(out) do model.insertMix(m[1], m[2], m[3]) end
end

-- --------------------------------------------------------------------- UI
-- Same screens as the robot wizard: laid out on a mono radio's 128x64 grid, which a
-- colour radio scales up. Colour EdgeTX has no drawScreenTitle, but a flags-0
-- rectangle and the box behind INVERS text come out the same colour there, whatever
-- the theme, so a bar still reads as one solid row.
local VIS, VALX = 6, 78     -- rows that fit on a 128x64 screen, value column
local MONO = lcd.drawScreenTitle ~= nil
local FONT, BIG, TOP = 0, DBLSIZE, 0

local function gx(v) return math.floor(v * LCD_W / 128) end
local function gy(v) return math.floor(v * LCD_H / 64) end

if not MONO then
  FONT, BIG = MIDSIZE, DBLSIZE
  if LCD_W >= 800 then FONT, BIG = DBLSIZE, XXLSIZE end
  local _, h = lcd.sizeText("Ag", FONT)
  TOP = math.floor((gy(7) - h) / 2)      -- centres the text on its 9-tall row
end

local function text(x, y, s, f, big)
  lcd.drawText(gx(x), gy(y) + TOP, s, f + (big and BIG or FONT))
end

local function bar(y)                    -- one full-width row, y is its text line
  lcd.drawFilledRectangle(0, gy(y - 1), LCD_W, gy(9), 0)
end

local function title(s, idx, cnt)
  if MONO then
    lcd.drawScreenTitle(s, idx, cnt)
    return
  end
  lcd.drawFilledRectangle(0, 0, LCD_W, gy(8), 0)     -- a gap, or it merges with a selected first row
  text(2, 1, s, INVERS)
  lcd.drawText(gx(126), gy(1) + TOP, idx .. "/" .. cnt, FONT + INVERS + RIGHT)
end

local function inc(e) return e == EVT_VIRTUAL_INC or e == EVT_VIRTUAL_INC_REPT end
local function dec(e) return e == EVT_VIRTUAL_DEC or e == EVT_VIRTUAL_DEC_REPT end
local function held(e) return e == EVT_VIRTUAL_INC_REPT or e == EVT_VIRTUAL_DEC_REPT end

-- Numeric fields clamp at their limits rather than wrapping. Holding the key steps
-- by 5 so -100..100 stays usable on a two-button radio.
local function bump(o, dir, fast)
  if o.num then
    o.val = o.val + dir * (fast and 5 or 1)
    if o.val > o.max then o.val = o.max end
    if o.val < o.min then o.val = o.min end
  elseif dir > 0 then
    o.v = (o.v % #o.list) + 1
  else
    o.v = ((o.v - 2) % #o.list) + 1
  end
end

local function shown(o)
  if o.num then return o.val .. "%" end
  return o.list[o.v]
end

local function sectionCount(f)
  local n, prev = 0, nil
  for _, o in ipairs(f) do
    if o.sec ~= prev then n, prev = n + 1, o.sec end
  end
  return n
end

local function drawTypeMenu()
  pageCount = sectionCount(fields()) + 2      -- plus this menu and the review
  lcd.clear()
  title("SPRC Air Wizard", 1, pageCount)
  for i = 0, NTYPES - 1 do
    text(30, 11 + i * 10, TYPE_NAME[i], i == vtype and INVERS or 0)
  end
end

-- Selected: the whole row is a bar. Editing: the bar goes and only the value blinks.
local function drawRow(o, y, sel)
  local fl, vf = 0, 0
  if sel and not edit then
    bar(y)
    fl, vf = INVERS, INVERS
  elseif sel then
    vf = INVERS + BLINK
  end
  text(2, y, o.txt, fl)
  text(VALX, y, shown(o), vf)
end

local function drawOptions()
  local f = fields()
  local sec, prev = f[cursor + 1].sec, nil
  local secs, here, view = 0, 0, {}
  for i, o in ipairs(f) do
    if o.sec ~= prev then secs, prev = secs + 1, o.sec end
    if o.sec == sec then here = secs ; view[#view + 1] = i end
  end
  lcd.clear()
  title(TYPE_NAME[vtype] .. " " .. sec, here + 1, pageCount)
  for r, i in ipairs(view) do
    drawRow(f[i], 1 + r * 9, i - 1 == cursor)
  end
  if #view < VIS then text(2, 56, "Hold ENTER: review", 0) end
end

-- At most five lines: the sixth row of the screen is the bar.
local function reviewLines()
  local l = {}
  local function add(a, b) l[#l + 1] = { a, b } end
  local function cutRow()
    if O("cut") ~= "No" then add("Thr cut", O("cut")) end
  end
  if vtype == T_DRONE then
    add("CH1-4 sticks", "AETR")
    add("CH5 CH6", O("ch5") .. " " .. O("ch6"))
    add("CH7 CH8", O("ch7") .. " " .. O("ch8"))
    add("CH9", O("ch9"))
    add("CH10", O("ch10"))
  elseif vtype == T_PLANE then
    add("CH1-4 sticks", yes("vtail") and "V-tail" or "AETR")
    cutRow()
    if O("flap") ~= "No" then add("CH5 Flap", O("flap")) end
    if yes("ail2") then add("CH6 Ail 2", "On") end
  elseif vtype == T_DELTA then
    add("CH1 L elevon", yes("revL") and "Rev" or "Norm")
    add("CH2 R elevon", yes("revR") and "Rev" or "Norm")
    add("CH3 Motor", nil)
    cutRow()
  else
    add("CH1 2 4 sticks", "AER")
    add("CH3 Thr", "Idle " .. O("idle"))
    add("CH5 Mode", O("mode"))
    add("CH6 Pitch", nil)
    add("Hold", O("hold"))
  end
  return l
end

local function drawReview()
  lcd.clear()
  title(TYPE_NAME[vtype] .. " channels", pageCount, pageCount)
  for i, l in ipairs(reviewLines()) do
    text(2, 2 + i * 9, l[1], 0)
    if l[2] ~= nil then text(VALX, 2 + i * 9, l[2], 0) end
  end
  bar(56)
  text(1, 56, clashSw or "[Long Enter] apply", INVERS)
end

-- Failsafe lives on the RECEIVER with ELRS, or in Betaflight on a drone. EdgeTX's
-- crossfire driver has no failsafe code at all, so Model Setup would be a dead end.
local function drawDone()
  lcd.clear()
  title("SPRC Air Wizard", pageCount, pageCount)
  if curvesFailed then
    text(2, 20, "Curves NOT set", 0)
    text(2, 30, "Mixes not written", 0)
    return
  end
  text(16, 10, "FAILSAFE!", INVERS, true)
  if vtype == T_DRONE then
    text(2, 30, "Set it in Betaflight", 0)
  else
    text(2, 30, "Set it on the RX:", 0)
    text(2, 39, "ELRS Lua or 10.0.0.1", 0)
  end
  text(2, 52, vtype == T_HELI and "Test: blades off" or "Test: props off", 0)
end

-- ------------------------------------------------------------------- main
local function run(event)
  if event == nil then
    error("Run this from SYS > Tools")
  end

  if done then
    drawDone()
    if event == EVT_VIRTUAL_EXIT or event == EVT_VIRTUAL_ENTER then return 2 end
    return 0
  end

  if page == 1 then
    drawTypeMenu()
    if event == EVT_VIRTUAL_EXIT then
      return 2
    elseif event == EVT_VIRTUAL_ENTER then
      page, cursor, edit = 2, 0, false
    elseif inc(event) then
      vtype = (vtype + 1) % NTYPES
    elseif dec(event) then
      vtype = (vtype + NTYPES - 1) % NTYPES
    end
    return 0
  end

  if page == 2 then
    drawOptions()
    local f = fields()
    if event == EVT_VIRTUAL_ENTER_LONG then
      plan = buildPlan()
      page = 3
    elseif event == EVT_VIRTUAL_EXIT then
      if edit then edit = false else page = 1 end
    elseif event == EVT_VIRTUAL_ENTER then
      edit = not edit
    elseif inc(event) then
      if edit then
        bump(f[cursor + 1], 1, held(event))
      else
        cursor = (cursor + 1) % #f
      end
    elseif dec(event) then
      if edit then
        bump(f[cursor + 1], -1, held(event))
      else
        cursor = (cursor - 1 + #f) % #f
      end
    end
    return 0
  end

  drawReview()
  if event == EVT_VIRTUAL_ENTER_LONG and clashSw == nil then
    applyPlan()
    done = true
  elseif event == EVT_VIRTUAL_EXIT then
    page = 2
  end
  return 0
end

local function init()
end

return { init = init, run = run }
