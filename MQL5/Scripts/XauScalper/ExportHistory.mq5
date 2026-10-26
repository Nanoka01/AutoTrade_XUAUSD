//+------------------------------------------------------------------+
//| ExportHistory.mq5                                                |
//| Writes M1 bars (with spread) to                                  |
//| Common\Files\XauScalper\data\<symbol>_M1.csv for research.       |
//| InpSymbols: comma-separated list; empty = the chart symbol.      |
//| Symbols the broker does not offer are skipped.                   |
//+------------------------------------------------------------------+
#property script_show_inputs

input datetime InpFrom    = D'2023.01.01';   // Export from
input string   InpDir     = "XauScalper\\data";
input string   InpSymbols = "";              // e.g. XAGUSD,EURUSD,GBPJPY,US30 (empty = chart symbol)

long ExportSymbol(const string symbol)
  {
   if(!SymbolSelect(symbol, true))
     {
      PrintFormat("Skip %s: not offered by this broker", symbol);
      return -1;
     }
   string path = InpDir + "\\" + symbol + "_M1.csv";
   int h = FileOpen(path, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(h == INVALID_HANDLE)
     {
      Print("Cannot open ", path, " error ", GetLastError());
      return -1;
     }
   FileWrite(h, "time", "open", "high", "low", "close", "tick_volume", "spread");
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   long total = 0;
   datetime end = TimeCurrent();

   // One month at a time so large ranges load reliably from the server.
   for(datetime from = InpFrom; from < end && !IsStopped(); from += 30 * 86400)
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
   PrintFormat("Export done: %I64d M1 bars of %s written to Common\\Files\\%s (point %s)", total, symbol, path,
               DoubleToString(SymbolInfoDouble(symbol, SYMBOL_POINT), digits));
   return total;
  }

void OnStart()
  {
   string list = InpSymbols == "" ? _Symbol : InpSymbols;
   string symbols[];
   int n = StringSplit(list, ',', symbols);
   string summary = "";
   for(int i = 0; i < n && !IsStopped(); i++)
     {
      string s = symbols[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      if(s == "")
         continue;
      long bars = ExportSymbol(s);
      summary += StringFormat("%s: %s\n", s, bars < 0 ? "skipped" : IntegerToString(bars) + " bars");
     }
   Comment("");
   Print(summary);
   Alert("Export done\n" + summary);
  }
//+------------------------------------------------------------------+
