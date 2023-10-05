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

MODULE DiskSpace;	(** non-portable *)	(* pmuller 22.06.95 *)

IMPORT Kernel, Texts, Oberon, Disk, In, Modules, Files;

CONST
	LogName = "DiskSpace.Log";
	
VAR
	W: Texts.Writer;
	task: Oberon.Task;
	prev, threshold: LONGINT;
	fprev, fthreshold, lprev, lthreshold: LONGINT;
	mem: BOOLEAN;
	text: Texts.Text;

PROCEDURE WriteInt(VAR r: Files.Rider; x, n: LONGINT);
VAR i: INTEGER; x0: LONGINT;
	a: ARRAY 14 OF CHAR;
BEGIN i := 0;
	IF x < 0 THEN
		IF x = MIN(LONGINT) THEN
			a := " -2147483648";  i := 0;
			WHILE a[i] # 0X DO Files.Write(r, a[i]); INC(i) END;
			RETURN
		ELSE DEC(n); x0 := -x
		END
	ELSE x0 := x
	END;
	REPEAT
		a[i] := CHR(x0 MOD 10 + 30H); x0 := x0 DIV 10; INC(i)
	UNTIL x0 = 0;
	WHILE n > i DO Files.Write(r, " "); DEC(n) END;
	IF x < 0 THEN Files.Write(r, "-") END;
	REPEAT DEC(i); Files.Write(r, a[i]) UNTIL i = 0
END WriteInt;

PROCEDURE WriteDate(VAR r: Files.Rider; t, d: LONGINT);
	PROCEDURE WritePair(ch: CHAR; x: LONGINT);
	BEGIN
		Files.Write(r, ch);
		Files.Write(r, CHR(x DIV 10 + 30H)); Files.Write(r, CHR(x MOD 10 + 30H))
	END WritePair;
BEGIN
	WritePair(" ", d MOD 32); WritePair(".", d DIV 32 MOD 16); WritePair(".", d DIV 512 MOD 128);
	WritePair(" ", t DIV 4096 MOD 32); WritePair(":", t DIV 64 MOD 64);
	(* WritePair(":", t MOD 64) *)
END WriteDate;
	
PROCEDURE UpdateLog(on: BOOLEAN);
VAR t, d: LONGINT;  f: Files.File;  log: Files.Rider;
BEGIN
	f := Files.Old(LogName);
	IF f = NIL THEN f := Files.New(LogName); Files.Register(f) END;
	Files.Set(log, f, Files.Length(f));
	Oberon.GetClock(t, d); WriteDate(log, t, d);
	Files.Write(log, " ");  Files.Write(log, "o");
	IF on THEN Files.Write(log, "n")
	ELSE Files.Write(log, "f");  Files.Write(log, "f")
	END;
	Files.Write(log, " ");
	WriteInt(log, Disk.Available()*Disk.SectorSize DIV 1024, 1);
	Files.Write(log, 0DX);
	Files.Close(f)
END UpdateLog;
	
PROCEDURE Stop*;
BEGIN
	IF task # NIL THEN
		UpdateLog(FALSE);
		Oberon.Remove(task);  task := NIL
	END
END Stop;

PROCEDURE Handler(t: Oberon.Task);
VAR s: LONGINT;  u: BOOLEAN;
BEGIN
	s := Disk.Available();  u := FALSE;
	IF ABS(s - prev) > threshold THEN
		IF s < 2*threshold THEN threshold := 1 END;	(* so little space, warn often! *)
		prev := s;
		Texts.WriteInt(W, s*Disk.SectorSize DIV 1024, 1);
		Texts.WriteString(W, "k disk space free");
		u := TRUE
	END;
	IF mem THEN
		s := Kernel.Available();
		IF ABS(s - fprev) > fthreshold THEN
			fprev := s;
			IF u THEN Texts.WriteString(W, ", ") END;
			Texts.WriteInt(W, s DIV 1024, 1);
			Texts.WriteString(W, "k bytes available");
			u := TRUE
		END;
		s := Kernel.LargestAvailable();
		IF ABS(s - lprev) > lthreshold THEN
			lprev := s;
			IF u THEN Texts.WriteString(W, ", ") END;
			Texts.WriteInt(W, s DIV 1024, 1);
			Texts.WriteString(W, "k byte block available");
			u := TRUE
		END
	END;
	IF u THEN Texts.WriteLn(W); Texts.Append(text, W.buf) END
END Handler;

PROCEDURE Start*;
BEGIN
	IF task = NIL THEN
		UpdateLog(TRUE);
		NEW(task);  task.time := -1;  task.safe := FALSE;  task.handle := Handler;
		Oberon.Install(task)
	END
END Start;

PROCEDURE ShowMem*;
VAR s: ARRAY 32 OF CHAR;
BEGIN
	In.Open;  In.Name(s);
	IF In.Done & (s = "on") THEN
		mem := TRUE;  fprev := -fthreshold;  lprev := -lthreshold;
	ELSIF In.Done & (s = "off") THEN
		mem := FALSE
	END
END ShowMem;

PROCEDURE SetColor*;
VAR i: INTEGER;
BEGIN
	In.Open;  In.Int(i);
	IF In.Done THEN Texts.SetColor(W, SHORT(i)) END
END SetColor;

PROCEDURE StartViewer*;
BEGIN
	NEW(text);  Texts.Open(text, "");
	Oberon.OpenText("DiskSpace.Out", text, 200, 200)
END StartViewer;

PROCEDURE StopViewer*;
BEGIN
	text := Oberon.Log
END StopViewer;

BEGIN
	text := Oberon.Log;
	task := NIL;  threshold := 100;  prev := -threshold;
	fthreshold := 128*1024;  fprev := -fthreshold;
	lthreshold := 128*1024;  lprev := -lthreshold;
	mem := FALSE;
	Texts.OpenWriter(W);
	Modules.InstallTermHandler(Stop)
END DiskSpace.

DiskSpace.Start
DiskSpace.Stop
DiskSpace.SetColor ^
DiskSpace.ShowMem ^ on off
DiskSpace.StartViewer
DiskSpace.StopViewer
