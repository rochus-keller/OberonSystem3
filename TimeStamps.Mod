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

MODULE TimeStamps;	(** portable *) (* ejz *)
	IMPORT Files, Strings, Display, Display3, Printer, Printer3, Fonts, Objects, Oberon, Gadgets;

	TYPE
		Frame* = POINTER TO FrameDesc;
		FrameDesc* = RECORD (Gadgets.FrameDesc)
			font: Fonts.Font;
			cap: ARRAY 64 OF CHAR;
			col: INTEGER;
			w: INTEGER (* width of gadgets based on display metrics *)
		END;
		RevFrame* = POINTER TO RevFrameDesc;
		RevFrameDesc* = RECORD (FrameDesc)
			revision: LONGINT
		END;

	PROCEDURE Restore(F: Frame; Q: Display3.Mask; x, y, w, h: INTEGER);
	VAR dx: INTEGER;
	BEGIN
		dx := (w - F.w) DIV 2;
		Display3.String(Q, F.col, x + dx, y-F.font.minY, F.font, F.cap, Display.paint);
		Display3.ReplConst(Q, F.col, x + dx, y, F.w, 1, Display.replace);
		IF Gadgets.selected IN F.state THEN
			Display3.FillPattern(Q, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
		END
	END Restore;

	PROCEDURE P(x: LONGINT): INTEGER;
	BEGIN RETURN SHORT((x * Display.Unit + (Printer.Unit-1)) DIV Printer.Unit)
	END P;

	PROCEDURE DR(x: LONGINT): REAL;
	BEGIN RETURN (x * Printer.Unit) / Display.Unit
	END DR;

	PROCEDURE Print(F: Frame; Q: Display3.Mask; x, y: INTEGER);
		VAR w, h, dsr: INTEGER;
	BEGIN
		Printer3.StringSize(F.cap, F.font, w, h, dsr); (* get dsr in printer metrics / ps - 30.5.96 *)
		Printer3.String(Q, F.col, x+(P(F.W)-P(F.w)) DIV 2, y + dsr, F.font, F.cap, Display.paint);
		Printer3.ReplConst(Q, F.col, x, y, P(F.W), 1, Display.replace)
	END Print;

	PROCEDURE Copy*(VAR M: Objects.CopyMsg; from, to: Frame);
	BEGIN
		to.font := from.font; COPY(from.cap, to.cap);
		to.col := from.col; to.w := from.w;
		Gadgets.CopyFrame(M, from, to)
	END Copy;

	PROCEDURE Caption(F: Frame; VAR w, h: INTEGER; newtime: BOOLEAN);
		VAR
			date, time: LONGINT;
			wr, hr: REAL;
			tmp: ARRAY 64 OF CHAR;
			pw, ph, dsr: INTEGER;
	BEGIN
		IF newtime THEN
			IF F IS RevFrame THEN
				WITH F: RevFrame DO
					INC(F.revision);
					Strings.IntToStr(F.revision, F.cap)
				END
			ELSE
				Oberon.GetClock(time, date);
				Strings.DateToStr(date, F.cap);
				Strings.TimeToStr(time, tmp);
				Strings.Append(F.cap, "  ");
				Strings.Append(F.cap, tmp)
			END
		END;
		(* ps - 30.5.96 *)
		Display3.StringSize(F.cap, F.font, w, h, dsr); (* get width based on display metrics *)
		Printer3.StringSize(F.cap, F.font, pw, ph, dsr); (* get size based on printer  metrics *)
		wr := DR(pw); hr := DR(ph);
		IF w < wr THEN w := SHORT(-ENTIER(-wr)) END; F.w := w;
		IF h < hr THEN h := SHORT(-ENTIER(-hr)) END
	END Caption;

	PROCEDURE Modify(F: Frame; w, h: INTEGER);
		VAR M: Display.ModifyMsg;
	BEGIN
		M.F := F; M.res := -1;
		M.id := Display.extend; M.mode := Display.display;
		M.x := 0; M.y := 0;
		M.X := F.X; M.dX := 0; M.Y := F.Y; M.dY := 0;
		M.W := w; M.dW := w-F.W; M.H := h; M.dH := h-F.H;
		Display.Broadcast(M)
	END Modify;

	PROCEDURE Attributes(F: Frame; VAR M: Objects.AttrMsg);
		VAR w, h: INTEGER;
	BEGIN
		IF M.id = Objects.get THEN
			IF M.name = "Gen" THEN
				M.class := Objects.String; M.s := "TimeStamps.New"; M.res:= 0
			ELSIF M.name = "Color" THEN
				M.class := Objects.Int; M.i := F.col; M.res := 0
			ELSIF M.name = "Font" THEN
				M.class := Objects.String; COPY(F.font.name, M.s); M.res:= 0
			ELSIF M.name = "LineupHY" THEN
				M.class := Objects.Int; M.i := -F.font.minY; M.res := 0
			ELSE
				Gadgets.framehandle(F, M)
			END
		ELSIF M.id = Objects.set THEN
			IF (M.class = Objects.Int) & (M.name = "Color") THEN
				F.col := SHORT(M.i); M.res := 0
			ELSIF (M.class = Objects.String) & (M.name = "Font") THEN
				F.font := Fonts.This(M.s); Caption(F, w, h, FALSE);
				Modify(F, w, h); M.res := 0
			ELSE
				Gadgets.framehandle(F, M)
			END
		ELSIF M.id = Objects.enum THEN
			Gadgets.framehandle(F, M);
			M.Enum("Color"); M.Enum("Font");
			M.res := 0
		END
	END Attributes;

	PROCEDURE Handle*(F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			F1: Frame;
			Q: Display3.Mask;
			x, y, w, h: INTEGER;
	BEGIN
		WITH F: Frame DO
			IF M IS Display.FrameMsg THEN
				WITH M: Display.FrameMsg DO
					IF (M.F = NIL) OR (M.F = F) THEN
						x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
						IF M IS Display.DisplayMsg THEN
							WITH M: Display.DisplayMsg DO
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
									Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, Q);
									Print(F, Q, M.x, M.y)
								END
							END
						ELSE
							Gadgets.framehandle(F, M)
						END
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				Attributes(F, M(Objects.AttrMsg))
			ELSIF M IS Objects.FileMsg THEN
				WITH M: Objects.FileMsg DO
					IF M.id = Objects.store THEN
						Caption(F, w, h, TRUE); Modify(F, w, h)
					END;
					Gadgets.framehandle(F, M);
					IF M.id = Objects.store THEN
						Files.WriteInt(M.R, F.col);
						Files.WriteString(M.R, F.font.name);
						Files.WriteString(M.R, F.cap)
					ELSIF M.id = Objects.load THEN
						Files.ReadInt(M.R, F.col);
						NEW(F.font);
						Files.ReadString(M.R, F.font.name);
						F.font := Fonts.This(F.font.name);
						Files.ReadString(M.R, F.cap);
						Caption(F, w, h, FALSE); Modify(F, w, h)
					END
				END
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					IF M.stamp = F.stamp THEN
						M.obj := F.dlink
					ELSE
						NEW(F1);
						F.stamp := M.stamp; F.dlink := F1;
						Copy(M, F, F1); M.obj := F1
					END
				END
			ELSE
				Gadgets.framehandle(F, M)
			END
		END
	END Handle;

	PROCEDURE Init*(F: Frame);
	BEGIN
		INCL(F.state, Gadgets.transparent);
		F.font := Fonts.Default; F.col := Display.FG;
		Caption(F, F.W, F.H, TRUE);
		F.handle := Handle
	END Init;

	PROCEDURE New*;
		VAR F: Frame;
	BEGIN
		NEW(F); Init(F);
		Objects.NewObj := F
	END New;

	PROCEDURE CopyRev*(VAR M: Objects.CopyMsg; from, to: RevFrame);
	BEGIN
		to.revision := from.revision;
		Copy(M, from, to)
	END CopyRev;

	PROCEDURE RevHandle*(F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR F1: RevFrame;
	BEGIN
		WITH F: RevFrame DO
			IF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.class := Objects.String; M.s := "TimeStamps.NewRev"; M.res:= 0
					ELSE
						Handle(F, M)
					END
				END
			ELSIF M IS Objects.FileMsg THEN
				WITH M: Objects.FileMsg DO
					Handle(F, M);
					IF M.id = Objects.store THEN
						Files.WriteLInt(M.R, F.revision)
					ELSIF M.id = Objects.load THEN
						Files.ReadLInt(M.R, F.revision)
					END
				END
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					IF M.stamp = F.stamp THEN
						M.obj := F.dlink
					ELSE
						NEW(F1);
						F.stamp := M.stamp; F.dlink := F1;
						CopyRev(M, F, F1); M.obj := F1
					END
				END
			ELSE
				Handle(F, M)
			END
		END
	END RevHandle;

	PROCEDURE InitRev*(F: RevFrame);
	BEGIN
		F.revision := -1; Init(F);
		F.handle := RevHandle
	END InitRev;

	PROCEDURE NewRev*;
		VAR F: RevFrame;
	BEGIN
		NEW(F); InitRev(F);
		Objects.NewObj := F
	END NewRev;

END TimeStamps.

System.Free TimeStamps ~
Gadgets.Insert TimeStamps.New ~
Gadgets.Insert TimeStamps.NewRev ~
