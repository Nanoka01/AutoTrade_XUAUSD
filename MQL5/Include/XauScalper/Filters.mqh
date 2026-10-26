//+------------------------------------------------------------------+
//| Filters.mqh                                                      |
//| Market-condition filters: spread, trading session, news.         |
//| All hours are broker SERVER time (the time shown in Market Watch)|
//+------------------------------------------------------------------+

class CFilters
  {
private:
   string            m_symbol;
   int               m_maxSpreadPoints;
   int               m_sessionStartHour;
   int               m_sessionEndHour;
   int               m_fridayCloseHour;
   bool              m_useNews;
   int               m_newsMinutes;
   string            m_newsCurrency;
   bool              m_isTester;
   datetime          m_newsCheckedAt;
   bool              m_newsBlocked;
   string            m_newsReason;

public:
   void              Init(const string symbol, const int maxSpreadPoints, const int sessionStart, const int sessionEnd,
                          const int fridayCloseHour, const bool useNews, const int newsMinutes, const string newsCurrency)
     {
      m_symbol = symbol;
      m_maxSpreadPoints = maxSpreadPoints;
      m_sessionStartHour = sessionStart;
      m_sessionEndHour = sessionEnd;
      m_fridayCloseHour = fridayCloseHour;
      m_useNews = useNews;
      m_newsMinutes = newsMinutes;
      m_newsCurrency = newsCurrency;
      m_isTester = (bool)MQLInfoInteger(MQL_TESTER);
      m_newsCheckedAt = 0;
      m_newsBlocked = false;
      m_newsReason = "";
     }

   int               SpreadPoints(void) const
     {
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point <= 0)
         return 0;
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      return (int)MathRound((ask - bid) / point);
     }

   bool              SpreadOk(void) const { return SpreadPoints() <= m_maxSpreadPoints; }

   bool              SessionOk(void) const
     {
      MqlDateTime t;
      TimeToStruct(TimeCurrent(), t);
      if(t.day_of_week == 0 || t.day_of_week == 6)
         return false;
      if(t.day_of_week == 5 && t.hour >= m_fridayCloseHour)
         return false;
      if(m_sessionStartHour <= m_sessionEndHour)
         return t.hour >= m_sessionStartHour && t.hour < m_sessionEndHour;
      return t.hour >= m_sessionStartHour || t.hour < m_sessionEndHour;  // session crosses midnight
     }

   // True once Friday reaches the close hour: all positions should be flat before the weekend.
   bool              IsFridayClose(void) const
     {
      MqlDateTime t;
      TimeToStruct(TimeCurrent(), t);
      return t.day_of_week == 5 && t.hour >= m_fridayCloseHour;
     }

   // Blocks trading m_newsMinutes before and after high-impact news for m_newsCurrency.
   // Uses the MT5 economic calendar, which is not available in the Strategy Tester.
   bool              NewsOk(string &reason)
     {
      reason = "";
      if(!m_useNews || m_isTester)
         return true;
      datetime now = TimeTradeServer();
      if(now - m_newsCheckedAt < 60)
        {
         reason = m_newsReason;
         return !m_newsBlocked;
        }
      m_newsCheckedAt = now;
      m_newsBlocked = false;
      m_newsReason = "";

      MqlCalendarValue values[];
      int window = m_newsMinutes * 60;
      if(CalendarValueHistory(values, now - window, now + window, NULL, m_newsCurrency) > 0)
        {
         for(int i = 0; i < ArraySize(values); i++)
           {
            MqlCalendarEvent ev;
            if(!CalendarEventById(values[i].event_id, ev))
               continue;
            if(ev.importance != CALENDAR_IMPORTANCE_HIGH)
               continue;
            m_newsBlocked = true;
            m_newsReason = StringFormat("%s news: %s at %s", m_newsCurrency, ev.name, TimeToString(values[i].time, TIME_MINUTES));
            break;
           }
        }
      reason = m_newsReason;
      return !m_newsBlocked;
     }
  };
//+------------------------------------------------------------------+
