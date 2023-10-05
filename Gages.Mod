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

MODULE Gages;	(** portable *) (* kr/ jm 21.12.94 *)

IMPORT
	Modules, Input, Display, Objects, Gadgets, Oberon, BasicGadgets, Fonts, Kernel, Display3, Printer, Printer3, Strings ; 

CONST
	Max = 128;

TYPE
	Frame* = POINTER TO FrameDesc;
	FrameDesc* = RECORD (Gadgets.FrameDesc)
		points*: ARRAY Max OF LONGINT;
		min, max: LONGINT;
		maxPoints : INTEGER;
		beg, end: INTEGER;
	END;

VAR
	Mem, Load, Lap: BasicGadgets.Integer;
	task : Oberon.Task;
	time, lastmem: LONGINT;
	maxLoad, loadtime,load, laptime: LONGINT; 

(* -------- models ---------- *)

PROCEDURE NewMem*;
BEGIN
	Objects.NewObj := Mem
END NewMem;

PROCEDURE NewLoad*;
BEGIN Objects.NewObj := Load
END NewLoad;

PROCEDURE NewLap*;
BEGIN Objects.NewObj := Lap
END NewLap;

PROCEDURE *HandleMem(obj: Objects.Object; VAR M: Objects.ObjMsg);	
BEGIN
	IF M IS Objects.CopyMsg THEN M(Objects.CopyMsg).obj := Mem
	ELSIF M IS Objects.AttrMsg THEN
		WITH M : Objects.AttrMsg DO
			IF (M.id = Objects.get) & (M.name = "Gen") THEN M.s := "Gages.NewMem"
			ELSE BasicGadgets.IntegerHandler(obj, M)
			END
		END
	ELSE BasicGadgets.IntegerHandler(obj, M)
	END
END HandleMem;

PROCEDURE *HandleLoad (obj: Objects.Object; VAR M: Objects.ObjMsg);	
BEGIN
	IF M IS Objects.CopyMsg THEN M(Objects.CopyMsg).obj := Load
	ELSIF M IS Objects.AttrMsg THEN
		WITH M : Objects.AttrMsg DO
			IF (M.id = Objects.get) & (M.name = "Gen") THEN M.s := "Gages.NewLoad"
			ELSE BasicGadgets.IntegerHandler(obj, M)
			END
		END
	ELSE BasicGadgets.IntegerHandler(obj, M)
	END
END HandleLoad;

PROCEDURE *HandleLap (obj: Objects.Object; VAR M: Objects.ObjMsg);	
BEGIN
	IF M IS Objects.CopyMsg THEN M(Objects.CopyMsg).obj := Lap
	ELSIF M IS Objects.AttrMsg THEN
		WITH M : Objects.AttrMsg DO
			IF (M.id = Objects.get) & (M.name = "Gen") THEN M.s := "Gages.NewLap" 
			ELSE BasicGadgets.IntegerHandler(obj, M)
			END
		END
	ELSE BasicGadgets.IntegerHandler(obj,M)
	END
END HandleLap;

PROCEDURE *TaskHandle(me : Oberon.Task);
VAR M: Gadgets.UpdateMsg; tm : LONGINT;
BEGIN
	INC(load); tm := Oberon.Time();
	IF tm - laptime > Input.TimeUnit DIV 2 THEN			
		Lap.val := (tm - laptime) * 1000 DIV Input.TimeUnit;
		Gadgets.Update(Lap)
	END;
	laptime := tm;
	IF tm - loadtime > Input.TimeUnit THEN  
		IF tm - loadtime > Input.TimeUnit*3 DIV 2 THEN load  := 0
		ELSE load := load * Input.TimeUnit DIV (tm - loadtime)
		END;
		IF load > maxLoad THEN maxLoad := load END;
		load := load * 100 DIV maxLoad; Load.val := (Load.val * 4 + (100 - load)) DIV 5;
		load := 0; loadtime := tm; M.F := NIL;
		M.obj :=Load; Display.Broadcast(M)
	END; 
	IF tm - time > Input.TimeUnit DIV 10 THEN time := tm;
		IF (Kernel.Used() # lastmem) THEN 
			Mem.val := Kernel.Used(); M.F := NIL;
			M.obj := Mem; Display.Broadcast(M);
			lastmem := Kernel.Used()
		END
	ELSE
		me.time := tm + Input.TimeUnit DIV 10
	END
END TaskHandle;

PROCEDURE *Deinstall;
BEGIN IF task # NIL THEN Oberon.Remove(task) END
END Deinstall;

(* --------- *)

PROCEDURE AddPoint(F: Frame; x: LONGINT);
VAR i: INTEGER;
BEGIN
	IF F.W -2 > Max THEN F.maxPoints := Max ELSE F.maxPoints  := F.W -2 END;
	F.points[F.end] := x;
	F.end := (F.end + 1) MOD F.maxPoints;
	IF F.end = F.beg THEN F.beg := (F.beg + 1) MOD F.maxPoints END;
	i := F.beg; F.min := MAX(LONGINT); F.max := MIN(LONGINT);
	WHILE i # F.end DO
		IF F.points[i] < F.min THEN F.min := F.points[i] END; IF F.points[i] > F.max THEN F.max := F.points[i] END;
		i := (i + 1) MOD F.maxPoints
	END;
	IF ABS(F.max - F.min) = 0 THEN F.max := F.min + 1 END
END AddPoint;
	
PROCEDURE RestoreFrame(F: Frame; M: Display3.Mask; x, y, w, h: INTEGER);
VAR i, j, mode: INTEGER; p: LONGINT; s: ARRAY 16 OF CHAR; 
BEGIN
	Oberon.RemoveMarks(x, y, w, h);
	Display3.Rect3D(M, Display3.bottomC,Display3.topC, x, y, w, h, 1, Display.replace);
	Display3.AdjustMask(M, x+1, y+1, w-2, h-2);
	IF F.W -2 > Max THEN F.maxPoints := Max ELSE F.maxPoints  := F.W -2 END;
	i := F.beg; j := 0;
	WHILE i # F.end DO
		p := (F.points[i] - F.min) * (h-5) DIV ABS(F.max - F.min);
		Display3.ReplConst(M,12,x + j,  y , 1, SHORT(p) + 2, Display.replace);
		Display3.ReplConst(M,Display3.textbackC,x + j,  y  + SHORT(p) + 2, 1, F.H - (SHORT(p) + 2), Display.replace);
		i := (i + 1) MOD F.maxPoints; INC(j)
	END;
	Display3.ReplConst(M,Display3.textbackC, x+ j, y+1, F.W, h-2, Display.replace);
	Strings.IntToStr(F.max, s);
	mode := Display.paint;
	Display3.String(M,Display3.textC, x + 2, y + h - 12, Fonts.Default, s, mode);
	Strings.IntToStr(F.min, s);
	Display3.String(M, Display3.textC, x + 2, y + 2,  Fonts.Default, s, mode);
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
	END
END RestoreFrame;

PROCEDURE PrintFrame(F: Frame; VAR M: Display.DisplayMsg);
VAR i, j, x, y, w, h, p: INTEGER; s: ARRAY 12 OF CHAR; Q: Display3.Mask;

	PROCEDURE P (X: INTEGER): INTEGER;
	BEGIN RETURN SHORT(Display.Unit*X DIV Printer.Unit)
	END P;

BEGIN
	Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, Q);
	x := M.x; y := M.y; w := P(F.W); h := P(F.H);
	Printer3.Rect3D(Q, Display3.bottomC,Display3.topC, x, y, w, h, P(1), Display.replace);
	INC(x, P(1)); INC(y, P(1)); DEC(w, P(2)); DEC(h, P(2));
	i := F.beg; j := 0;
	WHILE i # F.end DO
		p := SHORT((F.points[i] - F.min) * (F.H-3) DIV ABS(F.max - F.min));
		Printer3.ReplConst(Q,12, x + j,  y , P(1), P(p + 1), Display.replace);
		Printer3.ReplConst(Q,Display3.textbackC,x + j,  y  + P(p + 1), P(1), P(F.H - p - 3), Display.replace);
		i := (i + 1) MOD F.maxPoints; INC(j, P(1))
	END;
	Printer3.ReplConst(Q,Display3.textbackC, x+ j, y, w - j, h, Display.replace);
	Strings.IntToStr(F.max, s);
	Printer3.String(Q,Display3.textC, x + P(1), y + h - P(10), Fonts.Default, s, Display.paint);
	Strings.IntToStr(F.min, s);
	Printer3.String(Q, Display3.textC, x + P(1), y + P(1), Fonts.Default, s, Display.paint)
END PrintFrame;

PROCEDURE FrameAttr(F: Frame; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class := Objects.String; COPY("Gages.NewFrame", M.s); M.res := 0
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		Gadgets.framehandle(F, M)
	ELSIF M.id = Objects.enum THEN
		Gadgets.framehandle(F, M)
	END
END FrameAttr;

PROCEDURE *FrameHandler(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR x, y, w, h: INTEGER; F0: Frame; R : Display3.Mask;
BEGIN
	WITH F: Frame DO
		IF M IS Objects.AttrMsg THEN
			FrameAttr(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink
				ELSE NEW(F0); Gadgets.CopyFrame(M, F, F0); F.dlink := F0; M.obj := F0
				END
			END
		ELSIF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
				IF M IS Display.DisplayMsg THEN
					WITH M : Display.DisplayMsg DO
						IF (M.device = Display.screen) & ((M.F = F) OR (M.F = NIL)) THEN
							Gadgets.MakeMask(F, x, y, M.dlink, R);
							IF M.id = Display.area THEN Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h) END;
							RestoreFrame(F, R, x, y, w, h)
						ELSIF M.device = Display.printer THEN PrintFrame(F, M)
						END
					END
				ELSIF  M IS Gadgets.UpdateMsg THEN
					WITH M: Gadgets.UpdateMsg  DO
						IF (M.obj = F.obj) & (M.obj IS BasicGadgets.Integer) THEN
							IF M.stamp # F.stamp THEN
								F.stamp := M.stamp;
								AddPoint(F, F.obj(BasicGadgets.Integer).val)
							END;
							Gadgets.MakeMask(F, x, y, M.dlink, R);
							RestoreFrame(F, R, x, y, w, h)
						END
					END
				ELSE
					Gadgets.framehandle(F, M)
				END
			END
		ELSE
			Gadgets.framehandle(F, M)
		END
	END
END FrameHandler;

PROCEDURE NewFrame*;
VAR F: Frame;
BEGIN
	NEW(F); F.W := 130; F.H := 100; F.handle := FrameHandler; Objects.NewObj := F;
	F.beg := 0; F.end := 0; F.min := 0; F.max := 1
END NewFrame;

BEGIN
	maxLoad := 1; load := 0;
	NEW(task); task.handle := TaskHandle; Oberon.Install(task);
	Modules.InstallTermHandler(Deinstall);
	BasicGadgets.NewInteger; Mem := Objects.NewObj(BasicGadgets.Integer);
	BasicGadgets.NewInteger; Load := Objects.NewObj(BasicGadgets.Integer);
	BasicGadgets.NewInteger; Lap := Objects.NewObj(BasicGadgets.Integer);
	Load.handle := HandleLoad; Mem.handle := HandleMem; Lap.handle := HandleLap;
	time := Oberon.Time();
	Lap.val := 0; laptime := time
END Gages.

System.Free Gages  ~
Gadgets.Insert Gages.NewFrame Gages.NewMem ~
Gadgets.Insert TextFields.NewTextField Gages.NewLap ~
Gadgets.Insert Gages.NewFrame ~Gages.NewLoad ~

Gadgets.Change Gages.NewFrame ~
Gadgets.SetAttr Max 1024
Gadgets.SetAttr Min -1024

Gadgets.Change Gages.NewFrame ~
