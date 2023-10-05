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

MODULE Scrollbars;	(** portable *)		(** ps (based on sources of rv and Effects),   *)

	IMPORT
		Input, Files, Effects, Printer, Printer3, Display3, Oberon, Objects, Display, Gadgets, Attributes;
	
	CONST
		VersionNo = 1; barW = 18;

		(** frame states *)
		hasarrows* = 0;
		dodrag* = 1;

	TYPE
		Frame* = POINTER TO FrameDesc;
		FrameDesc* = RECORD (Gadgets.FrameDesc)
			state0*: SET;
			backC*, knoblen: INTEGER;
			min*, max*, step*, val*: LONGINT;
			stepO*, minO*, maxO*: Objects.Object;
			vertical*: BOOLEAN
		END;

	VAR
		HoldTime, WaitTime, mayscroll: LONGINT;

	PROCEDURE TimeOk (): BOOLEAN;
	BEGIN
		IF Oberon.Time() - mayscroll <= 0 THEN RETURN FALSE
		ELSE mayscroll := Oberon.Time() + WaitTime; RETURN TRUE
		END
	END TimeOk;

	(* Given a position, calculate the relative slider position. *)
	PROCEDURE Value (F: Frame; x, y, w, h, X, Y: INTEGER; min, max: LONGINT): LONGINT;
	VAR res: LONGINT;

		PROCEDURE CalcVal (x, w, bx, bw: INTEGER; min, max: LONGINT): LONGINT;
		VAR r, d: LONGINT;
		BEGIN
			d := max - min;
			IF d = 0 THEN r := 0
			ELSE
				r := (bx - x - bw DIV 2) * d DIV (w - bw);
				r := min + r;
				IF min > max THEN d :=  max; max := min; min := d END;
				IF r > max THEN r := max ELSIF r < min THEN r := min END
			END;
			RETURN r
		END CalcVal;

	BEGIN
		IF F.vertical THEN res := CalcVal(y, h, Y, F.knoblen, min, max)
		ELSE res := CalcVal(x, w, X, F.knoblen, min, max)
		END;
		RETURN res
	END Value;

	(* Given the min, max and val, calculate the absolute bar position *)
	PROCEDURE Pos (F: Frame; x, y, w, h, bw: INTEGER; min, max, val: LONGINT): INTEGER;
	VAR res: INTEGER;

		PROCEDURE CalcPos (x, w, bw: INTEGER; min, max, val: LONGINT): INTEGER;
		VAR d: LONGINT;
		BEGIN
			d := ABS(max - min);
			IF d = 0 THEN RETURN x
			ELSE
				IF max > min THEN
					IF val < min THEN val := min ELSIF val > max THEN val := max END
				ELSE
					IF val > min THEN val := min ELSIF val < max THEN val := max END
				END;
				val := ABS(val - min);
				RETURN SHORT(x + val * (w - bw) DIV d)
			END
		END CalcPos;

	BEGIN
		IF F.vertical THEN res := CalcPos(y, h, bw, min, max, val)
		ELSE res := CalcPos(x, w, bw, min, max, val)
		END;
		RETURN res
	END Pos;

	PROCEDURE SendUpdate (F: Frame; px, py: INTEGER; dlink: Objects.Object; full: BOOLEAN);
	VAR D: Display.DisplayMsg;
	BEGIN
		D.device := Display.screen; D.id := Display.area; D.dlink := dlink;
		D.F := F; D.x := px; D.y := py; D.res := -1;
		IF full THEN D.id := Display.full
		ELSE
			D.u := 1; D.v := -F.H + 2; D.w := F.W - 2; D.h := F.H - 2;
			IF hasarrows IN F.state0 THEN
				IF F.vertical THEN INC(D.v, barW); DEC(D.h, 2*barW)
				ELSE INC(D.u, barW); DEC(D.w, 2*barW)
				END
			END
		END;
		F.handle(F, D)
	END SendUpdate;

	PROCEDURE SetValue (F: Frame; val: LONGINT);
	VAR name: ARRAY 64 OF CHAR;
	BEGIN
		F.val := val;
		IF F.obj # NIL THEN
			Attributes.GetString(F, "Field", name); IF name = "" THEN name := "Value" END;
			Attributes.SetInt(F.obj, name, val); Gadgets.Update(F.obj)
		END
	END SetValue;

	PROCEDURE SetValueAndUpdate (F: Frame; val: LONGINT; px, py: INTEGER; dlink: Objects.Object);
	VAR name: ARRAY 64 OF CHAR;
	BEGIN
		F.val := val;
		IF F.obj # NIL THEN
			Attributes.GetString(F, "Field", name); IF name = "" THEN name := "Value" END;
			Attributes.SetInt(F.obj, name, val); Gadgets.Update(F.obj)
		ELSE SendUpdate(F, px, py, dlink, FALSE)
		END
	END SetValueAndUpdate;

	PROCEDURE GetValue (F: Frame);
	VAR name: ARRAY 64 OF CHAR;
	BEGIN
		IF F.obj # NIL THEN
			Attributes.GetString(F, "Field", name); IF name = "" THEN name := "Value" END;
			Attributes.GetInt(F.obj, name, F.val)
		END
	END GetValue;

	PROCEDURE AdjustKnoblen (F: Frame);
	VAR W: INTEGER; kl: LONGINT;
	BEGIN
		IF F.minO # NIL THEN Attributes.GetInt(F.minO, "Value", F.min) END;
		IF F.maxO # NIL THEN Attributes.GetInt(F.maxO, "Value", F.max) END;
		IF F.vertical THEN W := F.H ELSE W := F.W END;
		IF hasarrows IN F.state0 THEN DEC(W, 2*barW) END;
		kl := LONG(W) - 2 - ABS(F.max - F.min);
		IF kl < barW THEN kl := barW END;
		F.knoblen := SHORT(kl)
	END AdjustKnoblen;
	
	PROCEDURE DrawKnob (Q: Display3.Mask; x, y, w, h: INTEGER; vertical: BOOLEAN);
	VAR m: INTEGER;
	BEGIN
		IF vertical THEN
			Display3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.groupC, x, y, w, h, 1, Display3.replace);
			m := y + h DIV 2; INC(x, 2); DEC(w, 4);
			Display3.ReplConst(Q, Display3.bottomC, x, m - 2, w, 1, Display3.replace);
			Display3.ReplConst(Q, Display3.topC, x, m - 1, w, 1, Display3.replace);
			Display3.ReplConst(Q, Display3.bottomC, x, m + 1, w, 1, Display3.replace);
			Display3.ReplConst(Q, Display3.topC, x, m + 2, w, 1, Display3.replace)
		ELSE
			Display3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.groupC, x, y, w, h, 1, Display3.replace);
			m := x + w DIV 2; INC(y, 2); DEC(h, 4);
			Display3.ReplConst(Q, Display3.topC, m - 2, y, 1, h, Display3.replace);
			Display3.ReplConst(Q, Display3.bottomC, m - 1, y, 1, h, Display3.replace);
			Display3.ReplConst(Q, Display3.topC, m + 1, y, 1, h, Display3.replace);
			Display3.ReplConst(Q, Display3.bottomC, m + 2, y, 1, h, Display3.replace)
		END
	END DrawKnob;

	PROCEDURE RestoreFrame (F: Frame; Q: Display3.Mask; x, y, w, h: INTEGER);
	VAR i : INTEGER;
	BEGIN
		Oberon.RemoveMarks(x, y, w, h);
		Display3.FilledRect3D(Q, Display3.bottomC, Display3.topC, F.backC, x, y, w, h, 1, Display3.replace);

		(* draw inside *)
		INC(x); INC(y); DEC(w, 2); DEC(h, 2);
		IF F.vertical THEN
			IF hasarrows IN F.state0 THEN
				(* Down button box *)
				Display3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.groupC, x, y, w, barW - 1, 1, Display3.replace);
				Display3.ReplConst(Q, Display3.FG, x, y + barW - 1, w, 1, Display3.replace);
				(* Up button box *)
				Display3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.groupC, x, y + h - barW + 1, w, barW - 1, 1, Display3.replace);
				Display3.ReplConst(Q, Display3.FG, x, y + h - barW, w, 1, Display3.replace);
				(* Triangles *)
				FOR i := -4 TO 1 DO
					Display3.ReplConst(Q, Display3.FG, x + w DIV 2 + i, y + barW DIV 3 - i, -i*2, 1, Display3.replace);
					Display3.ReplConst(Q, Display3.FG, x + w DIV 2 + i, y + h - barW DIV 3 + i, -i*2, 1, Display3.replace);
				END;
				DrawKnob(Q, x, Pos(F, x, y + barW, w, h - 2*barW, F.knoblen, F.min, F.max, F.val), w, F.knoblen, TRUE)
			ELSE
				DrawKnob(Q, x, Pos(F, x, y, w, h, F.knoblen, F.min, F.max, F.val), w, F.knoblen, TRUE)
			END
		ELSE	(* horizontal *)
			IF hasarrows IN F.state0 THEN
				(* Left button box *)
				Display3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.groupC, x, y, barW - 1, h, 1, Display3.replace);
				Display3.ReplConst(Q, Display3.FG, x + barW - 1, y, 1, h, Display3.replace);
				(* Right button box *)
				Display3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.groupC, x + w - barW + 1, y, barW-1, h, 1, Display3.replace);
				Display3.ReplConst(Q, Display3.FG, x + w - barW, y, 1, h, Display3.replace);
				(* Triangles *)
				FOR i := -4 TO 1 DO
					Display3.ReplConst(Q, Display3.FG, x + barW DIV 3 - i, y + h DIV 2 + i, 1, -i*2, Display3.replace);
					Display3.ReplConst(Q, Display3.FG, x + w - barW DIV 3 + i, y + h DIV 2 + i, 1, -i*2, Display3.replace);
				END;
				DrawKnob(Q, Pos(F, x + barW, y, w - 2*barW, h, F.knoblen, F.min, F.max, F.val), y, F.knoblen, h, FALSE)
			ELSE
				DrawKnob(Q, Pos(F, x, y, w, h, F.knoblen, F.min, F.max, F.val), y, F.knoblen, h, FALSE)
			END
		END;
		DEC(x); DEC(y); INC(w, 2); INC(h, 2);

		IF Gadgets.selected IN F.state THEN
			Display3.FillPattern(Q, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
		END
	END RestoreFrame;

	PROCEDURE P (x: LONGINT): INTEGER;
	BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
	END P;
	
	PROCEDURE PrintKnob (Q: Display3.Mask; x, y, w, h: INTEGER; vertical: BOOLEAN);
	VAR m: INTEGER;
	BEGIN
		IF vertical THEN
			Printer3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.groupC, x, y, w, h, P(1), Display3.replace);
			m := y + h DIV 2; INC(x, P(2)); DEC(w, P(4));
			Printer3.ReplConst(Q, Display3.bottomC, x, m-P(2), w, P(1), Display3.replace);
			Printer3.ReplConst(Q, Display3.topC, x, m-P(1), w, P(1), Display3.replace);
			Printer3.ReplConst(Q, Display3.bottomC, x, m+P(1), w, P(1), Display3.replace);
			Printer3.ReplConst(Q, Display3.topC, x, m+P(2), w, P(1), Display3.replace)
		ELSE
			Printer3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.groupC, x, y, w, h, P(1), Display3.replace);
			m := x + w DIV 2; INC(y, P(2)); DEC(h, P(4));
			Printer3.ReplConst(Q, Display3.topC, m-P(2), y, P(1), h, Display3.replace);
			Printer3.ReplConst(Q, Display3.bottomC, m-P(1), y+2, P(1), h, Display3.replace);
			Printer3.ReplConst(Q, Display3.topC, m+P(1), y, P(1), h, Display3.replace);
			Printer3.ReplConst(Q, Display3.bottomC, m+P(2), y, P(1), h, Display3.replace)
		END
	END PrintKnob;

	PROCEDURE PrintFrame (F: Frame; VAR M: Display.DisplayMsg);
	VAR Q: Display3.Mask; x, y, w, h, barw, knoblen, one, i : INTEGER;
	BEGIN
		Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, Q);
		x := M.x; y := M.y; w := P(F.W); h := P(F.H); barw := P(barW); knoblen := P(F.knoblen); one := P(1);
		Printer3.FilledRect3D(Q, Display3.bottomC, Display3.topC, F.backC, x, y, w, h, P(1), Display3.replace);
		INC(x, one); INC(y, one); DEC(w, P(2)); DEC(h, P(2));
		IF F.vertical THEN
			IF hasarrows IN F.state0 THEN
				(* Down button box *)
				Printer3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.groupC,
													x, y, w, barw - one, one, Display3.replace);
				Printer3.ReplConst(Q, Display3.FG, x, y + barw - one, w, one, Display3.replace);
				(* Up button box *)
				Printer3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.groupC,
													x, y + h - barw + one, w, barw - one, one, Display3.replace);
				Printer3.ReplConst(Q, Display3.FG, x, y + h - barw, w, one, Display3.replace);
				(* Triangles *)
				FOR i := -P(4) TO 1 DO
					Printer3.ReplConst(Q, Display3.FG, x + w DIV 2 + i, y+barw DIV 3 - i, -i*2, 1, Display3.replace);
					Printer3.ReplConst(Q, Display3.FG, x + w DIV 2 + i, y+h-barw DIV 3 + i, -i*2, 1, Display3.replace);
				END;
				y := Pos(F, x, y + barw, w, h - 2*barw, knoblen, F.min, F.max, F.val)
			ELSE
				y := Pos(F, x, y, w, h, knoblen, F.min, F.max, F.val)
			END;
			PrintKnob(Q, x, y, w, knoblen, TRUE)
		ELSE
			IF hasarrows IN F.state0 THEN
				(* Left button box *)
				Printer3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.groupC,
													x, y, barw - one, h, one, Display3.replace);
				Printer3.ReplConst(Q, Display3.FG, x+ barw - one, y, one, h, Display3.replace);
				(* Right button box *)
				Printer3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.groupC,
													x + w - barw + one, y, barw - one, h, one, Display3.replace);
				Printer3.ReplConst(Q, Display3.FG, x + w - barw, y, one, h, Display3.replace);
				(* Triangles *)
				FOR i := -P(4) TO 1 DO
					Printer3.ReplConst(Q, Display3.FG, x + barw DIV 3 - i, y + h DIV 2 + i, 1, -i*2, Display3.replace);
					Printer3.ReplConst(Q, Display3.FG, x + w - barw DIV 3 + i, y+h DIV 2 + i, 1, -i*2, Display3.replace);
				END;
				x := Pos(F, x + barw, y, w - 2*barw, h, knoblen, F.min, F.max, F.val)
			ELSE
				x := Pos(F, x, y, w, h, knoblen, F.min, F.max, F.val)
			END;
			PrintKnob(Q, x, y, knoblen, h, FALSE)
		END
	END PrintFrame;

	PROCEDURE TrackFrame (F: Frame; x, y, w, h: INTEGER; VAR M: Oberon.InputMsg);
	VAR Q: Display3.Mask; keysum: SET; n: INTEGER; pos, npos, dpos, oldpos: LONGINT;
	
		PROCEDURE Pushed (x, y, w, h: INTEGER; step: LONGINT);
		VAR pos: LONGINT; on, newstate: BOOLEAN;
		
			PROCEDURE On (): BOOLEAN;
			BEGIN RETURN Effects.Inside(M.X, M.Y, x, y, w, h)
			END On;
			
			PROCEDURE Highlight;
			BEGIN Oberon.FadeCursor(Oberon.Mouse); Display3.ReplConst(Q, Display.FG, x, y, w, h, Display.invert)
			END Highlight;

			PROCEDURE SetNewValue;
			BEGIN
				IF F.min < F.max THEN
					INC(pos, step); IF pos < F.min THEN pos := F.min ELSIF pos > F.max THEN pos := F.max END
				ELSE
					DEC(pos, step); IF pos > F.min THEN pos := F.min ELSIF pos < F.max THEN pos := F.max END
				END;
				IF F.val # pos THEN SetValueAndUpdate(F, pos, M.x, M.y, M.dlink) END
			END SetNewValue;
		
		BEGIN
			Display3.Copy(Q, Q);
			on := FALSE; pos := F.val;
			keysum := M.keys;
			mayscroll := Oberon.Time() + HoldTime; SetNewValue;
			WHILE M.keys # {} DO
				newstate := On();
				IF newstate & TimeOk() THEN SetNewValue END;
				IF newstate # on THEN on := newstate; Highlight END;
				Input.Mouse(M.keys, M.X, M.Y); keysum := keysum+M.keys;
				Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, M.X, M.Y)
			END;
			IF on THEN Highlight END
		END Pushed;
		
	BEGIN
		Gadgets.MakeMask(F, x, y, M.dlink, Q);
		keysum := M.keys;
		oldpos := F.val;
		INC(x, 1); INC(y, 1); DEC(w, 2); DEC(h, 2);

		IF (hasarrows IN F.state0) & (~F.vertical & ~Effects.Inside(M.X, M.Y, x + barW, y, w - 2*barW, h)
		 OR F.vertical & ~Effects.Inside(M.X, M.Y, x, y + barW, w, h - 2*barW)) THEN	(* Relative scroll with arrow buttons *)
			IF F.vertical THEN
				IF Effects.Inside(M.X, M.Y, x, y, w, barW) THEN
					Pushed(x, y, w, barW, -F.step)	(* Down button *)
				ELSIF Effects.Inside(M.X, M.Y, x, y + h - barW, w, barW) THEN
					Pushed(x, y + h - barW, w, barW, F.step)	(* Up button *)
				END
			ELSE
				IF Effects.Inside(M.X, M.Y, x, y, barW, h) THEN
					Pushed(x, y, barW, h, -F.step)	(* Left button *)
				ELSIF Effects.Inside(M.X, M.Y, x + w - barW, y, barW, h)THEN
					Pushed(x + w - barW, y, barW, h, F.step)	(* Right button *)
				END
			END
		ELSE	(* Absolute scroll using knob *)
			pos := F.val; dpos := pos;
			IF hasarrows IN F.state0 THEN
				IF F.vertical THEN INC(y, barW); DEC(h, 2*barW) ELSE INC(x, barW); DEC(w, 2*barW) END
			END;
			IF ~(dodrag IN F.state0) THEN
				IF F.vertical THEN
					n := Pos(F, x, y, w, h, F.knoblen, F.min, F.max, pos);
					Display3.Rect(Q, Display3.groupC, Display3.selectpat, x, n, w, F.knoblen, 2, Display3.invert)
				ELSE
					n := Pos(F, x, y, w, h, F.knoblen, F.min, F.max, pos);
					Display3.Rect(Q, Display3.groupC, Display3.selectpat, n, y, F.knoblen, h, 2, Display3.invert)
				END
			END;
			REPEAT
				npos := Value(F, x, y, w, h, M.X, M.Y, F.min, F.max);
				IF npos # pos THEN (* new position *)
					Oberon.FadeCursor(Oberon.Mouse);
					IF ~(dodrag IN F.state0) THEN	(* draw a drag indicator *)
						IF F.vertical THEN
							Display3.Rect(Q, Display3.groupC, Display3.selectpat, x, n, w, F.knoblen, 2, Display3.invert);
							n := Pos(F, x, y, w, h, F.knoblen, F.min, F.max, npos);
							Display3.Rect(Q, Display3.groupC, Display3.selectpat, x, n, w, F.knoblen, 2, Display3.invert)
						ELSE
							Display3.Rect(Q, Display3.groupC, Display3.selectpat, n, y, F.knoblen, h, 2, Display3.invert);
							n := Pos(F, x, y, w, h, F.knoblen, F.min, F.max, npos);
							Display3.Rect(Q, Display3.groupC, Display3.selectpat, n, y, F.knoblen, h, 2, Display3.invert)
						END
					ELSIF ((ABS(npos - dpos) > F.step) OR (npos = F.min) OR (npos = F.max)) THEN
						dpos := npos; SetValueAndUpdate(F, npos, M.x, M.y, M.dlink)
					END;
					pos := npos
				END;
				Input.Mouse(M.keys, M.X, M.Y); keysum := keysum + M.keys;
				Oberon.DrawCursor(Oberon.Mouse, Effects.FlatHand, M.X, M.Y)
			UNTIL M.keys = {};
			IF ~(dodrag IN F.state0) THEN SetValueAndUpdate(F, npos, M.x, M.y, M.dlink) END
		END;
		IF keysum = {0, 1, 2} THEN SetValueAndUpdate(F, oldpos, M.x, M.y, M.dlink)
		ELSIF keysum = {1} THEN Gadgets.ExecuteAttr(F, "Cmd", M.dlink, F, NIL)
		END
	END TrackFrame;

	PROCEDURE UpdateFrame (F: Frame; VAR M: Gadgets.UpdateMsg);
	BEGIN
		IF F.obj # NIL THEN F.obj.handle(F.obj, M) END;
		IF F.minO # NIL THEN F.minO.handle(F.minO, M) END;
		IF F.maxO # NIL THEN F.maxO.handle(F.maxO, M) END;
		IF F.stepO # NIL THEN F.stepO.handle(F.stepO, M) END;
		IF (M.obj = F.obj) THEN
			IF F.stamp # M.stamp THEN F.stamp := M.stamp; GetValue(F) END;
			SendUpdate(F, M.x, M.y, M.dlink, FALSE)
		ELSIF (M.obj = F.minO) OR (M.obj = F.maxO) THEN
			IF F.stamp # M.stamp THEN F.stamp := M.stamp; AdjustKnoblen(F) END;
			SendUpdate(F, M.x, M.y, M.dlink, FALSE)
		ELSIF M.obj = F.stepO THEN
			IF F.stamp # M.stamp THEN
				F.stamp := M.stamp; Attributes.GetInt(M.obj, "Value", F.step)
			END
		ELSE Gadgets.framehandle(F, M)
		END
	END UpdateFrame;

	PROCEDURE ModifyFrame (F: Frame; VAR M: Display.ModifyMsg);
	VAR O: Display3.OverlapMsg;
	BEGIN
		IF F.stamp # M.stamp THEN
			F.stamp := M.stamp;
			F.X := M.X; F.Y := M.Y; F.W := M.W; F.H := M.H;
			O.F := F; O.M := NIL; O.x := 0; O.y := 0; O.res := -1; O.dlink := NIL; F.handle(F, O);
			AdjustKnoblen(F)
		END;
		IF (M.mode = Display.display) & (F.H > 0) & (F.W > 0) THEN SendUpdate(F, M.x, M.y, M.dlink, TRUE) END
	END ModifyFrame;

	PROCEDURE CopyFrame* (VAR M: Objects.CopyMsg; from, to: Frame);
	BEGIN
		to.backC := from.backC; to.knoblen := from.knoblen;
		to.vertical := from.vertical; to.state0 := from.state0;
		to.min := from.min; to.max := from.max; to.step := from.step; to.val := from.val;
		(* Copy model objects *)
		to.minO := Gadgets.CopyPtr(M, from.minO);
		to.maxO := Gadgets.CopyPtr(M, from.maxO);
		to.stepO := Gadgets.CopyPtr(M, from.stepO);
		Gadgets.CopyFrame(M, from, to)
	END CopyFrame;

	PROCEDURE FrameAttr (F: Frame; VAR M: Objects.AttrMsg);
		VAR msg: Display.ModifyMsg;
	BEGIN
		IF M.id = Objects.get THEN
			IF M.name = "Gen" THEN
				M.class := Objects.String; COPY("Scrollbars.New", M.s); M.res := 0
			ELSIF M.name = "Min" THEN
				M.class := Objects.Int; M.i := F.min; M.res := 0
			ELSIF M.name = "Max" THEN
				M.class := Objects.Int; M.i := F.max; M.res := 0
			ELSIF M.name = "StepSize" THEN
				M.class := Objects.Int; M.i := F.step; M.res := 0
			ELSIF M.name = "Value" THEN
				M.class := Objects.Int; M.i := F.val; M.res := 0
			ELSIF M.name = "BackColor" THEN
				M.class := Objects.Int; M.i := F.backC; M.res := 0
			ELSIF M.name = "Vertical" THEN
				M.class := Objects.Bool; M.b := F.vertical; M.res := 0
			ELSIF M.name = "ArrowBoxes" THEN
				M.class := Objects.Bool; M.b := hasarrows IN F.state0; M.res := 0
			ELSIF M.name = "HeavyDrag" THEN
				M.class := Objects.Bool; M.b := dodrag IN F.state0; M.res := 0
			ELSIF M.name = "Cmd" THEN
				Gadgets.framehandle(F, M);
				IF M.res < 0 THEN M.class := Objects.String; M.s := ""; M.res := 0 END
			ELSIF M.name = "Field" THEN
				Gadgets.framehandle(F, M);
				IF M.res < 0 THEN M.class := Objects.String; M.s := ""; M.res := 0 END
			ELSIF M.name = "LineupHY" THEN
				M.class := Objects.Int; M.i := F.H DIV 2 - 5; M.res := 0
			ELSE Gadgets.framehandle(F, M)
			END
		ELSIF M.id = Objects.set THEN
			IF M.name = "BackColor" THEN
				IF M.class = Objects.Int THEN
					F.backC := SHORT(M.i); M.res := 0
				END
			ELSIF M.name = "Min" THEN
				IF M.class = Objects.Int THEN
					F.min := M.i;
					IF F.minO # NIL THEN Attributes.SetInt(F.minO, "Value", F.min); Gadgets.Update(F.minO)
					ELSE AdjustKnoblen(F)
					END;
					M.res := 0
				END
			ELSIF M.name = "Max" THEN
				IF M.class = Objects.Int  THEN
					F.max := M.i;
					IF F.maxO # NIL THEN Attributes.SetInt(F.maxO, "Value", F.max); Gadgets.Update(F.maxO)
					ELSE AdjustKnoblen(F)
					END;
					M.res := 0
				END
			ELSIF M.name = "StepSize" THEN
				IF M.class = Objects.Int  THEN
					F.step := M.i;
					IF F.stepO # NIL THEN Attributes.SetInt(F.stepO, "Value", F.step); Gadgets.Update(F.stepO) END;
					M.res := 0
				END
			ELSIF M.name = "Value" THEN
				IF M.class = Objects.Int THEN SetValue(F, M.i); M.res := 0 END
			ELSIF M.name = "Vertical" THEN
				IF M.class = Objects.Bool THEN
					IF F.vertical # M.b THEN
						F.vertical := M.b;
						msg.id := Display.extend; msg.mode := Display.display;
						msg.F := F; msg.X := F.X; msg.W := F.H; msg.H := F.W; msg.Y := F.Y+F.H-msg.H;
						msg.dX := 0; msg.dY := msg.Y-F.Y; msg.dW := msg.W-F.W; msg.dH := msg.H-F.H;
						msg.res := -1; Display.Broadcast(msg);
						F.X := msg.X; F.Y := msg.Y; F.W := msg.W; F.H := msg.H;
					END;
					M.res := 0
				END
			ELSIF M.name = "ArrowBoxes" THEN
				IF M.class = Objects.Bool THEN
					IF M.b THEN INCL(F.state0, hasarrows) ELSE EXCL(F.state0, hasarrows) END;
					AdjustKnoblen(F); M.res := 0
				END
			ELSIF M.name = "HeavyDrag" THEN
				IF M.class = Objects.Bool THEN
					IF M.b THEN INCL(F.state0, dodrag) ELSE EXCL(F.state0, dodrag) END;
					M.res := 0
				END
			ELSE Gadgets.framehandle(F, M);
			END
		ELSIF M.id = Objects.enum THEN
			M.Enum("Min"); M.Enum("Max"); M.Enum("Value"); M.Enum("StepSize");
			M.Enum("BackColor");
			M.Enum("Field"); M.Enum("Cmd");
			M.Enum("Vertical"); M.Enum("ArrowBoxes"); M.Enum("HeavyDrag");
			Gadgets.framehandle(F, M)
		END
	END FrameAttr;

	PROCEDURE FrameLink (F: Frame; VAR M: Objects.LinkMsg);
	BEGIN
		IF M.id = Objects.get THEN
			IF M.name = "Min" THEN M.obj := F.minO; M.res := 0
			ELSIF M.name = "Max" THEN M.obj := F.maxO; M.res := 0
			ELSIF M.name = "Step" THEN M.obj := F.stepO; M.res := 0
			ELSE Gadgets.framehandle(F, M)
			END
		ELSIF M.id = Objects.set THEN
			IF M.name = "Min" THEN F.minO := M.obj; AdjustKnoblen(F); M.res := 0
			ELSIF M.name = "Max" THEN F.maxO := M.obj; AdjustKnoblen(F); M.res := 0
			ELSIF M.name = "Step" THEN F.stepO := M.obj; M.res := 0
			ELSIF M.name = "Model" THEN F.obj := M.obj; GetValue(F); M.res := 0
			ELSE Gadgets.framehandle(F, M)
			END
		ELSIF M.id = Objects.enum THEN
			M.Enum("Min"); M.Enum("Max"); M.Enum("Step"); Gadgets.framehandle(F, M)
		ELSE Gadgets.framehandle(F, M)
		END
	END FrameLink;

	PROCEDURE FrameBind (F: Frame; VAR M: Objects.BindMsg);
	BEGIN
		Gadgets.framehandle(F, M);
		IF F.stepO # NIL THEN F.stepO.handle(F.stepO, M) END;
		IF F.minO # NIL THEN F.minO.handle(F.minO, M) END;
		IF F.maxO # NIL THEN F.maxO.handle(F.maxO, M) END
	END FrameBind;

	PROCEDURE FrameFile (F: Frame; VAR M: Objects.FileMsg);
	VAR ver: LONGINT;
	BEGIN
		IF M.id = Objects.store THEN
			Files.WriteNum(M.R, VersionNo);
			Files.WriteLInt(M.R, F.min); Files.WriteLInt(M.R, F.max);
			Files.WriteLInt(M.R, F.step); Files.WriteLInt(M.R, F.val);
			Files.WriteInt(M.R, F.backC); Files.WriteBool(M.R, F.vertical);
			Files.WriteSet(M.R, F.state0);
			Gadgets.WriteRef(M.R, F.lib, F.minO);
			Gadgets.WriteRef(M.R, F.lib, F.maxO);
			Gadgets.WriteRef(M.R, F.lib, F.stepO);
			Gadgets.framehandle(F, M)
		ELSIF M.id = Objects.load THEN
			Files.ReadNum(M.R, ver);
			IF ver >= 1 THEN
				Files.ReadLInt(M.R, F.min); Files.ReadLInt(M.R, F.max);
				Files.ReadLInt(M.R, F.step); Files.ReadLInt(M.R, F.val);
				Files.ReadInt(M.R, F.backC); Files.ReadBool(M.R, F.vertical);
				Files.ReadSet(M.R, F.state0);
				Gadgets.ReadRef(M.R, F.lib, F.minO);
				Gadgets.ReadRef(M.R, F.lib, F.maxO);
				Gadgets.ReadRef(M.R, F.lib, F.stepO)
			END;
			Gadgets.framehandle(F, M)
		END
	END FrameFile;

	PROCEDURE FrameHandler* (F: Objects.Object; VAR M: Objects.ObjMsg);
	VAR x, y, w, h: INTEGER; F1: Frame; Q: Display3.Mask;
	BEGIN
		WITH F: Frame DO
			IF M IS Display.FrameMsg THEN
				WITH M: Display.FrameMsg DO
					IF (M.F = NIL) OR (M.F = F) THEN (* message addressed to box *)
						x := M.x+F.X; y := M.y+F.Y; w := F.W; h := F.H; (* calculate display coordinates *)
						IF M IS Display.DisplayMsg THEN
							WITH M: Display.DisplayMsg DO
								IF M.device = Display.screen THEN
									IF (M.id = Display.full) OR (M.F = NIL) THEN
										Gadgets.MakeMask(F, x, y, M.dlink, Q);
										RestoreFrame(F, Q, x, y, w, h)
									ELSIF M.id = Display.area THEN
										Gadgets.MakeMask(F, x, y, M.dlink, Q);
										Display3.AdjustMask(Q, x+M.u, y+h-1+M.v, M.w, M.h);
										RestoreFrame(F, Q, x, y, w, h)
									END
								ELSIF M.device = Display.printer THEN PrintFrame(F, M)
								END
							END
						ELSIF M IS Display.ControlMsg THEN
							WITH M: Display.ControlMsg DO
								Gadgets.framehandle(F, M);
								IF M.id = Display.restore THEN
									AdjustKnoblen(F); GetValue(F);
									IF F.stepO # NIL THEN Attributes.GetInt(F.stepO, "Value", F.step) END
								END
							END
						ELSIF M IS Oberon.InputMsg THEN
							WITH M: Oberon.InputMsg DO
								IF (M.id = Oberon.track) & Gadgets.InActiveArea(F, M) & (M.keys = {1}) THEN
									TrackFrame(F, x, y, w, h, M); M.res := 0
								ELSE Gadgets.framehandle(F, M)
								END
							END
						ELSIF M IS Display.ModifyMsg THEN ModifyFrame(F, M(Display.ModifyMsg))
						ELSIF M IS Gadgets.UpdateMsg THEN UpdateFrame(F, M(Gadgets.UpdateMsg))
						ELSE Gadgets.framehandle(F, M)
						END
					END
				END
			ELSIF M IS Objects.AttrMsg THEN FrameAttr(F, M(Objects.AttrMsg))
			ELSIF M IS Objects.FileMsg THEN FrameFile(F, M(Objects.FileMsg))
			ELSIF M IS Objects.LinkMsg THEN FrameLink(F, M(Objects.LinkMsg))
			ELSIF M IS Objects.BindMsg THEN FrameBind(F, M(Objects.BindMsg))
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					IF M.stamp = F.stamp THEN M.obj := F.dlink
					ELSE  NEW(F1); F.stamp := M.stamp; F.dlink := F1; CopyFrame(M, F, F1); M.obj := F1
					END
				END
			ELSE Gadgets.framehandle(F, M)
			END
		END
	END FrameHandler;
	
	PROCEDURE InitFrame* (F: Frame);
	BEGIN
		F.handle := FrameHandler; F.W := barW; F.H := 100;
		F.min := 0; F.max := 100; F.step := 1; F.val := 50;
		F.backC := Display3.textbackC; F.vertical := TRUE; F.state0 := {hasarrows};
		AdjustKnoblen(F)
	END InitFrame;
	
	PROCEDURE New*;
	VAR F: Frame;
	BEGIN NEW(F); InitFrame(F); Objects.NewObj := F
	END New;

BEGIN
	WaitTime := 50 * Input.TimeUnit DIV 1000; HoldTime :=  500 * Input.TimeUnit DIV 1000;
	mayscroll := Oberon.Time()
END Scrollbars.
