// soon
//+------------------------------------------------------------------+
//|                    Cycle Market  v1.0                              |
//|  Analysis-only indicator (panel layout like SP2L / Spike)          |
//|  3 mode buttons: Spike / Chanel / Range  +  Check + Clear          |
//|  Selection: green (START) + yellow (END) vertical lines, width 2   |
//|  Panel: fixed at the right-top corner, near the price scale        |
//|  Display box above the Spike button shows the detection result     |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_type1   DRAW_NONE
#property indicator_color1  clrDodgerBlue
#property indicator_label1  "CycleMarket"

//--- ONLY input: spike deviation threshold (in points)
input int  SpikeDevPts = 50;      // Spike: min |Close - 1h MA| deviation (points)

//--- object names
#define PREFIX      "CM_"
#define O_BG        PREFIX "Panel_BG"
#define O_DISP_BG   PREFIX "Disp_BG"
#define O_DISP_LBL  PREFIX "Disp_Label"
#define O_BTN_S     PREFIX "Btn_Spike"
#define O_BTN_C     PREFIX "Btn_Chanel"
#define O_BTN_R     PREFIX "Btn_Range"
#define O_BTN_CHK   PREFIX "Btn_Check"
#define O_BTN_X     PREFIX "Btn_Clear"
#define O_START     PREFIX "Start"
#define O_END       PREFIX "End"

#define ALL_TF  0xFFFFFFFF
#define NO_TF   0

//--- panel geometry (fixed, like SP2L: right-top, near the price)
#define PN_W     204
#define PN_H     198
#define PANEL_X  180      // distance from the RIGHT edge (px)
#define PANEL_Y  150      // distance from the TOP edge (px)

//--- modes
enum CM_Mode
  {
   CM_NONE   = 0,
   CM_SPIKE  = 1,
   CM_CHANEL = 2,
   CM_RANGE  = 3
  };

//--- state
struct SelState
  {
   bool              InSelection;
   datetime          StartTime;
   datetime          EndTime;
   bool              HasSelection;
  };

CM_Mode  g_mode = CM_NONE;
SelState Sel;
double   Dummy[];

//+------------------------------------------------------------------+
//| Indicator initialization                                          |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, Dummy, INDICATOR_DATA);
   IndicatorSetString(INDICATOR_SHORTNAME, "Cycle Market");

//--- restore the last selected mode from a terminal global variable
   string gvMode = "CM_Mode_" + IntegerToString(ChartID());
   g_mode = CM_NONE;
   if(GlobalVariableCheck(gvMode))
      g_mode = (CM_Mode)(int)GlobalVariableGet(gvMode);

   Sel.InSelection = false;
   Sel.StartTime   = 0;
   Sel.EndTime     = 0;
   Sel.HasSelection= false;

//--- restore the selection from surviving chart objects (TF change)
   if(ObjectFind(0, O_START) >= 0 && ObjectFind(0, O_END) >= 0)
     {
      Sel.StartTime    = (datetime)ObjectGetInteger(0, O_START, OBJPROP_TIME, 0);
      Sel.EndTime      = (datetime)ObjectGetInteger(0, O_END, OBJPROP_TIME, 0);
      Sel.HasSelection = (Sel.EndTime > Sel.StartTime);
     }

   CreatePanel();
   ApplyModeButtons();

   if(Sel.HasSelection)
     {
      DrawStartLine();
      DrawEndLine();
      UpdateDisplay("press Check");
     }
   else
      UpdateDisplay("");

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Indicator deinitialization                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   string gvMode = "CM_Mode_" + IntegerToString(ChartID());
   GlobalVariableSet(gvMode, (double)g_mode);

//--- on TF change / parameter change keep the chart objects
   if(reason == REASON_CHARTCHANGE || reason == REASON_PARAMETERS)
     {
      ChartRedraw();
      return;
     }

   ObjectsDeleteAll(0, PREFIX);
   GlobalVariableDel(gvMode);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Chart events                                                      |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
//--- button clicks
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      if(sparam == O_BTN_S)
         ToggleMode(CM_SPIKE);
      else
         if(sparam == O_BTN_C)
            ToggleMode(CM_CHANEL);
         else
            if(sparam == O_BTN_R)
               ToggleMode(CM_RANGE);
            else
               if(sparam == O_BTN_CHK)
                  DoCheck();
               else
                  if(sparam == O_BTN_X)
                     ClearAll();
      return;
     }

//--- chart click -> selection (start = green, end = yellow)
   if(id == CHARTEVENT_CLICK)
     {
      int x = (int)lparam;
      int y = (int)dparam;

      if(IsPointOnPanel(x, y))
         return;

      datetime clickTime = 0;
      double clickPrice = 0;
      int subwindow = 0;
      if(ChartXYToTimePrice(0, x, y, subwindow, clickTime, clickPrice))
        {
         if(subwindow != 0)
            return;
         OnChartClick(clickTime);
        }
      return;
     }

//--- lines dragged with the mouse -> keep the selection in sync
   if(id == CHARTEVENT_OBJECT_DRAG)
     {
      AfterLinesDragged();
      return;
     }
  }

//+------------------------------------------------------------------+
//| Snap a time to the bar open time                                  |
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
//| Chart click -> build the selection                                |
//+------------------------------------------------------------------+
void OnChartClick(datetime t)
  {
   if(g_mode == CM_NONE)
      return;

   t = SnapToBarTime(t);

   if(!Sel.InSelection)
     {
      ObjectDelete(0, O_END);
      Sel.StartTime   = t;
      Sel.InSelection = true;
      Sel.HasSelection= false;
      DrawStartLine();
      UpdateDisplay("now click END");
     }
   else
     {
      if(t <= Sel.StartTime)
        {
         UpdateDisplay("END after START");
         return;
        }
      Sel.EndTime      = t;
      Sel.InSelection  = false;
      Sel.HasSelection = true;
      DrawEndLine();
      UpdateDisplay("press Check");
     }
  }

//+------------------------------------------------------------------+
//| Mode buttons: radio behaviour (one ON at a time)                  |
//+------------------------------------------------------------------+
void ToggleMode(CM_Mode m)
  {
   if(g_mode == m)
      g_mode = CM_NONE;          // clicking the active mode turns it OFF
   else
      g_mode = m;                // activate this mode, others become OFF

   ApplyModeButtons();

   if(g_mode == CM_NONE)
     {
      UpdateDisplay("mode off");
      return;
     }

//--- two selector lines must appear (green + yellow)
   if(!Sel.HasSelection)
      CreateDefaultSelection();
   else
     {
      DrawStartLine();
      DrawEndLine();
     }

   UpdateDisplay("select range");
  }

//+------------------------------------------------------------------+
//| Refresh the look of the three mode buttons                        |
//+------------------------------------------------------------------+
void ApplyModeButtons()
  {
   SetBtnState(O_BTN_S, g_mode == CM_SPIKE,  "Spike",  C'25,155,70', C'28,55,38', clrWhite);
   SetBtnState(O_BTN_C, g_mode == CM_CHANEL, "Chanel", C'240,200,30', C'90,75,25', clrBlack);
   SetBtnState(O_BTN_R, g_mode == CM_RANGE,  "Range",  C'25,65,150', C'28,38,60', clrWhite);
  }

//+------------------------------------------------------------------+
//| Helper: set the state of one mode button                          |
//+------------------------------------------------------------------+
void SetBtnState(string name, bool on, string label, color onBg, color offBg, color tc)
  {
   ObjectSetString(0, name, OBJPROP_TEXT,   label + (on ? ": ON" : ": OFF"));
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, on ? onBg : offBg);
   ObjectSetInteger(0, name, OBJPROP_COLOR,   tc);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Check button: run the rule of the active mode                     |
//+------------------------------------------------------------------+
void DoCheck()
  {
   if(g_mode == CM_NONE)
     {
      UpdateDisplay("select mode");
      return;
     }
   if(!Sel.HasSelection)
     {
      UpdateDisplay("select range");
      return;
     }

   string res = "";
   switch(g_mode)
     {
      case CM_SPIKE:  res = CheckSpike();  break;
      case CM_CHANEL: res = CheckChanel(); break;
      case CM_RANGE:  res = CheckRange();  break;
     }
   UpdateDisplay(res);
  }

//+------------------------------------------------------------------+
//| SPIKE rule: selected candles too far from the 1-hour MA           |
//+------------------------------------------------------------------+
string CheckSpike()
  {
   if(SpikeDevPts <= 0)
      return("spike off");

//--- 1 hour = 3600 sec -> number of bars on the current timeframe
   int maPeriod = (int)MathMax(1, 3600 / PeriodSeconds(_Period));

   int bars = iBars(_Symbol, _Period);
   int sb = iBarShift(_Symbol, _Period, Sel.StartTime, false);
   int eb = iBarShift(_Symbol, _Period, Sel.EndTime, false);
   if(sb < 0 || eb < 0 || sb < eb || bars <= 0)
      return("no range");

   double maxDev = 0;
   for(int i = sb; i >= eb; i--)
     {
      if(i + maPeriod - 1 >= bars)
         continue;                       // not enough history for this bar
      double sum = 0;
      for(int k = i; k < i + maPeriod; k++)
         sum += iClose(_Symbol, _Period, k);
      double ma   = sum / maPeriod;
      double dev  = MathAbs(iClose(_Symbol, _Period, i) - ma) / _Point;
      if(dev > maxDev)
         maxDev = dev;
     }

   if(maxDev >= SpikeDevPts)
      return("spike");
   return("no spike");
  }

//+------------------------------------------------------------------+
//| CHANEL rule: start candle vs end candle -> trend direction        |
//+------------------------------------------------------------------+
string CheckChanel()
  {
   int sb = iBarShift(_Symbol, _Period, Sel.StartTime, false);
   int eb = iBarShift(_Symbol, _Period, Sel.EndTime, false);
   if(sb < 0 || eb < 0)
      return("no range");

   double cs = iClose(_Symbol, _Period, sb);
   double ce = iClose(_Symbol, _Period, eb);

   if(cs < ce)
      return("trend up");
   if(cs > ce)
      return("trend down");
   return("flat");
  }

//+------------------------------------------------------------------+
//| RANGE rule: highest high first, then lowest low, then revisit     |
//+------------------------------------------------------------------+
string CheckRange()
  {
   int sb = iBarShift(_Symbol, _Period, Sel.StartTime, false);
   int eb = iBarShift(_Symbol, _Period, Sel.EndTime, false);
   if(sb < 0 || eb < 0 || sb < eb)
      return("no range");

   int n = sb - eb + 1;                  // candles in selection, left -> right
   double highs[], lows[];
   ArrayResize(highs, n);
   ArrayResize(lows,  n);

   int idx = 0;
   for(int i = sb; i >= eb; i--)
     {
      highs[idx] = iHigh(_Symbol, _Period, i);
      lows[idx]  = iLow(_Symbol, _Period, i);
      idx++;
     }

//--- 1) leftmost candle with the highest high
   double hiH = highs[0];
   int    hiIdx = 0;
   for(int j = 1; j < n; j++)
      if(highs[j] > hiH)
        {
         hiH    = highs[j];
         hiIdx  = j;
        }

//--- 2) after it: the first candle that makes the lowest low
   double loL = lows[hiIdx + 1];
   int    loIdx = hiIdx + 1;
   for(int j = hiIdx + 2; j < n; j++)
      if(lows[j] < loL)
        {
         loL   = lows[j];
         loIdx = j;
        }

   if(loIdx <= hiIdx)
      return("no range");

   double span = hiH - loL;
   if(span <= 0)
      return("no range");

//--- 3) after the low: price must come back near the high / low levels
   bool revisit = false;
   for(int j = loIdx + 1; j < n && !revisit; j++)
     {
      if(highs[j] >= hiH - span * 0.30)
         revisit = true;
      if(lows[j]  <= loL + span * 0.10)
         revisit = true;
     }

   if(revisit)
      return("range");
   return("no range");
  }

//+------------------------------------------------------------------+
//| Create a default ~13-candle selection in the middle of the chart  |
//+------------------------------------------------------------------+
void CreateDefaultSelection()
  {
   int first = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
   int vis   = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
   if(vis <= 0)
      vis = 100;
   int center = first - vis / 2;
   int bars   = iBars(_Symbol, _Period);
   datetime centerTime = 0;
   if(center >= 0 && center < bars)
      centerTime = iTime(_Symbol, _Period, center);
   if(centerTime <= 0)
      centerTime = TimeCurrent();

   long step = (long)PeriodSeconds(_Period) * 6;
   Sel.StartTime    = (datetime)((long)centerTime - step);
   Sel.EndTime      = (datetime)((long)centerTime + step);
   Sel.InSelection  = false;
   Sel.HasSelection = (Sel.EndTime > Sel.StartTime);

   DrawStartLine();
   DrawEndLine();
   CenterOnSelection();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Center the chart on the selection                                 |
//+------------------------------------------------------------------+
void CenterOnSelection()
  {
   if(!Sel.HasSelection)
      return;
   int sb = iBarShift(_Symbol, _Period, Sel.StartTime, false);
   int eb = iBarShift(_Symbol, _Period, Sel.EndTime, false);
   if(sb < 0 || eb < 0)
      return;
   if(sb < eb)
     {
      int t = sb; sb = eb; eb = t;
     }
   int mid  = (sb + eb) / 2;
   int bars = iBars(_Symbol, _Period);
   if(bars <= 0)
      return;
   if(mid < 0)
      mid = 0;
   if(mid >= bars)
      mid = bars - 1;
   int visible = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
   if(visible <= 0)
      visible = 100;
   int f = mid + visible / 2;
   if(f >= bars)
      f = bars - 1;
   if(f < 0)
      f = 0;
   ChartSetInteger(0, CHART_FIRST_VISIBLE_BAR, f);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Lines dragged by the mouse                                        |
//+------------------------------------------------------------------+
void AfterLinesDragged()
  {
   if(ObjectFind(0, O_START) < 0 || ObjectFind(0, O_END) < 0)
      return;

   Sel.StartTime = SnapToBarTime((datetime)ObjectGetInteger(0, O_START, OBJPROP_TIME, 0));
   Sel.EndTime   = SnapToBarTime((datetime)ObjectGetInteger(0, O_END, OBJPROP_TIME, 0));

   if(Sel.EndTime > Sel.StartTime)
     {
      Sel.HasSelection = true;
      Sel.InSelection  = false;
      ObjectSetInteger(0, O_START, OBJPROP_TIME, Sel.StartTime);
      ObjectSetInteger(0, O_END,   OBJPROP_TIME, Sel.EndTime);
      UpdateDisplay("press Check");
     }
  }

//+------------------------------------------------------------------+
//| Draw the green START line                                         |
//+------------------------------------------------------------------+
void DrawStartLine()
  {
   EnsureObject(O_START, OBJ_VLINE);
   ObjectSetInteger(0, O_START, OBJPROP_TIME, Sel.StartTime);
   ObjectSetInteger(0, O_START, OBJPROP_COLOR, clrLimeGreen);
   ObjectSetInteger(0, O_START, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, O_START, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, O_START, OBJPROP_BACK, true);
   ObjectSetInteger(0, O_START, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, O_START, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, O_START, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, O_START, OBJPROP_TIMEFRAMES, ALL_TF);
  }

//+------------------------------------------------------------------+
//| Draw the yellow END line                                          |
//+------------------------------------------------------------------+
void DrawEndLine()
  {
   EnsureObject(O_END, OBJ_VLINE);
   ObjectSetInteger(0, O_END, OBJPROP_TIME, Sel.EndTime);
   ObjectSetInteger(0, O_END, OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, O_END, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, O_END, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, O_END, OBJPROP_BACK, true);
   ObjectSetInteger(0, O_END, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, O_END, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, O_END, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, O_END, OBJPROP_TIMEFRAMES, ALL_TF);
  }

//+------------------------------------------------------------------+
//| Clear the selection and the display box                           |
//+------------------------------------------------------------------+
void ClearAll()
  {
   ObjectDelete(0, O_START);
   ObjectDelete(0, O_END);
   Sel.InSelection  = false;
   Sel.StartTime    = 0;
   Sel.EndTime      = 0;
   Sel.HasSelection = false;
   UpdateDisplay("");
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Create an object if it does not exist yet                         |
//+------------------------------------------------------------------+
bool EnsureObject(string name, ENUM_OBJECT type)
  {
   if(ObjectFind(0, name) >= 0)
      return(true);
   return(ObjectCreate(0, name, type, 0, 0, 0));
  }

//+------------------------------------------------------------------+
//| Update the small display box above the Spike button               |
//+------------------------------------------------------------------+
void UpdateDisplay(string txt)
  {
   if(ObjectFind(0, O_DISP_LBL) < 0)
      return;
   ObjectSetString(0, O_DISP_LBL, OBJPROP_TEXT, txt);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Build the fixed panel (right-top corner, like SP2L)               |
//+------------------------------------------------------------------+
void CreatePanel()
  {
//--- panel background
   EnsureObject(O_BG, OBJ_RECTANGLE_LABEL);
   ObjectSetInteger(0, O_BG, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, O_BG, OBJPROP_XDISTANCE, PANEL_X);
   ObjectSetInteger(0, O_BG, OBJPROP_YDISTANCE, PANEL_Y);
   ObjectSetInteger(0, O_BG, OBJPROP_XSIZE, PN_W);
   ObjectSetInteger(0, O_BG, OBJPROP_YSIZE, PN_H);
   ObjectSetInteger(0, O_BG, OBJPROP_BGCOLOR, C'24,28,36');
   ObjectSetInteger(0, O_BG, OBJPROP_BORDER_COLOR, clrGold);
   ObjectSetInteger(0, O_BG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, O_BG, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, O_BG, OBJPROP_BACK, false);
   ObjectSetInteger(0, O_BG, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, O_BG, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, O_BG, OBJPROP_ZORDER, 100);
   ObjectSetInteger(0, O_BG, OBJPROP_TIMEFRAMES, ALL_TF);

//--- display box (above the Spike button)
   EnsureObject(O_DISP_BG, OBJ_RECTANGLE_LABEL);
   ObjectSetInteger(0, O_DISP_BG, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, O_DISP_BG, OBJPROP_XDISTANCE, PANEL_X + 10);
   ObjectSetInteger(0, O_DISP_BG, OBJPROP_YDISTANCE, PANEL_Y + 6);
   ObjectSetInteger(0, O_DISP_BG, OBJPROP_XSIZE, PN_W - 20);
   ObjectSetInteger(0, O_DISP_BG, OBJPROP_YSIZE, 40);
   ObjectSetInteger(0, O_DISP_BG, OBJPROP_BGCOLOR, C'10,14,24');
   ObjectSetInteger(0, O_DISP_BG, OBJPROP_BORDER_COLOR, C'80,90,110');
   ObjectSetInteger(0, O_DISP_BG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, O_DISP_BG, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, O_DISP_BG, OBJPROP_BACK, false);
   ObjectSetInteger(0, O_DISP_BG, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, O_DISP_BG, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, O_DISP_BG, OBJPROP_ZORDER, 101);
   ObjectSetInteger(0, O_DISP_BG, OBJPROP_TIMEFRAMES, ALL_TF);

//--- display label (result text)
   EnsureObject(O_DISP_LBL, OBJ_LABEL);
   ObjectSetInteger(0, O_DISP_LBL, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, O_DISP_LBL, OBJPROP_XDISTANCE, PANEL_X + 16);
   ObjectSetInteger(0, O_DISP_LBL, OBJPROP_YDISTANCE, PANEL_Y + 16);
   ObjectSetString(0, O_DISP_LBL, OBJPROP_TEXT, "");
   ObjectSetInteger(0, O_DISP_LBL, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, O_DISP_LBL, OBJPROP_FONTSIZE, 13);
   ObjectSetString(0, O_DISP_LBL, OBJPROP_FONT, "Arial Black");
      // (bold look via Arial Black font)
   ObjectSetInteger(0, O_DISP_LBL, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, O_DISP_LBL, OBJPROP_ZORDER, 102);
   ObjectSetInteger(0, O_DISP_LBL, OBJPROP_TIMEFRAMES, ALL_TF);

//--- buttons (one column): Spike / Chanel / Range / Check / Clear
   CreateButton(O_BTN_S, PANEL_X + 10, PANEL_Y + 52,  184, 24, "Spike",  C'25,155,70', clrWhite);
   CreateButton(O_BTN_C, PANEL_X + 10, PANEL_Y + 80,  184, 24, "Chanel", C'240,200,30', clrBlack);
   CreateButton(O_BTN_R, PANEL_X + 10, PANEL_Y + 108, 184, 24, "Range",  C'25,65,150', clrWhite);
   CreateButton(O_BTN_CHK,PANEL_X + 10, PANEL_Y + 136, 184, 24, "Check", C'70,95,150', clrWhite);
   CreateButton(O_BTN_X, PANEL_X + 10, PANEL_Y + 164, 184, 24, "Clear",  C'150,50,50', clrWhite);

   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Create one bold button                                            |
//+------------------------------------------------------------------+
void CreateButton(string name, int x, int y, int w, int h, string text, color bg, color tc)
  {
   EnsureObject(name, OBJ_BUTTON);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, tc);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'90,100,120');
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 11);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Black");
      // (bold look via Arial Black font)
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 103);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, ALL_TF);
  }

//+------------------------------------------------------------------+
//| Is the pixel point inside the panel?                              |
//+------------------------------------------------------------------+
bool IsPointOnPanel(int x, int y)
  {
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   if(cw <= 0)
      cw = 800;
   int left = cw - PANEL_X - PN_W;
   if(left < 0)
      left = 0;
   if(x >= left && x <= left + PN_W &&
      y >= PANEL_Y && y <= PANEL_Y + PN_H)
      return(true);
   return(false);
  }

//+------------------------------------------------------------------+
//| Indicator iteration function                                     |
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
   for(int i = 0; i < rates_total; i++)
      Dummy[i] = EMPTY_VALUE;
   return(rates_total);
  }
//+------------------------------------------------------------------+
//|  End of Cycle Market                                             |
//+------------------------------------------------------------------+
