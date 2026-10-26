//+------------------------------------------------------------------+
//| Bridge.mqh                                                       |
//| File bridge between the EA and the Discord bot.                  |
//| Everything lives in the terminal's Common\Files folder:          |
//|   <dir>\status.json        EA -> bot, rewritten every few seconds |
//|   <dir>\events\*.json      EA -> bot, one file per event          |
//|   <dir>\commands\*.cmd     bot -> EA, one file per command        |
//| Files are written as .tmp first, then renamed, so the reader     |
//| never sees a half-written file.                                  |
//+------------------------------------------------------------------+

string JsonEscape(string s)
  {
   StringReplace(s, "\\", "\\\\");
   StringReplace(s, "\"", "\\\"");
   StringReplace(s, "\r", " ");
   StringReplace(s, "\n", " ");
   return s;
  }

string JStr(const string key, const string value)  { return "\"" + key + "\":\"" + JsonEscape(value) + "\""; }
string JNum(const string key, const double value, const int digits = 2) { return "\"" + key + "\":" + DoubleToString(value, digits); }
string JInt(const string key, const long value)    { return "\"" + key + "\":" + IntegerToString(value); }
string JBool(const string key, const bool value)   { return "\"" + key + "\":" + (value ? "true" : "false"); }

struct BridgeCommand
  {
   string            id;
   string            cmd;
   string            arg;
  };

class CBridge
  {
private:
   bool              m_enabled;
   string            m_dir;
   ulong             m_counter;

   bool              WriteAtomic(const string tmpPath, const string finalPath, const string content)
     {
      int h = FileOpen(tmpPath, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON, '\t', CP_UTF8);
      if(h == INVALID_HANDLE)
        {
         PrintFormat("Bridge: cannot open %s (error %d)", tmpPath, GetLastError());
         return false;
        }
      FileWriteString(h, content);
      FileClose(h);
      if(!FileMove(tmpPath, FILE_COMMON, finalPath, FILE_COMMON | FILE_REWRITE))
        {
         PrintFormat("Bridge: cannot move %s -> %s (error %d)", tmpPath, finalPath, GetLastError());
         return false;
        }
      return true;
     }

public:
                     CBridge(void) : m_enabled(false), m_dir("XauScalper"), m_counter(0) {}

   void              Init(const bool enabled, const string dir)
     {
      m_enabled = enabled;
      m_dir = dir;
      if(!m_enabled)
         return;
      FolderCreate(m_dir, FILE_COMMON);
      FolderCreate(m_dir + "\\events", FILE_COMMON);
      FolderCreate(m_dir + "\\commands", FILE_COMMON);
     }

   bool              Enabled(void) const { return m_enabled; }

   void              WriteStatus(const string json)
     {
      if(!m_enabled)
         return;
      WriteAtomic(m_dir + "\\status.tmp", m_dir + "\\status.json", json);
     }

   // level: info | warning | critical. dataJson: comma-separated JSON fields without braces, or "".
   void              Event(const string type, const string level, const string msg, const string dataJson = "")
     {
      PrintFormat("[%s] %s: %s", level, type, msg);
      if(!m_enabled)
         return;
      m_counter++;
      string name = StringFormat("evt_%I64u_%I64u", GetTickCount64(), m_counter);
      string json = "{" + JStr("type", type) + "," + JStr("level", level) + "," + JStr("msg", msg) + ","
                    + JInt("ts", (long)TimeGMT()) + ",\"data\":{" + dataJson + "}}";
      WriteAtomic(m_dir + "\\events\\" + name + ".tmp", m_dir + "\\events\\" + name + ".json", json);
     }

   // Reads and deletes every pending command file. Returns the number of commands read.
   int               ReadCommands(BridgeCommand &out[])
     {
      ArrayResize(out, 0);
      if(!m_enabled)
         return 0;
      string fileName;
      long search = FileFindFirst(m_dir + "\\commands\\*.cmd", fileName, FILE_COMMON);
      if(search == INVALID_HANDLE)
         return 0;
      string names[];
      do
        {
         int n = ArraySize(names);
         ArrayResize(names, n + 1);
         names[n] = fileName;
        }
      while(FileFindNext(search, fileName));
      FileFindClose(search);

      for(int i = 0; i < ArraySize(names); i++)
        {
         string path = m_dir + "\\commands\\" + names[i];
         int h = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON, '\t', CP_UTF8);
         if(h == INVALID_HANDLE)
            continue;
         BridgeCommand c;
         c.id = "";
         c.cmd = "";
         c.arg = "";
         while(!FileIsEnding(h))
           {
            string line = FileReadString(h);
            StringTrimLeft(line);
            StringTrimRight(line);
            int eq = StringFind(line, "=");
            if(eq <= 0)
               continue;
            string key = StringSubstr(line, 0, eq);
            string val = StringSubstr(line, eq + 1);
            if(key == "id")
               c.id = val;
            else
               if(key == "cmd")
                  c.cmd = val;
               else
                  if(key == "arg")
                     c.arg = val;
           }
         FileClose(h);
         FileDelete(path, FILE_COMMON);
         if(c.cmd == "")
            continue;
         int n = ArraySize(out);
         ArrayResize(out, n + 1);
         out[n] = c;
        }
      return ArraySize(out);
     }
  };

CBridge g_bridge;
//+------------------------------------------------------------------+
