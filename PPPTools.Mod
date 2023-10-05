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

MODULE PPPTools;	(** non-portable *)
(* $VCS   1, Edgar.Schwarz@z.zgs.de, 28 Feb 99, 22:9:47 $
    $Log$
$   1, Edgar.Schwarz@z.zgs.de, 28 Feb 99, 22:9:47
version for PPP 1.0.0
*)
IMPORT
	SYSTEM, PT := (*es*) NetBase, NetIP (*PacketTools*), Debug := PPPDebug;

CONST
	GoodFCS = - 0F48H;	(* 0F0B8H *)
		InitialFCS = - 1H;	(* 0FFFFH *)

VAR
	FCSTable: ARRAY 256 OF INTEGER;
		
PROCEDURE XOR(a, b:INTEGER): INTEGER;
BEGIN RETURN SYSTEM.VAL(INTEGER, (SYSTEM.VAL(SET, LONG(a)) / SYSTEM.VAL(SET, LONG(b))))
END XOR;

(*es*) (* aktiviert *)
PROCEDURE FCS (VAR a: ARRAY OF CHAR; pos, len: INTEGER): INTEGER;
VAR code, i: INTEGER;	(* we use 16 bit chksum *)
BEGIN
	code := InitialFCS;
	FOR i := pos TO pos+len-1 DO
		code := XOR(SYSTEM.LSH(code, - 8), FCSTable[SYSTEM.VAL(INTEGER, 
			SYSTEM.VAL(SET, LONG(XOR(code, SYSTEM.VAL(SHORTINT, a[i])))) * {0..7})])
	END;
	RETURN code
END FCS;
(**)

PROCEDURE CalcFCS16;
BEGIN
END CalcFCS16;
(*
PROCEDURE -CalcFCS16
	43H, 0F1H, 10H, 00H,					(* LEA 0(A1, D1.W), D1 *)
	70H, 0FFH,									(* MOVEQ #-1, D0 *)
	4AH, 42H,									(* TST.W D2 *)
	67H, 14H,									(* BEQ.S end *)
	53H, 42H,									(* SUBQ.W #1, D2 *)
	12H, 19H,									(* MOVE.B (A1)+, D1 *)
	0B1H, 41H,								(* EOR.W D0, D1 *)
	0E0H, 48H,									(* LSR.W #8, D0 *)
	02H, 41H, 00H, 0FFH,				(* ANDI.W #$00FF, D1 *)
	32H, 30H, 12H, 00H,					(* MOVE.W 0(A0, D1.W*2), D1*)
	0B3H, 40H,									(* EOR.W D1, D0 *)
	60H, 0E8H;									(* BRA.S loop1 *)
*)
(*es*) (*
PROCEDURE FCS (VAR a: ARRAY OF CHAR; pos, len: INTEGER): INTEGER;
CONST 
	D0 = 0; D1 = 1; D2 = 2; A0 = 8; A1 = 9;
VAR code: INTEGER;	
BEGIN
	SYSTEM.PUTREG(A0, SYSTEM.ADR(FCSTable)); SYSTEM.PUTREG(A1, SYSTEM.ADR(a));
	SYSTEM.PUTREG(D1, pos); SYSTEM.PUTREG(D2, len);
	CalcFCS16;
	SYSTEM.GETREG(D0, code);
	RETURN code
END FCS;
*)
(** CalcFCS - Calculates the FCS, should include Flag, Address etc., 
but no EscCodes, Space for FCS.. *)
PROCEDURE CalcFCS* (VAR a: ARRAY OF CHAR; pos, len: INTEGER): INTEGER;
BEGIN RETURN XOR(FCS(a, pos, len), -1)
END CalcFCS;

(* CheckFCS - Checks a complete packet, including Flag, Address AND FCS-Code! Returns TRUE if Packet is ok *)
PROCEDURE CheckFCS* (VAR a: ARRAY OF CHAR; pos, len: INTEGER): BOOLEAN;
BEGIN RETURN GoodFCS = FCS(a, pos, len)
END CheckFCS;
	
PROCEDURE GenerateFCSTab;
CONST P = - 7BF8H;	(* 8408H *)
VAR b, v, i:INTEGER;
BEGIN
	FOR b := 0 TO 255 DO v := b;
		FOR i:= 0 TO 7 DO
			IF ODD(v) THEN v := XOR(SYSTEM.LSH(v, -1), P) ELSE v := SYSTEM.LSH(v, -1) END
		END;
		FCSTable[b] := v
	END
END GenerateFCSTab;

(*---*)
		
PROCEDURE PutInt* (x: INTEGER; VAR p: ARRAY OF CHAR; pos: INTEGER);
BEGIN
	p[pos + 0] := CHR(SYSTEM.LSH(x, -8) MOD 256);
	p[pos + 1] := CHR(x MOD 256)
END PutInt;
	
PROCEDURE GetInt* (VAR p: ARRAY OF CHAR; pos: INTEGER): INTEGER;
BEGIN RETURN ORD(p[pos])*256 + ORD(p[pos + 1])
END GetInt;
	
PROCEDURE PutLong *(x: LONGINT; VAR p: ARRAY OF CHAR; pos: INTEGER);
BEGIN
	p[pos + 0] := CHR(SYSTEM.LSH(x, -24) MOD 256);
	p[pos + 1] := CHR(SYSTEM.LSH(x, -16) MOD 256);
	p[pos + 2] := CHR(SYSTEM.LSH(x, -8) MOD 256);
	p[pos + 3] := CHR(x MOD 256)	
END PutLong;

PROCEDURE GetLong* (VAR p: ARRAY OF CHAR; pos: INTEGER): LONGINT;
BEGIN
	RETURN ((LONG(ORD(p[pos]))*256 + LONG(ORD(p[pos + 1])))*256 
		+ LONG(ORD(p[pos + 2])))*256 + LONG(ORD(p[pos + 3]))
END GetLong;
		
PROCEDURE GetSet* (VAR p: ARRAY OF CHAR; pos: INTEGER): SET;
BEGIN RETURN SYSTEM.VAL(SET, GetLong(p, pos))
END GetSet;
	
PROCEDURE PutSet* (x: SET; VAR p: ARRAY OF CHAR; pos: INTEGER);
BEGIN PutLong(SYSTEM.VAL(LONGINT, x), p, pos)
END PutSet;

PROCEDURE GetIP* (VAR p: ARRAY OF CHAR; pos: INTEGER; 
								   VAR x: (*es*)NetIP.Adr(*PT.IPAdr*));
VAR i: INTEGER;
BEGIN FOR i := 0 TO (*es*)NetIP.AdrLen(*PT.IPAdrLen*) - 1 DO x[i] := p[pos + i] END
END GetIP;
	
PROCEDURE PutIP* (VAR x: (*es*)NetIP.Adr(*PT.IPAdr*); VAR p: ARRAY OF CHAR; pos: INTEGER);
VAR i: INTEGER;
BEGIN
	FOR i := 0 TO (*es*)NetIP.AdrLen(*PT.IPAdrLen*) - 1 DO 
		p[pos + i] := SYSTEM.VAL(CHAR,x[i])(*x[i]*) 
	END
END PutIP;
	
PROCEDURE EqualIP* (VAR p: ARRAY OF CHAR; pos: INTEGER; 
									VAR x: (*es*)NetIP.Adr(*PT.IPAdr*)): BOOLEAN;
VAR i: INTEGER;
BEGIN i := 0;
	WHILE (i # (*es*)NetIP.AdrLen(*PT.IPAdrLen*)) 
				& ((*es*)SYSTEM.VAL(CHAR,x[i])(*x[i]*) = p[pos + i]) DO 
		INC(i) 
	END;
	RETURN i = (*es*)NetIP.AdrLen(*PT.IPAdrLen*)
END EqualIP;
	
PROCEDURE CopyString* (VAR a: ARRAY OF CHAR; posfrom, posto, len: INTEGER);
VAR i: INTEGER;
BEGIN
	IF posfrom > posto THEN		FOR i := 0 TO len - 1 DO a[posto + i] := a[posfrom + i] END
	ELSIF posfrom < posto THEN  FOR i := len - 1 TO 0 BY - 1 DO a[posto + i] := a[posfrom + i] END
	END
END CopyString;
	
PROCEDURE Magic* (): LONGINT;
BEGIN RETURN 0;
END Magic;
	
PROCEDURE OutPacket* (VAR p: ARRAY OF CHAR; pos, len: INTEGER);
VAR i: INTEGER;
BEGIN
	FOR i := 0 TO len - 1 DO
		Debug.HexByte(p[pos + i]); 
		IF i MOD   4 = 3 THEN Debug.String(" "); END;
		IF i MOD 16 = 15 THEN Debug.Ln END;
	END;
	(*
	FOR i := 0 TO len BY 4 DO
		Debug.Hex(SYSTEM.VAL(LONGINT, p[pos + i])); Debug.String(" ");
		IF i MOD 16 = 0 THEN Debug.Ln END
	END;
	*)
	Debug.Ln
END OutPacket;
	
PROCEDURE WriteSet*(s:SET; VAR a:ARRAY OF CHAR);
VAR k,i:INTEGER;
BEGIN k:=0;
	FOR i:=31 TO 0 BY -1 DO	IF (i IN s) THEN a[k]:="1"; ELSE a[k]:="0";  END; INC(k); END; a[k]:=0X;
END WriteSet;

BEGIN
	GenerateFCSTab
END PPPTools.
