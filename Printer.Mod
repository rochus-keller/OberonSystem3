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

MODULE Printer;	(** portable, except where noted *) (* jm, pjm *)

(** Module Printer provide an interface for installable printers.
*)

IMPORT Files, Modules, Fonts, Texts, Input, Oberon, Pictures, Centronics, V24;

CONST
	Unit300 = 3048; (* 300 dpi resolution *)

TYPE
	Printer* = POINTER TO PrinterDesc;
	PrinterDesc* = RECORD
		res*: INTEGER; (** Result code for Open method. *)
		name*: ARRAY 64 OF CHAR; (** Command used for installing the printer. *)
		Height*, Width*, Depth*: INTEGER;	(** Page size (in printer pixels), and available colors (bit depth) **)
		FrameX*, FrameY*, FrameW*, FrameH*: INTEGER; (** Prinatble region of the page. *)
		Unit*: LONGINT;	(** Printer resolution in 1/36000 mm per pixel. *)
		
		InitMetrics*: PROCEDURE (P: Printer);
		Open*: PROCEDURE (P: Printer; printer, options: ARRAY OF CHAR); (** Initialize printer & set result code. *)
		Close*: PROCEDURE (P: Printer);	(** Stop printing & set result code. *)
		Page*: PROCEDURE (P: Printer; nofcopies: INTEGER);	(** End of page reached. *)
		ReplConst*: PROCEDURE (P: Printer; x, y, w, h: INTEGER);	(** Block fill. *)
		ReplPattern*: PROCEDURE (P: Printer; x, y, w, h: INTEGER; patno: INTEGER);	(** Pattern fill. *)
		Line*: PROCEDURE (P: Printer; x0, y0, x1, y1: INTEGER);	(** Line between (x0, y0) and (x1, y1). *)
		Circle*: PROCEDURE (P: Printer; x0, y0, r: INTEGER);
		Ellipse*: PROCEDURE (P: Printer; x0, y0, a, b: INTEGER);
		Spline*: PROCEDURE (P: Printer; x0, y0, n, open: INTEGER; VAR X, Y: ARRAY OF INTEGER);
		Picture*: PROCEDURE (P: Printer; pict: Pictures.Picture; sx, sy, sw, sh, dx, dy, dw, dh, mode: INTEGER);
		UseListFont*: PROCEDURE (P: Printer; name: ARRAY OF CHAR);
		String*: PROCEDURE (P: Printer; x, y: INTEGER; str: ARRAY OF CHAR; fnt: Fonts.Font);
		ContString*: PROCEDURE (P: Printer; str: ARRAY OF CHAR; fnt: Fonts.Font);
		UseColor*: PROCEDURE (P: Printer; red, green, blue: INTEGER);
		GetMetric*: PROCEDURE (P: Printer; fnt: Fonts.Font): Fonts.Font
	END;
	
	SendProc = PROCEDURE (port: INTEGER;  ch: CHAR;  VAR done: BOOLEAN);
	SpoolList = POINTER TO RECORD
		next: SpoolList;
		send: SendProc;
		r: Files.Rider;
		port: INTEGER;
		done: BOOLEAN;
		ch: CHAR;
		v24: BOOLEAN
	END;
	
VAR
	Height*, Width*, Depth*: INTEGER;	(** In printer pixels, and bit depth *)
	FrameX*, FrameY*, FrameW*, FrameH*: INTEGER;	(** Printable area. *)
	Unit*: LONGINT;	(** Printer resolution in 1/36000 mm per pixel. *)
	res*: INTEGER;	(** result code. 0 = ok, 1 = no such printer, 2 = no link, 3 = printer not ready, 4 = no permission *)
	current*: Printer;	(** Current active printer. (read-only) *)
	spool: SpoolList;
	W: Texts.Writer;
	task: Oberon.Task;
	timeslice: LONGINT;
	spoollength, spoolpos: LONGINT;	(* view with System.State Printer *)

PROCEDURE LoadDefaultPrinter;
VAR defMod, defCmd: ARRAY 64 OF CHAR; Mod: Modules.Module; Cmd: Modules.Command;
	W: Texts.Writer;  S: Texts.Scanner;

	PROCEDURE SplitName (VAR name, MName, PName: ARRAY OF CHAR);
	VAR i, j: INTEGER;
	BEGIN i := 0;
		WHILE name[i] # "." DO MName[i] := name[i]; INC(i) END;
		MName[i] := 0X; INC(i); j := 0;
		WHILE name[i] # 0X DO PName[j] := name[i]; INC(i); INC(j) END;
		PName[j] := 0X
	END SplitName;

BEGIN
	current := NIL;
	Oberon.OpenScanner(S, "Printer.Default");
	IF S.class IN {Texts.Name, Texts.String} THEN
		SplitName(S.s, defMod, defCmd);
		Mod := Modules.ThisMod(defMod);
		IF Modules.res = 0 THEN
			Cmd := Modules.ThisCommand(Mod, defCmd);
			IF Modules.res = 0 THEN
				Cmd()
			END
		ELSE
			Texts.OpenWriter(W);
			Texts.WriteString(W, "Printer: ");  Texts.WriteString(W, S.s);  Texts.WriteString(W, " not found");
			Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf)
		END
	END
END LoadDefaultPrinter;

(** Install printer driver. P.InitMetrics is called to initialise the page metrics. *) 
PROCEDURE Install*(P: Printer);
BEGIN
	P.InitMetrics(P);
	Width := P.Width; Height := P.Height; Depth := P.Depth;
	FrameX := P.FrameX; FrameY := P.FrameY; FrameW := P.FrameW; FrameH := P.FrameH;
	Unit := P.Unit;
	current := P
END Install;

(** Open specified printer.  res code is set. *)
PROCEDURE Open* (printer, options: ARRAY OF CHAR);
VAR P: Printer;
BEGIN
	IF current # NIL THEN
		P := current;
		P.Open(P, printer, options);
		res := P.res;
		Width := P.Width; Height := P.Height; Depth := P.Depth;
		FrameX := P.FrameX; FrameY := P.FrameY; FrameW := P.FrameW; FrameH := P.FrameH;
		Unit := P.Unit
	ELSE
		res := 1	(* no such printer *)
	END
END Open;

PROCEDURE Close*;
VAR P: Printer;
BEGIN
	P := current;
	P.Close(P);
	res := P.res;
	Width := P.Width; Height := P.Height; Depth := P.Depth;
	FrameX := P.FrameX; FrameY := P.FrameY; FrameW := P.FrameW; FrameH := P.FrameH;
	Unit := P.Unit;
END Close;

PROCEDURE Page* (nofcopies: INTEGER);
BEGIN current.Page(current, nofcopies)
END Page;

PROCEDURE ReplConst* (x, y, w, h: INTEGER);
BEGIN current.ReplConst(current, x, y, w, h)
END ReplConst;

PROCEDURE ReplPattern* (x, y, w, h: INTEGER; patno: INTEGER);
BEGIN current.ReplPattern(current, x, y, w, h, patno)
END ReplPattern;

PROCEDURE Line* (x0, y0, x1, y1: INTEGER);
BEGIN current.Line(current, x0, y0, x1, y1)
END Line;

PROCEDURE Circle* (x0, y0, r: INTEGER);
BEGIN current.Circle(current, x0, y0, r)
END Circle;

PROCEDURE Ellipse* (x0, y0, a, b: INTEGER);
BEGIN current.Ellipse(current, x0, y0, a, b)
END Ellipse;

PROCEDURE Spline* (x0, y0, n, open: INTEGER; VAR X, Y: ARRAY OF INTEGER);
BEGIN current.Spline(current, x0, y0, n, open, X, Y)
END Spline;

PROCEDURE Picture* (P: Pictures.Picture; sx, sy, sw, sh, dx, dy, dw, dh, mode: INTEGER);
BEGIN current.Picture(current, P, sx, sy, sw, sh, dx, dy, dw, dh, mode)
END Picture;

PROCEDURE UseListFont* (name: ARRAY OF CHAR);
BEGIN current.UseListFont(current, name)
END UseListFont;

PROCEDURE String* (x, y: INTEGER; str: ARRAY OF CHAR; fnt: Fonts.Font);
BEGIN current.String(current, x, y, str, fnt)
END String;

PROCEDURE ContString* (str: ARRAY OF CHAR; fnt: Fonts.Font);
BEGIN current.ContString(current, str, fnt)
END ContString;

PROCEDURE UseColor* (red, green, blue: INTEGER);
BEGIN current.UseColor(current, red, green, blue)
END UseColor;

PROCEDURE GetMetric* (fnt: Fonts.Font): Fonts.Font;
BEGIN RETURN current.GetMetric(current, fnt)
END GetMetric;

(* System.PrinterCOMn configuration syntax (default 9600,8,n,1)
	config = bps ["," databits ["," parity ["," stopbits]]] .
	bps = <any valid numeric value> .
	databits = "5"|"6"|"7"|"8" .
	parity = "n"|"o"|"e"|"m"|"s" .
	stopbits = "1"|"2" .
*)

PROCEDURE GetConfig(port: LONGINT;  VAR bps, data, parity, stop: LONGINT);
VAR s: Texts.Scanner;  label: ARRAY 32 OF CHAR;  i: LONGINT;
BEGIN
	bps := 9600;  data := 8;  parity := V24.ParNo;  stop := V24.Stop1;
	label := "Printer.COM#";
	i := 0;  WHILE label[i] # 0X DO INC(i) END;
	label[i-1] := CHR(ORD("1")+port-V24.COM1);
	Oberon.OpenScanner(s, label);
	IF s.class = Texts.Int THEN
		bps := s.i;  Texts.Scan(s);
		IF (s.class = Texts.Char) & (s.c = ",") THEN
			Texts.Scan(s);
			IF s.class = Texts.Int THEN
				data := s.i;  Texts.Scan(s);
				IF (s.class = Texts.Char) & (s.c = ",") THEN
					Texts.Scan(s);
					IF s.class IN {Texts.Name, Texts.String} THEN
						CASE CAP(s.s[0]) OF
							"N": parity := V24.ParNo
							|"O": parity := V24.ParOdd
							|"E": parity := V24.ParEven
							|"M": parity := V24.ParMark
							|"S": parity := V24.ParSpace
						ELSE
						END;
						Texts.Scan(s);
						IF (s.class = Texts.Char) & (s.c = ",") THEN
							Texts.Scan(s);
							IF s.class = Texts.Int THEN stop := s.i END
						END
					END
				END
			END
		END
	END
END GetConfig;

(* Spooling *)

PROCEDURE StartJob(n: SpoolList);
VAR err, bps, data, parity, stop: LONGINT;
BEGIN
	spoollength := Files.Length(Files.Base(n.r));
	IF n.v24 THEN
		GetConfig(n.port, bps, data, parity, stop);
		V24.Start(n.port, bps, data, parity, stop, err);
		ASSERT(err = 0)
	ELSE
		Centronics.Start(n.port)
	END
END StartJob;

PROCEDURE EndJob(n: SpoolList);
BEGIN
	spoollength := 0;  spoolpos := 0;
	IF n.v24 THEN
		V24.Stop(n.port)
	ELSE
		Centronics.Stop(n.port)
	END
END EndJob;

PROCEDURE V24Send(port: INTEGER;  ch: CHAR;  VAR done: BOOLEAN);
VAR s: SET;  err: LONGINT;
BEGIN
	V24.GetMC(port, s);
	IF V24.CTS IN s THEN
		V24.Send(port, ch, err);
		done := err = 0
	ELSE
		done := FALSE
	END
END V24Send;

PROCEDURE Spooler(me: Oberon.Task);
VAR t: LONGINT;
BEGIN
	t := Input.Time();
	LOOP
		WHILE ~spool.done DO
			spool.send(spool.port, spool.ch, spool.done);
			IF Input.Time() - t > timeslice THEN EXIT END	(* end of timeslice *)
		END;
		Files.Read(spool.r, spool.ch);
		INC(spoolpos);
		IF spool.r.eof THEN
			EndJob(spool);
			spool := spool.next;
			IF spool = NIL THEN
				task := NIL;  Oberon.Remove(me);
				Texts.WriteString(W, "Printing finished");  Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf);
				EXIT
			END;
			spool.done := TRUE;
			StartJob(spool)
		ELSE
			spool.done := FALSE
		END
	END;
	me.time := t
END Spooler;

PROCEDURE Enter(f: Files.File;  port: INTEGER;  v24: BOOLEAN);
VAR p, n: SpoolList;
BEGIN
	NEW(n);  n.next := NIL;
	Files.Set(n.r, f, 0);  n.port := port;  n.done := TRUE;  n.v24 := v24;
	IF v24 THEN n.send := V24Send ELSE n.send := Centronics.SendPoll END;
	IF spool = NIL THEN	(* idle *)
		ASSERT(task = NIL);
		StartJob(n);
		spool := n;
		NEW(task);  task.time := Input.Time();  task.safe := FALSE;  task.handle := Spooler;
		Oberon.Install(task)
	ELSE	(* busy *)
		ASSERT(task # NIL);
		p := spool;  WHILE p.next # NIL DO p := p.next END;
		p.next := n
	END
END Enter;

(** Send file to the local printer specified by its name, or if not a known printer, register the file.  res code is set. *)
PROCEDURE Spool*(f: Files.File);	(** non-portable *)
VAR name: ARRAY 32 OF CHAR;  pre: ARRAY 4 OF CHAR;  p: INTEGER;
BEGIN
	Files.GetName(f, name);
	COPY(name, pre);
	IF name = "" THEN
		res := 0
	ELSIF (pre = "LPT") & (name[3] >= "1") & (name[3] <= "3") & (name[4] = 0X) THEN	(* centronics *)
		CASE name[3] OF
			"1": p := Centronics.LPT1
			|"2": p := Centronics.LPT2
			|"3": p := Centronics.LPT3
		END;
		Enter(f, p, FALSE);
		res := 0
	ELSIF (pre = "COM") & (name[3] >= "1") & (name[3] <= "4") & (name[4] = 0X) THEN	(* v24 *)
		CASE name[3] OF
			"1": p := V24.COM1
			|"2": p := V24.COM2
			|"3": p := V24.COM3
			|"4": p := V24.COM4
		END;
		Enter(f, p, TRUE)
	ELSE
		Files.Register(f);
		res := 0
	END
END Spool;

PROCEDURE Cleanup;
BEGIN
	IF task # NIL THEN
		Oberon.Remove(task);  task := NIL;  spool := NIL;
		Texts.WriteString(W, "Printing aborted");  Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf)
	END
END Cleanup;

PROCEDURE Init;
BEGIN
	Texts.OpenWriter(W);
	spool := NIL;  task := NIL;  spoollength := 0;  spoolpos := 0;
	timeslice := Input.TimeUnit DIV 50;
	Height := 0; Width := 0;
	Unit := Unit300;
	LoadDefaultPrinter;
	Modules.InstallTermHandler(Cleanup)
END Init;

BEGIN
	Init
END Printer.

(** Remarks:

1. Installing a printer involves calling Printer.Install with a filled-out printer (say P) descriptor. The installed printer is assigned to Printer.current. Immediately after installation, the InitMetrics method is called so that the printer can return its metrics in P.Width, P.Height, P.Depth, P.FrameX, P.FrameY, P.FrameW, P.FrameH, and P.Unit (see next remark also). These variables are copied to the global variables with the same names. Calling procedures of module Printer results in a call to a corresponding method of the currently active printer Printer.current.

2. The Open method may interpret the user and password for allowing access to a printer. A res code of 0 indicates that the printer has successfully been opened. The Open method must fill in the fields Height, Width, Depth, FrameX, FrameY, FrameW, FrameH, and Unit of the printer descriptor. All values except Unit and Depth are in printer pixels. Typical printers have 300 pixels per inch (commonly abbreviated dots-per-inch (dpi)). Unit specifies the width and height of a single pixel in units of 1/36000 mm. The printer origin 0, 0 is the left bottom corner of the page (and may not be printable). FrameX, FrameY, FrameW, FrameH indicate the printable area of the page. Depth (bits per pixel) has a typical value of 1 (black and white printer) or 24 (true-color printer). A printer must be closed for output to appear.

3. All coordinates are in printer pixels. Only the first characters of a font name (fname) up to the first period are relevant. Strings are positioned relative to their base-line. A module is free to print anywhere on the page regardless of the printer connected (there is no need to print from the top to the bottom of a page when a line printer is connected).

4. The printer patterns are defined as follows:

1	2	3	4	5	6	7	8
	
5. UseListFont has no meaning.

6. The String method keeps track of where the last character ends, allowing ContString to continue from that position.

7. UseColor takes intensity values in the range 0 <= x < 256 for each color component. Setting a color influences all further drawing operations. Setting the color to white allows you to delete already printer areas (a single page is normally cached in memory).

8. Method Spline draws a spline through the n points in arrays X, Y. (x0, y0) specifies a translation vector. Open set to 1 indicates an open spline should be drawn, otherwise a closed spline is assumed.

9. Implementation restriction: On Oberon for Windows nofcopies is ignored and defaults to 1.

10. Method Picture prints the area sx, sy, sw, sh of a picture onto the area dx, dy, dw, dh of the printer (scaling as needed).

11. The default printer driver that is installed at startup is specified with System.DefaultPrinter in the Oberon.Text/Registry. The value of the key must be the name of a command that installs a printer.
*)
