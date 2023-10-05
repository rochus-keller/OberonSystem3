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

MODULE Diskette0;	(** non-portable *)

(* Native Oberon diskette driver
	pjm 13.09.95	first version
	pjm 26.04.96	Cleanup
	pjm 03.07.96	CopyDWord 
	pjm 08.08.96	reset errors before every Do, weakened Recal result test
	pjm 11.09.96	retry Recal many times *)

IMPORT SYSTEM, Kernel;	(* don't import too much - also used in Ram.Disk.Mod *)

CONST
	Read = 0;  Write = 1;  Format = 2;  Verify = 3;	(* operations *)
	Ready = 0;  Reset = 1;  Recal = 2;	(* states *)
	T0 = 0;  T720 = 1;  T1440 = 2;  T2880 = 3;	(* drive/media types *)
	
TYPE
	Params = RECORD
		type, media: SHORTINT;	(* drive type & current media *)
			(* current parameters *)
		size, sectors, heads, tracks: LONGINT;
		gap, rate, spec1, spec2, fgap: CHAR
	END;

VAR
	param: ARRAY 2 OF Params;
	curtrack: LONGINT;
	result: ARRAY 7 OF SET;
	errors: ARRAY 3 OF SET;
	dmabuf: LONGINT;
	dmabufsize: LONGINT;
	curdrive: LONGINT;
	state: SHORTINT;
	motor, interrupt, trace: BOOLEAN;

(* Device driver *)

(* Error - Report an error *)

PROCEDURE Error(msg: ARRAY OF CHAR);
VAR error, reason: ARRAY 32 OF CHAR;  i: SHORTINT;  r0, r1, r2: SET;
BEGIN
	COPY(msg, error);  r0 := errors[0];  r1 := errors[1];  r2 := errors[2];
	IF (0 IN r1) OR (0 IN r2) THEN reason := "Missing address mark"
	ELSIF 1 IN r1 THEN reason := "Write protected"
	ELSIF 2 IN r1 THEN reason := "Sector not found"
	ELSIF 4 IN r1 THEN reason := "Over- or Underrun"
	ELSIF (5 IN r1) OR (5 IN r2) THEN reason := "CRC error"
	ELSIF 7 IN r1 THEN reason := "Sector past end"
	ELSIF (1 IN r2) OR (4 IN r2) THEN reason := "Bad track"
	ELSIF 6 IN r2 THEN reason := "Bad mark"
	ELSIF r0 * {6,7} = {6} THEN reason := "Command not completed"
	ELSIF r0 * {6,7} = {7} THEN reason := "Invalid command"
	ELSE reason := ""
	END;
	Kernel.WriteLn;  Kernel.WriteString("Diskette: ");  Kernel.WriteString(error);  
	Kernel.WriteString(". ");  Kernel.WriteString(reason);  Kernel.WriteLn;
	IF trace THEN
		FOR i := 0 TO 2 DO Kernel.WriteHex(SYSTEM.VAL(LONGINT, result[i]), 9) END;
		Kernel.WriteLn;
		FOR i := 0 TO 2 DO Kernel.WriteHex(SYSTEM.VAL(LONGINT, errors[i]), 9) END;
		Kernel.WriteLn
	END;
	FOR i := 0 TO 6 DO result[i] := {} END;
	FOR i := 0 TO 2 DO errors[i] := {} END;
	state := Reset;  HALT(99)
END Error;

(* AllocateDMABuffer - Allocate a byte DMA-safe buffer *)

PROCEDURE AllocateDMABuffer(size: LONGINT): LONGINT;
VAR p: LONGINT;
BEGIN
	IF size > dmabufsize THEN
		IF dmabufsize # MIN(LONGINT) THEN	(* deallocate previous buffer *)
			Kernel.DisposeDMA(dmabufsize, dmabuf);
			dmabufsize := MIN(LONGINT);  dmabuf := 0
		END;
		Kernel.NewDMA(size, dmabuf, p);  ASSERT(p = dmabuf);	(* allocate buffer *)
		dmabufsize := size
	END;
	RETURN dmabuf
END AllocateDMABuffer;

(* SetupDMA - Start a DMA operation *)

PROCEDURE SetupDMA(chan, op: SHORTINT;  buf: LONGINT;  len: LONGINT);
VAR page, mode, p: INTEGER;  adr: LONGINT;
BEGIN
	CASE op OF
		Read:  mode := 44H	(* IO->memory, no autoinit, increment, single mode *)
		|Write:  mode := 48H	(* memory->IO, no autoinit, increment, single mode *)
	END;  (* CASE *)
	DEC(len);  adr := SYSTEM.VAL(LONGINT, buf);
	CASE chan OF
		0:  page := 87H
		|1:  page := 83H
		|2:  page := 81H
		|3:  page := 82H
	END;  (* CASE *)
	SYSTEM.CLI();
	SYSTEM.PORTOUT(0AH, CHR(chan + 4));	(* disable DMA *)
	SYSTEM.PORTOUT(0CH, 0X);	(* clear flip-flop *)
	SYSTEM.PORTOUT(0BH, CHR(chan + mode));	(* set mode *)
	SYSTEM.PORTOUT(page, CHR(ASH(adr, -16)));	(* set page register *)
	p := chan*2;  SYSTEM.PORTOUT(p, CHR(adr));	(* set address *)
	SYSTEM.PORTOUT(p, CHR(ASH(adr, -8)));
	INC(p);  SYSTEM.PORTOUT(p, CHR(len));	(* set length *)
	SYSTEM.PORTOUT(p, CHR(ASH(len, -8)));
	SYSTEM.PORTOUT(0AH, CHR(chan));	(* enable DMA *)
	SYSTEM.STI()
END SetupDMA;

(* PutByte - Send byte to controller *)

PROCEDURE PutByte(b: CHAR);
VAR t: LONGINT;  s: SET;
BEGIN
	IF state # Reset THEN
		t := Kernel.GetTimer();
		REPEAT
			SYSTEM.PORTIN(3F4H, SYSTEM.VAL(CHAR, s));
			IF s * {6,7} = {7} THEN	(* ready for write *)
				SYSTEM.PORTOUT(3F5H, b);
				RETURN	(* done *)
			END
		UNTIL Kernel.GetTimer() - t > Kernel.TimeUnit DIV 2;	(* 0.5s *)
		state := Reset;  IF trace THEN Kernel.WriteString("~response ") END
	END
END PutByte;

(* GetResults - Get results from controller, returns length of result *)

PROCEDURE GetResults(): INTEGER;
VAR t: LONGINT;  s: SET;  i: SHORTINT;
BEGIN
	IF state # Reset THEN
		i := 0;  s := {};  t := Kernel.GetTimer();
		REPEAT
			SYSTEM.PORTIN(3F4H, SYSTEM.VAL(CHAR, s));
			IF s * {4,6,7} = {7} THEN	(* ready for write (end) *)
				IF trace THEN Kernel.WriteChar("=");  Kernel.WriteInt(i, 1) END;
				RETURN i
			ELSIF s * {6,7} = {6,7} THEN	(* ready for read *)
				SYSTEM.PORTIN(3F5H, SYSTEM.VAL(CHAR, s));  result[i] := s;
				IF i < 3 THEN errors[i] := errors[i] + result[i] END;
				INC(i)
			ELSE (* skip *)
			END
		UNTIL Kernel.GetTimer() - t > Kernel.TimeUnit DIV 2;	(* 0.5s *)
		state := Reset;  IF trace THEN Kernel.WriteString("~response ") END
	END;
	RETURN -1
END GetResults;

(* InterruptHandler - Handle floppy interrupt *)

PROCEDURE InterruptHandler;
BEGIN
	SYSTEM.STI();  interrupt := TRUE
END InterruptHandler;

(* WaitInterrupt - Wait for an interrupt *)

PROCEDURE WaitInterrupt;
VAR t: LONGINT;
BEGIN
	IF state # Reset THEN
		t := Kernel.GetTimer();  REPEAT UNTIL interrupt OR (Kernel.GetTimer() - t > Kernel.TimeUnit*2);	(* 2s *)
		IF ~interrupt THEN IF trace THEN Kernel.WriteString("~interrupt ") END; state := Reset END;
		interrupt := FALSE
	END
END WaitInterrupt;

(* SetParams - Set parameters depending on drive type and media *)

PROCEDURE SetParams(VAR p: Params);
BEGIN
	CASE p.media OF
		T720:
			IF trace THEN Kernel.WriteString("720k ") END;
			p.sectors := 9;  p.heads := 2;  p.tracks := 80;
			p.gap := 1BX;  p.rate := 2X;  (* transfer rate 250k/s *)
			p.spec1 := 0E1X;  (* step rate 4ms, head unload 32ms *)
			p.spec2 := 6X;  (* head load 12ms, DMA mode *)
			p.fgap := 50X	(* format gap size *)
		|T1440:
			IF trace THEN Kernel.WriteString("1.44M ") END;
			p.sectors := 18;  p.heads := 2;  p.tracks := 80;
			p.gap := 1BX;  p.rate := 0X;  (* transfer rate 500k/s *)
			p.spec1 := 0C1X;  (* step rate 4ms, head unload 16ms *)
			p.spec2 := 6X;  (* head load 6ms, DMA mode *)
			p.fgap := 6CX	(* format gap size *)
	END;
	p.size := p.sectors * p.heads * p.tracks;
	state := Reset
END SetParams;

(* CycleMedia - Skip to next media for a drive *)

PROCEDURE CycleMedia(VAR p: Params);
BEGIN
	CASE p.type OF
		T0: HALT(99)	(* no such drive *)
		|T720:	(* 720k drive can only handle 720k media *)
			CASE p.media OF
				T0: p.media := T720
				|T720: p.media := T0
			END
		|T1440:	(* 1.44M drive first tries 1.44M & then 720k *)
			CASE p.media OF
				T0: p.media := T1440
				|T1440: p.media := T720
				|T720: p.media := T0
			END
		|T2880:	(* 2.88M drive first tries 1.44M & then 720k (2.88M not handled yet) *)
			CASE p.media OF
				T0: p.media := T1440
				|T1440: p.media := T720
				|T720: p.media := T0
			END
	END; (* CASE *)
	IF p.media # T0 THEN SetParams(p) END	(* now set params according to media *)
END CycleMedia;

(* CopyDWord - Copy len dwords from src to dst. *)

PROCEDURE CopyDWord(src, dst, len: LONGINT);
CODE {SYSTEM.i386}
	MOV ESI, src[EBP]
	MOV EDI, dst[EBP]
	MOV ECX, len[EBP]
	CLD
	REP MOVSD
END CopyDWord;

(* Do - Perform a floppy operation *)

PROCEDURE Do(op, drive, sector, head, track, num: LONGINT;  VAR buf: ARRAY OF SYSTEM.BYTE): BOOLEAN;
CONST MaxLoops = 18;  MaxTries = 3;
VAR s: SET;  t, i, loops, try: LONGINT;  dmabuf: LONGINT;  ok: BOOLEAN;  media: SHORTINT;
BEGIN
	FOR i := 0 TO 2 DO errors[i] := {} END;
	IF (num < 1) OR (num > 126) THEN Error("Bad number of sectors") END;
	IF (track < 0) OR (track >= param[drive].tracks) THEN Error("Invalid track") END;
	IF (head < 0) OR (head >= param[drive].heads) THEN Error("Invalid head") END;
	dmabuf := AllocateDMABuffer(num*512);
	IF curdrive # drive THEN state := Reset;  curdrive := drive END;
	loops := 0;  try := 0;  media := param[drive].media;
	LOOP	(* two EXIT's at end of CASE state = Ready *)
		IF trace THEN
			CASE state OF
				Ready: Kernel.WriteString("Ready ")
				|Reset: Kernel.WriteString("Reset ")
				|Recal: Kernel.WriteString("Recal ")
				ELSE Kernel.WriteString("Unknown ")
			END
		END;
			(* select the drive & send power to the motor *)
		s := {2,3,drive+4} + SYSTEM.VAL(SET, drive);
		SYSTEM.PORTOUT(3F2H, SYSTEM.VAL(CHAR, s));
		IF (op IN {Write, Format}) & ~motor THEN	(* motor was not running, wait for it to spin up *)
			t := Kernel.GetTimer();  REPEAT UNTIL Kernel.GetTimer() - t > Kernel.TimeUnit DIV 2	(* 0.5s *)
		END;
		motor := TRUE;  ok := TRUE;
		CASE state OF
			Ready:
				IF trace THEN
					Kernel.WriteLn;
					CASE op OF
						Read: Kernel.WriteString("Read(")
						|Write: Kernel.WriteString("Write(")
						|Format: Kernel.WriteString("Format(")
						|Verify: Kernel.WriteString("Verify(")
					END;
					Kernel.WriteInt(track, 1);  Kernel.WriteChar(",");
					Kernel.WriteInt(head, 1);  Kernel.WriteChar(",");
					Kernel.WriteInt(sector, 1);  Kernel.WriteChar(",");
					Kernel.WriteInt(num, 1);  Kernel.WriteString(") ")
				END;
				IF curtrack # track THEN	(* seek to right track *)
					PutByte(0FX);  PutByte(CHR(ASH(head, 2) + drive));  PutByte(CHR(track));	(* seek *)
					WaitInterrupt;
					PutByte(8X);  i := GetResults();	(* sense *)
					IF (i < 1) OR (result[0] * {3..7} # {5}) THEN
						IF trace THEN Kernel.WriteString("~seek ") END;  state := Reset
					ELSE
						curtrack := track
					END
				END;
				IF state # Reset THEN
					CASE op OF
						Read, Verify:
							SetupDMA(2, Read, dmabuf, num*512);
							PutByte(0E6X)
						|Write:
							CopyDWord(SYSTEM.ADR(buf[0]), SYSTEM.VAL(LONGINT, dmabuf), num*512 DIV 4);
							SetupDMA(2, Write, dmabuf, num*512);
							PutByte(0C5X)
						|Format:
							FOR i := 0 TO num-1 DO
								SYSTEM.PUT(dmabuf+i*4+0, CHR(track));
								SYSTEM.PUT(dmabuf+i*4+1, CHR(head));
								SYSTEM.PUT(dmabuf+i*4+2, CHR(i+1));
								SYSTEM.PUT(dmabuf+i*4+3, CHR(2))
							END;
							SetupDMA(2, Write, dmabuf, num*4);
							PutByte(4DX);  PutByte(CHR(ASH(head, 2) + drive));
							PutByte(2X);  PutByte(CHR(num));
							PutByte(param[drive].fgap);  PutByte(0F6X)
					END;
					IF op IN {Read, Write, Verify} THEN	(* standard parameters *)
						PutByte(CHR(ASH(head, 2) + drive));  PutByte(CHR(track));	(* drive, head, track *)
						PutByte(CHR(head));  PutByte(CHR(sector));	(* head, sector *)
						PutByte(2X);	(* 512 byte sector *)
						PutByte(CHR(param[drive].sectors));	(* last sector *)
						PutByte(param[drive].gap);	(* gap length *)
						PutByte(0FFX)	(* sector size (unused) *)
					END;
					WaitInterrupt;
					IF (GetResults() < 7) OR (result[0] * {6,7} # {}) THEN
						IF trace THEN Kernel.WriteString("~op ") END;  state := Reset
					END
				END;
				IF state = Reset THEN
					INC(try);  IF trace THEN Kernel.WriteInt(try, 1);  Kernel.WriteString("-try ") END;
					IF try = MaxTries THEN
						IF op IN {Read, Write} THEN
							try := 0;  CycleMedia(param[drive]);	(* advance to next media type *)
							IF param[drive].media # T0 THEN
								EXIT	(* EXIT: media type changed *)
							END
						END;
						IF op IN {Read, Verify} THEN Error("Read failed")
						ELSE Error("Write failed")
						END
					END
				ELSE
					IF op = Read THEN
						CopyDWord(SYSTEM.VAL(LONGINT, dmabuf), SYSTEM.ADR(buf[0]), num*512 DIV 4)
					END;
					EXIT	(* EXIT: operation successful *)
				END

			|Reset:
				curtrack := -1;  interrupt := FALSE;  (* reset possible late interrupt *)
				SYSTEM.PORTIN(3F2H, SYSTEM.VAL(CHAR, s));  EXCL(s, 2);
				SYSTEM.PORTOUT(3F2H, SYSTEM.VAL(CHAR, s));
				t := Kernel.GetTimer();	(* assume one GetTimer tick > 50us *)
				REPEAT UNTIL Kernel.GetTimer()-t >= 2;
				INCL(s, 2);  SYSTEM.PORTOUT(3F2H, SYSTEM.VAL(CHAR, s));
				state := Recal;  WaitInterrupt;
				PutByte(8X);	(* sense *)
				IF GetResults() < 1 THEN Error("Reset failed") END;
				PutByte(3X);	(* specify (step rate, head load/unload) *)
				PutByte(param[drive].spec1);  PutByte(param[drive].spec2);
				IF state = Reset THEN Error("Specify failed") END;
				SYSTEM.PORTOUT(3F7H, param[drive].rate);	(* data rate *)
			
			|Recal:
				PutByte(7X);  PutByte(CHR(drive));	(* recalibrate *)
				WaitInterrupt;
				PutByte(8X);  i := GetResults();	(* sense *)
				IF (i < 1) OR (result[0] * {6..7} # {}) THEN
					(*Error("Recalibrate failed")*)
				ELSE
					state := Ready;  curtrack := 0
				END
				
		END; (* CASE *)
		INC(loops);  IF loops = MaxLoops THEN Error("Too many retries") END;
		IF param[drive].media # media THEN RETURN FALSE END	(* trying new media type *)
	END;
	RETURN param[drive].media = media
END Do;

(** GetSectors - Read sectors from diskette *)

PROCEDURE GetSectors*(drive, start, num: LONGINT;
		VAR buf: ARRAY OF SYSTEM.BYTE;  ofs: LONGINT);
VAR sector, head, track, s, ofs0, n, max, start0, num0: LONGINT;
BEGIN
	IF param[drive].type = T0 THEN Error("Invalid drive") END;
	IF param[drive].media = T0 THEN CycleMedia(param[drive]) END;
	start0 := start;  num0 := num;  ofs0 := ofs;
	REPEAT
		s := start;  sector := (s MOD param[drive].sectors) + 1;
		s := s DIV param[drive].sectors;  head := s MOD param[drive].heads;
		track := s DIV param[drive].heads;
		max := param[drive].sectors - sector + 1;	(* sectors left on track *)
		IF (head = 0) & (param[drive].heads > 1) THEN
			INC(max, param[drive].sectors)	(* multi-track *)
		END;
		IF num > max THEN n := max ELSE n := num END;
		IF Do(Read, drive, sector, head, track, n, buf[ofs]) THEN
			DEC(num, n);  INC(start, n);  INC(ofs, n*512)
		ELSE	(* media type changed, start over *)
			start := start0;  num := num0;  ofs := ofs0
		END
	UNTIL num = 0
END GetSectors;

(** PutSectors - Write sectors to diskette *)

PROCEDURE PutSectors*(drive, start, num: LONGINT;
		VAR buf: ARRAY OF SYSTEM.BYTE;  ofs: LONGINT);
VAR sector, head, track, s, ofs0, n, max, start0, num0: LONGINT;
BEGIN
	IF param[drive].type = T0 THEN Error("Invalid drive") END;
	IF param[drive].media = T0 THEN CycleMedia(param[drive]) END;
	start0 := start;  num0 := num;  ofs0 := ofs;
	REPEAT
		s := start;  sector := (s MOD param[drive].sectors) + 1;
		s := s DIV param[drive].sectors;  head := s MOD param[drive].heads;
		track := s DIV param[drive].heads;
		max := param[drive].sectors - sector + 1;	(* sectors left on track *)
		IF (head = 0) & (param[drive].heads > 1) THEN
			INC(max, param[drive].sectors)	(* multi-track *)
		END;
		IF num > max THEN n := max ELSE n := num END;
		IF Do(Write, drive, sector, head, track, n, buf[ofs]) THEN
			DEC(num, n);  INC(start, n);  INC(ofs, n*512)
		ELSE	(* media type changed, start over *)
			start := start0;  num := num0;  ofs := ofs0
		END
	UNTIL num = 0
END PutSectors;

(** FormatDisk - Low-level format a diskette.  fmt="H" for high density (1.44M), "D" for double (720k) *)

PROCEDURE FormatDisk*(drive: LONGINT;  fmt: CHAR);
VAR error: ARRAY 32 OF CHAR;  head, track, i, div: LONGINT;  phys: BOOLEAN;  buf: ARRAY 512 OF CHAR;
BEGIN
	error := "Format not supported";
	CASE fmt OF
		"H", "h":	(* 1.44M *)
			IF param[drive].type < T1440 THEN HALT(99) END;
			param[drive].media := T1440;
			div := 1
		|"D", "d":	(* 720k *)
			IF param[drive].type < T720 THEN HALT(99) END;
			param[drive].media := T720;
			div := 2
	END; (* CASE *)
	phys := (CAP(fmt) = fmt);
		(* format & verify *)
	error := "Format or verify error";
	SetParams(param[drive]);
	FOR track := 0 TO param[drive].tracks-1 DO
		FOR head := 0 TO param[drive].heads-1 DO
			IF phys & ~Do(Format, drive, 0, head, track, param[drive].sectors, buf) THEN HALT(99) END;
			IF ~Do(Verify, drive, 1, head, track, param[drive].sectors, buf) THEN HALT(99) END
		END
	END;
		(* init boot sector *)
	FOR i := 0 TO 511 DO buf[i] := 0X END;
	buf[0CH] := 2X;	(* 512 bytes per sector *)
	buf[0DH] := 1X;	(* sectors per cluster *)
	buf[0EH] := 1X;	(* reserved sectors *)
	buf[10H] := 2X;	(* number of FAT copies *)
	buf[11H] := CHR(224 DIV div);	(* number of root dir entries *)
	buf[13H] := CHR(param[drive].size MOD 100H);
	buf[14H] := CHR(param[drive].size DIV 100H);
	IF div = 2 THEN buf[15H] := 0F9X ELSE buf[15H] := 0F0X END;
	IF div = 2 THEN buf[16H] := 3X ELSE buf[16H] := 9X END;
	buf[18H] := CHR(param[drive].sectors);
	buf[1AH] := CHR(param[drive].heads);
		(* write boot sector *)
	IF ~Do(Write, drive, 1, 0, 0, 1, buf) THEN HALT(99) END
END FormatDisk;

(** StopMotor - Switch off diskette motor *)

PROCEDURE StopMotor*(drive: LONGINT);
BEGIN
	param[drive].media := T0;	(* reset media type *)
	SYSTEM.PORTOUT(3F2H, 0CX);	(* all motors off *)
	motor := FALSE
END StopMotor;

PROCEDURE StrToInt(s: ARRAY OF CHAR): LONGINT;
VAR i: SHORTINT;  v: LONGINT;
BEGIN
	v := 0;  i := 0;
	WHILE s[i] # 0X DO v := v*10+(ORD(s[i])-48); INC(i) END;
	RETURN v
END StrToInt;

PROCEDURE GetCMOS(i: SHORTINT): INTEGER;
VAR c: CHAR;
	PROCEDURE Wait;
	END Wait;
BEGIN
	INCL(SYSTEM.VAL(SET, i), 7);  SYSTEM.CLI();
	SYSTEM.PORTOUT(70H, i);  Wait;  SYSTEM.PORTIN(71H, c);
	SYSTEM.PORTOUT(70H, 0X);  SYSTEM.STI();
	RETURN ORD(c)
END GetCMOS;

PROCEDURE Init;
VAR s: ARRAY 12 OF CHAR;  b10, b14: INTEGER;
BEGIN
	Kernel.GetConfig("TraceDiskette", s);
	trace := (s[0] = "1");
	dmabufsize := MIN(LONGINT);
	curdrive := -1;  curtrack := -1;  motor := FALSE;  interrupt := FALSE;  state := Reset;
	Kernel.GetConfig("Diskette", s);
	IF s = "" THEN
		b10 := GetCMOS(10H);  b14 := GetCMOS(14H)
	ELSE
		b10 := SHORT(StrToInt(s) MOD 100H);
		b14 := SHORT(ASH(StrToInt(s), -8))
	END;
	IF trace THEN
		Kernel.WriteString("Diskette config:");  Kernel.WriteHex(b10, -3);
		Kernel.WriteHex(b14, -3);  Kernel.WriteLn
	END;
		(* look at drive 0 setup *)
	CASE ASH(b10, -4) OF
		3: param[0].type := T720
		|4: param[0].type := T1440
		|5: param[0].type := T2880
		ELSE param[0].type := T0
	END;
	param[0].media := T0;
		(* look at drive 1 setup, if present *)
	IF ODD(ASH(b14, -6)) THEN
		CASE b10 MOD 16 OF
			3: param[1].type := T720
			|4: param[1].type := T1440
			|5: param[1].type := T2880
			ELSE param[1].type := T0
		END;
		param[1].media := T0
	ELSE param[1].type := T0
	END
END Init;

PROCEDURE *Cleanup;
VAR p: LONGINT;
BEGIN
	StopMotor(0);
	Kernel.RemoveIP(InterruptHandler, Kernel.IRQ+6);
	IF dmabufsize # MIN(LONGINT) THEN	(* deallocate DMA buffer *)
		Kernel.NewDMA(-dmabufsize, dmabuf, p);
		dmabufsize := MIN(LONGINT);  dmabuf := 0
	END
END Cleanup;

BEGIN
	Init;
	SYSTEM.PORTOUT(3F2H, 0CX);	(* motors off, select drive 0, clear reset *)
	Kernel.InstallIP(InterruptHandler, Kernel.IRQ+6);
	Kernel.InstallTermHandler(Cleanup)
END Diskette0.
