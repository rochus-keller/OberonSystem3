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

MODULE Math;	(** portable *)

(**
	Commonly needed Math for REALs.
*)

IMPORT S := SYSTEM, Kernel;

CONST
	e* = 2.7182818284590452354E0;
	pi* = 3.14159265358979323846E0;

VAR
		(* sqrt: *) c11, c12, c13, c14, c15: REAL;
		(* exp: *) c21, c22, c23, c24: REAL;
		(* ln: *) c41, c42, c43, c44, c45: REAL;
		(* sin, cos: *) c31, p31, p32, p33, p30, q31, q32, q33: REAL;
		(* atan: *) c51, s51, c52, s52, p50, q52, q51, q50: REAL;

PROCEDURE -Sin(x: REAL):REAL;
CODE {SYSTEM.i386, SYSTEM.FPU}
	DB 0D9H, 004H, 024H 	(* FLD [ESP] *)
	DB 0D9H, 0FEH	(* FSIN *)
	DB 058H	(* POP EAX *)
END Sin;

PROCEDURE -Cos(x: REAL):REAL;
CODE {SYSTEM.i386, SYSTEM.FPU}
	DB 0D9H, 004H, 024H	(* FLD [ESP] *)
	DB 0D9H, 0FFH	(* FCOS *)
	DB 058H	(* POP EAX *)
END Cos;

PROCEDURE -Arctan(x: REAL):REAL;
CODE {SYSTEM.i386, SYSTEM.FPU}
	DB 0D9H, 004H, 024H	(* FLD [ESP] *)
	DB 0D9H, 0E8H	(* FLD1 *)
	DB 0D9H, 0F3H	(* FPATAN ST(1)/ST(0) *)
	DB 058H	(* POP EAX *)
END Arctan;

PROCEDURE -Sqrt(x: REAL):REAL;
CODE {SYSTEM.i386, SYSTEM.FPU}
	DB 0D9H, 004H, 024H	(* FLD [ESP] *)
	DB 0D9H, 0FAH	(* FSQRT ST(0) *)
	DB 058H	(* POP EAX *)
END Sqrt;

PROCEDURE -Ln(x: REAL):REAL;
CODE {SYSTEM.i386, SYSTEM.FPU}
	DB 0D9H, 0E8H	(* FLD1 *)
	DB 0D9H, 0EAH 	(* FLDL2E *)
	DB 0DEH, 0F9H	(* FDIVP ST(1)/ST(0) *)
	DB 0D9H, 004H, 024H	(* FLD [ESP] *)
	DB 0D9H, 0F1H	(* FYL2X *)
	DB 058H	(* POP EAX *)
END Ln;

PROCEDURE -Exp(x: REAL):REAL;
CODE {SYSTEM.i386, SYSTEM.FPU}
	DB 0D9H, 004H, 24H	(* FLD [ESP] *)
	DB 0D9H, 0EAH	(* FLDL2E *)
	DB 0DEH, 0C9H	(* FMULP ST(1), ST(0) *)
	DB 0D9H, 0C0H	(* FLD ST(0) *)
	DB 0D9H, 0FCH	(* FRNDINT *)
	DB 0D9H, 0C9H	(* FXCH ST(1), ST(0) *)
	DB 0D8H, 0E1H	(* FSUB ST(0), ST(1) *)
	DB 0D9H, 0F0H	(* F2XM1 *)
	DB 0D9H, 0E8H	(* FLD1 *)
	DB 0DEH, 0C1H	(* FADDP ST(1), ST(0) *)
	DB 0D9H, 0FDH	(* FSCALE *)
	DB 0DDH, 0D9H	(* FSTP ST(1) *)
	DB 058H	(* POP EAX *)
END Exp;

PROCEDURE sin*(x: REAL): REAL;
VAR n: LONGINT; y, yy, f: REAL;
BEGIN 
	IF Kernel.copro THEN
		IF x < 0.0 THEN RETURN -Sin(-x) ELSE RETURN Sin(x) END 
	ELSE
		y := c31*x; n := ENTIER(y + 0.5);  (*c31 = 2/pi*)
		y := 2*(y-n); yy := y*y;
		IF ~ODD(n) THEN
			f := ((p33*yy + p32)*yy + p31) / (p30 + yy) * y
		ELSE
			f := ((q33*yy + q32)*yy + q31) / (q31 + yy)
		END ;
		IF ODD(n DIV 2) THEN f := -f END ;
		RETURN f
	END
END sin;

PROCEDURE cos*(x: REAL): REAL;
VAR n: LONGINT; y, yy, f: REAL;
BEGIN 
	IF Kernel.copro THEN
		IF x < 0.0 THEN RETURN Cos(-x) ELSE RETURN Cos(x) END 
	ELSE
		y := c31*x; n := ENTIER(y + 0.5);  (*c31 = 2/pi*)
		y := 2*(y-n); INC(n); yy := y*y;
		IF ~ODD(n) THEN
			f := ((p33*yy + p32)*yy + p31) / (p30 + yy) * y
		ELSE
			f := ((q33*yy + q32)*yy + q31) / (q31 + yy)
		END ;
		IF ODD(n DIV 2) THEN f := -f END ;
		RETURN f
	END
END cos;

PROCEDURE arctan*(x: REAL): REAL;
VAR y, yy, s: REAL;
BEGIN 
	IF Kernel.copro THEN
		RETURN Arctan(x)
	ELSE
		y := ABS(x); s := 0;
		IF y > c51 THEN y := -1/y; s := s51
		ELSIF y > c52 THEN y := (y-1)/(y+1); s := s52
		END ;
		yy := y*y;
		y := p50 * y/(yy + q52 + q51/(yy + q50)) + s;
		IF x < 0 THEN y := -y END ;
		RETURN y
	END
END arctan;

PROCEDURE sqrt*(x: REAL): REAL;
VAR e: LONGINT; a, s: REAL; Error: ARRAY 32 OF CHAR;
BEGIN 
	IF x <= 0 THEN
		IF x = 0 THEN RETURN 0 ELSE Error := "NEGATIVE ARGUMENT"; HALT(80) END
	ELSIF Kernel.copro THEN
		RETURN Sqrt(x)
	ELSE
		a := S.VAL(REAL, S.VAL(SET, x) - {23..30} + {24..29});	(* expo(a) = 126 *)
		e := S.LSH(S.VAL(LONGINT, x), -23) MOD 256 - 126;
		s := c11*a + c12 + c13/(c14 + a);
		s := (s + a/s)*0.5;
		IF ODD(e) THEN INC(e); s := c15*s END ;
		RETURN S.VAL(REAL, S.VAL(LONGINT, s) + S.LSH(e DIV 2, 23))
	END
END sqrt;

PROCEDURE ln*(x: REAL): REAL;
VAR e: LONGINT; a: REAL; Error: ARRAY 32 OF CHAR;
BEGIN 
	IF x <= 0 THEN Error := "NEGATIVE ARGUMENT"; HALT(80)
	ELSIF Kernel.copro THEN
		RETURN Ln(x)
	ELSE
		a := S.VAL(REAL, S.VAL(SET, x) - {23..30} + {24..29});	(* expo(a) = 126 *)
		e := S.LSH(S.VAL(LONGINT, x), -23) MOD 256 - 126;
		IF a < c41 THEN a := 2*a; DEC(e) END ;
		a := (a-1)/(a+1);
		a := c42*e + a*(c43 + c44/(c45 - a*a));
		RETURN a
	END
END ln;

PROCEDURE exp*(x: REAL): REAL;
VAR n: LONGINT; p, y, yy: REAL; Error: ARRAY 32 OF CHAR;
BEGIN 
	IF Kernel.copro THEN
		RETURN Exp(x)
	ELSE
		y := c21*x;  (*1/ln(2)*)
		n := ENTIER(y + 0.5); y := y-n;
		IF y >= 0 THEN INC(n) END ;
		IF n < -128 THEN RETURN 0
		ELSIF n > 127 THEN Error := "ARGUMENT TOO LARGE"; HALT(81)
		ELSE yy := y*y;
			p := (c22 + c23*yy)*y;
			p := p/(c24 + yy - p) + 0.5;
			IF y < 0 THEN p := 2*p END;
			RETURN S.VAL(REAL, S.VAL(LONGINT, p) + S.LSH(n, 23))
		END
	END
END exp;

BEGIN 
	S.PUT(S.ADR(c11), 03EAFBA81H);
	S.PUT(S.ADR(c12), 03F665222H);
	S.PUT(S.ADR(c13), 0BEBA6391H);
	S.PUT(S.ADR(c14), 03F00000EH);
	S.PUT(S.ADR(c15), 03F3504F3H);	(* 1/sqrt(2) *)
	S.PUT(S.ADR(c21), 03FB8AA3BH);	(* 1/ln(2) *)
	S.PUT(S.ADR(c22), 040E6E1ACH);
	S.PUT(S.ADR(c23), 03D6C5665H);
	S.PUT(S.ADR(c24), 041A68BBBH);
	S.PUT(S.ADR(c41), 03F3504F3H);	(* 1/sqrt(2) *)
	S.PUT(S.ADR(c42), 03F317218H);	(* ln(2) *)
	S.PUT(S.ADR(c43), 03F654226H);
	S.PUT(S.ADR(c44), 03FEA3856H);
	S.PUT(S.ADR(c45), 03FD4114DH);
	S.PUT(S.ADR(c31), 03F22F983H);	(* 2/pi *)
	S.PUT(S.ADR(p31), 04253463FH);
	S.PUT(S.ADR(p32), 0C094A235H);
	S.PUT(S.ADR(p33), 03DB1AC59H);
	S.PUT(S.ADR(p30), 042868060H);
	S.PUT(S.ADR(q31), 0423EBFC9H);
	S.PUT(S.ADR(q32), 0C15B53F8H);
	S.PUT(S.ADR(q33), 03EE548F8H);
	S.PUT(S.ADR(c51), 0401A827AH);	(* 1 + sqrt(2) *)
	S.PUT(S.ADR(s51), 03FC90FDBH);	(* pi/2 *)
	S.PUT(S.ADR(c52), 03ED413CDH);	(* sqrt(2) - 1 *)
	S.PUT(S.ADR(s52), 03F490FDBH);	(* pi/4 *)
	S.PUT(S.ADR(p50), 040CBD065H);
	S.PUT(S.ADR(q52), 041099F6AH);
	S.PUT(S.ADR(q51), 0C08DFBCBH);
	S.PUT(S.ADR(q50), 03FFE6CB2H)
END Math.
