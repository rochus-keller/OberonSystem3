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

MODULE Conversions;	(** portable *)	(** PRK / 20.01.97**)

(*
	This module performs useful conversions between the different formats
	
History

1.0 / 20.01.96
	o IntToStr, StrToInt, RealToStr
	o leading zeros removed in base2 conversion to Str

*)

IMPORT
	Reals, Strings, BIT;
	
TYPE
	String = ARRAY 34 OF CHAR;
	
VAR
	Min: ARRAY 16 OF String;
	Digit: ARRAY 17 OF CHAR;


PROCEDURE BitPatternToStr (val: LONGINT; VAR str: ARRAY OF CHAR; base: LONGINT);
	VAR i, j,shift, size: SHORTINT;
BEGIN
	ASSERT ((base=2) OR (base=8) OR (base=16));
	IF	base = 2	THEN shift := 1; size := 32
	ELSIF	base = 8	THEN shift := 3; size := 11
	ELSIF	base = 16	THEN shift := 4; size := 8
	END;
	IF LEN(str) < size+1 THEN COPY ("str to short", str); RETURN END;
	i := 0; j := 0;
	WHILE i < size DO
		str[j] := Digit[BIT.LAND(BIT.LLSH(val, (i+1)*shift - 32), base-1)];
		INC (i);
		IF (j#0) OR (base#2) OR (str[0]#"0") THEN INC (j) END		(* ejz proposal *)
	END;
	IF j=0 THEN str[0] := "0"; INC (j) END;		(* ejz proposal *)
	str[j] := 0X;
END BitPatternToStr;

(** IntToStr -- convert a longint to a representation in a given base (2..16) *)
PROCEDURE IntToStr* (val: LONGINT; VAR str: ARRAY OF CHAR; base: LONGINT);
	VAR i, j: LONGINT;	digits: ARRAY 32 OF LONGINT;
BEGIN
	IF (base <= 1) OR (base > 16) THEN COPY("???", str); RETURN END;
	IF (base = 2) OR (base = 16) THEN BitPatternToStr (val, str, base); RETURN END;
	IF val = MIN(LONGINT) THEN
		COPY (Min[base-1], str); RETURN
	END;
	IF val < 0 THEN val := -val; str[0] := "-"; j := 1	ELSE	j := 0	END;
	i := 0;
	REPEAT
		digits[i] := val MOD base; INC (i); val := val DIV base
	UNTIL val = 0;
	DEC(i);
	WHILE i >= 0 DO
		str[j] := Digit[digits[i]]; INC (j); DEC (i)
	END;
	str[j] := 0X
END IntToStr;


(** RealToStr -- convert a longreal to a representation in a given base (2..16) *)
PROCEDURE RealToStr*(x: LONGREAL; VAR s: ARRAY OF CHAR; base: LONGINT);
VAR h, l: LONGINT; d: ARRAY 16 OF CHAR;
	
BEGIN
	IF (base # 2) & (base # 10) & (base # 16) THEN COPY("???", s); RETURN END;
	IF base # 10 THEN
		Reals.IntL (x, h, l);
		IntToStr (h, s, base); IntToStr (l, d, base);
		Strings.Append (s, d);
		RETURN
	END;
	Strings.RealToStr (x, s)
END RealToStr;

(* ============================================================= *)
PROCEDURE StrToInt* (s: ARRAY OF CHAR; VAR val: LONGINT; base: LONGINT);
	VAR j: LONGINT; neg: BOOLEAN;
	
	PROCEDURE IsOK (ch: CHAR; base: LONGINT): BOOLEAN;
	BEGIN
		IF Strings.UpperCh(ch) >= "A" THEN
			base := base - ORD(Strings.UpperCh(ch)) + ORD ("A") + 10
		ELSE
			base := base - ORD(ch) + ORD ("0")
		END;
		RETURN (ch >= "0") & (base > 0)
	END IsOK;
	
BEGIN
	val := 0; j := 0;
	IF (base < 2) OR (base > 16) THEN RETURN END;
	IF s[j] = "-" THEN neg := TRUE; INC (j) END;
	WHILE IsOK(s[j], base) DO
		val := val * base;
		IF s[j] <= "9" THEN val := val+ ORD(s[j])-ORD("0")
		ELSE val := val + ORD(s[j])-ORD("7")
		END;
		INC (j)
	END;
	IF neg THEN val := -val END
END StrToInt;


BEGIN
	Min[0] := "???";
	Min[1] := "10000000000000000000000000000000";
	Min[2] := "???";
	Min[3] := "???";
	Min[4] := "???";
	Min[5] := "???";
	Min[6] := "???";
	Min[7] := "???";
	Min[8] := "???";
	Min[9] := "-2147483648";
	Min[10] := "???";
	Min[11] := "???";
	Min[12] := "???";
	Min[13] := "???";
	Min[14] := "???";
	Min[15] := "80000000";
	Digit := "0123456789ABCDEF";
END Conversions.

