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

MODULE CD;	(** non-portable *)	(* UNFINISHED *)

(* 
	CD driver for Mitsumi drive
	31.03.96 pjm - based on Atapi CD driver by fbogsany 06.01.96
*)
(* changes for Init - SA96, tburri 06.96 *)
IMPORT Oberon, Texts, Kernel, SYSTEM, Out, In;

CONST
	Trace = FALSE;
	Timeout = 5000*Kernel.TimeUnit DIV 1000;
	Retries = 5;
	MaxTracks = 103;
	
		(* values for status *)
	None = 0;
	Playing = 1;
	Completed = 2;
	Error = 3;

TYPE
	MSF = RECORD
		min, sec, frame: CHAR
	END;
	TOCEntry = RECORD
		ctrladdr: CHAR;
		track: CHAR;
		pointindex: CHAR;
		tracktime: MSF;
		disktime: MSF
	END;

VAR
	devID*: INTEGER;
	base, version, irq: LONGINT;
	toc: ARRAY MaxTracks OF TOCEntry;
	disklen, firsttrack: MSF;
	diskfirst, disklast: INTEGER;
	dataread: CHAR;
	status: SHORTINT;
	diskchanged: BOOLEAN;
	tocok: BOOLEAN;
	S: Texts.Scanner;

(* GetStatus - Wait for status from drive *)

PROCEDURE GetStatus(long: BOOLEAN): BOOLEAN;
VAR t: LONGINT;  s: SET;  ch: CHAR;
BEGIN
	IF long THEN t := Kernel.GetTimer() + 2*Timeout
	ELSE t := Kernel.GetTimer() + Timeout
	END;
	LOOP
		SYSTEM.PORTIN(base+1, SYSTEM.VAL(CHAR, s));
		IF ~(2 IN s) THEN EXIT END;	(* status available *)
		IF Kernel.GetTimer() > t THEN RETURN FALSE END
	END;
	SYSTEM.PORTIN(base, ch);
	IF ch = 0FFX THEN RETURN FALSE END;
	IF (status = Playing) & ~(1 IN SYSTEM.VAL(SET, ch)) THEN
		status := Completed
	END;
	IF 5 IN SYSTEM.VAL(SET, ch) THEN
		diskchanged := TRUE;  tocok := FALSE;
		status := None
	END;
	RETURN TRUE
END GetStatus;

(* GetValue - Read a value from the drive *)

PROCEDURE GetValue(VAR ch: CHAR);
VAR i: LONGINT;  s: SET;
BEGIN
	i := 0;
	LOOP
		SYSTEM.PORTIN(base+1, SYSTEM.VAL(CHAR, s));
		IF ~(2 IN s) THEN EXIT END;	(* status available *)
		INC(i);
		IF i = 200000000 THEN HALT(99) END
	END;
	SYSTEM.PORTIN(base, ch)
END GetValue;

(* Bcd2Bin - Convert BCD to binary *)

PROCEDURE Bcd2Bin(x: INTEGER): INTEGER;
BEGIN
	RETURN SHORT(ASH(x, -4))*10 + x MOD 10H
END Bcd2Bin;

(* Bin2Bcd - Convert binary to BCD *)

PROCEDURE Bin2Bcd(x: INTEGER): INTEGER;
BEGIN
	RETURN x MOD 10 + SHORT(ASH(x DIV 10, 4))
END Bin2Bcd;

(* GetBin - Get a value and convert to binary *)

PROCEDURE GetBin(VAR ch: CHAR);
BEGIN
	GetValue(ch);  ch := CHR(Bcd2Bin(ORD(ch)))
END GetBin;
	
(* GetQChannelInfo - Read current Q channel info *)

PROCEDURE GetQChannelInfo(VAR q: TOCEntry);
VAR i: LONGINT;
BEGIN
	i := 0;
	LOOP
		SYSTEM.PORTOUT(base, 20X);	(* get q channel *)
		IF GetStatus(FALSE) THEN EXIT END;
		INC(i);
		IF i = Retries THEN HALT(99) END
	END;
	GetValue(q.ctrladdr);  GetBin(q.track);  GetBin(q.pointindex);
	GetBin(q.tracktime.min);  GetBin(q.tracktime.sec);
	GetBin(q.tracktime.frame);  GetValue(q.disktime.min);	(* ignore *)
	GetBin(q.disktime.min);  GetBin(q.disktime.sec);
	GetBin(q.disktime.frame)
END GetQChannelInfo;

PROCEDURE ReadHdr;
VAR i: LONGINT;  ch: CHAR;
BEGIN
	tocok := FALSE;
	i := 0;
	LOOP
		SYSTEM.PORTOUT(base, 10X);	(* get disk info *)
		IF GetStatus(FALSE) THEN EXIT END;
		INC(i);
		IF i = Retries THEN HALT(99) END
	END;
	GetBin(ch);  diskfirst := ORD(ch);
	GetBin(ch);  disklast := ORD(ch);
	GetBin(disklen.min);  GetBin(disklen.sec);
	GetBin(disklen.frame);  GetBin(firsttrack.min);
	GetBin(firsttrack.sec);  GetBin(firsttrack.frame)
END ReadHdr;

PROCEDURE Print(ch: CHAR);
BEGIN
	Out.Int(ORD(ch), 4)
END Print;
	
PROCEDURE ReadTOC;
VAR i, limit: LONGINT;  q: TOCEntry;  px: INTEGER;
BEGIN
	tocok := FALSE;
	i := 0;
	LOOP
		SYSTEM.PORTOUT(base, 70X);	(* stop *)
		IF GetStatus(FALSE) THEN EXIT END;
		INC(i);
		IF i = Retries THEN HALT(99) END
	END;
	i := 0;
	LOOP
		SYSTEM.PORTOUT(base, 50X);	(* set mode *)
		SYSTEM.PORTOUT(base, 5X);	(* TOC *)
		IF GetStatus(FALSE) THEN EXIT END;
		INC(i);
		IF i = Retries THEN HALT(99) END
	END;
	FOR i := 0 TO MaxTracks-1 DO toc[i].pointindex := 0X END;
	i := disklast+3;  limit := 300;
	WHILE (i # 0) & (limit # 0) DO
		GetQChannelInfo(q);
		px := ORD(q.pointindex);
		IF (px > 0) & (px < MaxTracks) & (q.track = 0X) THEN
			IF toc[px].pointindex = 0X THEN
				toc[px] := q;  DEC(i)
			END
		END;
		DEC(limit)
	END;
	toc[disklast+1].disktime := disklen;
	i := 0;
	LOOP
		SYSTEM.PORTOUT(base, 50X);	(* set mode *)
		SYSTEM.PORTOUT(base, 1X);
		IF GetStatus(FALSE) THEN EXIT END;
		INC(i);
		IF i = Retries THEN HALT(99) END
	END;
(*
	i := 1;
	WHILE i # 103 DO
		Print(toc[i].ctrladdr);  Print(toc[i].track);  Print(toc[i].pointindex);
		Print(toc[i].tracktime.min);  Print(toc[i].tracktime.sec);  
		Print(toc[i].tracktime.frame);  Print(toc[i].disktime.min);  
		Print(toc[i].disktime.sec);  Print(toc[i].disktime.frame);
		Out.Ln;
		IF i = disklast THEN i := 100 ELSE INC(i) END
	END;
*)
	IF limit = 0 THEN HALT(99) END;
	tocok := TRUE
END ReadTOC;

(* Init - Initialise the drive *)

PROCEDURE Init;
VAR i: LONGINT;  ch: CHAR;  s: SET;  res: ARRAY 3 OF CHAR;
BEGIN
	IF Trace THEN Out.String("Init");  Out.Ln END;
	SYSTEM.PORTOUT(base+1, 0X);	(* reset *)
	FOR i := 0 TO 2000000 DO
		SYSTEM.PORTIN(base+1, ch)
	END;
	SYSTEM.PORTOUT(base, 40X);	(* get status cmd *)
	i := 0;
	LOOP
		SYSTEM.PORTIN(base+1, SYSTEM.VAL(CHAR, s));
		IF ~(2 IN s) THEN EXIT END;	(* status available *)
		INC(i);
		IF i = 2000000 THEN HALT(99) END
	END;
	SYSTEM.PORTIN(base, ch);	(* get status *)
	SYSTEM.PORTOUT(base, 0DCX);	(* get version *)
	FOR i := 0 TO 2 DO GetValue(res[i]) END;
	IF Trace THEN
		Out.String("status: ");  Out.Int(ORD(res[0]), 1);
		Out.String("  type: ");  Out.Int(ORD(res[1]), 1);
		Out.String("  version: ");  Out.Int(ORD(res[2]), 1);  Out.Ln
	END;
	IF (res[0] = res[1]) & (res[1] = res[2]) THEN RETURN END;
	IF res[1] = "D" THEN dataread := 0C1X END;
	version := ORD(res[2]);
	IF version >= 4 THEN SYSTEM.PORTOUT(base+2, 4X) END;	(* magic *)
	(*Kernel.InstallIP(InterruptHandler, Kernel.IRQ+irq);*)
	SYSTEM.PORTOUT(base, 90X);	(* config drive *)
	SYSTEM.PORTOUT(base, 2X);  SYSTEM.PORTOUT(base, 0X);
	GetValue(ch);
	SYSTEM.PORTOUT(base, 90X);	(* config drive *)
	SYSTEM.PORTOUT(base, 10X);  SYSTEM.PORTOUT(base, 4X);
	GetValue(ch);
	devID := 0
END Init;

PROCEDURE Eject*;
BEGIN
	IF Trace THEN Out.String("Eject");  Out.Ln END
END Eject;

PROCEDURE Stop*;
BEGIN
	IF Trace THEN Out.String("Stop");  Out.Ln END;
	SYSTEM.PORTOUT(base, 70X);	(* stop *)
	IF GetStatus(FALSE) THEN END;
	status := None
END Stop;

PROCEDURE Load*;
BEGIN
	IF Trace THEN Out.String("Load");  Out.Ln END
END Load;

PROCEDURE Pause*;
BEGIN
	IF Trace THEN Out.String("Pause");  Out.Ln END
END Pause;

PROCEDURE Resume*;
BEGIN
	IF Trace THEN Out.String("Resume");  Out.Ln END
END Resume;

PROCEDURE ReadTocHdr*(VAR first, last: INTEGER);
BEGIN
	IF Trace THEN Out.String("ReadTocHdr");  Out.Ln END;
	IF ~tocok THEN ReadHdr;  ReadTOC END;
	first := diskfirst;  last := disklast
END ReadTocHdr;

PROCEDURE ReadTocEntry*(track: INTEGER; VAR min, sec, frame: INTEGER);
BEGIN
	IF Trace THEN Out.String("ReadTocEntry");  Out.Ln END;
	IF ~tocok THEN ReadHdr;  ReadTOC END;
	IF track = 0AAH THEN
		min := ORD(disklen.min);  sec := ORD(disklen.sec);
		frame := ORD(disklen.frame)
	ELSIF (track >= diskfirst) & (track <= disklast) THEN
		min := ORD(toc[track].disktime.min);
		sec := ORD(toc[track].disktime.sec);
		frame := ORD(toc[track].disktime.frame)
	ELSE
		HALT(99)
	END
END ReadTocEntry;

PROCEDURE Play*(min0, sec0, frame0, min1, sec1, frame1: INTEGER);
VAR i: LONGINT;

	PROCEDURE Bcd(x: INTEGER): CHAR;
	BEGIN
		RETURN CHR(Bin2Bcd(x))
	END Bcd;
	
BEGIN
	IF Trace THEN Out.String("Play");  Out.Ln END;
	IF status = Playing THEN
		SYSTEM.PORTOUT(base, 70X);	(* stop *)
		IF GetStatus(FALSE) THEN END;
		status := None
	END;
	i := 0;
	LOOP
		SYSTEM.PORTOUT(base, 0C0X);	(* play/read *)
		SYSTEM.PORTOUT(base, Bcd(min0));
		SYSTEM.PORTOUT(base, Bcd(sec0));
		SYSTEM.PORTOUT(base, Bcd(frame0));
		SYSTEM.PORTOUT(base, Bcd(min1));
		SYSTEM.PORTOUT(base, Bcd(sec1));
		SYSTEM.PORTOUT(base, Bcd(frame1));
		IF GetStatus(TRUE) THEN EXIT END;
		INC(i);
		IF i = Retries THEN status := Error; HALT(99) END
	END;
	status := Playing
END Play;

PROCEDURE ReadLen*(VAR len: LONGINT);
BEGIN
	HALT(99)
END ReadLen;

PROCEDURE Sense*(VAR acs, acsq: CHAR);
BEGIN
	IF Trace THEN Out.String("Sense");  Out.Ln END;
	acs := 0X;  acsq := 0X
END Sense;

PROCEDURE GetPosition*(VAR track, minute, second: INTEGER);
VAR q: TOCEntry;
BEGIN
	IF Trace THEN Out.String(" GetPosition");  Out.Ln END;
	GetQChannelInfo(q);
	track := ORD(q.track);  minute := ORD(q.tracktime.min);
	second := ORD(q.tracktime.sec);
(*
	Print(q.ctrladdr);  Print(q.track);  Print(q.pointindex);
	Print(q.tracktime.min);  Print(q.tracktime.sec);  
	Print(q.tracktime.frame);  Print(q.disktime.min);  
	Print(q.disktime.sec);  Print(q.disktime.frame);
	Out.Ln
*)
END GetPosition;

PROCEDURE MediumType*(VAR medtyp: CHAR);
BEGIN
	IF Trace THEN Out.String("MediumType");  Out.Ln END;
	medtyp := 0X
END MediumType;

PROCEDURE TestPlay;
VAR first, last, min, sec, frame, min1, sec1: INTEGER;
BEGIN
	In.Open;  In.Int(min);  In.Int(sec);  In.Int(frame);
	IF In.Done THEN
		min1 := min;  sec1 := sec+10;
		IF sec1 > 59 THEN INC(min1);  DEC(sec1, 60) END;
		Play(min, sec, frame, min1, sec1, frame)
	END
END TestPlay;

PROCEDURE PlayAll;
VAR first, last, min, sec, frame: INTEGER;
BEGIN
	In.Open;  In.Int(min);  In.Int(sec);  In.Int(frame);
	IF In.Done THEN
		Play(min, sec, frame, ORD(disklen.min), ORD(disklen.sec), 
			ORD(disklen.frame))
	END
END PlayAll;

BEGIN
	Oberon.OpenScanner(S, "Sound.CDMitsumi.Port");
	IF S.class = Texts.Int THEN base:= S.i ELSE base:= MAX(LONGINT) END;
	Oberon.OpenScanner(S, "Sound.CDMitsumi.IRQ");
	IF S.class = Texts.Int THEN irq:= S.i ELSE irq:= MAX(LONGINT) END;
	dataread := 0C0X;  devID := -1;
	diskchanged := FALSE;  tocok := FALSE;
	status := None;  tocok := FALSE;
	Init
END CD.

CD.Test	CD.TestPlay ^	CD.PlayAll ^

System.State CD ~	System.Free CDAudioPlayer Audio CD ~
Desktops.OpenDoc CDAudio.Panel
