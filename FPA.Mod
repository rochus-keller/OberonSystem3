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

MODULE FPA;	(** non-portable *)	(* RC 25.2.92 *)
(* i87 Floating-Point Accelerator Emulator originally for MIPS R2010 *)
(* all routines deliver and accept only normalized numbers or +0        *)

(* Authors: Edgar Schwarz (es)                              *)
(* 19.11.1997 (es) update for PC Native 2.2 CD    *)
(* J. Sedlacek 30.8.97 update for version 2.2         *)
(* pjm 25.03.96 - ported to version 2.06               *)
(* Modified for Native Oberon - muller 07.11.95 *)
(* ported to DOS Oberon ARD, 3. 9. 92                *)

(* number formats: s = sign, m = mantissa, e = exponent
REAL 4 bytes
seeeeeee          emmmmmmm mmmmmmmm mmmmmmmm
real = s * 2^(e-127) * (1 + m/MAX(m))
LONGREAL 8 bytes
seeeeeee          eeeemmmm     mmmmmmmm mmmmmmmm
mmmmmmmm mmmmmmmm mmmmmmmm mmmmmmmm
longreal = s * 2^(e-1023) * (1 + m/MAX(m))
And don't forget that Intel has a wrong byte order !
*)
IMPORT
	Kernel, S := SYSTEM, SYSTEM;
CONST
	zeroDivTrap = 80;
	ovflTrap = 81;
	niTrap = ovflTrap;

	sign = {31}; plus = {}; minus = sign;
	expS = {23..30}; eshiftS = 23; biasS = 127; maxexpS = 254;
	expD = {52-32..62-32}; eshiftD = 52-32; biasD = 1023; maxexpD = 2046;
	mantS = {0..22}; normS = 8388608; normSbit = {23};
	mantD = {0..51-32}; normD = 1048576; 
	normDbit = {52-32}; (* high part *)

(* debug * opTraceNum * = 100; *)
TYPE
	Proc = PROCEDURE;
(* debug: buffer element to save calling information *
	OpTrace * = RECORD
		op1 *, op2 *: CHAR;
		sp* : INTEGER;
		adr *, fgrL *, fgrH *: LONGINT;
	END;
* end debug *)
VAR
	FGR : ARRAY 16 OF SET; (* 8 x 8 Bytes Floating Point Stack *)
	xch : ARRAY 2 OF SET;
	equal, less : BOOLEAN;
	adr: LONGINT;
	SP, length, modReg, opfield, rm, i: INTEGER;
	OP1, OP2, OP3: CHAR;
	uEAX, uEBX, uECX, uEDX, uESI, uEDI, EIP, uEBP, oldebp, uESP, oldesp: LONGINT;
	flags: SET;
	low, hi, carry, R3: LONGINT;
	code: ARRAY 32 OF CHAR;
	codeptr: LONGINT;
	return: LONGINT;
	
(* debug: for tracing calls calling information *
	opTsI*: LONGINT;
	opTs *: ARRAY opTraceNum OF OpTrace;
	pushF: BOOLEAN;
	OP4: CHAR;

	(* save OP1, OP2 in buffer, data is set to 0, can be overwritten later
		by other Push procedures (just to store data more compact     *)
	PROCEDURE OpsPush;
	VAR opTsi: LONGINT;
	BEGIN
		opTsi := opTsI MOD opTraceNum;
		opTs[opTsi].op1 := OP1; opTs[opTsi].op2 := OP2; opTs[opTsi].sp := SP;
		opTs[opTsi].adr := 0; opTs[opTsi].fgrL := 0; opTs[opTsi].fgrH := 0; 
		pushF := TRUE; 
		INC(opTsI);
	END OpsPush;

	(* save two item of floating stack *)
	PROCEDURE ParsPush(sp: INTEGER);
	VAR opTsi: LONGINT;
	BEGIN 
		opTsi := opTsI MOD opTraceNum;
		IF pushF THEN
			IF opTsi = 0 THEN opTsi := 1 END;
			opTs[opTsi-1].adr := adr; 
			opTs[opTsi-1].fgrL := S.VAL(LONGINT,FGR[sp]);
			opTs[opTsi-1].fgrH := S.VAL(LONGINT,FGR[sp+1]);
			pushF := FALSE;
		ELSE	
			opTs[opTsi].op1 := 0X; opTs[opTsi].op2 := 0X; 
			opTs[opTsi].adr := adr; opTs[opTsi].sp := 0;
			opTs[opTsi].fgrL := S.VAL(LONGINT,FGR[sp]);
			opTs[opTsi].fgrH := S.VAL(LONGINT,FGR[sp+1]);
			INC(opTsI);
		END;
	END ParsPush;

	(* save 8 bytes from address *)
	PROCEDURE MemPush(adr: LONGINT);
	VAR li, opTsi: LONGINT;
	BEGIN 
		opTsi := opTsI MOD opTraceNum;
		IF pushF THEN
			IF opTsi = 0 THEN opTsi := 1 END;
			opTs[opTsi-1].adr := adr; 
			S.GET(adr, li); opTs[opTsi-1].fgrL := li;
			S.GET(adr+4, li); opTs[opTsi-1].fgrH := li;
			pushF := FALSE;
		ELSE	
			opTs[opTsi].op1 := 0X; opTs[opTsi].op2 := 0X; 
			opTs[opTsi].adr := adr; opTs[opTsi].sp := 0;
			S.GET(adr, li); opTs[opTsi].fgrL := li;
			S.GET(adr+4, li); opTs[opTsi].fgrH := li;
			INC(opTsI);
		END;
	END MemPush;
* end debug *)

	PROCEDURE MULTU(r4, r5: LONGINT);
	CODE {SYSTEM.i386}
		MOV EAX, r4[EBP]
		MUL r5[EBP]
		MOV low, EAX
		MOV hi, EDX
	END MULTU;
	
	PROCEDURE DIVU(r4, r5: LONGINT);
	CODE {SYSTEM.i386}
		XOR EDX, EDX
		MOV EAX, r4[EBP]
		DIV r5[EBP]
		MOV low, EAX
		MOV hi, EDX
	END DIVU;

	PROCEDURE Carry(r4, r5: LONGINT): LONGINT;
	CODE {SYSTEM.i386}
		XOR EAX, EAX
		MOV EBX, r5[EBP]
		ADD EBX, r4[EBP]
		SETB AL
	END Carry;
	
	PROCEDURE SLRVD(r4, r5, r6: LONGINT): LONGINT;
	CODE {SYSTEM.i386}
			MOV EDX, r5[EBP]
			MOV EAX, r4[EBP]
			MOV ECX, r6[EBP]
			CMP ECX, 32
			JGE lab1
			SHRD EAX, EDX, CL
			SHR EDX, CL
			JMP end
lab1:	MOV EAX, EDX
			XOR EDX, EDX
			SHR EAX, CL
end:	MOV R3, EDX
	END SLRVD;
	
	PROCEDURE ABSD*(d, s: LONGINT);	(* FPR[d] := ABS(FPR[s]) *)
	BEGIN
		FGR[d] := FGR[s]; FGR[d+1] := FGR[s+1] - sign
	END ABSD;

	PROCEDURE NEGD*(d, s: LONGINT);	(* FPR[d] := -FPR[s] *)
		VAR s1: SET;
	BEGIN
		FGR[d] := FGR[s];
		s1 := FGR[s+1];
		IF s1 = {} THEN FGR[d+1] := {}
		ELSE FGR[d+1] := s1 / sign
		END
	END NEGD;

	PROCEDURE ADDD*(d, s, t: LONGINT);	(* FPR[d] := FPR[s]+FPR[t] *)	(* denormalized allowed as input, Round = RN *)
		VAR m1l, m2l, m1h, m2h, e1, e2, ed: LONGINT; s1, s2: SET; Error: ARRAY 32 OF CHAR;
	BEGIN
		m1h := S.VAL(LONGINT, FGR[s+1]); m2h := S.VAL(LONGINT, FGR[t+1]);
		e1 := S.LSH(S.LSH(m1h, 1), -eshiftD-1); s1 := S.VAL(SET, m1h)*sign; m1h := S.VAL(LONGINT, S.VAL(SET, m1h)*mantD);
		e2 := S.LSH(S.LSH(m2h, 1), -eshiftD-1); s2 := S.VAL(SET, m2h)*sign; m2h := S.VAL(LONGINT, S.VAL(SET, m2h)*mantD);
		IF e1 = 0 THEN e1 := 1 ELSE INC(m1h, normD) END;
		IF e2 = 0 THEN e2 := 1 ELSE INC(m2h, normD) END;
		(* IF (e1 = maxexpD + 1) OR (e2 = maxexpD + 1) THEN HALT(NaNTrap) END; *)
		IF e1 < e2 THEN
			m1l := S.VAL(LONGINT, FGR[t]); m2l := S.VAL(LONGINT, FGR[s]);
			ed := e2; e2 := e1; e1 := ed;
			ed := m2h; m2h := m1h; m1h := ed;
			ed := S.VAL(LONGINT, s2); s2 := s1; s1 := S.VAL(SET, ed)
		ELSE m1l := S.VAL(LONGINT, FGR[s]); m2l := S.VAL(LONGINT, FGR[t])
		END;
		(* e1 is exponent of result *)
		ed := e1- e2;
		IF ed > 56 THEN ed := 56 END;
		m1h := S.LSH(m1h, 3) + S.LSH(m1l, -29); m1l := S.LSH(m1l, 3);
		IF ed < 3 THEN	(* sticky = 0, shift left by 3-ed, ed < 3 *)
			m2h := S.LSH(m2h, 3-ed) + S.LSH(m2l, -29-ed); m2l := S.LSH(m2l, 3-ed);
		ELSIF (ed > 34) & (m2l = 0) & (S.VAL(SET, m2h)*{0..ed-35} = {}) OR
				(ed <= 34) & (S.VAL(SET, m2l)*{0..ed-3} = {}) THEN	(* sticky = 0, shift right by ed-3, ed >= 3 *)
			m2l := SLRVD(m2l, m2h, ed-3); m2h := R3
		ELSE	(* sticky = 1, shift right by ed-3, ed >= 3 *)
			m2l := SLRVD(m2l, m2h, ed-3); m2h := R3;
			INCL(S.VAL(SET, m2l), 0)
		END;
		IF s1 # plus THEN m1h := -m1h;
			IF m1l # 0 THEN DEC(m1h) END;
			m1l := -m1l
		END;
		IF s2 # plus THEN m2h := -m2h;
			IF m2l # 0 THEN DEC(m2h) END;
			m2l := -m2l
		END;
		m1h := m1h + m2h + Carry(m1l, m2l); m1l := m1l + m2l;
		IF m1h < 0 THEN s1 := minus; m1h := -m1h;
			IF m1l # 0 THEN DEC(m1h) END;
			m1l := -m1l
		ELSE s1 := plus
		END;
		IF m1h >= ASH(normD, 4) THEN m1l := S.LSH(m1l, -1) + S.LSH(m1h, 31); m1h := S.LSH(m1h, -1); INC(e1)
		ELSIF (m1h = 0) & (m1l = 0) THEN e1 := 1; s1 := plus
		ELSE
			WHILE (m1h < ASH(normD, 3)) & (e1 > 0) DO
				m1h := S.LSH(m1h, 1) + S.LSH(m1l, -31); m1l := S.LSH(m1l, 1); DEC(e1)
			END
		END;
		IF m1l MOD 16 IN {5..7, 12..15} THEN
			m1l := S.LSH(m1l, -3) + S.LSH(m1h, 29); m1h := S.LSH(m1h, -3);
			IF m1l = -1 THEN (* carry *) m1l := 0; INC(m1h);
				IF m1h >= ASH(normD, 1) THEN m1h := S.LSH(m1h, -1); (*1.00...00*); INC(e1) END
			ELSE INC(m1l)
			END
		ELSE m1l := S.LSH(m1l, -3) + S.LSH(m1h, 29); m1h := S.LSH(m1h, -3)
		END;
		IF e1 > maxexpD THEN Error := "FLOATING POINT OVERFLOW"; HALT(ovflTrap)
		ELSIF e1 <= 0 THEN (* denormalized FGR[d] := s1 + S.VAL(SET, m1) => +0 *) FGR[d] := {}; FGR[d+1] := {}
		ELSE FGR[d+1] := s1 + S.VAL(SET, S.LSH(e1, eshiftD)) + (S.VAL(SET, m1h) - normDbit); FGR[d] := S.VAL(SET, m1l)
		END
	END ADDD;

	PROCEDURE SUBD*(d, s, t: LONGINT);	(* FPR[d] := FPR[s]-FPR[t], Round = RN *)
	(* identical to ADDD except in the second line *)
		VAR m1l, m2l, m1h, m2h, e1, e2, ed: LONGINT; s1, s2: SET; Error: ARRAY 32 OF CHAR;
	BEGIN
		m1h := S.VAL(LONGINT, FGR[s+1]); m2h := S.VAL(LONGINT, FGR[t+1] / sign);
		e1 := S.LSH(S.LSH(m1h, 1), -eshiftD-1); s1 := S.VAL(SET, m1h)*sign; m1h := S.VAL(LONGINT, S.VAL(SET, m1h)*mantD);
		e2 := S.LSH(S.LSH(m2h, 1), -eshiftD-1); s2 := S.VAL(SET, m2h)*sign; m2h := S.VAL(LONGINT, S.VAL(SET, m2h)*mantD);
		IF e1 = 0 THEN e1 := 1 ELSE INC(m1h, normD) END;
		IF e2 = 0 THEN e2 := 1 ELSE INC(m2h, normD) END;
		(* IF (e1 = maxexpD + 1) OR (e2 = maxexpD + 1) THEN HALT(NaNTrap) END; *)
		IF e1 < e2 THEN
			m1l := S.VAL(LONGINT, FGR[t]); m2l := S.VAL(LONGINT, FGR[s]);
			ed := e2; e2 := e1; e1 := ed;
			ed := m2h; m2h := m1h; m1h := ed;
			ed := S.VAL(LONGINT, s2); s2 := s1; s1 := S.VAL(SET, ed)
		ELSE m1l := S.VAL(LONGINT, FGR[s]); m2l := S.VAL(LONGINT, FGR[t])
		END;
		(* e1 is exponent of result *)
		ed := e1- e2;
		IF ed > 56 THEN ed := 56 END;
		m1h := S.LSH(m1h, 3) + S.LSH(m1l, -29); m1l := S.LSH(m1l, 3);
		IF ed < 3 THEN	(* sticky = 0, shift left by 3-ed, ed < 3 *)
			m2h := S.LSH(m2h, 3-ed) + S.LSH(m2l, -29-ed); m2l := S.LSH(m2l, 3-ed);
		ELSIF (ed > 34) & (m2l = 0) & (S.VAL(SET, m2h)*{0..ed-35} = {}) OR
				(ed <= 34) & (S.VAL(SET, m2l)*{0..ed-3} = {}) THEN	(* sticky = 0, shift right by ed-3, ed >= 3 *)
			m2l := SLRVD(m2l, m2h, ed-3); m2h := R3
		ELSE	(* sticky = 1, shift right by ed-3, ed >= 3 *)
			m2l := SLRVD(m2l, m2h, ed-3); m2h := R3;
			INCL(S.VAL(SET, m2l), 0)
		END;
		IF s1 # plus THEN m1h := -m1h;
			IF m1l # 0 THEN DEC(m1h) END;
			m1l := -m1l
		END;
		IF s2 # plus THEN m2h := -m2h;
			IF m2l # 0 THEN DEC(m2h) END;
			m2l := -m2l
		END;
		m1h := m1h + m2h + Carry(m1l, m2l); m1l := m1l + m2l;
		IF m1h < 0 THEN s1 := minus; m1h := -m1h;
			IF m1l # 0 THEN DEC(m1h) END;
			m1l := -m1l
		ELSE s1 := plus
		END;
		IF m1h >= ASH(normD, 4) THEN m1l := S.LSH(m1l, -1) + S.LSH(m1h, 31); m1h := S.LSH(m1h, -1); INC(e1)
		ELSIF (m1h = 0) & (m1l = 0) THEN e1 := 1; s1 := plus
		ELSE
			WHILE (m1h < ASH(normD, 3)) & (e1 > 0) DO
				m1h := S.LSH(m1h, 1) + S.LSH(m1l, -31); m1l := S.LSH(m1l, 1); DEC(e1)
			END
		END;
		IF m1l MOD 16 IN {5..7, 12..15} THEN
			m1l := S.LSH(m1l, -3) + S.LSH(m1h, 29); m1h := S.LSH(m1h, -3);
			IF m1l = -1 THEN (* carry *) m1l := 0; INC(m1h);
				IF m1h >= ASH(normD, 1) THEN m1h := S.LSH(m1h, -1); (*1.00...00*); INC(e1) END
			ELSE INC(m1l)
			END
		ELSE m1l := S.LSH(m1l, -3) + S.LSH(m1h, 29); m1h := S.LSH(m1h, -3)
		END;
		IF e1 > maxexpD THEN Error := "FLOATING POINT OVERFLOW"; HALT(ovflTrap)
		ELSIF e1 <= 0 THEN (* denormalized FGR[d] := s1 + S.VAL(SET, m1) => +0 *) FGR[d] := {}; FGR[d+1] := {}
		ELSE FGR[d+1] := s1 + S.VAL(SET, S.LSH(e1, eshiftD)) + (S.VAL(SET, m1h) - normDbit); FGR[d] := S.VAL(SET, m1l)
		END
	END SUBD;

	PROCEDURE MULD*(d, s, t: LONGINT);	(* FPR[d] := FPR[s]*FPR[t], Round = RN *)
		VAR m1l, m2l, m1h, m2h, e1, e2: LONGINT; s1, s2: SET; ah, bl, bh, cl, ch, dl, c0, c1: LONGINT; Error: ARRAY 32 OF CHAR;
	BEGIN
		m1l := S.VAL(LONGINT, FGR[s]); m1h := S.VAL(LONGINT, FGR[s+1]);
		m2l := S.VAL(LONGINT, FGR[t]); m2h := S.VAL(LONGINT, FGR[t+1]);
		IF (m1l = 0) & (m1h = 0) OR (m2l = 0) & (m2h = 0) THEN FGR[d] := {}; FGR[d+1] := {}; RETURN END;
		e1 := S.LSH(S.LSH(m1h, 1), -eshiftD-1); s1 := S.VAL(SET, m1h)*sign;
		m1h := S.VAL(LONGINT, S.VAL(SET, m1h)*mantD) + normD;
		e2 := S.LSH(S.LSH(m2h, 1), -eshiftD-1); s2 := S.VAL(SET, m2h)*sign;
		m2h := S.VAL(LONGINT, S.VAL(SET, m2h)*mantD) + normD;
		(* IF (e1 = maxexpD + 1) OR (e2 = maxexpD + 1) THEN HALT(NaNTrap) END; *)
		(* IF (e1 = 0) OR (e2 = 0) THEN HALT(DenormTrap) END; *)
		e1 := e1 + e2 - biasD; s1 := s1/s2;
		m1h := S.LSH(m1h, 8) + S.LSH(m1l, -24); m1l := S.LSH(m1l, 8);
		m2h := S.LSH(m2h, 7) + S.LSH(m2l, -25); m2l := S.LSH(m2l, 7);
		MULTU(m2l, m1l); s2 (*sticky*) := S.VAL(SET, low); ah := hi;
		MULTU(m2l, m1h); bl := low; bh := hi;
		MULTU(m2h, m1l); cl := low; ch := hi;
		MULTU(m2h, m1h); dl := low; m1h := hi;
		c0 := Carry(ah, bl); m2h := ah + bl; s2 := s2 + S.VAL(SET, m2h);
		c1 := Carry(m2h, cl); m2h := m2h + cl; s2 := s2 + S.VAL(SET, m2h);
		m1l := c0 + c1 + bh;
		c0 := Carry(m1l, ch); m1l := m1l + ch;
		c1 := Carry(m1l, dl); m1l := m1l + dl;
		m1h := m1h + c0 + c1;
		IF m1h >= ASH(normD, 4) THEN m1l := S.LSH(m1l, -1) + S.LSH(m1h, 31); m1h := S.LSH(m1h, -1); INC(e1) END;
		IF s2 # {} THEN (* sticky *) INCL(S.VAL(SET, m1l), 0) END;
		IF m1l MOD 16 IN {5..7, 12..15} THEN
			m1l := S.LSH(m1l, -3) + S.LSH(m1h, 29); m1h := S.LSH(m1h, -3);
			IF m1l = -1 THEN (* carry *) m1l := 0; INC(m1h);
				IF m1h >= ASH(normD, 1) THEN m1h := S.LSH(m1h, -1); (*1.00...00*); INC(e1) END
			ELSE INC(m1l)
			END
		ELSE m1l := S.LSH(m1l, -3) + S.LSH(m1h, 29); m1h := S.LSH(m1h, -3)
		END;
		IF e1 > maxexpD THEN Error := "FLOATING POINT OVERFLOW"; HALT(ovflTrap)
		ELSIF e1 <= 0 THEN (* denormalized FGR[d] := s1 + S.VAL(SET, m1) => +0 *) FGR[d] := {}; FGR[d+1] := {}
		ELSE FGR[d+1] := s1 + S.VAL(SET, S.LSH(e1, eshiftD)) + (S.VAL(SET, m1h) - normDbit); FGR[d] := S.VAL(SET, m1l)
		END
	END MULD;

	PROCEDURE DIVD*(d, s, t: LONGINT);	(* FPR[d] := FPR[s]/FPR[t], Round = RN *)
		VAR m1l, m2l, m1h, m2h, q, ql, qh, rl, rh, e1, e2: LONGINT; s1, s2: SET; Error: ARRAY 32 OF CHAR;
	BEGIN
		m1l := S.VAL(LONGINT, FGR[s]); m1h := S.VAL(LONGINT, FGR[s+1]);
		m2l := S.VAL(LONGINT, FGR[t]); m2h := S.VAL(LONGINT, FGR[t+1]);
		IF (m2l = 0) & (m2h = 0) THEN Error := "FLOATING POINT DIVIDE BY ZERO"; HALT(zeroDivTrap) END;
		IF (m1l = 0) & (m1h = 0) THEN FGR[d] := {}; FGR[d+1] := {}; RETURN END;
		e1 := S.LSH(S.LSH(m1h, 1), -eshiftD-1); s1 := S.VAL(SET, m1h)*sign;
		m1h := S.VAL(LONGINT, S.VAL(SET, m1h)*mantD) + normD;
		e2 := S.LSH(S.LSH(m2h, 1), -eshiftD-1); s2 := S.VAL(SET, m2h)*sign;
		m2h := S.VAL(LONGINT, S.VAL(SET, m2h)*mantD) + normD;
		(* IF (e1 = maxexpD + 1) OR (e2 = maxexpD + 1) THEN HALT(NaNTrap) END; *)
		(* IF (e1 = 0) OR (e2 = 0) THEN HALT(DenormTrap) END; *)
		e1 := e1 - e2 + biasD; s1 := s1/s2;
		qh := 0; ql := 0; e2 := 5;
		WHILE e2 > 0 DO DEC(e2);
			qh := S.LSH(qh, 11) + S.LSH(ql, -21); ql := S.LSH(ql, 11);
			m1h := S.LSH(m1h, 11) + S.LSH(m1l, -21); m1l := S.LSH(m1l, 11);
			DIVU(m1h, m2h); q := low; rh := hi;
			MULTU(q, m2l); rl := -low; m1h := -hi;
			IF rl # 0 THEN DEC(m1h) END;
			rh := rh + m1h + Carry(rl, m1l); rl := rl + m1l;
			IF rh < 0 THEN rh := rh + m2h + Carry(rl, m2l); rl := rl + m2l; DEC(q) END;
			qh := qh + Carry(ql, q); ql := ql + q; m1h := rh; m1l := rl
		END;
		WHILE (qh < ASH(normD, 3)) & (e1 > 0) DO
			qh := S.LSH(qh, 1) + S.LSH(ql, -31); ql := S.LSH(ql, 1); DEC(e1)
		END;
		IF (rl # 0) OR (rh # 0) THEN (* sticky *) INCL(S.VAL(SET, ql), 0) END;
		IF ql MOD 16 IN {5..7, 12..15} THEN
			ql := S.LSH(ql, -3) + S.LSH(qh, 29); qh := S.LSH(qh, -3);
			IF ql = -1 THEN (* carry *) ql := 0; INC(qh);
				IF qh >= ASH(normD, 1) THEN qh := S.LSH(qh, -1); (*1.00...00*); INC(e1) END
			ELSE INC(ql)
			END
		ELSE ql := S.LSH(ql, -3) + S.LSH(qh, 29); qh := S.LSH(qh, -3)
		END;
		IF e1 > maxexpD THEN Error := "FLOATING POINT OVERFLOW"; HALT(ovflTrap)
		ELSIF e1 <= 0 THEN (* denormalized FGR[d] := s1 + S.VAL(SET, q) => +0 *) FGR[d] := {}; FGR[d+1] := {}
		ELSE FGR[d+1] := s1 + S.VAL(SET, S.LSH(e1, eshiftD)) + (S.VAL(SET, qh) - normDbit); FGR[d] := S.VAL(SET, ql)
		END
	END DIVD;

	PROCEDURE CEQD*(s, t: LONGINT);	(* equal := FPR[s]=FPR[t] *)
	BEGIN
		equal := (FGR[s] = FGR[t]) & (FGR[s+1] = FGR[t+1]);
		(*
		IF equal THEN OPsPushCh(1X, 1X, 1X);
		ELSE OPsPushCh(1X, 1X, 0X); END;
		*)
	END CEQD;

	PROCEDURE CLTD*(s, t: LONGINT);	(* less := FPR[s]<FPR[t] *)
		VAR s1, s2: SET;
	BEGIN
		s1 := FGR[s+1]; s2 := FGR[t+1];
		IF s1*s2*sign = plus THEN
			IF s1 # s2 THEN less := S.VAL(LONGINT, s1) < S.VAL(LONGINT, s2)
			ELSE s1 := FGR[s]; s2 := FGR[t];
				IF (s1/s2)*sign = plus THEN less := S.VAL(LONGINT, s1) < S.VAL(LONGINT, s2)
				ELSE (* bit 31 is different *) less := S.VAL(LONGINT, s2) < S.VAL(LONGINT, s1)
				END
			END
		ELSE (* both negative *)
			IF s1 # s2 THEN less := S.VAL(LONGINT, s2) < S.VAL(LONGINT, s1)
			ELSE s1 := FGR[s]; s2 := FGR[t];
				IF (s1/s2)*sign = plus THEN less := S.VAL(LONGINT, s2) < S.VAL(LONGINT, s1)
				ELSE (* bit 31 is different *) less := S.VAL(LONGINT, s1) < S.VAL(LONGINT, s2)
				END
			END
		END
	END CLTD;

	PROCEDURE CVTDW*(d, s: LONGINT);	(* FPR[d] := LONGFLOAT(FGR[s] *)	(* always exact *)
		VAR m, e: LONGINT; sgn: SET;
	BEGIN
		m := S.VAL(LONGINT, FGR[s]); sgn := plus;
		IF m = 0 THEN FGR[d] := {}; FGR[d+1] := {}; RETURN END;
		IF m < 0 THEN sgn := minus;
			IF m # MIN(LONGINT) THEN m := -m END
		END;
		e := biasD + 31;
		WHILE m > 0 DO m := S.LSH(m, 1); DEC(e) END;
		FGR[d] := S.VAL(SET, S.LSH(m, 21));
		FGR[d+1] := sgn + S.VAL(SET, S.LSH(e, eshiftD)) + (S.VAL(SET, S.LSH(m, -11))*mantD)
	END CVTDW;

	PROCEDURE CVTSD*(d, s: LONGINT);	(* FGR[d] := SHORT(FPR[s]) *)	(* Round = RN *)
		VAR ml, mh, sgn: SET; e: LONGINT; Error: ARRAY 32 OF CHAR;
	BEGIN
		ml := FGR[s]; mh := FGR[s+1]; sgn := mh*sign;
		e := S.VAL(LONGINT, mh*expD) + ASH(biasS-biasD, eshiftD);
		(* round to nearest: *)
		IF ml*{28..31} = {28..31} THEN (* carry to mh *)
			IF mh*mantD = mantD THEN (* carry to norm bit *)
				INC(e, ASH(1, eshiftD)); mh := {}; ml := S.LSH(ml, -1)*{0..26}
			ELSE ml := ml - {28..31}; INC(S.VAL(LONGINT, mh), 1)
			END
		ELSE INC(S.VAL(LONGINT, ml), ASH(1, 28))
		END;
		IF ml*{0..28} = {} THEN EXCL(ml, 29) END;
		IF e > ASH(maxexpS, eshiftD) THEN Error := "FLOATING POINT OVERFLOW"; HALT(ovflTrap) END;
		IF e <= 0 THEN FGR[d] := {}
		ELSE FGR[d] := sgn + S.VAL(SET, S.LSH(e, 3)) + S.LSH(mh, 3)*mantS + S.LSH(ml, -29)
		END
	END CVTSD;

	PROCEDURE CVTDS*(d, s: LONGINT);	(* FPR[d] := LONG(FGR[s]) *)
		VAR m: SET;
	BEGIN
		m := FGR[s];
		IF m = {} THEN FGR[d] := {}; FGR[d+1] := {}; RETURN END;
		FGR[d] := S.LSH(m, 29);
		FGR[d+1] := m*sign + S.VAL(SET, S.VAL(LONGINT, S.LSH(m*expS, -3)) 
						+ ASH(biasD-biasS, eshiftD)) + S.LSH(m, -3)*mantD;
	END CVTDS;

	PROCEDURE CVTWD*(d, s: LONGINT);	(* FGR[d] := ENTIER(FPR[s]) *)	(* Round = RM *)
		VAR ml, mh, help: SET; e, help2: LONGINT; Error: ARRAY 32 OF CHAR;
	BEGIN
		ml := FGR[s]; mh := FGR[s+1];
		IF (ml = {}) & (mh = {}) THEN FGR[d] := {}; RETURN END;
		e := S.LSH(S.VAL(LONGINT, mh*expD), -eshiftD) - (biasD + 20);
		IF mh*sign = plus THEN
			IF e > 0 THEN
				IF e > 10 THEN Error := "FLOATING POINT OVERFLOW"; HALT(ovflTrap) END;
				help := S.LSH(ml, e-32)*{0..e-1};
				FGR[d] := S.LSH(mh*mantD + normDbit, e) + help
			ELSIF e < -20 THEN FGR[d] := {}
			ELSE FGR[d] := S.LSH(mh*mantD + normDbit, e)
			END
		ELSE
			IF e > 0 THEN
				help2 := S.VAL(LONGINT, S.LSH(ml, e-32)*{0..e-1});
				FGR[d] := S.VAL(SET, -(S.LSH(S.VAL(LONGINT, mh*mantD) + normD, e) + help2));
				IF (e > 10) & (FGR[d] # {31}) THEN Error := "FLOATING POINT OVERFLOW"; HALT(ovflTrap) END;
			ELSIF e < -20 THEN FGR[d] := (* -1 *) {0..31}
			ELSIF (e # 0) & (mh*{0..-e-1} # {}) OR (ml # {}) THEN
				FGR[d] := S.VAL(SET, -(S.LSH(S.VAL(LONGINT, mh*mantD) + normD, e) + 1))
			ELSE FGR[d] := S.VAL(SET, -S.LSH(S.VAL(LONGINT, mh*mantD) + normD, e))
			END
		END
	END CVTWD;

	PROCEDURE GetAdr(start, len: LONGINT);	(* start is ADR(OP2), len is length-2 *)
	CODE {SYSTEM.i386}	(* implicit: PUSH EBP; MOV EBP, ESP (interrupts are off)*)
		POP oldebp	; save caller EBP
		POP return	; save caller return address
		POP ECX	; len (max 5)
		POP ESI	; start
		MOV oldesp, ESP	; save caller ESP
		
			; compute number of NOPs
		MOV EDX, 5
		SUB EDX, ECX
		
			; assemble getadr instruction (max 7 bytes)
		CLD
		LEA EDI, code
		INC EDI	; { code[0] = 8DX (LEA) }
		LODSB
		AND AL, 0C7H	; clear reg bits (LEA EAX)
		STOSB
		REP MOVSB	; copy possible other bytes (LEA EAX, xxx)
		
			; assemble NOPs
		MOV ECX, EDX
		MOV AL, 90H
		REP STOSB
		
			; switch to emulation registers
		MOV EAX, uEAX
		MOV EBX, uEBX
		MOV ECX, uECX
		MOV EDX, uEDX
		MOV ESI, uESI
		MOV EDI, uEDI
		MOV EBP, uEBP
		MOV ESP, uESP
		
			; call assembled instruction
		JMP codeptr
	END GetAdr;
	
	PROCEDURE GetLength;
	BEGIN
		CASE ORD(OP2) DIV 64 OF
			0: IF rm = 4 THEN 
					IF (ORD(OP3) MOD 8) = 5 THEN length := 7 ELSE length := 3 END
				ELSIF rm = 5 THEN length := 6
				ELSE length := 2 END; 
			|1: IF rm = 4 THEN length := 4 ELSE length := 3 END;
			|2: IF rm = 4 THEN length := 7 ELSE length := 6 END;
			|3: length := 2
		END
	END GetLength;

PROCEDURE *Interpret;
CONST
	SpRel = 24X; (* stackpointer relative adressing: 00|100|100 *)
VAR 
	ebp, cs: LONGINT;
BEGIN	(* interrupts are off *)
	(* get relevant registers of caller *) 
	S.GETREG(5, ebp);
	S.GET(ebp+36, uEAX);  S.GET(ebp+32, uECX);  S.GET(ebp+28, uEDX);
	S.GET(ebp+24, uEBX);  S.GET(ebp+16, uEBP);  S.GET(ebp+12, uESI);
	S.GET(ebp+8, uEDI);  S.GET(ebp+48, EIP);  S.GET(ebp+52, cs);
	IF cs MOD 4 = 0 THEN
		S.GET(ebp+20, uESP);  INC(uESP, 20)
	ELSE
		S.GET(ebp+60, uESP)
	END;
	(* Get instruction bytes *)
	S.GET(EIP, OP1); S.GET(EIP+1, OP2); S.GET(EIP+2, OP3); 
(* debug *
	S.GET(EIP+3, OP4);
	OpsPush(); (* if you comment this statement be careful not to use
	other Push procedures *) pushF := FALSE; 
	spalt := SP; opTsIalt:=opTsI; opI := opTsI;
* end debug *)
	length := 2;	(* Default *)
	(* standard x86 Instruction byte: mod*2 reg*3 r/m*3  *)
	modReg := ORD(OP2) DIV 8; (* mod+register field  *)
	opfield := modReg MOD 8; (* register field *)
	(* r/m field or floating point register index *)
	rm := ORD(OP2) MOD 8;
(*	IF (SP < 0) OR (SP > 16) THEN HALT(niTrap) END; *)
	IF OP1 = 0D8X THEN
		IF       modReg = 18H (*C0..7*) THEN (*FADD 0:=i+0*)
			ADDD(SP-2, SP-2-2*rm, SP-2)
		ELSIF modReg = 19H (*C8..F*) THEN (*FMUL 0:=i*0 *)
 			 MULD(SP-2, SP-2-2*rm, SP-2)
		ELSIF modReg = 1AH(*D0..7*) THEN (*FCOM 0-i *)
			HALT(niTrap);
		ELSIF modReg = 1BH(*D8..F*) THEN  (* FCOMP 0-i, pop *)
			DEC(SP, 2); CEQD(SP, SP-2*rm); CLTD(SP, SP-2*rm);
		ELSIF OP2 = 0E9X (*FSUBJ*) THEN SUBD(SP-2, SP-4, SP-2)
		ELSIF OP2 = 0F1X (*FDIVRJ*) THEN DIVD(SP-2, SP-2, SP-4)
		ELSIF OP2 = 0F9X (*FDIVJ*) THEN DIVD(SP-2, SP-4, SP-2)
		ELSIF OP2 >= 0C0X THEN HALT(88)
		ELSE
			HALT(88); (* do we come here ? *)
			GetLength; GetAdr(EIP+1, length-2);
			(*IF (rm = 4) & (OP3 = SpRel) THEN INC(adr, 4); END;*)
			IF       opfield = 2 THEN (* FCOM memr4-0 *) HALT(niTrap);
			ELSIF opfield = 3 THEN (* FCOMP memr4-0,pop *) HALT(niTrap);
			ELSE HALT(88)
			END
		END
	ELSIF OP1 = 0D9X THEN 
		IF modReg= 18H(*C0..7*)THEN (* FLD i, push 0 := old i *)
			FGR[SP] := FGR[SP-2-2*rm]; FGR[SP+1] := FGR[SP-1-2*rm];
			INC(SP,2);
		ELSIF OP2 = 0C9X THEN (* FXCH *)
			xch[0] := FGR[SP-2]; xch[1] := FGR[SP-1]; 
			FGR[SP-2] := FGR[SP-4]; FGR[SP-1] := FGR[SP-3];
			FGR[SP-4] := xch[0]; FGR[SP-3] := xch[1]
		ELSIF OP2 = 0E0X THEN (* FCHS *) NEGD(SP-2, SP-2)
		ELSIF OP2 = 0E1X THEN (* FABS *) ABSD(SP-2, SP-2)
		ELSIF OP2 = 0E4X THEN (* FTST 0-0.0 *) HALT(niTrap);
		ELSIF OP2 = 0E8X THEN (* FLD1 +1.0 *)
			FGR[SP] := {}; FGR[SP+1] := {20 .. 29}; INC(SP, 2); 
		ELSIF OP2 = 0EEX THEN (* FLDZ +0.0 *)
			FGR[SP] := {}; FGR[SP+1] := {}; INC(SP, 2)
		ELSIF OP2 = 0F6X THEN (* FDECSTP *) HALT(niTrap)
		ELSIF OP2 = 0F7X THEN (* FINCSTP *)  HALT(niTrap)
		ELSIF OP2 >= 0C0X THEN HALT(88)
		ELSE 
			GetLength; GetAdr(EIP+1, length-2);
			(*IF (rm = 4) & (OP3 = SpRel) THEN INC(adr, 4); END;*)
			IF opfield = 0 THEN (* FLD real *)
				S.GET(adr, FGR[SP]); CVTDS(SP, SP); INC(SP, 2);
			ELSIF opfield = 2 THEN (* FST real *)
				HALT(niTrap);
			ELSIF opfield = 3 THEN (* FSTP real *)
				DEC(SP, 2); CVTSD(SP, SP); S.PUT(adr, FGR[SP])
			ELSIF (opfield = 5) OR (opfield = 7) THEN
				(* do nothing; FLDCW and FSTCW, rounding in procedure *)
			ELSE HALT(88) 
			END
		END
	ELSIF OP1 = 0DAX THEN
		IF OP2 >= 0C0X THEN HALT(88)
		ELSE
			HALT(88); (* let's see whether it's called *)
			GetLength; GetAdr(EIP+1, length-2);
			(*IF (rm = 4) & (OP3 = SpRel) THEN INC(adr, 4); END;*)
			IF       opfield = 2 THEN (* FCOM memr8 *) HALT(niTrap)
			ELSIF opfield = 3 THEN (* FCOMP memr8 *) HALT(niTrap)
			ELSE HALT(88)
			END
		END
	ELSIF OP1 = 0DBX THEN
		IF OP2 >= 0C0X THEN HALT(88)
		ELSE
			GetLength; GetAdr(EIP+1, length-2);
			(*IF (rm = 4) & (OP3 = SpRel) THEN INC(adr, 4); END;*)
			IF opfield = 0 THEN (* FILD longint *)
				S.GET(adr, FGR[SP]); CVTDW(SP, SP); INC(SP, 2)
			ELSIF opfield = 2 THEN (* FIST mem4i := 0 *)
				CVTWD(SP-2,SP-2); S.PUT(adr, FGR[SP-2]);
			ELSIF opfield = 3 THEN (* FISTP mem4i := 0, pop *)
				DEC(SP,2); CVTWD(SP,SP); S.PUT(adr, FGR[SP]);
			ELSIF opfield = 5 THEN (* FLD ext. real; treated as longreal *)
				S.GET(adr, FGR[SP]); S.GET(adr+4, FGR[SP+1]); INC(SP, 2)	
			ELSIF opfield = 7 THEN  	(* FSTP ext. real; treated as longreal *)
				DEC(SP, 2); S.PUT(adr, FGR[SP]); S.PUT(adr+4, FGR[SP+1])
			ELSE HALT(88)
			END
		END
	ELSIF OP1 = 0DCX THEN
		HALT(88); (* let's see whether it's called *)
		GetLength; GetAdr(EIP+1, length-2);
		(*IF (rm = 4) & (OP3 = SpRel) THEN INC(adr, 4); END;*)
		IF       opfield = 2 THEN (* FCOM memr8 *) HALT(niTrap)
		ELSIF opfield = 3 THEN (* FCOMP memr8 *) HALT(niTrap)
		ELSE HALT(88)
		END
	ELSIF OP1 = 0DDX THEN
		IF modReg= 18H(*C0..7*)THEN  (* FFREE i *)
			(* discard stackitem i ,rest settles down *)
			FOR i := 0 TO 2*rm-1 DO
				FGR[SP-2*rm-2+i] := FGR[SP-2*rm+i];
			END;
			DEC(SP,2);
		ELSIF modReg = 1AH(*D0..7*)THEN (* FST i := 0 *) 
			HALT(niTrap)
		ELSIF modReg = 1BH(*D8..F*)THEN (* FSTP i := 0,pop *) 
			HALT(niTrap)
		ELSIF OP2 >= 0C0X THEN HALT(88)
		ELSE
			GetLength; GetAdr(EIP+1, length-2);
			(*IF (rm = 4) & (OP3 = SpRel) THEN INC(adr,4); END;*)
			IF opfield = 0 THEN (* FLD longreal *)
				S.GET(adr, FGR[SP]); S.GET(adr+4, FGR[SP+1]); INC(SP, 2)
			ELSIF opfield = 2 THEN (* FST real *)
				HALT(niTrap)
			ELSIF opfield = 3 THEN (* FSTP longreal *)
				DEC(SP, 2); S.PUT(adr, FGR[SP]); S.PUT(adr+4, FGR[SP+1]);
			ELSE
				HALT(88)
			END
		END
	ELSIF OP1 = 0DEX THEN
		IF OP2 = 0C1X THEN (* FADDP *)
			DEC(SP, 2); ADDD(SP-2, SP-2, SP)
		ELSIF OP2 = 0C9X THEN (* FMULP *)
			DEC(SP, 2); MULD(SP-2, SP-2, SP)
		ELSIF OP2 = 0D9X THEN (* FCOMPP *)
			DEC(SP, 2); CEQD(SP, SP-2); CLTD(SP, SP-2); DEC(SP, 2)
		ELSIF OP2 = 0E1X THEN (* FSUBR 1 := 0 - 1, pop*)
			DEC(SP, 2); SUBD(SP-2, SP, SP-2)
		ELSIF OP2 = 0E9X THEN (* FSUBP 1 := 1 - 0, pop *)
			DEC(SP, 2); SUBD(SP-2, SP-2, SP)
		ELSIF OP2 = 0F1X THEN (* FDIVRP *)
			DEC(SP, 2); DIVD(SP-2, SP, SP-2)
		ELSIF modReg = 1FH(*F8..F*) THEN (* FDIVP i:=i/0,pop*)
			DEC(SP, 2); DIVD(SP-2*rm, SP-2*rm, SP)
		ELSE
			HALT(88) 
		END
	ELSIF OP1 = 0DFX THEN
		IF OP2 = 0E0X THEN (* FSTSWAX *)
			S.GET(ebp+56, flags);
			IF less THEN INCL(flags, 0) ELSE EXCL(flags, 0) END;
			IF equal THEN INCL(flags, 6) ELSE EXCL(flags, 6) END;
			EXCL(flags, 2); INC(length);
			S.PUT(ebp+56, flags)
		ELSIF OP2 >= 0C0X THEN HALT(88);
		ELSE
			HALT(88); (* do we come here ? *)
			GetLength; GetAdr(EIP+1, length-2);
			(*IF (rm = 4) & (OP3 = SpRel) THEN INC(adr,4); END;*)
			IF       opfield = 2 THEN (* FIST mem2i := 0 *) HALT(niTrap)
			ELSIF opfield = 3 THEN (* FIST mem2i := 0,pop *) HALT(niTrap)
			ELSIF opfield = 7 THEN (* FISTP longint *)
				HALT(niTrap); (* ??? *)
				DEC(SP, 2); CVTWD(SP, SP); S.PUT(adr, FGR[SP])
			ELSE
				HALT(88)
			END
		END
	ELSIF OP1 = 9BX THEN	(* do nothing *)
		length := 1;
	ELSE HALT(88)
	END;
	(* set registers to new values *)
(*
	S.PUT(ebp+36, uEAX);  S.PUT(ebp+32, uECX);  S.PUT(ebp+28, uEDX);
	S.PUT(ebp+24, uEBX);  S.PUT(ebp+16, uEBP);  S.PUT(ebp+12, uESI);
	S.PUT(ebp+8, uEDI);
*)
	S.PUT(ebp+48, EIP + length)
END Interpret;
	
PROCEDURE Reset*;
BEGIN
	SP := 0; (*debug * opTsI := 0; *)
END Reset;

PROCEDURE InitCode;
BEGIN
	codeptr := SYSTEM.ADR(code[0]);
	code[0] := 8DX;	(* LEA *)
	(* code[1..6] is filled in by GetAdr *)
	code[7] := 89X;  code[8] := 5X;	(* MOV [adr], EAX *)
	SYSTEM.PUT(SYSTEM.ADR(code[9]), SYSTEM.ADR(adr));
	code[13] := 8BX;  code[14] := 25X;	(* MOV ESP, [oldesp] *)
	SYSTEM.PUT(SYSTEM.ADR(code[15]), SYSTEM.ADR(oldesp));
	code[19] := 8BX;  code[20] := 2DX;	(* MOV EBP, [oldebp] *)
	SYSTEM.PUT(SYSTEM.ADR(code[21]), SYSTEM.ADR(oldebp));
	code[25] := 0FFX;  code[26] := 25X;	(* JMP [return] *)
	SYSTEM.PUT(SYSTEM.ADR(code[27]), SYSTEM.ADR(return));
	code[31] := 90X	(* NOP *)
END InitCode;

BEGIN
	InitCode;
	SP := 0; (*debug * opTsI := 0; *)
	Kernel.RemoveIP(NIL, 7);	(* uninstall default handler in Kernel *)
	Kernel.InstallIP(Interpret, 7)	(* install our handler *)
END FPA.

Compiler.Compile *\xp
System.Free FPA ~
FPA.Reset
