(* OBERON System 3, Release 2.3.

Copyright 1999 ETH Zürich Institute for Computer Systems, 
ETH Center, CH-8092 Zürich.  e-mail: oberon@inf.ethz.ch.

This module may be used under the conditions of the general Oberon 
System 3 license contract.  The full text can be downloaded from

	"ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/license.txt;type=A"

Under the license terms stated it is in particular (a) prohibited to modify
the interface of this module in any way that disagrees with the style
or content of the system and (b) requested to provide all conversions
of the source code to another platform with the name OBERON. *)

MODULE FTP; (** portable *)	(* EJZ,   *)
	IMPORT Files, Strings, Input, Display, Fonts, Texts, Oberon, NetSystem;

(** A simple single session FTP Tool using commands. Useful for transfering many files to or from the
		same server. *)

	CONST
		MaxLine = 1024; BufLen = MaxLine; MaxTry = 1000;
		Tab = 9X; Esc = 01BX; BreakChar = Esc;
		Done = 0; NotReady = 1; NotConnected = 2; WrongUser = 3; WrongPassword = 4; TimedOut = 5; LocFileNotFound = 6;
		Interrupted = 7; Disconnected = 8; Failed = MAX(INTEGER);
		MinDataPort = 1100; MaxDataPort = 1500;
		Unknown = -1; UNIX = 0; VMS = 1;
		DefConPort = 21;

	TYPE
		Session = POINTER TO SessionDesc;
		SessionDesc = RECORD
			C: NetSystem.Connection;
			dataC: NetSystem.Connection;
			reply: ARRAY MaxLine OF CHAR;
			portIPAddress: ARRAY 64 OF CHAR;
			dataIP: NetSystem.IPAdr;
			dataPort, status, system, res: INTEGER;
			ack: BOOLEAN
		END;
		EnumProc = PROCEDURE (entry: ARRAY OF CHAR);

	VAR
		S: Session;
		W: Texts.Writer;
		log: Texts.Text;
		line: ARRAY MaxLine OF CHAR;
		buffer: ARRAY BufLen OF CHAR;
		timeOut: LONGINT;
		dataPort, col: INTEGER;

	PROCEDURE Connected(C: NetSystem.Connection; mode: INTEGER): BOOLEAN;
		VAR state: INTEGER;
	BEGIN
		state := NetSystem.State(C);
		RETURN state IN {mode, NetSystem.inout}
	END Connected;

	PROCEDURE Disconnect(VAR C: NetSystem.Connection);
	BEGIN
		IF C # NIL THEN
			NetSystem.CloseConnection(C)
		END;
		C := NIL
	END Disconnect;

	PROCEDURE Connect(VAR C: NetSystem.Connection; port: INTEGER; host: ARRAY OF CHAR): BOOLEAN;
		VAR
			adr: NetSystem.IPAdr;
			res: INTEGER;
	BEGIN
		NetSystem.GetIP(host, adr);
		IF adr = NetSystem.anyIP THEN
			C := NIL; RETURN FALSE
		END;
		NetSystem.OpenConnection(C, NetSystem.anyport, adr, port, res);
		IF res # NetSystem.done THEN
			C := NIL
		END;
		RETURN res = NetSystem.done
	END Connect;

	PROCEDURE UserBreak(): BOOLEAN;
		VAR ch: CHAR;
	BEGIN
		IF Input.Available() > 0 THEN
			Input.Read(ch);
			IF ch = BreakChar THEN
				Texts.WriteString(W, "interrupted");
				Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf);
				RETURN TRUE
			END
		END;
		RETURN FALSE
	END UserBreak;

	PROCEDURE ReadResponse(S: Session; VAR sline: ARRAY OF CHAR);
		VAR
			time, i, j, cpos: LONGINT;
			code: ARRAY 8 OF CHAR;
			line: ARRAY MaxLine OF CHAR;
	BEGIN
		IF ~Connected(S.C, NetSystem.in) THEN
			COPY("Connection closed by server.", sline);
			COPY(sline, S.reply);
			S.status := 0; S.res := Disconnected;
			RETURN
		END;
		time := NetSystem.Available(S.C);
		NetSystem.ReadString(S.C, line);
		IF log # NIL THEN
			Texts.WriteString(W, line);
			Texts.WriteLn(W); Texts.Append(log, W.buf)
		END;
		Strings.StrToInt(line, time); S.status := SHORT(time);
		Strings.IntToStr(time, code);
		cpos := 0;
		WHILE code[cpos] # 0X DO
			INC(cpos)
		END;
		i := cpos+1; j := 0;
		WHILE line[i] # 0X DO
			sline[j] := line[i];
			INC(j); INC(i)
		END;
		sline[j] := 0X;
		time := Input.Time();
		IF line[cpos] = "-" THEN
			LOOP
				IF NetSystem.Available(S.C) > 0 THEN
					line[cpos] := 0X;
					NetSystem.ReadString(S.C, line);
					IF log # NIL THEN
						Texts.WriteString(W, line);
						Texts.WriteLn(W); Texts.Append(log, W.buf)
					END;
					IF line[cpos] # "-" THEN
						line[cpos] := 0X;
						IF line = code THEN
							EXIT
						END
					END;
					time := Input.Time()
				ELSIF (Input.Time()-time) >= timeOut THEN
					S.res := TimedOut;
					RETURN
				ELSIF UserBreak() THEN
					S.res := Interrupted;
					RETURN
				END
			END
		END;
		S.ack := TRUE
	END ReadResponse;

	PROCEDURE SendString(C: NetSystem.Connection; str: ARRAY OF CHAR);
		VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE str[i] # 0X DO
			INC(i)
		END;
		NetSystem.WriteBytes(C, 0, i, str)
	END SendString;

	PROCEDURE SendLine(C: NetSystem.Connection; VAR str: ARRAY OF CHAR);
	BEGIN
		SendString(C, str);
		NetSystem.WriteBytes(C, 0, 2, Strings.CRLF)
	END SendLine;

	PROCEDURE SendCmd(S: Session; str: ARRAY OF CHAR);
	BEGIN
		IF ~S.ack THEN
			ReadResponse(S, line)
		ELSE
			S.ack := FALSE
		END;
		SendLine(S.C, str)
	END SendCmd;

	PROCEDURE CloseS(S: Session);
	BEGIN
		S.ack := TRUE;
		SendCmd(S, "QUIT"); ReadResponse(S, S.reply);
		Disconnect(S.dataC); Disconnect(S.C);
		S.res := Done
	END CloseS;

	PROCEDURE Close2(S: Session);
	BEGIN
		S.ack := TRUE;
		SendCmd(S, "QUIT");
		Disconnect(S.dataC); Disconnect(S.C)
	END Close2;

	PROCEDURE QuerySystem(S: Session);
		VAR pos: LONGINT;
	BEGIN
		S.system := UNIX;
		SendCmd(S, "SYST"); ReadResponse(S, line);
		IF (S.status >= 200) & (S.status < 300) THEN
			pos := 0;
			Strings.Search("VMS", line, pos);
			IF pos >= 0 THEN
				S.system := VMS
			END
		END
	END QuerySystem;

	PROCEDURE QueryString(key: ARRAY OF CHAR; VAR s: ARRAY OF CHAR): BOOLEAN;
		VAR S: Texts.Scanner; lKey: ARRAY 32 OF CHAR;
	BEGIN
		lKey := "NetSystem."; Strings.Append(lKey, key);
		Oberon.OpenScanner(S, lKey);
		IF S.class IN {Texts.Name, Texts.String} THEN
			COPY(S.s, s)
		ELSE
			COPY("", s)
		END;
		RETURN s # ""
	END QueryString;

	PROCEDURE GetLogin(VAR host, usr, passw: ARRAY OF CHAR);
	BEGIN
		IF (usr = "ftp") OR (usr = "anonymous") OR (usr = "") THEN
			IF ~QueryString("EMail", passw) OR (passw[0] = "<") THEN
				COPY("anonymous@host.nowhere", passw)
			END;
			IF usr = "" THEN
				COPY("anonymous", usr)
			END
		ELSIF passw = "" THEN
			NetSystem.GetPassword("ftp", host, usr, passw)
		END
	END GetLogin;

	PROCEDURE OpenS(server, user, passwd: ARRAY OF CHAR; port: INTEGER; VAR S: Session);
	BEGIN
		GetLogin(server, user, passwd);
		NEW(S); S.dataC := NIL; S.dataPort := -1;
		IF NetSystem.hostIP = NetSystem.anyIP THEN
			S.C := NIL;
			S.reply := "invalid NetSystem.hostIP";
			S.res := Failed;
			RETURN
		END;
		S.system := Unknown;
		S.reply := "connecting failed";
		S.portIPAddress := "";
		S.ack := TRUE;
		IF (user = "") OR (passwd = "") THEN
			S.res := Failed;
			S.reply := "no password or username specified";
			RETURN
		END;
		IF Connect(S.C, port, server) THEN
			ReadResponse(S, S.reply);
			IF (S.status >= 200) & (S.status < 300) THEN
				line := "USER "; Strings.Append(line, user);
				SendCmd(S, line); ReadResponse(S, line);
				IF (S.status = 330) OR (S.status = 331) THEN
					line := "PASS "; Strings.Append(line, passwd);
					SendCmd(S, line); ReadResponse(S, line);
					IF (S.status = 230) OR (S.status= 330) THEN
						S.res := Done
					ELSE
						S.res := WrongPassword; COPY(line, S.reply);
						Close2(S)
					END
				ELSIF S.status # 230 THEN
					S.res := WrongUser; COPY(line, S.reply);
					Close2(S)
				ELSE
					S.res := Done
				END;
				IF S.res # Done THEN
					NetSystem.DelPassword("ftp", user, server)
				END
			ELSE
				S.res := NotReady;
				Close2(S)
			END
		ELSE
			S.res := NotConnected
		END;
		IF S.res = Done THEN
			SendCmd(S, "TYPE I");
			ReadResponse(S, line);
			IF S.status # 200 THEN
				(* should not happen *)
			END;
			QuerySystem(S);
			S.res := Done
		END
	END OpenS;

	PROCEDURE ChangeDirS(S: Session; newDir: ARRAY OF CHAR);
	BEGIN
		S.reply := "CWD ";
		Strings.Append(S.reply, newDir);
		SendCmd(S, S.reply);
		ReadResponse(S, S.reply);
		IF S.status = 250 THEN
			S.res := Done
		ELSE
			S.res := Failed
		END
	END ChangeDirS;

	PROCEDURE SetDataPort(S: Session);
		VAR str: ARRAY 4 OF CHAR; p0, p1: LONGINT; i, j, k: INTEGER; done: BOOLEAN;
	BEGIN
		SendCmd(S, "PASV"); ReadResponse(S, line);
		IF (S.status >= 200) & (S.status < 300) THEN
			S.res := Interrupted; i := 0;
			WHILE (line[i] # 0X) & ~Strings.IsDigit(line[i]) DO INC(i) END;
			j := 0; k := 0;
			WHILE (line[i] # 0X) & (k < 4) DO
				IF line[i] # "," THEN
					S.portIPAddress[j] := line[i]
				ELSE
					S.portIPAddress[j] := "."; INC(k)
				END;
				INC(i); INC(j)
			END;
			IF (j <= 0) & (k < 4) THEN RETURN END;
			S.portIPAddress[j-1] := 0X;
			NetSystem.ToHost(S.portIPAddress, S.dataIP, done);
			IF ~done THEN RETURN END;
			WHILE (line[i] # 0X) & ((line[i] <= " ") OR (line[i] = ",")) DO INC(i) END;
			Strings.StrToIntPos(line, p0, i);
			WHILE (line[i] # 0X) & ((line[i] <= " ") OR (line[i] = ",")) DO INC(i) END;
			Strings.StrToIntPos(line, p1, i);
			S.dataPort := SHORT(256*p0+p1);
			S.res := Done
		ELSE
			S.dataIP := NetSystem.anyIP;
			S.dataPort := dataPort;
			REPEAT
				IF S.dataPort >= MaxDataPort THEN
					S.dataPort := MinDataPort
				END;
				INC(S.dataPort);
				(* not 100% safe *)
				NetSystem.OpenConnection(S.dataC, S.dataPort, NetSystem.anyIP, NetSystem.anyport, S. res)
			UNTIL (S.res = NetSystem.done) OR UserBreak();
			IF S.res = NetSystem.done THEN
				dataPort := S.dataPort; S.res := Failed;
				NetSystem.ToNum(NetSystem.hostIP, S.portIPAddress);
				i := 0;
				WHILE S.portIPAddress[i] # 0X DO
					IF S.portIPAddress[i] = "." THEN
						S.portIPAddress[i] := ","
					END;
					INC(i)
				END;
				Strings.AppendCh(S.portIPAddress, ",");
				Strings.IntToStr(S.dataPort DIV 256, str);
				Strings.Append(S.portIPAddress, str);
				Strings.AppendCh(S.portIPAddress, ",");
				Strings.IntToStr(S.dataPort MOD 256, str);
				Strings.Append(S.portIPAddress, str);
				line := "PORT "; Strings.Append(line, S.portIPAddress);
				SendCmd(S, line)
			ELSE
				Disconnect(S.dataC); S.dataC := NIL;
				S.reply := "Interrupted"; S.res := Interrupted
			END
		END
	END SetDataPort;

	PROCEDURE WaitDataCon(S: Session): NetSystem.Connection;
		VAR
			time: LONGINT;
			C1: NetSystem.Connection;
	BEGIN
		IF S.dataIP = NetSystem.anyIP THEN
			time := Input.Time();
			REPEAT
			UNTIL NetSystem.Requested(S.dataC) OR ((Input.Time()-time) > timeOut) OR UserBreak();
			IF NetSystem.Requested(S.dataC) THEN
				NetSystem.Accept(S.dataC, C1, S.res); Disconnect(S.dataC);
				IF S.res = NetSystem.done THEN
					S.res := Done;
					RETURN C1
				ELSE
					S.res := Failed
				END
			ELSIF (Input.Time()-time) > timeOut THEN
				S.res := TimedOut
			ELSE
				S.res := Interrupted
			END;
			Disconnect(S.dataC)
		ELSE
			NetSystem.OpenConnection(C1, NetSystem.anyport, S.dataIP, S.dataPort, S.res);
			IF S.res = Done THEN RETURN C1 END
		END;
		RETURN NIL
	END WaitDataCon;

	PROCEDURE EnumDir(S: Session; enum: EnumProc);
		VAR
			C: NetSystem.Connection;
			len: LONGINT;
	BEGIN
		S.reply := ""; SetDataPort(S);
		IF S.res = Interrupted THEN RETURN END;
		IF S.dataIP = NetSystem.anyIP THEN
			ReadResponse(S, line)
		ELSE
			C := WaitDataCon(S);
			IF S.res = Done THEN S.status := 200 END
		END;
		IF S.status = 200 THEN
			IF S.system = VMS THEN
				SendCmd(S, "NLST")
			ELSE
				SendCmd(S, "LIST")
			END;
			ReadResponse(S, S.reply);
			IF (S.status = 150) OR (S.status = 250) THEN
				IF S.dataIP = NetSystem.anyIP THEN C := WaitDataCon(S) END;
				IF S.res = Done THEN
					S.res := Done;
					len := NetSystem.Available(C);
					WHILE ((len > 0) OR Connected(C, NetSystem.in)) & ~UserBreak() DO
						IF len > 0 THEN
							NetSystem.ReadString(C, line);
							enum(line)
						END;
						len := NetSystem.Available(C)
					END;
					Disconnect(C)
				END;
				ReadResponse(S, S.reply)
			ELSE
				S.res := Failed
			END
		END;
		IF S.dataC # NIL THEN Disconnect(S.dataC) END
	END EnumDir;

	PROCEDURE GetCurDir(S: Session; VAR curdir: ARRAY OF CHAR);
		VAR i, j: INTEGER;
	BEGIN
		SendCmd(S, "PWD");
		ReadResponse(S, S.reply);
		IF S.status = 257 THEN
			IF S.system = VMS THEN
				COPY(S.reply, curdir);
				i := 0;
				WHILE curdir[i] > " " DO
					INC(i)
				END;
				curdir[i] := 0X
			ELSE
				i := 0;
				WHILE (S.reply[i] # 0X) & (S.reply[i] # 22X) DO
					INC(i)
				END;
				j := 0;
				IF S.reply[i] = 22X THEN
					INC(i);
					WHILE (S.reply[i] # 0X) & (S.reply[i] # 22X) DO
						curdir[j] := S.reply[i];
						INC(j); INC(i)
					END
				END;
				curdir[j] := 0X
			END;
			S.res := Done
		ELSE
			COPY("", curdir);
			S.res := Failed
		END
	END GetCurDir;

	PROCEDURE MakeDirS(S: Session; newDir: ARRAY OF CHAR);
	BEGIN
		S.reply := "MKD ";
		Strings.Append(S.reply, newDir);
		SendCmd(S, S.reply);
		ReadResponse(S, S.reply);
		IF S.status = 257 THEN
			S.res := Done
		ELSE
			S.res := Failed
		END
	END MakeDirS;

	PROCEDURE RmDirS(S: Session; dir: ARRAY OF CHAR);
	BEGIN
		S.reply := "RMD ";
		Strings.Append(S.reply, dir);
		SendCmd(S, S.reply);
		ReadResponse(S, S.reply);
		IF S.status = 250 THEN
			S.res := Done
		ELSE
			S.res := Failed
		END
	END RmDirS;

	PROCEDURE DeleteFile(S: Session; remName: ARRAY OF CHAR);
	BEGIN
		S.reply := "DELE ";
		Strings.Append(S.reply, remName);
		SendCmd(S, S.reply);
		ReadResponse(S, S.reply);
		IF S.status = 250 THEN
			S.res := Done
		ELSE
			S.res := Failed
		END
	END DeleteFile;

	PROCEDURE ReadData(C: NetSystem.Connection; VAR R: Files.Rider);
		VAR len, rlen, try: LONGINT;
	BEGIN
		try := 0;
		len := NetSystem.Available(C);
		WHILE (len > 0) OR Connected(C, NetSystem.in) DO
			IF UserBreak() THEN
				RETURN
			END;
			IF len > BufLen THEN
				rlen := BufLen
			ELSE
				rlen := len
			END;
			NetSystem.ReadBytes(C, 0, rlen, buffer);
			Files.WriteBytes(R, buffer, rlen);
			DEC(len, rlen);
			IF len <= 0 THEN
				len := NetSystem.Available(C);
				IF len <= 0 THEN
					INC(try);
					IF try > MaxTry THEN
						RETURN
					END
				ELSE
					try := 0
				END
			END
		END
	END ReadData;

	PROCEDURE GetF(S: Session; remName: ARRAY OF CHAR; VAR R: Files.Rider);
		VAR C: NetSystem.Connection;
	BEGIN
		S.reply := ""; SetDataPort(S);
		IF S.res = Interrupted THEN RETURN END;
		IF S.dataIP = NetSystem.anyIP THEN
			ReadResponse(S, line)
		ELSE
			C := WaitDataCon(S);
			IF S.res = Done THEN S.status := 200 END
		END;
		IF S.status = 200 THEN
			line := "RETR ";
			Strings.Append(line, remName);
			SendCmd(S, line);
			ReadResponse(S, line);
			COPY(line, S.reply);
			IF (S.status = 150) OR (S.status = 250) THEN
				IF S.dataIP = NetSystem.anyIP THEN C := WaitDataCon(S) END;
				IF S.res = Done THEN
					ReadData(C, R);
					Disconnect(C)
				END;
				ReadResponse(S, S.reply);
				IF S.res = Interrupted THEN
					ReadResponse(S, line)
				END
			ELSE
				S.res := Failed
			END
		END;
		IF S.dataC # NIL THEN Disconnect(S.dataC) END
	END GetF;

	PROCEDURE GetFile(S: Session; remName, locName: ARRAY OF CHAR);
		VAR
			F: Files.File;
			R: Files.Rider;
	BEGIN
		F := Files.New(locName);
		Files.Set(R, F, 0);
		GetF(S, remName, R);
		Files.Register(F)
	END GetFile;

	PROCEDURE WriteData(C: NetSystem.Connection; VAR R: Files.Rider);
	BEGIN
		Files.ReadBytes(R, buffer, BufLen);
		WHILE ~R.eof DO
			NetSystem.WriteBytes(C, 0, BufLen, buffer);
			Files.ReadBytes(R, buffer, BufLen)
		END;
		IF R.res > 0 THEN
			NetSystem.WriteBytes(C, 0, BufLen-R.res, buffer)
		END
	END WriteData;

	PROCEDURE PutFile(S: Session; remName, locName: ARRAY OF CHAR);
		VAR
			F: Files.File;
			R: Files.Rider;
			C: NetSystem.Connection;
	BEGIN
		S.reply := "";
		F := Files.Old(locName);
		IF F # NIL THEN
			SetDataPort(S);
			IF S.res = Interrupted THEN RETURN END;
			IF S.dataIP = NetSystem.anyIP THEN
				ReadResponse(S, line)
			ELSE
				C := WaitDataCon(S);
				IF S.res = Done THEN S.status := 200 END
			END;
			IF S.status = 200 THEN
				line := "STOR ";
				Strings.Append(line, remName);
				SendCmd(S, line);
				ReadResponse(S, S.reply);
				IF (S.status = 150) OR (S.status = 250) THEN
					IF S.dataIP = NetSystem.anyIP THEN C := WaitDataCon(S) END;
					IF S.res = Done THEN
						Files.Set(R, F, 0);
						WriteData(C, R);
						Disconnect(C)
					END;
					ReadResponse(S, S.reply)
				ELSE
					S.res := Failed
				END
			END
		ELSE
			COPY(locName, S.reply);
			Strings.Append(S.reply, " not found");
			S.res := LocFileNotFound
		END;
		IF S.dataC # NIL THEN Disconnect(S.dataC) END
	END PutFile;

	PROCEDURE ReadText(C: NetSystem.Connection; VAR W: Texts.Writer);
		VAR
			len, rlen, i: LONGINT;
			ch: CHAR;
	BEGIN
		len := NetSystem.Available(C);
		WHILE (len > 0) OR Connected(C, NetSystem.in) DO
			IF len > (BufLen-2) THEN
				rlen := BufLen-2
			ELSE
				rlen := len
			END;
			NetSystem.ReadBytes(C, 0, rlen, buffer);
			i := 0;
			WHILE i < rlen DO
				ch := buffer[i];
				IF ch = Strings.CR THEN
					(* ignore CR *)
				ELSIF ch = Strings.LF THEN
					Texts.WriteLn(W)
				ELSE
					ch := Strings.ISOToOberon[ORD(ch)];
					Texts.Write(W, ch)
				END;
				INC(i)
			END;
			DEC(len, rlen);
			IF len <= 0 THEN
				len := NetSystem.Available(C)
			END
		END
	END ReadText;

	PROCEDURE GetText(S: Session; remName: ARRAY OF CHAR; VAR W: Texts.Writer);
		VAR C: NetSystem.Connection;
	BEGIN
		S.reply := "";
		SendCmd(S, "TYPE A");
		ReadResponse(S, line);
		SetDataPort(S);
		IF S.res = Interrupted THEN SendCmd(S, "TYPE I"); ReadResponse(S, line); RETURN END;
		IF S.dataIP = NetSystem.anyIP THEN
			ReadResponse(S, line)
		ELSE
			C := WaitDataCon(S);
			IF S.res = Done THEN S.status := 200 END
		END;
		IF S.status = 200 THEN
			line := "RETR ";
			Strings.Append(line, remName);
			SendCmd(S, line);
			ReadResponse(S, line);
			COPY(line, S.reply);
			IF (S.status = 150) OR (S.status = 250) THEN
				IF S.dataIP = NetSystem.anyIP THEN C := WaitDataCon(S) END;
				IF S.res = Done THEN
					ReadText(C, W);
					Disconnect(C)
				END;
				ReadResponse(S, S.reply);
				IF S.res = Interrupted THEN
					ReadResponse(S, line)
				END
			ELSE
				S.res := Failed
			END
		END;
		IF S.dataC # NIL THEN Disconnect(S.dataC) END;
		SendCmd(S, "TYPE I");
		ReadResponse(S, line)
	END GetText;

	PROCEDURE WriteText(C: NetSystem.Connection; T: Texts.Text);
		VAR
			R: Texts.Reader;
			ch: CHAR;
	BEGIN
		Texts.OpenReader(R, T, 0);
		Texts.Read(R, ch);
		WHILE ~R.eot DO
			IF R.lib IS Fonts.Font THEN
				IF ch = Strings.CR THEN
					NetSystem.WriteBytes(C, 0, 2, Strings.CRLF)
				ELSIF ch # Strings.LF THEN
					ch := Strings.OberonToISO[ORD(ch)];
					NetSystem.Write(C, ch)
				END
			END;
			Texts.Read(R, ch)
		END
	END WriteText;

	PROCEDURE PutText(S: Session; remName: ARRAY OF CHAR; text: Texts.Text);
		VAR C: NetSystem.Connection;
	BEGIN
		S.reply := "";
		SendCmd(S, "TYPE A");
		ReadResponse(S, line);
		IF (S.status < 200) OR (S.status >= 300) THEN
			RETURN
		END;
		SetDataPort(S);
		IF S.res = Interrupted THEN SendCmd(S, "TYPE I"); ReadResponse(S, line); RETURN END;
		IF S.dataIP = NetSystem.anyIP THEN
			ReadResponse(S, line)
		ELSE
			C := WaitDataCon(S);
			IF S.res = Done THEN S.status := 200 END
		END;
		IF S.status = 200 THEN
			line := "STOR ";
			Strings.Append(line, remName);
			SendCmd(S, line);
			ReadResponse(S, S.reply);
			IF (S.status = 150) OR (S.status = 250) THEN
				IF S.dataIP = NetSystem.anyIP THEN C := WaitDataCon(S) END;
				IF S.res = Done THEN
					WriteText(C, text);
					Disconnect(C)
				END;
				ReadResponse(S, S.reply)
			ELSE
				S.res := Failed
			END
		END;
		IF S.dataC # NIL THEN Disconnect(S.dataC) END;
		SendCmd(S, "TYPE I");
		ReadResponse(S, line)
	END PutText;

	PROCEDURE ShowRes();
	BEGIN
		Texts.WriteString(W, S.reply);
		Texts.WriteLn(W);
		Texts.Append(log, W.buf)
	END ShowRes;

	PROCEDURE OpenScanner(VAR S: Texts.Scanner);
		VAR
			beg, end, time: LONGINT;
			text: Texts.Text;
	BEGIN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "^") THEN
			time := -1;
			text := NIL;
			Oberon.GetSelection(text, beg, end, time);
			IF (text # NIL) & (time >= 0) THEN
				Texts.OpenScanner(S, text, beg);
				Texts.Scan(S)
			END
		END
	END OpenScanner;

	PROCEDURE SplitFTPAdr(VAR url, host, path, user, passwd: ARRAY OF CHAR; VAR type: CHAR; VAR port: INTEGER): BOOLEAN;
		VAR i, j, l: LONGINT;
		PROCEDURE Blanks();
		BEGIN
			WHILE (url[i] # 0X) & (url[i] <= " ") DO
				INC(i)
			END
		END Blanks;
	BEGIN
		type := 0X; port := DefConPort;
		COPY("", user); COPY("", passwd);
		i := 0; Blanks();
		(* look ahead for @ *)
		j := i;
		WHILE (url[j] # 0X) & (url[j] # "@") & (url[j] # "/") DO
			INC(j)
		END;
		IF url[j] = "@" THEN
			(* get user *)
			l := LEN(user)-1; j := 0;
			WHILE (url[i] # 0X) & (url[i] # ":") & (url[i] # "@") DO
				IF (j < l) THEN
					user[j] := url[i]; INC(j)
				END;
				INC(i)
			END;
			user[j] := 0X; DEC(j);
			WHILE (j >= 0) & (user[j] <= " ") DO
				user[j] := 0X; DEC(j)
			END;
			IF url[i] = ":" THEN
				(* get password *)
				l := LEN(passwd);
				INC(i); Blanks(); j := 0;
				WHILE (url[i] # 0X) &  (url[i] # "@") DO
					IF j < l THEN
						passwd[j] := url[i]; INC(j)
					END;
					INC(i)
				END;
				passwd[j] := 0X; DEC(j);
				WHILE (j >= 0) & (passwd[j] <= " ") DO
					passwd[j] := 0X; DEC(j)
				END
			END;
			INC(i); Blanks()
		END;
		(* get host *)
		l := LEN(host); j := 0;
		WHILE (url[i] # 0X) & (url[i] # ":") & (url[i] # "/") DO
			IF j < l THEN
				host[j] := url[i]; INC(j)
			END;
			INC(i)
		END;
		host[j] := 0X; DEC(j);
		WHILE (j >= 0) & (host[j] <= " ") DO
			host[j] := 0X; DEC(j)
		END;
		IF url[i] = ":" THEN
			port := 0; INC(i);
			WHILE (url[i] # "/") & (url[i] # 0X) DO
				IF Strings.IsDigit(url[i]) THEN
					port := port*10+ORD(url[i])-ORD("0")
				END;
				INC(i)
			END;
			IF port <= 0 THEN
				port := DefConPort
			END
		END;
		(* get path *)
		l := LEN(path); j := 0;
		IF url[i] # 0X THEN
			path[j] := url[i]; INC(j); INC(i);
			IF url[i] = "~" THEN
				j := 0
			END
		END;
		WHILE (url[i] # 0X) & (url[i] # ";") DO
			IF j < l THEN
				path[j] := url[i]; INC(j)
			END;
			INC(i)
		END;
		path[j] := 0X; DEC(j);
		WHILE (j >= 0) & (path[j] <= " ") DO
			path[j] := 0X; DEC(j)
		END;
		IF url[i] = ";" THEN
			INC(i); Blanks();
			IF CAP(url[i]) # "T" THEN
				type := CAP(url[i])
			ELSE
				WHILE (url[i] # 0X) & (url[i] # "=") DO
					INC(i)
				END;
				IF url[i] = "=" THEN
					INC(i); Blanks();
					type := CAP(url[i])
				ELSE
					type := "T"
				END
			END
		END;
		RETURN (host # "") & (port > 0)
	END SplitFTPAdr;

(** FTP.Open (server | "^")
		Open an ftp connection to server using username and password set with FTP.SetUser. *)
	PROCEDURE Open*;
		VAR
			Sc: Texts.Scanner;
			host, path, user, passwd: ARRAY 64 OF CHAR;
			port: INTEGER;
			type: CHAR;
	BEGIN
		IF S = NIL THEN
			OpenScanner(Sc);
			IF Sc.class IN {Texts.Name, Texts.String} THEN
				IF SplitFTPAdr(Sc.s, host, path, user, passwd, type, port) THEN
					OpenS(host, user, passwd, port, S);
					ShowRes();
					IF S.res # Done THEN
						S := NIL
					END
				END
			END
		ELSE
			Texts.WriteString(W, "already connected");
			Texts.WriteLn(W);
			Texts.Append(log, W.buf)
		END
	END Open;

	PROCEDURE Con(): BOOLEAN;
	BEGIN
		IF S = NIL THEN
			Texts.WriteString(W, "not connected");
			Texts.WriteLn(W);
			Texts.Append(log, W.buf);
			RETURN FALSE
		ELSE
			RETURN TRUE
		END
	END Con;

(** FTP.Close
		Close an previously opened FTP connection. *)
	PROCEDURE Close*;
	BEGIN
		IF Con() THEN
			CloseS(S);
			ShowRes();
			IF S.res = Done THEN
				S := NIL
			END
		END
	END Close;

(** FTP.ChangeDir (newdir | "^")
		Change the current directory on the FTP server to newdir. *)
	PROCEDURE ChangeDir*;
		VAR Sc: Texts.Scanner;
	BEGIN
		IF Con() THEN
			OpenScanner(Sc);
			IF Sc.class IN {Texts.Name, Texts.String} THEN
				ChangeDirS(S, Sc.s);
				ShowRes()
			END
		END
	END ChangeDir;

	PROCEDURE *ShowEntry(entry: ARRAY OF CHAR);
	BEGIN
		Texts.WriteString(W, entry);
		Texts.WriteLn(W);
		Texts.Append(log, W.buf)
	END ShowEntry;

(** FTP.Dir
		List the contents of the current directory on the FTP server. *)
	PROCEDURE Dir*;
	BEGIN
		IF Con() THEN
			EnumDir(S, ShowEntry);
			ShowRes()
		END
	END Dir;

	PROCEDURE *ShowCompactEntry(entry: ARRAY OF CHAR);
		VAR i: INTEGER;
	BEGIN
		i := 0;
		WHILE entry[i] # 0X DO
			INC(i)
		END;
		IF i > 0 THEN DEC(i) ELSE RETURN END;
		WHILE (i > 0) & (entry[i] > " ") DO
			DEC(i)
		END;
		IF entry[i] <= " " THEN
			INC(i)
		END;
		WHILE entry[i] # 0X DO
			INC(col);
			Texts.Write(W, entry[i]);
			INC(i)
		END;
		INC(col);
		IF col >= 50  THEN
			Texts.WriteLn(W);
			col := 0
		ELSE
			INC(col);
			Texts.Write(W, Tab)
		END;
		Texts.Append(log, W.buf)
	END ShowCompactEntry;

(** FTP.CompactDir
		List the contents of the current directory on the FTP server in a more
		compact form. *)
	PROCEDURE CompactDir*;
	BEGIN
		IF Con() THEN
			col := 0;
			EnumDir(S, ShowCompactEntry);
			IF col > 0 THEN
				Texts.WriteLn(W);
				Texts.Append(log, W.buf)
			END;
			ShowRes()
		END
	END CompactDir;

(** FTP.CurDir
		Display the current path on the FTP server *)
	PROCEDURE CurDir*;
		VAR curdir: ARRAY 256 OF CHAR;
	BEGIN
		IF Con() THEN
			GetCurDir(S, curdir);
			ShowRes()
		END
	END CurDir;

(** FTP.MakeDir (server | "^")
		Create a new directory. *)
	PROCEDURE MakeDir*;
		VAR Sc: Texts.Scanner;
	BEGIN
		IF Con() THEN
			OpenScanner(Sc);
			IF Sc.class IN {Texts.Name, Texts.String} THEN
				MakeDirS(S, Sc.s);
				ShowRes()
			END
		END
	END MakeDir;

(** FTP.RmDir (server | "^")
		Remove an existing directory. *)
	PROCEDURE RmDir*;
		VAR Sc: Texts.Scanner;
	BEGIN
		IF Con() THEN
			OpenScanner(Sc);
			IF Sc.class IN {Texts.Name, Texts.String} THEN
				RmDirS(S, Sc.s);
				ShowRes()
			END
		END
	END RmDir;

(** FTP.DeleteFiles ({remname} | "^")
		Delete the files remname on the FTP server. *)
	PROCEDURE DeleteFiles*;
		VAR
			Sc: Texts.Scanner;
			beg, end, time, pos: LONGINT;
			text: Texts.Text;
	BEGIN
		IF Con() THEN
			end := Oberon.Par.text.len;
			Texts.OpenScanner(Sc, Oberon.Par.text, Oberon.Par.pos);
			pos := Texts.Pos(Sc);
			Texts.Scan(Sc);
			IF (Sc.class = Texts.Char) & (Sc.c = "^") THEN
				time := -1;
				text := NIL;
				Oberon.GetSelection(text, beg, end, time);
				IF (text # NIL) & (time >= 0) THEN
					Texts.OpenScanner(Sc, text, beg);
					pos := Texts.Pos(Sc);
					Texts.Scan(Sc)
				ELSE
					end := Oberon.Par.text.len
				END
			END;
			Texts.WriteString(W, "FTP.DeleteFile");
			Texts.WriteLn(W);
			Texts.Append(log, W.buf);
			WHILE (Sc.class IN {Texts.Name, Texts.String}) & (pos < end) & (S.res = Done) DO
				Texts.Write(W, Tab);
				Texts.WriteString(W, Sc.s);
				Texts.Write(W, Tab);
				Texts.Append(log, W.buf);
				DeleteFile(S, Sc.s);
				ShowRes();
				pos := Texts.Pos(Sc);
				Texts.Scan(Sc)
			END
		END
	END DeleteFiles;

	PROCEDURE ScanPair(VAR S: Texts.Scanner; VAR name1, name2: ARRAY OF CHAR): BOOLEAN;
	BEGIN (* while loop from pieter *)
		WHILE ~(S.class IN {Texts.Name, Texts.String}) & ((S.class # Texts.Char) OR (S.c # "~")) & ~S.eot DO
			Texts.Scan(S)
		END;
		IF S.class IN {Texts.Name, Texts.String} THEN
			COPY(S.s, name1);
			Texts.Scan(S);
			IF (S.class = Texts.Char) & (S.c = "=") THEN
				Texts.Scan(S);
				IF (S.class = Texts.Char) & (S.c = ">") THEN
					Texts.Scan(S);
					IF S.class IN {Texts.Name, Texts.String} THEN
						COPY(S.s, name2);
						Texts.Scan(S);
						RETURN TRUE
					END
				END
			ELSE
				COPY(name1, name2);
				RETURN TRUE
			END
		END;
		RETURN FALSE
	END ScanPair;

(** FTP.GetFiles ({remname "=>" locname} | "^")
		Get files remname from the FTP server and store them as locname. *)
	PROCEDURE GetFiles*;
		VAR
			Sc: Texts.Scanner;
			loc, rem: ARRAY LEN(Sc.s) OF CHAR;
	BEGIN
		IF Con() THEN
			OpenScanner(Sc);
			Texts.WriteString(W, "FTP.GetFile");
			Texts.WriteLn(W);
			Texts.Append(log, W.buf);
			WHILE ScanPair(Sc, rem, loc) & (S.res = Done) DO
				Texts.Write(W, Tab);
				Texts.WriteString(W, rem);
				Texts.WriteString(W, " => ");
				Texts.WriteString(W, loc);
				Texts.Write(W, Tab);
				Texts.Append(log, W.buf);
				GetFile(S, rem, loc);
				Texts.Append(log, W.buf);
				Texts.WriteLn(W);
				ShowRes()
			END
		END
	END GetFiles;

(** FTP.GetTexts ({remname "=>" locname} | "^")
		Get text-files remname from the FTP server and store them as locname. *)
	PROCEDURE GetTexts*;
		VAR
			Sc: Texts.Scanner;
			loc, rem: ARRAY LEN(Sc.s) OF CHAR;
			T: Texts.Text;
			F: Files.File;
			len: LONGINT;
			Wr: Texts.Writer;
	BEGIN
		IF Con() THEN
			OpenScanner(Sc);
			Texts.WriteString(W, "FTP.GetText");
			Texts.WriteLn(W);
			Texts.Append(log, W.buf);
			WHILE ScanPair(Sc, rem, loc) & (S.res = Done) DO
				Texts.Write(W, Tab);
				Texts.WriteString(W, rem);
				Texts.WriteString(W, " => ");
				Texts.WriteString(W, loc);
				Texts.Write(W, Tab);
				Texts.Append(log, W.buf);
				Texts.OpenWriter(Wr);
				GetText(S, rem, Wr);
				NEW(T); Texts.Open(T, "");
				Texts.Append(T, Wr.buf);
				F := Files.New(loc);
				Texts.Store(T, F, 0, len);
				Files.Register(F);
				ShowRes()
			END
		END
	END GetTexts;

(** FTP.PutFiles ({locname "=>" remname} | "^")
		Put files locname as remname on the FTP server. *)
	PROCEDURE PutFiles*;
		VAR
			Sc: Texts.Scanner;
			loc, rem: ARRAY LEN(Sc.s) OF CHAR;
	BEGIN
		IF Con() THEN
			OpenScanner(Sc);
			Texts.WriteString(W, "FTP.PutFile");
			Texts.WriteLn(W);
			Texts.Append(log, W.buf);
			WHILE ScanPair(Sc, loc, rem) & (S.res = Done) DO
				Texts.Write(W, Tab);
				Texts.WriteString(W, loc);
				Texts.WriteString(W, " => ");
				Texts.WriteString(W, rem);
				Texts.Write(W, Tab);
				Texts.Append(log, W.buf);
				PutFile(S, rem, loc);
				Texts.WriteLn(W);
				ShowRes()
			END
		END
	END PutFiles;

(** FTP.PutTexts ({locname "=>" remname} | "^")
		Put text-files locname as remname on the FTP server. *)
	PROCEDURE PutTexts*;
		VAR
			Sc: Texts.Scanner;
			loc, rem: ARRAY LEN(Sc.s) OF CHAR;
			text: Texts.Text;
	BEGIN
		IF Con() THEN
			OpenScanner(Sc);
			Texts.WriteString(W, "FTP.PutFile");
			Texts.WriteLn(W);
			Texts.Append(log, W.buf);
			WHILE ScanPair(Sc, loc, rem) & (S.res = Done) DO
				Texts.Write(W, Tab);
				Texts.WriteString(W, loc);
				Texts.WriteString(W, " => ");
				Texts.WriteString(W, rem);
				Texts.Write(W, Tab);
				Texts.Append(log, W.buf);
				NEW(text);
				Texts.Open(text, loc);
				PutText(S, rem, text);
				Texts.WriteLn(W);
				ShowRes()
			END
		END
	END PutTexts;

	PROCEDURE OpenLog*;
	BEGIN
		IF log = Oberon.Log THEN
			NEW(log); Texts.Open(log, "")
		END;
		Oberon.OpenText("FTP.Log", log, Display.Width DIV 2, Display.Height DIV 2)
	END OpenLog;

BEGIN
	S := NIL; log := Oberon.Log;
	Texts.OpenWriter(W);
	timeOut := 5*60*Input.TimeUnit;
	dataPort := MinDataPort
END FTP.
