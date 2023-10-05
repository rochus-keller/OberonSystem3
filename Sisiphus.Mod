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

MODULE Sisiphus;	(** portable *) (* gri 18.3.91 / 30.1.92 / 27.4.92 / jt/jm 7.11.95*)

	IMPORT
		SYSTEM, Modules, Objects, Input, Display, Oberon, Math, Files, Gadgets, Display3, Printer;

	CONST
		IStag = 753; (* icon stretch tag *)
		left = 2; middle = 1; right = 0; (* mouse keys *)
		HSide = 31; Side = 64; (* dimensions *)
		MaxN = 64; Sleep = 100; (* in ms *)

	TYPE
		Icon = ARRAY 2 OF RECORD
			addr: LONGINT;
			image: ARRAY Side+1 OF SET
		END;

		Frame* = POINTER TO RECORD (Gadgets.FrameDesc)
			col*: INTEGER;
			age*: LONGINT
		END;
		
		NotifyMsg = RECORD (Display.FrameMsg) END;

		SyncMsg = RECORD (Display.FrameMsg) END;

	VAR
		N: LONGINT; (* no. of figurs *)
		Task: Oberon.Task;
		Fig: ARRAY MaxN OF Icon;

	PROCEDURE EmptyFig;
		VAR j: INTEGER;
	BEGIN N := 1; j := 1;
		WHILE j < Side DO
			Fig[0, 0].image[j] := {};
			Fig[0, 1].image[j] := {};
			INC(j)
		END;
		Fig[0, 0].addr := Display.NewPattern(HSide, Side, Fig[0, 0].image);
		Fig[0, 1].addr := Display.NewPattern(HSide, Side, Fig[0, 1].image)
	END EmptyFig;

	PROCEDURE LoadFig (file: ARRAY OF CHAR); (* read portable file format *)
		VAR F: Files.File; R: Files.Rider; i, j: INTEGER;

		PROCEDURE ReadInt (VAR x: LONGINT);
			VAR n: LONGINT; i: SHORTINT; ch: CHAR;
		BEGIN i := 0; n := 0; Files.Read(R, ch);
			WHILE ORD(ch) >= 128 DO INC(n, ASH(ORD(ch) - 128, i)); INC(i, 7); Files.Read(R, ch) END;
			x := n + ASH(ORD(ch) MOD 64 - ORD(ch) DIV 64 * 64, i)
		END ReadInt;

		PROCEDURE ReadSet (VAR s: SET);
			VAR x: LONGINT; i: INTEGER;
		BEGIN ReadInt(x); s := {}; i := 0;
			WHILE i < 32 DO
				IF ODD(x) THEN INCL(s, i) END;
				x := x DIV 2; INC(i)
			END
		END ReadSet;

	BEGIN F := Files.Old(file);
		IF F = NIL THEN EmptyFig; RETURN END;
		Files.Set(R, F, 0); ReadInt(N);
		IF N # IStag THEN EmptyFig; RETURN END;
		ReadInt(N); i := 0;
		WHILE i < N DO j := 1;
			WHILE j <= Side DO
				ReadSet(Fig[i, 0].image[j]);
				ReadSet(Fig[i, 1].image[j]);
				Fig[i, 1].image[j] := SYSTEM.LSH(Fig[i, 1].image[j], 1) + SYSTEM.LSH(Fig[i, 0].image[j], -31);
				INC(j)
			END;
			Fig[i, 0].addr := Display.NewPattern(HSide, Side, Fig[i, 0].image);
			Fig[i, 1].addr := Display.NewPattern(HSide, Side, Fig[i, 1].image);
			INC(i)
		END
	END LoadFig;
	
	PROCEDURE Draw (M: Display3.Mask; VAR icn: Icon; x, y, color: INTEGER);
	BEGIN
		Oberon.RemoveMarks(x, y, Side, Side);
		Display3.CopyPattern(M, color, icn[0].addr, x, y, Display.paint);
		Display3.CopyPattern(M, color, icn[1].addr, x + HSide, y, Display.paint)
	END Draw;

	PROCEDURE P(x: INTEGER): INTEGER;
	BEGIN RETURN SHORT((x*Display.Unit + Display.Unit DIV 2) DIV Printer.Unit)
	END P;

	PROCEDURE PrintIcn (VAR icn: Icon; x, y: INTEGER);
		VAR i: INTEGER;

		PROCEDURE PrintLine (x, y: INTEGER; line: SET);
			VAR i, i0: INTEGER;
		BEGIN i := 0;
			WHILE i < HSide DO
				IF i IN line THEN i0 := i; INC(i);
					WHILE (i < HSide) & (i IN line) DO INC(i) END;
					Printer.ReplConst(x + P(i0), y, P(i-i0), P(1))
				END;
				INC(i)
			END
		END PrintLine;

	BEGIN i := 0;
		WHILE i < Side DO
			PrintLine(x, y + P(i), icn[0].image[i+1]);
			PrintLine(x + P(HSide), y + P(i), icn[1].image[i+1]);
			INC(i)
		END
	END PrintIcn;

	PROCEDURE HotSpot (X, Y, W, H, X0, Y0: INTEGER);
		CONST d = 6;
		VAR dx, dy: LONGINT; r: INTEGER;
	
		PROCEDURE Block (x, y, w, h, col, mode: INTEGER);
		BEGIN
			IF x < X THEN DEC(w, X-x); x := X END;
			IF x+w > X+W THEN w := X+W-x END;
			IF w <= 0 THEN RETURN END;
			IF y < Y THEN DEC(h, Y-y); y := Y END;
			IF y+h > Y+H THEN h := Y+H-y END;
			IF h <= 0 THEN RETURN END;
			Display.ReplConst(col, x, y, w, h, mode)
		END Block;
		
		PROCEDURE Dot4 (x1, x2, y1, y2, col, mode: INTEGER);
			CONST r = (d+1) DIV 2;
		BEGIN
			Block(x1-r, y1-r, 2*r+1, 2*r+1, col, mode);
			Block(x1-r, y2-r, 2*r+1, 2*r+1, col, mode);
			Block(x2-r, y1-r, 2*r+1, 2*r+1, col, mode);
			Block(x2-r, y2-r, 2*r+1, 2*r+1, col, mode)
		END Dot4;
		
		PROCEDURE Circle (X, Y, R, col, mode: INTEGER);
			VAR x, y, dx, dy, d: INTEGER;
		BEGIN
			x := R; y := 0; dx := 8*(x-1); dy := 8*y+4; d := 1 - 4*R;
			WHILE x > y DO
				Dot4(X-x-1, X+x, Y-y-1, Y+y, col, mode);
				Dot4(X-y-1, X+y, Y-x-1, Y+x, col, mode);
				INC(d, dy); INC(dy, 8); INC(y);
				IF d >= 0 THEN DEC(d, dx); DEC(dx, 8); DEC(x) END
			END;
			IF x = y THEN Dot4(X-x-1, X+x, Y-y-1, Y+y, col, mode) END
		END Circle;
		
	BEGIN
		IF X0-X > X+W-X0 THEN dx := X0-X ELSE dx := X+W-X0 END;
		IF Y0-Y > Y+H-Y0 THEN dy := Y0-Y ELSE dy := Y+H-Y0 END;
		r := SHORT(ENTIER(Math.sqrt(dx*dx + dy*dy)));
		WHILE r > 0 DO Circle(X0, Y0, r, Display3.black, Display.replace); DEC(r, d) END
	END HotSpot;
	
	PROCEDURE SaveScreen (x0, y0: INTEGER; keys: SET; col: INTEGER; VAR State: LONGINT);
		VAR sum: SET; x, y, w, h: INTEGER; msg: Display.ControlMsg; wakeUp: LONGINT;
	BEGIN
		Oberon.RemoveMarks(x0, y0, 52, 52);
		Display.ReplConst(Display3.black, x0, y0, 52, 52, Display.invert); sum := keys;
		REPEAT
			Input.Mouse(keys, x, y); sum := sum+keys; 
			Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, x, y)
		UNTIL keys = {};
		Display.ReplConst(Display3.black, x0, y0, 52, 52, Display.invert);
		IF sum # {left, middle, right} THEN
			x := Oberon.UserTrack(x0); w := Oberon.DisplayWidth(x0);
			y := Display.Bottom; h := Oberon.DisplayHeight(x0);
			Oberon.RemoveMarks(x, y, w, h);
			msg.id := Display.suspend; Display.Broadcast(msg);
			HotSpot(x, y, w, h, x0 + Side DIV 2, y0 + Side DIV 2);
			REPEAT
				Display.ReplConst(Display3.black, x0, y0, Side, Side, Display.replace);
				INC(State); INC(x0, 10);
				IF x0+Side > x+w THEN x0 := x; INC(y0, Side);
					IF y0+Side > y+h THEN y0 := y END
				END;
				Draw(NIL, Fig[State MOD N], x0, y0, col);
				wakeUp := Oberon.Time() + Sleep*Input.TimeUnit DIV 1000;
				REPEAT UNTIL Oberon.Time() - wakeUp >= 0
			UNTIL Input.Available() > 0;
			msg.id := Display.restore; Display.Broadcast(msg)
		END
	END SaveScreen;
	
	PROCEDURE FrameAttr(F: Frame; VAR M: Objects.AttrMsg);
	BEGIN
		IF M.id = Objects.get THEN
			IF M.name = "Gen" THEN M.class := Objects.String; COPY("Sisiphus.New", M.s); M.res := 0
			ELSIF M.name = "Color" THEN M.class := Objects.Int; M.i := F.col; M.res := 0 
			ELSIF M.name = "Age" THEN M.class := Objects.Int; M.i := F.age; M.res := 0 
			ELSE Gadgets.framehandle(F, M)
			END
		ELSIF M.id = Objects.set THEN
			IF M.name = "Color" THEN
				IF M.class = Objects.Int THEN F.col := SHORT(M.i); M.res := 0 END
			ELSIF M.name = "Age" THEN
				IF M.class = Objects.Int THEN F.age := M.i; M.res := 0 END
			ELSE Gadgets.framehandle(F, M);
			END
		ELSIF M.id = Objects.enum THEN
			M.Enum("Color"); M.Enum("Age"); Gadgets.framehandle(F, M)
		END
	END FrameAttr;

PROCEDURE RestoreFrame(F: Frame; M: Display3.Mask; x, y, w, h: INTEGER);
BEGIN
	Display3.ReplConst(M, F.col, x, y, w, h, Display.replace);
	Draw(M, Fig[F.age MOD N], x, y, Display3.black);
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
	END
END RestoreFrame;
	
PROCEDURE Print(F: Frame; VAR M: Display.DisplayMsg);
VAR R: Display3.Mask;
BEGIN
	Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, R);
	PrintIcn(Fig[F.age MOD N], M.x, M.y);
END Print;

PROCEDURE CopyFrame*(VAR M: Objects.CopyMsg; from, to: Frame);
BEGIN
	to.col := from.col; to.age := from.age;
	Gadgets.CopyFrame(M, from, to);
END CopyFrame;

PROCEDURE FrameHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR x, y, w, h: INTEGER; F0: Frame; R: Display3.Mask;
BEGIN
	WITH F: Frame DO
		IF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF (M.F = NIL) OR (M.F = F) THEN	(* message addressed to this frame *)
					x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H; (* calculate display coordinates *)
					IF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg  DO
							IF M.device = Display.screen THEN
								IF (M.id = Display.full) OR (M.F = NIL) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									RestoreFrame(F, R, x, y, w, h)
								ELSIF M.id = Display.area THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
									RestoreFrame(F, R, x, y, w, h)
								END
							ELSIF M.device = Display.printer THEN Print(F, M)
							END
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) & Gadgets.InActiveArea(F, M) & (M.keys = {1}) THEN
								SaveScreen(x, y, M.keys, Display3.white, F.age); M.res := 0;
							ELSE Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS SyncMsg THEN
						IF Gadgets.selected IN F.state THEN
							Gadgets.MakeMask(F, x, y, M.dlink, R);
							F.age := 0;  RestoreFrame(F, R, x, y, w, h)
						END
					ELSIF M IS NotifyMsg THEN
						WITH M: NotifyMsg DO
							IF ~(Gadgets.selected IN F.state) THEN
								IF M.stamp # F.stamp THEN INC(F.age); F.stamp := M.stamp END;
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								Draw(R, Fig[(F.age-1) MOD N], x, y, F.col);
								Draw(R, Fig[F.age MOD N], x, y, Display3.black (*F.col*))
							END
						END
					ELSE Gadgets.framehandle(F, M)
					END
				END
			END
			
		(* Object messages *)
		
		ELSIF M IS Objects.AttrMsg THEN FrameAttr(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN (* store private data here *)
					Files.WriteInt(M.R, 2); Files.WriteInt(M.R, F.col);
					Files.WriteInt(M.R, SHORT(F.age MOD N)); Gadgets.framehandle(F, M)
				ELSIF M.id = Objects.load THEN (* load private data here *)
					Files.ReadInt(M.R, x); Files.ReadInt(M.R, F.col);
					IF x > 1 THEN Files.ReadInt(M.R, y); F.age := y ELSE F.age := 0 END;
					Gadgets.framehandle(F, M)
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink	(* copy msg arrives again *)
				ELSE	(* first time copy message arrives *)
					NEW(F0); F.stamp := M.stamp; F.dlink := F0; CopyFrame(M, F, F0); M.obj := F0
				END
			END
		ELSE	(* unknown msg, framehandler might know it *)
			Gadgets.framehandle(F, M)
		END
	END
END FrameHandler;

PROCEDURE New*;
VAR F: Frame;
BEGIN NEW(F); F.W := 52; F.H := 52; F.col := 14 (*Display3.white*); F.age := 0; F.handle := FrameHandler;
	F.state := {Gadgets.lockedsize}; Objects.NewObj := F;
END New;

PROCEDURE Sync*;
VAR msg: SyncMsg;
BEGIN
	msg.F := NIL; Display.Broadcast(msg)
END Sync;

PROCEDURE Step(me: Oberon.Task);
VAR msg: NotifyMsg;
BEGIN
	msg.x := 0;  msg.y := 0;
	msg.F := NIL; Display.Broadcast(msg);
	me.time := Oberon.Time() + Sleep*Input.TimeUnit DIV 1000
END Step;
	
PROCEDURE *Cleanup;
BEGIN
	Oberon.Remove(Task)
END Cleanup;

BEGIN
	LoadFig("Sisiphus.Data");
	NEW(Task); Task.time := 0; Task.safe := FALSE; Task.handle := Step; Oberon.Install(Task);
	Modules.InstallTermHandler(Cleanup)
END Sisiphus.Insert

System.Free Sisiphus ~
Gadgets.Insert Sisiphus.New ~

