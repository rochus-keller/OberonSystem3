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

MODULE Spider;	(** portable *)	(** written by Patrick Saladin   *)
(*
	14.04.95	fixed bug  redraw of cards and mouse cursor
	05.03.95	updated to Oberon System 3 V2.0
						changed msgs back to FrameMsg
	06.10.94	release of a good beta (V1.0)
*)

IMPORT Files, Input, Display, Display3, Effects, Objects, Gadgets, Oberon, Cards, Documents, Desktops, Out;

CONST
	IconName = "Icons2.Spider";
	MenuString = "Cards.Undo[Undo] Spider.New[New] Desktops.StoreDoc[Store]";
	Version = "V 1.2";

	CardW = Cards.CardW; CardH = Cards.CardH;
	DeltaH = 13; DeltaHH = 5;
	CARDS = 104;	COLUMN = 10;
	
TYPE
	DistribMove = POINTER TO DistribMoveDesc;
	DistribMoveDesc = RECORD (Cards.MoveDesc)
		to: ARRAY  COLUMN OF Cards.Stack;
	END;

	SimpleMove = POINTER TO SimpleMoveDesc;
	SimpleMoveDesc = RECORD (Cards.SimpleMoveDesc)
		flipped: BOOLEAN;
	END;

	TakeCardMsg = RECORD (Display.FrameMsg)
		tail: Cards.Card
	END;

	CanDistrMsg = RECORD (Display.FrameMsg)
		myRes, allowEmpty: BOOLEAN;
	END;
	
	DistributeMsg = RECORD (Display.FrameMsg)
		tail: Cards.Card;
		to: ARRAY COLUMN OF Cards.Stack;
		index: INTEGER;
	END;
	
	FitMsg = RECORD (Display.FrameMsg)
		this: Cards.Card;
		on: Cards.Stack;
	END;
	
	Talon = POINTER TO TalonDesc;
	TalonDesc = RECORD (Cards.StackDesc)
	END;
	
	Depot = POINTER TO DepotDesc;
	DepotDesc = RECORD (Cards.StackDesc)
	END;
	
	Column = POINTER TO ColumnDesc;
	ColumnDesc = RECORD (Cards.StackDesc)
		topY: INTEGER;	(* left, top corner of top card *)
		nrCards: INTEGER;	(* nr of cards at beginning *)
		first: BOOLEAN;
	END;

VAR 
	talonMethods: Cards.Methods;
	depotMethods: Cards.Methods;
	columnMethods: Cards.Methods;
	king: Cards.Card;

(*	-----------------------------	aux procedures	-----------------------------	*)
	
PROCEDURE StartGame(F: Display.Frame);
VAR C: Cards.CollectMsg; T: TakeCardMsg; D: DistributeMsg;
BEGIN C.res:= -1; T.res:= -1; D.res:= -1;
	C.tail:= Cards.NewTail(); F.handle(F, C);
	Cards.Shuffle(C.tail);
	D.tail:= C.tail; D.index:= 0; F.handle(F, D);
	T.tail:= C.tail; F.handle(F, T)
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
	UNTIL M.keys = {}
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
	IF (M.id = Objects.get) & (M.name = "Gen") THEN
		M.class := Objects.String; COPY("Spider.NewTalon", M.s); M.res := 0
	ELSE Cards.StackHandler(T, M)
	END
END TalonAttr;

PROCEDURE CopyTalon(VAR M: Objects.CopyMsg; from, to: Talon);
BEGIN Cards.CopyStack(M, from, to);
END CopyTalon;

PROCEDURE TalonUndoMove(T: Cards.Stack; M: Cards.Move);
VAR S: Cards.Stack; i: INTEGER;
BEGIN
	WITH M: DistribMove DO
		FOR i:= COLUMN-1 TO 0 BY -1 DO
			S:= M.to[i]; S.tail.next.visible:= FALSE;
			S.do.moveCard(S, T, S.tail.next, TRUE)
		END;
	END
END TalonUndoMove;

PROCEDURE TrackTalon(T: Cards.Stack; VAR M: Oberon.InputMsg);
VAR DM: DistribMove; x, y, i: INTEGER; CD: CanDistrMsg; D: DistributeMsg;
BEGIN
	WITH T: Talon DO
		x:= T.X+M.x; y:= T.Y+M.y;
		IF ~Cards.IsEmpty(T.tail) & Effects.Inside(M.X, M.Y, x, y, CardW, CardH) THEN
			IF M.keys = {2} THEN
				CD.myRes:= TRUE; CD.allowEmpty:= TRUE; CD.res:= -1; M.dlink.handle(M.dlink, CD);
				IF CD.myRes THEN D.res:= -1;
					D.tail:= T.tail; D.index:= 0; M.dlink.handle(M.dlink, D); Gadgets.Update(T);
					NEW(DM); FOR i:= 0 TO COLUMN-1 DO DM.to[i]:= D.to[i] END;
					Cards.AppendMove(T, DM)
				END;
				WaitMouseRelease(M)
			ELSE Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, M.X, M.Y)
			END;
			M.res := 0
		END
	END
END TrackTalon;

PROCEDURE TalonHandler(T: Objects.Object; VAR M: Objects.ObjMsg);
VAR T0: Talon; c: Cards.Card;
BEGIN
	WITH T: Talon DO
		IF M IS TakeCardMsg THEN
			WITH M: TakeCardMsg DO
				c:= M.tail.prev; Cards.RemoveCard(M.tail, c); Cards.AppendCard(T.tail, c);
				Gadgets.Update(T)
			END
		ELSIF M IS Objects.AttrMsg THEN TalonAttr(T, M(Objects.AttrMsg))
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
	NEW(T); Cards.InitStack(T);
	T.handle:= TalonHandler; T.do:= talonMethods;
	Objects.NewObj:= T
END NewTalon;

(*	-----------------------------	depot stuff	-----------------------------	*)

PROCEDURE DepotAttr(D: Depot; VAR M: Objects.AttrMsg);
BEGIN
	IF (M.id = Objects.get) & (M.name = "Gen") THEN
		M.class := Objects.String; COPY("Spider.NewDepot", M.s); M.res := 0
	ELSE Cards.StackHandler(D, M);
	END
END DepotAttr;

PROCEDURE CopyDepot(VAR M: Objects.CopyMsg; from, to: Depot);
BEGIN Cards.CopyStack(M, from, to);
END CopyDepot;

PROCEDURE DepotCanDrop(D: Cards.Stack; card: Cards.Card): BOOLEAN;
VAR c: Cards.Card; res: BOOLEAN;
BEGIN
	res:= Cards.IsEmpty(D.tail) & (card.nr = 12);
	WHILE res  & (card.nr # 0) DO
		c:= card.prev;
		res:= res & (card.nr = c.nr+1) & (card.suit = c.suit) & c.visible;
		card:= c
	END;
	RETURN res
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
		M.class := Objects.String; COPY("Spider.NewColumn", M.s); M.res := 0
	ELSE Cards.StackHandler(C, M);
	END
END ColumnAttr;

PROCEDURE CopyColumn(VAR M: Objects.CopyMsg; from, to: Column);
BEGIN
	to.nrCards:= from.nrCards;
	to.first:= from.first;
	Cards.CopyStack(M, from, to);
END CopyColumn;

PROCEDURE CanDropColumn(C: Cards.Stack; card: Cards.Card): BOOLEAN;
VAR c: Cards.Card; res: BOOLEAN;
BEGIN
	IF Cards.IsEmpty(C.tail) THEN RETURN TRUE END;
	c:= C.tail.next;
	res:= (card.nr = c.nr-1) & c.visible;
	c:= card; card:= card.prev;
	WHILE res & card.visible DO
		res:= res & (card.nr = c.nr-1) & (card.suit = c.suit);
		c:= card; card:= card.prev
	END;
	RETURN res
END CanDropColumn;

PROCEDURE ColumnMoveCard(self, to: Cards.Stack; card: Cards.Card; undo: BOOLEAN);
VAR SM: SimpleMove;
BEGIN
	Cards.methods.moveCard(self, to, card, TRUE);
	IF ~undo THEN
		NEW(SM); SM.card:= card; SM.to:= to;
		SM.flipped:= ~self.tail.next.visible; Cards.AppendMove(self, SM);
		IF ~self.tail.next.visible THEN self.tail.next.visible:= TRUE; Gadgets.Update(self) END
	END
END ColumnMoveCard;

PROCEDURE ColumnUndoMove(C: Cards.Stack; M: Cards.Move);
BEGIN
	C.tail.next.visible:= ~M(SimpleMove).flipped;
	Cards.methods.undoMove(C, M)
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
VAR c, cc: Cards.Card; x, y, dH: INTEGER;
BEGIN
	WITH C: Column DO
		x:= C.X+M.x; y:= C.Y+M.y;
		c:= C.tail.next; cc:= c.next; dH:= 0; C.tail.visible:= FALSE;
		WHILE (c.suit = cc.suit) & (c.nr = cc.nr-1) & cc.visible DO
			INC(dH, DeltaH); c:= cc; cc:= cc.next
		END;
		IF ~Cards.IsEmpty(C.tail) & (M.keys = {1}) & C.tail.next.visible THEN
			c:= C.tail.next; cc:= c.next; 
			WHILE cc.visible & (cc.suit = c.suit) & (cc.nr = c.nr+1) DO c:= cc; cc:= cc.next END;
			DropOnFittingStack(M, c, C);
			M.res:= 0
		ELSIF ~Cards.IsEmpty(C.tail) & Effects.Inside(M.X, M.Y, x, C.topY+M.y-CardH, CardW, CardH+dH) THEN
			IF M.keys = {2} THEN
				c:= C.tail.next; y:= M.y + C.topY; WHILE y < M.Y DO INC(y, DeltaH); c:= c.next END;
				Cards.TrackMove(M, x, C.topY+M.y-CardH, C, c, DrawRect, DrawRect)
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
		IF M IS FitMsg THEN
			WITH M: FitMsg DO
				IF (M.on = NIL) THEN IF C.do.canDrop(C, M.this) THEN M.on:= C END
				ELSIF M.on IS Column THEN
					c:= C.tail.next;
					IF Cards.IsEmpty(M.on.tail) & (c.nr-1 = M.this.nr) THEN M.on:= C
					ELSIF (c.suit = M.this.suit) & (c.nr-1 = M.this.nr) THEN M.on:= C
					END
				END
			END
			ELSIF M IS CanDistrMsg THEN
			WITH M: CanDistrMsg DO
				IF M.myRes THEN
					IF ~M.allowEmpty THEN M.myRes:= ~Cards.IsEmpty(C.tail)
					ELSE
						c:= C.tail.prev;
						WHILE c.visible & (c.suit = c.prev.suit) & (c.nr-1 = c.prev.nr) DO c:= c.prev END;
						M.allowEmpty:= (c = C.tail.next)
					END
				END
			END
		ELSIF M IS DistributeMsg THEN
			WITH M: DistributeMsg DO
				IF C.first THEN
					C.first:= FALSE; i:= C.nrCards; c:= M.tail;
					REPEAT c:= c.next; DEC(i) UNTIL i = 0
				ELSE c:= M.tail.next
				END;
				M.to[M.index]:= C; INC(M.index);
				Cards.RemoveCard(M.tail, c); c.next.visible:= TRUE;
				Cards.AppendCard(C.tail, c); Gadgets.Update(C)
			END
		ELSIF M IS Cards.CollectMsg THEN C.first:= TRUE; Cards.StackHandler(C, M)
		ELSIF M IS Objects.AttrMsg THEN ColumnAttr(C, M(Objects.AttrMsg))
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Files.WriteInt(M.R, C.nrCards); Files.WriteBool(M.R, C.first); Cards.StackHandler(C, M)
				ELSIF M.id = Objects.load THEN
					Files.ReadInt(M.R, C.nrCards); Files.ReadBool(M.R, C.first); Cards.StackHandler(C, M)
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
	C.do:= columnMethods; C.topY:= 0; C.first:= TRUE;
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
		main.W:= 10+10*(CardW+2); main.H:= 4*CardH;
		A.res:= -1; A.class:= Objects.Int; A.name:= "Color"; A.i:= Cards.backC; main.handle(main, A);
	
		obj:= Gadgets.CreateObject("Spider.NewTalon"); talon:= obj(Cards.Stack);
		talon.X:= 5; talon.Y:= -5-talon.H; talon.slink:= NIL; C.obj:= talon;
		FOR i:= 0 TO CARDS-1 DO
			Cards.AppendCard(talon.tail, Cards.NewCard(i DIV 26, i MOD 13, FALSE))
		END;
		Cards.Shuffle(talon.tail);
		Y:= talon.Y;
		
		FOR i:= 1 TO 8 DO
			obj:= Gadgets.CreateObject("Spider.NewDepot"); stack:= obj(Cards.Stack);
			stack.X:= main.W-5-i*(CardW+2); stack.Y:= -5-stack.H; stack.slink:= C.obj; C.obj:= stack
		END;

		FOR i:= 0 TO COLUMN-1 DO
			obj:= Gadgets.CreateObject("Spider.NewColumn"); stack:= obj(Cards.Stack);
			stack.X:= 5+i*(CardW+2); stack.Y:= Y-10-stack.H; stack.slink:= C.obj; C.obj:= stack;
			stack(Column).nrCards:= 4 + (((i + 1) MOD 3) MOD 2);
			k:= stack(Column).nrCards; c:= talon.tail;
			REPEAT c:= c.next; DEC(k) UNTIL k = 0;
			Cards.RemoveCard(talon.tail, c); c.next.visible:= TRUE; Cards.AppendCard(stack.tail, c);
			stack(Column).first:= FALSE
		END;
		Y:= stack.Y; main.H:= -Y+10;

		C.res:= -1; C.x:= 0; C.y:= 0; C.F:= main; C.u:= 5; C.v:= Y; main.handle(main, C);
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
			Files.WriteInt(R, Documents.Id); Files.WriteString(R, "Spider.NewDoc");
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
					IF M.name = "Gen" THEN M.class:= Objects.String; M.s:= "Spider.NewDoc"; M.res:= 0
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
	Out.String("Spider by P. Saladin "); Out.String(Version); Out.Ln;

	king:= Cards.NewCard(0, 12, TRUE); king.next:= king; king.prev:= king;
	NEW(talonMethods); talonMethods^:= Cards.methods^;
		talonMethods.trackMouse:= TrackTalon; talonMethods.undoMove:= TalonUndoMove;
	NEW(depotMethods); depotMethods^:= Cards.methods^;
		depotMethods.canDrop:= DepotCanDrop;
	NEW(columnMethods); columnMethods^:= Cards.methods^;
		columnMethods.canDrop:= CanDropColumn; columnMethods.moveCard:= ColumnMoveCard;
		columnMethods.undoMove:= ColumnUndoMove;
		columnMethods.restoreStack:= DrawColumn; columnMethods.trackMouse:= TrackColumn; 
END Spider.
