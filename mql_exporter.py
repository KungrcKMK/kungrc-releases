"""
mql_exporter.py — Export current profile settings into MQL5 source template
แล้ว compile เป็น .ex5 (ถ้าหา MetaEditor เจอ)

ข้อมูลที่ถูกสงวน (ไม่ export):
  - InpTelegramBotToken  → ""
  - InpTelegramChatId    → ""
"""

import os
import re
import json
import subprocess
from datetime import datetime

import config
import settings_manager as sm
import paths

# ── ตำแหน่ง MetaEditor ที่พบบ่อย ─────────────────────────────────
_METAEDITOR_PATHS = [
    r"C:\Program Files\MetaTrader 5\metaeditor64.exe",
    r"C:\Program Files (x86)\MetaTrader 5\metaeditor64.exe",
    r"C:\Program Files\MetaTrader 5 EXNESS\metaeditor64.exe",
    r"C:\Program Files\MetaTrader 5 ICMarkets\metaeditor64.exe",
    r"C:\Program Files\MetaTrader 5 FBS\metaeditor64.exe",
    r"C:\Program Files\MetaTrader 5 XM\metaeditor64.exe",
]

# ── Mapping: Python config key → (MQL param name, type) ──────────
_FIELD_MAP = {
    # General
    "MAGIC_NUMBER":          ("InpMagicNumber",              "long"),
    "SLIPPAGE_POINTS":       ("InpSlippagePoints",           "int"),
    "VERBOSE_LOGS":          ("InpVerboseLogs",              "bool"),
    "ENABLE_AUTO_ENTRY":     ("InpEnableAutoEntry",          "bool"),
    # Capital / Lot
    "BASE_LOT":              ("InpBaseLotAtReference",       "double"),
    "LOT_MULTIPLIER":        ("InpLotMultiplier",            "double"),
    "MIN_LOT":               ("InpMinLot",                   "double"),
    "MAX_LOT":               ("InpMaxLot",                   "double"),
    "MAX_ORDERS_PER_SIDE":   ("InpMaxOrdersPerSide",         "int"),
    # Entry
    "OPEN_AT_STARTUP_IF_FLAT":  ("InpOpenAtStartupIfFlat",  "bool"),
    "STARTUP_GATE_SECONDS":  ("InpStartupGateSeconds",       "int"),
    "ONLY_OPEN_ON_NEW_BAR":  ("InpOnlyOpenOnNewBar",         "bool"),
    "ENTRY_COOLDOWN":        ("InpEntryCooldownSeconds",     "int"),
    "RECOVERY_COOLDOWN":     ("InpRecoveryCooldownSeconds",  "int"),
    "EMA_FAST_PERIOD":       ("InpEmaFastPeriod",            "int"),
    "EMA_SLOW_PERIOD":       ("InpEmaSlowPeriod",            "int"),
    "ATR_PERIOD":            ("InpATRPeriod",                "int"),
    "ENTRY_MIN_SCORE":       ("InpMinSignalScore",           "int"),
    "STARTUP_MIN_SCORE":     ("InpStartupMinSignalScore",    "int"),
    # RSI Filter
    "ENABLE_RSI_FILTER":     ("InpEnableRSIFilter",          "bool"),
    "RSI_PERIOD":            ("InpRSIPeriod",                "int"),
    "RSI_OVERBOUGHT":        ("InpRSIOverboughtLevel",       "double"),
    "RSI_OVERSOLD":          ("InpRSIOversoldLevel",         "double"),
    # Recovery / Grid
    "ALLOW_RECOVERY":        ("InpAllowRecovery",            "bool"),
    "BASE_GRID_POINTS":      ("InpBaseGridPoints",           "double"),
    "ATR_GRID_MULTIPLIER":   ("InpATRGridMultiplier",        "double"),
    "GRID_EXPAND_PCT":       ("InpGridExpandPercent",        "double"),
    # Smart Recovery
    "ENABLE_SMART_RECOVERY": ("InpEnableSmartRecovery",      "bool"),
    "ENABLE_MAX_GRID_DD":    ("InpEnableMaxGridDD",          "bool"),
    "MAX_GRID_DD_PERCENT":   ("InpMaxGridDDPercent",         "double"),
    # Basket / Profit
    "BASKET_TARGET_MONEY":   ("InpBasketBaseTargetMoney",    "double"),
    "BASKET_TRAIL_MONEY":    ("InpBasketPullbackMoney",      "double"),
    # Total Profit
    "TOTAL_PROFIT_TARGET":   ("InpTotalProfitTarget",        "double"),
    "TOTAL_PROFIT_TRAIL":    ("InpTotalProfitPullback",      "double"),
    # Bad Trade
    "CUT_LOSS_PER_POS":      ("InpCutLossPerPosAmount",      "double"),
    "CUT_LOSS_TOTAL":        ("InpCutLossTotalAmount",       "double"),
    "CUT_LOSS_TIME_HOURS":   ("InpCutLossTimeHours",         "int"),
    # Break-Even
    "ENABLE_BREAK_EVEN":     ("InpEnableBreakEven",          "bool"),
    "BREAK_EVEN_TRIGGER_PTS":("InpBreakEvenTriggerPoints",  "double"),
    "BREAK_EVEN_BUFFER_PTS": ("InpBreakEvenBufferPoints",   "double"),
    # Partial Close
    "ENABLE_PARTIAL_CLOSE":  ("InpEnablePartialClose",       "bool"),
    "PARTIAL_CLOSE_TRIGGER": ("InpPartialCloseTriggerPoints","double"),
    "PARTIAL_CLOSE_PERCENT": ("InpPartialClosePercent",      "double"),
    # Account SL / Daily Loss / Max Pos
    "ENABLE_ACCOUNT_SL":     ("InpEnableAccountSL",          "bool"),
    "ACCOUNT_SL_PERCENT":    ("InpAccountSLPercent",         "double"),
    "ENABLE_MAX_DAILY_LOSS": ("InpEnableMaxDailyLoss",       "bool"),
    "MAX_DAILY_LOSS_AMOUNT": ("InpMaxDailyLossAmount",       "double"),
    "ENABLE_MAX_TOTAL_POS":  ("InpEnableMaxTotalPositions",  "bool"),
    "MAX_TOTAL_POSITIONS":   ("InpMaxTotalPositions",        "int"),
    # Hedging
    "ENABLE_HEDGING":        ("InpEnableHedging",            "bool"),
    "HEDGE_TRIGGER_LOSS":    ("InpHedgeTriggerLoss",         "double"),
    "HEDGE_LOT_MULTIPLIER":  ("InpHedgeLotMultiplier",       "double"),
    # Side Guard (direct values — enum derived separately)
    "SIDE_GUARD_LOSS_USD":   ("InpSideGuardLossUSD",         "double"),
    "SIDE_GUARD_DD_PCT":     ("InpSideGuardDDPct",           "double"),
    "SIDE_GUARD_IMBALANCE_LV":("InpSideGuardImbalanceLv",    "int"),
    "SIDE_GUARD_RESUME_RATIO":("InpSideGuardResumeRatio",    "double"),
    # Schedule
    "USE_SCHEDULE":          ("InpUseSchedule",              "bool"),
    "TRADE_START_HOUR":      ("InpTradeStartHour",           "int"),
    "TRADE_START_MIN":       ("InpTradeStartMinute",         "int"),
    "TRADE_STOP_HOUR":       ("InpTradeStopHour",            "int"),
    "TRADE_STOP_MIN":        ("InpTradeStopMinute",          "int"),
    "AUTO_START_NEXT_DAY":   ("InpAutoStartNextDay",         "bool"),
    # Session
    "SERVER_GMT_OFFSET":     ("InpServerGMTOffset",          "int"),
    "ENABLE_SESSION_FILTER": ("InpEnableSessionFilter",      "bool"),
    "ALLOW_SYDNEY":          ("InpAllowSydney",              "bool"),
    "ALLOW_TOKYO":           ("InpAllowTokyo",               "bool"),
    "ALLOW_LONDON":          ("InpAllowLondon",              "bool"),
    "ALLOW_NEW_YORK":        ("InpAllowNewYork",             "bool"),
    "ALLOW_OVERLAP_TK_LN":   ("InpAllowOverlapTkLn",         "bool"),
    "ALLOW_OVERLAP_LN_NY":   ("InpAllowOverlapLnNY",         "bool"),
    "BLOCK_LOW_LIQUIDITY":   ("InpBlockLowLiquidity",        "bool"),
    "ENABLE_SESSION_RISK":   ("InpEnableSessionRisk",        "bool"),
    "SYDNEY_RISK_PCT":       ("InpSydneyRiskPct",            "double"),
    "TOKYO_RISK_PCT":        ("InpTokyoRiskPct",             "double"),
    "LONDON_RISK_PCT":       ("InpLondonRiskPct",            "double"),
    "NEW_YORK_RISK_PCT":     ("InpNewYorkRiskPct",           "double"),
    "OVERLAP_RISK_PCT":      ("InpOverlapRiskPct",           "double"),
    # Telegram — เปิด/ปิดได้ แต่ token/chatid ถูกสงวนเสมอ
    "ENABLE_TELEGRAM":       ("InpEnableTelegramAlert",      "bool"),
}


def _fmt_value(val, typ: str) -> str:
    """แปลง Python value → string ที่ถูก syntax MQL"""
    if typ == "bool":
        return "true" if val else "false"
    if typ in ("int", "long"):
        return str(int(val))
    if typ == "double":
        v = float(val)
        s = f"{v:.8f}".rstrip("0")
        if s.endswith("."):
            s += "0"
        return s
    return str(val)


def _replace_param(source: str, param: str, value: str) -> str:
    """แทนที่ค่า default ของ MQL input parameter"""
    pattern = rf'(input\s+\S+\s+{re.escape(param)}\s*=\s*)([^;]+?)((?:\s*//[^\n]*)?\s*;)'
    repl    = rf'\g<1>{value}\3'
    result, n = re.subn(pattern, source, repl)
    if n == 0:
        result, _ = re.subn(pattern, repl, source)
    return result


def _replace_param(source: str, param: str, value: str) -> str:
    pattern = rf'(input\s+\S+\s+{re.escape(param)}\s*=\s*)([^;]+?)((?:\s*//[^\n]*)?\s*;)'
    repl    = rf'\g<1>{value}\3'
    new_src, _ = re.subn(pattern, repl, source)
    return new_src


def _map_side_guard(cfg: dict) -> str:
    if not cfg.get("ENABLE_SIDE_GUARD", False):
        return "GUARD_OFF"
    by_loss = cfg.get("SIDE_GUARD_BY_LOSS", False)
    by_dd   = cfg.get("SIDE_GUARD_BY_DD",   False)
    by_imb  = cfg.get("SIDE_GUARD_BY_IMBALANCE", False)
    count   = sum([by_loss, by_dd, by_imb])
    if count >= 2:
        return "GUARD_ALL"
    if by_loss:
        return "GUARD_LOSS_USD"
    if by_dd:
        return "GUARD_DD_PCT"
    if by_imb:
        return "GUARD_IMBALANCE"
    return "GUARD_OFF"


def _map_total_profit(mode: int) -> str:
    return {0: "TOTAL_PROFIT_OFF", 1: "TOTAL_PROFIT_SIMPLE",
            2: "TOTAL_PROFIT_TRAIL", 3: "TOTAL_PROFIT_TRAIL"}.get(mode, "TOTAL_PROFIT_OFF")


def _map_badtrade(mode: int) -> str:
    return {0: "BADTRADE_OFF", 1: "BADTRADE_PER_POS", 2: "BADTRADE_TOTAL",
            3: "BADTRADE_TIME", 4: "BADTRADE_ALL"}.get(mode, "BADTRADE_OFF")


def find_metaeditor() -> str | None:
    for p in _METAEDITOR_PATHS:
        if os.path.exists(p):
            return p
    return None


def get_template_path() -> str:
    """หา template .mq5 — ข้าง exe (frozen) หรือข้าง script"""
    import sys
    base = os.path.dirname(sys.executable) if getattr(sys, "frozen", False) \
           else os.path.dirname(os.path.abspath(__file__))
    return os.path.join(base, "mql_template_mt5.mq5")


def export_mt5(output_path: str) -> tuple[bool, str]:
    """
    อ่าน template .mq5 → inject ค่าจาก config ปัจจุบัน → เขียน output_path
    คืน (success, message)
    """
    tpl = get_template_path()
    if not os.path.exists(tpl):
        return False, f"ไม่พบ template: {tpl}"

    try:
        with open(tpl, encoding="utf-8") as f:
            src = f.read()
    except Exception as e:
        return False, f"อ่าน template ไม่ได้: {e}"

    # ── รวม config ปัจจุบัน ────────────────────────────────────────
    cfg: dict = {k: getattr(config, k) for k in dir(config)
                 if not k.startswith("_") and isinstance(getattr(config, k),
                 (bool, int, float, str))}

    # ── inject ทีละ param ──────────────────────────────────────────
    for py_key, (mql_param, typ) in _FIELD_MAP.items():
        if py_key not in cfg:
            continue
        val_str = _fmt_value(cfg[py_key], typ)
        src = _replace_param(src, mql_param, val_str)

    # ── Enum fields ────────────────────────────────────────────────
    src = _replace_param(src, "InpSideGuardMode",   _map_side_guard(cfg))
    src = _replace_param(src, "InpTotalProfitMode",
                         _map_total_profit(int(cfg.get("TOTAL_PROFIT_MODE", 0))))
    src = _replace_param(src, "InpBadTradeMode",
                         _map_badtrade(int(cfg.get("BADTRADE_MODE", 0))))

    # ── สงวน: ลบ TG credentials ───────────────────────────────────
    src = _replace_param(src, "InpTelegramBotToken", '""')
    src = _replace_param(src, "InpTelegramChatId",   '""')

    # ── เพิ่ม header comment ───────────────────────────────────────
    profile = sm.get_profile().upper()
    stamp   = datetime.now().strftime("%Y-%m-%d %H:%M")
    header  = (f"// [EXPORTED] Profile: {profile}  |  "
               f"Symbol: {cfg.get('SYMBOL','?')}  |  "
               f"Generated: {stamp}\n"
               f"// TelegramToken/ChatID have been removed. Fill in manually if needed.\n")
    src = src.replace("//+--", header + "//+--", 1)

    try:
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(src)
    except Exception as e:
        return False, f"เขียนไฟล์ไม่ได้: {e}"

    return True, output_path


def compile_mt5(mq5_path: str) -> tuple[bool, str]:
    """เรียก MetaEditor compile .mq5 → .ex5  คืน (success, message)"""
    editor = find_metaeditor()
    if not editor:
        return False, "ไม่พบ MetaEditor — ต้อง compile เองใน MetaTrader"

    log_path = mq5_path.replace(".mq5", "_compile.log")
    try:
        result = subprocess.run(
            [editor, f'/compile:{mq5_path}', f'/log:{log_path}'],
            timeout=60, capture_output=True
        )
        ex5 = mq5_path.replace(".mq5", ".ex5")
        if os.path.exists(ex5):
            return True, ex5
        # อ่าน log ดูข้อผิดพลาด
        log_txt = ""
        if os.path.exists(log_path):
            with open(log_path, encoding="utf-16-le", errors="replace") as f:
                log_txt = f.read()[-500:]
        return False, f"Compile ไม่สำเร็จ:\n{log_txt}"
    except subprocess.TimeoutExpired:
        return False, "MetaEditor timeout"
    except Exception as e:
        return False, f"Compile error: {e}"


def export_set_file(output_path: str) -> tuple[bool, str]:
    """Export .set file (MetaTrader settings preset) — ใช้ได้ทั้ง MT4/MT5"""
    cfg: dict = {k: getattr(config, k) for k in dir(config)
                 if not k.startswith("_") and isinstance(getattr(config, k),
                 (bool, int, float, str))}

    lines = [
        f"; KungRC EA — Profile: {sm.get_profile().upper()}",
        f"; Symbol: {cfg.get('SYMBOL','?')}  Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        "",
    ]
    for py_key, (mql_param, typ) in _FIELD_MAP.items():
        if py_key not in cfg:
            continue
        val = cfg[py_key]
        if typ == "bool":
            lines.append(f"{mql_param}={1 if val else 0}")
        elif typ == "double":
            lines.append(f"{mql_param}={float(val):.8f}".rstrip("0").rstrip(".") + "0"
                         if "." not in f"{float(val):.8f}".rstrip("0") else
                         f"{mql_param}={float(val):.8f}".rstrip("0"))
        else:
            lines.append(f"{mql_param}={int(val)}")

    # Enums
    lines.append(f"InpSideGuardMode={_map_side_guard(cfg)}")
    lines.append(f"InpTotalProfitMode={_map_total_profit(int(cfg.get('TOTAL_PROFIT_MODE',0)))}")
    lines.append(f"InpBadTradeMode={_map_badtrade(int(cfg.get('BADTRADE_MODE',0)))}")
    # สงวน TG credentials
    lines += ['InpTelegramBotToken=""', 'InpTelegramChatId=""']

    try:
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        with open(output_path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
    except Exception as e:
        return False, f"เขียนไฟล์ไม่ได้: {e}"

    return True, output_path
