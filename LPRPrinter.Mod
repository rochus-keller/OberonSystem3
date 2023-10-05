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

MODULE LPRPrinter;	(** portable *)  (* ejz  , LPR Version of PSPrinter, RFC 1179 *)
	
	IMPORT FileDir, Files, Texts, Strings, Oberon, Printer, PSPrinter, NetSystem;

	CONST
		DefConPort = 515;
		BegLocPort = 721;
		EndLocPort = 731;
		LF = 0AX;
		CR = 0DX;
		BufLen = 1024;

	VAR
		W: Texts.Writer;
		buffer: ARRAY BufLen OF CHAR;
		opts: FileDir.FileName;
		jobNr: INTEGER;
		bannerPage, mailBack: BOOLEAN;
		host, queue: ARRAY 64 OF CHAR;

	PROCEDURE SendString(C: NetSystem.Connection; str: ARRAY OF CHAR);
		VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE str[i] # 0X DO
			INC(i)
		END;
		NetSystem.WriteBytes(C, 0, i, str)
	END SendString;

	PROCEDURE Connect(VAR C: NetSystem.Connection; host: ARRAY OF CHAR): BOOLEAN;
		VAR
			adr: NetSystem.IPAdr;
			res, locport: INTEGER;
	BEGIN
		NetSystem.GetIP(host, adr);
		IF adr = NetSystem.anyIP THEN
			RETURN FALSE
		END;
		locport := BegLocPort;
		REPEAT
			NetSystem.OpenConnection(C, locport, adr, DefConPort, res);
			INC(locport)
		UNTIL (res = NetSystem.done) OR (locport > EndLocPort);
		IF res = NetSystem.done THEN
			RETURN TRUE
		ELSE
			C := NIL;
			RETURN FALSE
		END
	END Connect;

	PROCEDURE ScanDest(VAR name, host, queue: ARRAY OF CHAR);
		VAR i, j: INTEGER;
	BEGIN
		i := 0;
		WHILE (name[i] # 0X) & (name[i] # "@") DO
			queue[i] := name[i];
			INC(i)
		END;
		queue[i] := 0X;
		IF name[i] = "@" THEN
			j := 0; INC(i);
			WHILE name[i] # 0X DO
				host[j] := name[i];
				INC(j); INC(i)
			END;
			host[j] := 0X
		ELSE
			COPY("", host)
		END
	END ScanDest;

	PROCEDURE IntToStr(val: LONGINT; VAR str: ARRAY OF CHAR);
		VAR
			i, j: LONGINT;
			digits: ARRAY 16 OF LONGINT;
	BEGIN
		IF val < 0 THEN
			val := ABS(val);
			str[0] := "-";
			j := 1
		ELSE
			j := 0
		END;
		i := 0;
		REPEAT
			digits[i] := val MOD 10;
			INC(i);
			val := val DIV 10
		UNTIL val = 0;
		DEC(i);
		WHILE i >= 0 DO
			str[j] := CHR(digits[i]+ORD("0"));
			INC(j);
			DEC(i)
		END;
		str[j] := 0X
	END IntToStr;

	PROCEDURE Concat(VAR str: ARRAY OF CHAR; str2: ARRAY OF CHAR);
		VAR i, j, l: INTEGER;
	BEGIN
		i := 0;
		WHILE str[i] # 0X DO
			INC(i)
		END;
		l := SHORT(LEN(str)-1);
		j := 0;
		WHILE (i < l) & (str2[j] # 0X) DO
			str[i] := str2[j];
			INC(i);
			INC(j)
		END;
		str[i] := 0X
	END Concat;

	PROCEDURE ConcatCh(VAR str: ARRAY OF CHAR; ch: CHAR);
		VAR i: INTEGER;
	BEGIN
		i := 0;
		WHILE str[i] # 0X DO
			INC(i)
		END;
		str[i] := ch;
		str[i+1] := 0X
	END ConcatCh;

	PROCEDURE PrintFile(VAR host, queue, options: ARRAY OF CHAR; F: Files.File; banner, mail: BOOLEAN);
		VAR
			C: NetSystem.Connection;
			R: Files.Rider;
			email, dataFile, controlFile: ARRAY 64 OF CHAR;
			docName: ARRAY 128 OF CHAR;
			nrStr: ARRAY 8 OF CHAR;
			i, j, k: INTEGER;
			state: CHAR;
			S: Texts.Scanner;
	BEGIN
		Oberon.OpenScanner(S, "NetSystem.EMail");
		IF S.class IN {Texts.Name, Texts.String} THEN COPY(S.s, email) ELSE email := "" END;
		INC(jobNr);
		IF jobNr >= 1000 THEN
			jobNr := 100
		END;
		IntToStr(jobNr, nrStr);
		dataFile := "dfA";
		Concat(dataFile, nrStr);
		Concat(dataFile, NetSystem.hostName);
		controlFile := "cfA";
		Concat(controlFile, nrStr);
		Concat(controlFile, NetSystem.hostName);
		Texts.WriteString(W, "LPR: ");
		Texts.WriteString(W, queue);
		Texts.Write(W, "@");
		Texts.WriteString(W, host);
		Texts.Append(Oberon.Log, W.buf);
		IF Connect(C, host) THEN
			Texts.WriteString(W, " sending ");
			Texts.Append(Oberon.Log, W.buf);
			NetSystem.Write(C, 02X); (* receive a print job *)
			SendString(C, queue);
			NetSystem.Write(C, LF);
			state := 0FFX; NetSystem.Read(C, state);
			IF state = 0X THEN
				NetSystem.Write(C, 03X); (* receive data file *)
				IntToStr(Files.Length(F)+1, nrStr);
				SendString(C, nrStr); (* data file length + 1 *)
				NetSystem.Write(C, " ");
				SendString(C, dataFile);
				NetSystem.Write(C, LF);
				state := 0FFX; NetSystem.Read(C, state);
				IF state = 0X THEN
					Files.Set(R, F, 0); (* send data file *)
					Files.ReadBytes(R, buffer, BufLen);
					WHILE ~R.eof & (C.res = NetSystem.done) DO
						NetSystem.WriteBytes(C, 0, BufLen, buffer);
						Files.ReadBytes(R, buffer, BufLen)
					END;
					ASSERT(C.res = NetSystem.done);
					NetSystem.WriteBytes(C, 0, BufLen-R.res, buffer);
					NetSystem.Write(C, LF);
					NetSystem.Write(C, 0X);
					state := 0FFX; NetSystem.Read(C, state);
					IF state = 0X THEN
						buffer := ""; (* build control file *)
						ConcatCh(buffer, "H"); (* host name *)
						Concat(buffer, NetSystem.hostName);
						ConcatCh(buffer, LF);
						ConcatCh(buffer, "P"); (* user identification *)
						Concat(buffer, email);
						ConcatCh(buffer, LF);
						IF mail THEN (* send mail when job has finished *)
							ConcatCh(buffer, "M"); (* user identification *)
							Concat(buffer, email);
							ConcatCh(buffer, LF)
						END;
						ConcatCh(buffer, "J"); (* job name *)
						j := 0;  WHILE (options[j] # Oberon.OptionChar) & (options[j] # 0X) DO INC(j) END;
						IF options[j] # 0X THEN
							k := 0;  INC(j);
							WHILE options[j] # 0X DO docName[k] := options[j];  INC(j);  INC(k) END;
							docName[k] := 0X
						ELSE
							docName[0] := 0X
						END;
						IF docName[0] = 0X THEN docName := "Oberon Document" END;
						Concat(buffer, docName);
						ConcatCh(buffer, LF);
						IF banner THEN
							ConcatCh(buffer, "L"); (* banner page *)
							Concat(buffer, email);
							ConcatCh(buffer, LF)
						END;
						ConcatCh(buffer, "l");	(* print file direct *)
						Concat(buffer, dataFile);
						ConcatCh(buffer, LF);
						ConcatCh(buffer, "U"); (* unlink data file *)
						Concat(buffer, dataFile);
						ConcatCh(buffer, LF);
						ConcatCh(buffer, "N"); (* name of source file *)
						Concat(buffer, docName);
						ConcatCh(buffer, LF);
						i := 0;
						WHILE buffer[i] # 0X DO
							INC(i)
						END;
						NetSystem.Write(C, 02X); (* receive control file *)
						IntToStr(i, nrStr);
						SendString(C, nrStr);
						NetSystem.Write(C, " ");
						SendString(C, controlFile);
						NetSystem.Write(C, LF);
						state := 0FFX; NetSystem.Read(C, state);
						IF state = 0X THEN
							NetSystem.WriteBytes(C, 0, i, buffer); (* send control file *)
							NetSystem.Write(C, 0X);
							state := 0FFX; NetSystem.Read(C, state);
							IF state = 0X THEN
								Texts.WriteString(W, "done")
							ELSE
								Texts.WriteInt(W, ORD(state), 0); Texts.WriteString(W, " send control file failed")
							END
						ELSE
							Texts.WriteInt(W, ORD(state), 0); Texts.WriteString(W, " receive control file failed")
						END
					ELSE
						Texts.WriteInt(W, ORD(state), 0); Texts.WriteString(W, " send data file failed")
					END
				ELSE
					Texts.WriteInt(W, ORD(state), 0); Texts.WriteString(W, " receive data file failed")
				END
			ELSE
				Texts.WriteInt(W, ORD(state), 0); Texts.WriteString(W, " receive print job failed")
			END;
			NetSystem.CloseConnection(C)
		ELSE
			Texts.WriteString(W, " connecting failed")
		END;
		Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf)
	END PrintFile;

	PROCEDURE Open*(P: Printer.Printer; printer, options: ARRAY OF CHAR);
	BEGIN
		COPY(options, opts);
		ScanDest(printer, host, queue);
		IF host # "" THEN	(* remote *)
			PSPrinter.Open(P, "", options)
		ELSE	(* local file *)
			PSPrinter.Open(P, queue, options)
		END
	END Open;

	PROCEDURE Close*(P: Printer.Printer);
	BEGIN
		WITH P: PSPrinter.PSPrinter DO
			PSPrinter.Close(P);
			IF host # "" THEN
				PrintFile(host, queue, opts, P.printF, bannerPage, mailBack)
			END
		END
	END Close;

(** LPRPrinter.PrintPSFile queue@host [ "\" options ] ps-file 
		Print the PostScript -file (ps-file) on the lpr-printer given by queue and host. *)
	PROCEDURE PrintPSFile*;
		VAR
			R: Texts.Reader;
			S: Texts.Scanner;
			name, options: FileDir.FileName;
			F: Files.File;
			i: INTEGER;
			ch, open: CHAR;
			host, queue: ARRAY 64 OF CHAR;
	BEGIN
		Texts.OpenReader(R, Oberon.Par.text, Oberon.Par.pos);
		Texts.Read(R, ch);
		WHILE ~R.eot & (ch <= " ") DO
			Texts.Read(R, ch)
		END;
		IF (ch = 022X) OR (ch = "'") THEN
			open := ch; Texts.Read(R, ch)
		ELSE
			open := 0X
		END;
		i := 0;
		WHILE ~R.eot & (ch > " ") & (ch # open) DO
			name[i] := ch; INC(i);
			Texts.Read(R, ch)
		END;
		name[i] := 0X;
		Texts.OpenScanner(S, Oberon.Par.text, Texts.Pos(R));
		Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = Oberon.OptionChar) THEN
			Texts.Scan(S); COPY(S.s, options);
			Texts.Scan(S)
		ELSE
			options := ""
		END;
		IF S.class IN {Texts.Name, Texts.String} THEN
			F := Files.Old(S.s);
			IF F # NIL THEN
				Strings.AppendCh(options, Oberon.OptionChar);
				Strings.Append(options, S.s);
				ScanDest(name, host, queue);
				IF queue = "" THEN
					Texts.WriteString(W, "no queue name")
				ELSIF host = "" THEN
					Texts.WriteString(W, "no host name")
				ELSE
					PrintFile(host, queue, options, F, bannerPage, mailBack);
					RETURN
				END;
				Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf)
			END
		END
	END PrintPSFile;

	PROCEDURE ReadText(C: NetSystem.Connection; VAR W: Texts.Writer);
		VAR
			len, rlen: LONGINT;
			state, i: INTEGER;
	BEGIN
		state := NetSystem.inout;
		len := NetSystem.Available(C);
		WHILE (len > 0) OR (state IN {NetSystem.in, NetSystem.inout}) DO
			WHILE len > 0 DO
				IF len > BufLen THEN
					rlen := BufLen
				ELSE
					rlen := len
				END;
				NetSystem.ReadBytes(C, 0, rlen, buffer);
				i := 0;
				WHILE i < rlen DO
					IF buffer[i] = CR THEN
						(* ignore CR *)
					ELSIF buffer[i] = LF THEN
						Texts.WriteLn(W)
					ELSE
						Texts.Write(W, buffer[i])
					END;
					INC(i)
				END;
				len := len-rlen
			END;
			len := NetSystem.Available(C);
			IF len <= 0 THEN
				state := NetSystem.State(C)
			END
		END
	END ReadText;

(** LPRPrinter.ShowJobs queue@host
		Display a list of the waiting jobs in the given queue. *)
	PROCEDURE ShowJobs*;
		VAR
			R: Texts.Reader;
			C: NetSystem.Connection;
			host, queue, name: ARRAY 32 OF CHAR;
			i: INTEGER;
			ch, open: CHAR;
	BEGIN
		Texts.OpenReader(R, Oberon.Par.text, Oberon.Par.pos);
		Texts.Read(R, ch);
		WHILE ~R.eot & (ch <= " ") DO
			Texts.Read(R, ch)
		END;
		IF (ch = 022X) OR (ch = "'") THEN
			open := ch; Texts.Read(R, ch)
		ELSE
			open := 0X
		END;
		i := 0;
		WHILE ~R.eot & (ch > " ") & (ch # open) DO
			name[i] := ch; INC(i);
			Texts.Read(R, ch)
		END;
		name[i] := 0X;
		ScanDest(name, host, queue);
		IF (host # "") & (queue # "") THEN
			Texts.WriteString(W, queue);
			Texts.Write(W, "@");
			Texts.WriteString(W, host);
			Texts.Append(Oberon.Log, W.buf);
			IF Connect(C, host) THEN
				Texts.WriteLn(W);
				NetSystem.Write(C, 04X); (* 03X short, 04X long *)
				SendString(C, queue);
				NetSystem.Write(C, LF);
				ReadText(C, W);
				NetSystem.CloseConnection(C)
			ELSE
				Texts.WriteString(W, " connecting failed");
				Texts.WriteLn(W)
			END;
			Texts.Append(Oberon.Log, W.buf)
		END
	END ShowJobs;

(** LPRPrinter.RemoveJob queue@host [ job-nr ]
		Remove the specified job or all jobs from queue. *)
	PROCEDURE RemoveJob*;
		VAR
			R: Texts.Reader;
			S: Texts.Scanner;
			C: NetSystem.Connection;
			email: ARRAY 64 OF CHAR;
			name, host, queue, job: ARRAY 32 OF CHAR;
			i: INTEGER;
			ch, open: CHAR;
	BEGIN
		Oberon.OpenScanner(S, "NetSystem.EMail");
		IF S.class IN {Texts.Name, Texts.String} THEN COPY(S.s, email) ELSE email := "" END;
		Texts.OpenReader(R, Oberon.Par.text, Oberon.Par.pos);
		Texts.Read(R, ch);
		WHILE ~R.eot & (ch <= " ") DO
			Texts.Read(R, ch)
		END;
		IF (ch = 022X) OR (ch = "'") THEN
			open := ch; Texts.Read(R, ch)
		ELSE
			open := 0X
		END;
		i := 0;
		WHILE ~R.eot & (ch > " ") & (ch # open) DO
			name[i] := ch; INC(i);
			Texts.Read(R, ch)
		END;
		name[i] := 0X;
		ScanDest(name, host, queue);
		IF (host # "") & (queue # "") THEN
			Texts.OpenScanner(S, Oberon.Par.text, Texts.Pos(R));
			Texts.Scan(S);
			IF S.class IN {Texts.String, Texts.Name} THEN
				COPY(S.s, job)
			ELSIF S.class = Texts.Int THEN
				IntToStr(S.i, S.s);
				COPY(S.s, job)
			ELSE
				job := ""
			END;
			Texts.WriteString(W, "Remove ");
			IF job # "" THEN
				Texts.WriteString(W, "job ");
				Texts.WriteString(W, job)
			ELSE
				Texts.WriteString(W, "all jobs")
			END;
			Texts.WriteString(W, " for ");
			Texts.WriteString(W, email);
			Texts.WriteString(W, " on ");
			Texts.WriteString(W, queue);
			Texts.Write(W, "@");
			Texts.WriteString(W, host);
			Texts.Append(Oberon.Log, W.buf);
			IF Connect(C, host) THEN
				NetSystem.Write(C, 05X); (* remove jobs *)
				SendString(C, queue);
				NetSystem.Write(C, " ");
				SendString(C, email);
				IF job # "" THEN
					NetSystem.Write(C, " ");
					SendString(C, job)
				END;
				NetSystem.Write(C, LF);
				NetSystem.CloseConnection(C)
			ELSE
				Texts.WriteString(W, " connecting failed")
			END;
			Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf)
		END
	END RemoveJob;

(** LPRPrinter.BannerPage ( "on" | "off") *)
	PROCEDURE BannerPage*;
		VAR S: Texts.Scanner;
	BEGIN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(S);
		IF S.class IN {Texts.Name, Texts.String} THEN
			CASE CAP(S.s[0]) OF
				"Y", "J", "T": bannerPage := TRUE
				|"N", "F": bannerPage := FALSE
				|"O": IF CAP(S.s[1]) = "N" THEN
							bannerPage := TRUE
						ELSIF CAP(S.s[1]) = "F" THEN
							bannerPage := FALSE
						END
			ELSE
			END
		ELSE
			bannerPage := ~bannerPage
		END;
		Texts.WriteString(W, "BannerPage = ");
		IF bannerPage THEN
			Texts.WriteString(W, "on")
		ELSE
			Texts.WriteString(W, "off")
		END;
		Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf)
	END BannerPage;

(** LPRPrinter.MailBack  ( "on" | "off") *)
	PROCEDURE MailBack*;
		VAR S: Texts.Scanner;
	BEGIN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(S);
		IF S.class IN {Texts.Name, Texts.String} THEN
			CASE CAP(S.s[0]) OF
				"Y", "J", "T": mailBack := TRUE
				|"N", "F": mailBack := FALSE
				|"O": IF CAP(S.s[1]) = "N" THEN
							mailBack := TRUE
						ELSIF CAP(S.s[1]) = "F" THEN
							mailBack := FALSE
						END
			ELSE
			END
		ELSE
			mailBack := ~mailBack
		END;
		Texts.WriteString(W, "MailBack = ");
		IF mailBack THEN
			Texts.WriteString(W, "on")
		ELSE
			Texts.WriteString(W, "off")
		END;
		Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf)
	END MailBack;

	PROCEDURE NewPrinter*(): Printer.Printer;
		VAR P: Printer.Printer;
	BEGIN
		P := PSPrinter.NewPrinter();
		P.name := "LPRPrinter.Install";
		P.Open := Open;
		P.Close := Close;
		RETURN P
	END NewPrinter;
	
	PROCEDURE Install*;
	BEGIN
		Printer.Install(NewPrinter())
	END Install;

BEGIN
	Texts.OpenWriter(W);
	jobNr := 99;
	bannerPage := TRUE; mailBack := FALSE
END LPRPrinter.

System.Free LPRPrinter PSPrinter ~

LPRPrinter.Install

LPRPrinter.ShowJobs lph1@lillian ~
LPRPrinter.ShowJobs "lph1-ds@lillian" ~
LPRPrinter.RemoveJob lph1@lillian 100 ~

LPRPrinter.MailBack on
LPRPrinter.BannerPage on

LPRPrinter.PrintPSFile lph1@lillian Win95ETHDialback.ps
