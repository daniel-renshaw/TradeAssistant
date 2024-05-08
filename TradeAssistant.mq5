#property copyright "Copyright 2020, Daniel Renshaw"
#property link      ""
#property version   "1.00"
#property strict

#include <GUI.mqh>
#include <ErrorDescription.mqh>
#include <MyIndicators.mqh>
#include <Indicators\Trend.mqh>

#define BUY_COLOR clrGreen
#define SELL_COLOR clrRed
#define ORDER_COLOR clrViolet
#define TP_COLOR clrRoyalBlue
#define SL_COLOR clrYellow
#define DEFAULT_BG_COLOR clrLightGray
#define DEFAULT_TEXT_COLOR clrBlack
#define TP_SL_DEFAULT_OFFSET 50 // in pips
#define POINT_TO_PIP 10.0
#define COMM_PER_LOT 0.0
#define DYNA_TOP_MARKER_OFFSET 50.0
#define DYNA_BOT_MARKER_OFFSET 300.0

ATR atr(20);
datetime lastCheck;

double GetCurrencyModifier()
{
	return Point() * SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
}

double NormalizeLots(double lots)
{
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    lots = MathRound(lots / lotStep) * lotStep;
    if (lots < minLot)
      lots = minLot;
    return lots;
}

double GetLotsWithCommission(double acctSize, double risk, double sl)
{
   double lots = NormalizeLots((acctSize * risk / sl) / GetCurrencyModifier());
   lots = NormalizeLots((((acctSize * risk) - (lots * COMM_PER_LOT)) / sl) / GetCurrencyModifier());
   return lots;
}

double NormalizePrice(double price)
{
   double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   return MathRound(price / tickSize) * tickSize;
}

// Main Container
enum MainContGUIStates
{
	GUI_STATE_HIDDEN		= 0x0000001,
	GUI_STATE_SHOWN			= 0x0000002,
	GUI_STATE_BUY			= 0x0000004,
	GUI_STATE_SELL			= 0x0000008,
	GUI_STATE_FREE_ORDER	= 0x0000010,
	GUI_STATE_LOCK_ORDER	= 0x0000020,
	GUI_STATE_DYNA_ORDER	= 0x0000040,
	GUI_STATE_HALF_PERC		= 0x0000080,
	GUI_STATE_ONE_PERC		= 0x0000100,
	GUI_STATE_TWO_PERC		= 0x0000200,
	GUI_STATE_FOUR_PERC		= 0x0000400,
	GUI_STATE_NOT_HIDDEN = GUI_STATE_SHOWN | GUI_STATE_BUY | GUI_STATE_SELL | GUI_STATE_FREE_ORDER | GUI_STATE_LOCK_ORDER | GUI_STATE_DYNA_ORDER,
};

datetime dynaMarkerTimeTop = iTime(Symbol(), Period(), 1);
datetime dynaMarkerTimeBottom = iTime(Symbol(), Period(), 1);

class ShowHideButtonGUIObject : public LabelGUIObject
{
public:
	ShowHideButtonGUIObject(int s, double x, double y, double sz, color clr) : LabelGUIObject(s, x, y, "", sz, clr) {}
	
protected:
	int HandleObjectClick()
	{
		if ((container.GetCurrentState() & GUI_STATE_SHOWN) != 0)
			return GUI_STATE_HIDDEN;
		return GUI_STATE_SHOWN | GUI_STATE_BUY | GUI_STATE_LOCK_ORDER | GUI_STATE_ONE_PERC;
	}
	
	void UpdateProc(long contX, long contY, long contWidth, long contHeight)
	{
		if ((container.GetCurrentState() & GUI_STATE_SHOWN) != 0)
			text = "HIDE";
		else
			text = "SHOW";
		
		LabelGUIObject::UpdateProc(contX, contY, contWidth, contHeight);
	}
};

class NextBarTimeGUIObject : public LabelGUIObject
{
public:
	NextBarTimeGUIObject(int s, double x, double y, string txt, double sz, color clr) : LabelGUIObject(s, x, y, txt, sz, clr) {}
	
protected:
	void UpdateProc(long contX, long contY, long contWidth, long contHeight)
	{
		CopyTime(Symbol(), Period(), 0, 1, time);
		time[0] = time[0] + PeriodSeconds() - TimeCurrent();
		text = TimeToString(time[0], TIME_SECONDS);
		LabelGUIObject::UpdateProc(contX, contY, contWidth, contHeight);
	}
	
	datetime time[1];
};

class OrderPriceLineGUIObject : public HoriLineGUIObject
{
public:
	OrderPriceLineGUIObject(int s, color clr) : HoriLineGUIObject(s, STORAGE_LOC, clr)
	{
		linkedSLTxt = NULL;
		linkedTPTxt = NULL;
	}
	
	void SetLinkedSLTextBox(TextBoxGUIObject *linked) { linkedSLTxt = linked; }
	void SetLinkedTPTextBox(TextBoxGUIObject *linked) { linkedTPTxt = linked; }
	double GetPrice() { return price; }
	
protected:
	void UpdateProc(long contX, long contY, long contWidth, long contHeight)
	{
		if (container)
		{
			int curState = container.GetCurrentState();
			if ((curState & GUI_STATE_LOCK_ORDER) != 0)
			{
			   MqlTick tick;
            SymbolInfoTick(Symbol(), tick);
				price = (curState & GUI_STATE_BUY) != 0 ? tick.ask : tick.bid;
				ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
				ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
				ObjectSetDouble(0, name, OBJPROP_PRICE, price);
			}
			else if ((curState & GUI_STATE_DYNA_ORDER) != 0)
			{
			   // Imbalance stuff
			   int indexTop = iBarShift(Symbol(), Period(), dynaMarkerTimeTop);
				int indexBottom = iBarShift(Symbol(), Period(), dynaMarkerTimeBottom);
				double spread = iSpread(Symbol(), Period(), 0) * Point();
				double risk = 0.0;
				double imbalance = 0.0;
				
				if ((curState & GUI_STATE_BUY) != 0)
				{
				   imbalance = iLow(Symbol(), Period(), indexTop - 1) - iHigh(Symbol(), Period(), indexTop + 1);
				   price = iHigh(Symbol(), Period(), indexTop + 1) + spread;
				   risk = price - iLow(Symbol(), Period(), indexBottom) + (imbalance / 2);
				}
				else
				{
				   imbalance = iLow(Symbol(), Period(), indexBottom + 1) - iHigh(Symbol(), Period(), indexBottom - 1);
				   price = iLow(Symbol(), Period(), indexBottom + 1);
				   risk = iHigh(Symbol(), Period(), indexTop) - price + (imbalance / 2) + spread;
				}

				ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
				ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
				ObjectSetDouble(0, name, OBJPROP_PRICE, price);
				
				if (linkedSLTxt != NULL && linkedTPTxt != NULL)
				{
				   risk /= Point();
				   risk /= POINT_TO_PIP;
					linkedSLTxt.SetText(DoubleToString(risk, 2));
					linkedTPTxt.SetText(DoubleToString(risk, 2));
				}
			}
			else
				ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
		}
		else
			ObjectSetDouble(0, name, OBJPROP_PRICE, price);
	}
	
	int HandleObjectDrag()
	{
		price = ObjectGetDouble(0, name, OBJPROP_PRICE);
		return 0;
	}
	
	TextBoxGUIObject *linkedSLTxt;
	TextBoxGUIObject *linkedTPTxt;
};

class BuySellButtonGUIObject : public LabelGUIObject
{
public:
	BuySellButtonGUIObject(int s, double x, double y, double sz) : LabelGUIObject(s, x, y, "", sz, clrBlack) {}
	
protected:
	int HandleObjectClick()
	{
		if (container == NULL)
			return 0;
			
		int curState = container.GetCurrentState();
		if ((curState & GUI_STATE_BUY) != 0)
		{
			curState &= ~(GUI_STATE_BUY);
			curState |= GUI_STATE_SELL;
		}
		else
		{
			curState &= ~(GUI_STATE_SELL);
			curState |= GUI_STATE_BUY;
		}

		return curState;
	}
	
	void UpdateProc(long contX, long contY, long contWidth, long contHeight)
	{
		if ((container.GetCurrentState() & GUI_STATE_BUY) != 0)
		{
			text = "BUY";
			textColor = BUY_COLOR;
		}
		else
		{
			text = "SELL";
			textColor = SELL_COLOR;
		}
		
		LabelGUIObject::UpdateProc(contX, contY, contWidth, contHeight);
	}
};

class TPSLLineGUIObject : public HoriLineGUIObject
{
public:
	TPSLLineGUIObject(int s, color clr, bool tp) : HoriLineGUIObject(s, STORAGE_LOC, clr)
	{
		linkedTxt = NULL;
		linkedOrder = NULL;
		offset = TP_SL_DEFAULT_OFFSET * Point() * POINT_TO_PIP;
		isTP = tp;
	}
	
	void SetLinkedTextBox(TextBoxGUIObject *linked) { linkedTxt = linked; }
	void SetLinkedOrderLine(OrderPriceLineGUIObject *linked) { linkedOrder = linked; }
	double GetPrice() { return price; }

protected:
	void UpdateProc(long contX, long contY, long contWidth, long contHeight)
	{
		if (ObjectGetInteger(0, name, OBJPROP_SELECTED) == 1)
			return;

		if (linkedTxt)
		{
			double str = StringToDouble(linkedTxt.GetText());
			if (str != 0.0)
				offset = str * Point() * POINT_TO_PIP;
		}
		
		bool isBuy = false;
		if (container)
		{
			int curState = container.GetCurrentState();
		 	if ((curState & GUI_STATE_BUY) != 0)
		 		isBuy = true;

			if ((curState & GUI_STATE_FREE_ORDER) == 0)
			{
				ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
				ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
			}
			else
				ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
		}
			
		if (linkedOrder)
		{
			if ((isBuy && isTP) || (!isBuy && !isTP))
				price = linkedOrder.GetPrice() + offset;
			else
				price = linkedOrder.GetPrice() - offset;
		}
		
		ObjectSetDouble(0, name, OBJPROP_PRICE, price);
	}

	int HandleObjectDrag()
	{
		if (linkedOrder == NULL)
			return 0;

		double newPrice = ObjectGetDouble(0, name, OBJPROP_PRICE);
		offset = MathAbs(newPrice - linkedOrder.GetPrice());
		
		if (linkedTxt)
		{
			double pipVal = offset / Point() / POINT_TO_PIP;
			string pipStr = DoubleToString(pipVal, 2);
			linkedTxt.SetText(pipStr);
		}

		return 0;
	}

	OrderPriceLineGUIObject *linkedOrder;
	TextBoxGUIObject *linkedTxt;
	double offset;
	bool isTP;
};

class ModeButtonGUIObject : public LabelGUIObject
{
public:
	ModeButtonGUIObject(int s, double x, double y, double sz) : LabelGUIObject(s, x, y, "", sz, DEFAULT_TEXT_COLOR) {}
	
protected:
	int HandleObjectClick()
	{
		if (container == NULL)
			return 0;

		int curState = container.GetCurrentState();
		if ((curState & GUI_STATE_LOCK_ORDER) != 0)
		{
			curState &= ~(GUI_STATE_LOCK_ORDER);
			curState |= GUI_STATE_FREE_ORDER;
		}
		else if ((curState & GUI_STATE_FREE_ORDER) != 0)
		{
			curState &= ~(GUI_STATE_FREE_ORDER);
			curState |= GUI_STATE_DYNA_ORDER;
		}
		else
		{
			curState &= ~(GUI_STATE_DYNA_ORDER);
			curState |= GUI_STATE_LOCK_ORDER;
		}

		return curState;
	}
	
	void UpdateProc(long contX, long contY, long contWidth, long contHeight)
	{
		if ((container.GetCurrentState() & GUI_STATE_LOCK_ORDER) != 0)
		{
			text = "LOCK";
			textColor = clrBlack;
		}
		else if ((container.GetCurrentState() & GUI_STATE_FREE_ORDER) != 0)
		{
			text = "FREE";
			textColor = clrBlack;
		}
		else if ((container.GetCurrentState() & GUI_STATE_DYNA_ORDER) != 0)
		{
			text = "DYNA";
			textColor = clrBlack;
		}
		
		LabelGUIObject::UpdateProc(contX, contY, contWidth, contHeight);
	}
};

class RiskPercButtonGUIObject : public LabelGUIObject
{
public:
	RiskPercButtonGUIObject(int s, double x, double y, double sz) : LabelGUIObject(s, x, y, "", sz, DEFAULT_TEXT_COLOR) {}
	
protected:
	int HandleObjectClick()
	{
		if (container == NULL)
			return 0;

		int curState = container.GetCurrentState();
		if ((curState & GUI_STATE_HALF_PERC) != 0)
		{
			curState &= ~(GUI_STATE_HALF_PERC);
			curState |= GUI_STATE_ONE_PERC;
		}
		else if ((curState & GUI_STATE_ONE_PERC) != 0)
		{
			curState &= ~(GUI_STATE_ONE_PERC);
			curState |= GUI_STATE_TWO_PERC;
		}
		else if ((curState & GUI_STATE_TWO_PERC) != 0)
		{
			curState &= ~(GUI_STATE_TWO_PERC);
			curState |= GUI_STATE_FOUR_PERC;
		}
		else if ((curState & GUI_STATE_FOUR_PERC) != 0)
		{
			curState &= ~(GUI_STATE_FOUR_PERC);
			curState |= GUI_STATE_HALF_PERC;
		}

		return curState;
	}
	
	void UpdateProc(long contX, long contY, long contWidth, long contHeight)
	{
		if (container)
		{
			int curState = container.GetCurrentState();
			if ((curState & GUI_STATE_HALF_PERC) != 0)
			{
				text = ".5%";
				textColor = clrGreenYellow;
			}
			else if ((curState & GUI_STATE_ONE_PERC) != 0)
			{
				text = "1%";
				textColor = clrDarkViolet;
			}
			else if ((curState & GUI_STATE_TWO_PERC) != 0)
			{
				text = "2%";
				textColor = clrOrange;
			}
			else if ((curState & GUI_STATE_FOUR_PERC) != 0)
			{
				text = "4%";
				textColor = clrFireBrick;
			}
		}
		
		LabelGUIObject::UpdateProc(contX, contY, contWidth, contHeight);
	}
};

double GetRiskFromState(int state)
{
	if ((state & GUI_STATE_HALF_PERC) != 0)
		return 0.005;
	else if ((state & GUI_STATE_ONE_PERC) != 0)
		return 0.01;
	else if ((state & GUI_STATE_TWO_PERC) != 0)
		return 0.02;
	else if ((state & GUI_STATE_FOUR_PERC) != 0)
		return 0.04;
	return 0;
}

class OrderLineLabelGUIObject : public LabelGUIObject
{
public:
	OrderLineLabelGUIObject(int s, double sz, color clr) : LabelGUIObject(s, 0, 0, "", sz, clr)
	{
		linkedOrder = NULL;
		linkedSL = NULL;
		linkedTP = NULL;
		posX = 0.85;
	}

	void SetLinkedOrder(OrderPriceLineGUIObject *linked) { linkedOrder = linked; }
	void SetLinkedSL(TextBoxGUIObject *linked) { linkedSL = linked; }
	void SetLinkedTP(TextBoxGUIObject *linked) { linkedTP = linked; }
	
protected:
	void UpdateProc(long contX, long contY, long contWidth, long contHeight)
	{
		if (container != NULL && linkedOrder != NULL && linkedSL != NULL && linkedTP != NULL)
		{
			double sl = StringToDouble(linkedSL.GetText()) * POINT_TO_PIP;
			double tp = StringToDouble(linkedTP.GetText()) * POINT_TO_PIP;
			double acctSize = AccountInfoDouble(ACCOUNT_BALANCE);
			double risk = GetRiskFromState(container.GetCurrentState());
			double lotSize = GetLotsWithCommission(acctSize, risk, sl);
			
			StringConcatenate(text, "Lot Size: ", DoubleToString(lotSize, 2), ", Ratio: ", DoubleToString(tp / sl, 2));
			ObjectSetTextFormat(name, text, int(size * contHeight), "Arial", textColor);
			
			int x = 0, y = 0;
			ChartTimePriceToXY(0, 0, iTime(Symbol(), Period(), 0), linkedOrder.GetPrice(), x, y);
			long labelY = y - long(size * contHeight * 1.6);
			long chartWidth = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
			ObjectSetInteger(0, name, OBJPROP_XDISTANCE, long(posX * chartWidth));
			ObjectSetInteger(0, name, OBJPROP_YDISTANCE, labelY);
		}
	}
	
	OrderPriceLineGUIObject *linkedOrder;
	TextBoxGUIObject *linkedSL;
	TextBoxGUIObject *linkedTP;
};

class TPSLLineLabelGUIObject : public LabelGUIObject
{
public:
	TPSLLineLabelGUIObject(int s, double sz, color clr, bool tp) : LabelGUIObject(s, 0, 0, "", sz, clr)
	{
		linkedLine = NULL;
		linkedSL = NULL;
		linkedTP = NULL;
		posX = 0.85;
		isTP = tp;
	}

	void SetLinkedLine(TPSLLineGUIObject *linked) { linkedLine = linked; }
	void SetLinkedSL(TextBoxGUIObject *linked) { linkedSL = linked; }
	void SetLinkedTP(TextBoxGUIObject *linked) { linkedTP = linked; }
	
protected:
	void UpdateProc(long contX, long contY, long contWidth, long contHeight)
	{
		if (container != NULL && linkedLine != NULL && linkedSL != NULL && linkedTP != NULL)
		{
			string sl = linkedSL.GetText();
			string tp = linkedTP.GetText();
			double acctSize = AccountInfoDouble(ACCOUNT_BALANCE);
			double risk = GetRiskFromState(container.GetCurrentState());
			double riskVal = acctSize * risk;
			double reward = StringToDouble(tp) / StringToDouble(sl) * riskVal;
			
			if (isTP)
				StringConcatenate(text, "TP: ", tp, ", Reward: $", DoubleToString(reward, 2));
			else
				StringConcatenate(text, "SL: ", sl, ", Risk: $", DoubleToString(riskVal, 2));
			ObjectSetTextFormat(name, text, int(size * contHeight), "Arial", textColor);
			
			int x = 0, y = 0;
			ChartTimePriceToXY(0, 0, iTime(Symbol(), Period(), 0), linkedLine.GetPrice(), x, y);
			long labelY = y - long(size * contHeight * 1.6);
			long chartWidth = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
			ObjectSetInteger(0, name, OBJPROP_XDISTANCE, long(posX * chartWidth));
			ObjectSetInteger(0, name, OBJPROP_YDISTANCE, labelY);
		}
	}
	
	TPSLLineGUIObject *linkedLine;
	TextBoxGUIObject *linkedSL;
	TextBoxGUIObject *linkedTP;
	bool isTP;
};

class PreviousBarHighLowGUIObject : public LabelGUIObject
{
public:
	PreviousBarHighLowGUIObject(int s, double x, double y, string txt, double sz, color clr, bool high) : LabelGUIObject(s, x, y, txt, sz, clr)
	{
		isHigh = high;
	}
	
protected:
	void UpdateProc(long contX, long contY, long contWidth, long contHeight)
	{
		if (isHigh)
			text = "PrevHigh: " + DoubleToString(iHigh(Symbol(), Period(), 1), 5);
		else
			text = "PrevLow: " + DoubleToString(iLow(Symbol(), Period(), 1), 5);
		LabelGUIObject::UpdateProc(contX, contY, contWidth, contHeight);
	}
	
	bool isHigh;
};

class SpreadGUIObject : public LabelGUIObject
{
public:
	SpreadGUIObject(int s, double x, double y, string txt, double sz, color clr) : LabelGUIObject(s, x, y, txt, sz, clr) {}
	
protected:
	void UpdateProc(long contX, long contY, long contWidth, long contHeight)
	{
		text = "Spread: " + DoubleToString(iSpread(Symbol(), Period(), 0) / POINT_TO_PIP, 1) + " pips";
		LabelGUIObject::UpdateProc(contX, contY, contWidth, contHeight);
	}
};

class ATRMultiGUIObject : public LabelGUIObject
{
public:
	ATRMultiGUIObject(int s, double x, double y, string txt, double sz, color clr, double multi) : LabelGUIObject(s, x, y, txt, sz, clr)
	{
	   multiplier = multi;
	}
	
protected:
	void UpdateProc(long contX, long contY, long contWidth, long contHeight)
	{
	   string multi = DoubleToString(multiplier, 1);
		text = "ATR (" + multi + "x): " + DoubleToString((atr.Get() * multiplier) / Point() / POINT_TO_PIP, 1) + " pips";
		LabelGUIObject::UpdateProc(contX, contY, contWidth, contHeight);
	}
	
	double multiplier;
};

class OpenTradesInfoGUIObject : public LabelGUIObject
{
public:
	OpenTradesInfoGUIObject(int s, double sz) : LabelGUIObject(s, 0.85, 0, "", sz, clrWhite) {}
	
protected:
	void UpdateProc(long contX, long contY, long contWidth, long contHeight)
	{
		double acctSize = AccountInfoDouble(ACCOUNT_BALANCE);
		double acctPL = AccountInfoDouble(ACCOUNT_PROFIT);
		int numPositions = PositionsTotal();

		if (numPositions == 0 || acctPL == 0)
		{
			text = "";
			ObjectSetTextFormat(name, text, int(size * contHeight), "Arial", clrWhite);
			ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
			return;
		}
		
		double symbolPL = 0.0;
		if (PositionSelect(Symbol()))
		   symbolPL += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_COMMISSION);
		
      double symbolPLPerc = symbolPL / acctSize * 100;
      text = "Symbol P/L: " + DoubleToString(symbolPLPerc, 2) + "%, Total P/L: ";
		double acctPLPerc = acctPL / acctSize * 100;		
		text += DoubleToString(acctPLPerc, 2) + "%";
		ObjectSetTextFormat(name, text, int(size * contHeight), "Arial", clrWhite);
		
		int x = 0, y = 0;
		MqlTick tick;
      SymbolInfoTick(Symbol(), tick);
		ChartTimePriceToXY(0, 0, tick.time, tick.bid, x, y);
		long labelY = y - long(size * contHeight * 1.6);
		long chartWidth = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
		ObjectSetInteger(0, name, OBJPROP_XDISTANCE, long(posX * chartWidth));
		ObjectSetInteger(0, name, OBJPROP_YDISTANCE, labelY);
		ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
	}
};

class DynaOrderMarkerGUIObject : public GUIObject
{
public:
	DynaOrderMarkerGUIObject(int s, bool top) : GUIObject(s, 0, 0), isTop(top) {}
	
protected:
	void UpdateProc(long contX, long contY, long contWidth, long contHeight) {}
	
	void InitProc(GUIContainer *cont, string n)
	{
		ObjectCreate(0, n, OBJ_ARROW, 0, iTime(Symbol(), Period(), 1), 0);
		ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
		ObjectSetInteger(0, n, OBJPROP_ZORDER, 2);
		ObjectSetInteger(0, n, OBJPROP_ARROWCODE, 170);
		ObjectSetInteger(0, n, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
		ObjectSetInteger(0, n, OBJPROP_COLOR, clrWhite);
		ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
		ObjectSetInteger(0, n, OBJPROP_SELECTABLE, true);
		GUIObject::InitProc(cont, n);
	}
	
	int HandleObjectDrag()
	{
	   if (isTop)
		{
   		dynaMarkerTimeTop = datetime(ObjectGetInteger(0, name, OBJPROP_TIME));
   		int index = iBarShift(Symbol(), Period(), dynaMarkerTimeTop);
   		ObjectMove(0, name, 0, dynaMarkerTimeTop, iHigh(Symbol(), Period(), index) + (DYNA_TOP_MARKER_OFFSET * Point()));
		}
		else
		{
		   dynaMarkerTimeBottom = datetime(ObjectGetInteger(0, name, OBJPROP_TIME));
   		int index = iBarShift(Symbol(), Period(), dynaMarkerTimeBottom);
   		ObjectMove(0, name, 0, dynaMarkerTimeBottom, iLow(Symbol(), Period(), index) - (DYNA_BOT_MARKER_OFFSET * Point()));
		}
		
		return 0;
	}
	
	void Disable()
	{
		ObjectMove(0, name, 0, iTime(Symbol(), Period(), 1), 0);
		enabled = false;
	}
	
	void Enable()
	{
		if (enabled)
			return;

      if (isTop)
      {
   		dynaMarkerTimeTop = iTime(Symbol(), Period(), 1);
   		ObjectMove(0, name, 0, dynaMarkerTimeTop, iHigh(Symbol(), Period(), 1) + (DYNA_TOP_MARKER_OFFSET * Point()));
		}
		else
		{
		   dynaMarkerTimeBottom = iTime(Symbol(), Period(), 1);
		   ObjectMove(0, name, 0, dynaMarkerTimeBottom, iLow(Symbol(), Period(), 1) - (DYNA_BOT_MARKER_OFFSET * Point()));
		}
		
		GUIObject::Enable();
	}
	
	bool isTop;
};

GUI gui("TradeAssistant");

int OnInit()
{
   lastCheck = iTime(Symbol(), Period(), 1);
   
   int bars = Bars(Symbol(), Period());
   for (int i = bars - 2; i > 1; --i)
   {
      atr.Update(iClose(Symbol(), Period(), i + 1), iHigh(Symbol(), Period(), i), iLow(Symbol(), Period(), i), iOpen(Symbol(), Period(), i), iClose(Symbol(), Period(), i));
   }

	GUIContainer *mainCont = gui.CreateContainer("Main", 0.125, 0.0275, 0.114, 0.1);
	if (mainCont)
	{
		OrderPriceLineGUIObject *orderLine = new OrderPriceLineGUIObject(GUI_STATE_SHOWN, ORDER_COLOR);
		mainCont.AddObject(orderLine);
		TPSLLineGUIObject *slLine = new TPSLLineGUIObject(GUI_STATE_SHOWN, SL_COLOR, false);
		mainCont.AddObject(slLine);
		slLine.SetLinkedOrderLine(orderLine);
		TPSLLineGUIObject *tpLine = new TPSLLineGUIObject(GUI_STATE_SHOWN, TP_COLOR, true);
		mainCont.AddObject(tpLine);
		tpLine.SetLinkedOrderLine(orderLine);
		
		OrderLineLabelGUIObject *orderLabel = new OrderLineLabelGUIObject(GUI_STATE_SHOWN, 0.18, ORDER_COLOR);
		mainCont.AddObject(orderLabel);
		orderLabel.SetLinkedOrder(orderLine);
		TPSLLineLabelGUIObject *slLabel = new TPSLLineLabelGUIObject(GUI_STATE_SHOWN, 0.18, SL_COLOR, false);
		mainCont.AddObject(slLabel);
		slLabel.SetLinkedLine(slLine);
		TPSLLineLabelGUIObject *tpLabel = new TPSLLineLabelGUIObject(GUI_STATE_SHOWN, 0.18, TP_COLOR, true);
		mainCont.AddObject(tpLabel);
		tpLabel.SetLinkedLine(tpLine);

		mainCont.AddObject(new RectGUIObject(GUI_STATE_HIDDEN, 0, 0, 0.55, 0.5, DEFAULT_BG_COLOR));
		mainCont.AddObject(new RectGUIObject(GUI_STATE_SHOWN, 0, 0, 1, 1, DEFAULT_BG_COLOR));
		mainCont.AddObject(new ShowHideButtonGUIObject(GUI_STATE_ALL, 0.05, 0.075, 0.25, DEFAULT_TEXT_COLOR));
		mainCont.AddObject(new BuySellButtonGUIObject(GUI_STATE_SHOWN, 0.05, 0.5, 0.25));
		mainCont.AddObject(new ModeButtonGUIObject(GUI_STATE_SHOWN, 0.4, 0.075, 0.25));
		mainCont.AddObject(new RiskPercButtonGUIObject(GUI_STATE_SHOWN, 0.775, 0.075, 0.25));
		
		TextBoxGUIObject *slTextBox = new TextBoxGUIObject(GUI_STATE_SHOWN, 0.4, 0.525, DoubleToString(TP_SL_DEFAULT_OFFSET, 2), 0.25, 0.325, DEFAULT_TEXT_COLOR, SL_COLOR);
		mainCont.AddObject(slTextBox);
		orderLine.SetLinkedSLTextBox(slTextBox);
		slLine.SetLinkedTextBox(slTextBox);
		orderLabel.SetLinkedSL(slTextBox);
		slLabel.SetLinkedSL(slTextBox);
		tpLabel.SetLinkedSL(slTextBox);
		
		TextBoxGUIObject *tpTextBox = new TextBoxGUIObject(GUI_STATE_SHOWN, 0.7, 0.525, DoubleToString(TP_SL_DEFAULT_OFFSET, 2), 0.25, 0.325, DEFAULT_TEXT_COLOR, TP_COLOR);
		mainCont.AddObject(tpTextBox);
		orderLine.SetLinkedTPTextBox(tpTextBox);
		tpLine.SetLinkedTextBox(tpTextBox);
		orderLabel.SetLinkedTP(tpTextBox);
		slLabel.SetLinkedTP(tpTextBox);
		tpLabel.SetLinkedTP(tpTextBox);
		
		DynaOrderMarkerGUIObject *dynaOrderMarkerTop = new DynaOrderMarkerGUIObject(GUI_STATE_DYNA_ORDER, true);
		mainCont.AddObject(dynaOrderMarkerTop);
		DynaOrderMarkerGUIObject *dynaOrderMarkerBottom = new DynaOrderMarkerGUIObject(GUI_STATE_DYNA_ORDER, false);
		mainCont.AddObject(dynaOrderMarkerBottom);
	}
	
	GUIContainer *nextBarTimeCont = gui.CreateContainer("NextBarTime", 0.9285, 0.95, 0.114, 0.1);
	if (nextBarTimeCont)
		nextBarTimeCont.AddObject(new NextBarTimeGUIObject(GUI_STATE_ALL, 0.05, 0.075, " ", 0.25, clrWhite));

	GUIContainer *miscInfoCont = gui.CreateContainer("MiscInfo", 0.915, 0.85, 0.114, 0.1);
	if (miscInfoCont)
	{
		miscInfoCont.AddObject(new PreviousBarHighLowGUIObject(GUI_STATE_ALL, 0.05, 0.075, "", 0.125, clrWhite, true));
		miscInfoCont.AddObject(new PreviousBarHighLowGUIObject(GUI_STATE_ALL, 0.05, 0.33, "", 0.125, clrWhite, false));
		miscInfoCont.AddObject(new SpreadGUIObject(GUI_STATE_ALL, 0.05, 0.585, "", 0.125, clrWhite));
		miscInfoCont.AddObject(new ATRMultiGUIObject(GUI_STATE_ALL, 0.05, 0.84, "", 0.125, clrWhite, 1.5));
		miscInfoCont.AddObject(new OpenTradesInfoGUIObject(GUI_STATE_ALL, 0.15));
	}
	
	EventSetMillisecondTimer(100);

	return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   gui.Reset();
	EventKillTimer();
}

void OnTimer()
{
	gui.Update();
}

void OnTick()
{
   datetime curTime = iTime(Symbol(), Period(), 0);
   if (curTime == lastCheck)
      return;
      
   lastCheck = curTime;
   atr.Update(iClose(Symbol(), Period(), 2), iHigh(Symbol(), Period(), 1), iLow(Symbol(), Period(), 1), iOpen(Symbol(), Period(), 1), iClose(Symbol(), Period(), 1));
}

void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
{
	gui.HandleEvent(id, sparam);
}