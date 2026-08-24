//+------------------------------------------------------------------+
//|              Price Path Analyzer - Panel UI v5.1                   |
//|   v5.1: survives chart timeframe changes (state is restored)      |
//|   v5.2: T-Line projection (cx/cy/n/t) added                      |
//|        Range Selection + Draggable Panel + Top Path Strip         |
//|   X axis = candle number (left->right) | Y axis = price (pips)    |
//|   Order: bullish O-L-H-C / bearish O-H-L-C                        |
//|                    For MetaTrader 5 (Analysis Only)               |
//+------------------------------------------------------------------+
#property strict
#property indicator_separate_window
#property indicator_buffers 2
#property indicator_plots   2
#property indicator_label1  "PPA_PathHigh"
#property indicator_type1   DRAW_NONE
#property indicator_color1  clrDodgerBlue
#property indicator_label2  "PPA_PathLow"
#property indicator_type2   DRAW_NONE
#property indicator_color2  clrDodgerBlue
//--- indicator short name is set in OnInit via IndicatorSetString()

#include <Canvas\Canvas.mqh>

//--- Input Parameters
input bool  EnableSelection = true;         // Enable click selection
input color StartLineColor  = clrGreen;     // Start line color
input color EndLineColor    = clrRed;       // End line color
input int   LineWidth       = 2;            // Line width
input color PathColor       = clrDodgerBlue;// Doji candle color (top strip)
input color BullColor       = clrGreen;     // Bullish candle color
input color BearColor       = clrRed;       // Bearish candle color
input bool  ShowInfo        = true;         // Show info text on panel
input int   PointsPerPip    = 10;           // Points per pip (Y axis scale)
input int   StripHeightPx   = 120;          // Top strip height (pixels)
input int   TableFontSize   = 9;            // Table font size (X/Y labels)
input int   ClassFontSize   = 10;           // Spike/Trend/Doji font size
input double TrendShadowRatio = 0.25;      // Shadow/body ratio: above = Trend, below = Spike

//--- point colors (each candle shows 4 points: O / H / L / C)
input color OpenColor   = clrGreen;         // Color of OPEN points (green)
input color HighColor   = clrRed;           // Color of HIGH points (red)
input color LowColor    = clrBlue;          // Color of LOW points (blue)
input color CloseColor  = clrYellow;        // Color of CLOSE points (yellow)

//--- connect the 4 points (O/H/L/C) of every selected candle with a line
input bool  ConnectCandles  = true;         // Connect each candle's 4 points
input color ConnectLineColor   = clrMagenta;// Color of the connecting line

//--- T-Line: cx/cy/n/t projection (horizontal line at cx price)
input bool            EnableTLine    = true;        // Enable cx/cy/n/t projection
input color           TLineColor     = clrAqua;     // T-line color
input ENUM_LINE_STYLE TLineStyle     = STYLE_DOT;   // T-line style
input int             TLineThick     = 2;           // T-line thickness (px)
input int             TLineCandleWidth = 5;         // T-line width (candles)
input bool            TLineBullStart = true;        // cx candle must be bullish (O<C)
input bool            TLineBearEnd   = true;        // cy candle must be bearish (O>C)
input bool            TLineInclusive = false;       // n includes cx & cy (distance+1)
input int             TLineSpikeFilter = 1;         // Draw only if this many Spike candles in range (0=off)
input bool            TLineShowLabel = true;        // Show "T" label on the line
input color           TLineLabelColor = clrYellow;  // T label color


//--- Object names
#define PREFIX     "PPA_"
#define O_BG       PREFIX "Panel_BG"
#define O_GRAB     PREFIX "Panel_Grab"
#define O_TITLE    PREFIX "Panel_Title"
#define O_STAT     PREFIX "Panel_Status"
#define O_BTN_L    PREFIX "Btn_Lines"
#define O_BTN_C    PREFIX "Btn_Calc"
#define O_BTN_P    PREFIX "Btn_Path"
#define O_BTN_X    PREFIX "Btn_Clear"
#define O_CANVAS   PREFIX "PathCanvas"

#define ALL_TF     0xFFFFFFFF
#define NO_TF      0

//--- terminal global variable that remembers which symbol this panel belongs to
#define GV_SYM     PREFIX "GV_" + IntegerToString(ChartID()) + "_Symbol"

//--- Panel geometry
#define PN_W       204
#define PN_H       180

//--- Global Variables
struct SelectionState
  {
   bool              InSelection;
   datetime          StartTime;
   datetime          EndTime;
   bool              HasSelection;
  };

SelectionState Sel;
int SelectedCandleCount = 0;

struct PathPoint
  {
   datetime          Time;
   double            Price;
   string            Label;
  };

PathPoint PathArray[];
int PathCount = 0;

//--- Candle classification (Spike / Trend / Doji) - one entry per selected candle
//    Body   = |Close - Open|
//    bullish (Close>=Open): ShadowUp = High-Close , ShadowDown = Open-Low
//    bearish (Close<Open) : ShadowUp = High-Open  , ShadowDown = Close-Low
string CandleClass[];
int    CandleClassCount = 0;

//--- shadow/body ratio threshold for "Trend" (input TrendShadowRatio, default 25%)
//

//--- Panel / strip state
int  PanelX = 20;
int  PanelY = 110;
bool LinesVisible = true;
bool PathVisible  = false;
bool PathDrawn    = false;

CCanvas Canvas;

double PathHighBuf[];
double PathLowBuf[];
int    MySubwindow = 1;

string PanelChildNames[8];
int    PanelChildOffX[8];
int    PanelChildOffY[8];

//--- T-Line (cx/cy/n/t) projection state
int    TLineStartBar = -1;
int    TLineEndBar   = -1;
double TLineCx       = 0;
double TLineCy       = 0;
double TLineN        = 0;
double TLineT        = 0;
bool   TLineBullDirection = true;

   // (TInfo cleanup is inside ResetProjectionState())
bool   TLineDrawn    = false;
string TLineWaitReason = "";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("[PPA-Panel] Initialization started...");

//--- bind the hidden scale buffers (they define the subwindow scale)
   SetIndexBuffer(0, PathHighBuf, INDICATOR_DATA);
   SetIndexBuffer(1, PathLowBuf, INDICATOR_DATA);

//--- give this indicator a stable short name (used to find its subwindow)
   IndicatorSetString(INDICATOR_SHORTNAME, "PPA_Path");

//--- find which subwindow this indicator is drawn in
   MySubwindow = FindOwnSubwindow();

//--- Try to restore the previous state (selection, panel position, path
//    strip). This survives a chart timeframe change, because the chart
//    objects are kept by OnDeinit and re-read here.
   bool restored = RestoreStateFromObjects();

   if(!restored)
     {
      Sel.InSelection  = false;
      Sel.StartTime    = 0;
      Sel.EndTime      = 0;
      Sel.HasSelection = false;

      PathCount    = 0;
      PathDrawn    = false;
      PathVisible  = false;
      LinesVisible = true;
     }

   UpdateProjection();

   CreatePanel();
   UpdateLinesButton();
   UpdatePathButton();

   if(Sel.HasSelection)
     {
      //--- objects survived: re-apply the range on the current timeframe
      DrawStartLine();
      DrawEndLine();
      SetLinesVisible(LinesVisible);
      FindCandlesInRange();
   UpdateProjection();

      if(PathDrawn && PathVisible)
        {
         UpdateProjection();
   CalculatePath();
         DrawPathCanvas();
        }

      UpdateStatus("Range: " + TimeToString(Sel.StartTime, TIME_DATE | TIME_MINUTES) + "\n" +
                   TimeToString(Sel.EndTime, TIME_DATE | TIME_MINUTES) + "\nCandles: " +
                   IntegerToString(SelectedCandleCount) + (PathDrawn ? " | Points: " + IntegerToString(PathCount)
                         : " | Press Calculate"));
     }
   else
     {
      UpdateStatus("Click chart:\n1) set START\n2) set END");
     }

   Print("[PPA-Panel] Ready. Select a range on chart, then press Calculate.");

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("[PPA-Panel] Deinitialization. Reason: ", reason);

//--- When only the timeframe (or input parameters) changed, the terminal
//    re-initializes the indicator. Keep the chart objects in that case so
//    the new instance can restore the selection / panel / path strip.
   if(reason == REASON_CHARTCHANGE || reason == REASON_PARAMETERS)
     {
      ChartRedraw();
      return;
     }

//--- real removal / chart close / recompile / etc. -> full cleanup
   ObjectsDeleteAll(0, PREFIX);
   Canvas.Destroy();
   GlobalVariableDel(GV_SYM);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Symbol marker (detects chart symbol changes)                     |
//+------------------------------------------------------------------+
double SymbolHash(string s)
  {
   double h = 0;
   int len = StringLen(s);
   for(int i = 0; i < len; i++)
      h = h * 131.0 + StringGetCharacter(s, i);
   return(h);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SaveSymbolMarker()
  {
   GlobalVariableSet(GV_SYM, SymbolHash(_Symbol));
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool SymbolMatchesSaved()
  {
   if(!GlobalVariableCheck(GV_SYM))
      return(true);
   double h = GlobalVariableGet(GV_SYM);
   return(MathAbs(h - SymbolHash(_Symbol)) < 0.5);
  }

//+------------------------------------------------------------------+
//| Create an object only if it does not exist yet                   |
//+------------------------------------------------------------------+
bool EnsureObject(string name, ENUM_OBJECT type)
  {
   if(ObjectFind(0, name) >= 0)
      return(true);
   return(ObjectCreate(0, name, type, 0, 0, 0));
  }

//+------------------------------------------------------------------+
//| Restore selection / panel state from surviving chart objects     |
//| (called from OnInit - lets the indicator survive TF changes)     |
//+------------------------------------------------------------------+
bool RestoreStateFromObjects()
  {
//--- if the chart symbol changed, old objects are meaningless
   if(!SymbolMatchesSaved())
     {
      ObjectsDeleteAll(0, PREFIX);
      Canvas.Destroy();
      SaveSymbolMarker();
      return(false);
     }

   bool havePanel = (ObjectFind(0, O_BG) >= 0);
   bool haveStart = (ObjectFind(0, PREFIX "Start") >= 0);
   bool haveEnd   = (ObjectFind(0, PREFIX "End") >= 0);

//--- nothing survived -> completely fresh start
   if(!havePanel && !haveStart && !haveEnd)
     {
      SaveSymbolMarker();
      return(false);
     }

   Sel.InSelection  = false;
   Sel.HasSelection = false;

   if(haveStart)
     {
      Sel.StartTime   = (datetime)ObjectGetInteger(0, PREFIX "Start", OBJPROP_TIME, 0);
      Sel.InSelection = true;

      if(haveEnd)
        {
         Sel.EndTime      = (datetime)ObjectGetInteger(0, PREFIX "End", OBJPROP_TIME, 0);
         Sel.HasSelection = (Sel.EndTime > Sel.StartTime);
         Sel.InSelection  = false;
        }
     }

//--- panel position
   if(havePanel)
     {
      PanelX  = (int)ObjectGetInteger(0, O_BG, OBJPROP_XDISTANCE);
      PanelY  = (int)ObjectGetInteger(0, O_BG, OBJPROP_YDISTANCE);
     }

//--- line visibility (stored on the Start line object)
   if(haveStart)
      LinesVisible = (ObjectGetInteger(0, PREFIX "Start", OBJPROP_TIMEFRAMES) != 0);

//--- path strip state (stored on the canvas object)
   if(Sel.HasSelection && ObjectFind(0, O_CANVAS) >= 0)
     {
      PathDrawn   = true;
      PathVisible = (ObjectGetInteger(0, O_CANVAS, OBJPROP_TIMEFRAMES) != 0);
     }
   else
     {
      PathDrawn   = false;
      PathVisible = false;
     }

//--- snap the selection to the bars of the current timeframe
   if(Sel.HasSelection)
     {
      datetime t1 = SnapToBarTime(Sel.StartTime);
      datetime t2 = SnapToBarTime(Sel.EndTime);
      if(t2 <= t1)
         t2 = t1 + PeriodSeconds(_Period);
      Sel.StartTime = t1;
      Sel.EndTime   = t2;

      if(Sel.StartTime >= Sel.EndTime)
        {
         Sel.HasSelection = false;
         PathDrawn        = false;
         PathVisible      = false;
        }
     }

   SaveSymbolMarker();
   return(true);
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
      else
         if(sparam == O_BTN_C)
           {
            DoCalculate();
           }
         else
            if(sparam == O_BTN_P)
              {
               TogglePath();
              }
            else
               if(sparam == O_BTN_X)
                 {
                  ClearAll();
                 }
      return;
     }

//--- Panel background drag (move whole panel)
   if(id == CHARTEVENT_OBJECT_DRAG && (sparam == O_BG || sparam == O_GRAB))
     {
      int nx = (int)ObjectGetInteger(0, sparam, OBJPROP_XDISTANCE);
      int ny = (int)ObjectGetInteger(0, sparam, OBJPROP_YDISTANCE);
      MovePanelTo(nx, ny);
      return;
     }

//--- Vertical line drag (adjust selection range)
   if(id == CHARTEVENT_OBJECT_DRAG)
     {
      string objName = sparam;

      if(StringFind(objName, PREFIX "Start") == 0)
        {
         datetime newTime = SnapToBarTime((datetime)ObjectGetInteger(0, objName, OBJPROP_TIME, 0));
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
         datetime newTime = SnapToBarTime((datetime)ObjectGetInteger(0, objName, OBJPROP_TIME, 0));
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
      if(false)  // (old overlay guard; the path strip is now in its own subwindow)
         return;

      datetime clickTime = 0;
      double clickPrice = 0;
      int subwindow = 0;
      if(ChartXYToTimePrice(0, x, y, subwindow, clickTime, clickPrice))
        {
         if(subwindow != 0)
            return;   // clicks inside the path subwindow must not select a range
         OnMouseClick(clickTime);
        }
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
//| Snap a click/drag time to the open time of the bar under it,     |
//| so the selected range always covers whole candles (both edges).  |
//+------------------------------------------------------------------+
datetime SnapToBarTime(datetime t)
  {
   int bars = iBars(_Symbol, _Period);
   if(bars <= 0)
      return(t);

   int idx = iBarShift(_Symbol, _Period, t, false);
   if(idx < 0 || idx >= bars)
      return(t);

   datetime bt = iTime(_Symbol, _Period, idx);
   if(bt <= 0)
      return(t);

   return(bt);
  }

//+------------------------------------------------------------------+
//| Mouse click processing (no popup alerts anymore)                 |
//+------------------------------------------------------------------+
void OnMouseClick(datetime clickTime)
  {
   if(!EnableSelection)
      return;

   clickTime = SnapToBarTime(clickTime);

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
      UpdateProjection();
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
   ResetProjectionState();
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

   for(int i = bars - 1; i >= 0; i--)
     {
      datetime barTime = iTime(_Symbol, _Period, i);
      if(barTime >= Sel.StartTime && barTime <= Sel.EndTime)
         SelectedCandleCount++;
     }
  }

//+------------------------------------------------------------------+
//| Classify a candle as Spike / Trend / Doji                        |
//|   Body      = |Close - Open|                                     |
//|   bullish (Close>=Open): ShadowUp = High-Close , ShadowDown = Open-Low |
//|   bearish (Close<Open) : ShadowUp = High-Open  , ShadowDown = Close-Low |
//|                                                                    |
//|   Body==0 -> "Doji" | shadows below threshold -> "Spike"           |
//|   any shadow >= TrendShadowRatio * Body -> "Trend"           |
//|   otherwise                                 -> "Spike"            |
//+------------------------------------------------------------------+
string ClassifyCandle(double o, double h, double l, double c)
  {
   double body = MathAbs(c - o);
   double shadowUp, shadowDown;

   if(c >= o) // bullish
     {
      shadowUp   = h - c;
      shadowDown = o - l;
     }
   else       // bearish
     {
      shadowUp   = h - o;
      shadowDown = c - l;
     }

   if(shadowUp < 0)
      shadowUp = 0;
   if(shadowDown < 0)
      shadowDown = 0;

   if(body <= 0)
      return("Doji");

   if(shadowUp <= 0 && shadowDown <= 0)
      return("Spike");

   double ratioUp   = shadowUp   / body;
   double ratioDown = shadowDown / body;

   if(ratioUp >= TrendShadowRatio || ratioDown >= TrendShadowRatio)
      return("Trend");

   return("Spike");
  }

//+------------------------------------------------------------------+
//| Calculate path points                                            |
//| Point order on X axis depends on candle direction       |
//|   bullish: O -> L -> H -> C | bearish: O -> H -> L -> C                |
//|   each point keeps its own price                |
//+------------------------------------------------------------------+
void CalculatePath()
  {
   ArrayResize(PathArray, 0);
   PathCount = 0;

   ArrayResize(CandleClass, 0);
   CandleClassCount = 0;

   int bars = iBars(_Symbol, _Period);

   /* --- direction logic removed: order is always O -> H -> L -> C ---
   bool IsBullish = true;
   bool found = false;
   double closeEnd   = 0;
   double closeStart = 0;

   for(int i = bars - 1; i >= 0; i--)
   {
      datetime bt = iTime(_Symbol, _Period, i);
      if(bt < Sel.StartTime || bt > Sel.EndTime)
         continue;
      if(!found)
      {
         closeStart = iClose(_Symbol, _Period, i);
         found = true;
      }
      closeEnd = iClose(_Symbol, _Period, i);
   }

   if(found)
      IsBullish = (closeEnd >= closeStart);

   */

//--- build the path
   for(int i = bars - 1; i >= 0; i--)
     {
      datetime bt = iTime(_Symbol, _Period, i);
      if(bt < Sel.StartTime || bt > Sel.EndTime)
         continue;

      double o = iOpen(_Symbol, _Period, i);
      double h = iHigh(_Symbol, _Period, i);
      double l = iLow(_Symbol, _Period, i);
      double c = iClose(_Symbol, _Period, i);

      //--- classify this candle (Spike / Trend / Doji) and store it,
      //    in the same left-to-right order the candles are added below
      ArrayResize(CandleClass, CandleClassCount + 1);
      CandleClass[CandleClassCount] = ClassifyCandle(o, h, l, c);
      CandleClassCount++;
      /* --- old direction-based order (O,L,H,C for bearish) disabled ---

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

      */

      //--- X order depends on candle direction:
      //    bullish: O -> L -> H -> C | bearish: O -> H -> L -> C
      if(c >= o)
        {
         //--- bullish: points on X axis in order O, L, H, C
         AddPathPoint(bt, o, "O");
         AddPathPoint(bt, l, "L");
         AddPathPoint(bt, h, "H");
         AddPathPoint(bt, c, "C");
        }
      else
        {
         //--- bearish: points on X axis in order O, H, L, C
         AddPathPoint(bt, o, "O");
         AddPathPoint(bt, h, "H");
         AddPathPoint(bt, l, "L");
         AddPathPoint(bt, c, "C");
        }
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
//+------------------------------------------------------------------+
//| T-Line (cx/cy/n/t) projection                                   |
//|                                                                  |
//| Definition requested for this version:                          |
//|   cx = OPEN of the FIRST candle under the green START line.     |
//|   direction = overall direction of the selected piece, measured  |
//|              from the first selected candle OPEN to the last    |
//|              selected candle close.                              |
//|   cy = close of the FIRST candle, scanning left -> right, whose  |
//|        direction is opposite to the selected piece.              |
//|   n  = ABS(cy - cx), i.e. the price distance from cx to cy.      |
//|   t  = cy + n  for a bullish selected piece,                     |
//|        t  = cy - n  for a bearish selected piece.                |
//|                                                                  |
//| The result t is a PRICE level. A finite horizontal segment is    |
//| drawn on the main chart at that exact price, beginning around    |
//| the cy candle. No projection-by-bar-index is used here.          |
//+------------------------------------------------------------------+
void DeleteProjectionObjects()
  {
   ObjectDelete(0, PREFIX "TLine");
   ObjectDelete(0, PREFIX "TLabel");
   ObjectDelete(0, PREFIX "TInfo");
   TLineDrawn = false;
  }

//+------------------------------------------------------------------+
//| Reset T-line state                                               |
//+------------------------------------------------------------------+
void ResetProjectionState()
  {
   DeleteProjectionObjects();
   TLineWaitReason = "";
   TLineStartBar = -1;
   TLineEndBar   = -1;
   TLineCx       = 0;
   TLineCy       = 0;
   TLineN        = 0;
   TLineT        = 0;
   TLineBullDirection = true;
  }

//+------------------------------------------------------------------+
//| Draw the finite horizontal T price segment on the MAIN chart.    |
//| The segment is centered on the first opposite candle (cy).       |
//+------------------------------------------------------------------+
void DrawTLineAt(int cyBarIdx, double price)
  {
   string objName = PREFIX "TLine";
   ObjectDelete(0, objName);

   datetime cyTime = iTime(_Symbol, _Period, cyBarIdx);
   if(cyTime <= 0)
      return;

   int width = MathMax(1, TLineCandleWidth);
   long step = (long)PeriodSeconds(_Period);
   if(step <= 0)
      step = 60;

   int leftBars  = width / 2;
   int rightBars = width - leftBars;
   datetime t1 = (datetime)((long)cyTime - step * leftBars);
   datetime t2 = (datetime)((long)cyTime + step * rightBars);

   if(!ObjectCreate(0, objName, OBJ_TREND, 0, t1, price, t2, price))
     {
      Print("[PPA-TLine] ObjectCreate failed. Error=", GetLastError());
      return;
     }

   ObjectSetInteger(0, objName, OBJPROP_RAY,        false);
   ObjectSetInteger(0, objName, OBJPROP_COLOR,      TLineColor);
   ObjectSetInteger(0, objName, OBJPROP_STYLE,      TLineStyle);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH,      MathMax(1, TLineThick));
   ObjectSetInteger(0, objName, OBJPROP_BACK,       false);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objName, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, ALL_TF);

   if(TLineShowLabel)
     {
      string lblName = PREFIX "TLabel";
      ObjectDelete(0, lblName);
      if(ObjectCreate(0, lblName, OBJ_TEXT, 0, t2, price))
        {
         ObjectSetString(0, lblName, OBJPROP_TEXT, "T");
         ObjectSetInteger(0, lblName, OBJPROP_COLOR, TLineLabelColor);
         ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, 10);
         ObjectSetInteger(0, lblName, OBJPROP_ANCHOR, ANCHOR_LEFT);
         ObjectSetInteger(0, lblName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, lblName, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, lblName, OBJPROP_TIMEFRAMES, ALL_TF);
        }
     }

   TLineDrawn = true;
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Small info label showing the actual cx/cy/n/t calculation.       |
//+------------------------------------------------------------------+
void UpdateTInfoLabel()
  {
   string lblName = PREFIX "TInfo";
   if(ObjectFind(0, lblName) < 0)
     {
      if(!ObjectCreate(0, lblName, OBJ_LABEL, 0, 0, 0))
         return;
      ObjectSetInteger(0, lblName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, lblName, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, lblName, OBJPROP_YDISTANCE, 10);
      ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, lblName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, lblName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, lblName, OBJPROP_TIMEFRAMES, ALL_TF);
     }
   ObjectSetInteger(0, lblName, OBJPROP_COLOR, TLineColor);
   ObjectSetString(0, lblName, OBJPROP_TEXT, "cx/cy/n/t:" + TLineStatusLine());
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Compute cx/cy/n/t from the selected range.                       |
//| IMPORTANT: cy is NOT the last selected candle. It is the FIRST   |
//| opposite-direction candle encountered from left to right.       |
//+------------------------------------------------------------------+
void UpdateProjection()
  {
   ResetProjectionState();

   if(!EnableTLine || !Sel.HasSelection)
      return;

   int bars = iBars(_Symbol, _Period);
   if(bars <= 0)
      return;

   int sb = iBarShift(_Symbol, _Period, Sel.StartTime, false);
   int eb = iBarShift(_Symbol, _Period, Sel.EndTime, false);
   if(sb < 0 || eb < 0 || sb < eb)
      return;

   //--- Chronological left-to-right order is: sb, sb-1, ..., eb.
   double firstClose = iClose(_Symbol, _Period, sb);
   double lastClose  = iClose(_Symbol, _Period, eb);
   double firstOpen  = iOpen(_Symbol, _Period, sb);

   //--- Direction of the selected piece. If net close is unchanged,
   //    use the first candle direction as the tie-breaker.
   if(lastClose > firstClose)
      TLineBullDirection = true;
   else
      if(lastClose < firstClose)
         TLineBullDirection = false;
      else
         TLineBullDirection = (firstClose >= firstOpen);

   //--- cx is ALWAYS the OPEN of the first candle under START.
   TLineStartBar = sb;
   TLineCx = firstOpen;

   //--- Scan from left to right and find the FIRST opposite candle.
   int cyBar = -1;
   for(int k = sb - 1; k >= eb; k--)
     {
      double ko = iOpen(_Symbol, _Period, k);
      double kc = iClose(_Symbol, _Period, k);

      bool candleBull = (kc > ko);
      bool candleBear = (kc < ko);

      // Doji is neither direction, so it is not the opposite candle.
      if(TLineBullDirection && candleBear)
        {
         cyBar = k;
         break;
        }
      if(!TLineBullDirection && candleBull)
        {
         cyBar = k;
         break;
        }
     }

   if(cyBar < 0)
     {
      TLineWaitReason = TLineBullDirection
                         ? "no bearish candle after START inside selection"
                         : "no bullish candle after START inside selection";
      UpdateTInfoLabel();
      return;
     }

   TLineEndBar = cyBar;
   TLineCy = iClose(_Symbol, _Period, cyBar);

   //--- n is the ABSOLUTE price distance cx -> cy.
   TLineN = MathAbs(TLineCy - TLineCx);

   //--- t is the same distance projected beyond cy in the direction
   //    of the selected piece: cy+n for bullish, cy-n for bearish.
   if(TLineBullDirection)
      TLineT = TLineCy + TLineN;
   else
      TLineT = TLineCy - TLineN;

   //--- Optional spike filter now checks the candles from START through CY.
   if(TLineSpikeFilter > 0)
     {
      int spikeCount = 0;
      for(int k = sb; k >= cyBar; k--)
        {
         double ko = iOpen(_Symbol, _Period, k);
         double kh = iHigh(_Symbol, _Period, k);
         double kl = iLow(_Symbol, _Period, k);
         double kc = iClose(_Symbol, _Period, k);
         if(ClassifyCandle(ko, kh, kl, kc) == "Spike")
            spikeCount++;
        }

      if(spikeCount < TLineSpikeFilter)
        {
         TLineWaitReason = "need at least " + IntegerToString(TLineSpikeFilter) +
                           " Spike candle(s) from START to CY";
         UpdateTInfoLabel();
         return;
        }
     }

   UpdateTInfoLabel();
   DrawTLineAt(cyBar, TLineT);
  }

//+------------------------------------------------------------------+
//| Status line for the cx/cy/n/t calculation.                       |
//+------------------------------------------------------------------+
string TLineStatusLine()
  {
   if(!EnableTLine)
      return("");

   if(TLineEndBar < 0)
      return("\nwaiting - " + (TLineWaitReason != "" ? TLineWaitReason : "no valid opposite candle"));

   string dir = TLineBullDirection ? "+" : "-";
   string s = "\ncx=" + DoubleToString(TLineCx, _Digits) +
              " cy=" + DoubleToString(TLineCy, _Digits) +
              " n=" + DoubleToString(TLineN, _Digits) +
              " t=" + DoubleToString(TLineT, _Digits) +
              " (" + dir + ")" +
              (TLineDrawn ? " [drawn]" : " [pending]");
   return(s);
  }

//+------------------------------------------------------------------+
//| Draw the vertical selection lines                                |
//+------------------------------------------------------------------+
void DrawStartLine()
  {
   string lineName = PREFIX "Start";
   EnsureObject(lineName, OBJ_VLINE);
   ObjectSetInteger(0, lineName, OBJPROP_TIME, Sel.StartTime);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, StartLineColor);
   ObjectSetInteger(0, lineName, OBJPROP_WIDTH, LineWidth);
   ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, lineName, OBJPROP_TIMEFRAMES, ALL_TF);

   string labelName = PREFIX "StartLabel";
   EnsureObject(labelName, OBJ_TEXT);
   ObjectSetInteger(0, labelName, OBJPROP_TIME, Sel.StartTime);
   ObjectSetString(0, labelName, OBJPROP_TEXT, "START");
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, StartLineColor);
   ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, labelName, OBJPROP_TIMEFRAMES, ALL_TF);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DrawEndLine()
  {
   string lineName = PREFIX "End";
   EnsureObject(lineName, OBJ_VLINE);
   ObjectSetInteger(0, lineName, OBJPROP_TIME, Sel.EndTime);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, EndLineColor);
   ObjectSetInteger(0, lineName, OBJPROP_WIDTH, LineWidth);
   ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, lineName, OBJPROP_TIMEFRAMES, ALL_TF);

   string labelName = PREFIX "EndLabel";
   EnsureObject(labelName, OBJ_TEXT);
   ObjectSetInteger(0, labelName, OBJPROP_TIME, Sel.EndTime);
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

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SetObjTimeframes(string name, bool visible)
  {
   if(ObjectFind(0, name) >= 0)
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, visible ? ALL_TF : NO_TF);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DeleteLineObjects()
  {
   ObjectDelete(0, PREFIX "Start");
   ObjectDelete(0, PREFIX "End");
   ObjectDelete(0, PREFIX "StartLabel");
   ObjectDelete(0, PREFIX "EndLabel");
  }

//+------------------------------------------------------------------+
//| Convert a price to a Y pixel inside the strip     |
//| (price is measured in pips from the lowest low of the range)    |
//+------------------------------------------------------------------+
int PipToY(double price, double pmin, double pip, double totalPips, int bottom, int top)
  {
   double pips = (price - pmin) / pip;
   return(bottom - (int)MathRound(pips / totalPips * (bottom - top)));
  }

//+------------------------------------------------------------------+
//| X coordinate of a path point inside the table                    |
//| ci  = candle index (0-based), rem = point inside candle (0..3)   |
//+------------------------------------------------------------------+
int PathPointX(int ci, int rem, int denom, int left, int right)
  {
   int halfSp = (int)MathRound(MathMin(40.0, (double)(right - left) / denom / 2.0));
   int cap = (right - left) / 4;
   if(halfSp > cap)
      halfSp = cap;
   if(halfSp < 1)
      halfSp = 1;

   double span = (double)(right - left) - 2.0 * halfSp;
   if(span < 1.0)
      span = 1.0;

   int x = left + halfSp + (int)MathRound((double)ci / denom * span)
           + (int)MathRound(((double)rem - 1.5) / 1.5 * halfSp);
   return(x);
  }

//+------------------------------------------------------------------+
//| Draw the path strip at the TOP of the chart (canvas overlay)     |
//| X axis = candle number (left -> right), Y axis = price in pips    |
//| Candles instead of a polyline: body = O/C, wick = H/L             |
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
   int swH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, MySubwindow);
   if(swH >= 60)
      ch = swH - 2;      // fill the whole subwindow height
   if(ch < 60)
      ch = 60;

//--- after a timeframe change the old canvas object is still on the chart
//    (OnDeinit keeps objects so state can be restored). Delete it first,
//    otherwise CreateBitmapLabel fails and the path strip disappears.
   if(ObjectFind(0, O_CANVAS) >= 0)
      ObjectDelete(0, O_CANVAS);

   if(!Canvas.CreateBitmapLabel(0, MySubwindow, O_CANVAS, 0, 0, cw, ch))
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
   int left     = MathMax(30, TableFontSize * 4 + 4);   // space for price labels (Y axis)
   int right    = cw - 8;
   int classRowY = 15;     // row for the Spike/Trend/Doji boxes (below title)
   int top      = 32;      // below the title + classification row
   int bottom   = ch - 14; // space for candle-number labels (X axis)

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
   Canvas.TextOut(8, 3, "PRICE PATH (PRICE)  |  " + _Symbol + " " + TimeframeStr() + "  |  " +
                  IntegerToString(candles) + " candles", XRGB(255, 215, 0), 0);

//--- price scale (actual price, not pips)

   double pmin = PathArray[0].Price;
   double pmax = PathArray[0].Price;
   for(int i = 1; i < PathCount; i++)
     {
      if(PathArray[i].Price < pmin)
         pmin = PathArray[i].Price;
      if(PathArray[i].Price > pmax)
         pmax = PathArray[i].Price;
     }

   double totalPrice = pmax - pmin;
   if(totalPrice <= 0)
      totalPrice = _Point * 10;
   double step = NiceStep(totalPrice / 5.0);
   int dec = 0;
   double sd = step;
   while(sd < 1 && dec < 8)
     {
      sd *= 10;
      dec++;
     }

   int denom = (candles > 1 ? candles - 1 : 1);

//--- Spike / Trend / Doji classification boxes (one per candle, top row)
   Canvas.FontSet("Arial", ClassFontSize, 0, 0);
   for(int ci = 0; ci < candles; ci++)
     {
      if(ci >= CandleClassCount)
         break;

      string cls = CandleClass[ci];

      uint boxColor;
      if(cls == "Spike")
         boxColor = XRGB(190, 60, 60);   // red-ish
      else
         if(cls == "Trend")
            boxColor = XRGB(50, 150, 90);   // green-ish
         else
            boxColor = XRGB(100, 100, 110); // gray (Doji)

      //--- center the box on this candle's 4 points
      int xStart = PathPointX(ci, 0, denom, left, right);
      int xEnd   = PathPointX(ci, 3, denom, left, right);
      int cx     = (xStart + xEnd) / 2;

      int boxHalfW = MathMax(18, ClassFontSize * 3);
      int boxTop   = classRowY;
      int boxBot   = classRowY + ClassFontSize + 4;

      Canvas.FillRectangle(cx - boxHalfW, boxTop, cx + boxHalfW, boxBot, boxColor);
      Canvas.Rectangle(cx - boxHalfW, boxTop, cx + boxHalfW, boxBot, XRGB(15, 17, 20));
      Canvas.TextOut(cx - boxHalfW + 3, boxTop + 2, cls, XRGB(255, 255, 255), 0);
     }

//--- X axis (bottom): one number per point, left to right
//    candle 1: O=1 L=2 H=3 C=4 (bull) / O=1 H=2 L=3 C=4 (bear), ...
   int labelEvery = 1;
   int maxXLabels = (right - left) / (TableFontSize * 3);
   if(maxXLabels < 1)
      maxXLabels = 1;
   if(candles * 4 > maxXLabels)
      labelEvery = (int)MathCeil((double)(candles * 4) / (double)maxXLabels);

   Canvas.FontSet("Arial", TableFontSize, 0, 0);
   for(int j = 0; j < candles * 4; j += labelEvery)
     {
      int ci = j / 4;
      int x = PathPointX(ci, j % 4, denom, left, right);
      // (labels are placed inside the table by PathPointX margins)
      Canvas.LineVertical(x, top, bottom, XRGB(45, 55, 70));
      Canvas.TextOut(x - (TableFontSize / 2 + 2), ch - TableFontSize - 6, IntegerToString(j + 1), XRGB(170, 190, 210), 0);
     }
//--- last point gridline + label
// (last point index = candles*4 - 1, handled directly below)
   int xLast = PathPointX(candles - 1, 3, denom, left, right);
// (PathPointX places the last point inside the table via margins)
   Canvas.LineVertical(xLast, top, bottom, XRGB(45, 55, 70));
   Canvas.TextOut(xLast - (TableFontSize + 2), ch - TableFontSize - 6, IntegerToString(candles * 4), XRGB(170, 190, 210), 0);

//--- Y axis (left): price labels, bottom -> top
   int nGrid = (int)MathFloor(totalPrice / step);
   for(int g = 0; g <= nGrid; g++)
     {
      double price = pmin + g * step;
      int y = bottom - (int)MathRound((price - pmin) / totalPrice * (bottom - top));
      Canvas.LineHorizontal(left, right, y, XRGB(45, 55, 70));
      Canvas.TextOut(2, y - TableFontSize / 2 - 1, DoubleToString(price, dec), XRGB(170, 190, 210), 0);
     }

   /* ---- candle-body drawing disabled (4-point polyline used instead) ----
   //--- draw candles: X = candle column (number), Y = price in pips
   int bodyHalf = (int)MathMax(2, MathMin(20, (double)(right - left) / denom / 3.0));

   for(int j = 0; j + 3 < PathCount; j += 4)
   {
      int ci = j / 4;

      //--- read O/H/L/C from the 4 points of this candle
      double oc = 0, hh = 0, ll = 0, cc = 0;
      for(int k = 0; k < 4; k++)
      {
         double pr = PathArray[j + k].Price;
         if(PathArray[j + k].Label == "O") oc = pr;
         else if(PathArray[j + k].Label == "H") hh = pr;
         else if(PathArray[j + k].Label == "L") ll = pr;
         else if(PathArray[j + k].Label == "C") cc = pr;
      }

      int x  = left + (int)MathRound((double)ci / denom * (right - left));
      int yo = PipToY(oc, pmin, pip, totalPips, bottom, top);
      int yh = PipToY(hh, pmin, pip, totalPips, bottom, top);
      int yl = PipToY(ll, pmin, pip, totalPips, bottom, top);
      int yc = PipToY(cc, pmin, pip, totalPips, bottom, top);

      //--- color: bullish = close>=open, bearish = close<open, doji = path color
      uint col;
      if(cc > oc)      col = COLOR2RGB(BullColor);
      else if(cc < oc) col = COLOR2RGB(BearColor);
      else             col = COLOR2RGB(PathColor);

      //--- wick (high -> low)
      Canvas.LineVertical(x, yh, yl, col);

      //--- body (open -> close), min 1px so a doji stays visible
      int bodyTop = MathMin(yo, yc);
      int bodyH   = MathMax(MathAbs(yo - yc), 1);
      Canvas.FillRectangle(x - bodyHalf, bodyTop, x + bodyHalf, bodyTop + bodyH - 1, col);

      //--- thin dark outline for contrast
      if(bodyH >= 3)
         Canvas.Rectangle(x - bodyHalf, bodyTop, x + bodyHalf, bodyTop + bodyH - 1, XRGB(12, 14, 18));
   }

   */

//--- map path: X = candle column, Y = actual price
   int px[];
   int py[];
   ArrayResize(px, PathCount);
   ArrayResize(py, PathCount);

   for(int j = 0; j < PathCount; j++)
     {
      int ci = j / 4;

      px[j] = PathPointX(ci, j % 4, denom, left, right);
      // (PathPointX places the first/last points inside the table via margins)
      py[j] = bottom - (int)MathRound((PathArray[j].Price - pmin) / totalPrice * (bottom - top));
     }

//--- blue path line
//--- no connecting line: every point stays at its own position

//--- colored points (O/H/L/C)
   for(int j = 0; j < PathCount; j++)
     {
      uint pc = COLOR2RGB(PathColor);
      if(PathArray[j].Label == "O")
         pc = COLOR2RGB(OpenColor);
      else
         if(PathArray[j].Label == "H")
            pc = COLOR2RGB(HighColor);
         else
            if(PathArray[j].Label == "L")
               pc = COLOR2RGB(LowColor);
            else
               if(PathArray[j].Label == "C")
                  pc = COLOR2RGB(CloseColor);

      Canvas.FillCircle(px[j], py[j], 2, pc);
     }

//--- connect the 4 points of every candle (directional order)
   if(ConnectCandles && candles >= 1 && PathCount >= 4)
     {
      uint lc = COLOR2RGB(ConnectLineColor);

      // connect this candle's 4 points in directional order
      for(int c = 0; c < candles; c++)
        {
         int b = c * 4;   // points already stored in X order (see CalculatePath)
         // connect the 4 points in their stored order
         for(int s = 0; s < 3; s++)
            Canvas.Line(px[b + s], py[b + s], px[b + s + 1], py[b + s + 1], lc);
        }


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
   if(n < 1.5)
      return(1 * m);
   if(n < 3.5)
      return(2 * m);
   if(n < 7.5)
      return(5 * m);
   return(10 * m);
  }

//+------------------------------------------------------------------+
//| Timeframe string (M1, M5, H1, D1 ...)                            |
//+------------------------------------------------------------------+
string TimeframeStr()
  {
   int sec = PeriodSeconds(_Period);
   if(sec >= 86400)
      return(IntegerToString(sec / 86400) + "D");
   if(sec >= 3600)
      return(IntegerToString(sec / 3600) + "H");
   if(sec >= 60)
      return(IntegerToString(sec / 60) + "M");
   return(IntegerToString(sec) + "S");
  }

//+------------------------------------------------------------------+
//| Panel creation                                                   |
//+------------------------------------------------------------------+
void CreatePanel()
  {
//--- background (draggable, with border) - reuse existing object if present
   EnsureObject(O_BG, OBJ_RECTANGLE_LABEL);
   if(ObjectFind(0, O_BG) >= 0)
     {
      PanelX = (int)ObjectGetInteger(0, O_BG, OBJPROP_XDISTANCE);
      PanelY = (int)ObjectGetInteger(0, O_BG, OBJPROP_YDISTANCE);
     }
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

//--- grab bar: drag the whole panel from this top strip
   RegisterChild(O_GRAB, 0, 0);
   EnsureObject(O_GRAB, OBJ_RECTANGLE_LABEL);
   ObjectSetInteger(0, O_GRAB, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, O_GRAB, OBJPROP_XDISTANCE, PanelX);
   ObjectSetInteger(0, O_GRAB, OBJPROP_YDISTANCE, PanelY);
   ObjectSetInteger(0, O_GRAB, OBJPROP_XSIZE, PN_W);
   ObjectSetInteger(0, O_GRAB, OBJPROP_YSIZE, 22);
   ObjectSetInteger(0, O_GRAB, OBJPROP_BGCOLOR, C'38,46,70');
   ObjectSetInteger(0, O_GRAB, OBJPROP_BORDER_COLOR, clrGold);
   ObjectSetInteger(0, O_GRAB, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, O_GRAB, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, O_GRAB, OBJPROP_BACK, false);
   ObjectSetInteger(0, O_GRAB, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, O_GRAB, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, O_GRAB, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, O_GRAB, OBJPROP_ZORDER, 100);
   ObjectSetInteger(0, O_GRAB, OBJPROP_TIMEFRAMES, ALL_TF);

//--- children (relative offsets, moved together with panel)
   RegisterChild(O_TITLE, 10, 6);
   EnsureObject(O_TITLE, OBJ_LABEL);
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
   EnsureObject(O_STAT, OBJ_LABEL);
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
//| Move the whole panel to a new position                           |
//+------------------------------------------------------------------+
void MovePanelTo(int x, int y)
  {
   PanelX = x;
   PanelY = y;
   if(ObjectFind(0, O_BG) >= 0)
     {
      ObjectSetInteger(0, O_BG, OBJPROP_XDISTANCE, PanelX);
      ObjectSetInteger(0, O_BG, OBJPROP_YDISTANCE, PanelY);
     }
   MovePanelChildren();
   ChartRedraw();
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
   EnsureObject(name, OBJ_BUTTON);
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

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//|                                                                  |
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
//--- keep the hidden scale buffers in sync with the selected range
   for(int i = 0; i < rates_total; i++)
     {
      PathHighBuf[i] = EMPTY_VALUE;
      PathLowBuf[i]  = EMPTY_VALUE;
     }
   if(Sel.HasSelection)
     {
      for(int i = rates_total - 1; i >= 0; i--)
        {
         if(time[i] >= Sel.StartTime && time[i] <= Sel.EndTime)
           {
            PathHighBuf[i] = high[i];
            PathLowBuf[i]  = low[i];
           }
        }
     }
//--- T-line live update: draw the horizontal line as soon as bar t
//    appears on the chart (works in live market and on history)
   if(prev_calculated == 0 || prev_calculated < rates_total)
     {
      if(!TLineDrawn && EnableTLine && Sel.HasSelection)
         UpdateProjection();
     }

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Find the subwindow that belongs to this indicator                |
//+------------------------------------------------------------------+
int FindOwnSubwindow()
  {
   int total = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
   for(int w = 1; w < total; w++)
     {
      if(ChartIndicatorGet(0, w, "PPA_Path") != INVALID_HANDLE)
         return(w);
     }
   return(1);
  }
//+------------------------------------------------------------------+
//| End of spikedetector   arad azadbakht                            |
//+------------------------------------------------------------------+
