local toolName = "TNS|SPRC MT12 Wiz|TNE"

---- #########################################################################
---- # TeamSPRC Wizard -- surface: car / crawler / tank / boat / robot        #
---- # Replaces the stock EdgeTX aircraft wizard, useless on a surface radio. #
---- # Built for RadioMaster MT12, EdgeTX 2.10, 128x64 mono screen.           #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html                #
---- #                                                                       #
---- # WARNING: applying overwrites ALL inputs and mixes of the CURRENT       #
---- #          model. Always run it on a fresh/empty model slot.             #
---- #          Failsafe is NOT configured here. With CRSF/ELRS the radio     #
---- #          never sends failsafe -- set it on the RECEIVER itself.        #
---- #                                                                       #
---- # NOTE: weights are plain percentages only. On EdgeTX 2.10               #
---- #       model.insertMix() stores `weight` straight into the bitfield     #
---- #       with no GVAR translation, so a gvar written from Lua just        #
---- #       overflows (1256 came back as -792). Swap a weight to GV1 by      #
---- #       hand on the MIXES page if you want live power trim.              #
---- #########################################################################

-- Which input carries throttle and steering is NOT fixed. A surface radio
-- (MT12) builds TH and ST; an air radio (Pocket) builds Ail/Ele/Thr/Rud, and a
-- robot flown on one may well be driven from Ele + Ail. So the plan carries
-- placeholders and the real input index is looked up by name at apply time.
local IN_TH, IN_ST = -1, -2
local inThr, inStr = 0, 1

local ADD, MULT = 0, 1
local CURVE_EXPO, CURVE_CUSTOM = 1, 3   -- myeeprom.h CurveRefType: DIFF, EXPO, FUNC, CUSTOM

local T_CAR, T_CRAWL, T_TANK, T_BOAT, T_ROBOT = 0, 1, 2, 3, 4
local NTYPES = 5
local TYPE_NAME = { [0]="Car", [1]="Crawler", [2]="Tank", [3]="Boat", [4]="Robot" }

local vtype, page, cursor, pageCount = T_CAR, 1, 0, 1
local edit, done = false, false
local plan = nil
local clashSw = nil
local dzFailed = false

local YN    = { "No", "Yes" }
-- Switch mix sources are NOT exported as constants on every build: the
-- MIXSRC_* list is generated per radio (lua_mixsrc.inc), so the switch
-- constants exist on one handset and are nil on the next -- which is exactly
-- how this crashed. getFieldInfo resolves a switch by name on any radio
-- ("sa".."sz"), so ask the radio once, at load, what it actually has.
local SW, SW0, SWSRC, ISSW = {}, { "No" }, {}, {}
if getFieldInfo ~= nil then
  for i = 0, 25 do
    local key = "s" .. string.char(97 + i)
    local fi = getFieldInfo(key)
    if fi ~= nil and fi.id ~= nil then
      local nm = string.upper(key)
      SW[#SW + 1]   = nm
      SW0[#SW0 + 1] = nm
      SWSRC[nm]     = fi.id
      ISSW[fi.id]   = true
    end
  end
end
if #SW == 0 then SW[1] = "n/a" end

-- S3 and S4 are latching 2-position flex switches. getFieldInfo only knows
-- "sa".."sz", but flex switches sit straight after the regular ones in the
-- source list, so read their names there. Whatever does not read as a flex
-- switch is left out, and an older radio simply offers SA..SD as before.
local lastSw = SWSRC[SW[#SW]]
if lastSw ~= nil and getSourceName ~= nil then
  for i = 1, 2 do
    local n = getSourceName(lastSw + i)
    if n ~= nil then n = string.match(n, "S%d$") or string.match(n, "FL%d$") end
    if n ~= nil then
      SW[#SW + 1]   = n
      SW0[#SW0 + 1] = n
      SWSRC[n]      = lastSw + i
      ISSW[lastSw + i] = true
    end
  end
end

-- Flip multiplies throttle by the switch, so a 3-position switch would cut all
-- throttle in its middle position. SB, SC and SD are momentary on this radio:
-- usable, but Flip then only holds while the button is held, so S3 comes first.
local FLIP, flipDef = { "No" }, 1
for _, nm in ipairs(SW) do
  if nm ~= "SA" and nm ~= "n/a" then
    FLIP[#FLIP + 1] = nm
    if flipDef == 1 and (nm == "S3" or nm == "FL1") then flipDef = #FLIP end
  end
end

local REV4  = { "None", "Str", "Thr", "Both" }

-- Every type starts with the same four rate/expo rows; `rest` is appended.
-- `sec` is the page a row sits on; no section may be longer than one screen.
-- (Returning them as a table, not multiple values -- a multi-value call in the
--  middle of a table constructor is truncated to its first result.)
local function rows(thrRate, strRate, rest)
  local t = {
    { key="thrIn",   sec="Sticks", txt="Fwd-Back stick", v=1, list={ "TH","Thr","Ele","Ail","Rud" } },
    { key="strIn",   sec="Sticks", txt="L-R stick", v=1, list={ "ST","Rud","Ail","Ele","Thr" } },
    { key="thrRate", sec="Sticks", txt="Fwd-Back rate", num=true, val=thrRate, min=1, max=100 },
    { key="strRate", sec="Sticks", txt="L-R rate", num=true, val=strRate, min=1, max=100 },
    { key="thrExpo", sec="Sticks", txt="Fwd-Back expo", num=true, val=0,       min=0, max=100 },
    { key="strExpo", sec="Sticks", txt="L-R expo", num=true, val=0,       min=0, max=100 },
  }
  for _, r in ipairs(rest) do
    r.sec = "Setup"
    t[#t + 1] = r
  end
  return t
end

local OPTS = {
  [T_CAR] = rows(100, 100, {
    { key="rev",     txt="Reverse",     v=1, list=REV4 },
    { key="steer2",  txt="2nd str srv", v=1, list=YN },
    { key="gearSw",  txt="Gear sw",     v=1, list=SW0 },
    { key="lightSw", txt="Lights sw",   v=1, list=SW0 },
  }),
  [T_CRAWL] = rows(100, 100, {
    { key="rev",     txt="Reverse",    v=1, list=REV4 },
    { key="rear",    txt="Rear steer", v=1, list={ "None","Crab","Counter" } },
    { key="gearSw",  txt="Gear sw",    v=1, list=SW0 },
    { key="dlock",   txt="Diff lock",  v=1, list={ "None","Rear","Frt+Rear" } },
    { key="dlockSw", txt="Dlock sw",   v=3, list=SW },
    { key="winchSw", txt="Winch sw",   v=1, list=SW0 },
  }),
  [T_TANK] = rows(100, 100, {
    { key="turn",  txt="Turn rate", num=true, val=100, min=1, max=100 },
    { key="revL",  txt="L wheel rev", v=1, list=YN },
    { key="revR",  txt="R wheel rev", v=1, list=YN },
    { key="auxSw", txt="Aux sw",    v=1, list=SW0 },
  }),
  [T_BOAT] = rows(100, 100, {
    { key="mot",  txt="Motors",      v=1, list={ "1","2" } },
    { key="rud",  txt="Rudder",      v=2, list=YN },
    { key="diff", txt="Diff thrust", num=true, val=0, min=0, max=100 },
    { key="rev",  txt="Reverse",     v=1, list={ "None","Rud","Thr","Both" } },
  }),
  -- House standard from the SUS304 / RB1500g experiments: SUS304's proven
  -- 80% throttle / 50% steering rates as the default, motors corrected in
  -- hardware rather than in the mix.
  [T_ROBOT] = {
    { key="thrIn",   sec="Drive",  txt="Fwd-Back stick", v=1, list={ "TH","Thr","Ele","Ail","Rud" } },
    { key="strIn",   sec="Drive",  txt="L-R stick",      v=1, list={ "ST","Rud","Ail","Ele","Thr" } },
    { key="revL",    sec="Drive",  txt="L wheel rev",    v=1, list=YN },
    { key="revR",    sec="Drive",  txt="R wheel rev",    v=1, list=YN },
    { key="invSw",   sec="Drive",  txt="Flip sw",        v=flipDef, list=FLIP },
    { key="thrRate", sec="Rates",  txt="Fwd-Back rate",  num=true, val=80,  min=1, max=100 },
    { key="strRate", sec="Rates",  txt="L-R rate",       num=true, val=50,  min=1, max=100 },
    { key="turn",    sec="Rates",  txt="Turn rate",      num=true, val=100, min=1, max=100 },
    { key="thrExpo", sec="Feel",   txt="Fwd-Back expo",  num=true, val=0,   min=0, max=100 },
    { key="strExpo", sec="Feel",   txt="L-R expo",       num=true, val=0,   min=0, max=100 },
    { key="dzT",     sec="Feel",   txt="Fwd-Back dead",  num=true, val=0,   min=0, max=25, zero="No" },
    { key="dzS",     sec="Feel",   txt="L-R dead",       num=true, val=0,   min=0, max=25, zero="No" },
    { key="wpn",     sec="Weapon", txt="Weapon",         num=true, val=100, min=0, max=100, zero="No" },
    { key="wpnSw",   sec="Weapon", txt="Weapon sw",      v=1, list=SW },
    { key="wpnDir",  sec="Weapon", txt="Weapon ESC",     v=1, list={ "Norm", "Rev" } },
  },
}

local function fields() return OPTS[vtype] end

local function fieldOf(key)
  for _, f in ipairs(fields()) do
    if f.key == key then return f end
  end
  return nil
end

local function O(key)
  local f = fieldOf(key)
  if f == nil or f.list == nil then return nil end
  return f.list[f.v]
end

local function isYes(key) return O(key) == "Yes" end

-- only Robot has these rows, and num() answers 100 for a row that does not exist
local function dzVal(key)
  if fieldOf(key) == nil then return 0 end
  return fieldOf(key).val
end

-- percentage fields are plain numbers edited in 1% steps
local function num(key)
  local f = fieldOf(key)
  if f == nil or not f.num then return 100 end
  return f.val
end

-- switch name -> mix source; "No" or anything this radio lacks -> nil
local function swSrc(name)
  return SWSRC[name]
end

local function swName(src)
  for nm, s in pairs(SWSRC) do
    if s == src then return nm end
  end
  return "?"
end

-- the switch one position after the given one, wrapping (front diff lock)
local function swNext(name)
  for i, s in ipairs(SW) do
    if s == name then return SWSRC[SW[(i % #SW) + 1]] end
  end
  return nil
end

local function stSign()
  local r = O("rev")
  if r == "Str" or r == "Rud" or r == "Both" then return -1 end
  return 1
end

local function thSign()
  local r = O("rev")
  if r == "Thr" or r == "Both" then return -1 end
  return 1
end

-- Two jobs sharing one switch is nearly always a mistake. Group by the mix
-- name first, because Invert deliberately drives both drive channels from
-- the same switch and must not count as a clash.
local function findClash(p)
  local byName = {}
  for _, c in ipairs(p) do
    for _, m in ipairs(c.mixes) do
      local src = m[1]
      if ISSW[src] then byName[m[3]] = src end
    end
  end
  local seen, dup = {}, nil
  for _, src in pairs(byName) do
    if seen[src] then dup = src else seen[src] = true end
  end
  return dup
end

-- ---------------------------------------------------------------- build plan
local function buildPlan()
  local st = 100 * stSign()
  local th = 100 * thSign()
  local p = {}
  -- A channel number may be stated outright; left out, it follows the order
  -- rows are added. Car/crawler/boat rely on that order on purpose (an
  -- unused option must not leave a gap), but tank/robot always have two
  -- drive rows, so their channels are pinned and the weapon stays on CH3.
  local function ch(name, mixes, num)
    if num == nil then num = #p + 1 end
    p[#p + 1] = { num = num, name = name, mixes = mixes }
  end

  if vtype == T_CAR then
    ch("Steering", { { IN_ST, st, "Steer" } })
    ch("Throttle", { { IN_TH, th, "Thr" } })
    if isYes("steer2") then ch("Steer 2", { { IN_ST, st, "Steer2" } }) end
    local g = swSrc(O("gearSw"))
    if g then ch("Gearbox", { { g, 100, "Gear" } }) end
    local l = swSrc(O("lightSw"))
    if l then ch("Lights", { { l, 100, "Light" } }) end

  elseif vtype == T_CRAWL then
    ch("Front str", { { IN_ST, st, "FrontSt" } })
    ch("Throttle",  { { IN_TH, th, "Thr" } })
    local r = O("rear")
    if r == "Crab" then
      ch("Rear str", { { IN_ST, st, "RearSt" } })
    elseif r == "Counter" then
      ch("Rear str", { { IN_ST, -st, "RearSt" } })
    end
    local g = swSrc(O("gearSw"))
    if g then ch("Gearbox", { { g, 100, "Gear" } }) end
    local d = O("dlock")
    if d ~= "None" then
      local dr = swSrc(O("dlockSw"))
      if dr then ch("Diff rear", { { dr, 100, "DiffR" } }) end
      if d == "Frt+Rear" then
        local df = swNext(O("dlockSw"))
        if df then ch("Diff frnt", { { df, 100, "DiffF" } }) end
      end
    end
    local w = swSrc(O("winchSw"))
    if w then ch("Winch", { { w, 100, "Winch" } }) end

  elseif vtype == T_TANK or vtype == T_ROBOT then
    local t  = num("turn")
    -- one flag per wheel: a motor soldered backwards is fixed on its own side
    local sL = (O("revL") == "Yes") and -1 or 1
    local sR = (O("revR") == "Yes") and -1 or 1
    local L = { { IN_TH, sL * 100, "Thr" } }
    local R = { { IN_TH, sR * 100, "Thr" } }
    if vtype == T_ROBOT then
      -- Flip (robot upside down): multiply ONLY the throttle line by the
      -- switch, then add Turn after it. Fwd/back must reverse, but left/right
      -- must not: flipping swaps which wheel is on which side as well, so the
      -- steering sense already comes out right. Weight -100 makes the switch's
      -- up position (-100, also where a momentary rests) normal driving.
      local iv = swSrc(O("invSw"))
      if iv then
        L[#L + 1] = { iv, -100, "Flip", MULT }
        R[#R + 1] = { iv, -100, "Flip", MULT }
      end
    end
    L[#L + 1] = { IN_ST,  sL * t, "Turn" }
    R[#R + 1] = { IN_ST, -sR * t, "Turn" }
    ch("Drive L", L, 1)
    ch("Drive R", R, 2)
    if vtype == T_TANK then
      local a = swSrc(O("auxSw"))
      if a then ch("Aux", { { a, 100, "Aux" } }, 3) end
    else
      -- Weapon 0% means no weapon channel at all, rather than a dead 0-weight
      -- mix sitting on a channel the receiver still has to drive.
      local wv = num("wpn")
      local ws = swSrc(O("wpnSw"))
      -- no usable switch on this radio -> no weapon channel at all
      if wv > 0 and ws ~= nil then
        -- Weapon ESC signal polarity -- NOT the direction the weapon spins.
        -- Brands disagree on which end of the channel means idle. Pick Rev when
        -- the ESC idles at the end the switch's safe position would otherwise
        -- send it to, or the weapon spins up the moment the model powers on.
        local pol = 1
        if O("wpnDir") == "Rev" then pol = -1 end
        -- Weapon power scales from the ESC's idle end up to the set percentage,
        -- NOT symmetrically around centre the way a stick rate does. A bare
        -- weight would pull both ends in, so at the switch's off position the
        -- channel would sit above idle and the weapon would never stop. The
        -- offset pins the low end to full idle and only lowers the ceiling.
        ch("Weapon", { { ws, pol * wv, "Weapon", ADD, pol * (wv - 100) } }, 3)
        p[#p].note = O("wpnSw")
      end
    end

  else -- T_BOAT
    if isYes("rud") then ch("Rudder", { { IN_ST, st, "Rudder" } }) end
    if O("mot") == "2" then
      local d = num("diff")
      ch("Motor L", { { IN_TH, th, "Thr" }, { IN_ST,  d, "Diff" } })
      ch("Motor R", { { IN_TH, th, "Thr" }, { IN_ST, -d, "Diff" } })
    else
      ch("Motor", { { IN_TH, th, "Thr" } })
    end
  end
  clashSw = findClash(p)
  return p
end

-- Locate the input line EdgeTX built for a named stick ("TH", "Ele", ...).
local function findInput(want)
  for i = 0, 15 do
    local inp = model.getInput(i, 0)
    if inp ~= nil then
      local nm = inp.inputName
      if nm == nil or nm == "" then nm = inp.name end
      if nm == want then return i end
    end
  end
  return nil
end

local function resolveSrc(src)
  if src == IN_TH then return MIXSRC_FIRST_INPUT + inThr end
  if src == IN_ST then return MIXSRC_FIRST_INPUT + inStr end
  return src
end

-- A stick line holds one curve, so dead zone and expo have to share it: flat
-- through the dead band, then EdgeTX's expo shape, y = x(kx^2 + 1-k), over the
-- travel that is left. An input's curve runs before its weight, so the zone is
-- a percentage of stick travel whatever the rate is.
local function dzCurve(idx, dz, expo)
  local k, x, y, n = expo / 100, {}, {}, 0
  local function pt(sign, u)
    n = n + 1
    x[n] = math.floor(sign * (dz + (100 - dz) * u) + 0.5)
    y[n] = math.floor(sign * 100 * u * (k * u * u + 1 - k) + 0.5)
  end
  for j = 4, 0, -1 do pt(-1, j / 4) end
  for j = 0, 4 do pt(1, j / 4) end
  return model.setCurve(idx, { name = "DZ", type = 1, smooth = false, x = x, y = y }) == 0
end

-- Rate and expo live on the INPUTS, not the mixes. Read back what
-- defaultInputs() just created so the raw stick source never has to be
-- guessed, then rewrite only the weight and curve. If the curve cannot be
-- stored the line keeps plain expo: a line pointing at a missing curve would
-- not drive, and the last screen says the dead zone was not set.
local function setInputRate(idx, rate, expo, curveIdx, dz)
  local inp = model.getInput(idx, 0)
  if inp == nil then return end
  local new = { name = inp.name, source = inp.source, weight = rate }
  if dz > 0 and dzCurve(curveIdx, dz, expo) then
    new.curveType  = CURVE_CUSTOM
    new.curveValue = curveIdx + 1
  else
    dzFailed = dzFailed or dz > 0
    if expo ~= 0 then
      new.curveType  = CURVE_EXPO
      new.curveValue = expo
    end
  end
  model.deleteInput(idx, 0)
  model.insertInput(idx, 0, new)
end

local function applyPlan()
  model.defaultInputs()
  inThr = findInput(O("thrIn")) or 0
  inStr = findInput(O("strIn")) or 1
  setInputRate(inThr, num("thrRate"), num("thrExpo"), 0, dzVal("dzT"))
  setInputRate(inStr, num("strRate"), num("strExpo"), 1, dzVal("dzS"))
  model.deleteMixes()
  for _, c in ipairs(plan) do
    for j, m in ipairs(c.mixes) do
      local mix = { source = resolveSrc(m[1]), weight = m[2], name = m[3] }
      if m[4] ~= nil then mix.multiplex = m[4] end
      if m[5] ~= nil then mix.offset    = m[5] end
      model.insertMix(c.num - 1, j - 1, mix)
    end
  end
end

-- --------------------------------------------------------------------- UI
-- One page per section, so a group of settings is seen whole and nothing scrolls.
local VIS, VALX = 6, 78     -- rows that fit on a 128x64 screen, value column

local function inc(e) return e == EVT_VIRTUAL_INC or e == EVT_VIRTUAL_INC_REPT end
local function dec(e) return e == EVT_VIRTUAL_DEC or e == EVT_VIRTUAL_DEC_REPT end
local function held(e) return e == EVT_VIRTUAL_INC_REPT or e == EVT_VIRTUAL_DEC_REPT end

-- Numeric fields clamp at their limits rather than wrapping -- rolling 100%
-- straight back to 1% while thumbing through rates is nobody's intent.
-- Holding the key steps by 5 so 1..100 stays usable on a two-button radio.
local function bump(o, dir, fast)
  if o.num then
    local step = 1
    if fast then step = 5 end
    o.val = o.val + dir * step
    if o.val > o.max then o.val = o.max end
    if o.val < o.min then o.val = o.min end
  elseif dir > 0 then
    o.v = (o.v % #o.list) + 1
  else
    o.v = ((o.v - 2) % #o.list) + 1
  end
end

local function shown(o)
  if o.num then
    -- a numeric field may name its zero (Weapon 0% reads "No", i.e. no channel)
    if o.zero ~= nil and o.val == 0 then return o.zero end
    return o.val .. "%"
  end
  return o.list[o.v]
end

local function sectionCount(list)
  local n, prev = 0, nil
  for _, o in ipairs(list) do
    if o.sec ~= prev then n, prev = n + 1, o.sec end
  end
  return n
end

local function drawTypeMenu()
  pageCount = sectionCount(fields()) + 2      -- plus this menu and the review
  lcd.clear()
  lcd.drawScreenTitle("SPRC MT12 Wizard", 1, pageCount)
  for i = 0, NTYPES - 1 do
    local fl = 0
    if i == vtype then fl = INVERS end
    lcd.drawText(30, 11 + i * 10, TYPE_NAME[i], fl)
  end
end

-- Selected: the whole row is a bar. Editing: the bar goes and only the value
-- blinks. The bar is drawn first and the text forced over it, so this does not
-- depend on how a filled rectangle combines with what is under it.
local function drawRow(o, y, sel)
  local fl, vf = 0, 0
  if sel and not edit then
    lcd.drawFilledRectangle(0, y - 1, LCD_W, 9, 0)
    fl, vf = INVERS, INVERS
  elseif sel then
    vf = INVERS + BLINK
  end
  lcd.drawText(2, y, o.txt, fl)
  lcd.drawText(VALX, y, shown(o), vf)
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
  lcd.drawScreenTitle(TYPE_NAME[vtype] .. " " .. sec, here + 1, pageCount)
  for r, i in ipairs(view) do
    drawRow(f[i], 1 + r * 9, i - 1 == cursor)
  end
  if #view < VIS then lcd.drawText(2, LCD_H - 8, "Hold ENTER: review", 0) end
end

local function drawReview()
  lcd.clear()
  lcd.drawScreenTitle(TYPE_NAME[vtype] .. " channels", pageCount, pageCount)
  for i, c in ipairs(plan) do
    local col, row
    if i <= 5 then col, row = 2, i else col, row = 66, i - 5 end
    lcd.drawText(col, 2 + row * 9, "CH" .. c.num .. " " .. c.name, 0)
    if c.note ~= nil then lcd.drawText(VALX, 2 + row * 9, c.note, 0) end
  end
  if vtype == T_ROBOT then
    local row = #plan
    local function extra(a, b)
      row = row + 1
      lcd.drawText(2, 2 + row * 9, a, 0)
      lcd.drawText(VALX, 2 + row * 9, b, 0)
    end
    if O("invSw") ~= "No" then extra("Flip sw", O("invSw")) end
    if dzVal("dzT") + dzVal("dzS") > 0 then
      extra("Dead zone", dzVal("dzT") .. "/" .. dzVal("dzS") .. "%")
    end
  end
  local msg = "[Long Enter] apply"
  if clashSw ~= nil then msg = "SW CLASH: " .. swName(clashSw) end
  lcd.drawFilledRectangle(0, LCD_H - 9, LCD_W, 9, 0)
  lcd.drawText(1, LCD_H - 8, msg, INVERS)
end

-- Failsafe lives on the RECEIVER with ELRS. EdgeTX's crossfire driver has no
-- failsafe code at all, so the model's failsafeMode is never read for CRSF --
-- pointing the user at Model Setup would send them to a dead end.
local function drawDone()
  lcd.clear()
  lcd.drawScreenTitle("SPRC MT12 Wizard", pageCount, pageCount)
  lcd.drawText(16, 10, "FAILSAFE!", DBLSIZE + INVERS)
  lcd.drawText(2, 30, "Set it on the RX:", 0)
  lcd.drawText(2, 39, "ELRS Lua or 10.0.0.1", 0)
  lcd.drawText(2, 52, dzFailed and "Dead zone NOT set" or "Then set OUTPUTS", 0)
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
  if event == EVT_VIRTUAL_ENTER_LONG then
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
