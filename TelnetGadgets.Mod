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

MODULE TelnetGadgets;	(** portable *)	(* ip/mh/mg 17.3.94 / 5.7.1994 / 05.09.94, RS, Mon, 5-Sep-1994*)
	IMPORT Kernel, Fonts, Display, Printer, Texts, Oberon, Objects, Terminals, TerminalGadgets, Gadgets, NetSystem, NetTools,
		Strings, HyperDocs, Documents, Desktops, TextGadgets, TextDocs, Input, SYSTEM;

	CONST
		OpenHeight = 24;
		BufSize = 1500;
		DefPort = 23;
		Gap* = 2; VSpace = 2 * Gap; HSpace = 3 * Gap;
		Menu = "TelnetGadgets.CloseCon[Dis] TelnetGadgets.OpenLog[Log]";

	TYPE
		Terminal = POINTER TO TerminalDesc;
		Task = POINTER TO TaskDesc;

		TerminalDesc = RECORD (Terminals.TerminalDesc)
			C: NetSystem.Connection;
			task: Task;
			message, localecho: BOOLEAN;
		END;
	
		TaskDesc = RECORD (Oberon.TaskDesc)
			T: Terminal;
			colon: INTEGER;
			user, passwd: ARRAY 32 OF CHAR
		END;

VAR
	buf: ARRAY BufSize OF CHAR;
	fnt: Fonts.Font;
	W: Texts.Writer;

	PROCEDURE Connected(C: NetSystem.Connection): BOOLEAN;
		VAR state: INTEGER;
	BEGIN
		state := NetSystem.State(C);
		RETURN (state = NetSystem.inout)
	END Connected;

PROCEDURE Send0(T: Terminals.Terminal; ch: CHAR);
	VAR len, l: LONGINT;
BEGIN
	WITH T: Terminal DO
		IF Connected(T.C) THEN
			NetSystem.Write(T.C, ch);
			IF T.localecho THEN
				Terminals.Receive(T, ch);
				IF ch = 0DX THEN NetSystem.Write(T.C, 0AX); Terminals.Receive(T, 0AX) END;
				Terminals.Flush(T)
			END
		ELSE len := NetSystem.Available(T.C);
			WHILE len > 0 DO l := len;
				IF l >= BufSize THEN l := BufSize-1 END;
				NetSystem.ReadBytes(T.C, 0, l, buf); len := len - l;
				Terminals.Flush(T)
			END;
			IF T.C # NIL THEN
				NetTools.Disconnect(T.C)
			END
		END
	END
END Send0;

PROCEDURE Break0(T: Terminals.Terminal);
END Break0;

PROCEDURE WriteString(T: Terminals.Terminal; str: ARRAY OF CHAR);
VAR i: INTEGER;
BEGIN i := 0;
	WHILE str[i] # 0X DO Terminals.Receive(T,str[i]); INC(i); END;
END WriteString;

PROCEDURE WriteLn(T: Terminals.Terminal);
BEGIN
	Terminals.Receive(T,0DX); Terminals.Receive(T,0AX)
END WriteLn;

PROCEDURE Sb (C: NetSystem.Connection; VAR l: INTEGER);
	VAR ch, ch0, ch1: CHAR;
		s: ARRAY 8 OF CHAR;
BEGIN NetSystem.Read(C, ch); l := 1;
	IF ch = 018X THEN (* TERMINAL-TYPE *)
		NetSystem.Read(C, ch); INC(l);
		IF ch = 01X THEN (* SEND *)
			NetSystem.Write(C, 0FFX); NetSystem.Write(C, 0FAX); NetSystem.Write(C, 018X); NetSystem.Write(C, 0X);
			s := "VT100"; NetSystem.WriteBytes(C, 0, 5, s);
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
	VAR ch: CHAR;
BEGIN NetSystem.Write(C, 0FFX);
	NetSystem.Read(C, ch); l := 1; 
	IF (ch = 01X) OR (ch = 03X) THEN (* ECHO, SUPPRESS-GO-AHEAD *)
		NetSystem.Write(C, 0FDX); NetSystem.Write(C, ch)
	ELSE NetSystem.Write(C, 0FEX); NetSystem.Write(C, ch)
	END
END Will;

PROCEDURE Wont (C: NetSystem.Connection; VAR l: INTEGER);
	VAR ch: CHAR;
BEGIN NetSystem.Write(C, 0FFX); NetSystem.Write(C, 0FEX);
	NetSystem.Read(C, ch); l := 1; NetSystem.Write(C, ch)
END Wont;

PROCEDURE Do (C: NetSystem.Connection; VAR l: INTEGER);
	VAR ch: CHAR;
BEGIN NetSystem.Write(C, 0FFX);
	NetSystem.Read(C, ch); l := 1;
	IF ch = 018X THEN (* TERMINAL-TYPE *)
		NetSystem.Write(C, 0FBX); NetSystem.Write(C, 018X)
	ELSE NetSystem.Write(C, 0FCX); NetSystem.Write(C, ch)
	END
END Do;

PROCEDURE Dont (C: NetSystem.Connection; VAR l: INTEGER);
	VAR ch: CHAR;
BEGIN NetSystem.Write(C, 0FFX); NetSystem.Write(C, 0FCX);
	NetSystem.Read(C, ch); l := 1; NetSystem.Write(C, ch)
END Dont;

PROCEDURE Receiver(me: Oberon.Task);
	VAR l: LONGINT; k: INTEGER;
		C: NetSystem.Connection;
		ch: CHAR;
BEGIN
	WITH me: Task DO
		C := me.T.C;
		IF (C # NIL) & Connected(C) THEN
			IF me.T.message THEN
				me.T.message := FALSE;
				WriteString(me.T,"Connection established"); WriteLn(me.T);
				Terminals.Flush(me.T);
			END;
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
							Terminals.Receive(me.T, 0FFX)
						END;
						l := l - k
					ELSIF ~((ch = 0X) OR (07X = ch) OR (ch = 011X) OR (ch = 012X)) THEN
						Terminals.Receive(me.T, ch);
						IF ch = ":" THEN
							INC(me.colon)
						END
					END
				UNTIL l <= 0;
				Terminals.Flush(me.T)
			ELSIF (me.user # "") & (me.colon = 1) & ~me.T.localecho THEN
				Terminals.SendString(me.T, me.user); Terminals.Send(me.T, 0DX);
				me.user[0] := 0X
			ELSIF (me.passwd # "") & (me.colon = 2) & ~me.T.localecho THEN
				Terminals.SendString(me.T, me.passwd); Terminals.Send(me.T, 0DX);
				me.passwd[0] := 0X
			END;
			me.time := Oberon.Time() + Input.TimeUnit DIV 50
		ELSE
			IF C # NIL THEN
				NetTools.Disconnect(C)
			END;
			WriteLn(me.T); WriteString(me.T,"Connection closed"); WriteLn(me.T);
			Terminals.Flush(me.T);
			WriteString(me.T,"Port released"); WriteLn(me.T);
			Terminals.Flush(me.T);
			Oberon.Remove(me);
		END
	END
END Receiver;

PROCEDURE SetUp (C: NetSystem.Connection);
BEGIN
	NetSystem.Write(C, 0FFX); NetSystem.Write(C, 0FDX); NetSystem.Write(C, 03X);
	NetSystem.Write(C, 0FFX); NetSystem.Write(C, 0FDX); NetSystem.Write(C, 01X);
	NetSystem.Write(C, 0FFX); NetSystem.Write(C, 0FBX); NetSystem.Write(C, 018X)
END SetUp;

	PROCEDURE CloseFrame(F: SYSTEM.PTR);
	BEGIN
		WITH F: TerminalGadgets.Frame DO
			IF (F.text # NIL) & (F.text IS Terminal) THEN
				NetTools.Disconnect(F.text(Terminal).C);
				IF F.text(Terminal).task # NIL THEN
					Oberon.Remove(F.text(Terminal).task);
					F.text(Terminal).task := NIL
				END
			END
		END
	END CloseFrame;

	PROCEDURE OpenConn(F: TerminalGadgets.Frame; host, user, passwd: ARRAY OF CHAR; port: INTEGER);
		VAR task: Task;
			C: NetSystem.Connection;
			user0: ARRAY 32 OF CHAR;
	BEGIN
		COPY(user, user0);
		IF passwd = "" THEN NetSystem.GetPassword("telnet", host, user, passwd) END;
		IF user = "" THEN COPY(user0, user) END;
		NEW(task); task.safe := FALSE; task.handle := Receiver; task.colon := 0; task.T := F.text(Terminal);
		WriteString(task.T,"Trying ..."); WriteLn(task.T);
		Terminals.Flush(task.T);
		IF NetTools.Connect(C, port, host, FALSE) THEN
			task.T.C := C; task.T.task := task;
			COPY(user, task.user);
			COPY(passwd, task.passwd);
			task.T.localecho := (port # DefPort);
			task.T.message := TRUE; 
			SetUp(task.T.C); Oberon.Install(task);
			Kernel.RegisterObject(F, CloseFrame, FALSE)
		ELSE
			Texts.WriteString(W, host); Texts.WriteString(W," not opened");
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END
	END OpenConn;

	PROCEDURE SplitTelnetAdr(VAR url, host, user, passwd: ARRAY OF CHAR; VAR port: INTEGER; prefix: BOOLEAN): LONGINT;
		VAR
			key, i, j, l: LONGINT;
			iskey: BOOLEAN;
			str: ARRAY 8 OF CHAR;
		PROCEDURE Blanks();
		BEGIN
			WHILE (url[i] # 0X) & (url[i] <= " ") DO
				INC(i)
			END
		END Blanks;
	BEGIN
		(* Pre: url must be a telnet url *)
		HyperDocs.UnESC(url);
		port := DefPort;
		COPY("", user);
		COPY("", passwd);
		i := 0;
		Blanks();
		IF prefix THEN
			(* skip telnet *)
			WHILE (url[i] # 0X) & (url[i] # ":") DO
				INC(i)
			END;
			(* skip :// *)
			IF url[i] = ":" THEN
				INC(i)
			END;
			Blanks();
			WHILE (url[i] = "/") & (url[i] # 0X) DO
				INC(i)
			END;
			Blanks()
		END;
		(* look ahead for @ *)
		j := i;
		WHILE (url[j] # 0X) & (url[j] # "@") & (url[j] # "/") DO
			INC(j)
		END;
		IF url[j] = "@" THEN
			(* get user *)
			l := LEN(user)-1;
			j := 0;
			WHILE (url[i] # 0X) & (url[i] # ":") & (url[i] # "@") DO
				IF (j < l) THEN
					user[j] := url[i]; INC(j)
				END;
				INC(i)
			END;
			user[j] := 0X;
			DEC(j);
			WHILE (j >= 0) & (user[j] <= " ") DO
				user[j] := 0X; DEC(j)
			END;
			IF url[i] = ":" THEN
				(* get password *)
				l := LEN(passwd);
				INC(i);
				Blanks();
				j := 0;
				WHILE (url[i] # 0X) &  (url[i] # "@") DO
					IF j < l THEN
						passwd[j] := url[i]; INC(j)
					END;
					INC(i)
				END;
				passwd[j] := 0X;
				DEC(j);
				WHILE (j >= 0) & (passwd[j] <= " ") DO
					passwd[j] := 0X; DEC(j)
				END
			END;
			INC(i);
			Blanks()
		END;
		(* get host *)
		iskey := (user = "") & (passwd = "");
		l := LEN(host);
		j := 0;
		WHILE (url[i] # 0X) & (url[i] # ":") & (url[i] # "/") DO
			IF (url[i] > " ") & ~Strings.IsDigit(url[i]) THEN
				iskey := FALSE
			END;
			IF j < l THEN
				host[j] := url[i]; INC(j)
			END;
			INC(i)
		END;
		host[j] := 0X;
		DEC(j);
		WHILE (j >= 0) & (host[j] <= " ") DO
			host[j] := 0X; DEC(j)
		END;
		IF (url[i] = 0X) & iskey THEN
			IF host # "" THEN
				Strings.StrToInt(host, key);
				HyperDocs.RetrieveLink(key, buf);
				key := SplitTelnetAdr(buf, host, user, passwd, port, prefix);
				RETURN key
			ELSE
				RETURN HyperDocs.UndefKey
			END
		END;
		IF url[i] = ":" THEN
			port := 0;
			INC(i);
			WHILE (url[i] # "/") & (url[i] # 0X) DO
				IF Strings.IsDigit(url[i]) THEN
					port := port*10+ORD(url[i])-ORD("0")
				END;
				INC(i)
			END;
			IF port <= 0 THEN
				port := DefPort
			END
		END;
		COPY("telnet://", url);
		IF user # "" THEN
			Strings.Append(url, user);
			IF passwd # "" THEN
				Strings.AppendCh(url, ":");
				Strings.Append(url, passwd)
			END;
			Strings.AppendCh(url, "@")
		END;
		Strings.Lower(host, host);
		Strings.Append(url, host);
		IF port # DefPort THEN
			Strings.AppendCh(url, ":");
			Strings.IntToStr(port, str);
			Strings.Append(url, str)
		END;
		key := HyperDocs.RegisterLink(url);
		RETURN key
	END SplitTelnetAdr;

	PROCEDURE Open*;	(*telnet adr*)
		VAR S: Texts.Scanner;
			obj: Objects.Object;
			F: TerminalGadgets.Frame;
			host: ARRAY NetTools.ServerStrLen OF CHAR;
			user, passwd: ARRAY NetTools.PathStrLen OF CHAR;
			port: INTEGER;
	BEGIN
		Texts.OpenScanner(S,Oberon.Par.text,Oberon.Par.pos); Texts.Scan(S);
		IF S.class = Texts.Name THEN obj := Gadgets.FindObj(Gadgets.context, S.s);
			IF obj # NIL THEN F := obj(TerminalGadgets.Frame); Texts.Scan(S);
				IF (S.class IN {Texts.Name, Texts.String}) & (SplitTelnetAdr(S.s, host, user, passwd, port, FALSE) >= 0) THEN
					OpenConn(F, host, user, passwd, port)
				END
			END
		END
	END Open;

	PROCEDURE Close*;
		VAR S: Texts.Scanner;
			F: TerminalGadgets.Frame;
			obj: Objects.Object;
	BEGIN
		Texts.OpenScanner(S,Oberon.Par.text,Oberon.Par.pos); Texts.Scan(S);
		IF S.class = Texts.Name THEN obj := Gadgets.FindObj(Gadgets.context, S.s);
			IF obj # NIL THEN F := obj(TerminalGadgets.Frame);
				IF (F.text IS Terminal) & (F.text(Terminal).C # NIL) THEN
					NetTools.Disconnect(F.text(Terminal).C)
				END
			END
		END
	END Close;

	PROCEDURE Reset*;
		VAR S: Texts.Scanner;
			F: TerminalGadgets.Frame;
			obj: Objects.Object;
	BEGIN
		Texts.OpenScanner(S,Oberon.Par.text,Oberon.Par.pos); Texts.Scan(S);
		IF S.class = Texts.Name THEN obj := Gadgets.FindObj(Gadgets.context, S.s);
			IF obj # NIL THEN F := obj(TerminalGadgets.Frame);
				Terminals.Reset(F.text);
			END
		END
	END Reset;

(* log view *)

	PROCEDURE Log(F: TerminalGadgets.Frame);
		VAR D: Documents.Document;
	BEGIN
		IF F.text IS Terminal THEN
			NEW(D); TextDocs.InitLog(D);
			D.dsc(TextGadgets.Frame).text := F.text.text;
			COPY("Telnet.Log", D.name);
			D.W := HyperDocs.docW; D.H := HyperDocs.docH;
			Desktops.ShowDoc(D)
		END
	END Log;

	PROCEDURE OpenLog*;
		VAR
			S: Texts.Scanner;
			F: Objects.Object;
			D: Documents.Document;
	BEGIN
		Texts.OpenScanner(S,Oberon.Par.text,Oberon.Par.pos);
		Texts.Scan(S);
		IF S.class IN {Texts.Name, Texts.String} THEN
			F := Gadgets.FindObj(Gadgets.context, S.s);
			IF F # NIL THEN
				Log(F(TerminalGadgets.Frame))
			END
		ELSE
			D := Desktops.CurDoc(Gadgets.context);
			IF (D # NIL) & (D.dsc # NIL) & (D.dsc IS TerminalGadgets.Frame) THEN
				Log(D.dsc(TerminalGadgets.Frame))
			END
		END
	END OpenLog;

(*
	\e = ESC
	\n = CR
	\t = TAB
	\\ = "\"
*)

	PROCEDURE SendString(T: Terminals.Terminal; VAR s: ARRAY OF CHAR);
		VAR i: INTEGER; ch: CHAR;
	BEGIN i := 0;
		WHILE s[i] # 0X DO
			ch := s[i]; INC(i);
			IF ch = "\" THEN ch := s[i]; INC(i);
				IF ch = "\" THEN Terminals.Send(T, "\")
				ELSIF ch = "n" THEN Terminals.Send(T, 0DX)	(*CR*)
				ELSIF ch = "e" THEN Terminals.Send(T, 1BX)	(*ESC*)
				ELSIF ch = "q" THEN Terminals.Send(T, 22X)	(*dquot*)
				ELSE	(*ignore*)
				END
			ELSE Terminals.Send(T, ch)
			END
		END
	END SendString;

	PROCEDURE Send*;
		VAR S: Texts.Scanner; F: TerminalGadgets.Frame; obj: Objects.Object;
	BEGIN
		Texts.OpenScanner(S,Oberon.Par.text,Oberon.Par.pos); Texts.Scan(S);
		IF S.class = Texts.Name THEN obj := Gadgets.FindObj(Gadgets.context, S.s);
			IF obj # NIL THEN F := obj(TerminalGadgets.Frame); Texts.Scan(S);
				IF S.class = Texts.String THEN SendString(F.text, S.s) END
			END
		END
	END Send;

	PROCEDURE FrameHandler(F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			host: ARRAY NetTools.ServerStrLen OF CHAR;
			user, passwd: ARRAY NetTools.PathStrLen OF CHAR;
			port: INTEGER;
	BEGIN
		WITH F: TerminalGadgets.Frame DO
			IF ((F.text(Terminal).C = NIL) OR ~Connected(F.text(Terminal).C))
				& (F.cursorState = TerminalGadgets.FullCursor)
				& ((M IS Oberon.InputMsg) & (M(Oberon.InputMsg).id = Oberon.consume)
					OR (M IS Oberon.ConsumeMsg)) THEN	(*ignore input if not connected*)
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.s := "TelnetGadgets.NewFrame"; M.res := 0
					ELSIF (M.id = Objects.set) & (M.name = "Connection") & (SplitTelnetAdr(M.s, host, user, passwd, port, FALSE) >= 0) THEN
						OpenConn(F, host, user, passwd, port); M.res := 0
					(*ELSIF (M.id = Objects.set) & (M.name = "DisconnCmd") THEN*)
					ELSE TerminalGadgets.Handle(F, M)
					END
				END
			ELSE TerminalGadgets.Handle(F, M)
			END
		END
	END FrameHandler;

	PROCEDURE NewFrame*;
		VAR
			T: Terminal;
			F: TerminalGadgets.Frame;
			text: Texts.Text;
	BEGIN
		NEW(text);
		Texts.Open(text, "");
		NEW(T); Terminals.Open(T, text,Send0,Break0,TerminalGadgets.NotifyDisplay, OpenHeight);
		NEW(F); TerminalGadgets.Open(F, FrameHandler,T, Fonts.This("Courier8.Scn.Fnt"));
		F.profile := 1;
		Objects.NewObj := F
	END NewFrame;

	PROCEDURE *SchemeHandler(L: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			port: INTEGER;
			host: ARRAY NetTools.ServerStrLen OF CHAR;
			user, passwd: ARRAY NetTools.PathStrLen OF CHAR;
	BEGIN
		WITH L: HyperDocs.LinkScheme DO
			IF M IS HyperDocs.RegisterLinkMsg THEN
				WITH M: HyperDocs.RegisterLinkMsg DO
					M.key := SplitTelnetAdr(M.link, host, user, passwd, port, TRUE);
					IF M.key # HyperDocs.UndefKey THEN
						M.res := 0
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.class := Objects.String;
						M.s := "TelnetGadgets.NewLinkScheme";
						M.res := 0
					ELSE
						HyperDocs.LinkSchemeHandler(L, M)
					END
				END
			ELSE
				HyperDocs.LinkSchemeHandler(L, M)
			END
		END
	END SchemeHandler;

	PROCEDURE NewLinkScheme*;
		VAR L: HyperDocs.LinkScheme;
	BEGIN
		NEW(L); L.handle := SchemeHandler;
		L.usePath := FALSE;
		Objects.NewObj := L
	END NewLinkScheme;

	PROCEDURE PrintCont(F: TerminalGadgets.Frame; VAR M: Display.DisplayMsg);
		VAR
			i, j: INTEGER;
			print: ARRAY 2 OF CHAR;
		PROCEDURE P(x: LONGINT): INTEGER;
		BEGIN
			RETURN SHORT((x * Display.Unit + Printer.Unit DIV 2) DIV Printer.Unit)
		END P;
	BEGIN
		print[1] := 0X;
		FOR j := 1 TO F.text.height DO
			FOR i := 1 TO F.text.line[j].len DO
				print[0] := F.text.line[j].ch[i].ch;
				Printer.String(Printer.FrameX+P(HSpace+i*F.charW), Printer.FrameY+Printer.FrameH+P(-VSpace-j*F.lineH), print, fnt)
			END
		END;
		Printer.Page(1)
	END PrintCont;

	PROCEDURE *DocHandler(D: Objects.Object; VAR M: Objects.ObjMsg);
	BEGIN
		WITH D: Documents.Document DO
			IF M IS Display.DisplayMsg THEN
				WITH M: Display.DisplayMsg DO
					IF (M.F = NIL) OR (M.F = D) THEN
						IF (M.device = Display.printer) & (M.id = Display.contents) & (D.dsc # NIL) THEN
							PrintCont(D.dsc(TerminalGadgets.Frame), M);
							M.res := 0
						ELSE
							Documents.Handler(D, M)
						END
					ELSE
						Documents.Handler(D, M)
					END				
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "Gen" THEN
							M.class := Objects.String;
							M.s := "TelnetGadgets.NewDoc";
							M.res := 0
						ELSIF M.name = "Adaptive" THEN
							M.class := Objects.Bool;
							M.b := TRUE;
							M.res := 0
						ELSE
							Documents.Handler(D, M)
						END
					ELSE
						Documents.Handler(D, M)
					END
				END
			ELSIF M IS Objects.LinkMsg THEN
				WITH M: Objects.LinkMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "DeskMenu" THEN
							M.obj := Gadgets.CopyPublicObject("NetDocs.TelnetDeskMenu", TRUE);
							IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
							M.res := 0
						ELSIF M.name = "SystemMenu" THEN
							M.obj := Gadgets.CopyPublicObject("NetDocs.TelnetSystemMenu", TRUE);
							IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
							M.res := 0
						ELSIF M.name = "UserMenu" THEN
							M.obj := Gadgets.CopyPublicObject("NetDocs.TelnetUserMenu", TRUE);
							IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
							M.res := 0
						ELSE
							Documents.Handler(D, M)
						END
					ELSE
						Documents.Handler(D, M)
					END
				END
			ELSE
				Documents.Handler(D, M)
			END
		END
	END DocHandler;

	PROCEDURE CloseCon*;
		VAR
			D: Documents.Document;
			F: TerminalGadgets.Frame;
	BEGIN
		D := Desktops.CurDoc(Gadgets.context);
		IF (D # NIL) & (D.dsc # NIL) & (D.dsc IS TerminalGadgets.Frame) THEN
			F := D.dsc(TerminalGadgets.Frame);
			IF F.text # NIL THEN
				NetTools.Disconnect(F.text(Terminal).C)
			END
		END
	END CloseCon;

	PROCEDURE *LoadDoc(D: Documents.Document);
		VAR
			host: ARRAY NetTools.ServerStrLen OF CHAR;
			user, passwd: ARRAY NetTools.PathStrLen OF CHAR;
			port: INTEGER;
			key: LONGINT;
			T: Terminal;
			text: Texts.Text;
			F: TerminalGadgets.Frame;
	BEGIN
		IF D.name = "" THEN
			D.dsc := NIL;
			RETURN
		END;
		key := SplitTelnetAdr(D.name, host, user, passwd, port, TRUE);
		IF key = HyperDocs.UndefKey THEN
			D.dsc := NIL;
			RETURN
		END;
		NEW(text); Texts.Open(text, "");
		NEW(T); Terminals.Open(T, text,Send0,Break0,TerminalGadgets.NotifyDisplay, OpenHeight);
		NEW(F); TerminalGadgets.Open(F, FrameHandler,T, Fonts.This("Courier10.Scn.Fnt"));
		F.profile := 2;
		OpenConn(F, host, user, passwd, port);
		D.dsc := F; D.W := F.W; D.H := F.H;
		Documents.Init(D, F);
		COPY(host, D.name);
		D.handle := DocHandler;
		IF HyperDocs.context # NIL THEN
			HyperDocs.context.replace := FALSE;
			HyperDocs.context.history := FALSE
		END
	END LoadDoc;

	PROCEDURE NewDoc*;
		VAR D: Documents.Document;
	BEGIN
		NEW(D);
		D.Load := LoadDoc;
		Objects.NewObj := D
	END NewDoc;

BEGIN
	fnt := Fonts.This("Courier8.Scn.Fnt");
	Texts.OpenWriter(W)
END TelnetGadgets.
