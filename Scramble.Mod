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

MODULE Scramble;	(** portable *) (* Copyright (C) 1995 by Emil J. Zeller *)
	IMPORT RandomNumbers, Files, Objects, Display, Fonts, Texts, Pictures, Display3, Effects, Strings, Gadgets, Oberon, Documents, Desktops;
	(* Scramble for Oberon Version 1.0
		Disclaimer
			Permission to use, copy, modify and distribute this software and its documentation for any purpose is hereby granted
			without fee, provided that the above copyright notice appear in all copies and that both that copyright notice and this
			permission notice appear in supporting documentation *)

	CONST
		Border = 1;
		middle = 1;
		left = 2;
		MaxN= 6;
		MaxM = 6;
		Left = CHR(196);
		Right = CHR(195);
		Up = CHR(193);
		Down = CHR(194);
		CurVer = 0;
		PictMenu = "Scramble.Scramble[Start] Scramble.Num[Pict] Desktops.StoreDoc[Store]";
		NumMenu = "Scramble.Scramble[Start] Scramble.Num[Num] Desktops.StoreDoc[Store]";

	TYPE
		Frame* = POINTER TO FrameDesc;
		FrameDesc* = RECORD (Gadgets.FrameDesc)
			pict: Pictures.Picture;
			n, m: INTEGER;
			arrange: ARRAY MaxN, MaxM OF RECORD x, y: INTEGER END;
			empty: RECORD x, y: INTEGER END;
			focus, done, num: BOOLEAN
		END;
		UpdateMsg = RECORD (Display.FrameMsg)
			i0, i1, j0, j1: INTEGER
		END;

	VAR
		W: Texts.Writer;

	PROCEDURE CalcSize(F: Frame; x, y: INTEGER; VAR xo, yo, dx, dy: INTEGER);
	BEGIN
		dx := (F.W-2*Border) DIV F.n;
		IF ~F.num & (F.n*dx > F.pict.width) THEN
			dx := F.pict.width DIV F.n
		END;
		xo := x+Border+(F.W-2*Border-F.n*dx) DIV 2;
		dy := (F.H-2*Border) DIV F.m;
		IF ~F.num & (F.m*dy > F.pict.height) THEN
			dy := F.pict.height DIV F.m
		END;
		yo := y+Border+(F.H-2*Border-F.m*dy) DIV 2
	END CalcSize;

	PROCEDURE DrawRect(F: Frame; Q: Display3.Mask; i0, i1, j0, j1, xo, yo, dx, dy: INTEGER);
		VAR
			i, j: INTEGER;
			num: ARRAY 4 OF CHAR;
	BEGIN
		FOR i := i0 TO i1 DO
			FOR j := j0 TO j1 DO
				IF F.done OR (i # F.empty.x) OR (j # F.empty.y) THEN
					IF F.num THEN
						Display3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.textbackC, xo+i*dx, yo+(F.m-1-j)*dy, dx, dy, 1, Display.replace);
						Strings.IntToStr(F.arrange[i, j].x+F.arrange[i, j].y*F.n+1, num);
						Display3.CenterString(Q, Display3.black, xo+i*dx, yo+(F.m-1-j)*dy, dx, dy, Fonts.Default, num, Display.paint)
					ELSE
						Display3.Pict(Q, F.pict, F.arrange[i, j].x*dx, (F.m-1-F.arrange[i, j].y)*dy, dx-2, dy-2, xo+i*dx+1, yo+(F.m-1-j)*dy+1, Display.replace);
						Display3.Rect3D(Q, Display3.topC, Display3.bottomC, xo+i*dx, yo+(F.m-1-j)*dy, dx, dy, 1, Display.replace)
					END
				ELSIF F.focus THEN
					Display3.ReplConst(Q, Display3.red, xo+i*dx, yo+(F.m-1-j)*dy, dx, dy, Display.replace)
				ELSE
					Display3.ReplConst(Q, Display3.white, xo+i*dx, yo+(F.m-1-j)*dy, dx, dy, Display.replace)
				END
			END
		END	
	END DrawRect;

	PROCEDURE Restore(F: Frame; Q: Display3.Mask; x, y, w, h: INTEGER);
		VAR xo, yo, dx, dy, i, j, d: INTEGER;
	BEGIN
		CalcSize(F, x, y, xo, yo, dx, dy);
		Display3.ReplConst(Q, Display3.textbackC, x+Border, y+Border, F.W-2*Border, yo-y-Border, Display.replace);
		Display3.ReplConst(Q, Display3.textbackC, x+Border, yo+F.m*dy, F.W-2*Border, yo-y-Border+1, Display.replace);
		Display3.ReplConst(Q, Display3.textbackC, x+Border, y+Border, xo-x-Border, F.H-2*Border, Display.replace);
		Display3.ReplConst(Q, Display3.textbackC, xo+F.n*dx, y+Border, xo-x-Border+1, F.H-2*Border, Display.replace);
		Display3.Rect3D(Q, Display3.topC, Display3.bottomC, x, y, w, h, Border, Display.replace);
		DrawRect(F, Q, 0, F.n-1, 0, F.m-1, xo, yo, dx, dy);
		IF F.done THEN
			Display3.StringSize("D O N E", Fonts.Default, i, j, d);
			Display3.ReplConst(Q, Display3.red, x+(w-i) DIV 2, y+(h-j) DIV 2, i, j, Display.replace);
			Display3.CenterString(Q, Display3.black, xo, yo, F.n*dx, F.m*dy, Fonts.Default, "D O N E", Display.paint)
		END;
		IF Gadgets.selected IN F.state THEN
			Display3.FillPattern(Q, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
		END
	END Restore;

	PROCEDURE Update(F: Frame; Q: Display3.Mask; x, y, w, h: INTEGER; VAR U: UpdateMsg);
		VAR xo, yo, dx, dy: INTEGER;
	BEGIN
		IF ~F.done THEN
			CalcSize(F, x, y, xo, yo, dx, dy);
			DrawRect(F, Q, U.i0, U.i1, U.j0, U.j1, xo, yo, dx, dy)
		ELSE
			F.focus := FALSE;
			Restore(F, Q, x, y, w, h)
		END;
		IF Gadgets.selected IN F.state THEN
			Display3.FillPattern(Q, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
		END
	END Update;

	PROCEDURE CheckDone(F: Frame);
		VAR i, j: INTEGER;
	BEGIN
		F.done := TRUE;
		FOR i := 0 TO F.n-1 DO
			FOR j := 0 TO F.m-1 DO
				IF ((i # F.empty.x) OR (j # F.empty.y)) & ((i # F.arrange[i, j].x) OR (j # F.arrange[i, j].y)) THEN
					F.done := FALSE;
					RETURN
				 END 
			END
		END
	END CheckDone;

	PROCEDURE Consume(F: Frame; VAR M: Oberon.InputMsg);
		VAR U: UpdateMsg;
	BEGIN
		U.i0 := F.empty.x;
		U.j0 := F.empty.y;
		IF (M.ch = Left) & (F.empty.x > 0) THEN
			F.arrange[F.empty.x, F.empty.y] := F.arrange[F.empty.x-1, F.empty.y];
			F.arrange[F.empty.x-1, F.empty.y].x := F.n-1;
			F.arrange[F.empty.x-1, F.empty.y].y := F.m-1;
			DEC(F.empty.x)
		ELSIF (M.ch = Right) & (F.empty.x < (F.n-1)) THEN
			F.arrange[F.empty.x, F.empty.y] := F.arrange[F.empty.x+1, F.empty.y];
			F.arrange[F.empty.x+1, F.empty.y].x := F.n-1;
			F.arrange[F.empty.x+1, F.empty.y].y := F.m-1;
			INC(F.empty.x)
		ELSIF (M.ch = Down) & (F.empty.y < (F.m-1)) THEN
			F.arrange[F.empty.x, F.empty.y] := F.arrange[F.empty.x, F.empty.y+1];
			F.arrange[F.empty.x, F.empty.y+1].x := F.n-1;
			F.arrange[F.empty.x, F.empty.y+1].y := F.m-1;
			INC(F.empty.y)
		ELSIF (M.ch = Up) & (F.empty.y > 0) THEN
			F.arrange[F.empty.x, F.empty.y] := F.arrange[F.empty.x, F.empty.y-1];
			F.arrange[F.empty.x, F.empty.y-1].x := F.n-1;
			F.arrange[F.empty.x, F.empty.y-1].y := F.m-1;
			DEC(F.empty.y)
		ELSE
			RETURN
		END;
		CheckDone(F);
		U.F := F;
		IF F.empty.x >= U.i0 THEN
			U.i1 := F.empty.x
		ELSE
			U.i1 := U.i0;
			U.i0 := F.empty.x
		END;
		IF F.empty.y >= U.j0 THEN
			U.j1 := F.empty.y
		ELSE
			U.j1 := U.j0;
			U.j0 := F.empty.y
		END;
		Display.Broadcast(U);
		M.res := 0
	END Consume;

	PROCEDURE Track(F: Frame; x, y: INTEGER; VAR M: Oberon.InputMsg);
		VAR
			U: UpdateMsg;
			keysum: SET;
			i, j, xo, yo, dx, dy: INTEGER;
			inside: BOOLEAN;
			Q: Display3.Mask;
		PROCEDURE Drop();
		BEGIN
			F.arrange[i, j].x := F.n-1;
			F.arrange[i, j].y := F.m-1;
			F.empty.x := i;
			F.empty.y := j;
			CheckDone(F);
			U.F := F;
			Display.Broadcast(U)
		END Drop;
	BEGIN
		keysum := M.keys;
		IF ~F.done & (M.keys = {left}) THEN
			REPEAT
				Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow);
				keysum := keysum + M.keys
			UNTIL M.keys = {};
			IF ~F.focus THEN
				Oberon.Defocus();
				F.focus := TRUE;
				Gadgets.Update(F)
			END
		ELSIF ~F.done & (M.keys = {middle}) THEN
			Gadgets.MakeMask(F, x, y, M.dlink, Q);
			CalcSize(F, x, y, xo, yo, dx, dy);
			i := (M.X-xo) DIV dx;
			j := F.m-((M.Y-yo) DIV dy)-1;
			IF ((i = F.empty.x) OR (j = F.empty.y)) & ((i # F.empty.x) OR (j # F.empty.y)) THEN
				Oberon.RemoveMarks(xo+i*dx, yo+(F.m-1-j)*dy, dx, dy);
				Display3.Rect3D(Q, Display3.bottomC, Display3.topC, xo+i*dx, yo+(F.m-1-j)*dy, dx, dy, 1, Display.replace);
				inside := TRUE
			ELSE
				inside := FALSE
			END;
			REPEAT
				IF (M.X > xo) & (M.X < (xo+F.n*dx)) & (M.Y > yo) & (M.Y < (yo+F.m*dy)) THEN
					Oberon.RemoveMarks(xo+i*dx, yo+(F.m-1-j)*dy, dx, dy);
					IF inside THEN
						Display3.Rect3D(Q, Display3.topC, Display3.bottomC, xo+i*dx, yo+(F.m-1-j)*dy, dx, dy, 1, Display.replace)
					END;
					i := (M.X-xo) DIV dx;
					j := F.m-((M.Y-yo) DIV dy)-1;
					IF ((i = F.empty.x) OR (j = F.empty.y)) & ((i # F.empty.x) OR (j # F.empty.y)) THEN
						Display3.Rect3D(Q, Display3.bottomC, Display3.topC, xo+i*dx, yo+(F.m-1-j)*dy, dx, dy, 1, Display.replace);
						inside := TRUE
					ELSE
						inside := FALSE
					END
				ELSE
					inside := FALSE
				END;
				Effects.TrackMouse(M.keys, M.X, M.Y, Effects.FlatHand);
				keysum := keysum + M.keys
			UNTIL M.keys = {};
			Oberon.RemoveMarks(xo+i*dx, yo+(F.m-1-j)*dy, dx, dy);
			IF inside THEN
				Display3.Rect3D(Q, Display3.topC, Display3.bottomC, xo+i*dx, yo+(F.m-1-j)*dy, dx, dy, 1, Display.replace)
			END;
			IF inside & (keysum = {middle}) THEN
				dx := ABS(F.empty.x-i);
				dy := ABS(F.empty.y-j);
				IF dx = 0 THEN
					U.i0 := i;
					U.i1 := i;
					IF F.empty.y < j THEN
						U.j0 := F.empty.y;
						U.j1 := j;
						FOR yo := F.empty.y TO j-1 DO
							F.arrange[i, yo] := F.arrange[i, yo+1]
						END
					ELSIF F.empty.y > j THEN
						U.j0 := j;
						U.j1 := F.empty.y;
						FOR yo := F.empty.y TO j+1 BY -1 DO
							F.arrange[i, yo] := F.arrange[i, yo-1]
						END
					END;
					Drop()
				ELSIF dy = 0  THEN
					U.j0 := j;
					U.j1 := j;
					IF F.empty.x < i THEN
						U.i0 := F.empty.x;
						U.i1 := i;
						FOR xo := F.empty.x TO i-1 DO
							F.arrange[xo, j] := F.arrange[xo+1, j]
						END
					ELSIF F.empty.x > i THEN
						U.i0 := i;
						U.i1 := F.empty.x;
						FOR xo := F.empty.x TO i+1 BY -1 DO
							F.arrange[xo, j] := F.arrange[xo-1, j]
						END
					END;
					Drop()
				END
			END;
			M.res := 0
		ELSE
			Gadgets.framehandle(F, M)
		END
	END Track;

	PROCEDURE Arrange(F: Frame; scramble: BOOLEAN);
		VAR i, j, n: INTEGER;
	BEGIN
		FOR i := 0 TO MaxN-1 DO
			FOR j := 0 TO MaxM-1 DO
				F.arrange[i, j].x := i;
				F.arrange[i, j].y := j
			END
		END;
		F.empty.x := F.n-1;
		F.empty.y := F.m-1;
		IF scramble THEN
			REPEAT
				FOR n := 0 TO (F.n+F.m)*F.n*F.m DO
					CASE ENTIER(4*RandomNumbers.Uniform()) OF
						0: IF F.empty.x > 0 THEN
								F.arrange[F.empty.x, F.empty.y] := F.arrange[F.empty.x-1, F.empty.y];
								DEC(F.empty.x)
							END;
						|1: IF F.empty.x < (F.n-1) THEN
								F.arrange[F.empty.x, F.empty.y] := F.arrange[F.empty.x+1, F.empty.y];
								INC(F.empty.x)
							END
						|2: IF F.empty.y > 0 THEN
								F.arrange[F.empty.x, F.empty.y] := F.arrange[F.empty.x, F.empty.y-1];
								DEC(F.empty.y)
							END
						|3: IF F.empty.y < (F.m-1) THEN
								F.arrange[F.empty.x, F.empty.y] := F.arrange[F.empty.x, F.empty.y+1];
								INC(F.empty.y)
							END
					END
				END;
				CheckDone(F)
			UNTIL ~F.done
		ELSE
			F.focus := FALSE
		END;
		F.done := ~scramble;
		Gadgets.Update(F)
	END Arrange;

	PROCEDURE CopyFrame(VAR M: Objects.CopyMsg; F, F1: Frame);
		VAR i, j: INTEGER;
	BEGIN
		Gadgets.CopyFrame(M, F, F1);
		F1.n := F.n;
		F1.m := F.m;
		FOR i := 0 TO MaxN-1 DO
			FOR j := 0 TO MaxM-1 DO
				F1.arrange[i, j] := F.arrange[i, j]
			END
		END;
		F1.empty := F.empty;
		F1.pict := F1.obj(Pictures.Picture);
		F1.num := F.num;
		F1.done := F.done;
		F1.focus := FALSE
	END CopyFrame;

	PROCEDURE Handle*(F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			x, y, w, h: INTEGER;
			Q: Display3.Mask;
			copy: Frame;
	BEGIN
		WITH F: Frame DO
			IF M IS Display.FrameMsg THEN
				WITH M: Display.FrameMsg DO
     		 	  IF (M.F = NIL) OR (M.F = F) THEN
						x := M.x + F.X; y := M.y + F.Y;
						w := F.W; h := F.H;
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
								ELSIF M.device = Display.printer THEN Gadgets.framehandle(F, M)
								END
							END
						ELSIF M IS UpdateMsg THEN
							WITH M: UpdateMsg DO
								Gadgets.MakeMask(F, x, y, M.dlink, Q);
								Update(F, Q, x, y, w, h, M)
							END
						ELSIF M IS Oberon.InputMsg THEN
							WITH M: Oberon.InputMsg DO
								IF M.id = Oberon.track THEN
									IF Gadgets.InActiveArea(F, M) THEN
										Track(F, x, y, M)
									ELSE
										Gadgets.framehandle(F, M)
									END
								ELSIF F.focus & (M.id = Oberon.consume) THEN
									Consume(F, M)
								ELSE
									Gadgets.framehandle(F, M)
								END
							END
						ELSIF M IS Oberon.ControlMsg THEN
							WITH  M: Oberon.ControlMsg DO
								IF ((M.id = Oberon.defocus) OR (M.id = Oberon.neutralize)) THEN
									IF F.focus THEN
										F.focus := FALSE;
										Gadgets.Update(F)
									END
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
							M.s := "Scramble.NewFrame";
							M.res := 0
						ELSIF (M.name[0] = "N") & (M.name[1] = 0X) THEN
							M.class := Objects.Int;
							M.i := F.n;
							M.res := 0
						ELSIF (M.name[0] = "M") & (M.name[1] = 0X) THEN
							M.class := Objects.Int;
							M.i := F.m;
							M.res := 0
						ELSIF M.name = "Pict" THEN
							M.class := Objects.Bool;
							M.b := ~F.num;
							M.res := 0
						ELSE
							Gadgets.framehandle(F, M)
						END
					ELSIF M.id = Objects.set THEN
						IF (M.class = Objects.Int) & (M.i > 1) THEN
							IF (M.name[0] = "N") & (M.name[1] = 0X) & (M.i # F.n) & (M.i <= MaxN) THEN
								F.n := SHORT(M.i);
								Arrange(F, FALSE);
								M.res := 0
							ELSIF (M.name[0] = "M") & (M.name[1] = 0X) & (M.i # F.m) & (M.i <= MaxM) THEN
								F.m := SHORT(M.i);
								Arrange(F, FALSE);
								M.res := 0
							ELSE
								Gadgets.framehandle(F, M)
							END
						ELSIF (M.class = Objects.Bool) & (M.name = "Pict") THEN
							F.num := ~M.b;
							M.res := 0;
							Gadgets.Update(F)
						ELSE
							Gadgets.framehandle(F, M)
						END
					ELSIF M.id = Objects.enum THEN
						Gadgets.framehandle(F, M);
						M.s[0] := "N";
						M.s[1] := 0X;
						M.Enum(M.s);
						M.s[0] := "M";
						M.s[1] := 0X;
						M.Enum(M.s);
						M.Enum("Pict");
						M.res := 0
					END
				END
			ELSIF M IS Objects.LinkMsg THEN
				WITH M: Objects.LinkMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "Picture" THEN
							M.obj := F.pict;
							M.res := 0
						ELSE
							Gadgets.framehandle(F, M)
						END
					ELSIF M.id = Objects.set THEN
						IF (M.name = "Picture") & (M.obj # NIL) & (M.obj IS Pictures.Picture) THEN
							F.obj := M.obj;
							F.pict := F.obj(Pictures.Picture);
							M.res := 0;
							Gadgets.Update(F)
						ELSE
							Gadgets.framehandle(F, M)
						END
					ELSIF M.id = Objects.enum THEN
						Gadgets.framehandle(F, M);
						M.Enum("Picture");
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
						Files.WriteInt(M.R, CurVer);
						Files.WriteInt(M.R, F.n);
						Files.WriteInt(M.R, F.m);
						Files.WriteInt(M.R, F.empty.x);
						Files.WriteInt(M.R, F.empty.y);
						Files.WriteBool(M.R, F.done);
						FOR x := 0 TO F.n-1 DO
							FOR y := 0 TO F.m-1 DO
								Files.WriteInt(M.R, F.arrange[x, y].x);
								Files.WriteInt(M.R, F.arrange[x, y].y)
							END
						END;
						Files.WriteBool(M.R, F.num)
					ELSIF M.id = Objects.load THEN
						Files.ReadInt(M.R, x);
						IF x # CurVer THEN
							HALT(99)
						END;
						F.pict := F.obj(Pictures.Picture);
						Files.ReadInt(M.R, F.n);
						Files.ReadInt(M.R, F.m);
						Files.ReadInt(M.R, F.empty.x);
						Files.ReadInt(M.R, F.empty.y);
						Files.ReadBool(M.R, F.done);
						FOR x := 0 TO F.n-1 DO
							FOR y := 0 TO F.m-1 DO
								Files.ReadInt(M.R, F.arrange[x, y].x);
								Files.ReadInt(M.R, F.arrange[x, y].y)
							END
						END;
						Files.ReadBool(M.R, F.num)
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
		F.focus := FALSE; F.done := TRUE; F.num := FALSE;
		F.n := 4; F.m := 4;
		Arrange(F, FALSE);
		NEW(F.pict); Pictures.Create(F.pict, 0, 0, 8);
		Pictures.Open(F.pict, "Default.Pict", TRUE); F.obj := F.pict;
		F.W := F.pict.width; F.H := F.pict.height;
		F.handle := Handle; Objects.NewObj := F
	END NewFrame;

	PROCEDURE *LoadDoc(D: Documents.Document);
		VAR
			F: Files.File;
			R: Files.Rider;
			main: Frame;
			tag, x, y, w, h, ref: INTEGER;
			gen: ARRAY 64 OF CHAR;
			lib: Objects.Library;
			len: LONGINT;
			obj: Objects.Object;
	BEGIN
		main := NIL;
		F := Files.Old(D.name);
		IF F # NIL THEN
			Files.Set(R, F, 0);
			Files.ReadInt(R, tag);
			IF tag = Documents.Id THEN
				Files.ReadString(R, gen);
				Files.ReadInt(R, x);
				Files.ReadInt(R, y);
				Files.ReadInt(R, w);
				Files.ReadInt(R, h);
				Files.ReadInt(R, ref);
				NEW(lib);
				Objects.OpenLibrary(lib);
				Objects.LoadLibrary(lib, F, Files.Pos(R)+1, len);
				lib.GetObj(lib, ref, obj);
				main := obj(Frame)
			END;
			Files.Close(F)
		END;
		IF main = NIL THEN
			D.name := "Scramble.Doc";
			NewFrame();
			main := Objects.NewObj(Frame);
			w := main.W;
			h := main.H
		END;
		D.W := w;
		D.H := h;
		Documents.Init(D, main)
	END LoadDoc;

	PROCEDURE *StoreDoc(D: Documents.Document);
		VAR
			F: Files.File;
			R: Files.Rider;
			B: Objects.BindMsg;
			len: LONGINT;
	BEGIN
		Texts.WriteString(W, "Store ");
		Texts.Append(Oberon.Log, W.buf);
		IF D.name # "" THEN
			Texts.Write(W, 22X);
			Texts.WriteString(W, D.name);
			Texts.Write(W, 22X);
			F := Files.New(D.name);
			Files.Set(R, F, 0);
			Files.WriteInt(R, Documents.Id);
			Files.WriteString(R, "Scramble.NewDoc");
			Files.WriteInt(R, D.X);
			Files.WriteInt(R, D.Y);
			Files.WriteInt(R, D.W);
			Files.WriteInt(R, D.H);
			NEW(B.lib);
			Objects.OpenLibrary(B.lib);
			D.dsc.handle(D.dsc, B);
			Files.WriteInt(R, D.dsc.ref);
			Objects.StoreLibrary(B.lib, F, Files.Pos(R), len);
			Files.Register(F);
			Files.Close(F)
		ELSE
			Texts.WriteString(W, "[Untitled document]")
		END;
		Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf)
	END StoreDoc;

	PROCEDURE DocHandler*(D: Objects.Object; VAR M: Objects.ObjMsg);
	BEGIN
		WITH D: Documents.Document DO
			IF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "Gen" THEN
							M.class := Objects.String; M.s := "Scramble.NewDoc"; M.res := 0
						ELSE
							Documents.Handler(D, M)
						END
					ELSE
						Documents.Handler(D, M)
					END
				END
			ELSIF M IS Objects.LinkMsg THEN
				WITH M: Objects.LinkMsg DO
					IF (M.id = Objects.get) & ((M.name = "DeskMenu") OR (M.name = "SystemMenu") OR (M.name = "UserMenu")) THEN
						IF D.dsc(Frame).num THEN
							M.obj := Desktops.NewMenu(PictMenu)
						ELSE
							M.obj := Desktops.NewMenu(NumMenu)
						END;
						M.res := 0
					ELSE Documents.Handler(D, M)
					END
				END
			ELSE
				Documents.Handler(D, M)
			END
		END
	END DocHandler;

	PROCEDURE NewDoc*;
		VAR D: Documents.Document;
	BEGIN
		NEW(D);
		D.Load := LoadDoc;
		D.Store := StoreDoc;
		D.handle := DocHandler;
		Objects.NewObj := D
	END NewDoc;

	PROCEDURE Scramble*;
		VAR
			doc: Documents.Document;
			F: Frame;
	BEGIN
		doc := Desktops.CurDoc(Gadgets.context);
		IF (doc # NIL) & (doc.dsc # NIL) & (doc.dsc IS Frame) THEN
			F := doc.dsc(Frame);
			Arrange(F, TRUE);
			Gadgets.Update(F)
		END
	END Scramble;

	PROCEDURE Num*;
		VAR
			doc: Documents.Document;
			F: Frame;
			A: Objects.AttrMsg;
	BEGIN
		doc := Desktops.CurDoc(Gadgets.context);
		IF (doc # NIL) & (doc.dsc # NIL) & (doc.dsc IS Frame) THEN
			F := doc.dsc(Frame);
			F.num := ~F.num;
			A.id := Objects.set;
			A.name := "Caption";
			A.class := Objects.String;
			IF ~F.num THEN
				A.s := "Num"
			ELSE
				A.s := "Pict"
			END;
			Gadgets.executorObj.handle(Gadgets.executorObj, A);
			Gadgets.Update(F);
			Gadgets.Update(Gadgets.executorObj)
		END
	END Num;

	PROCEDURE Env(VAR S: Texts.Scanner; VAR F: Frame);
		VAR
			text: Texts.Text;
			beg, end, time: LONGINT;
			doc: Documents.Document;
	BEGIN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "^") THEN
			time := -1;
			text := NIL;
			Oberon.GetSelection(text, beg, end, time);
			IF (time > 0) & (text # NIL) THEN
				Texts.OpenScanner(S, text, beg);
				Texts.Scan(S)
			END
		END;
		doc := Documents.MarkedDoc();
		IF (doc # NIL) & (doc.dsc # NIL) & (doc.dsc IS Frame) THEN
			F := doc.dsc(Frame)
		ELSE
			F := NIL
		END
	END Env;

	PROCEDURE ChangePict*;
		VAR
			S: Texts.Scanner;
			F: Frame;
			pict: Pictures.Picture;
			L: Objects.LinkMsg;
	BEGIN
		Env(S, F);
		IF (F # NIL) & (S.class IN {Texts.Name, Texts.String}) THEN
			F.num := FALSE;
			NEW(pict); Pictures.Create(pict, 0, 0, 8);
			Pictures.Open(pict, S.s, TRUE);
			L.id := Objects.set;
			L.obj := pict;
			L.name := "Picture";
			F.handle(F, L)
		END
	END ChangePict;

	PROCEDURE ChangeSize*;
		VAR
			S: Texts.Scanner;
			F: Frame;
			A: Objects.AttrMsg;
	BEGIN
		Env(S, F);
		IF (F # NIL) & (S.class = Texts.Int) THEN
			A.i := S.i;
			Texts.Scan(S);
			IF S.class = Texts.Int THEN
				A.id := Objects.set;
				A.class := Objects.Int;
				A.name[1] := 0X;
				A.name[0] := "N";
				F.handle(F, A);
				A.i := S.i;
				A.name[0] := "M";
				F.handle(F, A)
			END
		END
	END ChangeSize;

BEGIN
	RandomNumbers.InitSeed(Oberon.Time());
	Texts.OpenWriter(W)
END Scramble.

(Scramble.NewDoc)
