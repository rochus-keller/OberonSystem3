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

MODULE Freecell;	(** portable *)	(** written by Patrick Saladin   *)
(*
	17.9.96	fixed bug when moving cards
*)

	IMPORT
	Files, Input, Display, Display3, Effects, Objects, Gadgets, Oberon, Cards, Panels, Documents, Desktops, Out;

CONST
	IconName = "Icons2.Freecell";
	MenuString = "Cards.Undo[Undo] Freecell.New[New] Desktops.StoreDoc[Store]";
	Version = "V 1.0";

	CardW = Cards.CardW; CardH = Cards.CardH;
	DeltaH = 12;
	CARDS = 52;	COLUMN = 8;
	
TYPE
	DistributeMsg = RECORD (Display.FrameMsg)
		tail: Cards.Card
	END;

	SetSelectMsg = RECORD (Display.FrameMsg)
		child: Display.Frame;
		stack: Cards.Stack
	END;

	FreeMsg = RECORD (Display.FrameMsg)
		tempCnt: INTEGER;
		columnCnt: INTEGER
	END;
	
	FitMsg = RECORD (Display.FrameMsg)
		card: Cards.Card;
		stack: Cards.Stack
	END;


	Temp = POINTER TO TempDesc;
	TempDesc = RECORD (Cards.StackDesc)
		sel: BOOLEAN
	END;
	
	Depot = POINTER TO DepotDesc;
	DepotDesc = RECORD (Cards.StackDesc)
	END;
	
	Column = POINTER TO ColumnDesc;
	ColumnDesc = RECORD (Cards.StackDesc)
		topY: INTEGER;	(* left, top corner of top card *)
		nrCards: INTEGER;	(* nr of cards at beginning *)
		sel: BOOLEAN
	END;

	Panel = POINTER TO PanelDesc;
	PanelDesc = RECORD (Panels.PanelDesc)
		stack: Cards.Stack;
		count: INTEGER;
		card: Cards.CardDesc
	END;

VAR 
	tempMethods: Cards.Methods;
	depotMethods: Cards.Methods;
	columnMethods: Cards.Methods;
	rowSize: ARRAY 5, 5 OF INTEGER;		(* nr of cards allowed to move *)

(*	-----------------------------	aux procedures	-----------------------------	*)
	
PROCEDURE StartGame(F: Display.Frame);
VAR C: Cards.CollectMsg; D: DistributeMsg;
BEGIN C.res:= -1; D.res:= -1;
	C.tail:= Cards.NewTail(); F.handle(F, C);
	Cards.Shuffle(C.tail);
	D.tail:= C.tail; F.handle(F, D)
END StartGame;

PROCEDURE WaitMouseRelease(VAR M: Oberon.InputMsg);
BEGIN
	REPEAT Input.Mouse(M.keys, M.X, M.Y); Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, M.X, M.Y)
	UNTIL M.keys = {};
	M.res:= 0
END WaitMouseRelease;

PROCEDURE GetRowSize(col, temp: INTEGER) : INTEGER;
BEGIN
	IF col > 4 THEN RETURN 13
	ELSE RETURN rowSize[col, temp]
	END
END GetRowSize;

(*	-----------------------------	talon stuff	-----------------------------	*)

PROCEDURE TempAttr(T: Temp; VAR M: Objects.AttrMsg);
BEGIN
	IF (M.id = Objects.get) & (M.name = "Gen") THEN
		M.class := Objects.String; COPY("Freecell.NewTemp", M.s); M.res := 0
	ELSE Cards.StackHandler(T, M)
	END
END TempAttr;

PROCEDURE CopyTemp(VAR M: Objects.CopyMsg; from, to: Temp);
BEGIN to.sel:= from.sel; Cards.CopyStack(M, from, to);
END CopyTemp;

PROCEDURE TempMoveCard(self, to: Cards.Stack; card: Cards.Card; undo: BOOLEAN);
	VAR S: SetSelectMsg;
BEGIN
	self(Temp).sel:= FALSE;
	Cards.methods.moveCard(self, to, card, undo);
	S.res:= -1; S.F:= NIL; S.child:= self; S.stack:= NIL;
	Display.Broadcast(S)
END TempMoveCard;

PROCEDURE DrawTemp(T: Cards.Stack; M: Display3.Mask; x, y, w, h: INTEGER);
BEGIN
	WITH T: Temp DO
		Oberon.RemoveMarks(x, y, w, h);
		Display3.ReplConst(M, Cards.backC, x, y, w, h, Display.replace);
		IF Cards.IsEmpty(T.tail) THEN
			Display3.Rect3D(M, Display3.bottomC, Cards.topC, x, y+h-CardH, CardW, CardH, 1, Display.replace)
		ELSE
			Cards.DrawCard(M, T.tail.next, x, y+h, CardW, CardH, T.bgNr);
		END;
		IF T.sel THEN Display3.ReplConst(M, Display3.black, x, y, w, h, Display.invert) END;
		IF Gadgets.selected IN T.state THEN
			Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
		END
	END
END DrawTemp;

PROCEDURE TrackTemp(T: Cards.Stack; VAR M: Oberon.InputMsg);
VAR P: Panel; Fit: FitMsg;
BEGIN
	WITH T: Temp DO
		IF (M.dlink IS Panel) THEN
			P:= M.dlink(Panel);
			IF M.keys = {1} THEN
				Fit.F:= NIL; Fit.card:= T.tail.next; Fit.stack:= NIL; Fit.res:= -1;
				P.handle(P, Fit);
				IF Fit.stack # NIL THEN T.do.moveCard(T, Fit.stack, Fit.card, FALSE)
				END;
				WaitMouseRelease(M)
			ELSIF T.sel THEN
				IF M.keys = {2} THEN
					P.stack:= NIL; T(Temp).sel:= FALSE; Gadgets.Update(T)
				END;
				WaitMouseRelease(M)
			ELSE
				IF ~Cards.IsEmpty(T.tail) & (P.stack = NIL) THEN
					IF M.keys = {2} THEN
						P.stack:= T; P.count:= 1; P.card:= T.tail.next^; T.sel:= TRUE;
						Gadgets.Update(T)
					END;
					WaitMouseRelease(M)
				ELSIF Cards.IsEmpty(T.tail) & (P.stack # NIL) THEN
					IF M.keys = {2} THEN
						P.stack.do.moveCard(P.stack, T, P.stack.tail.next, FALSE)
					END;
					WaitMouseRelease(M)
				END
			END
		END
	END
END TrackTemp;

PROCEDURE TempHandler(T: Objects.Object; VAR M: Objects.ObjMsg);
VAR T0: Temp;
BEGIN
	WITH T: Temp DO
		IF (M IS FreeMsg) & Cards.IsEmpty(T.tail) THEN INC(M(FreeMsg).tempCnt)
		ELSIF M IS Objects.AttrMsg THEN TempAttr(T, M(Objects.AttrMsg))
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = T.stamp THEN M.obj := T.dlink	(* copy msg arrives again *)
				ELSE NEW(T0); T.stamp := M.stamp; T.dlink := T0; CopyTemp(M, T, T0); M.obj := T0
				END
			END
		ELSE Cards.StackHandler(T, M)
		END
	END;
END TempHandler;

PROCEDURE NewTemp*;
VAR T: Temp;
BEGIN
	NEW(T); Cards.InitStack(T);
	T.sel:= FALSE; T.handle:= TempHandler; T.do:= tempMethods;
	Objects.NewObj:= T
END NewTemp;

(*	-----------------------------	depot stuff	-----------------------------	*)

PROCEDURE DepotAttr(D: Depot; VAR M: Objects.AttrMsg);
BEGIN
	IF (M.id = Objects.get) & (M.name = "Gen") THEN
		M.class := Objects.String; COPY("Freecell.NewDepot", M.s); M.res := 0
	ELSE Cards.StackHandler(D, M);
	END
END DepotAttr;

PROCEDURE CopyDepot(VAR M: Objects.CopyMsg; from, to: Depot);
BEGIN Cards.CopyStack(M, from, to);
END CopyDepot;

PROCEDURE TrackDepot(D: Cards.Stack; VAR M: Oberon.InputMsg);
VAR P: Panel; card: Cards.Card; x, y: INTEGER; fit: BOOLEAN;
BEGIN
	WITH D: Depot DO
		IF (M.dlink IS Panel) THEN
			P:= M.dlink(Panel); x:= D.X+M.x; y:= D.Y+M.y; card:= D.tail.next;
			IF Effects.Inside(M.X, M.Y, x, y, CardW, CardH) & (P.stack # NIL) THEN
				IF Cards.IsEmpty(D.tail) & (P.card.nr = 0) THEN fit:= TRUE
				ELSIF (P.card.nr = card.nr+1) & (P.card.suit = card.suit) THEN fit:= TRUE
				ELSE fit:= FALSE
				END;
				IF fit & (M.keys = {2}) THEN
					P.stack.do.moveCard(P.stack, D, P.stack.tail.next, FALSE);
					WaitMouseRelease(M)
				ELSIF fit THEN Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, M.X, M.Y); M.res := 0
				ELSE Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y); M.res:= 0;
				END
			END
		END
	END
END TrackDepot;

PROCEDURE DepotHandler(D: Objects.Object; VAR M: Objects.ObjMsg);
VAR D0: Depot; c: Cards.Card;
BEGIN
	WITH D: Depot DO
		IF M IS FitMsg THEN
			WITH M: FitMsg DO
				c:= D.tail.next;
				IF Cards.IsEmpty(D.tail) & (M.card.nr = 0) THEN M.stack:= D
				ELSIF (M.card.nr = c.nr+1) & (M.card.suit = c.suit) THEN M.stack:= D
				END
			END
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
		M.class := Objects.String; COPY("Freecell.NewColumn", M.s); M.res := 0
	ELSE Cards.StackHandler(C, M);
	END
END ColumnAttr;

PROCEDURE CopyColumn(VAR M: Objects.CopyMsg; from, to: Column);
BEGIN
	to.nrCards:= from.nrCards;
	to.sel:= from.sel;
	Cards.CopyStack(M, from, to);
END CopyColumn;

PROCEDURE ColumnMoveCard(self, to: Cards.Stack; card: Cards.Card; undo: BOOLEAN);
	VAR S: SetSelectMsg;
BEGIN
	self(Column).sel:= FALSE;
	Cards.methods.moveCard(self, to, card, undo);
	S.res:= -1; S.F:= NIL; S.child:= self; S.stack:= NIL;
	Display.Broadcast(S)
END ColumnMoveCard;

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
				Cards.DrawCard(M, c, x, C.topY, CardW, DeltaH, C.bgNr); DEC(C.topY, DeltaH);
				c:= c.prev
			END;
			Cards.DrawCard(M, c, x, C.topY, CardW, CardH, C.bgNr);
			C.topY:= C.topY - y + C.Y
		END;
		IF C.sel THEN Display3.ReplConst(M, Display3.black, x, y-C.Y+C.topY-CardH, w, CardH, Display.invert) END;
		IF Gadgets.selected IN C.state THEN
			Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
		END
	END
END DrawColumn;

PROCEDURE TrackColumn(C: Cards.Stack; VAR M: Oberon.InputMsg);
VAR P: Panel; c, cc: Cards.Card; x, i, diff: INTEGER; dcol: BOOLEAN; F: FreeMsg; Fit: FitMsg;	
BEGIN
	WITH C: Column DO
		x:= C.X+M.x;
		IF Effects.Inside(M.X, M.Y, x, M.y+C.topY-CardH, CardW, C.H-(C.topY-C.Y)+CardH) & (M.dlink IS Panel) THEN
			P:= M.dlink(Panel);
			IF Cards.IsEmpty(C.tail) THEN
				IF P.stack # NIL THEN
					IF M.keys = {2} THEN
						c:= P.stack.tail;
						IF P.count > 1 THEN
							F.F:= NIL; F.res:= -1; F.tempCnt:= 0; F.columnCnt:= 0;
							P.handle(P, F);  
							i:= GetRowSize(F.columnCnt-1, F.tempCnt);
							IF i > P.count THEN i:= P.count END
						ELSE i := 1	(* invariant(P.count >= 1) *)
						END;
						REPEAT c:= c.next; DEC(i) UNTIL i = 0;
						P.stack.do.moveCard(P.stack, C, c, FALSE);
						WaitMouseRelease(M)
					ELSIF M.keys = {1} THEN
						P.stack.do.moveCard(P.stack, C, P.stack.tail.next, FALSE);
						WaitMouseRelease(M)
					ELSE
						Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, M.X, M.Y); M.res:= 0
					END
				END
			ELSIF M.keys = {1} THEN
				Fit.F:= NIL; Fit.card:= C.tail.next; Fit.stack:= NIL; Fit.res:= -1;
				P.handle(P, Fit);
				IF Fit.stack # NIL THEN C.do.moveCard(C, Fit.stack, Fit.card, FALSE)
				END;
				WaitMouseRelease(M)
			ELSIF C.sel THEN
				IF M.keys = {2} THEN	(* wants deselect this stack *)
					P.stack:= NIL; C.sel:= FALSE; Gadgets.Update(C)
				END;
				WaitMouseRelease(M)
			ELSE	(* wants to move cards or select a stack *)
				c:= C.tail.next;
				diff:= c.nr - P.card.nr;
				dcol:= (c.suit DIV 2) = (P.card.suit DIV 2);	(* same color *)
				dcol:= dcol = ~ODD(diff);	(* if same color, difference has to be even *)
				IF (P.stack # NIL) & (diff > 0) & (diff <= P.count) & dcol THEN
					IF M.keys = {2} THEN
						c:= P.stack.tail; REPEAT c:= c.next; DEC(diff) UNTIL diff = 0;
						P.stack.do.moveCard(P.stack, C, c, FALSE);
					END;
					WaitMouseRelease(M)
				ELSIF P.stack = NIL THEN
					IF M.keys = {2} THEN
						P.stack:= C; P.card:= C.tail.next^;
						F.F:= NIL; F.res:= -1; F.tempCnt:= 0; F.columnCnt:= 0;
						P.handle(P, F);
						diff:= GetRowSize(F.columnCnt, F.tempCnt);
						i:= 0; cc:= C.tail.next;
						REPEAT c:= cc; cc:= c.next; INC(i)
						UNTIL (i = diff) OR (c.nr # cc.nr-1) OR ((c.suit DIV 2) = (cc.suit DIV 2));
						P.count:= i;
						C.sel:= TRUE; Gadgets.Update(C)
					END;
					Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, M.X, M.Y);
					WaitMouseRelease(M)
				END
			END
		END
	END	(* WITH *)
END TrackColumn;

PROCEDURE ColumnHandler*(C: Objects.Object; VAR M: Objects.ObjMsg);
VAR C0: Column; c: Cards.Card; i: INTEGER;
BEGIN
	WITH C: Column DO
		IF M IS DistributeMsg THEN
			WITH M: DistributeMsg DO
				i:= C.nrCards; c:= M.tail;
				REPEAT c:= c.next; c.visible:= TRUE; DEC(i) UNTIL i = 0;
				Cards.RemoveCard(M.tail, c);
				Cards.AppendCard(C.tail, c); Gadgets.Update(C)
			END
		ELSIF M IS Cards.CollectMsg THEN Cards.StackHandler(C, M)
		ELSIF (M IS FreeMsg) & Cards.IsEmpty(C.tail) THEN INC(M(FreeMsg).columnCnt)
		ELSIF M IS Objects.AttrMsg THEN ColumnAttr(C, M(Objects.AttrMsg))
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Files.WriteInt(M.R, C.nrCards); Cards.StackHandler(C, M)
				ELSIF M.id = Objects.load THEN
					Files.ReadInt(M.R, C.nrCards); Cards.StackHandler(C, M)
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
	NEW(C); Cards.InitStack(C); C.handle:= ColumnHandler; C.H:= (CARDS DIV 5)*DeltaH + CardH;
	C.do:= columnMethods; C.topY:= 0; C.sel:= FALSE;
	Objects.NewObj:= C
END NewColumn;

(*	-----------------------------	panel stuff	-----------------------------	*)

PROCEDURE CopyPanel(VAR M: Objects.CopyMsg; from, to: Panel);
	VAR s: Display.Frame; c: Cards.Card;
BEGIN
	Panels.CopyPanel(M, from, to);
	to.card:= from.card; to.count:= from.count;
	s:= to.dsc;
	WHILE s # NIL DO
		IF s IS Cards.Stack THEN
			WITH s: Cards.Stack DO
				c:= s.tail.next;
				IF (c.nr = to.card.nr) & (c.suit = to.card.suit) THEN to.stack:= s END
			END
		END;
		s:= s.next
	END
END CopyPanel;

PROCEDURE PanelHandler(P: Objects.Object; VAR M: Objects.ObjMsg);
	VAR P0: Panel;
BEGIN
	WITH P: Panel DO
		IF (M IS SetSelectMsg) THEN
			WITH M: SetSelectMsg DO
				IF Panels.IsChild(P, M.child) THEN
					P.stack:= M.stack;
					IF M.stack # NIL THEN P.card:= M.stack.tail.next^END
				END
			END
		ELSIF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF (M.id = Objects.get) & (M.name = "Gen") THEN
					M.class := Objects.String; COPY("Freecell.NewPanel", M.s); M.res:= 0
				ELSE Panels.PanelHandler(P, M)
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = P.stamp THEN M.obj := P.dlink	(* copy msg arrives again *)
				ELSE NEW(P0); P.stamp := M.stamp; P.dlink := P0; CopyPanel(M, P, P0); M.obj := P0
				END
			END
		ELSE Panels.PanelHandler(P, M)
		END
	END
END PanelHandler;

PROCEDURE NewPanel*;
VAR P: Panel;
BEGIN
	NEW(P); Panels.InitPanel(P); P.handle:= PanelHandler;
	P.stack:= NIL; P.count:= 0;
	Objects.NewObj:= P
END NewPanel;

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
		obj:= Gadgets.CreateObject("Freecell.NewPanel"); main:= obj(Gadgets.Frame);
		main.W:= 14+COLUMN*(CardW+2); main.H:= 4*CardH;
		A.res:= -1; A.class:= Objects.Int; A.name:= "Color"; A.i:= Cards.backC; main.handle(main, A);
	
		obj:= Gadgets.CreateObject("Cards.NewStack"); talon:= obj(Cards.Stack);
		FOR i:= 0 TO CARDS-1 DO
			Cards.AppendCard(talon.tail, Cards.NewCard(i DIV 13, i MOD 13, TRUE))
		END;
		Cards.Shuffle(talon.tail);

		C.obj:= NIL;
		FOR i:= 0 TO 3 DO
			obj:= Gadgets.CreateObject("Freecell.NewTemp"); stack:= obj(Cards.Stack);
			stack.X:= i*(CardW+2); stack.Y:= -5-stack.H; stack.slink:= C.obj; C.obj:= stack
		END;

		FOR i:= 1 TO 4 DO
			obj:= Gadgets.CreateObject("Freecell.NewDepot"); stack:= obj(Cards.Stack);
			stack.X:= main.W-4-i*(CardW+2); stack.Y:= -5-stack.H; stack.slink:= C.obj; C.obj:= stack
		END;
		Y:= stack.Y;
		
		FOR i:= 0 TO 3 DO
			obj:= Gadgets.CreateObject("Freecell.NewColumn"); stack:= obj(Cards.Stack);
			stack.X:= 4+i*(CardW+2); stack.Y:= Y-10-stack.H; stack.slink:= C.obj; C.obj:= stack;
			stack(Column).nrCards:= 7;
			c:= talon.tail; FOR k:= 0 TO 6 DO c:= c.next; c.visible:= TRUE END;
			Cards.RemoveCard(talon.tail, c); Cards.AppendCard(stack.tail, c);
		END;
		FOR i:= 4 TO 7 DO
			obj:= Gadgets.CreateObject("Freecell.NewColumn"); stack:= obj(Cards.Stack);
			stack.X:= 4+i*(CardW+2); stack.Y:= Y-10-stack.H; stack.slink:= C.obj; C.obj:= stack;
			stack(Column).nrCards:= 6;
			c:= talon.tail; FOR k:= 0 TO 5 DO c:= c.next; c.visible:= TRUE END;
			Cards.RemoveCard(talon.tail, c); Cards.AppendCard(stack.tail, c);
		END;
		Y:= stack.Y; main.H:= -Y+10;

		C.res:= -1; C.x:= 0; C.y:= 0; C.F:= main; C.u:= 3; C.v:= Y; main.handle(main, C);
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
			Files.WriteInt(R, Documents.Id); Files.WriteString(R, "Freecell.NewDoc");
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
			WITH M: Objects.AttrMsg DO				IF M.id = Objects.get THEN
					IF M.name = "Gen" THEN M.class:= Objects.String; M.s:= "Freecell.NewDoc"; M.res:= 0
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

BEGIN
	Out.String("Freecell by P. Saladin "); Out.String(Version); Out.Ln;

	rowSize[0][0]:= 1; rowSize[0][1]:= 2; rowSize[0][2]:= 3; rowSize[0][3]:= 4;  rowSize[0][4]:= 5;
	rowSize[1][0]:= 2; rowSize[1][1]:= 4; rowSize[1][2]:= 6; rowSize[1][3]:= 8;  rowSize[1][4]:= 10;
	rowSize[2][0]:= 4; rowSize[2][1]:= 8; rowSize[2][2]:= 12; rowSize[2][3]:= 13;  rowSize[2][4]:= 13;
	rowSize[3][0]:= 7; rowSize[3][1]:= 12; rowSize[3][2]:= 13; rowSize[3][3]:= 13;  rowSize[3][4]:= 13;
	rowSize[4][0]:= 11; rowSize[4][1]:= 13; rowSize[4][2]:= 13; rowSize[4][3]:= 13;  rowSize[4][4]:= 13;
	
	NEW(tempMethods); tempMethods^:= Cards.methods^;
		tempMethods.moveCard:= TempMoveCard;
		tempMethods.restoreStack:= DrawTemp; tempMethods.trackMouse:= TrackTemp;
	NEW(depotMethods); depotMethods^:= Cards.methods^;
		depotMethods.trackMouse:= TrackDepot;
	NEW(columnMethods); columnMethods^:= Cards.methods^;
		columnMethods.moveCard:= ColumnMoveCard;
		columnMethods.restoreStack:= DrawColumn; columnMethods.trackMouse:= TrackColumn; 
END Freecell.
