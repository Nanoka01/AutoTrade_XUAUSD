//+------------------------------------------------------------------+
//| Signal.mqh                                                       |
//| Trend-following scalp entry:                                     |
//|  1. Trend on the higher timeframe: fast EMA above slow EMA and   |
//|     the last closed bar above the fast EMA (mirror for shorts).  |
//|  2. Pullback on the entry timeframe: one of the last N closed    |
//|     bars touched the entry EMA.                                  |
//|  3. Trigger: the last closed bar closed back beyond the entry    |
//|     EMA and RSI crossed the mid level in the trend direction.    |
//| Only closed bars are used, so a signal never repaints.           |
//+------------------------------------------------------------------+

enum ENUM_SIGNAL
  {
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1
  };

class CSignal
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_trendTf;
   ENUM_TIMEFRAMES   m_entryTf;
   int               m_pullbackBars;
   double            m_rsiMid;
   int               m_hTrendFast;
   int               m_hTrendSlow;
   int               m_hEntryEma;
   int               m_hRsi;
   int               m_hAtr;

   bool              Copy(const int handle, const int count, double &buf[]) const
     {
      ArraySetAsSeries(buf, true);
      return CopyBuffer(handle, 0, 0, count, buf) == count;
     }

public:
                     CSignal(void) : m_hTrendFast(INVALID_HANDLE), m_hTrendSlow(INVALID_HANDLE), m_hEntryEma(INVALID_HANDLE),
                     m_hRsi(INVALID_HANDLE), m_hAtr(INVALID_HANDLE) {}

   bool              Init(const string symbol, const ENUM_TIMEFRAMES trendTf, const int fastEma, const int slowEma,
                          const ENUM_TIMEFRAMES entryTf, const int entryEma, const int rsiPeriod, const double rsiMid,
                          const int atrPeriod, const int pullbackBars)
     {
      m_symbol = symbol;
      m_trendTf = trendTf;
      m_entryTf = entryTf;
      m_rsiMid = rsiMid;
      m_pullbackBars = MathMax(1, pullbackBars);
      m_hTrendFast = iMA(symbol, trendTf, fastEma, 0, MODE_EMA, PRICE_CLOSE);
      m_hTrendSlow = iMA(symbol, trendTf, slowEma, 0, MODE_EMA, PRICE_CLOSE);
      m_hEntryEma = iMA(symbol, entryTf, entryEma, 0, MODE_EMA, PRICE_CLOSE);
      m_hRsi = iRSI(symbol, entryTf, rsiPeriod, PRICE_CLOSE);
      m_hAtr = iATR(symbol, entryTf, atrPeriod);
      return m_hTrendFast != INVALID_HANDLE && m_hTrendSlow != INVALID_HANDLE && m_hEntryEma != INVALID_HANDLE
             && m_hRsi != INVALID_HANDLE && m_hAtr != INVALID_HANDLE;
     }

   void              Release(void)
     {
      if(m_hTrendFast != INVALID_HANDLE) IndicatorRelease(m_hTrendFast);
      if(m_hTrendSlow != INVALID_HANDLE) IndicatorRelease(m_hTrendSlow);
      if(m_hEntryEma != INVALID_HANDLE)  IndicatorRelease(m_hEntryEma);
      if(m_hRsi != INVALID_HANDLE)       IndicatorRelease(m_hRsi);
      if(m_hAtr != INVALID_HANDLE)       IndicatorRelease(m_hAtr);
     }

   // ATR of the last closed entry bar, in price units. 0 when data is not ready.
   double            Atr(void) const
     {
      double atr[];
      if(!Copy(m_hAtr, 2, atr))
         return 0;
      return atr[1];
     }

   // +1 uptrend, -1 downtrend, 0 no clear trend.
   int               Trend(void) const
     {
      double fast[], slow[];
      if(!Copy(m_hTrendFast, 2, fast) || !Copy(m_hTrendSlow, 2, slow))
         return 0;
      double close1 = iClose(m_symbol, m_trendTf, 1);
      if(fast[1] > slow[1] && close1 > fast[1])
         return 1;
      if(fast[1] < slow[1] && close1 < fast[1])
         return -1;
      return 0;
     }

   ENUM_SIGNAL       Check(void) const
     {
      int trend = Trend();
      if(trend == 0)
         return SIGNAL_NONE;

      int need = m_pullbackBars + 2;
      double ema[], rsi[];
      if(!Copy(m_hEntryEma, need, ema) || !Copy(m_hRsi, 3, rsi))
         return SIGNAL_NONE;

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(m_symbol, m_entryTf, 0, need, rates) != need)
         return SIGNAL_NONE;

      bool touched = false;
      for(int i = 1; i <= m_pullbackBars; i++)
        {
         if(trend > 0 && rates[i].low <= ema[i])
            touched = true;
         if(trend < 0 && rates[i].high >= ema[i])
            touched = true;
        }
      if(!touched)
         return SIGNAL_NONE;

      if(trend > 0 && rates[1].close > ema[1] && rsi[2] < m_rsiMid && rsi[1] >= m_rsiMid)
         return SIGNAL_BUY;
      if(trend < 0 && rates[1].close < ema[1] && rsi[2] > (100.0 - m_rsiMid) && rsi[1] <= (100.0 - m_rsiMid))
         return SIGNAL_SELL;
      return SIGNAL_NONE;
     }
  };
//+------------------------------------------------------------------+
