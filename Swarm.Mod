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

(* Swarm, Version 1.0 / BES October 96

Please send comments, improvements to Bruno Essmann. (bessmann@iiic.ethz.ch)

Commands
Builder.Compile Swarm.Mod ~	Compile Swarm
System.Free Swarm ~	Get rid of it
Watson.ShowDef Swarm ~	Show Swarm commands
Tasks.Show	Check if the Swarm task is active

Desktops.OpenDoc Swarm.Book ~	Open the Swarm docu
Swarm.Screensaver	Invoke Swarm manually
Swarm.Install	Install the Swarm task
Swarm.Remove	Remove the Swarm task
Gadgets.Insert Swarm.New ~	Insert a Swarm Gadget

Revision History
Oct 25 96	to stay portable Second and Tick are now variables, removed version output to log,
	swarm gadgets no longer age if a parent is selected (looks messy otherwise)
Oct 24 96	changed speed setting, speed is the higher the faster...
Oct 23 96	added public objects for settings in Swarm.Lib and a small Swarm.Book
Oct 20 96	creation of swarm gadgets
Oct 16 96	creation of module

		Notes
		Some statements are not portable (check them out using Search.NotPortable).
		If a transparent gadget is placed on swarm gadget then it is messed up, that's because of
		the way transparent gadgets are handled and cannot be helped.
		Under Oberon System 3 for Windows the screensaver flickers if there are too many bees
		in a swarm, that's obviously a Windows-related problem...
*)

MODULE Swarm;  (** BES, Oct 16 96 - Oct 25 96 *)
	(* Please send comments, improvements to Bruno Essmann. (bessmann@iiic.ethz.ch) *)
	(** Swarm, a simple screensaver for Oberon System 3 *)
	(** Adapted from xswarm by Jeff Butterworth. (butterwo@ncsc.org) *)

	IMPORT
		Display, Display3, Effects, Files, Gadgets, Input, Modules, Oberon, Objects, Printer, Printer3, RandomNumbers, Texts;

	CONST
		Version = 100;  (* version number for swarm gadget *)
				
		MaxSpeed = 10;  (* maximum speed (unit Swarm.Tick) *)
		MouseMove = 3;  (* mouse sensitivity in pixels (per direction) *)

		(* object names for the global screensaver settings stored in Swarm.Lib *)
		SleepObj = "Swarm.Sleep"; SleepDef = 5;  (* default number of minutes before screensaver kicks in *)
		BlankObj = "Swarm.Blank"; BlankDef = TRUE;  (* default blank out screen setting *)
		MinColObj = "Swarm.MinCol"; MinColDef = 16;  (* suppose running in >= 256 color mode *)
		MaxColObj = "Swarm.MaxCol"; MaxColDef = 255;  (* suppose running in >= 256 color mode *)
		SpeedObj = "Swarm.Speed"; SpeedDef = 2;  (* default speed of swarm (unit Swarm.Tick) *)
		SizeObj = "Swarm.Size"; SizeDef = 100;  (* default number of bees in swarm *)
		BorderObj = "Swarm.Border"; BorderDef = 20;  (* default border of wasp *)
		WVelObj = "Swarm.WVel"; WVelDef = 10;  (* default wasp max. velocity *)
		WAccObj = "Swarm.WAcc"; WAccDef = 5;  (* default wasp max. acceleration *)
		BVelObj = "Swarm.BVel"; BVelDef = 12;  (* default bee max. velocity *)
		BAccObj = "Swarm.BAcc"; BAccDef = 2;  (* default bee max. acceleration *)

		(* swarm gadget defaults *)
		GadgetSpeedDef = 5;  (* default speed for gadget *)
		GadgetSizeDef = 50;  (* default swarm size for gadget *)
		GadgetWidthDef = 100;  (* default width of gadget *)
		GadgetHeightDef = 100;  (* default height of gadget *)
		GadgetMinColDef = 16;  (* default minimum color of gadget (256 color mode) *)
		GadgetMaxColDef = 255;  (* default maximum color of gadget (256 color mode) *)
		GadgetBorderDef = 10;  (* default gadget wasp border *)
		GadgetWVelDef = 5;  (* default wasp max. velocity for gadget *)
		GadgetWAccDef = 3;  (* default wasp max. acceleration for gadget *)
		GadgetBVelDef = 6;  (* default bee max. velocity for gadget *)
		GadgetBAccDef = 2;  (* default bee max. acceleration for gadget *)

	TYPE
		Bee = RECORD
			x, y: ARRAY 3 OF INTEGER;  (* bee positions x[time], y[time] *)
			vx, vy: INTEGER;  (* bee velocity *)
		END;
		BeeSwarm = POINTER TO ARRAY OF Bee;
		
		Swarm = POINTER TO SwarmDesc;
		SwarmDesc = RECORD (Gadgets.FrameDesc)
			speed, time: INTEGER;  (* speed of swarm *)
			size: INTEGER;  (* number of bees in swarm *)
			mincol, maxcol, col, colstep: INTEGER;  (* display colors and update step for swarm *)
			wacc, wvel: INTEGER;  (* maximum wasp acceleration and velocity *)
			border: INTEGER;  (* minimum border for wasp *)
			wasp: Bee;  (* the wasp, special kind of bee *)
			bacc, bvel: INTEGER;  (* maximum bee acceleration and velocity *)
			bees: BeeSwarm;  (* the swarm of bees *)
		END;

		Task = POINTER TO TaskDesc;
		TaskDesc = RECORD (Oberon.TaskDesc)
			x, y: INTEGER; keys: SET;  (* mouse state *)
			timeout: LONGINT;  (* timeout of state *)
			ticks: LONGINT;  (* ticks for swarm gadgets *)
		END;
	
		SwarmMsg = RECORD (Display.FrameMsg) END;
	
	VAR
		W: Texts.Writer;  (* everybody needs a writer now and then *)
		task: Task;  (* singleton screensaver task *)
		Second, Tick: LONGINT;
		warn: BOOLEAN;

	(* Swarm *)
	
	PROCEDURE RandomizeSwarm (VAR s: Swarm);
		VAR i, startv: INTEGER;
	BEGIN
		s.wasp.x[0] := s.border+SHORT(ENTIER((s.W-(2*s.border))*RandomNumbers.Uniform())); s.wasp.x[1] := s.wasp.x[0];
		s.wasp.y[0] := s.border+SHORT(ENTIER((s.H-(2*s.border))*RandomNumbers.Uniform())); s.wasp.y[1] := s.wasp.y[0];
		s.wasp.vx := 0; s.wasp.vy := 0;  (* start velocity of wasp is zero *)
		startv := (7*s.bvel) DIV 12; IF startv = 0 THEN startv := 1 END; (* start velocity of bees is 7/12 of maximum velocity *)
		FOR i := 0 TO s.size-1 DO
			s.bees[i].x[0] := SHORT(ENTIER(s.W*RandomNumbers.Uniform())); s.bees[i].x[1] := s.bees[i].x[0];
			s.bees[i].y[0] := SHORT(ENTIER(s.H*RandomNumbers.Uniform())); s.bees[i].y[1] := s.bees[i].y[0];
			s.bees[i].vx := SHORT(ENTIER(startv*RandomNumbers.Uniform())-(startv DIV 2));
			s.bees[i].vy := SHORT(ENTIER(startv*RandomNumbers.Uniform())-(startv DIV 2))
		END
	END RandomizeSwarm;
	
	PROCEDURE InitSwarm (VAR s: Swarm; speed, size, width, height, border, mincol, maxcol, bacc, bvel, wacc, wvel: INTEGER);
	BEGIN
		s.speed := speed; s.time := 0; 
		s.size := size; NEW(s.bees, s.size);
		s.W := width; s.H := height; s.border := border;
		s.mincol := mincol; s.maxcol := maxcol; s.col := s.mincol; s.colstep := 1;
		s.wacc := wacc; s.wvel := wvel; 
		s.bacc := bacc; s.bvel := bvel;
		RandomizeSwarm(s)
	END InitSwarm;

	PROCEDURE ResizeSwarm (s: Swarm; size: INTEGER);
		VAR i, startv: INTEGER;
	BEGIN  (* resizing the swarm forces a redraw *)
		IF size > s.size THEN
			s.size := size; NEW(s.bees, s.size);
			RandomizeSwarm(s)
		ELSE
			s.size := size
		END
	END ResizeSwarm;

	PROCEDURE AgeSwarm (s: Swarm; m: Display3.Mask; x, y: INTEGER);
		(* move and draw wasp and bees without background *)
		VAR i, dx, dy, dist, acc: INTEGER; bees: BeeSwarm;
	BEGIN
		(* handle wasp *)
		s.wasp.x[2] := s.wasp.x[1]; s.wasp.x[1] := s.wasp.x[0];  (* age coordinates... *)
		s.wasp.y[2] := s.wasp.y[1]; s.wasp.y[1] := s.wasp.y[0];
		acc := s.wacc;  (* accelerate... *)
		INC(s.wasp.vx, SHORT(ENTIER(acc*RandomNumbers.Uniform())-(acc DIV 2)));
		INC(s.wasp.vy, SHORT(ENTIER(acc*RandomNumbers.Uniform())-(acc DIV 2)));
		IF s.wasp.vx > s.wvel THEN s.wasp.vx := s.wvel END;  (* check speed limit... *)
		IF s.wasp.vx < -s.wvel THEN s.wasp.vx := -s.wvel END;
		IF s.wasp.vy > s.wvel THEN s.wasp.vy := s.wvel END;
		IF s.wasp.vy < -s.wvel THEN s.wasp.vy := -s.wvel END;
		INC(s.wasp.x[0], s.wasp.vx);  (* move... *)
		INC(s.wasp.y[0], s.wasp.vy);
		IF (s.wasp.x[0] < s.border) OR (s.wasp.x[0] > s.W-s.border) THEN  (* bounce checks... *)
			s.wasp.vx := -s.wasp.vx; INC(s.wasp.x[0], s.wasp.vx)
		END;
		IF (s.wasp.y[0] < s.border) OR (s.wasp.y[0] > s.H-s.border) THEN
			s.wasp.vy := -s.wasp.vy; INC(s.wasp.y[0], s.wasp.vy)
		END;

		(* don't let things settle down *)
		acc := (7*s.bvel) DIV 12; IF acc = 0 THEN acc := 1 END;  (* acceleration is 7/12 of maximum *)
		INC(s.bees[SHORT(ENTIER(s.size*RandomNumbers.Uniform()))].vx, SHORT(ENTIER(acc*RandomNumbers.Uniform())-(acc DIV 2)));
		INC(s.bees[SHORT(ENTIER(s.size*RandomNumbers.Uniform()))].vy, SHORT(ENTIER(acc*RandomNumbers.Uniform())-(acc DIV 2)));

		(* handle bees *)
		bees := s.bees;
		acc := s.bacc;
		FOR i := 0 TO s.size-1 DO
			bees[i].x[2] := bees[i].x[1]; bees[i].x[1] := bees[i].x[0];  (* age coordinates... *)
			bees[i].y[2] := bees[i].y[1]; bees[i].y[1] := bees[i].y[0];
			dx := s.wasp.x[1] - bees[i].x[1]; dy := s.wasp.y[1] - bees[i].y[1];  (* accelerate... *)
			dist := ABS(dx) + ABS(dy);  (* approx. *)
			IF dist = 0 THEN dist := 1 END;  (* always keep some distance *)
			INC(bees[i].vx, (dx*acc) DIV dist); INC(bees[i].vy, (dy*acc) DIV dist);
			IF bees[i].vx > s.bvel THEN bees[i].vx := s.bvel END;  (* check speed limit... *)
			IF bees[i].vx < -s.bvel THEN bees[i].vx := -s.bvel END;
			IF bees[i].vy > s.bvel THEN bees[i].vy := s.bvel END;
			IF bees[i].vy < -s.bvel THEN bees[i].vy := -s.bvel END;
			INC(bees[i].x[0], bees[i].vx);  (* move... *)
			INC(bees[i].y[0], bees[i].vy);
		END;

		(* draw swarm *)
		Display3.Line(m, Display3.FG, Display.solid, x+s.wasp.x[1], y+s.wasp.y[1], x+s.wasp.x[2], y+s.wasp.y[2], 1, Display3.replace);
		FOR i := 0 TO s.size-1 DO  (* paint old bee positions using black *)
			Display3.Line(m, Display3.FG, Display.solid, x+bees[i].x[1], y+bees[i].y[1], x+bees[i].x[2], y+bees[i].y[2], 1, Display3.replace)
		END;
		Display3.Line(m, Display3.BG, Display.solid, x+s.wasp.x[0], y+s.wasp.y[0], x+s.wasp.x[1], y+s.wasp.y[1], 1, Display3.replace);
		INC(s.col, s.colstep);  (* increase, or decrease current swarm color *)
		IF s.col > s.maxcol THEN s.col := s.maxcol; s.colstep := -1 ELSIF s.col < s.mincol THEN s.col := s.mincol; s.colstep := 1 END;
		FOR i := 0 TO s.size-1 DO  (* draw bees *)
			Display3.Line(m, s.col, Display.solid, x+bees[i].x[0], y+bees[i].y[0], x+bees[i].x[1], y+bees[i].y[1], 1, Display3.replace)
		END
	END AgeSwarm;

	PROCEDURE DrawSwarm (s: Swarm; m: Display3.Mask; x, y: INTEGER);
		(* only draw the swarm in its current from with a black background *)
		VAR i: INTEGER; bees: BeeSwarm;
	BEGIN
		bees := s.bees;
		Display3.ReplConst(m, Display.FG, x, y, s.W, s.H, Display.paint);
		Display3.Line(m, Display3.BG, Display.solid, x+s.wasp.x[0], y+s.wasp.y[0], x+s.wasp.x[1], y+s.wasp.y[1], 1, Display3.replace);
		FOR i := 0 TO s.size-1 DO  (* draw bees *)
			Display3.Line(m, s.col, Display.solid, x+bees[i].x[0], y+bees[i].y[0], x+bees[i].x[1], y+bees[i].y[1], 1, Display3.replace)
		END
	END DrawSwarm;

	PROCEDURE PrintSwarm (s: Swarm; M: Display.DisplayMsg);
		(* print swarm with black background, I suppose it only looks good on a color printer *)
		VAR Q: Display3.Mask; i, x, y: INTEGER; bees: BeeSwarm;

		PROCEDURE P(x: INTEGER): INTEGER;
		BEGIN RETURN SHORT(x * LONG(10000) DIV Printer.Unit)
		END P;

	BEGIN
		x := M.x; y := M.y; bees := s.bees;
		Gadgets.MakePrinterMask(s, M.x, M.y, M.dlink, Q);
		Printer3.ReplConst(Q, Display.FG, x, y, s.W, s.H, Display.paint);  (* change this if you don't have a color printer *)
		Printer3.Line(Q, Display3.BG, Display.solid, P(x+s.wasp.x[0]), P(y+s.wasp.y[0]), P(x+s.wasp.x[1]), P(y+s.wasp.y[1]), 1, Display3.replace);
		FOR i := 0 TO s.size-1 DO  (* print bees *)
			Printer3.Line(Q, s.col, Display.solid, P(x+bees[i].x[0]), P(y+bees[i].y[0]), P(x+bees[i].x[1]), P(y+bees[i].y[1]), 1, Display3.replace)
		END
	END PrintSwarm;

	PROCEDURE CopySwarm (from: Swarm; to: Swarm);
		(* deep copy of a swarm *)
		VAR i: INTEGER;
	BEGIN
		to.speed := from.speed; to.time := from.time;
		to.size := from.size; to.W := from.W; to.H := from.H; to.border := from.border;
		to.mincol := from.mincol; to.maxcol := from.maxcol; to.col := from.col; to.colstep := from.colstep;
		to.wacc := from.wacc; to.wvel := from.wvel; to.wasp := from.wasp;
		to.bacc := from.bacc; to.bvel := from.bvel;
		NEW(to.bees, to.size);
		FOR i := 0 TO from.size-1 DO to.bees[i] := from.bees[i] END
	END CopySwarm;


	(* Swarm Gadget *)
	
	PROCEDURE HandleAttributes (s: Swarm; VAR M: Objects.AttrMsg);

		PROCEDURE SetColors (min, max: INTEGER);
			VAR swap: INTEGER;
		BEGIN
			IF (s.mincol = min) & (s.maxcol = max) THEN RETURN END;
			s.mincol := min; s.maxcol := max;
			IF s.mincol > s.maxcol THEN swap := s.mincol; s.mincol := s.maxcol; s.maxcol := swap END;
			s.col := s.mincol; s.colstep := 1;
		END SetColors;
		
		PROCEDURE Resize (size: INTEGER);
		BEGIN
			IF size < 10 THEN size := 10 ELSIF size > 200 THEN size := 200 END;
			IF s.size = size THEN RETURN END;
			ResizeSwarm(s, size);
			Gadgets.Update(s)   (* resizing forces update *)
		END Resize;
	
		PROCEDURE SetInt (VAR x: INTEGER; new, min, max: INTEGER);
		BEGIN
			IF new < min THEN new := min ELSIF new > max THEN new := max END;
			IF x = new THEN RETURN END;
			x := new
		END SetInt;
		
		PROCEDURE SetBorder (border: INTEGER);
			VAR max: INTEGER;
		BEGIN
			IF s.W > s.H THEN max := s.W DIV 2 ELSE max := s.H DIV 2 END;
			SetInt(s.border, border, 0, max);
			IF (s.wasp.x[0] < s.border) OR (s.wasp.x[0] > s.W - s.border) OR (s.wasp.y[0] < s.border) OR (s.wasp.y[0] > s.H - s.border) THEN
				RandomizeSwarm(s);  (* unfortunately the wasp was inside the new border, this forces a re-randomize *)
				Gadgets.Update(s)   (* randomizing forces update *)
			END
		END SetBorder;
	
	BEGIN
		IF M.id = Objects.get THEN
			IF M.name = "Gen" THEN M.class := Objects.String; COPY("Swarm.New", M.s); M.res := 0
			ELSIF M.name = "Swarm Size" THEN M.class := Objects.Int; M.i := s.size; M.res := 0
			ELSIF M.name = "Swarm Speed" THEN M.class := Objects.Int; M.i := MaxSpeed-s.speed; M.res := 0
			ELSIF M.name = "First Color" THEN M.class := Objects.Int; M.i := s.mincol; M.res := 0
			ELSIF M.name = "Last Color" THEN M.class := Objects.Int; M.i := s.maxcol; M.res := 0
			ELSIF M.name = "Wasp Border" THEN M.class := Objects.Int; M.i := s.border; M.res := 0
			ELSIF M.name = "Wasp Acceleration" THEN M.class := Objects.Int; M.i := s.wacc; M.res := 0
			ELSIF M.name = "Wasp Velocity" THEN M.class := Objects.Int; M.i := s.wvel; M.res := 0
			ELSIF M.name = "Bee Acceleration" THEN M.class := Objects.Int; M.i := s.bacc; M.res := 0
			ELSIF M.name = "Bee Velocity" THEN M.class := Objects.Int; M.i := s.bvel; M.res := 0
			ELSIF M.name = "Cmd" THEN
				Gadgets.framehandle(s, M);  (* some black magic since we don't store the CmdAttr in a Swarm object *)
				IF M.res < 0 THEN M.class := Objects.String; M.s := "Swarm.Screensaver"; M.res := 0 END
			ELSE Gadgets.framehandle(s, M)
			END
		ELSIF M.id = Objects.set THEN
			IF M.name = "Swarm Size" THEN IF M.class = Objects.Int THEN Resize(SHORT(M.i)); M.res := 0 END
			ELSIF M.name = "Swarm Speed" THEN  (* set speed, the higher the faster *)
				IF M.class = Objects.Int THEN SetInt(s.speed, MaxSpeed-SHORT(M.i), 0, 10); s.time := 0; M.res := 0 END
			ELSIF M.name = "First Color" THEN IF M.class = Objects.Int THEN SetColors(SHORT(M.i), s.maxcol); M.res := 0 END
			ELSIF M.name = "Last Color" THEN IF M.class = Objects.Int THEN SetColors(s.mincol, SHORT(M.i)); M.res := 0 END
			ELSIF M.name = "Wasp Border" THEN IF M.class = Objects.Int THEN SetBorder(SHORT(M.i)); M.res := 0 END
			ELSIF M.name = "Wasp Acceleration" THEN IF M.class = Objects.Int THEN SetInt(s.wacc, SHORT(M.i), 1, 10); M.res := 0 END
			ELSIF M.name = "Wasp Velocity" THEN IF M.class = Objects.Int THEN SetInt(s.wvel, SHORT(M.i), 2, 20); M.res := 0 END
			ELSIF M.name = "Bee Acceleration" THEN IF M.class = Objects.Int THEN SetInt(s.bacc, SHORT(M.i), 1, 10); M.res := 0 END
			ELSIF M.name = "Bee Velocity" THEN IF M.class = Objects.Int THEN SetInt(s.bvel, SHORT(M.i), 2, 20); M.res := 0 END
			ELSE Gadgets.framehandle(s, M);
			END
		ELSIF M.id = Objects.enum THEN
			M.Enum("Cmd");
			M.Enum("Swarm Size"); M.Enum("Swarm Speed"); M.Enum("First Color"); M.Enum("Last Color");
			M.Enum("Bee Acceleration"); M.Enum("Bee Velocity"); M.Enum("Wasp Acceleration"); M.Enum("Wasp Velocity");
			M.Enum("Wasp Border"); Gadgets.framehandle(s, M)
		END
	END HandleAttributes;

	PROCEDURE Copy (VAR M: Objects.CopyMsg; from, to: Swarm);
	BEGIN CopySwarm(from, to); Gadgets.CopyFrame(M, from, to)
	END Copy;

	PROCEDURE Handle (F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR x, y, w, h, tag: INTEGER; s1: Swarm; Q: Display3.Mask; keysum: SET; inside: BOOLEAN; O: Display3.OverlapMsg; S: SwarmMsg;
		
		PROCEDURE Selected (): BOOLEAN;
			(* return if object or any of its parents is selected, maybe we're overdoing things a bit here but it's well worth the trouble... *)
			VAR obj: Objects.Object;
		BEGIN
			IF Gadgets.selected IN F(Gadgets.Frame).state THEN RETURN TRUE (* object is selected *) END;
			obj := M.dlink;  (* get parent of object (supposing the parent sent this message, otherwise dlink should be NIL) *)
			WHILE obj # NIL DO
				IF obj IS Gadgets.Frame THEN
					IF Gadgets.selected IN obj(Gadgets.Frame).state THEN RETURN TRUE (* parent is selected *) END
				END;
				obj := obj.dlink
			END;
			RETURN FALSE  (* not selected *)
		END Selected;
		
	BEGIN
		WITH F: Swarm DO
			IF M IS Display.FrameMsg THEN
				WITH M: Display.FrameMsg DO
					IF (M.F = NIL) OR (M.F = F) THEN (* message addressed to box *)
						x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
						IF M IS Display.DisplayMsg THEN
							WITH M: Display.DisplayMsg DO
								IF M.device = Display.screen THEN
									IF (M.id = Display.full) OR (M.F = NIL) THEN
										Gadgets.MakeMask(F, x, y, M.dlink, Q);
										Oberon.RemoveMarks(x, y, w, h);
										DrawSwarm(F, Q, x, y);
										IF Gadgets.selected IN F.state THEN
											Display3.FillPattern(Q, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
										END
									ELSIF M.id = Display.area THEN
										Gadgets.MakeMask(F, x, y, M.dlink, Q);
										Display3.AdjustMask(Q, x + M.u, y + h - 1 + M.v, M.w, M.h);
										Oberon.RemoveMarks(x, y, w, h);
										DrawSwarm(F, Q, x, y);
										IF Gadgets.selected IN F.state THEN
											Display3.FillPattern(Q, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
										END
									END
								ELSIF M.device = Display.printer THEN PrintSwarm(F, M)
								END
							END
						ELSIF M IS SwarmMsg THEN
							IF F.time = F.speed THEN  (* the swarm can only be aged on a timeout *)
								F.time := 0;  (* reset timer *)
								IF ~Selected() THEN  (* we cannot redraw if we're selected... *)
									x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
									Gadgets.MakeMask(F, x, y, M.dlink, Q);
									Oberon.RemoveMarks(x, y, w, h);
									AgeSwarm(F, Q, x, y)
								END
							ELSE
								INC(F.time)  (* increment timer *)
							END
						ELSIF M IS Oberon.InputMsg THEN
							WITH M: Oberon.InputMsg DO
								IF (M.id = Oberon.track) & Gadgets.InActiveArea(F, M) & (M.keys = {1}) THEN
									Effects.TrackHighlight(Q, keysum, M.X, M.Y, x, y, w, h);
									IF Effects.Inside(M.X, M.Y, x, y, w, h) & (keysum # {0, 1, 2}) THEN
										Gadgets.ExecuteAttr(F, "Cmd", M.dlink, NIL, NIL)
									END;
									M.res := 0
								ELSE Gadgets.framehandle(F, M)
								END
							END
						ELSIF M IS Display.ModifyMsg THEN
							WITH M: Display.ModifyMsg DO
								IF (F.X # M.X) OR (F.Y # M.Y) OR (F.W # M.W) OR (F.H # M.H) THEN  (* first resize *)
									IF M.W < 32 THEN M.W := 32 END; IF M.H < 32 THEN M.H := 32 END;  (* minimum size is 32x32 *)
									F.X := M.X; F.Y := M.Y; F.W := M.W; F.H := M.H;
									RandomizeSwarm(F);  (* we don't even bother to check if swarm will be visible, we simple redistribute it *)
									O.F := F; O.M := NIL; O.x := 0; O.y := 0; O.res := -1; O.dlink := NIL; F.handle(F, O)  (* send overlapmsg to self *)
								END;
								Gadgets.framehandle(F, M)  (* for whatever there still might be left to do *)
							END
						ELSIF M IS Oberon.ControlMsg THEN Gadgets.framehandle(F, M)
						ELSIF M IS Display.SelectMsg THEN Gadgets.framehandle(F, M)
						ELSIF M IS Display.ConsumeMsg THEN Gadgets.framehandle(F, M)
						ELSE Gadgets.framehandle(F, M)
						END
					END
				END
			ELSIF M IS Objects.AttrMsg THEN HandleAttributes(F, M(Objects.AttrMsg))
			ELSIF M IS Objects.FileMsg THEN
				WITH M: Objects.FileMsg DO
					IF M.id = Objects.store THEN
						Files.WriteInt(M.R, Version);  (* write tag to ensure we can enhance swarm without harming old ones *)
						Files.WriteInt(M.R, F.speed); Files.WriteInt(M.R, F.size); Files.WriteInt(M.R, F.mincol); Files.WriteInt(M.R, F.maxcol);
						Files.WriteInt(M.R, F.bacc); Files.WriteInt(M.R, F.bvel); Files.WriteInt(M.R, F.wacc); Files.WriteInt(M.R, F.wvel);
						Files.WriteInt(M.R, F.border); Gadgets.framehandle(F, M)
					ELSIF M.id = Objects.load THEN
						Files.ReadInt(M.R, tag);
						IF tag # Version THEN  (* only one version at the moment... *)
						ELSE
							Files.ReadInt(M.R, F.speed); Files.ReadInt(M.R, F.size); Files.ReadInt(M.R, F.mincol); Files.ReadInt(M.R, F.maxcol);
							Files.ReadInt(M.R, F.bacc); Files.ReadInt(M.R, F.bvel); Files.ReadInt(M.R, F.wacc); Files.ReadInt(M.R, F.wvel);
							Files.ReadInt(M.R, F.border); Gadgets.framehandle(F, M);
							InitSwarm(F, F.speed, F.size, F.W, F.H, F.border, F.mincol, F.maxcol, F.bacc, F.bvel, F.wacc, F.wvel)
						END
					END
				END
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					IF M.stamp = F.stamp THEN M.obj := F.dlink (*non-first arrival*)
					ELSE (*first arrival*)
						NEW(s1); F.stamp := M.stamp; F.dlink := s1;
						Copy(M, F, s1); M.obj := s1
					END
				END
			ELSE Gadgets.framehandle(F, M)
			END
		END
	END Handle;

	PROCEDURE Init (s: Swarm);
	BEGIN
		InitSwarm(s, GadgetSpeedDef, GadgetSizeDef, GadgetWidthDef, GadgetHeightDef,
			GadgetBorderDef, GadgetMinColDef, GadgetMaxColDef,
			GadgetBAccDef, GadgetBVelDef, GadgetWAccDef, GadgetWVelDef);
		s.handle := Handle
	END Init;
	
	PROCEDURE New*;	(** The generator procedure for Swarm gadgets *)
	VAR s: Swarm;
	BEGIN
		NEW(s); Init(s);  (* create and initialize swarm *)
		Objects.NewObj := s  (* deposit *)
	END New;

	PROCEDURE Exec*;	(** Simple executor procedure to call more than one command from a button *)
		(* simple trick to execute more than one command in a row, separator is a comma *)
		VAR i: INTEGER; s: ARRAY 255 OF CHAR; R: Texts.Reader; ch: CHAR;
			executor, dlink, sender, receiver: Objects.Object;
	BEGIN
		executor := Gadgets.executorObj; dlink := Gadgets.context; sender := Gadgets.senderObj; receiver := Gadgets.receiverObj;
		Texts.OpenReader(R, Oberon.Par.text, Oberon.Par.pos); Texts.Read(R, ch);
		WHILE ~R.eot DO  (* here we rely on the fact that a new text is set up for the Exec command, therefore the whole text contains commands *)
			i := 0; WHILE ~R.eot & (ch # '~') & (ch # ';') DO s[i] := ch; Texts.Read(R, ch); INC(i) END; s[i] := 0X;
			Gadgets.Execute(s, executor, dlink, sender, receiver);
			Texts.Read(R, ch); WHILE ch = ' ' DO Texts.Read(R, ch) END
		END
	END Exec;


	(* Screensaver Settings *)

	PROCEDURE Warning (name: ARRAY OF CHAR);
	BEGIN
		IF warn THEN
			Texts.WriteString(W, "Swarm: public object '"); Texts.WriteString(W, name);
			Texts.WriteString(W, "' not found"); Texts.WriteLn(W);
			Texts.WriteString(W, "Make sure the Swarm.Lib is present!"); Texts.WriteLn(W);
			Texts.WriteString(W, "Using defaults until Swarm.Lib is found"); Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf);
			warn := FALSE  (* disable further warnings, once should be enough... *)
		END
	END Warning;

	PROCEDURE GetBool (name: ARRAY OF CHAR; default: BOOLEAN): BOOLEAN;
		(* return positive longint model of public object name, or default if failure *)
		VAR L: Objects.LinkMsg; A: Objects.AttrMsg; obj: Objects.Object;
	BEGIN
		obj := Gadgets.FindPublicObj(name);
		IF obj # NIL THEN
			L.id := Objects.get; L.res := -1; L.name := "Model";
			obj.handle(obj, L); (* get model of this object *)
			IF L.res >= 0 THEN
				A.id := Objects.get; A.name := "Value"; A.res := -1; A.class := Objects.Inval;
				L.obj.handle(L.obj, A);
				IF (A.res >= 0) & (A.class = Objects.Bool) THEN
					RETURN A.b  (* return value of model *)
				END
			END
		END;
		Warning(name); RETURN default  (* some error occured, return default *)
	END GetBool;

	PROCEDURE GetInt (name: ARRAY OF CHAR; default: LONGINT): LONGINT;
		(* return longint model of public object name, or default if failure *)
		VAR L: Objects.LinkMsg; A: Objects.AttrMsg; obj: Objects.Object;
	BEGIN
		obj := Gadgets.FindPublicObj(name);
		IF obj # NIL THEN
			L.id := Objects.get; L.res := -1; L.name := "Model";
			obj.handle(obj, L); (* get model of this object *)
			IF L.res >= 0 THEN
				A.id := Objects.get; A.name := "Value"; A.res := -1; A.class := Objects.Inval;
				L.obj.handle(L.obj, A);
				IF (A.res >= 0) & (A.class = Objects.Int) THEN
					RETURN A.i  (* return value of model *)
				END
			END
		END;
		Warning(name); RETURN default  (* some error occured, return default *)
	END GetInt;

	PROCEDURE GetSleepTime (): LONGINT;
		VAR sleep: LONGINT;
	BEGIN
		sleep := GetInt(SleepObj, SleepDef);
		IF sleep < 1 THEN sleep := 1 END;  (* can't prevent user from setting stupid sleep time *)
		RETURN sleep*60*Second  (* return sleep time in Input.Ticks *)
	END GetSleepTime;
	

	(* Screensaver *)
	
	PROCEDURE FadeAway (): BOOLEAN;  (* dummy procedure to blank screen *)
		VAR minx, miny, maxx, maxy: INTEGER; keys: SET;

		PROCEDURE Fade (pat: Display.Pattern; delay: LONGINT): BOOLEAN;
			CONST steps = 32;
			VAR i, x, y: INTEGER; time: LONGINT;
		BEGIN
			FOR i := 0 TO steps-1 DO
				y := Display.Height-i;
				WHILE y >= 0 DO
					Display.ReplPattern(Display.FG, pat, 0, y, Display.Width, 1, Display.paint);
					DEC(y, steps)
				END;
				Input.Mouse(keys, x, y);
				IF (Input.Available() > 0) OR (keys # {}) OR (x < minx) OR (x > maxx) OR (y < miny) OR (y > maxy) THEN RETURN FALSE END;
				time := Input.Time() + delay;
				REPEAT UNTIL Input.Time() > time
			END;
			RETURN TRUE
		END Fade;
		
	BEGIN
		IF ~GetBool(BlankObj, BlankDef) THEN RETURN TRUE END;
		Input.Mouse(keys, minx, miny); maxx := minx+MouseMove; maxy := miny+MouseMove;
		DEC(minx, MouseMove); DEC(miny, MouseMove);
		IF Fade(Display.grey0, Second DIV 100) THEN
			IF Fade(Display.grey1, Second DIV 50) THEN
				RETURN Fade(Display.solid, Second DIV 25)
			END
		END;
		RETURN FALSE
	END FadeAway;

	PROCEDURE SwarmOut (speed, size, border, mincol, maxcol, bacc, bvel, wacc, wvel: INTEGER);
		VAR s: Swarm; m: Display3.Mask; minx, miny, maxx, maxy, x, y: INTEGER; keys: SET; msg: Display.ControlMsg; tdiff, timeout: LONGINT;
	BEGIN
		Oberon.RemoveMarks(0, 0, Display.Width, Display.Height);
		IF FadeAway() THEN
			NEW(s); InitSwarm(s, 1, size, Display.Width, Display.Height, border, mincol, maxcol, bacc, bvel, wacc, wvel);
			NEW(m); Display3.Open(m); Display3.Add(m, 0, 0, Display.Width, Display.Height);  (* new mask for entire display *)
			Input.Mouse(keys, minx, miny); maxx := minx+MouseMove; maxy := miny+MouseMove;
			DEC(minx, MouseMove); DEC(miny, MouseMove);
			tdiff := (MaxSpeed-speed)*Tick;
			REPEAT
				AgeSwarm(s, m, 0, 0);
				timeout := Input.Time()+tdiff;
				REPEAT UNTIL Input.Time() > timeout;
				Input.Mouse(keys, x, y)
			UNTIL (Input.Available() > 0) OR (keys # {}) OR (x < minx) OR (x > maxx) OR (y < miny) OR (y > maxy)
		END;
		msg.id := Display.restore; Display.Broadcast(msg)
	END SwarmOut;

	(*L Swarm.Screensaver *)
	PROCEDURE Screensaver*;	(** Use Swarm.Screensaver to start Swarm manually *)
	BEGIN
		SwarmOut(SHORT(GetInt(SpeedObj, SpeedDef)), SHORT(GetInt(SizeObj, SizeDef)), SHORT(GetInt(BorderObj, BorderDef)),
			SHORT(GetInt(MinColObj, MinColDef)), SHORT(GetInt(MaxColObj, MaxColDef)), 
			SHORT(GetInt(BAccObj, BAccDef)), SHORT(GetInt(BVelObj, BVelDef)),
			SHORT(GetInt(WAccObj, WAccDef)), SHORT(GetInt(WVelObj, WVelDef)))
 	END Screensaver;


	(* Screensaver Task *)
	
	PROCEDURE TaskHandler (task: Oberon.Task);
		VAR x, y: INTEGER; keys: SET; time: LONGINT; msg: SwarmMsg;
	BEGIN
		WITH task: Task DO
			time := Input.Time();
			IF time > task.ticks THEN  (* time to broadcast update message? *)
				Display.Broadcast(msg);  (* notify all swarm gadgets to update if they received enough update messages *)
				task.ticks := time+Tick
			END;
			Input.Mouse(keys, x, y);
			IF (x # task.x) OR (y # task.y) OR (keys # task.keys) THEN
				task.x := x; task.y := y; task.keys := keys;
				task.timeout := time+GetSleepTime()  (* reset timeout *)
			ELSIF time >= task.timeout THEN
				Screensaver;  (* action! *)
				Input.Mouse(task.keys, task.x, task.y);  (* initialize task state *)
				task.timeout := Input.Time()+GetSleepTime()  (* reset timeout *)
			END
		END
	END TaskHandler;
	
	PROCEDURE* RemoveTask;
	BEGIN
		IF task = NIL THEN RETURN END;  (* nothing to remove *)
		Oberon.Remove(task);  (* if we're kicked out, then at least gracefully! *)
		task := NIL  (* prepare later re-installation *)
	END RemoveTask;
	
	PROCEDURE InstallTask;
	BEGIN
		IF task # NIL THEN RETURN END;  (* already installed *)
		NEW(task); task.safe := FALSE; task.time := 0; task.handle := TaskHandler;  (* initialize oberon task *)
		Input.Mouse(task.keys, task.x, task.y); task.timeout := Input.Time()+GetSleepTime();  (* initialize task state *)
		Oberon.Install(task)  (* install task in oberon loop *)
	END InstallTask;

	(*L Swarm.Install *)
	PROCEDURE Install*;	(** Use Swarm.Install in the System, InitCommands section of Oberon.Text *)
	BEGIN
		IF task # NIL THEN RETURN END;  (* already installed *)
		InstallTask;
		Texts.WriteString(W, "Swarm enabled ("); 
		Texts.WriteString(W, "sleep time "); Texts.WriteInt(W, GetSleepTime() DIV (60*Second), 1);
		Texts.WriteString(W, " minutes)"); Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf)
	END Install;

	(*L Swarm.Remove *)
	PROCEDURE Remove*;	(** Use Swam.Remove to disable Swarm *)
	BEGIN
		IF task = NIL THEN RETURN END;  (* nothing to remove *)
		RemoveTask;
		Texts.WriteString(W, "Swarm disabled."); Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf)
	END Remove;

BEGIN
	Second := Input.TimeUnit; Tick := Second DIV 100;  (* to stay portable *)
	Texts.OpenWriter(W);
	warn := TRUE;  (* enable warnings *)
	task := NIL; InstallTask;  (* install task immediately (without message in the log) *)
	(* not portable, Native Oberon version: *)
	Modules.InstallTermHandler(RemoveTask)  (* install termination handler (to cleanup task) *)
END Swarm.
