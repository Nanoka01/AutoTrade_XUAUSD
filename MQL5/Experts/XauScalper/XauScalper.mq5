//+------------------------------------------------------------------+
//| XauScalper.mq5                                                   |
//| Trend-following scalper for XAUUSD with Discord control.         |
//| Attach to an XAUUSD chart (any timeframe; the EA uses its own    |
//| timeframes from the inputs).                                     |
//|                                                                  |
//| Risk warning: trading leveraged gold/forex can lose more than    |
//| you expect. Test on a demo account first.                        |
//+------------------------------------------------------------------+
#property copyright "XauScalper"
#property version   "2.00"
#property description "Trend-following XAUUSD EA (M15 breakout + daily trend). Risk control in the EA, monitoring via the Discord bot."

#include <XauScalper\Bridge.mqh>
#include <XauScalper\Filters.mqh>
#include <XauScalper\Signal.mqh>
#include <XauScalper\AsianRange.mqh>
#include <XauScalper\RiskManager.mqh>
#include <XauScalper\TradeExecutor.mqh>
#include <XauScalper\PositionManager.mqh>

input group "Strategy"
input ENUM_STRATEGY   InpStrategy       = STRATEGY_BREAKOUT; // Strategy
input int             InpBreakoutBars   = 55;          // Breakout: bars for highest high / lowest low
input int             InpBreakoutEma    = 200;         // Breakout: trend EMA on entry timeframe
input int             InpDailyEma       = 200;         // Breakout: daily trend EMA
input int             InpMaxHoldHours   = 72;          // Close a position after this many hours (0 = off)
input ENUM_TIMEFRAMES InpTrendTf        = PERIOD_M15;  // Pullback: trend timeframe
input int             InpTrendFastEma   = 50;          // Pullback: trend fast EMA
input int             InpTrendSlowEma   = 200;         // Pullback: trend slow EMA
input ENUM_TIMEFRAMES InpEntryTf        = PERIOD_M15;  // Entry timeframe
input int             InpEntryEma       = 20;          // Pullback: entry EMA
input int             InpRsiPeriod      = 7;           // Pullback: RSI period
input double          InpRsiMid         = 50.0;        // Pullback: RSI trigger level
input int             InpPullbackBars   = 3;           // Pullback: bars to look back
input int             InpAtrPeriod      = 14;          // ATR period (entry timeframe)
input double          InpSlAtrMult      = 3.0;         // Stop loss = ATR x
input double          InpTpRMult        = 0.0;         // Take profit = stop distance x (0 = none)
input double          InpBreakevenAtR   = 0.0;         // Move stop to breakeven at R x (0 = off)
input double          InpTrailStartR    = 0.0;         // Start trailing at R x (0 = off)
input double          InpTrailAtrMult   = 1.0;         // Trailing distance = ATR x

input group "Risk"
input double          InpRiskPct        = 0.15;        // Risk per trade (% of equity), each system
input double          InpMaxRiskPct     = 2.0;         // Highest risk allowed from Discord (%)
input double          InpMaxDailyLoss   = 1.5;         // Max daily loss (%) -> stop for the day
input double          InpMaxDrawdown    = 8.0;         // Max drawdown from peak (%) -> close all, halt
input int             InpMaxPositions   = 1;           // Max open positions per system
input int             InpMaxSameSide    = 0;           // Max open positions on one side, all systems together (0 = no limit)
input int             InpMaxTradesDay   = 10;          // Max trades per day
input int             InpMaxConsecLoss  = 4;           // Losses in a row before cooldown
input int             InpCooldownMin    = 120;         // Cooldown minutes
input bool            InpTesterResume   = true;        // Backtest only: resume next day after a drawdown halt

input group "Filters (server time)"
input int             InpMaxSpread      = 60;          // Max spread (points)
input int             InpSessionStart   = 0;           // Session start hour
input int             InpSessionEnd     = 24;          // Session end hour
input int             InpFridayClose    = 20;          // Friday: close all from this hour
input bool            InpUseNews        = true;        // Avoid high-impact news
input int             InpNewsMinutes    = 30;          // Minutes before/after news
input string          InpNewsCurrency   = "USD";       // News currency

input group "Execution"
input long            InpMagic          = 260501;      // Magic number
input int             InpDeviation      = 30;          // Max slippage (points)
input int             InpRetries        = 3;           // Order retries

input group "Extra breakout systems (each trades on its own, magic + 1 / + 2)"
input bool            InpSys2On         = true;        // System 2 on
input ENUM_TIMEFRAMES InpSys2Tf         = PERIOD_M30;  // System 2 timeframe
input int             InpSys2Bars       = 20;          // System 2 breakout bars
input bool            InpSys3On         = true;        // System 3 on
input ENUM_TIMEFRAMES InpSys3Tf         = PERIOD_H1;   // System 3 timeframe
input int             InpSys3Bars       = 20;          // System 3 breakout bars

input group "System 4: Asian range breakout (magic + 3)"
input bool            InpSys4On         = true;        // System 4 on
input int             InpOrbStartHour   = 1;           // Range start hour (server)
input int             InpOrbEndHour     = 8;           // Range end hour (server)
input int             InpOrbLastEntry   = 20;          // No new entries from this hour
input double          InpOrbSlMult      = 1.0;         // Stop loss = range width x
input double          InpOrbTpR         = 3.0;         // Take profit = stop x
input int             InpOrbMaxHold     = 12;          // Close after this many hours
input int             InpOrbDailyEma    = 50;          // Daily trend EMA

input group "Discord bridge"
input bool            InpUseBridge      = true;        // Talk to the Discord bot
input string          InpBridgeDir      = "XauScalper"; // Folder under Common\Files
input int             InpStatusSeconds  = 10;          // Status update interval (seconds)

#define MAX_SYSTEMS 4

CFilters         g_filters;
CRiskManager     g_risk;
// One signal, executor and position manager per system; system i trades with magic InpMagic + i.
CSignal          g_signal[MAX_SYSTEMS];
CTradeExecutor   g_exec[MAX_SYSTEMS];
CPositionManager g_positions[MAX_SYSTEMS];
ENUM_TIMEFRAMES  g_tf[MAX_SYSTEMS];
datetime         g_lastEntryBar[MAX_SYSTEMS];
int              g_systems = 0;
int              g_orbIdx = -1;        // index of the Asian range system, -1 when off
CAsianRange      g_orb;
datetime         g_lastStatus = 0;
string           g_lastBlock = "";

//+------------------------------------------------------------------+
int OnInit()
  {
   bool tester = (bool)MQLInfoInteger(MQL_TESTER);
   g_bridge.Init(InpUseBridge && !tester, InpBridgeDir);

   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
      Print("Warning: this EA is tuned for XAUUSD; current symbol is ", _Symbol);

   // System 1 runs the chosen strategy; systems 2 and 3 are extra breakouts on other timeframes.
   ENUM_TIMEFRAMES tfs[MAX_SYSTEMS];
   int bars[MAX_SYSTEMS];
   g_systems = 0;
   tfs[g_systems] = InpEntryTf;
   bars[g_systems++] = InpBreakoutBars;
   if(InpStrategy == STRATEGY_BREAKOUT && InpSys2On)
     {
      tfs[g_systems] = InpSys2Tf;
      bars[g_systems++] = InpSys2Bars;
     }
   if(InpStrategy == STRATEGY_BREAKOUT && InpSys3On)
     {
      tfs[g_systems] = InpSys3Tf;
      bars[g_systems++] = InpSys3Bars;
     }
   for(int i = 0; i < g_systems; i++)
     {
      g_tf[i] = tfs[i];
      g_lastEntryBar[i] = 0;
      if(!g_signal[i].Init(_Symbol, InpTrendTf, InpTrendFastEma, InpTrendSlowEma, tfs[i], InpEntryEma,
                           InpRsiPeriod, InpRsiMid, InpAtrPeriod, InpPullbackBars))
        {
         Print("Failed to create indicators: ", GetLastError());
         return INIT_FAILED;
        }
      if(InpStrategy == STRATEGY_BREAKOUT)
        {
         if(!g_signal[i].InitBreakout(bars[i], InpBreakoutEma, InpDailyEma))
           {
            Print("Failed to create breakout indicators: ", GetLastError());
            return INIT_FAILED;
           }
        }
      else
         g_signal[i].UsePullback();
      g_exec[i].Init(_Symbol, InpMagic + i, InpDeviation, InpRetries);
      g_positions[i].Init(_Symbol, InpMagic + i, InpBreakevenAtR, InpTrailStartR, InpTrailAtrMult);
      PrintFormat("System %d: %s, breakout %d bars, magic %I64d", i + 1, EnumToString(tfs[i]), bars[i], InpMagic + i);
     }
   g_orbIdx = -1;
   if(InpStrategy == STRATEGY_BREAKOUT && InpSys4On)
     {
      if(!g_orb.Init(_Symbol, InpOrbStartHour, InpOrbEndHour, InpOrbLastEntry, InpOrbSlMult, InpOrbDailyEma))
        {
         Print("Failed to create Asian range indicators: ", GetLastError());
         return INIT_FAILED;
        }
      g_orbIdx = g_systems++;
      g_tf[g_orbIdx] = PERIOD_M5;
      g_lastEntryBar[g_orbIdx] = 0;
      g_exec[g_orbIdx].Init(_Symbol, InpMagic + g_orbIdx, InpDeviation, InpRetries);
      g_positions[g_orbIdx].Init(_Symbol, InpMagic + g_orbIdx, InpBreakevenAtR, InpTrailStartR, InpTrailAtrMult);
      PrintFormat("System %d: Asian range %02d-%02d, entries until %02d:00, magic %I64d", g_orbIdx + 1, InpOrbStartHour,
                  InpOrbEndHour, InpOrbLastEntry, InpMagic + g_orbIdx);
     }
   g_filters.Init(_Symbol, InpMaxSpread, InpSessionStart, InpSessionEnd, InpFridayClose, InpUseNews, InpNewsMinutes, InpNewsCurrency);
   g_risk.Init(_Symbol, InpMagic, InpRiskPct, InpMaxRiskPct, InpMaxDailyLoss, InpMaxDrawdown,
               InpMaxConsecLoss, InpCooldownMin, InpMaxTradesDay);
   g_risk.ApplyInputRisk(InpRiskPct);
   g_risk.SetAutoResumeNewDay(tester && InpTesterResume);
   g_risk.PrintSizingInfo(1.0);

   if(!tester)
      EventSetTimer(2);

   g_bridge.Event("ea_start", "info",
                  StringFormat("XauScalper started on %s, account %I64d (%s), state %s, %d system(s), risk %.2f%% per trade",
                               _Symbol, AccountInfoInteger(ACCOUNT_LOGIN),
                               AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO ? "demo" : "REAL",
                               g_risk.StateName(), g_systems, g_risk.RiskPct()));
   WriteStatus();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if((bool)MQLInfoInteger(MQL_TESTER))
      PrintFormat("Backtest: drawdown halt triggered %d time(s).", g_risk.Halts());
   g_bridge.Event("ea_stop", "warning", StringFormat("XauScalper stopped (reason %d). Open positions keep their broker-side SL/TP.", reason),
                  JInt("reason", reason));
   for(int i = 0; i < g_systems; i++)
      if(i != g_orbIdx)
         g_signal[i].Release();
   g_orb.Release();
  }

double SystemAtr(const int sys) { return sys == g_orbIdx ? 0 : g_signal[sys].Atr(); }
int    SystemHoldHours(const int sys) { return sys == g_orbIdx ? InpOrbMaxHold : InpMaxHoldHours; }

//+------------------------------------------------------------------+
// System index of a magic number, or -1 when the position is not ours.
int SystemOf(const long magic)
  {
   long i = magic - InpMagic;
   return (i >= 0 && i < g_systems) ? (int)i : -1;
  }

int CloseAllSystems()
  {
   int n = 0;
   for(int i = 0; i < g_systems; i++)
      n += g_exec[i].CloseAll();
   return n;
  }

int CountOpenAll()
  {
   int n = 0;
   for(int i = 0; i < g_systems; i++)
      n += g_exec[i].CountOpen();
   return n;
  }

// Open positions of all our systems on one side (buy or sell).
int CountOpenSide(const ENUM_POSITION_TYPE side)
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol || SystemOf(PositionGetInteger(POSITION_MAGIC)) < 0)
         continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == side)
         n++;
     }
   return n;
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(g_risk.Update())
      CloseAllSystems();

   for(int i = 0; i < g_systems; i++)
      g_positions[i].Manage(g_exec[i].Trade(), SystemAtr(i));

   CloseExpired();

   if(g_filters.IsFridayClose() && CountOpenAll() > 0)
     {
      int n = CloseAllSystems();
      if(n > 0)
         g_bridge.Event("friday_close", "info", StringFormat("Closed %d position(s) before the weekend.", n));
     }

   // Each system evaluates entries once per new bar of its own timeframe.
   for(int i = 0; i < g_systems; i++)
     {
      datetime bar = iTime(_Symbol, g_tf[i], 0);
      if(bar == 0 || bar == g_lastEntryBar[i])
         continue;
      g_lastEntryBar[i] = bar;
      TryEntry(i);
     }
  }

//+------------------------------------------------------------------+
// Closes positions held longer than InpMaxHoldHours.
void CloseExpired()
  {
   datetime now = TimeCurrent();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      int sys = SystemOf(PositionGetInteger(POSITION_MAGIC));
      if(sys < 0)
         continue;
      int hold = SystemHoldHours(sys);
      if(hold > 0 && now - (datetime)PositionGetInteger(POSITION_TIME) >= hold * 3600)
        {
         if(g_exec[sys].Close(ticket))
            g_bridge.Event("time_exit", "info", StringFormat("Closed #%I64u after %d hours.", ticket, hold),
                           JInt("ticket", (long)ticket));
        }
     }
  }

//+------------------------------------------------------------------+
void TryEntry(const int sys)
  {
   string reason;
   if(!g_risk.CanOpen(reason))
     {
      NoteBlock(reason);
      return;
     }
   if(g_exec[sys].CountOpen() >= InpMaxPositions)
      return;
   if(!g_filters.SessionOk())
      return;
   if(!g_filters.SpreadOk())
     {
      NoteBlock(StringFormat("spread %d > %d points", g_filters.SpreadPoints(), InpMaxSpread));
      return;
     }
   if(!g_filters.NewsOk(reason))
     {
      NoteBlock(reason);
      return;
     }

   double stop, take;
   ENUM_SIGNAL sig;
   if(sys == g_orbIdx)
     {
      sig = g_orb.Check();
      if(sig == SIGNAL_NONE)
         return;
      stop = g_orb.StopDistance();
      if(stop <= 0)
         return;
      take = (InpOrbTpR > 0) ? stop * InpOrbTpR : 0;
     }
   else
     {
      sig = g_signal[sys].Check();
      if(sig == SIGNAL_NONE)
         return;
      double atr = g_signal[sys].Atr();
      if(atr <= 0)
         return;
      stop = atr * InpSlAtrMult;
      take = (InpTpRMult > 0) ? stop * InpTpRMult : 0;
     }
   int sameSide = CountOpenSide((sig == SIGNAL_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);
   if(InpMaxSameSide > 0 && sameSide >= InpMaxSameSide)
     {
      PrintFormat("System %d %s skipped: %d position(s) already open on that side (limit %d)", sys + 1,
                  sig == SIGNAL_BUY ? "BUY" : "SELL", sameSide, InpMaxSameSide);
      return;
     }
   double lots = g_risk.LotsForStop(stop);
   if(lots <= 0)
     {
      g_bridge.Event("skip", "warning",
                     StringFormat("Signal skipped: minimum lot would risk more than %.2f%% (stop %.2f). Increase balance or lower the ATR multiplier.",
                                  g_risk.RiskPct(), stop));
      return;
     }

   PrintFormat("System %d entry %s: stop %.2f, %.2f lots, risk %.2f %s (%.2f%%)", sys + 1, sig == SIGNAL_BUY ? "BUY" : "SELL", stop, lots,
               lots * g_risk.LossPerLot(stop), AccountInfoString(ACCOUNT_CURRENCY), g_risk.RiskPct());
   ENUM_ORDER_TYPE type = (sig == SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   ulong ticket = g_exec[sys].Open(type, lots, stop, take, StringFormat("XauScalper S%d", sys + 1));
   if(ticket > 0)
     {
      g_risk.OnTradeOpened();
      g_lastBlock = "";
     }
  }

// Sends a "blocked" note to Discord only when the reason changes, to avoid spam.
void NoteBlock(const string reason)
  {
   if(reason == g_lastBlock)
      return;
   g_lastBlock = reason;
   g_bridge.Event("blocked", "info", "New entries blocked: " + reason);
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   if(g_risk.Update())
      CloseAllSystems();
   ProcessCommands();
   if(TimeLocal() - g_lastStatus >= InpStatusSeconds)
      WriteStatus();
  }

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   int sys = SystemOf(HistoryDealGetInteger(trans.deal, DEAL_MAGIC));
   if(sys < 0)
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   long dealType = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   ulong position = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   double volume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
   double price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   string side = (dealType == DEAL_TYPE_BUY) ? "BUY" : "SELL";

   if(entry == DEAL_ENTRY_IN)
     {
      double sl = 0, tp = 0;
      if(PositionSelectByTicket(position))
        {
         sl = PositionGetDouble(POSITION_SL);
         tp = PositionGetDouble(POSITION_TP);
        }
      g_bridge.Event("trade_open", "info",
                     StringFormat("%s %.2f %s @ %.2f SL %.2f TP %.2f", side, volume, _Symbol, price, sl, tp),
                     JInt("ticket", (long)position) + "," + JStr("side", side) + "," + JNum("volume", volume) + ","
                     + JNum("price", price, _Digits) + "," + JNum("sl", sl, _Digits) + "," + JNum("tp", tp, _Digits));
     }
   else
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
        {
         double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                         + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
         // Closing deal is opposite to the position; report the position's side.
         string posSide = (dealType == DEAL_TYPE_BUY) ? "SELL" : "BUY";
         long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
         string why = "manual/EA";
         if(reason == DEAL_REASON_SL)
            why = "SL";
         if(reason == DEAL_REASON_TP)
            why = "TP";
         if(reason == DEAL_REASON_SO)
            why = "STOP OUT";
         g_risk.OnTradeClosed(profit);
         g_positions[sys].Forget(position);
         g_bridge.Event("trade_close", "info",
                        StringFormat("Closed %s %.2f %s @ %.2f (%s) P/L %.2f %s", posSide, volume, _Symbol, price, why, profit,
                                     AccountInfoString(ACCOUNT_CURRENCY)),
                        JInt("ticket", (long)position) + "," + JStr("side", posSide) + "," + JNum("volume", volume) + ","
                        + JNum("price", price, _Digits) + "," + JNum("profit", profit) + "," + JStr("reason", why) + ","
                        + JStr("currency", AccountInfoString(ACCOUNT_CURRENCY)));
         WriteStatus();
        }
  }

//+------------------------------------------------------------------+
void ProcessCommands()
  {
   BridgeCommand cmds[];
   int n = g_bridge.ReadCommands(cmds);
   for(int i = 0; i < n; i++)
     {
      string msg = "";
      bool ok = true;
      string cmd = cmds[i].cmd;
      string arg = cmds[i].arg;

      if(cmd == "status")
         msg = "ok";
      else
         if(cmd == "pause")
           {
            if(g_risk.State() == EA_HALTED)
              {
               ok = false;
               msg = "EA is halted; use /resume";
              }
            else
              {
               g_risk.SetState(EA_PAUSED);
               msg = "Paused. Open positions are still managed.";
              }
           }
         else
            if(cmd == "resume")
              {
               bool wasHalted = (g_risk.State() == EA_HALTED);
               g_risk.Resume();
               msg = wasHalted ? "Resumed from halt. Equity peak reset to current equity." : "Resumed.";
              }
            else
               if(cmd == "close")
                 {
                  if(arg == "all")
                     msg = StringFormat("Closed %d position(s).", CloseAllSystems());
                  else
                    {
                     ulong ticket = (ulong)StringToInteger(arg);
                     int sys = PositionSelectByTicket(ticket) ? SystemOf(PositionGetInteger(POSITION_MAGIC)) : -1;
                     ok = (sys >= 0) && g_exec[sys].Close(ticket);
                     msg = ok ? StringFormat("Closed #%I64u.", ticket) : StringFormat("Could not close #%s (not found or not ours).", arg);
                    }
                 }
               else
                  if(cmd == "risk")
                    {
                     double pct = StringToDouble(arg);
                     ok = g_risk.SetRiskPct(pct);
                     msg = ok ? StringFormat("Risk per trade set to %.2f%%.", pct)
                           : StringFormat("Risk must be between 0.05 and %.2f%%.", InpMaxRiskPct);
                    }
                  else
                     if(cmd == "kill")
                       {
                        g_risk.SetState(EA_HALTED);
                        int closed = CloseAllSystems();
                        msg = StringFormat("KILL: closed %d position(s), EA halted. Use /resume to restart.", closed);
                       }
                     else
                       {
                        ok = false;
                        msg = "Unknown command: " + cmd;
                       }

      g_bridge.Event("cmd_result", ok ? "info" : "warning", msg,
                     JStr("id", cmds[i].id) + "," + JStr("cmd", cmd) + "," + JBool("ok", ok));
      WriteStatus();
     }
  }

//+------------------------------------------------------------------+
void WriteStatus()
  {
   g_lastStatus = TimeLocal();
   if(!g_bridge.Enabled())
      return;

   string positions = "";
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || SystemOf(PositionGetInteger(POSITION_MAGIC)) < 0 || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(positions != "")
         positions += ",";
      positions += "{" + JInt("ticket", (long)ticket) + ","
                   + JStr("side", PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY" : "SELL") + ","
                   + JNum("volume", PositionGetDouble(POSITION_VOLUME)) + ","
                   + JNum("open", PositionGetDouble(POSITION_PRICE_OPEN), _Digits) + ","
                   + JNum("sl", PositionGetDouble(POSITION_SL), _Digits) + ","
                   + JNum("tp", PositionGetDouble(POSITION_TP), _Digits) + ","
                   + JNum("profit", PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP)) + "}";
     }

   string json = "{"
                 + JInt("ts", (long)TimeGMT()) + ","
                 + JStr("server_time", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)) + ","
                 + JStr("state", g_risk.StateName()) + ","
                 + JStr("symbol", _Symbol) + ","
                 + JInt("login", AccountInfoInteger(ACCOUNT_LOGIN)) + ","
                 + JBool("demo", AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO) + ","
                 + JBool("algo_trading", (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && (bool)MQLInfoInteger(MQL_TRADE_ALLOWED)) + ","
                 + JBool("connected", (bool)TerminalInfoInteger(TERMINAL_CONNECTED)) + ","
                 + JStr("currency", AccountInfoString(ACCOUNT_CURRENCY)) + ","
                 + JNum("balance", AccountInfoDouble(ACCOUNT_BALANCE)) + ","
                 + JNum("equity", AccountInfoDouble(ACCOUNT_EQUITY)) + ","
                 + JNum("margin_level", AccountInfoDouble(ACCOUNT_MARGIN_LEVEL)) + ","
                 + JNum("risk_pct", g_risk.RiskPct()) + ","
                 + JNum("daily_pnl_pct", g_risk.DailyPnlPct()) + ","
                 + JNum("dd_pct", g_risk.DrawdownPct()) + ","
                 + JNum("max_dd_pct", InpMaxDrawdown) + ","
                 + JNum("peak", g_risk.Peak()) + ","
                 + JInt("trades_today", g_risk.TradesToday()) + ","
                 + JInt("consec_losses", g_risk.ConsecLosses()) + ","
                 + JInt("spread", g_filters.SpreadPoints()) + ","
                 + JInt("trend", g_signal[0].Trend()) + ","
                 + "\"positions\":[" + positions + "]}";
   g_bridge.WriteStatus(json);
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Optimization score ("Custom max" in the Strategy Tester).        |
//| Rewards profit factor above 1 and trade count, punishes drawdown.|
//+------------------------------------------------------------------+
double OnTester()
  {
   double trades = TesterStatistics(STAT_TRADES);
   double pf = TesterStatistics(STAT_PROFIT_FACTOR);
   double dd = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   if(trades < 100)
      return -100;
   return (pf - 1.0) * MathSqrt(trades) * MathMax(0.0, 1.0 - dd / 50.0);
  }
//+------------------------------------------------------------------+
