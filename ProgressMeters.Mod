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

MODULE ProgressMeters;	(** portable *) (* ejz,   *)
	IMPORT Files, Objects, Display, Printer, Fonts, Display3, Printer3, Strings, Gadgets;

	CONST
		CurVer = 0;

	TYPE
		Frame* = POINTER TO FrameDesc;
		FrameDesc* = RECORD (Gadgets.FrameDesc)
			min, max, val, step: LONGINT;
			col: INTEGER;
			marks, labels: BOOLEAN
		END;
		UpdateMsg = RECORD (Display.FrameMsg)
		END;

	PROCEDURE ApplyValue(F: Frame; VAR A: Objects.AttrMsg);
	BEGIN
		IF A.class = Objects.Real THEN
			A.i := ENTIER(A.x)
		ELSIF A.class = Objects.LongReal THEN
			A.i := ENTIER(A.y)
		ELSIF A.class = Objects.String THEN
			Strings.StrToInt(A.s, A.i)
		ELSIF A.class # Objects.Int THEN
			RETURN
		END;
		IF A.i < F.min THEN
			F.val := F.min
		ELSIF A.i > F.max THEN
			F.val := F.max
		ELSE
			F.val := A.i
		END;
		A.res := 0
	END ApplyValue;

	PROCEDURE UpdateValue(F: Frame): BOOLEAN;
		VAR A: Objects.AttrMsg;
	BEGIN
		A.id := Objects.get; A.name := "Field"; A.class := Objects.Inval; A.s := ""; A.res := -1;
		F.handle(F, A);
		IF (A.res >= 0) & (A.s # "") THEN COPY(A.s, A.name) ELSE A.name := "Value" END;
		A.class := Objects.Inval; A.res := -1; F.obj.handle(F.obj, A);
		A.res := -1; ApplyValue(F, A);
		RETURN A.res = 0
	END UpdateValue;

	PROCEDURE Restore(F: Frame; Q: Display3.Mask; x, y, w, h: INTEGER; back: BOOLEAN);
		VAR
			red, xm, ym, wm, hm, xma, diff, fw, fh, dsr: INTEGER;
			mark, range: LONGINT;
			cap: ARRAY 16 OF CHAR;
			horz: BOOLEAN;
	BEGIN
		IF back & (F.obj # NIL) & UpdateValue(F) THEN
		END;
		horz := w >= h;
		range := F.max-F.min;
		xm := x+1;
		ym := y+1;
		IF horz THEN
			wm := w-2;
			IF F.labels THEN
				hm := h-2-Fonts.Default.height;
				Strings.IntToStr(F.min, cap);
				Display3.StringSize(cap, Fonts.Default, fw, fh, dsr);
				INC(xm, fw DIV 2);
				DEC(wm, fw DIV 2);
				Strings.IntToStr(F.max, cap);
				Display3.StringSize(cap, Fonts.Default, fw, fh, dsr);
				DEC(wm, fw DIV 2)
			ELSIF F.marks THEN
				hm := h-2-Fonts.Default.height
			ELSE
				hm := h-2
			END
		ELSE
			hm := h-2;
			IF F.labels THEN
				Strings.IntToStr(F.min, cap);
				Display3.StringSize(cap, Fonts.Default, wm, fh, dsr);
				Strings.IntToStr(F.max, cap);
				Display3.StringSize(cap, Fonts.Default, fw, fh, dsr);
				IF wm > fw THEN
					fw := wm
				END;
				wm := w-4-fw;
				hm := hm-Fonts.Default.height;
				INC(ym, Fonts.Default.height DIV 2)
			ELSIF F.marks THEN
				wm := w-2-Fonts.Default.height
			ELSE
				wm := w-2
			END
		END;
		IF back THEN
			IF F.marks THEN
				mark := F.min;
				IF horz THEN
					xma := xm;
					WHILE mark <= F.max DO
						Display3.ReplConst(Q, Display3.FG, xma, ym+hm+2, 1, Fonts.Default.height DIV 2, Display.replace);
						INC(mark, F.step);
						xma := xm+SHORT(((range DIV 2)+wm*(mark-F.min)) DIV range)-1
					END
				ELSE
					xma := ym;
					WHILE mark <= F.max DO
						Display3.ReplConst(Q, Display3.FG, xm+wm+2, xma, Fonts.Default.height DIV 2, 1, Display.replace);
						INC(mark, F.step);
						xma := ym+SHORT(((range DIV 2)+hm*(mark-F.min)) DIV range)-1
					END
				END
			END;
			IF F.labels THEN
				mark := F.min;
				IF horz THEN
					xma := xm;
					WHILE mark <= F.max DO
						Strings.IntToStr(mark, cap);
						INC(mark, F.step);
						diff := SHORT(((range DIV 2)+wm*(mark-F.min)) DIV range);
						Display3.CenterString(Q, Display3.FG, xma-diff, ym+hm+1, 2*diff, Fonts.Default.height, Fonts.Default, cap, Display.paint);
						xma := xm+diff
					END
				ELSE
					xma := ym;
					WHILE mark <= F.max DO
						Strings.IntToStr(mark, cap);
						INC(mark, F.step);
						diff := SHORT(((range DIV 2)+hm*(mark-F.min)) DIV range);
						Display3.String(Q, Display3.FG, xm+wm+4(*x+w-fw*), xma-dsr, Fonts.Default, cap, Display.paint);
						xma := ym+diff
					END
				END
			END;
			Display3.Rect3D(Q, Display3.bottomC, Display3.topC, xm-1, ym-1, wm+2, hm+2, 1, Display.replace)
		END;
		mark := F.val-F.min;
		IF horz THEN
			red := SHORT(((range DIV 2)+wm*mark) DIV range);
			Display3.ReplConst(Q, F.col, xm, ym, red, hm, Display.replace);
			Display3.ReplConst(Q, Display3.textbackC, xm+red, ym, wm-red, hm, Display.replace)
		ELSE
			red := SHORT(((range DIV 2)+hm*mark) DIV range);
			Display3.ReplConst(Q, F.col, xm, ym, wm, red, Display.replace);
			Display3.ReplConst(Q, Display3.textbackC, xm, ym+red, wm, hm-red, Display.replace)
		END;
		IF Gadgets.selected IN F.state THEN
			Display3.FillPattern(Q, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
		END
	END Restore;
	
	PROCEDURE Print (F: Frame; VAR M: Display.DisplayMsg);
		VAR
			Q: Display3.Mask;
			x, y, w, h, red, xm, ym, wm, hm, xma, diff, fw, fh, dsr: INTEGER;
			mark, range: LONGINT;
			cap: ARRAY 16 OF CHAR;
			horz: BOOLEAN;
		PROCEDURE P(x: INTEGER): INTEGER;
		BEGIN
			RETURN SHORT(x * Display.Unit DIV Printer.Unit)
		END P;
		PROCEDURE D(x: INTEGER): INTEGER;
		BEGIN RETURN SHORT((LONG(x) * Printer.Unit + (Display.Unit DIV 2)) DIV Display.Unit)
		END D;

	BEGIN
		Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, Q);
		w := F.W; h := F.H;
		horz := w >= h; range := F.max-F.min;
		x := M.x; y := M.y;
		xm := x+P(1); ym := y+P(1);
		IF horz THEN
			wm := w-2;
			IF F.labels THEN
				hm := h-2-Fonts.Default.height; Strings.IntToStr(F.min, cap);
				Printer3.StringSize(cap, Fonts.Default, fw, fh, dsr);
				INC(xm, fw DIV 2); DEC(wm, fw DIV 2);
				Strings.IntToStr(F.max, cap);
				Printer3.StringSize(cap, Fonts.Default, fw, fh, dsr);
				DEC(wm, fw DIV 2)
			ELSIF F.marks THEN
				hm := h-2-Fonts.Default.height
			ELSE
				hm := h-2
			END
		ELSE
			hm := h-2;
			IF F.labels THEN
				Strings.IntToStr(F.max, cap);
				Printer3.StringSize(cap, Fonts.Default, fw, fh, dsr);
				wm := w-4-D(fw); hm := hm-Fonts.Default.height;
				INC(ym, P(Fonts.Default.height DIV 2))
			ELSIF F.marks THEN
				wm := w-2-Fonts.Default.height
			ELSE
				wm := w-2
			END
		END;
		IF F.marks THEN
			mark := F.min;
			IF horz THEN
				xma := xm;
				WHILE mark <= F.max DO
					Printer3.ReplConst(Q, Display3.FG, xma, ym+P(hm+2), P(1), P(Fonts.Default.height DIV 2), Display.replace);
					INC(mark, F.step);
					xma := xm+P(SHORT(((range DIV 2)+wm*(mark-F.min)) DIV range)-1)
				END
			ELSE
				xma := ym;
				WHILE mark <= F.max DO
					Printer3.ReplConst(Q, Display3.FG, xm+P(wm+2), xma, P(Fonts.Default.height DIV 2), P(1), Display.replace);
					INC(mark, F.step);
					xma := ym+P(SHORT(((range DIV 2)+hm*(mark-F.min)) DIV range)-1)
				END
			END
		END;
		IF F.labels THEN
			mark := F.min;
			IF horz THEN
				xma := xm;
				WHILE mark <= F.max DO
					Strings.IntToStr(mark, cap);
					INC(mark, F.step);
					diff := SHORT(((range DIV 2)+wm*(mark-F.min)) DIV range);
					Printer3.CenterString(Q, Display3.FG, xma-P(diff), ym+P(hm+1), P(2*diff), P(Fonts.Default.height), Fonts.Default, cap, Display.paint);
					xma := xm+P(diff)
				END
			ELSE
				xma := ym;
				WHILE mark <= F.max DO
					Strings.IntToStr(mark, cap);
					INC(mark, F.step);
					diff := SHORT(((range DIV 2)+hm*(mark-F.min)) DIV range);
					Printer3.String(Q, Display3.FG, xm+P(wm+4), xma-dsr, Fonts.Default, cap, Display.paint);
					xma := ym+P(diff)
				END
			END
		END;
		Printer3.Rect3D(Q, Display3.bottomC, Display3.topC, xm-P(1), ym-P(1), P(wm+2),P( hm+2), 1, Display.replace);
		mark := F.val-F.min;
		IF horz THEN
			red := SHORT(((range DIV 2)+wm*mark) DIV range);
			Printer3.ReplConst(Q, F.col, xm, ym, P(red), P(hm), Display.replace);
			Printer3.ReplConst(Q, Display3.textbackC, xm+P(red), ym, P(wm-red), P(hm), Display.replace)
		ELSE
			red := SHORT(((range DIV 2)+hm*mark) DIV range);
			Printer3.ReplConst(Q, F.col, xm, ym, P(wm), P(red), Display.replace);
			Printer3.ReplConst(Q, Display3.textbackC, xm, ym+P(red), P(wm), P(hm-red), Display.replace)
		END
	END Print;

	PROCEDURE CopyFrame*(VAR C: Objects.CopyMsg; F, F1: Frame);
	BEGIN
		Gadgets.CopyFrame(C, F, F1);
		F1.min := F.min;
		F1.max := F.max;
		F1.val := F.val;
		F1.step := F.step;
		F1.col := F.col;
		F1.marks := F.marks;
		F1.labels := F.labels
	END CopyFrame;

	PROCEDURE FrameHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			x, y, w, h: INTEGER;
			F1: Frame; 
			Q: Display3.Mask;
			U: UpdateMsg;
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
							WITH M: Display.DisplayMsg DO
								IF M.device = Display.screen THEN
									IF (M.id = Display.full) OR (M.F = NIL) THEN
										Gadgets.MakeMask(F, x, y, M.dlink, Q);
										Restore(F, Q, x, y, w, h, TRUE)
									ELSIF M.id = Display.area THEN
										Gadgets.MakeMask(F, x, y, M.dlink, Q);
										Display3.AdjustMask(Q, x + M.u, y + h - 1 + M.v, M.w, M.h);
										Restore(F, Q, x, y, w, h, TRUE)
									END
								ELSIF M.device = Display.printer THEN Print(F, M)
								END
							END
						ELSIF M IS Gadgets.UpdateMsg THEN
							WITH M: Gadgets.UpdateMsg DO
								IF (M.obj = F.obj) & UpdateValue(F) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, Q);
									Restore(F, Q, x, y, w, h, FALSE)
								ELSIF M.obj = F THEN
									Gadgets.MakeMask(F, x, y, M.dlink, Q);
									Restore(F, Q, x, y, w, h, FALSE)
								END
							END
						ELSIF M IS UpdateMsg THEN
							WITH M: UpdateMsg DO
								Gadgets.MakeMask(F, x, y, M.dlink, Q);
								Restore(F, Q, x, y, w, h, FALSE)
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
							M.s := "ProgressMeters.NewFrame";
							M.res := 0
						ELSIF M.name = "Value" THEN
							M.class := Objects.Int;
							M.i := F.val;
							M.res := 0
						ELSIF M.name = "Min" THEN
							M.class := Objects.Int;
							M.i := F.min;
							M.res := 0
						ELSIF M.name = "Max" THEN
							M.class := Objects.Int;
							M.i := F.max;
							M.res := 0
						ELSIF M.name = "Color" THEN
							M.class := Objects.Int;
							M.i := F.col;
							M.res := 0
						ELSIF M.name = "Step" THEN
							M.class := Objects.Int;
							M.i := F.step;
							M.res := 0
						ELSIF M.name = "Marks" THEN
							M.class := Objects.Bool;
							M.b := F.marks;
							M.res := 0
						ELSIF M.name = "Labels" THEN
							M.class := Objects.Bool;
							M.b := F.labels;
							M.res := 0
						ELSIF M.name = "Field" THEN
							Gadgets.framehandle(F, M);
							IF M.res < 0 THEN M.class := Objects.String; M.s := ""; M.res := 0 END
						ELSE
							Gadgets.framehandle(F, M)
						END
					ELSIF M.id = Objects.set THEN
						IF M.name = "Value" THEN
							ApplyValue(F, M);
							U.F := F;
							Display.Broadcast(U)
						ELSIF M.class = Objects.Int THEN
							IF (M.name = "Min") & (M.i < F.max) THEN
								F.min := M.i;
								M.res := 0
							ELSIF (M.name = "Max") & (M.i > F.min) THEN
								F.max := M.i;
								M.res := 0
							ELSIF (M.name = "Step") & (M.i > 0) THEN
								F.step := M.i;
								M.res := 0
							ELSIF M.name = "Color" THEN
								F.col := SHORT(M.i);
								M.res := 0
							ELSE
								Gadgets.framehandle(F, M)
							END
						ELSIF M.class = Objects.Bool THEN
							IF M.name = "Marks" THEN
								F.marks := M.b;
								M.res := 0
							ELSIF M.name = "Labels" THEN
								F.labels := M.b;
								M.res := 0
							ELSE
								Gadgets.framehandle(F, M)
							END
						ELSE
							Gadgets.framehandle(F, M)
						END
					ELSIF M.id = Objects.enum THEN
						Gadgets.framehandle(F, M);
						M.Enum("Value");
						M.Enum("Min");
						M.Enum("Max");
						M.Enum("Color");
						M.Enum("Step");
						M.Enum("Marks");
						M.Enum("Labels");
						M.Enum("Field");
						M.res := 0
					END
				END
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					IF M.stamp = F.stamp THEN
						M.obj := F.dlink
					ELSE
						NEW(F1);
						F.stamp := M.stamp;
						F.dlink := F1;
						CopyFrame(M, F, F1);
						M.obj := F1
					END
				END
			ELSIF M IS Objects.LinkMsg THEN
				WITH M: Objects.LinkMsg DO
					IF M.id = Objects.get THEN
						IF (M.name = "Value") OR (M.name = "Model") THEN
							M.obj := F.obj; M.res := 0
						ELSE
							Gadgets.framehandle(F, M)
						END
					ELSIF M.id = Objects.set THEN
						IF (M.name = "Value") OR (M.name = "Model") THEN
							F.obj := M.obj;
							IF UpdateValue(F) THEN
								M.res := 0
							END
						ELSE
							Gadgets.framehandle(F, M)
						END
					ELSIF M.id = Objects.enum THEN
						Gadgets.framehandle(F, M); M.Enum("Value"); M.res := 0
					END
				END
			ELSIF M IS Objects.FileMsg THEN
				WITH M:Objects.FileMsg DO
					Gadgets.framehandle(F, M);
					IF M.id = Objects.store THEN
						Files.WriteInt(M.R, CurVer);
						Files.WriteLInt(M.R, F.min);
						Files.WriteLInt(M.R, F.max);
						Files.WriteLInt(M.R, F.val);
						Files.WriteLInt(M.R, F.step);
						Files.WriteInt(M.R, F.col);
						Files.WriteBool(M.R, F.marks);
						Files.WriteBool(M.R, F.labels)
					ELSIF M.id = Objects.load THEN
						Files.ReadInt(M.R, x);
						IF x # CurVer THEN
							HALT(99)
						END;
						Files.ReadLInt(M.R, F.min);
						Files.ReadLInt(M.R, F.max);
						Files.ReadLInt(M.R, F.val);
						Files.ReadLInt(M.R, F.step);
						Files.ReadInt(M.R, F.col);
						Files.ReadBool(M.R, F.marks);
						Files.ReadBool(M.R, F.labels)
					END
				END
			ELSE
				Gadgets.framehandle(F, M)
			END
		END
	END FrameHandler;

	PROCEDURE InitFrame*(F: Frame);
	BEGIN
		F.handle := FrameHandler;
		INCL(F.state, Gadgets.transparent);
		F.obj := NIL;
		F.min := 0;
		F.max := 100;
		F.step := 20;
		F.H := 8+Fonts.Default.height;
		F.W := SHORT(2+2*(F.max-F.min));
		F.val := F.min;
		F.col := Display3.red;
		F.marks := TRUE;
		F.labels := TRUE
	END InitFrame;

	PROCEDURE NewFrame*;
		VAR F: Frame;
	BEGIN
		NEW(F);
		InitFrame(F);
		Objects.NewObj := F
	END NewFrame;

END ProgressMeters.

System.Free ProgressMeters ~

Gadgets.Insert ProgressMeters.NewFrame ~
