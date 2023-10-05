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

MODULE Outlines;	(** portable *)	(*	code written by P. Saladin	June 1994/modified jm 14.12.94	*)	

IMPORT
	Files, Texts, Objects, Display, Display3, Printer, Printer3, Effects, Attributes, Gadgets,
	Oberon, Documents, Desktops, Out;
	
CONST
	open* = 0; close* = 1; folded* = 2; 
	tempOpen* = 3; 	(* states *)
	openMode* = {open, tempOpen};

	FW = 12;	FH = 10;

	MaxPatLen = 128;

TYPE
	Outline* = POINTER TO OutlineDesc;
	OutlineDesc* = RECORD (Gadgets.FrameDesc)
		fstate* : INTEGER;
		len*: LONGINT;
		buf* : Texts.Buffer;
	END;

	FindInfo = RECORD
		sPat: ARRAY MaxPatLen OF CHAR;	(* search pattern [read only] *)
		sDv: ARRAY MaxPatLen + 1 OF INTEGER;	(* displacement vector for search pattern *)
		sLen: INTEGER;	(* number of valid characters in sPat [read only] *)
		time: LONGINT;	(* most recent time for sPat and/or rBuf *)
		rBuf: Texts.Buffer;	(* replace buffer [read only] *)
	END;

VAR
	oldBroadcast: Display.MsgProc;
	inf: FindInfo;
	handle : Objects.Handler;
	insertT: Texts.Text;
	saveB: Texts.Buffer;

PROCEDURE MakeOutline*(state: INTEGER) : Outline;
VAR F: Outline;
BEGIN
	NEW(F); F.state := {Gadgets.lockedsize}; F.W := FW; F.H := FH; F.handle := handle; F.fstate := state; F.len:= 1;
	RETURN F;
END MakeOutline;

PROCEDURE GetFrame (): Display.Frame;
VAR D, F: Display.Frame;

	PROCEDURE MarkedFrame;
	BEGIN
		D:= Documents.MarkedDoc();
		IF D # NIL THEN F := D.dsc
		ELSE
			D := Oberon.MarkedViewer();
			IF D # NIL THEN F := D.dsc.next END
		END
	END MarkedFrame;
	
BEGIN
	F := NIL;
	IF Oberon.Par.vwr IS Desktops.DocViewer THEN
		IF Desktops.CurMenu(Gadgets.context) = Gadgets.context THEN	(* command in menu *)
			D:= Desktops.CurDoc(Gadgets.context);
			IF D # NIL THEN F:= D.dsc END
		ELSE	(* command in main *)
			MarkedFrame
		END
	ELSE
		IF Oberon.Par.vwr.next = Oberon.Par.frame THEN	(* command in menu *)
			F:= Oberon.Par.frame.next
		ELSE	(* command in main *)
			MarkedFrame
		END
	END;
	RETURN F
END GetFrame;

PROCEDURE GetText(F: Display.Frame): Texts.Text;
VAR L: Objects.LinkMsg;
BEGIN
	L.obj:= NIL; 
	IF (F # NIL) THEN L.res:= -1; Objects.Stamp(L); L.id:= Objects.get; L.name:= "Model"; F.handle(F, L) END;
	IF (L.obj # NIL) & (L.obj IS Texts.Text) THEN
		RETURN L.obj(Texts.Text)
	ELSE
		RETURN NIL
	END
END GetText;

PROCEDURE FindBefore(T: Texts.Text; obj: Objects.Object; VAR before: Objects.Object; VAR pos: LONGINT);
VAR F: Texts.Finder; p: LONGINT; o: Objects.Object;
BEGIN
	before := NIL; pos := 0; o := NIL; p := 0;
	Texts.OpenFinder(F, T, 0);
	LOOP
		before := o; pos := p;
		p := F.pos;
		Texts.FindObj(F, o);
		IF F.eot THEN
			before := NIL; EXIT;
		END;
		IF (o # NIL) & (o = obj) THEN (* stop before *)
			EXIT;
		END;
	END;
END FindBefore;

PROCEDURE CloseForward(F: Outline; T: Texts.Text; pos: LONGINT);
VAR f: Texts.Finder; o: Objects.Object; pos0: LONGINT; cnt : INTEGER;
BEGIN
	F.len:= 0;
	Texts.OpenFinder(f, T, pos+1);
	pos0 := f.pos;
	Texts.FindObj(f, o); cnt := 1;
	LOOP
		IF f.eot THEN RETURN END;
		IF (o # NIL) & (o IS Outline) THEN (* strech between pos and pos0 should be saved *)
			WITH o : Outline DO
				IF o.fstate = open THEN INC(cnt);
				ELSIF o.fstate = folded THEN
				ELSIF o.fstate = close THEN
					DEC(cnt);
					IF cnt = 0 THEN
						NEW(F.buf); Texts.OpenBuf(F.buf); Texts.Save(T, pos+1, pos0+1, F.buf);
						Texts.Delete(T, pos+1, pos0+1); F.fstate := folded; F.len:= F.buf.len;
						Gadgets.Update(F);
						EXIT
					END
				END
			END
		END;
		pos0 := f.pos;
		Texts.FindObj(f, o);
	END;
END CloseForward;

PROCEDURE CloseBackward(F: Outline; T: Texts.Text; pos: LONGINT);
VAR obj: Objects.Object; pos0: LONGINT; cnt : INTEGER;
BEGIN
	obj := F; cnt := 1;
	LOOP
		FindBefore(T, obj, obj, pos0);
		IF obj = NIL THEN
			EXIT
		ELSIF obj IS Outline THEN
			WITH obj : Outline DO
				IF obj.fstate = open THEN
					DEC(cnt);
					IF cnt = 0 THEN
						NEW(obj.buf); Texts.OpenBuf(obj.buf); Texts.Save(T, pos0+1, pos+1, obj.buf);
						Texts.Delete(T, pos0+1, pos+1); obj.fstate := folded;
						obj.len:= obj.buf.len;
						Gadgets.Update(obj);
						EXIT
					END
				ELSIF obj.fstate = folded THEN
				ELSIF obj.fstate = close THEN
					INC(cnt)
				END
			END
		END
	END;
END CloseBackward;

PROCEDURE Ins(T: Texts.Text; pos: LONGINT; obj : Objects.Object);
VAR W: Texts.Writer;
BEGIN
	Texts.OpenWriter(W);
	Texts.WriteObj(W, obj);
	Texts.Insert(T, pos, W.buf)
END Ins;

PROCEDURE Open(F: Outline; T: Texts.Text; pos: LONGINT);
BEGIN
	IF F.buf # NIL THEN F.len:= F.buf.len; Texts.Insert(T, pos+1, F.buf); F.buf:= NIL
	ELSE Ins(T, pos+1, MakeOutline(close))
	END;
	F.fstate := open; Gadgets.Update(F)
END Open;

PROCEDURE Fold(F: Outline; x, y, w, h: INTEGER; VAR M: Oberon.InputMsg; R: Display3.Mask);
VAR f: Texts.Finder; o: Objects.Object; T: Texts.Text; pos: LONGINT; found: BOOLEAN;
	FF: Display.Frame;
BEGIN
	Effects.TrackHighlight(R, M.keys, M.X, M.Y, x, y, w, h);
	IF ~Gadgets.InActiveArea(F, M) THEN M.res := 0; RETURN END;
	FF := NIL;
	IF FF = NIL THEN T:= GetText(M.dlink(Display.Frame)) ELSE T:= GetText(FF) END;
	IF T # NIL  THEN (* frame in a text *)
		Texts.OpenFinder(f, T, 0);
		pos := f.pos; found := FALSE;
		Texts.FindObj(f, o);
		LOOP
			IF f.eot THEN EXIT END;
			IF (o # NIL) & (o = F) THEN
				IF found THEN
					Out.String("Outliner twice in text"); Out.Ln; RETURN
				ELSE
					found := TRUE;
				END;
			END;
			IF ~found THEN pos := f.pos; END;
			Texts.FindObj(f, o);
		END;
		IF found THEN (* outliner only once in text *)
			IF F.fstate = open THEN
				CloseForward(F, T, pos);
			ELSIF F.fstate = close THEN
				CloseBackward(F, T, pos);
			ELSIF F.fstate = folded THEN
				Open(F, T, pos);
			END;
		END;
	END;
	M.res := 0;
	Gadgets.ExecuteAttr(F, "Cmd", M.dlink, NIL, NIL)
END Fold;

PROCEDURE ExpandAll*(T: Texts.Text; from: LONGINT; temporal: BOOLEAN);
VAR F: Texts.Finder; o: Objects.Object; pos: LONGINT;
BEGIN
	Texts.OpenFinder(F, T, from); pos:= F.pos;
	LOOP
		Texts.FindObj(F, o);
		IF F.eot THEN EXIT END;
		IF (o IS Outline) & (o(Outline).fstate = folded) THEN
			Open(o(Outline), T, pos);
			IF temporal THEN o(Outline).fstate:= tempOpen END;
			Texts.OpenFinder(F, T, from); pos:= F.pos
		ELSE pos:= F.pos
		END
	END
END ExpandAll;

(** Collapse from the position of the next Outline to its matching one. *)
PROCEDURE CollapseFromTo*(T: Texts.Text; beg, end: LONGINT; modes: SET);
VAR F: Texts.Finder; o: Objects.Object; pos: LONGINT;
BEGIN
	Texts.OpenFinder(F, T, beg); pos := F.pos;
	LOOP
		Texts.FindObj(F, o);
		IF F.eot THEN EXIT END;
		IF (o # NIL) & (o IS Outline) & (o(Outline).fstate IN modes) THEN EXIT
		ELSE pos := F.pos
		END
	END;
	IF F.pos < end THEN
		CollapseFromTo(T, F.pos, end, modes);
		CloseForward(o(Outline), T, pos)
	END
END CollapseFromTo;

PROCEDURE CollapseAll*(T: Texts.Text; modes: SET);
BEGIN
	CollapseFromTo(T, 0, T.len, modes)
END CollapseAll;

(*	----------------------------	Gadgets Stuff	----------------------------	*)

PROCEDURE DTriangle (R: Display3.Mask; x, y, dim: INTEGER; open: BOOLEAN);
VAR h, max: INTEGER;
BEGIN
	max := 1 + 2*(dim DIV 2);
	IF open THEN
		h := max;
		WHILE h > 0 DO
			Display3.ReplConst(R, Display3.black, x, y, 1, h, Display3.replace);
			Display3.ReplConst(R, Display3.black, x + 1, y, 1, h, Display3.replace);
			INC(x, 2); INC(y); DEC(h, 2)
		END
	ELSE
		h := 1; y := y + max DIV 2;
		WHILE h <= max DO
			Display3.ReplConst(R, Display3.black, x, y, 1, h, Display3.replace);
			Display3.ReplConst(R, Display3.black, x + 1, y, 1, h, Display3.replace);
			INC(x, 2); DEC(y); INC(h, 2)
		END
	END
END DTriangle;

PROCEDURE RestoreOutline(F: Outline; R: Display3.Mask; x, y, w, h: INTEGER);
VAR cx, cy, cw, ch: INTEGER;
BEGIN
	Display3.ReplConst(R, Display3.groupC, x, y, w, h, Display.replace);
	cx := x + w DIV 4; cy := y + h DIV 4; cw := w DIV 2; ch := h DIV 2;
	CASE F.fstate OF
		folded: Display3.ReplConst(R, Display3.black, cx, cy, cw, ch, Display.replace)
		|open: DTriangle(R, cx, cy, ch, TRUE)
		|close: DTriangle(R, cx, cy, ch, FALSE)
	ELSE
	END;
	IF Gadgets.selected IN F.state THEN Display3.FillPattern(R, 15, Display3.selectpat, x, y, x, y, w, h, Display.paint) END
END RestoreOutline;

PROCEDURE P(x: INTEGER): INTEGER;
BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
END P;

PROCEDURE PTriangle (R: Display3.Mask; x, y, dim: INTEGER; open: BOOLEAN);
VAR h, max: INTEGER;
BEGIN
	max := 1 + 2*(dim DIV 2);
	IF open THEN
		h := max;
		WHILE h > 0 DO
			Printer3.ReplConst(R, Display3.black, x, y, 1, h, Display3.replace);
			Printer3.ReplConst(R, Display3.black, x + 1, y, 1, h, Display3.replace);
			INC(x, 2); INC(y); DEC(h, 2)
		END
	ELSE
		h := 1; y := y + max DIV 2;
		WHILE h <= max DO
			Printer3.ReplConst(R, Display3.black, x, y, 1, h, Display3.replace);
			Printer3.ReplConst(R, Display3.black, x + 1, y, 1, h, Display3.replace);
			INC(x, 2); DEC(y); INC(h, 2)
		END
	END
END PTriangle;

PROCEDURE PrintOutline(F: Outline; M: Display.DisplayMsg);
VAR R: Display3.Mask; x, y, w, h: INTEGER;

BEGIN
	Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, R);
	w := P(F.W); h := P(F.H);
	Printer3.ReplConst(R, Display3.textbackC, M.x, M.y, w, h, Display.replace);
	x := M.x + w DIV 4; y := M.y + h DIV 4; w := w DIV 2; h := h DIV 2;
	CASE F.fstate OF
		folded: Printer3.ReplConst(R, Display3.black, x, y, w, h, Display.replace)
		|open: PTriangle(R, x, y, h, TRUE)
		|close: PTriangle(R, x, y, h, FALSE)
	ELSE
	END
END PrintOutline;

PROCEDURE CopyOutline*(VAR M: Objects.CopyMsg; from, to: Outline);
BEGIN
	Gadgets.CopyFrame(M, from, to);
	to.fstate := from.fstate; to.len:= from.len;
	IF from.buf # NIL THEN NEW(to.buf); Texts.OpenBuf(to.buf); Texts.Copy(from.buf, to.buf)
	ELSE to.buf:= NIL
	END
END CopyOutline;

PROCEDURE Attr(F: Outline; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class := Objects.String; COPY("Outlines.NewOutline", M.s); M.res := 0
		ELSIF M.name = "LineupHY" THEN M.class := Objects.Int; M.i := 0; M.res := 0
		ELSIF M.name = "Cmd" THEN
			Gadgets.framehandle(F, M);
			IF M.res < 0 THEN
				M.class := Objects.String; M.s := ""; M.res := 0; 
			END
		ELSE Gadgets.framehandle(F, M)
		END;
	ELSIF M.id = Objects.set THEN
		Gadgets.framehandle(F, M)
	ELSIF M.id = Objects.enum THEN
		M.Enum("Cmd");
		Gadgets.framehandle(F, M)
	END
END Attr;

PROCEDURE OutlineHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR file: Files.File; text: Texts.Text; pos, len: LONGINT; x, y, w, h, version: INTEGER; F0: Outline;
		R: Display3.Mask; ch: CHAR;
BEGIN
	WITH F: Outline DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO Attr(F, M) END;
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink
				ELSE NEW(F0); F.stamp := M.stamp; F.dlink := F0; CopyOutline(M, F, F0); M.obj := F0
				END;
			END;
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.load THEN
					Files.ReadInt(M.R, version);
					IF version >= 0 THEN F.fstate := version
					ELSE Files.ReadInt(M.R, F.fstate)
					END;
					Files.ReadLInt(M.R, F.len);
					Files.Read(M.R, ch);
					IF (F.fstate = folded) & (ch = Texts.TextBlockId) THEN
						NEW(F.buf); Texts.OpenBuf(F.buf);
						file := Files.Base(M.R); pos := Files.Pos(M.R);
						NEW(text); Texts.Open(text, "");
						Texts.Load(text, file, pos, len);
						Files.Set(M.R, file, pos + len);
						Texts.Save(text, 0, text.len, F.buf);
					ELSE
						IF version >= 0 THEN 
							Files.Set(M.R, Files.Base(M.R), Files.Pos(M.R) -1);
						END;
						F.buf := NIL
					END;
					Gadgets.framehandle(F, M);
				ELSIF M.id = Objects.store THEN
					Files.WriteInt(M.R, -1);
					Files.WriteInt(M.R, F.fstate);
					Files.WriteLInt(M.R, F.len);
					IF (F.fstate = folded) & (F.buf # NIL) THEN (* there is a text to save *)
						NEW(text); Texts.Open(text, "");
						Texts.OpenBuf(saveB); Texts.Copy(F.buf, saveB); Texts.Append(text, saveB);
						file := Files.Base(M.R); pos := Files.Pos(M.R);
						Texts.Store(text, file, pos, len);
						Files.Set(M.R, file, pos + len)
					ELSE
						Files.Write(M.R, 0)
					END;
					Gadgets.framehandle(F, M);
				END
			END
		ELSIF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				x:= M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H; (* calculate actual coordinates *)
				IF M IS Display.DisplayMsg THEN
					WITH M: Display.DisplayMsg DO
						IF M.device = Display.screen THEN
							IF (M.F = NIL) OR ((M.id = Display.full) & (M.F = F)) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								RestoreOutline(F, R, x, y, w, h);
							ELSIF (M.id = Display.area) & (M.F = F) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
								RestoreOutline(F, R, x, y, w, h);
							END
						ELSIF M.device = Display.printer THEN
							PrintOutline(F, M)
						END
					END
				ELSIF M IS Oberon.InputMsg THEN
					WITH M: Oberon.InputMsg DO
						IF (M.id = Oberon.track) & (M.keys = {1}) & Gadgets.InActiveArea(F, M) & ~(Gadgets.selected IN F.state) THEN
							Gadgets.MakeMask(F, x, y, M.dlink, R);
							Fold(F, x, y, w, h, M, R)
						ELSE
							Gadgets.framehandle(F, M);
						END
					END
				ELSE
					Gadgets.framehandle(F, M);
				END
			END;
		ELSE
			Gadgets.framehandle(F, M);
		END;
	END;
END OutlineHandler;

(*	----------------------------	Generators	----------------------------	*)

PROCEDURE NewOutline*;
(* make a neutral one *)
VAR F: Outline;
BEGIN F := MakeOutline(-1); Objects.NewObj := F;
END NewOutline;

PROCEDURE New*;
VAR F, CF: Outline;
BEGIN
	F:= MakeOutline(folded); 
	CF:= MakeOutline(close);
	NEW(F.buf); Texts.OpenBuf(F.buf);
	Texts.Delete(insertT, 0, insertT.len);
	Ins(insertT, 0, CF);
	Texts.Save(insertT, 0, 1, F.buf);
	F.len:= F.buf.len;
	Objects.NewObj:= F
END New;

(*	----------------------------	HD extensions	----------------------------	*)

PROCEDURE InsertText*(T: Texts.Text; beg, end: LONGINT); (*gs*)
	VAR o: Outline;
BEGIN
	o := MakeOutline(folded); NEW(o.buf); Texts.OpenBuf(o.buf);
	Ins(T, end, MakeOutline(close));
	Texts.Save(T, beg, end+1, o.buf);
	o.len := o.buf.len;
	Texts.Delete(T, beg, end+1);
	Ins(T, beg, o)
END InsertText;

PROCEDURE RemoveAll*(T: Texts.Text); (*gs*)
	VAR F: Texts.Finder; o: Objects.Object; pos: LONGINT;
BEGIN
	ExpandAll(T, 0, FALSE);
	Texts.OpenFinder(F, T, 0);
	pos := F.pos; Texts.FindObj(F, o);
	WHILE ~F.eot DO
		IF o IS Outline THEN
			Texts.Delete(T, pos, pos+1);
			Texts.OpenFinder(F, T, pos)
		END;
		pos := F.pos; Texts.FindObj(F, o)
	END
END RemoveAll;

(*	----------------------------	commands operating on outlines	----------------------------	*)

PROCEDURE Remove*; (*gs*)
	VAR T: Texts.Text;
BEGIN
	T := GetText(GetFrame());
	IF T # NIL THEN RemoveAll(T)
	ELSE Out.String("no text found"); Out.Ln
	END
END Remove;

PROCEDURE Insert*;
VAR S: Oberon.SelectMsg; o: Outline;
BEGIN
	S.id:= Oberon.get; S.time:= -1; S.res:= -1; S.F:= NIL;
	Display.Broadcast(S);
	IF (S.time >= 0) & (S.text # NIL) THEN
		InsertText(S.text, S.beg, S.end)
	ELSE
		Gadgets.Integrate( MakeOutline(folded))
	END
END Insert;

(* -- search engine by uh *)

PROCEDURE NoBroadcast (VAR M: Display.FrameMsg);
BEGIN
END NoBroadcast;

PROCEDURE MarkPatPos (F: Display.Frame; T: Texts.Text; pos: LONGINT);
VAR C: Oberon.CaretMsg; S: Oberon.SelectMsg;
BEGIN
	Oberon.Defocus;
	C.id := Oberon.set; C.F := F; C.car := F; C.text := T; C.pos := pos; Display.Broadcast(C);
	S.id := Oberon.set; S.F := F; S.sel := F; S.text := T; S.beg := pos - inf.sLen; S.end := pos;
	Display.Broadcast(C);
	S.id := Oberon.set; S.F := F; S.time := -1; Display.Broadcast(C); inf.time :=S.time
END MarkPatPos;

PROCEDURE CalcDispVec (time: LONGINT);
VAR i, j, d: INTEGER;
BEGIN
	inf.time := time;
	i := 1; d := 1; (* calculate displacement vector *)
	WHILE i <= inf.sLen DO
		j := 0; WHILE (j + d < inf.sLen) & (inf.sPat[j] = inf.sPat[j + d]) DO INC(j) END;
		WHILE i <= j + d DO inf.sDv[i] := d; INC(i) END;
		INC(d)
	END
END CalcDispVec;

PROCEDURE SPatFound (text: Texts.Text; VAR pos: LONGINT): BOOLEAN;
VAR root, obj: Objects.Object; bpos, fpos, l: LONGINT; i: INTEGER; f: Texts.Finder; R: Texts.Reader; ch: CHAR;

	PROCEDURE Append (o: Objects.Object);
	VAR cur: Objects.Object;
	BEGIN
		o.slink := NIL;
		IF root = NIL THEN root:= o
		ELSE
			cur:= root;
			WHILE cur.slink # NIL DO cur := cur.slink END;
			cur.slink := o
		END
	END Append;

	PROCEDURE RemoveLast;
	VAR cur: Objects.Object;
	BEGIN
		IF root = NIL THEN RETURN
		ELSIF root.slink = NIL THEN
			IF root(Outline).fstate = tempOpen THEN pos := pos - root(Outline).len END;
			root := NIL
		ELSE
			cur:= root;
			WHILE cur.slink.slink # NIL DO cur:= cur.slink END;
			IF cur.slink(Outline).fstate = tempOpen THEN pos := pos - cur.slink(Outline).len END;
			cur.slink := NIL
		END
	END RemoveLast;

BEGIN
	IF inf.sLen > 0 THEN
		root := NIL;
		bpos:= pos;
		oldBroadcast:= Display.Broadcast;
		Display.Broadcast:= NoBroadcast; ExpandAll(text, pos, TRUE); Display.Broadcast:= oldBroadcast;

		Texts.OpenReader(R, text, pos); Texts.Read(R, ch); INC(pos);
		l := text.len; i := 0;
		WHILE (i # inf.sLen) & (pos <= l) DO
			IF ch = inf.sPat[i] THEN INC(i); IF i < inf.sLen THEN Texts.Read(R, ch); INC(pos) END
			ELSIF i = 0 THEN Texts.Read(R, ch); INC(pos)
			ELSE DEC(i, inf.sDv[i])
			END
		END;

		IF i = inf.sLen THEN	(* pattern found *)
			(* compute open path *)
			Texts.OpenFinder(f, text, bpos); fpos:= f.pos;
			LOOP
				Texts.FindObj(f, obj);
				IF f.eot OR (fpos >= pos) THEN EXIT END;
				fpos:= f.pos;
				IF (obj IS Outline) THEN
					WITH obj: Outline DO
						IF obj.fstate IN openMode THEN Append(obj)
						ELSIF obj.fstate= close THEN RemoveLast
						END
					END
				END
			END;	(* LOOP *)

			Display.Broadcast:= NoBroadcast; CollapseFromTo(text, bpos, text.len, {tempOpen}); 
			Display.Broadcast:= oldBroadcast;
			(* open needed Outlines in text *)
			Texts.OpenFinder(f, text, bpos); fpos:= f.pos;
			LOOP
				Texts.FindObj(f, obj);
				IF f.eot OR (root = NIL) THEN EXIT END;
				IF obj = root THEN
					obj:= root; root:= root.slink; obj.slink:= NIL;
					IF obj(Outline).fstate = folded THEN Open(obj(Outline), text, fpos); Texts.OpenFinder(f, text, fpos) END
				END;
				fpos:= f.pos
			END;
			RETURN TRUE
		ELSE
			Display.Broadcast:= NoBroadcast; CollapseFromTo(text, bpos, text.len, {tempOpen}); 
			Display.Broadcast:= oldBroadcast;
			RETURN FALSE
		END
	ELSE RETURN FALSE
	END
END SPatFound;

PROCEDURE Search*;
VAR F: Display.Frame; T: Texts.Text; pos: LONGINT; i: INTEGER; R: Texts.Reader;
		aS: Attributes.Scanner; C: Oberon.CaretMsg; S: Oberon.SelectMsg;
BEGIN
	F:= GetFrame();
	IF F = NIL THEN C.id:= Oberon.get; C.res:= -1; C.F:= NIL; C.pos:= -1; Display.Broadcast(C); F:= C.car END;
	IF (F # NIL) THEN
		T:= GetText(F); IF T = NIL THEN RETURN END;
		Attributes.OpenScanner(aS, Oberon.Par.text, Oberon.Par.pos);
		Attributes.Scan(aS);
		IF aS.class = Attributes.String THEN
			COPY(aS.s, inf.sPat); inf.sLen := aS.len; CalcDispVec(Oberon.Time())
		ELSE
			S.id:= Oberon.get; S.F:= NIL; S.time:= -1; Display.Broadcast(S);
			IF (S.text # NIL) & (S.time >= 0) THEN	(* get new search pattern and save in info-structure*)
				Texts.OpenReader(R, S.text, S.beg); 
				i := 0; pos := S.beg; inf.sLen:= 0;
				REPEAT Texts.Read(R, inf.sPat[i]); INC(i); INC(pos) UNTIL (i = MaxPatLen) OR (pos = S.end);
				inf.sLen := i; CalcDispVec(S.time)
			END
		END;
		C.id:= Oberon.get; C.res:= -1; C.F:= F; C.pos:= -1; Display.Broadcast(C);
		IF C.pos >= 0 THEN pos:= C.pos; ELSE pos:= 0 END;
		IF SPatFound(T, pos) THEN MarkPatPos(F, T, pos)
		ELSE
			S.id := Oberon.reset; S.F := F; Display.Broadcast(S);
			C.id := Oberon.reset; C.F := F; Display.Broadcast(C)
		END
	END
END Search;

PROCEDURE replace (): BOOLEAN;
VAR F: Display.Frame; R: Texts.Reader; tBuf: Texts.Buffer; i, pos, p, len: LONGINT;
		ch: CHAR; T: Texts.Text; S: Oberon.SelectMsg; C: Oberon.CaretMsg;
BEGIN
	F := GetFrame(); T := GetText(F);
	IF (T # NIL) THEN
		S.id := Oberon.get; S.F := NIL; S.time := -1; Display.Broadcast(S);
		IF (S.text # NIL) & (S.time > inf.time) THEN	(* set replace buffer *)
			inf.time := S.time; NEW(inf.rBuf); Texts.OpenBuf(inf.rBuf); Texts.Save(S.text, S.beg, S.end, inf.rBuf)
		END;
		C.id := Oberon.get; C.F := NIL; C.car := NIL; Display.Broadcast(C);
		IF (C.car = NIL) OR ~(inf.sLen > 0) OR (inf.rBuf = NIL) THEN RETURN FALSE END;	(*###*)
		pos := C.pos; p := pos - inf.sLen;
		IF p < 0 THEN RETURN FALSE END;	(*###*)
		Texts.OpenReader(R, T, p); Texts.Read(R, ch); i := 0;
		WHILE (ch = inf.sPat[i]) & (i < inf.sLen) DO Texts.Read(R, ch); INC(i) END;
		IF i = inf.sLen THEN
			Texts.Delete(T, p, pos); pos := p;
			NEW(tBuf); Texts.OpenBuf(tBuf);
			Texts.Copy(inf.rBuf, tBuf); len := tBuf.len;
			Texts.Insert(T, pos, tBuf); pos := pos + len
		END;
		IF SPatFound(T, pos) THEN MarkPatPos(F, T, pos); RETURN TRUE
		ELSE
			S.id := Oberon.reset; S.F := F; Display.Broadcast(S);
			C.id := Oberon.reset; C.F := F; Display.Broadcast(C);
			RETURN FALSE
		END
	END;
	RETURN FALSE
END replace;

PROCEDURE Replace*;
BEGIN
	IF replace() THEN END
END Replace;

PROCEDURE ReplaceAll*;
BEGIN
	WHILE replace() DO END
END ReplaceAll;

PROCEDURE Expand*;
VAR T: Texts.Text;
BEGIN
	T:= GetText(GetFrame());
	IF T # NIL THEN ExpandAll(T, 0, FALSE)
	ELSE Out.String("no text found"); Out.Ln
	END
END Expand;

PROCEDURE Collapse*;
VAR T: Texts.Text;
BEGIN
	T:= GetText(GetFrame());
	IF T # NIL THEN CollapseAll(T, openMode)
	ELSE Out.String("no text found"); Out.Ln
	END
END Collapse;

BEGIN
	handle := OutlineHandler;
	NEW(insertT); Texts.Open(insertT, "");
	NEW(saveB)
END Outlines.

System.Free Outlines ~
Gadgets.Insert Outlines.New ~

Outlines.Insert
Outlines.Collapse *
Outlines.Expand *
Outlines.Search	Outlines.Replace	Outlines.ReplaceAll
