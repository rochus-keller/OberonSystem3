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

MODULE Cards;	(** portable *)	(** written by Patrick Saladin   *)
(* a basic module to implement card games like Solitaire
	05.03.95	updated to Oberon System 3 V2.0
						changed CollectMsg back to FrameMsg
	06.10.94	added Undo-funktionality 
	06.10.94	changed CollectMsg: is now an ObjMsg and no longer a FrameMsg
*)

IMPORT
	Input, Files, Display, Display3, Objects, Effects, Oberon, Pictures, Attributes, Gadgets, Panels, Desktops;
	
CONST
	(* cards size *)
	(* CardW* = 71;	CardH* = 96; *)
	CardW* = 50; CardH* = 68;
	
	(* colours *)
	topC* = 2; backC* = 8;
	
TYPE
	Card* = POINTER TO CardDesc;
	CardDesc* = RECORD
		next*, prev*: Card;
		suit*, nr*: INTEGER;
		visible*: BOOLEAN;
	END;

	Move* = POINTER TO MoveDesc;
	MoveDesc* = RECORD
		next: Move;
		time: LONGINT;
	END;

	Stack* = POINTER TO StackDesc;
	Methods* = POINTER TO MethodBlock;

	StackDesc* = RECORD (Gadgets.FrameDesc)
		move: Move;
		tail*: Card;
		do*: Methods;
		bgNr*: INTEGER;
	END;

	MethodBlock* = RECORD
		canDrop*: PROCEDURE (S: Stack; C: Card): BOOLEAN;
		dropCard*: PROCEDURE (S: Stack; C: Card);
		moveCard*: PROCEDURE (self, to: Stack; C: Card; undo: BOOLEAN);
		undoMove*: PROCEDURE (S: Stack; M: Move);
		restoreStack*: PROCEDURE (S:Stack; M: Display3.Mask; x, y, w, h: INTEGER);
		trackMouse*: PROCEDURE (S: Stack; VAR M: Oberon.InputMsg);
	END;
	
	SimpleMove * = POINTER TO SimpleMoveDesc;
	SimpleMoveDesc* = RECORD (MoveDesc)
		to*: Stack;
		card*: Card;
	END;

	CollectMsg* = RECORD (Display.FrameMsg)
		tail*: Card;
	END;
	
	UndoMsg* = RECORD (Display.FrameMsg)
		time: LONGINT;
		stack: Stack;
	END;
	
	BGMsg* = RECORD (Display.FrameMsg)
		bgNr*: INTEGER;
	END;
	
VAR
	methods*: Methods;
	seed: LONGINT;
	cardPicts: Pictures.Picture;
	
(*	-----------------------------	auxiliary procs	-----------------------------	*)

PROCEDURE Random*(range: LONGINT): LONGINT;
CONST a = 16807; m = 2147483647; q = m DIV a; r = m MOD a;
VAR g: LONGINT;
BEGIN
	g:= a*(seed MOD q) - r*(seed DIV q);
	IF g > 0 THEN seed:= g ELSE seed:= g + m END;
	RETURN ENTIER(seed*(1.0/m)*range)
END Random;

PROCEDURE Shuffle*(tail: Card);
VAR c: Card; i, r: INTEGER;
BEGIN
	c:= tail.next; r:= 0;
	WHILE c # tail DO c.visible:= FALSE; c:= c.next; INC(r) END;
	WHILE r > 0 DO
		i:= SHORT(Random(r));
		c:= tail.next;
		WHILE i > 0 DO c:= c.next; DEC(i) END;
		c.prev.next:= c.next; c.next.prev:= c.prev;
		c.prev:= tail.prev; c.next:= tail; tail.prev:= c; c.prev.next:= c;
		DEC(r)
	END
END Shuffle;

PROCEDURE TrackMove*(VAR M: Oberon.InputMsg;  x, y: INTEGER; self: Stack; card: Card;
																draw, fade: PROCEDURE (x, y: INTEGER; card: Card));
VAR F: Display.Frame; keysum: SET; oX, oY, u, v: INTEGER;
BEGIN
	oX:= M.X; oY:= M.Y; keysum:= M.keys; draw(x, y, card);
	REPEAT
		Oberon.DrawCursor(Oberon.Mouse, Effects.FlatHand, M.X, M.Y);
		Input.Mouse(M.keys, M.X, M.Y); keysum:= keysum + M.keys;
		IF (oX # M.X) OR (oY # M.Y) THEN
			fade(x, y, card);
			INC(x, M.X-oX); INC(y, M.Y-oY); oX:= M.X; oY:= M.Y;
			draw(x, y, card)
		END
	UNTIL M.keys = {};
	fade(x, y, card);
	IF keysum = {2} THEN	(* left mouse *)
		Gadgets.ThisFrame(M.X, M.Y, F, u, v);
		IF (F # NIL) & (F IS Stack) & Panels.IsChild(M.dlink(Display.Frame), F) THEN
			IF F(Stack).do.canDrop(F(Stack), card) THEN self.do.moveCard(self, F(Stack), card, FALSE) END
		END
	END
END TrackMove;

(*	-----------------------------	card stuff	-----------------------------	*)

PROCEDURE DrawCard*(R: Display3.Mask; card: Card; x, y, w, h, bgNr: INTEGER);
(* x, y top left corner *)
VAR px, py: INTEGER;
BEGIN
	y:= y-h;
	IF  card.visible THEN px:= card.nr*CardW; py:= (5-card.suit)*CardH-h
	ELSE px:= bgNr*CardW; py:= CardH-h
	END;
	Display3.Pict(R, cardPicts, px, py, w, h, x, y, Display.replace)
END DrawCard;

PROCEDURE NewCard*(suit, nr: INTEGER; visible: BOOLEAN): Card;
VAR card: Card;
BEGIN
	NEW(card);
	card.next:= card; card.prev:= card;
	card.suit:= suit; card.nr:= nr; card.visible:= visible;
	RETURN card
END NewCard;

PROCEDURE CloneCard*(card: Card): Card;
BEGIN
	IF card = NIL THEN RETURN NIL
	ELSE RETURN NewCard(card.suit, card.nr, card.visible)
	END
END CloneCard;

PROCEDURE WriteCard*(VAR R: Files.Rider; card: Card);
BEGIN
	IF card = NIL THEN Files.WriteInt(R, -1)
	ELSE
		Files.WriteInt(R, card.suit); Files.WriteInt(R, card.nr);
		Files.WriteBool(R, card.visible)
	END
END WriteCard;

PROCEDURE ReadCard*(VAR R: Files.Rider; VAR card: Card);
VAR suit, nr: INTEGER; vis: BOOLEAN;
BEGIN
	Files.ReadInt(R, suit);
	IF suit = -1 THEN card:= NIL
	ELSE
		Files.ReadInt(R, nr); Files.ReadBool(R, vis);
		card:= NewCard(suit,nr, vis)
	END
END ReadCard;

PROCEDURE NewTail*(): Card;
VAR tail: Card;
BEGIN
	NEW(tail); tail.visible:= FALSE; tail.suit:= -1; tail.nr:= -1; tail.next:= tail; tail.prev:= tail;
	RETURN tail
END NewTail;

(*	-----------------------------	stack stuff	-----------------------------	*)

PROCEDURE IsEmpty*(tail: Card): BOOLEAN;
BEGIN RETURN tail.next = tail
END IsEmpty;

PROCEDURE RemoveCard*(tail: Card; card: Card);
VAR c: Card;
BEGIN
	IF card # NIL THEN
		c:= tail.next;
		tail.next:= card.next; card.next.prev:= tail;
		card.next:= c; c.prev:= card
	END
END RemoveCard;

PROCEDURE AppendCard*(tail: Card; card: Card);
VAR c: Card;
BEGIN
	IF card # NIL THEN
		c:= card.next;
		tail.next.prev:= card; card.next:= tail.next;
		tail.next:= c; c.prev:= tail 
	END
END AppendCard;

(*	-----------------------------	move procs	-----------------------------	*)

PROCEDURE AppendMove*(S: Stack; M: Move);
BEGIN
	M.time:= Oberon.Time();
	M.next:= S.move; S.move:= M
END AppendMove;

PROCEDURE ClearMoves*(S: Stack);
BEGIN S.move:= NIL
END ClearMoves;

(*	-----------------------------	basic methods	-----------------------------	*)

PROCEDURE CanDropCard(S: Stack; card: Card): BOOLEAN;
BEGIN RETURN FALSE
END CanDropCard;

PROCEDURE DropCard(S: Stack; card: Card);
BEGIN AppendCard(S.tail, card); Gadgets.Update(S)
END DropCard;

PROCEDURE MoveCard(self, to: Stack; card: Card; undo: BOOLEAN);
VAR M: SimpleMove;
BEGIN
	RemoveCard(self.tail, card); Gadgets.Update(self);
	IF ~undo THEN NEW(M); M.card:= card; M.to:= to; AppendMove(self, M) END;
	to.do.dropCard(to, card); Gadgets.Update(to)
END MoveCard;

PROCEDURE UndoMove(S: Stack; M: Move);
BEGIN
	IF M IS SimpleMove THEN
		WITH M: SimpleMove DO
			M.to.do.moveCard(M.to, S, M.card, TRUE)
		END
	END
END UndoMove;

PROCEDURE DrawStack(S: Stack; M: Display3.Mask; x, y, w, h: INTEGER);
BEGIN
	Oberon.RemoveMarks(x, y, w, h);
	Display3.ReplConst(M, backC, x, y, w, h, Display.replace);
	IF IsEmpty(S.tail) THEN Display3.Rect3D(M, Display3.bottomC, topC, x, y+h-CardH, CardW, CardH, 1, Display.replace)
	ELSE DrawCard(M, S.tail.next, x, y+h, CardW, CardH, S.bgNr);
	END;
	IF Gadgets.selected IN S.state THEN
		Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
	END
END DrawStack;

PROCEDURE TrackMouse(S: Stack; VAR M: Oberon.InputMsg);
BEGIN
END TrackMouse;

(*	-----------------------------	gatdet proc	-----------------------------	*)

PROCEDURE StackAttr(S: Stack; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class := Objects.String; COPY("Cards.NewStack", M.s); M.res := 0
		ELSIF M.name = "Background" THEN M.class := Objects.Int; M.i := S.bgNr; M.res := 0 
		ELSE Gadgets.framehandle(S, M)
		END
	ELSIF M.id = Objects.set THEN
		IF M.name = "Background" THEN
			IF M.class = Objects.Int THEN S.bgNr:= SHORT(M.i); M.res := 0 END;
		ELSE Gadgets.framehandle(S, M);
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("Background"); Gadgets.framehandle(S, M)
	END
END StackAttr;

PROCEDURE PrintStack(S: Stack; VAR M: Display.DisplayMsg);
VAR R: Display3.Mask;
BEGIN Gadgets.MakePrinterMask(S, M.x, M.y, M.dlink, R)
END PrintStack;

PROCEDURE CopyStack*(VAR M: Objects.CopyMsg; from, to: Stack);
VAR c: Card;
BEGIN
	to.bgNr:= from.bgNr; to.tail:= NewTail(); to.do:= from.do;
	c:= from.tail.prev;
	WHILE c # from.tail DO AppendCard(to.tail, CloneCard(c)); c:= c.prev END;
	Gadgets.CopyFrame(M, from, to)
END CopyStack;

PROCEDURE StackHandler*(S: Objects.Object; VAR M: Objects.ObjMsg);
VAR x, y, w, h: INTEGER; S0: Stack; c: Card; R: Display3.Mask;
BEGIN
	WITH S: Stack DO
		IF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF (M.F = NIL) OR (M.F = S) THEN	(* message addressed to this frame *)
					x := M.x + S.X; y := M.y + S.Y; w := S.W; h := S.H; (* calculate display coordinates *)
					IF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg  DO
							IF M.device = Display.screen THEN
								IF (M.id = Display.full) OR (M.F = NIL) THEN
									Gadgets.MakeMask(S, x, y, M.dlink, R);
									S.do.restoreStack(S, R, x, y, w, h)
								ELSIF M.id = Display.area THEN
									Gadgets.MakeMask(S, x, y, M.dlink, R);
									Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
									S.do.restoreStack(S, R, x, y, w, h)
								END
							ELSIF M.device = Display.printer THEN PrintStack(S, M)
							END
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) & Gadgets.InActiveArea(S, M) THEN
								S.do.trackMouse(S, M);
								IF M.res < 0 THEN Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y); M.res:= 0 END
							ELSE Gadgets.framehandle(S, M)
							END
						END
					ELSIF M IS CollectMsg THEN
						ClearMoves(S);
						IF ~IsEmpty(S.tail) THEN
							c:= S.tail.prev; RemoveCard(S.tail, c); AppendCard(M(CollectMsg).tail, c); Gadgets.Update(S)
						END
					ELSIF M IS UndoMsg THEN
						WITH M: UndoMsg DO
							IF (S.move # NIL) & (M.time < S.move.time) THEN M.time:= S.move.time; M.stack:= S END
						END
					ELSIF M IS BGMsg THEN S.bgNr:= M(BGMsg).bgNr; Gadgets.Update(S)
					ELSE Gadgets.framehandle(S, M)
					END
				END
			END
		ELSIF M IS Objects.AttrMsg THEN StackAttr(S, M(Objects.AttrMsg))
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					c:= S.tail.prev;
					WHILE c # S.tail DO WriteCard(M.R, c); c:= c.prev END;
					WriteCard(M.R, NIL);	(* sentinell *)
					Files.WriteInt(M.R, S.bgNr);
					Gadgets.framehandle(S, M)
				ELSIF M.id = Objects.load THEN
					REPEAT ReadCard(M.R, c); AppendCard(S.tail, c) UNTIL c = NIL;
					Files.ReadInt(M.R, S.bgNr);
					Gadgets.framehandle(S, M)
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = S.stamp THEN M.obj := S.dlink	(* copy msg arrives again *)
				ELSE NEW(S0); S.stamp := M.stamp; S.dlink := S0; CopyStack(M, S, S0); M.obj := S0
				END
			END
		ELSE Gadgets.framehandle(S, M)
		END
	END
END StackHandler;

PROCEDURE InitStack*(S: Stack);
BEGIN
	S.tail:= NewTail();
	S.W:= CardW; S.H:= CardH; S.handle:= StackHandler; S.do:= methods; S.move:= NIL;
	S.bgNr:= 0
END InitStack;

PROCEDURE NewStack*;
VAR stack: Stack;
BEGIN
	NEW(stack); InitStack(stack);
	Objects.NewObj:= stack
END NewStack;

(*	-----------------------------	commands	-----------------------------	*)

PROCEDURE SetBG*;
VAR S: Attributes.Scanner; B: BGMsg;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Attributes.Scan(S);
	IF (S.class = Attributes.Int) & (S.i >= 0) & (S.i < 9) THEN
		B.bgNr:= SHORT(S.i); B.F:= NIL; Display.Broadcast(B) 
	END
END SetBG;

PROCEDURE Undo*;
VAR F: Display.Frame; S: Stack; U: UndoMsg;
BEGIN
	 F:= Desktops.CurDoc(Gadgets.context);
	 U.res:= -1; U.time:= -1; U.stack:= NIL; F.dsc.handle(F.dsc, U);
	 IF U.stack # NIL THEN
	 	S:= U.stack;
	 	IF S.move # NIL THEN S.do.undoMove(S, S.move); S.move:= S.move.next END
	 END
END Undo;

BEGIN
	NEW(methods);
	methods.canDrop:= CanDropCard; methods.dropCard:= DropCard; methods.moveCard:= MoveCard;
	methods.undoMove:= UndoMove; methods.restoreStack:= DrawStack; methods.trackMouse:= TrackMouse;
	seed:= Oberon.Time();
	NEW(cardPicts); Pictures.Open(cardPicts, "Cards.Pict", TRUE)
END Cards.

