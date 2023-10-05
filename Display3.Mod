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

MODULE Display3;	(** portable *)	(** jm 17.1.95 / tk 7.12.95*)

(** Module Display3 implements the clipped graphic primitives used by the Gadget system. It has a twin module called Printer3 that implements the same primitives for the printer.
**)

(*
	jm  11.2.93 - mask msg
	jm 15.4.93  fixed center string
	kr 2.6.93  fixed Poly with patterns
	jm 17.09.93 10:46:54 - fixed shift mask
	25.3.94 - fixed problem with Subtract (bug surfaces after 2 years only)
	29.3.94 - Added Pict and ReplPict
	15.11.94 - changed definition of String and CenterString
		- added selectpat (from Effects)
		- removed MakeMask
	12.12.94 - fixed clipping problem with lines (was a stupid mistake from Rege).
	6.1.95 - removed all the rubbish from rege
		- implemented brushes
			Lines (supports width, patterns)
			Poly (supports width, patterns, filled)
			Circle (supports width, patterns, filled)
			Ellipse (supports patterns /no fill & width)
	3.1.96 - fixed Open by setting clipping port to a maximum area
	29.8.96 - fixed Ellipse & Circle (thanks to eos)
*)

IMPORT
	Display, Objects, Fonts, Pictures, Oberon, Texts;

CONST
	replace* = Display.replace; paint* = Display.paint; invert* = Display.invert;		(** Standard display modes. **)
	
	(** Display styles **)
	filled* = 1;		(** Filled *)
	
	maxcoord = 8192; 
	add = 1; subtract = 2;

TYPE
	Mask* = POINTER TO MaskDesc;	(** Clipping Mask. *)
	
	(** Informs a frame of a new mask. This message is always sent directly. **)
	OverlapMsg* = RECORD (Display.FrameMsg)
		M*: Mask;		(** Use NIL to indicate to a frame that its current mask is invalid. *)
	END;

	(** Message broadcast by a frame (identified by the F field) to indicate that it has an invalid mask and now requires
	its parent, to calculate a new mask for it and to inform it through the OverlapMsg. *)
	UpdateMaskMsg* = RECORD (Display.FrameMsg)
	END;

	Run = POINTER TO RunDesc;
	RunDesc = RECORD
		x, w, right: INTEGER;
		value: INTEGER;
		next, prev: Run;
	END;
	
	ScanLine = POINTER TO ScanLineDesc;
	ScanLineDesc = RECORD
		y, h, top: INTEGER;
		maymerge: BOOLEAN;
		run: Run;
		next,prev: ScanLine;
	END;
	
	MaskDesc* = RECORD	(** Clipping mask descriptor. *)
		x*, y*: INTEGER;		(** Relative mask origin or offset. *)
		X*, Y*, W*, H*: INTEGER;		(** Current clipping port in absolute coordinates. *)
		sX, sY, sW, sH: INTEGER;
		simple: BOOLEAN;
		scanline: ScanLine;
	END;
	
	(** Enumerate the set of rectangles in a mask. The clipping port is not enumerated. *)
	EnumProc* = PROCEDURE (X, Y, W, H: INTEGER);
	
VAR 
	selectpat*: Display.Pattern; (** Pattern used to draw gadgets when in a selected state. **)
	
	(** Colors *)
	FG*, BG*: INTEGER;		(** Foreground (black) and background (white) color indexes. *)
	red*, green*, blue*: INTEGER;	(** Primary color indexes. *)

	black*, white*: INTEGER;	(** True black and white. **)
	topC*: INTEGER;	(** Top shadow color. *)
	bottomC*: INTEGER;	(** Bottom shadow color. *)
	upC*: INTEGER;	(** Color of a button. *)
	downC*: INTEGER;	(** Color of the pushed  button *)
	groupC*: INTEGER;	(** Color of containers, i.e. gadgets that have a grouping function like panels. *)
	invertC*: INTEGER;	(** Best color for doing inverts.. *)
	textC*: INTEGER;	(** Default text color. *)
	textbackC*: INTEGER;	(** Default text background. *)
	textmode*: INTEGER;	(** Best CopyPattern mode for this display card. *)

	typ: INTEGER;
	aM, bM: Mask; (* for enums *)
	
	(* tmp variables for picture enumerator *)
	tmpP: Pictures.Picture;
	tmpM, dX, dY: INTEGER;

	compactionflag: BOOLEAN;
	
(* ========= Brush related ========= *)

CONST BrushSize = 100; (* maximum width of the brush *)
	
TYPE
	Brush = RECORD
		brul, brur: ARRAY BrushSize OF INTEGER;
		bufl, bufr: ARRAY BrushSize OF INTEGER;
		bufh, brushr: INTEGER;
		x, y, mode: INTEGER;
		col: Display.Color;
		M: Mask;
		pat: Display.Pattern
	END;

VAR
	drawingPolygon: BOOLEAN;
	brush: Brush; (* global Bursh *)

PROCEDURE Min(x, y: INTEGER): INTEGER;
BEGIN
	IF x < y THEN RETURN x ELSE RETURN y END
END Min;

PROCEDURE Max(x, y: INTEGER): INTEGER;
BEGIN IF x > y THEN RETURN x ELSE RETURN y END
END Max;

PROCEDURE ClipAgainst(VAR x, y, w, h: INTEGER; x1, y1, w1, h1: INTEGER);
VAR r, t, r1, t1: INTEGER;
BEGIN
	r := x + w - 1; r1 := x1 + w1 - 1; t := y + h - 1; t1 := y1 + h1 - 1;
	IF x < x1 THEN x := x1 END;
	IF y < y1 THEN y := y1 END;
	IF r > r1 THEN r := r1 END;
	IF t > t1 THEN t := t1 END;
	w := r - x + 1; h := t - y + 1;
END ClipAgainst;

PROCEDURE Clip(M: Mask; VAR x, y, w, h : INTEGER);
VAR l, b, t, r, tmp : INTEGER;
BEGIN
    l := x; b := y; r := x+w-1; t := y +h-1;
	IF (l < M.sX) THEN l := M.sX; END;
	tmp := M.sX + M.sW - 1;
	IF (r > tmp) THEN r := tmp; END;
	IF (b < M.sY) THEN b := M.sY; END;
	tmp := M.sY + M.sH - 1;
	IF (t > tmp) THEN t := tmp; END;
	x := l; y := b; w := r - l + 1; h := t - b + 1;
END Clip;

PROCEDURE Open0(M: Mask);
VAR r: Run; s: ScanLine;
BEGIN
	NEW(s); NEW(r);
	M.scanline := s; s.run := r; r.next := NIL;
	
	s.y := -maxcoord; s.h := 2 * maxcoord + 1; s.top := maxcoord;
	r.x := -maxcoord; r.w := 2 * maxcoord + 1; r.right := maxcoord;
END Open0;

(** Initialize the Mask to the empty region, i.e. everything will be clipped away. *)
PROCEDURE Open*(M: Mask);
BEGIN M.scanline := NIL;
	M.x := 0; M.y := 0;
	M.simple := TRUE; M.sX := 0; M.sY := 0; M.sW := 0; M.sH := 0;
	M.X := 0; M.Y := 0; M.W := maxcoord; M.H := maxcoord
END Open;

(** Enumerate all the visible areas of a mask. The clipping port is not enumerated. The mask translation vector is taken into account.**)
PROCEDURE Enum*(M: Mask; enum: EnumProc);
VAR s: ScanLine; r: Run;
BEGIN
	IF M.simple THEN
		IF (M.sW > 0) & (M.sH > 0) THEN enum(M.x + M.sX, M.y + M.sY, M.sW, M.sH) END;
	ELSE
		s := M.scanline;
		WHILE s # NIL DO
			r := s.run;
			WHILE r # NIL DO
				IF r.value # 0 THEN enum(M.x + r.x, M.y + s.y, r.w, s.h) END;
				r := r.next
			END;
			s := s.next
		END
	END
END Enum;

(** Enumerate all the invisible areas of a mask. The clipping port is not enumerated. Note that you might obtain coordinates outside of the normal screen area, bounded by approximately -/+ 8192. The mask translation vector is taken into account.**)
PROCEDURE EnumInvert*(M: Mask; enum: EnumProc);
VAR s: ScanLine; r: Run; X, Y, W, H: INTEGER;
BEGIN
	IF M.simple THEN
		X := M.x + M.sX; Y := M.y + M.sY; W := M.sW; H := M.sH;
		enum(-maxcoord, -maxcoord, 2*maxcoord + 1, Y + maxcoord);
		enum(-maxcoord, Y+H, 2*maxcoord + 1, maxcoord - (Y+H) + 1);
		enum(-maxcoord, Y, X + maxcoord, H);
		enum(X+W, Y, maxcoord - (X+W) , H)
	ELSE
		s := M.scanline;
		WHILE s # NIL DO
			r := s.run;
			WHILE r # NIL DO
				IF r.value = 0 THEN enum(M.x + r.x, M.y + s.y, r.w, s.h) END;
				r := r.next
			END;
			s := s.next
		END
	END
END EnumInvert;

(** Enumerate all the visible areas in the given rectangular region. The clipping port is not taken into account. *)
PROCEDURE EnumRect*(M: Mask; X, Y, W, H: INTEGER; enum: EnumProc);
	VAR hleft, wleft, nw, nh, x, y, X0: INTEGER; s: ScanLine; r: Run;
BEGIN
	IF M.simple THEN
		ClipAgainst(X, Y, W, H, M.x + M.sX, M.y + M.sY, M.sW, M.sH); (* enum(M.x + M.sX, M.y + M.sY, M.sW, M.sH); *)
		IF (W > 0) & (H > 0) THEN enum(X, Y, W, H) END;
	ELSE
		x := M.x; y := M.y;
		hleft := H;
		r := NIL;
		s := M.scanline;
		WHILE s.top + y < Y DO s := s.next; END;
		X0 := X;
		WHILE hleft > 0 DO
			nh := Min(s.top + y - Y + 1, hleft);
			r := s.run;
			WHILE r.right + x < X DO r := r.next END;
			wleft := W;
			WHILE wleft > 0 DO
				nw := r.right + x - X + 1; 
				IF wleft < nw THEN nw := wleft END;
				IF r.value > 0 THEN enum(X, Y, nw, nh) END;
				INC(X, nw); DEC(wleft, nw);
				r := r.next
			END;
			INC(Y, nh); DEC(hleft, nh);
			s := s.next; r := NIL; X := X0
		END
	END
END EnumRect;

PROCEDURE SplitScan(s: ScanLine; y: INTEGER); (* s.y < y < s.top *)
VAR ns: ScanLine; nr, r, tmp: Run;
BEGIN
	NEW(ns); ns.y := y; ns.top := s.top; ns.h := s.top - y + 1; 
	r := s.run; (* NEWRun(nr); *) NEW(nr);ns.run := nr;
	WHILE r # NIL DO
		nr.x := r.x; nr.w := r.w; nr.right := r.right; nr.value := r.value;
		IF r.next # NIL THEN 
			(* NEWRun(tmp); *) NEW(tmp); nr.next := tmp; nr := tmp;
		ELSE
			nr.next := NIL;
		END;
		r := r.next;
	END;
	ns.next := s.next; s.next := ns; s.top := y - 1; s.h := s.top - s.y + 1; 
END SplitScan;

PROCEDURE MergeScanLine(s : ScanLine);
VAR r, rt: Run; noinc: BOOLEAN;
BEGIN
	r := s.run;
	WHILE r # NIL DO (* Merge *)
		IF r.value > 0 THEN r.value := 1; END;
		rt := r.next; noinc := FALSE;
		IF (rt # NIL) THEN
			IF rt.value > 0 THEN rt.value := 1; END;
			IF (rt.value = r.value) & (r.right+1 = rt.x) THEN
				INC(r.w, rt.w); r.right := rt.right; r.next := rt.next; (* DisposeRun(rt); *) noinc := TRUE;
			END;
		END;
		IF ~noinc THEN r := r.next; END;
	END;
END MergeScanLine;

PROCEDURE Compact(M: Mask);
VAR r, rt, thesinglerect: Run;
	bs, st, thesinglescanline: ScanLine;
	noofrects: INTEGER; merge, noinc: BOOLEAN;
BEGIN
	IF ~compactionflag THEN RETURN END;
	bs := M.scanline;
	WHILE bs # NIL DO
		IF bs.maymerge THEN MergeScanLine(bs); END;
		bs := bs.next;
	END;
	bs := M.scanline; 
	WHILE bs # NIL DO
		st := bs.next; noinc := FALSE; 
		IF st # NIL THEN
			r := bs.run; rt := st.run; merge := TRUE;
			WHILE merge & (r # NIL) DO
				IF (r.value = rt.value) & (r.x = rt.x) & (r.w = rt.w) THEN ELSE merge := FALSE; END;
				r := r.next; rt := rt.next;
			END;
			IF merge THEN
				INC(bs.h, st.h); INC(bs.top, st.h);
				bs.next := st.next;
				noinc := TRUE;
			END;
		END;
		IF ~noinc THEN bs := bs.next; END;
	END;
	bs := M.scanline; noofrects := 0;
	WHILE (bs # NIL) & (noofrects <= 1) DO
		r := bs.run;
		WHILE (r # NIL) & (noofrects <= 1) DO
			IF (r.value > 0)  THEN 
					INC(noofrects);
					thesinglerect := r; thesinglescanline := bs;
			END;
			r := r.next;
		END;
		bs := bs.next;
	END;
	IF noofrects = 1 THEN (* super compact  *)
		M.scanline := NIL;
		
		M.simple := TRUE;
		M.sX := thesinglerect.x; M.sY := thesinglescanline.y; 
		M.sW := thesinglerect.w; M.sH := thesinglescanline.h;
	END
END Compact;

PROCEDURE DoLine(s: ScanLine; x, y, w, h: INTEGER);
VAR splittop, splitbottom: BOOLEAN; r, rt: Run; wleft, nw: INTEGER;
BEGIN
	splitbottom := (y > s.y); splittop := (y+h-1) < s.top;
	r := s.run;
	WHILE r.right < x DO r := r.next; END;
	wleft := w;
	WHILE (wleft > 0) & (r # NIL) DO
		nw := Min(wleft, r.right - x + 1);
		(* x, y, nw, h *)
		IF r.value = 1 THEN (* draw okay in this run *)
		ELSE
			IF splittop THEN
				SplitScan(s, y + h);
				splittop := FALSE;
			END;
			IF splitbottom THEN
				SplitScan(s, y);
				rt := s.next.run;
				WHILE rt.x # r.x DO rt := rt.next END;
				r := rt;
				s := s.next;
				splitbottom := FALSE
			END;
			IF x > r.x THEN	(* split left *)
				NEW(rt);
				rt.next := r.next;
				rt.x := x; rt.w := r.right - x + 1; rt.right := r.right; rt.value := 2;
				r.w := x - r.x; r.right := r.x + r.w - 1; r.value := 0;
				r.next := rt;  nw:=0; s.maymerge := TRUE
			ELSIF x + wleft - 1 < r.right THEN 	(* split right *)
				NEW(rt);
				rt.next := r.next;
				rt.x := x + wleft ; rt.w := r.right - rt.x + 1; rt.right := r.right; rt.value := 0;
				r.w := nw; r.right := r.x + r.w - 1; r.value := 1;
				r.next := rt; s.maymerge := TRUE
			ELSE
				r.value := 1; s.maymerge := TRUE
			END
		END;
		INC(x, nw); DEC(wleft, nw); r := r.next
	END
END DoLine;

PROCEDURE ExclLine(s: ScanLine; x, y, w, h: INTEGER);
VAR splittop, splitbottom: BOOLEAN;
	r, rt: Run; wleft, nw: INTEGER;
BEGIN
	splitbottom := (y > s.y); splittop := (y+h-1) < s.top;
	r := s.run;
	WHILE r.right < x DO r := r.next END;
	wleft := w;
	WHILE (wleft > 0) & (r # NIL) DO
		nw := Min(wleft, r.right - x + 1);
		(* x, y, nw, h *)
		IF (r.value = 0) THEN 
		ELSE
			IF splittop THEN
				SplitScan(s, y + h);
				splittop := FALSE
			END;
			IF splitbottom THEN
				SplitScan(s, y);
				rt := s.next.run;
				WHILE rt.x # r.x DO rt := rt.next; END;
				r := rt;
				s := s.next;
				splitbottom := FALSE
			END;
			IF x > r.x THEN	(* split left *)
				NEW(rt);
				rt.next := r.next;
				rt.x := x; rt.w := r.right - x + 1; rt.right := r.right; 
				IF x + wleft - 1 < r.right THEN rt.value := 2; ELSE rt.value := 0; END;
				r.w := x - r.x; r.right := r.x + r.w - 1; r.value := 2;
				r.next := rt;  nw:=0; s.maymerge := TRUE;
			ELSIF x + wleft - 1 < r.right THEN 	(* split right *)
				 NEW(rt);
				rt.next := r.next;
				rt.x := x + wleft; rt.w := r.right - rt.x + 1; rt.right := r.right; rt.value := 1;
				r.w := nw; r.right := r.x + r.w - 1; r.value := 0; s.maymerge := TRUE;
				r.next := rt;
			ELSE
				r.value := 0; s.maymerge := TRUE;
			END;
		END;
		INC(x, nw); DEC(wleft, nw);r := r.next;
	END;
END ExclLine;

(** Make a copy of a mask. *)
PROCEDURE Copy*(from: Mask; VAR to: Mask);
VAR r, Tr, Nr: Run; s, Ns, Ts: ScanLine;
BEGIN
	NEW(to); 
	to^ := from^;
	IF from.scanline # NIL THEN
		s := from.scanline;
		NEW(Ns); to.scanline := Ns;
		WHILE s # NIL DO
			Ns^ := s^; Ns.prev := NIL;
			(* copy run *)
			r := s.run;
			NEW(Nr); Ns.run := Nr;
			WHILE r # NIL DO
				Nr^ := r^; Nr.prev := NIL;
				IF r.next # NIL THEN NEW(Tr); Nr.next := Tr; Nr := Tr;
				ELSE Nr.next := NIL;
				END;
				r := r.next;
			END;
			(* end copy run *)
			IF s.next # NIL THEN NEW(Ts); Ns.next := Ts; Ns := Ts;
			ELSE Ns.next := NIL;
			END;
			s := s.next;
		END
	END
END Copy;

(** Add the rectangle X, Y, W, H as a visible/drawable area to the mask. *)
PROCEDURE Add*(M: Mask; X, Y, W, H: INTEGER);
VAR hleft, nh: INTEGER; s: ScanLine;
BEGIN
	X := X - M.x; Y := Y - M.y; (* adjust for offset *)
	IF M.simple THEN
		IF M.sW + M.sH = 0 THEN
			M.sX := X; M.sY := Y; M.sW := W; M.sH := H;
			RETURN;
		ELSE
			M.simple := FALSE; Open0(M);
			compactionflag := FALSE;
			Add(M, M.sX + M.x, M.sY + M.y, M.sW, M.sH);
			compactionflag := TRUE; 
		END;
	END;
	hleft := H;
	s := M.scanline; WHILE s # NIL DO s.maymerge := FALSE; s := s.next; END;
	s := M.scanline; 
	WHILE s.top < Y DO s := s.next; END;
	WHILE hleft > 0 DO
		nh := Min(s.top - Y + 1, hleft); 
		DoLine(s, X, Y, W, nh);
		INC(Y, nh);
		DEC(hleft, nh);
		s := s.next;
	END;
	Compact(M); 
END Add;

(** Clip the current clipping port of the mask to the rectangle X, Y, W, H. The result is an updated clipping port. *)
PROCEDURE AdjustMask*(M: Mask; X, Y, W, H: INTEGER);
BEGIN
	ClipAgainst(X, Y, W, H, M.X, M.Y, M.W, M.H);
	M.X := X; M.Y := Y; M.W := W; M.H := H
END AdjustMask;

(** Remove area X, Y, W, H from the mask i.e. make area undrawable.  *)
PROCEDURE Subtract*(M: Mask; X, Y, W, H: INTEGER);
VAR hleft, nh: INTEGER;s: ScanLine;
BEGIN
	IF M.simple THEN
		M.simple := FALSE; Open0(M);
		compactionflag := FALSE;
		Add(M, M.x + M.sX, M.y + M.sY, M.sW, M.sH);
		compactionflag := TRUE;
	END;
	X := X - M.x; Y := Y - M.y;
	hleft := H;
	s := M.scanline; WHILE s # NIL DO s.maymerge := FALSE; s := s.next; END;
	s := M.scanline;
	WHILE s.top < Y DO s := s.next; END;
	WHILE hleft > 0 DO
		nh := Min(s.top - Y + 1, hleft);
		ExclLine(s, X, Y, W, nh);
		INC(Y, nh);
		DEC(hleft, nh);
		s := s.next;
	END;
	Compact(M);
END Subtract;

(** Interset the mask with the rectangle X, Y, W, H. The visible areas are restricted to this rectangle. *)
PROCEDURE Intersect*(M: Mask; X, Y, W, H: INTEGER);
BEGIN
	IF M.simple THEN
		X := X - M.x; Y := Y - M.y;
		Clip(M, X, Y, W, H); M.sX := X; M.sY := Y; M.sW := W; M.sH := H
	ELSE
		Subtract(M, -maxcoord, -maxcoord, 2*maxcoord + 1, Y + maxcoord (*+ 1*));
		Subtract(M, -maxcoord, Y+H, 2*maxcoord + 1, maxcoord - (Y+H) + 1);
		Subtract(M, -maxcoord, Y, X + maxcoord (*+ 1*), H);
		Subtract(M, X+W, Y, maxcoord - (X+W) , H)
	END
END Intersect;

PROCEDURE *IntersectMasks1(x, y, w, h: INTEGER);
BEGIN
	IF typ = add THEN Add(bM, x, y, w, h) ELSIF typ = subtract THEN Subtract(bM, x, y, w, h) END;
END IntersectMasks1;

PROCEDURE *IntersectMasks0(X, Y, W, H: INTEGER);
BEGIN EnumRect(aM, X, Y, W, H, IntersectMasks1);
END IntersectMasks0;

(** Intersect the masks A and B resulting in R. *)
PROCEDURE IntersectMasks*(A, B: Mask; VAR R: Mask);		(** R is an out parameter only *)
BEGIN
	IF (A = NIL) OR (B = NIL) THEN R := NIL
	ELSE
		NEW(R); Open(R); R.x := A.x; R.y := A.y; 
		aM := B; bM := R; typ := add; Enum(A, IntersectMasks0); aM := NIL; bM := NIL
	END;
END IntersectMasks;

(** Subtracts the visible areas of B from A to give mask R. *)
PROCEDURE SubtractMasks*(A, B: Mask; VAR R: Mask);
BEGIN
	IF (A = NIL) OR (B = NIL) THEN R := NIL
	ELSE
		Copy(A, R); aM := A; bM := R; typ := subtract; Enum(B, IntersectMasks0); aM := NIL; bM := NIL
	END;
END SubtractMasks;

(** Translate the mask so that the resulting origin/offset is 0, 0. This is done by "adding in" the translation vector. *)
PROCEDURE Shift*(M: Mask);
VAR s, first, last: ScanLine; r, f, l: Run;
BEGIN
	IF M # NIL THEN
		IF M.simple THEN INC(M.sX, M.x); INC(M.sY, M.y);
		ELSIF (M.x # 0) OR (M.y # 0) THEN
			s := M.scanline; first := s;
			WHILE s # NIL DO
				INC(s.y, M.y); INC(s.top, M.y);
				r := s.run; f := r;
				WHILE r # NIL DO
					INC(r.x, M.x); INC(r.right, M.x);
					l := r; r := r.next
				END;
				f.x := -maxcoord; l.right := maxcoord; (* ! *)
				f.w := f.right - f.x + 1; l.w := l.right - l.x + 1; (* ! *)
				last := s; s := s.next;
			END;
			first.y := -maxcoord; last.top := maxcoord; (* ! *)
			first.h := first.top - first.y + 1; last.h := last.top - last.y + 1; (* ! *)
		END;
		M.x := 0; M.y := 0;
	END;
END Shift;

(** Returns TRUE if the visible areas of the mask form a single rectangle. The result, when TRUE, is returned. The clipping port is not taken into account. *)
PROCEDURE Rectangular*(M: Mask; VAR X, Y, W, H: INTEGER): BOOLEAN;
BEGIN
	X := M.x + M.sX; Y := M.y + M.sY; W := M.sW; H := M.sH;
	RETURN M.simple
END Rectangular;

(* --------- CopyMask ---- *)

(** Using Display.CopyBlock, copy the area M to position X, Y. The point M.x, M.y is copied to screen coordinates X, Y. *)
PROCEDURE CopyMask*(M: Mask; X, Y: INTEGER; mode: INTEGER);
VAR s, sp: ScanLine; r, rp: Run; rruns, rscans: BOOLEAN;
BEGIN
	IF M.simple THEN
		Display.CopyBlock(M.x + M.sX, M.y + M.sY, M.sW, M.sH, X + M.sX, Y + M.sY, mode)
	ELSE
		rruns := X > M.x; rscans := Y > M.y;
		IF rscans THEN
			s := M.scanline; sp := NIL;
			WHILE s # NIL DO
				s.prev := sp; sp := s; s := s.next
			END;
			s := sp
		ELSE s := M.scanline
		END;
		WHILE s # NIL DO
			IF rruns THEN
				r := s.run; rp := NIL;
				WHILE r # NIL DO
					r.prev := rp; rp := r; r := r.next;
				END;
				r := rp;
				WHILE r # NIL DO
					IF r.value > 0 THEN
						Display.CopyBlock(M.x + r.x, M.y + s.y, r.w, s.h, X + r.x, Y + s.y, mode)
					END;
					r := r.prev;
				END;
			ELSE
				r := s.run;
				WHILE r # NIL DO
					IF r.value > 0 THEN
						Display.CopyBlock(M.x + r.x, M.y + s.y, r.w, s.h, X + r.x, Y + s.y, mode);
					 END;
					r := r.next;
				END;
			END;
			IF ~rscans THEN s := s.next ELSE s := s.prev END;
		END
	END;
END CopyMask;
	
(** Display.ReplConst through a mask. *)
PROCEDURE ReplConst*(M: Mask; col: Display.Color; X, Y, W, H, mode: INTEGER);
VAR hleft, wleft, nw, nh, x, y, X0  : INTEGER; s : ScanLine; r : Run;
BEGIN
	IF M = NIL THEN Display.ReplConst(col, X, Y, W, H, mode);
	ELSIF M.simple THEN
		ClipAgainst(X, Y, W, H, M.X, M.Y, M.W, M.H);
		ClipAgainst(X, Y, W, H, M.x + M.sX, M.y + M.sY, M.sW, M.sH); 
		Display.ReplConst(col, X, Y, W, H, mode);
	ELSE 
		ClipAgainst(X, Y, W, H, M.X, M.Y, M.W, M.H);
		x := M.x; y := M.y;
		hleft := H;
		s := M.scanline;
		WHILE s.top + y < Y DO s := s.next; END;
		
		X0 := X;
		WHILE hleft > 0 DO
			nh := Min(s.top + y - Y + 1, hleft);
			r := s.run; WHILE r.right + x < X DO r := r.next END;
			wleft := W;
			WHILE wleft > 0 DO
				nw := r.right + x - X + 1; 
				IF wleft < nw THEN nw := wleft END;
				IF r.value > 0 THEN Display.ReplConst(col, X, Y, nw, nh, mode); END;
				INC(X, nw); DEC(wleft, nw);
				r := r.next;
			END;
			INC(Y, nh); DEC(hleft, nh);
			s := s.next; r := NIL; X := X0;
		END
	END
END ReplConst;

(** Is this rectangle completely visible? The clipping port is taken into acount. **)
PROCEDURE Visible*(M: Mask; X, Y, W, H : INTEGER) : BOOLEAN;
VAR x, y, X0, hleft, wleft, nh, nw: INTEGER; vis: BOOLEAN; s: ScanLine; r: Run;
BEGIN
	IF M = NIL THEN RETURN TRUE;
	ELSIF (X < M.X) OR (Y < M.Y) OR  (X + W > M.X + M.W) OR (Y + H >  M.Y + M.H ) THEN RETURN FALSE
	ELSIF M.simple THEN x := M.x; y := M.y;
		RETURN (X >= M.sX + x) & (Y >= M.sY + y) & (X + W <= M.sX + M.sW + x) & (Y + H <=  M.sY + M.sH + y)
	ELSE x := M.x; y := M.y;
		(* jm mod *)
		vis := TRUE;
		s := M.scanline;
		WHILE s.top + y < Y DO s := s.next; END;
		hleft := H;
		X0 := X;
		WHILE vis & (hleft > 0) DO
			nh := Min(s.top + y - Y + 1, hleft);
			r := s.run;
			WHILE r.right + x < X DO r := r.next END;
			wleft := W;
			WHILE vis & (wleft > 0) DO
				nw := r.right + x - X + 1; 
				IF wleft < nw THEN nw := wleft END;
				IF r.value = 0 THEN vis := FALSE END;
				INC(X, nw); DEC(wleft, nw);
				r := r.next;
			END;
			INC(Y, nh); DEC(hleft, nh);
			s := s.next; X := X0;
		END;
		RETURN vis;
	END;
END Visible;

(** Display.Dot through a clipping mask. *)
PROCEDURE Dot*(M: Mask; col: Display.Color; X, Y, mode: INTEGER);
VAR x, y: INTEGER; s: ScanLine; r: Run;
BEGIN
	IF M = NIL THEN Display.Dot(col, X, Y, mode)
	ELSIF M.simple THEN
		x := M.x; y := M.y;
		IF (X >= M.X) & (Y >= M.Y )  & (X < M.X + M.W ) & (Y < M.Y + M.H) THEN
			IF (X >= M.sX + x) & (Y >= M.sY + y) & (X < M.sX + M.sW + x) & (Y < M.sY + M.sH + y) THEN
				Display.Dot(col, X, Y, mode)
			END
		END
	ELSE
		IF (X >= M.X) & (Y >= M.Y )  & (X < M.X + M.W ) & (Y < M.Y + M.H) THEN
			x := M.x; y := M.y;
			s := M.scanline;
			WHILE s.top + y < Y DO s := s.next; END; 
			r := s.run;
			WHILE  r.right + x < X DO r := r.next; END;
			IF r.value > 0  THEN Display.Dot(col, X, Y, mode) END
		END
	END
END Dot;	

(** Display.FillPattern through a clipping mask. pX, pY is the pattern pin-point. *)
PROCEDURE FillPattern*(M: Mask; col: Display.Color; pat: Display.Pattern; pX, pY, X, Y, W, H, mode: INTEGER);
VAR hleft, nh, wleft, nw, x, y, X0 : INTEGER; s: ScanLine;  r : Run;
BEGIN
	IF pat = Display.solid THEN ReplConst(M, col, X, Y, W, H, mode); RETURN END;
	
	IF M = NIL THEN Display.FillPattern(col, pat, pX, pY, X, Y, W, H, mode)
	ELSIF M.simple THEN
		ClipAgainst(X, Y, W, H, M.X, M.Y, M.W, M.H);		
		ClipAgainst(X, Y, W, H, M.x + M.sX, M.y + M.sY, M.sW, M.sH); 
		Display.FillPattern(col, pat, pX, pY, X, Y, W, H, mode);
	ELSE
		ClipAgainst(X, Y, W, H, M.X, M.Y, M.W, M.H);
		x := M.x; y := M.y;
		s := M.scanline;
		WHILE s.top + y < Y DO s := s.next; END;
		hleft := H; X0 := X;
		WHILE hleft > 0 DO
			nh := s.top + M.y - Y + 1; IF hleft < nh THEN nh := hleft END;
			r := s.run; WHILE r.right + x < X DO r := r.next END;
			wleft := W;
			WHILE wleft > 0 DO
				nw := r.right + x - X + 1; IF wleft < nw THEN nw := wleft END;
				IF r.value > 0 THEN Display.FillPattern(col, pat, pX, pY, X,Y, nw, nh, mode); END;
				INC(X, nw);
				DEC(wleft, nw);
				r := r.next;
			END;
			INC(Y, nh);
			DEC(hleft, nh);
			s := s.next; r := NIL; X := X0;
		END;
	END;
END FillPattern;

(** Same as Display.CopyPattern, but through a clipping mask. *)
PROCEDURE CopyPattern*(M: Mask; col: Display.Color; pat: Display.Pattern; X, Y, mode: INTEGER);
VAR  W, H, X0, hleft, wleft, nw, nh, ax, ay, cx, cy, cw, ch, x, y : INTEGER; s: ScanLine; r: Run; 
BEGIN
	Display.GetDim(pat,W,H);
	IF (M = NIL) OR Visible(M,X,Y,W,H) THEN Display.CopyPattern(col, pat, X, Y, mode)
	ELSIF (X >= M.X + M.W) OR (X + W <= M.X) OR (Y >= M.Y + M.H) OR (Y + H <= M.Y) THEN (* skip *)
	ELSIF M.simple THEN
		Display.SetClip(M.X, M.Y, M.W, M.H);
		Display.AdjustClip(M.sX+M.x, M.sY+M.y, M.sW, M.sH); 
		Display.CopyPattern(col, pat, X, Y, mode);
		Display.ResetClip;
	ELSE
		ax := X; ay := Y;
		Display.SetClip(M.X, M.Y, M.W, M.H);
		Display.GetClip(cx, cy, cw, ch);
		x := M.x; y := M.y;
		s := M.scanline;
		WHILE s.top + y < Y DO s := s.next; END;
		hleft := H;  X0 := X;
		WHILE hleft > 0 DO
			nh := Min(s.top + M.y - Y + 1, hleft); 
			r := s.run; WHILE r.right + x < X DO r := r.next END;
			wleft := W;
			WHILE wleft > 0 DO
				nw :=  r.right + x - X + 1; IF wleft < nw THEN nw := wleft END;
				IF r.value > 0 THEN 
					Display.AdjustClip(r.x+x, s.y+y, r.w, s.h); 
					Display.CopyPattern(col, pat, ax, ay, mode); 
					Display.SetClip(cx, cy, cw, ch)
				END;
				INC(X, nw);
				DEC(wleft, nw);
				r := r.next
			END;
			INC(Y, nh);
			DEC(hleft, nh);
			s := s.next; r := NIL; X := X0
		END;
		Display.ResetClip
	END
END CopyPattern;

(* ---------- Extra output primitives -------- *)

(** Draw rectangle outline in the specified size, line width and pattern. *)
PROCEDURE Rect*(M: Mask; col: Display.Color; pat: Display.Pattern; X, Y, W, H, width, mode: INTEGER);
	VAR mX,mW : INTEGER;
BEGIN
	width := Min(width, Min(H DIV 2, W DIV 2));
	FillPattern(M, col, pat, X, Y, X, Y, width, H, mode);
	FillPattern(M, col, pat, X, Y, X + W - width, Y, width, H, mode);
	IF (X < Display.Width) & (X + W >= Display.Width) & (M # NIL) &  (M.X < Display.Width) & (M.X + M.W >= Display.Width) THEN
		mX := M.X; mW := M.W;
		M.W := Display.Width - M.X;
		FillPattern(M, col, pat, X, Y, X + width, Y, W - 2 * width, width, mode);
		FillPattern(M, col, pat, X, Y, X + width, Y + H - width, W - 2 * width, width, mode);
		M.W := mW - M.W; M.X := Display.Width;
		FillPattern(M, col, pat, X, Y, X + width, Y, W - 2 * width, width, mode);
		FillPattern(M, col, pat, X, Y, X + width, Y + H - width, W - 2 * width, width, mode);
		M.X := mX; M.W := mW
	ELSE	
		FillPattern(M, col, pat, X, Y, X + width, Y, W - 2 * width, width, mode);
		FillPattern(M, col, pat, X, Y, X + width, Y + H - width, W - 2 * width, width, mode)
	END
END Rect;

(** Draw rectangle outline in width using top and bottom shadow (3D effects ).*)
PROCEDURE Rect3D*(M: Mask; topcol, botcol: Display.Color; X, Y, W, H, width, mode: INTEGER);
BEGIN
	width := Min(width, Min(H DIV 2, W DIV 2));
	WHILE width > 0 DO
		ReplConst(M, botcol, X, Y, W, 1,mode);
		ReplConst(M, topcol, X, Y + H - 1, W, 1, mode);
		ReplConst(M, topcol, X, Y, 1, H, mode);
		ReplConst(M, botcol, X + W - 1, Y, 1, H, mode);
		DEC(width); INC(X); INC(Y); DEC(W, 2); DEC(H, 2)
	END
END Rect3D;
	
(** Fill rectangle with 3D shadow effects. incol specifies the "inside" color. *)
PROCEDURE FilledRect3D*(M: Mask; topcol, botcol, incol: Display.Color; X, Y, W, H, width, mode: INTEGER);
BEGIN
	width := Min(width, Min(H DIV 2, W DIV 2));
	WHILE width > 0 DO
		ReplConst(M, botcol, X, Y, W, 1,mode);
		ReplConst(M, topcol, X, Y + H - 1, W, 1, mode);
		ReplConst(M, topcol, X, Y, 1, H, mode);
		ReplConst(M, botcol, X + W - 1, Y, 1, H, mode);
		DEC(width); INC(X); INC(Y); DEC(W, 2); DEC(H, 2)
	END;
	ReplConst(M, incol, X , Y, W, H, mode)
END FilledRect3D;

(* BRUSHES *)

PROCEDURE BrushJump(VAR b: Brush; x, y: INTEGER);
VAR i: INTEGER;
BEGIN
	IF (b.x # x) OR (b.y # y) THEN
		b.x := x; b.y := y;
		FOR i := 0 TO b.bufh - 1 DO b.bufl[i] := b.brul[i] + b.x; b.bufr[i] := b.brur[i] + b.x END
	END
END BrushJump;
		
PROCEDURE BrushWalk(VAR b: Brush; x, y: INTEGER);
VAR i, dx, dy, t: INTEGER;
BEGIN
	dx := x - b.x; dy := y - b.y; t := b.bufh - 1;
	IF dy = 0 THEN (* horizontal move *)
		IF dx < 0 THEN
			FOR i := 0 TO t DO b.bufl[i] := Min(b.bufl[i], b.brul[i] + x) END
		ELSIF dx > 0 THEN
			FOR i := 0 TO t DO b.bufr[i] := Max(b.bufr[i], b.brur[i] + x) END
		END
	ELSIF dy > 0 THEN (* up *)
		FillPattern(b.M, b.col, b.pat, 0, 0, b.bufl[0], b.y - b.brushr, b.bufr[0] - b.bufl[0] + 1, 1, b.mode);
		FOR i := 0 TO b.bufh - 2 DO
			b.bufl[i] := Min(b.bufl[i+1], b.brul[i] + x); b.bufr[i] := Max(b.bufr[i+1], b.brur[i] + x);
		END;
		b.bufl[t] := b.brul[t] + x; b.bufr[t] := b.brur[t] + x
		
	ELSE (* dy < 0 *) (* down *)
		FillPattern(b.M, b.col, b.pat, 0, 0,
			b.bufl[t], b.y - b.brushr + b.bufh-1, b.bufr[t] - b.bufl[t] + 1, 1, b.mode);
		FOR i := b.bufh - 1 TO 1 BY -1 DO
			b.bufl[i] := Min(b.bufl[i-1], b.brul[i] + x); b.bufr[i] := Max(b.bufr[i-1], b.brur[i] + x);
		END;
		b.bufl[0] := b.brul[0] + x; b.bufr[0] := b.brur[0] + x;
	END;
	b.x := x; b.y := y
END BrushWalk;

PROCEDURE BrushFlush(VAR b: Brush);
VAR i: INTEGER;
BEGIN
	FOR i := 0 TO b.bufh - 1 DO
		FillPattern(b.M, b.col, b.pat, 0, 0,
			b.bufl[i], b.y + i - b.brushr, b.bufr[i] - b.bufl[i] + 1, 1, b.mode);
	END
END BrushFlush;

PROCEDURE InitBrush(VAR b: Brush; M: Mask; pat: Display.Pattern; col: Display.Color; w, mode: INTEGER);
VAR r, x, y, d, dx, dy: INTEGER;

	PROCEDURE Set(x, y: INTEGER);
	BEGIN
		b.brul[y + r] := -x+1; b.brur[y + r] := x; b.brul[-y + r] := -x+1; b.brur[-y + r] := x;
		IF y + r > b.bufh THEN b.bufh := y + r END
	END Set;

BEGIN b.bufh := 0;
	b.M := M; b.col := col; b.mode := mode; b.pat := pat;
	IF w >= BrushSize THEN w := BrushSize - 1 END;
	
	b.x := MIN(INTEGER); b.y := MIN(INTEGER);
	r := w DIV 2; (* radius *)
	IF r < 0 THEN r := 1 END;
	x := r; y := 0; d := 2 * r; dx := 4 * r; dy := 0;
	Set(x, y);
    WHILE y # r DO
		WHILE d <= 1 DO DEC(x); DEC(dx, 4); INC(d, dx) END;
		INC(y); Set(x, y); INC(dy, 4); DEC(d, dy);
	END;
	b.brushr := r; INC(b.bufh)
END InitBrush;

(* --------------------- Scan line based primitives --------------------- *)

(** Draw a line in the specified pattern and width. Round brushes are used to draw thick lines. *)
PROCEDURE Line*(M: Mask; col: Display.Color; pat: Display.Pattern; X, Y, X1, Y1, width, mode: INTEGER);
VAR x, y, dx, dy, inx, iny, d, dy2, dx2: INTEGER;
BEGIN
	dx := width DIV 2; dx2 := width + 1;
	IF Visible(M, Min(X, X1)-dx, Min(Y, Y1)-dx, ABS(X1-X)+dx2, ABS(Y1-Y)+dx2) THEN M := NIL END;
	x := X; y := Y; dx := X1 - X; dy := Y1 - Y;
	IF width > 1 THEN
		IF drawingPolygon THEN
		ELSE InitBrush(brush, M, pat, col, width, mode); BrushJump(brush, x, y)
		END;
		IF ABS(dy) > ABS(dx) THEN
			d := -ABS(dx); dy2 := 2 * ABS(dy); dx2 := 2 * ABS(dx);
			IF dx < 0 THEN inx := -1; ELSE inx := 1; END;
			IF dy < 0 THEN iny := -1; ELSE iny := 1; END;
			WHILE y # Y1 DO
				INC(y, iny);
				INC(d, dx2);
				IF d > 0 THEN INC(x, inx); DEC(d, dy2); END;
				BrushWalk(brush, x, y);
			END;
		ELSE
			d := -ABS(dx); dy2 := 2 * ABS(dy); dx2 := 2 * ABS(dx);
			IF dx < 0 THEN inx := -1; ELSE inx := 1; END;
			IF dy < 0 THEN iny := -1; ELSE iny := 1; END;
			WHILE x # X1 DO
				INC(x, inx);
				INC(d, dy2);
				IF d > 0 THEN INC(y, iny); DEC(d, dx2); END;
				BrushWalk(brush, x, y);
			END;
		END;
		IF ~drawingPolygon THEN BrushFlush(brush) END;
	ELSE
		IF ABS(dy) > ABS(dx) THEN
			d := -ABS(dx); dy2 := 2 * ABS(dy); dx2 := 2 * ABS(dx);
			IF dx < 0 THEN inx := -1; ELSE inx := 1; END;
			IF dy < 0 THEN iny := -1; ELSE iny := 1; END;
			WHILE y # Y1 DO
				INC(y, iny);
				INC(d, dx2);
				IF d > 0 THEN INC(x, inx); DEC(d, dy2); END;
				IF pat = Display.solid THEN Dot(M, col, x, y, mode)
				ELSE FillPattern(M, col, pat, 0, 0, x, y, 1, 1, mode)
				END
			END;
		ELSE
			d := -ABS(dx); dy2 := 2 * ABS(dy); dx2 := 2 * ABS(dx);
			IF dx < 0 THEN inx := -1; ELSE inx := 1; END;
			IF dy < 0 THEN iny := -1; ELSE iny := 1; END;
			WHILE x # X1 DO
				INC(x, inx);
				INC(d, dy2);
				IF d > 0 THEN INC(y, iny); DEC(d, dx2); END;
				IF pat = Display.solid THEN Dot(M, col, x, y, mode)
				ELSE FillPattern(M, col, pat, 0, 0, x, y, 1, 1, mode)
				END
			END
		END
	END
END Line;

PROCEDURE FilledPoly(M: Mask; col: Display.Color; pat: Display.Pattern; VAR X, Y: ARRAY OF INTEGER; n, mode: INTEGER);
	TYPE
		Run = POINTER TO RunDesc0;
		RunDesc0 = RECORD next: Run; x: INTEGER END;
	VAR
		scan: ARRAY 2000 OF Run; free, s: Run;
		i, miny, maxy, x0, x1: INTEGER;
		
	PROCEDURE New(VAR s: Run);
	BEGIN IF free = NIL THEN NEW(s) ELSE s := free; free := free.next; s.next := NIL END
	END New;
	
	PROCEDURE Free(VAR s: Run);
	VAR s0: Run;
	BEGIN
		IF s # NIL THEN
			s0 := s; WHILE s0.next # NIL DO s0 := s0.next END;
			s0.next := free; free := s; s := NIL
		END
	END Free;

	PROCEDURE Insert(VAR s: Run; x: INTEGER);
	VAR t, t0: Run;
	BEGIN
		IF s = NIL THEN New(s); s.x := x
		ELSE
			New(t); t.x := x;
			IF x < s.x THEN t.next := s; s := t
			ELSE t0 := s;
				WHILE (t0.next # NIL) & (t0.next.x < x) DO t0 := t0.next END;
				IF t0.next = NIL THEN t0.next := t
				ELSE t.next := t0.next; t0.next := t
				END
			END
		END
	END Insert;
		
	PROCEDURE line(x1, y1, x2, y2: INTEGER); (* standard bresenham *)
	VAR x, y, d, dx, dy, incx, incy: INTEGER;
	BEGIN
		(* Seg(x1,y1); *)
		x := x1; y := y1; dx := (x2 - x1) * 2; dy := (y2 - y1) * 2;
		incx := 0;
		IF dx < 0 THEN incx := -1; dx := -dx;
		ELSIF dx  >0 THEN incx := 1
		END;
		incy := 0;
		IF dy < 0 THEN incy := -1; dy := -dy ELSIF dy > 0 THEN incy := 1 END;
		d := incx * (x1 - x2);
		WHILE y # y2 DO
			INC(y, incy); INC(d, dx);
			WHILE d > 0 DO INC(x, incx); DEC(d, dy) END;
			IF incy > 0 THEN Insert(scan[y], x) ELSE Insert(scan[y+1], x) END
		END
	END line;

BEGIN free := NIL;
	miny := MAX(INTEGER); maxy := MIN(INTEGER);
	i := 0; WHILE i < n DO IF Y[i] < miny THEN miny := Y[i] END; IF Y[i] > maxy THEN maxy := Y[i]; END; INC(i) END;
	i := 0; WHILE i <= maxy - miny DO scan[i] := NIL; INC(i) END;
	i := 1;
	WHILE i < n DO
		line(X[i - 1], Y[i - 1] - miny, X[i], Y[i] - miny); INC(i)
	END;
	line(X[n - 1], Y[n - 1] - miny, X[0], Y[0] - miny);
	
	i := 0;
	WHILE i <= maxy - miny DO
		s := scan[i];
		WHILE s # NIL DO
			x0 := s.x; s := s.next;
			IF s = NIL THEN x1 := x0 ELSE x1 := s.x; s := s.next END;
			FillPattern(M, col, pat, 0, 0, x0, i + miny, x1 - x0 + 1, 1, mode)
		END;
		Free(scan[i]);
		INC(i)
	END
END FilledPoly;

(** Draw a polygon in pattern pat. n specifies the number of vertices listed in the arrays X and Y. Style may be {filled}. *)
PROCEDURE Poly*(M: Mask; col: Display.Color; pat: Display.Pattern; VAR X, Y: ARRAY OF INTEGER; n, width: INTEGER; style: SET; mode: INTEGER);
VAR i: INTEGER;
BEGIN
	IF filled IN style THEN FilledPoly(M, col, pat, X, Y, n, mode)
	ELSE
		drawingPolygon := TRUE;
		IF width > 1 THEN InitBrush(brush, M, pat, col, width, mode); BrushJump(brush, X[0], Y[0]) END;
		i := 0;
		WHILE i < n - 1 DO 
			Line(M, col, pat, X[i], Y[i], X[i+1], Y[i+1], width, mode); INC(i) 
		END;
		drawingPolygon := FALSE;
		IF width > 1 THEN BrushFlush(brush) END
	END
END Poly;

(** Draw an ellipse. Implementation restriction: cannot fill an ellipse or draw an ellipse with line width > 1 *)
PROCEDURE Ellipse*(M: Mask; col: Display.Color; pat: Display.Pattern; X, Y, a, b, width: INTEGER; style: SET; mode: INTEGER); 
VAR x1, y1: INTEGER;  d, dx, dy, x2, y2, a1, a2, a8, b1, b2, b8: LONGINT;  		
		
	PROCEDURE Dot4(x1, x2, y1, y2: INTEGER);
	BEGIN
		IF pat = Display.solid THEN 
			Dot(M, col, x1, y1, mode); Dot(M, col, x1, y2, mode);
			Dot(M, col, x2, y1, mode); Dot(M, col, x2, y2, mode)
		ELSE
			FillPattern(M, col, pat, 0, 0, x1, y1, 1, 1, mode); FillPattern(M, col, pat, 0, 0, x1, y2, 1, 1, mode);
			FillPattern(M, col, pat, 0, 0, x2, y1, 1, 1, mode); FillPattern(M, col, pat, 0, 0, x2, y2, 1, 1, mode)
		END
	END Dot4;

BEGIN
	IF Visible(M, X - a, Y - b, 2 * a + 1, 2 * b + 1) THEN M := NIL END;
	IF (a < 600) & (b < 600) THEN
		a1 := a; a2 := a1*a1; a8 := 8*a2; b1 := b; b2 := b1*b1; b8 := 8*b2;
		x1 := a; y1 := 0; x2 := a1*b2; y2 := 0; dx := b8*(a1-1); dy := 4*a2; d := b2*(1- 4*a1);
		WHILE y2 < x2 DO
			Dot4(X-x1(*-1*), X+x1, Y-y1(*-1*), Y+y1);
			INC(d, dy); INC(dy, a8); INC(y1); INC(y2, a2);
			IF d >= 0 THEN DEC(d, dx); DEC(dx, b8); DEC(x1); DEC(x2, b2) END
		END;
		INC(d, 4*(x2+y2)-b2+a2);
		WHILE x1 >= 0 DO
			Dot4(X-x1(*-1*), X+x1, Y-y1(*-1*), Y+y1);
			DEC(d, dx); DEC(dx, b8); DEC(x1);
			IF d < 0 THEN INC(d, dy); INC(dy, a8); INC(y1) END
		END;
	END
END Ellipse;

(** Draw a circle in radius r using pattern pat at position X, Y. Thick line widths are allowed. *)
PROCEDURE Circle*(M: Mask; col: Display.Color; pat: Display.Pattern; X, Y, r, width: INTEGER; style: SET; mode: INTEGER);
VAR x, y, dx, dy, d, e: INTEGER;
BEGIN
	IF filled IN style THEN
		IF Visible(M, X - r, Y - r, 2 * r + 1, 2 * r + 1) THEN M := NIL END;
		x := r; y := 0; e := 0; dx := 2; dy := 2;
		WHILE y <=x DO
			FillPattern(M, col, pat, X, Y, X - x, Y + y, 2 * x + 1, 1, mode);
			FillPattern(M, col, pat, X, Y, X - x, Y - y, 2 * x + 1, 1, mode);
			INC(y);
			INC(e, y * dy - 1);
			IF e > x THEN
				DEC(x); DEC(e, x * dx + 1);
				FillPattern(M, col, pat, X, Y, X - y, Y + x, 2* y + 1, 1, mode);
				FillPattern(M, col, pat, X, Y, X - y, Y - x, 2 * y + 1, 1, mode)
			END
		END
	ELSIF width > 1 THEN
		d := r + (width + 1) DIV 2;
		IF Visible(M, X - d, Y - d, 2*d + 1, 2*d + 1) THEN M := NIL END;
		x :=  X + r; y := Y;
		InitBrush(brush, M, pat, col, width, mode); BrushJump(brush, x, y);
		
		d := 2* r; dx := 4* r; dy := 0;
		WHILE y # Y + r DO
			WHILE d <= 1 DO DEC(x); BrushWalk(brush, x, y); DEC(dx,4); INC(d,dx) END;
			INC(y); BrushWalk(brush, x, y); INC(dy,4); DEC(d,dy);
		END;
		WHILE x # X DO DEC(x); BrushWalk(brush, x, y); DEC(dx,4); INC(d,dx) END;
		d := -d;
		WHILE x # X - r DO
			WHILE d <= 1 DO DEC(y); BrushWalk(brush,x,y); DEC(dy,4); INC(d,dy) END;
			DEC(x); BrushWalk(brush,x,y); INC(dx,4); DEC(d,dx);
		END;
		WHILE y # Y DO DEC(y); BrushWalk(brush,x,y); DEC(dy,4); INC(d,dy) END;
		d := -d;
		WHILE y # Y - r DO
			WHILE d <= 1 DO INC(x); BrushWalk(brush,x,y); DEC(dx,4); INC(d,dx) END;
			DEC(y); BrushWalk(brush,x,y); INC(dy,4); DEC(d,dy);
		END;
		WHILE x # X DO INC(x); BrushWalk(brush,x,y); DEC(dx,4); INC(d,dx) END;
		d := -d;
		WHILE x # X + r DO
			WHILE d <= 1 DO INC(y); BrushWalk(brush,x,y); DEC(dy,4); INC(d,dy) END;
			INC(x); BrushWalk(brush,x,y); INC(dx,4); DEC(d,dx);
		END;
		WHILE y # Y DO INC(y); BrushWalk(brush,x,y); DEC(dy,4); INC(d,dy) END;
		BrushFlush(brush)
	ELSE
		(*IF Visible(M, X - r, Y - r, 2 * r + 1, 2 * r + 1) THEN M := NIL END;*)
		Ellipse(M, col, pat, X, Y, r, r, width, style, mode)
	END
END Circle;

(* ---- end of scanline primitives ---- *)

(** Draw string s in font fnt and color col at position X, Y. *)
PROCEDURE String*(M: Mask; col: Display.Color; X, Y: INTEGER; fnt: Fonts.Font; s: ARRAY OF CHAR; mode: INTEGER);
VAR r: Objects.Object; p: INTEGER;
BEGIN
	p := 0;
	WHILE s[p] # 0X DO
		fnt.GetObj(fnt,ORD(s[p]),r);
		WITH r: Fonts.Char DO
   		CopyPattern(M, col, r.pat, X + r.x, Y + r.y, mode);
		   INC(X, r.dx); INC(p)
		END
	END
END String;

(** Draw a string s in font fnt centered in the rectangle X, Y, W, H. Line breaks will be inserted as needed. *)
PROCEDURE CenterString*(M: Mask; col: Display.Color; X, Y, W, H: INTEGER; fnt: Fonts.Font; s: ARRAY OF CHAR; mode: INTEGER);
VAR len, p, h, lspc, i, y: INTEGER; r: Objects.Object; s0: ARRAY 64 OF CHAR;
BEGIN
	len := 0; p := 0;
	WHILE (s[p] # 0X) DO
		fnt.GetObj(fnt, ORD(s[p]), r);
		INC(p); INC(len, r(Fonts.Char).dx)
	END;
	IF len < W - 4 THEN (* normal print *)
		String(M, col, (W - len) DIV 2 + X, Y + H DIV 2 - fnt.height DIV 2 + ABS(fnt.minY), fnt, s, mode)
	ELSE (* formatted print *)
		p := 0; len := 0; h := 0; lspc := -1; 
		WHILE s[p] # 0X DO
			fnt.GetObj(fnt, ORD(s[p]), r);
			IF len + r(Fonts.Char).dx >= W THEN (* too long next line *)
				IF s[p] = " " THEN lspc := -1; s[p] := 1X; INC(h, fnt.height); len := 0
				ELSIF lspc > 0 THEN (* space exists *) p := lspc; lspc := -1; s[p] := 1X; INC(h, fnt.height); len := 0
				ELSE INC(len, r(Fonts.Char).dx)
				END
			ELSE
				INC(len, r(Fonts.Char).dx);
				IF s[p] = " " THEN lspc := p END
			END;
			INC(p)
		END; INC(h, fnt.height);
		
		(* print *)
		p := 0; i := 0; len := 0; y := Y + H DIV 2 + h DIV 2 + ABS(fnt.minY); 
		WHILE s[p] # 0X DO
			fnt.GetObj(fnt, ORD(s[p]), r);
			IF s[p] = 1X THEN (* break *)
				s0[i] := 0X; i := 0; DEC(y, fnt.height);
				String(M, col, X + W DIV 2 - len DIV 2, y, fnt, s0, mode);
				len := 0
			ELSE
				fnt.GetObj(fnt, ORD(s[p]), r);
				INC(len, r(Fonts.Char).dx);
				s0[i] := s[p]; INC(i)
			END;
			INC(p)
		END; DEC(y, fnt.height);
		IF i > 0 THEN s0[i] := 0X;
			String(M, col, X + W DIV 2 - len DIV 2, y, fnt, s0, mode)
		END
	END
END CenterString;

(** Return the size of a string in width w and height h. dsr returns the baseline offset as a positive value. *)
PROCEDURE StringSize*(s: ARRAY OF CHAR; fnt: Fonts.Font; VAR w, h, dsr: INTEGER);
VAR p: INTEGER; r: Objects.Object;
BEGIN
	w := 0; h := fnt.height; dsr := ABS(fnt.minY);
	p := 0;
	WHILE s[p] # 0X DO
		fnt.GetObj(fnt, ORD(s[p]), r); INC(w, r(Fonts.Char).dx);
		INC(p)
	END
END StringSize;

PROCEDURE *EnumPict(X, Y, W, H: INTEGER);
BEGIN Pictures.DisplayBlock(tmpP, X + dX, Y + dY, W, H, X, Y, tmpM);
END EnumPict;

(** Draw the area X, Y, W, H of picture P at position DX, DY on the display. *)
PROCEDURE Pict*(M: Mask; P: Pictures.Picture; X, Y, W, H, DX, DY, mode: INTEGER);
BEGIN
	dX := X - DX; dY :=Y - DY;
	ClipAgainst(DX, DY, W, H, M.X, M.Y, M.W, M.H);
	tmpP := P; tmpM := mode;
	EnumRect(M, DX, DY, W, H, EnumPict);
	tmpP := NIL; (* for GC *)
END Pict;

(** Replicate a picture filling area X, Y, W, H on the display. px, py is the picture pin-point. *)
PROCEDURE ReplPict*(M: Mask; P: Pictures.Picture; px, py, X, Y, W, H, mode: INTEGER);
VAR x, y, w, h, pw, ph, w0, x0: INTEGER;
BEGIN
	pw := P.width; ph := P.height; w0 := W; x0 := X;
	
	WHILE H > 0 DO
		y := (Y - py) MOD ph; h := Min(H, ph - y);
		W := w0; X := x0;
		WHILE W > 0 DO
			x := (X - px) MOD pw; w := Min(W, pw - x);
			Pict(M, P, x, y, w, h, X, Y, mode);
			INC(X, w); DEC(W, w); 
		END;
		INC(Y, h); DEC(H, h)
	END
END ReplPict;

PROCEDURE Init;
 VAR s: Texts.Scanner;
BEGIN
	Oberon.OpenScanner(s, "Gadgets.Hardlook");
	IF ((s.class = Texts.Name) OR (s.class = Texts.String)) & (CAP(s.s[0]) = "Y") THEN
		bottomC := Display.FG	(* hardlook *)
	ELSE
		bottomC := 12	(* softlook *)
	END
END Init;

BEGIN drawingPolygon := FALSE; selectpat := Display.grey1;
	FG := 15; BG := 0;
	red := 1; green := 2; blue := 3;

	black := Display.FG; white := Display.BG;
	IF Display.Depth(0) = 1 THEN
		topC := Display.FG;
		upC := Display.BG;
		downC := Display.BG;
		groupC := Display.BG;
		invertC := Display.FG;
		textC := Display.FG;
		textbackC := Display.BG;
		bottomC := Display.FG
	ELSE
		topC := Display.BG;
		upC := 13;
		downC := 12;
		groupC := 13;
		IF Display.TrueColor(0) THEN invertC := Display.FG ELSE invertC := 3 END;
		textC := Display.FG;
		textbackC := 14;
		Init
	END;
	textmode := Display.paint
END Display3.

(** Remarks:

1. Clipping Masks
Built on top of the Display module, the Display3 module is the basis of the gadgets imaging model. It extends the Display module with more advanced clipped drawing primitives like lines, polygonal lines, ellipses, circles etc. A clipping mask indicates which areas on the display can be drawn in. You can imagine the mask to be a sheet of paper, possibly full of holes, and a display primitive being a spray can. The holes are all rectangular, and may overlap (i.e. only rectangular holes can be cut out of the paper). Just as you can move the piece of paper to spray an image at a new location, the mask can be translated by a translation vector (also refered to as the mask origin). By default, the holes of a mask are always defined relative to the origin (0, 0). The origin can be translated, efficiently moving the mask to a different position. In the MaskDesc, the fields x, y specify the mask origin/translation vector. It can be changed directly as needed. Internally masks are sets of non-overlapping rectangles, where each rectangle has a flag to indicate if drawing is allowed in that area or not. After each operation that changes the mask, the mask is checked to see if it might be optimal, i.e. if it is a single rectangular visible area. The latter case is handled separately, allowing more efficient drawing and masking operations. The construction of a mask is more heavyweight in comparison to drawing through a mask, mainly due to the latter checks. Masks should be generated once, and then left unchanged for as long as possible.

2. Clipping Ports
Clipping ports are used to optimize masks operations. A clipping port is an absolutely positioned rectangular area through which all display operations are clipped (a clipping rectangle). The mask and clipping port form together the clipped region, where drawing primitives are first clipped to the mask, and then to the clipping port. This is an implementation of the following idea. Each gadget on the display can be overlapped by other visual objects, and potentially need to clip itself when displayed. Each gadget is thus allocated a static clipping mask. In some cases however, only parts of a gadget need to be redisplayed, for example when a gadget lying partially in front is removed. Rather than creating a new clipping mask just for this simple case, the clipping port can manipulated to indicate which "sub-area" of a gadget must be drawn. The key idea is thus to restrict the clipping mask of a gadget without actually changing the mask (a potentially expensive operation). The clipping port is set by the rectangle X, Y, W, H in the MaskDesc. These are absolute display coordinates. Programmers are allowed to manipulate the clipping port directly or use Display3.AdjustMask.

3. OverlapMsg and UpdateMaskMsg
Each gadget has a (cached) display mask associated with it, even if it is completely visible. This mask is used when a gadget wants to draw on the display. Each parent visual gadget (container) has to manage the display masks of its children. The Display3 module provides messages for requesting a mask and for setting a mask. The OverlapMsg informs a gadget of its display mask. It is sent directly to a visual gadget by its parent. After some editing operations it may happen that a gadgets' mask has become invalid, in which case it is set to nothing (NIL). Should the gadget notice that it has no mask when it wants to draw itself, it may broadcast an UpdateMaskMsg to indicate that the parent must create a mask for it (the gadget itself is identified by the F field in the frame message). The latter should then calculate the mask, and inform the gadget using the OverlapMsg. In some cases, a parent can indicate to a child that its mask is not valid any more, by sending an OverlapMsg with no mask (M.M = NIL).

*)