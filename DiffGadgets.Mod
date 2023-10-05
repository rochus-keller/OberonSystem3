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

MODULE DiffGadgets;	(** portable *) (** PS   *)

	IMPORT Input, Files, Objects, Fonts, Texts, Display, Display3, Effects, Gadgets, Oberon, 
		TextGadgets0, TextGadgets, Documents, Desktops;

	CONST
		BarW = 14;
		TitleH  = 14;

		CR = 0DX;

	TYPE
		Line = POINTER TO LineDesc;
		LineDesc = RECORD
			prev, next: Line;
			p1, p2, nr: LONGINT
		END;
		
		Slider = POINTER TO SliderDesc;
		SliderDesc = RECORD (Gadgets.FrameDesc)
			lines, curL: INTEGER
		END;

		Frame* = POINTER TO FrameDesc;
		FrameDesc = RECORD (Gadgets.FrameDesc)
			T1, T2: TextGadgets.Frame;
			slider: Slider;
			lines, org: Line;
			name1,name2: ARRAY 64 OF CHAR;
		END;

	VAR
		W: Texts.Writer;


PROCEDURE S*;
BEGIN IF Input.Available() > 0 THEN HALT(99) END
END S;

(* *************** SLIDER STUFF *************** *)

PROCEDURE AttributesSlider (F: Slider; VAR M: Objects.AttrMsg);
BEGIN
	IF (M.id = Objects.get) & (M.name = "Gen") THEN
			M.class := Objects.String; COPY("DiffGadgets.NewSlider", M.s); M.res := 0
	ELSE Gadgets.framehandle(F, M)
	END
END AttributesSlider;

PROCEDURE RestoreSlider (F: Slider; M: Display3.Mask; x, y, w, h: INTEGER);
	VAR pos: INTEGER;
BEGIN
	Display3.FilledRect3D(M, Display3.topC, Display3.bottomC, Display3.textbackC, x-1, y, w+1, h, 1, Display.replace);
	pos := y + h - 1 - SHORT(F.curL * LONG(h - 2) DIV F.lines);
	IF pos <= y + 4 THEN pos:= y + 5 END;
	Display3.FilledRect3D(M, Display3.topC, Display3.bottomC, Display3.groupC, x+2, pos - 4, 8, 3, 1, Display.replace);
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
	END
END RestoreSlider;

PROCEDURE CopySlider (VAR M: Objects.CopyMsg; from, to: Slider);
BEGIN to.lines := from.lines; to.curL:= from.curL; Gadgets.CopyFrame(M, from, to)
END CopySlider;

PROCEDURE TrackLine(F: Frame; R: Display3.Mask; VAR keysum: SET; x, y: INTEGER; VAR L: Line);
	VAR f1, f2: TextGadgets0.Frame; keys: SET; fx1, fx2, X, Y, W1, W2, t1, t2: INTEGER; loc: TextGadgets0.Loc; 
		oL1, oL2, nL: TextGadgets0.Line;
BEGIN
	f1:= F.T1; fx1:= x + f1.X; t1:= y + f1.Y + f1.H - 1;
	f2:= F.T2; fx2:= x + f2.X; t2:= y + f2.Y + f2.H - 1; 
	Input.Mouse(keys, X, Y); keysum := keys;
	f1.do.LocateChar(f1, fx1, y + f1.Y, X, Y, loc); oL1:= loc.line;
	L:= F.org; WHILE L.p1 < loc.org DO S; L:= L.next END;
	f2.do.LocatePos(f2, L.p2, loc); oL2:= loc.line;
	W1 := oL1.right - f1.left; W2:= oL2.right - f2.left; 
	Oberon.FadeCursor(Oberon.Mouse);
	Display3.ReplConst(R, 2, fx1 + f1.left, t1 + oL1.base - 3, W1, 2, Display.invert);
	Display3.ReplConst(R, 2, fx2 + f2.left, t2 + oL2.base - 3, W2, 2, Display.invert);
	WHILE keys # {} DO
		Input.Mouse(keys, X, Y); keysum := keysum + keys;
		f1.do.LocateChar(f1, fx1, y + f1.Y, X, Y, loc); nL:= loc.line;
		IF nL # oL1 THEN
			Oberon.FadeCursor(Oberon.Mouse);
			Display3.ReplConst(R, 2, fx1 + f1.left, t1 + oL1.base - 3, W1, 2, Display.invert);
			Display3.ReplConst(R, 2, fx2 + f2.left, t2 + oL2.base - 3, W2, 2, Display.invert);
			L:= F.org; WHILE L.p1 < loc.org DO S; L:= L.next END;
			f2.do.LocatePos(f2, L.p2, loc); oL2:= loc.line;
			oL1 := nL; W1 := oL1.right - f1.left; W2:= oL2.right - f2.left;
			Display3.ReplConst(R, 2, fx1 + f1.left, t1 + oL1.base - 3, W1, 2, Display.invert);
			Display3.ReplConst(R, 2, fx2 + f2.left, t2 + oL2.base - 3, W2, 2, Display.invert)
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, X, Y)
	END;
	Oberon.FadeCursor(Oberon.Mouse);
	Display3.ReplConst(R, 2, fx1 + f1.left, t1 + oL1.base - 3, W1, 2, Display.invert);
	Display3.ReplConst(R, 2, fx2 + f2.left, t2 + oL2.base - 3, W2, 2, Display.invert)
END TrackLine;

PROCEDURE ScrollTo(F: Frame; L: Line);
BEGIN
	TextGadgets0.ScrollTo(F.T1, L.p1); TextGadgets0.ScrollTo(F.T2, L.p2);
	F.org:= L; F.slider.curL:= SHORT(L.nr)
END ScrollTo;

PROCEDURE ScrollUp(F: Frame; L: Line);
	VAR tF: TextGadgets0.Frame; l: TextGadgets0.Line; L1: Line; hUsed: INTEGER;
BEGIN
	L1:= L; tF:= F.T1;
	NEW(l); tF.do.Format(tF, L1.p1, l); hUsed:= l.h + tF.top + tF.bottom;
	LOOP
		IF (hUsed + l.h >= tF.H) OR (L1 = F.lines) THEN EXIT END;
		L1:= L1.prev;
		NEW(l); tF.do.Format(tF, L1.p1, l); INC(hUsed, l.h)
	END;

	tF:= F.T2;
	NEW(l); tF.do.Format(tF, L.p2, l); hUsed:= l.h + tF.top + tF.bottom;
	LOOP
		IF (hUsed >= tF.H) OR (L = F.lines) THEN EXIT END;
		L:= L.prev;
		NEW(l); tF.do.Format(tF, L.p2, l); INC(hUsed, l.h)
	END;

	IF L1.nr > L.nr THEN L:= L1 END;
	TextGadgets0.ScrollTo(F.T1, L.p1); TextGadgets0.ScrollTo(F.T2, L.p2);
	F.org:= L; F.slider.curL:= SHORT(L.nr)
END ScrollUp;


PROCEDURE Edit(F: Frame; R: Display3.Mask; VAR M: Oberon.InputMsg; x, y, w, h: INTEGER);
VAR sF: Slider; L: Line; keysum, keys: SET; line, X, Y: INTEGER;
BEGIN sF:= F.slider;
	IF M.keys # {} THEN
		IF M.keys = {2} THEN	(* scroll up *)
			TrackLine(F, R, keysum, M.x, M.y, L); M.res := 0;
			IF keysum # {0, 1, 2} THEN ScrollTo(F, L) END
		ELSIF M.keys = {0} THEN
			TrackLine(F, R, keysum, M.x, M.y, L); M.res := 0;
			IF keysum # {0, 1, 2} THEN ScrollUp(F, L) END
		ELSIF M.keys = {1} THEN
			Input.Mouse(keys, X, Y); keysum := keys;
			WHILE keys # {} DO S;
				Input.Mouse(keys, X, Y); keysum := keysum+keys; Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, X, Y);
			END;
			M.res := 0; 
			IF keysum = {1, 0} THEN	(* to begin *)
				ScrollTo(F,F.lines)
			ELSIF keysum = {1, 2} THEN	(* to end *)
				ScrollUp(F, F.lines.prev)
			ELSIF keysum # {0, 1, 2} THEN	(* relative positioning *)
				line := SHORT(sF.lines * LONG(y + h - Y) DIV h);
				IF line <= 0 THEN L:= F.lines; sF.curL:= 0
				ELSE 
					IF line > sF.lines THEN line:= sF.lines END;
					L:= F.lines; WHILE line > 0 DO L:= L.next; DEC(line) END
				END;
				ScrollTo(F, L)
			END
		END;
		Gadgets.Update(sF)
	ELSE Gadgets.framehandle(sF, M)
	END
END Edit;

PROCEDURE HandleSlider(F: Objects.Object; VAR M: Objects.ObjMsg);
	VAR x, y, w, h: INTEGER; F1: Slider; Q: Display3.Mask; main: Frame;
BEGIN
	WITH F: Slider DO
		IF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF (M.F = NIL) OR (M.F = F) THEN
					x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
					IF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg DO
							IF M.device = Display.screen THEN
								IF (M.id = Display.full) OR (M.F = NIL) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, Q);
									RestoreSlider(F, Q, x, y, w, h)
								ELSIF M.id = Display.area THEN
									Gadgets.MakeMask(F, x, y, M.dlink, Q);
									Display3.AdjustMask(Q, x + M.u, y + h - 1 + M.v, M.w, M.h);
									RestoreSlider(F, Q, x, y, w, h)
								END
							ELSIF M.device = Display.printer THEN
								Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) & Gadgets.InActiveArea(F, M) & (M.dlink IS Frame) THEN
								main:= M.dlink(Frame);
								Gadgets.MakeMask(main, M.x, M.y-main.H+1, M.dlink.dlink, Q);
								Edit(main, Q, M, x, y, w, h)
							ELSE Gadgets.framehandle(F, M)
							END
						END
					ELSE Gadgets.framehandle(F, M)
					END
				END
			END
		ELSIF M IS Objects.AttrMsg THEN AttributesSlider(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Files.WriteInt(M.R, F.lines); Files.WriteInt(M.R, F.curL); Gadgets.framehandle(F, M)
				ELSIF M.id = Objects.load THEN
					Files.ReadInt(M.R, F.lines); Files.ReadInt(M.R, F.curL); Gadgets.framehandle(F, M)
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink (*non-first arrival*)
				ELSE (*first arrival*)
					NEW(F1); F.stamp := M.stamp; F.dlink := F1;
					CopySlider(M, F, F1); M.obj := F1
				END
			END
		ELSE Gadgets.framehandle(F, M)
		END
	END
END HandleSlider;

PROCEDURE InitSlider(F: Slider; lines: INTEGER);
BEGIN
	F.handle := HandleSlider; F.W:= 20; F.H:= 100;
	F.lines:= lines; F.curL:= 0
END InitSlider;
	
PROCEDURE NewSlider*;
	VAR F: Slider;
BEGIN
	NEW(F); InitSlider(F, 0);
	Objects.NewObj:= F
END NewSlider;


(* *************** FRAME STUFF *************** *)

PROCEDURE SetMask (F: Display.Frame; Q: Display3.Mask);
	VAR M: Display3.OverlapMsg;
BEGIN M.M := Q; M.x := 0; M.y := 0; M.F := F; M.dlink := NIL; M.res := -1;
	F.handle(F, M)
END SetMask;

PROCEDURE SetContentMask (F: Frame; subF: Display.Frame);
	VAR Q: Display3.Mask;
BEGIN
	IF F.mask = NIL THEN SetMask(subF, NIL); SetMask(F.T2, NIL); SetMask(F.slider, NIL)
	ELSE Display3.Copy(F.mask, Q); Q.x := 0; Q.y := 0;
		Display3.Intersect(Q, subF.X, subF.Y, subF.W, subF.H);
		Q.x := -subF.X; Q.y := -(subF.Y + subF.H - 1); Display3.Shift(Q);
		SetMask(subF, Q)
	END
END SetContentMask;

PROCEDURE ToContent (F: Frame; to: Display.Frame; x, y: INTEGER; VAR M: Display.FrameMsg);
	VAR Mdlink, Fdlink: Objects.Object; tx, ty: INTEGER;
BEGIN
	tx := M.x; ty := M.y;
	M.x := x; M.y := y + F.H - 1;
	Fdlink := F.dlink; Mdlink := M.dlink; 
	F.dlink := M.dlink; M.dlink := F; to.handle(to, M);
	F.dlink := Fdlink; M.dlink := Mdlink;
	M.x := tx; M.y := ty
END ToContent;

PROCEDURE ToKids(F: Frame; VAR M: Display.FrameMsg);
BEGIN
	ToContent(F, F.T1, M.x + F.X, M.y + F.Y, M);
	ToContent(F, F.T2, M.x + F.X, M.y + F.Y, M);
	ToContent(F, F.slider, M.x + F.X, M.y + F.Y, M)
END ToKids;

PROCEDURE Modify (F: Frame; VAR M: Display.ModifyMsg);
	VAR midX: INTEGER; N: Display.ModifyMsg;
	
	PROCEDURE ModifySub(subF: Display.Frame; x, w: INTEGER);
	BEGIN
		N.X := x; N.Y := -M.H + 1; N.W := w; N.H := M.H-TitleH;
		N.dX := N.X - subF.X; N.dY := N.Y - subF.Y; N.dW := N.W - subF.W; N.dH := N.H - subF.H;
		N.x := 0; N.y := 0; N.res := -1; N.F := subF;
		subF.handle(subF, N)
	END ModifySub;

BEGIN
	midX:= (M.W - BarW) DIV 2;
	N.id := Display.extend; N.mode := Display.state; Objects.Stamp(N);
	ModifySub(F.slider, 0, BarW);
	ModifySub(F.T1, BarW, midX); 
	IF BarW+2*midX < F.W THEN ModifySub(F.T2, BarW+midX, midX+1)
	ELSE ModifySub(F.T2, BarW+midX, midX)
	END;
	
	Gadgets.framehandle(F, M)
END Modify;

PROCEDURE Restore (F: Frame; Q: Display3.Mask; x, y, w, h: INTEGER; VAR M: Display.DisplayMsg);
	VAR N: Display.DisplayMsg; mX, tY: INTEGER;

	PROCEDURE ClipAgainst (VAR x, y, w, h: INTEGER; x1, y1, w1, h1: INTEGER);
		VAR r, t, r1, t1: INTEGER;
	BEGIN
		r := x + w - 1; r1 := x1 + w1 - 1; t := y + h - 1; t1 := y1 + h1 - 1;
		IF x < x1 THEN x := x1 END; IF y < y1 THEN y := y1 END;
		IF r > r1 THEN r := r1 END; IF t > t1 THEN t := t1 END;
		w := r - x + 1; h := t - y + 1;
	END ClipAgainst;
	
	PROCEDURE ToFrame(subF: Display.Frame);
	BEGIN
		IF M.id = Display.area THEN
			N.u := M.u; N.v := M.v; N.w := M.w; N.h := M.h;
			ClipAgainst(N.u, N.v, N.w, N.h, subF.X, subF.Y, subF.W, subF.H)
		END;
		DEC(N.u, subF.X); N.device := M.device; N.id := M.id; N.F := subF; N.dlink := M.dlink; N.res := -1;
		ToContent(F, subF, x, y, N)
	END ToFrame;
	
BEGIN
	tY:= y+h-TitleH; mX:= x+F.T1.X;
	Display3.ReplConst(Q, Display3.textbackC, mX, tY, w, TitleH, Display.replace);
	Display3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.textbackC, x, tY, F.slider.W, TitleH, 1, Display.replace);
	Display3.ReplConst(Q, Display3.bottomC, mX, tY, 1, TitleH, Display.replace);
	Display3.String(Q, Display3.black, mX+4, tY+3, Fonts.Default, F.name1, Display3.paint);
	mX:= x+F.T2.X;
	Display3.ReplConst(Q, Display3.topC, mX-1, tY, 1, TitleH, Display.replace);
	Display3.ReplConst(Q, Display3.bottomC, mX, tY, 1, TitleH, Display.replace);
	Display3.String(Q, Display3.black, mX+4, tY+3, Fonts.Default, F.name2, Display3.paint);

	Objects.Stamp(N); ToFrame(F.T1); ToFrame(F.T2); ToFrame(F.slider);

	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(Q, Display3.white, Display3.selectpat, x, y, x, y, w, h,
		Display.paint)
	END
END Restore;

PROCEDURE Copy* (VAR M: Objects.CopyMsg; from, to: Frame);
	VAR N: Objects.CopyMsg;
BEGIN
	Gadgets.CopyFrame(M, from, to);
	N.id := Objects.shallow; Objects.Stamp(N);
	from.T1.handle(from.T1, N); to.T1 := N.obj(TextGadgets.Frame);
	from.T2.handle(from.T2, N); to.T2 := N.obj(TextGadgets.Frame);
	from.slider.handle(from.slider, N); to.slider := N.obj(Slider);
	to.lines:= from.lines;
	to.org:= from.org;
	COPY(from.name1, to.name1); COPY(from.name2, to.name2)
END Copy;

PROCEDURE Attributes (F: Frame; VAR M: Objects.AttrMsg);
BEGIN
	IF (M.id = Objects.get) & (M.name = "Gen") THEN
		M.s := "DiffGadgets.New"; M.class := Objects.String; M.res := 0
	ELSE Gadgets.framehandle(F, M)
	END
END Attributes;

PROCEDURE InChild(F: Display.Frame; x, y, MX, MY: INTEGER): BOOLEAN;
BEGIN
	RETURN Effects.Inside(MX, MY, x+F.X, y+F.Y, F.W, F.H) & ~Effects.InBorder(MX, MY, x+F.X, y+F.Y, F.W, F.H)
END InChild;

PROCEDURE Handle* (F: Objects.Object; VAR M: Objects.ObjMsg);
	VAR x, y, w, h: INTEGER; F1: Frame; Q: Display3.Mask;
BEGIN
	WITH F: Frame DO
		IF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF (M.F = NIL) OR (M.F = F) THEN
					x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
					IF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg	DO
							IF M.device = Display.screen THEN
								IF (M.id = Display.full) OR (M.F = NIL) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, Q);
									Restore(F, Q, x, y, w, h, M)
								ELSIF M.id = Display.area THEN
									Gadgets.MakeMask(F, x, y, M.dlink, Q);
									Display3.AdjustMask(Q, x + M.u, y + h - 1 + M.v, M.w, M.h);
									Restore(F, Q, x, y, w, h, M)
								END
							ELSIF M.device = Display.printer THEN
								Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) & ~(Gadgets.selected IN F.state) THEN
								IF InChild(F.slider, x, y+F.H, M.X, M.Y) THEN ToContent(F, F.slider, x, y, M)
								ELSIF InChild(F.T1, x, y+F.H, M.X, M.Y) THEN ToContent(F, F.T1, x, y, M)
								ELSIF InChild(F.T2, x, y+F.H, M.X, M.Y) THEN ToContent(F, F.T2, x, y, M)
								ELSE Gadgets.framehandle(F, M)
								END
							ELSE Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS Display.ModifyMsg THEN Modify(F, M(Display.ModifyMsg))
					ELSIF M IS Display.LocateMsg THEN
						WITH M: Display.LocateMsg DO
							M.loc := F; M.u := M.X - x; M.v := M.Y - (y + h - 1); M.res := 0
						END
					ELSIF M IS Display3.OverlapMsg THEN
						WITH M: Display3.OverlapMsg DO
							F.mask := M.M;
							SetContentMask(F, F.T1);
							SetContentMask(F, F.T2);
							SetContentMask(F, F.slider)
						END
					ELSIF M.F # NIL THEN Gadgets.framehandle(F, M) 
					ELSE ToContent(F, F.T1, x, y, M); ToContent(F, F.T2, x, y, M); ToContent(F, F.slider, x, y, M)
					END
				ELSE (* message perhaps for content *)	
					IF M IS Display3.UpdateMaskMsg THEN
						IF M.F = F.T1 THEN SetContentMask(F, F.T1)
						ELSIF M.F = F.T2 THEN SetContentMask(F, F.T2)
						ELSIF M.F = F.slider THEN SetContentMask(F, F.slider)
						ELSE ToKids(F, M)
						END
					ELSIF M IS Display.ControlMsg THEN
						ToKids(F, M)
					ELSIF M IS Display.ModifyMsg THEN
						IF (M.F = F.T1) OR (M.F = F.T2) OR (M.F = F.slider) THEN
						ELSE ToKids(F, M)
						END
					ELSIF M IS Display.ConsumeMsg THEN
					ELSE ToKids(F, M)
					END
				END
			END
		ELSIF M IS Objects.BindMsg THEN
			Gadgets.framehandle(F, M)
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Gadgets.framehandle(F, M)
				ELSIF M.id = Objects.load THEN
					Gadgets.framehandle(F, M)
				END
			END
		ELSIF M IS Objects.AttrMsg THEN Attributes(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink (*non-first arrival*)
				ELSE (*first arrival*)
					NEW(F1); F.stamp := M.stamp; F.dlink := F1; Copy(M, F, F1); M.obj := F1
				END
			END
		ELSE Gadgets.framehandle(F, M)
		END
	END
END Handle;

PROCEDURE MakeLines(t1, t2: Texts.Text; VAR first: Line; VAR lines: INTEGER);
	VAR new: Line; R1, R2: Texts.Reader; ch: CHAR;
	
	PROCEDURE Insert(first, l: Line);
	BEGIN l.next:= first; l.prev:= first.prev; first.prev.next:= l; first.prev:= l; l.nr:= lines
	END Insert;
	
BEGIN
	NEW(first); first.prev:= first; first.next:= first; new:= first; lines:= -1;
	Texts.OpenReader(R1, t1, 0); Texts.OpenReader(R2, t2, 0);
	REPEAT INC(lines); Insert(first, new);
		new.p1:= Texts.Pos(R1); new.p2:= Texts.Pos(R2); NEW(new);
		REPEAT Texts.Read(R1, ch) UNTIL (ch = CR) OR R1.eot;
		REPEAT Texts.Read(R2, ch) UNTIL (ch = CR) OR R2.eot;
	UNTIL R1.eot OR R2.eot;
	IF ~R1.eot THEN
		REPEAT INC(lines); Insert(first, new);
			new.p1:= Texts.Pos(R1); new.p2:= new.prev.p2;
			REPEAT Texts.Read(R1, ch) UNTIL ch = CR
		UNTIL R1.eot
	ELSIF ~R2.eot THEN
		REPEAT INC(lines); Insert(first, new);
			new.p1:= new.prev. p1; new.p2:= Texts.Pos(R2);
			REPEAT Texts.Read(R2, ch) UNTIL ch = CR
		UNTIL R2.eot
	END
END MakeLines;

PROCEDURE Init* (F: Frame; t1, t2: Texts.Text; n1, n2: ARRAY OF CHAR);
	VAR lines: INTEGER; M: Display.ModifyMsg; A: Objects.AttrMsg;
BEGIN
	F.handle := Handle;
	IF t1.len = 0 THEN
		Texts.WriteString(W, "*** empty Text ***"); Texts.Write(W, CR);
		Texts.Append(t1, W.buf)
	END;
	IF t2.len = 0 THEN
		Texts.WriteString(W, "*** empty Text ***"); Texts.Write(W, CR);
		Texts.Append(t2, W.buf)
	END;
	
	NEW(F.T1); TextGadgets.Init(F.T1, t1, TRUE);
	NEW(F.T2); TextGadgets.Init(F.T2, t2, TRUE);
	MakeLines(t1, t2, F.lines, lines); F.org:= F.lines;
	
	NEW(F.slider); InitSlider(F.slider, lines);
	INCL(F.slider.state, Gadgets.lockedsize);
	
	COPY(n1, F.name1); COPY(n2, F.name2);

	M.id := Display.extend; M.mode:= Display.state;
	M.X:= 0; M.Y:= 0; M.W:= F.W; M.H:= F.H;
	M.dX:= 0; M.dY:= 0; M.dW:= 0; M.dH:= 0;
	M.x:= 0; M.y:= 0; M.res:= -1; M.F:= F;
	Modify(F, M);
	A.id:= Objects.set; A.name:= "Locked"; A.class:= Objects.Bool; A.b:= TRUE;
	A.res:= -1; F.T1.handle(F.T1, A);
	A.res:= -1; F.T1.handle(F.T2, A)
END Init;

PROCEDURE New*;
	VAR F: Frame; T1, T2: Texts.Text;
BEGIN
	NEW(F); F.X:= 0; F.Y:= 0; F.W:= 320; F.H:= 200;
	NEW(T1); Texts.Open(T1, "");
	NEW(T2); Texts.Open(T2, "");
	Init(F, T1, T2, "", "");
	Objects.NewObj := F
END New;


(* *************** DOCUMENT STUFF *************** *)


PROCEDURE Load(D: Documents.Document);
	VAR obj: Objects.Object;
BEGIN
	obj:= Gadgets.CreateObject("DiffGadgets.New");
	IF obj #NIL THEN Documents.Init(D, obj(Frame)) END
END Load;

PROCEDURE Store(D: Documents.Document);
BEGIN
	Texts.WriteString(W, "Diff: document can not be stored"); Texts.WriteLn(W);
	Texts.Append(Oberon.Log, W.buf)
END Store;

PROCEDURE Handler(D: Objects.Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH D: Documents.Document DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF M.id = Objects.get THEN
					IF M.name = "Gen" THEN M.class := Objects.String; M.s := "DiffGadgets.NewDoc"; M.res := 0
					ELSIF M.name = "Adaptive" THEN M.class := Objects.Bool; M.b := TRUE; M.res := 0
					ELSIF M.name = "Icon" THEN M.class := Objects.String; M.s := "Icons.Text"; M.res := 0
					ELSIF M.name = "Menu" THEN M.class := Objects.String; M.s := ""; M.res := 0
					ELSE Documents.Handler(D, M)
					END
				ELSE Documents.Handler(D, M)
				END
			END
		ELSE Documents.Handler(D, M)
		END
	END
END Handler;

PROCEDURE NewDoc*;
	VAR D: Documents.Document;
BEGIN
	NEW(D);
	D.Load := Load; D.Store := Store; D.handle := Handler;
	D.W := 250; D.H := 200;
	Objects.NewObj := D
END NewDoc;

PROCEDURE OpenDoc*(t1, t2: Texts.Text; n1, n2: ARRAY OF CHAR);
	VAR D: Documents.Document; F: Frame;
BEGIN
	NEW(D);
	D.Load := Load; D.Store := Store; D.handle := Handler;
	D.W := 640; D.H := 200;
	
	NEW(F); Init(F, t1, t2, n1, n2);
	Documents.Init(D, F);
	COPY("Diff.Text", D.name);
	Desktops.ShowDoc(D)
END OpenDoc;

BEGIN
	Texts.OpenWriter(W)
END DiffGadgets.
