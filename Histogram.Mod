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

MODULE Histogram;	(** portable *) (* gs   / ps *)
(* System.Free Histogram ~*)
IMPORT
	Display, Objects, Gadgets, Oberon, BasicGadgets, Fonts, Display3, Printer, Printer3, Strings, Reals, MathL, Files; 

CONST
	idversion* = "Histogram 0.1d7"; Bins = 256; Mems = 256;
	
TYPE
	Histogram* = POINTER TO HistogramDesc;
	HistogramDesc* = RECORD (Gadgets.FrameDesc)
		count: ARRAY Bins OF LONGINT; (* Counting bins *)
		nrBins: INTEGER; (* Visible bins *)
		offs,width,top: LONGREAL;
		toosmall,toolarge,nans: LONGINT; (* special counters *)
		nrobs,maxcount: LONGINT;
		prevmax: LONGREAL;
		adapting: BOOLEAN;		(* adapt number of bins and limits *)
		moving: BOOLEAN;		(* show mem data only *)
		suspended: BOOLEAN;	(* ignore data updates *)
		logtransform: BOOLEAN; (* use log data *)
		diff: BOOLEAN;				(* use data diferences *)
		lastentry: LONGREAL;
		mem: ARRAY Mems OF LONGREAL;
		upd: BOOLEAN
	END;

PROCEDURE IsNaN (x:LONGREAL): BOOLEAN; (*! replace by portable version *)
BEGIN RETURN (Reals.ExpoL(x) = 2047)
END IsNaN;

PROCEDURE NaN (code:INTEGER): LONGREAL;
VAR x: LONGREAL;
BEGIN	
	(*! code not yet supported *)
	Reals.SetExpoL(2047,x);
	RETURN x
END NaN;

PROCEDURE LongReal (VAR M: Objects.AttrMsg; VAR x: LONGREAL): BOOLEAN;
BEGIN
	IF M.class=Objects.LongReal THEN x := M.y
	ELSIF M.class=Objects.Real THEN x := M.x
	ELSIF M.class=Objects.Int THEN x := M.i
	ELSIF M.class=Objects.String THEN Strings.StrToReal(M.s, x)
	ELSE RETURN FALSE
	END;
	RETURN TRUE
END LongReal;

PROCEDURE LongInt (VAR M: Objects.AttrMsg; VAR x: LONGINT): BOOLEAN;
BEGIN
	IF M.class=Objects.Int THEN x:=M.i
	ELSIF M.class=Objects.String THEN Strings.StrToInt(M.s,x)
	ELSE RETURN FALSE
	END;
	RETURN TRUE
END LongInt;

(* Histogram actions *)
PROCEDURE Update* (H: Histogram);
VAR U: Gadgets.UpdateMsg;
BEGIN U.obj := H; U.F := NIL; H.upd := FALSE; Display.Broadcast(U)
END Update;

PROCEDURE ClearHistCounts (H: Histogram);
VAR i : INTEGER;
BEGIN
	H.toosmall := 0; H.toolarge := 0; H.nans := 0; H.maxcount := 0;
	FOR i := 0 TO Bins-1 DO H.count[i] := 0 END;
	H.upd := TRUE
END ClearHistCounts;

PROCEDURE ResetCounts* (H: Histogram);
BEGIN ClearHistCounts(H); H.nrobs := 0; H.lastentry := NaN(0); H.upd := TRUE
END ResetCounts;

PROCEDURE Reset* (H: Histogram);
BEGIN
	ClearHistCounts(H); H.nrobs := 0; H.lastentry := NaN(0);
	H.adapting := TRUE; H.offs := MAX(LONGREAL); H.top := MIN(LONGREAL); H.width := 0;
	H.nrBins := 0; H.suspended := TRUE; H.moving := FALSE; H.upd := TRUE
END Reset;

PROCEDURE AddHistCounts (H: Histogram; x: LONGREAL);
VAR bin: INTEGER;
BEGIN
	ASSERT(H.width >= 0, 100);
	IF IsNaN(x) THEN INC(H.nans)
	ELSIF x < H.offs THEN INC(H.toosmall)
	ELSIF x >= H.top THEN INC(H.toolarge)
	ELSIF H.width = 0 THEN INC(H.count[0]) 
	ELSE
		ASSERT(((x - H.offs) / H.width) < MAX(INTEGER), 101);
		bin := SHORT(ENTIER((x - H.offs) / H.width));
		INC(H.count[bin]);
		IF H.count[bin] > H.maxcount THEN H.maxcount := H.count[bin] END;
	END;
	H.upd:=TRUE
END AddHistCounts;

PROCEDURE GetHistCounts (H: Histogram; VAR nrcounted: LONGINT);
VAR i: LONGINT;
BEGIN
	ClearHistCounts(H); nrcounted := 0;
	IF H.nrobs > Mems THEN
		FOR i := 0 TO Mems-1 DO AddHistCounts(H, H.mem[i]) END;
		nrcounted := Mems
	ELSE
		FOR i := 0 TO H.nrobs-1 DO AddHistCounts(H, H.mem[i]) END;
		nrcounted := H.nrobs
	END
END GetHistCounts;

PROCEDURE AddPoint* (H: Histogram; x: LONGREAL);
VAR bin,i,nr: LONGINT; xorig,w,min,max: LONGREAL; tempbins: INTEGER;
BEGIN
	IF H.logtransform THEN x := MathL.ln(x) END;
	IF H.diff THEN
		xorig := x; x := x - H.lastentry; 
		IF IsNaN(H.lastentry) THEN H.lastentry := xorig; RETURN
		ELSE H.lastentry := xorig
		END
	END;
	IF ~H.suspended THEN
		INC(H.nrobs);
		bin := (H.nrobs - 1) MOD Mems;
		H.mem[bin] := x;
		IF H.moving & (H.nrobs >= Mems) THEN GetHistCounts(H, nr); H.nrobs := nr END;
		IF H.adapting & ((x < H.offs) OR (x >= H.top)) THEN 
			IF H.nrobs<Mems THEN (* exact solution *)
		 		min := MAX(LONGREAL); max := MIN(LONGREAL);
			     FOR i := 0 TO H.nrobs - 1 DO 
			     	IF ~IsNaN(H.mem[i]) THEN
			     		IF H.mem[i] < min THEN min := H.mem[i] END;
			     		IF H.mem[i] > max THEN max := H.mem[i] END
			     	END
			     END;
			     w := (max-min)*1.01; IF w < 0 THEN w := 0 END; (*! improve to decimal adjustment *)
			     H.offs := min; H.top := min + w; 
			     
			    (* brute force approximation to gaussian adapted bandwitdht.
			    Asymptotically optimal bandwidth is 3.49* stddev * (H.nrobs)^(-1/3)
			    Brute force assumes range=3.49* stddev *)
	   		 tempbins := SHORT(ENTIER(MathL.exp(MathL.ln(H.nrobs)/3))); 
			    
			     IF tempbins > H.nrBins THEN H.nrBins := tempbins END; 
			     IF H.nrBins < 2 THEN H.nrBins := 2 END;
			     H.width := w / H.nrBins;
			     GetHistCounts(H, nr);
			     RETURN
			ELSE (* rescale *)
				H.adapting := FALSE
			END
		END;
		IF H.moving & (H.nrobs > Mems) THEN GetHistCounts(H, nr) 
		ELSE AddHistCounts(H, x)
		END;
		H.upd:=TRUE
	END (* ~H.suspended *)
 END AddPoint;
	
PROCEDURE RestoreFrame (H: Histogram; M: Display3.Mask; x, y, w, h: INTEGER);
CONST specialwidth = 2;
VAR count: LONGINT; yfact,xfact,curmax: LONGREAL; s: ARRAY 16 OF CHAR; i, width, p, xpos, col, freew: INTEGER; 
BEGIN
	Oberon.RemoveMarks(x, y, w, h);
	freew := w - 2 - 4*specialwidth;
	Display3.Rect3D(M, Display3.bottomC,Display3.topC, x, y, w, h, 1, Display.replace);
	Display3.AdjustMask(M, x+1, y+1, w-2, h-2);
	Display3.ReplConst(M, Display3.textbackC, x, y, w, h, Display.replace);

	IF H.maxcount > 0 THEN 
		curmax:=H.maxcount/H.nrobs;
		IF (curmax < H.prevmax*0.75) OR (curmax > H.prevmax) THEN
			yfact := (h - 2)/(H.maxcount); H.prevmax := curmax;
		ELSE
			yfact := (h-2)/(H.prevmax*H.nrobs);
		END;
		xfact := freew/H.nrBins; width := (freew DIV H.nrBins);
		IF width <= 0 THEN width := 1 END;
		IF H.toosmall > 0 THEN
			xpos := 2; col := 3; p := SHORT(ENTIER(yfact*H.toosmall)); 
			IF p > h THEN p := h; col := 4 END;
			Display3.ReplConst(M, col, x + xpos,  y, width, p, Display.replace);
			Display3.ReplConst(M, Display3.textbackC, x + xpos,  y + p, specialwidth, H.H - p, Display.replace)
		END;
		IF H.toolarge > 0 THEN
			xpos := w - specialwidth - 2; col := 3; p := SHORT(ENTIER(yfact*H.toolarge)); 
			IF p > h THEN p := h; col := 4 END;
			Display3.ReplConst(M, col, x + xpos,  y, width, p, Display.replace);
			Display3.ReplConst(M, Display3.textbackC, x + xpos, y  + p, specialwidth, H.H - p, Display.replace)
		END;
	
		FOR i := 0 TO H.nrBins-1 DO
			count := H.count[i];
			xpos := SHORT(ENTIER(i*xfact)) + 2*specialwidth; p := SHORT(ENTIER(yfact*count)); 
			Display3.ReplConst(M, 12, x + xpos,  y, width, p, Display.replace);
			Display3.ReplConst(M, Display3.textbackC, x + xpos, y + p, width, H.H - p, Display.replace)
		END
	END;

	IF H.offs < H.top THEN
   	 Strings.RealToStr(H.offs, s); Display3.String(M, Display3.textC, x + 2, y + 2, Fonts.Default, s, Display.paint);
    	Strings.RealToStr(H.top, s); Display3.String(M, Display3.textC, x + w - 30, y + 2, Fonts.Default, s, Display.paint)
    END;
    IF H.nrobs # 0.0 THEN
		Strings.RealToStr(H.maxcount/H.nrobs, s); s[5] := 0X; (* brute truncation for maximum percentage*)
		Display3.String(M, Display3.textC, x + 2, y + h - 12, Fonts.Default, s, Display.paint)
	END;
	Display3.String(M, Display3.textC, x + 60, y + h - 12, Fonts.Default, "n=", Display.paint);
	Strings.IntToStr(H.nrobs, s); Display3.String(M, Display3.textC, x + 78, y + h - 12, Fonts.Default, s, Display.paint);
	IF H.nans > 0 THEN
		Display3.String(M, Display3.textC, x + 60, y + h - 24, Fonts.Default, "Missing:", Display.paint);
		Strings.IntToStr(H.nans, s); Display3.String(M, Display3.textC, x + 78, y + h - 24, Fonts.Default, s, Display.paint)
	END;

	IF Gadgets.selected IN H.state THEN
		Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
	END
END RestoreFrame;

PROCEDURE Dev (x: INTEGER): INTEGER;
BEGIN RETURN SHORT(LONG(x) * Display.Unit DIV Printer.Unit)
END Dev;

PROCEDURE PrintFrame (H: Histogram; VAR Msg: Display.DisplayMsg);
CONST specialwidth=2;
VAR i, mode,width,p,xpos: INTEGER; s: ARRAY 16 OF CHAR; freew:INTEGER;M: Display3.Mask; x, y, w, h: INTEGER;
	count:LONGINT;yfact,xfact,curmax:LONGREAL;col:INTEGER;
BEGIN
	x := Msg.x; y := Msg.y; w := Dev(H.W); h := Dev(H.H);
	Gadgets.MakePrinterMask(H, x, y, Msg.dlink, M);
	freew := w - Dev(2 + 4*specialwidth);
	Printer3.Rect3D(M, Display3.bottomC, Display3.topC, x, y, w, h, Dev(1), Display.replace);
	Display3.AdjustMask(M, x + Dev(1), y + Dev(1), w - Dev(2), h - Dev(2));
	Printer3.ReplConst(M, Display3.textbackC, x, y, w, h, Display.replace);

	IF H.maxcount> 0 THEN 
		curmax := H.maxcount/H.nrobs;
		IF (curmax < H.prevmax*0.75) OR (curmax > H.prevmax) THEN
			yfact:=(h - Dev(2))/(H.maxcount); H.prevmax := curmax
		ELSE
			yfact := (h - Dev(2))/(H.prevmax*H.nrobs)
		END;
		xfact := freew / H.nrBins; width := (freew DIV H.nrBins);
		IF width <= 0 THEN width := Dev(1) END;
		IF H.toosmall > 0 THEN
			xpos := Dev(2); col := 3; p := SHORT(ENTIER(yfact*H.toosmall)); 
			IF p > h THEN p := h; col := 4 END;
			Printer3.ReplConst(M, col, x + xpos, y, width, p, Display.replace);
			Printer3.ReplConst(M, Display3.textbackC, x + xpos,  y + p, specialwidth, H.H - p, Display.replace)
		END;
		IF H.toolarge > 0 THEN
			xpos := w - Dev(specialwidth - 2); p := SHORT(ENTIER(yfact*H.toolarge)); 
			IF p > h THEN p := h END;
			Printer3.ReplConst(M, col, x + xpos,  y , width, p, Display.replace);
			Printer3.ReplConst(M, Display3.textbackC, x + xpos,  y  + p, specialwidth, H.H - p, Display.replace)
		END;
	
		FOR i := 0 TO H.nrBins - 1 DO
			count := H.count[i];
			xpos := SHORT(ENTIER(i*xfact)) + Dev(2*specialwidth); p := SHORT(ENTIER(yfact*count)); 
			Printer3.ReplConst(M, 12, x + xpos,  y, width, p, Display.replace);
			Printer3.ReplConst(M, Display3.textbackC, x + xpos,  y  + p, width, H.H - p, Display.replace)
		END
	END;

	mode := Display.paint;
	IF H.offs < H.top THEN
    	Strings.RealToStr(H.offs, s); Printer3.String(M, Display3.textC, x + Dev(2), y + Dev(2), Fonts.Default, s, mode);
   	 Strings.RealToStr(H.top, s); Printer3.String(M, Display3.textC, x + w - Dev(30), y + Dev(2), Fonts.Default, s, mode)
    END;
	Strings.RealToStr(H.maxcount/H.nrobs, s); s[5]:=0X; (* brute truncation for maximum percentage*)
	Printer3.String(M, Display3.textC, x + Dev(2), y + h - Dev(12), Fonts.Default, s, mode);
	Printer3.String(M,Display3.textC, x + Dev(60), y + h - Dev(12), Fonts.Default, "n=", mode);
	Strings.IntToStr(H.nrobs, s); Printer3.String(M, Display3.textC, x + Dev(78), y + h - Dev(12), Fonts.Default, s, mode);
	IF H.nans > 0 THEN
		Printer3.String(M,Display3.textC, x + Dev(60), y + h - Dev(24), Fonts.Default, "Missing:", mode);
		Strings.IntToStr(H.nans, s); Printer3.String(M, Display3.textC, x + Dev(78), y + h - Dev(24), Fonts.Default, s, mode)
	END
END PrintFrame;

PROCEDURE FrameAttr (F: Histogram; VAR M: Objects.AttrMsg);
VAR nr, ilong: LONGINT; x: LONGREAL;
BEGIN
	IF M.id = Objects.get THEN
	(* settable attributes first *)
		IF M.name = "Gen" THEN M.class := Objects.String; COPY("Histogram.NewFrame", M.s); M.res := 0
		ELSIF M.name = "adaptive" THEN M.class := Objects.Bool; M.b := F.adapting; M.res := 0
		ELSIF M.name = "moving" THEN M.class := Objects.Bool; M.b := F.moving; M.res := 0
		ELSIF M.name = "suspended" THEN M.class := Objects.Bool; M.b := F.suspended; M.res := 0
		ELSIF M.name = "Diff" THEN M.class := Objects.Bool; M.b := F.diff; M.res := 0
		ELSIF M.name = "LogTransform" THEN M.class := Objects.Bool; M.b := F.logtransform; M.res := 0
		ELSIF M.name = "DoResetCounts" THEN M.class := Objects.Bool; M.b := FALSE; M.res := 0
		ELSIF M.name = "DoResetAll" THEN M.class := Objects.Bool; M.b := FALSE; M.res := 0
		ELSIF M.name = "Min" THEN M.class := Objects.LongReal; M.y := F.offs; M.res := 0
		ELSIF M.name = "Max" THEN M.class := Objects.LongReal; M.y := F.top; M.res := 0
		ELSIF M.name = "CellWidth" THEN M.class := Objects.LongReal; M.y := F.width; M.res := 0
		ELSIF M.name = "nrCells" THEN M.class := Objects.Int; M.i := F.nrBins; M.res := 0
	(* limited *)
		ELSIF M.name = "NrObs" THEN M.class := Objects.Int; M.i := F.nrobs; M.res := 0
	(* not settable *)
		ELSIF M.name = "TooSmall" THEN M.class := Objects.Int; M.i := F.toosmall; M.res := 0
		ELSIF M.name = "TooLarge" THEN M.class := Objects.Int; M.i := F.toolarge; M.res := 0
		ELSIF M.name = "NaNs" THEN M.class := Objects.Int; M.i := F.nans; M.res := 0
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		(*! handle private fields *)
		IF M.name="NrObs" THEN
			IF (M.class = Objects.Int) & (M.i = 0) THEN F.nrobs := 0; ClearHistCounts(F) END; M.res := 0
		ELSIF M.name="Min" THEN
			IF LongReal(M, x) & (x < F.top) THEN
				F.offs := x; F.width := (F.top - F.offs)/F.nrBins;
				GetHistCounts(F, nr)
			END;
			M.res := 0
		ELSIF M.name = "Max" THEN
			IF LongReal(M, x) & (x > F.offs) THEN
				F.top := x; F.width := (F.top - F.offs)/F.nrBins;
				GetHistCounts(F,nr)
			END;
			M.res := 0
		ELSIF M.name = "CellWidth" THEN
			IF LongReal(M, x) & (x > 0) THEN
				F.width := x; F.top := F.offs + F.width*F.nrBins;
				GetHistCounts(F, nr)
			END;
			M.res := 0
		ELSIF M.name = "nrCells" THEN
			IF LongInt(M, ilong) & (ilong > 0) THEN
				F.nrBins := SHORT(ilong); F.width := (F.top - F.offs)/F.nrBins;
				GetHistCounts(F, F.nrobs)
			END;
			M.res := 0
		ELSIF M.name = "adaptive" THEN
			IF M.class = Objects.Bool THEN F.adapting:=M.b END; M.res := 0
		ELSIF M.name = "moving" THEN
			IF M.class = Objects.Bool THEN F.moving := M.b END; M.res := 0
		ELSIF M.name = "LogTransform" THEN
			IF M.class = Objects.Bool THEN F.logtransform := M.b; Reset(F) END; M.res := 0
		ELSIF M.name = "Diff" THEN
			IF M.class = Objects.Bool THEN F.diff := M.b; Reset(F) END; M.res := 0
		ELSIF M.name = "suspended" THEN
			IF M.class = Objects.Bool THEN F.suspended := M.b END; M.res := 0
		ELSIF M.name = "DoResetCounts" THEN ResetCounts(F); M.res := 0
		ELSIF M.name = "DoResetAll" THEN Reset(F); M.res := 0
		ELSIF (M.name = "TooSmall") OR (M.name = "TooLarge") OR (M.name = "NaNs") THEN M.res := 0
		ELSE Gadgets.framehandle(F, M)
		END;
		F.upd := TRUE
	ELSIF M.id = Objects.enum THEN
		M.Enum("adaptive"); M.Enum("moving"); M.Enum("suspended");
		M.Enum("DoResetCounts"); (*! This should be a button *)
		M.Enum("DoResetAll"); (*! This should be a button *)
		M.Enum("NrObs"); M.Enum("Min"); M.Enum("Max");
		M.Enum("CellWidth"); M.Enum("nrCells");
		M.Enum("NrObs"); M.Enum("TooSmall");
		M.Enum("TooLarge"); M.Enum("NaNs");
		M.Enum("LogTransform"); (*! Implies Reset *)
		M.Enum("Diff"); (*! Implies Reset *)
		Gadgets.framehandle(F, M)
	END
END FrameAttr;

PROCEDURE File (F: Histogram; VAR M: Objects.FileMsg);
CONST Version = 2;
VAR i, version: LONGINT;
BEGIN
	IF M.id=Objects.load THEN 		
		Files.ReadLInt(M.R, version);
		FOR i := 0 TO Bins - 1 DO Files.ReadLInt(M.R,F.count[i]) END;
		Files.ReadInt(M.R, F.nrBins);
		Files.ReadLReal(M.R,F.offs); Files.ReadLReal(M.R,F.width);Files.ReadLReal(M.R,F.top);
		Files.ReadLInt(M.R,F.toosmall); Files.ReadLInt(M.R,F.toolarge);Files.ReadLInt(M.R,F.nans);
		Files.ReadLInt(M.R,F.nrobs); Files.ReadLInt(M.R,F.maxcount);
		Files.ReadLReal(M.R,F.prevmax);
		Files.ReadBool(M.R,F.adapting); Files.ReadBool(M.R,F.moving); Files.ReadBool(M.R,F.suspended);
		F.upd:=TRUE;
		IF version >= 2 THEN Files.ReadBool(M.R,F.logtransform); Files.ReadBool(M.R,F.diff)
		ELSE F.logtransform := FALSE; F.diff := FALSE
		END;
		FOR i := 0 TO Mems - 1 DO Files.ReadLReal(M.R, F.mem[i]) END
	ELSIF M.id=Objects.store THEN
		Files.WriteLInt(M.R, Version);
		FOR i := 0 TO Bins - 1 DO Files.WriteLInt(M.R,F.count[i]) END;
		Files.WriteInt(M.R,F.nrBins);
		Files.WriteLReal(M.R,F.offs); Files.WriteLReal(M.R,F.width); Files.WriteLReal(M.R,F.top);
		Files.WriteLInt(M.R,F.toosmall); Files.WriteLInt(M.R,F.toolarge); Files.WriteLInt(M.R,F.nans);
		Files.WriteLInt(M.R,F.nrobs); Files.WriteLInt(M.R,F.maxcount);
		Files.WriteLReal(M.R,F.prevmax);
		Files.WriteBool(M.R,F.adapting); Files.WriteBool(M.R,F.moving); Files.WriteBool(M.R,F.suspended);
		Files.WriteBool(M.R,F.logtransform); Files.WriteBool(M.R,F.diff);
		FOR i := 0 TO Mems - 1 DO Files.WriteLReal(M.R,F.mem[i]) END
	END;
	Gadgets.framehandle(F, M)
END File;

PROCEDURE CopyFrame* (VAR M: Objects.CopyMsg; from, to: Histogram);
BEGIN
	Gadgets.CopyFrame(M, from, to);
	(* copy private data here *)
	to.count := from.count; to.nrBins := from.nrBins; to.offs := from.offs; to.width := from.width;
	to.top := from.top; to.toosmall := from.toosmall; to.toolarge := from.toolarge; to.nans := from.nans; 
	to.nrobs := from.nrobs; to.maxcount := from.maxcount; to.prevmax := from.prevmax;
	to.adapting := from.adapting;to.moving := from.moving;to.suspended := from.suspended;
	to.logtransform := from.logtransform; to.diff := from.diff; to.mem := from.mem
END CopyFrame;

PROCEDURE FrameHandler* (F: Objects.Object; VAR M: Objects.ObjMsg);
VAR F1: Histogram; x, y, w, h: INTEGER; R : Display3.Mask;
BEGIN
	WITH F: Histogram DO
		IF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF (M.F = NIL) OR (M.F = F) THEN
					x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H; (* calculate actual coordinates *)
					IF M IS Display.DisplayMsg THEN
						WITH M : Display.DisplayMsg DO
							IF M.device = Display.screen THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								IF M.id = Display.area THEN Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h) END;
								RestoreFrame(F, R, x, y, w, h)
							ELSIF M.device = Display.printer THEN PrintFrame(F, M)
							END
						END
					ELSIF M IS Gadgets.UpdateMsg THEN
						WITH M: Gadgets.UpdateMsg  DO
							IF F.obj # NIL THEN F.obj.handle(F.obj, M) END; 
							IF M.obj = F.obj THEN
								IF M.stamp # F.stamp THEN
									F.stamp := M.stamp;
									IF M.obj IS BasicGadgets.Integer THEN AddPoint(F, F.obj(BasicGadgets.Integer).val)
									ELSIF M.obj IS BasicGadgets.Real THEN AddPoint(F, F.obj(BasicGadgets.Real).val)
									END
								END;
								IF ~F.suspended THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									RestoreFrame(F, R, x, y, w, h)
								END
							END
						END
					ELSE Gadgets.framehandle(F, M)
					END
				END
			END
		ELSIF M IS Objects.AttrMsg THEN FrameAttr(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.FileMsg THEN File(F, M(Objects.FileMsg))
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink (*non-first arrival*)
				ELSE (*first arrival*)
					NEW(F1); F.stamp := M.stamp; F.dlink := F1;
					CopyFrame(M, F, F1); M.obj := F1
				END
			END
		ELSE Gadgets.framehandle(F, M)
		END;
		IF F.upd THEN Update(F) END
	END
END FrameHandler;

PROCEDURE InitFrame* (F: Histogram; suspended, diff: BOOLEAN);
BEGIN
	F.W := 130; F.H := 100; F.handle := FrameHandler;
	Reset(F); F.suspended := suspended; F.diff := diff
END InitFrame;

PROCEDURE NewFrame*;
VAR F: Histogram;
BEGIN NEW(F); InitFrame(F, FALSE, FALSE); Objects.NewObj := F
END NewFrame;

PROCEDURE NewSuspendedFrame*;
VAR F: Histogram;
BEGIN NEW(F); InitFrame(F, TRUE, FALSE); Objects.NewObj := F
END NewSuspendedFrame;

PROCEDURE NewDiffFrame*;
VAR F: Histogram;
BEGIN NEW(F); InitFrame(F, FALSE, TRUE); Objects.NewObj := F
END NewDiffFrame;

PROCEDURE NewSuspendedDiffFrame*;
VAR F: Histogram;
BEGIN NEW(F); InitFrame(F, TRUE, TRUE); Objects.NewObj := F
END NewSuspendedDiffFrame;

END Histogram.

(*
System.Free Histogram  ~
Gadgets.Insert Histogram.NewFrame Gages.NewMem ~
Gadgets.Insert Histogram.NewFrame Gages.NewLoad ~
Gadgets.Change Histogram.NewFrame ~

Histogram.NewFrame							gives a running histogram. 
Histogram.NewSuspendedFrame		starts in supended state.  To register updates, "suspended" must be set to FALSE.
Histogram.NewDiffFrame					uses differences instead of true values.
Histogram.NewSuspendedDiffFrame	like NewSuspendedFrame					
*)

