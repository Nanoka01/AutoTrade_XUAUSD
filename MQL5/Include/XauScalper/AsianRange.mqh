//+------------------------------------------------------------------+
//| AsianRange.mqh                                                   |
//| Asian range breakout:                                            |
//|  1. Range = high/low of the M5 bars from StartHour to EndHour    |
//|     (server time) of the current day.                            |
//|  2. Daily bias: yesterday's D1 close above its EMA (mirror).     |
//|  3. Trigger: the first M5 close beyond the range in the bias     |
//|     direction between EndHour and LastEntryHour. One per day.    |
//| Stop = range width x multiplier, so StopDistance() is set by     |
//| the last signal.                                                 |
//+------------------------------------------------------------------+
// Needs Signal.mqh (ENUM_SIGNAL) included first.

class CAsianRange
  {
private:
   string            m_symbol;
   int               m_startHour;
   int               m_endHour;
   int               m_lastEntryHour;
   double            m_slMult;
   int               m_hDailyEma;
   datetime          m_usedDay;
   double            m_stop;

   int               DailyBias(void) const
     {
      double ema[];
      ArraySetAsSeries(ema, true);
      if(CopyBuffer(m_hDailyEma, 0, 0, 2, ema) != 2)
         return 0;
      double close1 = iClose(m_symbol, PERIOD_D1, 1);
      if(close1 <= 0)
         return 0;
      return close1 > ema[1] ? 1 : (close1 < ema[1] ? -1 : 0);
     }

public:
                     CAsianRange(void) : m_hDailyEma(INVALID_HANDLE), m_usedDay(0), m_stop(0) {}

   bool              Init(const string symbol, const int startHour, const int endHour, const int lastEntryHour,
                          const double slMult, const int dailyEma)
     {
      m_symbol = symbol;
      m_startHour = startHour;
      m_endHour = endHour;
      m_lastEntryHour = lastEntryHour;
      m_slMult = slMult;
      m_hDailyEma = iMA(symbol, PERIOD_D1, dailyEma, 0, MODE_EMA, PRICE_CLOSE);
      return m_hDailyEma != INVALID_HANDLE;
     }

   void              Release(void)
     {
      if(m_hDailyEma != INVALID_HANDLE)
         IndicatorRelease(m_hDailyEma);
     }

   double            StopDistance(void) const { return m_stop; }

   // Call once per new M5 bar.
   ENUM_SIGNAL       Check(void)
     {
      MqlRates last[];
      ArraySetAsSeries(last, true);
      if(CopyRates(m_symbol, PERIOD_M5, 1, 1, last) != 1)
         return SIGNAL_NONE;
      datetime t = last[0].time;
      datetime day = t - (t % 86400);
      MqlDateTime dt;
      TimeToStruct(t, dt);
      if(day == m_usedDay || dt.hour < m_endHour || dt.hour >= m_lastEntryHour)
         return SIGNAL_NONE;

      MqlRates rng[];
      int n = CopyRates(m_symbol, PERIOD_M5, day + m_startHour * 3600, day + m_endHour * 3600 - 1, rng);
      if(n <= 0)
         return SIGNAL_NONE;
      double hi = rng[0].high, lo = rng[0].low;
      for(int i = 1; i < n; i++)
        {
         hi = MathMax(hi, rng[i].high);
         lo = MathMin(lo, rng[i].low);
        }

      int bias = DailyBias();
      ENUM_SIGNAL sig = SIGNAL_NONE;
      if(bias > 0 && last[0].close > hi)
         sig = SIGNAL_BUY;
      if(bias < 0 && last[0].close < lo)
         sig = SIGNAL_SELL;
      if(sig == SIGNAL_NONE)
         return SIGNAL_NONE;
      m_usedDay = day;   // only the first breakout of the day counts, taken or not
      m_stop = (hi - lo) * m_slMult;
      return sig;
     }
  };
//+------------------------------------------------------------------+
