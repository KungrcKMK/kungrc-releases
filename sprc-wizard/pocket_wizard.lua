local toolName = "TNS|SPRC Robot Wiz|TNE"

---- #########################################################################
---- # TeamSPRC Robot -- stick radios: Pocket, TX15, TX16S, TX16S MK3.        #
---- # Fighting-robot setup only. The file keeps its Pocket name so a card    #
---- # that already has it is overwritten, not left with two wizards.         #
---- #                                                                       #
---- # Installed alongside the stock aircraft wizard, which this radio still  #
---- # needs, so nothing here touches SCRIPTS/WIZARD.                        #
---- # Car / crawler / tank / boat are stripped out: on the Pocket the only   #
---- # surface models are robots, so there is nothing to choose between.      #
---- # Only the Pocket and EdgeTX 2.10 have been tried on a real radio.       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html                #
---- #                                                                       #
---- # WARNING: applying overwrites ALL inputs and mixes of the CURRENT       #
---- #          model. Always run it on a fresh/empty model slot.             #
---- #          Failsafe is NOT configured here. With CRSF/ELRS the radio     #
---- #          never sends failsafe -- set it on the RECEIVER itself.        #
---- #                                                                       #
---- # NOTE: weights are plain percentages. On EdgeTX 2.10 model.insertMix()  #
---- #       stores `weight` straight into the bitfield with no GVAR          #
---- #       translation, so a gvar written from Lua just overflows           #
---- #       (1256 came back as -792). Set GV weights by hand on MIXES.       #
---- #########################################################################

local ADD, MULT  = 0, 1
local CURVE_EXPO, CURVE_CUSTOM = 1, 3   -- myeeprom.h CurveRefType: DIFF, EXPO, FUNC, CUSTOM

-- Which input carries throttle and steering is NOT fixed. This radio builds
-- Ail/Ele/Thr/Rud, and the team's robots are driven from Ele + Ail (right
-- stick only). The plan carries placeholders; the real index is looked up by
-- name at apply time, so the same file also works if the sticks are changed.
local IN_TH, IN_ST, IN_WPN, IN_ROT = -1, -2, -3, -4
local inThr, inStr, inWpn, inRot = 0, 1, nil, nil

-- Omni and mecanum: one row per wheel, numbered clockwise from the front left. CH3
-- stays free for the weapon. { channel, fwd, strafe, rotate } as stick percentages.
-- Never a wheel on CH5: ELRS sends it as a 2-position arm switch, so the wheel would
-- slam between full forward and full reverse. CH6 is proportional, but only in
-- Full Res 8ch mode, and the review screen says so.
local OMNI4 = { { 1, 100, 100, 100 }, { 2, 100, -100, -100 }, { 4, 100, 100, -100 }, { 6, 100, -100, 100 } }
local WHEELS = { Omni3 = { { 1, 100, 0, 100 }, { 2, -50, 87, 100 }, { 4, -50, -87, 100 } },
                 Omni4 = OMNI4, Mecanum = OMNI4 }

-- Switch mix sources are NOT exported as constants on every build: the
-- MIXSRC_* list is generated per radio (lua_mixsrc.inc), so the switch
-- constants exist on one handset and are nil on the next -- which is exactly
-- how this crashed. getFieldInfo resolves a switch by name on any radio
-- ("sa".."sz"), so ask the radio once, at load, what it actually has.
local SW, SW0, SWSRC, ISSW, SWINFO = {}, { "No" }, {}, {}, {}
if getFieldInfo ~= nil then
  for i = 0, 25 do
    local key = "s" .. string.char(97 + i)
    local fi = getFieldInfo(key)
    -- EdgeTX 2.12 also says how each switch is set up. Type 0 is switched off.
    local si = nil
    if fi ~= nil and fi.id ~= nil and getSwitchInfo ~= nil then si = getSwitchInfo(fi.id) end
    if fi ~= nil and fi.id ~= nil and (si == nil or si.type ~= 0) then
      local nm = string.upper(key)
      SW[#SW + 1]   = nm
      SW0[#SW0 + 1] = nm
      SWSRC[nm]     = fi.id
      ISSW[fi.id]   = true
      SWINFO[nm]    = si
    end
  end
end
if #SW == 0 then SW[1] = "n/a" end

-- Flip multiplies throttle by the switch, so a 3-position switch would cut all
-- throttle in its middle position. Those are left out of the Flip list: EdgeTX
-- 2.12 says which they are, and older firmware gets the radio's stock layout.
-- A colour radio's front buttons can be chosen, but Flip never starts on one.
local _, RADIO = getVersion()
local POS3 = { SB = true, SC = true }
if string.find(RADIO, "tx16", 1, true) then
  POS3 = { SA = true, SB = true, SC = true, SD = true, SE = true, SG = true }
end
local FLIP, flipAt = { "No" }, 1
for _, nm in ipairs(SW) do
  local si, pos3 = SWINFO[nm], POS3[nm]
  if si ~= nil then pos3 = si.type == 3 end
  if not pos3 and nm ~= "n/a" then
    FLIP[#FLIP + 1] = nm
    if flipAt == 1 and not (si ~= nil and si.isCustomisableSwitch) then flipAt = #FLIP end
  end
end

-- The weapon may hang off a switch or off the Thr stick, which on this radio
-- is free (driving uses Ele/Ail) and gives proportional weapon speed.
local WSRC = {}
for _, nm in ipairs(SW) do WSRC[#WSRC + 1] = nm end
WSRC[#WSRC + 1] = "Thr stick"
local YN = { "No", "Yes" }

local page, cursor, pageCount = 1, 0, 1   -- 1 = options, 2 = review
local edit, done = false, false
local plan, clashSw = nil, nil
local dzFailed = false

-- House standard from the SUS304 / RB1500g experiments: SUS304's proven
-- 80% throttle / 50% steering rates, and motors corrected in hardware
-- rather than in the mix so every model file looks the same.
-- `sec` is the page a row sits on. `tank` is its label in Tank drive; `arcade`
-- rows do nothing in Tank drive and are hidden there. `omni` is a row's label on
-- omni and mecanum wheels; `omniOnly` and `noOmni` rows exist on one side of that line.
local OPTS = {
  { key="drive",   sec="Drive",  txt="Drive",          v=1, list={ "Arcade","Tank","Omni3","Omni4","Mecanum" } },
  { key="thrIn",   sec="Drive",  txt="Fwd-Back stick", tank="L wheel stick", v=3, list={ "TH","Thr","Ele","Ail","Rud" } },
  { key="strIn",   sec="Drive",  txt="L-R stick",      tank="R wheel stick", omni="Strafe stick", v=3, list={ "ST","Rud","Ail","Ele","Thr" } },
  { key="rotIn",   sec="Drive",  txt="Rotate stick",   omniOnly=true, v=1, list={ "Rud","Ail","Ele","Thr" } },
  { key="revL",    sec="Drive",  txt="L wheel rev",    noOmni=true, v=1, list=YN },
  { key="revR",    sec="Drive",  txt="R wheel rev",    noOmni=true, v=1, list=YN },
  { key="invSw",   sec="Drive",  txt="Flip sw",        noMecanum=true, v=flipAt, list=FLIP },   -- default on Pocket: SA
  { key="rev1",    sec="Wheels", txt="Wheel 1 rev",    omniOnly=true, v=1, list=YN },
  { key="rev2",    sec="Wheels", txt="Wheel 2 rev",    omniOnly=true, v=1, list=YN },
  { key="rev3",    sec="Wheels", txt="Wheel 3 rev",    omniOnly=true, v=1, list=YN },
  { key="rev4",    sec="Wheels", txt="Wheel 4 rev",    omniOnly=true, wheel4=true, v=1, list=YN },
  { key="thrRate", sec="Rates",  txt="Fwd-Back rate",  tank="Wheel rate", num=true, val=80,  min=1, max=100 },
  { key="strRate", sec="Rates",  txt="L-R rate",       arcade=true, omni="Strafe rate", num=true, val=50,  min=1, max=100 },
  { key="turn",    sec="Rates",  txt="Turn rate",      arcade=true, omni="Rotate rate", num=true, val=100, min=1, max=100 },
  { key="spdSw",   sec="Rates",  txt="Speed sw",       v=1, list=SW0 },
  { key="spdLow",  sec="Rates",  txt="Low speed",      num=true, val=50, min=10, max=100, step=2 },
  { key="thrExpo", sec="Feel",   txt="Fwd-Back expo",  tank="Wheel expo", num=true, val=0, min=0, max=100 },
  { key="strExpo", sec="Feel",   txt="L-R expo",       arcade=true, omni="Strafe expo", num=true, val=0, min=0, max=100 },
  { key="dzT",     sec="Feel",   txt="Fwd-Back dead",  tank="L wheel dead", num=true, val=0, min=0, max=25, zero="No" },
  { key="dzS",     sec="Feel",   txt="L-R dead",       tank="R wheel dead", omni="Strafe dead", num=true, val=0, min=0, max=25, zero="No" },
  { key="wpn",     sec="Weapon", txt="Weapon",         num=true, val=100, min=0, max=100, zero="No" },
  { key="wpnSw",   sec="Weapon", txt="Weapon src",     v=#WSRC, list=WSRC },   -- default: Thr stick
  { key="wpnDir",  sec="Weapon", txt="Weapon ESC",     v=1, list={ "Norm", "Rev" } },
}

local function fieldOf(key)
  for _, f in ipairs(OPTS) do
    if f.key == key then return f end
  end
  return nil
end

local function O(key)
  local f = fieldOf(key)
  if f == nil or f.list == nil then return nil end
  return f.list[f.v]
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

local function tank() return O("drive") == "Tank" end

local function omni() return WHEELS[O("drive")] end

-- Upside down, the rollers of a mecanum wheel lean the other way: X becomes O and
-- strafing stops working, so Flip is an omni and two-wheel idea only.
local function flipName()
  if O("drive") == "Mecanum" then return "No" end
  return O("invSw")
end

-- Tank drive needs both vertical sticks, and Thr is one of them, so the weapon
-- moves off that stick and onto a switch (SB: off, half, full).
local function driveDefaults()
  local t = tank()
  fieldOf("thrIn").v = t and 2 or 3                 -- Thr / Ele
  fieldOf("strIn").v = t and 4 or 3                 -- Ele / Ail
  fieldOf("wpnSw").v = t and math.min(2, #WSRC) or #WSRC
end

local function swName(src)
  for nm, s in pairs(SWSRC) do
    if s == src then return nm end
  end
  return "?"
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
  local seen = {}
  for _, src in pairs(byName) do
    if seen[src] then return "SW CLASH: " .. swName(src) end
    seen[src] = true
  end
  -- the stick can be double-booked too: weapon on Thr while Thr also drives
  if O("wpnSw") == "Thr stick" and (O("thrIn") == "Thr" or O("strIn") == "Thr"
                                    or (omni() and O("rotIn") == "Thr")) then
    return "CLASH: Thr stick"
  end
  return nil
end

-- Speed switch: up is the full rate, down is Low speed. It scales the whole wheel
-- channel, last in line, and weight and offset make the switch read 1 up and Low speed
-- down. Low speed moves in steps of 2 so the weight stays a whole number.
local function speedLine()
  local sp = swSrc(O("spdSw"))
  if sp == nil then return nil end
  local w = math.floor((num("spdLow") - 100) / 2)
  return { sp, w, "Speed", MULT, 100 + w }
end

local function speeded(m)
  local s = speedLine()
  if s ~= nil then m[#m + 1] = s end
  return m
end

-- ---------------------------------------------------------------- build plan
local function buildPlan()
  local p = {}
  -- Channel numbers are stated, not inferred from the order things were
  -- added: the weapon belongs on CH3 whatever happens to the drive rows.
  local function ch(num, name, mixes)
    p[#p + 1] = { num = num, name = name, mixes = mixes }
  end

  local t  = num("turn")
  local tk = tank()
  -- one flag per wheel: a motor soldered backwards is fixed on its own side
  local sL = (O("revL") == "Yes") and -1 or 1
  local sR = (O("revR") == "Yes") and -1 or 1
  -- Flip (robot upside down): multiply ONLY the fwd/back part by the switch,
  -- then add the turn part after it. Fwd/back must reverse, but left/right must
  -- not: flipping swaps which wheel is on which side as well, so the steering
  -- sense already comes out right. Weight -100 makes the switch's up position
  -- (-100, also where a momentary rests) normal driving.
  -- Tank drive is the same split written with sticks: fwd/back is the sticks'
  -- half sum, turn their half difference. Those add back to one stick per wheel.
  local iv = swSrc(flipName())
  local function side(s, dir)        -- dir: +1 left wheel, -1 right wheel
    local m
    if tk then
      m = { { IN_TH, s * 50, "Thr" }, { IN_ST, s * 50, "Thr" } }
    else
      m = { { IN_TH, s * 100, "Thr" } }
    end
    if iv then m[#m + 1] = { iv, -100, "Flip", MULT } end
    if tk then
      m[#m + 1] = { IN_TH,  dir * s * 50, "Turn" }
      m[#m + 1] = { IN_ST, -dir * s * 50, "Turn" }
    else
      m[#m + 1] = { IN_ST, dir * s * t, "Turn" }
    end
    return speeded(m)
  end
  if omni() then
    -- Same split as above: only fwd/back goes through Flip, strafe and rotate come
    -- after it. An omni wheel's force flips with the side it touches the floor on.
    for i, w in ipairs(omni()) do
      local s = (O("rev" .. i) == "Yes") and -1 or 1
      local m = { { IN_TH, s * w[2], "Fwd" } }
      if iv then m[#m + 1] = { iv, -100, "Flip", MULT } end
      if w[3] ~= 0 then m[#m + 1] = { IN_ST, s * w[3], "Strf" } end
      m[#m + 1] = { IN_ROT, s * w[4], "Rot" }
      ch(w[1], "Wheel " .. i, speeded(m))
      p[#p].quiet = true
    end
  else
    ch(1, "Drive L", side(sL, 1))
    ch(2, "Drive R", side(sR, -1))
  end

  -- Weapon 0% means no weapon channel at all, rather than a dead 0-weight
  -- mix sitting on a channel the receiver still has to drive.
  local wv = num("wpn")
  local ws
  if O("wpnSw") == "Thr stick" then ws = IN_WPN else ws = swSrc(O("wpnSw")) end
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
    -- No arm mix: the weapon channel is left bare on purpose so the arming
    -- interlock is built by hand, the way the team already does it.
    ch(3, "Weapon", { { ws, pol * wv, "Weapon", ADD, pol * (wv - 100) } })
    p[#p].note = O("wpnSw")
  end

  clashSw = findClash(p)
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
  return nil
end

local function resolveSrc(src)
  if src == IN_TH then return MIXSRC_FIRST_INPUT + inThr end
  if src == IN_ST then return MIXSRC_FIRST_INPUT + inStr end
  if src == IN_ROT then return MIXSRC_FIRST_INPUT + inRot end
  if src == IN_WPN then
    if inWpn == nil then return nil end
    return MIXSRC_FIRST_INPUT + inWpn
  end
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
  inRot = omni() and findInput(O("rotIn")) or 3
  inWpn = findInput("Thr")          -- may be nil: then no weapon channel
  setInputRate(inThr, num("thrRate"), num("thrExpo"), 0, num("dzT"))
  if tank() then
    setInputRate(inStr, num("thrRate"), num("thrExpo"), 1, num("dzS"))
  else
    setInputRate(inStr, num("strRate"), num("strExpo"), 1, num("dzS"))
  end
  if omni() then setInputRate(inRot, num("turn"), 0, 2, 0) end
  model.deleteMixes()
  for _, c in ipairs(plan) do
    for j, m in ipairs(c.mixes) do
      local mix = { source = resolveSrc(m[1]), weight = m[2], name = m[3] }
      if m[4] ~= nil then mix.multiplex = m[4] end
      if m[5] ~= nil then mix.offset    = m[5] end
      if mix.source ~= nil then model.insertMix(c.num - 1, j - 1, mix) end
    end
  end
end

-- --------------------------------------------------------------------- UI
-- One page per section, so a group of settings is seen whole and nothing scrolls.
-- Every screen is laid out on a mono radio's 128x64 grid and a colour radio scales
-- that grid up. Colour EdgeTX has no drawScreenTitle, but a flags-0 rectangle and
-- the box behind INVERS text come out the same colour there, whatever the theme,
-- so a bar still reads as one solid row.
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

-- Numeric fields clamp at their limits rather than wrapping -- rolling 100%
-- straight back to 1% while thumbing through rates is nobody's intent.
-- Holding the key steps by 5 so 1..100 stays usable on a two-button radio.
local function bump(o, dir, fast)
  if o.num then
    local step = o.step or 1
    if fast then step = step * 5 end
    o.val = o.val + dir * step
    if o.val > o.max then o.val = o.max end
    if o.val < o.min then o.val = o.min end
  elseif dir > 0 then
    o.v = (o.v % #o.list) + 1
  else
    o.v = ((o.v - 2) % #o.list) + 1
  end
  if o.key == "drive" then driveDefaults() end
end

local function shown(o)
  if o.num then
    -- a numeric field may name its zero (Weapon 0% reads "No", i.e. no channel)
    if o.zero ~= nil and o.val == 0 then return o.zero end
    return o.val .. "%"
  end
  return o.list[o.v]
end

local function rows()
  local t = {}
  for _, o in ipairs(OPTS) do
    local hide = (o.arcade and tank()) or (o.omniOnly and not omni()) or (o.noOmni and omni())
              or (o.wheel4 and O("drive") == "Omni3") or (o.noMecanum and O("drive") == "Mecanum")
    if not hide then t[#t + 1] = o end
  end
  return t
end

local function label(o)
  if o.tank ~= nil and tank() then return o.tank end
  if o.omni ~= nil and omni() then return o.omni end
  return o.txt
end

-- Selected: the whole row is a bar. Editing: the bar goes and only the value
-- blinks. The bar is drawn first and the text forced over it, so this does not
-- depend on how a filled rectangle combines with what is under it.
local function drawRow(o, y, sel)
  local fl, vf = 0, 0
  if sel and not edit then
    bar(y)
    fl, vf = INVERS, INVERS
  elseif sel then
    vf = INVERS + BLINK
  end
  text(2, y, label(o), fl)
  text(VALX, y, shown(o), vf)
end

local function drawOptions()
  local list = rows()
  if cursor >= #list then cursor = #list - 1 end
  local sec, prev = list[cursor + 1].sec, nil
  local secs, here, view = 0, 0, {}
  for i, o in ipairs(list) do
    if o.sec ~= prev then secs, prev = secs + 1, o.sec end
    if o.sec == sec then here = secs ; view[#view + 1] = i end
  end
  pageCount = secs + 1              -- the review page
  lcd.clear()
  title("Robot " .. sec, here, pageCount)
  for r, i in ipairs(view) do
    drawRow(list[i], 1 + r * 9, i - 1 == cursor)
  end
  if #view < VIS then text(2, 56, "Hold ENTER: review", 0) end
  return list
end

local function drawReview()
  lcd.clear()
  title((O("drive") == "Arcade" and "Robot" or O("drive")) .. " channels", pageCount, pageCount)
  local y = 2
  local function line(a, b)
    y = y + 9
    text(2, y, a, 0)
    if b ~= nil then text(VALX, y, b, 0) end
  end
  if omni() then line(O("drive") == "Omni3" and "CH1 2 4 wheels" or "CH1 2 4 6 wheels", nil) end
  for _, c in ipairs(plan) do
    if not c.quiet then line("CH" .. c.num .. " " .. c.name, c.note) end
  end
  local flip, speed = flipName(), O("spdSw")
  if flip ~= "No" and speed ~= "No" then
    line("Flip Speed", flip .. " " .. speed)      -- one row: the last row of the screen is the bar
  elseif flip ~= "No" then
    line("Flip sw", flip)
  elseif speed ~= "No" then
    line("Speed sw", speed)
  end
  if num("dzT") + num("dzS") > 0 then line("Dead zone", num("dzT") .. "/" .. num("dzS") .. "%") end
  if omni() and O("drive") ~= "Omni3" then line("ELRS mode", "8ch Full") end
  bar(56)
  text(1, 56, clashSw or "[Long Enter] apply", INVERS)
end

-- Failsafe lives on the RECEIVER with ELRS. EdgeTX's crossfire driver has no
-- failsafe code at all, so the model's failsafeMode is never read for CRSF --
-- pointing the user at Model Setup would send them to a dead end.
local function drawDone()
  lcd.clear()
  title("SPRC Robot Wizard", pageCount, pageCount)
  text(16, 10, "FAILSAFE!", INVERS, true)
  text(2, 30, "Set it on the RX:", 0)
  text(2, 39, "ELRS Lua or 10.0.0.1", 0)
  text(2, 52, dzFailed and "Dead zone NOT set" or "Then set OUTPUTS", 0)
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
    local list = drawOptions()
    if event == EVT_VIRTUAL_ENTER_LONG then
      plan = buildPlan()
      page = 2
    elseif event == EVT_VIRTUAL_EXIT then
      if edit then edit = false else return 2 end
    elseif event == EVT_VIRTUAL_ENTER then
      edit = not edit
    elseif inc(event) then
      if edit then
        bump(list[cursor + 1], 1, held(event))
      else
        cursor = (cursor + 1) % #list
      end
    elseif dec(event) then
      if edit then
        bump(list[cursor + 1], -1, held(event))
      else
        cursor = (cursor - 1 + #list) % #list
      end
    end
    return 0
  end

  drawReview()
  if event == EVT_VIRTUAL_ENTER_LONG then
    applyPlan()
    done = true
  elseif event == EVT_VIRTUAL_EXIT then
    page = 1
  end
  return 0
end

local function init()
end

return { init = init, run = run }
