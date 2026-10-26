//+------------------------------------------------------------------+
//| PositionManager.mqh                                              |
//| Breakeven and ATR trailing stop for open positions.              |
//| "R" is the initial stop distance, read from the stop loss the    |
//| position was opened with and kept in a global variable.          |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

class CPositionManager
  {
private:
   string            m_symbol;
   long              m_magic;
   string            m_prefix;
   double            m_breakevenAtR;
   double            m_trailStartR;
   double            m_trailAtrMult;

   string            RKey(const ulong ticket) const { return m_prefix + "r_" + IntegerToString((long)ticket); }

public:
   void              Init(const string symbol, const long magic, const double breakevenAtR, const double trailStartR,
                          const double trailAtrMult)
     {
      m_symbol = symbol;
      m_magic = magic;
      m_prefix = ((bool)MQLInfoInteger(MQL_TESTER) ? "XST_" : "XS_") + IntegerToString(magic) + "_";
      m_breakevenAtR = breakevenAtR;
      m_trailStartR = trailStartR;
      m_trailAtrMult = trailAtrMult;
     }

   void              Forget(const ulong ticket) const { GlobalVariableDel(RKey(ticket)); }

   // True when the current server time is inside one of the symbol's trading sessions.
   bool              TradeSessionOpen(void) const
     {
      MqlDateTime t;
      TimeToStruct(TimeCurrent(), t);
      datetime secs = (datetime)(t.hour * 3600 + t.min * 60 + t.sec);
      datetime from, to;
      for(uint i = 0; SymbolInfoSessionTrade(m_symbol, (ENUM_DAY_OF_WEEK)t.day_of_week, i, from, to); i++)
         if(secs >= from && secs < to)
            return true;
      return false;
     }

   void              Manage(CTrade *trade, const double atr)
     {
      if(!TradeSessionOpen())
         return;
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double minStop = (double)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
      MqlTick tick;
      if(!SymbolInfoTick(m_symbol, tick))
         return;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magic || PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;

         long type = PositionGetInteger(POSITION_TYPE);
         double open = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);
         if(sl <= 0)
            continue;

         string key = RKey(ticket);
         if(!GlobalVariableCheck(key))
            GlobalVariableSet(key, MathAbs(open - sl));
         double r = GlobalVariableGet(key);
         if(r <= 0)
            continue;

         bool isBuy = (type == POSITION_TYPE_BUY);
         double price = isBuy ? tick.bid : tick.ask;
         double moved = isBuy ? price - open : open - price;
         double newSl = sl;

         // Breakeven (0 = off): lock the entry plus the current spread once price has moved enough.
         if(m_breakevenAtR > 0 && moved >= m_breakevenAtR * r)
           {
            double spread = tick.ask - tick.bid;
            double be = isBuy ? open + spread : open - spread;
            if(isBuy && be > newSl)
               newSl = be;
            if(!isBuy && be < newSl)
               newSl = be;
           }

         // ATR trailing stop (start 0 = off).
         if(atr > 0 && m_trailStartR > 0 && moved >= m_trailStartR * r)
           {
            double trail = isBuy ? price - m_trailAtrMult * atr : price + m_trailAtrMult * atr;
            if(isBuy && trail > newSl)
               newSl = trail;
            if(!isBuy && trail < newSl)
               newSl = trail;
           }

         newSl = NormalizeDouble(newSl, digits);
         // Move the stop only in meaningful steps (10% of ATR, at least 10 points) so the
         // broker is not flooded with modify requests on every tick.
         double minStep = MathMax(10 * point, 0.1 * atr);
         if(MathAbs(newSl - sl) < minStep)
            continue;
         // Respect the broker's minimum stop distance.
         if(isBuy && price - newSl < minStop)
            continue;
         if(!isBuy && newSl - price < minStop)
            continue;
         if(trade != NULL)
            trade.PositionModify(ticket, newSl, tp);
        }
     }
  };
//+------------------------------------------------------------------+
