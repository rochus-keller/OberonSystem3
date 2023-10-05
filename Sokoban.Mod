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

MODULE Sokoban;	(** portable *) (* Copyright (C) 1995 by Emil J. Zeller *)
	IMPORT Files, Objects, Input, Display, Pictures, Display3, Fonts, Effects, Strings, Gadgets, Texts, Oberon, TextGadgets, TextDocs, Documents, Desktops;
	(* Sokoban for Oberon Version 1.0
		Disclaimer
			Permission to use, copy, modify and distribute this software and its documentation for any purpose is hereby granted
			without fee, provided that the above copyright notice appear in all copies and that both that copyright notice and this
			permission notice appear in supporting documentation *)

	CONST
		left = 2;
		MaxN = 32;
		MaxM = 32;
		Outside = 0;
		Floor = 1;
		Wall = 2;
		CanPark = 4;
		FloorCan = 8;
		ParkedCan = 12;
		Man = 16;
		ParkMan = 20;
		Left = CHR(196);
		Right = CHR(195);
		Up = CHR(193);
		Down = CHR(194);
		Back = "b";
		DocGen = "Sokoban.NewDoc";
		DEL = CHR(127);
		border = 1;
		Levels = "Sokoban.Data";
		HighScores = "Sokoban.Score";
		DefaultBackPict = "Flock.Pict";
		DefaultWallPict = "Pebbles.Pict";
		DefaultParkPict = "Crochet.Pict";
		DefaultUserName = "unknown";
		CurVer = 0;
		Menu = "Sokoban.Restart[Restart] Desktops.StoreDoc[Store]";

	TYPE
		Frame* = POINTER TO FrameDesc;
		Task = POINTER TO TaskDesc;
		TaskDesc = RECORD (Oberon.TaskDesc)
			F: Frame
		END;
		FrameDesc* = RECORD (Gadgets.FrameDesc)
			level: INTEGER;
			world: ARRAY MaxN+2, MaxM+2 OF SHORTINT;
			mani, manj, oldmani, oldmanj, n, m, moves: INTEGER;
			backPictName, wallPictName, parkPictName, userName: ARRAY 32 OF CHAR;
			backPict, wallPict, parkPict: Pictures.Picture;
			focus, nameFocus, done, movedCan: BOOLEAN;
			startTime, time: LONGINT;
			task: Task
		END;
		UpdateMsg = RECORD (Display.FrameMsg)
			name, moves, time: BOOLEAN;
			points: INTEGER;
			new: ARRAY 4 OF RECORD x, y: INTEGER END
		END;

	VAR
		statusBarH: INTEGER;
		W: Texts.Writer;

	PROCEDURE RestoreField(F: Frame; field: SHORTINT; Q: Display3.Mask; x, y, w, h: INTEGER);
	BEGIN
		Oberon.RemoveMarks(x, y, w, h);
		CASE field OF
			Outside, Floor: Display3.ReplPict(Q, F.backPict, 0, 0, x, y, w, h, Display.replace)
			|Wall: Display3.Rect3D(Q, Display3.topC, Display3.bottomC, x, y, w, h, 2, Display.replace);
					Display3.ReplPict(Q, F.wallPict, 0, 0, x+2, y+2, w-4, h-4, Display.replace)
			|CanPark: Display3.ReplPict(Q, F.parkPict, 0, 0, x, y, w, h, Display.replace)
			|FloorCan:
				Display3.Rect(Q, Display3.FG, Display.solid, x, y, w, h, 2, Display.replace);
				Display3.ReplConst(Q, 5, x+2, y+2, w-4, h-4, Display.replace);
				Display3.Line(Q, Display3.FG, Display.solid, x+1, y+1, x+w-2, y + h-2, 2, Display.replace);
				Display3.Line(Q, Display3.FG, Display.solid, x+1, y+h-2, x+w-2, y+1, 2, Display.replace)
			| ParkedCan:
				Display3.Rect(Q, Display3.FG, Display.solid, x, y, w, h, 2, Display.replace);
				Display3.ReplConst(Q, Display3.green, x+2, y+2, w-4, h-4, Display.replace);
				Display3.Line(Q, Display3.FG, Display.solid, x+1, y+1, x+w-2, y + h-2, 2, Display.replace);
				Display3.Line(Q, Display3.FG, Display.solid, x+1, y+h-2, x+w-2, y+1, 2, Display.replace)
			|Man, ParkMan:
				Display3.Rect(Q, Display3.FG, Display.solid, x, y, w, h, 2, Display.replace);
				Display3.ReplConst(Q, Display3.red, x+2, y+2, w-4, h-4, Display.replace);
				Display3.Circle(Q, Display.FG, Display.solid, x + w DIV 2, y + h DIV 2, 5, 2, {}, Display.replace)
		END
	END RestoreField;

	PROCEDURE CalcSize(F: Frame; x, y: INTEGER; VAR xo, yo, dx, dy: INTEGER);
	BEGIN
		dx := (F.W-2*border) DIV F.n;
		xo := x+border+((F.W-2*border) MOD F.n) DIV 2;
		dy := (F.H-2*border-statusBarH) DIV F.m;
		yo := y+border+statusBarH+((F.H-2*border-statusBarH) MOD F.m) DIV 2
	END CalcSize;

	PROCEDURE ShowStatus(F: Frame; Q: Display3.Mask; x, y, w, h: INTEGER; level, moves, time, name: BOOLEAN);
		VAR
			str: ARRAY 8 OF CHAR;
			Q2: Display3.Mask;
	BEGIN
		IF level & moves & time & name THEN
			Display3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.groupC, x, y, w, statusBarH, border, Display.replace)
		END;
		IF level THEN
			Display3.FilledRect3D(Q, Display3.bottomC, Display3.topC, Display3.groupC, x+4, y+3, statusBarH-4, statusBarH-6, border, Display.replace);
			Strings.IntToStr(F.level, str);
			Display3.CenterString(Q, Display3.black, x+4, y+3, statusBarH-4, statusBarH-6, Fonts.Default, str, Display.paint)
		END;
		IF moves THEN
			Display3.FilledRect3D(Q, Display3.bottomC, Display3.topC, Display3.groupC, x+4+statusBarH, y+3, statusBarH, statusBarH-6, border, Display.replace);
			Strings.IntToStr(F.moves, str);
			Display3.CenterString(Q, Display3.black, x+4+statusBarH, y+3, statusBarH, statusBarH-6, Fonts.Default, str, Display.paint)
		END;
		IF time THEN
			Display3.FilledRect3D(Q, Display3.bottomC, Display3.topC, Display3.groupC, x+8+2*statusBarH, y+3, statusBarH, statusBarH-6, border, Display.replace);
			Strings.IntToStr(F.time DIV Input.TimeUnit, str);
			Display3.CenterString(Q, Display3.black, x+8+2*statusBarH, y+3, statusBarH, statusBarH-6, Fonts.Default, str, Display.paint)
		END;
		IF name THEN
			Oberon.RemoveMarks(x, y, w, h);
			Display3.FilledRect3D(Q, Display3.bottomC, Display3.topC, Display3.groupC, x+12+3*statusBarH, y+3, w-16-3*statusBarH, statusBarH-6, border, Display.replace);
			IF F.nameFocus THEN
				NEW(Q2);
				Display3.Copy(Q, Q2);
				Display3.AdjustMask(Q2, x+12+3*statusBarH, y+3, w-16-3*statusBarH, statusBarH-6);
				Display3.String(Q2, Display3.black, x+15+3*statusBarH, y+3+(statusBarH-Fonts.Default.height) DIV 2, Fonts.Default, F.userName, Display.paint)
			ELSE
				Display3.CenterString(Q, Display3.black, x+12+3*statusBarH, y+3, w-16-3*statusBarH, statusBarH-6, Fonts.Default, F.userName, Display.paint)
			END
		END
	END ShowStatus;

	PROCEDURE Restore(F: Frame; Q: Display3.Mask; x, y, w, h: INTEGER);
		VAR i, j, dx, dy, xo, yo, xi, yj: INTEGER;
	BEGIN
		IF F.focus & ~F.done THEN
			CalcSize(F, x, y, xo, yo, dx, dy);
			Display3.ReplPict(Q, F.backPict, 0, 0, x+border, y+border+statusBarH, w-2*border, yo-y-border-statusBarH, Display.replace);
			Display3.ReplPict(Q, F.backPict, 0, 0, x+border, yo+F.m*dy, w-2*border, yo-y-border+1, Display.replace);
			Display3.ReplPict(Q, F.backPict, 0, 0, x+border, y+border+statusBarH, xo-x-border, h-2*border-statusBarH, Display.replace);
			Display3.ReplPict(Q, F.backPict, 0, 0, xo+F.n*dx, y+border+statusBarH, xo-x-border+1, h-2*border-statusBarH, Display.replace);
			Display3.Rect3D(Q, Display3.topC, Display3.bottomC, x, y+statusBarH, w, h-statusBarH, border, Display.replace);
			ShowStatus(F, Q, x, y, w, h, TRUE, TRUE, TRUE, TRUE);
			xi := xo;
			FOR i := 1 TO F.n DO
				yj := yo;
				FOR j := F.m TO 1 BY-1 DO
					RestoreField(F, F.world[i, j], Q, xi, yj, dx, dy);
					yj := yj+dy
				END;
				xi := xi+dx
			END
		ELSE
			ShowStatus(F, Q, x, y, w, h, TRUE, TRUE, TRUE, TRUE);
			Display3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.white, x, y+statusBarH, w, h-statusBarH, border, Display.replace);
			IF F.done THEN
				Display3.CenterString(Q, Display3.black, x, y+statusBarH, w, h-statusBarH, Fonts.Default, "N O   M O R E   L E V E L S", Display.paint)
			ELSE
				Display3.CenterString(Q, Display3.black, x, y+statusBarH, w, h-statusBarH, Fonts.Default, "P A U S E D", Display.paint)
			END
		END;
		IF Gadgets.selected IN F.state THEN
			Display3.FillPattern(Q, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
		END
	END Restore;

	PROCEDURE CheckDone(F: Frame);
		VAR i, j: INTEGER;
	BEGIN
		FOR i := 1 TO F.n DO
			FOR j := 1 TO F.m DO
				IF F.world[i, j] = FloorCan THEN
					F.done := FALSE;
					RETURN
				END
			END
		END;
		F.done := TRUE
	END CheckDone;

	PROCEDURE StopTask(F: Frame);
	BEGIN
		IF F.task # NIL THEN
			Oberon.Remove(F.task);
			F.task := NIL
		END
	END StopTask;

	PROCEDURE LoadLevel(F: Frame);
		VAR
			i, j, levels: INTEGER;
			offs: LONGINT;
			file: Files.File;
			R: Files.Rider;
	BEGIN
		F.done := TRUE;
		F.moves := 0;
		FOR i := 1 TO MaxN DO
			FOR j := 1 TO MaxM DO
				F.world[i, j] := Floor
			END
		END;
		F.n := 0;
		F.m := 0;
		file := Files.Old(Levels);
		IF file # NIL THEN
			Files.Set(R, file, 0);
			Files.ReadInt(R, levels);
			IF (F.level > 0 ) & (F.level <= levels) THEN
				Files.Set(R, file, Files.Length(file)-(1+levels-F.level)*4);
				Files.ReadLInt(R, offs);
				Files.Set(R, file, offs);
				Files.ReadInt(R, F.n);
				Files.ReadInt(R, F.m);
				FOR  i := 1 TO F.n DO
					FOR j := 1 TO F.m DO
						Files.Read(R, F.world[i, j]);
						IF F.world[i, j] = Man THEN
							F.mani := i; F.manj := j
						END
					END
				END;
				FOR i := 0 TO F.n+1 DO
					F.world[i, 0] := Wall;
					F.world[i, F.m+1] := Wall
				END;
				FOR j := 0 TO F.m+1 DO
					F.world[0, j] := Wall;
					F.world[F.n+1, j] := Wall
				END;
				F.done := FALSE
			END;
			Files.Close(file)
		END;
		F.time := 0;
		F.oldmani := -1;
		F.oldmanj := -1;
		F.movedCan := FALSE;
		StopTask(F)
	END LoadLevel;

	PROCEDURE ShowHighScores*;
		VAR
			TG: TextGadgets.Frame;
			D: Documents.Document;
			text: Texts.Text;
			W: Texts.Writer;
			file: Files.File;
			R: Files.Rider;
			level, moves: INTEGER;
			time: LONGINT;
			name: ARRAY 32 OF CHAR;
	BEGIN
		file := Files.Old(HighScores);
		IF file = NIL THEN
			RETURN
		END;
		Texts.OpenWriter(W);
		Texts.SetFont(W, Fonts.This("Courier10.Scn.Fnt"));
		Texts.WriteString(W, "   level   moves    time    name");
		Texts.WriteLn(W);
		Texts.WriteLn(W);
		Files.Set(R, file, 0);
		Files.ReadInt(R, level);
		WHILE ~R.eof DO
			Files.ReadInt(R, moves);
			Files.ReadLInt(R, time);
			Files.ReadBytes(R, name, 32);
			Texts.WriteInt(W, level, 8);
			Texts.WriteInt(W, moves, 8);
			Texts.WriteInt(W, time DIV Input.TimeUnit, 8);
			Texts.WriteString(W, "    ");
			Texts.WriteString(W, name);
			Texts.WriteLn(W);
			Files.ReadInt(R, level)
		END;
		NEW(text);
		Texts.Open(text, "");
		Texts.Append(text, W.buf);
		TextGadgets.New;
		TG := Objects.NewObj(TextGadgets.Frame);
		TextGadgets.Init(TG, text, FALSE);
		TextDocs.NewDoc;
		D := Objects.NewObj(Documents.Document);
		D.name := HighScores;
		D.W := Display.Width DIV 3;
		D.H := Display.Height DIV 2;
		Documents.Init(D, TG);
		Desktops.ShowDoc(D)
	END ShowHighScores;

	PROCEDURE CheckScore(F: Frame);
		VAR
			file: Files.File;
			new: BOOLEAN;
			R: Files.Rider;
			level, moves: INTEGER;
			time, pos: LONGINT;
			name: ARRAY 32 OF CHAR;
	BEGIN
		file := Files.Old(HighScores);
		IF file = NIL THEN
			file := Files.New(HighScores);
			new := TRUE
		ELSE
			new := FALSE
		END;
		Files.Set(R, file, 0);
		level := MIN(INTEGER);
		moves := MIN(INTEGER);
		pos := 0;
		WHILE ~R.eof & (level # F.level) DO
			pos := Files.Pos(R);
			Files.ReadInt(R, level);
			IF ~R.eof THEN
				Files.ReadInt(R, moves);
				Files.ReadLInt(R, time);
				Files.ReadBytes(R, name, 32)
			ELSE
				level := MIN(INTEGER)
			END
		END;
		IF new THEN
			Files.Register(file)
		END;
		IF ((level = F.level) & ((moves > F.moves) OR ((moves = F.moves) & (time > F.time)))) OR (level # F.level) THEN
			Files.Set(R, file, pos);
			Files.WriteInt(R, F.level);
			Files.WriteInt(R, F.moves);
			Files.WriteLInt(R, F.time);
			Files.WriteBytes(R, F.userName, 32);
			Files.Close(file);
			ShowHighScores()
		ELSE
			Files.Close(file)
		END
	END CheckScore;

	PROCEDURE *Timer(me: Oberon.Task);
		VAR U: UpdateMsg;
	BEGIN
		WITH me: Task DO
			me.time := Oberon.Time();
			me.F.time := me.time-me.F.startTime;
			U.F := me.F;
			U.name := FALSE;
			U.moves := FALSE;
			U.time := TRUE;
			U.points := -1;
			U.res := -1;
			Display.Broadcast(U);
			IF U.res # -2 THEN
				StopTask(me.F)
			ELSE
				me.time := me.time+Input.TimeUnit
			END
		END
	END Timer;

	PROCEDURE StartTask(F: Frame);
	BEGIN
		IF F.task = NIL THEN
			NEW(F.task);
			F.task.F := F;
			F.task.safe := FALSE;
			F.task.time := Oberon.Time()-F.time;
			F.startTime := F.task.time;
			F.task.handle := Timer;
			Oberon.Install(F.task)
		END
	END StartTask;

	PROCEDURE MoveMan(F: Frame; ch: CHAR);
		VAR
			i, j, ci, cj: INTEGER;
			U: UpdateMsg;
			movedCan: BOOLEAN;
	BEGIN
		U.points := 0;
		U.name := FALSE;
		U.time := FALSE;
		CASE ch OF
			Left: i := F.mani-1;
					ci := i-1;
					j := F.manj;
					cj := j
			|Right: i := F.mani+1;
					ci := i+1;
					j := F.manj;
					cj := j
			|Up: j := F.manj-1;
					cj := j-1;
					i := F.mani;
					ci := i
			|Down: j := F.manj+1;
					cj := j+1;
					i := F.mani;
					ci := i
			|Back: IF (F.oldmani > 0) & (F.oldmanj > 0) THEN
							i := F.oldmani;
							j := F.oldmanj;
							ci := -1;
							cj := -1
						ELSE
							RETURN
						END
		ELSE
			RETURN
		END;
		movedCan := FALSE;
		CASE F.world[i, j] OF
			Floor: F.world[i, j] := Man
			|CanPark: F.world[i, j] := ParkMan
			|FloorCan: IF F.world[ci, cj] = Floor THEN
								F.world[i, j] := Man;
								F.world[ci, cj] := FloorCan;
								movedCan := TRUE;
								U.new[U.points].x := ci;
								U.new[U.points].y := cj;
								INC(U.points)
							ELSIF F.world[ci, cj] = CanPark THEN
								F.world[i, j] := Man;
								F.world[ci, cj] := ParkedCan;
								movedCan := TRUE;
								U.new[U.points].x := ci;
								U.new[U.points].y := cj;
								INC(U.points);
								CheckDone(F)
							ELSE
								RETURN
							END
			|ParkedCan: IF F.world[ci, cj] = Floor THEN
								F.world[i, j] := ParkMan;
								F.world[ci, cj] := FloorCan;
								movedCan := TRUE;
								U.new[U.points].x := ci;
								U.new[U.points].y := cj;
								INC(U.points);
								CheckDone(F)
							ELSIF F.world[ci, cj] = CanPark THEN
								F.world[i, j] := ParkMan;
								F.world[ci, cj] := ParkedCan;
								movedCan := TRUE;
								U.new[U.points].x := ci;
								U.new[U.points].y := cj;
								INC(U.points);
								CheckDone(F)
							ELSE
								RETURN
							END
		ELSE
			RETURN
		END;
		IF F.world[F.mani, F.manj] = ParkMan THEN
			F.world[F.mani, F.manj] := CanPark
		ELSIF F.world[F.mani, F.manj] = Man THEN
			F.world[F.mani, F.manj] := Floor
		ELSE
			HALT(99)
		END;
		IF (ch = Back) & F.movedCan THEN
			ci := F.mani+F.mani-F.oldmani;
			cj := F.manj+F.manj-F.oldmanj;
			IF F.world[ci, cj] = FloorCan THEN
				F.world[ci, cj] := Floor
			ELSIF F.world[ci, cj] = ParkedCan THEN
				F.world[ci, cj] := CanPark
			ELSE
				HALT(99)
			END;
			IF F.world[F.mani, F.manj] = CanPark THEN
				F.world[F.mani, F.manj] := ParkedCan
			ELSIF F.world[F.mani, F.manj] = Floor THEN
				F.world[F.mani, F.manj] := FloorCan
			ELSE
				HALT(99)
			END;
			U.new[U.points].x := ci;
			U.new[U.points].y := cj;
			INC(U.points)
		END;
		IF F.task = NIL THEN
			StartTask(F)
		END;
		U.new[U.points].x := i;
		U.new[U.points].y := j;
		INC(U.points);
		U.new[U.points].x := F.mani;
		U.new[U.points].y := F.manj;
		INC(U.points);
		IF ch = Back THEN
			F.oldmani := -1;
			F.oldmanj := -1;
			F.movedCan := FALSE
		ELSE
			F.oldmani := F.mani;
			F.oldmanj := F.manj;
			F.movedCan := movedCan
		END;
		F.mani := i;
		F.manj := j;
		INC(F.moves);
		IF F.done THEN
			CheckScore(F);
			INC(F.level);
			LoadLevel(F);
			Gadgets.Update(F)
		ELSE
			U.moves := TRUE;
			U.F := F;
			Display.Broadcast(U)
		END
	END MoveMan;

	PROCEDURE Consume(F: Frame; ch: CHAR);
		VAR i: INTEGER;
	BEGIN
		i := 0;
		WHILE F.userName[i] # 0X DO
			INC(i)
		END;
		IF (ch >= " ") & (ch < DEL) & (i < (LEN(F.userName)-1)) THEN
			F.userName[i] := ch;
			F.userName[i+1] := 0X
		ELSIF (ch = DEL) & (i > 0) THEN
			F.userName[i-1] := 0X
		END
	END Consume;
	
	PROCEDURE CopyFrame(VAR M: Objects.CopyMsg; F, F1: Frame);
		VAR i, j: INTEGER;
	BEGIN
		Gadgets.CopyFrame(M, F, F1);
		F1.level := F.level;
		F1.moves := F.moves;
		F1.mani := F.mani;
		F1.manj := F.manj;
		F1.n := F.n;
		F1.m := F.m;
		F1.done := F.done;
		F1.startTime := F.startTime;
		F1.time := F.time;
		COPY(F.backPictName, F1.backPictName);
		COPY(F.wallPictName, F1.wallPictName);
		COPY(F.parkPictName, F1.parkPictName);
		COPY(F.userName, F1.userName);
		FOR i := 0 TO MaxN+1 DO
			FOR j := 0 TO MaxM+1 DO
				F1.world[i, j] := F.world[i, j]
			END
		END;
		NEW(F1.backPict);
		Pictures.Open(F1.backPict, F1.backPictName, TRUE);
		NEW(F1.wallPict);
		Pictures.Open(F1.wallPict, F1.wallPictName, TRUE);
		NEW(F1.parkPict);
		Pictures.Open(F1.parkPict, F1.parkPictName, TRUE);
		F1.focus := FALSE;
		F1.nameFocus := FALSE
	END CopyFrame;

	PROCEDURE UpdateName(F: Frame);
		VAR U: UpdateMsg;
	BEGIN
		U.F := F;
		U.name := TRUE;
		U.moves := FALSE;
		U.time := FALSE;
		U.points := -1;
		U.res := -1;
		Display.Broadcast(U)
	END UpdateName;

	PROCEDURE Handle*(F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			x, y, w, h, xo, yo, ver, i: INTEGER;
			Q: Display3.Mask;
			keysum: SET;
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
								ELSIF M.device = Display.printer THEN Gadgets.framehandle(F, M)
								END
							END
						ELSIF M IS UpdateMsg THEN
							WITH M: UpdateMsg DO
								Gadgets.MakeMask(F, x, y, M.dlink, Q);
								IF M.name OR M.moves OR M.time THEN
									ShowStatus(F, Q, x, y, w, h, FALSE, M.moves, M.time, M.name);
									M.res := -2
								END;
								IF M.points > 0 THEN
									CalcSize(F, x, y, xo, yo, w, h);
									FOR i := 0 TO M.points-1 DO
										RestoreField(F, F.world[M.new[i].x, M.new[i].y], Q, xo+(M.new[i].x-1)*w, yo+(F.m-M.new[i].y)*h, w, h)
									END
								END
							END
						ELSIF M IS Oberon.InputMsg THEN
							WITH M: Oberon.InputMsg DO
								IF M.id = Oberon.track THEN
									IF Gadgets.InActiveArea(F, M) THEN
										IF M.keys = {left} THEN
											keysum := M.keys;
											REPEAT
												Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow);
												keysum := keysum + M.keys
											UNTIL M.keys = {};
											M.res := 0;
											xo := M.X-(x+12+3*statusBarH);
											yo := M.Y-(y+3);
											IF (xo > 0) & (yo > 0) & (((w-16-3*statusBarH)-xo) > 0) & (((statusBarH-6)-yo) > 0) THEN
												Oberon.Defocus();
												F.nameFocus := TRUE;
												UpdateName(F)
											ELSIF ~F.focus THEN
												Oberon.Defocus();
												F.focus := TRUE;
												IF F.time > 0 THEN
													StartTask(F)
												END;											
												Gadgets.Update(F)
											END
										ELSE
											Gadgets.framehandle(F, M)
										END
									ELSE
										Gadgets.framehandle(F, M)
									END 
								ELSIF (M.id = Oberon.consume) & (M.stamp # F.stamp) THEN
									F.stamp := M.stamp;
									IF F.focus THEN
										MoveMan(F, M.ch)
									ELSIF F.nameFocus THEN
										Consume(F, M.ch);
										UpdateName(F)
									ELSE
										Gadgets.framehandle(F, M)
									END
								ELSE
									Gadgets.framehandle(F, M)
								END
							END
						ELSIF M IS Oberon.ControlMsg THEN
							WITH  M: Oberon.ControlMsg DO
								IF ((M.id = Oberon.defocus) OR (M.id = Oberon.neutralize)) THEN
									IF F.focus THEN
										StopTask(F);
										F.focus := FALSE;
										Gadgets.Update(F)
									ELSIF F.nameFocus THEN
										F.nameFocus := FALSE;
										UpdateName(F)
									END
								END
							END
						ELSIF M IS Oberon.CaretMsg THEN
							WITH  M: Oberon.CaretMsg DO
								IF F.focus & (M.id = Oberon.get) THEN
									M.car := F;
									M.text := NIL;
									M.pos := 0;
									M.res := 0
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
							M.s := "Sokoban.NewFrame";
							M.res := 0
						ELSIF M.name = "BackPicture" THEN
							M.class := Objects.String;
							COPY(F.backPictName, M.s);
							M.res := 0
						ELSIF M.name = "WallPicture" THEN
							M.class := Objects.String;
							COPY(F.wallPictName, M.s);
							M.res := 0
						ELSIF M.name = "ParkPicture" THEN
							M.class := Objects.String;
							COPY(F.parkPictName, M.s);
							M.res := 0
						ELSE
							Gadgets.framehandle(F, M)
						END
					ELSIF M.id = Objects.set THEN
						IF (M.class = Objects.String) & (M.name = "BackPicture") THEN
							COPY(M.s, F.backPictName);
							Pictures.Open(F.backPict, F.backPictName, TRUE);
							IF F.focus THEN
								Gadgets.Update(F)
							END;
							M.res := 0
						ELSIF (M.class = Objects.String) & (M.name = "WallPicture") THEN
							COPY(M.s, F.wallPictName);
							Pictures.Open(F.wallPict, F.wallPictName, TRUE);
							IF F.focus THEN
								Gadgets.Update(F)
							END;
							M.res := 0
						ELSIF (M.class = Objects.String) & (M.name = "ParkPicture") THEN
							COPY(M.s, F.parkPictName);
							Pictures.Open(F.parkPict, F.parkPictName, TRUE);
							IF F.focus THEN
								Gadgets.Update(F)
							END;
							M.res := 0
						ELSE
							Gadgets.framehandle(F, M)
						END
					ELSIF M.id = Objects.enum THEN
						Gadgets.framehandle(F, M);
						M.Enum("BackPicture");
						M.Enum("WallPicture");
						M.Enum("ParkPicture");
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
						Files.WriteInt(M.R, F.level);
						Files.WriteInt(M.R, F.moves);
						Files.WriteInt(M.R, F.mani);
						Files.WriteInt(M.R, F.manj);
						Files.WriteInt(M.R, F.oldmani);
						Files.WriteInt(M.R, F.oldmanj);
						Files.WriteBool(M.R, F.movedCan);
						Files.WriteInt(M.R, F.n);
						Files.WriteInt(M.R, F.m);
						Files.WriteBool(M.R, F.done);
						FOR x := 1 TO F.n DO
							FOR y := 1 TO F.m DO
								Files.Write(M.R, F.world[x, y])
							END
						END;
						Files.WriteLInt(M.R, F.time);
						Files.WriteString(M.R, F.backPictName);
						Files.WriteString(M.R, F.wallPictName);
						Files.WriteString(M.R, F.parkPictName);
						Files.WriteString(M.R, F.userName)
					ELSIF M.id = Objects.load THEN
						Files.ReadInt(M.R, ver);
						Files.ReadInt(M.R, F.level);
						Files.ReadInt(M.R, F.moves);
						Files.ReadInt(M.R, F.mani);
						Files.ReadInt(M.R, F.manj);
						IF ver = CurVer THEN
							Files.ReadInt(M.R, F.oldmani);
							Files.ReadInt(M.R, F.oldmanj);
							Files.ReadBool(M.R, F.movedCan)
						END;
						Files.ReadInt(M.R, F.n);
						Files.ReadInt(M.R, F.m);
						Files.ReadBool(M.R, F.done);
						FOR x := 1 TO F.n DO
							FOR y := 1 TO F.m DO
								Files.Read(M.R, F.world[x, y])
							END
						END;
						Files.ReadLInt(M.R, F.time);
						Files.ReadString(M.R, F.backPictName);
						Pictures.Open(F.backPict, F.backPictName, TRUE);
						Files.ReadString(M.R, F.wallPictName);
						Pictures.Open(F.wallPict, F.wallPictName, TRUE);
						Files.ReadString(M.R, F.parkPictName);
						Pictures.Open(F.parkPict, F.parkPictName, TRUE);
						Files.ReadString(M.R, F.userName)
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
		F.task := NIL;
		F.level := 1;
		LoadLevel(F);
		F.W := F.n*16+2*border+statusBarH;
		F.H := F.m*16+2*border;
		F.handle := Handle;
		F.focus := FALSE;
		F.nameFocus := FALSE;
		F.done := FALSE;
		F.backPictName := DefaultBackPict;
		NEW(F.backPict);
		Pictures.Open(F.backPict, F.backPictName, TRUE);
		F.wallPictName := DefaultWallPict;
		NEW(F.wallPict);
		Pictures.Open(F.wallPict, F.wallPictName, TRUE);
		F.parkPictName := DefaultParkPict;
		NEW(F.parkPict);
		Pictures.Open(F.parkPict, F.parkPictName, TRUE);
		F.userName := DefaultUserName;
		Objects.NewObj := F
	END NewFrame;

	PROCEDURE Restart*;
		VAR
			doc: Documents.Document;
			F: Frame;
			C: Oberon.CaretMsg;
			S: Texts.Scanner;
			level: INTEGER;
		PROCEDURE Do();
		BEGIN
			IF level > 0 THEN
				F.level := level
			END;
			LoadLevel(F);
			IF F.done THEN
				F.level := level;
				LoadLevel(F)
			END;
			IF ~F.focus THEN
				Oberon.Defocus();
				F.focus := TRUE
			END;
			Gadgets.Update(F)
		END Do;
	BEGIN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(S);
		IF S.class = Texts.Int THEN
			level := SHORT(S.i)
		ELSE
			level := -1
		END;
		doc := Desktops.CurDoc(Gadgets.context);
		IF (doc # NIL) & (doc.dsc IS Frame) THEN
			F := doc.dsc(Frame);
			Do()
		ELSE
			doc := Documents.MarkedDoc();
			IF (doc # NIL) & (doc.dsc IS Frame) THEN
				F := doc.dsc(Frame);
				Do()
			ELSE
				C.F := NIL;
				C.id := Oberon.get;
				C.car := NIL;
				Display.Broadcast(C);
				IF (C.car # NIL) & (C.car IS Frame) THEN
					F := C.car(Frame);
					Do()
				END
			END
		END
	END Restart;

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
			D.name := "Sokoban.Doc";
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
		F := Files.New(D.name);
		IF F # NIL THEN
			Files.Set(R, F, 0);
			Files.WriteInt(R, Documents.Id);
			Files.WriteString(R, DocGen);
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
		END
	END StoreDoc;

	PROCEDURE DocHandler*(D: Objects.Object; VAR M: Objects.ObjMsg);
	BEGIN
		WITH D: Documents.Document DO
			IF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "Gen" THEN
							M.class := Objects.String; M.s := DocGen; M.res := 0
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
						M.obj := Desktops.NewMenu(Menu); M.res := 0
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

BEGIN
	Texts.OpenWriter(W);
	statusBarH := 2*Fonts.Default.height
END Sokoban.

Desktops.OpenDoc (Sokoban.NewDoc) ~

Sokoban.ShowHighScores ~

Sokoban.Restart 1 ~


