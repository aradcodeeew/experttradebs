//+------------------------------------------------------------------+
//|                                      MarketCycle_Indicator_v1.0  |
//|                          Market Cycle Analysis Panel v1.0        |
//+------------------------------------------------------------------+
#property copyright "MetaTrader Assistant"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- Input options
input bool EnablePanel   = true;    // Enable Panel
input int  PanelWidth    = 180;     // Panel Width
input int  PanelHeight   = 120;     // Panel Height
input int  ButtonHeight  = 24;      // Button Height
input int  PanelPosX     = 5;       // Panel X position (px from left edge, near price scale)
input int  PanelPosY     = 20;      // Panel Y position (px from top edge)

//--- Spike condition inputs
input int    SpikeFirstPct    = 10;     // SPIKE: first N% of candles to check bodies
input double SpikeBodyMinPct  = 80.0;   // SPIKE: min body % (|close-open| / range * 100)
input double SpikeRangeMinATR = 3.0;    // SPIKE: total range must be >= N x avg candle range

//--- Trend condition inputs
input int TrendSegments = 4;            // TREND: split range into N segments

//--- Range condition inputs
input int    RangeExtremeCount = 10;    // RANGE: N highest / N lowest candles
input double RangeClusterPct   = 24.0;  // RANGE: cluster spread limit (% of total range)

//--- Result box colors
input color ResOKColor   = clrLime;
input color ResFailColor = C'230,90,90';

//--- Object name prefix
#define PREFIX "MC_"

//--- Mode identifiers
#define MODE_NONE  0
#define MODE_SPIKE 1
#define MODE_TREND 2
#define MODE_RANGE 3

//--- Colors
#define CLR_SPIKE_ON  C'0,180,0'
#define CLR_SPIKE_OFF C'0,90,0'
#define CLR_TREND_ON  C'255,230,0'
#define CLR_TREND_OFF C'160,120,0'
#define CLR_RANGE_ON  C'0,140,230'
#define CLR_RANGE_OFF C'0,60,130'
#define CLR_CHECK     C'150,0,150'
#define CLR_CLEAR     C'200,0,0'
#define CLR_HIDE      C'120,120,120'
#define CLR_PANEL     C'30,30,40'
#define CLR_BORDER    C'90,90,110'
#define CLR_TEXT      C'255,255,255'
#define CLR_RES_BG    C'35,35,50'

//--- Object names
#define OBJ_PANEL    PREFIX+"Panel"
#define OBJ_TITLE    PREFIX+"Title"
#define OBJ_GRAB     PREFIX+"Grab"
#define OBJ_BT_SPIKE PREFIX+"BtSpike"
#define OBJ_BT_TREND PREFIX+"BtTrend"
#define OBJ_BT_RANGE PREFIX+"BtRange"
#define OBJ_BT_CHECK PREFIX+"BtCheck"
#define OBJ_BT_CLEAR PREFIX+"BtClear"
#define OBJ_BT_HIDE  PREFIX+"BtHide"
#define OBJ_BT_SHOW  PREFIX+"BtShow"
#define OBJ_RES_BG   PREFIX+"ResBox"
#define OBJ_RES_TXT  PREFIX+"ResTxt"
#define OBJ_VLINE1   PREFIX+"VLine1"
#define OBJ_VLINE2   PREFIX+"VLine2"

//--- Global state
int    g_mode         = MODE_NONE; // Selected mode
int    g_click_state  = 0;         // 0=none,1=first(green),2=both set
bool   g_panel_hidden = false;     // Hide panel status

//--- Drag (panel)
int    g_drag_x = 0;
int    g_drag_y = 0;
bool   g_dragging = false;
int    g_panel_x = 0;
int    g_panel_y = 0;

//--- Drag (collapsed SHOW button)
bool   g_show_dragging = false; // SHOW button is being dragged
bool   g_show_moved    = false; // SHOW button was just dragged (suppress next click)

//+------------------------------------------------------------------+
//| Custom indicator initialization function                          |
//+------------------------------------------------------------------+
int OnInit()
{
   if(EnablePanel) {
      //-- Remove any leftover objects from a previous run (fresh state, no lines)
      ObjectsDeleteAll(0, PREFIX);

      //-- Interface position: from inputs PanelPosX/PanelPosY (left price scale by default)
      g_panel_x = PanelPosX;
      g_panel_y = PanelPosY;

      CreatePanel();
      UpdateModeButtons();
   } else {
      HidePanel(true);
   }

   Print("MarketCycle_Indicator_v1.0 loaded. Panel position -> X=" + IntegerToString(g_panel_x) + " Y=" + IntegerToString(g_panel_y));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PREFIX);
}

//+------------------------------------------------------------------+
//| OnCalculate (required; panel only, no buffers)                    |
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
//| Create all panel objects                                          |
//+------------------------------------------------------------------+
void CreatePanel()
{
   //-- Panel background
   ObjectCreate(0, OBJ_PANEL, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, OBJ_PANEL, OBJPROP_XDISTANCE, g_panel_x);
   ObjectSetInteger(0, OBJ_PANEL, OBJPROP_YDISTANCE, g_panel_y);
   ObjectSetInteger(0, OBJ_PANEL, OBJPROP_XSIZE,     PanelWidth);
   ObjectSetInteger(0, OBJ_PANEL, OBJPROP_YSIZE,     PanelHeight);
   ObjectSetInteger(0, OBJ_PANEL, OBJPROP_BGCOLOR,   CLR_PANEL);
   ObjectSetInteger(0, OBJ_PANEL, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, OBJ_PANEL, OBJPROP_BORDER_COLOR, CLR_BORDER);
   ObjectSetInteger(0, OBJ_PANEL, OBJPROP_WIDTH,     1);
   ObjectSetInteger(0, OBJ_PANEL, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, OBJ_PANEL, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, OBJ_PANEL, OBJPROP_HIDDEN,    true);
   ObjectSetInteger(0, OBJ_PANEL, OBJPROP_ZORDER,    0);

   //-- Title / grab bar
   ObjectCreate(0, OBJ_TITLE, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, OBJ_TITLE, OBJPROP_XDISTANCE, g_panel_x + 6);
   ObjectSetInteger(0, OBJ_TITLE, OBJPROP_YDISTANCE, g_panel_y + 3);
   ObjectSetInteger(0, OBJ_TITLE, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetString(0, OBJ_TITLE, OBJPROP_TEXT,       "Market Cycle");
   ObjectSetInteger(0, OBJ_TITLE, OBJPROP_COLOR,     CLR_TEXT);
   ObjectSetInteger(0, OBJ_TITLE, OBJPROP_FONTSIZE,  8);
   ObjectSetString(0, OBJ_TITLE, OBJPROP_FONT,       "Arial");
   ObjectSetInteger(0, OBJ_TITLE, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, OBJ_TITLE, OBJPROP_HIDDEN,    true);
   ObjectSetInteger(0, OBJ_TITLE, OBJPROP_ZORDER,    10);

   //-- Grab bar (invisible rectangle for dragging)
   ObjectCreate(0, OBJ_GRAB, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, OBJ_GRAB, OBJPROP_XDISTANCE, g_panel_x);
   ObjectSetInteger(0, OBJ_GRAB, OBJPROP_YDISTANCE, g_panel_y);
   ObjectSetInteger(0, OBJ_GRAB, OBJPROP_XSIZE,     PanelWidth);
   ObjectSetInteger(0, OBJ_GRAB, OBJPROP_YSIZE,     24);
   ObjectSetInteger(0, OBJ_GRAB, OBJPROP_BGCOLOR,   CLR_PANEL);
   ObjectSetInteger(0, OBJ_GRAB, OBJPROP_BORDER_COLOR, CLR_PANEL);
   ObjectSetInteger(0, OBJ_GRAB, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, OBJ_GRAB, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, OBJ_GRAB, OBJPROP_HIDDEN,    true);
   ObjectSetInteger(0, OBJ_GRAB, OBJPROP_ZORDER,    1);

   //-- Row 1: SPIKE / TREND / RANGE (y = 32)
   CreateButton(OBJ_BT_SPIKE, "SPIKE", 32, CLR_SPIKE_OFF, false);
   CreateButton(OBJ_BT_TREND, "TREND", 32, CLR_TREND_OFF, false);
   CreateButton(OBJ_BT_RANGE, "RANGE", 32, CLR_RANGE_OFF, false);

   //-- Row 2: CHECK / CLEAR / HIDE (y = 32 + ButtonHeight + 4)
   CreateButton(OBJ_BT_CHECK, "CHECK", 32 + ButtonHeight + 4, CLR_CHECK, false);
   CreateButton(OBJ_BT_CLEAR, "CLEAR", 32 + ButtonHeight + 4, CLR_CLEAR, false);
   CreateButton(OBJ_BT_HIDE,  "HIDE",  32 + ButtonHeight + 4, CLR_HIDE,  false);

   //-- Row 3: result display box (SPIKE / TREND / RANGE / DON'T SEE)
   int r3 = 32 + 2 * (ButtonHeight + 4);
   ObjectCreate(0, OBJ_RES_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, OBJ_RES_BG, OBJPROP_XDISTANCE,   g_panel_x + 4);
   ObjectSetInteger(0, OBJ_RES_BG, OBJPROP_YDISTANCE,   g_panel_y + r3);
   ObjectSetInteger(0, OBJ_RES_BG, OBJPROP_XSIZE,       PanelWidth - 8);
   ObjectSetInteger(0, OBJ_RES_BG, OBJPROP_YSIZE,       ButtonHeight);
   ObjectSetInteger(0, OBJ_RES_BG, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0, OBJ_RES_BG, OBJPROP_BGCOLOR,     CLR_RES_BG);
   ObjectSetInteger(0, OBJ_RES_BG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, OBJ_RES_BG, OBJPROP_BORDER_COLOR, CLR_BORDER);
   ObjectSetInteger(0, OBJ_RES_BG, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, OBJ_RES_BG, OBJPROP_HIDDEN,      true);
   ObjectSetInteger(0, OBJ_RES_BG, OBJPROP_ZORDER,      90);

   ObjectCreate(0, OBJ_RES_TXT, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, OBJ_RES_TXT, OBJPROP_XDISTANCE, g_panel_x + 4 + (PanelWidth - 8) / 2);
   ObjectSetInteger(0, OBJ_RES_TXT, OBJPROP_YDISTANCE, g_panel_y + r3 + ButtonHeight / 2);
   ObjectSetInteger(0, OBJ_RES_TXT, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, OBJ_RES_TXT, OBJPROP_ANCHOR,    ANCHOR_CENTER);
   ObjectSetString(0,  OBJ_RES_TXT, OBJPROP_TEXT,       "");
   ObjectSetInteger(0, OBJ_RES_TXT, OBJPROP_COLOR,      CLR_TEXT);
   ObjectSetInteger(0, OBJ_RES_TXT, OBJPROP_FONTSIZE,   10);
   ObjectSetString(0,  OBJ_RES_TXT, OBJPROP_FONT,       "Arial");
   ObjectSetInteger(0, OBJ_RES_TXT, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, OBJ_RES_TXT, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, OBJ_RES_TXT, OBJPROP_ZORDER,     95);

   //-- Collapsed "SHOW" button (size of one button, appears only after HIDE)
   int btnW = (PanelWidth - 12) / 3;
   ObjectCreate(0, OBJ_BT_SHOW, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, OBJ_BT_SHOW, OBJPROP_XDISTANCE, g_panel_x);
   ObjectSetInteger(0, OBJ_BT_SHOW, OBJPROP_YDISTANCE, g_panel_y);
   ObjectSetInteger(0, OBJ_BT_SHOW, OBJPROP_XSIZE,     btnW);
   ObjectSetInteger(0, OBJ_BT_SHOW, OBJPROP_YSIZE,     ButtonHeight);
   ObjectSetInteger(0, OBJ_BT_SHOW, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, OBJ_BT_SHOW, OBJPROP_BGCOLOR,   CLR_HIDE);
   ObjectSetInteger(0, OBJ_BT_SHOW, OBJPROP_BORDER_COLOR, CLR_BORDER);
   ObjectSetString(0,  OBJ_BT_SHOW, OBJPROP_TEXT,       "SHOW");
   ObjectSetInteger(0, OBJ_BT_SHOW, OBJPROP_COLOR,      CLR_TEXT);
   ObjectSetInteger(0, OBJ_BT_SHOW, OBJPROP_FONTSIZE,   8);
   ObjectSetString(0,  OBJ_BT_SHOW, OBJPROP_FONT,       "Arial");
   ObjectSetInteger(0, OBJ_BT_SHOW, OBJPROP_STATE,      false);
   ObjectSetInteger(0, OBJ_BT_SHOW, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, OBJ_BT_SHOW, OBJPROP_HIDDEN,     false);
   ObjectSetInteger(0, OBJ_BT_SHOW, OBJPROP_ZORDER,     100);
   ObjectSetInteger(0, OBJ_BT_SHOW, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS); // hidden until HIDE

   //-- Green/Red vertical lines are created on demand inside OnChartEvent.
   //-- No line is shown when the indicator is first attached.
}

//+------------------------------------------------------------------+
//| Create a button with text and color at a sub-position             |
//+------------------------------------------------------------------+
void CreateButton(string name, string text, int yRel, color bg, bool state)
{
   int btnW = (PanelWidth - 12) / 3;
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, g_panel_x + 4);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, g_panel_y + yRel);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,     btnW);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,     ButtonHeight);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,   bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, CLR_BORDER);
   ObjectSetString(0,  name, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      CLR_TEXT);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   8);
   ObjectSetString(0,  name, OBJPROP_FONT,       "Arial");
   ObjectSetInteger(0, name, OBJPROP_STATE,      state);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,     100);
}

//+------------------------------------------------------------------+
//| Create a vertical line object (not selectable so it never moves) |
//+------------------------------------------------------------------+
void CreateVLine(string name, color clr)
{
   ObjectCreate(0, name, OBJ_VLINE, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_COLOR,   clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE,   STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,   2);
   ObjectSetInteger(0, name, OBJPROP_BACK,    false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,  true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,  50);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
}

//+------------------------------------------------------------------+
//| Refresh button positions after a move                             |
//+------------------------------------------------------------------+
void UpdatePanelPosition(int x, int y)
{
   int btnW = (PanelWidth - 12) / 3;
   int r3 = 32 + 2 * (ButtonHeight + 4);
   g_panel_x = x;
   g_panel_y = y;

   ObjectSetInteger(0, OBJ_PANEL, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, OBJ_PANEL, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, OBJ_GRAB,  OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, OBJ_GRAB,  OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, OBJ_TITLE, OBJPROP_XDISTANCE, x + 6);
   ObjectSetInteger(0, OBJ_TITLE, OBJPROP_YDISTANCE, y + 3);

   ObjectSetInteger(0, OBJ_BT_SPIKE, OBJPROP_XDISTANCE, x + 4);
   ObjectSetInteger(0, OBJ_BT_SPIKE, OBJPROP_YDISTANCE, y + 32);
   ObjectSetInteger(0, OBJ_BT_TREND, OBJPROP_XDISTANCE, x + 4 + btnW);
   ObjectSetInteger(0, OBJ_BT_TREND, OBJPROP_YDISTANCE, y + 32);
   ObjectSetInteger(0, OBJ_BT_RANGE, OBJPROP_XDISTANCE, x + 4 + 2 * btnW);
   ObjectSetInteger(0, OBJ_BT_RANGE, OBJPROP_YDISTANCE, y + 32);

   int row2 = y + 32 + ButtonHeight + 4;
   ObjectSetInteger(0, OBJ_BT_CHECK, OBJPROP_XDISTANCE, x + 4);
   ObjectSetInteger(0, OBJ_BT_CHECK, OBJPROP_YDISTANCE, row2);
   ObjectSetInteger(0, OBJ_BT_CLEAR, OBJPROP_XDISTANCE, x + 4 + btnW);
   ObjectSetInteger(0, OBJ_BT_CLEAR, OBJPROP_YDISTANCE, row2);
   ObjectSetInteger(0, OBJ_BT_HIDE,  OBJPROP_XDISTANCE, x + 4 + 2 * btnW);
   ObjectSetInteger(0, OBJ_BT_HIDE,  OBJPROP_YDISTANCE, row2);

   ObjectSetInteger(0, OBJ_RES_BG, OBJPROP_XDISTANCE, x + 4);
   ObjectSetInteger(0, OBJ_RES_BG, OBJPROP_YDISTANCE, y + r3);
   ObjectSetInteger(0, OBJ_RES_TXT, OBJPROP_XDISTANCE, x + 4 + (PanelWidth - 8) / 2);
   ObjectSetInteger(0, OBJ_RES_TXT, OBJPROP_YDISTANCE, y + r3 + ButtonHeight / 2);

   ObjectSetInteger(0, OBJ_BT_SHOW, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, OBJ_BT_SHOW, OBJPROP_YDISTANCE, y);
}

//+------------------------------------------------------------------+
//| Update mode button colors (only one ON = brighter)                |
//+------------------------------------------------------------------+
void UpdateModeButtons()
{
   ObjectSetInteger(0, OBJ_BT_SPIKE, OBJPROP_BGCOLOR, (g_mode==MODE_SPIKE) ? CLR_SPIKE_ON : CLR_SPIKE_OFF);
   ObjectSetInteger(0, OBJ_BT_TREND, OBJPROP_BGCOLOR, (g_mode==MODE_TREND) ? CLR_TREND_ON : CLR_TREND_OFF);
   ObjectSetInteger(0, OBJ_BT_RANGE, OBJPROP_BGCOLOR, (g_mode==MODE_RANGE) ? CLR_RANGE_ON : CLR_RANGE_OFF);
   ObjectSetInteger(0, OBJ_BT_SPIKE, OBJPROP_STATE, (g_mode==MODE_SPIKE) ? true : false);
   ObjectSetInteger(0, OBJ_BT_TREND, OBJPROP_STATE, (g_mode==MODE_TREND) ? true : false);
   ObjectSetInteger(0, OBJ_BT_RANGE, OBJPROP_STATE, (g_mode==MODE_RANGE) ? true : false);
}

//+------------------------------------------------------------------+
//| Show the analysis result in the result box                        |
//+------------------------------------------------------------------+
void SetResultText(string txt)
{
   bool ok = (txt != "DON'T SEE");
   ObjectSetString(0, OBJ_RES_TXT, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, OBJ_RES_TXT, OBJPROP_COLOR, ok ? ResOKColor : ResFailColor);
   ObjectSetInteger(0, OBJ_RES_BG, OBJPROP_BGCOLOR, ok ? C'20,60,25' : C'60,20,20');
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Set panel visible or hidden                                       |
//+------------------------------------------------------------------+
void SetPanelVisible(bool visible)
{
   long tf = visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
   ObjectSetInteger(0, OBJ_PANEL, OBJPROP_TIMEFRAMES, tf);
   ObjectSetInteger(0, OBJ_GRAB,  OBJPROP_TIMEFRAMES, tf);
   ObjectSetInteger(0, OBJ_TITLE, OBJPROP_TIMEFRAMES, tf);
   ObjectSetInteger(0, OBJ_BT_SPIKE, OBJPROP_TIMEFRAMES, tf);
   ObjectSetInteger(0, OBJ_BT_TREND, OBJPROP_TIMEFRAMES, tf);
   ObjectSetInteger(0, OBJ_BT_RANGE, OBJPROP_TIMEFRAMES, tf);
   ObjectSetInteger(0, OBJ_BT_CHECK, OBJPROP_TIMEFRAMES, tf);
   ObjectSetInteger(0, OBJ_BT_CLEAR, OBJPROP_TIMEFRAMES, tf);
   ObjectSetInteger(0, OBJ_BT_HIDE,  OBJPROP_TIMEFRAMES, tf);
   ObjectSetInteger(0, OBJ_RES_BG, OBJPROP_TIMEFRAMES, tf);
   ObjectSetInteger(0, OBJ_RES_TXT, OBJPROP_TIMEFRAMES, tf);
}

//+------------------------------------------------------------------+
//| Hide the entire panel (only a small SHOW button remains)          |
//+------------------------------------------------------------------+
void HidePanel(bool hide)
{
   g_panel_hidden = hide;
   if(!hide) {
      //-- Panel opens exactly where the SHOW button was dragged
      UpdatePanelPosition(g_panel_x, g_panel_y);
   }
   SetPanelVisible(!hide);
   ObjectSetInteger(0, OBJ_BT_SHOW, OBJPROP_TIMEFRAMES, hide ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Clear the green/red range selection                               |
//+------------------------------------------------------------------+
void ClearRange()
{
   ObjectDelete(0, OBJ_VLINE1);
   ObjectDelete(0, OBJ_VLINE2);
   g_click_state = 0;
   SetResultText("");
   ChartRedraw();
   Print("Range cleared. Mode still active. Next chart click = GREEN (1st), then RED (2nd).");
}

//+------------------------------------------------------------------+
//| SPIKE: big total range + a fat-bodied candle among the first     |
//| ~SpikeFirstPct% candles (body >= SpikeBodyMinPct% of high-low).  |
//| iA = older (left, larger index) , iB = newer (right, smaller)    |
//+------------------------------------------------------------------+
bool CheckSpike(int iA, int iB)
{
   int n = iA - iB + 1;
   if(n < 3) return false;

   double maxH = -DBL_MAX, minL = DBL_MAX, sumHL = 0.0;
   for(int i = iA; i >= iB; i--) {
      double h = iHigh(_Symbol, _Period, i);
      double l = iLow(_Symbol, _Period, i);
      if(h > maxH) maxH = h;
      if(l < minL) minL = l;
      sumHL += (h - l);
   }
   double totalRange = maxH - minL;
   double avgHL = sumHL / n;
   if(avgHL <= 0 || totalRange < SpikeRangeMinATR * avgHL)
      return false;

   int m = (int)MathRound(n * SpikeFirstPct / 100.0);
   if(m < 1) m = 1;
   if(m > n) m = n;
   for(int k = 0; k < m; k++) {
      int i = iA - k; // walk from left toward right
      double o = iOpen(_Symbol, _Period, i);
      double c = iClose(_Symbol, _Period, i);
      double h = iHigh(_Symbol, _Period, i);
      double l = iLow(_Symbol, _Period, i);
      double body = MathAbs(c - o);
      double rng = h - l;
      if(rng > 0 && body / rng * 100.0 >= SpikeBodyMinPct)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| TREND: split range into segments; UPTREND = higher highs AND     |
//| higher lows across all segments, DOWNTREND = the opposite.       |
//+------------------------------------------------------------------+
bool CheckTrend(int iA, int iB)
{
   int n = iA - iB + 1;
   int seg = TrendSegments;
   if(seg < 2) seg = 2;
   if(n < seg * 2) return false;

   int idx[];
   ArrayResize(idx, seg + 1);
   idx[0] = iA;
   for(int s = 1; s < seg; s++) {
      idx[s] = iA - (int)MathRound((double)s * n / seg);
      if(idx[s] >= idx[s - 1]) idx[s] = idx[s - 1] - 1;
   }
   idx[seg] = iB;
   if(idx[seg] >= idx[seg - 1]) idx[seg] = idx[seg - 1] - 1;

   double h[], l[];
   ArrayResize(h, seg);
   ArrayResize(l, seg);
   for(int s = 0; s < seg; s++) {
      h[s] = -DBL_MAX;
      l[s] = DBL_MAX;
      for(int i = idx[s]; i >= idx[s + 1]; i--) {
         double hh = iHigh(_Symbol, _Period, i);
         double ll = iLow(_Symbol, _Period, i);
         if(hh > h[s]) h[s] = hh;
         if(ll < l[s]) l[s] = ll;
      }
   }

   bool up = true, down = true;
   for(int s = 1; s < seg; s++) {
      if(h[s] <= h[s - 1] || l[s] <= l[s - 1]) up = false;
      if(h[s] >= h[s - 1] || l[s] >= l[s - 1]) down = false;
   }
   return(up || down);
}

//+------------------------------------------------------------------+
//| RANGE: the N highest highs and N lowest lows must each cluster   |
//| within RangeClusterPct% of the total high-low range.             |
//+------------------------------------------------------------------+
bool CheckRange(int iA, int iB)
{
   int n = iA - iB + 1;
   if(n < 4) return false;
   int cnt = RangeExtremeCount;
   if(cnt < 1) cnt = 1;
   if(cnt > n / 2) cnt = n / 2;

   double top[], bot[];
   ArrayResize(top, cnt);
   ArrayResize(bot, cnt);
   int fTop = 0, fBot = 0;
   double maxH = -DBL_MAX, minL = DBL_MAX;

   for(int i = iA; i >= iB; i--) {
      double h = iHigh(_Symbol, _Period, i);
      double l = iLow(_Symbol, _Period, i);
      if(h > maxH) maxH = h;
      if(l < minL) minL = l;

      if(fTop < cnt) {
         top[fTop++] = h;
      } else {
         int p = 0;
         for(int k = 1; k < cnt; k++) if(top[k] < top[p]) p = k;
         if(h > top[p]) top[p] = h;
      }
      if(fBot < cnt) {
         bot[fBot++] = l;
      } else {
         int p = 0;
         for(int k = 1; k < cnt; k++) if(bot[k] > bot[p]) p = k;
         if(l < bot[p]) bot[p] = l;
      }
   }

   double topMin = top[0], topMax = top[0];
   double botMin = bot[0], botMax = bot[0];
   for(int k = 1; k < cnt; k++) {
      if(top[k] < topMin) topMin = top[k];
      if(top[k] > topMax) topMax = top[k];
      if(bot[k] < botMin) botMin = bot[k];
      if(bot[k] > botMax) botMax = bot[k];
   }

   double totalRange = maxH - minL;
   if(totalRange <= 0) return false;
   double limit = RangeClusterPct / 100.0 * totalRange;
   double topSpread = topMax - topMin;
   double botSpread = botMax - botMin;
   return(topSpread <= limit && botSpread <= limit);
}

//+------------------------------------------------------------------+
//| Check button - runs the condition for the selected mode           |
//+------------------------------------------------------------------+
void DoCheck()
{
   //-- Requirement 1: a mode must be selected
   if(g_mode == MODE_NONE) {
      Alert("CHECK: No mode selected! Select SPIKE / TREND / RANGE first.");
      Print("CHECK: No mode selected! (Mode = NONE)");
      return;
   }

   //-- Requirement 2: a green/red range must be set
   if(g_click_state != 2) {
      Alert("CHECK: Range not set! Click chart: 1st=Green(start), 2nd=Red(end).");
      Print("CHECK: Range not set! (click_state=" + IntegerToString(g_click_state) + ")");
      return;
   }

   datetime t1 = (datetime)ObjectGetInteger(0, OBJ_VLINE1, OBJPROP_TIME);
   datetime t2 = (datetime)ObjectGetInteger(0, OBJ_VLINE2, OBJPROP_TIME);
   if(t1 >= t2) {
      Alert("CHECK: Green line must be before Red line.");
      return;
   }

   //-- Convert line times to bar indices (iA=older/left, iB=newer/right)
   int iA = iBarShift(_Symbol, _Period, t1, false);
   int iB = iBarShift(_Symbol, _Period, t2, false);
   if(iA < 0 || iB < 0 || iA <= iB) {
      Alert("CHECK: range outside available history.");
      return;
   }

   string modeName = (g_mode==MODE_SPIKE) ? "SPIKE" : (g_mode==MODE_TREND) ? "TREND" : "RANGE";
   string res = "DON'T SEE";

   if(g_mode == MODE_SPIKE && CheckSpike(iA, iB))
      res = "SPIKE";
   else if(g_mode == MODE_TREND && CheckTrend(iA, iB))
      res = "TREND";
   else if(g_mode == MODE_RANGE && CheckRange(iA, iB))
      res = "RANGE";

   SetResultText(res);
   Print("CHECK [" + modeName + "] -> " + res +
         "  (range bars=" + IntegerToString(iA - iB + 1) + ")");
}

//+------------------------------------------------------------------+
//| Convert chart pixel X to a bar datetime (accurate)                |
//+------------------------------------------------------------------+
datetime ChartXToTime(int x, int y)
{
   int     subwin = 0;
   datetime t      = 0;
   double  price   = 0;
   if(ChartXYToTimePrice(0, x, y, subwin, t, price))
      return(t);
   return(0);
}

//+------------------------------------------------------------------+
//| Handle chart events                                               |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   //-- Chart resize / property change: keep panel inside chart
   if(id == CHARTEVENT_CHART_CHANGE) {
      int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      if(g_panel_x + PanelWidth  > cw) g_panel_x = cw - PanelWidth;
      if(g_panel_y + PanelHeight > ch) g_panel_y = ch - PanelHeight;
      UpdatePanelPosition(g_panel_x, g_panel_y);
      ChartRedraw();
      return;
   }

   //-- BUTTON clicks
   if(id == CHARTEVENT_OBJECT_CLICK) {
      if(sparam == OBJ_BT_SPIKE) {
         g_mode = (g_mode==MODE_SPIKE) ? MODE_NONE : MODE_SPIKE;
         UpdateModeButtons();
         Print("Mode SPIKE " + ((g_mode==MODE_SPIKE) ? "ON" : "OFF") + " (single-select)");
      } else if(sparam == OBJ_BT_TREND) {
         g_mode = (g_mode==MODE_TREND) ? MODE_NONE : MODE_TREND;
         UpdateModeButtons();
         Print("Mode TREND " + ((g_mode==MODE_TREND) ? "ON" : "OFF") + " (single-select)");
      } else if(sparam == OBJ_BT_RANGE) {
         g_mode = (g_mode==MODE_RANGE) ? MODE_NONE : MODE_RANGE;
         UpdateModeButtons();
         Print("Mode RANGE " + ((g_mode==MODE_RANGE) ? "ON" : "OFF") + " (single-select)");
      } else if(sparam == OBJ_BT_CHECK) {
         DoCheck();
      } else if(sparam == OBJ_BT_CLEAR) {
         ClearRange();
      } else if(sparam == OBJ_BT_HIDE) {
         HidePanel(true);
         Print("Panel collapsed to SHOW button.");
      } else if(sparam == OBJ_BT_SHOW) {
         //-- If the SHOW button was just dragged, this click only confirms the new spot.
         //-- A second click then opens the panel there.
         if(g_show_moved) {
            g_show_moved = false;
            Print("SHOW moved to X=" + IntegerToString(g_panel_x) + " Y=" + IntegerToString(g_panel_y) + ". Click again to open.");
         } else {
            HidePanel(false);
            Print("Panel shown.");
         }
      }

      ChartRedraw();
      return;
   }

   //-- MOUSE move: handle dragging of the panel / collapsed SHOW button
   if(id == CHARTEVENT_MOUSE_MOVE) {
      int x = (int)lparam;
      int y = (int)dparam;
      int btns = (int)sparam;
      int sbw = (PanelWidth - 12) / 3; // SHOW button width

      //-- Left button pressed on SHOW button (panel collapsed): begin drag
      if((btns & 1) == 1 && g_panel_hidden && !g_show_dragging && !g_dragging) {
         if(x >= g_panel_x && x <= g_panel_x + sbw &&
            y >= g_panel_y && y <= g_panel_y + ButtonHeight) {
            g_show_dragging = true;
            g_show_moved    = false;
            g_drag_x = x;
            g_drag_y = y;
            ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
         }
      }

      //-- Left button pressed on grab bar (panel visible): begin drag
      if((btns & 1) == 1 && !g_dragging && !g_panel_hidden) {
         if(x >= g_panel_x && x <= g_panel_x + PanelWidth &&
            y >= g_panel_y && y <= g_panel_y + 24) {
            g_dragging = true;
            g_drag_x = x;
            g_drag_y = y;
            ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
         }
      }

      if(g_dragging) {
         int dx = x - g_drag_x;
         int dy = y - g_drag_y;
         int nx = g_panel_x + dx;
         int ny = g_panel_y + dy;

         int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
         int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
         if(nx < 0) nx = 0;
         if(ny < 0) ny = 0;
         if(nx + PanelWidth  > cw) nx = cw - PanelWidth;
         if(ny + PanelHeight > ch) ny = ch - PanelHeight;

         UpdatePanelPosition(nx, ny);
         g_drag_x = x;
         g_drag_y = y;
      }

      //-- Drag the collapsed SHOW button: move it and remember the new panel spot
      if(g_show_dragging) {
         int dx = x - g_drag_x;
         int dy = y - g_drag_y;
         int nx = g_panel_x + dx;
         int ny = g_panel_y + dy;

         int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
         int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
         if(nx < 0) nx = 0;
         if(ny < 0) ny = 0;
         if(nx + sbw > cw) nx = cw - sbw;
         if(ny + ButtonHeight > ch) ny = ch - ButtonHeight;

         if(nx != g_panel_x || ny != g_panel_y) g_show_moved = true;
         g_panel_x = nx;
         g_panel_y = ny;
         ObjectSetInteger(0, OBJ_BT_SHOW, OBJPROP_XDISTANCE, g_panel_x);
         ObjectSetInteger(0, OBJ_BT_SHOW, OBJPROP_YDISTANCE, g_panel_y);
         g_drag_x = x;
         g_drag_y = y;
         ChartRedraw();
      }

      //-- Left button released: end panel drag
      if(((btns & 1) == 0) && g_dragging) {
         g_dragging = false;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
      }

      //-- Left button released: end SHOW drag
      if(((btns & 1) == 0) && g_show_dragging) {
         g_show_dragging = false;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
         if(g_show_moved)
            Print("SHOW button moved to X=" + IntegerToString(g_panel_x) + " Y=" + IntegerToString(g_panel_y));
      }
      return;
   }

   //-- CLICK on chart background: set green/red range lines
   if(id == CHARTEVENT_CLICK) {
      int cx = (int)lparam;
      int cy = (int)dparam;

      //-- Ignore clicks on the collapsed SHOW button (so it never places a line)
      int sbx = (PanelWidth - 12) / 3;
      if(g_panel_hidden &&
         cx >= g_panel_x && cx <= g_panel_x + sbx &&
         cy >= g_panel_y && cy <= g_panel_y + ButtonHeight)
         return;

      //-- Ignore clicks on the visible panel (CHECK/CLEAR/etc. never disturb lines)
      if(!g_panel_hidden &&
         cx >= g_panel_x && cx <= g_panel_x + PanelWidth &&
         cy >= g_panel_y && cy <= g_panel_y + PanelHeight)
         return;

      //-- Lines are placed only after one of the mode buttons is selected
      if(g_mode == MODE_NONE) {
         Print("Click ignored: select SPIKE, TREND or RANGE first.");
         return;
      }

      datetime ctime = ChartXToTime(cx, cy);
      if(ctime <= 0)
         return;

      if(g_click_state == 0) {
         if(ObjectFind(0, OBJ_VLINE1) < 0)
            CreateVLine(OBJ_VLINE1, clrGreen);
         ObjectSetInteger(0, OBJ_VLINE1, OBJPROP_TIME, ctime);
         ObjectSetInteger(0, OBJ_VLINE1, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
         g_click_state = 1;
         Print("1st click: GREEN line at " + TimeToString(ctime, TIME_DATE|TIME_MINUTES));
      } else if(g_click_state == 1) {
         datetime tGreen = (datetime)ObjectGetInteger(0, OBJ_VLINE1, OBJPROP_TIME);
         if(ctime <= tGreen) {
            Print("2nd click ignored: RED line must be placed AFTER the GREEN line (click to the right).");
            return;
         }
         if(ObjectFind(0, OBJ_VLINE2) < 0)
            CreateVLine(OBJ_VLINE2, clrRed);
         ObjectSetInteger(0, OBJ_VLINE2, OBJPROP_TIME, ctime);
         ObjectSetInteger(0, OBJ_VLINE2, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
         g_click_state = 2;
         Print("2nd click: RED line at " + TimeToString(ctime, TIME_DATE|TIME_MINUTES) + " (range complete)");
      } else {
         Print("Range already set. Press CLEAR to reset and click again.");
      }

      ChartRedraw();
      return;
   }
}
//+------------------------------------------------------------------+
