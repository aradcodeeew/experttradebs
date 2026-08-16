//+------------------------------------------------------------------+
//|                    Price Path Analyzer v1.0                      |
//|              تجزیه و تحلیل مسیر قیمت داخل کندل‌ها                 |
//|                    For MetaTrader 5 (Analysis Only)               |
//+------------------------------------------------------------------+

#property strict
#property indicator_chart_window
#property indicator_buffers 0

//--- Input Parameters
enum DISPLAY_MODE
{
   MODE_OVERLAY = 0,      // روی خود چارت
   MODE_SUBWINDOW = 1,    // پایین چارت
   MODE_SEPARATE = 2      // پنجره جداگانه
};

input DISPLAY_MODE DisplayMode = MODE_OVERLAY;
input bool ShowPath = true;
input color PathColor = clrDodgerBlue;
input int PathWidth = 2;
input bool ShowPoints = true;
input int PointSize = 3;
input ENUM_TIMEFRAMES LowerTimeframe = PERIOD_M1;
input int CandlesToAnalyze = 5;
input bool ShowInfo = true;
input color InfoColor = clrWhite;
input int FontSize = 9;

//--- Global Variables
struct PathPoint
{
   datetime Time;
   double Price;
   string Label;
};

PathPoint PathArray[];
int PathCount = 0;

string ObjectPrefix = "PPA_";
int SubWindowNumber = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("[PPA] Initialization started...");
   
   // تعیین Sub-window بر اساس Display Mode
   if(DisplayMode == MODE_SUBWINDOW)
   {
      SubWindowNumber = 1;
      Print("[PPA] Display Mode: Sub-window (Window 1)");
   }
   else if(DisplayMode == MODE_OVERLAY)
   {
      SubWindowNumber = 0;
      Print("[PPA] Display Mode: Overlay (Chart)");
   }
   else
   {
      SubWindowNumber = 0;
      Print("[PPA] Display Mode: Separate (Will create new window)");
   }
   
   Print("[PPA] Settings:");
   Print("  - Show Path: ", ShowPath);
   Print("  - Path Color: ", PathColor);
   Print("  - Path Width: ", PathWidth);
   Print("  - Show Points: ", ShowPoints);
   Print("  - Lower Timeframe: ", EnumToString(LowerTimeframe));
   Print("[PPA] Ready to analyze!");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("[PPA] Deinitialization. Reason: ", reason);
   
   // تمام Objects رو حذف کن
   ObjectsDeleteAll(0, ObjectPrefix);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   // فقط یک بار در هر کندل جدید اجرا شود
   static datetime lastBarTime = 0;
   
   if(time[0] == lastBarTime)
      return(rates_total);
   
   lastBarTime = time[0];
   
   // تمام Objects قدیمی رو پاک کن
   ObjectsDeleteAll(0, ObjectPrefix);
   
   // آخرین کندل‌ها رو تجزیه کن
   AnalyzeLastCandles(rates_total, time, open, high, low, close);
   
   // Path رو رسم کن
   if(ShowPath)
      DrawPath();
   
   // Points رو نمایش بده
   if(ShowPoints)
      DrawPoints();
   
   // معلومات رو نمایش بده
   if(ShowInfo)
      DrawInfo();
   
   ChartRedraw();
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| تجزیه آخرین کندل‌ها                                              |
//+------------------------------------------------------------------+
void AnalyzeLastCandles(const int rates_total,
                        const datetime &time[],
                        const double &open[],
                        const double &high[],
                        const double &low[],
                        const double &close[])
{
   ArrayResize(PathArray, 0);
   PathCount = 0;
   
   int startBar = MathMin(CandlesToAnalyze, rates_total - 1);
   
   // برای هر کندل از آخر به عقب برو
   for(int bar = startBar; bar >= 0; bar--)
   {
      datetime barTime = time[bar];
      double barOpen = open[bar];
      double barHigh = high[bar];
      double barLow = low[bar];
      double barClose = close[bar];
      
      // نقطه Open
      AddPathPoint(barTime, barOpen, "O");
      
      // ترتیب High و Low رو تعیین کن
      bool HighFirst = DetermineHighLowOrder(barTime, barHigh, barLow);
      
      if(HighFirst)
      {
         AddPathPoint(barTime, barHigh, "H");
         AddPathPoint(barTime, barLow, "L");
      }
      else
      {
         AddPathPoint(barTime, barLow, "L");
         AddPathPoint(barTime, barHigh, "H");
      }
      
      // نقطه Close
      AddPathPoint(barTime, barClose, "C");
   }
   
   // مسیر رو reverse کن تا از بیشترین قدیمی تا جدید باشد
   ReversePathArray();
}

//+------------------------------------------------------------------+
//| تعیین ترتیب High و Low                                           |
//+------------------------------------------------------------------+
bool DetermineHighLowOrder(datetime barTime, double high, double low)
{
   // M1 (یا تایم‌فریم پایین‌تر) داده رو load کن
   int m1Bars = iBars(_Symbol, LowerTimeframe);
   
   if(m1Bars < 5)
   {
      Print("[PPA] Warning: Insufficient M1 data");
      return true; // Default: High اول
   }
   
   datetime barStart = barTime;
   datetime barEnd = barTime + 60 * 5; // فرض M5 است
   
   if(LowerTimeframe == PERIOD_M1)
      barEnd = barTime + 60;
   else if(LowerTimeframe == PERIOD_M5)
      barEnd = barTime + 60 * 5;
   else if(LowerTimeframe == PERIOD_M15)
      barEnd = barTime + 60 * 15;
   else if(LowerTimeframe == PERIOD_M30)
      barEnd = barTime + 60 * 30;
   else if(LowerTimeframe == PERIOD_H1)
      barEnd = barTime + 3600;
   
   datetime firstHighTime = 0;
   datetime firstLowTime = 0;
   
   // M1 داده رو بررسی کن
   for(int i = 0; i < m1Bars && i < 100; i++)
   {
      datetime candleTime = iTime(_Symbol, LowerTimeframe, i);
      double candleHigh = iHigh(_Symbol, LowerTimeframe, i);
      double candleLow = iLow(_Symbol, LowerTimeframe, i);
      
      if(candleTime < barStart || candleTime >= barEnd)
         continue;
      
      if(MathAbs(candleHigh - high) < _Point && firstHighTime == 0)
         firstHighTime = candleTime;
      
      if(MathAbs(candleLow - low) < _Point && firstLowTime == 0)
         firstLowTime = candleTime;
      
      if(firstHighTime != 0 && firstLowTime != 0)
         break;
   }
   
   // اگر هر دو یافت شد، مقایسه کن
   if(firstHighTime != 0 && firstLowTime != 0)
   {
      return firstHighTime < firstLowTime;
   }
   
   // Default
   return true;
}

//+------------------------------------------------------------------+
//| اضافه کردن نقطه به Path                                           |
//+------------------------------------------------------------------+
void AddPathPoint(datetime time, double price, string label)
{
   ArrayResize(PathArray, PathCount + 1);
   PathArray[PathCount].Time = time;
   PathArray[PathCount].Price = price;
   PathArray[PathCount].Label = label;
   PathCount++;
}

//+------------------------------------------------------------------+
//| Reverse کردن آرایه                                                |
//+------------------------------------------------------------------+
void ReversePathArray()
{
   for(int i = 0; i < PathCount / 2; i++)
   {
      PathPoint temp = PathArray[i];
      PathArray[i] = PathArray[PathCount - 1 - i];
      PathArray[PathCount - 1 - i] = temp;
   }
}

//+------------------------------------------------------------------+
//| رسم مسیر خطی                                                      |
//+------------------------------------------------------------------+
void DrawPath()
{
   if(PathCount < 2)
      return;
   
   for(int i = 0; i < PathCount - 1; i++)
   {
      string lineName = ObjectPrefix + "Line_" + IntegerToString(i);
      
      bool created = ObjectCreate(
         0,
         lineName,
         OBJ_TREND,
         SubWindowNumber,
         PathArray[i].Time,
         PathArray[i].Price,
         PathArray[i + 1].Time,
         PathArray[i + 1].Price
      );
      
      if(created)
      {
         ObjectSetInteger(0, lineName, OBJPROP_COLOR, PathColor);
         ObjectSetInteger(0, lineName, OBJPROP_WIDTH, PathWidth);
         ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, lineName, OBJPROP_RAY_LEFT, false);
         ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
      }
   }
}

//+------------------------------------------------------------------+
//| رسم نقاط                                                          |
//+------------------------------------------------------------------+
void DrawPoints()
{
   for(int i = 0; i < PathCount; i++)
   {
      string pointName = ObjectPrefix + "Point_" + IntegerToString(i);
      
      color pointColor = PathColor;
      if(PathArray[i].Label == "O") pointColor = clrGreen;
      else if(PathArray[i].Label == "H") pointColor = clrRed;
      else if(PathArray[i].Label == "L") pointColor = clrBlue;
      else if(PathArray[i].Label == "C") pointColor = clrOrange;
      
      ObjectCreate(
         0,
         pointName,
         OBJ_ARROW,
         SubWindowNumber,
         PathArray[i].Time,
         PathArray[i].Price
      );
      
      ObjectSetInteger(0, pointName, OBJPROP_ARROWCODE, 159);   // کد دایره
      ObjectSetInteger(0, pointName, OBJPROP_COLOR, pointColor);
      ObjectSetInteger(0, pointName, OBJPROP_WIDTH, PointSize);
      
      
   }
}

//+------------------------------------------------------------------+
//| رسم معلومات                                                       |
//+------------------------------------------------------------------+
void DrawInfo()
{
   string infoText = "";
   infoText += "Price Path Analyzer\n";
   infoText += "Symbol: " + _Symbol + "\n";
   infoText += "Timeframe: " + EnumToString(_Period) + "\n";
   infoText += "Lower TF: " + EnumToString(LowerTimeframe) + "\n";
   infoText += "Points: " + IntegerToString(PathCount) + "\n";
   infoText += "\nColors:\n";
   infoText += "Green(O) → Blue(H/L) → Orange(C)\n";
   infoText += "\nMode: " + EnumToString(DisplayMode);
   
   string infoName = ObjectPrefix + "Info";
   
   ObjectCreate(0, infoName, OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, infoName, OBJPROP_TEXT, infoText);
   ObjectSetInteger(0, infoName, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, infoName, OBJPROP_YDISTANCE, 30);
   ObjectSetInteger(0, infoName, OBJPROP_COLOR, InfoColor);
   ObjectSetInteger(0, infoName, OBJPROP_FONTSIZE, FontSize);
   ObjectSetString(0, infoName, OBJPROP_FONT, "Arial");
}

//+------------------------------------------------------------------+
//| End of Indicator                                                  |
//+------------------------------------------------------------------+
