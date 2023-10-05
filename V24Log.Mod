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

MODULE V24Log;	(** portable *) (* ejz,   *)
	IMPORT Modules, V24, Input, Texts, Oberon;

	CONST
		CR = 0DX; LF = 0AX; Tab = 09X;

	VAR
		W: Texts.Writer;
		T: Oberon.Task;
		res: LONGINT;
		last: CHAR;
		Port: LONGINT;

	PROCEDURE *Poller(me: Oberon.Task);
		VAR
			avail: LONGINT;
			ch: CHAR;
	BEGIN
		avail := V24.Available(Port);
		IF avail > 0 THEN
			WHILE avail > 0 DO
				V24.Receive(Port, ch, res);
				IF ch >= " " THEN
					Texts.Write(W, ch)
				ELSIF (ch = LF) & (last # CR) THEN
					Texts.WriteLn(W)
				ELSIF (ch = CR) OR (ch = Tab) THEN
					Texts.Write(W, ch)
				END;
				last := ch; DEC(avail)
			END;
			Texts.Append(Oberon.Log, W.buf);
			me.time := Oberon.Time()
		ELSE
			me.time := Oberon.Time() + (Input.TimeUnit DIV 20)
		END
	END Poller;

	PROCEDURE GetPar(VAR port, bps, data, parity, stop: LONGINT);
	VAR S: Texts.Scanner;
	BEGIN
		port := V24.COM2;  bps := 57600;
		data := 8;  stop := V24.Stop1;  parity := V24.ParNo;
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF (S.class = Texts.Int) & (S.i >= 1) & (S.i <= 4) THEN
			CASE S.i OF
				1: port := V24.COM1
				|2: port := V24.COM2
				|3: port := V24.COM3
				|4: port := V24.COM4
			END;
			Texts.Scan(S);
			IF S.class = Texts.Int THEN
				bps := S.i;  Texts.Scan(S);
				IF (S.class = Texts.Int) & (S.i >= 5) & (S.i <= 8) THEN
					data := S.i; Texts.Scan(S);
					IF S.class IN {Texts.Name, Texts.String} THEN
						IF CAP(S.s[0]) = "N" THEN parity := V24.ParNo
						ELSIF CAP(S.s[0]) = "O" THEN parity := V24.ParOdd
						ELSIF CAP(S.s[0]) = "E" THEN parity := V24.ParEven
						ELSE parity := V24.ParNo
						END;
						Texts.Scan(S);
						IF (S.class = Texts.Int) & (S.i >= 1) & (S.i <= 2) THEN
							IF S.i = 1 THEN stop := V24.Stop1 ELSE stop := V24.Stop2 END
						END
					END
				END
			END
		END
	END GetPar;
	
	PROCEDURE Start*;	(* port bps databits none|even|odd stopbits *)
		VAR errMsg: ARRAY 32 OF CHAR;
			Baud, Data, Parity, StopB: LONGINT;
	BEGIN
		Texts.WriteString(W, "V24Log.Start ");
		IF T = NIL THEN
			GetPar(Port, Baud, Data, Parity, StopB);
			Texts.WriteInt(W, Port-V24.COM1+1, 1);  Texts.Write(W, " ");
			Texts.WriteInt(W, Baud, 1);  Texts.WriteInt(W, Data, 2);
			CASE Parity OF
				V24.ParNo: Texts.WriteString(W, " none")
				|V24.ParOdd: Texts.WriteString(W, " odd")
				|V24.ParEven: Texts.WriteString(W, " even")
			END;
			Texts.WriteInt(W, StopB, 2);  Texts.Write(W, " ");
			V24.Start(Port, Baud, Data, Parity, StopB, res);
			IF res = 0 THEN
				NEW(T); T.handle := Poller; T.time := 0; T.safe := FALSE;
				Oberon.Install(T); last := 0X
			END;
			CASE res OF
				0: errMsg := "ok"
				|1: errMsg := "port in use"
				|2: errMsg := "no such port"
				|3: errMsg := "bad bps"
				|4: errMsg := "bad data"
			ELSE
				errMsg := "failed"
			END
		ELSE
			errMsg := "log in use"
		END;
		Texts.WriteString(W, errMsg);
		Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END Start;

	PROCEDURE *stop();
	BEGIN
		IF T # NIL THEN
			V24.Stop(Port);
			Oberon.Remove(T); T := NIL
		END
	END stop;

	PROCEDURE Stop*;
	BEGIN
		Texts.WriteString(W, "V24Log.Stop ");
		IF T # NIL THEN
			stop();
			Texts.WriteString(W, "ok")
		ELSE
			Texts.WriteString(W, "not started")
		END;
		Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END Stop;

	PROCEDURE Send*;
		VAR S: Texts.Scanner;
	BEGIN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(S);
		IF S.class IN {Texts.Name, Texts.String} THEN
			V24.SendBytes(Port, S.s, S.len, res)
		END
	END Send;

	PROCEDURE SendLn*;
		VAR str: ARRAY 4 OF CHAR;
	BEGIN
		str[0] := CR; str[1] := LF; str[2] := 0X;
		V24.SendBytes(Port, str, 2, res)
	END SendLn;

BEGIN
	Texts.OpenWriter(W); T := NIL;
	Modules.InstallTermHandler(stop)
END V24Log.

V24Log.Start ~
V24Log.Start 1 19200 8 none 2 ~

V24Log.Stop

V24Log.Send ATZ
V24Log.SendLn
