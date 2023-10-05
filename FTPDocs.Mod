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

MODULE FTPDocs; (** portable *)	(* ejz,  , some tips by bh & pm *)
	IMPORT Files, Objects, Fonts, Display, NetSystem, Strings, HyperDocs, NetTools, Input, Texts, Display3, Oberon,
		Links, Gadgets, Attributes, TextGadgets, Documents, TextDocs, Desktops, Streams, MIME;

(** This module implements an API-interface and a interactive interface to FTP (RFC 959).
		The FTPDocs-modul supports ftp urls. The following line should be added to the LinkSchemes section of the Registry:
			ftp = FTPDocs.NewLinkScheme
		And the following line to the Documents section:
			ftp = FTPDocs.NewDoc
		To ensure that anonymous ftp works correctly your e-mail address should be defined in the NetSystem section of
		the Registry. e.g.: EMail = "me@home"
		To access FTP within a firewall, add the proxy to the NetSystem section of the Registry:
			FTPProxy = host [ ":" port ] . *)

	CONST
		DefConPort* = 21;
		FixedFont = "Courier10.Scn.Fnt";
	(** res codes *)
		Done* = NetTools.Done;
		NotReady* = 1;
		NotConnected* = 2;
		WrongUser* = 3;
		WrongPassword* = 4;
		TimedOut* = 5;
		LocFileNotFound* = 6;
		Interrupted* = 7;
		Disconnected* = 8;
		Failed* = NetTools.Failed;
		(* systems *)
		Unknown = -1;
		UNIX = 0;
		VMS = 1;
		TempFile = "Temp.FTP";
		Menu = "HyperDocs.Back[Back] FTPDocs.DeleteDocFile[Del] FTPDocs.GetDocFile[Get] FTPDocs.PutDocFile[Put] TextDocs.Search[Search]";
		SysMenu = "HyperDocs.Back[Back] FTPDocs.GetDocFile[Get] FTPDocs.PutDocFile[Put]";
		MinDataPort = 1100;
		MaxDataPort = 1500;

	TYPE
(** The connection to an ftp server is controlled by a session handle. *)
		Session* = POINTER TO SessionDesc;
		SessionDesc* = RECORD (NetTools.SessionDesc)
			dataC: NetSystem.Connection;
			log: Texts.Text;
			curDir: ARRAY NetTools.PathStrLen OF CHAR;
			system, dataPort: INTEGER;
			dataIP: NetSystem.IPAdr;
			portIPAddress: ARRAY 64 OF CHAR;
			usr, passw, host: ARRAY NetTools.ServerStrLen OF CHAR;
			port: INTEGER;
			ack, bin: BOOLEAN
		END;
		EnumProc* = PROCEDURE (entry: ARRAY OF CHAR);
		Frame = POINTER TO FrameDesc;
		FrameDesc = RECORD (TextGadgets.FrameDesc)
			S: Session
		END;

	VAR
		system: INTEGER;
		W, dirW: Texts.Writer;
		line, link: ARRAY NetTools.MaxLine OF CHAR;
		cacheS, curS: Session;
		curF: Frame;
		message: BOOLEAN;
		proxyHost: ARRAY NetTools.ServerStrLen OF CHAR;
		proxyPort, dataPort: INTEGER;
		proxy: BOOLEAN;

	PROCEDURE ReadResponse(S: Session; VAR sline: ARRAY OF CHAR);
		VAR
			time, i, j, cpos: LONGINT;
			code: ARRAY 8 OF CHAR;
			line: ARRAY NetTools.MaxLine OF CHAR;
	BEGIN
		IF ~NetTools.Connected(S.C, NetSystem.in) THEN
			COPY("Connection closed by server.", sline);
			COPY(sline, S.reply);
			S.status := 0; S.res := Disconnected;
			RETURN
		END;
		time := NetSystem.Available(S.C);
		NetSystem.ReadString(S.C, line);
		IF S.log # NIL THEN
			Texts.WriteString(W, line);
			Texts.WriteLn(W); Texts.Append(S.log, W.buf)
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
					IF S.log # NIL THEN
						Texts.WriteString(W, line);
						Texts.WriteLn(W); Texts.Append(S.log, W.buf)
					END;
					IF line[cpos] # "-" THEN
						line[cpos] := 0X;
						IF line = code THEN
							EXIT
						END
					END;
					time := Input.Time()
				ELSIF (Input.Time()-time) >= NetTools.TimeOut THEN
					S.res := TimedOut;
					RETURN
				ELSIF NetTools.UserBreak() THEN
					S.res := Interrupted;
					RETURN
				END
			END
		END;
		S.ack := TRUE
	END ReadResponse;

	PROCEDURE SendLine(C: NetSystem.Connection; VAR str: ARRAY OF CHAR);
	BEGIN
		NetTools.SendString(C, str);
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

(** Close connection for session S.
	res: allways = Done *)
	PROCEDURE Close*(S: Session);
	BEGIN
		S.ack := TRUE;
		SendCmd(S, "QUIT"); ReadResponse(S, S.reply);
		NetTools.Disconnect(S.dataC); NetTools.Disconnect(S.C);
		S.res := Done
	END Close;

	PROCEDURE Close2(S: Session);
	BEGIN
		S.ack := TRUE;
		SendCmd(S, "QUIT");
		NetTools.Disconnect(S.dataC); NetTools.Disconnect(S.C)
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

	PROCEDURE GetLogin(VAR host, usr, passw: ARRAY OF CHAR);
	BEGIN
		IF (usr = "ftp") OR (usr = "anonymous") OR (usr = "") THEN
			IF ~NetTools.QueryString("EMail", passw) OR (passw[0] = "<") THEN
				COPY("anonymous@host.nowhere", passw)
			END;
			IF usr = "" THEN
				COPY("anonymous", usr)
			END
		ELSIF passw = "" THEN
			NetSystem.GetPassword("ftp", host, usr, passw)
		END
	END GetLogin;

(** Open a new ftp session S to server using USER=user and PASS=passwd.
	If user is either ftp or anonymous, passwd defaults to the e-mail address set in the
	Registry (NetSystem.EMail).
	port gives the Telnet-port of the FTP server, most FTP servers use FTPDocs.DefConPort.
	If log # NIL all responses from the server will be appended to log. NetSystem.hostIP
	must be set correctly.
	res:
		Done: all ok
		WrongPassword: the password given is incorrect
		WrongUser: the given user is not allowd to use this server
		NotReady: the server is busy, retry later
		NotConnected: server not found
		Failed: NetSystem.hostIP not set *)
	PROCEDURE Open*(server, user, passwd: ARRAY OF CHAR; port: INTEGER; log: Texts.Text; VAR S: Session);
	BEGIN
		GetLogin(server, user, passwd);
		NEW(S); S.dataC := NIL;
		COPY(server, S.host); S.port := port; S.dataPort := -1;
		COPY(user, S.usr); COPY(passwd, S.passw);
		IF NetSystem.hostIP = NetSystem.anyIP THEN
			S.C := NIL;
			S.reply := "invalid NetSystem.hostIP";
			S.res := Failed;
			RETURN
		END;
		S.system := Unknown;
		S.reply := "connecting failed";
		S.portIPAddress := "";
		S.log := log;
		S.ack := TRUE;
		IF (user = "") OR (passwd = "") THEN
			S.res := Failed;
			S.reply := "no password or username specified";
			RETURN
		END;
		IF NetTools.Connect(S.C, port, server, FALSE) THEN
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
			SendCmd(S, "TYPE I"); S.bin := TRUE;
			ReadResponse(S, line);
			IF S.status # 200 THEN
				(* should not happen *)
			END;
			QuerySystem(S);
			S.res := Done
		END
	END Open;

(** Change the current directory.
		res:
			Done: all ok
			Failed: directory not changed *)
	PROCEDURE ChangeDir*(S: Session; newDir: ARRAY OF CHAR);
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
	END ChangeDir;

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
			UNTIL (S.res = NetSystem.done) OR NetTools.UserBreak();
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
				NetTools.Disconnect(S.dataC); S.dataC := NIL;
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
			UNTIL NetSystem.Requested(S.dataC) OR ((Input.Time()-time) > NetTools.TimeOut) OR NetTools.UserBreak();
			IF NetSystem.Requested(S.dataC) THEN
				NetSystem.Accept(S.dataC, C1, S.res); NetTools.Disconnect(S.dataC);
				IF S.res = NetSystem.done THEN
					S.res := Done;
					RETURN C1
				ELSE
					S.res := Failed
				END
			ELSIF (Input.Time()-time) > NetTools.TimeOut THEN
				S.res := TimedOut
			ELSE
				S.res := Interrupted
			END;
			NetTools.Disconnect(S.dataC)
		ELSE
			NetSystem.OpenConnection(C1, NetSystem.anyport, S.dataIP, S.dataPort, S.res);
			IF S.res = Done THEN RETURN C1 END
		END;
		RETURN NIL
	END WaitDataCon;

(** Retrieve a list of the current directory and call enum for each entry in the list.
		res:
			Done: all ok
			TimeOut: server did not answer in time
			Failed: see S.reply(Line) *)
	PROCEDURE EnumDir*(S: Session; enum: EnumProc);
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
					WHILE ((len > 0) OR NetTools.Connected(C, NetSystem.in)) & ~NetTools.UserBreak() DO
						IF len > 0 THEN
							NetSystem.ReadString(C, line);
							enum(line)
						END;
						len := NetSystem.Available(C)
					END;
					NetTools.Disconnect(C)
				END;
				ReadResponse(S, S.reply)
			ELSE
				S.res := Failed
			END
		END;
		IF S.dataC # NIL THEN NetTools.Disconnect(S.dataC) END
	END EnumDir;

	PROCEDURE ScanLen(VAR reply: ARRAY OF CHAR; VAR len: LONGINT);
		VAR
			i, d: INTEGER;
			last: BOOLEAN;
	BEGIN
		last := FALSE; d := -1; i := 0;
		WHILE reply[i] # 0X DO
			IF Strings.IsDigit(reply[i]) THEN
				IF ~last THEN
					d := i; last := TRUE
				END
			ELSE
				last := FALSE
			END;
			INC(i)
		END;
		IF d > 0 THEN
			Strings.StrToIntPos(reply, len, d)
		ELSE
			len := 0
		END
	END ScanLen;

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
					ScanLen(S.reply, NetTools.curLen); NetTools.curPos := 0;
					NetTools.ReadData(C, R, MAX(LONGINT));
					NetTools.Disconnect(C)
				END;
				ReadResponse(S, S.reply);
				IF S.res = Interrupted THEN
					ReadResponse(S, line)
				END
			ELSE
				S.res := Failed
			END
		END;
		IF S.dataC # NIL THEN NetTools.Disconnect(S.dataC) END
	END GetF;

(** Retrieve the file remName from the server and store it as local file locName.
		res:
			Done: all ok
			TimeOut: server did not answer in time
			Failed: file not found or no permission, see S.reply(Line) *)
	PROCEDURE GetFile*(S: Session; remName, locName: ARRAY OF CHAR);
		VAR
			F: Files.File;
			R: Files.Rider;
	BEGIN
		S.bin := TRUE;
		F := Files.New(locName);
		Files.Set(R, F, 0);
		GetF(S, remName, R);
		Files.Register(F)
	END GetFile;

(** Retrieve the text file remName from the server and write it to writer W.
		The text is converted from iso-8859-1 to the Oberon-code.
		res:
			Done: all ok
			TimeOut: server did not answer in time
			Failed: file not found or no permission, see S.reply(Line) *)
	PROCEDURE GetText*(S: Session; remName: ARRAY OF CHAR; VAR W: Texts.Writer);
		VAR
			C: NetSystem.Connection;
			in: Streams.Stream;
	BEGIN
		S.reply := "";
		SendCmd(S, "TYPE A"); S.bin := FALSE;
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
					ScanLen(S.reply, NetTools.curLen); NetTools.curPos := 0;
					in := NetTools.OpenStream(C); MIME.textCont.len := MAX(LONGINT);
					MIME.ReadText(in, W, MIME.textCont, FALSE);
					NetTools.Disconnect(C)
				END;
				ReadResponse(S, S.reply);
				IF S.res = Interrupted THEN
					ReadResponse(S, line)
				END
			ELSE
				S.res := Failed
			END
		END;
		IF S.dataC # NIL THEN NetTools.Disconnect(S.dataC) END;
		SendCmd(S, "TYPE I");
		ReadResponse(S, line)
	END GetText;

(** Store the local file locName as remName on the server.
		res:
			Done: all ok
			TimeOut: server did not answer in time
			Failed: no permission or bad file name
			LocFileNotFound: could not open the local file *)
	PROCEDURE PutFile*(S: Session; remName, locName: ARRAY OF CHAR);
		VAR
			F: Files.File;
			R: Files.Rider;
			C: NetSystem.Connection;
	BEGIN
		S.reply := ""; S.bin := TRUE;
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
						NetTools.curLen := Files.Length(F); NetTools.curPos := 0;
						Files.Set(R, F, 0);
						NetTools.WriteData(C, R);
						NetTools.Disconnect(C)
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
		IF S.dataC # NIL THEN NetTools.Disconnect(S.dataC) END
	END PutFile;

(** Store text as remName on the server.
		The text is converted to iso-8859-1. All none ascii content is ignored (colors, fonts, objects, ...).
		res:
			Done: all ok
			TimeOut: server did not answer in time
			Failed: no permission or bad file name *)
	PROCEDURE PutText*(S: Session; remName: ARRAY OF CHAR; text: Texts.Text);
		VAR
			C: NetSystem.Connection;
			out: Streams.Stream;
	BEGIN
		S.reply := "";
		SendCmd(S, "TYPE A"); S.bin := FALSE;
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
					NetTools.curLen := text.len; NetTools.curPos := 0;
					out := NetTools.OpenStream(C); MIME.textCont.len := MAX(LONGINT);
					MIME.WriteText(text, 0, text.len, out, MIME.textCont, FALSE, FALSE);
					NetTools.Disconnect(C)
				END;
				ReadResponse(S, S.reply)
			ELSE
				S.res := Failed
			END
		END;
		IF S.dataC # NIL THEN NetTools.Disconnect(S.dataC) END;
		SendCmd(S, "TYPE I");
		ReadResponse(S, line)
	END PutText;

(** Delete the file remName from the server.
		res:
			Done: all ok
			Failed: file not found or no permission, see S.reply(Line) *)
	PROCEDURE DeleteFile*(S: Session; remName: ARRAY OF CHAR);
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

(** Query the current dir (path).
		res:
			Done: all ok
			Failed: see S.reply(Line) *)
	PROCEDURE GetCurDir*(S: Session; VAR curdir: ARRAY OF CHAR);
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

(** Create a new directory.
		res:
			Done: all ok
			Failed: see S.reply(Line) *)
	PROCEDURE MakeDir*(S: Session; newDir: ARRAY OF CHAR);
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
	END MakeDir;

(** Remove an existing directory.
		res:
			Done: all ok
			Failed: see S.reply(Line) *)
	PROCEDURE RmDir*(S: Session; dir: ARRAY OF CHAR);
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
	END RmDir;

	PROCEDURE *DocHandler(D: Objects.Object; VAR M: Objects.ObjMsg);
	BEGIN
		WITH D: Documents.Document DO
			IF M IS Objects.LinkMsg THEN
				WITH M: Objects.LinkMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "DeskMenu" THEN
							M.obj := Gadgets.CopyPublicObject("NetDocs.FTPDeskMenu", TRUE);
							IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
							M.res := 0
						ELSIF M.name = "SystemMenu" THEN
							M.obj := Gadgets.CopyPublicObject("NetDocs.FTPSystemMenu", TRUE);
							IF M.obj = NIL THEN M.obj := Desktops.NewMenu(SysMenu) END;
							M.res := 0
						ELSIF M.name = "UserMenu" THEN
							M.obj := Gadgets.CopyPublicObject("NetDocs.FTPUserMenu", TRUE);
							IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
							M.res := 0
						ELSE
							TextDocs.DocHandler(D, M)
						END
					ELSE
						TextDocs.DocHandler(D, M)
					END
				END
			ELSE
				TextDocs.DocHandler(D, M)
			END
		END
	END DocHandler;

(** Register a ftp URL and get a unique key for it. *)
	PROCEDURE RegisterFTPAdr*(host, path, user, passwd: ARRAY OF CHAR; type: CHAR; port: INTEGER): LONGINT;
		VAR
			portS: ARRAY 8 OF CHAR;
			key: LONGINT;
	BEGIN
		COPY("ftp://", line);
		IF user # "" THEN
			HyperDocs.ESC(user, "@");
			Strings.Append(line, user);
			IF passwd # "" THEN
				HyperDocs.ESC(passwd, "@");
				Strings.AppendCh(line, ":"); Strings.Append(line, passwd)
			END;
			Strings.AppendCh(line, "@")
		END;
		Strings.Lower(host, host);
		Strings.Append(line, host);
		IF port # DefConPort THEN
			Strings.AppendCh(line, ":"); Strings.IntToStr(port, portS); Strings.Append(line, portS)
		END;
		IF path # "" THEN
			Strings.Append(line, path);
			IF type # 0X THEN
				Strings.Append(line, ";type="); Strings.AppendCh(line, type)
			END
		END;
		key := HyperDocs.RegisterLink(line);
		RETURN key
	END RegisterFTPAdr;

(** Parsing of an ftp url. *)
	PROCEDURE SplitFTPAdr*(VAR url, host, path, user, passwd: ARRAY OF CHAR; VAR type: CHAR; VAR port: INTEGER): LONGINT;
		VAR
			key, i, j, l: LONGINT;
			iskey: BOOLEAN;
		PROCEDURE Blanks();
		BEGIN
			WHILE (url[i] # 0X) & (url[i] <= " ") DO
				INC(i)
			END
		END Blanks;
	BEGIN
		(* Pre: url must be a ftp url *)
		type := 0X; port := DefConPort;
		COPY("", user); COPY("", passwd);
		i := 0; Blanks();
		(* skip ftp *)
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
		Blanks();
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
		iskey := (user = "") & (passwd = "");
		l := LEN(host); j := 0;
		WHILE (url[i] # 0X) & (url[i] # ":") & (url[i] # "/") DO
			IF (url[i] > " ") & ~Strings.IsDigit(url[i]) THEN
				iskey := FALSE
			END;
			IF j < l THEN
				host[j] := url[i]; INC(j)
			END;
			INC(i)
		END;
		host[j] := 0X; DEC(j);
		WHILE (j >= 0) & (host[j] <= " ") DO
			host[j] := 0X; DEC(j)
		END;
		IF (url[i] = 0X) & iskey THEN
			IF host # "" THEN
				Strings.StrToInt(host, key);
				HyperDocs.RetrieveLink(key, line);
				key := SplitFTPAdr(line, host, path, user, passwd, type, port);
				RETURN key
			ELSE
				RETURN HyperDocs.UndefKey
			END
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
		HyperDocs.UnESC(host); HyperDocs.UnESC(path); 
		HyperDocs.UnESC(user); HyperDocs.UnESC(passwd);
		key := RegisterFTPAdr(host, path, user, passwd, type, port);
		RETURN key
	END SplitFTPAdr;

	PROCEDURE *LinkSchemeHandler(L: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			usr, passw, host: ARRAY NetTools.ServerStrLen OF CHAR;
			path: ARRAY NetTools.PathStrLen OF CHAR;
			port: INTEGER;
			type: CHAR;
	BEGIN
		WITH L: HyperDocs.LinkScheme DO
			IF M IS HyperDocs.RegisterLinkMsg THEN
				WITH M: HyperDocs.RegisterLinkMsg DO
					IF (M.base = NIL) OR (HyperDocs.CheckPrefix(M.link) >= 0) THEN
						M.key := SplitFTPAdr(M.link, host, path, usr, passw, type, port)
					ELSIF M.base.prefix = "ftp" THEN
						link := "ftp://"; Strings.Append(link, M.base.host);
						IF M.base.port > 0 THEN
							Strings.AppendCh(link, ":"); Strings.IntToStr(M.base.port, path); Strings.Append(link, path)
						END;
						HyperDocs.Path(M.base, link, M.link); M.key := HyperDocs.RegisterLink(link)
					ELSE
						HyperDocs.LinkSchemeHandler(L, M)
					END;
					IF M.key # HyperDocs.UndefKey THEN
						M.res := 0
					END
				END
			ELSIF M IS HyperDocs.FetchMsg THEN
				WITH M: HyperDocs.FetchMsg DO
					IF M.key # HyperDocs.UndefKey THEN
						HyperDocs.RetrieveLink(M.key, line);
						M.key := SplitFTPAdr(line, host, path, usr, passw, type, port);
(*GetLogin(host, usr, passw);*)
						Texts.WriteString(W, "ftp://");
						Texts.WriteString(W, host);
						Texts.WriteString(W, path);
						Texts.Append(Oberon.Log, W.buf);
						IF (cacheS # NIL) & ((cacheS.host # host) OR (cacheS.port # port) OR (cacheS.usr # usr) OR (cacheS.passw # passw)) THEN
							Close(cacheS); cacheS := NIL
						END;
						IF cacheS = NIL THEN
							Open(host, usr, passw, port, NIL, cacheS)
						END;
						IF cacheS.res = Done THEN
							GetF(cacheS, path, M.R);
							IF cacheS.res # Done THEN
								Texts.WriteString(W, cacheS.reply)
							ELSE
								Texts.WriteString(W, " done"); M.res := 0
							END
						ELSE
							Texts.WriteString(W, cacheS.reply)
						END;
						Texts.WriteLn(W);
						Texts.Append(Oberon.Log, W.buf)
					ELSE
						IF cacheS # NIL THEN
							Close(cacheS); cacheS := NIL;
						END;
						M.res := 0
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.class := Objects.String;
						M.s := "FTPDocs.NewLinkScheme";
						M.res := 0
					ELSE
						HyperDocs.LinkSchemeHandler(L, M)
					END
				END
			ELSE
				HyperDocs.LinkSchemeHandler(L, M)
			END
		END
	END LinkSchemeHandler;

	PROCEDURE NewLinkScheme*;
		VAR L: HyperDocs.LinkScheme;
	BEGIN
		NEW(L); L.handle := LinkSchemeHandler;
		L.usePath := TRUE;
		Objects.NewObj := L
	END NewLinkScheme;

	PROCEDURE TrimmVMS(VAR name: ARRAY OF CHAR);
		VAR i: INTEGER;
	BEGIN
		i := 0;
		WHILE (name[i] # 0X) & (name[i] # ";") DO
			INC(i)
		END;
		name[i] := 0X
	END TrimmVMS;

	PROCEDURE GetDoc(F: Frame; name: ARRAY OF CHAR; type: CHAR): Documents.Document;
		VAR
			i, j: LONGINT;
			D: Documents.Document;
			tempName: ARRAY 64 OF CHAR;
			T: Texts.Text;
			tW: Texts.Writer;
			obj: Objects.Object;
			bin: BOOLEAN;
	BEGIN
		IF type # 0X THEN
			bin := ~((type = "A") OR (type = "T"))
		ELSE
			obj := Gadgets.FindObj(Gadgets.context, "Ascii");
			IF obj # NIL THEN
				Attributes.GetBool(obj, "Value", bin);
				bin := ~bin
			ELSE
				bin := TRUE
			END
		END;
		IF bin THEN
			Texts.WriteString(W, "FTPDocs.GetFile ")
		ELSE
			Texts.WriteString(W, "FTPDocs.GetText ")
		END;
		Texts.WriteString(W, name);
		Texts.Write(W, " ");
		Texts.Append(Oberon.Log, W.buf);
		j := -1; i := 0;
		WHILE name[i] # 0X DO
			IF name[i] = "." THEN
				j := i
			END;
			INC(i)
		END;
		IF ~bin THEN
			type := "A";
			Texts.OpenWriter(tW);
			GetText(F.S, name, tW);
			NEW(T); Texts.Open(T, "");
			Texts.Append(T, tW.buf)
		ELSE
			COPY(TempFile, tempName);
			IF j > 0 THEN
				i := 0;
				WHILE tempName[i] # 0X DO
					INC(i)
				END;
				WHILE name[j] # 0X DO
					tempName[i] := name[j]; INC(i); INC(j)
				END;
				tempName[i] := 0X;
				IF F.S.system = VMS THEN
					TrimmVMS(tempName)
				END
			END;
			GetFile(F.S, name, tempName)
		END;
		Texts.WriteLn(W);
		Texts.WriteString(W, F.S.reply);
		Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf);
		IF F.S.res = Done THEN
			IF type = "A" THEN
				NEW(D); TextDocs.InitDoc(D);
				D.W := HyperDocs.docW; D.H := HyperDocs.docH;
				Links.SetLink(D.dsc, "Model", T);
				COPY(name, D.name)
			ELSE
				D := Documents.Open(tempName)
			END
		ELSE
			D := NIL
		END;
		RETURN D
	END GetDoc;

	PROCEDURE *ShowEntry(entry: ARRAY OF CHAR);
		VAR
			link: Objects.Object;
			i, j, beg0, beg1, beg2, begL, key: LONGINT;
			name: ARRAY 64 OF CHAR;
	BEGIN
		begL := -1;
		IF entry = "" THEN
			RETURN
		END;
		IF system = UNIX THEN
			i := 0; beg0 := 0; beg1 := beg0; beg2 := beg1;
			WHILE entry[i] # 0X DO
				IF entry[i] <= " " THEN
					beg0 := beg1; beg1 := beg2; beg2 := i
				END;
				INC(i)
			END;
			i := 0;
			WHILE entry[i] # 0X DO
				IF (i >= beg2) & ((entry[0] = "d") OR (entry[0] = "-")) THEN
					Texts.SetColor(dirW, SHORT(HyperDocs.linkC));
					IF begL < 0 THEN
						Texts.Append(curF.text, dirW.buf); begL := curF.text.len
					END
				ELSIF (i >= beg0) & (entry[0] = "l") THEN
					Texts.SetColor(dirW, SHORT(HyperDocs.linkC));
					IF begL < 0 THEN
						Texts.Append(curF.text, dirW.buf); begL := curF.text.len
					END
				END;
				Texts.Write(dirW, entry[i]); INC(i)
			END;
			Texts.SetColor(dirW, SHORT(Display3.textC));
			IF begL >= 0 THEN
				i := 0; INC(beg2);
				WHILE (entry[beg2] > " ") & (i < 63) DO
					name[i] := entry[beg2];
					INC(i); INC(beg2)
				END;
				name[i] := 0X;
				IF name = ".message" THEN
					message := TRUE
				END;
				IF name[0] # "/" THEN
					COPY(curS.curDir, line);
					IF curS.curDir # "/" THEN Strings.AppendCh(line, "/") END;
					Strings.Append(line, name);
					IF entry[0] = "d" THEN
						Strings.AppendCh(line, "/")
					END
				ELSE
					COPY(name, line)
				END;
				key := RegisterFTPAdr(curS.host, line, "", "", 0X, curS.port);
				IF HyperDocs.Visited(key) THEN
					Texts.Append(curF.text, dirW.buf);
					Texts.ChangeLooks(curF.text, begL, curF.text.len, {1}, NIL, SHORT(HyperDocs.oldLinkC), 0)
				END;
				link := HyperDocs.LinkControl(key);
				Texts.WriteObj(dirW, link)
			END;
			Texts.WriteLn(dirW)
		ELSIF system = VMS THEN
			beg0 := 0;
			Strings.Search(".dir;", entry, beg0);
			IF beg0 < 0 THEN
				Strings.Search(".DIR;", entry, beg0)
			END;
			i := 0;
			IF beg0 > 0 THEN
				Texts.SetColor(dirW, SHORT(HyperDocs.linkC));
				WHILE (entry[i] # 0X) & (i < beg0) DO
					Texts.Write(dirW, entry[i]);
					INC(i)
				END;
				Texts.SetColor(dirW, SHORT(Display3.textC));
				beg1 := i; entry[beg1] := 0X;
				COPY(curS.curDir, line); line[0] := "/";
				i := 0;
				WHILE (line[i] # 0X) & (line[i] # "]") DO
					INC(i)
				END;
				line[i] := 0X;
				Strings.AppendCh(line, "."); Strings.Append(line, entry);
				Strings.AppendCh(line, "]");
				key := RegisterFTPAdr(curS.host, line, "", "", 0X, curS.port);
				link := HyperDocs.LinkControl(key);
				Texts.WriteObj(dirW, link);
				entry[beg1] := "."; i := beg1
			ELSE
				beg0 := 0;
				Strings.Search(";", entry, beg0);
				IF beg0 > 0 THEN
					j := 0;
					Texts.SetColor(dirW, SHORT(HyperDocs.linkC));
					WHILE (entry[i] # 0X) & (i < beg0) & (j < 63) DO
						name[j] := entry[i]; INC(j);
						Texts.Write(dirW, entry[i]); INC(i)
					END;
					name[j] := 0X; beg1 := i; 
					Texts.SetColor(dirW, SHORT(Display3.textC));
					COPY(curS.curDir, line); line[0] := "/";
					i := 0;
					WHILE (line[i] # 0X) & (line[i] # "]") DO
						INC(i)
					END;
					line[i] := 0X;
					Strings.AppendCh(line, "]"); Strings.Append(line, name);
					key := RegisterFTPAdr(curS.host, line, "", "", 0X, curS.port);
					link := HyperDocs.LinkControl(key);
					Texts.WriteObj(dirW, link);
					i := beg1
				END
			END;
			WHILE entry[i] # 0X DO
				Texts.Write(dirW, entry[i]);
				INC(i)
			END;
			Texts.WriteLn(dirW)
		END;
		Texts.SetColor(W, SHORT(Display3.textC))
	END ShowEntry;

	PROCEDURE HorzRule(): Objects.Object;
		VAR obj: Objects.Object;
	BEGIN
		obj := Gadgets.CreateObject("BasicFigures.NewRect3D");
		Attributes.SetBool(obj, "Filled", TRUE);
		Attributes.SetInt(obj, "Color", Display3.textbackC);
		Gadgets.ModifySize(obj(Display.Frame), Display.Width, 4);
		RETURN obj
	END HorzRule;

	PROCEDURE DoDir(D: Documents.Document; F: Frame);
		VAR
			f, o: Objects.Object;
			pos: LONGINT;
			msgW: Texts.Writer;
			U: Gadgets.UpdateMsg;
			h: INTEGER;
			oldBin: BOOLEAN;
	BEGIN
		Texts.Delete(F.text, 0, F.text.len);
		system := F.S.system; GetCurDir(F.S, F.S.curDir);
		f := Gadgets.CreateObject("TextFields.NewTextField");
		Attributes.SetString(f, "Value", F.S.curDir);
		Attributes.SetString(f, "Cmd", "FTPDocs.ChangeDocDir '#Value '");
		WITH f: Display.Frame DO
			f.W := 3*f.W; h := f.H
		END;
		Texts.WriteObj(dirW, f); Texts.Write(dirW, Strings.Tab);
		o := Gadgets.CreateObject("BasicGadgets.NewInteger");
		f := Gadgets.CreateObject("BasicGadgets.NewCheckBox");
		WITH f: Gadgets.Frame DO
			f.H := h; f.obj := o
		END;
		Gadgets.NameObj(f, "Bin");
		Attributes.SetInt(f, "SetVal", 0); Attributes.SetString(f, "YesVal", "I");
		Texts.WriteObj(dirW, f);
		Texts.WriteString(dirW, " binary");
		Texts.Write(dirW, 09X);
		f := Gadgets.CreateObject("BasicGadgets.NewCheckBox");
		WITH f: Gadgets.Frame DO
			f.H := h; f.obj := o
		END;
		Gadgets.NameObj(f, "Ascii");
		Attributes.SetInt(f, "SetVal", 1); Attributes.SetString(f, "YesVal", "A");
		Texts.WriteObj(dirW, f);
		Attributes.SetBool(f, "Value", ~F.S.bin);
		Texts.WriteString(dirW, " ascii"); Texts.WriteLn(dirW);
		Texts.WriteObj(dirW, HorzRule()); Texts.WriteLn(dirW);
		Texts.Append(F.text, dirW.buf);
		pos := F.text.len-1;
		message := FALSE;
		curS := F.S; curF := F;
		EnumDir(F.S, ShowEntry);
		curS := NIL; curF := NIL;
		Attributes.SetInt(F, "LinkColor", HyperDocs.linkC);
		Attributes.SetInt(F, "OldLinkColor", HyperDocs.oldLinkC);
		F.do := HyperDocs.linkMethods;
		IF F.S.res # Done THEN
			Texts.WriteString(W, F.S.reply);
			Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf)
		ELSE
			D.name := "ftp://";
			Strings.Append(D.name, F.S.host);
			Strings.Append(D.name, F.S.curDir);
			Attributes.SetString(D, "DocumentName", D.name);
			U.obj := D; U.F := NIL;
			Display.Broadcast(U)
		END;
		IF message THEN
			Texts.OpenWriter(msgW);
			Texts.WriteObj(msgW, HorzRule());
			Texts.SetFont(msgW, Fonts.This(FixedFont));
			Texts.WriteLn(msgW);
			oldBin := F.S.bin; GetText(F.S, ".message", msgW); F.S.bin := oldBin;
			Texts.Insert(F.text, pos-1, msgW.buf)
		END;
		Texts.Append(F.text, dirW.buf)
	END DoDir;

	PROCEDURE GetContext(VAR F: Frame; VAR D: Documents.Document);
	BEGIN
		D := Desktops.CurDoc(Gadgets.context);
		IF (D.dsc # NIL) & (D.dsc IS Frame) & (D.dsc(Frame).S # NIL) THEN
			F := D.dsc(Frame)
		ELSE
			F := NIL
		END
	END GetContext;

	PROCEDURE ScanName(context: Objects.Object; VAR name: ARRAY OF CHAR; VAR bin: BOOLEAN);
		VAR
			R: Texts.Reader;
			S: Texts.Scanner;
			obj: Objects.Object;
			T: Texts.Text;
			i, beg, end, time: LONGINT;
			ch: CHAR;
	BEGIN
		bin := TRUE; COPY("", name);
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = Oberon.OptionChar) THEN
			Texts.Scan(S); bin := (CAP(S.s[0]) # "A") & (CAP(S.s[0]) # "T");
			Texts.Scan(S)
		ELSE
			obj := Gadgets.FindObj(context, "Ascii");
			IF obj # NIL THEN
				Attributes.GetBool(obj, "Value", bin);
				bin := ~bin
			ELSE
				bin := TRUE
			END
		END;
		IF ((S.class = Texts.Char) & (S.c = "^")) OR Desktops.IsInMenu(Gadgets.context)THEN
			T := NIL; time := -1;
			Oberon.GetSelection(T, beg, end, time);
			IF (time >= 0) & (T # NIL) THEN
				Texts.OpenReader(R, T, beg);
				Texts.Read(R, ch);
				WHILE ~R.eot & (~(R.lib IS Fonts.Font) OR (ch <= " ")) DO
					Texts.Read(R, ch)
				END
			ELSE
				COPY("", name);
				RETURN
			END;
			IF ~R.eot & (R.lib IS Fonts.Font) & (ch = 22X) THEN
				Texts.Read(R, ch)
			END;
			i := 0;
			WHILE ~R.eot & (R.lib IS Fonts.Font) & (ch > " ") & (ch # 22X) DO
				name[i] := ch; INC(i);
				Texts.Read(R, ch)
			END;
			name[i] := 0X
		ELSIF S.class IN {Texts.Name, Texts.String} THEN
			COPY(S.s, name)
		END
	END ScanName;

(** Used by the interactive interface to retrieve the selected file and store it under the same name. *)
	PROCEDURE GetDocFile*;
		VAR
			D: Documents.Document;
			F: Frame;
			name: ARRAY NetTools.MaxLine OF CHAR;
			lname: ARRAY 128 OF CHAR;
			T: Texts.Text;
			Wr: Texts.Writer;
			Fi: Files.File;
			len: LONGINT;
			bin: BOOLEAN;
	BEGIN
		GetContext(F, D);
		IF F # NIL THEN
			ScanName(D.dsc, name, bin);
			IF name # "" THEN
				COPY(name, lname);
				IF F.S.system = VMS THEN
					TrimmVMS(lname)
				END;
				IF bin THEN
					Texts.WriteString(W, "FTPDocs.GetFile ")
				ELSE
					Texts.WriteString(W, "FTPDocs.GetText ")
				END;
				Texts.WriteString(W, name);
				Texts.WriteString(W, " => ");
				Texts.WriteString(W, lname);
				Texts.Write(W, " ");
				Texts.Append(Oberon.Log, W.buf);
				IF bin THEN
					GetFile(F.S, name, lname)
				ELSE
					NEW(T); Texts.Open(T, "");
					Texts.OpenWriter(Wr); GetText(F.S, name, Wr);
					Texts.Append(T, Wr.buf);
					Fi := Files.New(lname);
					Texts.Store(T, Fi, 0, len);
					Files.Register(Fi)
				END;
				Texts.WriteString(W, F.S.reply);
				Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf)
			END
		END
	END GetDocFile;

	PROCEDURE SkipPath(VAR pname, name: ARRAY OF CHAR);
		VAR i, j: LONGINT;
	BEGIN
		i := 0;  j := 0;
		WHILE (pname[i] # 0X) & (j = 0) DO
			IF (pname[i] = "=") & (pname[i+1] = ">") THEN
				j := i
			ELSE
				INC(i)
			END
		END;
		IF j # 0 THEN
			pname[j] := 0X;
			INC(j, 2);  i := 0;
			WHILE pname[j] # 0X DO
				name[i] := pname[j]; INC(i); INC(j)
			END;
			name[i] := 0X
		ELSE
			i := 0; j := 0;
			WHILE pname[i] # 0X DO
				IF (pname[i] = "/") OR (pname[i] = "\") OR (pname[i] = ":") THEN
					j := 0
				ELSE
					name[j] := pname[i]; INC(j)
				END;
				INC(i)
			END;
			name[j] := 0X
		END
	END SkipPath;

(** Used by the interactive interface to send the selected file and store it under the same name. *)
	PROCEDURE PutDocFile*;
		VAR
			D: Documents.Document;
			F: Frame;
			name, rname: ARRAY 128 OF CHAR;
			T: Texts.Text;
			bin: BOOLEAN;
	BEGIN
		GetContext(F, D);
		IF F # NIL THEN
			ScanName(D.dsc, name, bin);
			IF name # "" THEN
				IF bin THEN
					Texts.WriteString(W, "FTPDocs.PutFile ")
				ELSE
					Texts.WriteString(W, "FTPDocs.PutText ")
				END;
				Texts.WriteString(W, name);
				Texts.Write(W, " ");
				Texts.Append(Oberon.Log, W.buf);
				SkipPath(name, rname);
				IF bin THEN
					PutFile(F.S, rname, name)
				ELSE
					NEW(T); Texts.Open(T, name);
					PutText(F.S, rname, T)
				END;
				Texts.WriteString(W, F.S.reply);
				Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf);
				DoDir(D, F)
			END
		END
	END PutDocFile;

(** Used by the interactive interface to delete the selected file. *)
	PROCEDURE DeleteDocFile*;
		VAR
			D: Documents.Document;
			F: Frame;
			name: ARRAY NetTools.MaxLine OF CHAR;
			bin: BOOLEAN;
	BEGIN
		GetContext(F, D);
		IF F # NIL THEN
			ScanName(D.dsc, name, bin);
			IF name # "" THEN
				DeleteFile(F.S, name);
				Texts.WriteString(W, F.S.reply);
				Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf);
				DoDir(D, F)
			END
		END
	END DeleteDocFile;

	PROCEDURE TrimmCurDirVMS(VAR curDir: ARRAY OF CHAR);
		VAR i: LONGINT;
	BEGIN
		curDir[0] := "/";
		i := 0;
		WHILE curDir[i] # 0X DO
			INC(i)
		END;
		IF i > 0 THEN
			curDir[i-1] := 0X
		END
	END TrimmCurDirVMS;

(** Used by the interactive interface to change to directory pointed at *)
	PROCEDURE ChangeDocDir*;
		VAR
			F: Frame;
			D: Documents.Document;
			S: Attributes.Scanner;
			old, new: HyperDocs.Node;
			key: LONGINT;
	BEGIN
		GetContext(F, D);
		IF F # NIL THEN
			Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
			Attributes.Scan(S);
			IF S.class IN {Attributes.Name, Attributes.String} THEN
				ChangeDir(F.S, S.s);
				IF F.S.res # Done THEN
					Texts.WriteString(W, F.S.reply);
					Texts.WriteLn(W);
					Texts.Append(Oberon.Log, W.buf)
				ELSE
					old := HyperDocs.NodeByDoc(D);
					DoDir(D, F);
					IF F.S.system = VMS THEN
						TrimmCurDirVMS(F.S.curDir)
					ELSIF F.S.curDir # "/" THEN
						Strings.AppendCh(F.S.curDir, "/")
					END;
					key := RegisterFTPAdr(F.S.host, F.S.curDir, "", "", 0X, F.S.port);
					IF (old = NIL) OR (old.key # key) THEN
						HyperDocs.Remember(key, old, new)
					ELSE
						new := old
					END;
					HyperDocs.LinkNodeToDoc(D, new)
				END
			END
		END
	END ChangeDocDir;

(** Extension of TextGadgets used by the interactive FTPDocs. *)
	PROCEDURE CopyFrame(VAR C: Objects.CopyMsg; from, to: Frame);
	BEGIN
		TextGadgets.CopyFrame(C, from, to);
		to.S := from.S
	END CopyFrame;

	PROCEDURE *FrameHandler(F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR F1: Frame;
	BEGIN
		WITH F: Frame DO
			IF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					IF M.stamp = F.stamp THEN
						M.obj := F.dlink
					ELSE
						NEW(F1);
						F.stamp := M.stamp;
						F.dlink := F1;
						CopyFrame(M, F, F1);
						M.obj := F1
					END
				END
			ELSE
				TextGadgets.FrameHandler(F, M)
			END
		END
	END FrameHandler;

	PROCEDURE CurrentS(VAR S: Session);
	BEGIN
		S := NIL;
		IF (HyperDocs.context # NIL) & (HyperDocs.context.curDoc # NIL) & (HyperDocs.context.curDoc.dsc IS Frame) THEN
			S := HyperDocs.context.curDoc.dsc(Frame).S
		END
	END CurrentS;

	PROCEDURE *LoadDoc(D: Documents.Document);
		VAR
			F: Frame;
			usr, pass, host: ARRAY NetTools.ServerStrLen OF CHAR;
			path, name: ARRAY NetTools.PathStrLen OF CHAR;
			i, j, k, key: LONGINT;
			D2: Documents.Document;
			T: Texts.Text;
			new: HyperDocs.Node;
			port: INTEGER;
			P: NetTools.ProxyMsg;
			S: HyperDocs.LinkScheme;
			type: CHAR;
			newC: BOOLEAN;
	BEGIN
		key := SplitFTPAdr(D.name, host, path, usr, pass, type, port);
		IF key = HyperDocs.UndefKey THEN
			D.dsc := NIL;
			RETURN
		END;
		IF proxy & NetTools.UseProxy(host) THEN
			GetLogin(host, usr, pass);
			IF (usr = "ftp") OR (usr = "anonymous") THEN
				usr := ""; pass := ""
			END;
			P.key := RegisterFTPAdr(host, path, usr, pass, type, port);
			P.res := -1;
			COPY(proxyHost, P.host); P.port := proxyPort;
			P.D := D;
			S := HyperDocs.LinkSchemeByPrefix("http");
			S.handle(S, P);
			RETURN
		END;
		NEW(F); CurrentS(F.S);
		IF F.S = NIL THEN
			newC := TRUE;
			Texts.WriteString(W, host);
			Texts.Append(Oberon.Log, W.buf);
			Open(host, usr, pass, port, NIL, F.S);
			IF F.S.res = Done THEN
				Texts.WriteString(W, " connected");
				Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf)
			END
		ELSE
			newC := FALSE; F.S.res := Done
		END;
		IF F.S.res = Done THEN
			IF F.S.system # VMS THEN
				j := -1; i := 0;
				WHILE path[i] # 0X DO
					IF path[i] = "/" THEN
						j := i
					END;
					INC(i)
				END;
				IF j > 0 THEN
					k := j; path[j] := 0X; INC(j)
				ELSE
					k := -1
				END;
				IF (j > 0) & (path # "") THEN
					ChangeDir(F.S, path)
				ELSIF j = 0 THEN
					ChangeDir(F.S, "/"); j := 1; k := 0
				END;
				IF (j > 0) & (i > j) THEN
					IF HyperDocs.context # NIL THEN
						HyperDocs.context.replace := FALSE;
						HyperDocs.context.history := FALSE
					END;
					i := 0;
					WHILE path[j] # 0X DO
						name[i] := path[j]; INC(i); INC(j)
					END;
					name[i] := 0X;
					D2 := GetDoc(F, name, type);
					IF D2 # NIL THEN
						IF newC THEN
							Close(F.S)
						END;
						D^ := D2^
					ELSE
						name := ""; path[k] := "/"; ChangeDir(F.S, path)
					END
				ELSE
					name := ""
				END
			ELSE
				i := 0;
				WHILE (path[i] # 0X) & (path[i] # "]") DO
					INC(i)
				END;
				IF path[i] = "]" THEN
					k := i+1; j := 0;
					WHILE path[k] # 0X DO
						name[j] := path[k]; INC(j); INC(k)
					END;
					name[j] := 0X;
					path[i+1] := 0X; i := 1;
					WHILE path[i] # 0X DO
						path[i-1] := path[i]; INC(i)
					END;
					path[i-1] := 0X;
					ChangeDir(F.S, path);
					IF name # "" THEN
						IF HyperDocs.context # NIL THEN
							HyperDocs.context.replace := FALSE;
							HyperDocs.context.history := FALSE
						END;
						D2 := GetDoc(F, name, type);
						IF D2 # NIL THEN
							IF newC THEN
								Close(F.S)
							END;
							D^ := D2^
						ELSE
							name := ""
						END
					END
				ELSE
					name := ""
				END
			END;
			IF (F.S.res = Done) & (name = "") THEN
				TextDocs.InitDoc(D);
				NEW(T); Texts.Open(T, "");
				TextGadgets.Init(F, T, FALSE);
				DoDir(D, F);
				IF HyperDocs.context = NIL THEN
					IF F.S.system = VMS THEN
						TrimmCurDirVMS(F.S.curDir)
					END;
					key := RegisterFTPAdr(host, F.S.curDir, "", "", 0X, port);
					HyperDocs.Remember(key, NIL, new);
					HyperDocs.LinkNodeToDoc(D, new)
				ELSE
					HyperDocs.context.replace := ~newC;
					HyperDocs.context.history := TRUE
				END;
				D.W := HyperDocs.docW; D.H := HyperDocs.docH;
				D.dsc := F; D.handle := DocHandler;
				F.handle := FrameHandler
			END;
			IF F.S.res = Done THEN
				RETURN
			ELSIF HyperDocs.context # NIL THEN
				HyperDocs.context.history := FALSE
			END
		END;
		Texts.WriteString(W, " - "); Texts.WriteString(W, F.S.reply);
		Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
		F.S := NIL; D.dsc := NIL
	END LoadDoc;

	PROCEDURE NewDoc*;
		VAR D: Documents.Document;
	BEGIN
		NEW(D);
		D.Load := LoadDoc; D.Store := NIL;
		D.handle := DocHandler;
		Objects.NewObj := D
	END NewDoc;

	PROCEDURE Init();
	BEGIN
		dataPort := MinDataPort;
		NetTools.GetHostPort("FTPProxy", proxyHost, proxyPort, 80);
		proxy := proxyHost # "";
		cacheS := NIL; curS := NIL
	END Init;

BEGIN
	Texts.OpenWriter(W);
	Texts.OpenWriter(dirW);
	Texts.SetFont(dirW, Fonts.This(FixedFont));
	Init()
END FTPDocs.
