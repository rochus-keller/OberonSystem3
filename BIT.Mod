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

MODULE BIT;	(** portable *)	(* tk 12.2.96 *)

	TYPE
		SHORTCARD* = SHORTINT;
		CARDINAL* = INTEGER;
		LONGCARD* = LONGINT;
	
	CONST
		rbo = FALSE;	(* reverse bit ordering, e.g. PowerPC*)
		risc = FALSE;	(* risc architecture - no support for 8 and 16-bit rotations *)
	
	(** bitwise exclusive or: x XOR y *)
	PROCEDURE CXOR*(x, y: CHAR): CHAR;
	BEGIN RETURN CHR(ORD( BITS( LONG(ORD(x))) / BITS( LONG(ORD(y)))))
	END CXOR;
	
	PROCEDURE SXOR*(x, y: SHORTINT): SHORTINT;
	BEGIN RETURN SHORT(SHORT(ORD( BITS( LONG(LONG(x))) / BITS( LONG(LONG(y))))))
	END SXOR;
	
	PROCEDURE IXOR*(x, y: INTEGER): INTEGER;
	BEGIN RETURN SHORT(ORD( BITS( LONG(x)) / BITS( LONG(y))))
	END IXOR;
	
	PROCEDURE LXOR*(x, y: LONGINT): LONGINT;
	BEGIN RETURN ORD( BITS( x) / BITS( y))
	END LXOR;
	
	
	(** bitwise or: x OR y *)
	PROCEDURE COR*(x, y: CHAR): CHAR;
	BEGIN RETURN CHR(ORD( BITS( LONG(ORD(x))) + BITS( LONG(ORD(y)))))
	END COR;
	
	PROCEDURE SOR*(x, y: SHORTINT): SHORTINT;
	BEGIN RETURN SHORT(SHORT(ORD( BITS( LONG(LONG(x))) + BITS( LONG(LONG(y))))))
	END SOR;
	
	PROCEDURE IOR*(x, y: INTEGER): INTEGER;
	BEGIN RETURN SHORT(ORD( BITS( LONG(x)) + BITS( LONG(y))))
	END IOR;
	
	PROCEDURE LOR*(x, y: LONGINT): LONGINT;
	BEGIN RETURN ORD( BITS( x) + BITS( y))
	END LOR;
	
	
	(** bitwise and: x AND y *)
	PROCEDURE CAND*(x, y: CHAR): CHAR;
	BEGIN RETURN CHR(ORD( BITS( LONG(ORD(x))) * BITS( LONG(ORD(y)))))
	END CAND;
	
	PROCEDURE SAND*(x, y: SHORTINT): SHORTINT;
	BEGIN RETURN SHORT(SHORT(ORD( BITS( LONG(LONG(x))) * BITS( LONG(LONG(y))))))
	END SAND;
	
	PROCEDURE IAND*(x, y: INTEGER): INTEGER;
	BEGIN RETURN SHORT(ORD( BITS( LONG(x)) * BITS( LONG(y))))
	END IAND;
	
	PROCEDURE LAND*(x, y: LONGINT): LONGINT;
	BEGIN RETURN ORD( BITS( x) * BITS( y))
	END LAND;
	
	
	(** bitwise logical left-shift: x shifted n *)
	PROCEDURE CLSH*(x: CHAR; n: SHORTINT): CHAR;
	BEGIN 
		IF risc THEN RETURN CHR(LSL(ORD( BITS( ORD(x)) * BITS( 0FFH)), n))
		ELSE RETURN CHR(LSL(ORD(x), n)) END
	END CLSH;
	
	PROCEDURE SLSH*(x: SHORTINT; n: SHORTINT): SHORTINT;
	BEGIN 
		IF risc THEN RETURN SHORT(SHORT(LSL(ORD( BITS( LONG(LONG(x))) * BITS( 0FFH)), n)))
		ELSE RETURN LSL(x, n) END
	END SLSH;
	
	PROCEDURE ILSH*(x: INTEGER; n: SHORTINT): INTEGER;
	BEGIN 
		IF risc THEN RETURN SHORT(LSL(ORD( BITS( LONG(x)) * BITS( 0FFFFH)), n))
		ELSE RETURN LSL(x, n) END
	END ILSH;
	
	PROCEDURE LLSH*(x: LONGINT; n: SHORTINT): LONGINT;
	BEGIN RETURN LSL(x, n)
	END LLSH;
	
	
	(** bitwise rotation: x rotatated by n bits *)
	PROCEDURE CROT*(x: CHAR; n: SHORTINT): CHAR;
		VAR s0, s1: SET; i: INTEGER;
	BEGIN
		IF risc THEN 
			s0 := BITS( ORD(x)); s1 := {};
			IF rbo THEN
				i := 0; WHILE i < 8 DO
					IF 31-i IN s0 THEN INCL(s1, 31 - ((i+n) MOD 8)) END;
					INC(i)
				END;
			ELSE
				i := 0; WHILE i < 8 DO
					IF i IN s0 THEN INCL(s1, (i+n) MOD 8) END;
					INC(i)
				END;
			END;
			RETURN CHR(ORD( s1))
		ELSE RETURN CHR(ROR(ORD(x), -n)) END;
	END CROT;
	
	PROCEDURE SROT*(x: SHORTINT; n: SHORTINT): SHORTINT;
		VAR s0, s1: SET; i: INTEGER;
	BEGIN
		IF risc THEN 
			s0 := BITS( LONG(LONG(x))); s1 := {};
			IF rbo THEN
				i := 0; WHILE i < 8 DO
					IF 31-i IN s0 THEN INCL(s1, 31 - ((i+n) MOD 8)) END;
					INC(i)
				END;
			ELSE
				i := 0; WHILE i < 8 DO
					IF i IN s0 THEN INCL(s1, (i+n) MOD 8) END;
					INC(i)
				END;
			END;
			RETURN SHORT(SHORT(ORD( s1)))
		ELSE RETURN ROR(x, -n) END;
	END SROT;
	
	PROCEDURE IROT*(x: INTEGER; n: SHORTINT): INTEGER;
		VAR s0, s1: SET; i: INTEGER;
	BEGIN
		IF risc THEN 
			s0 := BITS( LONG(x)); s1 := {};
			IF rbo THEN
				i := 0; WHILE i < 16 DO
					IF 31-i IN s0 THEN INCL(s1, 31 - ((i+n) MOD 16)) END;
					INC(i)
				END;
			ELSE
				i := 0; WHILE i < 16 DO
					IF i IN s0 THEN INCL(s1, (i+n) MOD 16) END;
					INC(i)
				END;
			END;
			RETURN SHORT(ORD( s1))
		ELSE RETURN ROR(x, -n) END;
	END IROT;
	
	PROCEDURE LROT*(x: LONGINT; n: SHORTINT): LONGINT;
	BEGIN RETURN ROR(x, -n)
	END LROT;
	
	
	(** swap bytes to change byteordering *)
	PROCEDURE ISWAP*(x: INTEGER): INTEGER;
		TYPE integer = ARRAY 2 OF CHAR; VAR a, b: integer; 
	BEGIN BYTES(a,x); b[0] := a[1]; b[1] := a[0]; NUMBER(x,b); RETURN x
	END ISWAP;
	
	PROCEDURE LSWAP*(x: LONGINT): LONGINT;
		TYPE longint = ARRAY 4 OF BYTE; VAR a, b: longint; l: LONGINT;
	BEGIN BYTES(a,x); b[0] := a[3]; b[1] := a[2]; b[2] := a[1]; b[3] := a[0]; 
	NUMBER(l,b);
	RETURN l
	END LSWAP;	
	
	(** test bit n in x*)
	PROCEDURE CBIT*(x: CHAR; n: SHORTINT): BOOLEAN;
	BEGIN ASSERT((n >= 0) & (n <= 7));
		IF rbo THEN RETURN (31-n) IN BITS(ORD(x)) ELSE RETURN n IN BITS(LONG(ORD(x))) END
	END CBIT;
	
	PROCEDURE BIT*(x: LONGINT; n: SHORTINT): BOOLEAN;
	BEGIN ASSERT((n >= 0) & (n <= 31));
		IF rbo THEN RETURN (31-n) IN BITS(x) ELSE RETURN n IN BITS(x) END
	END BIT;
	
	
	(** set bit n in x*)
	PROCEDURE CSETBIT*(VAR x: CHAR; n: SHORTINT);
		VAR i: LONGINT; s: SET;
	BEGIN ASSERT((n >= 0) & (n <= 7));
		i := ORD(x); s := BITS(i);
		IF rbo THEN INCL(s, 31-n) ELSE INCL(s, n) END; 
		i := ORD(s); x := CHR(i)
	END CSETBIT;
	
	PROCEDURE SSETBIT*(VAR x: SHORTINT; n: SHORTINT);
		VAR i: LONGINT; s: SET;
	BEGIN ASSERT((n >= 0) & (n <= 7));
		i := LONG(LONG(x)); s := BITS(i);
		IF rbo THEN INCL(s, 31-n) ELSE INCL(s, n) END; 
		i := ORD(s); x := SHORT(SHORT(i))
	END SSETBIT;
	
	PROCEDURE ISETBIT*(VAR x: INTEGER; n: SHORTINT);
		VAR i: LONGINT; s: SET;
	BEGIN ASSERT((n >= 0) & (n <= 15));
		i := LONG(x); s := BITS(i);
		IF rbo THEN INCL(s, 31-n) ELSE INCL(s, n) END; 
		i := ORD(s); x := SHORT(i)
	END ISETBIT;
	
	PROCEDURE LSETBIT*(VAR x: LONGINT; n: SHORTINT);
  	VAR s: SET;
	BEGIN ASSERT((n >= 0) & (n <= 31)); 
  	s := BITS(x);
		IF rbo THEN INCL(s, 31-n) ELSE INCL(s, n) END;
		x := ORD(s);
	END LSETBIT;	
	
	(** clear bit n in x*)
	PROCEDURE CCLRBIT*(VAR x: CHAR; n: SHORTINT);
		VAR i: LONGINT; s: SET;
	BEGIN ASSERT(ABS(n) < 8);
		i := ORD(x); s := BITS(i);
		IF rbo THEN EXCL(s, 31-n) ELSE EXCL(s, n) END; 
		i := ORD(s); x := CHR(i)
	END CCLRBIT;
	
	PROCEDURE SCLRBIT*(VAR x: SHORTINT; n: SHORTINT);
		VAR i: LONGINT; s: SET;
	BEGIN ASSERT(ABS(n) < 8);
		i := LONG(LONG(x)); s := BITS(i);
		IF rbo THEN EXCL(s, 31-n) ELSE EXCL(s, n) END; 
		i := ORD(s); x := SHORT(SHORT(i))
	END SCLRBIT;
	
	PROCEDURE ICLRBIT*(VAR x: INTEGER; n: SHORTINT);
		VAR i: LONGINT; s: SET;
	BEGIN ASSERT(ABS(n) < 16);
		i := LONG(x); s := BITS(i);
		IF rbo THEN EXCL(s, 31-n) ELSE EXCL(s, n) END; 
		i := ORD(s); x := SHORT(i)
	END ICLRBIT;
	
	PROCEDURE LCLRBIT*(VAR x: LONGINT; n: SHORTINT);
	VAR s: SET;
	BEGIN 
	s := BITS(x);
	IF rbo THEN EXCL(s, 31-n) ELSE EXCL(s, n) END;
	x := ORD(s)
	END LCLRBIT;
	
	
	(** unsigned comparison: x < y *)
	PROCEDURE SLESS*(x, y: SHORTCARD): BOOLEAN;
	BEGIN
		RETURN 
			ORD( BITS( LONG(LONG(x))) * BITS( 0FFH))
		 	< 
		 ORD( BITS( LONG(LONG(y))) * BITS( 0FFH));
	END SLESS;
	
	PROCEDURE ILESS*(x, y: CARDINAL): BOOLEAN;
	BEGIN
		RETURN 
			ORD( BITS(LONG(x)) * BITS( 0FFFFH)) 
		< 
			ORD( BITS( LONG(y)) * BITS( 0FFFFH))
	END ILESS;
	
	PROCEDURE LLESS*(x, y: LONGCARD): BOOLEAN;
		VAR x0, y0: LONGINT;
	BEGIN x0 := LSL(x, -1); y0 := LSL(y, -1);
		IF x0 - y0 = 0 THEN RETURN x0 MOD 2 < y0 MOD 2 ELSE RETURN x0 < y0 END
	END LLESS;

				
	(** unsigned comparison: x <= y *)
	PROCEDURE SLESSEQ*(x, y: SHORTCARD): BOOLEAN;
	BEGIN 
		RETURN 
			ORD( BITS( LONG(LONG(x))) * BITS( 0FFH)) 
		<= 
			ORD( BITS( LONG(LONG(y))) * BITS( 0FFH))
	END SLESSEQ;
	
	PROCEDURE ILESSEQ*(x, y: CARDINAL): BOOLEAN;
	BEGIN
		RETURN
			ORD( BITS(LONG(x)) * BITS( 0FFFFH))
		<=
			ORD( BITS( LONG(y)) * BITS( 0FFFFH))
	END ILESSEQ;
	
	PROCEDURE LLESSEQ*(x, y: LONGCARD): BOOLEAN;
		VAR x0, y0: LONGINT;
	BEGIN x0 := LSL(x, -1); y0 := LSL(y, -1);
		IF x0 - y0 = 0 THEN RETURN x0 MOD 2 <= y0 MOD 2 ELSE RETURN x0 <= y0 END
	END LLESSEQ;
	
	
	(** unsigned division: x DIV y *)
	PROCEDURE SDIV*(x, y: SHORTCARD): SHORTCARD;
	BEGIN RETURN SHORT(SHORT(ORD( BITS( LONG(LONG(x))) * BITS( 0FFH)) DIV y))
	END SDIV;
	
	PROCEDURE IDIV*(x, y: CARDINAL): CARDINAL;
	BEGIN RETURN SHORT(ORD( BITS( LONG(x)) * BITS( 0FFFFH))) DIV y;
	END IDIV;
	
	PROCEDURE LDIV*(x, y: LONGCARD): LONGCARD;
		CONST m = 4.294967296D9;
		VAR x0, y0: LONGREAL;
	BEGIN IF x < 0 THEN x0 := m - x ELSE x0 := x END;
		IF y < 0 THEN y0 := m - y ELSE y0 := y END;
		RETURN ENTIER(x0 / y0)
	END LDIV;
	
END BIT.

