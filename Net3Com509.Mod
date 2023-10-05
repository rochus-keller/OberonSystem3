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

MODULE Net3Com509;	(** non-portable *)

(* 3COM EtherLink III adapter driver - tested on ISA and EISA machines *)

(* On 3com509 combo with TP, configure "TP", not "auto-select" *)

IMPORT SYSTEM, NetBase, Kernel, Files;

CONST
	MaxPkt = 1514;
	BufSize = 8192 DIV 4;	(* receive buffer size *)

TYPE 
	Adr = ARRAY 6 OF CHAR;	
	
	Header = POINTER TO HeaderDesc;
	HeaderDesc = RECORD
		dst, src: Adr;		(* 0, 6 *)
		type: INTEGER; 		(* 12 *)
	END;
	
	Data = POINTER TO DataDesc;
	DataDesc = RECORD
		data: ARRAY 1500 OF SYSTEM.BYTE	(* Note: SendPacket may access data[1500] & data[1501] *)
	END;
	
	Device = POINTER TO DeviceDesc;
	DeviceDesc = RECORD (NetBase.DeviceDesc)
	END;
	
VAR
	Noverruns, Nrunts, Nbadframes, Nbadcrcs, Noversizes, Ninerrors, Npops, Nints, Nouterrors, Nresets, Nenables, 
	Nsizeerrors, Nsplits, Nreceived, Nsent, Ntimeouts, Ndropped: LONGINT;	(* stats *)
	port, rxsize, txsize: INTEGER;
	buf: ARRAY BufSize OF LONGINT;
	bufhead, buftail: INTEGER;
	dbuf: ARRAY MaxPkt+3 OF CHAR;
	irq: SHORTINT;
	dev: Device;
	sendhdr: HeaderDesc;
	logging: BOOLEAN;
	log: Files.Rider;

(* RepInDWord - Block port input instruction. *)

PROCEDURE RepInDWord(port, buf, len: LONGINT);
CODE {SYSTEM.i386}
	MOV EDX, port[EBP]
	MOV EDI, buf[EBP]
	MOV ECX, len[EBP]
	CLD
	REP INSD
END RepInDWord;

(* RepOut14 - Block port output instruction (14 bytes). *)

PROCEDURE RepOut14(port, buf: LONGINT);
CODE {SYSTEM.i386}
	MOV EDX, port[EBP]
	MOV ESI, buf[EBP]
	CLD
	OUTSD
	OUTSD
	OUTSD
	OUTSW
END RepOut14;

(* RepOut4n2 - Block port output instruction (4*n+2 bytes). *)

PROCEDURE RepOut4n2(port, buf, n: LONGINT);
CODE {SYSTEM.i386}
	MOV EDX, port[EBP]
	MOV ESI, buf[EBP]
	MOV ECX, n[EBP]
	CLD
	REP OUTSD
	OUTSW
END RepOut4n2;

(* Send - Send a packet.  Interrupts must be enabled. *)

PROCEDURE Send(dev: NetBase.Device; prno: INTEGER; VAR dest: ARRAY OF SYSTEM.BYTE; item: NetBase.Item);
VAR p, free, len: INTEGER;  s, u: SET;  t: LONGINT;  data: Data;
BEGIN
	len := item.len;
	IF (len < 0) OR (len > 1500) THEN INC(Nouterrors); RETURN END;	(* packet too big *)
	SYSTEM.MOVE(SYSTEM.ADR(dest[0]), SYSTEM.ADR(sendhdr.dst[0]), 6);	(* set up sendhdr *)
	sendhdr.type := SYSTEM.ROT(prno, 8);	(* sendhdr.src remains our address *)
	p := port+14;
	LOOP
		SYSTEM.PORTIN(port+11, SYSTEM.VAL(CHAR, s));
		IF s * {4,5} # {} THEN	(* underrun or jabber error *)
			INC(Nresets);  SYSTEM.CLI();
			SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, 5800H));	(* tx reset *)
			REPEAT
				SYSTEM.PORTIN(p, SYSTEM.VAL(INTEGER, u))	(* get status *)
			UNTIL ~(12 IN u);	(* wait until complete *)
			SYSTEM.STI()
		END;
		IF s * {3..5} # {} THEN	(* any error *)
			INC(Nenables);  SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, 4800H))	(* tx enable *)
		END;
		IF 7 IN s THEN	(* TX complete *)
			INC(Npops);  SYSTEM.PORTOUT(port+11, 0X)	(* pop stack *)
		ELSE
			EXIT
		END
	END;
	INC(len, 14);  t := Kernel.GetTimer();  p := port+12;	(* tx free *)
	LOOP
		SYSTEM.PORTIN(p, free);	(* from window 1, i.e. trunc'ed to dword boundary p. 6-21 *)
		IF free >= len THEN EXIT END;
		IF Kernel.GetTimer() - t > Kernel.TimeUnit DIV 2 THEN INC(Ntimeouts); RETURN END;	(* 0.5s timeout *)
	END;
	SYSTEM.PORTOUT(port, len);  SYSTEM.PORTOUT(port, SYSTEM.VAL(INTEGER, 0));
	RepOut14(port, SYSTEM.ADR(sendhdr));	(* output header *)
	DEC(len, 14);  RepOut4n2(port, SYSTEM.ADR(item.data[item.ofs]), (len+1) DIV 4);	(* output data *)
	INC(Nsent);
	IF logging THEN
		t := Kernel.GetTimer();
		Files.WriteLInt(log, t DIV Kernel.TimeUnit);  
		Files.WriteLInt(log, ((t MOD Kernel.TimeUnit)*1000 DIV Kernel.TimeUnit)*1000+1);
		Files.WriteLInt(log, len+14);  Files.WriteLInt(log, len+14);
		Files.WriteBytes(log, sendhdr, 14);
		data := SYSTEM.VAL(Data, SYSTEM.ADR(item.data[item.ofs]));
		Files.WriteBytes(log, data^, len)
	END
END Send;

(* Avail - Return TRUE iff a packet is available *)

PROCEDURE Avail(dev: NetBase.Device): BOOLEAN;
BEGIN
	RETURN bufhead # buftail
END Avail;

(* Copy4 - Copy len dwords from src to dst. *)

PROCEDURE Copy4(src, dst, len: LONGINT);
CODE {SYSTEM.i386}
	MOV ESI, src[EBP]
	MOV EDI, dst[EBP]
	MOV ECX, len[EBP]
	CLD
	REP MOVSD
END Copy4;

(* Copy - Copy size bytes from source to dest.  (No overlap allowed) *)

PROCEDURE Copy(source, dest, size: LONGINT);
CODE {SYSTEM.i386}
	MOV ESI, source[EBP]
	MOV EDI, dest[EBP]
	MOV ECX, size[EBP]
	CLD
	CMP ECX, 8
	JB bytemove
	XOR EAX, EAX
	SHRD EAX, ESI, 2
	JZ copyd
	TEST EDI, 3
	JZ copyd
	SHRD EAX, EDI, 2
	SHR EAX, 28
	CMP AL, 10
	JZ mov2
	CMP AL, 5
	JZ mov3
	NOT AL
	AND AL, 5
	JNZ copyd
	MOVSB
	DEC ECX
	JMP copyd
mov3:
	MOVSB
	DEC ECX
mov2:
	MOVSW
	SUB ECX, 2
copyd:
	SHRD EAX, ECX, 2
	SHR ECX, 2
	REP MOVSD
	SHLD ECX, EAX, 2
bytemove:
	REP MOVSB
END Copy;

(* ReceivePacket - Remove a packet from the input buffer *)

PROCEDURE Receive(dev: NetBase.Device;  VAR prno: INTEGER; VAR src: ARRAY OF SYSTEM.BYTE; VAR item: NetBase.Item);
VAR len, size, left, prno0, dlen: INTEGER;  t: LONGINT;  data: Data;  hdr: Header;
BEGIN
	IF bufhead # buftail THEN
		SYSTEM.GET(SYSTEM.ADR(buf[bufhead]), size);  SYSTEM.GET(SYSTEM.ADR(buf[bufhead])+2, len);
		SYSTEM.CLI();  INC(bufhead);  IF bufhead = BufSize THEN bufhead := 0 END;  SYSTEM.STI();
		left := BufSize - bufhead;  dlen := len-14;
		IF size > left THEN	(* split packet - double copy *)
				(* first move to dbuf & unsplit *)
			Copy4(SYSTEM.ADR(buf[bufhead]), SYSTEM.ADR(dbuf[0]), left);
			Copy4(SYSTEM.ADR(buf[0]), SYSTEM.ADR(dbuf[left*4]), size-left);
				(* then move to buffer & split *)
			SYSTEM.MOVE(SYSTEM.ADR(dbuf[6]), SYSTEM.ADR(src[0]), 6);	(* source address *)
			SYSTEM.GET(SYSTEM.ADR(dbuf[12]), prno0);
			Copy(SYSTEM.ADR(dbuf[14]), SYSTEM.ADR(item.data[0]), dlen)
		ELSE	(* ~split *)
			SYSTEM.MOVE(SYSTEM.ADR(buf[bufhead])+6, SYSTEM.ADR(src[0]), 6);	(* source address *)
			SYSTEM.GET(SYSTEM.ADR(buf[bufhead])+12, prno0);
			Copy(SYSTEM.ADR(buf[bufhead])+14, SYSTEM.ADR(item.data[0]), dlen)
		END;
		prno := SYSTEM.ROT(prno0, 8);
		IF logging THEN
			t := Kernel.GetTimer();
			Files.WriteLInt(log, t DIV Kernel.TimeUnit);  
			Files.WriteLInt(log, ((t MOD Kernel.TimeUnit)*1000 DIV Kernel.TimeUnit)*1000+1);
			Files.WriteLInt(log, len);  Files.WriteLInt(log, len);
			IF size > left THEN	(* split packet *)
				hdr := SYSTEM.VAL(Header, SYSTEM.ADR(dbuf[0]))
			ELSE
				hdr := SYSTEM.VAL(Header, SYSTEM.ADR(buf[bufhead]))
			END;
			data := SYSTEM.VAL(Data, SYSTEM.ADR(item.data[0]));
			Files.WriteBytes(log, hdr^, 14);
			Files.WriteBytes(log, data^, dlen)
		END;
		SYSTEM.CLI();  bufhead := (bufhead+size) MOD BufSize;  SYSTEM.STI();
		item.len := dlen
	ELSE
		item.len := 0
	END
END Receive;

(** SetMode - Set receive mode (1-6) *)

PROCEDURE SetMode*(mode: INTEGER);
VAR f: Files.File;
BEGIN
	CASE mode OF
		1: mode := 0	(* no packets *)
		|2: mode := 1	(* only packets to this interface *)
		|3: mode := 5	(* mode 2 & broadcast *)
		|4: mode := 7	(* mode 3 & limited multicast *)
		|5: mode := 7	(* mode 3 and all multicast *)
		|6: mode := 15	(* all packets *)
		|-1:	(* logging on *)
			IF ~logging THEN
				f := Files.New("EtherNet.Log");  Files.Set(log, f, 0);	(* tcpdump compatible log file *)
				Files.WriteLInt(log, 0A1B2C3D4H);  Files.WriteInt(log, 2);
				Files.WriteInt(log, 4);  Files.WriteLInt(log, 0);  Files.WriteLInt(log, 0);
				Files.WriteLInt(log, 1514);  Files.WriteLInt(log, 1);
				logging := TRUE
			END
		|-2:	(* logging off *)
			IF logging THEN
				logging := FALSE;  Files.Register(Files.Base(log));  Files.Set(log, NIL, 0)
			END
	END;
	SYSTEM.PORTOUT(port+14, SYSTEM.VAL(INTEGER, mode+8000H))	(* set rx filter *)
END SetMode;

(* InterruptHandler - Handle interrupts *)

PROCEDURE *InterruptHandler;
VAR p, q, len, size, left, timer: INTEGER;  s: SET;
BEGIN
	timer := 0;  SYSTEM.PORTIN(port+10, SYSTEM.VAL(CHAR, timer));
	SYSTEM.STI();  (*INC(inttime1, LONG(timer));*)  INC(Nints);
	p := port+14;  q := port+8;
	LOOP
		SYSTEM.PORTIN(p, SYSTEM.VAL(INTEGER, s));	(* status *)
		s := s - {8..15} + {11,13,14};
		SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, s));	(* ack *)
		IF 4 IN s THEN	(* recv complete *)
			SYSTEM.PORTIN(q, SYSTEM.VAL(INTEGER, s));	(* size *)
			IF 14 IN s THEN	(* error *)
				CASE SYSTEM.VAL(SHORTINT, SYSTEM.LSH(s, -11) * {0..2}) OF
					0:  INC(Noverruns)
					|3:  INC(Nrunts)
					|4:  INC(Nbadframes)
					|5:  INC(Nbadcrcs)
					|1:  INC(Noversizes)
					ELSE INC(Ninerrors)
				END (* CASE *)
			ELSE
				len := SYSTEM.VAL(INTEGER, s * {0..10});	(* packet length *)
				IF (len < 60) OR (len > MaxPkt) THEN	(* too small or big *)
					INC(Nsizeerrors)
				ELSE
					size := (len+7) DIV 4;	(* 2 bytes for len, 2 bytes for size, 3 bytes for INSD padding *)
					IF size < (bufhead - buftail - 1) MOD BufSize THEN	(* there is space *)
						DEC(size); SYSTEM.PUT(SYSTEM.ADR(buf[buftail]), size);
						SYSTEM.PUT(SYSTEM.ADR(buf[buftail])+2, len);
						buftail := (buftail+1) MOD BufSize;  left := BufSize - buftail;  INC(Nreceived);
						IF size > left THEN	(* split *)
							RepInDWord(port, SYSTEM.ADR(buf[buftail]), left);  DEC(size, left);
							RepInDWord(port, SYSTEM.ADR(buf[0]), size);  buftail := size;
							INC(Nsplits)
						ELSE	(* ~split *)
							RepInDWord(port, SYSTEM.ADR(buf[buftail]), size);  INC(buftail, size);
							IF buftail = BufSize THEN buftail := 0 END
						END
					ELSE
						INC(Ndropped)	(* no space in local buffer *)
					END
				END
			END
		ELSE
			EXIT
		END;
		SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, 4000H));	(* discard *)
		REPEAT SYSTEM.PORTIN(p, SYSTEM.VAL(INTEGER, s)) UNTIL ~(12 IN s)	(* wait for fin *)
	END;
	SYSTEM.PORTIN(port+10, SYSTEM.VAL(CHAR, timer));  (*INC(inttime2, LONG(timer))*)
END InterruptHandler;

(* WriteID - Write the 3c509 ID pattern to the ID port *)

PROCEDURE WriteID(id: INTEGER);
VAR s: SET;  i: INTEGER;
BEGIN
	SYSTEM.PORTOUT(id, 0X);	(* select ID port *)
	SYSTEM.PORTOUT(id, 0X);	(* reset hardware pattern generator *)
	s := {0..7};
	FOR i := 1 TO 255 DO
		SYSTEM.PORTOUT(id, SYSTEM.VAL(CHAR, s));
		s := SYSTEM.LSH(s, 1);
		IF 8 IN s THEN s := s / {0..3,6,7} END
	END
END WriteID;

(* Delay - Delay for the specified time *)

PROCEDURE Delay(us: LONGINT);
CONST Rate = 1193180;	(* 1.19318 MHz *)
VAR s: SET;
BEGIN
	ASSERT(MAX(LONGINT) DIV us >= Rate);
	us := us*Rate DIV 1000000;
	ASSERT(us < 65536);
	SYSTEM.CLI();
	SYSTEM.PORTIN(61H, SYSTEM.VAL(CHAR, s));	(* disable timer 2 gate *)
	SYSTEM.PORTOUT(61H, SYSTEM.VAL(CHAR, s - {0}));
	SYSTEM.PORTOUT(43H, 0B0X);	(* timer 2, mode 0 *)
	SYSTEM.PORTOUT(42H, CHR(us MOD 100H));
	SYSTEM.PORTOUT(42H, CHR(us DIV 100H));
	SYSTEM.PORTIN(61H, SYSTEM.VAL(CHAR, s));	(* enable timer 2 gate *)
	SYSTEM.PORTOUT(61H, SYSTEM.VAL(CHAR, s + {0}));
	SYSTEM.STI();
	REPEAT SYSTEM.PORTIN(61H, SYSTEM.VAL(CHAR, s)) UNTIL 5 IN s
END Delay;

(* ReadEE - Read EEPROM register *)

PROCEDURE ReadEE(id, reg: INTEGER): LONGINT;
VAR i: SHORTINT;  b: CHAR;  s: SET;
BEGIN
	INC(reg, 80H);  SYSTEM.PORTOUT(id, CHR(reg));
	Delay(400);
	s := {};
	FOR i := 15 TO 0 BY -1 DO
		SYSTEM.PORTIN(id, b);
		IF ODD(ORD(b)) THEN INCL(s, i) END
	END;
	RETURN SYSTEM.VAL(LONGINT, s)
END ReadEE;

(* ReadEE2 - Read EEPROM register (EISA) *)

PROCEDURE ReadEE2(p, reg: INTEGER): LONGINT;
VAR t: LONGINT;
BEGIN
	INC(reg, 80H);  SYSTEM.PORTOUT(p, CHR(reg));
	Delay(170);
	t := 0;  INC(p, 2);  SYSTEM.PORTIN(p, SYSTEM.VAL(INTEGER, t));
	RETURN t
END ReadEE2;

(* Cleanup - Clean up at module termination *)

PROCEDURE *Cleanup;
BEGIN
	Kernel.RemoveIP(InterruptHandler, Kernel.IRQ+irq)
END Cleanup;

(* Init - Initialise the 3c509 card.  Can handle only one card. *)

PROCEDURE Init(VAR adr: Adr);
VAR slot, id, p, q: INTEGER;  t: LONGINT;  baseT: BOOLEAN;  s: SET;

	PROCEDURE Swap(w: LONGINT): INTEGER;
	VAR t: ARRAY 2 OF CHAR;
	BEGIN
		SYSTEM.GET(SYSTEM.ADR(w), t[1]);  SYSTEM.GET(SYSTEM.ADR(w)+1, t[0]);
		RETURN SYSTEM.VAL(INTEGER, t)
	END Swap;
	
BEGIN
	port := MAX(INTEGER);  SYSTEM.GET(0FFFD9H, t);
	IF t = 41534945H THEN	(* try eisa *)
		slot := 1;  id := 9;
		WHILE slot # id DO
			p := SHORT(ASH(slot, 12) + 0C80H);
			t := 0;  SYSTEM.PORTIN(p, SYSTEM.VAL(INTEGER, t));
			IF t = 6D50H THEN
				INC(p, 2);  SYSTEM.PORTIN(p, SYSTEM.VAL(INTEGER, t));
				IF SYSTEM.VAL(SET, t) * {0..7,12..15} = {4,6,12,15} THEN	(* found 509 *)
					id := slot;  port := SHORT(ASH(slot, 12));
					INC(p, 4);  SYSTEM.PORTIN(p, SYSTEM.VAL(INTEGER, t));
					baseT := SYSTEM.VAL(SET, t) * {14,15} # {14,15};
					INC(p, 2);  SYSTEM.PORTIN(p, SYSTEM.VAL(INTEGER, t));
					irq := SHORT(SHORT(ASH(t, -12)));
					SYSTEM.CLI();  INC(p, 2);
					SYSTEM.PUT(SYSTEM.ADR(adr[0]), Swap(ReadEE2(p, 10)));
					SYSTEM.PUT(SYSTEM.ADR(adr[2]), Swap(ReadEE2(p, 11)));
					SYSTEM.PUT(SYSTEM.ADR(adr[4]), Swap(ReadEE2(p, 12)));
					SYSTEM.STI();
					p := 110H;  SYSTEM.PORTOUT(p, 0FFX)	(* activate the adapter *)
				ELSE
					INC(slot)
				END
			ELSE
				INC(slot)
			END
		END
	END;
	IF port = MAX(INTEGER) THEN	(* try isa *)
		SYSTEM.CLI();  id := 110H;   WriteID(id);	(* ch. 7 & A *)
		SYSTEM.PORTOUT(id, 0C0X);	(* reset to power-on state *)
		SYSTEM.STI();
		t := Kernel.GetTimer();  REPEAT UNTIL Kernel.GetTimer() - t > Kernel.TimeUnit DIV 10;	(* 100ms *)
		SYSTEM.CLI();
		WriteID(id);  SYSTEM.PORTOUT(id, 0D0X);	(* untag *)
		IF ReadEE(id, 7) = 6D50H THEN
			SYSTEM.PUT(SYSTEM.ADR(adr[0]), Swap(ReadEE(id, 10)));
			SYSTEM.PUT(SYSTEM.ADR(adr[2]), Swap(ReadEE(id, 11)));
			SYSTEM.PUT(SYSTEM.ADR(adr[4]), Swap(ReadEE(id, 12)));
			t := ReadEE(id, 8);  baseT := SYSTEM.VAL(SET, t) * {14,15} # {14,15};
			port := (SHORT(t) MOD 20H)*16 + 200H;
			irq := SHORT(SHORT(ASH(ReadEE(id, 9), -12)));
			t := ReadEE(id, 13);	(* software config (ignore) *)
			SYSTEM.PORTOUT(id, 0FFX)	(* activate the adapter *)
		END;
		SYSTEM.STI()
	END;
	IF port # MAX(INTEGER) THEN
		Kernel.WriteString("3Com509: ");  Kernel.WriteInt(irq, 1);  Kernel.WriteHex(port, 9);
		Kernel.WriteHex(ORD(adr[0]), -3);
		FOR p := 1 TO 5 DO Kernel.WriteChar(":");  Kernel.WriteHex(ORD(adr[p]), -2) END;
		IF baseT THEN Kernel.WriteString(" 10baseT") END;
		Kernel.WriteLn;
		SYSTEM.PORTOUT(port+14, SYSTEM.VAL(INTEGER, 0800H));	(* setup window *)
		SYSTEM.PORTOUT(port+4, 1X);	(* enable adapter *)
		p := port+14;  SYSTEM.CLI();
		SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, 5800H));	(* tx reset *)
		REPEAT
			SYSTEM.PORTIN(p, SYSTEM.VAL(INTEGER, s))	(* get status *)
		UNTIL ~(12 IN s);	(* wait until complete *)
		SYSTEM.STI();
		SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, 2800H));	(* rx reset *)
		SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, 7010H));	(* enable rxcomplete interrupt *)
		SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, 78FEH));	(* enable all status bits *)
		SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, 8005H));	(* receive mine+broadcast *)
		SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, 0802H));	(* station address window *)
		FOR q := port TO port+5 DO SYSTEM.PORTOUT(q, adr[q-port]) END;	(* set address *)
		SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, 0803H));	(* FIFO window *)
		SYSTEM.PORTIN(port+10, rxsize);	(* get buffer sizes *)
		SYSTEM.PORTIN(port+12, txsize);
		IF baseT THEN
			SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, 0804H));	(* diagnostics window *)
			SYSTEM.PORTIN(port+10, SYSTEM.VAL(INTEGER, s));	(* media status *)
			s := s + {6,7};  SYSTEM.PORTOUT(port+10, SYSTEM.VAL(INTEGER, s));	(* link beat & jabber enable *)
			SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, 0B800H));	(* stop internal transceiver *)
			Delay(800)	(* p. 6-11 *)
		ELSE
			SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, 1000H));	(* start internal transceiver *)
			Delay(800)	(* p. 6-4 *)
		END;
		SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, 0800H));	(* setup window *)
		SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, 4800H));	(* tx enable *)
		SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, 2000H));	(* rx enable *)
		SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, 0801H));	(* operating window *)
		Kernel.InstallIP(InterruptHandler, Kernel.IRQ+irq);
		Kernel.InstallTermHandler(Cleanup)
	ELSE (* port = MAX(INTEGER) will cause overflow in SendPacket *)
	END
END Init;

(** InstallDevice - Command to install ethernet device. *)

PROCEDURE InstallDevice*;
VAR i: LONGINT;
BEGIN
	NEW(dev);  dev.typ := NetBase.broadcast;  dev.state := NetBase.closed;
	dev.sndCnt := 0;  dev.recCnt := 0;
	SYSTEM.MOVE(SYSTEM.ADR(sendhdr.src[0]), SYSTEM.ADR(dev.hostAdr[0]), 6);
	FOR i := 0 TO 5 DO dev.castAdr[i] := 0FFX END;
	dev.Receive := Receive;  dev.Send := Send;  dev.Available := Avail;
	NetBase.InstallDevice(dev)
END InstallDevice;

BEGIN
	Ninerrors := 0;  Noverruns := 0;  Nrunts := 0;  Nbadframes := 0;  Nbadcrcs := 0;  Noversizes := 0;  Npops := 0;
	Nouterrors := 0;  Nresets := 0;  Nenables := 0;  Nsizeerrors := 0;  Nsplits := 0;  Nreceived := 0;  Ntimeouts := 0;
	Ndropped := 0;  Nints := 0;  Nsent := 0;
	bufhead := 0;  buftail := 0;  logging := FALSE;
	Init(sendhdr.src);  dev := NIL
END Net3Com509.

NetSystem.Stop
!Net3Com509.InstallDevice
NetSystem.Start
