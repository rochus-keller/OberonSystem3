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

MODULE Effects;	(** portable *) (** jm 18.1.95 *)

(**Implements special effects and encapsulates a few platform dependent features.
*)
(*
	THIS IS THE NATIVE VERSION
	
	jm 22.2.93 - removed max screen
	6.5.94 - Improved palette
	20.9.94 - better usage of the background bitmap
	15.11.94 - removed selectpat to Display3
		-removed middle, right, left
		- removed ticks per sec
		- removed font
	16.11.94 - Added callback for SizeRect
	pjm 13.01.96 - inverting arrow cursor
	pjm 28.03.96 - flying cursor (thanks PM)
*)

IMPORT Display, Display3, Input, Oberon;

CONST markW = 5; GravQ = 4; MinGrav = 2; 
			left = 2; middle = 1; right = 0;
	
TYPE
	Callback* = PROCEDURE (MX, MY, X, Y, W, H: INTEGER; keysum: SET);
	
	Area = RECORD
		X, Y, W, H: INTEGER;
		buf: POINTER TO ARRAY OF CHAR;
		pix: LONGINT;
		offscreen: BOOLEAN
	END;

	(* --- *)
	
	Tracker = POINTER TO TrackerDesc;
	Drawer = PROCEDURE (T : Tracker; X, Y : INTEGER);
    TrackerDesc = RECORD 
    	R: Display3.Mask;
    	exit: BOOLEAN;
    	keysum, keys: SET;
    	MX, MY, X, Y, W, H: INTEGER;
    	Fade, Draw: Drawer;
    	X0, Y0: INTEGER
    END;

VAR
	FlatHand*: Oberon.Marker;		(** Marker used to indicate a dragging/moving operation. *)
	PointHand*: Oberon.Marker;		(** Marker used to indicate a pointing/resizing operation. *)
	Arrow*: Oberon.Marker;		(** Substitute for the normal Oberon marker that does not operate using XOR mode. *)
	MoveHand*: Oberon.Marker;		(** Marker used to indicate a moving operation. *)
	CopyHand*: Oberon.Marker;		(** Marker used to indicate a copying operation. *)
	Cross*: Oberon.Marker;		(** Marker used by Rembrandt. *)
	gravity*: INTEGER;		(** Size of gravity spot used for "snapping" the cursor. *)

	moveRect, cross, bar, highlight: Tracker;

	flatHand, pointHand: Display.Pattern;
	movePat, copyPat, crossPat, crossPat2: Display.Pattern;
	block, A: Area;
	snapX, snapY, snapW, snapH: INTEGER;
	
	X0, Y0, bX, bY: INTEGER; (* global tracker variables; complete bullshit, must be deleted ! *)

	arrowshape: Display.Pattern;

PROCEDURE Min(x, y: INTEGER): INTEGER;
BEGIN IF x < y THEN RETURN x ELSE RETURN y END END Min;

PROCEDURE Max(x, y: INTEGER): INTEGER;
BEGIN IF x > y THEN RETURN x ELSE RETURN y END  END Max;

(** Set the snapping grid origin and width and height used for all future effects. *)			
PROCEDURE SetSnap*(sX, sY, sW, sH: INTEGER);
BEGIN snapX := sX; snapY := sY; snapW := sW; snapH := sH
END SetSnap;

(** Snap X, Y to the snapping grid. *)
PROCEDURE Snap*(VAR X, Y: INTEGER);
VAR sX, sY: INTEGER;
BEGIN
	sX := snapW - snapX MOD snapW; sY := snapH- snapY MOD snapH; 
	X := (X + sX + snapW DIV 2) DIV snapW * snapW - sX;
	Y := (Y + sY + snapH DIV 2) DIV snapH * snapH- sY
END Snap;

PROCEDURE FadeMouse;
	VAR cx,cy,cw,ch : INTEGER;
BEGIN
	Display.GetClip(cx,cy,cw,ch); Display.ResetClip;
	Oberon.FadeCursor(Oberon.Mouse);
	Display.SetClip(cx,cy,cw,ch);
END FadeMouse;

PROCEDURE GetBlock(X, Y, W, H: INTEGER; VAR A: Area; cursor: BOOLEAN);
VAR dX: INTEGER;  size: LONGINT;
BEGIN
		(* clip to full display *)
	IF X < 0 THEN INC(W, X);  X := 0 END;
	IF Y < 0 THEN INC(H, Y);  Y := 0 END;
	IF X+W-1 >= Display.Width THEN W := Display.Width-X END;
	IF Y+H-1 >= Display.Height THEN H := Display.Height-Y END;
		(* save area *)
	A.X := X; A.Y := Y; A.W := W; A.H := H;
	IF H <= -Display.UBottom THEN
		A.offscreen := TRUE;
		IF cursor THEN dX := Display.Width-32 ELSE dX := 0 END;
		Display.CopyBlock(X,Y,W,H,dX,-H,Display.replace)
	ELSE
		A.offscreen := FALSE;
		A.pix := Display.TransferFormat(0) DIV 8;
		IF A.pix # 0 THEN
			size := LONG(W)*H*A.pix;
			IF (A.buf = NIL) OR (size > LEN(A.buf^)) THEN NEW(A.buf, size) END;
			Display.TransferBlock(A.buf^, 0, W*A.pix, X, Y, W, H, Display.get)
		ELSE
			(* skip *)
		END
	END
END GetBlock;

PROCEDURE RestoreBlock(VAR A: Area; cursor: BOOLEAN);
VAR cx,cy,cw,ch,dX: INTEGER;
BEGIN
	Display.GetClip(cx,cy,cw,ch);
	Display.ResetClip;
	IF A.offscreen THEN
		IF cursor THEN dX := Display.Width-32 ELSE dX := 0 END;
		Display.CopyBlock(dX,-A.H,A.W,A.H,A.X,A.Y,Display.replace)
	ELSE
		IF A.pix # 0 THEN
			Display.TransferBlock(A.buf^, 0, A.W*A.pix, A.X, A.Y, A.W, A.H, Display.set)
		ELSE
			(* skip *)
		END
	END;
	Display.SetClip(cx,cy,cw,ch)
END RestoreBlock;

(** Temporarily save a part of the display in an offscreen buffer. Note that the height of the buffer might be limited from
platform to platform. *)
PROCEDURE OpenMenu*(X, Y, W, H: INTEGER);
VAR cx,cy,cw,ch: INTEGER;
BEGIN
	Display.GetClip(cx,cy,cw,ch); 
	Display.ResetClip;
	GetBlock(X, Y, W, H, A, FALSE);
	Display.SetClip(cx,cy,cw,ch)
END OpenMenu;

(** Restore the screen area saved  by OpenMenu. *)
PROCEDURE CloseMenu*;
BEGIN RestoreBlock(A, FALSE)
END CloseMenu;

(** Tempory save a part of the display in an offscreen buffer. This area must be small, and is thought for saving the
areas under non-inverting cursors. *)
PROCEDURE OpenCursor*(X, Y, W, H: INTEGER);
VAR cx,cy,cw,ch: INTEGER;
BEGIN
	Display.GetClip(cx,cy,cw,ch); 
	Display.ResetClip;
	GetBlock(X, Y, W, H, block, TRUE);
	Display.SetClip(cx,cy,cw,ch)
END OpenCursor;

(** Restore the screen area saved by OpenCursor. *)
PROCEDURE CloseCursor*;
BEGIN RestoreBlock(block, TRUE)
END CloseCursor;

(** Returns TRUE if mx, my is within gravity pixels from X, Y. *)
PROCEDURE Invicinity*(mx, my, X, Y: LONGINT): BOOLEAN;
BEGIN RETURN (mx - X) * (mx - X) + (my - Y) * (my - Y) < gravity * gravity
END Invicinity;

(** Returns TRUE if mx, my is inside the rectange X, Y, W, H. *)
PROCEDURE Inside*(mx, my, X, Y, W, H: INTEGER): BOOLEAN;
BEGIN RETURN (mx >= X) & (mx < X + W) & (my >= Y) & ( my < Y + H)
END Inside;

(** Returns TRUE if mx, my is near (within gravity) one of the four corners of  X, Y, W, H. The gravity is tempory adjusted should W, H be too small. *)
PROCEDURE InCorner*(mx, my, X, Y, W, H: INTEGER): BOOLEAN;
VAR hg, vg: INTEGER;
BEGIN
	IF (W <= gravity*3) OR (H <= gravity*3) THEN
		hg := Min(gravity, Max(W DIV GravQ, MinGrav)); vg := Min(gravity, Max(H DIV GravQ, MinGrav));
		RETURN Inside(mx, my, X, Y, hg, vg) OR
			Inside(mx, my, X+W-hg, Y, hg, vg) OR
			Inside(mx, my, X, Y+H-vg, hg, vg) OR
			Inside(mx, my, X+W-hg, Y+H-vg, hg, vg)
	ELSE
		RETURN Inside(mx, my, X, Y, gravity, gravity) OR
			Inside(mx, my, X+W-gravity, Y, gravity, gravity) OR
			Inside(mx, my, X, Y+H-gravity, gravity, gravity) OR
			Inside(mx, my, X+W-gravity, Y+H-gravity, gravity, gravity)
	END
END InCorner;

(** Returns TRUE if mx, my is inside the border of X, Y, W, H (gravity is used). The gravity is tempory adjusted should W, H be too small. *)
PROCEDURE InBorder*(mx, my, X, Y, W, H: INTEGER): BOOLEAN;
VAR hg, vg: INTEGER;
BEGIN
	IF (W <= gravity*3) OR (H <= gravity*3) THEN
		hg := Min(gravity, Max(W DIV GravQ, MinGrav)); vg := Min(gravity, Max(H DIV GravQ, MinGrav));
		RETURN Inside(mx, my, X, Y, hg, H) OR
		 Inside(mx, my, X, Y, W, vg) OR
		 Inside(mx, my, X+W-hg, Y, hg, H) OR
		 Inside(mx, my, X, Y+H-vg, W, vg)
	ELSE
		RETURN Inside(mx, my, X, Y, gravity, H) OR
		 Inside(mx, my, X, Y, W, gravity) OR
		 Inside(mx, my, X+W-gravity, Y, gravity, H) OR
		 Inside(mx, my, X, Y+H-gravity, W, gravity)
	END
END InBorder;

(** Returns TRUE if mx, my is within gravity pixels of the line from X, Y to X1, Y1. *)
PROCEDURE InLineVicinity*(mx, my, X, Y, X1, Y1: INTEGER): BOOLEAN;
VAR  w, h, pw, ph, det,len : LONGINT;

	PROCEDURE Between(x, a, b: INTEGER): BOOLEAN;
	VAR min, max: INTEGER;
	BEGIN
		min := Min(a, b); max := Max(a, b);
		RETURN (min - gravity <= x) & (x <= max + gravity);
	END Between;

BEGIN
	IF ABS(X - X1) > gravity  THEN
		IF ABS(Y - Y1) > gravity THEN
			IF Invicinity(mx, my,X, Y) OR Invicinity(mx, my,X1, Y1) THEN RETURN TRUE END;
			pw := mx - X; ph := my - Y; w := X1 -X;  h := Y1 - Y;
			det := pw * h - ph * w; len := w * w + h * h;
			RETURN  Between(mx, X, X1) & Between(my, Y, Y1) & (det / len * det < gravity * gravity)
		ELSE
			RETURN Between(mx, X, X1) & (ABS(my - Y) < gravity)
		END
	ELSE
		RETURN Between(my, Y, Y1) & (ABS(mx - X) < gravity)
	END
END InLineVicinity;

(** Returns TRUE if the two rectangles intersect each other. *)
PROCEDURE Intersect*(X, Y, W, H, X1, Y1, W1, H1: INTEGER): BOOLEAN;
BEGIN
	RETURN (X + W > X1) & (X1 + W1 > X) & (Y + H > Y1) & (Y1 + H1 > Y)
END Intersect;

PROCEDURE TrackerValues(tracker : Tracker; VAR keys, keysum : SET; VAR MX, MY, X, Y, W, H : INTEGER);
BEGIN
	MX := tracker.MX; MY :=  tracker.MY;
	X := tracker.X; Y := tracker.Y; W := tracker.W; H := tracker.H; keys := tracker.keys; keysum := tracker.keysum
END TrackerValues;

(** Polls the mouse, continually drawing the specified marker, until the mouse snaps to the nearest grid position. *)
PROCEDURE TrackMouse*(VAR keys: SET; VAR X, Y: INTEGER; marker: Oberon.Marker);
VAR k: SET; x, y, cx, cy, cw, ch: INTEGER;
BEGIN
	Display.GetClip(cx, cy, cw, ch); Display.ResetClip();
	Snap(X,Y);			
	REPEAT
		Input.Mouse(k,x,y); Oberon.DrawCursor(Oberon.Mouse, marker, x, y); Snap(x,y)
	UNTIL (k # keys)  OR (X # x) OR (Y # y);
	keys := k; X := x; Y := y;
	Display.SetClip(cx, cy, cw, ch)
END TrackMouse;

PROCEDURE Track (tracker : Tracker; marker: Oberon.Marker);
	VAR MX, MY: INTEGER; keys: SET;
BEGIN
	MX := tracker.MX; MY := tracker.MY; keys :=  tracker.keys;
	Snap(MX, MY);
	WHILE ~tracker.exit DO
		IF tracker.Draw # NIL THEN
			FadeMouse; tracker.Draw(tracker, MX, MY)
		END;
		IF ~tracker.exit THEN  TrackMouse(keys,MX,MY,marker) END;
		IF tracker.Fade # NIL THEN
			FadeMouse; tracker.Fade(tracker, tracker.MX, tracker.MY)
		END;
		tracker.MX := MX; tracker.MY := MY;
		tracker.keys := keys; tracker.keysum := tracker.keysum + keys
	END
END Track;

PROCEDURE TrackDrag (tracker : Tracker);
	VAR MX, MY, x, y, cx, cy, cw, ch: INTEGER; k, keys: SET;
BEGIN
	MX := tracker.MX; MY := tracker.MY; keys :=  tracker.keys;
	Snap(MX, MY);
	WHILE ~tracker.exit DO
		IF tracker.Draw # NIL THEN
			FadeMouse; tracker.Draw(tracker, MX, MY)
		END;
		IF ~tracker.exit THEN
			Display.GetClip(cx, cy, cw, ch); Display.ResetClip();
			Snap(MX, MY);			
			REPEAT
				Input.Mouse(k, x, y);
				IF tracker.keysum = {middle, right} THEN
					Oberon.DrawCursor(Oberon.Mouse, CopyHand, x, y)
				ELSIF tracker.keysum = {middle, left} THEN
					Oberon.DrawCursor(Oberon.Mouse, MoveHand, x, y)
				ELSIF tracker.keysum = {middle} THEN
					Oberon.DrawCursor(Oberon.Mouse, FlatHand, x, y)
				ELSE
					Oberon.DrawCursor(Oberon.Mouse, Arrow, x, y)
				END;
				Snap(x, y)
			UNTIL (k # keys)  OR (MX # x) OR (MY # y);
			keys := k; MX := x; MY := y;
			Display.SetClip(cx, cy, cw, ch)
		END;
		IF tracker.Fade # NIL THEN
			FadeMouse; tracker.Fade(tracker, tracker.MX, tracker.MY)
		END;
		tracker.MX := MX; tracker.MY := MY;
		tracker.keys := keys; tracker.keysum := tracker.keysum + keys
	END
END TrackDrag;

PROCEDURE OpenTracker(tracker : Tracker;  R : Display3.Mask; draw, fade : Drawer; keys : SET; MX, MY, X, Y, W, H : INTEGER);
BEGIN
	IF tracker.Draw = NIL  THEN tracker.Draw := draw END;
	IF tracker.Fade = NIL THEN tracker.Fade := fade END;
	tracker.R := R;
	tracker.keysum := keys; tracker.keys := keys;
	tracker.X := X; tracker.Y := Y; tracker.W := W; tracker.H := H;
	tracker.MX := MX; tracker.MY := MY; tracker.exit := FALSE
END OpenTracker;

(* ------MoveRect---------------------------------------------------- *) 
PROCEDURE *drawMoveRect(T: Tracker; X, Y : INTEGER);
BEGIN
	T.exit := T.keys = {}; 
	T.X := X - T.X0; T.Y := Y - T.Y0;
	Display3.Rect(T.R,Display3.invertC,Display.solid,T.X, T.Y, T.W, T.H, 1, Display.invert)
END drawMoveRect;

PROCEDURE OpenMoveRect(tracker : Tracker; R : Display3.Mask; keys : SET; MX, MY, X, Y, W, H : INTEGER);
BEGIN Snap(MX, MY);
	OpenTracker(tracker,R,drawMoveRect,drawMoveRect,keys,MX, MY, X, Y, W, H);
	tracker.X0 := MX - tracker.X; tracker.Y0 := MY - tracker.Y
END OpenMoveRect;

(* ------ Cross ---------------------------------------------------- *) 

PROCEDURE *drawCross(T : Tracker; X, Y : INTEGER);
BEGIN
	(* jm fix *)
	T.MX := Max(T.X, X); T.MX := Min(T.MX, T.X + T.W - 1);
	T.MY := Max(T.Y, Y); T.MY := Min(T.MY, T.Y + T.H - 1);
	T.exit := T.keys = {};
	OpenMenu(T.MX - markW, T.MY - markW, 2 * markW+1, 2 * markW+1);
	Display.CopyPattern(Display.FG, Display.cross, T.MX - markW, T.MY - markW, Display.paint)
END drawCross;

PROCEDURE *fadeCross(T : Tracker; X, Y : INTEGER);
BEGIN CloseMenu()
END fadeCross;

PROCEDURE OpenTrackCross(tracker : Tracker; R : Display3.Mask; keys : SET; MX, MY, X, Y, W, H : INTEGER);
BEGIN
	OpenTracker(tracker, R, drawCross,fadeCross,keys,MX, MY, X, Y, W, H)
END OpenTrackCross;

(* ------ Highlight ---------------------------------------------------- *) 

PROCEDURE *drawHighlight(T : Tracker; X, Y : INTEGER);
	VAR X0 : INTEGER;
	
	PROCEDURE Draw(X0 : INTEGER);
	BEGIN
		IF X0 = 1 THEN Display3.Rect(T.R,Display3.invertC,Display.solid,T.X,T.Y,T.W,T.H,1,Display.invert)
		ELSIF X0 = 0 THEN Display3.ReplConst(T.R, Display3.invertC,T.X,T.Y,T.W,T.H,Display.invert) END;
	END Draw;
	
BEGIN
	T.exit := T.keys = {};
	IF InBorder(X,Y,T.X,T.Y,T.W,T.H) THEN X0 := 1 ELSIF Inside(X,Y,T.X,T.Y,T.W,T.H) THEN X0 := 0 ELSE X0 := 2 END;
	IF T.exit THEN
		Draw(T.X0); T.X0 := 2
	ELSIF T.X0 # X0 THEN
		Draw(T.X0); T.X0 := X0; Draw(T.X0)
	END;
	T.Y0 := (T.Y0 +1) MOD 2
END drawHighlight;

PROCEDURE OpenHighlight(tracker : Tracker; VAR  R : Display3.Mask; keys : SET; MX, MY, X, Y, W, H : INTEGER);
BEGIN
	tracker.X0 := 2; tracker.Y0 := 0; 
	OpenTracker(tracker,R, drawHighlight, drawHighlight,keys,MX, MY, X, Y, W, H)
END OpenHighlight;

(* -----bar  ------------------------------------------------ *)

(** Given a bar position, calculate the relative bar position. *)
PROCEDURE BarValue*(X, Y, W, H, B, BW: INTEGER; min, max: LONGINT): LONGINT;
VAR  d, r, h: LONGINT;  
BEGIN
	d := (max - min);
	IF H > W THEN r := (B - Y - 1 ) * d DIV (H - 2 - BW)
	ELSE r := (B - X - 1) * d DIV (W - 2 - BW) END;
	r := min +  r;
	IF min > max THEN h := max; max := min ; min := h END;
	IF r > max THEN r := max ELSIF r < min THEN r := min END;
	RETURN r
END BarValue;

(** Given the min, max, and val values, calculate the absolute bar position. *)
PROCEDURE BarPos*(X, Y, W, H, BW: INTEGER; min, max, val: LONGINT): INTEGER;
	VAR  b,  d  : LONGINT; 
BEGIN
	d := (max - min);
	IF min < max THEN IF val < min THEN val := min ELSIF val > max THEN val := max END
	ELSE  IF val < max THEN val := max ELSIF val > min THEN val := min END END;
	val := val - min;
	IF H > W THEN  b := Y + val * (H - 2 - BW) DIV d
	ELSE b := X + val * (W - 2 - BW) DIV d END;
	RETURN SHORT(b)
END BarPos;

PROCEDURE DrawSlider(T : Tracker); 
BEGIN
	IF T.H > T.W THEN 
		IF Y0 < 0 THEN Y0 := T.Y0 END;
		Display3.FilledRect3D(T.R,Display3.topC,Display3.bottomC,Display3.groupC,T.X+1,T.Y0,T.W-2,T.X0,1,Display.replace);
		IF T.W > 6 THEN
			Display3.ReplConst(T.R,Display3.bottomC,T.X+3,T.Y0 + T.X0 DIV 2, T.W - 6,1,Display.replace);
			Display3.ReplConst(T.R,Display3.topC,T.X+3,T.Y0 + T.X0 DIV 2-1, T.W - 6,1,Display.replace)
		END
	ELSE
		IF X0 < 0 THEN X0 := T.X0 END;
		Display3.FilledRect3D(T.R,Display3.topC,Display3.bottomC,Display3.groupC,T.X0,T.Y+1,T.Y0,T.H-2,1,Display.replace);
		IF T.H > 6 THEN
			Display3.ReplConst(T.R,Display3.bottomC,T.X0+ T.Y0 DIV 2-1, T.Y+3, 1,T.H - 6,Display.replace);
			Display3.ReplConst(T.R,Display3.topC,T.X0+ T.Y0 DIV 2, T.Y+3, 1, T.H- 6,Display.replace)
		END
	END
END DrawSlider;

PROCEDURE *drawBar(T : Tracker; X, Y : INTEGER);
	VAR col : INTEGER;
	
BEGIN
	T.exit := (T.keys = {}) ;
	IF ~T.exit  THEN
		col := 12;
		IF T.H > T.W THEN 
			T.Y0 := Max(T.Y+1,Min(Y + bY,T.Y + T.H - T.X0 - 1));
			IF Y0 # T.Y0 THEN
				DrawSlider(T);
				IF Y0 > T.Y0 THEN Display3.ReplConst(T.R,col,T.X+1,T.Y0 + T.X0, T.W-2, Y0-T.Y0,Display.replace)
				ELSE Display3.ReplConst(T.R,col,T.X+1,Y0, T.W-2, T.Y0-Y0,Display.replace) END;
				Y0 := T.Y0
			END
		ELSE
			T.X0 := Max(T.X+1,Min(X + bX,T.X + T.W - T.Y0 - 1));
			IF T.X0 # X0 THEN
				DrawSlider(T);
				IF X0 > T.X0 THEN Display3.ReplConst(T.R,col,T.X0 + T.Y0, T.Y+1, X0-T.X0, T.H-2, Display.replace)
				ELSE Display3.ReplConst(T.R,col,X0, T.Y+1, T.X0 - X0, T.H-2, Display.replace)
				END;
				X0 := T.X0
			END
		END
	END
END drawBar;

PROCEDURE OpenBar(tracker : Tracker; R : Display3.Mask;  keys : SET; MX, MY, X, Y, W, H, B, BW : INTEGER);
	VAR col,T : INTEGER; 
BEGIN	
	OpenTracker(tracker, R, drawBar,drawBar,keys,MX, MY, X, Y, W, H);
	IF tracker.W > tracker.H THEN tracker.X0 := B (*+ X*) + 1; tracker.Y0 := Min(BW,tracker.W-2) 
	ELSE tracker.Y0 := B (*+ Y*) + 1; tracker.X0 :=Min(BW,tracker.H-2) END;
	FadeMouse; 
	IF MX + MY # 0 THEN (* jm *)
		IF tracker.H > tracker.W THEN bX :=  tracker.X - MX; 
			IF (MY < tracker.Y0) OR (MY >  tracker.Y0 + tracker.X0) THEN (* not in bar *)
				tracker.Y0 := Max(tracker.Y+1,Min(MY - tracker.X0 DIV 2,tracker.Y + tracker.H - tracker.X0 - 2));
				bY :=  -tracker.X0  DIV 2
			ELSE bY :=  tracker.Y0 - MY END
		ELSE bY :=  tracker.Y - MY; 
			IF (MX < tracker.X0) OR (MX >  tracker.X0 + tracker.Y0) THEN (* not in bar *)
				tracker.X0 := Max(tracker.X+1,Min(MX - tracker.Y0 DIV 2, tracker.X + tracker.W - tracker.Y0 - 2));
				bX :=  -tracker.Y0  DIV 2
			ELSE bX :=  tracker.X0 - MX END
		END
	END;
	Display3.Rect3D(R,Display3.bottomC,Display3.topC,tracker.X,tracker.Y,tracker.W,tracker.H,1,Display.replace);
	col := 12;
	IF tracker.H > tracker.W THEN T := tracker.Y0 + tracker.X0;
		Display3.ReplConst(R,col,tracker.X+1,tracker.Y+1,tracker.W-2,tracker.Y0-tracker.Y-1,Display.replace);
		Display3.ReplConst(R,col,tracker.X+1,T,tracker.W-2,tracker.Y + tracker.H - T- 1,Display.replace)
	ELSE T := tracker.Y0 + tracker.X0;
		Display3.ReplConst(R,col,tracker.X+1,tracker.Y+1,tracker.X0-tracker.X-1,tracker.H-2,Display.replace);
		Display3.ReplConst(R,col,T,tracker.Y+1,tracker.X + tracker.W - T - 1,tracker.H-2,Display.replace)
	END;
	DrawSlider(tracker);
	X0 := tracker.X0; Y0 := tracker.Y0
END OpenBar;

(** Displays a scroll bar. B is the absolute control knob position and BW the bar width/height. Use BarPos to calculate B. *)
PROCEDURE Bar*(R: Display3.Mask; X, Y, W, H, B, BW: INTEGER);
BEGIN
	OpenBar(bar, R, {}, 0, 0,X, Y, W, H, B, BW)
END Bar;

(** Drag rectangle X, Y, W, H outline until the mouse button is released. MX, MY is the position where the mouse was released, and keys contains all the mouse buttons that were pressed. *)
PROCEDURE MoveRect*(R: Display3.Mask; VAR keysum: SET; VAR MX, MY, X, Y, W, H: INTEGER);
	VAR keys : SET;
BEGIN
	Input.Mouse(keys, MX,MY); 
	OpenMoveRect(moveRect,R, keys, MX,MY,X, Y, W, H);
	TrackDrag(moveRect);
	TrackerValues(moveRect,keys,keysum,MX, MY, X, Y,W,H)
END MoveRect;

(** Resize the rectangle X, Y, W, H using rubber-banding. The nearest resize corner is determined according to the mouse position MX, MY. During resizing the callback procedure is continually called.Keysum returns the set of mouse buttons pressed and MX, MY the position where the mouse buttons were released. *)
PROCEDURE SizeRect*(R: Display3.Mask; VAR keysum: SET; VAR MX, MY, X, Y, W, H: INTEGER; callback: Callback);
	VAR keys: SET; x0, y0, x1, y1: INTEGER; 
	
	PROCEDURE sizeRect(x0, y0: INTEGER; VAR x1, y1: INTEGER);
	VAR x, y: INTEGER;  
	BEGIN
		Snap(x1, y1);
		REPEAT
			Oberon.FadeCursor(Oberon.Mouse); 
			Display3.Rect(R, Display3.invertC,Display.solid,Min(x0,x1 ), Min(y0,y1 ),ABS(x0-x1), ABS(y0-y1), 1, Display.invert);
			x := x1; y := y1; TrackMouse(keys,x1,y1,PointHand); keysum := keysum + keys; 
			Snap(x1,y1);
			Oberon.FadeCursor(Oberon.Mouse);
			Display3.Rect(NIL, Display3.invertC,Display.solid,Min(x0,x), Min(y0,y), ABS(x0-x), ABS(y0-y), 1, Display.invert);
			IF callback # NIL THEN callback(x, y, Min(x0,x1), Min(y0,y1),ABS(x0-x1), ABS(y0-y1),keysum) END
		UNTIL  keys = {}
	END sizeRect;	
	
BEGIN
	Input.Mouse(keys, MX, MY); Snap(MX, MY); Snap(X,Y); keysum := keys; 
	x0 := X; y0 := Y; x1 := X + W; y1 := Y + H; 
	IF MY < (y0 +y1) DIV 2 THEN
		IF MX < (x0 + x1) DIV 2 THEN sizeRect(x1,y1,x0,y0) ELSE sizeRect(x0,y1,x1,y0) END
	ELSE
		IF MX < (x0 + x1) DIV 2 THEN sizeRect(x1,y0,x0,y1) ELSE sizeRect(x0,y0,x1,y1) END
	END;
	X := Min(x0,x1); Y := Min(y0,y1); W := ABS(x0-x1); H := ABS(y0 - y1)
END SizeRect;

(** Track a cross mark inside the rectangle X, Y, W, H. Keysum returns all the mouse buttons pressed and MX, MY the position where the mouse buttons were released. *)
PROCEDURE TrackCross*(R: Display3.Mask; VAR keysum: SET; VAR MX, MY, X, Y, W, H: INTEGER);
VAR keys: SET;
BEGIN
	Input.Mouse(keys, MX,MY);
	OpenTrackCross(cross, R, keys, MX, MY, X, Y, W, H);
	Track(cross, Arrow);
	TrackerValues(cross, keys, keysum, MX, MY, X, Y,W,H);
	MX := Max(MX, X); MY := Max(MY, Y);
	MX := Min(MX, X + W - 1); MY := Min(MY, Y + H - 1)
END TrackCross;

(** Track the position knob of a scrollbar. By bars are meant scroll bars with a knob. The bar orients itself according to the width/height ratio of the bounding rectangle. The interpolation functions allow you to convert between internal measurements and screen coordinates. *)
PROCEDURE TrackBar*(R: Display3.Mask; VAR keysum: SET; VAR MX, MY, X, Y, W, H, B, BW: INTEGER);
VAR keys: SET;
BEGIN
	Input.Mouse(keys, MX, MY);
	OpenBar(bar,R, keys, MX, MY, X, Y, W, H, B, BW);
	Track(bar,FlatHand);
	TrackerValues(bar,keys,keysum, MX, MY, X, Y, W, H);
	IF H > W THEN B := bar.Y0 (*- bar.Y*) ELSE B := bar.X0 (*- bar.X*)  END
END TrackBar;

(** Track mouse in area X, Y, W, H, highlighting the border or inside of the rectangle, depending on the mouse location. Keysum returnes all the mouse buttons pressed and MX, MY the position where the mouse buttons were released. *)
PROCEDURE TrackHighlight*(R: Display3.Mask; VAR keysum: SET; VAR MX, MY: INTEGER; X, Y, W, H: INTEGER);
VAR keys: SET;
BEGIN
	Input.Mouse(keys, MX,MY);
	OpenHighlight(highlight, R, keys,MX,MY,X, Y, W, H);
	Track(highlight,Arrow);
	TrackerValues(highlight,keys,keysum,MX, MY, X, Y,W,H)
END TrackHighlight;

(* --- Misc --- *)

PROCEDURE *DrawFlatHand (x, y: INTEGER);
VAR s: INTEGER; cx, cy, cw, ch: INTEGER;
BEGIN
	Display.GetClip(cx,cy,cw,ch);
	Display.ResetClip;
	s := x DIV Display.Width * Display.Width; x := x - s;
	IF x < 8 THEN x := 8 ELSIF (x > Display.Width - 8) & (x < Display.Width)  THEN x := Display.Width - 8 END; x := x + s;
	IF y < 7 THEN y := 7 ELSIF y > Display.Height - 9 THEN y := Display.Height - 9 END;
	
	(* --- NP --- *)
	GetBlock(x-8, y-7,16,16,block, TRUE);
	Display.CopyPattern (Display.FG, flatHand, x-8, y-7, Display.paint);
	
	(* --- If you need an inverting flathand use this: rather than ^ 
	Display.CopyPattern(Display.FG, flatHand, x-8, y-7, Display.invert);
	 --- *)
	
	Display.SetClip(cx,cy,cw,ch);
END DrawFlatHand;

PROCEDURE *DrawPointHand (x, y: INTEGER);
	VAR s : INTEGER; cx,cy,cw,ch : INTEGER;
BEGIN
	Display.GetClip(cx,cy,cw,ch);
	Display.ResetClip;
	s := x DIV Display.Width * Display.Width; x := x - s;
	IF x < 1 THEN x := 1 ELSIF (x > Display.Width - 15) & (x < Display.Width) THEN x := Display.Width - 15 END; x := x + s;
	IF y < 15 THEN y := 15 ELSIF y >= Display.Height THEN y := Display.Height - 1 END;
	
	(* --- NP --- *)
	GetBlock(x, y- 15,16,16,block, TRUE); Display.CopyPattern(Display.FG,pointHand, x, y - 15, Display.paint);
	
	(* --- If you need an inverting pointhand use this: rather than ^
	Display.CopyPattern(Display.FG, flatHand, x-8, y-7, Display.invert);
	 --- *)

	Display.SetClip(cx,cy,cw,ch);
END DrawPointHand;

(* --- NP --- If you want inverting hands 
PROCEDURE *FadeFlatHand(x, y: INTEGER);
BEGIN DrawFlatHand(x, y);
END FadeFlatHand;

PROCEDURE *FadePointHand(x, y: INTEGER);
BEGIN DrawPointHand(x, y);
END FadePointHand;
*)

PROCEDURE *DrawCopyHand (x, y: INTEGER);
VAR s: INTEGER;
BEGIN
	s := x DIV Display.Width * Display.Width; x := x - s;
	IF x < 8 THEN x := 8 ELSIF (x > Display.Width - 8) & (x < Display.Width)  THEN x := Display.Width - 8 END; x := x + s;
	IF y < 7 THEN y := 7 ELSIF y > Display.Height - 9 THEN y := Display.Height - 9 END;
	x:= x-8; y:= y-7;
	OpenCursor(x, y, 16, 16);
	Display.CopyPattern (Display.FG, flatHand, x, y, Display.paint);
	Display.CopyPattern (9, copyPat, x, y, Display.paint)
END DrawCopyHand;

PROCEDURE *DrawMoveHand (x, y: INTEGER);
VAR s: INTEGER;
BEGIN
	s := x DIV Display.Width * Display.Width; x := x - s;
	IF x < 8 THEN x := 8 ELSIF (x > Display.Width - 8) & (x < Display.Width)  THEN x := Display.Width - 8 END; x := x + s;
	IF y < 7 THEN y := 7 ELSIF y > Display.Height - 9 THEN y := Display.Height - 9 END;
	x:= x-8; y:= y-7;
	OpenCursor(x, y, 16, 16);
	Display.CopyPattern (Display.FG, flatHand, x, y, Display.paint);
	Display.CopyPattern (9, movePat, x, y, Display.paint)
END DrawMoveHand;

PROCEDURE *DrawCross (x, y: INTEGER);
CONST d = 11;
BEGIN
	OpenCursor(x-d, y-d, 23, 23);
	Display.CopyPattern(Display.FG, crossPat, x-d,y-d, Display.paint);
	Display.CopyPattern(Display.BG, crossPat2, x-d,y-d, Display.paint)
END DrawCross;

PROCEDURE *Fade(x, y: INTEGER);
BEGIN  RestoreBlock(block, TRUE); END Fade;

PROCEDURE *DrawArrow(x, y: INTEGER);
VAR s: INTEGER; cx,cy,cw,ch : INTEGER;
BEGIN
	Display.GetClip(cx,cy,cw,ch);
	Display.ResetClip;
	IF x < 1 THEN x := 1 END;
(*
	IF (x < Display.ColLeft) THEN
		s := x DIV Display.Width * Display.Width; x := x - s;
		IF (x > Display.Width - 15) & (x < Display.Width) THEN x := Display.Width - 15 END; x := x + s;
		IF y >= Display.Height THEN y := Display.Height - 1 END;
		Display.CopyPattern(Display.FG, Display.arrow, x, y - 15, Display.invert) 
	ELSE
*)
	GetBlock(x-1, y- 15,16,16,block, TRUE); 
	Display.SetClip(0, 0, Display.Width, Display.Height);
	Display.CopyPattern(Display.FG,Display.arrow, x, y - 15, Display.paint);
	Display.CopyPattern(Display.BG, arrowshape, x-1, y - 15, Display.paint);
	Display.SetClip(cx,cy,cw,ch);
END DrawArrow;

PROCEDURE *FadeArrow(x, y: INTEGER);
BEGIN
	RestoreBlock(block, TRUE)
END FadeArrow;
(* --- *)

PROCEDURE InitCursors;	
VAR flatHandS, pointHandS, movePatS, copyPatS, image: ARRAY 16 OF SET; crossPatS: ARRAY 23 OF SET;
BEGIN
	flatHandS[0] := {10..11};	flatHandS[1] := {7..9};	flatHandS[2] := {4..6};	flatHandS[3] := {2..3};	
	flatHandS[4] := {1};	flatHandS[5] := {0,5,15};	flatHandS[6] := {0,3..4,15};	flatHandS[7] := {1..3,15};
	flatHandS[8] := {1,6,15};	flatHandS[9] := {0,5,14};	flatHandS[10] := {0,3..4,8,14};	flatHandS[11] := {1..3,7,11,14};
	flatHandS[12] := {2,6,10,13};	flatHandS[13] := {2,5,9,12};	flatHandS[14] := {3..5,8,10..11};	flatHandS[15] := {6..7};	
	pointHandS[0] := {9..10};	pointHandS[1] := {7..9};	pointHandS[2] := {5..6,10,16};	pointHandS[3] := {4,16};
	pointHandS[4] := {3,11,16};	pointHandS[5] := {2..6,10,15..16};	pointHandS[6] := {1..2,5..8,10,15};
	pointHandS[7] := {1,4,7..10,15};	pointHandS[8] := {2..3,6..7,11,14};	pointHandS[9] := {3,5,8,14};
	pointHandS[10] := {3..4,7,9..13};	pointHandS[11] := {5..6,10};	pointHandS[12] := {4..5,8..9};
	pointHandS[13] := {2..3,7};	pointHandS[14] := {2,5..6};	pointHandS[15] := {3..4};
	flatHand := Display.NewPattern(16,16,flatHandS); pointHand := Display.NewPattern(16,16,pointHandS);
	
	crossPatS[0]:= {}; crossPatS[1]:= {11}; crossPatS[2]:= {11}; crossPatS[3]:= {11}; crossPatS[4]:= {11};
	crossPatS[5]:= {11}; crossPatS[6]:= {11}; crossPatS[7]:= {11}; crossPatS[8]:= {11}; crossPatS[9]:= {11};
	crossPatS[10]:= {}; crossPatS[11]:= {1..9, 13..21}; crossPatS[12]:= {}; crossPatS[13]:= {11};
	crossPatS[14]:= {11}; crossPatS[15]:= {11}; crossPatS[16]:= {11}; crossPatS[17]:= {11};
	crossPatS[18]:= {11}; crossPatS[19]:= {11}; crossPatS[20]:= {11}; crossPatS[21]:= {};
	crossPat:=Display.NewPattern(22, 22, crossPatS);
	
	crossPatS[0]:= {10..12}; crossPatS[1]:= {10, 12}; crossPatS[2]:= {10, 12}; crossPatS[3]:= {10, 12}; crossPatS[4]:= {10, 12};
	crossPatS[5]:= {10, 12}; crossPatS[6]:= {10, 12}; crossPatS[7]:= {10, 12}; crossPatS[8]:= {10, 12}; crossPatS[9]:= {10, 12};
	crossPatS[10]:= {0..9, 11,  13..22}; crossPatS[11]:= {0, 10, 12, 22}; crossPatS[12]:= {0..9, 11, 13..22}; 
	crossPatS[13]:= {10, 12}; crossPatS[14]:= {10, 12}; crossPatS[15]:= {10, 12}; crossPatS[16]:= {10, 12}; 
	crossPatS[17]:= {10, 12}; crossPatS[18]:= {10, 12}; crossPatS[19]:= {10, 12}; crossPatS[20]:= {10, 12}; 
	crossPatS[21]:= {10, 12}; crossPatS[22]:= {10..12};
	crossPat2:=Display.NewPattern(22, 23, crossPatS);
	Cross.Draw := DrawCross;
	Cross.Fade := Fade;
	
	movePatS[0] := {10..15};	movePatS[1] := {10,15};	movePatS[2] := {10,15};	movePatS[3] := {7..10,15};
	movePatS[4] := {7..10,15};	movePatS[5] := {7..15};	movePatS[6] := {7..12};	movePatS[7] := {7..12};
	movePatS[8] := {7..12};	movePatS[9] := {};	movePatS[10] := {};	movePatS[11] := {};
	movePatS[12] := {};	movePatS[13] := {};	movePatS[14] := {};	movePatS[15] := {};
	movePat := Display.NewPattern(16,16,movePatS);
	MoveHand.Draw := DrawMoveHand;
	MoveHand.Fade := Fade;

	copyPatS[0] := {14..15};	copyPatS[1] := {13..15};	copyPatS[2] := {9, 12..14};	copyPatS[3] := {9..13};
	copyPatS[4] := {9..12};	copyPatS[5] := {9..12};	copyPatS[6] := {9..13};	copyPatS[7] := {};
	copyPatS[8] := {};	copyPatS[9] := {};	copyPatS[10] := {};	copyPatS[11] := {};
	copyPatS[12] := {};	copyPatS[13] := {};	copyPatS[14] := {};	copyPatS[15] := {};
	copyPat := Display.NewPattern(16,16,copyPatS);
	CopyHand.Draw := DrawCopyHand;
	CopyHand.Fade := Fade;

	image[0] := {13};	image[1] := {12};
	image[2] := {11, 15};	image[3] := {10, 14};
	image[4] := {9, 13};	image[5] := {8, 12};
	image[6] := {0, 1, 7, 11};	image[7] := {0, 2, 6, 10};
	image[8] := {0, 3, 5, 9};	image[9] := {0, 4, 8};
	image[10] := {0, 7};	image[11] := {0, 6};
	image[12] := {0, 7};	image[13] := {0, 8};
	image[14] := {0, 9};	image[15]:= {0..9};
	arrowshape := Display.NewPattern(16, 16, image);	(* thanks PM *)
	
	FlatHand.Draw := DrawFlatHand;
	FlatHand.Fade := Fade;
	PointHand.Draw := DrawPointHand;
	PointHand.Fade := Fade;
	Arrow.Draw := DrawArrow; 
	Arrow.Fade := FadeArrow;
END InitCursors;

BEGIN
	gravity := 6;
	snapX := 0; snapY := 0; snapH := 1; snapW := 1;
	A.buf := NIL;  block.buf := NIL;
	InitCursors();
	NEW(moveRect); NEW(cross); NEW(bar); NEW(highlight)
END Effects.

(** Remarks:

1. Gravity
Gravity is a measurement of how far the user can "miss" a point he/she points to with the mouse and still indicate that point or object.  For example it determines the thickness of the border of a rectangle (InBorder). To prevent the border filling the rectangle when very small, the gravity is adjusted dynamicly when very small features are to be selected. The resulting gravity is a value between 1 and the gravity setting.

2. Saving and Restoring areas
Often you need to save and restore small areas of the display, for example, when using pop-up menus. There are two such areas, one for what is underneath a cursor, and one for general use. The corresponding Open procedure saves the area indicated by the rectangle, and the close area restores it to its previous value. This cannot be done recursively. The buffer area is restricted and may be less that 200 pixels in height. There are however more portable ways of doing the same thing (see the Views and Bitmaps module).

3. Tracking
All the tracking procedures assume that the a mouse button is depressed when they are called. They will return when all the mouse buttons are released.

4. Bars
By bars are meant scroll bars with a knob. The bar orients itself according to the width/height ratio of the bounding rectangle. The height/width of the knob is specified by BW. The interpolation functions BarPos and BarValue allow you to convert between a value between a minimum and a maximum and screen coordinates.

5. The Gadgets Palette
The Gadgets system assume that the system palette is organized in the following manner:

	Index	Color
	0		white/background
	1		red
	2		green
	3		blue
	4		free to application
	5		free to application
	6		free to application
	7		free to application
	8		free to application
	9		free to application
	10		free to application
	11		free to application
	12		dark grey
	13		medium grey
	14		light grey
	15		black/foreground
	16 +		free to application
	
On Oberon for Windows, colors 16 to 19 are also fixed.

*)