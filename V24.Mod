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

MODULE V24;	(** portable *)	(* pjm/ejz *)

(** V24/RS232 serial communications interface. *)

(* Currently only supports 2 com ports *)

IMPORT SYSTEM, Kernel;

CONST
	(** port aliases (check with NumberOfPorts) *)
	COM1* = 0;  COM2* = 1;  COM3* = 2;  COM4* = 3;
	
	(** parity *)
	ParNo* = 0;  ParOdd* = 1;  ParEven* = 2;  ParMark* = 3;  ParSpace* = 4;
	(** stop bits *)
	Stop1* = 1;  Stop2* = 2;  Stop1dot5* = 3;
	(** modem control - MC *)
	DTR* = 0;  RTS* = 1;	(** output *)
	Break* = 2;	(** input/output *)
	DSR* = 3;  CTS* = 4;  RI* = 5;  DCD* = 6;	(** input *)
	
	Ok* =  0; PortInUse* =  1; NoSuchPort* =  2; WrongBPS* =  3; WrongData* =  4; WrongParity* =  5;
	WrongStop* =  6; Failed* =  MAX(INTEGER);
		
	BufSize = 4096;
	
TYPE
	Port = POINTER TO PortDesc;
	PortDesc = RECORD
		base: LONGINT;
		head, tail: LONGINT;
		buf: ARRAY BufSize OF CHAR
	END;

VAR
	ports: ARRAY 2 OF Port;
	numports: LONGINT;

PROCEDURE *InterruptHandler0;
VAR p: Port;  c: CHAR;  n: LONGINT;
BEGIN
	LOOP
		SYSTEM.PORTIN(3FAH, c);	(* IIR *)
		IF ODD(ORD(c)) THEN EXIT END;	(* nothing pending *)
		p := ports[0];  SYSTEM.PORTIN(3F8H, c);	(* RBR *)
		n := (p.tail+1) MOD BufSize;
		IF n # p.head THEN
			p.buf[p.tail] := c;  p.tail := n
		END
	END
END InterruptHandler0;

PROCEDURE *InterruptHandler1;
VAR p: Port;  c: CHAR;  n: LONGINT;
BEGIN
	LOOP
		SYSTEM.PORTIN(2FAH, c);	(* IIR *)
		IF ODD(ORD(c)) THEN EXIT END;	(* nothing pending *)
		p := ports[1];  SYSTEM.PORTIN(2F8H, c);
		n := (p.tail+1) MOD BufSize;
		IF n # p.head THEN
			p.buf[p.tail] := c;  p.tail := n
		END
	END
END InterruptHandler1;

(** NumberOfPorts - Return number of ports available. *)

PROCEDURE NumberOfPorts*(): LONGINT;
BEGIN
	RETURN numports
END NumberOfPorts;

(** Start - Open a serial port (numbered from 0).  bps is the required bits per second.
	data is the number of bits per communication unit.  parity is the parity mode (Par 
	values above).  stop is the number of stop bits (Stop values above).  res returns 0 
	if ok, or error code on error.  1 means port already in use.  2 means no such port.  
	3 means bad bps value.  4 means bad data/parity/stop.   DTR and RTS are enabled. *)
	
PROCEDURE Start*(port, bps, data, parity, stop: LONGINT;  VAR res: LONGINT);
VAR p: Port;  base: LONGINT;  s: SET;
BEGIN
	IF (port >= 0) & (port < numports) THEN
		IF port = 0 THEN base := 3F8H ELSE base := 2F8H END;
		SYSTEM.PORTIN(base+4, SYSTEM.VAL(CHAR, s));
		IF s * {5..7} = {} THEN
			IF (bps > 0) & (115200 MOD bps = 0) THEN
				IF (data >= 5) & (data <= 8) & (parity >= ParNo) & (parity <= ParSpace) & (stop >= Stop1) & (stop <= Stop1dot5) THEN
					IF ports[port] = NIL THEN
						NEW(p);  bps := 115200 DIV bps;
						p.base := base;  p.head := 0;  p.tail := 0;
							(* disable interrupts *)
						SYSTEM.PORTOUT(base+3, 0X);	(* clear DLAB *)
						SYSTEM.PORTOUT(base+1, 0X);	(* IER *)
							(* clear latches *)
						SYSTEM.PORTIN(base+5, SYSTEM.VAL(CHAR, s));	(* LSR *)
						SYSTEM.PORTIN(base+2, SYSTEM.VAL(CHAR, s));	(* IIR *)
						SYSTEM.PORTIN(base+6, SYSTEM.VAL(CHAR, s));	(* MSR *)
							(* enable FIFO & check for 16550 *)
						SYSTEM.PORTOUT(base+2, 1X);	(* FCR *)
						SYSTEM.PORTIN(base+2, SYSTEM.VAL(CHAR, s));	(* IIR *)
						IF s * {6,7} = {6,7} THEN
							SYSTEM.PORTOUT(base+2, 47X)	(* 16550 setup: EnableFifo, CLRRX, CLRTX, SIZE4 *)
						ELSE
							SYSTEM.PORTOUT(base+2, 0X)
						END;
							(* set parameters *)
						SYSTEM.PORTOUT(base+3, 80X);	(* LCR *)
						SYSTEM.PORTOUT(base, CHR(bps));
						SYSTEM.PORTOUT(base+1, CHR(bps DIV 100H));
						CASE data OF
							5: s := {}
							|6: s := {0}
							|7: s := {1}
							|8: s := {0,1}
						END;
						IF stop # Stop1 THEN INCL(s, 2) END;
						CASE parity OF
							ParNo:
							|ParOdd: INCL(s, 3)
							|ParEven: s := s + {3,4}
							|ParMark: s := s + {3,5}
							|ParSpace: s := s + {3..5}
						END;
						SYSTEM.PORTOUT(base+3, SYSTEM.VAL(CHAR, s));	(* LCR *)
						SYSTEM.PORTOUT(base+4, SYSTEM.VAL(CHAR, {0,1,3}));	(* MCR: DTR, RTS, OUT2 *)
							(* install interrupt handler *)
						IF port = 0 THEN Kernel.InstallIP(InterruptHandler0, Kernel.IRQ+4)
						ELSE Kernel.InstallIP(InterruptHandler1, Kernel.IRQ+3)
						END;
						ports[port] := p;
							(* enable receive interrupts *)
						SYSTEM.PORTOUT(base+1, 01X);	(* ICR *)
						res := Ok
					ELSE res := PortInUse (* port in use *)
					END
				ELSE res := WrongData (* bad data/parity/stop *)
				END
			ELSE res := WrongBPS (* bad bps *)
			END
		ELSE res := NoSuchPort	(* no such port *)
		END
	ELSE res := NoSuchPort	(* no such port *)
	END
END Start;

(** Stop - Close the specified port.  Effect on Modem Control lines is undefined. *)

PROCEDURE Stop*(port: LONGINT);
VAR base, a: LONGINT;  s: SET;
BEGIN
	IF (port >= 0) & (port <= numports) THEN
		IF port = 0 THEN base := 3F8H ELSE base := 2F8H END;
		REPEAT	(* wait for last byte to leave *)
			a := base+5;  SYSTEM.PORTIN(a, SYSTEM.VAL(CHAR, s))	(* LSR *)
		UNTIL 6 IN s;
			(* disable interrupts *)
		a := base+1;  SYSTEM.PORTOUT(a, 0X);	(* ICR *)
			(* remove interrupt handler *)
		IF port = 0 THEN Kernel.RemoveIP(InterruptHandler0, Kernel.IRQ+4)
		ELSE Kernel.RemoveIP(InterruptHandler1, Kernel.IRQ+3)
		END;
		ports[port] := NIL
	ELSE HALT(99)
	END
END Stop;

(** Available - Return the number of bytes available in the specified port's buffer. *)

PROCEDURE Available*(port: LONGINT): LONGINT;
VAR p: Port;
BEGIN
	p := ports[port];
	(*IF p = NIL THEN RETURN -1 END*)
	RETURN (p.tail-p.head) MOD BufSize
END Available;

(** Receive - Read one byte from the specified port.  Waits until a byte is available.  res = Ok iff ok. *)

PROCEDURE Receive*(port: LONGINT;  VAR x: SYSTEM.BYTE;  VAR res: LONGINT);
VAR p: Port;
BEGIN
	p := ports[port];
	REPEAT UNTIL p.tail # p.head;
	x := p.buf[p.head];  p.head := (p.head+1) MOD BufSize;
	res := Ok
END Receive;

(** ReceiveBytes - Read n bytes from the specified port.  Waits until n bytes are available.  res = Ok iff ok. *)

PROCEDURE ReceiveBytes*(port: LONGINT;  VAR x: ARRAY OF SYSTEM.BYTE;  n: LONGINT;  VAR res: LONGINT);
VAR i: LONGINT;
BEGIN
	i := 0;  res := Ok;
	WHILE (i # n) & (res = Ok) DO
		Receive(port, x[i], res);  INC(i)
	END
END ReceiveBytes;

(** Send - Send a byte to the specified port.  Waits until buffer space is available.  res = Ok iff ok. *)

PROCEDURE Send*(port: LONGINT;  x: SYSTEM.BYTE;  VAR res: LONGINT);
VAR p: Port;  s: SET;  adr: LONGINT;
BEGIN
	p := ports[port];  adr := p.base+5;
	REPEAT	(* wait for transmitter empty *)
		SYSTEM.PORTIN(adr, SYSTEM.VAL(CHAR, s))	(* LSR *)
	UNTIL 5 IN s;
	SYSTEM.PORTOUT(p.base, x);  res := Ok
END Send;

(** SendBytes - Send n bytes to the specified port.  Waits until buffer space is available.  res = Ok iff all ok. *)

PROCEDURE SendBytes*(port: LONGINT;  VAR x: ARRAY OF SYSTEM.BYTE;  n: LONGINT;  VAR res: LONGINT);
VAR i: LONGINT;
BEGIN
	i := 0;  res := Ok;
	WHILE (i # n) & (res = Ok) DO
		Send(port, x[i], res);  INC(i)
	END
END SendBytes;

(** ClearMC - Clear the specified Model Control lines of the specified port.  s may contain DTR, RTS & Break. *)

PROCEDURE ClearMC*(port: LONGINT;  s: SET);
VAR p: LONGINT;  t: SET;
BEGIN
	IF s * {DTR, RTS} # {} THEN
		p := ports[port].base+4;	(* MCR *)
		SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, t));
		t := t - (s * {DTR, RTS});	(* modify only bits 0 & 1 *)
		SYSTEM.PORTOUT(p, SYSTEM.VAL(CHAR, t))
	END;
	IF Break IN s THEN
		p := ports[port].base+3;	(* LCR *)
		SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, t));
		EXCL(t, 6);	(* break off *)
		SYSTEM.PORTOUT(p, SYSTEM.VAL(CHAR, t))
	END
END ClearMC;

(** SetMC - Set the specified Model Control lines of the specified port.  s may contain DTR, RTS & Break. *)

PROCEDURE SetMC*(port: LONGINT;  s: SET);
VAR p: LONGINT;  t: SET;
BEGIN
	p := ports[port].base+4;	(* MCR *)
	IF s * {DTR, RTS} # {} THEN
		SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, t));
		t := t + (s * {DTR, RTS});	(* modify only bits 0 & 1 *)
		SYSTEM.PORTOUT(p, SYSTEM.VAL(CHAR, t))
	END;
	IF Break IN s THEN
		DEC(p);	(* LCR *)
		SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, t));
		INCL(t, 6);	(* break on *)
		SYSTEM.PORTOUT(p, SYSTEM.VAL(CHAR, t))
	END
END SetMC;

(** GetMC - Return the state of the specified Model Control lines of the specified port.  s contains
	the current state of DSR, CTS, RI, DCD & Break. *)
	
PROCEDURE GetMC*(port: LONGINT;  VAR s: SET);
VAR p: LONGINT;  t: SET;
BEGIN
	s := {};  p := ports[port].base+6;	(* MSR *)
	SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, t));	(* note: this clears bits 0-3 *)
	IF 4 IN t THEN INCL(s, CTS) END;
	IF 5 IN t THEN INCL(s, DSR) END;
	IF 6 IN t THEN INCL(s, RI) END;
	IF 7 IN t THEN INCL(s, DCD) END;
	DEC(p);	(* LSR *)
	SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, t));	(* note: this clears bits 1-4 *)
	IF 4 IN t THEN INCL(s, Break) END
END GetMC;

PROCEDURE Present(base: INTEGER): BOOLEAN;
VAR s: SET;
BEGIN
	INC(base, 4);  SYSTEM.PORTIN(base, SYSTEM.VAL(CHAR, s));
	RETURN s * {5..7} = {}
END Present;

PROCEDURE Init;
BEGIN
	numports := 0;
	IF Present(3F8H) THEN
		INC(numports);
		IF Present(2F8H) THEN INC(numports) END
	END
END Init;

BEGIN
	ports[0] := NIL;  ports[1] := NIL;  Init
END V24.
