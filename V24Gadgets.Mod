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

MODULE V24Gadgets;	(** portable *)	(* ip/mh/mg 17.3.94 / 5.7.1994 / 05.09.94, RS, Mon, 5-Sep-1994, pm *)
	IMPORT Fonts, Texts, Oberon, Objects, Terminals, TerminalGadgets, Gadgets, Documents, Desktops, V24, TextDocs,
		Display, Files, Input, SYSTEM, Kernel;

	CONST
		OpenHeight = 24;

	TYPE
		Task = POINTER TO TaskDesc;
		Terminal = POINTER TO TerminalDesc;
		TerminalDesc = RECORD (Terminals.TerminalDesc)
			localecho, stop: BOOLEAN;
			port, bps, data, stopb, parity: LONGINT
		END;
	
		TaskDesc = RECORD (Oberon.TaskDesc)
			T: Terminal
		END;

CONST
	P4000 = FALSE;

VAR
	W: Texts.Writer;
	fixed: Fonts.Font;
	track: SHORTINT;

PROCEDURE Send0(T: Terminals.Terminal; ch: CHAR);
	VAR t: LONGINT;
BEGIN
	WITH T: Terminal DO
		IF T.port # -1 THEN
			IF ch = 7FX THEN ch := 8X END;
			V24.Send(T.port, ch, t);
			IF T.localecho THEN
				Terminals.Receive(T, ch);
				IF ch = 0DX THEN V24.Send(T.port, 0AX, t); Terminals.Receive(T, 0AX) END;
				Terminals.Flush(T)
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

PROCEDURE Receiver(me: Oberon.Task);
	VAR ch: CHAR;  port, l, t: LONGINT;
BEGIN
	WITH me: Task DO
		IF me.T.stop THEN
			WriteLn(me.T);  WriteString(me.T, "Closed");  WriteLn(me.T);
			V24.Stop(me.T.port);  me.T.port := -1;  me.T.stop := FALSE;
			Oberon.Remove(me)
		ELSE
			port := me.T.port;
			l := V24.Available(port);
			IF l > 0 THEN
				REPEAT V24.Receive(port, ch, t); DEC(l);
					IF track < 0 THEN	(* skip *)
					ELSIF (track = 0) & (ch = " ") THEN INC(track)
					ELSIF (track = 1) & (ch = "6") THEN
						me.T.bps := 19200;  V24.Stop(me.T.port);
						t := Input.Time() + Input.TimeUnit DIV 100;
						REPEAT UNTIL Input.Time() - t > 0;
						V24.Start(me.T.port, me.T.bps, me.T.data, me.T.parity, me.T.stopb, t);
						IF t # 0 THEN HALT(99) END;
						WriteLn(me.T);  WriteString(me.T, " ** switched to 19200 **");  WriteLn(me.T);
						l := 0
					ELSE track := 0
					END;
					IF (ch = CHR(14)) OR (ch = CHR(15)) THEN
						IF ch = CHR(14) THEN Texts.SetFont(me.T.cache, fixed) 
						ELSE Texts.SetFont(me.T.cache, Fonts.Default)
						END
					ELSIF ~((ch = 0X) OR (07X = ch) OR (ch = 011X) OR (ch = 012X)) THEN
						Terminals.Receive(me.T, ch)
					END
				UNTIL l <= 0;
				Terminals.Flush(me.T)
			END
		END
	END
END Receiver;

PROCEDURE *Cleanup(f: SYSTEM.PTR);
VAR t: Terminal;
BEGIN
	WITH f: TerminalGadgets.Frame DO
		IF f.text IS Terminal THEN
			t := f.text(Terminal);
			IF t.port # -1 THEN t.stop := TRUE END
		END
	END
END Cleanup;

	PROCEDURE OpenConn(F: TerminalGadgets.Frame; port, bps, data, stop, parity: LONGINT);
		VAR task: Task; t: LONGINT;
	BEGIN
		NEW(task); task.safe := FALSE; task.handle := Receiver; task.T := F.text(Terminal);
		V24.Start(port, bps, data, parity, stop, t);
		IF t # 0 THEN
			Texts.WriteString(W, "Can not open port, error = ");
			Texts.WriteInt(W, t, 1);  Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf)
		ELSE
			task.T.port := port;  task.T.bps := bps;  task.T.data := data;  
			task.T.stopb := stop;  task.T.parity := parity;
			task.T.localecho := FALSE;
			Oberon.Install(task);
			Kernel.RegisterObject(F, Cleanup, FALSE);
			WriteString(task.T,"Opened ..."); 
			IF track = 0 THEN WriteString(task.T," (P4000 mode)") END;
			WriteLn(task.T);
			Terminals.Flush(task.T)
		END
	END OpenConn;

	PROCEDURE Open*;	(* framename params *)
		VAR S: Texts.Scanner;
			obj: Objects.Object;
			F: TerminalGadgets.Frame;
			port, bps, data, stop, parity: LONGINT;
			ok: BOOLEAN;
	BEGIN
		data := 8;  stop := V24.Stop1;  parity := V24.ParNo;  ok := FALSE;
		IF P4000 THEN track := 0 ELSE track := -1 END;
		Texts.OpenScanner(S,Oberon.Par.text,Oberon.Par.pos); Texts.Scan(S);
		IF S.class = Texts.Name THEN obj := Gadgets.FindObj(Gadgets.context, S.s);
			IF obj # NIL THEN F := obj(TerminalGadgets.Frame); Texts.Scan(S);
				IF (S.class = Texts.Int) & (S.i >= 1) & (S.i <= 4) THEN
					IF (S.i >=  1) & (S.i <= 4) THEN port := (S.i-1) + V24.COM1 ELSE port := 1 END;
					Texts.Scan(S);
					IF (S.class = Texts.Int) & (S.i >= 110) & (S.i <= 115200) THEN
						ok := TRUE;  bps := S.i;  Texts.Scan(S);
						IF (S.class = Texts.Int) & (S.i >= 5) & (S.i <= 8) THEN
							data := S.i; Texts.Scan(S);
							IF (S.class = Texts.Int) & (S.i >= 1) & (S.i <= 2) THEN
								IF S.i = 1 THEN stop := V24.Stop1 ELSE stop := V24.Stop2 END;
								Texts.Scan(S);
								IF S.class IN {Texts.Name, Texts.String} THEN
									IF CAP(S.s[0]) = "N" THEN parity := V24.ParNo
									ELSIF CAP(S.s[0]) = "O" THEN parity := V24.ParOdd
									ELSIF CAP(S.s[0]) = "E" THEN parity := V24.ParEven
									ELSE parity := V24.ParNo
									END
								END
							END
						END
					END
				END
			END
		END;
		IF ok THEN
			OpenConn(F, port, bps, data, stop, parity)
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
				IF (F.text IS Terminal) & (F.text(Terminal).port # -1) THEN
					F.text(Terminal).stop := TRUE
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
	BEGIN
		IF F.text IS Terminal THEN
			TextDocs.ShowText("V24.Log", F.text.text, Oberon.SystemTrack(0)-Oberon.UserTrack(0), 2*Display.Height DIV 3)
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

	PROCEDURE SendS(VAR br: Files.Rider;  T: Terminals.Terminal);
	VAR
		adr, size, x: LONGINT;
		buf: ARRAY 8 OF LONGINT;
		i, sum: INTEGER;
		
		PROCEDURE Write(ch: CHAR);
		BEGIN
			Terminals.Send(T, ch)
		END Write;
		
		PROCEDURE WriteHexByte(x: INTEGER);
		BEGIN
			IF x DIV 16 > 9 THEN Write(CHR((x DIV 16) MOD 16 - 10 + 65))
			ELSE Write(CHR(x DIV 16 + 48))
			END;
			IF x MOD 16 > 9 THEN Write(CHR(x MOD 16 - 10 + 65))
			ELSE Write(CHR(x MOD 16 + 48))
			END;
			sum := (sum + x) MOD 100H
		END WriteHexByte;
		
		PROCEDURE WriteHex(x: LONGINT);
		BEGIN
			WriteHexByte(SHORT(ASH(x, -24) MOD 100H));
			WriteHexByte(SHORT(ASH(x, -16) MOD 100H));
			WriteHexByte(SHORT(ASH(x, -8) MOD 100H));
			WriteHexByte(SHORT(x MOD 100H))
		END WriteHex;

		PROCEDURE Flush(ch: CHAR);
		VAR j: INTEGER;
		BEGIN
			j := 0;  sum := 0;  Write("S");  Write(ch);
			WriteHexByte(4+i*4+1);  WriteHex(adr);
			WHILE j # i DO WriteHex(buf[j]); INC(j);  INC(adr, 4) END;
			WriteHexByte(255 - sum);  Write(0DX);
			Texts.Append(Oberon.Log, W.buf);
			i := 0
		END Flush;
		
	BEGIN
		Files.ReadLInt(br, adr);  Files.ReadLInt(br, size);
		Texts.WriteString(W, "HeapAdr ");  Texts.WriteHex(W, adr);  
		Texts.WriteString(W, " HeapSize ");  Texts.WriteInt(W, size, 1);
		Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf);
		Files.ReadLInt(br, adr);  Files.ReadLInt(br, size);
		WHILE ~br.eof & (size # 0) DO
			Texts.WriteString(W, "Adr ");  Texts.WriteHex(W, adr);  
			Texts.WriteString(W, " Size ");  Texts.WriteInt(W, size, 1);
			i := 0;
			WHILE ~br.eof & (size # 0) DO
				Files.ReadLInt(br, x);  buf[i] := x;  INC(i);  DEC(size, 4);
				IF size MOD 1000 = 0 THEN Texts.Write(W, "."); Texts.Append(Oberon.Log, W.buf) END;
				IF i = 8 THEN Flush("3") END
			END;
			IF i # 0 THEN Flush("3") END;
			Files.ReadLInt(br, adr);  Files.ReadLInt(br, size);
			Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf)
		END;
		Texts.WriteString(W, "Entry ");  Texts.WriteHex(W, adr);
		Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf);
		Flush("7")
	END SendS;
	
	PROCEDURE SendSRec*;	(* terminalname cmdstr filename *)
	VAR S: Texts.Scanner; F: TerminalGadgets.Frame; obj: Objects.Object;  bf: Files.File;  br: Files.Rider;
	BEGIN
		Texts.OpenScanner(S,Oberon.Par.text,Oberon.Par.pos); Texts.Scan(S);
		IF S.class = Texts.Name THEN obj := Gadgets.FindObj(Gadgets.context, S.s);
			IF obj # NIL THEN F := obj(TerminalGadgets.Frame); Texts.Scan(S);
				IF (S.class = Texts.String) OR (S.class = Texts.Name) THEN
					SendString(F.text, S.s);  Texts.Scan(S);
					IF S.class = Texts.Name THEN
						bf := Files.Old(S.s);
						IF bf # NIL THEN Files.Set(br, bf, 0);  SendS(br, F.text) END
					END
				END
			END
		END
	END SendSRec;
	
	PROCEDURE FrameHandler(F: Objects.Object; VAR M: Objects.ObjMsg);
	BEGIN
		WITH F: TerminalGadgets.Frame DO
			IF (F.text(Terminal).port = -1)
				& (F.cursorState = TerminalGadgets.FullCursor)
				& ((M IS Oberon.InputMsg) & (M(Oberon.InputMsg).id = Oberon.consume)
					OR (M IS Oberon.ConsumeMsg)) THEN
				(*ignore input if not connected*)
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.s := "V24Gadgets.NewFrame"; M.res := 0
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
		NEW(F); TerminalGadgets.Open(F, FrameHandler,T, fixed);
		Objects.NewObj := F
	END NewFrame;

BEGIN
	fixed := Fonts.This("Courier8.Scn.Fnt");
	Texts.OpenWriter(W)
END V24Gadgets.

System.Free V24Gadgets ~
Gadgets.Insert V24Gadgets.NewFrame ~
