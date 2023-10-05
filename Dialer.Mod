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

MODULE Dialer;	(** non-portable *)	(* 26.08.96 mg *)

IMPORT
	Oberon, NetSystem, Strings, Texts, Input, V24, NetBase, Modules, TextFrames;

CONST
	RI = 5;  DCD = 6;	(* input *)
	Service = "dialup";
	GrabPort = TRUE;	(* take over com port by force, if already in use *)

VAR
	W: Texts.Writer;
	script: Oberon.Task;
	host: ARRAY 64 OF CHAR;
	waitStr: ARRAY 32 OF CHAR;
	waitPos: INTEGER;
	waitTime: LONGINT;
	err, open: BOOLEAN;
	S: Texts.Scanner;
	port: INTEGER;
	dev: NetBase.Device;

PROCEDURE Delay (i: LONGINT);
VAR t: LONGINT;
BEGIN
	t := Input.Time();
	WHILE Input.Time() - t < i DO END
END Delay;

PROCEDURE Hang(port: INTEGER);
BEGIN
	V24.ClearMC(port, {V24.DTR});
	Delay(Input.TimeUnit DIV 6);
	V24.SetMC(port, {V24.DTR})
END Hang;

PROCEDURE InitComPort (port: INTEGER; baud: LONGINT);
VAR ok: BOOLEAN; res: LONGINT;
BEGIN
	ok := TRUE;
	V24.Start(port, baud, 8, V24.ParNo, 1, res);
	IF GrabPort & (res = 1) THEN
		V24.Stop(port);  V24.Start(port, baud, 8, V24.ParNo, 1, res)
	END;
	ok := FALSE;
	IF res = 0 THEN ok := TRUE
	ELSIF res = 3 THEN
		Texts.WriteString(W,"Dialer: Baudrate not supported"); Texts.WriteLn(W)
	ELSIF res = 1 THEN
		Texts.WriteString(W,"Dialer: Port already in use"); Texts.WriteLn(W)
	ELSE
		Texts.WriteString(W,"Dialer: Init error ");  Texts.WriteInt(W, res, 1); Texts.WriteLn(W)
	END;
	Texts.Append(Oberon.Log, W.buf);
	IF ~ok THEN err := TRUE END
END InitComPort;

PROCEDURE SendStr(str: ARRAY OF CHAR);
VAR ch: CHAR;  i: INTEGER;  res: LONGINT;
BEGIN
	i := 0;
	WHILE str[i] # 0X DO ch := str[i];
		IF ch = "~" THEN Delay(300)
		ELSE V24.Send(port, ch, res)
		END;
		INC(i)
	END;
	V24.Send(port, 0DX, res)
END SendStr;

PROCEDURE WaitStr(str: ARRAY OF CHAR; timeOut: LONGINT);
BEGIN
	COPY(str, waitStr);
	waitPos := 0;  waitTime := Input.Time() + timeOut
END WaitStr;

PROCEDURE StartLine;
BEGIN
	IF open THEN Texts.Write(W, "}");  open := FALSE END;
	Texts.WriteLn(W)
END StartLine;

PROCEDURE SendUser(use: BOOLEAN;  VAR err: BOOLEAN);
VAR user, passwd: ARRAY 64 OF CHAR;
BEGIN
	user := "";
	NetSystem.GetPassword(Service, host, user, passwd);
	IF (user # "") & (passwd # "") THEN
		StartLine;  Texts.WriteString(W, "Sending ");
		IF use THEN Texts.WriteString(W, "USER [");  Texts.WriteString(W, user);  SendStr(user)
		ELSE Texts.WriteString(W, "PASSWORD [***");  SendStr(passwd)
		END;
		Texts.WriteString(W, "]");  Texts.Append(Oberon.Log, W.buf);
		Texts.Scan(S)
	ELSE
		StartLine;  Texts.WriteString(W, "NetSystem.SetUser ");
		Texts.WriteString(W, Service);  Texts.WriteString(W, ":<user>@<server> ~ required");
		err := TRUE
	END
END SendUser;

PROCEDURE Call(cmd: ARRAY OF CHAR);
VAR F: TextFrames.Frame;  par: Oberon.ParList;  T: Texts.Text;
BEGIN
	IF Oberon.Par = NIL THEN par := NIL
	ELSE NEW(par); par^ := Oberon.Par^
	END;
	NEW(T); Texts.Open(T, "");
	Texts.WriteString(W, cmd);  Texts.WriteLn(W);
	Texts.Append(T, W.buf);
	F := TextFrames.NewText(T, 0);  TextFrames.Call(F, 0, FALSE);
	IF (par # NIL) & (Oberon.Par # NIL) THEN Oberon.Par^ := par^ END
END Call;

PROCEDURE DoScript(me: Oberon.Task);
VAR timo, res: LONGINT;  any: BOOLEAN;  ch: CHAR;
BEGIN
	err := FALSE;
	IF waitPos >= 0 THEN	(* wait for response *)
		any := FALSE;
		WHILE (waitPos >= 0) & (V24.Available(port) > 0) DO
			any := TRUE; V24.Receive(port, ch, res);
			IF ch = 0AX THEN (* skip *)
			ELSIF ch = 0DX THEN Texts.Write(W, "|")
			ELSIF (ch >= 20X) & (ch <= 7EX) THEN Texts.Write(W, ch)
			ELSE Texts.Write(W, CHR(147))
			END;
			IF waitPos >= 0 THEN
				IF CAP(ch) = CAP(waitStr[waitPos]) THEN
					INC(waitPos);
					IF waitStr[waitPos] = 0X THEN waitPos := -1 END	(* matched! *)
				ELSE
					waitPos := 0	(* restart *)
				END
			END
		END;
		IF any THEN Texts.Append(Oberon.Log, W.buf) END;
		IF (waitPos >= 0) & (Input.Time() - waitTime > 0) THEN
			StartLine;  Texts.WriteString(W, "Dialer: Timed out");
			err := TRUE
		END
	ELSE	(* execute next script statement *)
		IF S.class = Texts.Name THEN
			IF S.s = "USER" THEN SendUser(TRUE, err)
			ELSIF S.s = "PASSWORD" THEN SendUser(FALSE, err)
			ELSIF S.s = "START" THEN
				StartLine;  Texts.WriteString(W, "Enabling device");  Texts.Append(Oberon.Log, W.buf);
				IF (dev # NIL) & (dev.state = NetBase.pending) THEN dev.state := NetBase.open END;
				dev := NIL;  Texts.Scan(S)
			ELSIF S.s = "CALL" THEN
				Texts.Scan(S);
				IF (S.class = Texts.String) OR (S.class = Texts.Name) THEN
					StartLine;  Texts.WriteString(W, "Calling [");  Texts.WriteString(W, S.s);
					Texts.WriteString(W, "]");  Texts.Append(Oberon.Log, W.buf);
					Call(S.s);  Texts.Scan(S)
				ELSE
					StartLine;  Texts.WriteString(W, "Dialer: Command expected after CALL");
					err := TRUE
				END
			ELSE
				StartLine;  Texts.WriteString(W, "Dialer: Unknown keyword [");  Texts.WriteString(W, S.s);
				Texts.Write(W, "]");
				err := TRUE
			END
		ELSIF S.class = Texts.String THEN
			StartLine;  Texts.WriteString(W, "Sending [");  Texts.WriteString(W, S.s);
			Texts.WriteString(W, "]");  Texts.Append(Oberon.Log, W.buf);
			SendStr(S.s); Texts.Scan(S)
		ELSIF S.class = Texts.Int THEN
			timo := S.i * Input.TimeUnit; Texts.Scan(S);
			IF S.class = Texts.String THEN
				StartLine;  Texts.WriteString(W, "Waiting ");  Texts.WriteInt(W, timo DIV Input.TimeUnit, 1);
				Texts.WriteString(W, "s for [");   Texts.WriteString(W, S.s);  Texts.WriteString(W, "] {");
				open := TRUE;  Texts.Append(Oberon.Log, W.buf);
				WaitStr(S.s, timo); Texts.Scan(S)
			ELSE
				StartLine;  Texts.WriteString(W, "Dialer: Wait string expected after integer");
				err := TRUE
			END
		ELSIF S.class = Texts.Char THEN
			IF S.c = "}" THEN
				StartLine;  Texts.WriteString(W, "End of script");
				Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf);
				Oberon.Remove(script);  script := NIL;  dev := NIL
			ELSE
				StartLine;  Texts.WriteString(W, "Dialer: Unexpected character in script");
				err := TRUE
			END
		ELSE HALT(99)
		END
	END;
	IF err THEN
		Oberon.Remove(script);  script := NIL;  dev := NIL;
		Hang(port);
		Texts.WriteLn(W);  Texts.WriteString(W, "Dialer: Script aborted");
		Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf)
	END
END DoScript;

PROCEDURE GetDevice(device: ARRAY OF CHAR;  VAR devnum: LONGINT);
BEGIN
	Strings.Lower(device, device);
	IF device = "default" THEN devnum := 0
	ELSIF Strings.Prefix("device", device) & (device[6] >= "0") & (device[6] <= "9") & (device[7] = 0X) THEN
		devnum := ORD(device[6])-ORD("0")
	ELSE devnum := -1
	END
END GetDevice;

PROCEDURE Dial*;	(** config device {config.Host is used to find password, config.Init for port, config.Dial for script} *)
VAR S0: Texts.Scanner;  prefix, path: ARRAY 64 OF CHAR;  err: BOOLEAN;  devnum: LONGINT;
BEGIN err := FALSE;
	Texts.OpenScanner(S0, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S0);
	IF S0.class = Texts.Name THEN
		COPY(S0.s, prefix);  COPY(prefix, host);
		Texts.Scan(S0);
		IF S0.class = Texts.Name THEN
			GetDevice(S0.s, devnum);
			dev := NetBase.FindDevice(devnum);
			IF dev # NIL THEN
				IF dev.state = NetBase.open THEN
					dev.state := NetBase.pending;
					Texts.WriteString(W, "Warning: ");  Texts.WriteString(W, S0.s);
					Texts.WriteString(W, " device is already open");  Texts.WriteLn(W);
					Texts.Append(Oberon.Log, W.buf)
				END;
				COPY(prefix, path); Strings.Append(path, ".Init");
				Oberon.OpenScanner(S, path);
				IF S.class = Texts.Name THEN
					IF S.s = "COM1" THEN port := V24.COM1
					ELSIF S.s = "COM2" THEN port := V24.COM2
					ELSIF S.s = "COM3" THEN port := V24.COM3
					ELSIF S.s = "COM4" THEN port := V24.COM4
					ELSE HALT(99)
					END;
					Texts.Scan(S);
					IF S.class = Texts.Int THEN InitComPort(port, S.i);
						COPY(prefix, path); Strings.Append(path, ".Dial");
						Oberon.OpenScanner(S, path);
						IF script # NIL THEN Oberon.Remove(script)
						ELSE NEW(script)
						END;
						waitPos := -1; script.safe := FALSE;
						script.time := 0; script.handle := DoScript;
						Texts.WriteString(W, "Dial script started");  open := FALSE;
						Texts.Append(Oberon.Log, W.buf);
						Oberon.Install(script)
					ELSE Texts.WriteString(W, "Init syntax error"); err := TRUE
					END
				ELSE Texts.WriteString(W, "Init syntax error"); err := TRUE
				END
			ELSE Texts.WriteString(W, S0.s); Texts.WriteString(W, " device not found"); err := TRUE
			END
		ELSE Texts.WriteString(W, "Dial syntax error"); err := TRUE
		END
	ELSE Texts.WriteString(W, "Dial syntax error"); err := TRUE
	END;
	IF err THEN Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf) END
END Dial;

PROCEDURE GetPort(VAR port: INTEGER;  VAR devnum: LONGINT);
VAR S, R: Texts.Scanner;  i: LONGINT;
BEGIN
	devnum := -1;
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Name THEN
		Strings.Append(S.s, ".Init");
		Oberon.OpenScanner(R, S.s);
		IF R.s = "COM1" THEN port := V24.COM1
		ELSIF R.s = "COM2" THEN port := V24.COM2
		ELSIF R.s = "COM3" THEN port := V24.COM3
		ELSIF R.s = "COM4" THEN port := V24.COM4
		ELSE HALT(99)
		END;
		Texts.Scan(S);
		IF S.class = Texts.Name THEN GetDevice(S.s, devnum) END
	ELSE HALT(99)
	END
END GetPort;

PROCEDURE Hangup*;
VAR port: INTEGER;  devnum: LONGINT;
BEGIN
	GetPort(port, devnum);
	IF script # NIL THEN
		Texts.WriteLn(W);  Texts.WriteString(W, "Script aborted");
		Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf);
		Oberon.Remove(script);  script := NIL;  dev := NIL
	END;
	Hang(port)
END Hangup;

PROCEDURE State*;
VAR port: INTEGER;  devnum: LONGINT;  s: SET;
BEGIN
	GetPort(port, devnum);
	V24.GetMC(port, s);
	IF DCD IN s THEN	(* carrier detected *)
		Texts.WriteString(W, "Modem on-line")
	ELSE
		Texts.WriteString(W, "Modem off-line")
	END;
	IF devnum # -1 THEN
		dev := NetBase.FindDevice(devnum);
		Texts.WriteString(W, ", ");  Texts.WriteString(W, " device");
		Texts.WriteInt(W, devnum, 1);
		IF dev = NIL THEN
			Texts.WriteString(W, "not installed")
		ELSE
			IF dev.state = NetBase.closed THEN
				Texts.WriteString(W, "closed")
			ELSIF dev.state = NetBase.open THEN
				Texts.WriteString(W, "open")
			ELSIF dev.state = NetBase.pending THEN
				Texts.WriteString(W, "link pending")
			ELSE
				Texts.WriteString(W, "in state"); Texts.WriteInt(W, dev.state, 1)
			END
		END
	END;
	Texts.WriteLn(W);
	Texts.Append(Oberon.Log, W.buf)
END State;

PROCEDURE Cleanup;
BEGIN
	IF script # NIL THEN Oberon.Remove(script);  script := NIL END
END Cleanup;

BEGIN
	Texts.OpenWriter(W);
	script := NIL;  dev := NIL;  port := 1;
	Modules.InstallTermHandler(Cleanup)
END Dialer.

System.Free Dialer ~

NetSystem.SetUser dialup:pmullerppp@ETHPPP ~
Dialer.Dial ETHPPP default
Dialer.State ETHPPP default
Dialer.Hangup ETHPPP
