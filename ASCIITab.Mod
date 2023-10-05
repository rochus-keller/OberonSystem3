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

MODULE ASCIITab;	(** portable *) (* EJZ,   *)
	IMPORT Files, Objects, Display, Printer, Fonts, Texts, Display3, Printer3, Effects, Oberon, Gadgets;

	CONST
		middle = 1;

	TYPE
		Frame* = POINTER TO FrameDesc;
		FrameDesc* = RECORD (Gadgets.FrameDesc)
			font: Fonts.Font
		END;

	VAR
		W: Texts.Writer;

	PROCEDURE Restore(F: Frame; Q: Display3.Mask; x, y, w, h: INTEGER);
		VAR
			pat: LONGINT;
			i, j, x0, y0, dx, cx, cy, cw, ch, dw, dh: INTEGER;
	BEGIN
		Display3.ReplConst(Q, Display3.textbackC, x, y, w, h, Display.replace);
		x0 := x; y0 := y;
		dw := F.font.maxX-F.font.minX;
		cw := (F.W-1) DIV 32;
		IF cw > dw THEN
			dw := cw
		END;
		x := x+(F.W-32*dw) DIV 2;
		dh := F.font.height;
		ch := (F.H-1) DIV 8;
		IF ch > dh THEN
			dh := ch
		END;
		y := y+(F.H-8*dh) DIV 2;
		FOR i := 0 TO 31 DO
			FOR j := 0 TO 7 DO
				Fonts.GetChar(F.font, CHR(i+32*j), dx, cx, cy, cw, ch, pat);
				Display3.CopyPattern(Q, Display.FG, pat, x+i*dw+(dw-cw) DIV 2, y+(7-j)*dh+(dh-ch) DIV 2, Display.paint)
			END
		END;
		FOR i := 0 TO 32 DO
			Display3.ReplConst(Q, Display3.black, x+i*dw, y, 1, 8*dh, Display.replace)
		END;
		FOR j := 0 TO 8 DO
			Display3.ReplConst(Q, Display3.black, x, y+j*dh, 32*dw, 1, Display.replace)
		END;
		IF Gadgets.selected IN F.state THEN
			Display3.FillPattern(Q, Display3.white, Display3.selectpat, x0, y0, x0, y0, w, h, Display.paint)
		END
	END Restore;

	PROCEDURE Print (F: Frame; VAR M: Display.DisplayMsg);
		VAR
			Q: Display3.Mask;
			pat: LONGINT;
			x, y, w, h: INTEGER;
			i, j, x0, y0, dx, cx, cy, cw, ch, dw, dh: INTEGER;
			str: ARRAY 2 OF CHAR;
		PROCEDURE P(x: INTEGER): INTEGER;
		BEGIN
			RETURN SHORT(x * Display.Unit DIV Printer.Unit)
		END P;
	BEGIN
		Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, Q);
		x := M.x; y := M.y; w := P(F.W); h := P(F.H);
		Printer3.ReplConst(Q, Display3.textbackC, x, y, w, h, Display.replace);
		x0 := x; y0 := y;
		dw := F.font.maxX-F.font.minX;
		cw := (F.W-1) DIV 32;
		IF cw > dw THEN
			dw := cw
		END;
		x := x+P((F.W-32*dw) DIV 2);
		dh := F.font.height;
		ch := (F.H-1) DIV 8;
		IF ch > dh THEN
			dh := ch
		END;
		y := y+P((F.H-8*dh) DIV 2);
		FOR i := 0 TO 31 DO
			FOR j := 0 TO 7 DO
				Fonts.GetChar(F.font, CHR(i+32*j), dx, cx, cy, cw, ch, pat);
				str[0] := CHR(i+32*j); str[1] := 0X;
				Printer3.String(Q, Display.FG, x+P(i*dw+(dw-cw) DIV 2), y+P((7-j)*dh+(dh-ch) DIV 2), F.font, str, Display.paint)
			END
		END;
		FOR i := 0 TO 32 DO
			Printer3.ReplConst(Q, Display3.black, x+P(i*dw), y, P(1), P(8*dh), Display.replace)
		END;
		FOR j := 0 TO 8 DO
			Printer3.ReplConst(Q, Display3.black, x, y+P(j*dh), P(32*dw), P(1), Display.replace)
		END;
		IF Gadgets.selected IN F.state THEN
			Printer3.FillPattern(Q, Display3.white, Display3.selectpat, x0, y0, x0, y0, w, h, Display.paint)
		END
	END Print;

	PROCEDURE Track(F: Frame; VAR M: Oberon.InputMsg; x, y: INTEGER);
		VAR
			w, h, i, j: INTEGER;
			keysum: SET;
			Q: Display3.Mask;
			Ca: Oberon.CaretMsg;
	BEGIN
		Gadgets.MakeMask(F, x, y, M.dlink, Q);
		w := F.font.maxX-F.font.minX;
		IF ((F.W-1) DIV 32) > w THEN
			w := (F.W-1) DIV 32
		END;
		x := x+(F.W-32*w) DIV 2;
		h := F.font.height;
		IF ((F.H-1) DIV 8) > h THEN
			h := (F.H-1) DIV 8
		END;
		y := y+(F.H-8*h) DIV 2;
		i := (M.X-x) DIV w;
		j := (M.Y-y) DIV h;
		Oberon.RemoveMarks(x+i*w, y+j*h, w+1, h+1);
		Display3.ReplConst(Q, Display.FG, x+i*w, y+j*h, w+1, h+1, Display.invert);
		keysum := M.keys;
		REPEAT
			Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow);
			Oberon.RemoveMarks(x+i*w, y+j*h, w+1, h+1);
			Display3.ReplConst(Q, Display.FG, x+i*w, y+j*h, w+1, h+1, Display.invert);
			i := (M.X-x) DIV w;
			j := (M.Y-y) DIV h;
			IF i < 0 THEN
				i := 0
			ELSIF i > 31 THEN
				i := 31
			END;
			IF j < 0 THEN
				j := 0
			ELSIF j > 7 THEN
				j := 7
			END;
			Oberon.RemoveMarks(x+i*w, y+j*h, w+1, h+1);
			Display3.ReplConst(Q, Display.FG, x+i*w, y+j*h, w+1, h+1, Display.invert);
			keysum := keysum + M.keys
		UNTIL M.keys = {};
		Oberon.RemoveMarks(x+i*w, y+j*h, w+1, h+1);
		Display3.ReplConst(Q, Display.FG, x+i*w, y+j*h, w+1, h+1, Display.invert);
		M.res := 0;
		IF keysum = {middle} THEN
			Ca.id := Oberon.get;
			Ca.car := NIL;
			Ca.F := NIL;
			Ca.text := NIL;
			Ca.pos := 0;
			Ca.res := -1;
			Display.Broadcast(Ca);
			IF Ca.text # NIL THEN
				Texts.SetFont(W, F.font);
				Texts.Write(W, CHR(i+(7-j)*32));
				Texts.Insert(Ca.text, Ca.pos, W.buf);
				Ca.F := Ca.car;
				Ca.id := Oberon.set;
				INC(Ca.pos);
				Display.Broadcast(Ca)
			END
		END
	END Track;

	PROCEDURE CopyFrame(VAR M: Objects.CopyMsg; F, F1: Frame);
	BEGIN
		Gadgets.CopyFrame(M, F, F1);
		F1.font := F.font
	END CopyFrame;

	PROCEDURE Handle*(F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			x, y, w, h: INTEGER;
			Q: Display3.Mask;
			name: ARRAY 32 OF CHAR;
			copy: Frame;
	BEGIN
		WITH F: Frame DO
			IF M IS Display.FrameMsg THEN
				WITH M: Display.FrameMsg DO
     		 	  IF (M.F = NIL) OR (M.F = F) THEN
						x := M.x + F.X;
						y := M.y + F.Y;
						w := F.W;
						h := F.H;
						IF M IS Display.DisplayMsg THEN
							WITH M: Display.DisplayMsg  DO
								IF M.device = Display.screen THEN
									IF (M.id = Display.full) OR (M.F = NIL) THEN
										Gadgets.MakeMask(F, x, y, M.dlink, Q);
										Restore(F, Q, x, y, w, h)
									ELSIF M.id = Display.area THEN
										Gadgets.MakeMask(F, x, y, M.dlink, Q);
										Display3.AdjustMask(Q, x + M.u, y + h - 1 + M.v, M.w, M.h);
										Restore(F, Q, x, y, w, h)
									END
								ELSIF M.device = Display.printer THEN
									Print(F, M)
								END
							END
						ELSIF M IS Oberon.InputMsg THEN
							WITH M: Oberon.InputMsg DO
								IF (M.id = Oberon.track) & Gadgets.InActiveArea(F, M) & (M.keys = {middle}) THEN
									Track(F, M, x, y)
								ELSE
									Gadgets.framehandle(F, M)
								END
							END
						ELSE
							Gadgets.framehandle(F, M)
						END
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "Gen" THEN
							M.class := Objects.String;
							M.s := "ASCIITab.NewFrame";
							M.res := 0
						ELSIF M.name = "Font" THEN
							M.class := Objects.String;
							COPY(F.font.name, M.s);
							M.res := 0
						ELSE
							Gadgets.framehandle(F, M)
						END
					ELSIF M.id = Objects.set THEN
						IF (M.class = Objects.String) & (M.name = "Font") THEN
							F.font := Fonts.This(M.s);
							M.res := 0
						ELSE
							Gadgets.framehandle(F, M)
						END
					ELSIF M.id = Objects.enum THEN
						Gadgets.framehandle(F, M);
						M.Enum("Font");
						M.res := 0
					END
				END
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					IF M.stamp = F.stamp THEN
						M.obj := F.dlink
					ELSE
						NEW(copy);
						F.stamp := M.stamp;
						F.dlink := copy;
						CopyFrame(M, F, copy);
						M.obj := copy
					END
				END
			ELSIF M IS Objects.FileMsg THEN
				WITH M: Objects.FileMsg DO
					Gadgets.framehandle(F, M);
					IF M.id = Objects.store THEN
						Files.WriteString(M.R, F.font.name)
					ELSIF M.id = Objects.load THEN
						Files.ReadString(M.R, name);
						F.font := Fonts.This(name)
					END
				END
			ELSE
				Gadgets.framehandle(F, M)
			END
		END
	END Handle;

	PROCEDURE NewFrame*;
		VAR F: Frame;
	BEGIN
		NEW(F);
		F.font := Fonts.Default;
		F.W := 32*(4+F.font.maxX-F.font.minX)+1;
		F.H := 8*(2+F.font.height)+1;
		F.handle := Handle;
		Objects.NewObj := F
	END NewFrame;

BEGIN
	Texts.OpenWriter(W)
END ASCIITab.Text

Gadgets.Insert ASCIITab.NewFrame ~

System.Free ASCIITab ~

