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

MODULE RembrandtTools;	(** portable *)
(** Enthält alle Operationen zum Rembrandt-Editor *)

IMPORT
	D3:= Display3, Display, Oberon, Pictures, Effects, Input, Rembrandt, Gadgets, Texts, Rembrandt0, Math, RembrandtDocs,
		Objects;

CONST
	(* Symmetrien *)
	Yachse =1 ;
	Xachse = 2;
	grad45 = 3;

	(* Schmierrichtung *)
	up = 1;
	down = 2;
	right = 3;
	left = 4;

	MM= 1;
	MR = 0;

VAR
	width, sprayspeed, smearspeed, smx, smy, cdx, cdy: INTEGER; symmetric: SET;
	filled, double: BOOLEAN;
	sintable: ARRAY 91 OF REAL;
	oldtrackMM: Rembrandt.TrackMMProc;
	oldcursor: Oberon.Marker;
	oldval: INTEGER; oldobj: Objects.Object;

PROCEDURE Min(a, b: INTEGER): INTEGER;
BEGIN
	IF a<b THEN RETURN a ELSE RETURN b END
END Min;

PROCEDURE Max(a, b: INTEGER): INTEGER;
BEGIN
	IF a<b THEN RETURN b ELSE RETURN a END
END Max;

PROCEDURE Update(P : Pictures.Picture; x, y, w, h: INTEGER);
BEGIN
	IF x<0 THEN w:=w+x; x:=0 END;
	IF y<0 THEN h:=h+y; y:=0 END;
	IF (w>0) & (h>0) THEN Pictures.Update(P, x, y, w, h) END
END Update;

PROCEDURE GetRun(P : Pictures.Picture; VAR col, x: INTEGER; y: INTEGER);
BEGIN
	IF (y<0) OR (y>=P.height) THEN
		INC(x); col:= D3.BG
	ELSIF x<0 THEN
		x:=0; col:= D3.BG
	ELSIF x>=P.width THEN
		INC(x); col:= D3.BG
	ELSE
		Pictures.GetRun(P, col, x, y)
	END
END GetRun;

PROCEDURE FilledCircle(P : Pictures.Picture; xm, ym, r, col: INTEGER);
VAR x, y , dx, dy, d : INTEGER; 
BEGIN
	x := r; y := 0; d := 2*r-1; dx := 4*r; dy := 0;
	WHILE y < r DO
		WHILE d <= 0 DO DEC(x); DEC(dx,4); INC(d,dx) END;
		Rembrandt0.ReplConst(P, col, xm-x+r, ym+y+r, 2*x,1);
		INC(y); INC(dy,4); DEC(d,dy);
		Rembrandt0.ReplConst(P, col, xm-x+r, ym-y+r, 2*x,1);
	END
END FilledCircle;

PROCEDURE SetPoint(P: Pictures.Picture; x, y, col: INTEGER);
BEGIN
	IF width=1 THEN
		IF symmetric#{} THEN
			IF Yachse IN symmetric THEN Pictures.Dot(P, col, -x+2*smx, y, Display.replace) END;
			IF Xachse IN symmetric THEN Pictures.Dot(P, col, x, -y+2*smy, Display.replace) END;
			IF (Xachse IN symmetric) & (Yachse IN symmetric) THEN
				IF grad45 IN symmetric THEN
					Pictures.Dot(P, col, smx+y-smy, smy+x-smx, Display.replace);
					Pictures.Dot(P, col, smx+y-smy, smy-x+smx,  Display.replace);
					Pictures.Dot(P, col, smx-y+smy, smy+x-smx, Display.replace);
					Pictures.Dot(P, col, smx-y+smy, smy-x+smx, Display.replace)
				END;
				Pictures.Dot(P, col, -x+2*smx, -y+2*smy, Display.replace)
			END;
		END;
		Pictures.Dot(P, col, x, y, Display.replace);
	ELSE
		IF symmetric#{} THEN
			IF Yachse IN symmetric THEN FilledCircle(P, -x+2*smx-width, y, width DIV 2, col) END;
			IF Xachse IN symmetric THEN FilledCircle(P, x,-y+2*smy-width, width DIV 2, col) END;
			IF (Xachse IN symmetric) & (Yachse IN symmetric) THEN
				IF grad45 IN symmetric THEN
					FilledCircle(P, smx+y-smy, smy+(-x+2*smx)-smx-width, width DIV 2, col);
					FilledCircle(P, smx+(-y+2*smy)-smy-width,smy+x-smx, width DIV 2, col); 
					FilledCircle(P, smx+y-smy, smy+x-smx, width DIV 2, col);
					FilledCircle(P, smx+(-y+2*smy)-smy-width, smy+(-x+2*smx)-smx-width, width DIV 2, col) 
				END;
				FilledCircle(P, -x+2*smx-width,-y+2*smy-width, width DIV 2, col) END;
		END;
		FilledCircle(P, x, y, width DIV 2, col);
	END;
END SetPoint;

PROCEDURE Circle(P : Pictures.Picture; xm, ym, r: INTEGER);
VAR x, y, d, col : INTEGER; sym: SET;
BEGIN
	sym:= symmetric; symmetric:= {}; 
	col:= Rembrandt0.color.col;
	x:= r; y:= 0; d:= 1-4*r;
	SetPoint(P, xm+r, ym, col);
	SetPoint(P, xm-r, ym, col);
	SetPoint(P, xm, ym+r, col);
	SetPoint(P, xm, ym-r, col);
	WHILE y<x DO
		d:=d+8*y+4; INC(y);
		IF d>=0 THEN DEC(x); d:=d-8*x END;
		SetPoint(P, xm+x, ym+y, col);
		SetPoint(P, xm-x, ym+y, col);
		SetPoint(P, xm+x, ym-y, col);
		SetPoint(P, xm-x, ym-y, col);
		SetPoint(P, xm-y, ym-x, col);
		SetPoint(P, xm+y, ym+x, col);
		SetPoint(P, xm-y, ym+x, col);
		SetPoint(P, xm+y, ym-x, col)
	END;
	symmetric:= sym
END Circle;

PROCEDURE SetLine(P: Pictures.Picture; x0, y0, x1, y1, col: INTEGER);
VAR x, y, d, dx, dy, incx, incy, w, h: INTEGER;
BEGIN
	x:= x0; y:= y0;
	dx:= (x1-x0)*2; dy:= (y1-y0)*2;
	incx:=0;
	IF dx<0 THEN incx:=-1; dx:=-dx ELSIF dx>0 THEN incx:=1 END;
	incy:=0;
	IF dy<0 THEN incy:=-1; dy:=-dy ELSIF dy>0 THEN incy:=1 END;
	SetPoint(P, x, y, col);
	d:= incx*(x0-x1);
	IF dx>dy THEN
		WHILE x#x1 DO
			INC(x, incx); INC(d, dy);
			IF d>0 THEN INC(y, incy); DEC(d, dx) END;
			SetPoint(P, x, y, col)
		END
	ELSE
		WHILE y#y1 DO
			INC(y, incy); INC(d, dx);
			IF d>0 THEN INC(x, incx); DEC(d, dy) END;
			SetPoint(P, x, y, col)
		END
	END;
	x:= Min(x0, x1); w:= ABS(x0-x1);
	y:= Min(y0, y1); h:= ABS(y0-y1);
	IF symmetric#{} THEN
		IF width=1 THEN
			IF Yachse IN symmetric THEN Update(P, 2*smx-x-w, y, w+1, h+1) END;
			IF Xachse IN symmetric THEN Update(P, x, 2*smy-y-h, w+1, h+1) END;
			IF (Xachse IN symmetric) & (Yachse IN symmetric) THEN
				IF grad45 IN symmetric THEN
					Update(P, smx+y-smy, smy+x-smx, h+1, w+1);
					Update(P, smx+y-smy, smy+smx-x-w, h+1, w+1);
					Update(P, smx+smy-y-h, smy+x-smx, h+1, w+1);
					Update(P, smx+smy-y-h, smy+smx-x-w, h+1, w+1)
				END;
				Update(P, 2*smx-x-w, 2*smy-y-h, w+1, h+1)
			END;
		ELSE
			IF Yachse IN symmetric THEN Update(P, 2*smx-x-w-width, y, w+width, h+width) END;
			IF Xachse IN symmetric THEN Update(P, x, 2*smy-y-h-width, w+width, h+width) END;
			IF (Xachse IN symmetric) & (Yachse IN symmetric) THEN
				IF grad45 IN symmetric THEN
					Update(P, smx+y-smy, smy+x-smx, h+width, w+width);
					Update(P, smx+y-smy, smy+smx-x-w-width, h+width, w+width);
					Update(P, smx+smy-y-h-width, smy+x-smx, h+width, w+width);
					Update(P, smx+smy-y-h-width, smy+smx-x-w-width, h+width, w+width)
				END;
				Update(P, 2*smx-x-w-width, 2*smy-y-h-width, w+width, h+width)
			END;
		END
	END;
	Update(P, x, y, w+width, h+width)
END SetLine;

PROCEDURE SetRectangle(P: Pictures.Picture; x, y, w, h: INTEGER);
BEGIN
	IF (filled) OR (w<width) OR (h<width) THEN
		Rembrandt0.ReplConst(P, Rembrandt0.color.col, x, y, w, h)
	ELSE
		Rembrandt0.ReplConst(P, Rembrandt0.color.col, x, y, w, width);
		Rembrandt0.ReplConst(P, Rembrandt0.color.col, x, y+h-width, w, width);
		Rembrandt0.ReplConst(P, Rembrandt0.color.col, x, y+width, width, h-2*width);
		Rembrandt0.ReplConst(P, Rembrandt0.color.col, x+w-width, y+width, width, h-2*width)
	END;
	Update(P, x, y, w, h)
END SetRectangle;

PROCEDURE Fillarea(F: Rembrandt.Frame; x0, y0: INTEGER);
(* fills the area around x0,y0*)
CONST    size=10;

TYPE Stack=POINTER TO StackDesc;
		StackDesc=RECORD
			x, y: ARRAY size OF INTEGER;
			prev, next: Stack;
		END;

VAR  st: Stack;
	bg: INTEGER; 
	x, y, 	
	l, r, 		(*left and right border of actual line*)
	l0, r0, 	(*left and right border of previous line*)
	l2, r2, 	
	pos: INTEGER;  	(*stack pointer*)
	P : Pictures.Picture;
	
	PROCEDURE PUT(x, y: INTEGER);
	(*put the pair x, y onto the stack*)
	BEGIN
		IF pos=size THEN
			IF st.next=NIL THEN NEW(st.next);  st.next.prev:=st END;
			st:=st.next;  pos:=0;
		END; (*if*)
		st.x[pos]:=x;  st.y[pos]:=y;
		INC(pos);
	END PUT;
	
	PROCEDURE GET(VAR x, y: INTEGER): BOOLEAN;
	(*fetch the pair x, y from the stack, return FALSE<=>stack is empty*)
	BEGIN
		IF pos=0 THEN
			st:=st.prev;  pos:=size;
		END;
		IF st#NIL THEN
			DEC(pos);
			x:=st.x[pos];  y:=st.y[pos];
			RETURN TRUE;
		ELSE
			RETURN FALSE;
		END; (*if*)
	END GET;

	PROCEDURE ScanRight(x0, lim, y: INTEGER;  background : BOOLEAN): INTEGER;
	(*scan line on y to first pixel in col, starting at x0*)
	BEGIN
		IF background THEN WHILE (x0<lim) & (bg # Pictures.Get(P,x0,y)) DO INC(x0) END;
		ELSE WHILE (x0<lim) & (bg = Pictures.Get(P,x0,y)) DO INC(x0) END END;
		RETURN x0;
	END ScanRight;
	
	PROCEDURE ScanLeft(x0, lim, y: INTEGER;  background : BOOLEAN): INTEGER;
	(*scan line on y to first pixel in col, starting at x0*)
	BEGIN
		IF background THEN WHILE (x0>lim) & (bg #  Pictures.Get(P,x0,y)) DO DEC(x0) END;
		ELSE WHILE (x0>lim) & (bg = Pictures.Get(P,x0,y)) DO DEC(x0) END END;
		RETURN x0;
	END ScanLeft;
	
	PROCEDURE FillLine(x, y: INTEGER;  VAR l, r: INTEGER);
	(*fill line starting at x, y with black, return left & right end of line*)
	BEGIN
		l:=ScanLeft(x, -1, y, FALSE)+1;
		IF l>x THEN (*no line to fill*)
			r:=x-1;
		ELSE
			r := ScanRight(x, P.width,y,FALSE)-1;
			IF r>=P.width THEN r:=P.width-1 END;
			Pictures.ReplConst(F.pict, Rembrandt0.color.col, l, y,r-l+1,1,Display.replace);
		END; (*if*)
	END FillLine;

BEGIN
	P := F.pict; bg := Pictures.Get(P,x0, y0); 
	IF (Rembrandt0.color.col = bg) OR ~Effects.Inside(x0, y0, 0, 0, P.width, P.height) THEN RETURN END;
	NEW(st); pos:=0;
	PUT(x0, y0);
	WHILE GET(x, y) DO
		WHILE (y>0) & (Pictures.Get(P,x, y-1)= bg) DO DEC(y) END;
		r0:=x-1;  l0:=x+1;
		REPEAT
			FillLine(x, y, l, r);
			IF (r-r0>1) & (y>0) THEN	(*fill area to the right beneath y*)
				l2:=r0+1;
				LOOP
					l2:=ScanRight(l2, r+1, y-1, TRUE);
					IF l2<=r THEN
						r2:=ScanRight(l2, P.width, y-1, FALSE)-1;
						PUT((l2+r2) DIV 2, y-1);  l2:=r2+1;
					ELSE
						EXIT;
					END; (*if*)
				END; (*loop*)
			ELSIF (r0-r>1) THEN	(*fill area to the right above y*)
				l2:=r+1;
				LOOP
					l2:=ScanRight(l2, r0+1, y, TRUE);
					IF l2<=r0 THEN
						r2:=ScanRight(l2, P.width, y, FALSE)-1;
						PUT((l2+r2) DIV 2, y);  l2:=r2+1;
					ELSE
						EXIT;
					END; (*if*)
				END; (*loop*)
			END; (*if*)
			IF (l0-l>1) & (y>0) THEN	(*fill area to the left beneath y*)
				r2:=l0-1;
				LOOP
					r2:=ScanLeft(r2, l-1, y-1, TRUE);
					IF r2>=l THEN
						l2:=ScanLeft(r2, -1, y-1, FALSE)+1;
						PUT((l2+r2) DIV 2, y-1);  r2:=l2-1;
					ELSE
						EXIT;
					END; (*if*)
				END; (*loop*)
			ELSIF (l-l0>1) THEN	(*fill area to the left above y*)
				r2:=l-1;
				LOOP
					r2:=ScanLeft(r2, l0-1, y, TRUE);
					IF r2>=l0 THEN
						l2:=ScanLeft(r2, -1, y, FALSE)+1;
						PUT((l2+r2) DIV 2, y);  r2:=l2-1;
					ELSE
						EXIT;
					END; (*if*)
				END; (*loop*)
			END; (*if*)
			INC(y);
			l0:=l;  r0:=r;
		UNTIL (y=P.height) OR (l>r);
	END; (*while*)
	Update(P,0,0,P.width,P.height);
END Fillarea;

PROCEDURE GetColor(P: Pictures.Picture; x, y: INTEGER): INTEGER;
BEGIN
	IF (x<0) OR (x>P.width) OR (y<0) OR (y>P.height) THEN
		RETURN D3.BG
	ELSE
		RETURN Pictures.Get(P, x, y)
	END
END GetColor;

PROCEDURE SetSmear(F: Rembrandt.Frame; xm, ym, direction: INTEGER);
VAR r, maxy, maxx, y, d, dx, dy, x, col, dr, i: INTEGER; 
BEGIN
	r:= width DIV 2;
		IF direction= down THEN
			maxy:= r; x:=0; d:= 2*r-1; dx:= 4*r; dy:=0;
			WHILE x<r DO
				WHILE d<= 0  DO DEC(maxy); DEC(dx, 4); INC(d, dx) END;
				IF maxy>= 1 THEN
					FOR i:= 1 TO smearspeed DO
						dr:= SHORT(ENTIER(Rembrandt0.Uniform()*maxy));
						col:= GetColor(F.pict, xm+x, ym+dr);
						IF col=Rembrandt0.color.col THEN
							Pictures.Dot(F.pict, col, xm+x, ym-dr, Display.replace)
						END;
						col:= GetColor(F.pict, xm-x, ym+dr);
						IF col=Rembrandt0.color.col THEN
							Pictures.Dot(F.pict, col, xm-x, ym-dr, Display.replace)
						END;
					END
				END;
				INC(x); INC(dy, 4); DEC(d, dy)
			END
		ELSIF direction = up THEN
			maxy:= r; x:=0; d:= 2*r-1; dx:= 4*r; dy:=0;
			WHILE x<r DO
				WHILE d<= 0  DO DEC(maxy); DEC(dx, 4); INC(d, dx) END;
				IF maxy>= 1 THEN
					FOR i:= 1 TO smearspeed DO
						dr:= SHORT(ENTIER(Rembrandt0.Uniform()*maxy));
						col:= GetColor(F.pict, xm+x, ym-dr);
						IF col=Rembrandt0.color.col THEN
							Pictures.Dot(F.pict, col, xm+x, ym+dr, Display.replace)
						END;
						col:= GetColor(F.pict, xm-x, ym-dr);
						IF col=Rembrandt0.color.col THEN
							Pictures.Dot(F.pict, col, xm-x, ym+dr, Display.replace)
						END;
					END
				END;
				INC(x); INC(dy, 4); DEC(d, dy)
			END
		ELSIF direction = left THEN
			maxx:= r; y:=0; d:= 2*r-1; dx:= 4*r; dy:=0;
			WHILE y<r DO
				WHILE d<= 0 DO DEC(maxx); DEC(dx, 4); INC(d, dx) END;
				IF maxx>= 1 THEN
					FOR i:= 1 TO smearspeed DO
						dr:= SHORT(ENTIER(Rembrandt0.Uniform()*maxx));
						col:= GetColor(F.pict, xm+dr, ym+y);
						IF col=Rembrandt0.color.col THEN
							Pictures.Dot(F.pict, col, xm-dr, ym+y, Display.replace)
						END;
						col:= GetColor(F.pict, xm+dr, ym-y);
						IF col=Rembrandt0.color.col THEN
							Pictures.Dot(F.pict, col, xm-dr, ym-y, Display.replace)
						END;
					END
				END;
				INC(y); INC(dy, 4); DEC(d, dy)
			END
		ELSIF direction = right THEN
			maxx:= r; y:=0; d:= 2*r-1; dx:= 4*r; dy:=0;
			WHILE y<r DO
				WHILE d<= 0 DO DEC(maxx); DEC(dx, 4); INC(d, dx) END;
				IF maxx>= 1 THEN
					FOR i:= 1 TO smearspeed DO
						dr:= SHORT(ENTIER(Rembrandt0.Uniform()*maxx));
						col:= GetColor(F.pict, xm-dr, ym+y);
						IF col=Rembrandt0.color.col THEN
							Pictures.Dot(F.pict, col, xm+dr, ym+y, Display.replace)
						END;
						col:= GetColor(F.pict, xm-dr, ym-y);
						IF col=Rembrandt0.color.col THEN
							Pictures.Dot(F.pict, col, xm+dr, ym-y, Display.replace)
						END;
					END
				END;
				INC(y); INC(dy, 4); DEC(d, dy)
			END
		END;
	Pictures.Update(F.pict, xm-r, ym-r, width, width)
END SetSmear;

PROCEDURE SetClone(F: Rembrandt.Frame; xm, ym: INTEGER);
VAR x, y , dx, dy, d, r , col, i, j: INTEGER; 
BEGIN
	r:= width DIV 2;
	x := r; y := 0; d := 2*r-1; dx := 4*r; dy := 0;
	WHILE y < r DO
		WHILE d <= 0 DO DEC(x); DEC(dx,4); INC(d,dx) END;
		i:= xm-x; 
		WHILE i<xm+x DO
			j:=i;
			GetRun(F.pict, col, i, ym+y);
			IF i>xm+x THEN i:= xm+x END;
			Rembrandt0.ReplConst(F.pict, col, cdx+j, cdy+ym+y, i-j, 1)
		END;
		INC(y); INC(dy,4); DEC(d,dy);
		i:= xm-x; 
		WHILE i<xm+x DO
			j:=i;
			GetRun(F.pict, col, i, ym-y);
			IF i>xm+x THEN i:= xm+x END;
			Rembrandt0.ReplConst(F.pict, col, cdx+j, cdy+ym-y, i-j, 1)
		END
	END;
	Pictures.Update(F.pict, xm+cdx-r, ym+cdy-r, width, width);
END SetClone;

PROCEDURE Delete(F: Rembrandt.Frame; xm, ym: INTEGER);
VAR x, y , dx, dy, d, r , col, i, j: INTEGER; 
BEGIN
	IF width>1 THEN
		r:= (width+1) DIV 2; INC(xm); INC(ym);
		x := r; y := 0; d := 2*r-1; dx := 4*r; dy := 0;
		WHILE y < r DO
			WHILE d <= 0 DO DEC(x); DEC(dx,4); INC(d,dx) END;
			IF ym+y<F.pict.height THEN
				i:= xm-x; 
				WHILE i<xm+x DO
					j:=i;
					GetRun(F.pict, col, i, ym+y);
					IF i>xm+x THEN i:= xm+x END;
					IF col=Rembrandt0.color.col THEN Rembrandt0.ReplConst(F.pict, D3.BG, j, ym+y, i-j, 1) END
				END
			END;
			INC(y); INC(dy,4); DEC(d,dy);
			IF ym-y>0 THEN
				i:= xm-x; 
				WHILE i<xm+x DO
					j:=i;
					GetRun(F.pict, col, i, ym-y);
					IF i>xm+x THEN i:= xm+x END;
					IF col=Rembrandt0.color.col THEN Rembrandt0.ReplConst(F.pict, D3.BG, j, ym-y, i-j, 1) END
				END
			END;
		END;
		Pictures.Update(F.pict, xm-r, ym-r, width+1, width+1);
	ELSE
		col:=Pictures.Get(F.pict, xm ,ym);
		IF col=Rembrandt0.color.col THEN Pictures.Dot(F.pict, D3.BG, xm, ym, Display.replace) END;
		Pictures.Update(F.pict, xm, ym, 1, 1)
	END
END Delete;

PROCEDURE HandleScale(F: Rembrandt.Frame; VAR M: Oberon.InputMsg; x, y: INTEGER);
VAR Q: D3.Mask; ox, oy, selx, sely, selw, selh, zoom: INTEGER; S, P: Pictures.Picture;
BEGIN
	IF F.selection#Rembrandt.No THEN
		Rembrandt.GetZoom(F, zoom);
		Rembrandt.PicttoScreen(F, x, y, F.sx, F.sy, ox, oy);
		Rembrandt.GetSelectioninFrame(F, S, selx, sely, selw, selh);
		Rembrandt.RemoveSelection(F);
		Gadgets.MakeMask(F, x, y, M.dlink, Q);
		F.sw:= F.sw*zoom; F.sh:= F.sh*zoom;
		Rembrandt.SizeRect(F, x, y, Q, M.keys, M.X, M.Y, ox, oy, F.sw, F.sh, TRUE);
		IF M.keys = {MM} THEN
			NEW(P); Rembrandt0.AllocatePictureMem(P, F.sw, F.sh, F.pict.depth);
			Pictures.Copy(S, P, selx, sely, selw, selh, 0, 0, F.sw, F.sh, Display.replace);
			RembrandtDocs.OpenPict(P, "")
		END
	END;
	M.res:=0;
END HandleScale;

PROCEDURE ConvertInttoString(number: INTEGER; VAR text: ARRAY OF CHAR);
BEGIN
	IF number<0 THEN text[0]:= "-"; number:=-number ELSE text[0]:= " " END;
	text[1]:= CHR((number MOD 1000) DIV 100 +48);
	text[2]:= CHR((number MOD 100) DIV 10 +48);
	text[3]:= CHR(number MOD 10 +48);
	text[4]:= 0X;
END ConvertInttoString;

PROCEDURE Rot(mx, my: INTEGER; VAR x, y: INTEGER; VAR phi: INTEGER);
VAR hx, hy: INTEGER; 
BEGIN
	IF phi>180 THEN
		phi:= phi-360
	ELSIF phi<-180 THEN
		phi:= phi+360
	END;
	hx:=x; hy:= y;
	IF (phi<0) & (phi>-91) THEN
		x:= SHORT(ENTIER((sintable[90+phi]*(hx-mx)+sintable[-phi]*(hy-my)+0.5))+mx);
		y:= SHORT(ENTIER((sintable[90+phi]*(hy-my)-sintable[-phi]*(hx-mx)+0.5))+my);
	ELSIF (phi>0) & (phi<91) THEN
		x:= SHORT(ENTIER((sintable[90-phi]*(hx-mx)-sintable[phi]*(hy-my)+0.5))+mx);
		y:= SHORT(ENTIER((sintable[90-phi]*(hy-my)+sintable[phi]*(hx-mx)+0.5))+my);
	ELSIF (phi>90) & (phi<181) THEN
		x:= SHORT(ENTIER((-sintable[phi-90]*(hx-mx)-sintable[180-phi]*(hy-my)+0.5))+mx);
		y:= SHORT(ENTIER((-sintable[phi-90]*(hy-my)+sintable[180-phi]*(hx-mx)+0.5))+my);
	ELSIF (phi<-90) & (phi>-181) THEN
		x:= SHORT(ENTIER((-sintable[-phi-90]*(hx-mx)+sintable[180+phi]*(hy-my)+0.5))+mx);
		y:= SHORT(ENTIER((-sintable[-phi-90]*(hy-my)-sintable[180+phi]*(hx-mx)+0.5))+my);
	END
END Rot;

PROCEDURE HandleRotate(F: Rembrandt.Frame; VAR M: Oberon.InputMsg; x, y: INTEGER);
CONST dispw=40; disph=16;
VAR keysum: SET; ox, oy, px, py, dphi, phi: INTEGER; Q: D3.Mask;
		orx1, ory1, orx2, ory2, orx3, ory3, orx4, ory4, cmx, cmy: INTEGER; S, D, P: Pictures.Picture;
		ox1, oy1, ox2, oy2, ox3, oy3, ox4, oy4, selx, sely, selw, selh, zoom: INTEGER;
		disptext: ARRAY 8 OF CHAR;

	PROCEDURE DrawRectangle;
	BEGIN
		Oberon.FadeCursor(Oberon.Mouse);
		D3.Line(Q, D3.black, Display.solid, orx1, ory1, orx2, ory2, zoom, Display.invert);
		D3.Line(Q, D3.black, Display.solid, orx2, ory2, orx3, ory3, zoom, Display.invert);
		D3.Line(Q, D3.black, Display.solid, orx4, ory4, orx3, ory3, zoom, Display.invert);
		D3.Line(Q, D3.black, Display.solid, orx1, ory1, orx4, ory4, zoom, Display.invert);
	END DrawRectangle;

	PROCEDURE Rotation(S: Pictures.Picture; phi: INTEGER): Pictures.Picture;
	VAR D: Pictures.Picture; px, py: INTEGER;
			dx, dy, tan, sin, maxx, maxy, h1, h2: REAL;
	BEGIN
	IF (phi>0) & (phi<91) THEN
		sin:= sintable[phi];
		tan:=(1-sintable[90-phi])/sin;
		maxx:= (S.height-0.5)*tan;
		NEW(D); Rembrandt0.AllocatePictureMem(D, S.width+SHORT(ENTIER(maxx)), S.height, S.depth);
		IF D=NIL THEN RETURN NIL END;
		py:=0;
		WHILE py<S.height DO
			dx:= -tan*(py+0.5);
			Pictures.CopyBlock(S, D, 0, py, S.width, 1, SHORT(ENTIER(maxx+dx)), py, Display.replace);
			INC(py)
		END;
		S:= D; 
		maxy:= (S.width-2*maxx)*sin; 
		h1:= (S.width-maxx)*sin;
		h2:= S.height-maxx*sin;
		NEW(D); Rembrandt0.AllocatePictureMem(D, S.width, S.height+SHORT(ENTIER(maxy)), S.depth);
		IF D=NIL THEN RETURN NIL END;
		px:=0;
		WHILE px< S.width DO
			dy:= sin*(px-maxx+0.5);
			IF dy<0 THEN
				Pictures.CopyBlock(S, D, px, SHORT(ENTIER(-dy)), 1, SHORT(ENTIER(S.height+dy)), px, 0, Display.replace);
			ELSE
				Pictures.CopyBlock(S, D, px, 0, 1, S.height, px, SHORT(ENTIER(dy)), Display.replace);
			END;
			INC(px)
		END;
		S:= D; 
		maxx:= h2*tan;
		NEW(D); Rembrandt0.AllocatePictureMem(D, S.width+SHORT(ENTIER(maxx-h1*tan)), S.height, S.depth);
		IF D=NIL THEN RETURN NIL END;
		py:=0;
		WHILE py<S.height DO
			dx:= -tan*(py+0.5); 
			IF maxx+dx<0 THEN
				Pictures.CopyBlock(S, D, SHORT(ENTIER(-dx-maxx)), py, S.width+SHORT(ENTIER(dx+maxx)), 1, 0, py, Display.replace)
			ELSE
				Pictures.CopyBlock(S, D, 0, py, S.width, 1,SHORT(ENTIER(maxx+dx)), py, Display.replace)
			END;
			INC(py)
		END;
	ELSIF (phi<0) & (phi>-91) THEN
		sin:=-sintable[-phi];
		tan:=(1-sintable[phi+90])/sin;
		maxx:= (S.height-0.5)*tan;
		NEW(D); Rembrandt0.AllocatePictureMem(D, S.width+SHORT(ENTIER(-maxx)), S.height, S.depth);
		IF D=NIL THEN RETURN NIL END;
		py:=0;
		WHILE py<S.height DO
			dx:= -tan*(py+0.5);
			Pictures.CopyBlock(S, D, 0, py, S.width, 1, SHORT(ENTIER(dx)), py, Display.replace);
			INC(py)
		END;
		S:= D; 
		maxy:= (S.width+maxx)*sin; 
		NEW(D); Rembrandt0.AllocatePictureMem(D, S.width, S.height+SHORT(ENTIER(-maxy-maxx*sin)), S.depth);
		IF D=NIL THEN RETURN NIL END;
		px:=0;
		WHILE px< S.width DO
			dy:= sin*(px+0.5);
			IF -maxy+dy<0 THEN
				Pictures.CopyBlock(S, D, px, -SHORT(ENTIER(-maxy+dy)), 1, S.height-SHORT(ENTIER(-maxy+dy)), px, 0, Display.replace)
			ELSE
				Pictures.CopyBlock(S, D, px, 0, 1, S.height, px, SHORT(ENTIER(-maxy+dy)), Display.replace)
			END;
			INC(px)
		END;
		h1:= S.height+S.width*sin;
		S:= D; 
		maxx:= h1*tan; 
		NEW(D); Rembrandt0.AllocatePictureMem(D, S.width-SHORT(ENTIER(maxx)), S.height, S.depth);
		IF D=NIL THEN RETURN NIL END;
		py:=0;
		WHILE py<S.height DO
			dx:= -tan*(py+maxy+0.5); 
			IF dx<0 THEN
				Pictures.CopyBlock(S, D, SHORT(ENTIER(-dx)), py, S.width+SHORT(ENTIER(dx)), 1, 0, py, Display.replace)
			ELSE
				Pictures.CopyBlock(S, D, 0, py, S.width, 1,SHORT(ENTIER(dx)), py, Display.replace)
			END;
			INC(py)
		END; 
	ELSE
		D:=S
	END;
	RETURN D
	END Rotation;

BEGIN
	Rembrandt.PicttoScreen(F, x, y, F.sx, F.sy, ox, oy);
	IF F.selection=Rembrandt.No THEN RETURN END;
	Gadgets.MakeMask(F, x, y, M.dlink, Q);
	orx1:= ox; ory1:= oy; orx2:= (ox+F.sw*zoom); ory2:= oy; orx3:= orx2; ory3:= (oy+F.sh*zoom); orx4:= ox; ory4:= ory3;
	ox1:= orx1; oy1:= ory1; ox2:= orx2; oy2:= ory2; ox3:= orx3; oy3:= ory3; ox4:= orx4; oy4:= ory4;
	cmx:= orx1+(orx2-orx1+1) DIV 2;
	cmy:= ory1+(ory3-ory1+1) DIV 2;
	Oberon.FadeCursor(Oberon.Mouse);
	Effects.OpenMenu(cmx, cmy, dispw, disph);
	DrawRectangle;
	ox:=M.X; oy:=M.Y; phi:=0;
	ConvertInttoString(phi, disptext);
	Rembrandt.DisplayText(cmx, cmy, dispw, disph, disptext);
	keysum:= M.keys;
	REPEAT
		IF (M.X#ox) THEN
			Oberon.FadeCursor(Oberon.Mouse);
			DrawRectangle;
			dphi:= M.X-ox; 
			INC(phi, dphi);
			orx1:= ox1; ory1:= oy1; orx2:= ox2; ory2:= oy2; orx3:= ox3; ory3:= oy3; orx4:= ox4; ory4:= oy4;
			Rot(cmx, cmy, orx1, ory1, phi); Rot(cmx, cmy, orx2, ory2, phi); Rot(cmx, cmy, orx3, ory3, phi); Rot(cmx, cmy, orx4, ory4, phi);
			DrawRectangle;
			ConvertInttoString(phi, disptext);
			Rembrandt.DisplayText(cmx, cmy, dispw, disph, disptext);
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Cross, M.X, M.Y); 
		ox:=M.X; oy:= M.Y;
		Input.Mouse(M.keys, M.X, M.Y);
		keysum := keysum + M.keys
	UNTIL M.keys = {};
	DrawRectangle;
	Effects.CloseMenu;;
	Rembrandt.GetSelectioninFrame(F, P, selx, sely, selw, selh);
	IF (keysum = {MM}) & (phi#0) THEN
		IF ABS(phi)>90 THEN
			NEW(D); Rembrandt0.AllocatePictureMem(D, selw, selh, F.pict.depth);
			IF D#NIL THEN
				py:= sely;
				WHILE py< selh+sely DO
					Pictures.CopyBlock(P, D, selx, py, selw, 1, 0, selh-py+sely-1, Display.replace);
					INC(py)
				END;
				NEW(S); Rembrandt0.AllocatePictureMem(S, selw, selh, D.depth); 
				IF S#NIL THEN
					px:= 0;
					WHILE px<selw DO
						Pictures.CopyBlock(D, S, px, 0, 1, selh, selw-px-1, 0, Display.replace);
						INC(px)
					END;
					IF phi>0 THEN phi:= phi-180 ELSE phi:= phi+180 END
				END
			END
		ELSE
			IF (selw#F.pict.width) OR (selh#F.pict.height) THEN
				NEW(S); Rembrandt0.AllocatePictureMem(S, selw, selh, F.pict.depth);
				IF S#NIL THEN Pictures.CopyBlock(P, S, selx, sely, selw, selh, 0, 0, Display.replace) END
			ELSE
				NEW(S); S:= F.pict
			END
		END;
		D:= Rotation(S, phi);
		IF D#NIL THEN RembrandtDocs.OpenPict(D, "") END
	END;
	M.keys:= keysum
END HandleRotate;

PROCEDURE HandlePoints(F: Rembrandt.Frame; VAR M: Oberon.InputMsg; x, y: INTEGER);
VAR keysum: SET; px0, py0, px1, py1, r: INTEGER; 
BEGIN
	r:= width DIV 2; 
	keysum := M.keys;
	Rembrandt.ScreentoPict(F, x, y, M.X, M.Y, px0, py0);
	px1:= px0; py1:= py0;
	Rembrandt.SavePicture(F.pict, 0, 0, F.pict.width, F.pict.height);
	IF F.car THEN cdx:= F.cx-px0; cdy:= F.cy-py0; smx:= F.cx; smy:= F.cy END;
	SetPoint(F.pict, px0-r, py0-r, Rembrandt0.color.col);
	IF double THEN SetPoint(F.pict, px0-r+cdx, py0-r+cdy, Rembrandt0.color.col); Update(F.pict, px0-r+cdx, py0-r+cdy, width, width) END;
	IF symmetric#{} THEN
		IF width=1 THEN r:=0 ELSE r:= (width+1) DIV 2 END;
		IF Yachse IN symmetric THEN Update(F.pict, 2*smx-px0-r, py0-r, width, width) END;
		IF Xachse IN symmetric THEN Update(F.pict, px0-r, 2*smy-py0-r, width, width) END;
		IF (Xachse IN symmetric) & (Yachse IN symmetric) THEN
			IF grad45 IN symmetric THEN
				Update(F.pict, smx-smy+py0-r, smy-smx+px0-r, width, width);
				Update(F.pict, smx-smy+py0-r, smy+smx-px0-r, width, width);
				Update(F.pict, smx+smy-py0-r, smy-smx+px0-r,  width, width);
				Update(F.pict, smx+smy-py0-r, smy+smx-px0-r,  width, width)
			END;
			Update(F.pict, 2*smx-px0-r, 2*smy-py0-r, width, width)
		END
	END;
	Update(F.pict, px0-r, py0-r, width, width);
	REPEAT
		IF (px1#px0) OR (py1#py0) THEN
			SetLine(F.pict, px0-r, py0-r, px1-r, py1-r, Rembrandt0.color.col);
			IF double THEN SetLine(F.pict, px0-r+cdx, py0-r+cdy, px1-r+cdx, py1-r+cdy, Rembrandt0.color.col) END;
		END;
		px0:=px1; py0:= py1;
		Input.Mouse(M.keys, px1, py1);
		Oberon.DrawCursor(Oberon.Mouse, Effects.Cross, px1, py1);
		Rembrandt.ScreentoPict(F, x, y, px1, py1, px1, py1);
		keysum := keysum + M.keys
	UNTIL M.keys = {};
	M.keys:= keysum
END HandlePoints;

PROCEDURE HandleLines(F: Rembrandt.Frame; VAR M: Oberon.InputMsg; x, y: INTEGER);
VAR keysum: SET; ox, oy, mx, my, px0, py0, px1, py1, x0, y0: INTEGER; Q: D3.Mask; r, zoom: INTEGER; first: BOOLEAN;
BEGIN
	Gadgets.MakeMask(F, x, y, M.dlink, Q);
	IF F.car THEN smx:= F.cx; smy:= F.cy END;
	keysum := M.keys; mx:= M.X; my:= M.Y; first:= TRUE;
	Rembrandt.SavePicture(F.pict, 0, 0, F.pict.width, F.pict.height);
	Rembrandt.GetZoom(F, zoom);
	x0:= mx; y0:= my; r:= width DIV 2;
	Oberon.FadeCursor(Oberon.Mouse);
	Rembrandt.DisplayLine(F, x, y, Q, Rembrandt0.color.col, x0, y0, x0, y0, zoom);
	REPEAT
		ox:=mx; oy:= my;
		Input.Mouse(M.keys, mx, my);
		IF (mx#ox) OR (my#oy) THEN
			Oberon.FadeCursor(Oberon.Mouse);
			Rembrandt.DisplayLine(F, x, y, Q, Rembrandt0.color.col, x0, y0, ox, oy, zoom);
			Rembrandt.DisplayLine(F, x, y, Q, Rembrandt0.color.col, x0, y0, mx, my, zoom);
		END;
		keysum := keysum + M.keys;
		IF keysum = {MR, MM} THEN
			Rembrandt.ScreentoPict(F, x, y, x0, y0, px0, py0);
			Rembrandt.ScreentoPict(F, x, y, mx, my, px1, py1);
			Oberon.FadeCursor(Oberon.Mouse);
			Rembrandt.DisplayLine(F, x, y, Q, Rembrandt0.color.col, x0, y0, mx, my, zoom);
			SetLine(F.pict, px0-r, py0-r, px1-r, py1-r, Rembrandt0.color.col);
			x0:= mx; y0:= my; first:= FALSE;
			EXCL(keysum, MR);
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Cross, mx, my);
	UNTIL M.keys = {};
	Oberon.FadeCursor(Oberon.Mouse);
	Rembrandt.DisplayLine(F, x, y, Q, Rembrandt0.color.col, x0, y0, mx, my, zoom);
	IF keysum = {MM} THEN
		(* Draw Line *)
		Rembrandt.ScreentoPict(F, x, y, x0, y0, px0, py0);
		Rembrandt.ScreentoPict(F, x, y, mx, my, px1, py1);
		SetLine(F.pict, px0-r, py0-r, px1-r, py1-r, Rembrandt0.color.col)
	ELSE
		IF ~first THEN Rembrandt.DisplayLine(F, x, y, Q, Rembrandt0.color.col, x0, y0, x0, y0, zoom) END;
	END
END HandleLines;

PROCEDURE HandleRectangles(F: Rembrandt.Frame; VAR M: Oberon.InputMsg; x, y: INTEGER);
VAR Q: D3.Mask; rx, ry, rw, rh, px, py: INTEGER;
BEGIN
	Gadgets.MakeMask(F, x, y, M.dlink, Q);
	IF F.car THEN smx:= F.cx; smy:= F.cy END;
	rx:= M.X; ry:= M.Y; rw:=0; rh:=0;
	Rembrandt.SizeRect(F, x, y, Q, M.keys, M.X, M.Y, rx, ry, rw, rh, FALSE);
	IF M.keys = {MM} THEN
		Rembrandt.ScreentoPict(F, x, y, rx, ry, px, py);
		Rembrandt.SavePicture(F.pict, px, py, rw, rh);
		SetRectangle(F.pict, px, py, rw, rh);
	END
END HandleRectangles;

PROCEDURE HandleFill(F: Rembrandt.Frame; VAR M: Oberon.InputMsg; x, y: INTEGER);
VAR keysum: SET; x0, y0: INTEGER;
BEGIN
	IF F.car THEN smx:= F.cx; smy:= F.cy END;
	keysum := M.keys; 
	REPEAT
		Oberon.DrawCursor(Oberon.Mouse, Effects.Cross, M.X, M.Y);
		Input.Mouse(M.keys, M.X, M.Y);
		keysum := keysum + M.keys
	UNTIL M.keys = {};
	IF (keysum= {MM}) & Rembrandt.InsidePict(F, M.X, M.Y, x, y) THEN
		Rembrandt.ScreentoPict(F, x, y, M.X, M.Y, x0, y0);
		Rembrandt.SavePicture(F.pict, 0, 0, F.pict.width, F.pict.height);
		IF symmetric#{} THEN
			IF Yachse IN symmetric THEN Fillarea(F,  2*smx-x0, y0) END;
			IF Xachse IN symmetric THEN Fillarea(F,  x0, 2*smy-y0) END;
			IF (Xachse IN symmetric) & (Yachse IN symmetric) THEN
				IF grad45 IN symmetric THEN
					Fillarea(F, smx-smy+y0, smy-smx+x0);
					Fillarea(F, smx-smy+y0, smy+smx-x0);
					Fillarea(F, smx+smy-y0, smy-smx+x0);
					Fillarea(F, smx+smy-y0, smy+smx-x0)
				END;
				Fillarea(F, 2*smx-x0,  2*smy-y0) END;
		END;
		Fillarea(F, x0, y0);
	END
END HandleFill;

PROCEDURE HandleSpray(F: Rembrandt.Frame; VAR M: Oberon.InputMsg; x, y: INTEGER);
VAR dx, dy, px, py, r, i, dw: INTEGER; 
BEGIN
	Rembrandt.ScreentoPict(F, x, y, M.X, M.Y, px, py);
	IF F.car THEN cdx:= F.cx-px; cdy:= F.cy-py; smx:= F.cx; smy:= F.cy END;
	IF width>1 THEN r:= width DIV 2; dw:= width ELSE r:= 1; dw:= 2 END;; 
	Rembrandt.SavePicture(F.pict, 0, 0, F.pict.width, F.pict.height);
	REPEAT
		i:=0;
		WHILE i< sprayspeed DO 
			REPEAT
				dx:= SHORT(ENTIER(Rembrandt0.Uniform()*dw)-r);
				dy:= SHORT(ENTIER(Rembrandt0.Uniform()*dw)-r);
			UNTIL Math.sqrt(dx*dx+dy*dy)<=r;
			Rembrandt.ScreentoPict(F, x, y, M.X, M.Y, px, py);
			Pictures.Dot(F.pict, Rembrandt0.color.col, px+dx, py+dy, Display.replace);
			IF double THEN Pictures.Dot(F.pict, Rembrandt0.color.col, px+dx+cdx, py+dy+cdy, Display.replace) END;
			IF symmetric#{} THEN
				IF Yachse IN symmetric THEN Pictures.Dot(F.pict, Rembrandt0.color.col, 2*smx-px-dx, py+dy, Display.replace) END;
				IF Xachse IN symmetric THEN Pictures.Dot(F.pict, Rembrandt0.color.col, px+dx, 2*smy-py-dy, Display.replace) END;
				IF (Xachse IN symmetric) & (Yachse IN symmetric) THEN
					IF grad45 IN symmetric THEN
						Pictures.Dot(F.pict, Rembrandt0.color.col, smx-smy+py+dy, smy-smx+px+dx, Display.replace);
						Pictures.Dot(F.pict, Rembrandt0.color.col, smx-smy+py+dy, smy+smx-px-dx, Display.replace);
						Pictures.Dot(F.pict, Rembrandt0.color.col, smx+smy-py-dy, smy-smx+px+dx, Display.replace);
						Pictures.Dot(F.pict, Rembrandt0.color.col, smx+smy-py-dy, smy+smx-px-dx, Display.replace)
					END;
					Pictures.Dot(F.pict, Rembrandt0.color.col, 2*smx-px-dx,  2*smy-py-dy, Display.replace) END;
			END;
			INC(i)
		END; 
		Pictures.Update(F.pict, px-r, py-r, dw, dw);
		IF double THEN Update(F.pict, px+dx+cdx, py+dy+cdy, dw, dw) END;
		IF symmetric#{} THEN
			IF Yachse IN symmetric THEN Pictures.Update(F.pict, 2*smx-px-r, py-r, dw, dw) END;
			IF Xachse IN symmetric THEN Pictures.Update(F.pict, px-r, 2*smy-py-r, dw, dw) END;
			IF (Xachse IN symmetric) & (Yachse IN symmetric) THEN
				IF grad45 IN symmetric THEN
					Pictures.Update(F.pict, smx-smy+py-r, smy-smx+px-r, dw, dw);
					Pictures.Update(F.pict, smx-smy+py-r, smy+smx-px-r, dw, dw);
					Pictures.Update(F.pict, smx+smy-py-r, smy-smx+px-r, dw, dw);
					Pictures.Update(F.pict, smx+smy-py-r, smy+smx-px-r, dw, dw)
				END;
				Pictures.Update(F.pict, 2*smx-px-r, 2*smy-py-r, dw, dw) END;
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Cross, M.X, M.Y);
		Input.Mouse(M.keys, M.X, M.Y);
	UNTIL M.keys # {MM};
	REPEAT
		Oberon.DrawCursor(Oberon.Mouse, Effects.Cross, M.X, M.Y);
		Input.Mouse(M.keys, M.X, M.Y);
	UNTIL M.keys = {};
END HandleSpray;

PROCEDURE HandleSmear(F: Rembrandt.Frame; VAR M: Oberon.InputMsg; x, y: INTEGER);
VAR keysum: SET; ox, oy, px, py: INTEGER;
BEGIN
	Rembrandt.SavePicture(F.pict, 0, 0, F.pict.width, F.pict.height);
	ox:=M.X; oy:=M.Y;
	REPEAT
		IF (M.X#ox) OR (M.Y#oy) THEN
			Rembrandt.ScreentoPict(F, x, y, M.X, M.Y, px, py);
			IF ABS(M.X-ox)> ABS(M.Y-oy) THEN
				IF M.X-ox <0 THEN SetSmear(F, px, py, left) ELSE SetSmear(F, px, py, right) END
			ELSE
				IF M.Y-oy <0 THEN SetSmear(F, px, py, down) ELSE SetSmear(F, px, py, up) END
			END
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Cross, M.X, M.Y); 
		ox:=M.X; oy:= M.Y;
		Input.Mouse(M.keys, M.X, M.Y);
		keysum := keysum + M.keys
	UNTIL M.keys = {};
	M.keys:= keysum
END HandleSmear;

PROCEDURE HandleClone(F: Rembrandt.Frame; VAR M: Oberon.InputMsg; x, y: INTEGER);
VAR keysum: SET; ox, oy, px, py, r: INTEGER; Q: D3.Mask;
BEGIN
	Gadgets.MakeMask(F, x, y, M.dlink, Q);
	Rembrandt.SavePicture(F.pict, 0, 0, F.pict.width, F.pict.height);
	Rembrandt.ScreentoPict(F, x, y, M.X, M.Y, px, py);
	r:= width DIV 2;
	IF F.car THEN cdx:= F.cx-px; cdy:= F.cy-py END;
	SetClone(F, px, py);
	Oberon.FadeCursor(Oberon.Mouse);
	D3.Circle(Q, D3.FG, Display.solid, M.X+cdx, M.Y+cdy, r, 1, {2}, Display.invert);
	D3.Circle(Q, D3.FG, Display.solid, M.X, M.Y, r, 1, {2}, Display.invert);
	ox:=M.X; oy:=M.Y;
	REPEAT
		IF (M.X#ox) OR (M.Y#oy) THEN
			Oberon.FadeCursor(Oberon.Mouse);
			D3.Circle(Q, D3.FG, Display.solid, ox+cdx, oy+cdy, r, 1, {2}, Display.invert);
			D3.Circle(Q, D3.FG, Display.solid, ox, oy, r, 1, {2}, Display.invert);
			Rembrandt.ScreentoPict(F, x, y, M.X, M.Y, px, py);
			IF (px>0) & (px<F.pict.width) & (py>0) & (py<F.pict.height) THEN SetClone(F, px, py) END; 
			D3.Circle(Q, D3.FG, Display.solid, M.X+cdx, M.Y+cdy, r, 1, {2}, Display.invert);
			D3.Circle(Q, D3.FG, Display.solid, M.X, M.Y, r, 1, {2}, Display.invert);
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Cross, M.X, M.Y); 
		ox:=M.X; oy:= M.Y;
		Input.Mouse(M.keys, M.X, M.Y);
		keysum := keysum + M.keys
	UNTIL M.keys = {};
	Oberon.FadeCursor(Oberon.Mouse);
	D3.Circle(Q, D3.FG, Display.solid, ox+cdx, oy+cdy, r, 1, {2}, Display.invert);
	D3.Circle(Q, D3.FG, Display.solid, ox, oy, r, 1, {2}, Display.invert);
	M.keys:= keysum
END HandleClone;

PROCEDURE HandleCircle(F: Rembrandt.Frame; VAR M: Oberon.InputMsg; x, y: INTEGER);
VAR keysum: SET; ox, oy, px, py, mx, my, r, or, d, zoom: INTEGER; Q: D3.Mask;
BEGIN
	Gadgets.MakeMask(F, x, y, M.dlink, Q);
	Rembrandt.GetZoom(F, zoom);
	mx:= M.X; my:= M.Y; r:=1;
	Oberon.FadeCursor(Oberon.Mouse);
	D3.Circle(Q, Rembrandt0.color.col, Display.solid, mx, my, zoom, 1, {2}, Display.invert);
	ox:=M.X; oy:=M.Y; or:=1; 
	keysum:= M.keys;
	REPEAT
		IF (M.X#ox) OR (M.Y#oy) THEN
			r:= Max(ABS(M.X-mx), ABS(M.Y-my)) DIV zoom;
			IF r#or THEN
				Oberon.FadeCursor(Oberon.Mouse);
				D3.Circle(Q, Rembrandt0.color.col, Display.solid, mx, my, or*zoom, 1, {2}, Display.invert);
				IF (width<or) & ~filled & (width>1) THEN D3.Circle(Q, Rembrandt0.color.col, Display.solid, mx, my, (or-width)*zoom, 1, {2}, Display.invert) END; 
				D3.Circle(Q, Rembrandt0.color.col, Display.solid, mx, my, r*zoom, 1, {2}, Display.invert);
				IF (width<r) & ~filled & (width>1) THEN D3.Circle(Q, Rembrandt0.color.col, Display.solid, mx, my, (r-width)*zoom, 1, {2}, Display.invert) END
			END
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Cross, M.X, M.Y); 
		ox:=M.X; oy:= M.Y; or:=r;
		Input.Mouse(M.keys, M.X, M.Y);
		keysum := keysum + M.keys
	UNTIL M.keys = {};
	Oberon.FadeCursor(Oberon.Mouse);
	D3.Circle(Q, Rembrandt0.color.col, Display.solid, mx, my, or*zoom, 1, {2}, Display.invert);
	IF (width<or) & ~filled & (width>1) THEN D3.Circle(Q, Rembrandt0.color.col, Display.solid, mx, my, (or-width)*zoom, 1, {2}, Display.invert) END;
	IF keysum= {MM} THEN
		Rembrandt.ScreentoPict(F, x, y, mx, my, px, py);
		ox:= px-or; oy:= py-or; mx:= 2*or+width; my:= mx;
		Rembrandt.SavePicture(F.pict, ox , oy, 2*or+1, 2*or+1);
		IF (or <width) & ~filled THEN
			FilledCircle(F.pict, ox, oy, or, Rembrandt0.color.col);
		ELSE
			d:= width DIV 2;
			IF filled THEN
				FilledCircle(F.pict, ox, oy, or, Rembrandt0.color.col);
			ELSE
				Circle(F.pict, px-d, py-d, or-d);
			END;
		END;
		IF ox<0 THEN mx:= mx+ox; ox:=0 END;
		IF oy<0 THEN my:= my+oy; oy:=0 END;
		Pictures.Update(F.pict, ox, oy, mx, my);
	END;
	M.keys:= keysum
END HandleCircle;

PROCEDURE HandleSpecialDel(F: Rembrandt.Frame; VAR M: Oberon.InputMsg; x, y: INTEGER);
VAR keysum: SET; ox, oy, px, py, r, zoom: INTEGER; Q: D3.Mask;
BEGIN
	Gadgets.MakeMask(F, x, y, M.dlink, Q);
	Rembrandt.GetZoom(F, zoom);
	Rembrandt.SavePicture(F.pict, 0, 0, F.pict.width, F.pict.height);
	Rembrandt.ScreentoPict(F, x, y, M.X, M.Y, px, py);
	r:= (width+1) DIV 2;
	Delete(F, px, py);
	Oberon.FadeCursor(Oberon.Mouse);
	D3.Circle(Q, D3.FG, Display.solid, M.X, M.Y, r*zoom, 1, {0}, Display.invert);
	ox:=M.X; oy:=M.Y;
	REPEAT
		IF (M.X#ox) OR (M.Y#oy) THEN
			D3.Circle(Q, D3.FG, Display.solid, ox, oy, r*zoom, 1, {0}, Display.invert);
			Rembrandt.ScreentoPict(F, x, y, M.X, M.Y, px, py);
			IF (px-r>0) & (px<F.pict.width-r) & (py>0) & (py<F.pict.height) THEN Delete(F, px, py) END;
			D3.Circle(Q, D3.FG, Display.solid, M.X, M.Y, r*zoom, 1, {0}, Display.invert);
		END;
		ox:=M.X; oy:= M.Y;
		Input.Mouse(M.keys, M.X, M.Y);
		keysum := keysum + M.keys
	UNTIL M.keys = {};
	D3.Circle(Q, D3.FG, Display.solid, ox, oy, r*zoom, 1, {0}, Display.invert);
	M.keys:= keysum
END HandleSpecialDel;

PROCEDURE HandleErease(F: Rembrandt.Frame; VAR M: Oberon.InputMsg; x, y: INTEGER);
VAR keysum: SET; px0, py0, px1, py1, r, zoom, omx, omy: INTEGER; Q: D3.Mask;
BEGIN
	Gadgets.MakeMask(F, x, y, M.dlink, Q);
	Rembrandt.GetZoom(F, zoom);
	Rembrandt.SavePicture(F.pict, 0, 0, F.pict.width, F.pict.height);
	r:= width DIV 2; 
	keysum := M.keys;
	Rembrandt.ScreentoPict(F, x, y, M.X, M.Y, px0, py0);
	px1:= px0; py1:= py0;
	IF F.car THEN cdx:= F.cx-px0; cdy:= F.cy-py0; smx:= F.cx; smy:= F.cy END;
	omx:= M.X; omy:= M.Y;
	SetPoint(F.pict, px0-r, py0-r, D3.BG);
	IF symmetric#{} THEN
		IF width=1 THEN r:=0 ELSE r:= (width+1) DIV 2 END;
		IF Yachse IN symmetric THEN Update(F.pict, 2*smx-px0-r, py0-r, width, width) END;
		IF Xachse IN symmetric THEN Update(F.pict, px0-r, 2*smy-py0-r, width, width) END;
		IF (Xachse IN symmetric) & (Yachse IN symmetric) THEN
			IF grad45 IN symmetric THEN
				Update(F.pict, smx-smy+py0-r, smy-smx+px0-r, width, width);
				Update(F.pict, smx-smy+py0-r, smy+smx-px0-r, width, width);
				Update(F.pict, smx+smy-py0-r, smy-smx+px0-r,  width, width);
				Update(F.pict, smx+smy-py0-r, smy+smx-px0-r,  width, width)
			END;
			Update(F.pict, 2*smx-px0-r, 2*smy-py0-r, width, width)
		END
	END;
	Update(F.pict, px0-r, py0-r, width, width);
	Oberon.FadeCursor(Oberon.Mouse);
	D3.Circle(Q, D3.FG, Display.solid, M.X, M.Y, r*zoom, 1, {0}, Display.invert);
	REPEAT
		IF (M.X#omx) OR (M.Y#omy) THEN
			D3.Circle(Q, D3.FG, Display.solid, omx, omy, r*zoom, 1, {0}, Display.invert);
			Rembrandt.ScreentoPict(F, x, y, M.X, M.Y, px1, py1);
			SetLine(F.pict, px0-r, py0-r, px1-r, py1-r, D3.BG);
			px0:=px1; py0:= py1;
			D3.Circle(Q, D3.FG, Display.solid, M.X, M.Y, r*zoom, 1, {0}, Display.invert);
		END;
		omx:= M.X; omy:= M.Y;
		Input.Mouse(M.keys, M.X, M.Y);  
		keysum := keysum + M.keys
	UNTIL M.keys = {};
	D3.Circle(Q, D3.FG, Display.solid, omx, omy, r*zoom, 1, {0}, Display.invert);
	M.keys:= keysum
END HandleErease;

PROCEDURE HandlePick(F: Rembrandt.Frame; VAR M: Oberon.InputMsg; x, y: INTEGER);
VAR keysum: SET; ox, oy, px, py: INTEGER; obj: Objects.Object; aM: Objects.AttrMsg;
BEGIN
	ox:=M.X; oy:=M.Y;
	Rembrandt.ScreentoPict(F, x, y, M.X, M.Y, px, py);
	Rembrandt0.color.col:= GetColor(F.pict, px, py);
	Gadgets.Update(Rembrandt0.color);
	REPEAT
		Oberon.DrawCursor(Oberon.Mouse, Effects.Cross, M.X, M.Y); 
		IF (M.X#ox) OR (M.Y#oy) THEN
			Rembrandt.ScreentoPict(F, x, y, M.X, M.Y, px, py);
			Rembrandt0.color.col:= GetColor(F.pict, px, py);
			Gadgets.Update(Rembrandt0.color)
		END;
		ox:=M.X; oy:= M.Y;
		Input.Mouse(M.keys, M.X, M.Y);
		keysum := keysum + M.keys
	UNTIL M.keys = {};
	M.keys:= keysum;
	Rembrandt.trackMM:= oldtrackMM;
	Rembrandt.cursor:= oldcursor;
	obj:= Gadgets.FindObj(oldobj, "drawingtool");
	IF obj#NIL THEN
		aM.id:= Objects.set; aM.name:= "Value"; aM.class:= Objects.Int; aM.i:= oldval; aM.res:=-1;
		obj.handle(obj, aM);  Gadgets.Update(obj); 
	END;
END HandlePick;

(** Spiegelt den selektierten Bereich an der Y-Achse *)
PROCEDURE FlipH*;
VAR x, px, py, pw, ph: INTEGER;
		 P, D: Pictures.Picture; F: Rembrandt.Frame;
BEGIN
	Rembrandt.GetSelectedPict(P, px, py, pw, ph);
	IF P=NIL THEN F:= RembrandtDocs.MarkedFrame(); IF F#NIL THEN P:= F.pict; px:=0; py:=0; pw:= P.width; ph:= P.height END END;
	IF P#NIL THEN
		NEW(D); Rembrandt0.AllocatePictureMem(D, pw, ph, P.depth);
		x:=0;
		WHILE x < pw DO
			Pictures.CopyBlock(P, D, x+px, py, 1, ph, pw-x-1, 0, Display.replace);
			INC(x)
		END;
		RembrandtDocs.OpenPict(D, "")
	END
END FlipH;

(** Spiegelt den selektierten Bereich an der X-Achse *)
PROCEDURE FlipV*;
VAR y, px, py, pw, ph: INTEGER;
		 P, D: Pictures.Picture; F: Rembrandt.Frame;
BEGIN
	Rembrandt.GetSelectedPict(P, px, py, pw, ph);
	IF P=NIL THEN F:= RembrandtDocs.MarkedFrame(); IF F#NIL THEN P:= F.pict; px:=0; py:=0; pw:= P.width; ph:= P.height END END;
	IF P#NIL THEN
		NEW(D); Rembrandt0.AllocatePictureMem(D, pw, ph, P.depth);
		y:=0;
		WHILE y< ph DO
			Pictures.CopyBlock(P, D, px, y+py, pw, 1, 0, ph-y-1, Display.replace);
			INC(y)
		END;
		RembrandtDocs.OpenPict(D, "")
	END
END FlipV;

(** Generiert aus dem selektierten Bereich ein Picture der Grösse eines Icons *)
PROCEDURE MakeIcon*;
VAR P, S, D: Pictures.Picture; px, py, pw, ph, iconw, iconh, bw, bh, bwr, bhr, i, j, k, l, col, r, g, b, weight: INTEGER;
		T: Texts.Scanner;  F: Rembrandt.Frame;
		wr, wg, wb: REAL; maxw, maxh, incbwr, incbhr: INTEGER;
BEGIN
	Texts.OpenScanner(T, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(T);
	IF T.class = Texts.Int THEN iconw:= SHORT(T.i) ELSE iconw:=32 END;
	Texts.Scan(T);
	IF T.class = Texts.Int THEN iconh:= SHORT(T.i) ELSE iconh:= 32 END;
	Rembrandt.GetSelectedPict(P, px, py, pw, ph);
	IF P=NIL THEN F:= RembrandtDocs.MarkedFrame(); IF F#NIL THEN P:= F.pict; px:=0; py:=0; pw:= P.width; ph:= P.height END END;
	bw:= pw DIV iconw; bh:= ph DIV iconh; col:=16;
	bwr:= pw MOD iconw; bhr:= ph MOD iconh;
	IF (P#NIL) & (pw>iconw) & (ph>iconh) THEN
		NEW(S); Pictures.Create(S, iconw, iconh, P.depth); 
		FOR i:=0 TO 15 DO
			Display.GetColor(i, Rembrandt0.coltable[i].r, Rembrandt0.coltable[i].g, Rembrandt0.coltable[i].b)
		END;
		FOR i:=16 TO Rembrandt0.maxnoc-1 DO Rembrandt0.coltable[i].r:=0; Rembrandt0.coltable[i].g:=0;Rembrandt0 .coltable[i].b:=0 END;
		IF bhr=0 THEN incbhr:=0 ELSE incbhr:=-1 END;	
		FOR i:= 0 TO iconh-1 DO
			IF i<bhr THEN maxh:= bh; INC(incbhr) ELSE maxh:= bh-1 END;
			IF bwr=0 THEN incbwr:=0 ELSE incbwr:=-1 END;	
			FOR j:= 0 TO iconw-1 DO
				wr:= 0; wg:= 0; wb:=0;
				IF j<bwr THEN maxw:= bw; INC(incbwr) ELSE maxw:=bw-1 END;	
				weight:= (maxw+1)*(maxh+1);
				FOR k:= 0 TO maxh DO
					FOR l:= 0 TO maxw DO
						Pictures.GetColor(P, Pictures.Get(P, px+j*bw+l+incbwr, py+i*bh+k+incbhr), r, g, b);
						wr:= wr+r/weight; wg:= wg+g/weight; wb:= wb+b/weight;
					END
				END;
				r:= SHORT(ENTIER(wr)); g:= SHORT(ENTIER(wg)); b:=SHORT(ENTIER(wb));
				k:=0; 
				WHILE (k<col) & ~((Rembrandt0.coltable[k].r=r) & (Rembrandt0.coltable[k].g=g) & (Rembrandt0.coltable[k].b=b)) DO INC(k) END;
				IF k=col THEN
					IF col<ASH(1, P.depth) THEN
						Pictures.SetColor(S, col, r, g, b); 
						Pictures.Dot(S, col, j, i, Display.replace);
						Rembrandt0.coltable[col].r:= r; Rembrandt0.coltable[col].g:= g; Rembrandt0.coltable[col].b:= b; 
						INC(col)
					ELSE
						k:= Rembrandt0.NearestColor(r, g, b);
						Pictures.Dot(S, k, j, i, Display.replace);
					END;
				ELSE
					Pictures.Dot(S, k, j, i, Display.replace);
				END;
			END
		END;
		NEW(D); Pictures.Create(D, S.width, S.height, S.depth);
		Rembrandt0.Floyd(S, D);  	 
		RembrandtDocs.OpenPict(D, "") 
	END				
END MakeIcon;

(** Dithert ein markiertes Picture mit den Parameter Helligkeit und Sättigung *)
PROCEDURE Reduce*;
VAR D: Pictures.Picture;
		ds, dv, r, g, b: INTEGER;
		S: Texts.Scanner; 
		F: Rembrandt.Frame;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Int THEN ds:= SHORT(S.i) ELSE ds:=100 END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN dv:= SHORT(S.i) ELSE dv:=100 END;
	F:= RembrandtDocs.MarkedFrame();
	IF F#NIL THEN
		NEW(D); Pictures.Create(D, F.pict.width, F.pict.height, F.pict.depth); 
		Rembrandt0.Reduce(F.pict, D, ds/100, dv/100); 
		ds:=0; WHILE ds<ASH(2, D.depth-1) DO Display.GetColor(ds, r, g, b); Pictures.SetColor(D, ds, r, g, b); INC(ds) END;
		RembrandtDocs.OpenPict(D, "") 
	END
END Reduce;

PROCEDURE Oldval;
VAR obj: Objects.Object; M: Objects.AttrMsg;
BEGIN
	obj:= Gadgets.FindObj(Gadgets.context, "drawingtool");
	IF obj#NIL THEN
		M.id:= Objects.get; M.name:= "Value"; M.class:= Objects.Int; M.res:=-1;
		obj.handle(obj, M);
		oldval:= SHORT(M.i);
	END
END Oldval;

(** Weist dem Handler für die mittlere Maustaste eine neue Prozedur zu *)
PROCEDURE Assign*(proc: Rembrandt.TrackMMProc; cursor: Oberon.Marker);
BEGIN
	Rembrandt.trackMM:= proc;
	Rembrandt.cursor:= cursor;
	Oldval
END Assign;

(** Operationen dem Handler für die mittlere Maustaste zuordnen; sind selbstsprechend *)
PROCEDURE Points*;
BEGIN
	Assign(HandlePoints, Effects.Cross)
END Points;

PROCEDURE Lines*;
BEGIN
	Assign(HandleLines, Effects.Cross)
END Lines;

PROCEDURE Rectangles*;
BEGIN
	Assign(HandleRectangles, Effects.Cross)
END Rectangles;

PROCEDURE Fill*;
BEGIN
	Assign(HandleFill, Effects.Cross)
END Fill;

PROCEDURE Spray*;
BEGIN
	Assign(HandleSpray, Effects.Cross)
END Spray;

PROCEDURE Smear*;
BEGIN
	Assign(HandleSmear, Effects.Cross)
END Smear;

PROCEDURE Clone*;
BEGIN
	Assign(HandleClone, Effects.Cross)
END Clone;

PROCEDURE Circles*;
BEGIN
	Assign(HandleCircle, Effects.Cross)
END Circles;

PROCEDURE Rotate*;
BEGIN
	Rembrandt.trackSelMM.track:= HandleRotate;
	Rembrandt.trackSelMM.id:= Rembrandt.idRotate;
	Rembrandt.cursor:= Effects.Cross;
END Rotate;

PROCEDURE Scale*;
BEGIN
	Rembrandt.trackSelMM.track:= HandleScale;
	Rembrandt.trackSelMM.id:= Rembrandt.idScale;
	Rembrandt.cursor:= Effects.Cross;
END Scale;

PROCEDURE SpecialDel*;
BEGIN
	Assign(HandleSpecialDel, Effects.Cross)
END SpecialDel;

PROCEDURE Erease*;
BEGIN
	Assign(HandleErease, Effects.Cross)
END Erease;

PROCEDURE PickColor*;
BEGIN
	oldtrackMM:= Rembrandt.trackMM;
	oldcursor:= Rembrandt.cursor;
	oldobj:= Gadgets.context;
	Rembrandt.trackMM:= HandlePick;
	Rembrandt.cursor:= Effects.Cross;
END PickColor;

(** Symmetriechsen einstellen *)
PROCEDURE SetSymmXaxis*;
VAR obj: Objects.Object;  M: Objects.AttrMsg;
BEGIN
    obj := Gadgets.FindObj(Gadgets.context, "xaxis");
	IF obj#NIL THEN	(* Wert lesen *)
		M.id:= Objects.get; M.name:= "Value"; M.class:= Objects.Bool; M.res:=-1;
		obj.handle(obj, M); 
		IF ~M.b THEN
			EXCL(symmetric, Xachse); EXCL(symmetric, grad45);
			obj := Gadgets.FindObj(Gadgets.context, "deg45");
			IF obj#NIL THEN
				M.id:= Objects.set; M.name:= "Value"; M.class:= Objects.Bool; M.res:=-1; M.b:= FALSE;
				obj.handle(obj, M); Gadgets.Update(obj)
			END
		ELSE
			INCL(symmetric, Xachse); double:= FALSE;
			obj := Gadgets.FindObj(Gadgets.context, "double");
			IF obj#NIL THEN
				M.id:= Objects.set; M.name:= "Value"; M.class:= Objects.Bool; M.res:=-1; M.b:= FALSE;
				obj.handle(obj, M); Gadgets.Update(obj);
			END
		END;
	END;
END SetSymmXaxis;

PROCEDURE SetSymmYaxis*;
VAR obj: Objects.Object;  M: Objects.AttrMsg;
BEGIN
    obj := Gadgets.FindObj(Gadgets.context, "yaxis");
	IF obj#NIL THEN	(* Wert lesen *)
		M.id:= Objects.get; M.name:= "Value"; M.class:= Objects.Bool; M.res:=-1;
		obj.handle(obj, M);
		IF ~M.b THEN
			EXCL(symmetric, Yachse); EXCL(symmetric, grad45);
			obj := Gadgets.FindObj(Gadgets.context, "deg45");
			IF obj#NIL THEN
				M.id:= Objects.set; M.name:= "Value"; M.class:= Objects.Bool; M.res:=-1; M.b:= FALSE;
				obj.handle(obj, M); Gadgets.Update(obj)
			END
		ELSE
			INCL(symmetric, Yachse); double:= FALSE;
			obj := Gadgets.FindObj(Gadgets.context, "double");
			IF obj#NIL THEN
				M.id:= Objects.set; M.name:= "Value"; M.class:= Objects.Bool; M.res:=-1; M.b:= FALSE;
				obj.handle(obj, M); Gadgets.Update(obj)
			END
		END;	
	END;
END SetSymmYaxis;

PROCEDURE SetSymmDeg45*;
VAR obj: Objects.Object;  M: Objects.AttrMsg;
BEGIN
    obj:= Gadgets.FindObj(Gadgets.context, "deg45");
	IF obj#NIL THEN	(* Wert lesen *)
		M.id:= Objects.get; M.name:= "Value"; M.class:= Objects.Bool; M.res:=-1;
		obj.handle(obj, M); 
		IF ~M.b THEN
			EXCL(symmetric, grad45)
		ELSE
			 INCL(symmetric, grad45); INCL(symmetric, Yachse); INCL(symmetric, Xachse);
			obj:= Gadgets.FindObj(Gadgets.context, "xaxis");
			IF obj#NIL THEN
				M.id:= Objects.set; M.name:= "Value"; M.class:= Objects.Bool; M.b:= TRUE; M.res:=-1;
				obj.handle(obj, M); Gadgets.Update(obj)
			END;
			obj:= Gadgets.FindObj(Gadgets.context, "yaxis");
			IF obj#NIL THEN
				M.id:= Objects.set; M.name:= "Value"; M.class:= Objects.Bool; M.b:= TRUE; M.res:=-1;
				obj.handle(obj, M); Gadgets.Update(obj)
			END;
			double:= FALSE;
			obj := Gadgets.FindObj(Gadgets.context, "double");
			IF obj#NIL THEN
				M.id:= Objects.set; M.name:= "Value"; M.class:= Objects.Bool; M.res:=-1; M.b:= FALSE;
				obj.handle(obj, M); Gadgets.Update(obj)
			END
		END;
	END;
END SetSymmDeg45;

(** Attribut Filled einstellen *)
PROCEDURE SetFilled*;
VAR obj: Objects.Object; M: Objects.AttrMsg;
BEGIN
    obj:= Gadgets.FindObj(Gadgets.context, "filled");
	IF obj#NIL THEN	(* Wert lesen *)
		M.id:= Objects.get; M.name:= "Value"; M.class:= Objects.Bool; M.res:=-1;
		obj.handle(obj, M);
		IF M.b THEN
			filled:= TRUE
		ELSE
			filled:= FALSE
		END
	ELSE
		IF filled THEN filled:= FALSE ELSE filled:= TRUE END
	END
END SetFilled;

PROCEDURE GetFilled*(): BOOLEAN;
BEGIN
	RETURN filled
END GetFilled;

PROCEDURE Filled*(set: BOOLEAN);
VAR obj: Objects.Object; M: Objects.AttrMsg;
BEGIN
    obj:= Gadgets.FindObj(Gadgets.context, "filled");
	IF obj#NIL THEN	
		M.id:= Objects.set; M.name:= "Value"; M.class:= Objects.Bool; M.b:= set; M.res:=-1;
		obj.handle(obj, M);
	END;
	filled:= set
END Filled;

(** Attribut Width einstellen *)
PROCEDURE SetWidth*;
VAR S: Texts.Scanner; 
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF (S.class = Texts.Int) & (S.i>0) THEN
		width:= SHORT(S.i);
	END
END SetWidth;

PROCEDURE GetWidth*(): INTEGER;
BEGIN
	RETURN width
END GetWidth;

PROCEDURE Width*(w: INTEGER);
VAR obj: Objects.Object; M: Objects.AttrMsg;
BEGIN
	width:= ABS(w);
	obj:= Gadgets.FindObj(Gadgets.context, "width");
	IF obj#NIL THEN
		M.id:= Objects.set; M.name:= "Value"; M.class:= Objects.Int; M.i:= w; M.res:=-1;
		obj.handle(obj, M);
	END;
END Width;

(** Attribut Double einstellen *)
PROCEDURE SetDouble*;
VAR obj: Objects.Object; M: Objects.AttrMsg;
BEGIN
    obj:= Gadgets.FindObj(Gadgets.context, "double");
	IF obj#NIL THEN	(* Wert lesen *)
		M.id:= Objects.get; M.name:= "Value"; M.class:= Objects.Bool; M.res:=-1;
		obj.handle(obj, M);
		IF M.b THEN
			double:= TRUE;
			symmetric:= {};
			obj:= Gadgets.FindObj(Gadgets.context, "xaxis");
			IF obj#NIL THEN
				M.id:= Objects.set; M.name:= "Value"; M.class:= Objects.Bool; M.b:= FALSE; M.res:=-1;
				obj.handle(obj, M); Gadgets.Update(obj)
			END;
			obj:= Gadgets.FindObj(Gadgets.context, "yaxis");
			IF obj#NIL THEN
				M.id:= Objects.set; M.name:= "Value"; M.class:= Objects.Bool; M.b:= FALSE; M.res:=-1;
				obj.handle(obj, M); Gadgets.Update(obj)
			END;
			obj:= Gadgets.FindObj(Gadgets.context, "deg45");
			IF obj#NIL THEN
				M.id:= Objects.set; M.name:= "Value"; M.class:= Objects.Bool; M.b:= FALSE; M.res:=-1;
				obj.handle(obj, M); Gadgets.Update(obj)
			END
		ELSE
			double:= FALSE
		END;
	END
END SetDouble;

(** Sprayspeed einstellen *)
PROCEDURE SetSpraySpeed*;
VAR S: Texts.Scanner;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF (S.class = Texts.Int) THEN sprayspeed:= SHORT(S.i) END
END SetSpraySpeed;

(** Smearspeed einstellen *)
PROCEDURE SetSmearSpeed*;
VAR S: Texts.Scanner;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF (S.class = Texts.Int) THEN smearspeed:= SHORT(S.i) END
END SetSmearSpeed;

(** Picturepalette des markierten Pictures laden *)
PROCEDURE LoadColors*;
VAR i, r, g, b: INTEGER; F: Rembrandt.Frame;
BEGIN
	F:= RembrandtDocs.MarkedFrame();
	IF F#NIL THEN
		i:=0;
		WHILE i< ASH(1, F.pict.depth) DO
			Pictures.GetColor(F.pict, i, r, g, b);
			Display.SetColor(i, r, g, b);
			INC(i)
		END
	END
END LoadColors;

(** Bildschirmpalette in markiertes Picture speichern *)
PROCEDURE StoreColors*;
VAR i, r, g, b: INTEGER; F: Rembrandt.Frame;
BEGIN
	F:= RembrandtDocs.MarkedFrame();
	IF F#NIL THEN
		i:=0;
		WHILE i< ASH(1, F.pict.depth) DO
			Display.GetColor(i, r, g, b);
			Pictures.SetColor(F.pict, i, r, g, b);
			INC(i)
		END
	END
END StoreColors;


BEGIN
	width:= 1; filled:= FALSE; Rembrandt0.InitSeed(Oberon.Time());
	FOR cdx:= 0 TO 90 DO
		sintable[cdx]:= Math.sin(2*Math.pi*cdx/360); 
	END;
	sprayspeed:= 1; symmetric:= {}; smearspeed:= 1;
	cdx:= 20; cdy:= 20;
END RembrandtTools.


