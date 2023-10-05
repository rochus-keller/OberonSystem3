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

MODULE PPPDebug;	(** non-portable *)	(* rb, 1996 *)
(* $VCS   1, Edgar.Schwarz@z.zgs.de, 28 Feb 99, 22:11:59 $
    $Log$
$   1, Edgar.Schwarz@z.zgs.de, 28 Feb 99, 22:11:59
version for PPP 1.0.0
*)
	IMPORT SYSTEM, NetBase;
	
	CONST
		LogSize* = 10000H;
		
	VAR
		Log*: ARRAY LogSize OF CHAR;
		LogLen*: LONGINT;
		i: LONGINT;
		full*: BOOLEAN;
		HexChar: ARRAY 17 OF CHAR; 
		vers: ARRAY 32 OF CHAR;
(*es when PPP is up (IPCP ist finished then) save the reached position
   in this variable. After the log buffer is full reset the log position to this
   point so there is a log of the startup in the buffer followed by the 
   most recent  traffic. *)
   	rollback*: LONGINT;
	
	PROCEDURE String*(s: ARRAY OF CHAR);
		VAR l: LONGINT;
	BEGIN
		l := 0;
		WHILE (LogLen # LogSize) & (s[l] # 0X) DO
			Log[LogLen] := s[l];  INC(l);  INC(LogLen);
			(* for ring buffer with keeping PPP startup data, (es, 12.09.1998) *)
			IF LogLen = LogSize THEN LogLen := rollback; full := TRUE; END;
		END
	END String;
	
	PROCEDURE Int*(x, n:LONGINT);
		VAR i, si, x0:LONGINT; s, a:ARRAY 11 OF CHAR;
	BEGIN
		i:=0; si:=0; 
		IF x < 0 THEN
			IF x = MIN(LONGINT) THEN 
				String(" -2147483648"); RETURN 
			ELSE 
				DEC(n); x0:=-x 
			END
		ELSE x0:=x END;
		IF x < 0 THEN a[i]:="-"; INC(i) END; 
		REPEAT
			a[i]:=CHR(x0 MOD 10 + 30H); x0:=x0 DIV 10; INC(i)
		UNTIL x0 = 0;
		WHILE n > i DO s[si]:=" "; INC(si); DEC(n) END;
		REPEAT DEC(i); s[si]:=a[i]; INC(si) UNTIL i = 0; 
		s[si]:=0X; String(s)
	END Int;
	
	PROCEDURE IntBin* (n:INTEGER);
	BEGIN
		String(" ");  Int(n, 1);  String(" ")
	END IntBin;
	
	PROCEDURE LIntBin* (n:LONGINT);
	BEGIN
		String(" ");  Int(n, 1);  String(" ")
	END LIntBin;
	
	PROCEDURE Hex*(n:LONGINT);
		VAR pos: LONGINT;	str: ARRAY 9 OF CHAR;
	BEGIN
		NetBase.NetLToHost(n); (* Bytes vertauschen *)
		pos:=7; 
		WHILE pos>=0 DO 
			str[pos]:=HexChar[n MOD 16]; n:=n DIV 16; DEC(pos) 
		END; 
		str[8]:=0X; String(str)
	END Hex;
	
	PROCEDURE HexByte*(b: SYSTEM.BYTE);
		VAR n: INTEGER; pos: LONGINT;	str: ARRAY 3 OF CHAR;
	BEGIN
		n := ORD(b); pos:=1; 
		WHILE pos>=0 DO 
			str[pos]:=HexChar[n MOD 16]; n:=n DIV 16; DEC(pos) 
		END; 
		str[2]:=0X; String(str)
	END HexByte;
	
	PROCEDURE Char*(ch: CHAR);
		VAR s: ARRAY 2 OF CHAR;
	BEGIN s[0]:=ch; s[1]:=0X; String(s)
	END Char;
	
	PROCEDURE Ln*;
	BEGIN String(0DX)
	END Ln;
	
	PROCEDURE LHex* (label: ARRAY OF CHAR; val: LONGINT);
	BEGIN String(label); String(": "); Hex(val); Ln
	END LHex;
	
	PROCEDURE Init * ();
	VAR 
	BEGIN
		vers :="2.0/es/14.01.1999";
		LogLen := 0; rollback := 0;
		full := FALSE;
		HexChar := "0123456789ABCDEF"
	END Init;	

BEGIN Init()
END PPPDebug.
