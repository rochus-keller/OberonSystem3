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

MODULE MathL;	(** portable *)

IMPORT S := SYSTEM, Kernel;

(**
	Commonly needed Math for LONGREALs.
*)

CONST
	e* = 2.7182818284590452354D0;
	pi* = 3.14159265358979323846D0;
		(* little-endian: *) L = 0; H = 4;
		(* big-endian: *) (* H = 0; L = 4; *)

VAR
		(* sqrt: *) c11, p10: LONGREAL;
		(* exp: *) c21, p22, p21, p20, q21, q20: LONGREAL;
		(* ln: *) c42, p42, p41, p40, q42, q41, q40: LONGREAL;
		(* sin, cos: *) c31, p36, p35, p34, p33, p32, p31, p30, q36, q35, q34, q33, q32, q31, q30: LONGREAL;
		(* atan: *) c51, s51, c52, s52, c53, s53, p53, p52, p51, p50, q52, q51, q50: LONGREAL;

PROCEDURE -Sin(x: LONGREAL):LONGREAL;
CODE {SYSTEM.i386, SYSTEM.FPU}
	DB 0DDH, 004H, 024H	(* FLD qword [ESP] *)
	DB 0D9H, 0FEH	(* FSIN *)
	DB 058H	(* POP EAX *)
	DB 058H	(* POP EAX *)
END Sin;

PROCEDURE -Cos(x: LONGREAL):LONGREAL;
CODE {SYSTEM.i386, SYSTEM.FPU}
	DB 0DDH, 004H, 024H	(* FLD qword [ESP] *)
	DB 0D9H, 0FFH	(* FCOS *)
	DB 058H	(* POP EAX *)
	DB 058H	(* POP EAX *)
END Cos;

PROCEDURE -Arctan(x: LONGREAL):LONGREAL;
CODE {SYSTEM.i386, SYSTEM.FPU}
	DB 0DDH, 004H, 024H	(* FLD qword [ESP] *)
	DB 0D9H, 0E8H	(* FLD1 *)
	DB 0D9H, 0F3H	(* FPATAN ST(1)/ST(0) *)
	DB 058H	(* POP EAX *)
	DB 058H	(* POP EAX *)
END Arctan;

PROCEDURE -Sqrt(x: LONGREAL):LONGREAL;
CODE {SYSTEM.i386, SYSTEM.FPU}
	DB 0DDH, 004H, 024H	(* FLD qword [ESP] *)
	DB 0D9H, 0FAH	(* FSQRT ST(0) *)
	DB 058H	(* POP EAX *)
	DB 058H	(* POP EAX *)
END Sqrt;

PROCEDURE -Ln(x: LONGREAL):LONGREAL;
CODE {SYSTEM.i386, SYSTEM.FPU}
	DB 0D9H, 0E8H				(* FLD1 *)
	DB 0D9H, 0EAH				(* FLDL2E *)
	DB 0DEH, 0F9H				(* FDIVP ST(1)/ST(0) *)
	DB 0DDH, 004H, 024H		(* FLD qword [ESP] *)
	DB 0D9H, 0F1H				(* FYL2X *)
	DB 058H	(* POP EAX *)
	DB 058H	(* POP EAX *)
END Ln;

PROCEDURE -Exp(x: LONGREAL):LONGREAL;
CODE {SYSTEM.i386, SYSTEM.FPU}
	DB 0DDH, 004H, 024H	(* FLD qword [ESP] *)
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
	DB 058H	(* POP EAX *)
END Exp;

PROCEDURE sin*(x: LONGREAL): LONGREAL;
VAR n: LONGINT; y, yy, f: LONGREAL;
BEGIN 
	IF Kernel.copro THEN
		IF x < 0.0D0 THEN RETURN -Sin(-x) ELSE RETURN Sin(x) END 
	ELSE
		y := c31*x; n := ENTIER(y+0.5);  (*c31 = 2/pi*)
		y := 2*(y-n); yy := y*y;
		IF ODD(n) THEN
			f := (((((q36*yy + q35)*yy + q34)*yy + q33)*yy + q32)*yy + q31)*yy + q30
		ELSE
			f := ((((((p36*yy + p35)*yy + p34)*yy + p33)*yy + p32)*yy + p31)*yy + p30)*y
		END ;
		IF ODD(n DIV 2) THEN f := -f END ;
		RETURN f
	END
END sin;

PROCEDURE cos*(x: LONGREAL): LONGREAL;
VAR n: LONGINT; y, yy, f: LONGREAL;
BEGIN 
	IF Kernel.copro THEN
		IF x < 0.0D0 THEN RETURN Cos(-x) ELSE RETURN Cos(x) END 
	ELSE
		y := c31*x; n := ENTIER(y+0.5);  (*c31 = 2/pi*)
		y := 2*(y-n); INC(n); yy := y*y;
		IF ODD(n) THEN
			f := (((((q36*yy + q35)*yy + q34)*yy + q33)*yy + q32)*yy + q31)*yy + q30
		ELSE
			f := ((((((p36*yy + p35)*yy + p34)*yy + p33)*yy + p32)*yy + p31)*yy + p30)*y
		END ;
		IF ODD(n DIV 2) THEN f := -f END ;
		RETURN f
	END
END cos;

PROCEDURE arctan*(x: LONGREAL): LONGREAL;
VAR y, yy, s: LONGREAL;
BEGIN 
	IF Kernel.copro THEN
		RETURN Arctan(x)
	ELSE
		y := ABS(x); s := 0;
		IF y > c51 THEN y := -1/y; s := s51
		ELSIF y > 1 THEN y := (y - c52)/(y*c52 + 1); s := s52
		ELSIF y > c53 THEN y := (y*c52 - 1)/(y + c52); s := s53
		END ;
		yy := y*y;
		y := y*(((p53*yy + p52)*yy + p51)*yy + p50)/
			(((yy + q52)*yy + q51)*yy + q50) + s;
		IF x < 0 THEN y := -y END ;
		RETURN y
	END
END arctan;

PROCEDURE sqrt*(x: LONGREAL): LONGREAL;
VAR h: SET; e: LONGINT; a, s: LONGREAL; Error: ARRAY 32 OF CHAR;
BEGIN 
	IF x <= 0 THEN
		IF x = 0 THEN RETURN 0 ELSE Error := "NEGATIVE ARGUMENT"; HALT(80) END
	ELSIF Kernel.copro THEN
		RETURN Sqrt(x)
	ELSE
		S.GET(S.ADR(x)+H, h); S.PUT(S.ADR(x)+H, h - {20..30} + {21..29}); a := x; 	(* expo(a) = 1022 *)
		e := S.LSH(S.VAL(LONGINT, h), -20) MOD 2048 - 1022;
		s := p10*(a + c11);  (*c11 = 1/sqrt(2)*)
		s := s + a/s;
		s := 0.25*s + a/s;
		s := 0.5*(s + a/s);
		IF ODD(e) THEN INC(e); s := c11*s END ;
		x := s; S.GET(S.ADR(x)+H, h); S.PUT(S.ADR(x)+H, S.VAL(LONGINT, h) + S.LSH(e DIV 2, 20));
		RETURN x
	END
END sqrt;

PROCEDURE ln*(x: LONGREAL): LONGREAL;
VAR h: SET; e: LONGINT; a, aa, a1, a2: LONGREAL; Error: ARRAY 32 OF CHAR;
BEGIN 
	IF x <= 0 THEN Error := "NEGATIVE ARGUMENT"; HALT(80)
	ELSIF Kernel.copro THEN
		RETURN Ln(x)
	ELSE
		S.GET(S.ADR(x)+H, h); S.PUT(S.ADR(x)+H, h - {20..30} + {21..29}); a := x; 	(* expo(a) = 1022 *)
		e := S.LSH(S.VAL(LONGINT, h), -20) MOD 2048 - 1022;
		IF a < c11 THEN a := 2*a; DEC(e) END ;
		a := (a-1)/(a+1);
		aa := a*a;
		a1 := ((p42*aa + p41)*aa + p40);
		a2 := (((aa + q42)*aa + q41)*aa + q40);
		a := c42*e + a*a1/a2;
		RETURN a   (*c42 = ln(2)*)
	END
END ln;

PROCEDURE exp*(x: LONGREAL): LONGREAL;
VAR h: SET; n: LONGINT; p, y, yy: LONGREAL; Error: ARRAY 32 OF CHAR;
BEGIN 
	IF Kernel.copro THEN
		RETURN Exp(x)
	ELSE
		y := c21*x;  (*c21 = 1/ln(2)*)
		n := ENTIER(y + 0.5); y := y-n;
		IF y >= 0 THEN INC(n) END ;
		IF n < -1023 THEN RETURN 0
		ELSIF n > 1024 THEN Error := "ARGUMENT TOO LARGE"; HALT(81)
		ELSE yy := y*y;
			p := ((p22*yy + p21)*yy + p20)*y;
			p := p/((yy + q21)*yy + q20 - p) + 0.5;
			IF y < 0 THEN p := 2*p END ;
			x := p; S.GET(S.ADR(x)+H, h); S.PUT(S.ADR(x)+H, S.VAL(LONGINT, h) + S.LSH(n, 20));
			RETURN x
		END
	END
END exp;

BEGIN 
	S.PUT(S.ADR(c11)+L, 0667F3BCDH); S.PUT(S.ADR(c11)+H, 03FE6A09EH);	(* 1/sqrt(2) *)
	S.PUT(S.ADR(p10)+L, 08F2FCF79H); S.PUT(S.ADR(p10)+H, 03FE2E29BH);
	S.PUT(S.ADR(c21)+L, 0652B82FEH); S.PUT(S.ADR(c21)+H, 03FF71547H);	(* 1/ln(2) *)
	S.PUT(S.ADR(p22)+L, 0AA5CD460H); S.PUT(S.ADR(p22)+H, 03F97A609H);
	S.PUT(S.ADR(p21)+L, 09C957776H); S.PUT(S.ADR(p21)+H, 0403433A2H);
	S.PUT(S.ADR(p20)+L, 0E9C773D2H); S.PUT(S.ADR(p20)+H, 04097A774H);
	S.PUT(S.ADR(q21)+L, 013B5FFD9H); S.PUT(S.ADR(q21)+H, 0406D25B4H);
	S.PUT(S.ADR(q20)+L, 0B314DFB1H); S.PUT(S.ADR(q20)+H, 040B11016H);
	S.PUT(S.ADR(c42)+L, 0FEFA39EFH); S.PUT(S.ADR(c42)+H, 03FE62E42H);	(* ln(2) *)
	S.PUT(S.ADR(p42)+L, 0500DFE4AH); S.PUT(S.ADR(p42)+H, 0C03253EFH);
	S.PUT(S.ADR(p41)+L, 08C526AEEH); S.PUT(S.ADR(p41)+H, 040575DB0H);
	S.PUT(S.ADR(p40)+L, 025EFD645H); S.PUT(S.ADR(p40)+H, 0C0568B2EH);
	S.PUT(S.ADR(q42)+L, 0DCDB3E86H); S.PUT(S.ADR(q42)+H, 0C034BBC5H);
	S.PUT(S.ADR(q41)+L, 098F7C5C0H); S.PUT(S.ADR(q41)+H, 0404EE16AH);
	S.PUT(S.ADR(q40)+L, 025EFD64BH); S.PUT(S.ADR(q40)+H, 0C0468B2EH);
	S.PUT(S.ADR(c31)+L, 06DC9C883H); S.PUT(S.ADR(c31)+H, 03FE45F30H);	(* 2/pi *)
	S.PUT(S.ADR(p36)+L, 0386DCB82H); S.PUT(S.ADR(p36)+H, 03D9E3EEDH);
	S.PUT(S.ADR(p35)+L, 0399B0141H); S.PUT(S.ADR(p35)+H, 0BE1E3006H);
	S.PUT(S.ADR(p34)+L, 0FCA31EF8H); S.PUT(S.ADR(p34)+H, 03E950782H);
	S.PUT(S.ADR(p33)+L, 0CE2D52FAH); S.PUT(S.ADR(p33)+H, 0BF032D2CH);
	S.PUT(S.ADR(p32)+L, 0677586FFH); S.PUT(S.ADR(p32)+H, 03F6466BCH);
	S.PUT(S.ADR(p31)+L, 0E625BE41H); S.PUT(S.ADR(p31)+H, 0BFB4ABBCH);
	S.PUT(S.ADR(p30)+L, 054442D18H); S.PUT(S.ADR(p30)+H, 03FE921FBH);
	S.PUT(S.ADR(q36)+L, 0814ECDA3H); S.PUT(S.ADR(q36)+H, 03DDF3C92H);
	S.PUT(S.ADR(q35)+L, 0987E2CEFH); S.PUT(S.ADR(q35)+H, 0BE5A6C98H);
	S.PUT(S.ADR(q34)+L, 0AE0F3ECCH); S.PUT(S.ADR(q34)+H, 03ECE1F4FH);
	S.PUT(S.ADR(q33)+L, 07DB78384H); S.PUT(S.ADR(q33)+H, 0BF355D3CH);
	S.PUT(S.ADR(q32)+L, 0081AFFA4H); S.PUT(S.ADR(q32)+H, 03F903C1FH);
	S.PUT(S.ADR(q31)+L, 0C9BE4580H); S.PUT(S.ADR(q31)+H, 0BFD3BD3CH);
	S.PUT(S.ADR(q30)+L, LONG(LONG(0FFFFFFFFH))); S.PUT(S.ADR(q30)+H, 03FEFFFFFH);
	S.PUT(S.ADR(c51)+L, 0742C2655H); S.PUT(S.ADR(c51)+H, 0400DDB3DH);	(* 2+sqrt(3) *)
	S.PUT(S.ADR(s51)+L, 054442D18H); S.PUT(S.ADR(s51)+H, 03FF921FBH);	(* pi/2 *)
	S.PUT(S.ADR(c52)+L, 0E8584CAAH); S.PUT(S.ADR(c52)+H, 03FFBB67AH);	(* sqrt(3) *)
	S.PUT(S.ADR(s52)+L, 0382D7366H); S.PUT(S.ADR(s52)+H, 03FF0C152H);	(* pi/3 *)
	S.PUT(S.ADR(c53)+L, 05E9ECD56H); S.PUT(S.ADR(c53)+H, 03FD12614H);	(* 2-sqrt(3) *)
	S.PUT(S.ADR(s53)+L, 0382D7366H); S.PUT(S.ADR(s53)+H, 03FE0C152H);	(* pi/6 *)
	S.PUT(S.ADR(p53)+L, 0FC998D80H); S.PUT(S.ADR(p53)+H, 03FCA5162H);
	S.PUT(S.ADR(p52)+L, 023C5E3D6H); S.PUT(S.ADR(p52)+H, 04013B19BH);
	S.PUT(S.ADR(p51)+L, 0A72936F6H); S.PUT(S.ADR(p51)+H, 040303E28H);
	S.PUT(S.ADR(p50)+L, 03717FEF3H); S.PUT(S.ADR(p50)+H, 04029A55DH);
	S.PUT(S.ADR(q52)+L, 029F407DCH); S.PUT(S.ADR(q52)+H, 040226552H);
	S.PUT(S.ADR(q51)+L, 0DB028A62H); S.PUT(S.ADR(q51)+H, 040348462H);
	S.PUT(S.ADR(q50)+L, 03717FEF3H); S.PUT(S.ADR(q50)+H, 04029A55DH)
END MathL.