//+------------------------------------------------------------------+
//| Shama V12 Demo-First EA v12.1                                    |
//| EMA trend + ATR stop; conservative capped recovery sizing.        |
//| Default: DEMO accounts only. No martingale grid or averaging.     |
//+------------------------------------------------------------------+
#property strict
#property version "12.10"
#property description "Demo-first risk-managed Shama V12 starter; test before use."
#include <Trade/Trade.mqh>
CTrade trade;

input bool   DemoOnly = true;
input bool   AllowLiveTrading = false;
input double RiskPercent = 0.25;          // Risk of equity per initial trade
input double MaxDailyLossPercent = 2.0;   // Stop new trades after this equity loss
input double MaxSpreadPoints = 80;
input double MaxLots = 0.10;              // Deliberately conservative cap
input int    MaxRecoverySteps = 2;        // Capped Martingale/recovery: 0..2
input double RecoveryMultiplier = 1.30;   // Mild scaling, never doubling
input int    FastEMA = 12;
input int    SlowEMA = 26;
input int    ATRPeriod = 14;
input double ATRStopMultiplier = 2.0;
input double RewardRisk = 1.5;
input ulong  MagicNumber = 121026;
input int    MaxPositions = 1;
input int    HeartbeatSeconds = 30;
input string BridgeURL = "https://shama-v12-app.onrender.com/api/mt5/heartbeat";
input string BridgeSecret = "";           // Set same secret as Render env; never publish it.

int hFast = INVALID_HANDLE, hSlow = INVALID_HANDLE, hATR = INVALID_HANDLE;
datetime lastBar = 0, dayAnchor = 0;
double dayStartEquity = 0;
int recoveryStep = 0;
bool dailyStopped = false;
datetime lastHeartbeat = 0;
string lastError = "";

bool IsDemoAccount() { return (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO); }

datetime DayStart(datetime t) {
   MqlDateTime x; TimeToStruct(t, x); x.hour=0; x.min=0; x.sec=0; return StructToTime(x);
}
void RefreshDailyGuard() {
   datetime now = TimeCurrent();
   datetime d = DayStart(now);
   if(dayAnchor != d) {
      dayAnchor = d; dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY); dailyStopped = false;
   }
   if(dayStartEquity > 0) {
      double lossPct = (dayStartEquity - AccountInfoDouble(ACCOUNT_EQUITY)) / dayStartEquity * 100.0;
      if(lossPct >= MaxDailyLossPercent) dailyStopped = true;
   }
}
bool IsNewBar() {
   datetime t=iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t==0 || t==lastBar) return false;
   lastBar=t; return true;
}
int CountMyPositions() {
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--) {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionSelectByTicket(ticket) &&
         PositionGetString(POSITION_SYMBOL)==_Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC)==MagicNumber) n++;
   }
   return n;
}
double NormalizeVolume(double lots) {
   double vmin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double vmax=MathMin(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX),MaxLots);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0 || vmax<vmin) return 0;
   lots=MathMax(vmin,MathMin(vmax,lots));
   lots=MathFloor(lots/step)*step;
   int digits=(int)MathMax(0,MathRound(-MathLog10(step)));
   return NormalizeDouble(lots,digits);
}
double CalculateLots(double stopDistance) {
   if(stopDistance<=0) return 0;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney=equity*(RiskPercent/100.0);
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue<=0) tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   if(tickSize<=0 || tickValue<=0) return 0;
   double lossPerLot=(stopDistance/tickSize)*tickValue;
   if(lossPerLot<=0) return 0;
   double lots=riskMoney/lossPerLot;
   // Capped, mild recovery sizing after losses; still bounded by MaxLots.
   int steps=MathMax(0,MathMin(MaxRecoverySteps,recoveryStep));
   for(int j=0;j<steps;j++) lots*=MathMax(1.0,MathMin(RecoveryMultiplier,1.5));
   return NormalizeVolume(MathMin(lots,MaxLots));
}
bool ReadIndicators(double &fast1,double &fast2,double &slow1,double &slow2,double &atr) {
   double f[3],s[3],a[2]; ArraySetAsSeries(f,true); ArraySetAsSeries(s,true); ArraySetAsSeries(a,true);
   if(CopyBuffer(hFast,0,0,3,f)<3 || CopyBuffer(hSlow,0,0,3,s)<3 || CopyBuffer(hATR,0,0,2,a)<2) return false;
   fast1=f[1]; fast2=f[2]; slow1=s[1]; slow2=s[2]; atr=a[1]; return atr>0;
}
void TryEntry() {
   if(dailyStopped || CountMyPositions()>=MaxPositions) return;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED)) return;
   if(DemoOnly && !IsDemoAccount()) { lastError="DemoOnly is enabled; non-demo account blocked."; return; }
   if(!IsDemoAccount() && !AllowLiveTrading) { lastError="Live trading is disabled."; return; }
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   double spread=(tick.ask-tick.bid)/_Point;
   if(spread>MaxSpreadPoints) return;
   double f1,f2,s1,s2,atr; if(!ReadIndicators(f1,f2,s1,s2,atr)) return;
   bool buy=(f2<=s2 && f1>s1);
   bool sell=(f2>=s2 && f1<s1);
   if(!buy && !sell) return;
   double stopDist=MathMax(atr*ATRStopMultiplier,SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point);
   double lots=CalculateLots(stopDist); if(lots<=0) { lastError="Lot sizing failed; check symbol tick values."; return; }
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double sl=0,tp=0;
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(20);
   if(buy) { sl=NormalizeDouble(tick.ask-stopDist,digits); tp=NormalizeDouble(tick.ask+stopDist*RewardRisk,digits); }
   else { sl=NormalizeDouble(tick.bid+stopDist,digits); tp=NormalizeDouble(tick.bid-stopDist*RewardRisk,digits); }
   bool ok= buy ? trade.Buy(lots,_Symbol,0,sl,tp,"Shama V12 EMA/ATR") : trade.Sell(lots,_Symbol,0,sl,tp,"Shama V12 EMA/ATR");
   if(!ok) lastError=trade.ResultRetcodeDescription(); else lastError="";
}
void SendHeartbeat() {
   if(BridgeURL=="" || BridgeSecret=="") return;
   datetime now=TimeCurrent(); if(now-lastHeartbeat<HeartbeatSeconds) return; lastHeartbeat=now;
   double dailyPnl=AccountInfoDouble(ACCOUNT_EQUITY)-dayStartEquity;
   string mode=IsDemoAccount()?"DEMO":(AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_REAL?"REAL":"UNKNOWN");
   string body=StringFormat("{\"accountMode\":\"%s\",\"symbol\":\"%s\",\"balance\":%.2f,\"equity\":%.2f,\"freeMargin\":%.2f,\"dailyPnl\":%.2f,\"openPositions\":%d,\"eaVersion\":\"12.10\"}",
      mode,_Symbol,AccountInfoDouble(ACCOUNT_BALANCE),AccountInfoDouble(ACCOUNT_EQUITY),
      AccountInfoDouble(ACCOUNT_MARGIN_FREE),dailyPnl,CountMyPositions());
   char data[],result[]; string headers="Content-Type: application/json\r\nX-Shama-Bridge-Secret: "+BridgeSecret+"\r\n";
   StringToCharArray(body,data,0,WHOLE_ARRAY,CP_UTF8);
   if(ArraySize(data)>0) ArrayResize(data,ArraySize(data)-1);
   string responseHeaders;
   ResetLastError();
   int code=WebRequest("POST",BridgeURL,headers,5000,data,result,responseHeaders);
   if(code<200 || code>=300) Print("Shama bridge heartbeat failed. HTTP=",code," err=",GetLastError());
}
int OnInit() {
   if(RiskPercent<=0 || RiskPercent>1.0 || MaxDailyLossPercent<=0 || MaxDailyLossPercent>5.0 ||
      MaxLots<=0 || RecoveryMultiplier<1.0 || RecoveryMultiplier>1.5 || MaxRecoverySteps<0 || MaxRecoverySteps>2) {
      Print("Unsafe inputs. RiskPercent must be (0,1], daily loss (0,5], recovery steps 0..2, multiplier <=1.5.");
      return INIT_PARAMETERS_INCORRECT;
   }
   hFast=iMA(_Symbol,PERIOD_CURRENT,FastEMA,0,MODE_EMA,PRICE_CLOSE);
   hSlow=iMA(_Symbol,PERIOD_CURRENT,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
   hATR=iATR(_Symbol,PERIOD_CURRENT,ATRPeriod);
   if(hFast==INVALID_HANDLE || hSlow==INVALID_HANDLE || hATR==INVALID_HANDLE) return INIT_FAILED;
   trade.SetExpertMagicNumber(MagicNumber);
   dayAnchor=DayStart(TimeCurrent()); dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   EventSetTimer(5);
   Print("Shama V12 started. DemoOnly=",DemoOnly," accountMode=",IsDemoAccount()?"DEMO":"NON-DEMO",
      ". This is a starter strategy, not a profit guarantee.");
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) { EventKillTimer(); if(hFast!=INVALID_HANDLE) IndicatorRelease(hFast); if(hSlow!=INVALID_HANDLE) IndicatorRelease(hSlow); if(hATR!=INVALID_HANDLE) IndicatorRelease(hATR); }
void OnTimer() { RefreshDailyGuard(); SendHeartbeat(); }
void OnTick() { RefreshDailyGuard(); if(IsNewBar()) TryEntry(); }

void OnTradeTransaction(const MqlTradeTransaction& trans,const MqlTradeRequest& request,const MqlTradeResult& result) {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=MagicNumber) return;
   long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) return;
   double net=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)+HistoryDealGetDouble(trans.deal,DEAL_SWAP)+HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);
   if(net<0) recoveryStep=MathMin(MaxRecoverySteps,recoveryStep+1);
   else if(net>0) recoveryStep=0;
}
