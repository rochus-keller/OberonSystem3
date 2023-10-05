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

MODULE ScriptFrames;	(** portable *) (* RS, Wed, 9-Jun-1993*)

	IMPORT Texts, Fonts, Objects, Oberon, Styles, Input, Display, Modules, Printer;
(*hyph*)
(*
	Tue, 17-May-1994: visualize page breaks
	Mon, 4-Jul-1994: error in format: Read CR -> dx := 0
	Fri, 22-Jul-1994: error in format: Read obj#{Frame, Style} -> wrong dx, H
	Fri, 14-Oct-1994: back scroll
*)
(*
	(*--back scroll--	->	(*--back scroll--*)
	--no scroll--*)		->	(*--no scroll--
	(*--end scroll--*)	->	--end scroll--*)
*)

	CONST
		TAB = 09X;	CR = 0DX;	LeftArrow = 0C4X;	RightArrow = 0C3X;	BRK = 0ACX;	(*special chars*)
		HYPH = 1FX;	(*CTRL-"-"*)
		SpcW = 3;
		ML = 2;	MM = 1;	MR = 0;

		LeftMode = {Styles.left};
		RightMode = {Styles.right};
		AdjMode = {Styles.left, Styles.right};
		CenterMode = {};
	
		car = 0; sel = 1; arrow = -1;	(* MarkMsg id *)
		
		OpenCmd = "Script.Open";
	
	TYPE
		Box = POINTER TO BoxDesc;
		Line = POINTER TO LineDesc;
		LineDesc = RECORD
			len, W: LONGINT;
			w, h: INTEGER;
			asr, dsr: INTEGER;
			off, w0: INTEGER;
			nSpc: INTEGER;
			style: Styles.Style;
			brk, eot, tabs: BOOLEAN;
			next: Line;
			box: Box
		END;
	
		Location* = RECORD
			org*, pos*: LONGINT;
			dx*, x*, y*: INTEGER;
			lin: Line
		END;
	
		Frame* = POINTER TO FrameDesc;
		FrameDesc* = RECORD (Display.FrameDesc)
			text*: Texts.Text;
			org*: LONGINT;
			col*: INTEGER;
			left*, right*, top*, bot*: INTEGER;
			markH*, mark*: INTEGER;
			time*: LONGINT;
			car*, sel*, hide*: BOOLEAN;
			carLoc*: Location;
			selBeg*, selEnd*: Location;
			trailer: Line;
		END;

	(*mark < 0: arrow mark
		mark = 0: no mark*)

		Formatter = RECORD(Texts.Reader)
			len, W: LONGINT;
			w, asr, dsr, nSpc: INTEGER;
			hide: BOOLEAN;
			fnt, mfnt: Fonts.Font;
			unit: LONGINT
		END;

		MarkMsg = RECORD(Display.FrameMsg)
			id: INTEGER
		END;
		DisplayMsg = RECORD(Display.DisplayMsg)
			pos: LONGINT
		END;
(*	-> CaretMsg
		FocusMsg* = RECORD(Display.FrameMsg)
			foc*: Frame
		END;
*)
		BoxDesc = RECORD
			next: Box;
			F: Display.Frame;
			off: LONGINT;
			X, dY: INTEGER
		END;
		
	VAR
		barW*, left*, right*, top*, bot*: INTEGER; (*standard sizes*)
		Asr, Dsr, markW, eolW: INTEGER;
		
		R1: Texts.Reader;	(* displayer *)
		fnt, mfnt: Fonts.Font; unit: LONGINT;	(*cache*)
		R: Formatter;
		ch: CHAR;
		dx, a, d: INTEGER;
		dX: LONGINT;
		style: Styles.Style;

		W, KW, XW: Texts.Writer; (*keyboard writer*)
	
		pL: Line;	(*prev line while printing*)
		show: PROCEDURE(F: Frame; pos: LONGINT);
		
		FullColor, BackCol, BarCol: INTEGER;

	PROCEDURE Min (i, j: LONGINT): LONGINT;
	BEGIN IF i >= j THEN RETURN j ELSE RETURN i END
	END Min;
	
	PROCEDURE Max (i, j: INTEGER): INTEGER;
	BEGIN IF j >= i THEN RETURN j ELSE RETURN i END
	END Max;

	(*---display support & misc---*)

	PROCEDURE ShowBrk(F: Frame; col, x, y: INTEGER);
		VAR obj: Objects.Object; L: Line; org: LONGINT; X, Y: INTEGER;
	BEGIN
		IF F.slink # NIL THEN obj := F.slink; org := F.org;
			WHILE obj.stamp < org DO obj := obj.slink END;
			L := F.trailer.next; Y := y+F.Y+F.H-F.top;
			WHILE L # F.trailer DO
				IF org = obj.stamp THEN	(*display line*)
					X := x+F.X+F.left;
					Display.FillPattern(col, Display.grey2, X, Y-1, X, Y-1, F.W-F.left-F.right, 1, Display.paint);
					obj := obj.slink
				END;
				INC(org, L.len); DEC(Y, L.h); L := L.next
			END
		END
	END ShowBrk;

	PROCEDURE Mask(F: Frame): Display.Frame;
	VAR msk: Display.Frame;
	BEGIN
		IF F.dsc = NIL THEN NEW(msk); F.dsc := msk ELSE msk := F.dsc END;
		msk.X := F.X+F.left; msk.Y := F.Y+F.bot; msk.W := F.W-F.left-F.right; msk.H := F.H-F.top-F.bot;
		RETURN msk
	END Mask;

	PROCEDURE Marks(F: Frame; id: INTEGER);
	VAR M: MarkMsg;
	BEGIN M.id := id; M.F := F; Display.Broadcast(M)
	END Marks;

	PROCEDURE Mark*(F: Frame; mark: INTEGER);
	BEGIN Marks(F, arrow)
	END Mark;

	PROCEDURE DrawCursor(X, Y: INTEGER);
	BEGIN Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, X, Y)
	END DrawCursor;

	PROCEDURE TrackMouse(VAR X, Y: INTEGER; VAR Keys, keysum: SET);
	BEGIN Input.Mouse(Keys, X, Y); DrawCursor(X, Y); keysum := keysum + Keys
	END TrackMouse;

	PROCEDURE InvertRect(F: Frame; x, y, X, Y, W, H: INTEGER);
	BEGIN INC(X, x+F.X); INC(Y, y+F.Y); Oberon.RemoveMarks(X, Y, W, H);
		IF X + W <= x+F.X + F.W THEN Display.ReplConst(FullColor, X, Y, W, H, Display.invert)
		ELSIF X < x+F.X + F.W THEN Display.ReplConst(FullColor, X, Y, x+F.X + F.W - X, H, Display.invert)
		END;
	END InvertRect;

	PROCEDURE ReplConst(col, x, y, w, h: INTEGER);
	BEGIN Oberon.RemoveMarks(x, y, w, h); Display.ReplConst(col, x, y, w, h, Display.replace)
	END ReplConst;

	PROCEDURE Erase(F: Frame; x, y, Y, H: INTEGER);	(* erase content *)
	BEGIN ReplConst(F.col, x+F.X + F.left, y+F.Y+Y, F.W - F.left, H)
	END Erase;

	PROCEDURE RemTick(F: Frame; x, y: INTEGER);
	BEGIN ReplConst(F.col, x+F.X, y+F.Y + F.H - 1 - F.markH, markW, 1)
	END RemTick;

	PROCEDURE ShowTick(F: Frame; x, y: INTEGER);	(*update*)
	BEGIN F.markH := SHORT(F.org * F.H DIV (F.text.len + 1));
		ReplConst(Display.FG, x+F.X, y+F.Y + F.H - 1 - F.markH, markW, 1)
	END ShowTick;

	PROCEDURE Bar(F: Frame; x, y, Y, H: INTEGER);
	BEGIN INC(x, F.X); INC(y, F.Y+Y); ReplConst(F.col, x, y, F.W, H);
		IF F.left >= barW THEN ReplConst(BarCol, x + barW - 1, y, 1, H) END	(* bar *)
	END Bar;

	PROCEDURE FrameDsr(F: Display.Frame): INTEGER;
		VAR B: Objects.AttrMsg;
	BEGIN B.dlink := NIL; B.i := 0; Objects.Stamp(B);
		B.res := -1; B.id := Objects.get; B.name := "LineupHY"; F.handle(F, B); RETURN SHORT(B.i)
	END FrameDsr;

	PROCEDURE DrawFrame(F: Frame; G: Display.Frame; x, y, X, Y: INTEGER);
	VAR M: Display.DisplayMsg; N: Display.ControlMsg;
	BEGIN INC(x, F.X + X); INC(y, F.Y + Y);
		IF X >= F.W-F.right THEN RETURN END;
		N.id := Display.restore; N.res := -1; N.F := G; Objects.Stamp(N);	(*restore*)
		N.dlink := Mask(F); N.x := x - G.X; N.y := y - G.Y; G.handle(G, N);
		M.device := Display.screen; M.id := Display.full; M.res := -1; M.F := G; Objects.Stamp(M);
		M.dlink := Mask(F); M.x := x - G.X; M.y := y - G.Y; G.handle(G, M)
	END DrawFrame;

	PROCEDURE Move(F: Frame; x, y, Y, H, dY: INTEGER);	(* move content including frames *)
	VAR w: INTEGER;
	BEGIN INC(x, F.X+F.left); INC(y, F.Y+Y); w := F.W - F.left;
		Oberon.RemoveMarks(x, SHORT(Min(y, y+dY)), w, Max(H+dY, H-dY));
		Display.CopyBlock (x, y, w, H, x, y + dY, 0)
	END Move;

	PROCEDURE FlipCaret (F: Frame; x, y: INTEGER);
	BEGIN
		IF (F.carLoc.y >= 10) & (F.carLoc.x + 12 < F.W) THEN
			Display.CopyPattern(FullColor, Display.hook, x+F.X + F.carLoc.x, y+F.Y + F.carLoc.y - 10, Display.invert)
		END
	END FlipCaret;

	(*---frames---*)

	PROCEDURE Insert(L: Line; X, voff: INTEGER; off: LONGINT; G: Display.Frame; VAR dY: INTEGER);
	VAR b, p: Box;
	BEGIN NEW(b); b.X := X; b.F := G; dY := FrameDsr(G)-voff; b.dY := dY; b.off := off;
		p := L.box;
		IF p = NIL THEN NEW(p); p.next := p; p.X := MAX(INTEGER); L.box := p END;
		WHILE p.next.X < X DO p := p.next END;
		b.next := p.next; p.next := b
	END Insert;

	PROCEDURE Append(L: Line; X: INTEGER; b: Box);	(*append everything up to X*)
	VAR p: Box;
	BEGIN
		IF b # NIL THEN p := b;
			WHILE (p.next # b) & (p.next.X + p.next.F.W <= X) DO p := p.next END; 	(*p.next.X + p.next.F.W > X*)
			IF p # b THEN	(*list ~empty*)
				IF L.box = NIL THEN L.box := b; p.next := b
				ELSE p.next := L.box.next; L.box.next := b.next
				END
			END
		END
	END Append;

	PROCEDURE Broadcast(F: Frame; VAR M: Display.FrameMsg);
	VAR x, y, Y: INTEGER; L: Line; msk: Display.Frame;

		PROCEDURE Broadcast0(box: Box; y: INTEGER; VAR M: Display.FrameMsg);
		VAR b: Box; G: Display.Frame;
		BEGIN b := box.next;
			WHILE b # box DO G := b.F;
				M.dlink := msk; M.x := x+b.X-G.X; M.y := y-b.dY-G.Y; G.handle(G, M); b := b.next
			END
		END Broadcast0;

	BEGIN x := M.x + F.X; y := M.y + F.Y;
		Y := F.H-F.top; L := F.trailer.next; msk := Mask(F);
		WHILE (M.res < 0) & (L # F.trailer) & (L # NIL) DO DEC(Y, L.h);	(*Broadcast while formatting !!!*)
			IF L.box # NIL THEN Broadcast0(L.box, y+Y+L.dsr, M) END;
			L := L.next
		END
	END Broadcast;

	(*---selection---*)

	PROCEDURE Transparent(G: Display.Frame): BOOLEAN;
		VAR M: Objects.AttrMsg;
	BEGIN M.b := FALSE; M.id := Objects.get; M.name := "Transparent";
		G.handle(G, M); RETURN M.b
	END Transparent;

	PROCEDURE InvertArea(F: Frame; L: Line; x, y, X, Y, W: INTEGER);
	VAR X0, H0, H1: INTEGER; b: Box; G: Display.Frame;
	BEGIN
		IF L.box # NIL THEN b := L.box.next;
			WHILE b.X < X DO b := b.next END;
			WHILE (b.X < X+W) (*& ~(b.F IS Styles.Frame)*) DO
				IF ~Transparent(b.F) THEN
					G := b.F; X0 := b.X; H0 := L.dsr - b.dY; H1 := L.h - G.H - H0;
					IF X < X0 THEN InvertRect(F, x, y, X, Y, X0-X, L.h) END;	(*before*)
					IF H0 > 0 THEN InvertRect(F, x, y, X0, Y, G.W, H0) END;	(*below*)
					IF H1 > 0 THEN InvertRect(F, x, y, X0, Y+H0+G.H, G.W, H1) END;	(*above*)
					INC(X0, G.W); DEC(W, X0-X); X := X0
				END;
				b := b.next
			END
		END;
		InvertRect(F, x, y, X, Y, W, L.h)
	END InvertArea;

	PROCEDURE FlipSelection (F: Frame; x, y: INTEGER; VAR beg, end: Location);
	VAR L: Line; Y: INTEGER;
	BEGIN
		L := beg.lin; Y := beg.y - L.dsr;	(* Y = bottom of line *)
		IF L = end.lin THEN InvertArea(F, L, x, y, beg.x, Y, end.x - beg.x)
		ELSE InvertArea(F, L, x, y, beg.x, Y, F.left + L.off + L.w0 - beg.x); L := L.next; DEC(Y, L.h);
			WHILE L # end.lin DO
				InvertArea(F, L, x, y, F.left + L.off, Y, L.w0); L := L.next; DEC(Y, L.h)
			END;
			InvertArea(F, L, x, y, F.left + L.off, Y, end.x - F.left - L.off)
		END
	END FlipSelection;

	PROCEDURE Deselect(F: Frame; G: Display.Frame);
		VAR S: Display.SelectMsg;
	BEGIN S.res := -1; S.x := 0; S.y := 0; S.id := Display.reset;
		S.sel := F; S.obj := G; S.dlink := Mask(F); Objects.Stamp(S);
		S.F := G; G.handle(G, S)
	END Deselect;

	(*---lines---*)

	PROCEDURE Lim(F: Frame): LONGINT;
	VAR pos: LONGINT; L: Line;
	BEGIN pos := F.org; L := F.trailer.next;
		WHILE L # F.trailer DO INC(pos, L.len); L := L.next END;
		RETURN pos
	END Lim;

	PROCEDURE CollectLines(F: Frame; VAR L: Line; VAR Y: INTEGER; VAR org: LONGINT);
	BEGIN
		WHILE (L.next # F.trailer) & (Y >= F.bot + L.next.h) DO
			L := L.next; INC(org, L.len); DEC(Y, L.h)
		END
	END CollectLines;

	(*---objects---*)

(*	PROCEDURE Objs(T: Texts.Text): Objects.Library;
	BEGIN IF T.obs = NIL THEN NEW(T.obs); Objects.OpenLibrary(T.obs) END; RETURN T.obs
	END Objs;	*)
	
	PROCEDURE Clone(obj: Objects.Object; id: INTEGER; VAR new: Objects.Object);
	VAR M: Objects.CopyMsg;
	BEGIN M.id := id; Objects.Stamp(M); obj.handle(obj, M); new := M.obj;	(* copy *)
		(*IF lib # NIL THEN N.lib := lib; Objects.Stamp(N); new.handle(new, N) END	(* bind *)*)
	END Clone;
	
	PROCEDURE SaveAndCopy(F: Frame; text: Texts.Text; beg, end: LONGINT; VAR W: Texts.Writer);
	VAR
		R: Texts.Finder;
		obj, new: Objects.Object;
	BEGIN
		IF end > text.len THEN end := text.len END;
		Texts.OpenFinder(R, text, beg);
		WHILE R.pos < end DO
			IF beg < R.pos THEN Texts.Save(text, beg, R.pos, W.buf) END;
			beg := R.pos; Texts.FindObj(R, obj);
			IF obj IS Display.Frame THEN
				(*lib := Objs(F.text); Clone(obj, Objects.shallow, lib, new); ch := CHR(new.ref);
				Texts.SetFont(W, lib); Texts.Write(W, ch); INC(beg)*)
				Clone(obj, Objects.shallow, new);
				Texts.WriteObj(W, new)
			END
		END;
		IF beg < end THEN Texts.Save(text, beg, end, W.buf) END
	END SaveAndCopy;

	PROCEDURE StyleAt(F: Frame; pos: LONGINT): Styles.Style;
	VAR R: Texts.Finder;
		obj: Objects.Object; style: Styles.Style;
	BEGIN Texts.OpenFinder(R, F.text, 0); style := Styles.defStyle;
		WHILE ~R.eot & (R.pos <= pos) DO
			Texts.FindObj(R, obj); IF (obj # NIL) & (obj IS Styles.Style) THEN style := obj(Styles.Style) END
		END;
		RETURN style
	END StyleAt;

	PROCEDURE StyleFrame(F: Frame; st: Styles.Style; X: INTEGER): Objects.Object;
	VAR G: Display.Frame;
	BEGIN G := Styles.NewFrame(st); G.W := SHORT(st.paraW DIV Display.Unit);
		IF G.W > F.W-F.right - X THEN G.W := F.W-F.right - X END;
		G(Styles.Frame).col := F.col;
		IF F.hide THEN G.H := 1 END;
		RETURN G
	END StyleFrame;

	(*---display---*)

	PROCEDURE Offsets(L: Line; VAR spc, rest: INTEGER);
	VAR
		width, diff: INTEGER;
		s: Styles.Style;
		mode: SET;
	BEGIN
		rest := 0; spc := 0; L.w0 := L.w; s := L.style;
		IF L.brk THEN INC(L.w0, eolW) ELSE INC(L.w0, SpcW) END;
		L.off := SHORT(s.left DIV Display.Unit);
		mode := s.opts * AdjMode;
		IF mode = LeftMode THEN RETURN
		ELSE width := SHORT(s.paraW DIV Display.Unit); diff := width - L.w;
			IF mode = AdjMode THEN
				IF L.brk OR (L.nSpc = 0) THEN RETURN END;	(* = left adjust for last line/one word*)
				L.w0 := width+SpcW; spc := diff DIV L.nSpc; rest := diff MOD L.nSpc
			ELSIF mode = CenterMode THEN INC(L.off, diff DIV 2)
			ELSIF mode = RightMode THEN INC(L.off, diff)
			END
		END
	END Offsets;

	PROCEDURE IncPos(spc: INTEGER; VAR rest, X: INTEGER);
	BEGIN INC(X, spc); IF rest > 0 THEN INC(X); DEC(rest) END
	END IncPos;
	
	PROCEDURE GetWidth(lib: Objects.Library; ch: CHAR; VAR obj: Objects.Object; VAR dx: INTEGER; VAR dX: LONGINT);
	BEGIN
		IF lib IS Fonts.Font THEN
			IF lib # fnt THEN fnt := lib(Fonts.Font); Styles.MetricFnt(fnt, unit, mfnt) END;	(*cache!!*)
			mfnt.GetObj(mfnt, ORD(ch), obj); dX := obj(Fonts.Char).dx*unit;
			lib.GetObj(lib, ORD(ch), obj); dx := obj(Fonts.Char).dx
		ELSE lib.GetObj(lib, ORD(ch), obj);
			IF obj IS Display.Frame THEN dx := obj(Display.Frame).W; dX := dx * Printer.Unit; RETURN
			ELSIF obj IS Styles.Style THEN dX := obj(Styles.Style).paraW; dx := SHORT(dX DIV Display.Unit); RETURN
			ELSE dx := 2; dX := 2*Printer.Unit
			END
		END
	END GetWidth;

	PROCEDURE Width(F: Frame; L: Line; beg, end: LONGINT; VAR x: INTEGER; VAR X: LONGINT);
		VAR R: Texts.Reader; obj: Objects.Object;
		pos: LONGINT; dx: INTEGER; ch: CHAR;
		spc, rest: INTEGER;
		DX: LONGINT;
	BEGIN Offsets(L, spc, rest);
		Texts.OpenReader(R, F.text, beg); Texts.Read(R, ch);
		pos := beg; x := 0; X := 0;
		WHILE pos # end DO
			GetWidth(R.lib, ch, obj, dx, DX);
			IF obj IS Fonts.Char THEN
				IF ch = TAB THEN Styles.Tab(L.style, R.lib(Fonts.Font), x, X, dx, DX)
				ELSIF ch = " " THEN IncPos(spc, rest, x)
				ELSIF ch = HYPH THEN dx := 0; DX := 0	(*hyph*)
				END
			END;
			INC(x, dx); INC(X, DX); INC(pos);
			Texts.Read(R, ch)
		END
	END Width;

	PROCEDURE Height(fnt: Fonts.Font; VAR a, d: INTEGER);	(*rule line height = 1.2*font height*)
	BEGIN a := 6*fnt.maxY DIV 5; d := (6*fnt.height DIV 5) - a
	END Height;

	PROCEDURE DisplayLine (F: Frame; pos, dXX: LONGINT; x, y, dX, Y: INTEGER; L: Line);	(*dX = offset into lineblock*)
	VAR
		X0, Y0, XT, x0, y0, dx, v, off, dY, bY, a, d: INTEGER;
		X, DX: LONGINT;
		spc, rest: INTEGER;
		obj: Objects.Object; G: Display.Frame;
		ch: CHAR;

		PROCEDURE GetObj(lib: Objects.Library; ch: CHAR; VAR obj: Objects.Object; VAR dx: INTEGER; VAR DX: LONGINT);
		BEGIN GetWidth(lib, ch, obj, dx, DX);
			IF lib IS Fonts.Font THEN
				IF ch > " " THEN RETURN
				ELSIF ch = " " THEN INC(dx, spc); IF rest > 0 THEN INC(dx); DEC(rest) END; RETURN
				ELSIF ch = TAB THEN Styles.Tab(L.style, lib(Fonts.Font), X0-x0, X, dx, DX); RETURN
				ELSIF ch = HYPH THEN dx := 0; DX := 0	(*hyph*)
				END
			ELSIF obj IS Styles.Style THEN obj := StyleFrame(F, obj(Styles.Style), X0-x0+off);
				dx := obj(Display.Frame).W; DX := LONG(dx)*Printer.Unit
			END
		END GetObj;

	BEGIN Offsets(L, spc, rest); off := F.left+L.off; L.box := NIL;
		x0 := x+F.X+off; XT := x+F.X+F.W-F.right; y0 := y+F.Y+Y-L.asr;	(*absolute screen*)
		v := 0; X0 := x0+dX; Y0 := y0; X := dXX; bY := Y-L.h;
		WHILE pos # L.len DO
			Texts.Read(R1, ch); INC(pos);
			IF R1.lib # NIL THEN GetObj(R1.lib, ch, obj, dx, DX);
				IF X0 (*+ dx*) <= XT THEN v := R1.voff;
					IF X0 + dx > XT THEN ch := " " END;	(*not draw*)
					IF (ch > " ") & (obj IS Fonts.Char) & (bY >= F.bot) THEN
						IF v # 0 THEN Height(R1.lib(Fonts.Font), a, d); Y0 := y0 + (a+d)*v DIV 100 ELSE Y0 := y0 END;	(*R1.voff#v*)
						WITH obj: Fonts.Char DO Display.CopyPattern(R1.col, obj.pat, X0+obj.x, Y0+obj.y, Display.paint) END
					ELSIF obj IS Display.Frame THEN G := obj(Display.Frame);
						IF v # 0 THEN dY := G.H * v DIV 100 ELSE dY := 0 END;
						Insert(L, X0-x0+off, dY, pos-1, G, dY);
						DrawFrame(F, G, x, y, X0-x0+off, Y-L.asr-dY)	(*rel*)
					ELSIF (ch = HYPH) & (obj IS Fonts.Char) & (pos = L.len) THEN	(*hyph*)
						GetObj(R1.lib, "_", obj, dx, DX);
						WITH obj: Fonts.Char DO Display.CopyPattern(R1.col, obj.pat, X0+obj.x, Y0+obj.y, Display.paint) END
					END
				END;
				INC(X0, dx); INC(X, DX)
			END
		END;
		(*Display.ReplConst(F.col, X0, y0-L.dsr, XT-X0, L.h, 0)*)
	END DisplayLine;

	PROCEDURE DisplaySec (F: Frame; x, y, Y0: INTEGER; org0: LONGINT; L0, L1: Line);
		VAR L: Line; Y: INTEGER;
	BEGIN L := L0; Y := Y0; Texts.OpenReader(R1, F.text, org0);
		WHILE L # L1 DO
			Erase(F, x, y, Y - L.h, L.h); DisplayLine(F, 0, 0, x, y, 0, Y, L); DEC(Y, L.h); L := L.next
		END
	END DisplaySec;

	PROCEDURE DisplaySec0 (F: Frame; x, y: INTEGER; org0, off: LONGINT; Y0: INTEGER; oldL0, L0, L1: Line);
	VAR pos: LONGINT; u, v, dx, xx: INTEGER; dXX: LONGINT;
	BEGIN
		IF (L0.asr = oldL0.asr) & (L0.dsr = oldL0.dsr) &
			((L0.style.opts * AdjMode = {Styles.left}) OR (L0.brk & oldL0.brk & (L0.style.opts * AdjMode = AdjMode))) THEN
			pos := Min(off, L0.len); Width(F, L0, org0, org0+pos, dx, dXX); Texts.OpenReader(R1, F.text, org0+pos);
			u := x+F.X+F.left; v := y+F.Y+Y0-L0.h; ReplConst(F.col, u, v, L0.off, L0.h);	(*left part*)
			xx := L0.off+dx; ReplConst(F.col, u+xx, v, F.W-xx-F.left, L0.h);
			DisplayLine(F, pos, dXX, x, y, dx, Y0, L0); Append(L0, F.left+xx, oldL0.box);	(*right part*)
			(*Display.ReplConst(15, u+xx, v, F.W-xx-F.left, L0.h, 2); debug*)
			DEC(Y0, L0.h); INC(org0, L0.len); L0 := L0.next
		END;
		DisplaySec(F, x, y, Y0, org0, L0, L1)
	END DisplaySec0;

	PROCEDURE ScrollBack(F: Frame; x, y: INTEGER; oldL: Line; VAR L: Line; VAR Y: INTEGER; VAR org: LONGINT);
	VAR
		L0: Line;
		dY, Y1: INTEGER;
	BEGIN d := 0; L.next := oldL; Y1 := Y; CollectLines(F, L, Y, org);
		IF L.next = oldL THEN L0 := L.next ELSE L0 := oldL END;	(* last line to draw *)
		dY := F.H - F.top - Y1; Move(F, x, y, Y + dY, Y1 - Y, -dY);
		DisplaySec(F, x, y, F.H - F.top, F.org, F.trailer.next, L0)
	END ScrollBack;

	(*---formatting---*)

	PROCEDURE Read;
	VAR
		obj: Objects.Object; G: Display.Frame;
		s: Styles.Style;
		v: INTEGER;
	BEGIN
		Texts.Read(R, ch);
		IF ~R.eot THEN R.lib.GetObj(R.lib, ORD(ch), obj);
			IF R.lib IS Fonts.Font THEN
				IF R.lib # R.fnt THEN R.fnt := R.lib(Fonts.Font); Styles.MetricFnt(R.fnt, R.unit, R.mfnt) END;
				Height(R.fnt, a, d);
				(*IF R.voff # 0 THEN v := (a+d)*R.voff DIV 100; INC(a, v); DEC(d, v) END;*)
				IF ch >= " " THEN
					dx := obj(Fonts.Char).dx;
					R.mfnt.GetObj(R.mfnt, ORD(ch), obj); dX := R.unit*obj(Fonts.Char).dx
				ELSE dx := 0; dX := 0
				END
			ELSIF obj IS Display.Frame THEN G := obj(Display.Frame);
				dx := G.W; dX := LONG(dx)*Display.Unit; d := FrameDsr(G); a := G.H - d
			ELSIF obj IS Styles.Style THEN s := obj(Styles.Style); style := s;
				dX := Styles.pageW; dx := SHORT(s.paraW DIV Display.Unit);
				a := SHORT(s.gap DIV Display.Unit); d := 0;
				IF R.hide THEN a := Max(1, a) ELSE G := Styles.NewFrame(s); INC(a, G.H) END
			ELSE dx := 2; dX := 2*Printer.Unit; Height(Fonts.Default, a, d)
			END;
			IF R.voff # 0 THEN v := (a+d)*R.voff DIV 100; INC(a, v); DEC(d, v) END
		ELSE dx := 0; dX := 0; a := 0; d := 0	(*a := Asr; d := Dsr*)
		END
	END Read;

	PROCEDURE InitFormatter(F: Frame; org: LONGINT);
	BEGIN
		Texts.OpenReader(R, F.text, org); R.fnt := NIL; R.hide := F.hide; Read;
		R.w := 0; R.len := 0; R.W := 0; R.nSpc := 0; R.asr := a; R.dsr := d;
		style := StyleAt(F, org)
	END InitFormatter;

	PROCEDURE FormatLine(VAR L: Line);
	VAR
		len, len0: LONGINT;
		w, spc, w0, nspc, dsr0, asr0, asr, dsr, width, lsp: INTEGER;
		W, Spc, W0, Width: LONGINT;
		brk, tab: BOOLEAN;
		s: Styles.Style;
		lsep: CHAR; obj: Objects.Object; dx0: INTEGER; dX0: LONGINT;	(*hyph*)
	BEGIN
		NEW(L); s := style;
		w := 0; len := 0; spc := 0; W := 0; Spc := 0;
		w0 := R.w; W0 := R.W; len0 := R.len; brk := FALSE; tab := FALSE; nspc := R.nSpc;
		asr := 0; dsr := 0; asr0 := R.asr; dsr0 := R.dsr;
		Width := style.paraW; width := SHORT(Width DIV Display.Unit);
		WHILE (w + spc + w0 + dx < width) & (W + Spc + W0 + dX < Width) & ~brk DO
			INC(len0);
			IF (R.lib # NIL) & (~(R.lib IS Fonts.Font) OR (ch > " ")) THEN
				INC(w0, dx); INC(W0, dX);
				IF a > asr0 THEN asr0 := a END; IF d > dsr0 THEN dsr0 := d END;
			ELSE 
				INC(w, spc + w0); INC(W, Spc + W0); INC(len, len0); w0 := 0; W0 := 0; len0 := 0;
				IF asr0 > asr THEN asr := asr0 END; IF dsr0 > dsr THEN dsr := dsr0 END;
				dsr0 := d; asr0 := a;
				IF ch = " " THEN spc := dx; Spc := dX; INC(nspc); tab := FALSE
				ELSIF ch = HYPH THEN spc := 0; Spc := 0; tab := TRUE	(*hyph*)
				ELSIF R.eot OR (ch = CR) THEN brk := TRUE; L.brk := TRUE; L.eot := R.eot;
					IF a > asr THEN asr := a END; IF d > dsr THEN dsr := d END; asr0 := 0; dsr0 := 0
				ELSIF ch = TAB THEN Styles.Tab(s, R.lib(Fonts.Font), w, W, spc, Spc); L.tabs := TRUE; tab := TRUE
				END;
				lsep := ch	(*hyph*)
			END;
			IF ~R.eot THEN Read END
		END;
		IF s # style (*OR (dx >= Width) OR (dX >= Width)*) (*OR brk (cr has no width)*) THEN
			INC(w, spc + w0); INC(W, Spc + W0); INC(len, len0); L.brk := TRUE;
			IF asr0 > asr THEN asr := asr0 END; IF dsr0 > dsr THEN dsr := dsr0 END;
			w0 := 0; W0 := 0; len0 := 0; asr0 := 0; dsr0 := 0	(*asr0 := Asr; dsr0 := Dsr*)
		END;
		IF len > 0 THEN
			IF lsep = HYPH THEN GetWidth(R.lib, "_", obj, dx0, dX0); INC(w, dx0); INC(W, dX0) END;	(*hyph*)
			L.w := w; L.W := W; L.len := len; L.asr := asr; L.dsr := dsr; L.nSpc := nspc;
			IF (nspc > 0) & ~tab THEN DEC(L.nSpc) END;
			R.w := w0; R.W := W0; R.len := len0; R.asr := asr0; R.dsr := dsr0
		ELSIF len0 > 0 THEN	(*one word*)
			L.w := w0; L.W := W0; L.len := len0; L.asr := asr0; L.dsr := dsr0; L.nSpc := 0;
			R.w := dx; R.W := dX; R.len := 1; R.asr := a; R.dsr := d
		ELSE	(*one char*)
			L.w := dx; L.W := dX; L.len := 1; L.asr := a; L.dsr := d;
			R.w := 0; R.W := 0; R.len := 0; R.asr := 0; R.dsr := 0	(*R.asr := Asr; R.dsr := Dsr*)
		END;
		IF (len = 0) & ~R.eot THEN Read END;
		L.style := s;
		lsp := SHORT(s.lsp DIV Display.Unit); dsr := SHORT(s.dsr DIV Display.Unit);	(*line spacing*)
		IF (Styles.grid IN s.opts) & (lsp > 0) THEN
			WHILE dsr < L.dsr DO INC(dsr, lsp) END;
			L.dsr := dsr;  L.h := Max(lsp, L.asr+dsr); INC(L.h, (-L.h) MOD lsp)
		ELSE L.dsr := Max(L.dsr, dsr); L.h := Max(lsp, L.asr+L.dsr)
		END;
		IF L.h = 0 THEN L.h := Asr+Dsr; L.dsr := Dsr END;	(*min height*)
		L.asr := L.h-L.dsr
	END FormatLine;

	PROCEDURE NewLines(F: Frame; limit: LONGINT; VAR L: Line; VAR Y: INTEGER; VAR org: LONGINT);
	VAR L1: Line;
	BEGIN InitFormatter(F, org); FormatLine(L1);
		WHILE ~L.eot & (Y >= F.bot + L1.h) & (org # limit) DO
			L.next := L1; L := L1; INC(org, L.len); DEC(Y, L.h); FormatLine(L1)
		END;
		L.next := L1	(*!*)
	END NewLines;

	PROCEDURE BottomLine(F: Frame; x, y, Y: INTEGER; VAR L: Line; org: LONGINT);
	VAR R: Texts.Finder; pos: LONGINT; obj: Objects.Object;
	BEGIN
		IF org < F.text.len THEN Texts.OpenFinder(R, F.text, org); pos := R.pos; Texts.FindObj(R, obj);
			IF (pos - org < L.next.len) & (obj # NIL) & (obj IS Display.Frame) THEN
				L := L.next; Erase(F, x, y, 0, Y);	(*clear to bottom*)
				Oberon.FadeCursor(Oberon.Mouse);
				Texts.OpenReader(R1, F.text, org); DisplayLine(F, 0, 0, x, y, 0, Y, L)
			ELSE Erase(F, x, y, F.bot, Y-F.bot)
			END
		ELSE Erase(F, x, y, F.bot, Y-F.bot)
		END
	END BottomLine;

	PROCEDURE AppendLines(F: Frame; x, y: INTEGER; org: LONGINT; L: Line; VAR Y: INTEGER);
	VAR
		L0: Line; Y0: INTEGER; org0: LONGINT;
		botY: INTEGER;
	BEGIN botY := F.bot; L0 := L; org0 := org; Y0 := Y;
		Erase(F, x, y, botY, Y0 - botY); (**)NewLines(F, F.text.len+1, L, Y, org);
		DisplaySec(F, x, y, Y0, org0, L0.next, L.next); BottomLine(F, x, y, Y, L, org);
		L.next := F.trailer
	END AppendLines;

	PROCEDURE ShowText (F: Frame; x, y: INTEGER; pos: LONGINT);
	VAR
		org, oldOrg, org0: LONGINT;
		curY, Y0, dY, botY: INTEGER;
		L, L1, oldL: Line;
	BEGIN	(* pos valid *)
		RemTick(F, x, y);
		botY := F.bot; curY := F.H - F.top;
		IF pos < F.org THEN
			oldOrg := F.org; oldL := F.trailer.next; org := pos; F.org := pos; L := F.trailer;
			Y0 := curY; NewLines(F, oldOrg, L, curY, org);	(* curY org L *)
			IF org = oldOrg THEN ScrollBack(F, x, y, oldL, L, curY, org)
			ELSE	(* totally before *)
				DisplaySec(F, x, y, Y0, F.org, F.trailer.next, L.next)
			END;
			BottomLine(F, x, y, curY, L, org); L.next := F.trailer	(*Erase(F, x, y, botY, curY - botY)*)
		ELSE (* pos >=org *)
			L := F.trailer; org := F.org;
			WHILE (L.next # F.trailer) & (org # pos) DO L := L.next; INC(org, L.len); DEC(curY, L.h) END;	(* find pos *)
			L1 := L.next;	(* curY org L1 *)
			IF (org = pos) & (L.next # F.trailer) THEN org0 := org; Y0 := curY; CollectLines(F, L, curY, org);	(* curY org L *)
				IF (L.next # F.trailer) & (F.org = org0) THEN	(*cut rest*)
					IF (L.next.box # NIL) & (curY > botY) THEN BottomLine(F, x, y, curY, L, org); curY := botY END;
					L.next := F.trailer; Erase(F, x, y, 0, curY)
				ELSE
					F.org := org0; F.trailer.next := L1; dY := F.H - F.top - Y0;
					IF dY # 0 THEN Move(F, x, y, curY, Y0 - curY, dY); INC(curY, dY) END;
					IF (L.next = F.trailer) & (L.box # NIL) THEN	(*redraw if more lines in frame*)
						Texts.OpenReader(R1, F.text, org-L.len); DisplayLine(F, 0, 0, x, y, 0, curY+L.h, L)
					END;
					AppendLines(F, x, y, org, L, curY)
				END
			ELSE	(* outside *)
				F.org := pos; curY := F.H - F.top; AppendLines(F, x, y, pos, F.trailer, curY)
			END
		END;
		ShowTick(F, x, y);
		ShowBrk(F, Display.FG, x, y)
	END ShowText;

	PROCEDURE Resize* (F: Frame; x, y, newY: INTEGER);
	BEGIN (*F.mark = 0*)
		IF newY < F.Y THEN Bar(F, x, y, newY-F.Y, F.Y - newY) END;	(* extend *)
		F.H := F.H + F.Y - newY; F.Y := newY;
		ShowText(F, x, y, F.org)
	END Resize;


	(*---locators---*)

	PROCEDURE LocateOrg(F: Frame; org, pos: LONGINT; VAR loc: Location);
		VAR L: Line; cury: INTEGER;
	BEGIN
		cury := F.H - F.top; L := F.trailer.next;
		IF pos < org THEN pos := org END;
		WHILE (L.next # F.trailer) & (pos >= org + L.len) DO
			INC(org, L.len); DEC(cury, L.h); L := L.next
		END;
		loc.org := org; loc.pos := pos; loc.lin := L;
		loc.x := F.left; loc.y := cury - L.asr
	END LocateOrg;

	PROCEDURE LocateLine (F: Frame; y: INTEGER; VAR loc: Location);
		VAR L: Line; cury: INTEGER;
	BEGIN loc.org := F.org; cury := F.H - F.top; L := F.trailer.next;
		WHILE (L.next # F.trailer) & (cury - L.h > y) & (cury - L.h - L.next.h >= F.bot) DO
			INC(loc.org, L.len); DEC(cury, L.h); L := L.next
		END;
		loc.y := cury - L.asr; loc.lin := L
	END LocateLine;

	PROCEDURE LocateObj (F: Frame; x, y: INTEGER; VAR loc: Location; VAR obj: Objects.Object);
		VAR R: Texts.Reader; pos, lim: LONGINT; ox, dx: INTEGER; ch: CHAR;
			spc, rest: INTEGER; L: Line;
			X, DX: LONGINT;
	BEGIN LocateLine(F, y, loc); L := loc.lin; Offsets(L, spc, rest);
		pos := loc.org; lim := loc.org+L.len- 1; ox := F.left + L.off; X := 0; obj := NIL;
		IF pos <= lim THEN
			Texts.OpenReader(R, F.text, pos); dx := 0; DX := 0; DEC(pos);
			REPEAT
				Texts.Read(R, ch);
				INC(ox, dx); INC(X, DX); INC(pos);
				IF R.lib # NIL THEN GetWidth(R.lib, ch, obj, dx, DX);
					IF R.lib IS Fonts.Font THEN
						IF ch = TAB THEN Styles.Tab(L.style, R.lib(Fonts.Font), ox - L.off - F.left, X, dx, DX)
						ELSIF ch = " " THEN IncPos(spc, rest, dx)
						ELSIF ch = HYPH THEN dx := 0; DX := 0	(*hyph*)
						END
					END
				ELSE obj := NIL
				END
			UNTIL (obj = NIL) OR (pos = lim) OR (ox+dx > x)
		END;
		IF pos = lim THEN
			IF (ch = CR) OR (obj = NIL) THEN dx := eolW
			ELSIF (ch = " ") OR (ch = TAB) THEN dx := SpcW
			END
		END;
		loc.pos := pos; loc.dx := dx; loc.x := ox
	END LocateObj;

	PROCEDURE LocatePos (F: Frame; pos: LONGINT; VAR loc: Location);
		VAR dX: LONGINT; dx: INTEGER;
	BEGIN LocateOrg(F, F.org, pos, loc);
		IF pos >= loc.org + loc.lin.len THEN pos := loc.org + loc.lin.len - 1 ELSIF pos < F.org THEN pos := F.org END;
		Width(F, loc.lin, loc.org, pos, dx, dX); loc.pos := pos; INC(loc.x, dx+loc.lin.off)
	END LocatePos;

	PROCEDURE LocateString (F: Frame; x, y: INTEGER; VAR loc: Location);
	VAR
		pos, end, X, lim: LONGINT;
		ch: CHAR;
		R: Texts.Reader;
		obj: Objects.Object;
	BEGIN LocateObj(F, x, y, loc, obj); lim := loc.org+loc.lin.len;
		end := loc.pos; Texts.OpenReader(R, F.text, end); Texts.Read(R, ch);
		IF R.lib # NIL THEN
			IF (R.lib IS Fonts.Font) & (ch <= " ") THEN	(*backwards*)
				REPEAT DEC(end); Texts.OpenReader(R, F.text, end); Texts.Read(R, ch)
				UNTIL (end < loc.org) OR ~(R.lib IS Fonts.Font) OR (ch > " ");
				INC(end); pos := end
			ELSIF R.lib # NIL THEN	(*forward*)
				REPEAT INC(end); Texts.Read(R, ch)
				UNTIL (R.lib = NIL) OR (end >= lim) OR (R.lib IS Fonts.Font) & (ch <= " ");
				pos := loc.pos
			END
		ELSE pos := end
		END;
		REPEAT DEC(pos); Texts.OpenReader(R, F.text, pos); Texts.Read(R, ch);
		UNTIL (pos < loc.org) OR (R.lib IS Fonts.Font) & (ch <= " ");
		INC(pos); LocatePos(F, pos, loc); Width(F, loc.lin, pos, end, loc.dx, X)
	END LocateString;

	PROCEDURE FindFrame(F: Frame; G: Display.Frame; VAR loc: Location);
	VAR Y: INTEGER; L: Line; b: Box;
	BEGIN Y := F.H-F.top; L := F.trailer.next; loc.org := F.org; loc.pos := -1;
		WHILE L # F.trailer DO DEC(Y, L.h);
			IF L.box # NIL THEN b := L.box.next;
				WHILE b # L.box DO
					IF b.F = G THEN loc.x := b.X; loc.y := Y+L.dsr-b.dY; loc.dx := b.F.W;
						loc.pos := loc.org+b.off; loc.lin := L; RETURN
					END;
					b := b.next
				END
			END;
			INC(loc.org, L.len); L := L.next
		END
	END FindFrame;
(*
	PROCEDURE FindObj(F: Frame; G: Display.Frame; VAR pos: LONGINT): BOOLEAN;
	VAR loc: Location;
	BEGIN FindFrame(F, G, loc); pos := loc.pos; RETURN (loc.pos >= 0)
	END FindObj;
*)
	PROCEDURE TouchFrame(F: Frame; VAR M: Oberon.InputMsg): BOOLEAN;
	VAR X, Y: INTEGER; b: Box; loc: Location; G: Display.Frame;
	BEGIN
		IF F.trailer.next # F.trailer THEN
			X := M.X-F.X-M.x; Y := M.Y-F.Y-M.y; LocateLine(F, Y, loc);
			IF Y < loc.y-loc.lin.dsr THEN DEC(loc.y, loc.lin.dsr+loc.lin.next.asr); loc.lin := loc.lin.next END;	(*bottom*)
			IF loc.lin.box # NIL THEN b := loc.lin.box;
				WHILE (b.next.X <= X) DO b := b.next END;
				G := b.F; DEC(loc.y, b.dY);
				IF (G # NIL) & (X < b.X+G.W) & (loc.y <= Y) & (Y < loc.y+G.H) THEN
					Oberon.FadeCursor(Oberon.Mouse);	(*clip !*)
					INC(M.x, F.X+b.X-G.X); INC(M.y, F.Y+loc.y-G.Y); M.dlink := Mask(F); G.handle(G, M);
					RETURN (M.res >= 0)
				END
			END
		END;
		RETURN FALSE
	END TouchFrame;

	PROCEDURE Pos* (F: Frame; X, Y: INTEGER): LONGINT;	(* local coords *)
	VAR loc: Location; obj: Objects.Object;
	BEGIN LocateObj(F, X, Y, loc, obj); RETURN loc.pos
	END Pos;

	PROCEDURE ParaBeg(T: Texts.Text; pos: LONGINT; VAR org: LONGINT);
	VAR R: Texts.Reader; ch: CHAR; obj: Objects.Object;
	BEGIN org := pos;
		WHILE org > 0 DO
			Texts.OpenReader(R, T, org-1); Texts.Read(R, ch);
			R.lib.GetObj(R.lib, ORD(ch), obj);
			IF (ch = CR) & (obj IS Fonts.Char) OR (obj IS Styles.Style) THEN RETURN END;
			DEC(org)
		END
	END ParaBeg;

	PROCEDURE Validate (F: Frame; VAR pos: LONGINT);	(* find org of line *)
		VAR org: LONGINT; L: Line; loc: Location;
	BEGIN
		IF F.trailer.next # F.trailer THEN
			IF pos >= F.org THEN LocateOrg(F, F.org, pos, loc);	(* find start of line within line list *)
				IF pos < loc.org + loc.lin.len THEN pos := loc.org; RETURN END
			END;
		END;
		IF pos > F.text.len THEN pos := F.text.len END;
		IF pos > 0 THEN ParaBeg(F.text, pos, org);
			InitFormatter(F, org); FormatLine(L);
			WHILE org + L.len <= pos DO INC(org, L.len); FormatLine(L) END;
			pos := org
		ELSE pos := 0
		END
	END Validate;

	PROCEDURE SetAttributes(F: Frame; pos: LONGINT);
		VAR R: Texts.Reader; x: CHAR; 
	BEGIN
		IF (F.text.len > 0) & (pos = F.text.len) THEN DEC(pos) END;
		Texts.OpenReader(R, F.text, pos); Texts.Read(R, x);
		IF (R.lib = NIL) OR ~(R.lib IS Fonts.Font) THEN
			Texts.SetFont(KW, Oberon.CurFnt); Texts.SetColor(KW, Oberon.CurCol); Texts.SetOffset(KW, Oberon.CurOff)
		ELSE
			Texts.SetFont(KW, R.lib); Texts.SetColor(KW, R.col); Texts.SetOffset(KW, R.voff)
		END
	END SetAttributes;

	(*---caret & selection---*)

	PROCEDURE SetCaret* (F: Frame; pos: LONGINT);
	BEGIN
		IF ~F.car OR (F.carLoc.pos # pos) THEN
			IF F.car THEN Marks(F, car); F.car := FALSE END;
			IF (pos < F.org) OR (pos >= Lim(F)) THEN show(F, pos) END;
			LocatePos(F, pos, F.carLoc); Marks(F, car); F.car := TRUE;	(*old version*)
			SetAttributes(F, F.carLoc.pos)
		END
	END SetCaret;

	PROCEDURE RemoveCaret* (F: Frame);
	BEGIN IF F.car THEN Marks(F, car) END; F.car := FALSE
	END RemoveCaret;

	PROCEDURE SetSelection* (F: Frame; beg, end: LONGINT);
	BEGIN
		IF F.sel THEN Marks(F, sel) END;
		IF (beg < F.org) OR (beg >= Lim(F)) THEN show(F, beg) END;
		LocatePos(F, beg, F.selBeg); LocatePos(F, end, F.selEnd);
		IF F.selBeg.pos < F.selEnd.pos THEN
			Marks(F, sel); F.time := Oberon.Time(); F.sel := TRUE
		END
	END SetSelection;

	PROCEDURE RemoveSelection* (F: Frame);
	BEGIN IF F.sel THEN Marks(F, sel); F.sel := FALSE END
	END RemoveSelection;

	PROCEDURE RemoveMarks (F: Frame);
	BEGIN RemoveCaret(F); RemoveSelection(F)
	END RemoveMarks;

	PROCEDURE Neutralize* (F: Frame);
	BEGIN RemoveMarks(F)
	END Neutralize;

	(*---update---*)

	PROCEDURE UpdateVisible(F: Frame; x, y: INTEGER; beg, end, corr: LONGINT);
	VAR
		oldL, oldL0, L, L0: Line;
		oldorg, org, org0: LONGINT;
		oldY, dY, Y, Y0, Y1, botY: INTEGER;
	BEGIN
		org := F.org; Y := F.H - F.top; L := F.trailer; botY := F.bot;
		WHILE (L.next # F.trailer) & (org + L.next.len <= beg) DO	(* find line where beg lies in *)
			L := L.next; INC(org, L.len); DEC(Y, L.h)
		END;
		IF L.next # F.trailer THEN
			(* [org, Y, L.next] = line where update starts *)
			oldorg := org; oldY := Y; oldL := L.next; oldL0 := oldL;
			INC(oldorg, oldL.len); DEC(oldY, oldL.h); oldL := oldL.next;	(* set org to next line *)
			IF (corr <= 0) OR (corr < end-beg) THEN
				WHILE (oldorg < end) & (oldL # F.trailer) DO
					INC(oldorg, oldL.len); DEC(oldY, oldL.h); oldL := oldL.next	(* find last line of update *)
				END
			END;
			oldorg := oldorg + corr;
			InitFormatter(F, org); FormatLine(L.next);
			IF Y >= botY + L.next.h THEN
				org0 := org; Y0 := Y; L0 := L.next;	(* L0 = first line *)
				LOOP
					L := L.next; INC(org, L.len); DEC(Y, L.h);
					IF L.eot THEN EXIT END;
					WHILE (oldL # F.trailer) & (oldorg < org) DO
						INC(oldorg, oldL.len); DEC(oldY, oldL.h); oldL := oldL.next
					END;
					IF (oldorg = org) & (style = oldL.style) THEN EXIT END;	(* old and new structure are synchronized again *)
					FormatLine(L.next);
					IF Y < botY + L.next.h THEN EXIT END	(* bot of frame *)
				END;
				IF L.eot OR ((oldorg # org) OR (style # oldL.style)) & (Y < botY + L.next.h) THEN (* redisplay to bottom of frame *)
					DisplaySec0(F, x, y, org0, beg - org0, Y0, oldL0, L0, L.next);
					BottomLine(F, x, y, Y, L, org);
(*
					IF org # oldorg THEN BottomLine(F, x, y, Y, L, org) ELSE Erase(F, x, y, botY, Y - botY) END;
*)
					L.next := F.trailer
					(* Erase(F, x, y, botY, Y - botY)	cleanup *)
				ELSE (* (oldorg = org) & (style = oldL.style) *)
					dY := Y - oldY; L.next := oldL;	(* connect line lists *)
					IF dY # 0 THEN Y1 := Y;	(* move sync part *)
						INC(F.bot, Max(dY, 0)); CollectLines(F, L, Y, org); F.bot := botY;	(*cut off bottom line*)
						Move(F, x, y, Y - dY, Y1 - Y, dY)
					END;
					DisplaySec0(F, x, y, org0, beg - org0, Y0, oldL0, L0, oldL);
					IF dY # 0 THEN AppendLines(F, x, y, org, L, Y) END;
				END
			ELSE (*L.next := F.trailer; Erase(F, x, y, botY, Y - botY)*)
				BottomLine(F, x, y, Y, L, org); L.next := F.trailer
			END
		END
	END UpdateVisible;

	PROCEDURE UpdateSection (F: Frame; x, y: INTEGER; beg, end, corr: LONGINT);
	VAR
		L, L0: Line;
		org: LONGINT;
	BEGIN L := F.trailer.next;
		IF (F.org > 0) & (beg < F.org + L.len) THEN
			IF beg < F.org THEN INC(F.org, corr); corr := 0; beg := F.org END;
			org := F.org -1; Validate(F, org); InitFormatter(F, org); FormatLine(L0);	(*outside line*)
			IF (org + L0.len = F.org) & (L0.style = L.style) THEN
				IF end > F.org THEN UpdateVisible(F, x, y, beg, end, corr) END
			ELSE
				IF F.org-org < L0.len DIV 3 THEN INC(corr, F.org-org); F.org := org
				ELSE DEC(corr, org + L0.len-F.org); F.org := org + L0.len
				END;
				IF end < F.org THEN end := F.org+corr END; UpdateVisible(F, x, y, F.org, end, corr)
			END
		ELSE
			org := F.org; L := F.trailer;
			WHILE (L.next # F.trailer) & (org + L.next.len <= beg) DO L := L.next; INC(org, L.len) END;
			IF org > 0 THEN InitFormatter(F, org - L.len); FormatLine(L0);
				IF (L0.len # L.len) OR (L.next.style # StyleAt(F, org)) THEN beg := org - L.len END	(*start at prev line*)
			END;
			IF (beg < org) OR (L.next # F.trailer) THEN UpdateVisible(F, x, y, beg, end, corr) END
(*
			IF L.next # F.trailer THEN
				IF org > 0 THEN
					InitFormatter(F, org - L.len); FormatLine(L0);
					IF L0.len # L.len THEN beg := org - L.len END	(*start at prev line*)
				END;
				UpdateVisible(F, x, y, beg, end, corr)
			END
*)
		END
	END UpdateSection;

	PROCEDURE DisplaySecBrk (F: Frame; x, y, Y0: INTEGER; org0: LONGINT; L0, L1: Line);
		VAR L: Line; Y: INTEGER;
	BEGIN L := L0; Y := Y0; Texts.OpenReader(R1, F.text, org0);
		WHILE L # L1 DO
			IF ~L.brk THEN Erase(F, x, y, Y - L.h, L.h); DisplayLine(F, 0, 0, x, y, 0, Y, L)
			ELSE Texts.OpenReader(R1, F.text, Texts.Pos(R1)+L.len)	(*skip*)
			END;
			DEC(Y, L.h); L := L.next
		END
	END DisplaySecBrk;

	PROCEDURE UpdateStyle(F: Frame; VAR M: Styles.UpdateMsg);
	VAR
		L0, L1: Line;
		org0, org1, pos, len: LONGINT;
		Y0, Y1, Y: INTEGER;
		style: Styles.Style;
		L: Line; org: LONGINT;
		tabs: BOOLEAN;
	BEGIN
		RemoveMarks(F); style := M.obj;
		L0 := F.trailer.next; org0 := F.org; Y0 := F.H - F.top;	(* top line *)
		WHILE L0 # F.trailer DO 
			IF L0.style = style THEN	(* [org0 Y0 L0] *) 
				org1 := org0; Y1 := Y0; L1 := L0;
				REPEAT INC(org1, L1.len); DEC(Y1, L1.h); L1 := L1.next UNTIL (L1 = F.trailer) OR (L1.style # style);
				(* [org1 Y1 L1] (first outside) *)
				IF (M.id = Styles.leftmarg) & (M.dX # 0) THEN DisplaySec(F, M.x, M.y, Y0, org0, L0, L1)
				ELSIF M.id = Styles.fmode THEN
					IF (M.dX = Styles.right) & (Styles.left IN style.opts) THEN DisplaySecBrk(F, M.x, M.y, Y0, org0, L0, L1)
					ELSE DisplaySec(F, M.x, M.y, Y0, org0, L0, L1)
					END;
				ELSIF M.id = Styles.tabs THEN
					WHILE L0 # L1 DO
						IF L0.tabs THEN	(*format upto next line break*)
							L := L0; org := org0; Y := Y0; len := 0; tabs := FALSE;
							WHILE ~L.brk & (L.next # L1) DO
								IF L.tabs THEN len := org+L.len-org0 END;	(*text portion to be formatted anyway*)
								INC(org, L.len); DEC(Y, L.h); L := L.next
							END;
							IF L.tabs THEN INC(len, L.len) END;
							INC(org, L.len); L := L.next; DEC(Y, L.h);	(*line after brk or L1*)
							UpdateSection(F, M.x, M.y, org0, org0+len, 0); L0 := L; org0 := org; Y0 := Y (*L0 := L1*)
						ELSE INC(org0, L0.len); DEC(Y0, L0.h); L0 := L0.next
						END
					END
				ELSIF M.id < 0 THEN	(* break -> no formatting *)
				ELSE
					pos := org0; Validate(F, pos); UpdateSection(F, M.x, M.y, pos, org1, 0)	(* replace *)
				END;
				L0 := L1; org0 := org1; Y0 := Y1
			ELSE
				INC(org0, L0.len); DEC(Y0, L0.h); L0 := L0.next
			END
		END
	END UpdateStyle;

	(*---user interface---*)

	PROCEDURE TrackCaret* (F: Frame; x, y, X, Y: INTEGER; VAR keysum: SET);
		VAR keys: SET;
	BEGIN
		IF F.trailer.next # F.trailer THEN keysum := {};
			REPEAT
				TrackMouse(X, Y, keys, keysum);
				SetCaret(F, Pos(F, X - F.X - x, Y - F.Y - y))
			UNTIL keys = {};
(*
			LocateObj(F, X - F.X - x, Y - F.Y - y, F.carLoc, obj);
			FlipCaret(F, x, y);
			keysum := {};
			REPEAT
				TrackMouse(X, Y, keys, keysum); LocateObj(F, X - F.X - x, Y - F.Y - y, loc, obj);
				IF loc.pos # F.carLoc.pos THEN FlipCaret(F, x, y); F.carLoc := loc; FlipCaret(F, x, y) END
			UNTIL keys = {};
			F.car := TRUE;
			KW.lib := FontAt(F.text, F.carLoc.pos)
*)
		END
	END TrackCaret;

	PROCEDURE TrackSelection* (F: Frame; x, y, X, Y: INTEGER; VAR keysum: SET);
		VAR loc: Location; obj: Objects.Object; modKeys, keys: SET; M: Oberon.SelectMsg;
	BEGIN
		IF F.trailer.next # F.trailer THEN
			IF F.sel THEN FlipSelection(F, x, y, F.selBeg, F.selEnd) END;
			LocateObj(F, X - F.X - x, Y - F.Y - y, loc, obj);
			IF F.sel & (loc.pos = F.selBeg.pos) & (F.selEnd.pos = F.selBeg.pos + 1) THEN
				LocateObj(F, F.left, Y - F.Y - y, F.selBeg, obj)
			ELSE F.selBeg := loc
			END;
			F.sel := FALSE;
			INC(loc.pos); INC(loc.x, loc.dx); F.selEnd := loc;
			FlipSelection(F, x, y, F.selBeg, F.selEnd);
			keysum := {};
			REPEAT
				TrackMouse(X, Y, keys, keysum); LocateObj(F, X - F.X - x, Y - F.Y - y, loc, obj);
				IF loc.pos < F.selBeg.pos THEN loc := F.selBeg END;
				INC(loc.pos); INC(loc.x, loc.dx);
				IF loc.pos < F.selEnd.pos THEN FlipSelection(F, x, y, loc, F.selEnd)
				ELSIF loc.pos > F.selEnd.pos THEN FlipSelection(F, x, y, F.selEnd, loc) 
				END;
				F.selEnd := loc
			UNTIL keys = {};
			(* ps - 3.4.98 *)
			Input.KeyState(modKeys);
			IF Input.SHIFT IN modKeys THEN
				M.id := Oberon.get; M.F := NIL; M.sel := NIL; M.text := NIL; M.time := -1; Display.Broadcast(M);
				IF (M.time > 0) & (M.text = F.text) & (M.sel IS Frame) THEN
					IF M.beg > F.selBeg.pos THEN M.beg := F.selBeg.pos END;
					IF M.end < F.selEnd.pos THEN M.end := F.selEnd.pos END;
					FlipSelection(F, x, y, F.selBeg, F.selEnd);
					LocatePos(F, M.beg, F.selBeg); LocatePos(F, M.end, F.selEnd);
					FlipSelection(F, x, y, F.selBeg, F.selEnd);
					M.F := M.sel; M.id := Oberon.set; Display.Broadcast(M);
				END
			END;
			F.time := Oberon.Time(); F.sel := TRUE
		END
	END TrackSelection;

	PROCEDURE TrackLine* (F: Frame; x, y, X, Y: INTEGER; VAR org: LONGINT; VAR keysum: SET);
		VAR old, new: Location; keys: SET;
	BEGIN org := -1;
		IF F.trailer.next # F.trailer THEN
			LocateLine(F, Y - F.Y - y, old); DEC(old.y, old.lin.dsr);
			InvertRect(F, x, y, F.left + old.lin.off, old.y, old.lin.w0, 2);
			keysum := {};
			REPEAT
				TrackMouse(X, Y, keys, keysum);
				LocateLine(F, Y - F.Y - y, new); DEC(new.y, new.lin.dsr);
				IF new.org # old.org THEN
					InvertRect(F, x, y, F.left + old.lin.off, old.y, old.lin.w0, 2);
					InvertRect(F, x, y, F.left + new.lin.off, new.y, new.lin.w0, 2);
					old := new
				END
			UNTIL keys = {};
			InvertRect(F, x, y, F.left + new.lin.off, new.y, new.lin.w0, 2);
			org := new.org
		END
	END TrackLine;

	PROCEDURE TrackWord* (F: Frame; x, y, X, Y: INTEGER; VAR pos: LONGINT; VAR keysum: SET);
		VAR old, new: Location; keys: SET;
	BEGIN pos := -1;
		IF F.trailer.next # F.trailer THEN
			LocateString(F, X - F.X - x, Y - F.Y - y, old); DEC(old.y, old.lin.dsr);
			InvertRect(F, x, y, old.x, old.y, old.dx, 2);
			keysum := {};
			REPEAT
				TrackMouse(X, Y, keys, keysum);
				LocateString(F, X - F.X - x, Y - F.Y - y, new); DEC(new.y, new.lin.dsr);
				IF new.pos # old.pos THEN
					InvertRect(F, x, y, old.x, old.y, old.dx, 2); InvertRect(F, x, y, new.x, new.y, new.dx, 2); old := new
				END
			UNTIL keys = {};
			InvertRect(F, x, y, new.x, new.y, new.dx, 2);
			pos := new.pos
		END
	END TrackWord;

	PROCEDURE Show* (F: Frame; pos: LONGINT);
	VAR M: DisplayMsg;
	BEGIN
		IF F.trailer.next # F.trailer THEN Validate(F, pos);
			M.device := Display.screen; M.id := Display.full; M.F := F; M.pos := pos; Display.Broadcast(M)
		END
	END Show;

	PROCEDURE CallCmd (cmd: ARRAY OF CHAR; F: Frame; pos: LONGINT; new: BOOLEAN);
		VAR res: INTEGER; par: Oberon.ParList;
	BEGIN
		NEW(par);
		par.frame := F; par.text := F.text; par.pos := pos;
		Oberon.Call(cmd, par, new, res);
		IF res > 0 THEN Texts.WriteString(W, "Call error: "); 
			Texts.WriteString(W, Modules.resMsg);
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END
	END CallCmd;

	PROCEDURE Call* (F: Frame; pos: LONGINT; new: BOOLEAN);
		VAR S: Texts.Scanner;
	BEGIN
		Texts.OpenScanner(S, F.text, pos); Texts.Scan(S);
		IF S.class = Texts.Name THEN CallCmd(S.s, F, pos + S.len, new) END
	END Call;

	(*---message handling---*)

	PROCEDURE Warning(s: ARRAY OF CHAR);
	BEGIN
		Texts.SetFont(W, Fonts.Default); Texts.WriteString(W, s); Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf)
	END Warning;

	PROCEDURE Integrate(F: Frame; pos: LONGINT; obj: Objects.Object; new: BOOLEAN);
		VAR N: Display.ControlMsg; len: LONGINT;
	BEGIN	(*clear XW.buf*)
		WHILE obj # NIL DO
			IF ~new THEN	(*unbind*)
				(*IF (obj.lib = NIL) OR (obj.lib = F.text.obs) OR (obj.lib.name = "") THEN	(*free own or public*)*)
					N.id := Display.remove; N.F := obj(Display.Frame); Display.Broadcast(N)
				(*ELSE Warning("cannot insert object: movement across library")
				END*)
			END;
			IF obj IS Display.Frame THEN Deselect(F, obj(Display.Frame)) END;
			IF (obj IS Display.Frame) OR (obj IS Styles.Style) THEN
			(*	(*IF (obj.lib = NIL) OR (obj.lib.name = "") THEN	!*)
				lib := Objs(F.text); lib.GenRef(lib, ref);
				IF ref > 255 THEN F.text.obs := NIL; lib := Objs(F.text); lib.GenRef(lib, ref) END;
				lib.PutObj(lib, ref, obj)
				(*ELSE lib := obj.lib; ref := obj.ref	!
				END*); Texts.SetFont(XW, lib); Texts.Write(XW, CHR(ref))*)
				Texts.WriteObj(XW, obj)
			ELSE Warning("cannot insert object: not a frame")
			END;
			obj := obj.slink
		END;
		len := XW.buf.len;
		Texts.Insert(F.text, pos, XW.buf);
		IF new THEN SetCaret(F, pos+len) END
	END Integrate;

	PROCEDURE Write* (F: Frame; ch: CHAR; lib: Objects.Library; col, voff: SHORTINT);
	VAR
		M: Objects.CopyMsg; obj: Objects.Object;
		pos, i: LONGINT;
		s: ARRAY 64 OF CHAR;

		PROCEDURE char(ch: CHAR): BOOLEAN;
		BEGIN RETURN (20X <= ch) & (ch <= 96X) & (ch # 7FX) OR (ch = CR) OR (ch = TAB) OR (ch = HYPH)	(*hyph*)
		END char;
	
		PROCEDURE ReadAll(ch: CHAR; VAR s: ARRAY OF CHAR);
		VAR i: INTEGER;
		BEGIN s[0] := ch; i := 1;
			WHILE Input.Available() > 0 DO Input.Read(s[i]); INC(i) END;
			s[i] := 0X
		END ReadAll;

	BEGIN (*F.car*)
		pos := F.carLoc.pos;
		IF ch = 7FX THEN
			IF pos > F.org THEN
				Texts.Delete(F.text, pos - 1, pos); DEC(pos)
			END;
			ReadAll(ch, s)	(*flush*)
		ELSIF char(ch) THEN
			ReadAll(ch, s);
			(*IF FALSE THEN KW.lib := lib; KW.col := col; KW.voff := voff END;*)
			i := 0; WHILE char(s[i]) DO Texts.Write(KW, s[i]); INC(i) END;
			IF i > 0 THEN Texts.Insert(F.text, pos, KW.buf); INC(pos, i) END
		ELSE
			IF ch = LeftArrow THEN DEC(pos)
			ELSIF ch = RightArrow THEN INC(pos)
			ELSIF ch = BRK THEN obj := StyleAt(F, pos);	(*copy style*)
				M.id := Objects.deep; obj.handle(obj, M); Integrate(F, pos, M.obj, TRUE); RETURN
			END;
			ReadAll(ch, s)	(*flush*)
		END;
		IF (pos < F.text.len) & (pos >= Lim(F)) THEN
			WHILE (pos >= Lim(F)) DO Show(F, F.org+F.trailer.next.len) END
		ELSIF pos < F.org THEN Show(F, pos)
		END;
		SetCaret(F, pos)
	END Write;

	PROCEDURE Open* (F: Frame; H: Objects.Handler; T: Texts.Text; org: LONGINT;
				col, left, right, top, bot: INTEGER);
		VAR L: Line;
	BEGIN NEW(L);
		L.len := 0; L.w := 0; L.eot := FALSE; L.next := L;
		F.handle := H; F.text := T; F.org := org; F.trailer := L;
		F.left := left; F.right := right; F.top := top; F.bot := bot;
		F.col := col; F.mark := 0; F.car := FALSE; F.sel := FALSE;
	END Open;

	PROCEDURE Copy* (F: Frame; VAR F1: Frame);
	BEGIN NEW(F1); Open(F1, F.handle, F.text, F.org, F.col, F.left, F.right, F.top, F.bot);
		F1.hide := F.hide
	END Copy;

	PROCEDURE CopyOver* (F: Frame; text: Texts.Text; beg, end: LONGINT);
		VAR buf: Texts.Buffer;
	BEGIN
		IF F.car THEN
			SaveAndCopy(F, text, beg, end, XW); buf := XW.buf;
			Texts.Insert(F.text, F.carLoc.pos, buf);
			SetCaret(F, F.carLoc.pos + (end - beg))
		END
	END CopyOver;

	PROCEDURE GetSelection* (F: Frame; VAR M: Oberon.SelectMsg);
	BEGIN
		IF F.sel THEN
			IF F.time > M.time THEN M.sel := F; M.time := F.time;
				M.text := F.text; M.beg := F.selBeg.pos; M.end := Min(F.selEnd.pos, F.text.len)
(*
			ELSIF (F.text = M.text) & (F.selBeg.pos < M.beg) & (M.sel IS Frame) THEN	(* extend selection over frame boundaries *)
    		    IF (M.beg <= M.sel(Frame).org) & (F.selEnd.pos >= Pos(F, F.X+F.W, F.Y)) THEN
					M.beg := F.selBeg.pos
  		      END
*)
			ELSIF F.text = M.text THEN	(* extend selection over frame boundaries *)
				(* 7.4.98 - ps *)
				IF (F.selBeg.pos < M.beg) & (F.selEnd.pos >= Pos(F, F.X+F.W, F.Y)) THEN M.beg := F.selBeg.pos END;
				IF (F.selEnd.pos > M.end) & (F.selBeg.pos = F.org) THEN M.end := F.selEnd.pos END;
				IF M.end > F.text.len THEN M.end :=  F.text.len END
			END
		END
	END GetSelection;

	PROCEDURE GetCaret* (F: Frame; VAR M: Oberon.CaretMsg);
	BEGIN
		IF F.car THEN M.car := F; M.text := F.text; M.pos := F.carLoc.pos; M.res := 0 END
	END GetCaret;

	PROCEDURE Update* (F: Frame; VAR M: Texts.UpdateMsg);
		VAR end: LONGINT;
	BEGIN (*F.text = M.text*)
		RemoveMarks(F);
		ShowBrk(F, 0, M.x, M.y); F.slink := NIL;
		end := M.beg + M.len; IF M.end > end THEN end := M.end END;
		UpdateSection(F, M.x, M.y, M.beg, end, M.beg + M.len - M.end)
(*
		IF M.len = M.end - M.beg THEN UpdateSection(F, M.x, M.y, M.beg, M.end, 0)	(*change*)
		ELSIF M.beg = M.end THEN UpdateSection(F, M.x, M.y, M.beg, M.beg + M.len, M.len)	(*insert*)
		ELSIF M.len = 0 THEN UpdateSection(F, M.x, M.y, M.beg, M.end, M.beg - M.end)	(*delete*)
		(*ELSE UpdateSection(F, M.x, M.y, M.beg, M.end, M.beg - M.end + M.len)*)
		END
*)
	END Update;

	PROCEDURE Recall (F: Frame);
		VAR buf: Texts.Buffer; pos: LONGINT;
	BEGIN	(*F.car*)
		NEW(buf); Texts.OpenBuf(buf); Texts.Recall(buf); pos := F.carLoc.pos + buf.len;
		Texts.Insert(F.text, F.carLoc.pos, buf); SetCaret(F, pos)
	END Recall;

(*--back scroll--
	PROCEDURE FormatBack(F: Frame; pos: LONGINT; H: INTEGER; VAR org: LONGINT; VAR L: Line; VAR h: INTEGER);
	VAR
		org0, org1: LONGINT;
		L0, L1: Line;
	BEGIN
		org := pos; h := 0;
		REPEAT
			ParaBeg(F.text, org-1, org0); InitFormatter(F, org0); FormatLine(L0); L1 := L0; org1 := org0; INC(h, L1.h);
			WHILE org1 + L1.len < org DO
				INC(org1, L1.len); FormatLine(L1.next); L1 := L1.next; INC(h, L1.h)
			END;
			L1.next := L; L := L0; org := org0
		UNTIL (h >= H) OR (org = 0);
		WHILE h > H DO DEC(h, L.h); INC(org, L.len); L := L.next END	(*remove overhead*)
	END FormatBack;

	PROCEDURE ScrollBackTo(F: Frame; x, y: INTEGER; pos: LONGINT);
	VAR
		L, L0, L1: Line;
		org, org0: LONGINT;
		h0, Y: INTEGER;
	BEGIN
		org := F.org; Y := F.H - F.top; L := F.trailer.next;
		WHILE org # pos DO INC(org, L.len); DEC(Y, L.h); L := L.next END;
		IF (*(L.next # F.trailer) &*) (F.org > 0) THEN	(*last line in frame*)
			L1 := F.trailer.next;	(*keep old first line*)
			FormatBack(F, F.org, Y - F.bot - L.h, org0, F.trailer.next, h0);
			RemoveMarks(F); RemTick(F, x, y);
			F.org := org0; Y := F.H - F.top - h0; org := org0;
			L := F.trailer.next; WHILE L.next # L1 DO INC(org, L.len); L := L.next END;	(*find last line of new section*)
			INC(org, L.len);
			ScrollBack(F, x, y, L1, L, Y, org); (*Erase(F, x, y, F.bot, Y - F.bot);*)
			BottomLine(F, x, y, Y, L, org); L.next := F.trailer;
			ShowTick(F, x, y);
			ShowBrk(F, Display.FG, x, y)
		END
	END ScrollBackTo;

	PROCEDURE ScrollToEnd(F: Frame; x, y: INTEGER);
	VAR L: Line; org: LONGINT; h: INTEGER;
	BEGIN L := F.trailer;
		FormatBack(F, F.text.len, F.H-F.top-F.bot, org, L, h);
		RemoveMarks(F); ShowText(F, x, y, org)
	END ScrollToEnd;
--no scroll--*)
(*--end scroll--*)

	PROCEDURE Edit* (F: Frame; x, y, X, Y: INTEGER; Keys: SET);
		VAR
			M: Oberon.ConsumeMsg;
			R: Texts.Reader;
			text: Texts.Text;
			time, pos, beg, end: LONGINT;
			keysum: SET;
			ch: CHAR;
	BEGIN	(*M.X & M.Y not inside any object*)
		DrawCursor(X, Y);
		IF F.trailer.next = F.trailer THEN RETURN END;	(* as nothing to edit exists *)
		IF X < x + F.X + Min(F.left, barW) THEN	(*bar*)
(*--back scroll--
			IF MR IN Keys THEN keysum := Keys; TrackLine(F, x, y, X, Y, pos, keysum); ScrollBackTo(F, x, y, pos)
			ELSIF MM IN Keys THEN keysum := Keys;
--no scroll--*)
			IF (MR IN Keys) OR (MM IN Keys) THEN keysum := Keys;
(*--end scroll--*)
				REPEAT TrackMouse(X, Y, Keys, keysum) UNTIL Keys = {};
				IF ~(ML IN keysum) THEN
					IF (MR IN keysum) OR (y+F.Y + F.H < Y) THEN
						IF MM IN keysum THEN
							pos := 0
						ELSE
							pos := F.org - LONG(F.H * 25) DIV Fonts.Default.height;
							IF pos < 0 THEN pos := 0 END
            			END
					ELSE pos := (y+F.Y + F.H - Y) * (F.text.len) DIV F.H
					END;
					Show(F, pos)
(*--back scroll--
				ELSIF ~(MR IN keysum) THEN ScrollToEnd(F, x, y)
--no scroll--*)
				ELSIF ~(MR IN keysum) THEN pos := F.text.len; Show(F, pos)
(*--end scroll--*)
				END
			ELSIF ML IN Keys THEN TrackLine(F, x, y, X, Y, pos, keysum);
				IF (pos >= 0) & ~(MR IN keysum) & (pos # F.org) THEN Show(F, pos) END
			END
		ELSE	(*text*)
			IF MR IN Keys THEN TrackSelection(F, x, y, X, Y, keysum);
				IF F.sel THEN
					IF keysum = {MR, ML} THEN	(*delete text*)
						Oberon.Defocus; Oberon.GetSelection(text, beg, end, time);	(*!*)
						Texts.Delete(text, beg, end); SetCaret(F, beg)
					ELSIF keysum = {MR, MM} THEN	(*copy to focus*)
						Oberon.GetSelection(M.text, M.beg, M.end, time); M.F := NIL; Display.Broadcast(M)
					END
				END
			ELSIF MM IN Keys THEN TrackWord(F, x, y, X, Y, pos, keysum);
				IF MR IN keysum THEN
					IF (pos >= 0) & ~(ML IN keysum) THEN CallCmd(OpenCmd, F, pos, FALSE) END
				ELSE
					IF pos >= 0 THEN Call(F, pos, ML IN keysum) END
				END
			ELSIF ML IN Keys THEN Oberon.Defocus; TrackCaret(F, x, y, X, Y, keysum);
				IF F.car THEN
					IF keysum = {ML, MM} THEN	(*copy from selection*)
						Oberon.GetSelection(text, beg, end, time);
						IF time >= 0 THEN CopyOver(F, text, beg, end) END
					ELSIF keysum = {ML, MR} THEN	(*copy font*)
						Oberon.GetSelection(text, beg, end, time);
						IF (time >= 0) & (F.carLoc.pos < F.text.len) THEN
							Texts.OpenReader(R, F.text, F.carLoc.pos); Texts.Read(R, ch);
							IF (R.lib # NIL) & (R.lib IS Fonts.Font) THEN
								Texts.ChangeLooks(text, beg, end, {0, 1, 2}, R.lib, R.col, R.voff)
							END
						END
					END
				END
			END
		END
	END Edit;

	PROCEDURE Control(F: Frame; VAR M: Display.ControlMsg);
	VAR R: Texts.Finder; obj: Objects.Object; pos: LONGINT;
	BEGIN
		IF M.id = Display.remove THEN
			Texts.OpenFinder(R, F.text, 0); pos := R.pos; Texts.FindObj(R, obj);
			WHILE ~R.eot DO
				IF obj = M.F THEN Texts.Delete(F.text, pos, pos+1); M.res := 0; RETURN END;
				pos := R.pos; Texts.FindObj(R, obj)
			END;
			Broadcast(F, M)
		ELSE Broadcast(F, M)
		END
	END Control;

	PROCEDURE ModifyDsc(F: Frame; x, y: INTEGER; VAR M: Display.ModifyMsg);
	VAR R: Texts.Finder; obj: Objects.Object; G, msk: Display.Frame;
		loc: Location;
		pos, org, lim, lim0: LONGINT;
		dw, mode: INTEGER;
	BEGIN
		org := F.org; lim := Lim(F); lim0 := 0; mode := M.mode; msk := Mask(F); loc.pos := 0;
		Texts.OpenFinder(R, F.text, 0); pos := R.pos; Texts.FindObj(R, obj);
		WHILE ~R.eot & (pos < F.text.len) & (M.res < 0) DO
			IF obj IS Display.Frame THEN G := obj(Display.Frame);
				IF M.F = G THEN	(*direct dsc*)
					IF (M.dW = 0) & (M.dH = 0) & (M.dX # 0) & (M.dY # 0) THEN M.res := 0	(*move: ignore*)
					ELSIF M.id = Display.extend THEN dw := M.W-Styles.scnW;
						IF dw > 0 THEN DEC(M.W, dw); DEC(M.dW, dw) END
					END
				END;
				IF M.res < 0 THEN
					IF pos < org THEN M.mode := Display.state; M.dlink := msk; G.handle(G, M);	(*before*)
						IF R.pos >= org THEN RemoveMarks(F); UpdateSection(F, x, y, pos, pos+1, 0); org := F.org; lim := Lim(F) END
					ELSE
						IF loc.pos >= 0 THEN FindFrame(F, G, loc) END;
						IF (*pos < lim*) loc.pos >= 0 THEN M.x := x+F.X+loc.x-G.X; M.y := y+F.Y+loc.y-G.Y;	(*visible*)
							IF M.F = G THEN M.mode := Display.state; M.dlink := msk; G.handle(G, M);
								RemoveMarks(F); UpdateSection(F, x, y, pos, pos+1, 0); lim := Lim(F)
							ELSE M.mode := mode; M.dlink := msk; G.handle(G, M)
							END
						ELSE M.mode := Display.state; M.dlink := msk; G.handle(G, M);
							IF lim0 < lim THEN lim0 := lim; RemoveMarks(F); UpdateSection(F, x, y, lim, lim+1, 0); lim := Lim(F) END
						END
					END
				END;
			END;
			pos := R.pos; Texts.FindObj(R, obj)
		END;
		M.mode := mode
	END ModifyDsc;

	PROCEDURE Modify(F: Frame; VAR M: Display.ModifyMsg);
	VAR x, y: INTEGER;
	BEGIN x := M.x; y := M.y;
		IF M.F = F THEN
			RemTick(F, x, y); RemoveMarks(F);
			IF M.id = Display.extend THEN
				IF M.dY > 0 THEN
					Bar(F, x, y, F.H, M.dY); Move(F, x, y, 0, F.H, M.dY); INC(F.Y, M.dY)
				END;
				Resize(F, x, y, M.Y)	(* Extend *)
			ELSIF M.id = Display.reduce THEN
				Resize(F, x, y, M.Y + M.dY);	(* Reduce *)
				IF M.dY > 0 THEN
					RemTick(F, x, y); Move(F, x, y, 0, F.H, -M.dY); DEC(F.Y, M.dY);
					IF F.H > 0 THEN ShowTick(F, x, y) END
				END
			END;
			M.res := 0
		ELSE ModifyDsc(F, x, y, M)
		END
	END Modify;

	PROCEDURE Restore(F: Frame; x, y: INTEGER; VAR M: Display.DisplayMsg);
		VAR Y: INTEGER;
	BEGIN
		IF M IS DisplayMsg THEN RemoveMarks(F); ShowText(F, x, y, M(DisplayMsg).pos)
		ELSE Y := F.Y; INC(F.Y, F.H); F.H := 0; F.trailer.next := F.trailer; Resize(F, x, y, Y)
		END
	END Restore;

	PROCEDURE Handle* (F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR F1: Frame; bcast: BOOLEAN;
			x, y: INTEGER; dlink: Objects.Object;
	BEGIN
		WITH F: Frame DO
			IF M IS Display.ModifyMsg THEN
				WITH M: Display.ModifyMsg DO Modify(F, M) END
			ELSIF M IS Display.ControlMsg THEN
				WITH M: Display.ControlMsg DO Control(F, M) END
			ELSIF M IS Display.FrameMsg THEN
				WITH M: Display.FrameMsg DO
					IF (M.F = F) OR (M.F = NIL) THEN
						x := M.x; y := M.y; dlink := M.dlink;	(* idiot *)
						bcast := (M.F = NIL);	(* bcast = "msg has to be broadcasted to every descender" *)
						IF M IS Oberon.InputMsg THEN
							WITH M: Oberon.InputMsg DO
								IF M.id = Oberon.track THEN
									IF (M.keys = {}) OR ~TouchFrame(F, M) THEN Edit(F, x, y, M.X, M.Y, M.keys); M.res := 0 END
								ELSIF M.id = Oberon.consume THEN
									IF F.car THEN Write(F, M.ch, M.fnt, M.col, M.voff); M.res := 0 (*ELSE bcast := TRUE*) END
								END
							END
						ELSIF M IS Oberon.ControlMsg THEN
							WITH M: Oberon.ControlMsg DO
								IF M.id = Oberon.defocus THEN RemoveCaret(F)
								ELSIF M.id = Oberon.neutralize THEN RemoveMarks(F)
								END;
								(*bcast := TRUE*)
							END
(*
						ELSIF M IS Display.ModifyMsg THEN
							WITH M: Display.ModifyMsg DO Modify(F, M) END
						ELSIF M IS Display.ControlMsg THEN
							WITH M: Display.ControlMsg DO Control(F, M) END
*)
						ELSIF M IS Display.DisplayMsg THEN
							WITH M: Display.DisplayMsg DO
								IF M.device = Display.screen THEN Restore(F, x, y, M) END
							END
						ELSIF M IS Display.ConsumeMsg THEN
							WITH M: Display.ConsumeMsg DO
								IF F.car & (M.id = Display.integrate) THEN
									Integrate(F, F.carLoc.pos, M.obj, TRUE); M.res := 0
								ELSIF (M.F = F) & (M.id = Display.drop) THEN
									Integrate(F, Pos(F, M.u, M.v), M.obj, FALSE); M.res := 0
								ELSE Broadcast(F, M)
								END
							END
						ELSIF M IS Display.LocateMsg THEN
							WITH M: Display.LocateMsg DO Broadcast(F, M);
								IF M.loc = NIL THEN M.u := M.X - F.X - x; M.v := M.Y - F.Y - y;
									IF (M.u >= 0) & (M.u <= F.W) & (M.v >= 0) & (M.v <= F.H) THEN M.loc := F; M.res := 0 END
								END
							END
						ELSIF M IS Texts.UpdateMsg THEN
							WITH M: Texts.UpdateMsg DO
								IF F.text = M.text THEN Update(F, M) (* cont *) (*ELSE bcast := TRUE*) END
							END
						ELSIF M IS Oberon.SelectMsg THEN
							WITH M: Oberon.SelectMsg DO
								IF M.id = Oberon.get THEN GetSelection(F, M)	(*; bcast := TRUE*)
								ELSIF (M.sel = F) & (M.text = F.text) THEN
									IF M.id = Oberon.set THEN SetSelection(F, M.beg, M.end)
									ELSIF M.id = Oberon.reset THEN RemoveSelection(F)
									END
								END
							END
						ELSIF M IS Oberon.CaretMsg THEN
							WITH M: Oberon.CaretMsg DO
								IF M.id = Oberon.get THEN GetCaret(F, M)	(*; bcast := TRUE*)
								ELSIF (M.car = F) & (M.text = F.text) THEN
									IF M.id = Oberon.set THEN SetCaret(F, M.pos);
										(*IF M.pos # F.carLoc.pos THEN Show(F, M.pos); SetCaret(F, M.pos) END*)
									ELSIF M.id = Oberon.reset THEN RemoveCaret(F)
									END
								END
							END
						ELSIF M IS Oberon.ConsumeMsg THEN
							WITH M: Oberon.ConsumeMsg DO
								IF F.car THEN CopyOver(F, M.text, M.beg, M.end); M.res := 0 (*ELSE bcast := TRUE*) END
							END
						ELSIF M IS Oberon.RecallMsg THEN  IF F.car THEN Recall(F) (*ELSE bcast := TRUE*) END
(*
						ELSIF M IS FocusMsg THEN  IF F.car THEN M(FocusMsg).foc := F; M.res := 0 END
*)
						ELSIF M IS MarkMsg THEN
							WITH M: MarkMsg DO
								IF M.F = F THEN
									IF M.id = car THEN FlipCaret(F, x, y)
									ELSIF M.id = sel THEN FlipSelection(F, x, y, F.selBeg, F.selEnd)
									ELSIF (M.id = arrow) & (F.H >= 16) THEN
										Display.CopyPattern(FullColor, Display.downArrow, x+F.X, y+F.Y, Display.invert)
									END
								END
							END
						ELSIF M IS Styles.UpdateMsg THEN
							WITH M: Styles.UpdateMsg DO UpdateStyle(F, M); bcast := TRUE (* *) END
						ELSE bcast := TRUE
						END;
						IF bcast THEN Broadcast(F, M) END;
						M.x := x; M.y := y; M.dlink := dlink	(*reset idiot*)
					ELSE Broadcast(F, M)
					END
				END
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO Copy(F, F1); M.obj := F1 END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN M.s := "ScriptFrames.New" END
				END
			ELSIF M IS Objects.LinkMsg THEN
				WITH M: Objects.LinkMsg DO
					IF M.id = Objects.get THEN M.obj := F.text; M.res := 0
					(*ELSIF (M.id = Objects.set) & (M.obj IS Texts.Text) THEN F.text := M.obj(Texts.Text) END*)
					END
				END
(*
			ELSIF M IS Objects.BindMsg THEN
				WITH M: Objects.BindMsg DO
					IF (F.lib = NIL) OR (F.lib.name = "") & (F.lib # M.lib) THEN
						M.lib.GenRef(M.lib, ref); M.lib.PutObj(M.lib, ref, F)
					END
				END
			ELSIF M IS Objects.LoadMsg THEN
				WITH M: Objects.LoadMsg DO Files.Read(M.R, ch);
					IF ch = Texts.TextBlockId THEN
						Texts.Load(F.text, Files.Base(M.R), Files.Pos(M.R), len);
						Files.Set(R, Files.Base(M.R), Files.Pos(M.R)+len)
					END
				END
			ELSIF M IS Objects.StoreMsg THEN
				WITH M: Objects.StoreMsg DO
					Texts.Store(obj, Files.Base(M.R), Files.Pos(M.R), len);
					Files.Set(M.R, Files.Base(M.R), Files.Pos(M.R) + len)
				END
*)
			END;
		END
	END Handle;

	(* --- creation --- *)

	PROCEDURE NewText* (text: Texts.Text; pos: LONGINT): Frame;
		VAR F: Frame;
	BEGIN NEW(F);
		Open(F, Handle, text, pos, BackCol, left, right, top, bot); RETURN F
	END NewText;


	PROCEDURE LineExtend(L: Line; VAR w, asr, dsr: INTEGER; VAR brk: BOOLEAN);
	BEGIN w := SHORT(L.W DIV Printer.Unit);
		IF (L.len = 1) & (pL.style # L.style) THEN asr := SHORT(L.style.gap DIV Printer.Unit); dsr := 0;
			brk := TRUE	(*for printing: styles always break the line*)
		ELSE brk := L.brk;
			asr := SHORT(LONG(L.asr)*Display.Unit DIV Printer.Unit); dsr := SHORT(LONG(L.dsr)*Display.Unit DIV Printer.Unit)
		END
	END LineExtend;

	PROCEDURE FirstLine*(T: Texts.Text; VAR w, asr, dsr, nSpc: INTEGER; VAR len: LONGINT; VAR brk, eot: BOOLEAN);
	VAR F: Frame; L: Line;
	BEGIN NEW(F); F.text := T; NEW(pL); pL.style := Styles.defStyle; InitFormatter(F, 0); FormatLine(L);
		len := L.len; eot := L.eot; nSpc := L.nSpc; LineExtend(L, w, asr, dsr, brk); pL := L
	END FirstLine;

	PROCEDURE NextLine*(VAR w, asr, dsr, nSpc: INTEGER; VAR len: LONGINT; VAR brk, eot: BOOLEAN);
	VAR L: Line;
	BEGIN FormatLine(L); len := L.len; eot := L.eot; nSpc := L.nSpc; LineExtend(L, w, asr, dsr, brk); pL := L
	END NextLine;

	PROCEDURE New*;
		VAR text: Texts.Text;
	BEGIN NEW(text); Texts.Open(text, "");
		Objects.NewObj := NewText(text, 0)
(*
	VAR F: Display.Frame;
		L: Line; b: Box;
		c: INTEGER;
	BEGIN
		F := Oberon.MarkedViewer(); F := F.dsc.next;
		IF F  IS Frame THEN
			L := F(Frame).trailer.next;
			WHILE L # F(Frame).trailer DO
				IF (L.box = NIL) OR (L.box.next = L.box) THEN Texts.Write(W, "0"); Texts.Write(W, 0DX)
				ELSE b := L.box.next; c := 0;
					WHILE b # L.box DO INC(c); b := b.next END;
					Texts.WriteInt(W, c, 0); Texts.Write(W, 0DX)
				END;
				L := L.next
			END;
			Texts.Append(Oberon.Log, W.buf)
		END
*)
	END New;

BEGIN
	IF Display.Depth(0) # 1 THEN
		BackCol := 14;  BarCol := 13;  FullColor := Display.FG - BackCol
	ELSE
		BackCol := Display.BG;  BarCol := Display.FG;  FullColor := Display.FG
	END;
	show := Show;
	barW := Fonts.Default.height + 2;
	top := Fonts.Default.height DIV 2; bot := top; left := barW + top; right := top;
	markW := top; eolW := top;
	Asr := Fonts.Default.maxY; Dsr := -Fonts.Default.minY;
	Texts.OpenWriter(W); Texts.OpenWriter(KW); Texts.OpenWriter(XW)
END ScriptFrames.
