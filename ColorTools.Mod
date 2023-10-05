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

MODULE ColorTools; (** portable *)  (** jm 19.1.95 *)

(** ColorPicker implementation *)
(*
	jm 1.3.93 - fixed selection
	- increased size of command string
	25.7.94 - added ChangeColor command
*)

IMPORT
	Objects, Gadgets, Effects, Display, Display3, Oberon, Files, Input, Texts,  Views, Printer, Printer3;
	
CONST
	VersionNo = 2; ModName = "ColorTools";
	
TYPE
	ColorPicker* = POINTER TO ColorPickerDesc;
	ColorPickerDesc* = RECORD (Gadgets.FrameDesc)
		cmd*: ARRAY 64 OF CHAR;		(** Cmd attribute *)
		colors*: ARRAY 256 OF INTEGER;		(** colors to be displayed *)
		col*: INTEGER;		(** last color to be picked *)
	END;
	
VAR
	W: Texts.Writer;

(* --- Version check --- *)

PROCEDURE WriteVersion(VAR R: Files.Rider);
BEGIN
	Files.WriteNum(R, VersionNo);
END WriteVersion;

(* ----------- Color Picker ---------- *)

PROCEDURE Parse(VAR s: ARRAY OF CHAR; VAR n: INTEGER; VAR values: ARRAY OF INTEGER);
VAR i: INTEGER; val: LONGINT; neg: BOOLEAN;
BEGIN
	n := 0;
	i := 0;
	LOOP
		WHILE (s[i] # 0X) & (s[i] <= " ") DO INC(i) END;
		IF s[i] = 0X THEN EXIT END;
		IF s[i] = "-" THEN INC(i); neg := TRUE ELSE neg := FALSE END;
		IF (s[i] >= "0") & (s[i] <= "9") THEN
			val := 0;
			WHILE (s[i] >= "0") & (s[i] <= "9") DO val := val * 10 + ORD(s[i]) - ORD("0"); INC(i) END;
			IF neg  THEN val := -val END;
			IF val < -127 THEN val := -127
			ELSIF val > 255 THEN val := 255
			END;
			values[n] := ABS(SHORT(val)); INC(n);
		ELSE EXIT
		END
	END
END Parse;

PROCEDURE Unparse(n: INTEGER; VAR values: ARRAY OF INTEGER; VAR s: ARRAY OF CHAR);
VAR i, j: INTEGER;

	PROCEDURE Out(i: LONGINT);
	VAR k: INTEGER; x0: LONGINT; a: ARRAY 10 OF CHAR;
	BEGIN k := 0;
		IF i < 0 THEN x0 := -i
		ELSE x0 := i
		END;	
		REPEAT
			a[k] := CHR(x0 MOD 10 + 30H); x0 := x0 DIV 10; INC(k)
		UNTIL x0 = 0;
		IF i < 0 THEN s[j] := "-"; INC(j); END;
		REPEAT DEC(k); s[j] := a[k]; INC(j); UNTIL k = 0;
		s[j] := " "; INC(j);
	END Out;
	
BEGIN
	j := 0;
	i := 0;
	WHILE i < n DO Out(values[i]); INC(i) END; s[j] := 0X;
END Unparse;

PROCEDURE ColorPickerAttr(F: ColorPicker; VAR M: Objects.AttrMsg);
VAR n: INTEGER;
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class := Objects.String; COPY("ColorTools.NewColorPicker", M.s); M.res := 0
		ELSIF M.name = "Cmd" THEN M.class := Objects.String; COPY(F.cmd, M.s); M.res := 0
		ELSIF M.name = "Col" THEN M.class := Objects.Int; M.i := F.col; M.res := 0
		ELSIF M.name = "Colors" THEN M.class := Objects.String; Unparse(16, F.colors, M.s); M.res := 0
		ELSE Gadgets.framehandle(F, M);
		END;
	ELSIF M.id = Objects.set THEN
		IF M.name = "Cmd" THEN
			IF  (M.class = Objects.String) THEN COPY(M.s, F.cmd); M.res := 0 END;
		ELSIF M.name = "Col" THEN
			IF  (M.class = Objects.Int) THEN F.col := SHORT(M.i); M.res := 0; END
		ELSIF M.name = "Colors" THEN
			IF  (M.class = Objects.String) THEN
				Parse(M.s, n, F.colors);
				WHILE n < 256 DO F.colors[n] := n; INC(n) END;
				M.res := 0
			END
		ELSE Gadgets.framehandle(F, M);
		END;
	ELSIF M.id = Objects.enum THEN
		M.Enum("Colors"); M.Enum("Col"); M.Enum("Cmd");
		Gadgets.framehandle(F, M);
	END;
END ColorPickerAttr;

PROCEDURE Grid(F: ColorPicker; R: Display3.Mask; b, x, y, w, h: INTEGER);
VAR i, j, c, max: INTEGER;
BEGIN
	IF Display.Depth(0) >= 8 THEN max := 16 ELSE max := 4 END; 
	c := 0; j := max - 1;
	WHILE j >= 0 DO
		 i := 0;
		 WHILE i < max DO Display3.ReplConst(R, F.colors[c] , x + i * b, y + j * b, b, b, Display.replace); INC(i); INC(c) END;
		DEC(j);
	END;
END Grid;

PROCEDURE ClipAgainst(VAR x, y, w, h: INTEGER; x1, y1, w1, h1: INTEGER);
VAR r, t, r1, t1: INTEGER;
BEGIN
	r := x + w - 1; r1 := x1 + w1 - 1; t := y + h - 1; t1 := y1 + h1 - 1;
	IF x < x1 THEN x := x1 END;
	IF y < y1 THEN y := y1 END;
	IF r > r1 THEN r := r1 END;
	IF t > t1 THEN t := t1 END;
	w := r - x + 1; h := t - y + 1;
END ClipAgainst;

PROCEDURE PickColor(F: ColorPicker; x, y, w, h: INTEGER; VAR M: Oberon.InputMsg);
VAR bw, bw4: INTEGER;
VAR keys, keysum: SET; X, Y, i, j, li, lj, ofs, px, py, b, max: INTEGER; block: Views.Block;

	PROCEDURE Cell(X, Y: INTEGER; VAR i, j: INTEGER);
	BEGIN
		IF Effects.Inside(X, Y, x+2, y + 2 + ofs, bw, bw) THEN
			i := (X - x - 2) DIV b; j := (Y - (y + 2 + ofs)) DIV b;
		ELSE
			i := -1; j := -1;
		END;
	END Cell;
	
	PROCEDURE Highlight(colno, i, j: INTEGER);
	BEGIN
		IF i >= 0 THEN
			Oberon.FadeCursor(Oberon.Mouse);
			Display3.Rect(block.mask, F.colors[colno], Display.solid, x + 2 + i * b, y + 2 + ofs + j * b, b, b, 1, Display.replace);
		END;
	END Highlight;
	
	PROCEDURE CalcPlace(VAR px, py: INTEGER);
	VAR cx, cy, cw, ch: INTEGER; (* clipping area *) f: Objects.Object;
	BEGIN
		cx := 0; cy := 0; cw := Display.Width; ch := Display.Height;
		f := Gadgets.context;
		WHILE f # NIL DO
			IF f IS Gadgets.View THEN
				WITH f: Gadgets.View DO
					ClipAgainst(cx, cy, cw, ch, f.absX, f.absY, f.W, f.H);
				END
			END;
			f := f.dlink
		END;
		px := x; py := y + h - (bw4-1);
		IF px < cx THEN px := cx; END;
		IF px + bw4 >= cx + cw THEN px := cx + cw - 1 - bw4; END;
		IF py < cy THEN py := cy; END;
		IF py + bw4 >= cy + ch THEN py := cy + ch - 1 - bw4 END;
	END CalcPlace;

BEGIN
	IF Display.Depth(0) >= 8 THEN bw := 112; max := 16 ELSE bw := 80; max := 4 END;
	bw4 := bw + 4; b := bw DIV max;
	CalcPlace(px, py);
	ofs := 0;
	x := px; y := py;
	Oberon.RemoveMarks(x, y+ofs, bw4, bw4);
	Views.GetBlock(x, y+ofs, bw4, bw4, M.dlink, block);
	
	Display3.ReplConst(block.mask, Display3.black, x, y+ofs, bw4, bw4, Display.replace);
	Grid(F, block.mask, b, x+2, y+2+ofs, w, h);
	Input.Mouse(keys, X, Y); keysum := keys;
	Cell(X, Y, li, lj); Highlight(15, li, lj);
	WHILE keys # {} DO
		Input.Mouse(keys, X, Y);
		Cell(X, Y, i, j);
		IF (i # li) OR (j # lj) THEN
			Highlight(li + (max - 1 - lj) * max, li, lj); li := i; lj := j; Highlight(15, li, lj);
		END;
		keysum := keysum + keys;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, X, Y);
	END;
	Highlight(li + (max - 1 - lj) * max, li, lj);
	Oberon.RemoveMarks(x, y+ofs, bw4, bw4);
	Views.RestoreBlock(block);
	IF (keysum = {1}) & (i >= 0) THEN
		F.col := F.colors[li + (max - 1 - lj) * max];
		IF F.cmd[0] # 0X THEN
			Gadgets.Execute(F.cmd, F, M.dlink, NIL, NIL);
		END;
	END;
END PickColor;

PROCEDURE RestoreColorPicker(R: Display3.Mask; F: ColorPicker; x, y, w, h: INTEGER);
VAR b, max: INTEGER;
BEGIN
	IF Display.Depth(0) >= 8 THEN max := 16 ELSE max := 4 END;
	b := (w - 4) DIV max;
	Display3.ReplConst(R, Display3.black, x, y, w, h, Display.replace);
	Grid(F, R, b, x+2, y+2, w-4, h-4);
	IF Gadgets.selected IN F.state THEN Display3.FillPattern(R, Display3.white, Display3.selectpat, 0, 0, x, y, w, h, Display.paint); END;
END RestoreColorPicker;

PROCEDURE PrintColorPicker(F: ColorPicker; VAR M: Display.DisplayMsg);
VAR R: Display3.Mask; x, y, w, h, b, i, j, c, max: INTEGER;

	PROCEDURE P(x: INTEGER): INTEGER;
	BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
	END P;

BEGIN
	Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, R);
	x := M.x; y := M.y; w := P(F.W); h := P(F.H);
	Printer3.ReplConst(R, Display3.black, x, y, w, h, Display.replace);
	IF Display.Depth(0) >= 8 THEN max := 16 ELSE max := 4 END; 
	b := (F.W - 4) DIV max;
	x := M.x + P(2); y := M.y + P(2);
	c := 0; j := max - 1;
	WHILE j >= 0 DO
		 i := 0;
		 WHILE i < max DO Printer3.ReplConst(R, F.colors[c] , x + P(i * b), y + P(j * b), P(b), P(b), Display.replace); INC(i); INC(c) END;
		DEC(j);
	END;
END PrintColorPicker;

PROCEDURE CopyColorPicker*(VAR M: Objects.CopyMsg; from, to: ColorPicker);
BEGIN
	Gadgets.CopyFrame(M, from, to); to.col := from.col; COPY(from.cmd, to.cmd); to.colors := from.colors;
END CopyColorPicker;

PROCEDURE ColorPickerHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR x, y, w, h, u, v: INTEGER; F0: ColorPicker; R: Display3.Mask; ver: LONGINT;
BEGIN
	WITH F: ColorPicker DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO ColorPickerAttr(F, M) END;
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					WriteVersion(M.R);
					Files.WriteString(M.R, F.cmd);
					x := 0; WHILE x < 256 DO Files.WriteInt(M.R, F.colors[x]); INC(x) END;
					Gadgets.framehandle(F, M)
				ELSIF M.id = Objects.load THEN
					Files.ReadNum(M.R, ver);
					IF ver = 1 THEN
						Files.ReadString(M.R, F.cmd);
						Gadgets.framehandle(F, M)
					ELSIF ver = VersionNo THEN
						Files.ReadString(M.R, F.cmd);
						x := 0; WHILE x < 256 DO
							Files.ReadInt(M.R, F.colors[x]);
							IF F.colors[x] < 0 THEN F.colors[x] := x END;
							INC(x)
						END;
						Gadgets.framehandle(F, M)
					ELSE
						Texts.WriteString(W, "Version "); Texts.WriteInt(W, VersionNo, 3); Texts.WriteString(W, " of ");
						Texts.WriteString(W, ModName);
						Texts.WriteString(W, " cannot read version "); Texts.WriteInt(W, ver, 3); Texts.WriteLn(W);
						Texts.Append(Oberon.Log, W.buf);
						HALT(99);
					END
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink
				ELSE NEW(F0); F.stamp := M.stamp; F.dlink := F0; CopyColorPicker(M, F, F0); M.obj := F0
				END
			END
 		ELSIF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H; (* calculate actual coordinates *)
				u := M.x; v := M.y; (* store volatile info *)
				IF M IS Display.DisplayMsg THEN
					WITH M: Display.DisplayMsg  DO
						IF M.device = Display.screen THEN
							IF (M.F = NIL) OR ((M.id = Display.full) & (M.F = F)) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								RestoreColorPicker(R, F, x, y, w, h);
							ELSIF (M.id = Display.area) & (M.F = F) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R); 
								Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
								RestoreColorPicker(R, F, x, y, w, h);
							END
						ELSIF M.device = Display.printer THEN PrintColorPicker(F, M)
						END
					END
				ELSIF M IS Oberon.InputMsg THEN
					WITH M: Oberon.InputMsg DO
						IF ~(Gadgets.selected IN F.state) THEN
							IF (M.id = Oberon.track) & (M.keys = {1}) & Gadgets.InActiveArea(F, M) THEN
								PickColor(F, x, y, w, h, M); M.res := 0;
							ELSE
								Gadgets.framehandle(F, M);
							END;
						END;
					END;
				ELSE
					Gadgets.framehandle(F, M);	
				END;
				M.x := u; M.y := v; (* restore volatile info *)
			END;
		ELSE
			Gadgets.framehandle(F, M);
		END;
	END;
END ColorPickerHandler;

PROCEDURE InitColorPicker*(F: ColorPicker);
VAR i: INTEGER;
BEGIN F.W := 32+4; F.H := 32+4; F.col := 15; F.state := {Gadgets.lockedsize};
	F.handle := ColorPickerHandler;
	F.cmd := "ColorTools.ChangeColor #Col ~";
	i := 0; WHILE i < 256 DO F.colors[i] := i; INC(i) END;
END InitColorPicker;

PROCEDURE NewColorPicker*;
VAR F: ColorPicker;
BEGIN
	NEW(F); InitColorPicker(F); Objects.NewObj := F;
END NewColorPicker;

(** Used in the form:
	
	ColorTools.ChangeColor <colno>
	
Change the color of the selected text or the selected gadgets.	
*)
PROCEDURE ChangeColor*;
	VAR col: INTEGER; S: Texts.Scanner;
	MOS: Display.SelectMsg; MTS: Oberon.SelectMsg; MA: Objects.AttrMsg; MU: Gadgets.UpdateMsg;
	obj: Objects.Object;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S); col := SHORT(S.i);
	MOS.id := Display.get; MOS.time := -1; MOS.F := NIL; MOS.obj := NIL;
	MTS.id := Oberon.get; MTS.time := -1; MTS.F := NIL; MTS.sel := NIL; MTS.text := NIL;
	Display.Broadcast(MOS); Display.Broadcast(MTS);
	IF (MTS.time >= 0) & (MTS.time >= MOS.time) THEN
		Texts.ChangeLooks(MTS.text, MTS.beg, MTS.end, {1}, NIL, SHORT(col), 0)
	ELSIF (MOS.time >= 0) & (MOS.time >= MTS.time) & (MOS.obj # NIL) THEN
		obj := MOS.obj;
		WHILE obj # NIL DO
			MA.id := Objects.set; MA.name := "Color"; MA.class := Objects.Int; MA.i := col; MA.res := -1;
			obj.handle(obj, MA);
			obj := obj.slink
		END;
		MU.obj := MOS.obj; MU.F := NIL; Display.Broadcast(MU);
	END
END ChangeColor;

BEGIN
	Texts.OpenWriter(W);
END ColorTools.
