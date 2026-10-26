//+------------------------------------------------------------------+
//| TradeExecutor.mqh                                                |
//| Sends and closes orders through CTrade, with retries.            |
//| Every order carries a hard stop loss on the broker side.         |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include "Bridge.mqh"

class CTradeExecutor
  {
private:
   string            m_symbol;
   long              m_magic;
   int               m_retries;
   CTrade            m_trade;

   bool              Retryable(const uint code) const
     {
      return code == TRADE_RETCODE_REQUOTE || code == TRADE_RETCODE_PRICE_CHANGED || code == TRADE_RETCODE_PRICE_OFF
             || code == TRADE_RETCODE_TIMEOUT || code == TRADE_RETCODE_CONNECTION || code == TRADE_RETCODE_TOO_MANY_REQUESTS;
     }

public:
   void              Init(const string symbol, const long magic, const int deviationPoints, const int retries)
     {
      m_symbol = symbol;
      m_magic = magic;
      m_retries = MathMax(1, retries);
      m_trade.SetExpertMagicNumber((ulong)magic);
      m_trade.SetDeviationInPoints(deviationPoints);
      m_trade.SetTypeFillingBySymbol(symbol);
      m_trade.SetMarginMode();
     }

   CTrade           *Trade(void) { return GetPointer(m_trade); }

   // stopDistance and takeDistance are in price units. Returns the position ticket, or 0 on failure.
   ulong             Open(const ENUM_ORDER_TYPE type, const double lots, const double stopDistance, const double takeDistance,
                          const string comment)
     {
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double minStop = (double)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
      double sd = MathMax(stopDistance, minStop + 2 * point);
      double td = MathMax(takeDistance, minStop + 2 * point);

      for(int attempt = 1; attempt <= m_retries; attempt++)
        {
         MqlTick tick;
         if(!SymbolInfoTick(m_symbol, tick))
           {
            Sleep(200);
            continue;
           }
         bool ok;
         if(type == ORDER_TYPE_BUY)
           {
            double sl = NormalizeDouble(tick.bid - sd, digits);
            double tp = NormalizeDouble(tick.bid + td, digits);
            ok = m_trade.Buy(lots, m_symbol, tick.ask, sl, tp, comment);
           }
         else
           {
            double sl = NormalizeDouble(tick.ask + sd, digits);
            double tp = NormalizeDouble(tick.ask - td, digits);
            ok = m_trade.Sell(lots, m_symbol, tick.bid, sl, tp, comment);
           }
         uint code = m_trade.ResultRetcode();
         if(ok && (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_PLACED))
            return m_trade.ResultOrder();  // on a netting/hedging account the position ticket equals the opening order ticket
         if(!Retryable(code) || attempt == m_retries)
           {
            g_bridge.Event("order_error", "warning",
                           StringFormat("Order failed: %s %.2f lots, retcode %u (%s)",
                                        type == ORDER_TYPE_BUY ? "BUY" : "SELL", lots, code, m_trade.ResultRetcodeDescription()),
                           JInt("retcode", code));
            return 0;
           }
         Sleep(300);
        }
      return 0;
     }

   bool              IsOurs(const ulong ticket) const
     {
      if(!PositionSelectByTicket(ticket))
         return false;
      return PositionGetInteger(POSITION_MAGIC) == m_magic && PositionGetString(POSITION_SYMBOL) == m_symbol;
     }

   bool              Close(const ulong ticket)
     {
      if(!IsOurs(ticket))
         return false;
      for(int attempt = 1; attempt <= m_retries; attempt++)
        {
         if(m_trade.PositionClose(ticket))
            return true;
         if(!Retryable(m_trade.ResultRetcode()))
            break;
         Sleep(300);
        }
      g_bridge.Event("order_error", "warning",
                     StringFormat("Close failed for #%I64u: retcode %u (%s)", ticket, m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription()));
      return false;
     }

   // Closes every position of this EA. Returns how many were closed.
   int               CloseAll(void)
     {
      int closed = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !IsOurs(ticket))
            continue;
         if(Close(ticket))
            closed++;
        }
      return closed;
     }

   int               CountOpen(void) const
     {
      int n = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket != 0 && IsOurs(ticket))
            n++;
        }
      return n;
     }
  };
//+------------------------------------------------------------------+
