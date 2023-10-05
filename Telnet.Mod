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

MODULE Telnet;	(** portable *)	(* ip/mg 17.3.94 / 07.04.95 *)

IMPORT Input, Display, Fonts, Texts, MenuViewers, TextFrames, Oberon, TerminalFrames, Terminals, NetSystem, Objects;

CONST
	left = 2; middle = 1; right = 0; OpenHeight = 24;

	menu = "System.Close  System.Grow  Telnet.OpenLog  Telnet.Reset  Telnet.Close";

TYPE
	Task = POINTER TO TaskDesc;
	Terminal = POINTER TO TerminalDesc;
	TerminalDesc = RECORD (Terminals.TerminalDesc)
		C: NetSystem.Connection;
		localecho: BOOLEAN;
		task: Task;
	END;
	
	TextFrame = POINTER TO TextFrameDesc;
	TextFrameDesc = RECORD (TextFrames.FrameDesc)
		T: Terminal;
	END;
	
	TaskDesc = RECORD (Oberon.TaskDesc)
		T: Terminal
	END;

VAR
	cclos: ARRAY 19 OF CHAR;
	W: Texts.Writer;

PROCEDURE Send0 (T: Terminals.Terminal; ch: CHAR);
BEGIN
	WITH T: Terminal DO
		IF T.C # NIL THEN
			NetSystem.Write(T.C, ch);
			IF T.localecho THEN
				Terminals.Receive(T, ch);
				IF ch = 0DX THEN NetSystem.Write(T.C, 0AX); Terminals.Receive(T, 0AX) END;
				Terminals.Flush(T)
			END
		END
	END
END Send0;

PROCEDURE Break0 (T: Terminals.Terminal);
END Break0;

PROCEDURE Sb (C: NetSystem.Connection; VAR l: INTEGER);
VAR
	ch, ch0, ch1: CHAR;
BEGIN NetSystem.Read(C, ch); l := 1;
	IF ch = 018X THEN (* TERMINAL-TYPE *)
		NetSystem.Read(C, ch); INC(l);
		IF ch = 01X THEN (* SEND *)
			NetSystem.Write(C, 0FFX); NetSystem.Write(C, 0FAX); NetSystem.Write(C, 018X); NetSystem.Write(C, 00X);
			NetSystem.Write(C, "V"); NetSystem.Write(C, "T"); NetSystem.Write(C, "1");
			NetSystem.Write(C, "0"); NetSystem.Write(C, "0");
			NetSystem.Write(C, 0FFX); NetSystem.Write(C, 0F0X)
		END
	ELSE NetSystem.Read(C, ch0); INC(l); NetSystem.Read(C, ch1); INC(l);
		WHILE (ch0 # 0FFX) & (ch1 # 0F0X) DO
			ch0 := ch1; NetSystem.Read(C, ch1); INC(l)
		END;
		NetSystem.Write(C, 0FFX); NetSystem.Write(C, 0FEX); NetSystem.Write(C, ch)
	END
END Sb;

PROCEDURE Will (C: NetSystem.Connection; VAR l: INTEGER);
VAR
	ch: CHAR;
BEGIN NetSystem.Write(C, 0FFX);
	NetSystem.Read(C, ch); l := 1; 
	IF (ch = 01X) OR (ch = 03X) THEN (* ECHO, SUPPRESS-GO-AHEAD *)
		NetSystem.Write(C, 0FDX); NetSystem.Write(C, ch)
	ELSE NetSystem.Write(C, 0FEX); NetSystem.Write(C, ch)
	END
END Will;

PROCEDURE Wont (C: NetSystem.Connection; VAR l: INTEGER);
VAR
	ch: CHAR;
BEGIN NetSystem.Write(C, 0FFX); NetSystem.Write(C, 0FEX);
	NetSystem.Read(C, ch); l := 1; NetSystem.Write(C, ch)
END Wont;

PROCEDURE Do (C: NetSystem.Connection; VAR l: INTEGER);
VAR
	ch: CHAR;
BEGIN NetSystem.Write(C, 0FFX);
	NetSystem.Read(C, ch); l := 1;
	IF ch = 018X THEN (* TERMINAL-TYPE *)
		NetSystem.Write(C, 0FBX); NetSystem.Write(C, 018X)
	ELSE NetSystem.Write(C, 0FCX); NetSystem.Write(C, ch)
	END
END Do;

PROCEDURE Dont (C: NetSystem.Connection; VAR l: INTEGER);
VAR
	ch: CHAR;
BEGIN NetSystem.Write(C, 0FFX); NetSystem.Write(C, 0FCX);
	NetSystem.Read(C, ch); l := 1; NetSystem.Write(C, ch)
END Dont;

PROCEDURE Receiver (me: Oberon.Task);
VAR
	C: NetSystem.Connection;
	T: Terminal;
	ch: CHAR;
	i, k: INTEGER;
	l: LONGINT;
BEGIN
	WITH me: Task DO
		T := me.T; C := T.C;
		IF C # NIL THEN
			l := NetSystem.Available(C);
			IF l > 0 THEN
				REPEAT NetSystem.Read(C, ch); DEC(l);
					IF ch = 0FFX THEN (* IAC *)
						NetSystem.Read(C, ch); DEC(l);
						IF (0F1X <= ch) & (ch < 0FAX) THEN (* ignore: NOP, ..., GA *)
						ELSIF ch = 0FAX THEN Sb(C, k)
						ELSIF ch = 0FBX THEN Will(C, k)
						ELSIF ch = 0FCX THEN Wont(C, k)
						ELSIF ch = 0FDX THEN Do(C, k)
						ELSIF ch = 0FEX THEN Dont(C, k)
						ELSIF ch = 0FFX THEN k := 0;
							Terminals.Receive(T, 0FFX)
						END;
						l := l - k
					ELSIF ~((ch = 0X) OR (07X = ch) OR (ch = 011X) OR (ch = 012X)) THEN
						Terminals.Receive(T, ch)
					ELSIF (ch = 011X) OR (ch = 012X) THEN
						(* skip *)
					END
				UNTIL l <= 0;
				Terminals.Flush(T)
			ELSE
				IF NetSystem.State(C) IN {NetSystem.out, NetSystem.closed} THEN
					NetSystem.CloseConnection(C);
					me.T.C := NIL
				END
			END;
			me.time := Oberon.Time() + Input.TimeUnit DIV 50
		ELSE	(* closed *)
			i := 0;  WHILE cclos[i] # 0X DO Terminals.Receive(T, cclos[i]); INC(i) END;
			Terminals.Receive(T, 0DX); Terminals.Receive(T, 0AX); Terminals.Flush(T);
			Oberon.Remove(me)
		END
	END
END Receiver;

PROCEDURE SetUp (C: NetSystem.Connection; localecho: BOOLEAN);
BEGIN NetSystem.Write(C, 0FFX); NetSystem.Write(C, 0FDX); NetSystem.Write(C, 03X);
	NetSystem.Write(C, 0FFX); NetSystem.Write(C, 0FDX); NetSystem.Write(C, 01X);
	NetSystem.Write(C, 0FFX); NetSystem.Write(C, 0FBX); NetSystem.Write(C, 018X)
END SetUp;

PROCEDURE Open*;	(** ^ |  ( hostname | IP address ) [port] **)
VAR
	S: Texts.Scanner;
	F: TerminalFrames.Frame;
	V: MenuViewers.Viewer;
	C: NetSystem.Connection;
	task: Task;
	T: Terminal;
	text: Texts.Text;
	x, y, res, port: INTEGER;
	beg, end, time: LONGINT;
		adr: NetSystem.IPAdr;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
	IF (S.class = Texts.Char) & (S.c = "^") THEN Oberon.GetSelection(text, beg, end, time);
		IF time > 0 THEN Texts.OpenScanner(S, text, beg); Texts.Scan(S) END
	END;
	IF S.class IN {Texts.Name, Texts.String} THEN
		Texts.WriteString(W, "Telnet.Open "); Texts.WriteString(W, S.s); 
		Texts.Append(Oberon.Log, W.buf);
		NetSystem.GetIP(S.s, adr);
		Texts.Scan(S);
		IF S.class = Texts.Int THEN port := SHORT(S.i);  Texts.Write(W, " ");  Texts.WriteInt(W, port, 1)
		ELSE port := 23 END;
		NetSystem.OpenConnection(C, 0, adr, port, res);
		Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
		IF res = NetSystem.done THEN
			NEW(T); Terminals.Open(T, TextFrames.Text(""), Send0, Break0, TerminalFrames.NotifyDisplay, OpenHeight);
			NEW(task); task.safe := FALSE; task.handle := Receiver; task.T := T;
			T.localecho := FALSE; T.C := C; T.task := task;
			NEW(F); TerminalFrames.Open(F, TerminalFrames.Handle, T, Fonts.This("Courier10.Scn.Fnt"));
			Oberon.AllocateUserViewer(Oberon.Mouse.X, x, y);
			V := MenuViewers.New(TextFrames.NewMenu(S.s, menu), F, TextFrames.menuH, x, y);
			Oberon.Install(task); SetUp(T.C, T.localecho)
		ELSE Texts.WriteString(W,"connection open failed");
			Texts.WriteLn(W); Texts.Append(Oberon.Log,W.buf)
		END
	END
END Open;

PROCEDURE Close*;
VAR
	F: TerminalFrames.Frame;
BEGIN
	IF Oberon.Par.vwr.dsc.next IS TerminalFrames.Frame THEN
		F := Oberon.Par.vwr.dsc.next(TerminalFrames.Frame);
		IF (F.text IS Terminal) & (F.text(Terminal).C # NIL) THEN
			NetSystem.CloseConnection(F.text(Terminal).C);
			F.text(Terminal).C := NIL
		END
	END
END Close;

PROCEDURE Reset*;
VAR
	F: TerminalFrames.Frame;
BEGIN
	IF Oberon.Par.vwr.dsc.next IS TerminalFrames.Frame THEN
		F := Oberon.Par.vwr.dsc.next(TerminalFrames.Frame);
		Terminals.Reset(F.text);
	END;
END Reset;

PROCEDURE Send*;	(* ^ | { string | name | number } *)
VAR
	S: Texts.Scanner;
	text: Texts.Text;
	beg, end, time: LONGINT;
	M: Oberon.ConsumeMsg;
	T: Terminals.Terminal;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
	IF (S.class = Texts.Char) & (S.c = "^") THEN Oberon.GetSelection(text, beg, end, time);
		IF time > 0 THEN Texts.OpenScanner(S, text, beg); Texts.Scan(S) END
	END;
	WHILE S.class IN {Texts.String, Texts.Name, Texts.Int} DO
		IF S.class IN {Texts.String, Texts.Name} THEN Terminals.SendString(T, S.s)
		ELSE Terminals.Send(T, CHR(S.i MOD 256));
		END;
		Texts.Scan(S);
	END;
	IF W.buf.len > 0 THEN
		NEW(M.text); Texts.Open(M.text, ""); Texts.Append(M.text, W.buf);
		M.beg := 0; M.end := M.text.len; Display.Broadcast(M)
	END
END Send;

PROCEDURE SetCaret (F: TextFrames.Frame);
VAR
	pos: LONGINT;
BEGIN pos := TextFrames.Pos(F, F.X + F.W, F.Y);
	IF ~(F.car > 0) OR (F.carloc.pos # pos) THEN TextFrames.SetCaret(F, pos) END
END SetCaret;

PROCEDURE Handle (F: Objects.Object; VAR msg: Objects.ObjMsg);
VAR
	F1: TextFrame;
	text: Texts.Text;
	beg, end, time: LONGINT;
	hasCar: BOOLEAN;
BEGIN
	WITH F: TextFrame DO
		IF msg IS Oberon.InputMsg THEN
			WITH msg: Oberon.InputMsg DO
				IF (msg.id = Oberon.consume) & (F.car > 0) THEN Terminals.Send(F.T,msg.ch)
				ELSIF (msg.id = Oberon.track) & (F.X + TextFrames.barW <= msg.X) & (left IN msg.keys) THEN
					Oberon.Defocus;
					TextFrames.TrackCaret(F, msg.X, msg.Y, msg.keys);
					IF msg.keys * {middle, right} = {middle} THEN
						Oberon.GetSelection(text, beg, end, time);
						IF time >= 0 THEN Terminals.SendText(F.T, text, beg, end) END
					END
				ELSE TextFrames.Handle(F, msg)
				END
			END
		ELSIF (msg IS Oberon.ConsumeMsg) & (F.car > 0) THEN
			WITH msg: Oberon.ConsumeMsg DO Terminals.SendText(F.T, msg.text, msg.beg, msg.end) END
		ELSIF msg IS Texts.UpdateMsg THEN
			WITH msg: Texts.UpdateMsg DO
				IF msg.text = F.text THEN hasCar := (F.car > 0); TextFrames.Handle(F, msg);
					IF hasCar THEN SetCaret(F) END
				END
			END
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				NEW(F1); TextFrames.Open(F1, F.handle, F.text, F.org,  F.col, F.left, F.right, F.top, F.bot, F.lsp);
				F1.T := F.T; msg.obj := F1
			END
		ELSE TextFrames.Handle(F, msg)
		END
	END
END Handle;

PROCEDURE OpenLog*;
VAR
	V: MenuViewers.Viewer;
	F: TerminalFrames.Frame;
	f: TextFrames.Frame;
	new: TextFrame;
	x, y: INTEGER;
BEGIN
	IF Oberon.Par.vwr.dsc.next IS TerminalFrames.Frame THEN
		F := Oberon.Par.vwr.dsc.next(TerminalFrames.Frame);
		IF F.text IS Terminal THEN
			Oberon.AllocateUserViewer(Oberon.Mouse.X, x, y);
			f := TextFrames.NewText(F.text.text, 0);	(*template*)
			NEW(new); TextFrames.Open(new, Handle, F.text.text, 0, f.col, f.left, f.right, f.top, f.bot, f.lsp);
			new.T := F.text(Terminal); new.handle := Handle;
			V := MenuViewers.New(
				TextFrames.NewMenu("Log", "System.Close  System.Copy  System.Grow  Telnet.Clear  Edit.Store  "),
				new,
				TextFrames.menuH, x, y);
			V.dsc.next.handle := Handle;
		END;
	END;
END OpenLog;

PROCEDURE Clear*;
VAR
	F: Display.Frame;
BEGIN F := Oberon.Par.vwr.dsc.next;
	WITH F: TextFrame DO Texts.Delete(F.T.text, 0, F.T.text.len) END
END Clear;

BEGIN cclos := "connection closed";
	Texts.OpenWriter(W)
END Telnet.

Telnet.Open oberon.ethz.ch 13
