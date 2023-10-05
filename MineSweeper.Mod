(* OBERON System 3, Release 2.3.

Copyright 1999 ETH Zürich Institute for Computer Systems, 
ETH Center, CH-8092 Zürich. e-mail: oberon@inf.ethz.ch.

This module may be used under the conditions of the general Oberon 
System 3 license contract. The full text can be downloaded from

	"ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/license.txt;A"

Under the license terms stated it is in particular (a) prohibited to modify
the interface of this module in any way that disagrees with the style
or content of the system and (b) requested to provide all conversions
of the source code to another platform with the name OBERON. *)

MODULE MineSweeper;	(** portable *)	(*	 written by M.Daetwyler & P.Saladin	 	*)
(*
	05.03.95	implemented automatic task removal	-> V 1.2
	17.02.95	updated to Oberon System3 2.0	-> V 1.1
	15.06.94	simplified procedure DisplayToField
						fixed mouse tracking (Effects.TrackMouse no longer used)
						simplified drawing of pressed fields in procedure TrackLeftRight
						integrated procedure New in procedure NewGame
*)

IMPORT Modules, Files, Input, Display, Display3, Fonts, Printer, Printer3, Effects, Objects, Attributes, Gadgets, Oberon,
	TextFields, Pictures, Panels, Documents, Desktops, Out, Strings;


CONST
	Version = "V 1.2";
	PictName = "MineSweeperBD.Pict";
	IconName = "Icons2.Bombe";
	FontName = "Default10b.Scn.Fnt";
	ViewName = "Mine";
	
	(* menu of MineSweeperDoc: string with following EBNF format: {CommandName["["MenuButtonCaption"]"] } *)
	MenuString = "Desktops.StoreDoc[Store] MineSweeper.NewGame[New]";
	
	(* display and logical sizes *)
	BoxW = 16; BoxH = 16;	(* size of a single mine box *)
	
	MinFieldW = 8; MaxFieldW = 30;	(* min/max values of field's size *)
	MinFieldH = 8; MaxFieldH = 16;
	MinMines = 10; MaxMines = 99;	(* min/max number of mines  *)
	
	FieldDX = 90; FieldDY = BoxH DIV 2;	(* offset (top-left) of field area in view *)
	
	TimeDX = BoxW DIV 2; TimeDY = FieldDY;	(* offset (top-left) of time area and its size *)
	TimeW = 70; TimeH = 20;
	TimeCol = 9;
	
	CountDX = TimeDX; CountDY = TimeDY + 2*BoxH;	(* offset (top-left) of flag counter area and its size *)
	CountW = TimeW; CountH = TimeH;
	CountCol = 7;
	
	VW = 2*TimeDX + TimeW; VH = CountDY + CountH + (BoxH DIV 2);	(* minimum size of view (without a mine field) *)
	PW = (MinFieldW * BoxW) + FieldDX + (BoxH DIV 2); PH = 204;	(* default size of panel *) 
	
	PausedCol = 12;	(* colour (!!!) of mine field while paused *)
	
	(* UpdateMsg ids *)
	DrawFields* = 0; Time* = 1; Flag* = 2; DrawAll* = 3;
	
	(* mine box state ids *)
	CoveredUp* = 1; Neutral* = 2; FlagSet* = 3; NotSure* = 4;
	FalseSet* = 5; NotFound* = 6;
	Bombe* = -1;

	(* mouse buttons *)
	Left = 2; Middle = 1; Right = 0;

TYPE
	(* data type to control a single mine box *)
	Area = RECORD
		state*: SHORTINT;	(* see mine box state ids *)
		mines*: SHORTINT;	(* number of mines in the neighbothood or 'Bombe' if it's a bombe*)
	END;

	(* abstract gadget (model), which holds the game's state *)
	Field* = POINTER TO FieldDesc;
	FieldDesc* = RECORD (Gadgets.ObjDesc)
		area* : ARRAY MaxFieldW,MaxFieldH OF Area;	(* the play field in its maximum size *)
		W, H : INTEGER;													(* actual number of boxes (actual size of mine field) *)
		mines : INTEGER;													(* total number of mines *)
		time : LONGINT;													(* time since first action on the field *)
		NrToGo : INTEGER;												(* number of flags to be set *)
		NrFound : INTEGER;												(* number of mines marked by a flag (found) *)
		NrCovered : INTEGER;											(* number of boxes still covered *)
		pause : BOOLEAN;
		over : BOOLEAN;
	END;

	(* displayable gadget *)
	Frame* = POINTER TO FrameDesc;
	FrameDesc* = RECORD (Gadgets.FrameDesc)
	END;
	
	MinePanel* = POINTER TO MinePanelDesc;
	MinePanelDesc* = RECORD (Panels.PanelDesc) 
	END;
	
	(* data structure to hold the coords of the modified boxes during last action on the field *)
	Coords = POINTER TO CoordsDesc;
	CoordsDesc = ARRAY (MaxFieldW*MaxFieldH + 1) * 2 OF SHORTINT; 

	(* message sent by the model to inform its views *)
	UpdateMsg* = RECORD (Display.FrameMsg)
		id*: INTEGER;				(* see UpdateMsg ids *)
		obj*: Objects.Object;	(* model itself *)
		coords*: Coords;			(* see Coords *)
	END;

	(* message sent by the timer-task *)
	NotifyMsg* = RECORD (Display.FrameMsg)
		dt*: LONGINT;	(* time difference since last message *)
	END;


(*	----------------------------	global variables	----------------------------	*)

VAR
	seek: LONGINT;			(* used in procedure Random *)
	task: Oberon.Task;		(* timer *)
	lastTime: LONGINT;

	changedFields: Coords;	(* global array to improve performance *)
	curArrayPos: INTEGER;	(* index to changedFields (needs to be global. why? see below) *)
	
	MineCols: ARRAY 9 OF INTEGER;	(* array of very pretty colours (or colors for fairness) *)
	
	font: Fonts.Font;
	
	flagDesc1, flagDesc2, mineDesc: ARRAY 11 OF SET;
	flag1,flag2, mine: Display.Pattern;	(* guess what these variables are for !?! *)

(*	---------------------------- ----------------------------	*)
	
PROCEDURE Random( z : INTEGER) : INTEGER;
(* a small and fast random generator (selfmade :-) ) *)
BEGIN
	seek:= (((seek-1) * 17) MOD 131071);
	RETURN SHORT(seek MOD z)
END Random;

PROCEDURE * Timer(me: Oberon.Task);
(* may I introduce you to: THE TIMER *)
VAR N: NotifyMsg;
BEGIN
	N.dt:= Oberon.Time()- lastTime;
	Objects.Stamp(N); N.F:= NIL; Display.Broadcast(N);
	lastTime := me.time;
	me.time := Oberon.Time() + Input.TimeUnit
END Timer;


(*	----------------------------	procedures to control the game itself	----------------------------	*)

PROCEDURE InitField*(F: Field; w, h, m: INTEGER; pause: BOOLEAN);
VAR i,j,x,y: INTEGER; p: LONGINT;
BEGIN
	p:= ENTIER(w * h * 0.7); IF m > p THEN m:= SHORT(p) END;	(* 30% of the field should be mine(d)less *)
	F.W:= w; F.H:= h; F.mines:= m;
	F.time:= -1;
	F.pause:= pause;
	F.over:= FALSE;
	F.NrToGo:= m;
	F.NrFound:= 0;
	F.NrCovered:= F.W * F.H;
	
	(* clear the mine boxes *)
	FOR x:= 0 TO F.W-1 DO
		FOR y:= 0 TO F.H -1 DO
			F.area[x,y].state:= Neutral;
			F.area[x,y].mines:= 0;
		END
	END;
	
	(* Operation Dessert Storm -> place the mines *)
	i:= 0;
	REPEAT
		x:= Random(F.W); y:= Random(F.H);
		IF F.area[x,y].mines # Bombe THEN
			F.area[x,y].mines:= Bombe;
			INC(i)
		END
	UNTIL i = F.mines;
	
	(* give those poore little soldiers a hint and count the mines in the neighbourhood
		("Hey, how many mines live in your neighbourhood?") *)
	FOR x:= 0 TO F.W-1 DO
		FOR y:= 0 TO F.H-1 DO
			IF F.area[x,y].mines # Bombe THEN
				FOR i:= x-1 TO x+1 DO
					FOR j:= y-1 TO y+1 DO
						IF (i >= 0) & (i < F.W) & (j >= 0) & (j < F.H) THEN
							IF F.area[i,j].mines = Bombe THEN INC(F.area[x,y].mines) END
						END
					END
				END
			END
		END
	END
END InitField;

PROCEDURE SetPause(F: Field; b: BOOLEAN);
(* to simple to loose time commenting this *)
BEGIN
	IF ~F.over THEN F.pause:= b END
END SetPause;

PROCEDURE TogglePause*(F: Field);
(* notice: this is a global procedure. So we should comment it, but we don't. We're too lazy! *)
BEGIN
	SetPause(F, ~F.pause)
END TogglePause;

PROCEDURE GetTime*(F: Field; VAR t: LONGINT);
(* hmmm... *)
BEGIN t:= F.time
END GetTime;

PROCEDURE GetNrToGo*(F: Field; VAR nr: INTEGER);
BEGIN nr:= F.NrToGo
END GetNrToGo;

PROCEDURE IsOver*(F: Field) : BOOLEAN;
BEGIN RETURN F.over
END IsOver;

PROCEDURE InsertXY(x,y : INTEGER);
(* inserts the given coords into the global array *)
VAR i: INTEGER;
BEGIN
	(* check if x, y are already in array *)
	i:= 0;
	WHILE i < curArrayPos DO
		IF (x = changedFields[i]) & (y = changedFields[i+1]) THEN RETURN END;
		INC(i, 2)
	END;
	
	(* no -> insert them *)
	changedFields[curArrayPos]:= SHORT(x); INC(curArrayPos);
	changedFields[curArrayPos]:= SHORT(y); INC(curArrayPos)
END InsertXY;

PROCEDURE GameOver(F: Field);
(* sets F.over to TRUE, covers up remaining boxes and marks flags, which were set wrong *)
VAR x,y: INTEGER; state: SHORTINT; U: UpdateMsg;
BEGIN
	F.over:= TRUE;
	curArrayPos:= 0;
	FOR x:= 0 TO F.W-1 DO
		FOR y:= 0 TO F.H-1 DO
			state:= F.area[x,y].state;
			InsertXY(x, y);
			IF ((state = NotSure) OR (state = Neutral)) & (F.area[x,y].mines = Bombe) THEN
				F.area[x,y].state:= NotFound
			ELSIF (state = FlagSet) & (F.area[x,y].mines # Bombe) THEN
				F.area[x,y].state:= FalseSet
			ELSIF (F.NrFound = F.mines) & (state # CoveredUp) & (F.area[x,y].mines # Bombe) THEN
				F.area[x,y].state:= CoveredUp
			END
		END
	END;
	(* make sure all the views show the correct state *)
	U.id:= Flag; U.res:= -1; U.obj:= F; U.F:= NIL; Objects.Stamp(U); Display.Broadcast(U);
	U.id:= Time; U.res:= -1; U.obj:= F; U.F:= NIL; Objects.Stamp(U); Display.Broadcast(U)
END GameOver;

PROCEDURE DoCoverUp(F: Field; x,y: INTEGER; normal: BOOLEAN);
(* covers up the field starting at box (x, y) *)
VAR i,j, count: INTEGER;
	
	PROCEDURE CoverUpBox(x, y: INTEGER);
	(* covers up a single mine box and does some checks (game over, ..) *)
	VAR i,j,x1,y1: INTEGER;
	BEGIN
		F.area[x,y].state:= CoveredUp;
		DEC(F.NrCovered);
		InsertXY(x,y);

		(* if the first action is covering up a field, make sure there is no mine *)
		IF F.time < 0 THEN
			IF F.area[x,y].mines = Bombe THEN
				(* find a new box (without a mine) *)
				REPEAT x1:= Random(F.W); y1:= Random(F.H) UNTIL F.area[x1,y1].mines # Bombe;
				F.area[x1,y1].mines:= Bombe;
				(* inc nr. of mines in the new neighbouhood *)
				FOR i:= x1-1 TO x1+1 DO
					FOR j:= y1-1 TO y1+1 DO
						IF (i >= 0) & (i < F.W) & (j >= 0) & (j < F.H) THEN
							IF F.area[i,j].mines # Bombe THEN INC(F.area[i,j].mines) END
						END
					END
				END;
				(* dec nr. of mines in the old neighbourhood *)
				F.area[x,y].mines:= 1;
				FOR i:= x-1 TO x+1 DO
					FOR j:= y-1 TO y+1 DO
						IF (i >= 0) & (i < F.W) & (j >= 0) & (j < F.H) THEN
							IF F.area[i,j].mines = Bombe THEN INC(F.area[x,y].mines)
							ELSE DEC(F.area[i,j].mines)
							END
						END
					END
				END
			END;
			(* finally set time to zero, so the game can start *)
			F.time:= 0
		END;
		
		(* and now some checks
			1.	droped on a mine? -> game over
			2.	are all boxes without a mine covered up? -> game over *)
		IF F.area[x,y].mines= Bombe THEN GameOver(F)
		ELSIF F.NrCovered = F.mines THEN
			FOR i:= 0 TO F.W-1 DO
				FOR j:= 0 TO F.H-1 DO
					IF F.area[i,j].state # CoveredUp THEN
						F.area[i,j].state:= FlagSet;
						InsertXY(i,j)
					END
				END
			END;
			F.NrFound:= F.mines;
			F.NrToGo:= 0;
			GameOver(F);
		END
	END CoverUpBox;
	
BEGIN
	IF normal THEN
		(* precondition: box has to be in neutral state (covered but no flag or question mask is set).
			If all the neighbouring boxes have no mine, cover these boxes up and check them, too. *)
		IF F.area[x,y].state = Neutral THEN
			CoverUpBox(x, y);
			IF F.area[x,y].mines= 0 THEN
				FOR i:= x-1 TO x+1 DO
					FOR j:= y-1 TO y+1 DO
						IF (i >= 0) & (i < F.W) & (j >= 0) & (j < F.H) THEN DoCoverUp(F,i,j,TRUE) END
					END
				END
			END
		END
	ELSE	(* extended cover up *)
		(* precondition: box has to be in CoveredUp state and there are the exact number of flags set on the
				neighbouring boxes. It covers up the remaining (covered) boxes and repeats the check on these, too. *)
		IF F.area[x,y].state = CoveredUp THEN
			(* count flags in neighbourhood *)
			count:= 0;
			FOR i:= x-1 TO x+1 DO
				FOR j:= y-1 TO y+1 DO
					IF (i >= 0) & (i < F.W) & (j >= 0) & (j < F.H) & (F.area[i,j].state = FlagSet) THEN INC(count) END
				END
			END;
			IF count = F.area[x,y].mines THEN
				FOR i:= x-1 TO x+1 DO
					FOR j:= y-1 TO y+1 DO
						IF (i >= 0) & (i < F.W) & (j >= 0) & (j < F.H) &
							((F.area[i,j].state = Neutral) OR (F.area[i,j].state = NotSure)) THEN
							CoverUpBox(i, j);
							IF F.area[i,j].mines # Bombe THEN DoCoverUp(F,i,j,FALSE) END
						END
					END
				END
			END
		END
	END
END DoCoverUp;

PROCEDURE CoverUp*(F: Field; x,y: INTEGER; normal: BOOLEAN);
(* does a first check, if it is generally allowed to perform an action on the field *)
VAR U: UpdateMsg;
BEGIN
	IF (x >= F.W) OR (y >= F.H) OR F.over OR F.pause THEN RETURN END;
	
	(* reset the index of array changedFields *)
	curArrayPos:= 0;
	DoCoverUp(F, x, y, normal);
	
	(* set end mark in array changedFields *)
	InsertXY(-1,-1);
	
	(* inform the views *)
	U.id:= DrawFields; U.obj:= F; Objects.Stamp(U); U.F:= NIL; U.coords:= changedFields; Display.Broadcast(U)
END CoverUp;
		
PROCEDURE ToggleState*(F: Field; x,y: INTEGER);
(* preforms action due to a right mouse click *)
VAR state: SHORTINT; U: UpdateMsg;
BEGIN
	(* return if performing the action is not allowed *)
	IF (x >= F.W) OR (y >= F.H) OR F.over OR F.pause THEN RETURN END;
	
	(* this action works only on covered boxes *)
	IF F.area[x,y].state # CoveredUp THEN
		IF F.time < 0 THEN F.time:= 0 END;	(* if not already stated (F.time >= 0) start game know *)
		
		(* toggle state: Neutral -> FlagSet -> NotSure -> Neutral *)
		state:= F.area[x,y].state;
		state:= ((state-1) MOD 3) + 2;
		F.area[x,y].state:= state;
		
		(* ajust state variables depending on new state *)
		IF state = FlagSet THEN
			IF F.NrToGo = 0 THEN F.area[x,y].state:= state+1	(* all flags already set, so toggle to NotSure state *)
			ELSE
				DEC(F.NrToGo);
				IF F.area[x,y].mines = Bombe THEN INC(F.NrFound) END;
				IF F.NrFound = F.mines THEN GameOver(F) END
			END
		ELSIF state = NotSure THEN
			INC(F.NrToGo); 
			IF F.area[x,y].mines = Bombe THEN DEC(F.NrFound) END
		END;
		
		(* update views (update flag counter just if necessary) *)
		IF ~F.over THEN
			IF (state = NotSure) OR ((F.area[x,y].state = FlagSet) & (state = FlagSet)) THEN
				U.id:= Flag; U.F:= NIL; U.obj:= F; Objects.Stamp(U);
				Display.Broadcast(U);
			END;
			curArrayPos:= 0;
			InsertXY(x,y);
		END;
		U.id:= DrawFields; U.F:= NIL; U.obj:= F; Objects.Stamp(U);
		InsertXY(-1,-1); U.coords:= changedFields;
		Display.Broadcast(U)
	END
END ToggleState;


(*	----------------------------	procedures to control the abstract gadget	-----------------------------	*)

PROCEDURE FieldAttr(F: Field; VAR M: Objects.AttrMsg);
(* handles Objects.AttrMsg *)
VAR i: LONGINT;
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class:= Objects.String; COPY("MineSweeper.NewField", M.s); M.res:= 0
		ELSIF M.name = "Width" THEN M.class:= Objects.Int; M.i:= F.W;  M.res:= 0
		ELSIF M.name = "Height" THEN M.class:= Objects.Int; M.i:= F.H;  M.res:= 0
		ELSIF M.name = "Mines" THEN M.class:= Objects.Int; M.i:= F.mines;  M.res:= 0
		ELSIF M.name = "Pause" THEN M.class:= Objects.Bool; M.b:= F.pause; M.res:= 0;
		ELSE Gadgets.objecthandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		(* each set causes a initialization of the field (except pause). An Display.UpdateMsg is allways sent by the sender of the
			AttrMsg (eg. Inspector after applying all attributes), so the object must not send an Display.UpdateMsg itself *)
		IF M.class = Objects.Int THEN i:= M.i
		ELSIF M.class = Objects.String THEN Strings.StrToInt(M.s, i)
		ELSE i:= -1
		END;
		IF (M.name = "Width") & (i >= MinFieldW ) & (i <= MaxFieldW) THEN InitField(F, SHORT(i), F.H, F.mines, F.pause); M.res:= 0
		ELSIF (M.name = "Height") & (i >= MinFieldH) & (i <= MaxFieldH) THEN InitField(F, F.W, SHORT(i), F.mines, F.pause); M.res:= 0
		ELSIF (M.name = "Mines") & (i >= MinMines) & (i <= MaxMines) THEN InitField(F, F.W, F.H, SHORT(i), F.pause); M.res:= 0
		ELSIF (M.name = "Pause") THEN
			IF M.class = Objects.String THEN Strings.StrToBool(M.s,M.b) END;
			SetPause(F, M.b); M.res:= 0
		ELSE Gadgets.objecthandle(F, M);
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("Width"); M.Enum("Height"); M.Enum("Mines"); M.Enum("Pause"); Gadgets.objecthandle(F, M)
	END
END FieldAttr;

PROCEDURE CopyField*(VAR M: Objects.CopyMsg; from, to: Field);
(* handles Objects.CopyMsg *)
BEGIN
	InitField(to, from.W, from.H, from.mines, FALSE);
	Gadgets.CopyObject(M, from, to)
END CopyField;

PROCEDURE FieldHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
(* handler of the abstract game gadget (model) *)
VAR F0: Field; w, h, mines: INTEGER; U: UpdateMsg;
BEGIN
	WITH F: Field DO
		IF M IS Objects.AttrMsg THEN
			FieldAttr(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN	(* we already got this message *)
					M.obj:= F.dlink;
				ELSE
					(* make a new instance of this gadget *)
					NEW(F0);
					F.stamp:= M.stamp; F.dlink:= F0;	(* remember new object and message stamp *)
					CopyField(M, F, F0); M.obj:= F0
				END
			END
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Files.WriteInt(M.R, F.W); Files.WriteInt(M.R, F.H); Files.WriteInt(M.R, F.mines);
					Gadgets.objecthandle(F, M);
				ELSIF M.id = Objects.load THEN
					Files.ReadInt(M.R, w); Files.ReadInt(M.R, h); Files.ReadInt(M.R, mines);
					Gadgets.objecthandle(F, M);
					InitField(F, w, h, mines, FALSE);
				END
			END
		ELSIF M IS NotifyMsg THEN
			(* message from THE TIMER *)
			WITH M: NotifyMsg DO
				IF (F.time >= 0) & ~F.over & ~F.pause & (M.stamp # F.stamp) THEN
					(* increment time only if game is running and message arrives for the first time (M.stamp) *)
					F.stamp:= M.stamp;
					F.time:= F.time + M.dt;
					(* inform all views of time change *)
					U.id:= Time; U.F:= NIL; U.obj:= F; Objects.Stamp(U); U.res:= -1;
					Display.Broadcast(U)
				END
			END
		ELSE
			Gadgets.objecthandle(F, M);
		END
	END
END FieldHandler;


(*	----------------------------	procedures to handle views (disp. gadget)	----------------------------	*)

PROCEDURE DisplayToField(x, y, w, h, pX, pY: INTEGER; VAR fieldX, fieldY: INTEGER);
(* convert screen coordinates to array coordinates.
	x, y, w, h, pX, pY are given in absolute screen coordinates. fieldX, fieldY relative to top-left corner *)
BEGIN
	pX:= pX - x - FieldDX;
	IF pX >= 0 THEN fieldX:= pX DIV BoxW
	ELSE fieldX:= -1
	END;
	pY:= y + h - FieldDY - 1 - pY;
	IF pY >= 0 THEN fieldY:= pY DIV BoxH
	ELSE fieldY:= -1
	END
END DisplayToField;

PROCEDURE FieldToDisplay(x, y, w, h, pX, pY: INTEGER; VAR dispX, dispY: INTEGER);
(* converts array coordinates to absolute screen coordinates *)
BEGIN
	dispX:= pX * BoxW + x + FieldDX;
	dispY:= y + h - FieldDY - (pY +1) * BoxH 
END FieldToDisplay;

PROCEDURE DrawTime(F: Frame; M: Display3.Mask; x, y, w, h: INTEGER);
(* draws modles time in time area *)
VAR t: LONGINT; oldX, oldY: INTEGER; obj: Objects.Object;
BEGIN
	IF (F.obj = NIL) OR ~(F.obj IS Field) THEN t:= 0
	ELSE GetTime(F.obj(Field),t)
	END;
	
	(* draw background and border of area *)
	x:= x + TimeDX; y:= y + h - TimeDY  - TimeH;
	Oberon.RemoveMarks(x, y, TimeW, TimeH);
	Display3.FilledRect3D(M, Display3.bottomC, Display3.topC, Display3.groupC, x, y, TimeW, TimeH, 1, Display.replace);
	Display3.Rect3D(M, Display3.topC, Display3.bottomC, x+1, y+1, TimeW-2, TimeH-2, 1, Display.replace);
	
	(* draw title *)
	oldX:= x; oldY:= y;
	y:= y + ((TimeH - 10) DIV 2);
	Display3.String(M, TimeCol, x+4, y, font, "Time:", Display3.textmode);
	IF t >= 0 THEN t:= t DIV Input.TimeUnit
	ELSE t:= 0
	END;
	
	(* draw number *)
	x:= x + TimeW - 4;
	REPEAT
		font.GetObj(font, ORD("0") + SHORT(t MOD 10), obj);
		WITH obj: Fonts.Char DO
			DEC(x, obj.dx); t:= t DIV 10;
			Display3.CopyPattern(M, TimeCol, obj.pat, x+obj.x, y+obj.y, Display3.textmode)
		END
	UNTIL t = 0;
	
	(* draw selectPattern if gadget is selected *)
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(M, Display3.white, Display3.selectpat, oldX, oldY, oldX, oldY, TimeW, TimeH, Display.paint)
	END
END DrawTime;

PROCEDURE DrawCount(F: Frame; M: Display3.Mask; x, y, w, h: INTEGER);
(* displays number of flags left to set *)
VAR oldX, oldY, c: INTEGER; obj: Objects.Object;
BEGIN
	IF (F.obj = NIL) OR ~(F.obj IS Field) THEN c:= 0
	ELSE GetNrToGo(F.obj(Field), c)
	END;
	
	(* draw background and border *)
	x:= x + CountDX; y:= y + h - CountDY  - CountH;
	Oberon.RemoveMarks(x, y, CountW, CountH);
	Display3.FilledRect3D(M, Display3.bottomC, Display3.topC, Display3.groupC, x, y, CountW, CountH, 1, Display.replace);
	Display3.Rect3D(M, Display3.topC, Display3.bottomC, x+1, y+1, CountW-2, CountH-2, 1, Display.replace);
	
	(* draw title *)
	oldX:= x; oldY:= y;
	y:= y + ((CountH - 10) DIV 2);
	Display3.String(M, CountCol, x+4, y, font, "Flags:", Display3.textmode);
	
	(* draw number *)
	x:= x + CountW - 4;
	REPEAT
		font.GetObj(font, ORD("0") + (c MOD 10), obj);
		WITH obj: Fonts.Char DO
			DEC(x, obj.dx); c:= c DIV 10;
			Display3.CopyPattern(M, CountCol, obj.pat, x+obj.x, y+obj.y, Display3.textmode)
		END
	UNTIL c = 0;
	
	(* draw selectPattern if gadget is selected *)
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(M, Display3.white, Display3.selectpat, oldX, oldY, oldX, oldY, CountW, CountH, Display.paint)
	END
END DrawCount;

PROCEDURE DrawField(F: Frame; M: Display3.Mask; x, y, w, h, pX, pY: INTEGER; paused: BOOLEAN);
(* draws a single mine box, depending on its state  *)
VAR fX, fY, state, mines: INTEGER; obj: Objects.Object;
BEGIN
	IF (F.obj = NIL) OR ~(F.obj IS Field) THEN RETURN END;
	Oberon.RemoveMarks(x, y, w, h);
	FieldToDisplay(x, y, w, h, pX, pY, fX, fY);
	state:= F.obj(Field).area[pX, pY].state;
	
	IF paused THEN	(* paused *)
		Display3.ReplConst(M, PausedCol, fX, fY, BoxW, BoxH, Display.replace);
		
	ELSIF state =CoveredUp  THEN	(* draw number of neighboring mines or a bombe (depends on area[].mines) *)
		Display3.FilledRect3D(M, Display3.bottomC, Display3.topC,  Display3.groupC, fX, fY, BoxW, BoxH, 1, Display.replace);
		mines:= F.obj(Field).area[pX, pY].mines;
		IF  mines = Bombe THEN
			Display3.ReplConst(M, Display3.red, fX+1, fY+1, BoxW-2, BoxH-2, Display.replace);
			Display3.CopyPattern(M, Display3.black, mine, fX+4, fY+3, Display.paint)
		ELSIF mines > 0 THEN
			font.GetObj(font, ORD("0")+mines, obj);
			WITH obj: Fonts.Char DO
				Display3.CopyPattern(M, MineCols[mines], obj.pat, fX+((BoxW-obj.w) DIV 2), fY+((BoxH - obj.h) DIV 2), Display.paint)
			END
		END
		
	ELSE	(* box is covered, draw appropriate symbol, depending on area[].state *)
		Display3.FilledRect3D(M, Display3.topC, Display3.bottomC, Display3.groupC, fX, fY, BoxW, BoxH, 1, Display.replace);
		IF state = FalseSet THEN
			Display3.CopyPattern(M, Display3.black, mine, fX+4, fY+3, Display.paint);
			Display3.Line(M, Display3.red, Display.solid, fX+1, fY+1, fX+BoxW-2, fY+BoxH-2, 1, Display.replace);
			Display3.Line(M, Display3.red, Display.solid, fX+1, fY+BoxH-2, fX+BoxW-2, fY+1, 1, Display.replace)
		ELSIF state = NotFound THEN
			Display3.CopyPattern(M, Display3.black, mine, fX+4, fY+3, Display.paint)
		ELSE
			IF state = FlagSet THEN
				Display3.CopyPattern(M, Display3.red, flag2, fX+5, fY+3, Display.paint);
				Display3.CopyPattern(M, Display3.black, flag1, fX+5, fY+3, Display.paint)
			ELSIF state = NotSure THEN
				font.GetObj(font, ORD("?"), obj);
				WITH obj: Fonts.Char DO
					Display3.CopyPattern(M, Display3.black, obj.pat, fX+((BoxW-obj.w) DIV 2), fY+((BoxH - obj.h) DIV 2), Display.paint)
				END
			END
		END
	END;
	
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(M, Display3.white, Display3.selectpat, fX, fY, fX, fY, BoxW, BoxH, Display.paint)
	END
END DrawField;
		
PROCEDURE RestoreFrame(F: Frame; M: Display3.Mask; x, y, w, h: INTEGER);
(* handles a redraw of the whole view *)
VAR A: Objects.AttrMsg; i, j, fW, fH: INTEGER;
BEGIN
	DrawTime(F, M, x, y, w, h);
	DrawCount(F, M, x, y, w, h);
	IF (F.obj # NIL) & (F.obj IS Field) THEN 
		A.id:= Objects.get;
		A.name:= "Width"; F.obj.handle(F.obj, A); fW:= SHORT(A.i);
		A.name:= "Height"; F.obj.handle(F.obj, A); fH:= SHORT(A.i);
		A.name:= "Pause"; F.obj.handle(F.obj, A);
		FOR i:= 0 TO fW - 1 DO
			FOR j:= 0 TO fH - 1 DO
				DrawField(F, M, x, y, w, h, i, j, A.b)
			END
		END
	END;
	
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
	END
END RestoreFrame;

PROCEDURE Print(F: Frame; VAR M: Display.DisplayMsg);
(* handles aprint request. Does the same as DrawTime, DrawCounts and DrawField.
	Display patterns have to be converted to Printer patterns by the procedure Printer3.NewPattern *)
VAR R: Display3.Mask; X, Y, W, H, x, y, bw, bh, one, mines, state, c, i, j: INTEGER; t: LONGINT;
	A: Objects.AttrMsg; str: ARRAY 8 OF CHAR; obj: Objects.Object;

	PROCEDURE P(x: INTEGER): INTEGER;
	(* convert display coords to printer coords *)
	BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
	END P;

BEGIN
	IF (F.obj # NIL) & (F.obj IS Field) THEN
		GetTime(F.obj(Field),t); IF t > 0 THEN t:= t DIV Input.TimeUnit ELSE t:= 0 END;
		GetNrToGo(F.obj(Field), c)
	ELSE
		c:= 0; t:= 0;
	END;
	Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, R);
	one:= P(1);
	X:= M.x; Y:= M.y + P(F.H);
	
	(* draw time *)
	x:= X + P(TimeDX); y:= Y - P(TimeDY + TimeH);
	Printer3.FilledRect3D(R, Display3.bottomC, Display3.topC, Display3.groupC, x, y, P(TimeW), P(TimeH), one, Display.replace);
	Printer3.Rect3D(R, Display3.topC, Display3.bottomC, x+one, y+one, P(TimeW-2), P(TimeH-2), one, Display.replace);
	y:= y + P((TimeH - 8) DIV 2);
	Printer3.String(R, TimeCol, x+6, y, font, "Time:", Display3.textmode);
	x:= x + P(TimeW) DIV 2;
	Strings.IntToStr(t, str);
	Printer3.CenterString(R, TimeCol, x, y, P(TimeW) DIV 2, P(12), font, str, Display3.textmode);
	
	(* draw number of flags remaining *)
	x:= X + P(CountDX); y:= Y - P(CountDY + CountH);
	Printer3.FilledRect3D(R, Display3.bottomC, Display3.topC, Display3.groupC, x, y, P(CountW), P(CountH), one, Display.replace);
	Printer3.Rect3D(R, Display3.topC, Display3.bottomC, x+one, y+one, P(CountW-2), P(CountH-2), one, Display.replace);
	y:= y + P((CountH - 8) DIV 2);
	Printer3.String(R, CountCol, x+6, y, font, "Flags:", Display3.textmode);
	x:= x + P(CountW) DIV 2;
	Strings.IntToStr(c, str);
	Printer3.CenterString(R, CountCol, x, y, P(CountW) DIV 2, P(12), font, str, Display3.textmode);
	
	(* draw field *)
	A.id:= Objects.get; A.class:= Objects.Int; A.name:= "Width"; A.res:= -1; F.obj.handle(F.obj, A); W:= SHORT(A.i);
	A.id:= Objects.get; A.class:= Objects.Int; A.name:= "Height"; A.res:= -1; F.obj.handle(F.obj, A); H:= SHORT(A.i);
	A.id:= Objects.get; A.class:= Objects.Bool; A.name:= "Pause"; A.res:= -1; F.obj.handle(F.obj, A);
	IF A.b THEN
		Display3.ReplConst(R, PausedCol, X+ P(FieldDX), Y - P(FieldDY + H*BoxH), P(W*BoxW), P(H*BoxH), Display.replace)
	ELSE
		bw:= P(BoxW); bh:= P(BoxH);
		y:= Y - P(FieldDY + BoxH);
		FOR i:= 0 TO H-1 DO
			x:= X+ P(FieldDX);
			FOR j:= 0 TO W-1 DO
				state:= F.obj(Field).area[j, i].state;
				IF state =CoveredUp  THEN
					Printer3.FilledRect3D(R, Display3.bottomC, Display3.topC,  Display3.groupC, x, y, bw, bh, one, Display.replace);
					mines:= F.obj(Field).area[j, i].mines;
					IF  mines = Bombe THEN
						Printer3.ReplConst(R, Display3.red, x+one, y+one, P(BoxW-2), P(BoxH-2), Display.replace);
						(* Printer3.CopyPattern(R, Display3.black, Printer3.NewPattern(mine), x+P(4), y+P(3), Display.paint) *)
					ELSIF mines > 0 THEN
						font.GetObj(font, ORD("0")+mines, obj);
						(* WITH obj: Fonts.Char DO
							Printer3.CopyPattern(R, MineCols[mines], Printer3.NewPattern(obj.pat),
								x+P((BoxW-obj.w) DIV 2), y+P((BoxH -obj.h) DIV 2), Display.paint)
						END *)
					END
				ELSIF state = FalseSet THEN
					Printer3.FilledRect3D(R, Display3.topC, Display3.bottomC, Display3.groupC, x, y, bw, bh, one, Display.replace);
					(* Printer3.CopyPattern(R, Display3.black, Printer3.NewPattern(mine), x+P(4), y+P(3), Display.paint); *)
					Printer3.Line(R, Display3.red, Display.solid, x+one, y+one, x+P(BoxW-2), y+P(BoxH-2), one, Display.replace);
					Printer3.Line(R, Display3.red, Display.solid, x+one, y+P(BoxH-2), x+P(BoxW-2), y+one, one, Display.replace)
				ELSIF state = NotFound THEN
					Printer3.FilledRect3D(R, Display3.topC, Display3.bottomC, Display3.groupC, x, y, bw, bh, one, Display.replace);
					(* Printer3.CopyPattern(R, Display3.black, Printer3.NewPattern(mine), x+P(4), y+P(3), Display.paint); *)
				ELSE
					Printer3.FilledRect3D(R, Display3.topC, Display3.bottomC, Display3.groupC, x, y, bw, bh, one, Display.replace);
					IF state = FlagSet THEN
						(* Printer3.CopyPattern(R, Display3.red, Printer3.NewPattern(flag2), x+P(5), y+P(3), Display.paint); *)
						(* Printer3.CopyPattern(R, Display3.black, Printer3.NewPattern(flag1), x+P(5), y+P(3), Display.paint) *)
					ELSIF state = NotSure THEN
						font.GetObj(font, ORD("?"), obj);
						(* WITH obj: Fonts.Char DO
							Printer3.CopyPattern(R, Display3.black, Printer3.NewPattern(obj.pat),
								x+P((BoxW-obj.w) DIV 2), y+P((BoxH-obj.h) DIV 2), Display.paint)
						END *)
					END
				END;
				INC(x, P(BoxW))
			END;
			DEC(y, P(BoxH))
		END
	END
END Print;

PROCEDURE TrackLeftRight(F: Frame; R: Display3.Mask; x, y, w, h: INTEGER; VAR M: Oberon.InputMsg);
(* handles left or right mouse clicks *)
VAR keysum: SET; W, H, oldX, oldY, fX, fY, dX, dY, state: INTEGER; A: Objects.AttrMsg; right: BOOLEAN;
BEGIN
	keysum:= M.keys;
	A.id:= Objects.get; A.class:= Objects.Int; A.name:= "Width"; A.res:= -1; F.obj.handle(F.obj, A); W:= SHORT(A.i);
	A.id:= Objects.get; A.class:= Objects.Int; A.name:= "Height"; A.res:= -1; F.obj.handle(F.obj, A); H:= SHORT(A.i);
	A.id:= Objects.get; A.class:= Objects.Bool; A.name:= "Pause"; A.res:= -1; F.obj.handle(F.obj, A);
	DisplayToField(x, y, w, h, M.X, M.Y, dX, dY);
	
	(* track mouse just when mouse pointer is in mine field and game is not over, nor is it paused *)
	IF ~A.b & ~IsOver(F.obj(Field)) & (dX >= 0) & (dX < W) & (dY >= 0) & (dY < H) THEN
		right:= (keysum = {Right});
		state:= F.obj(Field).area[dX, dY].state;
		(* draw box in a pressed look, so one can see which box will be affected when releasing the mouse button *) 
		IF (right & (state # CoveredUp)) OR (state = Neutral) THEN
			FieldToDisplay(x, y, w, h, dX, dY, fX, fY);
			Display3.Rect3D(R, Display3.bottomC, Display3.topC, fX, fY, BoxW, BoxH, 1, Display.replace);
			oldX:= fX; oldY:= fY
		ELSE
			oldX:= -1; oldY:= -1
		END;
		
		(* tracking the mouse while mouse buttons are pressed *)
		REPEAT
			Input.Mouse(M.keys, M.X, M.Y); keysum:= keysum + M.keys;
			Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y);
			
			(* redraw pressed box  and draw a next pressed box, if necessary *)
			Oberon.RemoveMarks(x, y, w, h);
			DisplayToField(x, y, w, h, M.X, M.Y, dX, dY);
			IF dX < 0 THEN dX:= 0 
			ELSIF dX >= W THEN dX:= W-1
			END;
			IF dY < 0 THEN dY:= 0 
			ELSIF dY >= H THEN dY:= H-1
			END;
			state:= F.obj(Field).area[dX, dY].state;
			IF (right & (state # CoveredUp)) OR (state = Neutral) THEN FieldToDisplay(x, y, w, h, dX, dY, fX, fY)
			ELSE fX:= -1; fY:= -1;
			END;
			IF (oldX # fX) OR (oldY # fY) THEN
				IF oldX >= 0 THEN Display3.Rect3D(R, Display3.topC, Display3.bottomC, oldX, oldY, BoxW, BoxH, 1, Display.replace) END;
				IF fX >= 0 THEN Display3.Rect3D(R, Display3.bottomC, Display3.topC, fX, fY, BoxW, BoxH, 1, Display.replace) END;
				oldX:= fX; oldY:= fY
			END
		UNTIL (M.keys = {});

		(* handle mouse click *)
		IF (keysum = {Left}) THEN
			CoverUp(F.obj(Field), dX, dY, TRUE)
		ELSIF (keysum = {Right}) THEN
			ToggleState(F.obj(Field), dX, dY)
		ELSIF oldX >= 0 THEN (* restore pressed box *)
			Display3.Rect3D(R, Display3.topC, Display3.bottomC, oldX, oldY, BoxW, BoxH, 1, Display.replace)
		END;
		
		(* set M.res to zero, to indicate we handled this message. If M.res is -1, a standard behaviour is assumed:
			set carret on left mouse click or select object on right mouse click *)
		M.res:= 0
	END
END TrackLeftRight;

PROCEDURE TrackMiddle(F: Frame; R: Display3.Mask; x, y, w, h: INTEGER; VAR M: Oberon.InputMsg);
(* handles a middle mouse click *)
VAR keysum: SET; dX, dY: INTEGER;
BEGIN
	(* track the mouse pointer *)
	keysum:= M.keys;
	REPEAT
		Input.Mouse(M.keys, M.X, M.Y); keysum:= keysum + M.keys;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y);
	UNTIL M.keys = {};
	
	(* check if mouse pointer is still in the gadgets active area (not in its border or edge).
		compute the mine box, which will be affected and do a extended CoverUp on this box *)
	IF Gadgets.InActiveArea(F, M) & (keysum = {Middle}) THEN
		DisplayToField(x, y, w, h, M.X, M.Y, dX, dY);
		IF (dX >= 0) & (dY >= 0) THEN CoverUp(F.obj(Field), dX, dY, FALSE) END;
		M.res:= 0;
	END
END TrackMiddle;

PROCEDURE FrameAttr(F: Frame; VAR M: Objects.AttrMsg);
(* handles Objects.AttrMsg. Each object has to set at least the Gen attribute *)
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class:= Objects.String; COPY("MineSweeper.NewView", M.s); M.res:= 0
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		Gadgets.framehandle(F, M);
	ELSIF M.id = Objects.enum THEN
		Gadgets.framehandle(F, M)
	END
END FrameAttr;

PROCEDURE CopyFrame*(VAR M: Objects.CopyMsg; from, to: Frame);
(* handles Objects.CopyMsg *)
BEGIN
	Gadgets.CopyFrame(M, from, to);
END CopyFrame;

PROCEDURE FrameHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
(* this is the view's handler *)
VAR x, y, w, h, i: INTEGER; F0: Frame; R: Display3.Mask; A: Objects.AttrMsg; Mo: Display.ModifyMsg;
BEGIN
	WITH F: Frame DO
		IF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF (M.F = NIL) OR (M.F = F) THEN	(* is message addressed to this frame ? *)
					x:= M.x + F.X; y:= M.y + F.Y; w:= F.W; h:= F.H;	(* calculate absolute display coordinates *)
					IF (M IS Gadgets.UpdateMsg) THEN
						WITH M: Gadgets.UpdateMsg DO
							(* pass this message to the model, to inform it about its update *)
							IF F.obj # NIL THEN F.obj.handle(F.obj, M) END;
							(* now update F *)
							IF  (F.obj = M.obj) & (F.stamp # M.stamp) THEN
								F.stamp:= M.stamp;
								(* check if model's field has changed its size. Change view's size if necessary *)
								IF F.obj IS Field THEN
									(* get values and compute size *)
									A.id:= Objects.get; A.name:= "Width"; F.obj.handle(F.obj, A); Mo.W:= SHORT(FieldDX + (A.i * BoxW) + (BoxW DIV 2));
									A.id:= Objects.get; A.name:= "Height"; F.obj.handle(F.obj, A); Mo.H:= SHORT((A.i + 1) * BoxH);
								ELSE
									(* if there is no MineField, change to default size *)
									Mo.W:= VW; Mo.H:= VH;
								END;
								(* if size has changed send a Display.ModifyMsg. (this lets the panel know, that we are going to
									change our size. The drawing is done when handling this Display.ModifyMsg) *)
								IF (Mo.W # F.W) OR (Mo.H # F.H) THEN
									Objects.Stamp(Mo);
									Mo.id:= Display.extend; Mo.mode:= Display.display; Mo.X:= F.X; Mo.Y:= F.Y + F.H - Mo.H;
									Mo.F:= F; Mo.dX:= 0; Mo.dY:= Mo.Y - F.Y; Mo.dW:= Mo.W - F.W; Mo.dH:= Mo.H - F.H;
									Display.Broadcast(Mo)
								ELSE
									(* no change of size -> just draw the whole view (make sure the views mask is correct) *)
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									RestoreFrame(F, R, x, y, w, h)
								END
							END
						END

					ELSIF (M IS UpdateMsg) THEN
						WITH M: UpdateMsg DO
							IF (M.stamp # F.stamp) & (M.obj = F.obj) THEN
								F.stamp:= M.stamp;
								(* make sure view's mask is correct, because we may draw some funny things *)
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								IF (M.id = Time) THEN
									DrawTime(F, R, x, y, w, h);
								ELSIF (M.id = Flag) THEN
									DrawCount(F, R, x, y, w, h);
								ELSIF (M.id = DrawFields) THEN
									A.id:= Objects.get; A.name:= "Pause"; F.obj.handle(F.obj, A);
									(* draw all boxes specified in array M.coords (remember: this array is terminated by -1) *)
									i:= 0;
									WHILE M.coords[i] # -1 DO
										DrawField(F, R, x, y, w, h, M.coords[i], M.coords[i+1], A.b);
										INC(i, 2)
									END
								ELSIF M.id = DrawAll THEN
									RestoreFrame(F, R, x, y, w, h)
								END
							END
						END
						
					ELSIF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg  DO
							IF M.device = Display.screen THEN
								IF (M.id = Display.full) OR (M.F = NIL) THEN
										Gadgets.MakeMask(F, x, y, M.dlink, R);
										RestoreFrame(F, R, x, y, w, h)
								ELSIF M.id = Display.area THEN
									(* restore area M.u, M.v, M.w, M.h, where M.u, M.v are relative (top-left) coordinates inside this frame *)
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
									RestoreFrame(F, R, x, y, w, h)
								END
							ELSIF M.device = Display.printer THEN
								Print(F, M)
							END
						END

					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							Gadgets.MakeMask(F, x, y, M.dlink, R);
							(* just handle the mouse messages *)
							IF (M.id = Oberon.track) & Gadgets.InActiveArea(F, M) & (M.keys # {}) & (F.obj # NIL) & (F.obj IS Field) THEN
								IF M.keys = {Middle} THEN TrackMiddle(F, R, x, y, w, h, M)
								ELSIF M.keys = {Left} THEN TrackLeftRight(F, R, x, y, w, h, M)
								ELSIF M.keys = {Right} THEN TrackLeftRight(F, R, x, y, w, h, M)
								END
							ELSE
								Gadgets.framehandle(F, M)
							END
						END
						
					ELSIF (F.obj # NIL) & (M IS NotifyMsg) THEN
						F.obj.handle(F.obj, M)
						
					ELSIF M IS Display.ControlMsg THEN
						(* pass this message to the model, to inform it about what happens *)
						IF F.obj # NIL THEN F.obj.handle(F.obj, M) END
	
					ELSE Gadgets.framehandle(F, M)
					END
				END
			END
			
		(* standard Object messages *)
		
		ELSIF M IS Objects.AttrMsg THEN
			FrameAttr(F, M(Objects.AttrMsg))

		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj:= F.dlink	(* copy msg arrives again *)
				ELSE	(* first time copy message arrives *)
					NEW(F0); F.stamp:= M.stamp; F.dlink:= F0; CopyFrame(M, F, F0); M.obj:= F0
				END
			END

		ELSE	(* unknown msg, standard framehandler might know it *)
			Gadgets.framehandle(F, M)
		END
	END
END FrameHandler;


(*	----------------------------	procedures to control panel gadget	-----------------------------	*)

PROCEDURE PanelAttr(F: MinePanel; VAR M: Objects.AttrMsg);
(* handles Objects.AttrMsg. Each object has to set at least the Gen attribute *)
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class:= Objects.String; COPY("MineSweeper.NewPanel", M.s); M.res:= 0
		ELSE Panels.PanelHandler(F, M)
		END
	ELSIF M.id = Objects.set THEN
		Panels.PanelHandler(F, M)
	ELSIF M.id = Objects.enum THEN
		Panels.PanelHandler(F, M)
	END
END PanelAttr;

PROCEDURE CopyPanel*(VAR M: Objects.CopyMsg; from, to: MinePanel);
(* handles Objects.CopyMsg *)
BEGIN
	Panels.CopyPanel(M, from, to);
END CopyPanel;

PROCEDURE PanelHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
(* the panels handler *)
VAR F0: MinePanel; Mo: Display.ModifyMsg;
BEGIN
	WITH F: MinePanel DO
		IF M IS Objects.AttrMsg THEN
			PanelAttr(F, M(Objects.AttrMsg))

		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj:= F.dlink	(* copy msg arrives again *)
				ELSE	(* first time copy message arrives *)
					NEW(F0); F.stamp:= M.stamp; F.dlink:= F0; CopyPanel(M, F, F0); M.obj:= F0
				END
			END

		(* check if the destination of the Display.ModifyMsg is a Mine Frame (view) and if this frame is a child of this panel. If so, change size of panel 
			according to the size of the Mine Frame *)
		ELSIF M IS Display.ModifyMsg THEN
			WITH M: Display.ModifyMsg DO
				IF (M.F # NIL) & (M.F IS Frame) & Panels.IsChild(F, M.F) THEN
					Mo.res:= -1; Objects.Stamp(Mo); Mo.F:= F; Mo.id:= Display.move; Mo.mode:= Display.display;
					Mo.X:= F.X; Mo.W:= M.X + M.W + 10; Mo.H:= -M.Y + 10;
					IF Mo.W < PW THEN Mo.W:= PW END; IF Mo.H < PH THEN Mo.H:= PH END;
					Mo.Y:= F.Y + F.H - Mo.H;
					Mo.dX:= 0; Mo.dY:= Mo.Y - F.Y; Mo.dW:= Mo.W - F.W; Mo.dH:= Mo.H - F.H;
					IF (Mo.dW # 0) OR (Mo.dH # 0) THEN
						(* change mode of msg to avoid flickering (otherwise the view will draw itself twice, because the panel
							sends an Display.UpdateMsg to all its children after modifying its size). The mode state causes the object to
							adjust its size but not to redraw itself. *)
						M.mode:= Display.state;
						Panels.PanelHandler(F, M);
						Display.Broadcast(Mo)
					ELSE
						Panels.PanelHandler(F, M)
					END
				ELSE
					Panels.PanelHandler(F, M)
				END
			END
		ELSE	(* unknown msg, panel's handler might know it *)
			Panels.PanelHandler(F, M)
		END

	END
END PanelHandler;


(*	----------------------------	procedures related to the MineSweeper document	-----------------------------	*)

PROCEDURE InsertSlider(P: Gadgets.Frame; model: Objects.Object; name: ARRAY OF CHAR; X, min, max: INTEGER);
(* inserts a vertical slider, a caption and a textfield (which displays the value of the slider). The attribute Field in visible gadgets
	determines which of the abstract gadget's (model) attribute has to be represented (made visible) by this gadget  *)
VAR s, t, c, p: Objects.Object; nolines: INTEGER; A: Objects.AttrMsg; C: Display.ConsumeMsg;
BEGIN
	(* get new instances of needed gadgets *)
	p:= Gadgets.CreateObject("Panels.NewPanel");
	c:= Gadgets.CreateObject("TextFields.NewCaption");
	s:= Gadgets.CreateObject("BasicGadgets.NewSlider");
	t:= Gadgets.CreateObject("TextFields.NewTextField");
	
	WITH s: Gadgets.Frame DO WITH t: Gadgets.Frame DO WITH p: Gadgets.Frame DO WITH c: Gadgets.Frame DO
		(* init the slider gadget *)
		s.W:= 20; s.H:= 120; s.obj:= model; 
		A.id:= Objects.set; 
		A.name:= "Min"; A.class:= Objects.Int; A.i:= min; A.res:= -1; s.handle(s, A);
		A.name:= "Max"; A.class:= Objects.Int; A.i:= max; A.res:= -1; s.handle(s, A);
		A.name:= "Field"; A.class:= Objects.String; COPY(name, A.s); A.res:= -1; s.handle(s, A);

		(* init the text gadget *)
		t.W:= s.W; t.H:= 17; t.obj:= model;
		A.name:= "Field"; A.class:= Objects.String; COPY(name, A.s); A.res:= -1; t.handle(t, A);
		(* make sure A.id is set to Objects.String, when setting the text gadget's Value attribute *)
		A.id:= Objects.get; COPY(name, A.name); A.class:= Objects.Int; A.res:= -1; model.handle(model, A);
		A.id:= Objects.set; A.name:= "Value"; A.class:= Objects.Int; A.res:= -1; s.handle(s, A);
		A.class:= Objects.String; Strings.IntToStr(A.i, A.s); A.res:= -1; t.handle(t, A);

		(* init the caption gadget and its underlying panel *)
		name[1]:= 0X;
		Attributes.StrToTxt(name, c(TextFields.Caption).text);
		TextFields.CalcSize(c(TextFields.Caption), c.W, c.H, nolines, TRUE);
		p.W:= 19; p.H:= 15;
		C.id:= Display.drop; C.obj:= c; C.x:= 0; C.y:= 0; C.u:= (p.W-c.W) DIV 2; C.v:= -c.H-1; C.F:= p; C.res:= -1; p.handle(p, C);
		A.name:= "Locked"; A.class:= Objects.Bool; A.res:= -1; A.b:= TRUE; p.handle(p, A);
		
		(* insert the gadgets into the panel with a Display.ConsumeMsg
			C.x C.y are frame coords. Set them to zero.
			C.u, C.v are the coords of the bounding box' bottom left corner relativ to the top left corner of the panel *)
		t.Y:= 0; s.Y:= t.H + 2; p.Y:= s.Y + s.H + 1;
		t.slink:= s; s.slink:= p; p.slink:= NIL;
		C.id:= Display.drop; C.obj:= t; C.x:= 0; C.y:= 0; C.F:= P; C.u:= X; C.v:= -(t.H+s.H+p.H+13); C.res:= -1; P.handle(P, C);
	END; END; END; END
END InsertSlider;

PROCEDURE InsertButton(P: Gadgets.Frame; model: Objects.Object; capt, cmd: ARRAY OF CHAR; popout: BOOLEAN; X: INTEGER);
(* inserts a button into the panel *)
VAR b: Objects.Object; A: Objects.AttrMsg; C: Display.ConsumeMsg;
BEGIN
	(* get instance *)
	b:= Gadgets.CreateObject("BasicGadgets.NewButton");
	
	(* init button gadget *)
	b(Gadgets.Frame).W:= 35; b(Gadgets.Frame).H:= 25; b(Gadgets.Frame).obj:= model;
	A.id:= Objects.set;
	A.name:= "Caption"; A.class:= Objects.String; COPY(capt, A.s); A.res:= -1; b.handle(b, A);
	(* if model is not NIL ,cmd holds not a command string, but the model's attribute name the button has to represent *)
	IF model = NIL THEN A.name:= "Cmd" ELSE A.name:= "Field" END;
	A.class:= Objects.String; COPY(cmd, A.s); A.res:= -1; b.handle(b, A);
	A.name:= "Popout"; A.class:= Objects.Bool; A.b:= popout; A.res:= -1; b.handle(b, A);

	(* insert button into the panel *)
	C.id:= Display.drop; C.obj:= b; C.x:= 0; C.y:= 0; C.F:= P; C.u:= X; C.v:= -195; C.res:= -1; P.handle(P, C);
END InsertButton;

PROCEDURE LoadDocument*(D: Documents.Document);
(* loads a document from a file or creates a new one if the file with name D.name does not exists. 
	This procedure has to be implemented, when you create a new document type *)
VAR obj, V: Objects.Object; main: Gadgets.Frame;
	F: Files.File; R: Files.Rider; name: ARRAY 64 OF CHAR; ch: CHAR;
	tag: INTEGER; len: LONGINT; lib: Objects.Library;
	C: Display.ConsumeMsg; A: Objects.AttrMsg;
BEGIN
	main:= NIL; D.W:= 300; D.H:= 200;
	
	F:= Files.Old(D.name);
	IF F # NIL THEN
		Files.Set(R, F, 0); Files.ReadInt(R, tag);
		IF tag = Documents.Id THEN
			Files.ReadString(R, name);	(* skip over generator name *)
			Files.ReadInt(R, D.X); Files.ReadInt(R, D.Y); Files.ReadInt(R, D.W); Files.ReadInt(R, D.H);
			Files.Read(R, ch);
			IF ch = Objects.LibBlockId THEN
				(* there's a library stored, so make a new (privat) library and let the library do the work *)
				NEW(lib); Objects.OpenLibrary(lib); Objects.LoadLibrary(lib, F, Files.Pos(R), len);
				lib.GetObj(lib, 0, obj);	(* by default *)
				IF (obj # NIL) & (obj IS Objects.Dummy) THEN
					(* an empty lib :-( *)
					Out.String("Discarding "); Out.String(obj(Objects.Dummy).GName); Out.Ln
				ELSIF (obj # NIL) & (obj IS Gadgets.Frame) THEN
					(* make the first (visible) gadget the document's main panel *)
					main:= obj(Gadgets.Frame)
				END
			END
		END
	END;
	
	IF main = NIL THEN
		(* there was no file or the file was not a MineSweeper document, so lets create a new doc *)
		(* first we need a panel. Make this panel to the document's main panel *)
		Objects.NewObj:= Gadgets.CreateObject("MineSweeper.NewPanel"); main:= Objects.NewObj(Gadgets.Frame);
		
		(* and now we need a MineSweeper View and a game model *)
		V:= Gadgets.CreateViewModel("MineSweeper.NewView", "MineSweeper.NewField");
		WITH V: Gadgets.Frame DO
			(* name the view, so we can access it through the GADGET system's macro language *)
			Gadgets.NameObj(V, ViewName);
	
			(* adjust the panel's and view's size *)
			V.W:= FieldDX + (MinFieldW * BoxW) + (BoxW DIV 2);
			V.H:= (MinFieldH + 1) * BoxH;
			main.W:= V.W + 90 + 10; D.W:= main.W;
			
			(* insert the view into the panel *)
			C.id:= Display.drop; C.obj:= V; C.x:= 0; C.y:= 0; C.F:= main; C.u:= 90; C.v:= -V.H - 5; C.res:= -1; main.handle(main, C);

			(* insert sliders to set the width, height and number of mines of the game. Use the same model for the slider and
				textfield as for the view *)
			InsertSlider(main, V.obj,"Width", 10, 8, 30);
			InsertSlider(main, V.obj, "Height", 35, 8, 16);
			InsertSlider(main, V.obj, "Mines", 60, 10, 99);
			
			(* insert a button to restart the game (no model is needed). The command MineSweeper.New needs a Gadget.Frame's name,
				which holds the game model *)
			InsertButton(main, NIL, "New", "MineSweeper.NewGame  Mine", TRUE, 10);
			(* insert a pause button and conect it to the game model (the button displays the model's attribute Pause *)
			InsertButton(main, V.obj, "Pause", "Pause", FALSE, 47);
			
			(* set some additional attributes on the panel. This must be done at the end, because as long as you want to
				operate on the panel (insert gadgets, ...), the panel must not be locked *)
			A.id:= Objects.set; A.name:= "Locked"; A.class:= Objects.Bool; A.res:= -1; A.b:= TRUE; main.handle(main, A);
		END
	END;

	Documents.Init(D, main)
END LoadDocument;

PROCEDURE StoreDocument(D: Documents.Document);
(* stores a document in a file with name D.name *)
VAR F: Files.File; len: LONGINT; R: Files.Rider; B: Objects.BindMsg; obj: Objects.Object;
BEGIN
	IF D.name # "" THEN
		obj:= D.dsc;
		IF obj # NIL THEN
			(* link all the gadgets in the document to a (private) library *)
			NEW(B.lib); Objects.OpenLibrary(B.lib); obj.handle(obj, B);
			
			F:= Files.New(D.name); Files.Set(R, F, 0);
			(* store Documents.Id and the document's generator name *)
			Files.WriteInt(R, Documents.Id); Files.WriteString(R, "MineSweeper.NewDoc");
			(* store the document's position and size *)
			Files.WriteInt(R, D.X); Files.WriteInt(R, D.Y); Files.WriteInt(R, D.W); Files.WriteInt(R, D.H);
			(* store the library (with all the gadgets) *)
			Objects.StoreLibrary(B.lib, F, Files.Pos(R), len);
			
			(* DON'T FORGET TO REGISTER THE FILE. OTHERWISE IT WILL BE LOST !!! *)
			Files.Register(F)
		END
	END
END StoreDocument;

PROCEDURE DocHandler*(D: Objects.Object; VAR M: Objects.ObjMsg);
(* the document's handler *)
BEGIN
	WITH D: Documents.Document DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF M.id = Objects.get THEN
					IF M.name = "Gen" THEN M.class:= Objects.String; M.s:= "MineSweeper.NewDoc"; M.res:= 0
					ELSIF M.name = "Adaptive" THEN M.class:= Objects.Bool; M.b:= FALSE; M.res:= 0
					ELSIF M.name = "Icon" THEN M.class:= Objects.String; M.s:= IconName; M.res:= 0	(* name "Lib.Obj" of doc's icon *)
					ELSE Documents.Handler(D, M)
					END
				ELSE Documents.Handler(D, M)
				END
			END
		ELSIF M IS Display.DisplayMsg THEN
			WITH M: Display.DisplayMsg DO
				IF (M.device = Display.printer) & (M.id = Display.contents) & (D.dsc # NIL) THEN
					(* print (not implemented yet, because of some bugs in Printer3 -> so theres an update to come!) *)
				ELSE Documents.Handler(D, M)
				END
			END
		ELSIF M IS Objects.LinkMsg THEN
			WITH M: Objects.LinkMsg DO
				IF (M.id = Objects.get) & ((M.name = "DeskMenu") OR (M.name = "SystemMenu") OR (M.name = "UserMenu")) THEN
					M.obj := Desktops.NewMenu(MenuString); M.res := 0
				ELSE Documents.Handler(D, M)
				END
			END
		ELSE Documents.Handler(D, M)
		END
	END
END DocHandler;


(*	----------------------------	procedures to generate the objects	-----------------------------	*)

PROCEDURE NewField*;
(* genarates a new instance of a (game) model. Sets its mine field size to default values *)
VAR F: Field;
BEGIN
	NEW(F);
	InitField(F, MinFieldW, MinFieldH, MinMines, FALSE);
	F.handle:= FieldHandler;
	Objects.NewObj:= F
END NewField;

PROCEDURE NewView*;
(* genarates a new instance of a (game) view. Sets its size to default values *)
VAR F: Frame; A: Objects.AttrMsg;
BEGIN
	NEW(F);
	F.W:= VW; F.H:= VH; F.handle:= FrameHandler;
	(* add tutorial attribute *)
	A.id:= Objects.set; A.res:= -1; A.name:= "Tutorial"; A.class:= Objects.String; A.s:= "MineSweeper.Book MineField"; F.handle(F, A);
	
	(* insert the state Gadgets.transparent. This causes the panel to redraw its background under the view each time the view
		has to redraw itself. This flag is needed when your (visible) gadget does not cover a rectangular area (or has transparent
		areas (magic holes) in its frame area (eg. a nonfilled circle) *)
	F.state:= {Gadgets.transparent};
	Objects.NewObj:= F
END NewView;

PROCEDURE NewPanel*;
(* genarates a new instance of a MineSweeper panel. Sets its size to default values *)
VAR P: MinePanel;
BEGIN
	(* in order to get an instance of the extended type, do the following:
			- make a new instance of the object (extended type)
			- init the base type fields by calling the base types Init-procedure
			- init the extra (added) record fields and set the new handler *)
	NEW(P); Panels.InitPanel(P);
	P.handle:= PanelHandler; P.W:= PW; P.H:= PH;
	(* set the panel's background picture *)
	NEW(P.pict); Pictures.Open(P.pict, PictName, FALSE);
	(* set Panels.texture so the panel will be filled with the picture *)
	INCL(P.state0, Panels.texture);
	Objects.NewObj:= P
END NewPanel;

PROCEDURE NewDoc*;
(* genarates a new instance of a MineSweeper document. Sets its size to default values and 
	inits the needed procedure variables *)
VAR D: Documents.Document;
BEGIN
	NEW(D);
	D.Load:= LoadDocument; D.Store:= StoreDocument; D.handle:= DocHandler;
	D.W:= 250; D.H:= 200;
	Objects.NewObj:= D
END NewDoc;


(*	----------------------------	global commands to control the game	-----------------------------	*)

PROCEDURE NewGame*;
(* command to restart from document's menu or new-button on panel *)
VAR S: Attributes.Scanner; A: Objects.AttrMsg; o: Objects.Object; doc: Documents.Document;
BEGIN
	IF Desktops.CurMenu(Gadgets.context) = Gadgets.context THEN	(* button in doc-menu *)
		S.class:= Attributes.Name; S.s:= ViewName
	ELSE	(* button on panel *)
		Attributes.OpenScanner(S,Oberon.Par.text,Oberon.Par.pos); Attributes.Scan(S);
	END;
	doc:= Desktops.CurDoc(Gadgets.context);
	IF (doc # NIL) & ((S.class= Attributes.Name) OR (S.class= Attributes.String)) THEN
		(* !!! there has to be at least one object in the panel with name S.s (either displayable or abstract).
			doc.dsc is the documents main panel and so we start looking for the object in this panel. Probability to find 
			the object there is tremendous big *)
		o:= Gadgets.FindObj(doc.dsc, S.s);
		IF (o # NIL) & (o IS Frame) THEN o:= o(Frame).obj END;	(* was a view's name, so get its model *)
		IF (o # NIL) & (o IS Field) THEN
			(* trick to reset the field and so to restart *)
			A.id:= Objects.get; A.name:= "Width"; A.class:= Objects.Int; A.res:= -1; o.handle(o, A);
			A.id:= Objects.set; A.res:= -1; o.handle(o, A);
			
			(* inform all the views of the change *)
			Gadgets.Update(o)
		ELSE
			(* give out a error message if there was no object with name "Mine" *)
			Out.String("Frame named '"); Out.String(S.s); Out.String("' not found !"); Out.Ln
		END
	END;
END NewGame;


(*	----------------------------	just to remove THE TIMER from the Oberon Loop	-----------------------------	*)

PROCEDURE Deinstall*;
(* deinstalls the task from the Oberon Loop, so one can free this module without danger to crash the system *)
BEGIN IF task # NIL THEN Oberon.Remove(task) END
END Deinstall;


(*	----------------------------	module's init part	-----------------------------	*)

BEGIN
	(* write out the most important text *)
	Out.String("MineSweeper "); Out.String(Version); Out.String(" by MadCat"); Out.Ln;
	
	(* allocate memory for the global array *)
	NEW(changedFields);
	
	(* set the font variable *)
	font:= Fonts.This(FontName);
	
	(* init the col. array to some nice colours *)
	MineCols[1]:= 3; MineCols[2]:= 1; MineCols[3]:= 8;
	MineCols[4]:= 7; MineCols[5]:= 9; MineCols[6]:= 11;
	MineCols[7]:= 15; MineCols[8]:= 4;
	
	(* define all the pretty patterns *)
	flagDesc1[1]:= {0};	flagDesc1[2]:= {0};	flagDesc1[3]:= {0};
	flagDesc1[4]:= {0};	flagDesc1[5]:= {0};	flagDesc1[6]:= {};
	flagDesc1[7]:= {};	flagDesc1[8]:= {};	flagDesc1[9]:= {};
	flagDesc1[10]:= {0};
	flag1:= Display.NewPattern(16, 10, flagDesc1);

	flagDesc2[1]:= {};	flagDesc2[2]:= {};	flagDesc2[3]:= {};
	flagDesc2[7]:= {0..7};	flagDesc2[8]:= {0..5};	flagDesc2[9]:= {0..2};
	flagDesc2[10]:= {};
	flag2:= Display.NewPattern(16,10, flagDesc2);

	mineDesc[1]:= {2..5};
	mineDesc[2]:= {1..6};	mineDesc[3]:= {1..6};	mineDesc[4]:= {1,2,4..6};
	mineDesc[5]:= {2..5};	mineDesc[6]:= {1};	mineDesc[7]:= {4,6,0};
	mineDesc[8]:= {7,3,0};	mineDesc[9]:= {7,4,1};	mineDesc[10]:= {6,3};
	mine:= Display.NewPattern(16,10, mineDesc);
	
	(* install THE TIMER *)
	NEW(task);
	IF task = NIL THEN Out.String("MineSweeper could not install THE TIMER"); Out.Ln
	ELSE
		task.safe:= FALSE; task.handle:= Timer; task.time := Oberon.Time();
		Oberon.Install(task);
		lastTime := 0;
		(* install procedure to remove THE TIMER when module is freed *)
		Modules.InstallTermHandler(Deinstall)
	END;

	(* init the random genarator *)
	seek:= ((Oberon.Time() MOD 32133)+1)*2
END MineSweeper.
