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

MODULE HSV;	(** portable *)

IMPORT  Oberon, Viewers, MenuViewers, Input, TextFrames, Objects, Fonts, Display;
CONST ML = 2; Border = 5;
TYPE 
	Frame* = POINTER TO FrameDesc;
	RestoreProc* = PROCEDURE(F : Frame; X, Y, W, H : INTEGER);
	FrameDesc* = RECORD
		(Display.FrameDesc)
		l*, t* : INTEGER;
		restore* : RestoreProc;
		x, y, w, h, cx, cw : INTEGER;
		color : INTEGER; 
	END;

VAR hsv : ARRAY 16 OF RECORD h, s, v : INTEGER END;

(* ------------------------ Frame ------------------------------------------------ *)		
PROCEDURE max (i, j: INTEGER): INTEGER; BEGIN IF i >= j THEN RETURN i ELSE RETURN j END END max;
PROCEDURE min (i, j: LONGINT): INTEGER; BEGIN  IF i >= j THEN RETURN SHORT(j) ELSE RETURN SHORT(i) END END min;
	
PROCEDURE Pos*(F : Frame; DX,DY: INTEGER; VAR X, Y : INTEGER);
	(* Yp = (Yf - F.Y) - (F.H - F.t); *)
BEGIN
	X := DX - F.X  + F.l; Y :=  DY  - F.Y- F.H  + F.t;
END Pos;

PROCEDURE Loc*(F : Frame; X,Y: INTEGER; VAR DX,DY : INTEGER);
	(* Yp = (Yf - F.Y) - (F.H - F.t); *)
BEGIN
	DX := X +F.X - F.l; DY := Y + F.Y + F.H - F.t;
END Loc;

PROCEDURE Clip*(CX, CY, CW, CH : INTEGER; VAR X, Y, W, H : INTEGER);
	VAR R,T : INTEGER;
BEGIN
	R := X + W; T := Y + H;
	X := max(CX,X); Y := max(CY,Y); W := min(CX+CW,R) - X; H := min(CY+CH,T) - Y;
END Clip;

PROCEDURE ClipFrame*(F : Frame;  X, Y : INTEGER;  VAR W, H, DX, DY : INTEGER);
	VAR R, T, dX, dY : INTEGER;
BEGIN
	Loc(F,0,0,dX,dY);
	DX := max(X + dX,F.X); DY := max(Y + dY,F.Y);
	R := min(X + W + dX,F.X + F.W); T := min(Y + H +dY, F.Y + F.H);
	W := R - DX; H := T - DY;
	W := max(0,W); H := max(0,H);
END ClipFrame;

PROCEDURE ReplConst* (F : Frame; col, X, Y, W, H, mode: INTEGER);
	VAR DX,DY, DW, DH : INTEGER;
BEGIN
	DW := W; DH := H;
	ClipFrame(F,X, Y, DW, DH, DX,DY);
	Display.ReplConst(col, DX, DY, DW, DH, mode);
END ReplConst;

PROCEDURE ReplPattern* (F : Frame; col: INTEGER; pat: LONGINT; X, Y, W, H, mode: INTEGER);
	VAR DX,DY,DW,DH : INTEGER;
BEGIN
	DW := W; DH := H;
	ClipFrame(F,X, Y, DW, DH, DX,DY);
	Display.ReplPattern(col,pat, DX, DY, W, H, mode);
END ReplPattern;

(*
PROCEDURE CopyPattern*(F : Frame; col: INTEGER; pat: LONGINT; X, Y, mode: INTEGER);
	VAR DX,DY,W,H : INTEGER;  w, h: SHORTINT;
BEGIN
	SYSTEM.GET(pat, w);  W := w;
	SYSTEM.GET(pat+1, h);  H := h;
	ClipFrame(F,X, Y, W, H, DX,DY);
	IF (W = w) & (H = h) THEN Display.CopyPattern(col,pat,DX,DY, mode) END;
END CopyPattern;
*)

PROCEDURE Rectangle(F : Frame; DX,DY,W,H : INTEGER);
BEGIN
	ReplConst(F,Display.FG,DX,DY,W,1,Display.replace); (* bottom *)
	ReplConst(F,Display.FG,DX+W,DY,1,H,Display.replace); (* right *)
	IF H > 0 THEN ReplConst(F,Display.FG,DX+1,DY+H, W,1,Display.replace);END;(* top *)
	IF W > 0 THEN ReplConst(F,Display.FG,DX,DY+1,1,H,Display.replace); END(* left *)
END Rectangle;

PROCEDURE Dot* (F :Frame; col, X, Y, mode: INTEGER);
	VAR DX,DY : INTEGER;
BEGIN
	Loc(F,X,Y,DX,DY);
	IF (DX >= F.X) & (DX < F.X+F.W) & (DY >= F.Y) & (DY < F.Y + F.H) THEN
		Display.ReplConst(col,DX,DY,1,1,mode);
	END;
END Dot;

PROCEDURE Neutralize* (F: Frame);
BEGIN
	Oberon.RemoveMarks(F.X, F.Y, F.W, F.H);
END Neutralize;

PROCEDURE RestoreFrame*(F : Frame);
	VAR X,Y : INTEGER;
BEGIN
	Oberon.FadeCursor(Oberon.Mouse);	
	Display.ReplConst(Display.BG,F.X,F.Y,F.W,F.H,Display.replace);
	Pos(F,F.X,F.Y,X,Y);
	IF F.restore # NIL THEN F.restore(F,X,Y,F.W,F.H ) END;
END RestoreFrame;

PROCEDURE Modify* (F: Frame; id, dY, Y, H: INTEGER);
	VAR dH,X : INTEGER;
BEGIN
	dH := H - F.H;
	IF F.H = 0 THEN
		F.Y := Y; F.H := H; 
		RestoreFrame(F);
	ELSE
		F.Y := Y; F.H := H; 
		IF id = Display.extend THEN
			IF dY # 0 THEN
				Display.CopyBlock(F.X,Y,F.W,H-dY,F.X,Y+dY, Display.replace);
				Display.ReplConst(Display.BG,F.X,Y,F.W,dY,Display.replace);
			END;
			Pos(F,F.X,F.Y,X,Y); 
			Display.ReplConst(Display.BG,F.X,F.Y,F.W,dH,Display.replace); 
			(* IF F.restore # NIL THEN F.restore(F,X,Y,F.W,dH) END; *)
		ELSIF id = Display.reduce THEN
			IF H # 0 THEN 
				IF dY # 0 THEN
					(* Display.CopyBlock(F.X,Y+dY,F.W,H,F.X,Y, Display.replace); *)
				END
			END
		END;
		
		RestoreFrame(F);
	END;
END Modify;

PROCEDURE Copy*(F : Frame; VAR F1 : Frame);
BEGIN
	NEW(F1); F1^ := F^; F1.H := 0; 
END Copy;

PROCEDURE TrackMouse*(VAR keys : SET; VAR X,Y : INTEGER);
BEGIN
	REPEAT Input.Mouse(keys, X, Y); Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, X, Y); UNTIL keys = {};
END TrackMouse;

PROCEDURE RGBtoHSV(R, G, B: REAL; VAR H, S, V: REAL);
CONST undef = 361;

VAR maxVal, minVal, diff, Rdist, Gdist, Bdist: REAL;

	PROCEDURE maxOf(R, G, B: REAL): REAL;
	VAR
		max: REAL;
	BEGIN
		IF R > G THEN max := R ELSE max := G END;
		IF B > max THEN RETURN B ELSE RETURN max END;
	END maxOf;

	PROCEDURE minOf(R, G, B: REAL): REAL;
	VAR
		min: REAL;
	BEGIN
		IF R < G THEN min := R ELSE min := G END;
		IF B < min THEN RETURN B ELSE RETURN min END
	END minOf;

BEGIN
	maxVal := maxOf(R, G, B);
	minVal := minOf(R, G, B);
	diff := maxVal - minVal;
	V := maxVal;
	IF maxVal # 0 THEN S := diff/maxVal ELSE S := 0 END;
	IF  S = 0 THEN H := undef
	ELSE
		Rdist := (maxVal - R)/diff;
		Gdist := (maxVal - G)/diff;
		Bdist := (maxVal - B)/diff;
		IF R = maxVal THEN H := Bdist - Gdist
		ELSIF G = maxVal THEN H := 2 + Rdist - Bdist
		ELSIF B = maxVal THEN H := 4 + Gdist - Rdist
		END;
		H := H*60;
		IF H < 0 THEN H := H + 360 END
	END
END RGBtoHSV;

PROCEDURE HSVtoRGB(H, S, V: REAL; VAR R, G, B: REAL);
VAR
	f, p, q, t: REAL;
	i: LONGINT;
BEGIN
	IF S = 0 THEN R := V; G := V; B := V
	ELSE
		IF H = 360 THEN H := 0 END;
		H := H/60;
		i := ENTIER(H);
		f := H - i;
		p := V*(1 - S);
		q := V*(1 - (S*f));
		t := V*(1 - S*(1-f));
		CASE i OF
			0: R := V; G := t; B := p
		| 1: R := q; G := V; B := p
		| 2: R := p; G := V; B := t
		| 3: R := p; G := q; B := V
		| 4: R := t; G := p; B := V
		| 5: R := V; G := p; B := q
		END
	END
END HSVtoRGB;

PROCEDURE Bar(F : Frame; c, n, h : INTEGER; pat : BOOLEAN);
BEGIN
	IF pat THEN
		ReplPattern(F,c,Display.grey1,F.x + n*F.cw,F.y,F.cw-2,h,Display.replace);
	ELSE
		ReplConst(F,c,F.x + n*F.cw,F.y,F.cw-2,h,Display.replace); 
	END;
	ReplConst(F,0,F.x + n*F.cw-1,F.y+h,F.cw,F.h-h,Display.replace);
END Bar;

PROCEDURE ShowColor(F : Frame);
	VAR r,g,b : INTEGER;
BEGIN	
	Display.GetColor(F.color,r,g,b);
	Bar(F,1,0, SHORT(LONG(F.h) * r DIV 255),FALSE); 
	Bar(F,2,1, SHORT(LONG(F.h) * g DIV 255),FALSE); 
	Bar(F,3,2, SHORT(LONG(F.h) * b DIV 255), FALSE);
END ShowColor;

PROCEDURE ShowHSV(F : Frame);
	VAR help: INTEGER;
BEGIN	
	IF hsv[F.color].h <= 64 THEN 
		help := hsv[F.color].h; Bar(F,15,3, SHORT(LONG(F.h) * help DIV 64),TRUE); 
		help := hsv[F.color].s; Bar(F,15,4, SHORT(LONG(F.h) * help DIV 64),TRUE); 
		help := hsv[F.color].v; Bar(F,15,5, SHORT(LONG(F.h) * help DIV 64),TRUE); 
	END
END ShowHSV;

PROCEDURE IntToString*(i : LONGINT; VAR alpha : ARRAY OF CHAR);
VAR d,p : INTEGER;	tmp : ARRAY 15 OF CHAR; neg:BOOLEAN;
BEGIN
	IF i = 0 THEN COPY("0 ",alpha); RETURN; END;
	p := 0; d := 0;
	IF i < 0 THEN i := -i; neg := TRUE; ELSE neg := FALSE; END;
	WHILE i > 0 DO tmp[p] := CHR(i MOD 10 + 30H);  i := i DIV 10; INC(p); END;
	DEC(p);
	IF neg THEN alpha[d] := "-"; INC(d); END;
	WHILE p >= 0 DO alpha[d] := tmp[p]; INC(d); DEC(p); END;
	alpha[d] := 0X;
END IntToString;

PROCEDURE String(VAR x : INTEGER; y : INTEGER; s : ARRAY OF CHAR);
	VAR dx,u,v,i: INTEGER; font : Objects.Library;
	ob1: Objects.Object;
BEGIN	
	font := Objects.ThisLibrary("Oberon10.Scn.Fnt");
	i := 0;
	WHILE s[i] # 0X DO
		IF  (s[i] >= " ")  OR (s[i] = 09X)  THEN
			font.GetObj(font,ORD(s[i]),ob1);
			WITH ob1: Fonts.Char DO
				dx := ob1.dx; u := ob1.x; v := ob1.y;
			(* Display.GetChar(font.raster,s[i],dx,u,v,w,h,pat); *)
				Display.CopyPattern(Display.FG,ob1.pat,x + u, y + v, Display.paint);
			END;
		END;
		x := x + dx; INC(i);
	END
END String;

PROCEDURE ShowValues(F : Frame);
	VAR   X,Y,r,g,b : INTEGER; s : ARRAY 10 OF CHAR;
BEGIN	
	IF F.H > 20 THEN
		Display.GetColor(F.color,r,g,b);Y :=  F.Y+Border+2;
		X := F.X + Border; IntToString(r DIV 16,s); String(X,Y,s);
		X := F.X + Border + F.cw; IntToString(g DIV 16,s); String(X,Y,s);
		X := F.X + Border+ F.cw*2; IntToString(b DIV 16,s); String(X,Y,s);
		Display.ReplConst(F.color,F.X+1,F.Y+F.H+1,20,13,Display.replace);
		IntToString(F.color,s); X := F.X+2; String(X,F.Y+F.H+3,s);
	END
END ShowValues;

PROCEDURE SetHSV(col : INTEGER);
	VAR H,S,v : REAL; c : ARRAY 3 OF INTEGER; 
BEGIN
	Display.GetColor(col,c[0],c[1],c[2]);	
	RGBtoHSV(c[0] / 255,c[1] / 255,c[2] / 255, H,S, v);
	hsv[col].h := SHORT(ENTIER(H * 8 / 45)); 
	hsv[col].s := SHORT(ENTIER(S * 63)); 
	hsv[col].v := SHORT(ENTIER(v * 63));
END SetHSV;

PROCEDURE EditPalette(F : Frame; col : INTEGER);
	VAR keys : SET; X, Y, x, y, V, V0, grain : INTEGER;c : ARRAY 3 OF INTEGER;  R, G, B: REAL;
BEGIN
	IF col < 3 THEN grain := 16 ELSE grain := 64 END;
	V := -1; 
	Display.GetColor(F.color,c[0],c[1],c[2]);
	c[0] := c[0] DIV 16; c[1] := c[1] DIV 16; c[2] := c[2] DIV 16;
	REPEAT
		REPEAT 
			Input.Mouse(keys, X, Y); Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, X, Y); 
			Pos(F,X,Y,x,y); V0 := SHORT(LONG( y -F.y) * grain DIV F.h);
			V0 := min(V0,grain-1); V0 := max(V0,0);
		UNTIL (keys = {}) OR (V # V0); V := V0;
		Oberon.FadeCursor(Oberon.Mouse);
		IF col < 3 THEN	
			c[col] := V;
			Display.SetColor(F.color,c[0]*17,c[1]*17,c[2]*17);	
			SetHSV(F.color);
			ShowColor(F);ShowHSV(F); 
		ELSE
			IF col = 3 THEN hsv[F.color].h := V
			ELSIF col = 4 THEN hsv[F.color].s := V
			ELSIF col = 5 THEN hsv[F.color].v := V END;
			HSVtoRGB(hsv[F.color].h * 45 DIV 8,hsv[F.color].s / 64, hsv[F.color].v / 64,R,G,B);
			Display.SetColor(F.color,SHORT(ENTIER(256*R)),SHORT(ENTIER(256*G)),SHORT(ENTIER(256*B)));
			ShowColor(F); ShowHSV(F);
		END;
		ShowValues(F);
	UNTIL keys = {}
END EditPalette;

PROCEDURE Handle*(F: Objects.Object; VAR msg: Objects.ObjMsg);
	VAR F1 : Frame; X, Y, col, r, g, b : INTEGER;
BEGIN
	WITH F : Frame DO
		IF msg IS Oberon.ControlMsg THEN
			WITH msg : Oberon.ControlMsg DO
				IF msg.id = Oberon.defocus THEN (* Defocus(F) *)
				ELSIF msg.id = Oberon.neutralize THEN Neutralize(F);
				ELSIF msg.id = Oberon.mark THEN Oberon.DrawCursor(Oberon.Pointer, Oberon.Star, msg.X, msg.Y)
				END;
			END				
		ELSIF msg IS Oberon.InputMsg THEN 			
			WITH msg: Oberon.InputMsg DO
				IF msg.id = Oberon.track THEN
					IF msg.keys # {} THEN  
						Pos(F,msg.X,msg.Y,X,Y);
						IF X > F.cx THEN
							REPEAT
								col := (X - F.cx) DIV F.cw;
								IF (col # F.color) & (col >= 0) & (col < 16)  THEN
									IF msg.keys = {ML} THEN
										REPEAT 
											Input.Mouse(msg.keys, msg.X, msg.Y); Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, msg.X, msg.Y);
										UNTIL msg.keys # {ML};
										IF msg.keys = {ML,1} THEN
											Display.GetColor(F.color,r,g,b); Display.SetColor(col,r,g,b)
										END

									END;
									F.color := col; ShowColor(F); SetHSV(col); ShowHSV(F); ShowValues(F);
								END;
								Input.Mouse(msg.keys, msg.X, msg.Y);	
								Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, msg.X, msg.Y);
								Pos(F,msg.X,msg.Y,X,Y);
							UNTIL (msg.keys = {})
						ELSIF X > F.x THEN
							col := (X - F.x) DIV F.cw;
							IF (col >= 0) & (col < 6) THEN
								EditPalette(F,col)
							END
						END
					END
				END;
				Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, msg.X, msg.Y);
			END
		ELSIF msg IS Oberon.InputMsg THEN
			WITH msg: Oberon.InputMsg DO
				IF msg.id = Oberon.consume THEN 
				(* write *)
				ELSIF  msg.id = Oberon.track THEN 
					Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, msg.X, msg.Y) 
				END
			END			
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg : Objects.CopyMsg DO
				Copy(F,F1); msg.obj := F1; 
			END
		ELSIF msg IS Display.ModifyMsg THEN
			WITH msg : Display.ModifyMsg DO
				IF msg.F = F THEN
					Neutralize(F); Modify(F, msg.id, msg.dY, msg.Y, msg.H)
				END
			END
		END
	END
END Handle;

PROCEDURE *Restore(F : Frame; x, y, w, h: INTEGER);
	VAR i : INTEGER; s : ARRAY 32 OF CHAR; X : INTEGER;
BEGIN
	IF h # 0 THEN
		Pos(F,F.X,F.Y,F.x,F.y);  
		INC(F.x,Border); INC(F.y,Border); 
		F.w := F.x + F.W - F.x - Border; F.h := F.y + F.H- F.y - 2* Border;
		F.cw := F.w DIV 22; F.cx := F.x + 6 * F.cw;  
		F.w := 16 * F.cw; DEC(F.x,2);
		Rectangle(F,F.cx-1,F.y-1,F.w+2,F.h+2);
		i := 0; 
		WHILE i < 16 DO X := F.cx + i* F.cw;  
			ReplConst(F,i,X, F.y,F.cw,F.h,Display.replace);
			IntToString(i,s); INC(X,F.X+4); String(X,F.y+F.Y+F.H+2,s); 
			INC(i);
		END;
		ShowColor(F); ShowHSV(F); ShowValues(F);
	END
END Restore;

PROCEDURE Open(F : Frame; l,t : INTEGER);
BEGIN
	F.t :=  t; F.l := l; F.restore := Restore; F.handle :=Handle;  F.color := 4;
END Open;

PROCEDURE Show*;
	VAR F : Frame; X,Y : INTEGER; V : Viewers.Viewer;
BEGIN
	NEW(F); Open(F,0,0);
	Oberon.AllocateUserViewer(Oberon.Par.vwr.X,X,Y);
	V := MenuViewers.New(TextFrames.NewMenu("      Color.Pal","System.Close"),F, TextFrames.menuH, X, Y);
END Show;

	PROCEDURE Insert*;
		VAR F : Frame;  M : Display.ConsumeMsg;

	BEGIN
		NEW(F); Open(F,0,0);
		M.id := Display.integrate; M.obj := F; Display.Broadcast(M);
	END Insert;

BEGIN	
END HSV.Show

	
