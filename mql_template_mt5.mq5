//+------------------------------------------------------------------+
//| KungRC_v1_4_0.mq5                                               |
//| Version: 1.400                                                   |
//| Edition: Full Feature Edition                                    |
//| Changes:                                                         |
//|  - Toggle RUN/PAUSE button (single button)                      |
//|  - Total Profit Close (BUY+SELL) mode A/B/C                     |
//|  - Bad Trade Close mode A/B/C/D/E                               |
//|  - Break-Even, Partial Close                                     |
//|  - Account Stop Loss, Max Daily Loss, Max Total Positions        |
//|  - RSI Filter, Hedging Mode                                      |
//|  - Max Grid Drawdown, Smart Recovery                             |
//|  - HUD: Max DD Today + Grid Level                               |
//|  - Telegram: text Entry/Exit/Recovery; photo DD+Daily+AccSL     |
//|  - Fixed WebRequest (7-param, proper headers)                    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, KUNGRC"
#property version   "1.400"
#property strict
#include <Trade/Trade.mqh>

#define APP_NAME    "CHATIMU_EA"
#define APP_VERSION "v1.4.0"

//========================= ENUMS ==================================//
enum ENUM_ENTRY_MODE
{
   ENTRY_AUTO_HYBRID = 0,  // Auto Hybrid (Both)
   ENTRY_BUY_ONLY    = 1,  // Buy Only
   ENTRY_SELL_ONLY   = 2   // Sell Only
};
enum ENUM_TUNE_PROFILE
{
   PROFILE_A_BALANCED_ATTACK = 0,  // A: Balanced Attack
   PROFILE_B_FASTER_FIRE     = 1,  // B: Faster Fire
   PROFILE_C_STRICTER        = 2   // C: Stricter
};
enum ENUM_TOTAL_PROFIT_MODE
{
   TOTAL_PROFIT_OFF    = 0,  // C: Disabled (Default)
   TOTAL_PROFIT_SIMPLE = 1,  // A: Close immediately at target
   TOTAL_PROFIT_TRAIL  = 2   // B: Track peak, close on pullback
};
enum ENUM_BADTRADE_MODE
{
   BADTRADE_OFF     = 0,  // E: Disabled (Default)
   BADTRADE_PER_POS = 1,  // A: Cut Loss per position ($)
   BADTRADE_TOTAL   = 2,  // B: Cut Loss total ($)
   BADTRADE_TIME    = 3,  // C: Time-based close (hours)
   BADTRADE_ALL     = 4   // D: All modes combined
};
enum ENUM_SIDE_GUARD_MODE
{
   GUARD_OFF       = 0,  // ปิด (Default)
   GUARD_LOSS_USD  = 1,  // A: หยุดฝั่งที่ขาดทุนเกิน $X
   GUARD_DD_PCT    = 2,  // B: หยุดฝั่งที่ขาดทุนเกิน X% ของ Equity
   GUARD_IMBALANCE = 3,  // C: หยุดฝั่งที่มีไม้มากกว่าอีกฝั่ง N ไม้
   GUARD_ALL       = 4   // A+B+C: ทุกเงื่อนไข
};

//========================= INPUTS =================================//
input string TH_GEN_01 = "========== General ==========";
input long   InpMagicNumber             = 26032036;
input bool   InpEnableAutoEntry         = true;
input ENUM_ENTRY_MODE InpEntryMode      = ENTRY_AUTO_HYBRID;
input int    InpSlippagePoints          = 30;
input int    InpMaxSpreadPoints         = 700;
input bool   InpVerboseLogs             = true;

input string TH_PROFILE_01B = "========== Entry Score Tuning ==========";
input ENUM_TUNE_PROFILE InpTuneProfile  = PROFILE_A_BALANCED_ATTACK;
input bool   InpUseTuningProfile        = true;

input string TH_MONEY_02 = "========== Capital / Position Sizing ==========";
input double InpCapitalReferenceUSD          = 2000.0;
input double InpCapitalReserveForRecoveryPct = 55.0;
input double InpBaseLotAtReference           = 0.01;
input double InpMinLot                       = 0.01;
input double InpMaxLot                       = 0.10;
input double InpLotMultiplier                = 1.18;
input int    InpMaxOrdersPerSide             = 4;

input string TH_ENTRY_03 = "========== Entry Tightening ==========";
input bool   InpOpenAtStartupIfFlat     = true;
input int    InpStartupGateSeconds      = 20;
input bool   InpOnlyOpenOnNewBar        = true;
input int    InpEntryCooldownSeconds    = 15;
input int    InpRecoveryCooldownSeconds = 25;
input int    InpEmaFastPeriod           = 20;
input int    InpEmaSlowPeriod           = 50;
input int    InpATRPeriod               = 14;
input double InpMinEmaSeparationPoints  = 60.0;
input double InpStrongEmaSeparationPoints = 120.0;
input double InpMinBodyPoints           = 80.0;
input double InpStrongBodyPoints        = 160.0;
input double InpATRMinPoints            = 120.0;
input double InpATRMaxPoints            = 3500.0;
input int    InpMinSignalScore          = 4;
input int    InpStartupMinSignalScore   = 5;

input string TH_RSI = "========== RSI Filter (Default: OFF) ==========";
input bool   InpEnableRSIFilter         = false;   // Enable RSI Filter
input int    InpRSIPeriod               = 14;      // RSI Period
input double InpRSIOverboughtLevel      = 70.0;    // Block BUY if RSI >= this
input double InpRSIOversoldLevel        = 30.0;    // Block SELL if RSI <= this

input string TH_RECOVERY_04 = "========== Recovery / Grid ==========";
input bool   InpAllowRecovery               = true;
input double InpBaseGridPoints              = 900.0;
input double InpATRGridMultiplier           = 0.90;
input double InpGridExpandPercent           = 22.0;
input int    InpNoRecoveryBeforeCloseMinutes = 45;

input string TH_SMART_REC = "========== Smart Recovery (Default: OFF) ==========";
input bool   InpEnableSmartRecovery     = false;   // Require signal to confirm recovery dir
input bool   InpEnableMaxGridDD         = false;   // Stop recovery when DD exceeds %
input double InpMaxGridDDPercent        = 25.0;    // Max DD % for recovery

input string TH_EXIT_05 = "========== Profit Hold / Exit ==========";
input bool   InpEnableSingleProfitHold   = true;
input double InpSingleMinProfitMoney     = 1.50;
input double InpSingleArmProfitMoney     = 2.20;
input double InpSinglePullbackMoney      = 0.80;
input bool   InpEnableBasketProfitHold   = true;
input double InpBasketBaseTargetMoney    = 7.00;
input double InpBasketTargetEquityPct    = 0.18;
input double InpBasketArmExtraMoney      = 2.20;
input double InpBasketPullbackMoney      = 1.50;
input bool   InpRequirePullbackConfirm   = true;
input int    InpProfitHoldCooldownSeconds = 8;
input bool   InpForceCloseAtSessionStop  = false;

input string TH_TOTAL_PROFIT = "========== Total Profit Close BUY+SELL (Default: OFF) ==========";
input ENUM_TOTAL_PROFIT_MODE InpTotalProfitMode = TOTAL_PROFIT_OFF;  // C=Off, A=Simple, B=Trail
input double InpTotalProfitTarget    = 15.0;  // Total profit target ($)
input double InpTotalProfitArmExtra  = 3.0;   // [Trail] Extra above target to arm
input double InpTotalProfitPullback  = 2.0;   // [Trail] Pullback amount to close ($)

input string TH_BADTRADE = "========== Bad Trade Close (Default: OFF) ==========";
input ENUM_BADTRADE_MODE InpBadTradeMode = BADTRADE_OFF;  // E=Off, A=PerPos, B=Total, C=Time, D=All
input double InpCutLossPerPosAmount   = 20.0;  // [A/D] Max loss per position ($)
input double InpCutLossTotalAmount    = 50.0;  // [B/D] Max total loss all positions ($)
input int    InpCutLossTimeHours      = 48;    // [C/D] Max position age (hours)

input string TH_BREAKEVEN = "========== Break-Even (Default: OFF) ==========";
input bool   InpEnableBreakEven        = false;
input double InpBreakEvenTriggerPoints = 300.0;  // Profit in points to trigger BE
input double InpBreakEvenBufferPoints  = 10.0;   // Buffer above open price (points)

input string TH_PARTIAL = "========== Partial Close (Default: OFF) ==========";
input bool   InpEnablePartialClose         = false;
input double InpPartialCloseTriggerPoints  = 500.0;  // Profit in points to trigger
input double InpPartialClosePercent        = 50.0;   // Close X% of lot size

input string TH_ACCTSL = "========== Account Stop Loss (Default: OFF) ==========";
input bool   InpEnableAccountSL        = false;
input double InpAccountSLPercent       = 10.0;   // Max DD from balance (%)

input string TH_DAILYLOSS = "========== Max Daily Loss (Default: OFF) ==========";
input bool   InpEnableMaxDailyLoss     = false;
input double InpMaxDailyLossAmount     = 30.0;   // Max daily loss ($) — stops trading for day

input string TH_MAXPOS = "========== Max Total Positions (Default: OFF) ==========";
input bool   InpEnableMaxTotalPositions = false;
input int    InpMaxTotalPositions       = 8;     // Max open positions (BUY + SELL combined)

input string TH_HEDGE = "========== Hedging Mode (Default: OFF) ==========";
input bool   InpEnableHedging          = false;
input double InpHedgeTriggerLoss       = 30.0;  // Open hedge when side loss >= ($)
input double InpHedgeLotMultiplier     = 1.0;   // Hedge lot = base * this multiplier

input string TH_SIDEGUARD = "========== Side Guard (Default: OFF) ==========";
input ENUM_SIDE_GUARD_MODE InpSideGuardMode  = GUARD_OFF;  // โหมด: Off / A / B / C / A+B+C
input double InpSideGuardLossUSD             = 50.0;   // [A] Loss threshold per side ($)
input double InpSideGuardDDPct               = 5.0;    // [B] DD% threshold per side (% Equity)
input int    InpSideGuardImbalanceLv         = 2;       // [C] Max grid level difference (ไม้)
input bool   InpSideGuardFreezeRecovery      = true;   // [E] หยุด Recovery ฝั่งที่ guard ด้วย
input double InpSideGuardResumeRatio         = 0.5;    // Resume เมื่อ loss ลดเหลือ X * threshold

input string TH_SCHEDULE_06 = "========== Schedule ==========";
input bool   InpUseSchedule            = true;
input int    InpTradeStartHour         = 7;
input int    InpTradeStartMinute       = 0;
input int    InpTradeStopHour          = 23;
input int    InpTradeStopMinute        = 30;
input bool   InpAutoStartNextDay       = true;
input bool   InpBlockSaturdaySunday    = true;

input string TH_SESSION = "========== Session Filter & Risk ==========";
input int    InpServerGMTOffset      = 3;      // Broker server GMT offset (e.g. 3 = GMT+3)
input bool   InpEnableSessionFilter  = false;  // Only trade in allowed sessions
input bool   InpAllowSydney          = true;   // Allow trading: Sydney (22:00-07:00 GMT)
input bool   InpAllowTokyo           = true;   // Allow trading: Tokyo  (00:00-09:00 GMT)
input bool   InpAllowLondon          = true;   // Allow trading: London (08:00-17:00 GMT)
input bool   InpAllowNewYork         = true;   // Allow trading: New York (13:00-22:00 GMT)
input bool   InpAllowOverlapTkLn     = true;   // Allow trading: Tokyo-London overlap (08-09 GMT)
input bool   InpAllowOverlapLnNY     = true;   // Allow trading: London-NY overlap (13-17 GMT)
input bool   InpBlockLowLiquidity    = false;  // Block when no major session is active
input bool   InpEnableSessionRisk    = false;  // Adjust lot multiplier per session
input double InpSydneyRiskPct        = 50.0;   // Sydney lot multiplier (% of base)
input double InpTokyoRiskPct         = 80.0;   // Tokyo lot multiplier (% of base)
input double InpLondonRiskPct        = 100.0;  // London lot multiplier (% of base)
input double InpNewYorkRiskPct       = 100.0;  // New York lot multiplier (% of base)
input double InpOverlapRiskPct       = 120.0;  // Overlap lot multiplier (% of base)

input string TH_SAFETY_07 = "========== Safety Toggles ==========";
input bool   InpUseSpreadGuard          = false;
input bool   InpUseMarginGuard          = false;
input double InpMinMarginLevelPercent   = 180.0;
input bool   InpUseEquityDDGuard        = false;
input double InpMaxEquityDDPercent      = 18.0;
input bool   InpUseVolatilityGuard      = false;
input double InpATRMaxPointsForEntry    = 2600.0;
input double InpATRMaxPointsForRecovery = 1800.0;
input bool   InpUseMaxTickAgeGuard      = false;
input int    InpMaxTickAgeSeconds       = 120;

input string TH_TG_08 = "========== Telegram ==========";
input bool   InpEnableTelegramAlert      = false;
input string InpTelegramBotToken         = "";
input string InpTelegramChatId           = "";
// Text only (high frequency)
input bool   InpTelegramSendOnEntry      = true;   // Alert on Entry — text only
input bool   InpTelegramSendOnExit       = true;   // Alert on Exit — text only
input bool   InpTelegramSendOnRecovery   = true;   // Alert on Recovery — text only
// Photo alerts (low frequency, important)
input bool   InpTelegramSendDDAlert      = true;   // DD Alert — WITH PHOTO
input double InpTelegramDDAlertPercent   = 10.0;   // DD% to trigger alert
input bool   InpTelegramSendDailySummary = true;   // Daily Summary — WITH PHOTO
// Screenshot settings
input int    InpScreenshotWidth          = 1280;
input int    InpScreenshotHeight         = 720;
input int    InpTelegramTimeoutMs        = 10000;
// Remote commands via Telegram bot
input bool   InpTelegramCmdEnabled      = true;   // Enable Telegram bot commands
input int    InpTelegramPollSeconds     = 5;      // Poll interval (sec)

input string TH_HUD_09 = "========== HUD ==========";
input bool   InpShowHUD                = true;
input color  InpHudTextColor           = clrWhite;
input int    InpHudX                   = 10;
input int    InpHudY                   = 52;
input int    InpHudFontSize            = 10;

//========================= GLOBALS ================================//
CTrade trade;

// Indicator handles
int  g_ema_fast_handle = INVALID_HANDLE;
int  g_ema_slow_handle = INVALID_HANDLE;
int  g_atr_handle      = INVALID_HANDLE;
int  g_rsi_handle      = INVALID_HANDLE;

// Timing
datetime g_last_bar_time          = 0;
datetime g_last_entry_time        = 0;
datetime g_last_recovery_time     = 0;
datetime g_init_time              = 0;
datetime g_last_hold_close_time   = 0;
datetime g_last_market_close_log  = 0;
datetime g_last_hud_update_second = 0;
datetime g_last_dd_alert_time     = 0;
datetime g_last_hedge_time        = 0;
datetime g_last_tg_poll_time      = 0;
long     g_tg_last_update_id      = 0;

// Runtime-adjustable limits (overrides inputs, set by Telegram commands)
int      g_max_orders_per_side    = 0;  // 0 = use InpMaxOrdersPerSide

// Side Guard state
bool     g_side_guard_buy         = false;  // true = BUY side paused by Side Guard
bool     g_side_guard_sell        = false;  // true = SELL side paused by Side Guard
string   g_side_guard_reason_buy  = "";     // reason string for HUD/log
string   g_side_guard_reason_sell = "";

// State flags
bool g_manual_pause         = false;
bool g_schedule_override    = false;
bool g_started_once_today   = false;
bool g_account_sl_triggered = false;
bool g_daily_loss_triggered = false;

// Daily tracking
int    g_last_day_of_year    = -1;
double g_session_start_equity = 0.0;
double g_max_dd_today         = 0.0;
double g_daily_start_balance  = 0.0;
double g_dd_alert_sent_pct    = 0.0;

// Profit peak trackers
double g_peak_single_profit_buy  = 0.0;
double g_peak_single_profit_sell = 0.0;
double g_peak_basket_profit_buy  = 0.0;
double g_peak_basket_profit_sell = 0.0;
double g_peak_total_profit       = 0.0;

// Partial close tracker
ulong g_partial_closed_tickets[200];
int   g_partial_closed_count = 0;

// Per-tick signal cache (ป้องกัน GetDirectionalSignalScore 4x ต่อ tick)
datetime g_sig_cache_bar_time = 0;
int      g_sig_cache_dir      = 0;
int      g_sig_cache_score    = 0;
string   g_sig_cache_why      = "";

// Effective profile params
double g_eff_min_ema_sep     = 60.0;
double g_eff_strong_ema_sep  = 120.0;
double g_eff_min_body        = 80.0;
double g_eff_strong_body     = 160.0;
double g_eff_atr_min         = 120.0;
double g_eff_atr_max         = 3500.0;
int    g_eff_min_score       = 4;
int    g_eff_startup_score   = 5;
double g_eff_base_grid       = 900.0;
double g_eff_grid_expand_pct = 22.0;

// HUD object names
string HUD_PANEL_NAME  = "KUNGRC_HUD_PANEL_V140";
string HUD_ACCENT_NAME = "KUNGRC_HUD_ACCENT_V140";
string HUD_LINE1_NAME  = "KUNGRC_HUD_LINE1_V140";
string HUD_LINE2_NAME  = "KUNGRC_HUD_LINE2_V140";
string HUD_LINE3_NAME  = "KUNGRC_HUD_LINE3_V140";
string HUD_LINE4_NAME  = "KUNGRC_HUD_LINE4_V140";
string HUD_LINE5_NAME  = "KUNGRC_HUD_LINE5_V140";
// Per-line colors
color  HUD_COLOR_L1    = C'210,210,210';   // ขาวอ่อน  — header / state
color  HUD_COLOR_L2    = C'100,210,255';   // ฟ้า      — BUY side
color  HUD_COLOR_L3    = C'255,110,110';   // แดงอ่อน  — SELL side
color  HUD_COLOR_L4    = C'255,210,80';    // ทอง      — market / session
color  HUD_COLOR_L5    = C'80,220,160';    // เขียวมิ้นท์ — account
string BTN_TOGGLE      = "KUNGRC_BTN_TOGGLE_V140";  // merged RUN+STOP
string BTN_CLOSE_ALL   = "KUNGRC_BTN_CLOSE_ALL_V140";

//========================= RUNTIME LIMITS =========================//
// Returns effective MaxOrdersPerSide (Telegram override takes priority)
int MaxOrdersPerSide()
{
   return (g_max_orders_per_side > 0) ? g_max_orders_per_side : InpMaxOrdersPerSide;
}

//========================= LOGGING ================================//
void LogInfo(const string msg)
{
   if(InpVerboseLogs)
      PrintFormat("[INFO][%s] %s", APP_VERSION, msg);
}
void LogWarn(const string msg)  { PrintFormat("[WARN][%s] %s",  APP_VERSION, msg); }
void LogError(const string msg) { PrintFormat("[ERROR][%s] %s", APP_VERSION, msg); }

//========================= URL ENCODE =============================//
string UrlEncode(const string src)
{
   string out = "";
   int len = StringLen(src);
   for(int i = 0; i < len; i++)
   {
      ushort c = (ushort)StringGetCharacter(src, i);
      bool safe = (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') ||
                  (c >= 'a' && c <= 'z') || c == '-' || c == '_' || c == '.' || c == '~';
      if(safe)       out += StringSubstr(src, i, 1);
      else if(c==' ') out += "%20";
      else            out += StringFormat("%%%02X", (int)(c & 0xFF));
   }
   return out;
}
string FormatSignedMoney(const double v)
{
   return (v > 0.0000001 ? "+" : "") + DoubleToString(v, 2);
}

//========================= BYTE HELPERS ===========================//
void AppendStringBytes(char &arr[], const string s)
{
   char tmp[];
   int n = StringToCharArray(s, tmp, 0, WHOLE_ARRAY, CP_UTF8);
   if(n <= 0) return;
   int old = ArraySize(arr);
   ArrayResize(arr, old + n - 1);
   for(int i = 0; i < n - 1; i++) arr[old + i] = tmp[i];
}
void AppendBytes(char &arr[], const char &src[])
{
   int sz = ArraySize(src);
   if(sz <= 0) return;
   int old = ArraySize(arr);
   ArrayResize(arr, old + sz);
   for(int i = 0; i < sz; i++) arr[old + i] = src[i];
}

//========================= TELEGRAM ===============================//
bool TelegramReady()
{
   return InpEnableTelegramAlert &&
          StringLen(InpTelegramBotToken) >= 10 &&
          StringLen(InpTelegramChatId) >= 1;
}

// Fixed: use 7-param WebRequest so Content-Type header is properly applied
bool TelegramSendMessage(const string text)
{
   if(!TelegramReady()) return false;
   string url     = "https://api.telegram.org/bot" + InpTelegramBotToken + "/sendMessage";
   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   string body    = "chat_id=" + UrlEncode(InpTelegramChatId) + "&text=" + UrlEncode(text);
   char data[], result[];
   string result_headers = "";
   StringToCharArray(body, data, 0, WHOLE_ARRAY, CP_UTF8);
   if(ArraySize(data) > 0) ArrayResize(data, ArraySize(data) - 1);
   ResetLastError();
   int code = WebRequest("POST", url, headers, InpTelegramTimeoutMs, data, result, result_headers);
   if(code == -1) { LogWarn(StringFormat("TG msg failed | err=%d", GetLastError())); return false; }
   if(code < 200 || code >= 300) { LogWarn(StringFormat("TG msg HTTP=%d", code)); return false; }
   return true;
}

bool TelegramSendPhotoFile(const string file_path, const string caption)
{
   if(!TelegramReady()) return false;
   int fh = FileOpen(file_path, FILE_READ | FILE_BIN);
   if(fh == INVALID_HANDLE) { LogWarn("TG photo: cannot open file"); return false; }
   int fsz = (int)FileSize(fh);
   if(fsz <= 0) { FileClose(fh); LogWarn("TG photo: file empty"); return false; }
   char fdata[];
   ArrayResize(fdata, fsz);
   FileReadArray(fh, fdata, 0, fsz);
   FileClose(fh);

   string boundary = "KungRC140Boundary";
   string headers  = "Content-Type: multipart/form-data; boundary=" + boundary + "\r\n";
   char post[], result[];
   ArrayResize(post, 0);
   AppendStringBytes(post, "--" + boundary + "\r\n");
   AppendStringBytes(post, "Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n");
   AppendStringBytes(post, InpTelegramChatId + "\r\n");
   AppendStringBytes(post, "--" + boundary + "\r\n");
   AppendStringBytes(post, "Content-Disposition: form-data; name=\"caption\"\r\n\r\n");
   AppendStringBytes(post, caption + "\r\n");
   AppendStringBytes(post, "--" + boundary + "\r\n");
   AppendStringBytes(post, "Content-Disposition: form-data; name=\"photo\"; filename=\"chart.png\"\r\n");
   AppendStringBytes(post, "Content-Type: image/png\r\n\r\n");
   AppendBytes(post, fdata);
   AppendStringBytes(post, "\r\n--" + boundary + "--\r\n");

   string url = "https://api.telegram.org/bot" + InpTelegramBotToken + "/sendPhoto";
   string result_headers = "";
   ResetLastError();
   int code = WebRequest("POST", url, headers, InpTelegramTimeoutMs, post, result, result_headers);
   if(code == -1) { LogWarn(StringFormat("TG photo failed | err=%d", GetLastError())); return false; }
   if(code < 200 || code >= 300) { LogWarn(StringFormat("TG photo HTTP=%d", code)); return false; }
   return true;
}

string MakeScreenshotFileName(const string tag)
{
   string ts = TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES | TIME_SECONDS);
   StringReplace(ts, ".", "");
   StringReplace(ts, ":", "");
   StringReplace(ts, " ", "_");
   return "KRC_" + APP_VERSION + "_" + tag + "_" + ts + ".png";
}

// Unified notify: with_photo=true → screenshot + sendPhoto; false → text only
void SendTelegramNotify(const string tag, const string message, const bool with_photo = false)
{
   if(!TelegramReady()) return;
   if(with_photo)
   {
      string fn = MakeScreenshotFileName(tag);
      if(ChartScreenShot(0, fn, InpScreenshotWidth, InpScreenshotHeight, ALIGN_RIGHT))
      {
         if(TelegramSendPhotoFile(fn, message)) return;
      }
      // fallback to text if photo fails
      TelegramSendMessage(message + "\n(photo failed)");
   }
   else
   {
      TelegramSendMessage(message);
   }
}

void SendDailySummaryTelegram()
{
   if(!InpTelegramSendDailySummary || !TelegramReady()) return;
   int buy_cnt  = CountPositionsByType(POSITION_TYPE_BUY);
   int sell_cnt = CountPositionsByType(POSITION_TYPE_SELL);
   double total_pnl = SumProfitByType(POSITION_TYPE_BUY) + SumProfitByType(POSITION_TYPE_SELL);
   string msg = StringFormat(
      "[%s] DAILY SUMMARY\n"
      "Symbol: %s | Profile: %s\n"
      "Balance: %.2f | Equity: %.2f\n"
      "Max DD Today: %.2f%%\n"
      "Open: %d (B:%d S:%d) | Float: %.2f\n"
      "Grid Level: %d",
      APP_VERSION, _Symbol, ProfileName(),
      AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY),
      g_max_dd_today,
      buy_cnt + sell_cnt, buy_cnt, sell_cnt, total_pnl,
      MathMax(buy_cnt, sell_cnt)
   );
   SendTelegramNotify("DAILY", msg, true);  // WITH PHOTO
}

void CheckAndSendDDAlert()
{
   if(!InpTelegramSendDDAlert || !TelegramReady()) return;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(bal <= 0.0) return;
   double dd = ((bal - eq) / bal) * 100.0;
   if(dd < InpTelegramDDAlertPercent) return;
   // throttle: send only if DD grew 2%+ OR 30 min passed since last alert
   if(dd < g_dd_alert_sent_pct + 2.0 && (TimeCurrent() - g_last_dd_alert_time) < 1800) return;
   g_last_dd_alert_time = TimeCurrent();
   g_dd_alert_sent_pct  = dd;
   string msg = StringFormat(
      "⚠️ [%s] DD ALERT\n"
      "Symbol: %s\n"
      "DD: %.2f%% (Threshold: %.1f%%)\n"
      "Balance: %.2f | Equity: %.2f\n"
      "Positions: %d | Grid Level: %d",
      APP_VERSION, _Symbol, dd, InpTelegramDDAlertPercent,
      bal, eq, PositionsTotal(),
      MathMax(CountPositionsByType(POSITION_TYPE_BUY), CountPositionsByType(POSITION_TYPE_SELL))
   );
   SendTelegramNotify("DD", msg, true);  // WITH PHOTO
}

//========================= HELPERS ================================//
double GetPointValue()   { return SymbolInfoDouble(_Symbol, SYMBOL_POINT); }
int    GetDigitsValue()  { return (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS); }
double NormalizePrice(const double price) { return NormalizeDouble(price, GetDigitsValue()); }

bool IsNewBar()
{
   datetime t = iTime(_Symbol, _Period, 0);
   if(t <= 0) return false;
   if(g_last_bar_time == 0) { g_last_bar_time = t; return false; }
   if(t != g_last_bar_time) { g_last_bar_time = t; return true; }
   return false;
}
bool ReadIndicatorValue(const int handle, const int shift, double &out)
{
   if(handle == INVALID_HANDLE) return false;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, shift, 1, buf) < 1) return false;
   out = buf[0];
   return true;
}
bool GetTickSafe(MqlTick &tick)
{
   if(!SymbolInfoTick(_Symbol, tick)) return false;
   if(InpUseMaxTickAgeGuard && (TimeCurrent() - tick.time) > InpMaxTickAgeSeconds) return false;
   return true;
}
double GetSpreadPoints()
{
   MqlTick tick;
   if(!GetTickSafe(tick)) return -1.0;
   double pt = GetPointValue();
   if(pt <= 0.0) return -1.0;
   return (tick.ask - tick.bid) / pt;
}
double GetATRPoints()
{
   double atr = 0.0;
   if(!ReadIndicatorValue(g_atr_handle, 1, atr)) return 0.0;
   double pt = GetPointValue();
   if(pt <= 0.0) return 0.0;
   return atr / pt;
}
bool IsWeekendBlocked()
{
   if(!InpBlockSaturdaySunday) return false;
   MqlDateTime st; TimeToStruct(TimeCurrent(), st);
   return (st.day_of_week == 0 || st.day_of_week == 6);
}
int GetNowMinutesOfDay()
{
   MqlDateTime st; TimeToStruct(TimeCurrent(), st);
   return st.hour * 60 + st.min;
}
bool IsInsideTradingWindow()
{
   if(g_schedule_override) return true;
   if(!InpUseSchedule) return true;
   if(IsWeekendBlocked()) return false;
   int now_m   = GetNowMinutesOfDay();
   int start_m = InpTradeStartHour * 60 + InpTradeStartMinute;
   int stop_m  = InpTradeStopHour  * 60 + InpTradeStopMinute;
   if(start_m <= stop_m) return (now_m >= start_m && now_m < stop_m);
   return (now_m >= start_m || now_m < stop_m);
}
//========================= SESSION MANAGEMENT =====================//
// Returns current time in GMT hours (0-23) using broker GMT offset
int GetGMTHour()
{
   MqlDateTime st;
   TimeToStruct(TimeCurrent(), st);
   int gmt_h = st.hour - InpServerGMTOffset;
   while(gmt_h <  0)  gmt_h += 24;
   while(gmt_h >= 24) gmt_h -= 24;
   return gmt_h;
}
// True if gmt_h is within [open_h, close_h), supports wrap-around midnight
bool IsHourInSession(const int gmt_h, const int open_h, const int close_h)
{
   if(open_h < close_h) return (gmt_h >= open_h && gmt_h < close_h);
   return (gmt_h >= open_h || gmt_h < close_h);
}
bool IsSessionSydney()   { return IsHourInSession(GetGMTHour(), 22, 7);  }  // 22:00-07:00
bool IsSessionTokyo()    { return IsHourInSession(GetGMTHour(), 0,  9);  }  // 00:00-09:00
bool IsSessionLondon()   { return IsHourInSession(GetGMTHour(), 8,  17); }  // 08:00-17:00
bool IsSessionNewYork()  { return IsHourInSession(GetGMTHour(), 13, 22); }  // 13:00-22:00
bool IsOverlapTkLn()     { return IsHourInSession(GetGMTHour(), 8,  9);  }  // 08:00-09:00 GMT
bool IsOverlapLnNY()     { return IsHourInSession(GetGMTHour(), 13, 17); }  // 13:00-17:00 GMT
bool IsAnySessionActive(){ return IsSessionSydney() || IsSessionTokyo() || IsSessionLondon() || IsSessionNewYork(); }

string GetCurrentSessionName()
{
   if(IsOverlapLnNY())    return "LN/NY";
   if(IsOverlapTkLn())    return "TK/LN";
   if(IsSessionNewYork()) return "NY";
   if(IsSessionLondon())  return "LN";
   if(IsSessionTokyo())   return "TK";
   if(IsSessionSydney())  return "SY";
   return "---";
}
bool IsInAllowedSession()
{
   if(!InpEnableSessionFilter) return true;
   if(InpBlockLowLiquidity && !IsAnySessionActive()) return false;
   if(IsOverlapLnNY() && InpAllowOverlapLnNY)  return true;
   if(IsOverlapTkLn() && InpAllowOverlapTkLn)  return true;
   if(IsSessionNewYork() && InpAllowNewYork)    return true;
   if(IsSessionLondon()  && InpAllowLondon)     return true;
   if(IsSessionTokyo()   && InpAllowTokyo)      return true;
   if(IsSessionSydney()  && InpAllowSydney)     return true;
   return false;
}
double GetSessionLotMultiplier()
{
   if(!InpEnableSessionRisk) return 1.0;
   if(IsOverlapLnNY() || IsOverlapTkLn()) return MathMax(0.01, InpOverlapRiskPct  / 100.0);
   if(IsSessionNewYork()) return MathMax(0.01, InpNewYorkRiskPct / 100.0);
   if(IsSessionLondon())  return MathMax(0.01, InpLondonRiskPct  / 100.0);
   if(IsSessionTokyo())   return MathMax(0.01, InpTokyoRiskPct   / 100.0);
   if(IsSessionSydney())  return MathMax(0.01, InpSydneyRiskPct  / 100.0);
   return 1.0;
}

bool IsNearSessionCloseForRecovery()
{
   if(!InpUseSchedule || g_schedule_override) return false;
   int now_m  = GetNowMinutesOfDay();
   int stop_m = InpTradeStopHour * 60 + InpTradeStopMinute;
   int remain = stop_m - now_m;
   if(remain < 0) remain += 24 * 60;
   return (remain <= InpNoRecoveryBeforeCloseMinutes);
}
bool IsTradeEnvironmentOk()
{
   return TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) &&
          MQLInfoInteger(MQL_TRADE_ALLOWED) &&
          AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);
}
bool PassSpreadGuard()
{
   if(!InpUseSpreadGuard) return true;
   double s = GetSpreadPoints();
   return (s >= 0.0 && s <= InpMaxSpreadPoints);
}
bool PassMarginGuard()
{
   if(!InpUseMarginGuard) return true;
   double ml = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   return (ml > 0.0 && ml >= InpMinMarginLevelPercent);
}
bool PassEquityDDGuard()
{
   if(!InpUseEquityDDGuard) return true;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(bal <= 0.0) return false;
   return (((bal - eq) / bal) * 100.0 <= InpMaxEquityDDPercent);
}
bool PassVolatilityGuardForEntry()
{
   if(!InpUseVolatilityGuard) return true;
   double atr = GetATRPoints();
   return (atr > 0.0 && atr <= InpATRMaxPointsForEntry);
}
bool PassVolatilityGuardForRecovery()
{
   if(!InpUseVolatilityGuard) return true;
   double atr = GetATRPoints();
   return (atr > 0.0 && atr <= InpATRMaxPointsForRecovery);
}
bool CanTradeNow()
{
   if(g_manual_pause)           return false;
   if(g_account_sl_triggered)   return false;
   if(g_daily_loss_triggered)   return false;
   if(!IsTradeEnvironmentOk())  return false;
   if(!IsInsideTradingWindow()) return false;
   if(!IsInAllowedSession())    return false;
   if(!PassSpreadGuard())       return false;
   if(!PassMarginGuard())       return false;
   if(!PassEquityDDGuard())     return false;
   return true;
}

//========================= VOLUME HELPERS =========================//
double GetVolumeStep()      { return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP); }
double GetMinVolumeAllowed(){ return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN); }
double GetMaxVolumeAllowed(){ return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX); }
double NormalizeVolume(double lot)
{
   double step   = GetVolumeStep();
   double minlot = GetMinVolumeAllowed();
   double maxlot = GetMaxVolumeAllowed();
   if(step <= 0.0) step = 0.01;
   lot = MathMax(lot, MathMax(InpMinLot, minlot));
   lot = MathMin(lot, MathMin(InpMaxLot, maxlot));
   return NormalizeDouble(MathFloor(lot / step) * step, 2);
}
double ComputeBaseLotFromCapital()
{
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double usable  = equity * (100.0 - InpCapitalReserveForRecoveryPct) / 100.0;
   if(InpCapitalReferenceUSD <= 0.0) return NormalizeVolume(InpBaseLotAtReference * GetSessionLotMultiplier());
   return NormalizeVolume(InpBaseLotAtReference * (usable / InpCapitalReferenceUSD) * GetSessionLotMultiplier());
}

//========================= PROFILE ================================//
string ProfileName()
{
   if(InpTuneProfile == PROFILE_A_BALANCED_ATTACK) return "A-Balanced";
   if(InpTuneProfile == PROFILE_B_FASTER_FIRE)     return "B-FastFire";
   return "C-Stricter";
}
void ApplyTuningProfile()
{
   g_eff_min_ema_sep    = InpMinEmaSeparationPoints;
   g_eff_strong_ema_sep = InpStrongEmaSeparationPoints;
   g_eff_min_body       = InpMinBodyPoints;
   g_eff_strong_body    = InpStrongBodyPoints;
   g_eff_atr_min        = InpATRMinPoints;
   g_eff_atr_max        = InpATRMaxPoints;
   g_eff_min_score      = InpMinSignalScore;
   g_eff_startup_score  = InpStartupMinSignalScore;
   g_eff_base_grid      = InpBaseGridPoints;
   g_eff_grid_expand_pct= InpGridExpandPercent;
   if(!InpUseTuningProfile) return;
   switch(InpTuneProfile)
   {
      case PROFILE_A_BALANCED_ATTACK:
         g_eff_min_ema_sep=60; g_eff_strong_ema_sep=120; g_eff_min_body=80;  g_eff_strong_body=160;
         g_eff_atr_min=120;  g_eff_atr_max=3500; g_eff_min_score=4; g_eff_startup_score=5;
         g_eff_base_grid=900; g_eff_grid_expand_pct=22; break;
      case PROFILE_B_FASTER_FIRE:
         g_eff_min_ema_sep=45; g_eff_strong_ema_sep=95;  g_eff_min_body=60;  g_eff_strong_body=130;
         g_eff_atr_min=90;   g_eff_atr_max=3800; g_eff_min_score=3; g_eff_startup_score=4;
         g_eff_base_grid=850; g_eff_grid_expand_pct=18; break;
      case PROFILE_C_STRICTER:
         g_eff_min_ema_sep=80; g_eff_strong_ema_sep=150; g_eff_min_body=100; g_eff_strong_body=190;
         g_eff_atr_min=150;  g_eff_atr_max=3200; g_eff_min_score=5; g_eff_startup_score=6;
         g_eff_base_grid=1000;g_eff_grid_expand_pct=25; break;
   }
}

//========================= POSITION STATS =========================//
int CountPositionsByType(const long pos_type)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)       continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;
      if(PositionGetInteger(POSITION_TYPE)   == pos_type) count++;
   }
   return count;
}
double SumProfitByType(const long pos_type)
{
   double sum = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)       continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;
      if(PositionGetInteger(POSITION_TYPE)   != pos_type)       continue;
      sum += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return sum;
}
double GetLastOpenPriceByType(const long pos_type)
{
   datetime last_t = 0; double price = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)       continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;
      if(PositionGetInteger(POSITION_TYPE)   != pos_type)       continue;
      datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
      if(ot >= last_t) { last_t = ot; price = PositionGetDouble(POSITION_PRICE_OPEN); }
   }
   return price;
}
double SumLotByType(const long pos_type)
{
   double sum = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetInteger(POSITION_TYPE)  != pos_type)       continue;
      sum += PositionGetDouble(POSITION_VOLUME);
   }
   return sum;
}
double GetAvgOpenPriceByType(const long pos_type)
{
   double lot_sum = 0.0, px_sum = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetInteger(POSITION_TYPE)  != pos_type)       continue;
      double lot = PositionGetDouble(POSITION_VOLUME);
      px_sum  += PositionGetDouble(POSITION_PRICE_OPEN) * lot;
      lot_sum += lot;
   }
   return (lot_sum > 0) ? px_sum / lot_sum : 0.0;
}

double GetNextRecoveryLot(const long pos_type)
{
   int count = CountPositionsByType(pos_type);
   double lot = ComputeBaseLotFromCapital();
   for(int i = 0; i < count; i++) lot *= InpLotMultiplier;
   lot = NormalizeVolume(lot);
   // D (AUTO): ถ้า Side Guard active → cap lot ไม่เกิน lot สูงสุดที่เปิดอยู่ (ไม่ escalate ต่อ)
   if(InpSideGuardMode != GUARD_OFF)
   {
      bool guarded = (pos_type == POSITION_TYPE_BUY) ? g_side_guard_buy : g_side_guard_sell;
      if(guarded)
      {
         double cap = GetMaxLotOnSide(pos_type);
         if(cap > 0.0 && lot > cap)
         {
            LogInfo(StringFormat("D-AutoCap: lot %.2f → %.2f (max on side)", lot, cap));
            lot = cap;
         }
      }
   }
   return lot;
}

//========================= SIGNAL ENGINE ==========================//
int GetDirectionalSignalScore(int &dir_out, string &why_out)
{
   dir_out = 0; why_out = "";
   double ema_fast = 0.0, ema_slow = 0.0;
   double close1 = iClose(_Symbol, _Period, 1);
   double open1  = iOpen(_Symbol,  _Period, 1);
   double high1  = iHigh(_Symbol,  _Period, 1);
   double low1   = iLow(_Symbol,   _Period, 1);
   if(close1 == 0.0 || open1 == 0.0) return 0;
   if(!ReadIndicatorValue(g_ema_fast_handle, 1, ema_fast)) return 0;
   if(!ReadIndicatorValue(g_ema_slow_handle, 1, ema_slow)) return 0;
   double atr_pts = GetATRPoints();
   if(atr_pts <= 0.0) return 0;
   double pt = GetPointValue();
   if(pt <= 0.0) return 0;
   double sep_pts  = MathAbs(ema_fast - ema_slow) / pt;
   double body_pts = MathAbs(close1 - open1) / pt;
   double rng_pts  = MathAbs(high1 - low1)   / pt;

   int score_buy = 0, score_sell = 0;
   if(ema_fast > ema_slow) score_buy  += 2;
   if(ema_fast < ema_slow) score_sell += 2;
   if(sep_pts >= g_eff_min_ema_sep)
   { if(ema_fast > ema_slow) score_buy++; else score_sell++; }
   if(sep_pts >= g_eff_strong_ema_sep)
   { if(ema_fast > ema_slow) score_buy++; else score_sell++; }
   if(close1 > open1 && body_pts >= g_eff_min_body)    score_buy++;
   if(close1 < open1 && body_pts >= g_eff_min_body)    score_sell++;
   if(close1 > open1 && body_pts >= g_eff_strong_body) score_buy++;
   if(close1 < open1 && body_pts >= g_eff_strong_body) score_sell++;
   if(atr_pts >= g_eff_atr_min && atr_pts <= g_eff_atr_max) { score_buy++; score_sell++; }
   if(rng_pts >= body_pts * 1.1)
   { if(close1 > open1) score_buy++; else score_sell++; }

   // RSI Filter: block entry into overbought/oversold zone
   if(InpEnableRSIFilter && g_rsi_handle != INVALID_HANDLE)
   {
      double rsi = 0.0;
      if(ReadIndicatorValue(g_rsi_handle, 1, rsi))
      {
         if(rsi >= InpRSIOverboughtLevel) score_buy  = 0;  // block BUY
         if(rsi <= InpRSIOversoldLevel)   score_sell = 0;  // block SELL
      }
   }

   if(InpEntryMode == ENTRY_BUY_ONLY)
   { dir_out = 1; why_out = StringFormat("BUY_ONLY|sc=%d", score_buy); return score_buy; }
   if(InpEntryMode == ENTRY_SELL_ONLY)
   { dir_out = -1; why_out = StringFormat("SELL_ONLY|sc=%d", score_sell); return score_sell; }

   if(score_buy > score_sell)
   { dir_out = 1;  why_out = StringFormat("BUY|sb=%d ss=%d sep=%.0f body=%.0f atr=%.0f", score_buy, score_sell, sep_pts, body_pts, atr_pts); return score_buy; }
   if(score_sell > score_buy)
   { dir_out = -1; why_out = StringFormat("SELL|sb=%d ss=%d sep=%.0f body=%.0f atr=%.0f", score_buy, score_sell, sep_pts, body_pts, atr_pts); return score_sell; }

   dir_out = 0;
   why_out = StringFormat("NEUTRAL|sb=%d ss=%d", score_buy, score_sell);
   return 0;
}
string DirectionText(const int dir) { return (dir > 0 ? "BUY" : dir < 0 ? "SELL" : "NONE"); }

//========================= ORDER EXECUTION ========================//
bool OpenPositionByDirection(const int dir, const double lot, const string reason)
{
   if(dir == 0 || lot <= 0.0) return false;
   MqlTick tick;
   if(!GetTickSafe(tick)) return false;
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   bool ok = (dir > 0) ? trade.Buy(lot, _Symbol, 0, 0, 0, reason)
                       : trade.Sell(lot, _Symbol, 0, 0, 0, reason);
   if(ok)
   {
      LogInfo(StringFormat("Order OK | %s | lot=%.2f", reason, lot));
      return true;
   }
   LogWarn(StringFormat("Order FAIL | %s | lot=%.2f | ret=%u", reason, lot, trade.ResultRetcode()));
   return false;
}
bool CloseAllByType(const long pos_type, const string reason)
{
   double profit_before = SumProfitByType(pos_type);
   bool all_ok = true;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber)  continue;
      if(PositionGetInteger(POSITION_TYPE)   != pos_type)        continue;
      trade.SetExpertMagicNumber(InpMagicNumber);
      trade.SetDeviationInPoints(InpSlippagePoints);
      if(!trade.PositionClose(ticket)) { all_ok = false; continue; }
      LogInfo(StringFormat("Closed #%I64u | %s", ticket, reason));
   }
   if(all_ok && InpTelegramSendOnExit)
   {
      string msg = StringFormat("[%s] EXIT %s\nSymbol:%s Reason:%s\nProfit:%.2f Equity:%.2f",
         APP_VERSION, (pos_type == POSITION_TYPE_BUY ? "BUY" : "SELL"),
         _Symbol, reason, profit_before, AccountInfoDouble(ACCOUNT_EQUITY));
      SendTelegramNotify("EXIT", msg, false);  // text only
   }
   return all_ok;
}
bool CloseAllManagedPositions(const string reason)
{
   bool any = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber)  continue;
      trade.SetExpertMagicNumber(InpMagicNumber);
      trade.SetDeviationInPoints(InpSlippagePoints);
      if(trade.PositionClose(ticket)) { any = true; LogInfo(StringFormat("Closed #%I64u | %s", ticket, reason)); }
   }
   return any;
}

//========================= EXIT: SINGLE / BASKET ==================//
double GetDynamicBasketTargetMoney()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   return MathMax(InpBasketBaseTargetMoney, InpBasketBaseTargetMoney + eq * (InpBasketTargetEquityPct / 100.0));
}
void ResetPeakTrackersIfFlat()
{
   if(CountPositionsByType(POSITION_TYPE_BUY)  == 0) { g_peak_single_profit_buy  = 0; g_peak_basket_profit_buy  = 0; }
   if(CountPositionsByType(POSITION_TYPE_SELL) == 0) { g_peak_single_profit_sell = 0; g_peak_basket_profit_sell = 0; }
   if(CountPositionsByType(POSITION_TYPE_BUY) + CountPositionsByType(POSITION_TYPE_SELL) == 0)
      g_peak_total_profit = 0;
}
bool ProfitHoldCooldownPassed()
{ return ((TimeCurrent() - g_last_hold_close_time) >= InpProfitHoldCooldownSeconds); }

void ManageSingleProfitHold(const long pos_type)
{
   if(!InpEnableSingleProfitHold || CountPositionsByType(pos_type) != 1) return;
   if(!ProfitHoldCooldownPassed()) return;
   double p = SumProfitByType(pos_type);
   double peak = (pos_type == POSITION_TYPE_BUY) ? g_peak_single_profit_buy : g_peak_single_profit_sell;
   if(p > peak) peak = p;
   if(pos_type == POSITION_TYPE_BUY) g_peak_single_profit_buy  = peak;
   else                              g_peak_single_profit_sell = peak;
   if(p < InpSingleMinProfitMoney || peak < InpSingleArmProfitMoney) return;
   if(peak - p >= InpSinglePullbackMoney)
   {
      if(CloseAllByType(pos_type, "SINGLE-PROFIT-HOLD"))
      {
         g_last_hold_close_time = TimeCurrent();
         if(pos_type == POSITION_TYPE_BUY) g_peak_single_profit_buy  = 0;
         else                              g_peak_single_profit_sell = 0;
      }
   }
}
void ManageBasketProfitHold(const long pos_type)
{
   if(!InpEnableBasketProfitHold || CountPositionsByType(pos_type) < 2) return;
   if(!ProfitHoldCooldownPassed()) return;
   double p      = SumProfitByType(pos_type);
   double target = GetDynamicBasketTargetMoney();
   double peak = (pos_type == POSITION_TYPE_BUY) ? g_peak_basket_profit_buy : g_peak_basket_profit_sell;
   if(p > peak) peak = p;
   if(pos_type == POSITION_TYPE_BUY) g_peak_basket_profit_buy  = peak;
   else                              g_peak_basket_profit_sell = peak;
   if(p < target) return;
   if(!InpRequirePullbackConfirm)
   {
      if(CloseAllByType(pos_type, "BASKET-TARGET-HIT"))
      {
         g_last_hold_close_time = TimeCurrent();
         if(pos_type == POSITION_TYPE_BUY) g_peak_basket_profit_buy  = 0;
         else                              g_peak_basket_profit_sell = 0;
      }
      return;
   }
   if(peak < target + InpBasketArmExtraMoney) return;
   if(peak - p >= InpBasketPullbackMoney)
   {
      if(CloseAllByType(pos_type, "BASKET-PROFIT-HOLD"))
      {
         g_last_hold_close_time = TimeCurrent();
         if(pos_type == POSITION_TYPE_BUY) g_peak_basket_profit_buy  = 0;
         else                              g_peak_basket_profit_sell = 0;
      }
   }
}

//========================= TOTAL PROFIT CLOSE =====================//
void ManageTotalProfitClose()
{
   if(InpTotalProfitMode == TOTAL_PROFIT_OFF) return;
   if(!ProfitHoldCooldownPassed()) return;
   double total = SumProfitByType(POSITION_TYPE_BUY) + SumProfitByType(POSITION_TYPE_SELL);

   if(InpTotalProfitMode == TOTAL_PROFIT_SIMPLE)
   {
      if(total >= InpTotalProfitTarget)
      {
         LogInfo(StringFormat("TotalProfitClose SIMPLE | total=%.2f", total));
         CloseAllManagedPositions("TOTAL-PROFIT-SIMPLE");
         g_last_hold_close_time = TimeCurrent();
      }
   }
   else if(InpTotalProfitMode == TOTAL_PROFIT_TRAIL)
   {
      if(total > g_peak_total_profit) g_peak_total_profit = total;
      if(total < InpTotalProfitTarget) return;
      if(g_peak_total_profit < InpTotalProfitTarget + InpTotalProfitArmExtra) return;
      if(g_peak_total_profit - total >= InpTotalProfitPullback)
      {
         LogInfo(StringFormat("TotalProfitClose TRAIL | peak=%.2f total=%.2f", g_peak_total_profit, total));
         CloseAllManagedPositions("TOTAL-PROFIT-TRAIL");
         g_last_hold_close_time = TimeCurrent();
         g_peak_total_profit = 0;
      }
   }
}

//========================= BAD TRADE CLOSE ========================//
void ManageBadTradeClose()
{
   if(InpBadTradeMode == BADTRADE_OFF) return;
   bool do_per_pos = (InpBadTradeMode == BADTRADE_PER_POS || InpBadTradeMode == BADTRADE_ALL);
   bool do_total   = (InpBadTradeMode == BADTRADE_TOTAL   || InpBadTradeMode == BADTRADE_ALL);
   bool do_time    = (InpBadTradeMode == BADTRADE_TIME    || InpBadTradeMode == BADTRADE_ALL);

   // B: Total loss check — close everything first
   if(do_total)
   {
      double total = SumProfitByType(POSITION_TYPE_BUY) + SumProfitByType(POSITION_TYPE_SELL);
      if(total <= -MathAbs(InpCutLossTotalAmount))
      {
         LogWarn(StringFormat("CutLoss TOTAL | total=%.2f", total));
         CloseAllManagedPositions("CUT-LOSS-TOTAL");
         return;
      }
   }

   // A: Per position + C: Time-based
   if(!do_per_pos && !do_time) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber)  continue;
      double profit    = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      datetime open_t  = (datetime)PositionGetInteger(POSITION_TIME);
      bool should_close = false;
      if(do_per_pos && profit <= -MathAbs(InpCutLossPerPosAmount)) should_close = true;
      if(do_time    && (int)((TimeCurrent() - open_t) / 3600) >= InpCutLossTimeHours) should_close = true;
      if(should_close)
      {
         trade.SetExpertMagicNumber(InpMagicNumber);
         trade.SetDeviationInPoints(InpSlippagePoints);
         if(trade.PositionClose(ticket))
            LogWarn(StringFormat("CutLoss closed #%I64u | profit=%.2f age=%dh",
               ticket, profit, (int)((TimeCurrent() - open_t) / 3600)));
      }
   }
}

//========================= BREAK-EVEN =============================//
void ManageBreakEven()
{
   if(!InpEnableBreakEven) return;
   double pt = GetPointValue();
   if(pt <= 0.0) return;
   MqlTick tick;
   if(!GetTickSafe(tick)) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber)  continue;
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl         = PositionGetDouble(POSITION_SL);
      double tp         = PositionGetDouble(POSITION_TP);
      long   ptype      = PositionGetInteger(POSITION_TYPE);
      double profit_pts, be_sl;
      if(ptype == POSITION_TYPE_BUY)
      {
         profit_pts = (tick.bid - open_price) / pt;
         be_sl      = NormalizePrice(open_price + InpBreakEvenBufferPoints * pt);
         if(profit_pts >= InpBreakEvenTriggerPoints && (sl < be_sl || sl == 0.0))
         { trade.PositionModify(ticket, be_sl, tp); LogInfo(StringFormat("BE BUY #%I64u | sl→%.5f", ticket, be_sl)); }
      }
      else
      {
         profit_pts = (open_price - tick.ask) / pt;
         be_sl      = NormalizePrice(open_price - InpBreakEvenBufferPoints * pt);
         if(profit_pts >= InpBreakEvenTriggerPoints && (sl > be_sl || sl == 0.0))
         { trade.PositionModify(ticket, be_sl, tp); LogInfo(StringFormat("BE SELL #%I64u | sl→%.5f", ticket, be_sl)); }
      }
   }
}

//========================= PARTIAL CLOSE ==========================//
bool IsPartialClosed(const ulong ticket)
{
   for(int i = 0; i < g_partial_closed_count; i++)
      if(g_partial_closed_tickets[i] == ticket) return true;
   return false;
}
void MarkPartialClosed(const ulong ticket)
{
   if(g_partial_closed_count >= 200) return;
   g_partial_closed_tickets[g_partial_closed_count++] = ticket;
}
void CleanPartialClosedList()
{
   // Remove tickets that no longer exist
   int new_count = 0;
   for(int i = 0; i < g_partial_closed_count; i++)
   {
      if(PositionSelectByTicket(g_partial_closed_tickets[i]))
         g_partial_closed_tickets[new_count++] = g_partial_closed_tickets[i];
   }
   g_partial_closed_count = new_count;
}
void ManagePartialClose()
{
   if(!InpEnablePartialClose) return;
   double pt = GetPointValue();
   if(pt <= 0.0) return;
   MqlTick tick;
   if(!GetTickSafe(tick)) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber)  continue;
      if(IsPartialClosed(ticket)) continue;
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double lot        = PositionGetDouble(POSITION_VOLUME);
      long   ptype      = PositionGetInteger(POSITION_TYPE);
      double profit_pts = 0.0;
      if(ptype == POSITION_TYPE_BUY)  profit_pts = (tick.bid - open_price) / pt;
      else                            profit_pts = (open_price - tick.ask) / pt;
      if(profit_pts < InpPartialCloseTriggerPoints) continue;
      double close_lot = NormalizeVolume(lot * (InpPartialClosePercent / 100.0));
      if(close_lot <= 0.0) continue;
      trade.SetExpertMagicNumber(InpMagicNumber);
      trade.SetDeviationInPoints(InpSlippagePoints);
      if(trade.PositionClosePartial(ticket, close_lot))
      {
         MarkPartialClosed(ticket);
         LogInfo(StringFormat("PartialClose #%I64u | lot=%.2f (%.0f%%)", ticket, close_lot, InpPartialClosePercent));
      }
   }
}

//========================= ACCOUNT STOP LOSS ======================//
void ManageAccountStopLoss()
{
   if(!InpEnableAccountSL || g_account_sl_triggered) return;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(bal <= 0.0) return;
   double dd = ((bal - eq) / bal) * 100.0;
   if(dd < InpAccountSLPercent) return;
   g_account_sl_triggered = true;
   g_manual_pause         = true;
   CloseAllManagedPositions("ACCOUNT-STOP-LOSS");
   LogError(StringFormat("Account SL triggered | DD=%.2f%%", dd));
   if(TelegramReady())
   {
      string msg = StringFormat(
         "🚨 [%s] ACCOUNT STOP LOSS\nSymbol:%s\nDD:%.2f%% Limit:%.1f%%\nBal:%.2f Eq:%.2f\nAll positions closed!",
         APP_VERSION, _Symbol, dd, InpAccountSLPercent, bal, eq);
      SendTelegramNotify("ACCTSL", msg, true);  // WITH PHOTO
   }
}

//========================= DAILY LOSS LIMIT =======================//
void CheckMaxDailyLoss()
{
   if(!InpEnableMaxDailyLoss || g_daily_loss_triggered) return;
   if(g_daily_start_balance <= 0.0) return;
   double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
   double loss = g_daily_start_balance - eq;
   if(loss < InpMaxDailyLossAmount) return;
   g_daily_loss_triggered = true;
   g_manual_pause         = true;
   LogWarn(StringFormat("Max daily loss | loss=%.2f | limit=%.2f", loss, InpMaxDailyLossAmount));
   if(TelegramReady())
   {
      string msg = StringFormat(
         "⛔ [%s] MAX DAILY LOSS\nSymbol:%s\nLoss:%.2f (Limit:%.2f)\nTrading stopped for today.",
         APP_VERSION, _Symbol, loss, InpMaxDailyLossAmount);
      SendTelegramNotify("DAILYLOSS", msg, false);
   }
}

//========================= MAX DD TRACKER =========================//
void UpdateMaxDDToday()
{
   if(g_session_start_equity <= 0.0) return;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd = ((g_session_start_equity - eq) / g_session_start_equity) * 100.0;
   if(dd > g_max_dd_today) g_max_dd_today = dd;
}

//========================= HEDGING ================================//
void ManageHedging()
{
   if(!InpEnableHedging) return;
   if(!CanTradeNow()) return;
   if((TimeCurrent() - g_last_hedge_time) < 300) return;  // 5-min cooldown
   double buy_profit  = SumProfitByType(POSITION_TYPE_BUY);
   double sell_profit = SumProfitByType(POSITION_TYPE_SELL);
   int    buy_count   = CountPositionsByType(POSITION_TYPE_BUY);
   int    sell_count  = CountPositionsByType(POSITION_TYPE_SELL);
   double base_lot    = NormalizeVolume(ComputeBaseLotFromCapital() * InpHedgeLotMultiplier);
   // BUY side losing heavily, no SELL hedge yet
   if(buy_count > 0 && sell_count == 0 && buy_profit <= -MathAbs(InpHedgeTriggerLoss))
   {
      LogInfo(StringFormat("Hedge SELL | buy_profit=%.2f", buy_profit));
      if(OpenPositionByDirection(-1, base_lot, "HEDGE-SELL")) g_last_hedge_time = TimeCurrent();
   }
   // SELL side losing heavily, no BUY hedge yet
   if(sell_count > 0 && buy_count == 0 && sell_profit <= -MathAbs(InpHedgeTriggerLoss))
   {
      LogInfo(StringFormat("Hedge BUY | sell_profit=%.2f", sell_profit));
      if(OpenPositionByDirection(+1, base_lot, "HEDGE-BUY")) g_last_hedge_time = TimeCurrent();
   }
}

//========================= SIDE GUARD =============================//
// D (AUTO): คืนค่า lot สูงสุดของไม้ที่เปิดอยู่ฝั่งนั้น
double GetMaxLotOnSide(const long pos_type)
{
   double max_lot = 0.0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if((long)PositionGetInteger(POSITION_TYPE) != pos_type) continue;
      double lot = PositionGetDouble(POSITION_VOLUME);
      if(lot > max_lot) max_lot = lot;
   }
   return max_lot;
}

// ประเมินเงื่อนไข guard ของ 1 ฝั่ง — คืน reason string ("" = ไม่ trigger)
string EvalSideGuardReason(const long pos_type, const double profit, const double equity,
                            const int lv_this, const int lv_other, const bool currently_guarded)
{
   bool use_a = (InpSideGuardMode == GUARD_LOSS_USD  || InpSideGuardMode == GUARD_ALL);
   bool use_b = (InpSideGuardMode == GUARD_DD_PCT    || InpSideGuardMode == GUARD_ALL);
   bool use_c = (InpSideGuardMode == GUARD_IMBALANCE || InpSideGuardMode == GUARD_ALL);

   double loss_abs  = MathAbs(MathMin(profit, 0.0));
   double loss_pct  = (equity > 0) ? (loss_abs / equity) * 100.0 : 0.0;
   int    lv_diff   = lv_this - lv_other;

   double thr_loss  = currently_guarded ? InpSideGuardLossUSD * InpSideGuardResumeRatio : InpSideGuardLossUSD;
   double thr_dd    = currently_guarded ? InpSideGuardDDPct   * InpSideGuardResumeRatio : InpSideGuardDDPct;

   string r = "";
   if(use_a && profit < -thr_loss)
      r += StringFormat("A:$%.1f>$%.1f ", loss_abs, InpSideGuardLossUSD);
   if(use_b && loss_pct >= thr_dd)
      r += StringFormat("B:%.1f%%>%.1f%% ", loss_pct, InpSideGuardDDPct);
   if(use_c && lv_diff >= InpSideGuardImbalanceLv)
      r += StringFormat("C:lv+%d ", lv_diff);

   StringTrimRight(r);
   return r;
}

// ตรวจสอบและอัปเดต guard flag ทั้ง 2 ฝั่ง — เรียกทุก tick
void ManageSideGuard()
{
   if(InpSideGuardMode == GUARD_OFF) return;

   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double buy_prof  = SumProfitByType(POSITION_TYPE_BUY);
   double sell_prof = SumProfitByType(POSITION_TYPE_SELL);
   int    buy_lv    = CountPositionsByType(POSITION_TYPE_BUY);
   int    sell_lv   = CountPositionsByType(POSITION_TYPE_SELL);

   // ── BUY ──────────────────────────────────────────────────────────
   {
      bool   prev   = g_side_guard_buy;
      string reason = (buy_lv > 0)
         ? EvalSideGuardReason(POSITION_TYPE_BUY, buy_prof, equity, buy_lv, sell_lv, prev)
         : "";
      g_side_guard_buy        = (StringLen(reason) > 0);
      g_side_guard_reason_buy = reason;
      if(g_side_guard_buy != prev)
      {
         string msg = g_side_guard_buy
            ? StringFormat("🛡 [%s] BUY Guard ON  [%s]\nEQ:%.2f Grid:%d", APP_VERSION, reason, equity, buy_lv)
            : StringFormat("✅ [%s] BUY Guard OFF (resumed)\nEQ:%.2f", APP_VERSION, equity);
         LogInfo(msg);
         if(TelegramReady()) TelegramSendMessage(msg);
         g_last_hud_update_second = 0;
      }
   }
   // ── SELL ─────────────────────────────────────────────────────────
   {
      bool   prev   = g_side_guard_sell;
      string reason = (sell_lv > 0)
         ? EvalSideGuardReason(POSITION_TYPE_SELL, sell_prof, equity, sell_lv, buy_lv, prev)
         : "";
      g_side_guard_sell        = (StringLen(reason) > 0);
      g_side_guard_reason_sell = reason;
      if(g_side_guard_sell != prev)
      {
         string msg = g_side_guard_sell
            ? StringFormat("🛡 [%s] SELL Guard ON  [%s]\nEQ:%.2f Grid:%d", APP_VERSION, reason, equity, sell_lv)
            : StringFormat("✅ [%s] SELL Guard OFF (resumed)\nEQ:%.2f", APP_VERSION, equity);
         LogInfo(msg);
         if(TelegramReady()) TelegramSendMessage(msg);
         g_last_hud_update_second = 0;
      }
   }
}

//========================= RECOVERY ===============================//
double ComputeAdaptiveGridPoints(const long pos_type)
{
   int count = CountPositionsByType(pos_type);
   double atr = GetATRPoints();
   double grid = g_eff_base_grid;
   if(atr > 0.0) grid = MathMax(grid, atr * InpATRGridMultiplier);
   for(int i = 1; i < count; i++) grid *= (1.0 + g_eff_grid_expand_pct / 100.0);
   return grid;
}
bool ShouldOpenRecovery(const long pos_type)
{
   if(!InpAllowRecovery || !CanTradeNow()) return false;
   // E: Side Guard — freeze recovery on guarded side (ถ้าเปิดใช้ option นี้)
   if(InpSideGuardFreezeRecovery)
   {
      if(pos_type == POSITION_TYPE_BUY  && g_side_guard_buy)
      { LogInfo("Recovery BUY blocked: Side Guard"); return false; }
      if(pos_type == POSITION_TYPE_SELL && g_side_guard_sell)
      { LogInfo("Recovery SELL blocked: Side Guard"); return false; }
   }
   if(!PassVolatilityGuardForRecovery()) return false;
   if(IsNearSessionCloseForRecovery())   return false;
   int count = CountPositionsByType(pos_type);
   if(count <= 0 || count >= MaxOrdersPerSide()) return false;
   if((TimeCurrent() - g_last_recovery_time) < InpRecoveryCooldownSeconds) return false;

   // Max Grid DD guard
   if(InpEnableMaxGridDD)
   {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
      if(bal > 0.0 && ((bal - eq) / bal) * 100.0 >= InpMaxGridDDPercent) return false;
   }

   MqlTick tick;
   if(!GetTickSafe(tick)) return false;
   double last_open = GetLastOpenPriceByType(pos_type);
   if(last_open <= 0.0) return false;
   double pt   = GetPointValue();
   if(pt <= 0.0) return false;
   double grid_pts = ComputeAdaptiveGridPoints(pos_type);
   double adverse  = (pos_type == POSITION_TYPE_BUY) ? (last_open - tick.bid) / pt
                                                      : (tick.ask - last_open) / pt;
   if(adverse < grid_pts) return false;

   // Smart Recovery: require signal to confirm recovery direction
   if(InpEnableSmartRecovery)
   {
      int dir = 0; string why = "";
      GetCachedSignalScore(dir, why);
      if(pos_type == POSITION_TYPE_BUY  && dir < 0) return false;
      if(pos_type == POSITION_TYPE_SELL && dir > 0) return false;
   }
   return true;
}
void ManageRecovery()
{
   if(ShouldOpenRecovery(POSITION_TYPE_BUY))
   {
      double lot = GetNextRecoveryLot(POSITION_TYPE_BUY);
      if(OpenPositionByDirection(+1, lot, "RECOVERY-BUY"))
      {
         g_last_recovery_time = TimeCurrent();
         if(InpTelegramSendOnRecovery)
         {
            string msg = StringFormat("[%s] RECOVERY BUY\nSymbol:%s Lot:%.2f\nGrid Level:%d Equity:%.2f",
               APP_VERSION, _Symbol, lot, CountPositionsByType(POSITION_TYPE_BUY),
               AccountInfoDouble(ACCOUNT_EQUITY));
            SendTelegramNotify("REC", msg, false);  // text only
         }
      }
   }
   if(ShouldOpenRecovery(POSITION_TYPE_SELL))
   {
      double lot = GetNextRecoveryLot(POSITION_TYPE_SELL);
      if(OpenPositionByDirection(-1, lot, "RECOVERY-SELL"))
      {
         g_last_recovery_time = TimeCurrent();
         if(InpTelegramSendOnRecovery)
         {
            string msg = StringFormat("[%s] RECOVERY SELL\nSymbol:%s Lot:%.2f\nGrid Level:%d Equity:%.2f",
               APP_VERSION, _Symbol, lot, CountPositionsByType(POSITION_TYPE_SELL),
               AccountInfoDouble(ACCOUNT_EQUITY));
            SendTelegramNotify("REC", msg, false);  // text only
         }
      }
   }
}

//========================= ENTRY ==================================//
bool StartupGatePassed()
{
   return ((TimeCurrent() - g_init_time) >= InpStartupGateSeconds) && InpOpenAtStartupIfFlat;
}
bool CanOpenFreshEntry()
{
   if(!InpEnableAutoEntry || !CanTradeNow()) return false;
   if(!PassVolatilityGuardForEntry()) return false;
   if((TimeCurrent() - g_last_entry_time) < InpEntryCooldownSeconds) return false;
   if(InpOnlyOpenOnNewBar && !IsNewBar()) return false;
   // Max total positions guard
   if(InpEnableMaxTotalPositions)
   {
      int total = CountPositionsByType(POSITION_TYPE_BUY) + CountPositionsByType(POSITION_TYPE_SELL);
      if(total >= InpMaxTotalPositions) return false;
   }
   return true;
}
void TryOpenStartupEntry()
{
   int total = CountPositionsByType(POSITION_TYPE_BUY) + CountPositionsByType(POSITION_TYPE_SELL);
   if(total > 0 || !StartupGatePassed()) return;
   if(g_started_once_today && InpAutoStartNextDay) return;
   if(!CanTradeNow() || !PassVolatilityGuardForEntry()) return;
   int dir = 0; string why = "";
   int score = GetCachedSignalScore(dir, why);
   if(score < g_eff_startup_score || dir == 0) { LogInfo(StringFormat("Startup blocked|sc=%d|%s", score, why)); return; }
   double lot = ComputeBaseLotFromCapital();
   if(OpenPositionByDirection(dir, lot, "STARTUP-GATE"))
   {
      g_last_entry_time    = TimeCurrent();
      g_started_once_today = true;
      if(InpTelegramSendOnEntry)
      {
         string msg = StringFormat("[%s] ENTRY %s\nSymbol:%s Lot:%.2f Score:%d\nEquity:%.2f",
            APP_VERSION, DirectionText(dir), _Symbol, lot, score, AccountInfoDouble(ACCOUNT_EQUITY));
         SendTelegramNotify("ENTRY", msg, false);  // text only
      }
   }
}
void TryOpenFreshEntry()
{
   int buy_cnt  = CountPositionsByType(POSITION_TYPE_BUY);
   int sell_cnt = CountPositionsByType(POSITION_TYPE_SELL);
   if(buy_cnt >= MaxOrdersPerSide() && sell_cnt >= MaxOrdersPerSide()) return;
   if(!CanOpenFreshEntry()) return;
   int dir = 0; string why = "";
   int score = GetCachedSignalScore(dir, why);
   if(score < g_eff_min_score || dir == 0) { LogInfo(StringFormat("Entry skip|sc=%d|%s", score, why)); return; }
   if(dir > 0 && buy_cnt  >= MaxOrdersPerSide()) return;
   if(dir < 0 && sell_cnt >= MaxOrdersPerSide()) return;
   // Side Guard: block new entry on guarded side
   if(InpSideGuardMode != GUARD_OFF)
   {
      if(dir > 0 && g_side_guard_buy)
      { LogInfo(StringFormat("Entry BUY blocked: Guard[%s]", g_side_guard_reason_buy)); return; }
      if(dir < 0 && g_side_guard_sell)
      { LogInfo(StringFormat("Entry SELL blocked: Guard[%s]", g_side_guard_reason_sell)); return; }
   }
   double lot = ComputeBaseLotFromCapital();
   if(OpenPositionByDirection(dir, lot, "FRESH-ENTRY"))
   {
      g_last_entry_time = TimeCurrent();
      if(InpTelegramSendOnEntry)
      {
         string msg = StringFormat("[%s] ENTRY %s\nSymbol:%s Lot:%.2f Score:%d\nEquity:%.2f",
            APP_VERSION, DirectionText(dir), _Symbol, lot, score, AccountInfoDouble(ACCOUNT_EQUITY));
         SendTelegramNotify("ENTRY", msg, false);  // text only
      }
   }
}

//========================= DAILY / SCHEDULE =======================//
void HandleDailyReset()
{
   MqlDateTime st; TimeToStruct(TimeCurrent(), st);
   if(st.day_of_year == g_last_day_of_year) return;
   // Send daily summary before reset
   if(g_started_once_today) SendDailySummaryTelegram();
   g_last_day_of_year       = st.day_of_year;
   g_started_once_today     = false;
   g_schedule_override      = false;
   g_daily_loss_triggered   = false;
   g_peak_single_profit_buy = g_peak_single_profit_sell = 0;
   g_peak_basket_profit_buy = g_peak_basket_profit_sell = 0;
   g_peak_total_profit      = 0;
   g_max_dd_today           = 0;
   g_dd_alert_sent_pct      = 0;
   g_partial_closed_count   = 0;
   g_daily_start_balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   g_session_start_equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   LogInfo(StringFormat("Daily reset | Balance=%.2f | Profile=%s", g_daily_start_balance, ProfileName()));
}
void HandleSessionStopClose()
{
   if(!InpUseSchedule || !InpForceCloseAtSessionStop || g_schedule_override) return;
   if(IsInsideTradingWindow()) return;
   if(CountPositionsByType(POSITION_TYPE_BUY)  > 0) CloseAllByType(POSITION_TYPE_BUY,  "SESSION-STOP");
   if(CountPositionsByType(POSITION_TYPE_SELL) > 0) CloseAllByType(POSITION_TYPE_SELL, "SESSION-STOP");
   if((TimeCurrent() - g_last_market_close_log) >= 120)
   { LogInfo("Session stop close executed"); g_last_market_close_log = TimeCurrent(); }
}

//========================= HUD ====================================//
int ClampInt(const int v, const int lo, const int hi) { return (v < lo ? lo : v > hi ? hi : v); }
string EllipsizeRight(const string s, const int max_c)
{
   int len = StringLen(s);
   if(max_c <= 0) return "";
   if(len <= max_c) return s;
   if(max_c <= 3) return StringSubstr(s, 0, max_c);
   return StringSubstr(s, 0, max_c - 3) + "...";
}
int ApproxTextPixelWidth(const string s, const int fz)
{ return (int)MathRound(14.0 + StringLen(s) * MathMax(5.0, (double)fz * 0.62)); }
int ApproxMaxCharsFromWidth(const int w, const int fz)
{ return MathMax(8, (int)MathFloor(MathMax(20, w - 20) / MathMax(5.0, (double)fz * 0.62))); }

// Toggle state: EA running = show "⏸ PAUSE" (red) / EA paused = show "▶ RUN" (green)
string ToggleButtonText()  { return g_manual_pause ? "▶ RUN"    : "⏸ PAUSE"; }
color  ToggleButtonColor() { return g_manual_pause ? C'16,185,129' : C'225,29,72'; }

color HudAccentColor()
{
   if(g_manual_pause)          return (color)ColorToARGB(C'225,29,72',  210);
   if(IsInsideTradingWindow()) return (color)ColorToARGB(C'16,185,129', 210);
   return                             (color)ColorToARGB(C'245,158,11', 210);
}
string HudStateText()
{
   if(g_manual_pause)          return "STOP";
   if(g_account_sl_triggered)  return "ACC-SL";
   if(g_daily_loss_triggered)  return "DAY-LOSS";
   if(IsInsideTradingWindow()) return "RUN" + (g_schedule_override ? "[OVR]" : "");
   return "WAIT";
}

void DeleteHUDObjects()
{
   ObjectDelete(0, HUD_PANEL_NAME);
   ObjectDelete(0, HUD_ACCENT_NAME);
   ObjectDelete(0, HUD_LINE1_NAME);
   ObjectDelete(0, HUD_LINE2_NAME);
   ObjectDelete(0, HUD_LINE3_NAME);
   ObjectDelete(0, HUD_LINE4_NAME);
   ObjectDelete(0, HUD_LINE5_NAME);
   ObjectDelete(0, BTN_TOGGLE);
   ObjectDelete(0, BTN_CLOSE_ALL);
}
void EnsureObj(const string name, const ENUM_OBJECT type)
{ if(ObjectFind(0, name) < 0) ObjectCreate(0, name, type, 0, 0, 0); }

void EnsureHudPanel()
{
   EnsureObj(HUD_PANEL_NAME, OBJ_RECTANGLE_LABEL);
   ObjectSetInteger(0, HUD_PANEL_NAME, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, HUD_PANEL_NAME, OBJPROP_XDISTANCE, InpHudX - 2);
   ObjectSetInteger(0, HUD_PANEL_NAME, OBJPROP_YDISTANCE, InpHudY - 4);
   ObjectSetInteger(0, HUD_PANEL_NAME, OBJPROP_XSIZE,     440);
   ObjectSetInteger(0, HUD_PANEL_NAME, OBJPROP_YSIZE,     92);
   ObjectSetInteger(0, HUD_PANEL_NAME, OBJPROP_BGCOLOR,   C'18,22,32');   // dark background
   ObjectSetInteger(0, HUD_PANEL_NAME, OBJPROP_COLOR,     C'18,22,32');   // border same color
   ObjectSetInteger(0, HUD_PANEL_NAME, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, HUD_PANEL_NAME, OBJPROP_BACK,      false);
   ObjectSetInteger(0, HUD_PANEL_NAME, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, HUD_PANEL_NAME, OBJPROP_HIDDEN,    true);
}
void EnsureHudAccent()
{
   EnsureObj(HUD_ACCENT_NAME, OBJ_RECTANGLE_LABEL);
   ObjectSetInteger(0, HUD_ACCENT_NAME, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, HUD_ACCENT_NAME, OBJPROP_XDISTANCE, InpHudX - 2);
   ObjectSetInteger(0, HUD_ACCENT_NAME, OBJPROP_YDISTANCE, InpHudY - 4);
   ObjectSetInteger(0, HUD_ACCENT_NAME, OBJPROP_XSIZE,     4);
   ObjectSetInteger(0, HUD_ACCENT_NAME, OBJPROP_YSIZE,     92);
   ObjectSetInteger(0, HUD_ACCENT_NAME, OBJPROP_BGCOLOR,   HudAccentColor());
   ObjectSetInteger(0, HUD_ACCENT_NAME, OBJPROP_COLOR,     HudAccentColor());
   ObjectSetInteger(0, HUD_ACCENT_NAME, OBJPROP_BACK,      false);
   ObjectSetInteger(0, HUD_ACCENT_NAME, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, HUD_ACCENT_NAME, OBJPROP_HIDDEN,    true);
}
void EnsureHudLine(const string name, const int y_off, const color clr)
{
   EnsureObj(name, OBJ_LABEL);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpHudX + 10);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpHudY + y_off);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  InpHudFontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetString(0,  name, OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,    true);
}
void EnsureButton(const string name, const string text, const int x, const int y,
                  const int w, const color bg)
{
   EnsureObj(name, OBJ_BUTTON);
   ObjectSetInteger(0, name, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,    x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,    y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,        22);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,      bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR,        clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, bg);
   ObjectSetString(0,  name, OBJPROP_TEXT,         text);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,       true);
}
void EnsureHUD()
{
   if(!InpShowHUD) { DeleteHUDObjects(); return; }
   EnsureHudLine(HUD_LINE1_NAME,  0, HUD_COLOR_L1);
   EnsureHudLine(HUD_LINE2_NAME, 18, HUD_COLOR_L2);
   EnsureHudLine(HUD_LINE3_NAME, 36, HUD_COLOR_L3);
   EnsureHudLine(HUD_LINE4_NAME, 54, HUD_COLOR_L4);
   EnsureHudLine(HUD_LINE5_NAME, 72, HUD_COLOR_L5);
}
void EnsureButtons()
{
   int btn_y = InpHudY + 98;
   EnsureButton(BTN_TOGGLE,    ToggleButtonText(), InpHudX + 10,  btn_y, 120, ToggleButtonColor());
   EnsureButton(BTN_CLOSE_ALL, "CLOSE ALL",        InpHudX + 140, btn_y, 120, C'245,158,11');
}

int HudMaxChars() { return ApproxMaxCharsFromWidth(MathMax(260, (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS) - InpHudX - 30), InpHudFontSize); }

// Line 1 (ขาว) — EA identity + state + signal score
string BuildLine1()
{
   int dir = 0; string why = "";
   int score = GetCachedSignalScore(dir, why);
   int buy_lv  = CountPositionsByType(POSITION_TYPE_BUY);
   int sell_lv = CountPositionsByType(POSITION_TYPE_SELL);
   string mx_str = (g_max_orders_per_side > 0)
      ? StringFormat("  ⚡Mx:%d", g_max_orders_per_side) : "";
   return EllipsizeRight(
      StringFormat("★ %s %s  |  %s  |  SIG %s(%d)  |  B:%d  S:%d%s",
         APP_NAME, APP_VERSION, HudStateText(),
         DirectionText(dir), score, buy_lv, sell_lv, mx_str),
      HudMaxChars());
}

// Line 2 (ฟ้า) — BUY side detail
string BuildLine2()
{
   int    cnt  = CountPositionsByType(POSITION_TYPE_BUY);
   double pnl  = SumProfitByType(POSITION_TYPE_BUY);
   double lot  = SumLotByType(POSITION_TYPE_BUY);
   double avg  = GetAvgOpenPriceByType(POSITION_TYPE_BUY);
   string guard_str = g_side_guard_buy ? "  🛡GUARD" : "";
   string avg_str   = (cnt > 0) ? StringFormat("  Avg:%.5f", avg) : "";
   return EllipsizeRight(
      StringFormat("▲ BUY   %d pos  |  PnL: %s  |  Lot: %.2f%s%s",
         cnt, FormatSignedMoney(pnl), lot, avg_str, guard_str),
      HudMaxChars());
}

// Line 3 (แดงอ่อน) — SELL side detail
string BuildLine3()
{
   int    cnt  = CountPositionsByType(POSITION_TYPE_SELL);
   double pnl  = SumProfitByType(POSITION_TYPE_SELL);
   double lot  = SumLotByType(POSITION_TYPE_SELL);
   double avg  = GetAvgOpenPriceByType(POSITION_TYPE_SELL);
   string guard_str = g_side_guard_sell ? "  🛡GUARD" : "";
   string avg_str   = (cnt > 0) ? StringFormat("  Avg:%.5f", avg) : "";
   return EllipsizeRight(
      StringFormat("▼ SELL  %d pos  |  PnL: %s  |  Lot: %.2f%s%s",
         cnt, FormatSignedMoney(pnl), lot, avg_str, guard_str),
      HudMaxChars());
}

// Line 4 (ทอง) — Market conditions + session + total PnL + basket target
string BuildLine4()
{
   double spread = GetSpreadPoints();
   double atr    = GetATRPoints();
   string ses_str = GetCurrentSessionName();
   if(InpEnableSessionRisk)
      ses_str += StringFormat("(%.0f%%)", GetSessionLotMultiplier() * 100.0);
   double total_pnl = SumProfitByType(POSITION_TYPE_BUY) + SumProfitByType(POSITION_TYPE_SELL);
   double tg        = GetDynamicBasketTargetMoney();
   return EllipsizeRight(
      StringFormat("◈ SPR:%.0f  ATR:%.0f  |  SES:%s  |  Total:%s  TG:%.2f",
         spread, atr, ses_str, FormatSignedMoney(total_pnl), tg),
      HudMaxChars());
}

// Line 5 (เขียวมิ้นท์) — Account summary
string BuildLine5()
{
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double dd_now = (bal > 0) ? ((bal - eq) / bal) * 100.0 : 0.0;
   return EllipsizeRight(
      StringFormat("◉ EQ:%.2f  BAL:%.2f  |  DD:%.1f%%  MaxDD:%.1f%%  |  PF:%s",
         eq, bal, dd_now, g_max_dd_today, ProfileName()),
      HudMaxChars());
}

void UpdateHUD()
{
   if(!InpShowHUD) { DeleteHUDObjects(); return; }
   datetime now_s = TimeCurrent();
   if(now_s == g_last_hud_update_second) return;
   g_last_hud_update_second = now_s;
   EnsureHUD();
   // Update toggle button text + color live
   ObjectSetString(0,  BTN_TOGGLE, OBJPROP_TEXT,    ToggleButtonText());
   ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_BGCOLOR,  ToggleButtonColor());
   ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_BORDER_COLOR, ToggleButtonColor());
   EnsureButtons();
   // Update accent color
   // Update text lines
   ObjectSetString(0, HUD_LINE1_NAME, OBJPROP_TEXT, BuildLine1());
   ObjectSetString(0, HUD_LINE2_NAME, OBJPROP_TEXT, BuildLine2());
   ObjectSetString(0, HUD_LINE3_NAME, OBJPROP_TEXT, BuildLine3());
   ObjectSetString(0, HUD_LINE4_NAME, OBJPROP_TEXT, BuildLine4());
   ObjectSetString(0, HUD_LINE5_NAME, OBJPROP_TEXT, BuildLine5());
   // Resize panel to fit content
}

//========================= CHART EVENTS ===========================//
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;
   if(sparam == BTN_TOGGLE)
   {
      if(g_manual_pause)
      {
         // Currently PAUSED → user wants to RUN
         g_manual_pause      = false;
         g_schedule_override = true;
         LogInfo("Toggle: RUN | schedule override ON");
      }
      else
      {
         // Currently RUNNING → user wants to PAUSE
         g_manual_pause      = true;
         g_schedule_override = false;
         LogInfo("Toggle: PAUSE | schedule override OFF");
      }
      ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_STATE, false);
      g_last_hud_update_second = 0;  // force immediate refresh
      UpdateHUD();
      ChartRedraw(0);
   }
   else if(sparam == BTN_CLOSE_ALL)
   {
      LogInfo("HUD: CLOSE ALL");
      CloseAllManagedPositions("HUD-CLOSE-ALL");
      ObjectSetInteger(0, BTN_CLOSE_ALL, OBJPROP_STATE, false);
   }
}

//========================= TELEGRAM BOT COMMANDS ==================//
// Close the oldest open position of a given type
ulong GetOldestTicketByType(const long pos_type)
{
   datetime oldest_t  = (datetime)2147483647; // max datetime
   ulong    oldest_tk = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber)  continue;
      if(PositionGetInteger(POSITION_TYPE)   != pos_type)        continue;
      datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
      if(ot < oldest_t) { oldest_t = ot; oldest_tk = ticket; }
   }
   return oldest_tk;
}
bool CloseOneByType(const long pos_type)
{
   ulong ticket = GetOldestTicketByType(pos_type);
   if(ticket == 0) return false;
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   return trade.PositionClose(ticket);
}

// Simple JSON field extractors (no external lib needed)
string TgExtractText(const string block)
{
   string search = "\"text\":\"";
   int pos = StringFind(block, search);
   if(pos < 0) return "";
   pos += StringLen(search);
   string out = "";
   int len = StringLen(block);
   for(int i = pos; i < len; i++)
   {
      ushort c = StringGetCharacter(block, i);
      if(c == '"') break;
      if(c == '\\')
      {
         i++;
         if(i >= len) break;
         ushort nc = StringGetCharacter(block, i);
         // Preserve: \/ → /   \" → "   \\ → \   others skip
         if(nc == '/' || nc == '"' || nc == '\\')
            out += StringSubstr(block, i, 1);
         // \n \t \r etc. → intentionally skipped (no newlines in commands)
         continue;
      }
      out += StringSubstr(block, i, 1);
   }
   return out;
}
long TgExtractChatId(const string block)
{
   // Find "chat":{ then the first "id": inside it
   int chat_pos = StringFind(block, "\"chat\":{");
   if(chat_pos < 0) return 0;
   int id_pos = StringFind(block, "\"id\":", chat_pos);
   if(id_pos < 0) return 0;
   int p = id_pos + 5;
   bool neg = false;
   if(p < StringLen(block) && StringGetCharacter(block, p) == '-') { neg = true; p++; }
   string num = "";
   for(int i = p; i < MathMin(p + 20, StringLen(block)); i++)
   {
      ushort c = StringGetCharacter(block, i);
      if(c >= '0' && c <= '9') num += StringSubstr(block, i, 1);
      else break;
   }
   if(StringLen(num) == 0) return 0;
   long v = StringToInteger(num);
   return neg ? -v : v;
}
long TgExtractUpdateId(const string block, const int start_pos)
{
   string search = "\"update_id\":";
   int pos = StringFind(block, search, start_pos);
   if(pos < 0) return -1;
   pos += StringLen(search);
   string num = "";
   for(int i = pos; i < MathMin(pos + 15, StringLen(block)); i++)
   {
      ushort c = StringGetCharacter(block, i);
      if(c >= '0' && c <= '9') num += StringSubstr(block, i, 1);
      else break;
   }
   return (StringLen(num) > 0) ? StringToInteger(num) : -1;
}

// Execute a recognized command and return reply string
string ExecuteTelegramCommand(const string cmd)
{
   // --- RUN ---
   if(cmd == "run" || cmd == "start")
   {
      g_manual_pause      = false;
      g_schedule_override = true;
      g_last_hud_update_second = 0;
      return StringFormat("✅ EA RUN\n%s | Equity:%.2f", _Symbol, AccountInfoDouble(ACCOUNT_EQUITY));
   }
   // --- STOP ---
   if(cmd == "stop" || cmd == "pause")
   {
      g_manual_pause      = true;
      g_schedule_override = false;
      g_last_hud_update_second = 0;
      return StringFormat("⏸ EA STOP\n%s | Equity:%.2f", _Symbol, AccountInfoDouble(ACCOUNT_EQUITY));
   }
   // --- CLOSE ALL ---
   if(cmd == "closeall")
   {
      CloseAllManagedPositions("TG-CLOSE-ALL");
      return "✕ All managed positions closed";
   }
   // --- OPEN BUY 1 ---
   if(cmd == "buyone")
   {
      double lot = ComputeBaseLotFromCapital();
      bool ok = OpenPositionByDirection(+1, lot, "TG-BUY");
      return ok ? StringFormat("✅ BUY opened | lot=%.2f", lot) : "❌ BUY open failed";
   }
   // --- OPEN SELL 1 ---
   if(cmd == "sellone")
   {
      double lot = ComputeBaseLotFromCapital();
      bool ok = OpenPositionByDirection(-1, lot, "TG-SELL");
      return ok ? StringFormat("✅ SELL opened | lot=%.2f", lot) : "❌ SELL open failed";
   }
   // --- CLOSE BUY 1 (oldest) ---
   if(cmd == "closebuyone")
   {
      bool ok = CloseOneByType(POSITION_TYPE_BUY);
      return ok ? "✅ 1 BUY closed (oldest)" : "❌ No BUY position to close";
   }
   // --- CLOSE SELL 1 (oldest) ---
   if(cmd == "closesellone")
   {
      bool ok = CloseOneByType(POSITION_TYPE_SELL);
      return ok ? "✅ 1 SELL closed (oldest)" : "❌ No SELL position to close";
   }
   // --- OPEN BUY + SELL ---
   if(cmd == "openbuysell" || cmd == "buysellone")
   {
      double lot = ComputeBaseLotFromCapital();
      bool ok_b = OpenPositionByDirection(+1, lot, "TG-BUY");
      bool ok_s = OpenPositionByDirection(-1, lot, "TG-SELL");
      return StringFormat("%s BUY | %s SELL | lot=%.2f",
         ok_b ? "✅" : "❌", ok_s ? "✅" : "❌", lot);
   }
   // --- CLOSE BUY + SELL (1 each) ---
   if(cmd == "closebuysell" || cmd == "closebuysellone")
   {
      bool ok_b = CloseOneByType(POSITION_TYPE_BUY);
      bool ok_s = CloseOneByType(POSITION_TYPE_SELL);
      return StringFormat("%s 1 BUY | %s 1 SELL",
         ok_b ? "✅ closed" : "❌ no pos", ok_s ? "✅ closed" : "❌ no pos");
   }
   // --- STATUS ---
   if(cmd == "status" || cmd == "s")
   {
      int bc = CountPositionsByType(POSITION_TYPE_BUY);
      int sc = CountPositionsByType(POSITION_TYPE_SELL);
      int mx = MaxOrdersPerSide();
      string mx_str = (g_max_orders_per_side > 0)
         ? StringFormat("%d (override)", mx)
         : StringFormat("%d (default)", mx);
      return StringFormat(
         "📊 %s | %s\n"
         "B:%d %.2f | S:%d %.2f\n"
         "EQ:%.2f BAL:%.2f\n"
         "MaxDD:%.1f%% | GridLv:%d\n"
         "MaxOrd/Side:%s",
         APP_VERSION, HudStateText(),
         bc, SumProfitByType(POSITION_TYPE_BUY),
         sc, SumProfitByType(POSITION_TYPE_SELL),
         AccountInfoDouble(ACCOUNT_EQUITY),
         AccountInfoDouble(ACCOUNT_BALANCE),
         g_max_dd_today,
         MathMax(bc, sc),
         mx_str);
   }
   // --- SIDE GUARD STATUS ---
   if(cmd == "guardstatus" || cmd == "gs")
   {
      string mode_names[] = {"OFF","A:Loss$","B:DD%","C:Imbalance","A+B+C"};
      string b_str = g_side_guard_buy  ? StringFormat("🛡GUARD[%s]", g_side_guard_reason_buy)  : "✅OK";
      string s_str = g_side_guard_sell ? StringFormat("🛡GUARD[%s]", g_side_guard_reason_sell) : "✅OK";
      return StringFormat("🛡 Side Guard | Mode:%s | FreezeRec:%s\nBUY : %s\nSELL: %s",
         mode_names[InpSideGuardMode],
         InpSideGuardFreezeRecovery ? "ON" : "OFF",
         b_str, s_str);
   }
   // --- FORCE CLEAR GUARD (manual override) ---
   if(cmd == "guardoffbuy" || cmd == "gob")
   {
      g_side_guard_buy        = false;
      g_side_guard_reason_buy = "";
      g_last_hud_update_second = 0;
      return "✅ BUY Side Guard manually cleared";
   }
   if(cmd == "guardoffsell" || cmd == "gos")
   {
      g_side_guard_sell        = false;
      g_side_guard_reason_sell = "";
      g_last_hud_update_second = 0;
      return "✅ SELL Side Guard manually cleared";
   }
   if(cmd == "guardoff" || cmd == "go")
   {
      g_side_guard_buy  = false; g_side_guard_reason_buy  = "";
      g_side_guard_sell = false; g_side_guard_reason_sell = "";
      g_last_hud_update_second = 0;
      return "✅ ALL Side Guard manually cleared (BUY + SELL)";
   }

   // --- MAX ORDERS PER SIDE +1 (one side at a time) ---
   if(cmd == "maxup")
   {
      int cur = MaxOrdersPerSide();
      g_max_orders_per_side = cur + 1;
      g_last_hud_update_second = 0;
      return StringFormat("⬆️ MaxOrders/Side: %d → %d\n(input default=%d)",
         cur, g_max_orders_per_side, InpMaxOrdersPerSide);
   }
   // --- MAX ORDERS PER SIDE -1 (one side at a time) ---
   if(cmd == "maxdown")
   {
      int cur = MaxOrdersPerSide();
      if(cur <= 1) return StringFormat("⚠️ MaxOrders/Side already at minimum (%d)", cur);
      g_max_orders_per_side = cur - 1;
      g_last_hud_update_second = 0;
      return StringFormat("⬇️ MaxOrders/Side: %d → %d\n(input default=%d)",
         cur, g_max_orders_per_side, InpMaxOrdersPerSide);
   }
   // --- MAX ORDERS BOTH SIDES +1 ---
   if(cmd == "maxupboth" || cmd == "maxup2")
   {
      int cur = MaxOrdersPerSide();
      g_max_orders_per_side = cur + 1;
      g_last_hud_update_second = 0;
      return StringFormat("⬆️⬆️ MaxOrders BUY+SELL: %d → %d\n(applies to both sides, input default=%d)",
         cur, g_max_orders_per_side, InpMaxOrdersPerSide);
   }
   // --- MAX ORDERS BOTH SIDES -1 ---
   if(cmd == "maxdownboth" || cmd == "maxdown2")
   {
      int cur = MaxOrdersPerSide();
      if(cur <= 1) return StringFormat("⚠️ MaxOrders/Side already at minimum (%d)", cur);
      g_max_orders_per_side = cur - 1;
      g_last_hud_update_second = 0;
      return StringFormat("⬇️⬇️ MaxOrders BUY+SELL: %d → %d\n(applies to both sides, input default=%d)",
         cur, g_max_orders_per_side, InpMaxOrdersPerSide);
   }
   // --- MAX ORDERS RESET to input default ---
   if(cmd == "maxreset")
   {
      int old = MaxOrdersPerSide();
      g_max_orders_per_side = 0;  // 0 = use InpMaxOrdersPerSide
      g_last_hud_update_second = 0;
      return StringFormat("🔄 MaxOrders/Side reset: %d → %d (input default)",
         old, InpMaxOrdersPerSide);
   }

   // --- HELP ---
   return "❓ Commands:\n"
          "/run  /stop  /closeall\n"
          "/buyone  /sellone\n"
          "/closebuyone  /closesellone\n"
          "/openbuysell  /closebuysellone\n"
          "/maxup  /maxdown\n"
          "/maxupboth  /maxdownboth\n"
          "/maxreset\n"
          "/guardstatus (gs)\n"
          "/guardoff (go)  /guardoffbuy (gob)  /guardoffsell (gos)\n"
          "/status (s)";
}

void ProcessTelegramCommand(const string raw_text, const long chat_id)
{
   // Security: only accept from configured chat
   string chat_id_str = IntegerToString(chat_id);
   if(chat_id_str != InpTelegramChatId)
   {
      LogWarn(StringFormat("TG CMD rejected: chat_id=%s (allowed=%s). Update InpTelegramChatId if this is correct.",
         chat_id_str, InpTelegramChatId));
      return;
   }

   // Normalize: strip leading '/', lowercase, strip @botname, strip args
   string cmd = raw_text;
   StringToLower(cmd);
   StringTrimLeft(cmd);
   StringTrimRight(cmd);
   if(StringLen(cmd) == 0) return;
   if(StringGetCharacter(cmd, 0) == '/') cmd = StringSubstr(cmd, 1);
   // strip @botname suffix (e.g. /run@MyBot)
   int at_pos = StringFind(cmd, "@");
   if(at_pos > 0) cmd = StringSubstr(cmd, 0, at_pos);
   // strip arguments after space
   int sp_pos = StringFind(cmd, " ");
   if(sp_pos > 0) cmd = StringSubstr(cmd, 0, sp_pos);
   StringTrimRight(cmd);
   if(StringLen(cmd) == 0) return;

   Print(StringFormat("[TG CMD] /%s  from chat_id=%s", cmd, chat_id_str));
   string reply = ExecuteTelegramCommand(cmd);
   if(StringLen(reply) > 0) TelegramSendMessage(reply);
}

void ParseAndProcessUpdates(const string json)
{
   long max_id = g_tg_last_update_id;
   int  search_pos = 0;

   while(true)
   {
      // Find next update block
      int uid_start = StringFind(json, "\"update_id\":", search_pos);
      if(uid_start < 0) break;

      long update_id = TgExtractUpdateId(json, uid_start);
      if(update_id < 0) { search_pos = uid_start + 12; continue; }
      if(update_id > max_id) max_id = update_id;

      // Find the end of this update block (start of next update_id, or end of array)
      int next_uid = StringFind(json, "\"update_id\":", uid_start + 12);
      string block = (next_uid > 0) ?
         StringSubstr(json, uid_start, next_uid - uid_start) :
         StringSubstr(json, uid_start);

      // Only process new updates
      if(update_id > g_tg_last_update_id)
      {
         string text   = TgExtractText(block);
         long   chat_id = TgExtractChatId(block);
         if(StringLen(text) > 0 && chat_id != 0)
            ProcessTelegramCommand(text, chat_id);
      }

      search_pos = uid_start + 12;
   }

   g_tg_last_update_id = max_id;
}

void PollTelegramCommands()
{
   if(!InpTelegramCmdEnabled) return;
   if(!TelegramReady())
   {
      // Log ครั้งเดียวทุก 60 วินาที ไม่ spam
      static datetime s_warn_time = 0;
      if(TimeCurrent() - s_warn_time >= 60)
      {
         s_warn_time = TimeCurrent();
         LogWarn("TG CMD poll skipped: BotToken or ChatId not set. Check EA inputs.");
      }
      return;
   }
   if((TimeCurrent() - g_last_tg_poll_time) < InpTelegramPollSeconds) return;
   g_last_tg_poll_time = TimeCurrent();

   string url = StringFormat(
      "https://api.telegram.org/bot%s/getUpdates?offset=%d&limit=20&timeout=0",
      InpTelegramBotToken, g_tg_last_update_id + 1);

   char   data[], result[];
   string headers        = "Accept: application/json\r\n";
   string result_headers = "";
   ResetLastError();
   int code = WebRequest("GET", url, headers, InpTelegramTimeoutMs, data, result, result_headers);
   if(code != 200)
   {
      if(code == -1)
      {
         int err = GetLastError();
         LogWarn(StringFormat("TG poll FAILED (err=%d). Check: Tools→Options→EA→Allow WebRequest for 'https://api.telegram.org'", err));
      }
      else
         LogWarn(StringFormat("TG poll HTTP=%d (expected 200)", code));
      return;
   }
   string response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   if(StringFind(response, "\"ok\":true") < 0)
   {
      LogWarn(StringFormat("TG poll response not ok: %s", StringSubstr(response, 0, 120)));
      return;
   }
   LogInfo(StringFormat("TG poll OK offset=%d", g_tg_last_update_id + 1));
   ParseAndProcessUpdates(response);
}

//========================= INIT / DEINIT ==========================//
bool CreateIndicators()
{
   g_ema_fast_handle = iMA(_Symbol, _Period, InpEmaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_ema_slow_handle = iMA(_Symbol, _Period, InpEmaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_atr_handle      = iATR(_Symbol, _Period, InpATRPeriod);
   if(g_ema_fast_handle == INVALID_HANDLE ||
      g_ema_slow_handle == INVALID_HANDLE ||
      g_atr_handle      == INVALID_HANDLE)
   { LogError("Failed to create EMA/ATR handles"); return false; }
   if(InpEnableRSIFilter)
   {
      g_rsi_handle = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
      if(g_rsi_handle == INVALID_HANDLE) { LogError("Failed to create RSI handle"); return false; }
   }
   return true;
}
int OnInit()
{
   g_init_time             = TimeCurrent();
   g_daily_start_balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   g_session_start_equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   MqlDateTime st; TimeToStruct(g_init_time, st);
   g_last_day_of_year = st.day_of_year;
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   ApplyTuningProfile();
   if(!CreateIndicators()) return INIT_FAILED;
   // ย้าย Telegram poll ไป OnTimer() ป้องกัน WebRequest บล็อก OnTick()
   EventSetTimer(MathMax(1, InpTelegramPollSeconds));
   if(InpShowHUD) { DeleteHUDObjects(); UpdateHUD(); }
   LogInfo(StringFormat("Init OK | %s | Profile=%s | RSI=%s | SmartRec=%s | TG=%s | SesFilter=%s | SesRisk=%s | GMToff=%d",
      APP_VERSION, ProfileName(),
      InpEnableRSIFilter     ? "ON" : "OFF",
      InpEnableSmartRecovery ? "ON" : "OFF",
      InpEnableTelegramAlert ? "ON" : "OFF",
      InpEnableSessionFilter ? "ON" : "OFF",
      InpEnableSessionRisk   ? "ON" : "OFF",
      InpServerGMTOffset));
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteHUDObjects();
   if(g_ema_fast_handle != INVALID_HANDLE) IndicatorRelease(g_ema_fast_handle);
   if(g_ema_slow_handle != INVALID_HANDLE) IndicatorRelease(g_ema_slow_handle);
   if(g_atr_handle      != INVALID_HANDLE) IndicatorRelease(g_atr_handle);
   if(g_rsi_handle      != INVALID_HANDLE) IndicatorRelease(g_rsi_handle);
   LogInfo(StringFormat("Deinit | reason=%d", reason));
}

//========================= SIGNAL CACHE ===========================//
// คำนวณ signal ครั้งเดียวต่อแท่ง แล้ว cache ไว้ให้ทุกฟังก์ชันใช้ร่วมกัน
int GetCachedSignalScore(int &dir_out, string &why_out)
{
   datetime bar_time = iTime(_Symbol, _Period, 1);
   if(bar_time != 0 && bar_time == g_sig_cache_bar_time)
   {
      dir_out = g_sig_cache_dir;
      why_out = g_sig_cache_why;
      return g_sig_cache_score;
   }
   int score = GetDirectionalSignalScore(dir_out, why_out);
   g_sig_cache_bar_time = bar_time;
   g_sig_cache_dir      = dir_out;
   g_sig_cache_score    = score;
   g_sig_cache_why      = why_out;
   return score;
}

//========================= MAIN LOOP ==============================//
void OnTick()
{
   HandleDailyReset();
   HandleSessionStopClose();
   UpdateMaxDDToday();
   ManageAccountStopLoss();
   CheckMaxDailyLoss();
   ManageSideGuard();
   ResetPeakTrackersIfFlat();
   CleanPartialClosedList();
   // Exit management
   ManageSingleProfitHold(POSITION_TYPE_BUY);
   ManageSingleProfitHold(POSITION_TYPE_SELL);
   ManageBasketProfitHold(POSITION_TYPE_BUY);
   ManageBasketProfitHold(POSITION_TYPE_SELL);
   ManageTotalProfitClose();
   // Risk management
   ManageBadTradeClose();
   ManageBreakEven();
   ManagePartialClose();
   ManageHedging();
   // Entry / Recovery
   TryOpenStartupEntry();
   TryOpenFreshEntry();
   ManageRecovery();
   // Telegram DD alert (ไม่มี WebRequest ถ้าไม่ถึง threshold)
   CheckAndSendDDAlert();
   // HUD
   UpdateHUD();
}

// Telegram polling ย้ายมา OnTimer() — ไม่บล็อก OnTick() อีกต่อไป
void OnTimer()
{
   PollTelegramCommands();
}
//+------------------------------------------------------------------+
//| END OF KungRC_v1_4_0.mq5                                        |
//+------------------------------------------------------------------+
