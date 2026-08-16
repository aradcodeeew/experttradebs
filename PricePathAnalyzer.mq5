//+------------------------------------------------------------------+
//|             Price Path Analyzer - Panel UI v5.0                   |
//|        Range Selection + Draggable Panel + Top Path Strip         |
//|   X axis = candle number (left->right) | Y axis = price (pips)    |
//|   Order: bullish O-H-L-C / bearish O-L-H-C                        |
//|                    For MetaTrader 5 (Analysis Only)               |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 0

#include <Canvas\Canvas.mqh>

//--- Input Parameters
input bool  EnableSelection = true;         // Enable click selection
input color StartLineColor  = clrGreen;     // Start line color
input color EndLineColor    = clrRed;       // End line color
input int   LineWidth       = 2;            // Line width
input color PathColor       = clrDodgerBlue;// Path color (top strip)
input bool  ShowInfo        = true;         // Show info text on panel
input int   PointsPerPip    = 10;           // Points per pip (Y axis scale)
input int   StripHeightPx   = 120;          // Top strip height (pixels)

//--- Object names
#define PREFIX     "PPA_"
#define O_BG       PREFIX "Panel_BG"
#define O_TITLE    PREFIX "Panel_Title"
#define O_STAT     PREFIX "Panel_Status"
#define O_BTN_L    PREFIX "Btn_Lines"
#define O_BTN_C    PREFIX "Btn_Calc"
#define O_BTN_P    PREFIX "Btn_Path"
#define O_BTN_X    PREFIX "Btn_Clear"
#define O_CANVAS   PREFIX "PathCanvas"

#define ALL_TF     0xFFFFFFFF
#define NO_TF      0

//--- Panel geometry
#define PN_W       204
#define PN_H       180

//--- Global Variables
struct SelectionState
{
   bool    InSelection;
   datetime StartTime;
   datetime EndTime;
   bool    HasSelection;
};

SelectionState Sel;
int SelectedCandleCount = 0;

struct PathPoint
{
   datetime Time;
   double   Price;
   string   Label;
};

PathPoint PathArray[];
int PathCount = 0;

//--- Panel / strip state
int  PanelX = 20;
int  PanelY = 110;
bool LinesVisible = true;
bool PathVisible  = false;
bool PathDrawn    = false;

CCanvas Canvas;

string PanelChildNames[6];
int    PanelChildOffX[6];
int    PanelChildOffY[6];

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("[PPA-Panel] Initialization started...");

   Sel.InSelection  = false;
   Sel.StartTime    = 0;
   Sel.EndTime      = 0;
   Sel.HasSelection = false;

   PathCount = 0;
   PathDrawn = false;
   PathVisible = false;
   LinesVisible = true;

   CreatePanel();
   UpdateLinesButton();
   UpdatePathButton();
   UpdateStatus("Click chart:\n1) set START\n2) set END");

   Print("[PPA-Panel] Ready. Select a range on chart, then press Calculate.");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("[PPA-Panel] Deinitialization. Reason: ", reason);
   ObjectsDeleteAll(0, PREFIX);
   Canvas.Destroy();
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Chart event handler                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   //--- Button clicks
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == O_BTN_L)
      {
         LinesVisible = !LinesVisible;
         SetLinesVisible(LinesVisible);
         UpdateLinesButton();
      }
      else if(sparam == O_BTN_C)
      {
         DoCalculate();
      }
      else if(sparam == O_BTN_P)
      {
         TogglePath();
      }
      else if(sparam == O_BTN_X)
      {
         ClearAll();
      }
      return;
   }

   //--- Panel background drag (move whole panel)
   if(id == CHARTEVENT_OBJECT_DRAG && sparam == O_BG)
   {
      PanelX = (int)ObjectGetInteger(0, O_BG, OBJPROP_XDISTANCE);
      PanelY = (int)ObjectGetInteger(0, O_BG, OBJPROP_YDISTANCE);
      MovePanelChildren();
      return;
   }

   //--- Vertical line drag (adjust selection range)
   if(id == CHARTEVENT_OBJECT_DRAG)
   {
      string objName = sparam;

      if(StringFind(objName, PREFIX "Start") == 0)
      {
         datetime newTime = (datetime)ObjectGetInteger(0, objName, OBJPROP_TIME, 0);
         if(Sel.HasSelection && newTime >= Sel.EndTime)
         {
            ObjectSetInteger(0, objName, OBJPROP_TIME, Sel.StartTime);
            ChartRedraw();
            return;
         }
         Sel.StartTime = newTime;
         UpdateRangeLines();
         AfterRangeChanged();
         return;
      }

      if(StringFind(objName, PREFIX "End") == 0)
      {
         datetime newTime = (datetime)ObjectGetInteger(0, objName, OBJPROP_TIME, 0);
         if(Sel.HasSelection && newTime <= Sel.StartTime)
         {
            ObjectSetInteger(0, objName, OBJPROP_TIME, Sel.EndTime);
            ChartRedraw();
            return;
         }
         Sel.EndTime = newTime;
         UpdateRangeLines();
         AfterRangeChanged();
         return;
      }
   }

   //--- Chart click (selection)
   if(id == CHARTEVENT_CLICK)
   {
      int x = (int)lparam;
      int y = (int)dparam;

      if(IsPointOnPanel(x, y))
         return;
      if(PathVisible && y <= StripHeightPx)
         return;

      datetime clickTime = 0;
      double clickPrice = 0;
      int subwindow = 0;
      if(ChartXYToTimePrice(0, x, y, subwindow, clickTime, clickPrice))
         OnMouseClick(clickTime);
      return;
   }

   //--- Chart resize / scroll: keep strip size in sync
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      if(PathDrawn && PathVisible)
         DrawPathCanvas();
      return;
   }
}

//+------------------------------------------------------------------+
//| Mouse click processing (no popup alerts anymore)                 |
//+------------------------------------------------------------------+
void OnMouseClick(datetime clickTime)
{
   if(!EnableSelection)
      return;

   if(!Sel.InSelection)
   {
      Sel.StartTime   = clickTime;
      Sel.InSelection = true;

      DrawStartLine();
      SetLinesVisible(LinesVisible);
      UpdateStatus("Start: " + TimeToString(Sel.StartTime, TIME_DATE | TIME_MINUTES) + "\nNow click End.");
      Print("[PPA-Panel] Start selected: ", TimeToString(Sel.StartTime));
   }
   else
   {
      if(clickTime <= Sel.StartTime)
      {
         UpdateStatus("End must be after Start!\nClick End again.");
         return;
      }

      Sel.EndTime      = clickTime;
      Sel.HasSelection = true;
      Sel.InSelection  = false;

      DrawEndLine();
      SetLinesVisible(LinesVisible);
      FindCandlesInRange();
      UpdateStatus("Range: " + TimeToString(Sel.StartTime, TIME_DATE | TIME_MINUTES) + "\n" +
                   TimeToString(Sel.EndTime, TIME_DATE | TIME_MINUTES) + "\nCandles: " +
                   IntegerToString(SelectedCandleCount) + " | Press Calculate");
      Print("[PPA-Panel] End selected: ", TimeToString(Sel.EndTime));
   }
}

//+------------------------------------------------------------------+
//| After range lines are dragged                                    |
//+------------------------------------------------------------------+
void AfterRangeChanged()
{
   if(!Sel.HasSelection || Sel.StartTime >= Sel.EndTime)
      return;

   FindCandlesInRange();

   if(PathDrawn)
   {
      // path is already visible -> keep it in sync automatically
      CalculatePath();
      DrawPathCanvas();
      UpdateStatus("Range: " + TimeToString(Sel.StartTime, TIME_DATE | TIME_MINUTES) + "\n" +
                   TimeToString(Sel.EndTime, TIME_DATE | TIME_MINUTES) + "\nCandles: " +
                   IntegerToString(SelectedCandleCount) + " | Points: " + IntegerToString(PathCount));
   }
   else
   {
      UpdateStatus("Range: " + TimeToString(Sel.StartTime, TIME_DATE | TIME_MINUTES) + "\n" +
                   TimeToString(Sel.EndTime, TIME_DATE | TIME_MINUTES) + "\nCandles: " +
                   IntegerToString(SelectedCandleCount) + " | Press Calculate");
   }
}

//+------------------------------------------------------------------+
//| Calculate button handler                                         |
//+------------------------------------------------------------------+
void DoCalculate()
{
   if(!Sel.HasSelection || Sel.StartTime >= Sel.EndTime)
   {
      UpdateStatus("No range selected.\nClick chart for Start,\nthen for End.");
      return;
   }

   FindCandlesInRange();
   CalculatePath();
   DrawPathCanvas();

   PathDrawn   = true;
   PathVisible = true;
   UpdatePathButton();

   UpdateStatus("Range: " + TimeToString(Sel.StartTime, TIME_DATE | TIME_MINUTES) + "\n" +
                TimeToString(Sel.EndTime, TIME_DATE | TIME_MINUTES) + "\nCandles: " +
                IntegerToString(SelectedCandleCount) + " | Points: " + IntegerToString(PathCount));
   Print("[PPA-Panel] Path drawn: ", PathCount, " points");
}

//+------------------------------------------------------------------+
//| Toggle path strip visibility                                     |
//+------------------------------------------------------------------+
void TogglePath()
{
   if(!PathDrawn)
   {
      DoCalculate();
      return;
   }

   PathVisible = !PathVisible;

   if(ObjectFind(0, O_CANVAS) >= 0)
   {
      if(PathVisible)
      {
         ObjectSetInteger(0, O_CANVAS, OBJPROP_TIMEFRAMES, ALL_TF);
         Canvas.Update(true);
      }
      else
         ObjectSetInteger(0, O_CANVAS, OBJPROP_TIMEFRAMES, NO_TF);
   }

   UpdatePathButton();
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Clear everything                                                 |
//+------------------------------------------------------------------+
void ClearAll()
{
   DeleteLineObjects();
   Sel.InSelection      = false;
   Sel.HasSelection     = false;
   Sel.StartTime        = 0;
   Sel.EndTime          = 0;
   SelectedCandleCount  = 0;
   PathCount            = 0;
   PathDrawn            = false;
   PathVisible          = false;

   if(Canvas.ChartObjectName() != NULL)
      Canvas.Destroy();

   UpdateLinesButton();
   UpdatePathButton();
   UpdateStatus("Cleared.\nClick chart to select\nnew range.");
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Find candles inside the selected range                           |
//+------------------------------------------------------------------+
void FindCandlesInRange()
{
   int bars = iBars(_Symbol, _Period);
   SelectedCandleCount = 0;

   for(int i = 0; i < bars; i++)
   {
      datetime barTime = iTime(_Symbol, _Period, i);
      if(barTime >= Sel.StartTime && barTime <= Sel.EndTime)
         SelectedCandleCount++;
   }
}

//+------------------------------------------------------------------+
//| Calculate path points                                            |
//| Section direction decides point order inside every candle:       |
//|   bullish (END close > START close) -> O, H, L, C                |
//|   bearish (END close < START close) -> O, L, H, C                |
//+------------------------------------------------------------------+
void CalculatePath()
{
   ArrayResize(PathArray, 0);
   PathCount = 0;

   int bars = iBars(_Symbol, _Period);

   //--- section direction: close(END click) vs close(START click)
   bool IsBullish = true;
   bool found = false;
   double closeEnd   = 0;
   double closeStart = 0;

   for(int i = 0; i < bars; i++)
   {
      datetime bt = iTime(_Symbol, _Period, i);
      if(bt < Sel.StartTime || bt > Sel.EndTime)
         continue;
      if(!found)
      {
         closeEnd = iClose(_Symbol, _Period, i);
         found = true;
      }
      closeStart = iClose(_Symbol, _Period, i);
   }

   if(found)
      IsBullish = (closeEnd >= closeStart);

   //--- build the path
   for(int i = 0; i < bars; i++)
   {
      datetime bt = iTime(_Symbol, _Period, i);
      if(bt < Sel.StartTime || bt > Sel.EndTime)
         continue;

      AddPathPoint(bt, iOpen(_Symbol, _Period, i), "O");

      if(IsBullish)
      {
         AddPathPoint(bt, iHigh(_Symbol, _Period, i), "H");
         AddPathPoint(bt, iLow(_Symbol, _Period, i), "L");
      }
      else
      {
         AddPathPoint(bt, iLow(_Symbol, _Period, i), "L");
         AddPathPoint(bt, iHigh(_Symbol, _Period, i), "H");
      }

      AddPathPoint(bt, iClose(_Symbol, _Period, i), "C");
   }
}

//+------------------------------------------------------------------+
//| Add a path point                                                 |
//+------------------------------------------------------------------+
void AddPathPoint(datetime time, double price, string label)
{
   ArrayResize(PathArray, PathCount + 1);
   PathArray[PathCount].Time  = time;
   PathArray[PathCount].Price = price;
   PathArray[PathCount].Label = label;
   PathCount++;
}

//+------------------------------------------------------------------+
//| Draw the vertical selection lines                                |
//+------------------------------------------------------------------+
void DrawStartLine()
{
   string lineName = PREFIX "Start";
   ObjectCreate(0, lineName, OBJ_VLINE, 0, Sel.StartTime, 0);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, StartLineColor);
   ObjectSetInteger(0, lineName, OBJPROP_WIDTH, LineWidth);
   ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, lineName, OBJPROP_TIMEFRAMES, ALL_TF);

   string labelName = PREFIX "StartLabel";
   ObjectCreate(0, labelName, OBJ_TEXT, 0, Sel.StartTime, 0);
   ObjectSetString(0, labelName, OBJPROP_TEXT, "START");
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, StartLineColor);
   ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, labelName, OBJPROP_TIMEFRAMES, ALL_TF);
}

void DrawEndLine()
{
   string lineName = PREFIX "End";
   ObjectCreate(0, lineName, OBJ_VLINE, 0, Sel.EndTime, 0);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, EndLineColor);
   ObjectSetInteger(0, lineName, OBJPROP_WIDTH, LineWidth);
   ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, lineName, OBJPROP_TIMEFRAMES, ALL_TF);

   string labelName = PREFIX "EndLabel";
   ObjectCreate(0, labelName, OBJ_TEXT, 0, Sel.EndTime, 0);
   ObjectSetString(0, labelName, OBJPROP_TEXT, "END");
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, EndLineColor);
   ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, labelName, OBJPROP_TIMEFRAMES, ALL_TF);
}

//+------------------------------------------------------------------+
//| Move labels along with dragged lines                             |
//+------------------------------------------------------------------+
void UpdateRangeLines()
{
   string startLabel = PREFIX "StartLabel";
   if(ObjectFind(0, startLabel) >= 0)
      ObjectSetInteger(0, startLabel, OBJPROP_TIME, Sel.StartTime);

   string endLabel = PREFIX "EndLabel";
   if(ObjectFind(0, endLabel) >= 0)
      ObjectSetInteger(0, endLabel, OBJPROP_TIME, Sel.EndTime);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Show / hide vertical lines                                       |
//+------------------------------------------------------------------+
void SetLinesVisible(bool visible)
{
   SetObjTimeframes(PREFIX "Start", visible);
   SetObjTimeframes(PREFIX "End", visible);
   SetObjTimeframes(PREFIX "StartLabel", visible);
   SetObjTimeframes(PREFIX "EndLabel", visible);
   ChartRedraw();
}

void SetObjTimeframes(string name, bool visible)
{
   if(ObjectFind(0, name) >= 0)
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, visible ? ALL_TF : NO_TF);
}

void DeleteLineObjects()
{
   ObjectDelete(0, PREFIX "Start");
   ObjectDelete(0, PREFIX "End");
   ObjectDelete(0, PREFIX "StartLabel");
   ObjectDelete(0, PREFIX "EndLabel");
}

//+------------------------------------------------------------------+
//| Draw the path strip at the TOP of the chart (canvas overlay)     |
//| X axis = candle number (left -> right), Y axis = price in pips    |
//+------------------------------------------------------------------+
void DrawPathCanvas()
{
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   if(cw <= 0)
      cw = 800;

   // leave room for the price scale on the right side
   if(ChartGetInteger(0, CHART_SHOW_PRICE_SCALE) != 0)
      cw -= 60;
   if(cw < 200)
      cw = 200;

   int ch = StripHeightPx;
   if(ch < 60)
      ch = 60;

   if(!Canvas.CreateBitmapLabel(O_CANVAS, 0, 0, cw, ch))
   {
      Print("[PPA-Panel] Canvas creation failed, error ", GetLastError());
      return;
   }

   ObjectSetInteger(0, O_CANVAS, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, O_CANVAS, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, O_CANVAS, OBJPROP_ZORDER, 50);
   ObjectSetInteger(0, O_CANVAS, OBJPROP_TIMEFRAMES, ALL_TF);

   //--- background + border around the strip
   Canvas.Erase(XRGB(16, 20, 27));
   Canvas.Rectangle(1, 1, cw - 2, ch - 2, XRGB(70, 90, 120));

   //--- plot area
   int left   = 30;      // space for pip labels (Y axis)
   int right  = cw - 8;
   int top    = 20;      // below the title
   int bottom = ch - 14; // space for candle-number labels (X axis)

   int candles = PathCount / 4;
   if(candles <= 0 || PathCount < 4)
   {
      Canvas.FontSet("Arial", 9, 0, 0);
      Canvas.TextOut(left, (top + bottom) / 2 - 8, "No path data in selected range", XRGB(200, 200, 200), 0);
      Canvas.Update(true);
      return;
   }

   //--- title
   Canvas.FontSet("Arial", 9, 0, 0);
   Canvas.TextOut(8, 3, "PRICE PATH (PIPS)  |  " + _Symbol + " " + TimeframeStr() + "  |  " +
                  IntegerToString(candles) + " candles", XRGB(255, 215, 0), 0);

   //--- pip scale
   double pip = _Point * PointsPerPip;
   if(pip <= 0)
      pip = _Point * 10;

   double pmin = PathArray[0].Price;
   double pmax = PathArray[0].Price;
   for(int i = 1; i < PathCount; i++)
   {
      if(PathArray[i].Price < pmin) pmin = PathArray[i].Price;
      if(PathArray[i].Price > pmax) pmax = PathArray[i].Price;
   }

   double totalPips = (pmax - pmin) / pip;
   if(totalPips < 1)
      totalPips = 1;
   double step = NiceStep(totalPips / 5.0);
   int dec = (step < 1 ? 1 : 0);

   int denom = (candles > 1 ? candles - 1 : 1);

   //--- X axis (bottom): candle numbers, left to right
   int labelEvery = 1;
   int maxXLabels = (right - left) / 24;
   if(maxXLabels < 1)
      maxXLabels = 1;
   if(candles > maxXLabels)
      labelEvery = (int)MathCeil((double)candles / (double)maxXLabels);

   Canvas.FontSet("Arial", 7, 0, 0);
   for(int i = 0; i < candles; i += labelEvery)
   {
      int x = left + (int)MathRound((double)i / denom * (right - left));
      Canvas.LineVertical(x, top, bottom, XRGB(45, 55, 70));
      Canvas.TextOut(x - 5, ch - 13, IntegerToString(i + 1), XRGB(170, 190, 210), 0);
   }
   //--- last candle gridline + label
   int xLast = left + (int)MathRound((double)(candles - 1) / denom * (right - left));
   Canvas.LineVertical(xLast, top, bottom, XRGB(45, 55, 70));
   Canvas.TextOut(xLast - 7, ch - 13, IntegerToString(candles), XRGB(170, 190, 210), 0);

   //--- Y axis (left): pip labels, bottom -> top
   int nGrid = (int)MathFloor(totalPips / step);
   for(int g = 0; g <= nGrid; g++)
   {
      double pips = g * step;
      int y = bottom - (int)MathRound(pips / totalPips * (bottom - top));
      Canvas.LineHorizontal(left, right, y, XRGB(45, 55, 70));
      Canvas.TextOut(2, y - 4, DoubleToString(pips, dec), XRGB(170, 190, 210), 0);
   }

   //--- map path: X = candle column, Y = price in pips
   int px[];
   int py[];
   ArrayResize(px, PathCount);
   ArrayResize(py, PathCount);

   for(int j = 0; j < PathCount; j++)
   {
      int ci = j / 4;
      double pips = (PathArray[j].Price - pmin) / pip;

      px[j] = left + (int)MathRound((double)ci / denom * (right - left)) + (int)MathRound(((double)(j % 4) - 1.5) / 1.5 * MathMin(40.0, (double)(right - left) / denom / 2.0));
      py[j] = bottom - (int)MathRound(pips / totalPips * (bottom - top));
   }

   //--- blue path line
   Canvas.PolylineThick(px, py, COLOR2RGB(PathColor), 2, 0, LINE_END_ROUND);

   //--- colored points (O/H/L/C)
   for(int j = 0; j < PathCount; j++)
   {
      uint pc = COLOR2RGB(PathColor);
      if(PathArray[j].Label == "O") pc = COLOR2RGB(clrGreen);
      else if(PathArray[j].Label == "H") pc = COLOR2RGB(clrRed);
      else if(PathArray[j].Label == "L") pc = COLOR2RGB(clrBlue);
      else if(PathArray[j].Label == "C") pc = COLOR2RGB(clrOrange);

      Canvas.FillCircle(px[j], py[j], 2, pc);
   }

   Canvas.Update(true);
}

//+------------------------------------------------------------------+
//| Round a raw step to a "nice" number (1/2/5 * 10^k)               |
//+------------------------------------------------------------------+
double NiceStep(double raw)
{
   if(raw <= 0)
      return(1);
   double m = MathPow(10, MathFloor(MathLog10(raw)));
   double n = raw / m;
   if(n < 1.5) return(1 * m);
   if(n < 3.5) return(2 * m);
   if(n < 7.5) return(5 * m);
   return(10 * m);
}

//+------------------------------------------------------------------+
//| Timeframe string (M1, M5, H1, D1 ...)                            |
//+------------------------------------------------------------------+
string TimeframeStr()
{
   int sec = PeriodSeconds(_Period);
   if(sec >= 86400) return(IntegerToString(sec / 86400) + "D");
   if(sec >= 3600)  return(IntegerToString(sec / 3600) + "H");
   if(sec >= 60)    return(IntegerToString(sec / 60) + "M");
   return(IntegerToString(sec) + "S");
}

//+------------------------------------------------------------------+
//| Panel creation                                                   |
//+------------------------------------------------------------------+
void CreatePanel()
{
   //--- background (draggable, with border)
   ObjectCreate(0, O_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, O_BG, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, O_BG, OBJPROP_XDISTANCE, PanelX);
   ObjectSetInteger(0, O_BG, OBJPROP_YDISTANCE, PanelY);
   ObjectSetInteger(0, O_BG, OBJPROP_XSIZE, PN_W);
   ObjectSetInteger(0, O_BG, OBJPROP_YSIZE, PN_H);
   ObjectSetInteger(0, O_BG, OBJPROP_BGCOLOR, C'24,28,36');
   ObjectSetInteger(0, O_BG, OBJPROP_BORDER_COLOR, clrGold);
   ObjectSetInteger(0, O_BG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, O_BG, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, O_BG, OBJPROP_BACK, false);
   ObjectSetInteger(0, O_BG, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, O_BG, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, O_BG, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, O_BG, OBJPROP_ZORDER, 100);
   ObjectSetInteger(0, O_BG, OBJPROP_TIMEFRAMES, ALL_TF);

   //--- children (relative offsets, moved together with panel)
   RegisterChild(O_TITLE, 10, 6);
   ObjectCreate(0, O_TITLE, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, O_TITLE, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, O_TITLE, OBJPROP_XDISTANCE, PanelX + 10);
   ObjectSetInteger(0, O_TITLE, OBJPROP_YDISTANCE, PanelY + 6);
   ObjectSetString(0, O_TITLE, OBJPROP_TEXT, "Price Path Analyzer");
   ObjectSetInteger(0, O_TITLE, OBJPROP_COLOR, clrGold);
   ObjectSetInteger(0, O_TITLE, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, O_TITLE, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, O_TITLE, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, O_TITLE, OBJPROP_ZORDER, 101);
   ObjectSetInteger(0, O_TITLE, OBJPROP_TIMEFRAMES, ALL_TF);

   RegisterChild(O_STAT, 10, 24);
   ObjectCreate(0, O_STAT, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, O_STAT, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, O_STAT, OBJPROP_XDISTANCE, PanelX + 10);
   ObjectSetInteger(0, O_STAT, OBJPROP_YDISTANCE, PanelY + 24);
   ObjectSetString(0, O_STAT, OBJPROP_TEXT, "");
   ObjectSetInteger(0, O_STAT, OBJPROP_COLOR, C'200,210,220');
   ObjectSetInteger(0, O_STAT, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, O_STAT, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, O_STAT, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, O_STAT, OBJPROP_ZORDER, 101);
   ObjectSetInteger(0, O_STAT, OBJPROP_TIMEFRAMES, ALL_TF);

   //--- buttons: 1 column x 4 rows
   RegisterChild(O_BTN_L, 12, 64);
   CreateButton(O_BTN_L, PanelX + 12, PanelY + 64, 180, 24, "Lines: ON", C'20,80,40');

   RegisterChild(O_BTN_C, 12, 92);
   CreateButton(O_BTN_C, PanelX + 12, PanelY + 92, 180, 24, "Calculate", C'20,60,120');

   RegisterChild(O_BTN_P, 12, 120);
   CreateButton(O_BTN_P, PanelX + 12, PanelY + 120, 180, 24, "Path: OFF", C'60,60,60');

   RegisterChild(O_BTN_X, 12, 148);
   CreateButton(O_BTN_X, PanelX + 12, PanelY + 148, 180, 24, "Clear", C'110,40,40');

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Register panel child for drag-move                               |
//+------------------------------------------------------------------+
void RegisterChild(string name, int offX, int offY)
{
   for(int i = 0; i < ArraySize(PanelChildNames); i++)
   {
      if(PanelChildNames[i] == "")
      {
         PanelChildNames[i] = name;
         PanelChildOffX[i]  = offX;
         PanelChildOffY[i]  = offY;
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Move all panel children with the background                      |
//+------------------------------------------------------------------+
void MovePanelChildren()
{
   for(int i = 0; i < ArraySize(PanelChildNames); i++)
   {
      if(PanelChildNames[i] == "")
         break;
      ObjectSetInteger(0, PanelChildNames[i], OBJPROP_XDISTANCE, PanelX + PanelChildOffX[i]);
      ObjectSetInteger(0, PanelChildNames[i], OBJPROP_YDISTANCE, PanelY + PanelChildOffY[i]);
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Create a button                                                  |
//+------------------------------------------------------------------+
void CreateButton(string name, int x, int y, int w, int h, string text, color bg)
{
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'80,90,110');
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 102);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, ALL_TF);
}

//+------------------------------------------------------------------+
//| Update panel status text                                         |
//+------------------------------------------------------------------+
void UpdateStatus(string text)
{
   if(!ShowInfo)
   {
      ObjectSetString(0, O_STAT, OBJPROP_TEXT, "");
      return;
   }
   ObjectSetString(0, O_STAT, OBJPROP_TEXT, text);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update button labels                                             |
//+------------------------------------------------------------------+
void UpdateLinesButton()
{
   if(LinesVisible)
   {
      ObjectSetString(0, O_BTN_L, OBJPROP_TEXT, "Lines: ON");
      ObjectSetInteger(0, O_BTN_L, OBJPROP_BGCOLOR, C'20,80,40');
   }
   else
   {
      ObjectSetString(0, O_BTN_L, OBJPROP_TEXT, "Lines: OFF");
      ObjectSetInteger(0, O_BTN_L, OBJPROP_BGCOLOR, C'60,60,60');
   }
   ChartRedraw();
}

void UpdatePathButton()
{
   if(PathDrawn && PathVisible)
   {
      ObjectSetString(0, O_BTN_P, OBJPROP_TEXT, "Path: ON");
      ObjectSetInteger(0, O_BTN_P, OBJPROP_BGCOLOR, C'20,60,120');
   }
   else
   {
      ObjectSetString(0, O_BTN_P, OBJPROP_TEXT, "Path: OFF");
      ObjectSetInteger(0, O_BTN_P, OBJPROP_BGCOLOR, C'60,60,60');
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Check if pixel point is inside the panel                         |
//+------------------------------------------------------------------+
bool IsPointOnPanel(int x, int y)
{
   if(x >= PanelX && x <= PanelX + PN_W &&
      y >= PanelY && y <= PanelY + PN_H)
      return(true);
   return(false);
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
   return(rates_total);
}

//+------------------------------------------------------------------+
//| End of Indicator                                                  |
//+------------------------------------------------------------------+
