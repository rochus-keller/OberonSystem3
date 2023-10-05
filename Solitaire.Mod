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

MODULE Solitaire;	(** portable *)	(** written by Patrick Saladin   *)
(*
	14.04.95	fixed bug  redraw of cards and mouse cursor
	05.03.95	updated to Oberon System 3 V2.0
						changed Msgs back to FrameMsg
	06.10.94	added Undo
	06.10.94	changed Msgs, they are no longer FrameMsg, exept SetDrawMsg
*)

IMPORT
	Files, Input, Display, Display3, Attributes, Effects, Objects, Gadgets, Oberon, Cards, Documents, Desktops, Out;

CONST
	IconName = "Icons2.Solitaire";
	MenuString = "Cards.Undo[Undo] Solitaire.New[New] Desktops.StoreDoc[Store]";
	Version = "V 1.4";

	CardW = Cards.CardW; CardH = Cards.CardH;
	DeltaH = 13; DeltaHH = 5;
	CARDS = 52;
	
TYPE
	TakeCardMsg = RECORD (Display.FrameMsg)
		tail: Cards.Card
	END;
	
	DistributeMsg = RECORD (Display.FrameMsg)
		tail: Cards.Card
	END;
	
	FitMsg = RECORD (Display.FrameMsg)
		this: Cards.Card;
		on: Cards.Stack;
	END;
	
	SetDrawMsg = RECORD (Display.FrameMsg)
		drawNum: INTEGER;
	END;

	FlipMove = POINTER TO FlipMoveDesc;
	FlipMoveDesc = RECORD (Cards.MoveDesc)
	END;
	
	SwapMove = POINTER TO SwapMoveDesc;
	SwapMoveDesc = RECORD (Cards.MoveDesc)
		nrVis: ARRAY CARDS OF SHORTINT;
		curSwap: INTEGER;
	END;

	Talon = POINTER TO TalonDesc;
	TalonDesc = RECORD (Cards.StackDesc)
		visTail: Cards.Card;	(* cards that are visible *)
		nrVis: ARRAY CARDS OF SHORTINT;	(* nr. of cards that are visible on top *)
		curSwap: INTEGER;	(* index into nr.Vis-array *)
		nrDraw: INTEGER;	(* nr. of cards to move from tail to visTail when clicked *)
	END;
	
	Depot = POINTER TO DepotDesc;
	DepotDesc = RECORD (Cards.StackDesc)
	END;
	
	Column = POINTER TO ColumnDesc;
	ColumnDesc = RECORD (Cards.StackDesc)
		topY: INTEGER;	(* left, top corner of top card *)
		nrCards: INTEGER;	(* nr of cards at beginning *)
	END;

VAR 
	talonMethods: Cards.Methods;
	depotMethods: Cards.Methods;
	columnMethods: Cards.Methods;

(*	-----------------------------	aux procedures	-----------------------------	*)
	
PROCEDURE StartGame(F: Display.Frame);
VAR C: Cards.CollectMsg; T: TakeCardMsg; D: DistributeMsg;
BEGIN C.res:= -1; T.res:= -1; D.res:= -1;
	C.tail:= Cards.NewTail(); F.handle(F, C);
	Cards.Shuffle(C.tail);
	D.tail:= C.tail; F.handle(F, D);
	T.tail:= D.tail; F.handle(F, T)
END StartGame;

PROCEDURE DrawRect(x, y: INTEGER; card: Cards.Card);
CONST MaxH = CardH+12*DeltaH;
BEGIN
	Oberon.RemoveMarks(x, y, CardW, MaxH);
	Display.ReplConst(15, x , y, 1, CardH-DeltaH, Display.invert);
	Display.ReplConst(15, x+CardW-1 , y, 1, CardH-DeltaH, Display.invert);
	Display.ReplConst(15, x+1 , y, CardW-2, 1, Display.invert);
	INC(y, CardH-DeltaH);
	REPEAT
		Display.ReplConst(15, x+1 , y+DeltaH-1, CardW-2, 1, Display.invert);
		Display.ReplConst(15, x , y, 1, DeltaH, Display.invert);
		Display.ReplConst(15, x+CardW-1 , y, 1, DeltaH, Display.invert);
		card:= card.prev; INC(y, DeltaH)
	UNTIL ~card.visible
END DrawRect;

PROCEDURE WaitMouseRelease(M: Oberon.InputMsg);
BEGIN
	REPEAT Input.Mouse(M.keys, M.X, M.Y); Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, M.X, M.Y)
	UNTIL M.keys = {};
END WaitMouseRelease;

PROCEDURE DropOnFittingStack(M: Oberon.InputMsg; c: Cards.Card; self: Cards.Stack);
VAR F: FitMsg;
BEGIN
	F.on:= NIL; F.this:= c; F.res:= -1; M.dlink.handle(M.dlink, F);
	IF F.on # NIL THEN self.do.moveCard(self, F.on, c, FALSE) END;
	WaitMouseRelease(M)
END DropOnFittingStack;

(*	-----------------------------	talon stuff	-----------------------------	*)

PROCEDURE TalonAttr(T: Talon; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class := Objects.String; COPY("Solitaire.NewTalon", M.s); M.res := 0
		ELSIF M.name = "DrawNum" THEN M.class := Objects.Int; M.i:= T.nrDraw; M.res := 0 
		ELSE Cards.StackHandler(T, M)
		END
	ELSIF M.id = Objects.set THEN
		IF M.name = "DrawNum" THEN
			IF (M.class = Objects.Int) & (M.i>0) & (M.i<4) THEN T.nrDraw:= SHORT(M.i); M.res := 0 END;
		ELSE Cards.StackHandler(T, M);
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("DrawNum"); Cards.StackHandler(T, M)
	END
END TalonAttr;

PROCEDURE CopyTalon(VAR M: Objects.CopyMsg; from, to: Talon);
VAR c: Cards.Card; i: INTEGER;
BEGIN
	to.nrDraw:= from.nrDraw;
	to.curSwap:= from.curSwap;
	i:= from.curSwap;
	WHILE i > 0 DO to.nrVis[i]:= from.nrVis[i]; DEC(i) END;
	to.visTail:= Cards.NewTail();
	c:= from.visTail.prev;
	WHILE c # from.visTail DO Cards.AppendCard(to.visTail, Cards.CloneCard(c)); c:= c.prev END;
	Cards.CopyStack(M, from, to);
END CopyTalon;

PROCEDURE DrawTalon(T: Cards.Stack; M: Display3.Mask; x, y, w, h: INTEGER);
VAR c: Cards.Card; i: INTEGER;
BEGIN
	WITH T: Talon DO
		Oberon.RemoveMarks(x, y, w, h);
		Display3.ReplConst(M, Cards.backC, x, y, w, h, Display.replace);
		IF Cards.IsEmpty(T.tail) THEN
			Display3.Rect3D(M, Display3.bottomC, Cards.topC, x, y+h-CardH, CardW, CardH, 1, Display.replace)
		ELSE
			Cards.DrawCard(M, T.tail.next, x, y+h, CardW, CardH, T.bgNr);
		END;
		IF (T.curSwap >= 0) & (T.nrVis[T.curSwap] > 0) THEN
			i:= T.nrVis[T.curSwap]; c:= T.visTail.next;
			Cards.DrawCard(M, c, x+CardW+i*10, y+h, CardW, CardH, T.bgNr);
			DEC(i); c:= c.next;
			WHILE i > 0 DO
				Cards.DrawCard(M, c, x+CardW+i*10, y+h, 10, CardH, T.bgNr);
				DEC(i); c:= c.next
			END
		END;
		IF Gadgets.selected IN T.state THEN
			Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
		END
	END
END DrawTalon;

PROCEDURE TalonDrop(T: Cards.Stack; card: Cards.Card);
BEGIN
	WITH T: Talon DO
		IF card.visible THEN
			IF (T.curSwap = -1) OR (T.nrVis[T.curSwap] = T.nrDraw) THEN
				INC(T.curSwap); T.nrVis[T.curSwap]:= 0
			END;
			INC(T.nrVis[T.curSwap]); Cards.AppendCard(T.visTail, card)
		ELSE Cards.AppendCard(T.tail, card)
		END;
		Gadgets.Update(T)
	END
END TalonDrop;

PROCEDURE TalonMove(self, to: Cards.Stack; card: Cards.Card; undo: BOOLEAN);
VAR M: Cards.SimpleMove;
BEGIN
	WITH self: Talon DO
		Cards.RemoveCard(self.visTail, card); 
		DEC(self.nrVis[self.curSwap]); IF self.nrVis[self.curSwap] = 0 THEN DEC(self.curSwap) END;
		to.do.dropCard(to, card); Gadgets.Update(self);
		IF ~undo THEN NEW(M); M.card:= card; M.to:= to; Cards.AppendMove(self, M) END
	END
END TalonMove;

PROCEDURE TalonUndoMove(T: Cards.Stack; M: Cards.Move);
VAR c: Cards.Card; i: INTEGER;
BEGIN
	WITH T: Talon DO
		IF M IS SwapMove THEN
			i:= M(SwapMove).curSwap; T.curSwap:= i;
			WHILE i >= 0 DO T.nrVis[i]:= M(SwapMove).nrVis[i]; DEC(i) END;
			IF Cards.IsEmpty(T.visTail) THEN
				REPEAT
					c:= T.tail.next; Cards.RemoveCard(T.tail, c); c.visible:= TRUE;
					Cards.AppendCard(T.visTail, c)
				UNTIL Cards.IsEmpty(T.tail)
			ELSE
				i:= T.nrVis[T.curSwap+1];
				REPEAT
					c:= T.visTail.next; c.visible:= FALSE; Cards.RemoveCard(T.visTail, c); 
					Cards.AppendCard(T.tail, c); DEC(i)
				UNTIL i = 0
			END;
			Gadgets.Update(T)
		ELSE Cards.methods.undoMove(T, M)
		END
	END
END TalonUndoMove;

PROCEDURE TrackTalon(T: Cards.Stack; VAR M: Oberon.InputMsg);
VAR c: Cards.Card; SM: SwapMove; x, y, i: INTEGER;
BEGIN
	WITH T: Talon DO
		x:= T.X+M.x; y:= T.Y+M.y;
		IF Effects.Inside(M.X, M.Y, x, y, CardW, CardH) & (~Cards.IsEmpty(T.tail) OR ~Cards.IsEmpty(T.visTail)) THEN
			IF M.keys = {2} THEN
				NEW(SM); i:= T.curSwap; SM.curSwap:= T.curSwap;
				WHILE i >= 0 DO SM.nrVis[i]:= T.nrVis[i]; DEC(i) END;
				IF Cards.IsEmpty(T.tail) THEN
					T.curSwap:= -1;
					WHILE ~Cards.IsEmpty(T.visTail) DO
						c:= T.visTail.next; Cards.RemoveCard(T.visTail, c); c.visible:= FALSE;
						Cards.AppendCard(T.tail, c)
					END
				ELSE 
					i:= T.nrDraw; INC(T.curSwap); T.nrVis[T.curSwap]:= 0;
					REPEAT
						DEC(i); INC(T.nrVis[T.curSwap]);
						c:= T.tail.next; c.visible:= TRUE; Cards.RemoveCard(T.tail, c); 
						Cards.AppendCard(T.visTail, c)
					UNTIL (i = 0) OR Cards.IsEmpty(T.tail)
				END;
				Cards.AppendMove(T, SM); Gadgets.Update(T); WaitMouseRelease(M)
			ELSE Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, M.X, M.Y)
			END;
			M.res := 0
		ELSIF ~Cards.IsEmpty(T.visTail) & Effects.Inside(M.X, M.Y, x+CardW+T.nrVis[T.curSwap]*10, y, CardW, CardH) THEN
			IF  M.keys = {2} THEN
				c:= T.visTail.next; Cards.TrackMove(M, x+CardW+T.nrVis[T.curSwap]*10, y, T, c, DrawRect, DrawRect);
			ELSIF M.keys = {1} THEN
				c:= T.visTail.next; DropOnFittingStack(M, c, T)
			ELSE
				Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, M.X, M.Y)
			END;
			M.res := 0
		END
	END
END TrackTalon;

PROCEDURE TalonHandler(T: Objects.Object; VAR M: Objects.ObjMsg);
VAR T0: Talon; c: Cards.Card; i, val: INTEGER;
BEGIN
	WITH T: Talon DO
		IF (M IS SetDrawMsg) & (M.stamp # T.stamp) THEN
			WITH M: SetDrawMsg DO
				T.stamp:= M.stamp; T.nrDraw:= M.drawNum; StartGame(M.dlink(Display.Frame));
			END
		ELSIF M IS Cards.CollectMsg THEN
			WITH M: Cards.CollectMsg DO
				IF T.visTail.next # T.visTail THEN
					T.curSwap:= -1;
					c:= T.visTail.prev; Cards.RemoveCard(T.visTail, c);
					Cards.AppendCard(T.tail, c)
				END;
				Cards.StackHandler(T, M)
			END
		ELSIF M IS TakeCardMsg THEN
			WITH M: TakeCardMsg DO
				c:= M.tail.prev; Cards.RemoveCard(M.tail, c); Cards.AppendCard(T.tail, c); Gadgets.Update(T)
			END
		ELSIF M IS Objects.AttrMsg THEN TalonAttr(T, M(Objects.AttrMsg))
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Files.WriteInt(M.R, T.nrDraw); Files.WriteInt(M.R, T.curSwap);
					i:= T.curSwap;
					WHILE i >= 0 DO Files.WriteInt(M.R, T.nrVis[i]); DEC(i) END;
					c:= T.visTail.prev;
					WHILE c # T.visTail DO Cards.WriteCard(M.R, c); c:= c.prev END;
					Cards.WriteCard(M.R, NIL);	(* sentinell *)
					Cards.StackHandler(T, M)
				ELSIF M.id = Objects.load THEN
					Files.ReadInt(M.R, T.nrDraw); Files.ReadInt(M.R, T.curSwap);
					i:= T.curSwap;
					WHILE i >= 0 DO Files.ReadInt(M.R, val); T.nrVis[i]:= SHORT(val); DEC(i) END;
					c:= T.visTail.prev;
					Cards.ReadCard(M.R, c);
					WHILE c # NIL DO Cards.AppendCard(T.visTail, c); Cards.ReadCard(M.R, c) END;
					Cards.StackHandler(T, M)
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = T.stamp THEN M.obj := T.dlink	(* copy msg arrives again *)
				ELSE NEW(T0); T.stamp := M.stamp; T.dlink := T0; CopyTalon(M, T, T0); M.obj := T0
				END
			END
		ELSE Cards.StackHandler(T, M)
		END
	END;
END TalonHandler;

PROCEDURE NewTalon*;
VAR T: Talon;
BEGIN
	NEW(T); Cards.InitStack(T); T.visTail:= Cards.NewTail();
	T.handle:= TalonHandler; T.do:= talonMethods; T.W:= 2*CardW + 30;
	T.nrDraw:= 3; T.curSwap:= -1;
	Objects.NewObj:= T
END NewTalon;

(*	-----------------------------	depot stuff	-----------------------------	*)

PROCEDURE DepotAttr(D: Depot; VAR M: Objects.AttrMsg);
BEGIN
	IF (M.id = Objects.get) & (M.name = "Gen") THEN
		M.class := Objects.String; COPY("Solitaire.NewDepot", M.s); M.res := 0
	ELSE Cards.StackHandler(D, M);
	END
END DepotAttr;

PROCEDURE CopyDepot(VAR M: Objects.CopyMsg; from, to: Depot);
BEGIN
	Cards.CopyStack(M, from, to);
END CopyDepot;

PROCEDURE DepotCanDrop(D: Cards.Stack; card: Cards.Card): BOOLEAN;
VAR c: Cards.Card; res: BOOLEAN;
BEGIN
	IF Cards.IsEmpty(D.tail) THEN RETURN (card.nr = 0) END;
	c:= D.tail.next;
	res:= (card.nr = c.nr+1) & ~card.prev.visible;
	RETURN res & (card.suit = c.suit)
END DepotCanDrop;

PROCEDURE DepotHandler(D: Objects.Object; VAR M: Objects.ObjMsg);
VAR D0: Depot;
BEGIN
	WITH D: Depot DO
		IF M IS FitMsg THEN IF D.do.canDrop(D, M(FitMsg).this) THEN M(FitMsg).on:= D END 
		ELSIF M IS Objects.AttrMsg THEN DepotAttr(D, M(Objects.AttrMsg))
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = D.stamp THEN M.obj := D.dlink	(* copy msg arrives again *)
				ELSE NEW(D0); D.stamp := M.stamp; D.dlink := D0; CopyDepot(M, D, D0); M.obj := D0
				END
			END
		ELSE Cards.StackHandler(D, M)
		END
	END
END DepotHandler;

PROCEDURE NewDepot*;
VAR D: Depot;
BEGIN
	NEW(D); Cards.InitStack(D);
	D.handle:= DepotHandler; D.do:= depotMethods;
	Objects.NewObj:= D
END NewDepot;

(*	-----------------------------	column stuff	-----------------------------	*)

PROCEDURE ColumnAttr(C: Column; VAR M: Objects.AttrMsg);
BEGIN
	IF (M.id = Objects.get) & (M.name = "Gen") THEN
		M.class := Objects.String; COPY("Solitaire.NewColumn", M.s); M.res := 0
	ELSE Cards.StackHandler(C, M);
	END
END ColumnAttr;

PROCEDURE CopyColumn(VAR M: Objects.CopyMsg; from, to: Column);
BEGIN
	to.nrCards:= from.nrCards;
	Cards.CopyStack(M, from, to);
END CopyColumn;

PROCEDURE ColumnCanDrop(C: Cards.Stack; card: Cards.Card): BOOLEAN;
VAR c: Cards.Card; res: BOOLEAN;
BEGIN
	IF Cards.IsEmpty(C.tail) THEN RETURN (card.nr = 12) END;
	c:= C.tail.next;
	res:= (card.nr = c.nr-1) & c.visible;
	RETURN res & ((card.suit DIV 2) # (c.suit DIV 2))
END ColumnCanDrop;

PROCEDURE ColumnUndoMove(C: Cards.Stack; M: Cards.Move);
BEGIN
	IF M IS FlipMove THEN C.tail.next.visible:= FALSE; Gadgets.Update(C)
	ELSE Cards.methods.undoMove(C, M)
	END
END ColumnUndoMove;

PROCEDURE DrawColumn(C: Cards.Stack; M: Display3.Mask; x, y, w, h: INTEGER);
VAR c: Cards.Card;
BEGIN
	WITH C: Column DO
		Oberon.RemoveMarks(x, y, w, h);
		Display3.ReplConst(M, Cards.backC, x, y, w, h, Display.replace);
		IF Cards.IsEmpty(C.tail) THEN
			C.topY:= C.Y;
			Display3.Rect3D(M, Display3.bottomC, Cards.topC, x, y+h-CardH, CardW, CardH, 1, Display.replace)
		ELSE
			c:= C.tail.prev; C.topY:= y+h;
			WHILE c.prev # C.tail DO
				IF c.visible THEN Cards.DrawCard(M, c, x, C.topY, CardW, DeltaH, C.bgNr); DEC(C.topY, DeltaH)
				ELSE Cards.DrawCard(M, c, x, C.topY, CardW, DeltaHH, C.bgNr); DEC(C.topY, DeltaHH)
				END;
				c:= c.prev
			END;
			Cards.DrawCard(M, c, x, C.topY, CardW, CardH, C.bgNr);
			C.topY:= C.topY - y + C.Y
		END;
		IF Gadgets.selected IN C.state THEN
			Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
		END
	END
END DrawColumn;

PROCEDURE TrackColumn(C: Cards.Stack; VAR M: Oberon.InputMsg);
VAR c: Cards.Card; FM: FlipMove; x, y, dH: INTEGER;
BEGIN
	WITH C: Column DO
		x:= C.X+M.x; y:= C.Y+M.y;
		c:= C.tail.next.next; dH:= 0; C.tail.visible:= FALSE;
		WHILE c.visible DO INC(dH, DeltaH); c:= c.next END; c:= c.prev;
		IF ~Cards.IsEmpty(C.tail) & Effects.Inside(M.X, M.Y, x, C.topY+M.y-CardH, CardW, CardH+dH) THEN
			IF M.keys = {2} THEN
				IF C.tail.next.visible THEN
					c:= C.tail.next; y:= M.y + C.topY; WHILE y < M.Y DO INC(y, DeltaH); c:= c.next END;
					Cards.TrackMove(M, x, C.topY+M.y-CardH, C, c, DrawRect, DrawRect);
				ELSE
					NEW(FM); Cards.AppendMove(C, FM);
					C.tail.next.visible:= TRUE; Gadgets.Update(C); WaitMouseRelease(M)
				END
			ELSIF (M.keys = {1}) & C.tail.next.visible THEN
				c:= C.tail.next; DropOnFittingStack(M, c, C)
			ELSE Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, M.X, M.Y)
			END;
			M.res:= 0
		END	(* IF *)
	END	(* WITH *)
END TrackColumn;

PROCEDURE ColumnHandler*(C: Objects.Object; VAR M: Objects.ObjMsg);
VAR C0: Column; c: Cards.Card; i: INTEGER;
BEGIN
	WITH C: Column DO
		IF M IS DistributeMsg THEN
			WITH M: DistributeMsg DO
				i:= C.nrCards; c:= M.tail;
				REPEAT c:= c.next; DEC(i) UNTIL i = 0;
				Cards.RemoveCard(M.tail, c); c.next.visible:= TRUE;
				Cards.AppendCard(C.tail, c); Gadgets.Update(C)
			END
		ELSIF M IS Objects.AttrMsg THEN ColumnAttr(C, M(Objects.AttrMsg))
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN Files.WriteInt(M.R, C.nrCards); Cards.StackHandler(C, M)
				ELSIF M.id = Objects.load THEN Files.ReadInt(M.R, C.nrCards); Cards.StackHandler(C, M)
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = C.stamp THEN M.obj := C.dlink	(* copy msg arrives again *)
				ELSE NEW(C0); C.stamp := M.stamp; C.dlink := C0; CopyColumn(M, C, C0); M.obj := C0
				END
			END
		ELSE Cards.StackHandler(C, M)
		END
	END
END ColumnHandler;

PROCEDURE NewColumn*;
VAR C: Column;
BEGIN
	NEW(C); Cards.InitStack(C); C.handle:= ColumnHandler; C.H:= (CARDS DIV 4)*DeltaH + CardH;
	C.do:= columnMethods; C.topY:= 0;
	Objects.NewObj:= C
END NewColumn;

(*	-----------------------------	document stuff	-----------------------------	*)

PROCEDURE LoadDocument(D: Documents.Document);
VAR obj: Objects.Object; main: Gadgets.Frame; talon, stack: Cards.Stack; c: Cards.Card;
	F: Files.File; R: Files.Rider; name: ARRAY 64 OF CHAR; ch: CHAR; len: LONGINT;
	lib: Objects.Library; tag, i, k, Y: INTEGER; A: Objects.AttrMsg; C: Display.ConsumeMsg;
BEGIN
	main:= NIL;
	
	F:= Files.Old(D.name);
	IF F # NIL THEN
		Files.Set(R, F, 0); Files.ReadInt(R, tag);
		IF tag = Documents.Id THEN
			Files.ReadString(R, name);	(* skip over generator name *)
			Files.ReadInt(R, D.X); Files.ReadInt(R, D.Y); Files.ReadInt(R, D.W); Files.ReadInt(R, D.H);
			Files.Read(R, ch);
			IF ch = Objects.LibBlockId THEN
				NEW(lib); Objects.OpenLibrary(lib); Objects.LoadLibrary(lib, F, Files.Pos(R), len);
				lib.GetObj(lib, 0, obj);	(* by default *)
				IF (obj # NIL) & (obj IS Objects.Dummy) THEN
					Out.String("Discarding "); Out.String(obj(Objects.Dummy).GName); Out.Ln
				ELSIF (obj # NIL) & (obj IS Gadgets.Frame) THEN
					main:= obj(Gadgets.Frame)
				END
			END
		END
	END;
	
	IF main = NIL THEN
		A.id:= Objects.set; C.id:= Display.drop;
		obj:= Gadgets.CreateObject("Panels.NewPanel"); main:= obj(Gadgets.Frame);
		main.W:= 20+7*(CardW+2); main.H:= 4*CardH;
		A.res:= -1; A.class:= Objects.Int; A.name:= "Color"; A.i:= Cards.backC; main.handle(main, A);
	
		obj:= Gadgets.CreateObject("Solitaire.NewTalon"); talon:= obj(Cards.Stack);
		talon.X:= 10; talon.Y:= -5-talon.H; talon.slink:= NIL; C.obj:= talon;
		FOR i:= 0 TO CARDS-1 DO
			Cards.AppendCard(talon.tail, Cards.NewCard(i DIV 13, i MOD 13, FALSE))
		END;
		Cards.Shuffle(talon.tail);
		Y:= talon.Y;
		
		FOR i:= 1 TO 4 DO
			obj:= Gadgets.CreateObject("Solitaire.NewDepot"); stack:= obj(Cards.Stack);
			stack.X:= main.W-10-i*(CardW+2); stack.Y:= -5-stack.H; stack.slink:= C.obj; C.obj:= stack
		END;

		FOR i:= 0 TO 6 DO
			obj:= Gadgets.CreateObject("Solitaire.NewColumn"); stack:= obj(Cards.Stack);
			stack.X:= 10+i*(CardW+2); stack.Y:= Y-10-stack.H; stack.slink:= C.obj; C.obj:= stack;
			stack(Column).nrCards:= i+1;
			k:= stack(Column).nrCards; c:= talon.tail;
			REPEAT c:= c.next; DEC(k) UNTIL k = 0;
			Cards.RemoveCard(talon.tail, c); c.next.visible:= TRUE; Cards.AppendCard(stack.tail, c)
		END;
		Y:= stack.Y; main.H:= -Y+10;

		C.res:= -1; C.x:= 0; C.y:= 0; C.F:= main; C.u:= 10; C.v:= Y; main.handle(main, C);
		A.res:= -1; A.name:= "Locked"; A.class:= Objects.Bool; A.b:= TRUE; main.handle(main, A);
	END;
	D.W:= main.W; D.H:= main.H; Documents.Init(D, main)
END LoadDocument;

PROCEDURE StoreDocument(D: Documents.Document);
VAR F: Files.File; len: LONGINT; R: Files.Rider; B: Objects.BindMsg; obj: Objects.Object;
BEGIN
	IF D.name # "" THEN
		obj:= D.dsc;
		IF obj # NIL THEN
			NEW(B.lib); Objects.OpenLibrary(B.lib); obj.handle(obj, B);
			
			F:= Files.New(D.name); Files.Set(R, F, 0);
			Files.WriteInt(R, Documents.Id); Files.WriteString(R, "Solitaire.NewDoc");
			Files.WriteInt(R, D.X); Files.WriteInt(R, D.Y); Files.WriteInt(R, D.W); Files.WriteInt(R, D.H);
			Objects.StoreLibrary(B.lib, F, Files.Pos(R), len);
			
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
					IF M.name = "Gen" THEN M.class:= Objects.String; M.s:= "Solitaire.NewDoc"; M.res:= 0
					ELSIF M.name = "Adaptive" THEN M.class:= Objects.Bool; M.b:= FALSE; M.res:= 0
					ELSIF M.name = "Icon" THEN M.class:= Objects.String; M.s:= IconName; M.res:= 0
					ELSE Documents.Handler(D, M)
					END
				ELSE Documents.Handler(D, M)
				END
			END
		ELSIF M IS Objects.LinkMsg THEN
			WITH M: Objects.LinkMsg DO
				IF M.id = Objects.get THEN
					IF (M.name = "SystemMenu") OR (M.name = "UserMenu") OR (M.name = "DeskMenu") THEN
						M.obj := Desktops.NewMenu(MenuString); M.res := 0
					ELSE Documents.Handler(D, M)
					END
				ELSE Documents.Handler(D, M)
				END
			END
		ELSIF M IS Display.DisplayMsg THEN
			WITH M: Display.DisplayMsg DO
				IF (M.device = Display.printer) & (M.id = Display.contents) & (D.dsc # NIL) THEN
				ELSE Documents.Handler(D, M)
				END
			END
		ELSE Documents.Handler(D, M)
		END
	END
END DocHandler;

PROCEDURE NewDoc*;
VAR D: Documents.Document;
BEGIN
	NEW(D);
	D.Load:= LoadDocument; D.Store:= StoreDocument; D.handle:= DocHandler;
	D.W:= 250; D.H:= 200;
	Objects.NewObj:= D
END NewDoc;

(*	-----------------------------	commands	-----------------------------	*)

PROCEDURE New*;
VAR doc: Documents.Document;
BEGIN
	doc:= Desktops.CurDoc(Gadgets.context);
	IF (doc#NIL) & (doc.dsc # NIL) THEN
		StartGame(doc.dsc(Display.Frame));
	END
END New;

PROCEDURE SetDraw*;
VAR S: Attributes.Scanner; SD: SetDrawMsg;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Attributes.Scan(S);
	IF (S.class = Attributes.Int) & (S.i > 0) & (S.i <= 3) THEN
		SD.drawNum:= SHORT(S.i); Objects.Stamp(SD); SD.F:= NIL; Display.Broadcast(SD)
	END
END SetDraw;


BEGIN
	Out.String("Solitaire by P. Saladin "); Out.String(Version); Out.Ln;
	
	NEW(talonMethods); talonMethods^:= Cards.methods^;
		talonMethods.restoreStack:= DrawTalon; talonMethods.trackMouse:= TrackTalon;
		talonMethods.dropCard:= TalonDrop; talonMethods.moveCard:= TalonMove;
		talonMethods.undoMove:= TalonUndoMove;
	NEW(depotMethods); depotMethods^:= Cards.methods^;
		depotMethods.canDrop:= DepotCanDrop;
	NEW(columnMethods); columnMethods^:= Cards.methods^;
		columnMethods.canDrop:= ColumnCanDrop; columnMethods.restoreStack:= DrawColumn; 
		columnMethods.trackMouse:= TrackColumn; columnMethods.undoMove:= ColumnUndoMove;
END Solitaire.
