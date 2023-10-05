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

MODULE Centronics;	(** non-portable *)	(* pjm 07.08.95 *)

(* Native version *)

IMPORT Kernel, Input, SYSTEM;

CONST 
	LPT1* = 0;
	LPT2* = 1;
	LPT3* = 2;

	Timeout = 0;
	
VAR
	adr: ARRAY 3 OF INTEGER;
	num: INTEGER;

PROCEDURE Halt(msg: ARRAY OF CHAR);
VAR error: ARRAY 32 OF CHAR;
BEGIN
	COPY(msg, error);
	HALT(99)
END Halt;

PROCEDURE Wait;
VAR t: LONGINT;
BEGIN
	t := Kernel.GetTimer()+2;	(* assume one GetTimer tick > 50us *)
	REPEAT UNTIL Kernel.GetTimer() >= t
END Wait;

(** Start - Open parallel port. *)

PROCEDURE Start*(port: INTEGER);
BEGIN
	IF (port < 0) OR (port >= num) THEN Halt("Invalid parallel port") END
END Start;

(** Reset - Reset parallel port. *)

PROCEDURE Reset*(port: INTEGER);
VAR p: INTEGER;
BEGIN
	IF port >= num THEN HALT(99) END;
	p := adr[port];
	INC(p, 2);  SYSTEM.PORTOUT(p, 8X);
	Wait;  SYSTEM.PORTOUT(p, 0CX)
END Reset;

(** Stop - Close parallel port. *)

PROCEDURE Stop*(port: INTEGER);
(* nop in current implementation *)
END Stop;

(** Send - Send byte to parallel port, waiting until it is ready. *)

PROCEDURE Send*(port: INTEGER; x: CHAR);
VAR p: INTEGER;  s: SET;  t: LONGINT;
BEGIN
	IF port >= num THEN Halt("Invalid parallel port") END;
	p := adr[port]+1;
	IF Timeout = 0 THEN
		REPEAT
			SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, s));
			SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, s));
			t := Input.Time()	(* allow break *)
		UNTIL 7 IN s
	ELSE
		t := Input.Time();
		REPEAT
			SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, s));
			SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, s));
			IF 5 IN s THEN	(* out of paper *)
				SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, s));
				IF 5 IN s THEN	(* still out of paper *)
					Halt("Out of paper")
				END
			END;
			IF ~(3 IN s) THEN	(* error *)
				Halt("Printer error")
			END
		UNTIL (7 IN s) OR (Input.Time() - t > Timeout*Input.TimeUnit)
	END;
	IF 7 IN s THEN
		p := adr[port];  SYSTEM.PORTOUT(p, x);
		INC(p, 2);  SYSTEM.PORTOUT(p, 0DX);
		SYSTEM.PORTOUT(p, 0DX);  SYSTEM.PORTOUT(p, 0CX)
	ELSE
		Halt("Printer timeout")
	END
END Send;

(** SendPoll - Send byte to parallel port.  done indicates success or failure. *)

PROCEDURE SendPoll*(port: INTEGER;  x: CHAR;  VAR done: BOOLEAN);
VAR p: INTEGER;  s: SET;
BEGIN
	IF port >= num THEN Halt("Invalid parallel port") END;
	p := adr[port]+1;
	SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, s));
	SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, s));
	IF 7 IN s THEN
		p := adr[port];  SYSTEM.PORTOUT(p, x);
		INC(p, 2);  SYSTEM.PORTOUT(p, 0DX);
		SYSTEM.PORTOUT(p, 0DX);  SYSTEM.PORTOUT(p, 0CX);
		done := TRUE
	ELSE
		done := FALSE
	END
END SendPoll;

(** Available - Returns number of bytes available for reading (implementation optional). *)

PROCEDURE Available*(port: INTEGER): LONGINT;
BEGIN
	Halt("Not implemented")
END Available;

(** Receive - Read a byte from the parallel port (implementation optional). *)

PROCEDURE Receive*(port: INTEGER; VAR x: CHAR);
BEGIN
	Halt("Not implemented")
END Receive;

PROCEDURE Detected(adr: INTEGER): BOOLEAN;
VAR p: INTEGER;  t: LONGINT;  ch: CHAR;
BEGIN
	p := adr+2;  SYSTEM.PORTOUT(p, 0CX);
	p := adr;  SYSTEM.PORTOUT(p, 55X);
	Wait;  SYSTEM.PORTIN(p, ch);
	IF ch = 55X THEN
		SYSTEM.PORTOUT(p, 0AAX);
		Wait;  SYSTEM.PORTIN(p, ch);
		IF ch = 0AAX THEN RETURN TRUE END
	END;
	RETURN FALSE
END Detected;

PROCEDURE Init;
VAR i: SHORTINT;  p: INTEGER;
BEGIN
	num := 0;
	FOR i := 0 TO 2 DO
		CASE i OF
			0: p := 3BCH
			|1: p := 378H
			|2: p := 278H
		END;
		IF Detected(p) THEN adr[num] := p;  INC(num) END
	END
END Init;

BEGIN
	Init
END Centronics.
