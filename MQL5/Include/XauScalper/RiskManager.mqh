//+------------------------------------------------------------------+
//| RiskManager.mqh                                                  |
//| Position sizing and account-level limits.                        |
//| State is kept in terminal global variables so a restart of the   |
//| terminal or EA does not reset the equity peak or daily counters. |
//+------------------------------------------------------------------+
#include "Bridge.mqh"

enum ENUM_EA_STATE
  {
   EA_RUNNING = 0,   // opens new trades
   EA_PAUSED  = 1,   // paused from Discord; open trades are still managed
   EA_HALTED  = 2    // max drawdown hit or /kill; needs /resume
  };

class CRiskManager
  {
private:
   string            m_symbol;
   string            m_prefix;
   double            m_maxRiskCap;
   double            m_maxDailyLossPct;
   double            m_maxDrawdownPct;
   int               m_maxConsecLosses;
   int               m_cooldownMinutes;
   int               m_maxTradesPerDay;
   bool              m_dailyAlerted;
   bool              m_autoResumeNewDay;

   double            GetGv(const string name, const double def) const
     {
      string key = m_prefix + name;
      if(GlobalVariableCheck(key))
         return GlobalVariableGet(key);
      return def;
     }
   void              SetGv(const string name, const double value) const { GlobalVariableSet(m_prefix + name, value); }

   datetime          DayStart(const datetime t) const { return t - (t % 86400); }

public:
   void              Init(const string symbol, const long magic, const double riskPct, const double maxRiskCap,
                          const double maxDailyLossPct, const double maxDrawdownPct, const int maxConsecLosses,
                          const int cooldownMinutes, const int maxTradesPerDay)
     {
      m_symbol = symbol;
      m_prefix = "XS_" + IntegerToString(magic) + "_";
      if((bool)MQLInfoInteger(MQL_TESTER))
         m_prefix = "XST_" + IntegerToString(magic) + "_";
      m_maxRiskCap = maxRiskCap;
      m_maxDailyLossPct = maxDailyLossPct;
      m_maxDrawdownPct = maxDrawdownPct;
      m_maxConsecLosses = maxConsecLosses;
      m_cooldownMinutes = cooldownMinutes;
      m_maxTradesPerDay = maxTradesPerDay;
      m_dailyAlerted = false;
      m_autoResumeNewDay = false;

      if((bool)MQLInfoInteger(MQL_TESTER))
        {
         // Fresh state for every test run.
         GlobalVariablesDeleteAll(m_prefix);
        }
      if(!GlobalVariableCheck(m_prefix + "risk"))
         SetGv("risk", riskPct);
      if(!GlobalVariableCheck(m_prefix + "state"))
         SetGv("state", EA_RUNNING);
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(GetGv("peak", 0) <= 0)
         SetGv("peak", equity);
      RollDay();
     }

   // Input risk overrides the stored value only when the user changes the input.
   void              ApplyInputRisk(const double riskPct)
     {
      double last = GetGv("input_risk", -1);
      if(MathAbs(last - riskPct) > 1e-9)
        {
         SetGv("risk", MathMin(riskPct, m_maxRiskCap));
         SetGv("input_risk", riskPct);
        }
     }

   ENUM_EA_STATE     State(void) const        { return (ENUM_EA_STATE)(int)GetGv("state", EA_RUNNING); }
   string            StateName(void) const
     {
      switch(State())
        {
         case EA_PAUSED: return "paused";
         case EA_HALTED: return "halted";
         default:        return "running";
        }
     }
   void              SetState(const ENUM_EA_STATE s) const { SetGv("state", s); }

   double            RiskPct(void) const      { return GetGv("risk", 0.5); }
   bool              SetRiskPct(const double pct)
     {
      if(pct < 0.05 || pct > m_maxRiskCap)
         return false;
      SetGv("risk", pct);
      return true;
     }

   double            Peak(void) const         { return GetGv("peak", AccountInfoDouble(ACCOUNT_EQUITY)); }
   int               TradesToday(void) const  { return (int)GetGv("trades_today", 0); }
   int               ConsecLosses(void) const { return (int)GetGv("consec", 0); }

   double            DrawdownPct(void) const
     {
      double peak = Peak();
      if(peak <= 0)
         return 0;
      return MathMax(0.0, (peak - AccountInfoDouble(ACCOUNT_EQUITY)) / peak * 100.0);
     }

   double            DailyPnlPct(void) const
     {
      double start = GetGv("day_balance", AccountInfoDouble(ACCOUNT_BALANCE));
      if(start <= 0)
         return 0;
      return (AccountInfoDouble(ACCOUNT_EQUITY) - start) / start * 100.0;
     }

   void              RollDay(void)
     {
      datetime today = DayStart(TimeCurrent());
      if((datetime)GetGv("day", 0) != today)
        {
         SetGv("day", (double)today);
         SetGv("day_balance", AccountInfoDouble(ACCOUNT_BALANCE));
         SetGv("trades_today", 0);
         m_dailyAlerted = false;
         if(m_autoResumeNewDay && State() == EA_HALTED)
           {
            Resume();
            Print("Backtest: auto-resumed after a drawdown halt (new day).");
           }
        }
     }

   // Call on every tick and timer. Returns true when the max drawdown limit has just been hit:
   // the caller must close all positions.
   bool              Update(void)
     {
      RollDay();
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity > Peak())
         SetGv("peak", equity);

      if(State() != EA_HALTED && DrawdownPct() >= m_maxDrawdownPct)
        {
         SetState(EA_HALTED);
         SetGv("halts", GetGv("halts", 0) + 1);
         g_bridge.Event("risk_halt", "critical",
                        StringFormat("Max drawdown %.2f%% reached (limit %.2f%%). EA halted, all positions closing. Use /resume after review.",
                                     DrawdownPct(), m_maxDrawdownPct),
                        JNum("dd_pct", DrawdownPct()) + "," + JNum("equity", equity));
         return true;
        }

      if(!m_dailyAlerted && -DailyPnlPct() >= m_maxDailyLossPct)
        {
         m_dailyAlerted = true;
         g_bridge.Event("risk_daily", "warning",
                        StringFormat("Daily loss %.2f%% reached (limit %.2f%%). No new trades until tomorrow (server time).",
                                     -DailyPnlPct(), m_maxDailyLossPct),
                        JNum("daily_pnl_pct", DailyPnlPct()));
        }
      return false;
     }

   // Backtest only: resume the next day after a drawdown halt, so one bad day does not end the whole test.
   void              SetAutoResumeNewDay(const bool on) { m_autoResumeNewDay = on; }
   int               Halts(void) const { return (int)GetGv("halts", 0); }

   void              OnTradeOpened(void) { SetGv("trades_today", TradesToday() + 1); }

   void              OnTradeClosed(const double profit)
     {
      if(profit < 0)
        {
         int c = ConsecLosses() + 1;
         SetGv("consec", c);
         if(c >= m_maxConsecLosses)
           {
            SetGv("cooldown_until", (double)(TimeCurrent() + m_cooldownMinutes * 60));
            SetGv("consec", 0);
            g_bridge.Event("risk_streak", "warning",
                           StringFormat("%d losses in a row. Cooling down for %d minutes.", c, m_cooldownMinutes),
                           JInt("losses", c));
           }
        }
      else
         SetGv("consec", 0);
     }

   // Resume after a pause or halt. A halt resets the equity peak so trading can restart.
   void              Resume(void)
     {
      if(State() == EA_HALTED)
         SetGv("peak", AccountInfoDouble(ACCOUNT_EQUITY));
      SetGv("cooldown_until", 0);
      SetState(EA_RUNNING);
     }

   bool              CanOpen(string &reason) const
     {
      ENUM_EA_STATE s = State();
      if(s != EA_RUNNING)
        {
         reason = "EA is " + StateName();
         return false;
        }
      if(-DailyPnlPct() >= m_maxDailyLossPct)
        {
         reason = "daily loss limit";
         return false;
        }
      if(TradesToday() >= m_maxTradesPerDay)
        {
         reason = "max trades per day";
         return false;
        }
      if(TimeCurrent() < (datetime)GetGv("cooldown_until", 0))
        {
         reason = "cooldown after loss streak";
         return false;
        }
      reason = "";
      return true;
     }

   // Lot size so that hitting the stop loses RiskPct() of equity. Returns 0 when even the
   // minimum lot would risk more than 1.5x the allowed amount (account too small for this stop).
   // Money lost on 1.0 lot when price moves stopDistance against the position, in account currency.
   // OrderCalcProfit uses the same contract size and currency conversion as real P/L, so it is
   // more reliable than tick value (which some servers report wrongly for metals).
   double            LossPerLot(const double stopDistance) const
     {
      double price = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double profit = 0;
      if(price > 0 && OrderCalcProfit(ORDER_TYPE_BUY, m_symbol, 1.0, price, price - stopDistance, profit) && profit < 0)
         return -profit;
      // Fallback: contract size x distance (quote currency = account currency).
      double contract = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      return contract * stopDistance;
     }

   void              PrintSizingInfo(const double sampleStop) const
     {
      PrintFormat("Sizing check %s: contract %.2f, tick size %.5f, tick value %.5f, loss per lot for %.2f stop = %.2f %s",
                  m_symbol, SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE),
                  SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE), SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE),
                  sampleStop, LossPerLot(sampleStop), AccountInfoString(ACCOUNT_CURRENCY));
     }

   double            LotsForStop(const double stopDistance) const
     {
      if(stopDistance <= 0)
         return 0;
      double minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      double step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      double lossPerLot = LossPerLot(stopDistance);
      if(lossPerLot <= 0 || step <= 0)
         return 0;

      double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * RiskPct() / 100.0;
      double lots = MathFloor(riskMoney / lossPerLot / step) * step;
      if(lots < minLot)
        {
         if(minLot * lossPerLot > riskMoney * 1.5)
            return 0;
         lots = minLot;
        }
      lots = MathMin(lots, maxLot);
      return NormalizeDouble(lots, 2);
     }
  };
//+------------------------------------------------------------------+
