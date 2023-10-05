(* OBERON System 3, Release 2.2.

Copyright 1997 Team of the Institute of Computer Systems of ETH Zuerich,
ETH Center, CH-8092 Zuerich, e-mail: oberon@inf.ethz.ch.

This module may be used under the conditions of the general Oberon 
System 3 license contract.  The full text can be requested from the 
above-mentioned address, or downloaded from

	"ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/license.txt;A"

Under the license terms stated it is in particular (a) prohibited to modify
the interface of this module in any way that disagrees with the style
or content of the system and (b) requested to provide all conversions
of the source code to another platform with the name OBERON. *)

MODULE CD;	(** non-portable *)	(* fbogsany 06.01.96, driver support based on Disk.Mod - pmuller 06.06.95 *)
(* changes for InitDriver - SA96, tburri 06.96 *)

IMPORT Oberon, Texts, Kernel, Modules, SYSTEM, Out;

CONST
	DriveNum = 0;	(* change this if your drive is the second on this interface *)
 
TYPE
	Packet = ARRAY 12 OF CHAR;

	Controller = POINTER TO ControllerDesc;
	ControllerDesc = RECORD
		port: LONGINT;	(* Disk controller port *)
		regPort: LONGINT;	(* Disk controller register port *)
	END;

VAR
	devID*, intnum: INTEGER;
	controller: Controller;
	interrupt: BOOLEAN;

(* ---- Driver support ---- *)

(* RepInWord - Block port input instruction. *)

PROCEDURE RepInWord(port, buf, len: LONGINT);
CODE {SYSTEM.i386}
	MOV EDX, port[EBP]
	MOV EDI, buf[EBP]
	MOV ECX, len[EBP]
	CLD
	REP INSW
END RepInWord;

(* RepOutWord - Block port output instruction. *)

PROCEDURE RepOutWord(port, buf, len: LONGINT);
CODE {SYSTEM.i386}
	MOV EDX, port[EBP]
	MOV ESI, buf[EBP]
	MOV ECX, len[EBP]
	CLD
	REP OUTSW
END RepOutWord;

(* ---- Disk driver (GST506 device-specific part) ---- *)

(* WaitBsy0 - Wait for controller to finish (~busy).
	Return TRUE if successful, FALSE on timeout. *)

PROCEDURE WaitBsy0(d: Controller): BOOLEAN;
VAR
	x: SET;
	p, t: LONGINT;
BEGIN
	p := d.port+7;  t := Kernel.GetTimer();
	SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, x));
	REPEAT
		IF ~(7 IN x) THEN RETURN TRUE END;
		SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, x))
	UNTIL Kernel.GetTimer() - t > 15000*Kernel.TimeUnit DIV 1000;	(* 15s, was 250ms *)
	RETURN FALSE
END WaitBsy0;

(* WaitDrq0 - Wait for Drq = 0.
	Return TRUE if successful, FALSE on timeout. *)

PROCEDURE WaitDrq0(d: Controller): BOOLEAN;
VAR
	x: SET;
	p, t: LONGINT;
BEGIN
	p := d.port+7;  t := Kernel.GetTimer();
	SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, x));
	REPEAT
		IF ~(3 IN x) THEN RETURN TRUE END;
		SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, x))
	UNTIL Kernel.GetTimer() - t > 15000*Kernel.TimeUnit DIV 1000;	(* 15s, was 250ms *)
	RETURN FALSE
END WaitDrq0;

(* WaitDrq1 - Wait for DRQ.
	Return TRUE if successful, FALSE on timeout. *)

PROCEDURE WaitDrq1(d: Controller): BOOLEAN;
VAR
	x: SET;
	p, t: LONGINT;
BEGIN
	p := d.port+7;  t := Kernel.GetTimer();
	SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, x));
	REPEAT
		IF 3 IN x THEN RETURN TRUE END;
		SYSTEM.PORTIN(p, SYSTEM.VAL(CHAR, x))
	UNTIL Kernel.GetTimer() - t > 15000*Kernel.TimeUnit DIV 1000;	(* 15s, was 250ms *)
	RETURN FALSE
END WaitDrq1;

(* AtapiCommand - Send A0h command to controller.  *)

PROCEDURE AtapiCommand(d: Controller; drive, byteCount: LONGINT): BOOLEAN;
VAR p: LONGINT;  control: CHAR;
BEGIN
	IF WaitBsy0(d) & WaitDrq0(d) THEN
		SYSTEM.PORTOUT(d.regPort, 0X);
		p := d.port+1;
		SYSTEM.PORTOUT(p, 0X);
		p := d.port + 4;
		SYSTEM.PORTOUT(p, CHR(byteCount MOD 100H));
		INC(p);  SYSTEM.PORTOUT(p, CHR(byteCount DIV 100H));
		INC(p);  SYSTEM.PORTOUT(p, CHR(0A0H+(drive*10H)));
		INC(p);  SYSTEM.PORTOUT(p, 0A0X);
		RETURN TRUE
	END;
	RETURN FALSE
END AtapiCommand;

PROCEDURE InterruptHandler;
BEGIN
	interrupt := TRUE
END InterruptHandler;

PROCEDURE InitDriver;	(* changed by Thomas Burri, SA96 : reads parameters out of Oberon.Text *)
VAR S: Texts.Scanner;  error: BOOLEAN;
BEGIN
	error := FALSE;
	Oberon.OpenScanner(S, "Sound.CDAtapi.CtrlPort");
	IF S.class = Texts.Int THEN controller.port:= S.i ELSE error := TRUE END;
	Oberon.OpenScanner(S, "Sound.CDAtapi.RegPort");
	IF S.class = Texts.Int THEN controller.regPort:= S.i ELSE error := TRUE END;
	Oberon.OpenScanner(S, "Sound.CDAtapi.IRQ");
	IF S.class = Texts.Int THEN intnum:= SHORT(S.i) ELSE error := TRUE END;
	IF error THEN
		Out.String("Sound.CDAtapi not configured in Oberon.Text");  Out.Ln;
		controller.port := 170H;  controller.regPort := 376H;  intnum := 15
	END;
	interrupt := FALSE;
	devID := DriveNum;
	Kernel.InstallIP(InterruptHandler, Kernel.IRQ+intnum)
END InitDriver;

(* clean up and rese the drive if the command fails *)
PROCEDURE AtapiSoftReset(d: Controller): BOOLEAN;
VAR p: LONGINT;
BEGIN
	SYSTEM.PORTOUT(d.regPort, 0X);
	p := d.port+1;
	SYSTEM.PORTOUT(p, 0X);
	p := d.port + 4;
	SYSTEM.PORTOUT(p, 0X);
	INC(p);  SYSTEM.PORTOUT(p, 0X);
	INC(p);  SYSTEM.PORTOUT(p, 0A0X);
	INC(p);  SYSTEM.PORTOUT(p, 8X);
	RETURN WaitBsy0(d)
END AtapiSoftReset;


(* WaitForInterrupt - Wait for and handle interrupts *)

PROCEDURE WaitForInterrupt(d: Controller; time: LONGINT): BOOLEAN;
VAR
	start: LONGINT;
BEGIN
	start := Kernel.GetTimer();
	LOOP
		REPEAT (* skip *) UNTIL interrupt OR (Kernel.GetTimer() - start > time);
		IF interrupt THEN	(* handle interrupt *)
			interrupt := FALSE;
			RETURN TRUE
		ELSE	(* timeout *)
			RETURN AtapiSoftReset(d)
		END
	END
END WaitForInterrupt;

(* PacketCommand - Send a packet to the data register. 
	Return the status. *)

PROCEDURE PacketCommand(d: Controller; packet: Packet): CHAR;
VAR p, buf: LONGINT;
		s: CHAR;
BEGIN
	p := d.port;
	buf := SYSTEM.ADR(packet);
	IF WaitDrq1(d) THEN
		interrupt := FALSE; (* Just in case an interrupt occurred. *)
		RepOutWord(d.port, buf, 12);
		IF WaitForInterrupt(d, 15000*Kernel.TimeUnit DIV 1000) THEN
			p := d.port + 7;
			SYSTEM.PORTOUT(p, s);
			RETURN s
		ELSE
			RETURN 0FFX
		END
	END;
	RETURN 0FFX
END PacketCommand;

PROCEDURE Eject*;
VAR cmd: Packet;
	status: CHAR;
	p: LONGINT;
BEGIN
	cmd[0] := 1BX;
	cmd[1] := 1X;
	cmd[4] := 2X;
	IF AtapiCommand(controller, DriveNum, 0) THEN
		status := PacketCommand(controller, cmd)
	END
END Eject;

PROCEDURE Stop*;
VAR cmd: Packet;
	status: CHAR;
	p: LONGINT;
BEGIN
	cmd[0] := 4EX;
	IF AtapiCommand(controller, DriveNum, 0) THEN
		status := PacketCommand(controller, cmd)
	END
END Stop;

PROCEDURE Load*;
VAR cmd: Packet;
	status: CHAR;
	t, p: LONGINT;
BEGIN
	cmd[0] := 1BX;
	cmd[1] := 1X;
	cmd[4] := 3X;
	IF AtapiCommand(controller, DriveNum, 0) THEN
		status := PacketCommand(controller, cmd)
	END
END Load;

PROCEDURE Pause*;
VAR cmd: Packet;
	status: CHAR;
	p: LONGINT;
BEGIN
	cmd[0] := 4BX;
	cmd[8] := 0X;
	IF AtapiCommand(controller, DriveNum, 0) THEN
		status := PacketCommand(controller, cmd)
	END
END Pause;

PROCEDURE Resume*;
VAR cmd: Packet;
	status: CHAR;
	p: LONGINT;
BEGIN
	cmd[0] := 4BX;
	cmd[8] := 1X;
	IF AtapiCommand(controller, DriveNum, 0) THEN
		status := PacketCommand(controller, cmd)
	END
END Resume;

PROCEDURE ReadTocHdr*(VAR first, last: INTEGER);
VAR cmd: Packet;
	status: CHAR;
	p: LONGINT;
	i: SHORTINT;
BEGIN
	cmd[0] := 43X;
	FOR i := 1 TO 11 DO cmd[i] := 0X END;
	cmd[8] := 4X;
	IF AtapiCommand(controller, DriveNum, 4) THEN
		status := PacketCommand(controller, cmd);
		cmd[0] := 0X;
		cmd[1] := 0X;
		cmd[2] := 0X;
		cmd[3] := 0X;
		RepInWord(controller.port, SYSTEM.ADR(cmd), 2);
		first := ORD(cmd[2]); last := ORD(cmd[3])
	END
END ReadTocHdr;

PROCEDURE ReadTocEntry*(track: INTEGER; VAR min, sec, frame: INTEGER);
VAR cmd: Packet;
	status: CHAR;
	p: LONGINT;
	i: SHORTINT;
BEGIN
	cmd[0] := 43X;
	cmd[1] := 2X;
	FOR i := 2 TO 11 DO cmd[i] := 0X END;
	cmd[6] := CHR(track);
	cmd[8] := 0CX;
	IF AtapiCommand(controller, DriveNum, 12) THEN
		status := PacketCommand(controller, cmd);
		FOR i := 0 TO 11 DO cmd[i] := 0X END;
		RepInWord(controller.port, SYSTEM.ADR(cmd), 6);
		min := ORD(cmd[9]); sec := ORD(cmd[10]); frame := ORD(cmd[11])
	END
END ReadTocEntry;

PROCEDURE Play*(min0, sec0, frame0, min1, sec1, frame1: INTEGER);
VAR cmd: Packet;
		status: CHAR;
		p: LONGINT;
BEGIN
	cmd[0] := 47X;
	cmd[1] := 0X;
	cmd[2] := 0X;
	cmd[3] := CHR(min0);
	cmd[4] := CHR(sec0);
	cmd[5] := CHR(frame0);
	cmd[6] := CHR(min1);
	cmd[7] := CHR(sec1);
	cmd[8] := CHR(frame1);
	IF AtapiCommand(controller, DriveNum, 0) THEN
		status := PacketCommand(controller, cmd)
	END
END Play;

PROCEDURE ReadLen*(VAR len: LONGINT);
VAR cmd: Packet;
		status: CHAR;
		p: LONGINT;
BEGIN
	cmd[0] := 25X;
	IF AtapiCommand(controller, DriveNum, 0) THEN
		status := PacketCommand(controller, cmd);
		RepInWord(controller.port, SYSTEM.ADR(cmd), 4);
		len := ORD(cmd[4])*1000000H + ORD(cmd[5])*10000H + ORD(cmd[6])*100H + ORD(cmd[7])
	END
END ReadLen;

PROCEDURE Sense*(VAR acs, acsq: CHAR);
VAR cmd: Packet;
		status: CHAR;
		p: LONGINT;
		i: INTEGER;
		response: ARRAY 18 OF CHAR;
BEGIN
	cmd[0] := 3X;
	FOR i := 1 TO 11 DO cmd[i] := 0X END;
	cmd[4] := CHR(18);
	IF AtapiCommand(controller, DriveNum, 18) THEN
		status := PacketCommand(controller, cmd);
		RepInWord(controller.port, SYSTEM.ADR(response), 9);
		acs := response[12]; acsq := response[13]
	END
END Sense;

PROCEDURE GetPosition*(VAR track, minute, second: INTEGER);
VAR cmd: Packet;
	status: CHAR;
	p: LONGINT;
	i: SHORTINT;
	response: ARRAY 16 OF CHAR;
BEGIN
	cmd[0] := 42X;
	cmd[1] := 2X;
	cmd[2] := 40X;
	cmd[3] := 01X;
	FOR i := 4 TO 11 DO cmd[i] := 0X END;
	cmd[8] := CHR(16);
	IF AtapiCommand(controller, DriveNum, 16) THEN
		status := PacketCommand(controller, cmd);
		FOR i := 0 TO 15 DO response[i] := 0X END;
		RepInWord(controller.port, SYSTEM.ADR(response), 8);
		track := ORD(response[6]);
		minute := ORD(response[13]);
		second := ORD(response[14])
	END
END GetPosition;

PROCEDURE MediumType*(VAR medtyp: CHAR);
VAR cmd: Packet;
	status: CHAR;
	p: LONGINT;
	i: SHORTINT;
	response: ARRAY 8 OF CHAR;
BEGIN
	cmd[0] := 5AX;
	FOR i := 1 TO 11 DO cmd[i] := 0X END;
	cmd[2] := 0DX;
	cmd[8] := 8X;
	IF AtapiCommand(controller, DriveNum, 8) THEN
		status := PacketCommand(controller, cmd);
		FOR i := 0 TO 7 DO response[i] := 0X END;
		RepInWord(controller.port, SYSTEM.ADR(response), 4);
		medtyp := response[2]
	END
END MediumType;

PROCEDURE Cleanup;
BEGIN
	Kernel.RemoveIP(InterruptHandler, Kernel.IRQ+intnum)
END Cleanup;

BEGIN
	NEW(controller); InitDriver; Modules.InstallTermHandler(Cleanup)
END CD.

