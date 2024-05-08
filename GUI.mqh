#property copyright "Copyright 2020, Daniel Renshaw"
#property link      ""
#property strict

#define __DELETE(x) if (x) { delete(x); x = NULL; }
#define STORAGE_LOC -10000

enum GUIState
{
	GUI_STATE_1		= 0x0000001,
	GUI_STATE_2		= 0x0000002,
	GUI_STATE_3		= 0x0000004,
	GUI_STATE_4		= 0x0000008,
	GUI_STATE_5		= 0x0000010,
	GUI_STATE_6		= 0x0000020,
	GUI_STATE_7		= 0x0000040,
	GUI_STATE_8		= 0x0000080,
	GUI_STATE_ALL	= 0xFFFFFFF,
};

void ObjectSetTextFormat(string name, string text, int size, string font, color clr)
{
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

class GUIContainer;

class GUIObject
{
public:
	GUIObject(int s, double x, double y)
	{
		posX = x;
		posY = y;
		state = s;
		enabled = true;
		container = NULL;
	}
	
	~GUIObject()
	{
		ObjectDelete(0, name);
	}
	
	string GetName() { return name; }
	void Update(long contX, long contY, long contWidth, long contHeight) { UpdateProc(contX, contY, contWidth, contHeight); }
	void Init(GUIContainer *cont, string n) { InitProc(cont, n); }
	
	int HandleEvent(int id)
	{
		switch (id)
		{
		case CHARTEVENT_OBJECT_CLICK:
			return HandleObjectClick();

		case CHARTEVENT_OBJECT_DRAG:
			return HandleObjectDrag();
			
		case CHARTEVENT_OBJECT_ENDEDIT:
			return HandleObjectEndEdit();
		}
		
		return 0;
	}
	
	bool IsVisible(int s)
	{
		if ((state & s) == 0)
		{
			if (enabled)
				Disable();

			return false;
		}

		Enable();
		return true;
	}
	
protected:
	string name;
	double posX;
	double posY;
	int state;
	bool enabled;
	GUIContainer *container;
	
	virtual void UpdateProc(long contX, long contY, long contWidth, long contHeight) = 0;
	virtual int HandleObjectClick() { return 0; }
	virtual int HandleObjectDrag() { return 0; }
	virtual int HandleObjectEndEdit() { return 0; }
	
	virtual void InitProc(GUIContainer *cont, string n)
	{
		container = cont;
		name = n;
		ObjectSetString(0, name, OBJPROP_TOOLTIP, "\n");
	}
	
	virtual void Disable()
	{
		ObjectSetInteger(0, name, OBJPROP_XDISTANCE, STORAGE_LOC);
		ObjectSetInteger(0, name, OBJPROP_YDISTANCE, STORAGE_LOC);
		enabled = false;
	}
	
	virtual void Enable()
	{
		enabled = true;
	}
};

class GUIContainer
{
public:
	GUIContainer(string n, double x, double y, double w, double h)
	{
		ArrayResize(objects, 5, 15);
		objCount = 0;
		name = n;
		posX = x;
		posY = y;
		width = w;
		height = h;
		currentState = 0x1;
	}
	
	~GUIContainer()
	{
		for (int i = 0; i < objCount; ++i)
		{
			__DELETE(objects[i]);
		}
	}
	
	void Update(long chartWidth, long chartHeight)
	{
		for (int i = 0; i < objCount; ++i)
		{
			if (objects[i] != NULL && objects[i].IsVisible(currentState))
				objects[i].Update(long(posX * chartWidth), long(posY * chartHeight), long(width * chartWidth), long(height * chartHeight));
		}
	}
	
	void HandleEvent(int id, string objName)
	{
		int newState = 0;
		
		for (int i = 0; i < objCount; ++i)
		{
			if (objects[i])
			{
				if (StringCompare(objects[i].GetName(), objName) == 0)
					newState = objects[i].HandleEvent(id);
				else
					ObjectSetInteger(0, objects[i].GetName(), OBJPROP_SELECTED, false);
			}
		}

		if (newState)
			currentState = newState;
	}
	
	void AddObject(GUIObject *obj)
	{
		if (objCount == ArraySize(objects))
			ArrayResize(objects, objCount + 2, 50);
		
		objects[objCount++] = obj;
		string str = "";
		StringConcatenate(str, name, "_", objCount);
		obj.Init(GetPointer(this), str);
	}
	
	void SetName(string n) { name = n; }
	string GetName() { return name; }
	int GetCurrentState() { return currentState; }
	
private:
	GUIObject *objects[];
	int objCount;
	string name;
	double posX;
	double posY;
	double width;
	double height;
	int currentState;
};

class GUI
{
public:
	GUI(string n)
	{
		ArrayResize(containers, 1, 50);
		contCount = 0;
		name = n;
		chartWidth = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
		chartHeight = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
	}
	
	~GUI()
	{
		Reset();
	}
	
	void Update()
	{
		chartWidth = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
		chartHeight = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
		
		for (int i = 0; i < contCount; ++i)
		{
			if (containers[i])
				containers[i].Update(chartWidth, chartHeight);
		}
		
		ChartRedraw();
	}
	
	GUIContainer *CreateContainer(string n, double x, double y, double w, double h)
	{
		if (contCount == ArraySize(containers))
			ArrayResize(containers, contCount + 2, 50);

		GUIContainer *cont = new GUIContainer(n, x, y, w, h);
		if (cont == NULL)
		{
			Print("Error initializing GUIContainer.");
			return NULL;
		}
		
		containers[contCount++] = cont;
		string str = "";
		StringConcatenate(str, name, "_", n);
		cont.SetName(str);
		return cont;
	}
	
	void HandleEvent(int id, string objName)
	{
	   string str = "";
	   StringConcatenate(str, name, "_");
		if (StringFind(objName, str, 0) == -1)
			return;

		for (int i = 0; i < contCount; ++i)
		{
			if (containers[i])
				containers[i].HandleEvent(id, objName);
		}
	}
	
	void Reset()
	{
	   for (int i = 0; i < contCount; ++i)
		{
			__DELETE(containers[i]);
		}
	}
	
private:
	GUIContainer *containers[];
	int contCount;
	string name;
	long chartWidth;
	long chartHeight;
};

class LabelGUIObject : public GUIObject
{
public:
	LabelGUIObject(int s, double x, double y, string txt, double sz, color clr) : GUIObject(s, x, y)
	{
		text = txt;
		size = sz;
		textColor = clr;
	}
	
protected:
	void InitProc(GUIContainer *cont, string n)
	{
		ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
		ObjectSetTextFormat(n, text, 1, "Arial", textColor);
		ObjectSetInteger(0, n, OBJPROP_ZORDER, 2);
		ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
		ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
		ObjectSetInteger(0, n, OBJPROP_XDISTANCE, STORAGE_LOC);
		ObjectSetInteger(0, n, OBJPROP_YDISTANCE, STORAGE_LOC);
		GUIObject::InitProc(cont, n);
	}
	
	void UpdateProc(long contX, long contY, long contWidth, long contHeight)
	{
		ObjectSetTextFormat(name, text, int(size * contHeight), "Arial", textColor);
		ObjectSetInteger(0, name, OBJPROP_XDISTANCE, contX + long(posX * contWidth));
		ObjectSetInteger(0, name, OBJPROP_YDISTANCE, contY + long(posY * contHeight));
	}

	double size;
	string text;
	color textColor;
};

class RectGUIObject : public GUIObject
{
public:
	RectGUIObject(int s, double x, double y, double w, double h, color clr) : GUIObject(s, x, y)
	{
		width = w;
		height = h;
		bgColor = clr;
	}

protected:
	void InitProc(GUIContainer *cont, string n)
	{
		ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
		ObjectSetInteger(0, n, OBJPROP_XSIZE, 1);
		ObjectSetInteger(0, n, OBJPROP_YSIZE, 1);
		ObjectSetInteger(0, n, OBJPROP_ZORDER, 1);
		ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
		ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bgColor);
		ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
		ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
		ObjectSetInteger(0, n, OBJPROP_XDISTANCE, STORAGE_LOC);
		ObjectSetInteger(0, n, OBJPROP_YDISTANCE, STORAGE_LOC);
		GUIObject::InitProc(cont, n);
	}
	
	void UpdateProc(long contX, long contY, long contWidth, long contHeight)
	{
		ObjectSetInteger(0, name, OBJPROP_XSIZE, long(width * contWidth));
		ObjectSetInteger(0, name, OBJPROP_YSIZE, long(height * contHeight));
		ObjectSetInteger(0, name, OBJPROP_XDISTANCE, contX + long(posX * contWidth));
		ObjectSetInteger(0, name, OBJPROP_YDISTANCE, contY + long(posY * contHeight));
	}
	
	double width;
	double height;
	color bgColor;
};

class HoriLineGUIObject : public GUIObject
{
public:
	HoriLineGUIObject(int s, double p, color clr) : GUIObject(s, 0, 0)
	{
		price = p;
		lineColor = clr;
	}

protected:
	void InitProc(GUIContainer *cont, string n)
	{
		ObjectCreate(0, n, OBJ_HLINE, 0, 0, STORAGE_LOC);
		ObjectSetInteger(0, n, OBJPROP_ZORDER, 1);
		ObjectSetInteger(0, n, OBJPROP_COLOR, lineColor);
		ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
		ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
		ObjectSetInteger(0, n, OBJPROP_STYLE, STYLE_DASH);
		GUIObject::InitProc(cont, n);
	}
	
	void UpdateProc(long contX, long contY, long contWidth, long contHeight)
	{
		ObjectSetDouble(0, name, OBJPROP_PRICE, price);
	}
	
	void Disable()
	{
		ObjectSetDouble(0, name, OBJPROP_PRICE, STORAGE_LOC);
	}

	double price;
	color lineColor;
};

class TextBoxGUIObject : public GUIObject
{
public:
	TextBoxGUIObject(int s, double x, double y, string txt, double w, double h, color txtClr, color bgClr) : GUIObject(s, x, y)
	{
		text = txt;
		width = w;
		height = h;
		textColor = txtClr;
		bgColor = bgClr;
	}
	
	string GetText() { return text; }
	void SetText(string txt) { text = txt; }
	
protected:
	void InitProc(GUIContainer *cont, string n)
	{
		ObjectCreate(0, n, OBJ_EDIT, 0, 0, 0);
		ObjectSetTextFormat(n, text, 12, "Arial", textColor);
		ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bgColor);
		ObjectSetInteger(0, n, OBJPROP_COLOR, textColor);
		ObjectSetInteger(0, n, OBJPROP_ALIGN, ALIGN_CENTER);
		ObjectSetInteger(0, n, OBJPROP_ZORDER, 2);
		ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
		ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
		ObjectSetInteger(0, n, OBJPROP_XDISTANCE, STORAGE_LOC);
		ObjectSetInteger(0, n, OBJPROP_YDISTANCE, STORAGE_LOC);
		GUIObject::InitProc(cont, n);
	}
	
	void UpdateProc(long contX, long contY, long contWidth, long contHeight)
	{
		ObjectSetTextFormat(name, text, 12, "Arial", textColor);
		ObjectSetInteger(0, name, OBJPROP_XSIZE, long(width * contWidth));
		ObjectSetInteger(0, name, OBJPROP_YSIZE, long(height * contHeight));
		ObjectSetInteger(0, name, OBJPROP_XDISTANCE, contX + long(posX * contWidth));
		ObjectSetInteger(0, name, OBJPROP_YDISTANCE, contY + long(posY * contHeight));
	}
	
	int HandleObjectEndEdit()
	{
		string str = ObjectGetString(0, name, OBJPROP_TEXT);
		double val = StringToDouble(str);
		if (val != 0.0)
			text = DoubleToString(val, 2);
		return 0;
	}

	string text;
	double width;
	double height;
	color textColor;
	color bgColor;
};