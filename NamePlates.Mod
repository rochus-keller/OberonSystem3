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

MODULE NamePlates;	(** portable *)  (** jm 19.4.95 *)

(*
	5.4.93 - object is not named anymore
	- selection is returned in full
	8.11.94 - improved findmodel
	19.4.95 - added delete right, arrow support
	26.10.95 - Added scrolling support
	20.6.96 - added iconize of documents when middle clicked (ps - 20.6.96)
	8.1.97 - removed iconize of documents when middle clicked (ps)
*)

IMPORT
	Objects, Input, Display, Fonts, Texts, Display3, Oberon, Gadgets, Effects, Printer, Printer3, Files, 
	Documents, Viewers, Desktops, FileDir;
	
CONST
 	(* name plates *)
 	VersionNo = 1; MaxLen = 128; CarHeight = 14; CarWidth = 2; Xoffset = 10;
 	
TYPE
	NamePlate* = POINTER TO NamePlateDesc;
	NamePlateDesc* = RECORD (Gadgets.FrameDesc)
		selbeg, selend: INTEGER;
		time: LONGINT;
		carpos, carx, cary: INTEGER;
		val: ARRAY MaxLen OF CHAR;
		start: INTEGER;
	END;
	
VAR
	W: Texts.Writer;
	invTF: INTEGER; (* focus & selection color for text fields *)

PROCEDURE Update(obj: Objects.Object);
VAR M: Desktops.UpdateNameMsg;
BEGIN M.obj := obj; M.F := NIL; Display.Broadcast(M)
END Update;

PROCEDURE Min(x, y: INTEGER): INTEGER;
BEGIN IF x < y THEN RETURN x; ELSE RETURN y; END;
END Min;

PROCEDURE Yoffset(F: NamePlate): INTEGER;
BEGIN RETURN F.H DIV 2 - Fonts.Default.height DIV 2 + ABS(Fonts.Default.minY);
END Yoffset;

PROCEDURE Length(VAR S: ARRAY OF CHAR): INTEGER;
VAR p: INTEGER;
BEGIN
	p := 0; WHILE S[p] # 0X DO INC(p); END; RETURN p
END Length;

PROCEDURE InsertChar(VAR S: ARRAY OF CHAR; pos: INTEGER; ch: CHAR);
VAR len, p: INTEGER;
BEGIN
	len := Length(S); 
	IF pos > len THEN pos := len ELSIF pos < 0 THEN pos := 0 END;
	IF len < LEN(S)-1 THEN (* space left *)
		p := len; S[len + 1] := 0X;
		WHILE p > pos DO S[p] := S[p-1]; DEC(p); END;
		S[pos] := ch;
	END
END InsertChar;

PROCEDURE DeleteChar(VAR S: ARRAY OF CHAR; pos: INTEGER);
VAR len, p: INTEGER;
BEGIN
	len := Length(S);
	IF pos > len THEN pos := len ELSIF pos < 0 THEN pos := 0 END;
	IF (pos < LEN(S)) & (len > 0) THEN
		p := pos; WHILE S[p] # 0X DO S[p] := S[p+1]; INC(p); END;
	END
END DeleteChar;

PROCEDURE Delete(VAR S: ARRAY OF CHAR; beg, end: INTEGER); (* [beg, end) *)
VAR len, p: INTEGER;
BEGIN
	IF beg < 0 THEN beg := 0 END; 
	len := Length(S); IF end > len THEN end := len END;
	p := end;
	WHILE p <= len DO S[beg] := S[p]; INC(beg); INC(p) END
END Delete;

PROCEDURE DocToPlate(F: NamePlate);
	VAR i, j, k: LONGINT;
BEGIN
(*ejz*)IF F.carpos >= 0 THEN RETURN END;
	COPY(F.obj(Documents.Document).name, F.val);
	i := 0; j := -1;
	WHILE F.val[i] # 0X DO
		IF F.val[i] = FileDir.PathChar THEN
			j := i+1
		END;
		INC(i)
	END;
	IF j > 0 THEN
		k := 0; i := j;
		WHILE F.val[i] # 0X DO
			F.val[k] := F.val[i]; INC(i); INC(k)
		END;
		F.val[k] := " "; INC(k);
		i := 0;
		WHILE (i < j) & (k < 127) DO
			F.val[k] := F.obj(Documents.Document).name[i]; INC(i); INC(k)
		END;
		F.val[k] := 0X
	END
END DocToPlate;

PROCEDURE PlateToDoc(F: NamePlate);
	VAR
		i, j: LONGINT;
		lastChar: CHAR;
BEGIN
(*ejz*)IF F.carpos >= 0 THEN RETURN END;
	(*COPY(F.val, F.obj(Documents.Document).name)*)
	i := 0;
	WHILE F.val[i] > " " DO
		INC(i)
	END;
	IF F.val[i] = " " THEN
		INC(i); j := 0; lastChar := FileDir.PathChar;
		WHILE F.val[i] # 0X DO
			lastChar := F.val[i];
			F.obj(Documents.Document).name[j] := lastChar; INC(i); INC(j)
		END;
		IF lastChar # FileDir.PathChar THEN
			F.obj(Documents.Document).name[j] := FileDir.PathChar; INC(j);
			IF i < 127 THEN
				F.val[i] := FileDir.PathChar; F.val[i+1] := 0X
			END
		END;
		i := 0;
		WHILE F.val[i] > " " DO
			F.obj(Documents.Document).name[j] := F.val[i]; INC(i); INC(j)
		END;
		F.obj(Documents.Document).name[j] := 0X
	ELSE
		COPY(F.val, F.obj(Documents.Document).name)
	END;
	Update(F.obj)
END PlateToDoc;

(* ----- NamePlates ----- *)

PROCEDURE FindModel(F: NamePlate; dlink: Objects.Object);
VAR f: Display.Frame; M: Objects.LinkMsg;
BEGIN
	WHILE (dlink # NIL) & ~(dlink IS Documents.Document) & ~(dlink IS Viewers.Viewer) & ~(dlink IS Desktops.DocGadget) DO dlink := dlink.dlink END;
	IF dlink # NIL THEN
		IF dlink IS Documents.Document THEN
			WITH dlink: Documents.Document DO
				IF F.obj # dlink THEN F.obj := dlink; DocToPlate(F) END
			END
		ELSIF dlink IS Desktops.DocGadget THEN
			WITH dlink: Desktops.DocGadget DO
				IF Desktops.Main(dlink) # NIL THEN
					f := Desktops.Main(dlink);
					IF f IS Documents.Document THEN
						F.obj := f; DocToPlate(F)
					ELSE
						M.id := Objects.get; M.name := "Model"; M.obj := NIL; M.res := -1; f.handle(f, M);
						IF (M.res >= 0) & (M.obj # NIL) & (M.obj IS Documents.Document) THEN
							F.obj := M.obj; DocToPlate(F)
						END
					END
				END
			END
		ELSE (* Viewer *)
			WITH dlink: Display.Frame DO
				f := dlink.dsc.next;
				IF f # NIL THEN
					IF f IS Documents.Document THEN
						F.obj := f; DocToPlate(F)
					ELSIF f IS Gadgets.Frame THEN
						WITH f: Gadgets.Frame DO
							IF (f.obj # NIL) & (f.obj IS Documents.Document) THEN
								F.obj := f.obj; DocToPlate(F)
							END
						END
					END
				END
			END
		END
	END
END FindModel;

PROCEDURE UpdateNamePlate(F: NamePlate);
VAR obj: Objects.Object;
BEGIN
	obj := F.obj;
	IF obj # NIL THEN
		IF obj IS Documents.Document THEN
			PlateToDoc(F); Update(obj)
		END
	ELSE Gadgets.Update(F)
	END
END UpdateNamePlate;

PROCEDURE^ LocatePos(F: NamePlate; pos: INTEGER; VAR x, y: INTEGER);

PROCEDURE ConsumeChar(F: NamePlate; ch: CHAR);
VAR x, y: INTEGER;
BEGIN
	IF ch = 7FX THEN
		IF F.carpos > 0 THEN
			DEC(F.carpos); DeleteChar(F.val, F.carpos);
			IF F.start > F.carpos THEN DEC(F.start) END;
			F.selbeg := -1; UpdateNamePlate(F)
		END;
	ELSIF ch = 0A1X  THEN (* Delete right *)
		IF F.val[F.carpos] # 0X THEN
			DeleteChar(F.val, F.carpos);
			F.selbeg := -1; UpdateNamePlate(F)
		END;
	ELSIF ch = 0C4X THEN (* left arrow *)
		IF F.carpos > 0 THEN
			DEC(F.carpos);
			IF F.start > F.carpos THEN DEC(F.start) END;
			F.selbeg := -1; UpdateNamePlate(F)
		END
	ELSIF ch = 0C3X THEN (* right arrow *)
		IF F.val[F.carpos] # 0X THEN
			INC(F.carpos);
			LocatePos(F, F.carpos, x, y);
			WHILE (x >= F.W - 3) & (F.val[F.start] # 0X) DO
				INC(F.start); LocatePos(F, F.carpos, x, y);
			END;
			F.selbeg := -1; UpdateNamePlate(F)
		END
	ELSIF ch = 0A8X THEN (* home *)
		IF F.carpos > 0 THEN
			F.carpos := 0; F.start := 0;
			F.selbeg := -1; UpdateNamePlate(F)
		END
	ELSIF ch = 0A9X THEN (* end *)
		IF F.val[F.carpos] # 0X THEN
			WHILE F.val[F.carpos] # 0X DO
				INC(F.carpos)
			END;
			LocatePos(F, F.carpos, x, y);
			WHILE (x >= F.W - 3) & (F.val[F.start] # 0X) DO
				INC(F.start); LocatePos(F, F.carpos, x, y);
			END;
			F.selbeg := -1; UpdateNamePlate(F)
		END
	ELSIF ((ch >= " ") OR (ch = 09X)) & (Length(F.val) < MaxLen-1) THEN
		InsertChar(F.val, F.carpos, ch);
		INC(F.carpos);
		LocatePos(F, F.carpos, x, y);
		WHILE (x >= F.W - 3) & (F.val[F.start] # 0X) DO
			INC(F.start); LocatePos(F, F.carpos, x, y);
		END;
		F.selbeg := -1; UpdateNamePlate(F);
	ELSIF ch = 0DX THEN
	END
END ConsumeChar;

PROCEDURE LocateChar(F: NamePlate; x, mx: INTEGER; VAR pos: INTEGER);
VAR p: INTEGER; r: Objects.Object; X: INTEGER;
BEGIN
	p := F.start; X := x + Xoffset;
	WHILE (F.val[p] # 0X) DO
		Fonts.Default.GetObj(Fonts.Default, ORD(F.val[p]), r);
		IF mx < X + r(Fonts.Char).dx THEN pos := p; RETURN; END;
		INC(X, r(Fonts.Char).dx); INC(p);
	END;
	pos := p;
END LocateChar;

PROCEDURE LocatePos(F: NamePlate; pos: INTEGER; VAR x, y: INTEGER);
VAR r: Objects.Object; p: INTEGER;
BEGIN
	x := Xoffset; y := Yoffset(F); p := F.start;
	WHILE (F.val[p] # 0X) & (p < pos) DO
		Fonts.Default.GetObj(Fonts.Default, ORD(F.val[p]), r);
		INC(x, r(Fonts.Char).dx); INC(p);
	END;
END LocatePos;

PROCEDURE FlipCaret(R: Display3.Mask; F: NamePlate; x, y: INTEGER);
BEGIN
	IF F.carpos >= 0 THEN Display3.ReplConst(R, invTF, x + F.carx, y + F.cary-3, CarWidth, CarHeight, Display.invert); END;
END FlipCaret;

PROCEDURE SetCaret(R: Display3.Mask; F: NamePlate; x, y, pos: INTEGER);
BEGIN
	LocatePos(F, pos, F.carx, F.cary);
	Display3.ReplConst(R, invTF, x + F.carx, y + F.cary-3, CarWidth, CarHeight, Display.invert);
END SetCaret;

PROCEDURE RemoveCaret(R: Display3.Mask; F: NamePlate; x, y: INTEGER);
BEGIN
	IF F.carpos >= 0 THEN FlipCaret(R, F, x, y); F.carpos := -1 END
END RemoveCaret;

PROCEDURE TrackCaret(VAR DR: Display3.Mask; F: NamePlate; x, y: INTEGER);
VAR mx, my, pos: INTEGER; keys, keysum: SET; time, beg, end, p: LONGINT; text: Texts.Text;
	R: Texts.Reader; ch: CHAR;
BEGIN
	RemoveCaret(DR, F, x, y); keysum := {};
	LOOP
		Input.Mouse(keys, mx, my); keysum := keysum + keys;
		IF keys = {} THEN EXIT; END;
		LocateChar(F, x, mx, pos);
		IF pos # F.carpos THEN
			Oberon.FadeCursor(Oberon.Mouse);
			FlipCaret(DR, F, x, y); F.carpos := pos; LocatePos(F, F.carpos, F.carx, F.cary); FlipCaret(DR, F, x, y);
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, mx, my);
	END;
	IF keysum = {2, 1} THEN
		Oberon.GetSelection(text, beg, end, time);
		IF time > 0 THEN
			p := beg; Texts.OpenReader(R, text, p);
			LOOP
				IF p = end THEN EXIT END;
				Texts.Read(R, ch);
				IF R.eot THEN EXIT END;
				IF Length(F.val) >= MaxLen-1 THEN EXIT END;
				IF (20X <= ch) & (ch < 86X) OR (ch = " ") OR (ch = 9X) THEN
					InsertChar(F.val, F.carpos, ch); INC(F.carpos)
				END;
				INC(p);
			END; F.selbeg := -1;
			UpdateNamePlate(F)
		END
	ELSE
		Gadgets.Update(F)
	END
END TrackCaret;

PROCEDURE FlipSelection(R: Display3.Mask; F: NamePlate; x, y: INTEGER; spos, epos: INTEGER);
VAR sx, sy, ex, ey: INTEGER;
BEGIN
	LocatePos(F, spos, sx, sy); LocatePos(F, epos, ex, ey);
	Display3.ReplConst(R, invTF, x + sx, y + sy - 3, (ex - sx), Min(CarHeight, F.H - 4), Display.invert);
END FlipSelection;

PROCEDURE RemoveSelection(R: Display3.Mask; F: NamePlate; x, y: INTEGER);
BEGIN
	IF F.selbeg >= 0 THEN FlipSelection(R, F, x, y, F.selbeg, F.selend); F.selbeg := -1; END;
END RemoveSelection;

PROCEDURE TrackSelection(R: Display3.Mask; F: NamePlate; x, y: INTEGER);
VAR mx, my, pos, spos, epos, len: INTEGER; keys, keysum: SET; time: LONGINT;
	C: Oberon.ConsumeMsg; 
BEGIN
	Oberon.FadeCursor(Oberon.Mouse);
	Input.Mouse(keys, mx, my);
	IF keys = {} THEN RETURN END;
	keysum := keys; len := Length(F.val);
	LocateChar(F, x, mx, spos);
	IF spos >= len THEN DEC(spos) END;
	IF (F.selbeg >= 0) & (F.selbeg = spos) & (F.selend = F.selbeg + 1) THEN
		RemoveSelection(R, F, x, y);
		epos := spos; spos := 0; FlipSelection(R, F, x, y, spos, epos+1);
	ELSE
		RemoveSelection(R, F, x, y);
		epos := spos;
		FlipSelection(R, F, x, y, spos, epos+1);
	END;
	LOOP
		Input.Mouse(keys, mx, my); keysum := keysum + keys;
		IF keys = {} THEN EXIT; END;
		LocateChar(F, x, mx, pos);
		IF pos >= len THEN DEC(pos) END;
		IF (pos >= spos) & (pos # epos) THEN
			Oberon.FadeCursor(Oberon.Mouse);
			IF (pos < epos) THEN
				FlipSelection(R, F, x, y,  pos+1, epos+1);
			ELSE
				FlipSelection(R, F, x, y,  epos+1, pos+1);
			END;
			epos := pos;
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, mx, my)
	END;
	FlipSelection(R, F, x, y,  spos, epos+1);
	F.selbeg := -1; 
	IF keysum = {0} THEN
		F.time := Oberon.Time();
		F.selbeg := spos; F.selend := epos+1;
		Gadgets.Update(F)
	ELSIF keysum = {0, 1} THEN (* copy out *)
		F.selbeg := spos; F.selend := epos+1; F.time := Oberon.Time();
		Gadgets.Update(F);
		Oberon.GetSelection(C.text, C.beg, C.end, time);
		C.F := NIL; C.res := -1;
		Display.Broadcast(C);
	ELSIF keysum = {0, 2} THEN (* delete *)
		Oberon.Defocus; 
		Delete(F.val, spos, epos+1); F.carpos := spos;
		UpdateNamePlate(F)
	ELSE Gadgets.Update(F)
	END
END TrackSelection;

PROCEDURE GetSelection(F: NamePlate; VAR text: Texts.Text; VAR beg, end, time: LONGINT);
VAR p: INTEGER; W: Texts.Writer;
BEGIN
	NEW(text); Texts.Open(text, "");
	(* old
	p := F.selbeg; Texts.OpenWriter(W);
	WHILE p < F.selend DO
		Texts.Write(W, F.val[p]); INC(p);
	END;
	*)
	p := 0; Texts.OpenWriter(W);
	WHILE F.val[p] # 0X DO
		Texts.Write(W, F.val[p]); INC(p);
	END;
	Texts.Append(text, W.buf);
	beg := F.selbeg; end := F.selend; time := F.time
END GetSelection;

PROCEDURE ForceString(F: Display.Frame; VAR M: Objects.AttrMsg);
BEGIN Gadgets.framehandle(F, M);
	IF M.res < 0 THEN M.class := Objects.String; M.s := ""; M.res := 0 END
END ForceString;

PROCEDURE NamePlateAttr(F: NamePlate; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class := Objects.String; COPY("NamePlates.NewNamePlate", M.s); M.res := 0
		ELSIF M.name = "Value" THEN
IF F.carpos >= 0 THEN
(*ejz*)PlateToDoc(F); DocToPlate(F)
END;
			M.class := Objects.String;
			IF (F.obj # NIL) & (F.obj IS Documents.Document) THEN
				COPY(F.obj(Documents.Document).name, M.s)
			ELSE
				COPY(F.val, M.s)
			END;
			M.res := 0
		ELSIF M.name = "Cmd" THEN ForceString(F, M)
		ELSE Gadgets.framehandle(F, M)
		END;
	ELSIF M.id = Objects.set THEN
		IF M.name = "Value" THEN
			IF M.class = Objects.String THEN
				IF (F.obj # NIL) & (F.obj IS Documents.Document) THEN
					COPY(M.s, F.obj(Documents.Document).name);
					DocToPlate(F)
				ELSE
					COPY(M.s, F.val)
				END;
				M.res := 0
			END;
		ELSE Gadgets.framehandle(F, M);
		END;
	ELSIF M.id = Objects.enum THEN
		M.Enum("Value"); M.Enum("Cmd"); Gadgets.framehandle(F, M); 
	END;
END NamePlateAttr;

PROCEDURE ConsumeText(F: NamePlate; VAR M: Oberon.ConsumeMsg);
VAR R: Texts.Reader; ch: CHAR; pos: LONGINT;
BEGIN
	F.selbeg := -1;
	pos := M.beg; Texts.OpenReader(R, M.text, pos);
	LOOP
		IF pos = M.end THEN EXIT END;
		Texts.Read(R, ch);
		IF R.eot THEN EXIT END;
		IF Length(F.val) >= MaxLen-1 THEN EXIT END;
		IF (20X <= ch) OR (ch = " ") OR (ch = 9X) THEN
			InsertChar(F.val, F.carpos, ch); INC(F.carpos);
		END;
		INC(pos);
	END;
	UpdateNamePlate(F);
END ConsumeText;

PROCEDURE Dot(R: Display3.Mask; x, y: INTEGER);
VAR c: INTEGER;

	PROCEDURE D(col: INTEGER);
	BEGIN Display3.Dot(R, col, x, y, Display.replace);
		INC(c); INC(x); IF c MOD 4 = 0 THEN INC(y); DEC(x, 4); END;
	END D;
BEGIN
	c := 0;
	D(14); D(13); D(12); D(13);
	D(14); D(14); D(13); D(12);
	D(0); D(14); D(14); D(13);
	D(13); D(0); D(14); D(14);
END Dot;

PROCEDURE RestoreNamePlate(R: Display3.Mask; F: NamePlate; x, y, w, h: INTEGER; dlink: Objects.Object);
VAR p, X, Y, cx, cy, cw, ch, col: INTEGER; r: Objects.Object;
BEGIN
	col := Display3.textbackC;
	FindModel(F, dlink);
	Oberon.RemoveMarks(x, y, w, h);
	Display3.Rect3D(R, Display3.topC, Display3.bottomC, x, y, w, h, 1, Display.replace);
	
	(* left border *)
	Display3.ReplConst(R, col, x+1, y+1, Xoffset - 1, h-2, Display.replace);
	
	Dot(R, x+2, y+2); Dot(R, x+2, y + h - 7); 
	
	p := F.start; X := x + Xoffset; Y := y + Yoffset(F);
	cx := R.X; cy := R.Y; cw := R.W; ch := R.H;
	Display3.AdjustMask(R, x+1, y+1, w-2, h-2);
	WHILE F.val[p] # 0X DO
		Fonts.Default.GetObj(Fonts.Default, ORD(F.val[p]), r);
		WITH r: Fonts.Char DO
			Display3.ReplConst(R, col, X, y+1, r.dx, h-2, Display.replace);
			Display3.CopyPattern(R, Display3.textC, r.pat, X + r.x, Y + r.y, Display3.textmode); INC(X, r.dx); INC(p); 
		END;
	END;
	IF X < x + w - 1 THEN
		Display3.ReplConst(R, col, X, y+1, x + w - X - 1, h-2, Display.replace);
	END;
	
	Dot(R, x+w-7, y+2); Dot(R, x+w-7, y + h - 7);
	
	IF F.carpos >= 0 THEN 
		IF F.carpos > Length(F.val) THEN
			F.carpos := Length(F.val)
		END;
		SetCaret(R, F, x, y, F.carpos);
	END;
	IF F.selbeg >= 0 THEN
		FlipSelection(R, F, x, y, F.selbeg, F.selend);
	END;
	R.X := cx; R.Y := cy; R.W := cw; R.H := ch;
	IF Gadgets.selected IN F.state THEN Display3.FillPattern(R, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint); END;
END RestoreNamePlate;

PROCEDURE PrintNamePlate(F: NamePlate; VAR M: Display.DisplayMsg);
VAR R: Display3.Mask; x, y, w, h: INTEGER;

	PROCEDURE P(x: INTEGER): INTEGER;
	BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
	END P;

BEGIN
	Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, R);
	x := M.x; y := M.y; w := P(F.W); h := P(F.H);
	Printer3.Rect3D(R, Display3.topC, Display3.bottomC, x, y, w, h, P(1), Display.replace); 
	Printer3.ReplConst(R, Display3.textbackC, x+P(1), y+P(1), w - P(2), h-P(2), Display.replace);
	Display3.AdjustMask(R, x+P(1), y+P(1), w-P(2), h-P(2));
	Printer3.String(R, Display3.textC, x + P(Xoffset), y + P(Yoffset(F)), Fonts.Default, F.val, Display.replace)
END PrintNamePlate;

PROCEDURE CopyNamePlate*(VAR M: Objects.CopyMsg; from, to: NamePlate);
VAR obj: Objects.Object;
BEGIN
	obj := from.obj; from.obj := NIL;
	Gadgets.CopyFrame(M, from, to);
	from.obj := obj;
	
	COPY(from.val, to.val); to.carpos := -1; to.selbeg := -1;
END CopyNamePlate;

PROCEDURE NamePlateHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR F2: NamePlate; x, y, w, h: INTEGER; R: Display3.Mask; ver: LONGINT; obj: Objects.Object; A: Objects.AttrMsg;
BEGIN
	WITH F: NamePlate DO
		IF M IS  Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO NamePlateAttr(F, M) END;
		ELSIF M IS  Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.load THEN
					Files.ReadNum(M.R, ver);
					IF ver # VersionNo THEN Texts.WriteString(W, "  cannot read nameplate"); Texts.WriteLn(W); HALT(99)
					END;
					Files.ReadString(M.R, F.val);
					Gadgets.framehandle(F, M);
					A.res := -1; A.id := Objects.get; A.name := "Cmd"; Gadgets.framehandle(F, A);
					IF (A.res = 0) & (A.s = "") THEN
						A.res := -1; A.id := Objects.set; A.name := "Cmd"; A.class := Objects.String; A.s := "Attributes.Echo '#Value '";
						Gadgets.framehandle(F, A);
					END
				ELSIF M.id = Objects.store THEN
					Files.WriteNum(M.R, VersionNo);
					Files.WriteString(M.R, F.val);
					obj := F.obj; F.obj := NIL; 
					Gadgets.framehandle(F, M);
					F.obj := obj;
				END
			END
		ELSIF M IS Objects.BindMsg THEN
			WITH M: Objects.BindMsg DO
				(* do not bind the model !!! *)
				obj := F.obj; F.obj := NIL; Gadgets.framehandle(F, M); F.obj := obj;
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink
				ELSE NEW(F2); F.stamp := M.stamp; F.dlink := F2; CopyNamePlate(M, F, F2); M.obj := F2
				END
			END;
		ELSIF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF M.res >= 0 THEN RETURN END;
				x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
				IF M IS Display.DisplayMsg THEN
					WITH M: Display.DisplayMsg DO
						IF M.device = Display.screen THEN
							IF (M.F = NIL) OR ((M.id = Display.full) & (M.F = F)) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								RestoreNamePlate(R, F, x, y, w, h, M.dlink);
							ELSIF (M.id = Display.area) & (M.F = F) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R); 
								Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
								RestoreNamePlate(R, F, x, y, w, h, M.dlink); 
							END
						ELSIF M.device = Display.printer THEN PrintNamePlate(F, M)
						END
					END
				ELSIF M IS Oberon.ControlMsg THEN
					WITH M: Oberon.ControlMsg DO
						IF (M.id = Oberon.defocus) & (F.carpos >= 0) THEN F.carpos := -1; F.start := 0;
(*ejz*)PlateToDoc(F); DocToPlate(F);
							Gadgets.Update(F);
						ELSIF (M.id = Oberon.neutralize) & (F.carpos >= 0) THEN F.carpos := -1; F.start := 0; (* hack @@@ *)
(*ejz*)PlateToDoc(F); DocToPlate(F);
							F.selbeg := -1; Gadgets.Update(F); 
						ELSIF (M.id = Oberon.neutralize) & (F.selbeg >= 0) THEN F.carpos := -1; F.start := 0;
(*ejz*)PlateToDoc(F); DocToPlate(F);
							F.selbeg := -1; Gadgets.Update(F);
						ELSIF M.id = Oberon.mark THEN Oberon.DrawCursor(Oberon.Pointer, Oberon.Star, M.X, M.Y);
						END;
					END
				ELSIF M IS Desktops.UpdateNameMsg THEN
					WITH M: Desktops.UpdateNameMsg  DO
						IF (M.obj = F.obj) THEN
							IF (M.stamp # F.stamp) THEN
								F.stamp := M.stamp;
								IF F.obj IS Documents.Document THEN
									DocToPlate(F)
								END
							END;
							F.selbeg := -1;
							Gadgets.MakeMask(F, x, y, M.dlink, R);
							RestoreNamePlate(R, F, x, y, w, h, M.dlink);
						END
					END
				ELSIF M IS Gadgets.UpdateMsg THEN
					WITH M: Gadgets.UpdateMsg DO
						IF M.obj = F.obj THEN
							Update(F.obj)
						ELSE Gadgets.framehandle(F, M)
						END
					END
				ELSIF M IS Display.ControlMsg THEN (*!!! *)
					WITH M: Display.ControlMsg DO
						IF FALSE & (M.id = Display.restore) & (F.obj # NIL) THEN
							IF (M.stamp # F.stamp) THEN
								F.stamp := M.stamp;
								IF F.obj IS Documents.Document THEN DocToPlate(F) END
							END;
							F.selbeg := -1;
						END
					END
				ELSIF M IS Oberon.SelectMsg THEN
					WITH M: Oberon.SelectMsg DO
						IF (F.selbeg >=0) & (F.time > M.time) THEN GetSelection(F, M.text, M.beg, M.end, M.time) END
					END
				ELSIF M IS Oberon.ConsumeMsg THEN
					WITH M: Oberon.ConsumeMsg DO
						IF F.carpos >= 0 THEN ConsumeText(F, M) END;
					END
				ELSIF (M IS Oberon.CaretMsg) & (F.carpos >= 0) THEN
					WITH M: Oberon.CaretMsg DO
						M.car := F; M.res := 0
					END
				ELSIF M IS Oberon.InputMsg THEN
					WITH M: Oberon.InputMsg DO
						IF (M.id = Oberon.track) & (Gadgets.InActiveArea(F, M) OR (2 IN M.keys)) THEN
							IF (2 IN M.keys) &
								((M.X-x) >= Xoffset) & ((F.W-M.X+x) >= Xoffset) & ((M.Y-y) >= Yoffset(F)) & ((F.H-M.Y+y) >= Yoffset(F)) THEN
								Oberon.Defocus();
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								TrackCaret(R, F, x, y); M.res := 0;
							ELSIF 0 IN M.keys THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								TrackSelection(R, F, x, y); M.res := 0;
							ELSE Gadgets.framehandle(F, M)
							END
						ELSIF (M.id = Oberon.consume) & (F.carpos >= 0) THEN
							ConsumeChar(F, M.ch); M.res := 0;
						ELSIF ~(Gadgets.selected IN F.state) THEN
							Gadgets.framehandle(F, M)
						END
					END
				ELSE
					Gadgets.framehandle(F, M);
				END
			END
		ELSE
			Gadgets.framehandle(F, M);
		END
	END
END NamePlateHandler;

PROCEDURE InitNamePlate*(F: NamePlate);
VAR M: Objects.AttrMsg;
BEGIN F.handle := NamePlateHandler; F.carpos := -1; COPY("", F.val); F.W := 100; F.H := 20;
	F.selbeg := -1;
	M.res := -1; M.id := Objects.set; M.name := "Cmd"; M.class := Objects.String; M.s := "Attributes.Echo '#Value '";
	Gadgets.framehandle(F, M)
END InitNamePlate;

PROCEDURE NewNamePlate*;
VAR B: NamePlate;
BEGIN
	NEW(B); InitNamePlate(B); Objects.NewObj := B
END NewNamePlate;

BEGIN Texts.OpenWriter(W); invTF := 15 - 14
END NamePlates.
