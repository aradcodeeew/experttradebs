//+------------------------------------------------------------------+
//|               Price Path Analyzer - Interactive v2.0              |
//|           Interactive Range Selection & Analysis Tool             |
//|                    For MetaTrader 5 (Analysis Only)               |
//+------------------------------------------------------------------+

#property strict
#property indicator_chart_window
#property indicator_buffers 0

//--- Input Parameters
input bool EnableSelection = true;
input int DisplayMode = 1;  // 0=Popup, 1=Overlay, 2=Sub-window
input color StartLineColor = clrGreen;
input color EndLineColor = clrRed;
input int LineWidth = 2;
input color PathColor = clrDodgerBlue;
input bool ShowInfo = true;

//--- Global Variables
struct SelectionState
{
   bool InSelection;
   datetime StartTime;
   datetime EndTime;
   bool HasSelection;
};

SelectionState Selection;
string ObjectPrefix = "PPA_Interactive_";
int SelectedCandleCount = 0;

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
   Print("[PPA-Interactive] Initialization started...");
   
   Selection.InSelection = false;
   Selection.StartTime = 0;
   Selection.EndTime = 0;
   Selection.HasSelection = false;
   
   Print("[PPA-Interactive] Selection mode: ACTIVE");
   Print("[PPA-Interactive] Click on chart to select range");
   Print("[PPA-Interactive] Display Mode: ", DisplayMode);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("[PPA-Interactive] Deinitialization. Reason: ", reason);
   ObjectsDeleteAll(0, ObjectPrefix);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Mouse Click Handler                                               |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // Handle mouse click
   if(id == CHARTEVENT_CLICK)
   {
      int x = (int)lparam;
      int y = (int)dparam;
      
      datetime clickTime = 0;
      double clickPrice = 0;
      int subwindow = 0;
      
      // تبدیل pixel به price/time
      if(ChartXYToTimePrice(0, x, y, subwindow, clickTime, clickPrice))
      {
         OnMouseClick(clickTime);
      }
      
      return;
   }
   
   // Handle object dragging (lines)
   if(id == CHARTEVENT_OBJECT_DRAG)
   {
      string objName = sparam;
      
      if(StringFind(objName, "Start") >= 0)
      {
         datetime newTime = (datetime)ObjectGetInteger(0, objName, OBJPROP_TIME, 0);
         
         // جلوگیری از عبور خط سبز از خط قرمز
         if(Selection.HasSelection && newTime >= Selection.EndTime)
         {
            ObjectSetInteger(0, objName, OBJPROP_TIME, Selection.StartTime);
            ChartRedraw();
            return;
         }
         
         Selection.StartTime = newTime;
         UpdateRangeLines();
         UpdateAnalysis();
      }
      else if(StringFind(objName, "End") >= 0)
      {
         datetime newTime = (datetime)ObjectGetInteger(0, objName, OBJPROP_TIME, 0);
         
         // جلوگیری از عبور خط قرمز از خط سبز
         if(Selection.HasSelection && newTime <= Selection.StartTime)
         {
            ObjectSetInteger(0, objName, OBJPROP_TIME, Selection.EndTime);
            ChartRedraw();
            return;
         }
         
         Selection.EndTime = newTime;
         UpdateRangeLines();
         UpdateAnalysis();
      }
   }
}

//+------------------------------------------------------------------+
//| Mouse Click Processing                                            |
//+------------------------------------------------------------------+
void OnMouseClick(datetime clickTime)
{
   if(!EnableSelection)
      return;
   
   if(!Selection.InSelection)
   {
      // First click - Start time
      Selection.StartTime = clickTime;
      Selection.InSelection = true;
      
      Print("[PPA-Interactive] Start time selected: ", TimeToString(Selection.StartTime));
      DrawStartLine();
      
      // نمایش پیغام
      Alert("Start time selected: " + TimeToString(Selection.StartTime) + "\nClick again for End time");
   }
   else
   {
      // Second click - End time
      if(clickTime <= Selection.StartTime)
      {
         Alert("End time must be after Start time!");
         return;
      }
      
      Selection.EndTime = clickTime;
      Selection.HasSelection = true;
      Selection.InSelection = false;
      
      Print("[PPA-Interactive] End time selected: ", TimeToString(Selection.EndTime));
      DrawEndLine();
      
      // تحلیل
      UpdateAnalysis();
      
      Alert("Range selected!\nAnalyzing...");
   }
}

//+------------------------------------------------------------------+
//| Draw Start Line                                                   |
//+------------------------------------------------------------------+
void DrawStartLine()
{
   string lineName = ObjectPrefix + "Start";
   
   ObjectCreate(0, lineName, OBJ_VLINE, 0, Selection.StartTime, 0);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, StartLineColor);
   ObjectSetInteger(0, lineName, OBJPROP_WIDTH, LineWidth);
   ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTED, false);
   
   // Add label
   string labelName = ObjectPrefix + "StartLabel";
   ObjectCreate(0, labelName, OBJ_TEXT, 0, Selection.StartTime, 0);
   ObjectSetString(0, labelName, OBJPROP_TEXT, "START");
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, StartLineColor);
   ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Draw End Line                                                     |
//+------------------------------------------------------------------+
void DrawEndLine()
{
   string lineName = ObjectPrefix + "End";
   
   ObjectCreate(0, lineName, OBJ_VLINE, 0, Selection.EndTime, 0);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, EndLineColor);
   ObjectSetInteger(0, lineName, OBJPROP_WIDTH, LineWidth);
   ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTED, false);
   
   // Add label
   string labelName = ObjectPrefix + "EndLabel";
   ObjectCreate(0, labelName, OBJ_TEXT, 0, Selection.EndTime, 0);
   ObjectSetString(0, labelName, OBJPROP_TEXT, "END");
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, EndLineColor);
   ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Update Range Lines & Labels (after dragging)                     |
//+------------------------------------------------------------------+
void UpdateRangeLines()
{
   // برچسب سبز را همراه خط جابجا کن
   string startLabel = ObjectPrefix + "StartLabel";
   if(ObjectFind(0, startLabel) >= 0)
      ObjectSetInteger(0, startLabel, OBJPROP_TIME, Selection.StartTime);
   
   // برچسب قرمز را همراه خط جابجا کن
   string endLabel = ObjectPrefix + "EndLabel";
   if(ObjectFind(0, endLabel) >= 0)
      ObjectSetInteger(0, endLabel, OBJPROP_TIME, Selection.EndTime);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update Analysis                                                   |
//+------------------------------------------------------------------+
void UpdateAnalysis()
{
   if(!Selection.HasSelection || Selection.StartTime >= Selection.EndTime)
      return;
   
   // تمام Objects تحلیلی رو پاک کن
   ObjectsDeleteAll(0, ObjectPrefix + "Path_");
   ObjectsDeleteAll(0, ObjectPrefix + "Point_");
   ObjectsDeleteAll(0, ObjectPrefix + "Panel_");
   ObjectsDeleteAll(0, ObjectPrefix + "Table_");
   
   // کندل‌های محدوده رو پیدا کن
   FindCandlesInRange();
   
   // Path رو محاسبه کن
   CalculatePath();
   
   // همیشه مسیر قیمت (Path) را رسم کن
   DisplayOverlay();
   
   // اطلاعات اضافی بر اساس Mode
   if(DisplayMode == 0)
      DisplayPopupPanel();
   // حالت 1 (Overlay) حذف شد؛ مسیر همیشه رسم میشود
      // مسیر قیمت در بالا همیشه رسم میشود
   else if(DisplayMode == 2)
      DisplaySubWindow();
   
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
   
   Print("[PPA-Interactive] Candles in range: ", SelectedCandleCount);
}

//+------------------------------------------------------------------+
//| Calculate Path                                                    |
//+------------------------------------------------------------------+
void CalculatePath()
{
   ArrayResize(PathArray, 0);
   PathCount = 0;
   
   int bars = iBars(_Symbol, _Period);
   
   // رفتار از جدید به قدیم
   for(int i = 0; i < bars; i++)
   {
      datetime barTime = iTime(_Symbol, _Period, i);
      
      if(barTime < Selection.StartTime || barTime > Selection.EndTime)
         continue;
      
      double barOpen = iOpen(_Symbol, _Period, i);
      double barHigh = iHigh(_Symbol, _Period, i);
      double barLow = iLow(_Symbol, _Period, i);
      double barClose = iClose(_Symbol, _Period, i);
      
      // Open
      AddPathPoint(barTime, barOpen, "O");
      
      // Determine High/Low order
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
      
      // Close
      AddPathPoint(barTime, barClose, "C");
   }
   
   Print("[PPA-Interactive] Path points calculated: ", PathCount);
}

//+------------------------------------------------------------------+
//| Determine High/Low Order                                          |
//+------------------------------------------------------------------+
bool DetermineHighLowOrder(datetime barTime, double high, double low)
{
   // فعلاً: Default High first
   // بعداً: M1 data integration
   
   return true;  // High first (default)
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
//| Display Popup Panel (Mode 0)                                      |
//+------------------------------------------------------------------+
void DisplayPopupPanel()
{
   string panelName = ObjectPrefix + "Panel_Main";
   
   // Create main background
   ObjectCreate(0, panelName, OBJ_RECTANGLE, 0, Selection.StartTime, iHigh(_Symbol, _Period, 0) * 1.05,
                Selection.EndTime, iLow(_Symbol, _Period, 0) * 0.95);
   ObjectSetInteger(0, panelName, OBJPROP_FILL, true);
   ObjectSetInteger(0, panelName, OBJPROP_BACK, true);
   ObjectSetInteger(0, panelName, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, panelName, OBJPROP_BORDER_COLOR, clrWhite);
   ObjectSetInteger(0, panelName, OBJPROP_BORDER_TYPE, BORDER_RAISED);
   ObjectSetInteger(0, panelName, OBJPROP_WIDTH, 2);
   
   // Add Title
   string titleName = ObjectPrefix + "Panel_Title";
   ObjectCreate(0, titleName, OBJ_TEXT, 0, Selection.StartTime, iHigh(_Symbol, _Period, 0) * 1.04);
   ObjectSetString(0, titleName, OBJPROP_TEXT, "Price Path Analysis");
   ObjectSetInteger(0, titleName, OBJPROP_COLOR, clrGold);
   ObjectSetInteger(0, titleName, OBJPROP_FONTSIZE, 12);
   
   // Add Info
   string infoName = ObjectPrefix + "Panel_Info";
   string infoText = "Range: " + TimeToString(Selection.StartTime) + " → " + TimeToString(Selection.EndTime) + "\n";
   infoText += "Candles: " + IntegerToString(SelectedCandleCount) + "\n";
   infoText += "Points: " + IntegerToString(PathCount);
   
   ObjectCreate(0, infoName, OBJ_TEXT, 0, Selection.StartTime, iHigh(_Symbol, _Period, 0) * 1.02);
   ObjectSetString(0, infoName, OBJPROP_TEXT, infoText);
   ObjectSetInteger(0, infoName, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, infoName, OBJPROP_FONTSIZE, 10);
}

//+------------------------------------------------------------------+
//| Display Overlay (Mode 1)                                          |
//+------------------------------------------------------------------+
void DisplayOverlay()
{
   // Draw Path Line
   if(PathCount < 2)
      return;
   
   for(int i = 0; i < PathCount - 1; i++)
   {
      string lineName = ObjectPrefix + "Path_" + IntegerToString(i);
      
      ObjectCreate(0, lineName, OBJ_TREND, 0, 
                   PathArray[i].Time, PathArray[i].Price,
                   PathArray[i + 1].Time, PathArray[i + 1].Price);
      
      ObjectSetInteger(0, lineName, OBJPROP_COLOR, PathColor);
      ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
   }
   
   // Draw Points
   for(int i = 0; i < PathCount; i++)
   {
      string pointName = ObjectPrefix + "Point_" + IntegerToString(i);
      
      color pointColor = PathColor;
      if(PathArray[i].Label == "O") pointColor = clrGreen;
      else if(PathArray[i].Label == "H") pointColor = clrRed;
      else if(PathArray[i].Label == "L") pointColor = clrBlue;
      else if(PathArray[i].Label == "C") pointColor = clrOrange;
      
      ObjectCreate(0, pointName, OBJ_ARROW, 0, PathArray[i].Time, PathArray[i].Price);
      ObjectSetInteger(0, pointName, OBJPROP_ARROWCODE, 159);
      ObjectSetInteger(0, pointName, OBJPROP_COLOR, pointColor);
      ObjectSetInteger(0, pointName, OBJPROP_ANCHOR, ANCHOR_CENTER);
      ObjectSetInteger(0, pointName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, pointName, OBJPROP_WIDTH, 2);
      // (اندازه نقطه با ARROWCODE تنظیم میشود)
   }
}

//+------------------------------------------------------------------+
//| Display Sub-window (Mode 2)                                       |
//+------------------------------------------------------------------+
void DisplaySubWindow()
{
   // Draw in separate area (simplified version)
   string infoName = ObjectPrefix + "SubWindow_Info";
   
   string text = "Candles: " + IntegerToString(SelectedCandleCount) + " | ";
   text += "Points: " + IntegerToString(PathCount);
   
   ObjectCreate(0, infoName, OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, infoName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, infoName, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, infoName, OBJPROP_YDISTANCE, 50);
   ObjectSetInteger(0, infoName, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, infoName, OBJPROP_FONTSIZE, 11);
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
   // Show instruction
   static bool instructionShown = false;
   
   if(!instructionShown && EnableSelection)
   {
      Print("═══════════════════════════════════════════");
      Print("Price Path Analyzer - Interactive Mode");
      Print("═══════════════════════════════════════════");
      Print("INSTRUCTIONS:");
      Print("1. Click on chart for START time (Green line)");
      Print("2. Click again for END time (Red line)");
      Print("3. Range will be analyzed automatically");
      Print("4. You can drag lines to adjust range");
      Print("═══════════════════════════════════════════");
      instructionShown = true;
   }
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| End of Indicator                                                  |
//+------------------------------------------------------------------+
