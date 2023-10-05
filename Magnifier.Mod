(* OBERON System 3, Release 2.3.

Copyright 1999 ETH Zürich Institute for Computer Systems, 
ETH Center, CH-8092 Zürich.  e-mail: oberon@inf.ethz.ch.

This module may be used under the conditions of the general Oberon 
System 3 license contract.  The full text can be downloaded from

	"ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/license.txt;A"

Under the license terms stated it is in particular (a) prohibited to modify
the interface of this module in any way that disagrees with the style
or content of the system and (b) requested to provide all conversions
of the source code to another platform with the name OBERON. *)

MODULE Magnifier; (** portable *)	(* ejz   *)
	IMPORT SYSTEM, Display, Oberon, Effects, Out;

	CONST
		W = 32; H = 32; Z = 4; W2 = W DIV 2; H2  = H DIV 2;

	VAR
		Marker, eArrow, oArrow: Oberon.Marker;
		buf, buf1, buf2: POINTER TO ARRAY OF CHAR;
		vX, vY, pix: LONGINT;
		installed: BOOLEAN;

	PROCEDURE FlipArrow(X, Y: LONGINT);
		VAR cx, cy, cw, ch: INTEGER;
	BEGIN
		Display.GetClip(cx, cy, cw, ch);
		Display.SetClip(0, 0, Display.Width, Display.Height);
		Display.CopyPattern(Display.FG, Display.arrow, X, Y - 14, 2);
		Display.SetClip(cx, cy, cw, ch)
	END FlipArrow;

	PROCEDURE Rect(VAR X, Y: INTEGER);
	BEGIN
		IF X < W2 THEN X := W2 END;
		IF X >= (Display.Width-W2) THEN X := Display.Width-W2-1 END;
		IF Y < H2 THEN Y := H2 END;
		IF Y >= (Display.Height-H2) THEN Y := Display.Height-H2-1 END;
		Display.TransferBlock(buf1^, 0, pix*W, X-W2, Y-H2, W, H, Display.get)
	END Rect;

	PROCEDURE FadeView();
	BEGIN
		IF (vX > 0) & (vY > 0) THEN
			Display.ReplConst(Display.FG, vX-1, vY-1, Z*W, 1, Display.invert);
			Display.ReplConst(Display.FG, vX-1, vY-1, 1, Z*H, Display.invert)
		ELSE
			Display.ReplConst(Display.FG, 0, Z*H, Z*W, 1, Display.invert);
			Display.ReplConst(Display.FG, Z*W, 0, 1, Z*H, Display.invert)
		END;
		Display.TransferBlock(buf^, 0, pix*Z*W, vX, vY, Z*W, Z*H, Display.set)
	END FadeView;

	PROCEDURE ShowView();
	BEGIN
		IF (vX > 0) & (vY > 0) THEN
			Display.ReplConst(Display.FG, vX-1, vY-1, Z*W, 1, Display.invert);
			Display.ReplConst(Display.FG, vX-1, vY-1, 1, Z*H, Display.invert)
		ELSE
			Display.ReplConst(Display.FG, 0, Z*H, Z*W, 1, Display.invert);
			Display.ReplConst(Display.FG, Z*W, 0, 1, Z*H, Display.invert)
		END
	END ShowView;

	PROCEDURE *Draw(X, Y: INTEGER);
		VAR i, j, m, n: LONGINT; p: LONGINT;
	BEGIN
		IF (X >= vX) & (X < (vX+Z*W)) & (Y >= vY) & (Y < (vY+Z*H)) THEN
			FadeView();
			IF vX = 0 THEN
				vX := Display.Width-Z*W; vY := Display.Height-Z*H
			ELSE
				vX := 0; vY := 0
			END;
			ShowView();
			Display.TransferBlock(buf^, 0, pix*Z*W, vX, vY, Z*W, Z*H, Display.get)
		END;
		i := X; j := Y; Rect(X, Y);
		FlipArrow(i, j);
		j := 0;
		WHILE j < pix*H DO
			i := 0;
			WHILE i < pix*W DO
				SYSTEM.MOVE(SYSTEM.ADR(buf1[j*W+i]), SYSTEM.ADR(p), pix);
				n := 0;
				WHILE n < pix*Z DO
					m := 0;
					WHILE m < pix*Z DO
						SYSTEM.MOVE(SYSTEM.ADR(p), SYSTEM.ADR(buf2[(Z*j+n)*Z*W + Z*i+m]), pix);
						INC(m, pix)
					END;
					INC(n, pix)
				END;
				INC(i, pix)
			END;
			INC(j, pix)
		END;
		Display.TransferBlock(buf2^, 0, pix*Z*W, vX, vY, Z*W, Z*H, Display.set)
	END Draw;

	PROCEDURE *Fade(X, Y: INTEGER);
	BEGIN
		FlipArrow(X, Y); Rect(X, Y)
	END Fade;

	PROCEDURE OK(): BOOLEAN;
	BEGIN
		IF pix = 0 THEN
			Out.String("Display module does not support TransferBlock");  Out.Ln
		END;
		RETURN pix # 0
	END OK;
	
	PROCEDURE Zoom*;
		VAR keys: SET; X, Y: INTEGER;
	BEGIN
		IF installed OR ~OK() THEN RETURN END; installed := TRUE;
		oArrow := Oberon.Arrow; eArrow := Effects.Arrow;
		NEW(buf, pix*Z*W*Z*H+4); NEW(buf1, pix*W*H+4); NEW(buf2, pix*Z*W*Z*H+4);
		vX := 0; vY := 0; ShowView();
		Display.TransferBlock(buf^, 0, pix*Z*W, vX, vY, Z*W, Z*H, Display.get);
		REPEAT Effects.TrackMouse(keys, X, Y, Marker) UNTIL keys # {};
		FadeView();
		REPEAT Effects.TrackMouse(keys, X, Y, Effects.Arrow) UNTIL keys = {};
		buf := NIL; buf1 := NIL; buf2 := NIL; installed := FALSE
	END Zoom;

	PROCEDURE Install*;
	BEGIN
		IF installed OR ~OK() THEN RETURN END; installed := TRUE;
		oArrow := Oberon.Arrow; eArrow := Effects.Arrow;
		NEW(buf, pix*Z*W*Z*H+4); NEW(buf1, pix*W*H+4); NEW(buf2, pix*Z*W*Z*H+4);
		vX := 0; vY := 0; ShowView();
		Display.TransferBlock(buf^, 0, pix*Z*W, vX, vY, Z*W, Z*H, Display.get);
		Oberon.Arrow := Marker; Effects.Arrow := Marker
	END Install;

	PROCEDURE Remove*;
	BEGIN
		IF ~installed OR ~OK() THEN RETURN END; installed := FALSE;
		FadeView();
		buf := NIL; buf1 := NIL; buf2 := NIL;
		Oberon.Arrow := oArrow; Effects.Arrow := eArrow
	END Remove;

	PROCEDURE Init();
	BEGIN
		pix := Display.TransferFormat(0) DIV 8; installed := FALSE;
		ASSERT((Z*W < Display.Width) & (Z*H < Display.Height));
		Marker.Draw := Draw; Marker.Fade := Fade
	END Init;

BEGIN
	Init()
END Magnifier.

Magnifier.Zoom
Magnifier.Install
Magnifier.Remove
