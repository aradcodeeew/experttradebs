//+------------------------------------------------------------------+
//|        Price Path Analyzer - Final Interactive v3.0               |
//|     Interactive Range Selection with Clean Path Visualization     |
//|                    For MetaTrader 5 (Analysis Only)               |
//+------------------------------------------------------------------+

#property strict
#property indicator_chart_window
#property indicator_buffers 0

//--- Input Parameters
input bool EnableSelection = true;
input color StartLineColor = clrGreen;
input color EndLineColor = clrRed;
input int LineWidth = 2;
input color BullishPathColor = clrGreen;
input color BearishPathColor = clrMagenta;
input int PathWidth = 2;
input double PathOffset = 0.005;  // Distance from candles (0.5%)

//--- Global Variables
struct SelectionState
{
   bool InSelection;
   datetime StartTime;
   datetime EndTime;
   bool HasSelection;
};

SelectionState Selection;
string ObjectPrefix = "PPA_V3_";
int SelectedCandleCount = 0;
bool IsBullish = false;

struct PathPoint
{
   datetime Time;
   double Price;
   string Label;
};

PathPoint PathArray[];
int PathCount = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("[PPA v3.0] Initialization...");
   Print("[PPA v3.0] Click twice on chart to select range");
   
   Selection.InSelection = false;
   Selection.StartTime = 0;
   Selection.EndTime = 0;
   Selection.HasSelection = false;
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("[PPA v3.0] Cleanup...");
   ObjectsDeleteAll(0, ObjectPrefix);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Mouse Click Handler                                               |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CLICK)
   {
      int x = (int)lparam;
      int y = (int)dparam;
      
      datetime clickTime = 0;
      double clickPrice = 0;
      int subwindow = 0;
      
      if(ChartXYToTimePrice(0, x, y, subwindow, clickTime, clickPrice))
      {
         OnMouseClick(clickTime);
      }
      return;
   }
   
   // Handle line dragging
   if(id == CHARTEVENT_OBJECT_DRAG)
   {
      string objName = sparam;
      
      if(StringFind(objName, "Start") >= 0)
      {
         Selection.StartTime = (datetime)ObjectGetInteger(0, objName, OBJPROP_TIME, 0);
         UpdateAnalysis();
      }
      else if(StringFind(objName, "End") >= 0)
      {
         Selection.EndTime = (datetime)ObjectGetInteger(0, objName, OBJPROP_TIME, 0);
         UpdateAnalysis();
      }
   }
}

//+------------------------------------------------------------------+
//| Mouse Click Processing                                            |
//+------------------------------------------------------------------+
void OnMouseClick(datetime clickTime)
{
   if(!EnableSelection) return;
   
   if(!Selection.InSelection)
   {
      Selection.StartTime = clickTime;
      Selection.InSelection = true;
      DrawStartLine();
      Print("[PPA] Start: ", TimeToString(Selection.StartTime));
   }
   else
   {
      if(clickTime <= Selection.StartTime)
      {
         Alert("End time must be after Start time!");
         return;
      }
      
      Selection.EndTime = clickTime;
      Selection.HasSelection = true;
      Selection.InSelection = false;
      DrawEndLine();
      Print("[PPA] End: ", TimeToString(Selection.EndTime));
      
      UpdateAnalysis();
      Alert("Analysis Complete!");
   }
}

//+------------------------------------------------------------------+
//| Draw Start Line (Green)                                           |
//+------------------------------------------------------------------+
void DrawStartLine()
{
   string lineName = ObjectPrefix + "Start";
   
   ObjectCreate(0, lineName, OBJ_VLINE, 0, Selection.StartTime, 0);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, StartLineColor);
   ObjectSetInteger(0, lineName, OBJPROP_WIDTH, LineWidth);
   ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, true);
}

//+------------------------------------------------------------------+
//| Draw End Line (Red)                                               |
//+------------------------------------------------------------------+
void DrawEndLine()
{
   string lineName = ObjectPrefix + "End";
   
   ObjectCreate(0, lineName, OBJ_VLINE, 0, Selection.EndTime, 0);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, EndLineColor);
   ObjectSetInteger(0, lineName, OBJPROP_WIDTH, LineWidth);
   ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, true);
}

//+------------------------------------------------------------------+
//| Update Analysis                                                   |
//+------------------------------------------------------------------+
void UpdateAnalysis()
{
   if(!Selection.HasSelection) return;
   
   // پاک کردن تحلیل‌های قدیم
   ObjectsDeleteAll(0, ObjectPrefix + "Path_");
   ObjectsDeleteAll(0, ObjectPrefix + "Info_");
   
   // شناسایی کندل‌های محدوده
   FindCandlesInRange();
   
   // محاسبه مسیر
   CalculatePath();
   
   // تعیین جهت (صعودی/نزولی)
   DetermineTrend();
   
   // رسم مسیر
   DrawPath();
   
   // نمایش اطلاعات
   DisplayInfo();
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Find Candles in Range                                             |
//+------------------------------------------------------------------+
void FindCandlesInRange()
{
   int bars = iBars(_Symbol, _Period);
   SelectedCandleCount = 0;
   
   for(int i = 0; i < bars; i++)
   {
      datetime barTime = iTime(_Symbol, _Period, i);
      
      if(barTime >= Selection.StartTime && barTime <= Selection.EndTime)
      {
         SelectedCandleCount++;
      }
   }
   
   Print("[PPA] Candles in range: ", SelectedCandleCount);
}

//+------------------------------------------------------------------+
//| Determine Trend (Bullish/Bearish)                                 |
//+------------------------------------------------------------------+
void DetermineTrend()
{
   int bars = iBars(_Symbol, _Period);
   
   double firstOpen = 0;
   double lastClose = 0;
   
   for(int i = 0; i < bars; i++)
   {
      datetime barTime = iTime(_Symbol, _Period, i);
      
      if(barTime >= Selection.StartTime && barTime <= Selection.EndTime)
      {
         if(firstOpen == 0)
            firstOpen = iOpen(_Symbol, _Period, i);
         
         lastClose = iClose(_Symbol, _Period, i);
      }
   }
   
   IsBullish = (lastClose >= firstOpen);
   Print("[PPA] Trend: ", IsBullish ? "BULLISH (GREEN)" : "BEARISH (MAGENTA)");
}

//+------------------------------------------------------------------+
//| Calculate Path Points                                             |
//+------------------------------------------------------------------+
void CalculatePath()
{
   ArrayResize(PathArray, 0);
   PathCount = 0;
   
   int bars = iBars(_Symbol, _Period);
   
   // از قدیمی به جدید
   for(int i = bars - 1; i >= 0; i--)
   {
      datetime barTime = iTime(_Symbol, _Period, i);
      
      if(barTime < Selection.StartTime || barTime > Selection.EndTime)
         continue;
      
      double barOpen = iOpen(_Symbol, _Period, i);
      double barHigh = iHigh(_Symbol, _Period, i);
      double barLow = iLow(_Symbol, _Period, i);
      double barClose = iClose(_Symbol, _Period, i);
      
      // نقطه 1: Open
      AddPathPoint(barTime, barOpen, "O");
      
      // تعیین ترتیب High/Low
      bool HighFirst = DetermineHighLowOrder(barHigh, barLow, barOpen, barClose);
      
      if(HighFirst)
      {
         // نقطه 2: High
         AddPathPoint(barTime, barHigh, "H");
         // نقطه 3: Low
         AddPathPoint(barTime, barLow, "L");
      }
      else
      {
         // نقطه 2: Low
         AddPathPoint(barTime, barLow, "L");
         // نقطه 3: High
         AddPathPoint(barTime, barHigh, "H");
      }
      
      // نقطه 4: Close
      AddPathPoint(barTime, barClose, "C");
   }
   
   Print("[PPA] Path points: ", PathCount);
}

//+------------------------------------------------------------------+
//| Determine High/Low Order (Simple Logic)                           |
//+------------------------------------------------------------------+
bool DetermineHighLowOrder(double high, double low, double open, double close)
{
   // Logic: اگر قیمت اول بالا رفت و بعد پایین آمد
   // یا اگر Bullish باشد، معمولاً High قبل می‌رسد
   
   double midPoint = (high + low) / 2;
   double openDistance = MathAbs(open - high);
   double closeDistance = MathAbs(close - high);
   
   // اگر Open به High نزدیک‌تر باشد، High اول است
   if(openDistance < closeDistance)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Add Path Point                                                    |
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
//| Draw Path - خط پیوسته تک                                         |
//+------------------------------------------------------------------+
void DrawPath()
{
   if(PathCount < 2) return;
   
   color pathColor = IsBullish ? BullishPathColor : BearishPathColor;
   
   // محاسبه offset (بالا یا پایین)
   double high = 0, low = 9999999;
   
   for(int i = 0; i < PathCount; i++)
   {
      if(PathArray[i].Price > high) high = PathArray[i].Price;
      if(PathArray[i].Price < low) low = PathArray[i].Price;
   }
   
   double range = high - low;
   double offset = range * PathOffset;
   
   // اگر Bullish: بالا، اگر Bearish: پایین
   if(!IsBullish)
      offset = -offset;
   
   // رسم خطوط بین نقاط
   for(int i = 0; i < PathCount - 1; i++)
   {
      string lineName = ObjectPrefix + "Path_" + IntegerToString(i);
      
      double price1 = PathArray[i].Price + offset;
      double price2 = PathArray[i + 1].Price + offset;
      
      ObjectCreate(0, lineName, OBJ_TREND, 0,
                   PathArray[i].Time, price1,
                   PathArray[i + 1].Time, price2);
      
      ObjectSetInteger(0, lineName, OBJPROP_COLOR, pathColor);
      ObjectSetInteger(0, lineName, OBJPROP_WIDTH, PathWidth);
      ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
   }
}

//+------------------------------------------------------------------+
//| Display Info                                                      |
//+------------------------------------------------------------------+
void DisplayInfo()
{
   string infoName = ObjectPrefix + "Info_Main";
   
   string trend = IsBullish ? "↑ BULLISH" : "↓ BEARISH";
   string color_str = IsBullish ? "GREEN" : "MAGENTA";
   
   string infoText = "Price Path Analysis\n";
   infoText += "Range: " + TimeToString(Selection.StartTime) + " → " + TimeToString(Selection.EndTime) + "\n";
   infoText += "Candles: " + IntegerToString(SelectedCandleCount) + "\n";
   infoText += "Points: " + IntegerToString(PathCount) + "\n";
   infoText += "Trend: " + trend + " (" + color_str + ")";
   
   ObjectCreate(0, infoName, OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, infoName, OBJPROP_TEXT, infoText);
   ObjectSetInteger(0, infoName, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, infoName, OBJPROP_YDISTANCE, 30);
   ObjectSetInteger(0, infoName, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, infoName, OBJPROP_FONTSIZE, 11);
   ObjectSetInteger(0, infoName, OBJPROP_SELECTABLE, false);
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
   static bool shown = false;
   
   if(!shown && EnableSelection)
   {
      Print("╔════════════════════════════════════════╗");
      Print("║  Price Path Analyzer v3.0 - Ready  ║");
      Print("╠════════════════════════════════════════╣");
      Print("║ 1. Click chart for START (Green)    ║");
      Print("║ 2. Click chart for END (Red)        ║");
      Print("║ 3. Path shows automatically         ║");
      Print("║ 4. Bullish: GREEN line (above)      ║");
      Print("║ 5. Bearish: MAGENTA line (below)    ║");
      Print("╚════════════════════════════════════════╝");
      shown = true;
   }
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| End of Indicator                                                  |
//+------------------------------------------------------------------+
