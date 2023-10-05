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

MODULE ATADisk;	(* cp/pjm *)

(* 
Native Oberon ATA disk driver with Intel 82371SB (PIIX3) bus-mastering support (e.g. 440FX chipset).

Reference: T13/1153D Rev. 17, AT Attachment with Packet Interface Extension (ATA/ATAPI-4).

30.07.1998	cp	first version working
04.12.1998	pjm	added bus-mastering and restructured
23.03.1999	pjm	fixed chs parameters
24.03.1999	pjm	non-polling versions of PIO transfers
26.03.1999	pjm	LBA mode implemented
19.04.1999	pjm	Fixed for Compaq laptop
*)

IMPORT SYSTEM, Kernel, Disk, PCI;

CONST
	MaxControllers = 2;
	MaxDevices = 2*MaxControllers;
	MaxTries = 5;
	
	BMEnabled = TRUE;	(* check for bus-master chipset *)
	OverrideBIOS = TRUE;	(* enable bus-master even if BIOS did not *)
	PrimaryEnabled = TRUE;	(* disable for testing *)
	SecondaryEnabled = TRUE;	(* disable for testing *)
	TraceStatus = TRUE;	(* show error information *)
	TraceIdentify = TRUE;	(* show identify information *)
	SelectWait = FALSE;	(* wait before select *)
	
	SelectTimeout = 5000;	(* ms *)
	IOTimeout = 10000;	(* ms *)
	IdentifyTimeout = 500;	(* ms *)
	ResetTimeout = 1000;	(* ms *)
	
	MaxTransfer = 256;	(* <= 256 *)
	MaxPRD = 3;	(* <= 4 *)
	BS = 512;
	MinLBA = 8000000;	(* (> 0) if reported size larger than this, use LBA mode *)
	
	AtapiBit = 0;  RemovableBit = 1;  DMABit = 2;  LBABit = 3;
	ERR = 0;  DRQ = 3;  BSY = 7;
	
TYPE
	PRDT = POINTER TO RECORD
		prd: ARRAY MaxPRD OF RECORD	(* aligned on 32-byte boundary, see Intel 290550-002 sec. 2.7.3 *)
			adr, count: LONGINT
		END
	END;
	
	Controller = POINTER TO RECORD
		port, port2, irq, bmbase: LONGINT;
		interrupts, mark: LONGINT;
		prdt: PRDT;
		busy: BOOLEAN
	END;
	
	CHS = RECORD
		cyls, hds, spt: LONGINT
	END;
	
	ID = RECORD
		type: SET;
		ver: LONGINT;
		model: ARRAY 44 OF CHAR
	END;
	
	Device = POINTER TO RECORD
		controller: Controller;
		dev: LONGINT;
		type: SET;
		size: LONGINT;	(* total size *)
		chs: CHS;	(* for controller *)
		getpar: CHS;	(* for GetParams *)
		id: ID;
		init: BOOLEAN	(* initialized? *)
	END;
	
VAR
	controller: ARRAY MaxControllers OF Controller;
	device: ARRAY MaxDevices OF Device;
	irqs: SET;
	Nunknown, Nunexpected: LONGINT;	(* number of unknown/unexpected interrupts *)

PROCEDURE WriteStatus(msg: ARRAY OF CHAR;  port: LONGINT);
VAR ch: CHAR;  t: LONGINT;
BEGIN
	Kernel.WriteString(msg);
	SYSTEM.PORTIN(port+6, ch);
	Kernel.WriteChar(" ");  Kernel.WriteInt(ORD(ch) DIV 10H MOD 2, 1);
	SYSTEM.PORTIN(port+5, ch);  t := ORD(ch);
	SYSTEM.PORTIN(port+4, ch);  t := ASH(t, 8) + ORD(ch);
	Kernel.WriteChar(" ");  Kernel.WriteInt(t, 1);
	SYSTEM.PORTIN(port+6, ch);
	Kernel.WriteChar(" ");  Kernel.WriteInt(ORD(ch) MOD 10H, 1);
	SYSTEM.PORTIN(port+3, ch);
	Kernel.WriteChar(" ");  Kernel.WriteInt(ORD(ch), 1);
	SYSTEM.PORTIN(port+1, ch);
	Kernel.WriteHex(ORD(ch), -3);
	SYSTEM.PORTIN(port+7, ch);
	Kernel.WriteHex(ORD(ch), -3)
END WriteStatus;

(* Wait for specified value of controller status bits. *)

PROCEDURE WaitStatus(port: LONGINT;  mask, expect, bad: SET;  ms: LONGINT): BOOLEAN;
VAR t: Kernel.MilliTimer;  s: SET;  ch: CHAR;
BEGIN
	Kernel.SetTimer(t, ms);
	REPEAT
		SYSTEM.PORTIN(port+7, ch);  s := SYSTEM.VAL(SET, LONG(ORD(ch)))
	UNTIL (s * mask = expect) OR (s * bad # {}) OR Kernel.Expired(t);
	IF TraceStatus & ((s * bad # {}) OR (s * mask # expect)) THEN
		WriteStatus("Status", port);
		Kernel.WriteHex(SYSTEM.VAL(LONGINT, s), -3);
		Kernel.WriteHex(SYSTEM.VAL(LONGINT, mask), -3);
		Kernel.WriteHex(SYSTEM.VAL(LONGINT, expect), -3);
		Kernel.WriteHex(SYSTEM.VAL(LONGINT, bad), -3);
		Kernel.WriteChar(" ");  Kernel.WriteInt(ms, 1);
		Kernel.WriteLn
	END;
	RETURN (s * mask = expect) & (s * bad = {})
END WaitStatus;

(* Wait for specified value of controller status bits using the alternate status bits (don't clear interrupts). *)

PROCEDURE WaitAltStatus(port, port2: LONGINT;  mask, expect, bad: SET;  ms: LONGINT): BOOLEAN;
VAR t: Kernel.MilliTimer;  s: SET;  ch: CHAR;
BEGIN
	Kernel.SetTimer(t, ms);
	REPEAT
		SYSTEM.PORTIN(port2, ch);  s := SYSTEM.VAL(SET, LONG(ORD(ch)));
	UNTIL (s * mask = expect) OR (s * bad # {}) OR Kernel.Expired(t);
	IF TraceStatus & ((s * bad # {}) OR (s * mask # expect)) THEN
		Kernel.WriteString("ATADisk: s");  Kernel.WriteHex(SYSTEM.VAL(LONGINT, s), -3);
		Kernel.WriteString(", mask");  Kernel.WriteHex(SYSTEM.VAL(LONGINT, mask), -3);
		Kernel.WriteString(", exp");  Kernel.WriteHex(SYSTEM.VAL(LONGINT, expect), -3);
		Kernel.WriteString(", bad");  Kernel.WriteHex(SYSTEM.VAL(LONGINT, bad), -3);
		Kernel.WriteString(", time ");  Kernel.WriteInt(ms, 1);
		Kernel.WriteLn
	END;
	RETURN (s * mask = expect) & (s * bad = {})
END WaitAltStatus;

(* NanoDelay - Delay at least ns nanoseconds. *)

PROCEDURE NanoDelay(ns: LONGINT);
BEGIN
	ns := ns DIV 2;	(* 400MHz clock => 2.5ns cycle *)
	WHILE ns > 0 DO DEC(ns) END
END NanoDelay;

(* Select device for next command (0 or 1).  Section 9.6. *)

PROCEDURE SelectDevice(port, d, timeout: LONGINT): LONGINT;
VAR res: LONGINT;
BEGIN
	IF ~SelectWait OR WaitStatus(port, {DRQ,BSY}, {}, {}, timeout) THEN
		SYSTEM.PORTOUT(port+6, CHR(ASH(d, 4)));
		NanoDelay(400);
		IF WaitStatus(port, {DRQ,BSY}, {}, {}, timeout) THEN res := 0 ELSE res := 2 END
	ELSE
		res := 1
	END;
	RETURN res
END SelectDevice;

(* Issue a command to the controller. *)

PROCEDURE Command(d: Device;  cmd: CHAR;  lba, num: LONGINT);
VAR port, sector, cylinder, head, x: LONGINT;
BEGIN
	port := d.controller.port;
	ASSERT((num > 0) & (num <= 100H));
	SYSTEM.PORTOUT(port+2, CHR(num MOD 100H));	(* 0 means 256 *)
	IF LBABit IN d.id.type THEN
		ASSERT((lba >= 0) & (lba < 10000000H));
		SYSTEM.PORTOUT(port+3, CHR(lba MOD 100H));
		SYSTEM.PORTOUT(port+4, CHR(ASH(lba, -8) MOD 100H));
		SYSTEM.PORTOUT(port+5, CHR(ASH(lba, -16) MOD 100H));
		SYSTEM.PORTOUT(port+6, CHR((40H + ASH(d.dev, 4) + ASH(lba, -24) MOD 10H)))
	ELSE
		sector := lba MOD d.chs.spt + 1;  x := lba DIV d.chs.spt;
		head := x MOD d.chs.hds;  cylinder := x DIV d.chs.hds;
		ASSERT((sector < 100H) & (cylinder < 10000H) & (head < 10H));
		SYSTEM.PORTOUT(port+3, CHR(sector));
		SYSTEM.PORTOUT(port+4, CHR(cylinder MOD 100H));
		SYSTEM.PORTOUT(port+5, CHR(cylinder DIV 100H));
		SYSTEM.PORTOUT(port+6, CHR((ASH(d.dev, 4) + head)))
	END;
	SYSTEM.PORTOUT(port+7, cmd)
END Command;

(* Interrupt handler (needed for DMA operation). *)

PROCEDURE InterruptHandler;
VAR i, u, int: LONGINT;  ctrl: Controller;
BEGIN
	SYSTEM.STI();
	SYSTEM.GETREG(SYSTEM.EBP, int);  SYSTEM.GET(int+40, int);
	DEC(int, Kernel.IRQ);  u := 1;
	FOR i := 0 TO MaxControllers-1 DO
		ctrl := controller[i];
		IF (ctrl # NIL) & (ctrl.irq = int) THEN u := 0;  INC(ctrl.interrupts) END
	END;
	SYSTEM.CLI();
	INC(Nunknown, u)
END InterruptHandler;

(* Wait for an interrupt to occur. *)

PROCEDURE WaitInterrupt(c: Controller;  ms: LONGINT): BOOLEAN;
VAR t: Kernel.MilliTimer;  ok: BOOLEAN;
BEGIN
	Kernel.SetTimer(t, ms);
	REPEAT ok := c.interrupts # c.mark UNTIL ok OR Kernel.Expired(t);
	c.mark := c.interrupts;
	RETURN ok
END WaitInterrupt;

(* Start interrupt waiting period. *)

PROCEDURE StartInterrupt(c: Controller);
BEGIN
	INC(Nunexpected, c.interrupts - c.mark);
	c.mark := c.interrupts
END StartInterrupt;

(* Block port input instruction. *)

PROCEDURE -RepInWord(port, bufAdr, len: LONGINT);
CODE {SYSTEM.i386}
	POP ECX
	POP EDI
	POP EDX
	CLD
	REP INSW
END RepInWord;

(* Block port out instruction. *)

PROCEDURE -RepOutWord(port, bufAdr, len: LONGINT);
CODE {SYSTEM.i386}
	POP ECX
	POP ESI
	POP EDX
	CLD
	REP OUTSW
END RepOutWord;

(* Read blocks using PIO protocol. *)

PROCEDURE ReadPIO(d: Device;  lba, num, bufAdr: LONGINT): LONGINT;
VAR port, port2, res: LONGINT;  x: CHAR;  s: SET;  c: Controller;
BEGIN
	res := 0;  c := d.controller;  port := c.port;  port2 := c.port2;
	StartInterrupt(c);
	Command(d, 20X, lba, num);	(* read sectors *)
	REPEAT
		IF WaitInterrupt(c, IOTimeout) THEN
			SYSTEM.PORTIN(port+7, x);  s := SYSTEM.VAL(SET, LONG(ORD(x)));
			IF ~(ERR IN s) THEN
				RepInWord(port, bufAdr, BS DIV 2);
				INC(bufAdr, BS);  DEC(num)
			ELSE
				res := 20
			END
		ELSE
			res := 19
		END
	UNTIL (num = 0) OR (res # 0);
	SYSTEM.PORTIN(port2, x);	(* according to spec *)
	SYSTEM.PORTIN(port+7, x);  s := SYSTEM.VAL(SET, LONG(ORD(x)));
	IF (res = 0) & (ERR IN s) THEN res := 21 END;
	IF TraceStatus & (res # 0) THEN WriteStatus("ReadPIO", port);  Kernel.WriteLn END;
	RETURN res
END ReadPIO;

(* Write blocks using PIO protocol. *)

PROCEDURE WritePIO(d: Device;  lba, num, bufAdr: LONGINT): LONGINT;
VAR port, port2, res: LONGINT;  x: CHAR;  s: SET;  c: Controller;
BEGIN
	res := 0;  c := d.controller;  port := c.port;  port2 := c.port2;
	StartInterrupt(c);
	Command(d, 30X, lba, num);	(* write sectors *)
	IF WaitAltStatus(port, port2, {DRQ,BSY}, {DRQ}, {ERR}, IOTimeout) THEN
		REPEAT
			RepOutWord(port, bufAdr, BS DIV 2);
			INC(bufAdr, BS);  DEC(num);
			IF WaitInterrupt(c, IOTimeout) THEN
				SYSTEM.PORTIN(port+7, x);  s := SYSTEM.VAL(SET, LONG(ORD(x)));
				IF ERR IN s THEN res := 24 END
			ELSE
				res := 23
			END
		UNTIL (num = 0) OR (res # 0)
	ELSE
		res := 22
	END;
	IF res # 0 THEN
		IF TraceStatus THEN WriteStatus("WritePIO", port);  Kernel.WriteLn END;
		SYSTEM.PORTIN(port+7, x)	(* clear interrupt *)
	END;
	RETURN res
END WritePIO;

(* Transfer blocks using DMA. *)

PROCEDURE TransferDMA(d: Device;  read: BOOLEAN;  lba, num, bufAdr: LONGINT): LONGINT;
VAR port, res, bmbase, i, size, left: LONGINT;  x: CHAR;  s: SET;  c: Controller;
BEGIN
	ASSERT(~ODD(bufAdr));	(* transfer must be word-aligned *)
	ASSERT((num > 0) & (num <= MaxTransfer));
	res := 0;  c := d.controller;
	port := c.port;  bmbase := c.bmbase;  ASSERT(bmbase # 0);
		(* init prdt *)
	i := 0;  size := num*BS;
	REPEAT
		left := 10000H - bufAdr MOD 10000H;	(* bytes left until next 64k boundary *)
		IF left > size THEN left := size END;
		c.prdt.prd[i].adr := bufAdr;  c.prdt.prd[i].count := left;
		INC(bufAdr, left);  DEC(size, left);  INC(i)
	UNTIL size = 0;
	INCL(SYSTEM.VAL(SET, c.prdt.prd[i-1].count), 31);	(* end marker *)
		(* init dma *)
	SYSTEM.PORTOUT(bmbase+4, SYSTEM.ADR(c.prdt.prd[0]));
	IF read THEN s := {3} ELSE s := {} END;
	SYSTEM.PORTOUT(bmbase, SYSTEM.VAL(CHAR, s));	(* set direction *)
	SYSTEM.PORTIN(bmbase+2, x);
	s := SYSTEM.VAL(SET, LONG(ORD(x)));
	SYSTEM.PORTOUT(bmbase+2, CHR(SYSTEM.VAL(LONGINT, s + {1,2})));	(* clear error, interrupt by writing *)
		(* init transfer *)
	StartInterrupt(c);
	IF read THEN x := 0C8X ELSE x := 0CAX END;	(* read dma or write dma *)
	Command(d, x, lba, num);
	SYSTEM.PORTIN(bmbase, x);
	s := SYSTEM.VAL(SET, LONG(ORD(x)));
	SYSTEM.PORTOUT(bmbase, CHR(SYSTEM.VAL(LONGINT, s + {0})));	(* start bm *)
	IF WaitInterrupt(c, IOTimeout) THEN
		SYSTEM.PORTIN(bmbase+2, x);	(* check dma status *)
		s := SYSTEM.VAL(SET, LONG(ORD(x)));
		IF 1 IN s THEN res := 8 END
	ELSE
		res := 7
	END;
	SYSTEM.PORTIN(bmbase, x);
	s := SYSTEM.VAL(SET, LONG(ORD(x)));
	SYSTEM.PORTOUT(bmbase, CHR(SYSTEM.VAL(LONGINT, s - {0})));	(* stop bm *)
	SYSTEM.PORTIN(port+7, x);	(* clear interrupt *)
	s := SYSTEM.VAL(SET, LONG(ORD(x)));
	IF (res = 0) & (ERR IN s) THEN res := 9 END;
	RETURN res
END TransferDMA;

(* Initialize/Reset the selected device. *)

PROCEDURE InitDevice(port, port2, dev: LONGINT;  type: SET;  chs: CHS): LONGINT;
VAR x: CHAR;  sector, head, res: LONGINT;
BEGIN
	IF AtapiBit IN type THEN
		SYSTEM.PORTOUT(port+6, CHR((ASH(dev, 4) + (head-1))));
		SYSTEM.PORTOUT(port+7, 8X);	(* reset packet device *)
		SYSTEM.PORTIN(port2, x);
		IF ~WaitStatus(port, {BSY}, {}, {}, ResetTimeout) THEN res := 16 END
	ELSE
		sector := chs.spt;
		head := chs.hds;
		SYSTEM.PORTOUT(port+2, CHR(sector));
		SYSTEM.PORTOUT(port+3, 0X);
		SYSTEM.PORTOUT(port+4, 0X);
		SYSTEM.PORTOUT(port+5, 0X);
		SYSTEM.PORTOUT(port+6, CHR((ASH(dev, 4) + (head-1) MOD 10H)));
		SYSTEM.PORTOUT(port+7, 091X);	(* initialize device parameters *)
		SYSTEM.PORTIN(port2, x);
		IF ~WaitStatus(port, {BSY}, {}, {ERR}, ResetTimeout) THEN
			IF LBABit IN type THEN
				Kernel.WriteString("ATADisk: using LBA mode, init dev param ignored");
				Kernel.WriteLn
			ELSE
				res := 17
			END
		END
	END;
	RETURN res
END InitDevice;

(* Convert a string to an integer. *)

PROCEDURE StrToInt(VAR i: LONGINT;  VAR s: ARRAY OF CHAR): LONGINT;
VAR vd, vh, sgn, d: LONGINT;  hex: BOOLEAN;
BEGIN
	vd := 0;  vh := 0;  hex := FALSE;
	IF s[i] = "-" THEN sgn := -1; INC(i) ELSE sgn := 1 END;
	LOOP
		IF (s[i] >= "0") & (s[i] <= "9") THEN d := ORD(s[i])-ORD("0")
		ELSIF (CAP(s[i]) >= "A") & (CAP(s[i]) <= "F") THEN d := ORD(CAP(s[i]))-ORD("A")+10; hex := TRUE
		ELSE EXIT
		END;
		vd := 10*vd + d;  vh := 16*vh + d;
		INC(i)
	END;
	IF CAP(s[i]) = "H" THEN hex := TRUE; INC(i) END;	(* optional H *)
	IF hex THEN vd := vh END;
	RETURN sgn * vd
END StrToInt;

(* Initialize controller parameters. *)

PROCEDURE ParseControllerConfig(num, dirq, dc: LONGINT);
VAR s: ARRAY 32 OF CHAR;  id: ARRAY 8 OF CHAR;  p, c, r, irq: LONGINT;
BEGIN
	id := "IDE#";  id[3] := CHR(ORD("0") + num);
	Kernel.GetConfig(id, s);
	IF (num = 0) & (s = "") THEN Kernel.GetConfig("IDE", s) END;
	IF s # "" THEN
		p := 0;  c := 0;  r := 0;
		irq := StrToInt(p, s);
		IF (irq # 0) & (s[p] = ",") THEN
			INC(p);  c := StrToInt(p, s);
			IF s[p] = "," THEN
				INC(p);  r := StrToInt(p, s)
			END;
			IF c = 0 THEN c := dc END;
			IF (r = 0) & (c > 0) THEN r := c + 206H END
		END
	ELSE
		irq := dirq;  c := dc;  r := c + 206H
	END;
	IF c > 0 THEN
		NEW(controller[num]);
		controller[num].port := c;  controller[num].port2 := r;  controller[num].irq := irq;
		controller[num].bmbase := 0	(* BM disabled *)
	END
END ParseControllerConfig;

(* Get hard disk parameters. *)

PROCEDURE GetPar(p: LONGINT;  ofs: LONGINT): LONGINT;
VAR x: CHAR;
BEGIN
	SYSTEM.GET(p+12+ofs, x);
	RETURN ORD(x)
END GetPar;

(* Parse hard disk parameters of first two drives from BIOS. *)

PROCEDURE GetKernelCHS(d: LONGINT;  VAR chs1: CHS);
VAR p, t, i : LONGINT;  chs: CHS;
BEGIN
	p := Kernel.bt;  i := 0;
	LOOP
		SYSTEM.GET(p, t);
		IF t = -1 THEN EXIT	(* end *)
		ELSIF t = 5 THEN	(* HD params *)
			IF i = d THEN
				chs.cyls := GetPar(p, 0) + 100H*GetPar(p, 1);
				chs.hds := GetPar(p, 2);  chs.spt := GetPar(p, 14);
				IF chs.cyls * chs.hds * chs.spt > 0 THEN chs1 := chs END
			END;
			INC(i)
		END;
		SYSTEM.GET(p+4, t);  INC(p, t)
	END
END GetKernelCHS;

(* Convert an ATA identify string to a readable format. *)

PROCEDURE GetATAString(VAR buf: ARRAY OF INTEGER;  from, to: LONGINT;  VAR s: ARRAY OF CHAR);
VAR i, j: LONGINT;
BEGIN
	FOR i := from TO to DO
		s[2*(i-from)] := CHR(buf[i] DIV 100H MOD 100H);
		s[2*(i-from)+1] := CHR(buf[i] MOD 100H)
	END;
	s[2*(to-from+1)] := 0X;
	i := 0;  j := 0;
	WHILE s[i] # 0X DO
		IF (s[i] >= 20X) & (s[i] <= 7EX) THEN s[j] := s[i];  INC(j) END;
		INC(i);
		IF (j # 0) & (s[j-1] = 20X) THEN
			WHILE s[i] = 20X DO INC(i) END
		END
	END;
	IF (j # 0) & (s[j-1] = 20X) THEN DEC(j) END;
	s[j] := 0X
END GetATAString;

(* Identify an Atapi packet device. *)

PROCEDURE IdentifyAtapi(port, port2: LONGINT;  VAR id: ID): LONGINT;
VAR res: LONGINT;  x: CHAR;  buf: ARRAY BS DIV 2 OF INTEGER;
BEGIN
	SYSTEM.PORTOUT(port+7, 0A1X);	(* identify ATAPI device *)
	SYSTEM.PORTIN(port2, x);	(* ensure status ok *)
	IF WaitStatus(port, {BSY}, {}, {}, IdentifyTimeout) THEN
		INCL(id.type, AtapiBit);
		RepInWord(port, SYSTEM.ADR(buf[0]), BS DIV 2);
		IF 7 IN SYSTEM.VAL(SET, LONG(buf[0])) THEN INCL(id.type, RemovableBit) END;
		IF 8 IN SYSTEM.VAL(SET, LONG(buf[49])) THEN INCL(id.type, DMABit) END;
		GetATAString(buf, 27, 46, id.model);
		IF (buf[80] # -1) & (buf[81] # -1) THEN
			id.ver := ASH(LONG(buf[80]) MOD 10000H, 16) + LONG(buf[81]) MOD 10000H
		END;
		res := 0
	ELSE
		res := 12
	END;
	RETURN res
END IdentifyAtapi;

(* Identify an ATA device. *)

PROCEDURE IdentifyATA(port: LONGINT;  VAR chs: CHS;  VAR size: LONGINT;  VAR id: ID): LONGINT;
VAR res, size1: LONGINT;  buf: ARRAY BS DIV 2 OF INTEGER;
BEGIN
	RepInWord(port, SYSTEM.ADR(buf[0]), BS DIV 2);
	(*Kernel.WriteMemory(SYSTEM.ADR(buf[0]), BS);*)
	chs.cyls := LONG(buf[1]) MOD 10000H;
	chs.hds := LONG(buf[3]) MOD 10000H;
	chs.spt := LONG(buf[6]) MOD 10000H;
	size := ASH(LONG(buf[61]) MOD 10000H, 16) + LONG(buf[60]) MOD 10000H;
	IF size >= MinLBA THEN INCL(id.type, LBABit) END;
	size1 := chs.cyls * chs.hds * chs.spt;
	IF size < size1 THEN size := size1 END;
	IF SYSTEM.VAL(SET, LONG(buf[0])) * {6,7} = {7} THEN INCL(id.type, RemovableBit) END;
	INCL(id.type, DMABit);	(* DMA support mandatory in ATA/ATAPI-4 *)
	GetATAString(buf, 27, 46, id.model);
	IF (buf[80] # -1) & (buf[81] # -1) THEN
		id.ver := ASH(LONG(buf[80]) MOD 10000H, 16) + LONG(buf[81]) MOD 10000H
	END;
	IF (chs.hds <= 16) & (chs.spt <= 255) THEN res := 0 ELSE res := 25 END;
	RETURN res
END IdentifyATA;

(* Identify a device. *)

PROCEDURE IdentifyDevice(controller: Controller;  dev: LONGINT;  VAR chs: CHS;  VAR size: LONGINT;  VAR id: ID): LONGINT;
VAR res, port, port2: LONGINT;  x: CHAR;  t: Kernel.MilliTimer;
BEGIN
	id.type := {};  id.ver := 0;  chs.cyls := 0;  chs.hds := 0;  chs.spt := 0;  size := 0;
	port := controller.port;  port2 := controller.port2;
	IF port # 0 THEN
		Kernel.SetTimer(t, 50);  REPEAT UNTIL Kernel.Expired(t);
		res := SelectDevice(port, dev, IdentifyTimeout);
		IF res = 0 THEN
			StartInterrupt(controller);
			SYSTEM.PORTOUT(port+7, 0ECX);	(* identify device *)
			IF WaitInterrupt(controller, IdentifyTimeout) THEN
				SYSTEM.PORTIN(port+5, x);	(* signature byte *)
				IF x = 0EBX THEN
					res := IdentifyAtapi(port, port2, id)
				ELSE
					res := IdentifyATA(port, chs, size, id)
				END
			ELSE
				res := 14
			END
		END;
		Kernel.SetTimer(t, 50);  REPEAT UNTIL Kernel.Expired(t);
		SYSTEM.PORTOUT(port+6, 0X);	(* select device 0 again *)
		NanoDelay(400)
	ELSE
		res := 15
	END;
	RETURN res
END IdentifyDevice;

(* Clean up unloaded module. *)

PROCEDURE Cleanup;
VAR i: LONGINT;
BEGIN
	FOR i := 0 TO 15 DO
		IF i IN irqs THEN
			EXCL(irqs, i);
			Kernel.RemoveIP(InterruptHandler, SHORT(Kernel.IRQ + i))
		END
	END
END Cleanup;

(* Initialization. *)

PROCEDURE IdentifyControllers;
VAR i: LONGINT;
BEGIN
	FOR i := 0 TO MaxControllers-1 DO controller[i] := NIL END;
	IF PrimaryEnabled THEN ParseControllerConfig(0, 14, 01F0H) END;
	IF SecondaryEnabled THEN ParseControllerConfig(1, 15, 0170H) END;
	IF MaxControllers > 2 THEN	(* compile-time expression *)
		FOR i := 2 TO MaxControllers-1 DO ParseControllerConfig(i, 0, 0) END
	END
END IdentifyControllers;

PROCEDURE IdentifyDevices;
VAR
	p, q, a, n, res, size: LONGINT;  ctrl: Controller;  dev: Device;  chs: CHS;  id: ID;
	atapi, ata: ARRAY MaxDevices OF Device;
BEGIN
		(* identify all devices *)
	a := 0;  n := 0;
	FOR p := 0 TO MaxDevices-1 DO
		ctrl := controller[p DIV 2];
		IF ctrl # NIL THEN
			res := IdentifyDevice(ctrl, p MOD 2, chs, size, id);
			IF res = 0 THEN
				NEW(dev);
				dev.controller := ctrl;  dev.dev := p MOD 2;  dev.init := FALSE;
				dev.id := id;  dev.size := size;  dev.chs := chs;  dev.getpar := dev.chs;
				IF AtapiBit IN id.type THEN
					atapi[a] := dev;  INC(a)
				ELSE
					IF p < 2 THEN GetKernelCHS(p, dev.getpar) END;	(* override CHS *)
					IF dev.size > 16383*16*63 THEN
						dev.getpar.cyls := dev.size DIV (dev.getpar.hds * dev.getpar.spt)
					END;
					ata[n] := dev;  INC(n)
				END
			ELSE (* skip *)
			END;
			IF TraceIdentify THEN
				Kernel.WriteString("IDE");  Kernel.WriteInt(p DIV 2, 1);
				Kernel.WriteChar(".");  Kernel.WriteInt(p MOD 2, 1);
				Kernel.WriteString(": Identify = ");  Kernel.WriteInt(res, 1);
				Kernel.WriteLn
			END
		END
	END;
		(* merge tables *)
	p := 0;  WHILE p # n DO device[p] := ata[p];  INC(p) END;
	q := 0;  WHILE q # a DO device[p] := atapi[q];  INC(p);  INC(q) END;
	WHILE p # MaxDevices DO device[p] := NIL;  INC(p) END
END IdentifyDevices;

PROCEDURE ShowCHS(chs: CHS);
BEGIN
	Kernel.WriteInt(chs.cyls, 1);
	Kernel.WriteChar("*");
	Kernel.WriteInt(chs.hds, 1);
	Kernel.WriteChar("*");
	Kernel.WriteInt(chs.spt, 1)
END ShowCHS;

PROCEDURE ShowDevices;
VAR i, j: LONGINT;  dev: Device;
BEGIN
	FOR i := 0 TO MaxDevices-1 DO
		dev := device[i];
		IF dev # NIL THEN
			Kernel.WriteString("Disk");  Kernel.WriteInt(i, 1);
			j := 0;  WHILE controller[j] # dev.controller DO INC(j) END;
			Kernel.WriteString(": IDE");  Kernel.WriteInt(j, 1);
			Kernel.WriteChar(".");  Kernel.WriteInt(dev.dev, 1);
			IF AtapiBit IN dev.id.type  THEN
				Kernel.WriteString(", packet")
			ELSE
				Kernel.WriteString(", ");  Kernel.WriteInt(dev.size DIV 2048, 1);  Kernel.WriteString("Mb");
				Kernel.WriteString(", ");  ShowCHS(dev.chs);
				IF (dev.getpar.cyls # dev.chs.cyls) OR (dev.getpar.hds # dev.chs.hds) OR (dev.getpar.spt # dev.chs.spt) THEN
					Kernel.WriteString(", (");  ShowCHS(dev.getpar);  Kernel.WriteChar(")")
				END
			END;
			IF RemovableBit IN dev.id.type THEN Kernel.WriteString(", removable") END;
			IF ~(DMABit IN dev.id.type) THEN Kernel.WriteString(", no DMA") END;
			IF LBABit IN dev.id.type THEN Kernel.WriteString(", LBA") END;
			Kernel.WriteString(", ");  Kernel.WriteString(dev.id.model);
			IF dev.id.ver # 0 THEN
				Kernel.WriteString(", ver ");
				j := 30;  WHILE (j # 16) & ~ODD(ASH(dev.id.ver, -j)) DO DEC(j) END;
				Kernel.WriteInt(j-16, 1);  Kernel.WriteChar(".");
				Kernel.WriteInt(dev.id.ver MOD 10000H, 1)
			END;
			Kernel.WriteLn
		END
	END
END ShowDevices;

PROCEDURE InitControllers;
VAR i: LONGINT;  ctrl: Controller;  t: Kernel.MilliTimer;
BEGIN
	FOR i := 0 TO MaxControllers-1 DO
		ctrl := controller[i];
		Kernel.WriteString("IDE");  Kernel.WriteInt(i, 1);  Kernel.WriteString(": ");
		IF ctrl # NIL THEN
			Kernel.WriteInt(ctrl.irq, 1);  Kernel.WriteHex(ctrl.port, 9);  Kernel.WriteHex(ctrl.port2, 9);
			Kernel.WriteChar(" ");
			IF ~(ctrl.irq IN irqs) THEN
				Kernel.InstallIP(InterruptHandler, SHORT(Kernel.IRQ + ctrl.irq));
				INCL(irqs, ctrl.irq)
			END;
			SYSTEM.PORTOUT(ctrl.port2, 4X);	(* reset controller *)
			Kernel.SetTimer(t, 1);  REPEAT UNTIL Kernel.Expired(t);	(* wait > 4.8us *)
			SYSTEM.PORTOUT(ctrl.port2, 8X);
			IF WaitStatus(ctrl.port, {BSY}, {}, {}, ResetTimeout) THEN
				Kernel.WriteString("reset ok");  Kernel.WriteLn
			ELSE
				controller[i] := NIL;
				IF ~TraceStatus THEN
					Kernel.WriteString("reset failed");  Kernel.WriteLn
				END
			END
		ELSE
			Kernel.WriteString("disabled");  Kernel.WriteLn
		END
	END
END InitControllers;

PROCEDURE InitBusMaster;
VAR bus, dev, fkt, i, bmbase, iobase: LONGINT;  s: SET;  str: ARRAY 8 OF CHAR;

	PROCEDURE FindDevice(id, vendor: LONGINT): BOOLEAN;	(* set bus, dev, fkt as side-effect *)
	VAR res: LONGINT;
	BEGIN
		res := PCI.FindPCIDevice(id, vendor, 0, bus, dev, fkt);
		RETURN res = PCI.Done
	END FindDevice;
	
	PROCEDURE ReadDWord(adr: LONGINT;  VAR s: SET);
	VAR res: LONGINT;
	BEGIN
		res := PCI.ReadConfigDword(bus, dev, fkt, adr, SYSTEM.VAL(LONGINT, s));
		IF res # PCI.Done THEN s := {} END
	END ReadDWord;

	PROCEDURE WriteByte(adr: LONGINT;  s: SET);
	VAR res: LONGINT;
	BEGIN
		res := PCI.WriteConfigByte(bus, dev, fkt, adr, SYSTEM.VAL(LONGINT, s));
		(* ignore res *)
	END WriteByte;

BEGIN
	IF BMEnabled THEN
		Kernel.GetConfig("ATABM", str);
		IF str[0] # "0" THEN
			IF FindDevice(7010H, 8086H) OR FindDevice(7111H, 8086H) THEN
				ReadDWord(PCI.CmdReg, s);
				IF OverrideBIOS & (s * {0,2} = {0}) THEN	(* override BIOS-disabled BM setting *)
					Kernel.WriteString("Overriding BIOS bus-master setting");  Kernel.WriteLn;
					WriteByte(PCI.CmdReg, s + {2});
					ReadDWord(PCI.CmdReg, s)
				END;
				IF s * {0,2} = {0,2} THEN	(* ports & BM enabled *)
					ReadDWord(20H, s);	(* BMIBA *)
					bmbase := SYSTEM.VAL(LONGINT, s * {4..15});
					IF bmbase # 0 THEN
						ReadDWord(40H, s);	(* IDETIM *)
						FOR i := 0 TO 1 DO	(* primary and secondary controller *)
							IF i = 0 THEN iobase := 1F0H ELSE iobase := 170H END;	(* standard ports *)
							IF (15 IN s) & (controller[i] # NIL) & (controller[i].port = iobase) THEN
								Kernel.WriteString("IDE");  Kernel.WriteInt(i, 1);
								Kernel.WriteString(": Bus-master enabled");  Kernel.WriteLn;
								controller[i].bmbase := bmbase + 8*i;
								NEW(controller[i].prdt)
							END;
							s := SYSTEM.LSH(s, -16)
						END
					ELSE
						Kernel.WriteString("Bus-master ports disabled (BIOS)");  Kernel.WriteLn
					END
				ELSE
					Kernel.WriteString("Bus-master disabled");  Kernel.WriteLn
				END
			ELSE
				Kernel.WriteString("Bus-master chipset not detected");  Kernel.WriteLn
			END
		END
	END
END InitBusMaster;

(* Report a disk error. *)

PROCEDURE Report(err: LONGINT);
CODE {SYSTEM.i386}
	MOV EAX, err[EBP]
	PUSH 17	(* Disk error *)
	INT 3
END Report;

(* Main transfer procedure. *)

PROCEDURE TransferBlocks(read: BOOLEAN;  drive, lba, num, bufAdr: LONGINT);
VAR ctrl: Controller;  dev: Device;  res, num1, try: LONGINT;
BEGIN
	dev := device[drive];
	IF dev # NIL THEN
		IF (lba >= 0) & (num >= 0) & (lba < dev.size) & (lba+num <= dev.size) THEN
			ctrl := dev.controller;
			SYSTEM.CLI();
			IF ctrl.busy THEN SYSTEM.STI();  Report(10) END;
			ctrl.busy := TRUE;
			SYSTEM.STI();
			res := SelectDevice(ctrl.port, dev.dev, SelectTimeout);
			IF (res = 0) & ~dev.init THEN	(* initialize *)
				res := InitDevice(ctrl.port, ctrl.port2, dev.dev, dev.id.type, dev.chs);
				dev.init := res = 0
			END;
			WHILE (res = 0) & (num > 0) DO
				try := MaxTries;  num1 := MaxTransfer;
				IF num1 > num THEN num1 := num END;
				REPEAT
					IF (ctrl.bmbase # 0) & ~ODD(bufAdr) THEN
						res := TransferDMA(dev, read, lba, num1, bufAdr)
					ELSE
						IF read THEN res := ReadPIO(dev, lba, num1, bufAdr)
						ELSE res := WritePIO(dev, lba, num1, bufAdr)
						END
					END;
					DEC(try)
				UNTIL (res = 0) OR (try = 0);
				INC(lba, num1);  DEC(num, num1);  INC(bufAdr, BS*num1)
			END;
			ctrl.busy := FALSE
		ELSE
			res := 26
		END
	ELSE
		res := 11
	END;
	IF res # 0 THEN Report(res) END
END TransferBlocks;

(* Disk.GetBlocks implementation. *)

PROCEDURE GetBlocks*(drive, start, num: LONGINT;  VAR buf: ARRAY OF SYSTEM.BYTE;  ofs: LONGINT);
BEGIN
	TransferBlocks(TRUE, drive, start, num, SYSTEM.ADR(buf[ofs]))
END GetBlocks;

(* Disk.PutBlocks implementation. *)

PROCEDURE PutBlocks*(drive, start, num: LONGINT;  VAR buf: ARRAY OF SYSTEM.BYTE;  ofs: LONGINT);
BEGIN
	TransferBlocks(FALSE, drive, start, num, SYSTEM.ADR(buf[ofs]))
END PutBlocks;

(* Disk.GetParams implementation. *)

PROCEDURE GetParams*(drive: LONGINT;  VAR cyls, hds, spt: LONGINT);
VAR dev: Device;
BEGIN
	cyls := 0;  hds := 0;  spt := 0;
	IF drive < MaxDevices THEN
		dev := device[drive];
		IF dev # NIL THEN
			cyls := dev.getpar.cyls;  hds := dev.getpar.hds;  spt := dev.getpar.spt
		END
	END
END GetParams;

(* Install the Disk upcalls. *)

PROCEDURE Install*;
BEGIN
	Disk.GetBlocks := GetBlocks;
	Disk.PutBlocks := PutBlocks;
	Disk.GetParams := GetParams
END Install;

BEGIN
	Kernel.WriteString("ATADisk 0.10 by Christian Plattner and Pieter Muller");  Kernel.WriteLn;
	irqs := {};  Kernel.InstallTermHandler(Cleanup);
	IdentifyControllers;
	InitControllers;
	IdentifyDevices;
	ShowDevices;
	(*InitControllers*);	(* re-initialize controllers after identify *)
	InitBusMaster;
	Install
END ATADisk.

Error codes:
1	device select failed before issueing
2	device select failed after issueing
3	pio read failed
4	pio read error
5	pio write failed
6	pio write error
7	dma transfer timeout
8	dma transfer failed
9	dma transfer error
10	controller re-entered
11	device does not exist
12	identify atapi failed
13	
14	identify failed
15	bad controller port
16	atapi reset failed
17	ata set parameters failed
18	
19	pio read timeout
20	pio read error
21	pio read error
22	pio write error
23	pio write timeout
24	pio write error
25	identify ata geometry bad
26	transfer out of range

ATADisk.Install

ATAErrors.Text

Backup.WriteFiles ATADisk.Mod ~  Backup.WriteFiles ATADisk.Obf ~  Backup.ReadFiles ATADisk.Obf ~

to do:
o check selected device
o atapi identify with interrupt
