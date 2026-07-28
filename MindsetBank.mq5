//+------------------------------------------------------------------+
//|                                                  MindsetBank.mq5 |
//|                                        Copyright © 2026, AbahRay |                     
//|                                       Original code by : AbahRay |
//+------------------------------------------------------------------+
#property copyright   "Copyright © 2026, AbahRay"
#property link        "https://www.tiktok.com/@abahraytrader"
#property version     "1.00"
#property description "Mindset Bank version\n"
#property description "Original Code by AbahRay"

#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

//+----------------------------------------------+
//| Indicator input parameters                   |
//+----------------------------------------------+
input uint               MA_Period  =          14;
input ENUM_MA_METHOD     MA_Method  =    MODE_SMA;    // MA method
input ENUM_APPLIED_PRICE MA_Price   = PRICE_CLOSE;    // MA Price
input double             MA_Delta   =           0;    // MA min slope for signal (in ticks)
input group "Appearance"
input uint              ATR_Period  =          60;    // ATR Period
input uint               SymbolBuy  =         233;    // Symbol Buy
input uint               SymbolSell =         234;    // Symbol Sell
input uint               SymbolSize =           1;    // Symbol Size
input uint                TrendSize =           1;    // Trend Size
input bool              TrendAsLine =       false;    // Show trend as line
input bool              ShowAtPrice =       false;    // Show signal at real price

// Anti-noise parameters
input uint ConfirmBars = 2;                   // number of consecutive bars that must confirm trend change
input uint MinBarsBetweenSignals = 3;         // minimum bars between two signals of same type
input double AdaptiveATRFactor = 0.25;        // fraction of ATR to use as adaptive threshold (0 disables if 0)
//+----------------------------------------------+

double UpSignal[],DnSignal[];       // declaration of dynamic arrays, used as indicator buffers for signals
double UpBuffer[],DnBuffer[];       // declaration of dynamic arrays, used as indicator buffers for the trend
double MA[],ATR[];                  // declaration of dynamic arrays, used as internal buffers tu receive data from iMA and iATR
int    MA_Handle=INVALID_HANDLE,ATR_Handle=INVALID_HANDLE;        // declaration of integer variables, used for handles to iMA and iATR
int    min_rates_total;             // declaration of integer variable for minimal data necessary
double min_delta;   // declare minimal delta of ma as price (initialized in OnInit)
int    buffer_idx;  // buffer index used by InitBuffer
bool   needCheckFlag; // flag to check handles/bars readiness
int    last_buy_bar = -1;   // store last buy signal bar (series index); -1 means none yet
int    last_sell_bar = -1;  // store last sell signal bar

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   ArraySetAsSeries( MA,true);         // set indexing as time series
   ArraySetAsSeries(ATR,true);         // set indexing as time series

   min_rates_total=(int)MathMax(MA_Period,ATR_Period);            // calculate min data necessary

   // compute min_delta here so it's correct if inputs or _Point changed
   min_delta = MA_Delta * _Point;

   MA_Handle=iMA(_Symbol,_Period,MA_Period,0,MA_Method,MA_Price); // get handle of iMA indicator
   if(InvalidHandle(MA_Handle,"iMA"))                             // check if valid
      return(INIT_FAILED);

   ATR_Handle=iATR(_Symbol,_Period,ATR_Period);                   // get handle of iATR indicator
   if(InvalidHandle(ATR_Handle,"iATR"))                           // check if valid
      return(INIT_FAILED);

   // initialize the plotbuffers
   ENUM_DRAW_TYPE DRAW_WHAT = TrendAsLine? DRAW_LINE:DRAW_ARROW;  // decide how to draw the trend

   // reset buffer index before registering buffers
   buffer_idx = 0;

   InitBuffer(UpBuffer,DRAW_WHAT ,"BuySell Trend up"   ,TrendSize ,clrLime,min_rates_total,158);
   InitBuffer(DnBuffer,DRAW_WHAT ,"BuySell Trend down" ,TrendSize ,clrRed ,min_rates_total,158);
   InitBuffer(UpSignal,DRAW_ARROW,"BuySell Signal up"  ,SymbolSize,clrLime,min_rates_total,SymbolBuy );
   InitBuffer(DnSignal,DRAW_ARROW,"BuySell Signal down",SymbolSize,clrRed ,min_rates_total,SymbolSell);

   // set flag to check handles/bars on first OnCalculate
   needCheckFlag = true;

   // reset last signal trackers
   last_buy_bar = -1;
   last_sell_bar = -1;

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(MA_Handle!=INVALID_HANDLE) IndicatorRelease(MA_Handle);
   if(ATR_Handle!=INVALID_HANDLE) IndicatorRelease(ATR_Handle);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int  OnCalculate( const int        rates_total,                // price[] array size 
                  const int        prev_calculated,            // number of handled bars at the previous call 
                  const int        begin,                      // index number in the price[] array meaningful data starts from 
                  const double&    price[])                    // array of values for calculation 
{
   // perform readiness checks only once after init; reset in OnInit when reattached
   if(needCheckFlag)
   {
      if(BarsCalculated( MA_Handle)<rates_total ||          //  MA not ready
         BarsCalculated(ATR_Handle)<rates_total ||          // ATR not ready
         rates_total<min_rates_total                        // not enough rates
        ) 
         return(0);                                         // reset and try again next tick
      needCheckFlag=false;                                  // never check this again for this attachment
   }

   int limit,to_copy,bar;

   // set starting bar index limit
   if(prev_calculated<=0)                                      // checking of first call
      limit=MathMax(0, rates_total-min_rates_total-2);         // starting bar index for all bars (clamped >=0)
   else 
   {
      // guard against bad prev_calculated (e.g., when history reduced)
      if(prev_calculated>rates_total) 
         limit = rates_total - min_rates_total - 2;
      else
         limit = rates_total - prev_calculated;               // starting bar index for new bars
      if(limit<0) limit=0;
   }

   // ensure we copy enough bars to support ConfirmBars checks (we access MA[bar+ConfirmBars])
   to_copy = limit + 2 + ConfirmBars;
   if(to_copy < 2) to_copy = 2; // ensure at least two bars copied for bar+1 access

   // copy new data to arrays
   if(CopyBuffer( MA_Handle,0,0,to_copy,MA )<=0)
   {
      PrintFormat("CopyBuffer MA failed, to_copy=%d", to_copy);
      return(0);
   }
   if(CopyBuffer(ATR_Handle,0,0,to_copy,ATR)<=0)
   {
      PrintFormat("CopyBuffer ATR failed, to_copy=%d", to_copy);
      return(0);
   }

   for(bar=limit; bar>=0; bar--)                      // calculation mainloop
     {
      UpBuffer[bar]=EMPTY_VALUE;                              // clear all plotbuffers
      DnBuffer[bar]=EMPTY_VALUE;
      UpSignal[bar]=EMPTY_VALUE;  
      DnSignal[bar]=EMPTY_VALUE;

      // compute adaptive threshold: max(user delta, fraction of ATR)
      double adaptive_min = min_delta;
      if(AdaptiveATRFactor>0 && ATR[bar]>0)
         adaptive_min = MathMax(adaptive_min, AdaptiveATRFactor * ATR[bar]);

      // MA slope detection using adaptive threshold
      if(MA[bar]>MA[bar+1]+adaptive_min)                 // MA increases ?
         UpBuffer[bar]=MA[bar]-ATR[bar];              // from MA subtract ATR

      if(MA[bar]<MA[bar+1]-adaptive_min)                 // MA decreases ?
         DnBuffer[bar]=MA[bar]+ATR[bar];              // to MA add ATR

      // Confirm signals only if trend persists for ConfirmBars bars
      bool up_persist = true;
      bool dn_persist = true;
      int k;
      for(k=0;k<ConfirmBars;k++)
      {
         // ensure we have enough buffered values (MA array size covers this due to to_copy)
         if(!(MA[bar+k] > MA[bar+k+1] + adaptive_min)) up_persist = false;
         if(!(MA[bar+k] < MA[bar+k+1] - adaptive_min)) dn_persist = false;
         if(!up_persist && !dn_persist) break;
      }

      // issue buy signal
      if(up_persist && (UpBuffer[bar] != EMPTY_VALUE))
      {
         if(last_buy_bar < 0 || (last_buy_bar - bar) >= (int)MinBarsBetweenSignals)
         {
            if(ShowAtPrice)
               UpSignal[bar]=price[bar];                 // show signal at price
            else
               UpSignal[bar]=UpBuffer[bar];              //  show signal at MA
            last_buy_bar = bar;
         }
      }

      // issue sell signal
      if(dn_persist && (DnBuffer[bar] != EMPTY_VALUE))
      {
         if(last_sell_bar < 0 || (last_sell_bar - bar) >= (int)MinBarsBetweenSignals)
         {
            if(ShowAtPrice)
               DnSignal[bar]=price[bar];                 // show signal at price
            else
               DnSignal[bar]=DnBuffer[bar];              //  show signal at MA
            last_sell_bar = bar;
         }
      }
     }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| utilities                                                        |
//+------------------------------------------------------------------+
bool InvalidHandle(int _handle, string _name)
{
   if(_handle==INVALID_HANDLE)                        // check handle
      PrintFormat("*ERROR* creating %s handle.",_name);    // log on error (avoid Alert popups)
   return(_handle==INVALID_HANDLE);                   // return true if invalid
}

void InitBuffer(double &_buffer[], ENUM_DRAW_TYPE _type, string _label, int _width=1, color _color=clrRed, int _begin=0, int _arrow=159)
{
   // use global buffer_idx (reset in OnInit)
   SetIndexBuffer     (buffer_idx,_buffer);                  // initialize buffer
   ArrayInitialize    (_buffer,EMPTY_VALUE);                 // initialize buffer with EMPTY_VALUE
   ArraySetAsSeries   (_buffer,true);                 // set AsSeries
   PlotIndexSetInteger(buffer_idx,PLOT_DRAW_TYPE  ,_type );  // set properties
   PlotIndexSetInteger(buffer_idx,PLOT_LINE_COLOR ,_color);
   PlotIndexSetInteger(buffer_idx,PLOT_LINE_WIDTH ,_width);
   PlotIndexSetInteger(buffer_idx,PLOT_DRAW_BEGIN ,_begin);
   PlotIndexSetInteger(buffer_idx,PLOT_ARROW      ,_arrow);
   PlotIndexSetString (buffer_idx,PLOT_LABEL      ,_label);
   PlotIndexSetDouble (buffer_idx,PLOT_EMPTY_VALUE,EMPTY_VALUE);    // define empty value not shown on chart and in datawindow
   buffer_idx++;                                             // increment bufferindex for next call
}
