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

MODULE IDEDisk;	(** non-portable *)	(* pjm *)

(* IDE Disk driver for Native Oberon
	References:  1. pmuller, Hybrid Oberon and Gneiss microkernel code *)

IMPORT SYSTEM, Kernel, Disk;

CONST
		(* Values for Params.op *)
	Read = 0;  Write = 1;

	BS = 512;	(* disk block size *)
	
		(* Values for ControllerDesc.state (<32)*)
	Initial0 = 0;  Ready0 = 1;  Busy0 = 2;  Reset0 = 3;  Reset1 = 4;
	Reset2 = 5;  Reset3 = 6;

		(* Timeout values in ms *)
	IOTime = 8000;	(* basic time allowed for an IO operation *)
	IOTimex = 60;	(* time extra per sector for IO *)

	MaxDrives = 2;

TYPE
	DeviceDesc = RECORD
		cylinders, cylinders0: LONGINT;	(* number of cylinders *)
		heads, heads0: LONGINT;	(* number of heads *)
		sectrack: LONGINT;	(* sectors/track *)
		writePreComp: LONGINT
	END;

	Controller = POINTER TO ControllerDesc;
	ControllerDesc = RECORD
		num: LONGINT;	(* number of devices *)
		state: LONGINT;	(* see CONST  *)
		device: ARRAY MaxDrives OF DeviceDesc;
		port: LONGINT;	(* Disk controller port *)
		regPort: LONGINT;	(* Disk controller register port *)
		num1: LONGINT	(* # of sectors currently being read (<256) *)
	END;

	Params = POINTER TO ParamsDesc;
	ParamsDesc = RECORD
		controller: Controller;
		drive, sector, num, bufadr: LONGINT;	(* request par. (inc) *)
		op: LONGINT	(* Read, Write *)
	END;

VAR
	singleblocks: BOOLEAN;
	par: Params;
	interrupt: LONGINT;
	large: BOOLEAN;
	wstate0, wstate1: LONGINT;

(* ---- Driver support ---- *)

(* RepInWord - Block port input instruction. *)

PROCEDURE -RepInWord(port, buf, len: LONGINT);
CODE {SYSTEM.i386}
	POP ECX
	POP EDI
	POP EDX
	CLD
	REP INSW
END RepInWord;

(* RepOutWord - Block port output instruction. *)

PROCEDURE -RepOutWord(port, buf, len: LONGINT);
CODE {SYSTEM.i386}
	POP ECX
	POP ESI
	POP EDX
	CLD
	REP OUTSW
END RepOutWord;

PROCEDURE -Error(err: LONGINT);
CODE {SYSTEM.i386}
	POP EAX	(* for register dump *)
	PUSH 17	(* Disk error *)
	INT 3
END Error;

(* ---- Disk driver (GST506 device-specific part) ---- *)

(* WaitFin - Wait for controller to finish (~busy).
	Return TRUE if successful, FALSE on timeout. *)

PROCEDURE WaitFin(d: Controller): BOOLEAN;
VAR x: SET;  p, t: LONGINT;
BEGIN
	p := d.port+7;  t := Kernel.GetTimer();
	SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, x));
	wstate0 := SYSTEM.VAL(LONGINT, x * {0..7});
	REPEAT
		IF ~(7 IN x) THEN RETURN TRUE END;
		SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, x))
	UNTIL Kernel.GetTimer() - t > 15000*Kernel.TimeUnit DIV 1000;	(* 15s, was 250ms *)
	wstate1 := SYSTEM.VAL(LONGINT, x * {0..7});
	RETURN FALSE
END WaitFin;

(* WaitDrq - Wait for DRQ.
	Return TRUE if successful, FALSE on timeout. *)

PROCEDURE WaitDrq(d: Controller): BOOLEAN;
VAR x: SET;  p, t: LONGINT;
BEGIN
	p := d.port+7;  t := Kernel.GetTimer();
	SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, x));
	wstate0 := SYSTEM.VAL(LONGINT, x * {0..7});
	REPEAT
		IF 3 IN x THEN RETURN TRUE END;
		SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, x))
	UNTIL Kernel.GetTimer() - t > 250*Kernel.TimeUnit DIV 1000;	(* 250ms *)
	wstate1 := SYSTEM.VAL(LONGINT, x * {0..7});
	RETURN FALSE
END WaitDrq;

(* CheckReady - Check if disk is ready.
	{(0 <= drive <= 1) & (0 <= head <= 15)} *)

PROCEDURE CheckReady(d: Controller;  drive, head: LONGINT): LONGINT;
VAR x: SET;  p, t: LONGINT;
BEGIN
	t := Kernel.GetTimer();
	REPEAT
		IF ~WaitFin(d) THEN RETURN 6010 END;
		p := d.port+6;
		SYSTEM.PORTOUT(p, CHR(0A0H+(drive*10H)+head));
		INC(p);  SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, x));
		IF (7 IN x) OR (x * {4,5,6} = {4,6}) THEN
			RETURN 0	(* busy OR (~writeerror & ready & seek) *)
		END
	UNTIL Kernel.GetTimer() - t > 500*Kernel.TimeUnit DIV 1000;	(* 500ms *)
	RETURN 6011
END CheckReady;

(* Command - Send command to controller.  p. 5-111 *)

PROCEDURE Command(cmd: CHAR;  d: Controller;  drive, sector, head,
		cylinder, numsec: LONGINT): LONGINT;
VAR p: LONGINT;  control: CHAR;
BEGIN
	IF (drive < 0) OR (drive > 1) THEN RETURN 6003 END;
	IF (head < 0) OR (head > 15) THEN RETURN 6004 END;
	IF (cylinder < 0) OR (cylinder > 0FFFFH) THEN RETURN 6006 END;
	IF (sector < 0) OR (sector > 255) THEN RETURN 6007 END;
	IF (numsec < 0) OR (numsec > 255) THEN RETURN 6008 END;
	p := CheckReady(d, drive, head);
	IF p # 0 THEN RETURN p END;
	IF d.device[drive].heads > 8 THEN control := 8X ELSE control := 0X END;
	SYSTEM.PORTOUT(d.regPort, control);
	p := d.port+1;
	SYSTEM.PORTOUT(p, CHR(d.device[drive].writePreComp DIV 4));
	INC(p);  SYSTEM.PORTOUT(p, CHR(numsec));
	INC(p);  SYSTEM.PORTOUT(p, CHR(sector));
	INC(p);  SYSTEM.PORTOUT(p, CHR(cylinder MOD 100H));
	INC(p);  SYSTEM.PORTOUT(p, CHR(cylinder DIV 100H));
	INC(p);  SYSTEM.PORTOUT(p, CHR(0A0H+(drive*10H)+head));
	INC(p);  SYSTEM.PORTOUT(p, cmd);
	RETURN 0
END Command;

(* Cleanup - Clean up an aborted operation. *)

PROCEDURE Cleanup(d: Controller;  params: Params): LONGINT;
VAR res: LONGINT;
BEGIN
	WITH d: Controller DO
		CASE d.state OF
			Reset0, Reset1, Reset2, Reset3:
				res := 6012	(* reset timeout *)
			|Busy0:
				res := 6013	(* IO timeout *)
		END; (* CASE *)
		d.state := Initial0
	END;
	RETURN res
END Cleanup;

(* Reset - Reset the disk system.  p. 5-108
	Q: d.ap # NIL
	R: (d.state = Reset0) OR ((d.state = Initial0) & Wakeup)
	If Reset fails, the controller is probably broken. *)

PROCEDURE Reset(d: Controller): LONGINT;
VAR x: CHAR;  p, res, t: LONGINT;
BEGIN
	d.state := Initial0;	(* assume the worst *)
	SYSTEM.PORTOUT(d.regPort, 4X);	(* reset controller *)
	t := Kernel.GetTimer();	(* assume one GetTimer tick > 4.8us *)
	REPEAT UNTIL Kernel.GetTimer()-t >= 2;	(* wait > 4.8us *)
	SYSTEM.PORTOUT(d.regPort, 8X);
	IF WaitFin(d) THEN
		p := d.port+1;  SYSTEM.PORTIN(p, x);	(* get reset status *)
		IF TRUE OR (x = 1X) THEN
			res := Command(91X, d, 0, d.device[0].sectrack, d.device[0].heads-1,
					d.device[0].cylinders, d.device[0].sectrack);	(* params. *)
			IF res = 0 THEN d.state := Reset0
			ELSE (* {d.state = Initial0} *)
			END
		ELSE res := 6002	(* bad reset status *)
		END
	ELSE res := 6001	(* controller not responding *)
	END;
	RETURN res
END Reset;

(* Start - Start the IO operation.
	R: d.state IN {Initial0, Busy0} *)

PROCEDURE Start(d: Controller;  params: Params;  VAR time: LONGINT): LONGINT;
VAR x, drv, sec, cyl, head, res: LONGINT;
BEGIN
	WITH d: Controller DO
		time := IOTime + params.num * IOTimex;
		CASE d.state OF
			Initial0:
				res := Reset(d)
			|Ready0, Busy0:
				drv := params.drive;
				sec := params.sector MOD d.device[drv].sectrack + 1;
				x := params.sector DIV d.device[drv].sectrack;
				head := x MOD d.device[drv].heads;
				cyl := x DIV d.device[drv].heads;
				IF params.num > 255 THEN d.num1 := 255 ELSE d.num1 := params.num END;
				CASE params.op OF
					Read:
						res := Command(20X, d, drv, sec, head, cyl, d.num1);	(* Read *)
						IF res = 0 THEN d.state := Busy0
						ELSE d.state := Initial0
						END
					|Write:
						res := Command(30X, d, drv, sec, head, cyl, d.num1);	(* Write *)
						IF res = 0 THEN
							IF WaitDrq(d) THEN	(* drq *)
								RepOutWord(d.port, params.bufadr, BS DIV 2);	(* PF *)
								d.state := Busy0	(* {res = 0} *)
							ELSE d.state := Initial0;  res := 6029	(* drq timeout *)
							END
						ELSE d.state := Initial0	(* {res # 0} *)
						END
				END (* CASE *)
		END (* CASE *)
	END;
	RETURN res
END Start;

(* GetResult - Get result of the current operation.  p. 5-112
	p+7:
		bit 7	busy
		bit 6	ready
		bit 5	write fault
		bit 4	seek complete
		bit 3	drq
		bit 2	ecc corrected
		bit 1	index
		bit 0	error
	p+1:
		bit 7	bad block
		bit 6	data ecc
		bit 5	not used
		bit 4	id not found
		bit 3	not used
		bit 2	command aborted
		bit 1	track 0 not found
		bit 0	data address mark not found *)

PROCEDURE GetResult(d: Controller): LONGINT;
VAR x: SET;  p, i: LONGINT;
BEGIN
	p := d.port+7;  SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, x));
	IF ~(7 IN x) THEN	(* ~busy *)
		IF 5 IN x THEN RETURN 6014 (* write fault *)
		ELSIF ~(6 IN x) THEN RETURN 6015 (* not ready *)
		ELSIF ~(4 IN x) THEN RETURN 6016 (* seek not complete *)
		(*ELSIF 2 IN x THEN RETURN 6018*) (* ecc corrected *)
		ELSE (* fall through *)
		END
	END;
	IF 0 IN x THEN	(* error *)
		p := d.port+1;  SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, x));
		FOR i := 0 TO 7 DO
			IF i IN x THEN RETURN 6024-i END	(* 6017-6024 *)
		END;
		RETURN 6025 (* no error code! *)
	ELSE
		RETURN 0
	END
END GetResult;

(* Transfer - Transfer data. *)

PROCEDURE Transfer(d: Controller;  params: Params;  VAR more: BOOLEAN): LONGINT;
VAR x, err: LONGINT;
BEGIN
	WITH d: Controller DO
		more := TRUE; 
		CASE d.state OF
			Ready0:
				err := 6030	(* unexpected interrupt *)

			|Busy0:
				CASE params.op OF
					Read:
						RepInWord(d.port, params.bufadr, BS DIV 2);	(* PF *)
						INC(params.bufadr, BS);  DEC(d.num1);
						DEC(params.num);  INC(params.sector);  err := GetResult(d);
						IF err # 0 THEN d.state := Initial0
						ELSE	(* ~error *)
							IF d.num1 = 0 THEN	(* finished... *)
								IF params.num = 0 THEN	(* ...totally *)
									d.state := Ready0;  more := FALSE
								ELSE	(* ...with partial request *)
									err := Start(d, params, x)	(* next partial request *)
										(* ignore x *)
								END
							ELSE	(* await another interrupt *)
							END
						END
					|Write:
						INC(params.bufadr, BS);  DEC(d.num1);
						DEC(params.num);  INC(params.sector);
						err := GetResult(d);
						IF err # 0 THEN d.state := Initial0
						ELSE	(* ~error *)
							IF d.num1 = 0 THEN	(* finished... *)
								IF params.num = 0 THEN	(* ...totally *)
									d.state := Ready0;  more := FALSE
								ELSE	(* ...with partial request *)
									err := Start(d, params, x)	(* next partial request *)
										(* ignore x *)
								END
							ELSE
								RepOutWord(d.port, params.bufadr, BS DIV 2)	(* PF *)
									(* await another interrupt *)
							END
						END
				END (* CASE *)
	
			|Reset0:
				err := Command(10X, d, 0, d.device[0].sectrack, 0, 0, 0);	(* recal. *)
				IF err # 0 THEN d.state := Initial0
				ELSE
					IF d.num = 2 THEN d.state := Reset1 ELSE d.state := Reset3 END
				END
	
			|Reset1:
				err := Command(91X, d, 1, d.device[1].sectrack, d.device[1].heads-1,
						d.device[1].cylinders, d.device[1].sectrack);	(* params. *)
				IF err # 0 THEN d.state := Initial0
				ELSE d.state := Reset2
				END
	
			|Reset2:
				err := Command(10X, d, 1, d.device[1].sectrack, 0, 0, 0);	(* recal. *)
				IF err # 0 THEN d.state := Initial0
				ELSE d.state := Reset3
				END
	
			|Reset3:
				d.state := Ready0;  err := Start(d, params, x)	(* ignore x *)
	
			|Initial0:
				err := 6031	(* unexpected interrupt *)
		END;
		RETURN err
	END
END Transfer;

PROCEDURE InterruptHandler;
BEGIN
	INC(interrupt)
END InterruptHandler;

(* WaitForInterrupt - Wait for and handle interrupts *)

PROCEDURE WaitForInterrupt(time: LONGINT): LONGINT;
VAR start, err: LONGINT;  more: BOOLEAN;
BEGIN
	start := Kernel.GetTimer();
	LOOP
		REPEAT (* skip *) UNTIL (interrupt # 0) OR (Kernel.GetTimer() - start > time);
		IF interrupt # 0 THEN	(* handle interrupt *)
			SYSTEM.CLI();  DEC(interrupt);  SYSTEM.STI();
			err := Transfer(par.controller, par, more);
			IF (err # 0) OR ~more THEN
				RETURN err
			END
		ELSE	(* timeout *)
			RETURN Cleanup(par.controller, par)
		END
	END
END WaitForInterrupt;

(* ReadBlocks - Read disk blocks *)

PROCEDURE ReadBlocks(drive, sec, num, adr, offset: LONGINT): LONGINT;
VAR err, time: LONGINT;
BEGIN
	REPEAT
		par.op := Read;  par.drive := drive;  par.sector := sec + offset;  par.bufadr := adr;
		IF singleblocks THEN par.num := 1 ELSE par.num := num END;
		DEC(num, par.num);  INC(sec, par.num);  INC(adr, par.num*BS);
		err := Start(par.controller, par, time);
		IF err = 0 THEN err := WaitForInterrupt(time) END
	UNTIL (num <= 0) OR (err # 0);
	RETURN err
END ReadBlocks;

(* WriteBlocks - Write disk blocks *)

PROCEDURE WriteBlocks(drive, sec, num, adr, offset: LONGINT): LONGINT;
VAR err, time: LONGINT;
BEGIN
	REPEAT
		par.op := Write;  par.drive := drive;  par.sector := sec + offset;  par.bufadr := adr;
		IF singleblocks THEN par.num := 1 ELSE par.num := num END;
		DEC(num, par.num);  INC(sec, par.num);  INC(adr, par.num*BS);
		err := Start(par.controller, par, time);
		IF err = 0 THEN err := WaitForInterrupt(time) END
	UNTIL (num <= 0) OR (err # 0);
	RETURN err
END WriteBlocks;

(* StrToInt - Convert a string to an integer *)

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

(** GetBlocks - Read 512-byte disk blocks.  Low-level interface to driver.
	"drive" - hard disk number (0 or 1)
	"start" - start sector number
	"num" - number of sectors
	"buf" - buffer to read into
	"ofs" - offset from start of buf in bytes *)

PROCEDURE GetBlocks*(drive, start, num: LONGINT;  VAR buf: ARRAY OF SYSTEM.BYTE;  ofs: LONGINT);
VAR err: LONGINT;
BEGIN
	err := ReadBlocks(drive, start, num, SYSTEM.ADR(buf[ofs]), 0);
	IF err # 0 THEN Error(err) END
END GetBlocks;

(** PutBlocks - Write 512-byte disk blocks.  Low-level interface to driver.
	"drive" - hard disk number (0 or 1)
	"start" - start sector number
	"num" - number of sectors
	"buf" - buffer to write from
	"ofs" - offset from start of buf in bytes *)

PROCEDURE PutBlocks*(drive, start, num: LONGINT;  VAR buf: ARRAY OF SYSTEM.BYTE;  ofs: LONGINT);
VAR err: LONGINT;
BEGIN
	err := WriteBlocks(drive, start, num, SYSTEM.ADR(buf[ofs]), 0);
	IF err # 0 THEN Error(err) END
END PutBlocks;

(** GetParams - Return parameters of drive *)

PROCEDURE GetParams*(drive: LONGINT;  VAR cyls, hds, spt: LONGINT);
VAR d: DeviceDesc;
BEGIN
	IF (drive >= 0) & (drive < par.controller.num) THEN
		d := par.controller.device[drive];
		cyls := d.cylinders0;  hds := d.heads0;  spt := d.sectrack
	ELSE
		cyls := 0;  hds := 0;  spt := 0
	END
END GetParams;

PROCEDURE GetPar(p: LONGINT;  ofs: LONGINT): LONGINT;
VAR x: LONGINT;
BEGIN
	x := 0;
	SYSTEM.GET(p+12+ofs, SYSTEM.VAL(CHAR, x));
	RETURN x
END GetPar;

PROCEDURE Parse(s: ARRAY OF CHAR;  VAR d: DeviceDesc);
VAR p: LONGINT;
BEGIN
	d.cylinders0 := 0;  d.heads0 := 0;  d.writePreComp := 65535;
	p := 0;  d.cylinders := StrToInt(p, s);
	IF CAP(s[p]) = "M" THEN	(* only size in Mb specified *)
		d.heads := 16;  d.sectrack := 63;  d.cylinders := (d.cylinders*1024*2) DIV (16*63);
		INC(p);  IF CAP(s[p]) = "B" THEN INC(p) END
	ELSE
		IF s[p] # "," THEN Error(6080) END;
		INC(p);  d.heads := StrToInt(p, s);  IF s[p] # "," THEN Error(6081) END;
		INC(p);  d.sectrack := StrToInt(p, s);
		IF s[p] = "," THEN
			INC(p);  d.writePreComp := StrToInt(p, s);
			IF s[p] = "," THEN
				INC(p);  d.cylinders0 := StrToInt(p, s);
				IF s[p] = "," THEN
					INC(p);  d.heads0 := StrToInt(p, s)
				END
			END
		END
	END;
	IF (s[p] # 0X) & (s[p] # 20X) THEN Error(6082) END;
	IF d.cylinders0 = 0 THEN d.cylinders0 := d.cylinders END;
	IF d.heads0 = 0 THEN d.heads0 := d.heads END;
	IF (d.cylinders < 1) OR (d.cylinders > 0FFFFH) OR (d.heads < 1) OR 
			(d.heads > 16) OR (d.sectrack < 1) OR (d.sectrack > 256) THEN
		Error(6083)
	END
END Parse;

(* Adjust - Adjust head and cylinder parameters for controller. *)

PROCEDURE Adjust(d: Controller;  i: LONGINT);
BEGIN
	WHILE (d.device[i].heads > 16) & ~ODD(d.device[i].heads) DO
		large := TRUE;
		d.device[i].heads := d.device[i].heads DIV 2;
		d.device[i].cylinders := d.device[i].cylinders*2
	END;
	IF d.device[i].heads > 16 THEN	(* still too large *)
		large := TRUE;
		d.device[i].cylinders := d.device[i].cylinders * d.device[i].heads DIV 16;
		d.device[i].heads := 16
	END
END Adjust;

(* Detect - Attempt to detect drive parameters for drive d.num-1. *)

PROCEDURE Detect(d: Controller);
VAR err: LONGINT;  buf: ARRAY BS OF CHAR;  drive, i, p, hd, sec, cyl, phd, pcyl, psec: LONGINT;
BEGIN
	drive := d.num-1;
	d.device[drive].cylinders := 1023;  d.device[drive].heads := 16;	(* provisional parameters *)
	d.device[drive].sectrack := 63;  d.device[drive].writePreComp := 65535;
	err := ReadBlocks(drive, 0, 1, SYSTEM.ADR(buf[0]), 0);	(* read first block *)
	IF err = 0 THEN
		IF (buf[510] = 055X) & (buf[511] = 0AAX) THEN	(* valid partition table *)
			phd := -1;  pcyl := -1;	(* find end head and sector for each valid primary partition *)
			FOR i := 0 TO 3 DO
				p := 01BEH + 16*i;
				IF buf[p+4] # 0X THEN	(* partition i in use *)
					hd := ORD(buf[p+5]); 	(* end head *)
					sec := ORD(buf[p+6]) MOD 64;	(* end sector *)
					cyl := ASH(ASH(ORD(buf[p+6]), -6), 8) + ORD(buf[p+7]);	(* end cylinder *)
					IF cyl > pcyl THEN pcyl := cyl END;	(* highest cyl so far *)
					IF phd = -1 THEN phd := hd;  psec := sec
					ELSIF (phd = hd) & (psec = sec) THEN (* skip *)
					ELSE err := 6091	(* inconsistent table *)
					END
				END
			END;
			IF err = 0 THEN
				IF (phd # -1) & (pcyl > 0) THEN	(* set parameters *)
					d.device[drive].cylinders := pcyl+1;  d.device[drive].cylinders0 := pcyl+1;
					d.device[drive].heads := phd+1;  d.device[drive].heads0 := phd+1;
					d.device[drive].sectrack := psec;
					Adjust(d, drive)
				ELSE err := 6092	(* no partitions *)
				END
			END
		ELSE err := 6090	(* no partition table *)
		END
	END;
	IF err # 0 THEN
		Kernel.WriteString("HD");  Kernel.WriteInt(drive, 1);
		Kernel.WriteString(": Not detected (");  Kernel.WriteInt(err, 1);  
		Kernel.WriteChar(")");  Kernel.WriteLn;
		DEC(d.num)	(* not detected *)
	END;
	d.state := Initial0	(* reset on next command *)
END Detect;

(* ReadConfig - Read disk device configuration.  Set d.num and d.device as side effect.  Reads boot table. *)

PROCEDURE ReadConfig(d: Controller);
VAR p, t, i: LONGINT;  s: ARRAY 40 OF CHAR;
BEGIN
	d.num := 0;  large := FALSE;
	Kernel.GetConfig("Disk0", s);
	IF s[0] = 0X THEN	(* Disk0 not specified, use table *)
		p := Kernel.bt;	(* get boot table *)
		LOOP
			SYSTEM.GET(p, t);
			IF t = -1 THEN EXIT	(* end *)
			ELSIF t = 5 THEN	(* HD params *)
				i := d.num;  INC(d.num);
				d.device[i].cylinders := GetPar(p, 0) + 100H*GetPar(p, 1);
				d.device[i].heads := GetPar(p, 2);
				d.device[i].cylinders0 := d.device[i].cylinders;
				d.device[i].heads0 := d.device[i].heads;
				Adjust(d, i);
				d.device[i].writePreComp := GetPar(p, 5) + 100H*GetPar(p, 6);
				d.device[i].sectrack := GetPar(p, 14)
			END;
			SYSTEM.GET(p+4, t);  INC(p, t)
		END
	ELSIF CAP(s[0]) = "A" THEN
		d.num := 1;  Detect(d)
	ELSE
		d.num := 1;  Parse(s, d.device[0])
	END;
	IF d.num >= 1 THEN	(* Disk1 may override second drive info *)
		Kernel.GetConfig("Disk1", s);
		IF CAP(s[0]) = "A" THEN
			d.num := 2;  Detect(d)
		ELSIF s[0] # 0X THEN
			d.num := 2;  Parse(s, d.device[1])
		END
	END;
	IF d.num = 0 THEN
		Kernel.WriteString("Disk: no HD configured")
	ELSE
		FOR i := 0 TO d.num-1 DO
			Kernel.WriteString("HD");  Kernel.WriteInt(i, 1);  Kernel.WriteString(": ");
			Kernel.WriteInt(d.device[i].cylinders*d.device[i].heads*d.device[i].sectrack DIV (100000H DIV BS), 1);
			Kernel.WriteString("Mb ");  Kernel.WriteInt(d.device[i].cylinders, 1);
			Kernel.WriteChar(",");  Kernel.WriteInt(d.device[i].heads, 1);
			Kernel.WriteChar(",");  Kernel.WriteInt(d.device[i].sectrack, 1);
			IF d.device[i].writePreComp # 65535 THEN
				Kernel.WriteChar(",");  Kernel.WriteInt(d.device[i].writePreComp, 1)
			END;
			Kernel.WriteLn
		END
	END
END ReadConfig;

PROCEDURE InitDriver(intnum, ctrlPort, regPort: LONGINT);
VAR d: Controller;
BEGIN
	interrupt := 0;
	NEW(par);  NEW(d);  par.controller := d;
	d.state := Initial0;  d.num := 0;  d.port := ctrlPort;  d.regPort := regPort;
	Kernel.InstallIP(InterruptHandler, SHORT(intnum));
	ReadConfig(d)
END InitDriver;

(* Init - Get parameters and initialise driver *)

PROCEDURE Init;
VAR s: ARRAY 32 OF CHAR;  irq, p, c, r: LONGINT;
BEGIN
	Kernel.GetConfig("SingleBlocks", s);
	singleblocks := s[0] = "1";
	Kernel.GetConfig("IDE", s);
	p := 0;  c := 0;  r := 0;
	irq := StrToInt(p, s);
	IF s[p] = "," THEN
		INC(p);  c := StrToInt(p, s);
		IF s[p] = "," THEN
			INC(p);  r := StrToInt(p, s)
		END
	END;
	IF irq = 0 THEN irq := 14 END;
	IF c = 0 THEN c := 01F0H END;
	IF r = 0 THEN r := 03F6H END;
	Kernel.WriteString("IDE: ");  Kernel.WriteInt(irq, 1);  Kernel.WriteHex(c, 9);  Kernel.WriteHex(r, 9);
	IF singleblocks THEN Kernel.WriteString(" single-blocks") END;
	Kernel.WriteLn;
	InitDriver(Kernel.IRQ+irq, c, r)
END Init;

(** Install - Install the driver in the Disk module. *)

PROCEDURE Install*;
BEGIN
	Disk.GetBlocks := GetBlocks;
	Disk.PutBlocks := PutBlocks;
	Disk.GetParams := GetParams
END Install;

BEGIN
	Init;
	Install
END IDEDisk.
