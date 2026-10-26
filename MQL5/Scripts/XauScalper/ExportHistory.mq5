//+------------------------------------------------------------------+
//| ExportHistory.mq5                                                |
//| Writes M1 bars (with spread) of the chart symbol to              |
//| Common\Files\XauScalper\data\<symbol>_M1.csv for research.       |
//+------------------------------------------------------------------+
#property script_show_inputs

input datetime InpFrom = D'2023.01.01';   // Export from
input string   InpDir  = "XauScalper\\data";

void OnStart()
  {
   string symbol = _Symbol;
   string path = InpDir + "\\" + symbol + "_M1.csv";
   int h = FileOpen(path, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(h == INVALID_HANDLE)
     {
      Print("Cannot open ", path, " error ", GetLastError());
      return;
     }
   FileWrite(h, "time", "open", "high", "low", "close", "tick_volume", "spread");
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   long total = 0;
   datetime end = TimeCurrent();

   // One month at a time so large ranges load reliably from the server.
   for(datetime from = InpFrom; from < end; from += 30 * 86400)
     {
      datetime to = MathMin(from + 30 * 86400 - 60, end);
      MqlRates rates[];
      int n = -1;
      for(int attempt = 0; attempt < 10 && n < 0; attempt++)
        {
         n = CopyRates(symbol, PERIOD_M1, from, to, rates);
         if(n < 0)
            Sleep(500);
        }
      for(int i = 0; i < n; i++)
         FileWrite(h, (long)rates[i].time, DoubleToString(rates[i].open, digits), DoubleToString(rates[i].high, digits),
                   DoubleToString(rates[i].low, digits), DoubleToString(rates[i].close, digits),
                   rates[i].tick_volume, rates[i].spread);
      total += MathMax(n, 0);
      Comment(StringFormat("Exporting %s: %s ... %I64d bars", symbol, TimeToString(from, TIME_DATE), total));
     }
   FileClose(h);
   Comment("");
   PrintFormat("Export done: %I64d M1 bars of %s written to Common\\Files\\%s", total, symbol, path);
   Alert(StringFormat("Export done: %I64d bars", total));
  }
//+------------------------------------------------------------------+
