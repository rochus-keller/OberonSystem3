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

MODULE Finger;	(** portable *) (* jm 4.7.95 *) (* ejz,   *)

(** Finger (RFC 1288) with Oberon text document support.

	Insert into your plain old ASCII .plan or .project file 
	the line
	
	-----ASCIICODED
	
	followed directly on the next line by an AsciiCoded version
	of the Oberon text you want to have shown instead of
	the normal contents of .plan or .project.
	
	Command Interface
	
	Usage:	Finger.Finger user@host
	Example:	Finger.Finger marais@lillian.inf.ethz.ch.
	
	Document Interface

	E.g.: Desktops.OpenDoc "finger://lillian.inf.ethz.ch/zeller".
	The following line should be added to the LinkSchemes section of the Registry:
		finger = Finger.NewLinkScheme
	And the following line to the Documents section:
		finger = Finger.NewDoc. *)

IMPORT Files, Objects, NetSystem, Strings, HyperDocs, NetTools, Attributes, Texts, Oberon, AsciiCoder, Documents, TextDocs,
	Links;

CONST
	DefPort* = 79;
	Temp = "Finger.Tmp";

VAR W: Texts.Writer;
	line: ARRAY NetTools.MaxLine OF CHAR;

(** Parsing of a finger url. *)
	PROCEDURE Split*(VAR url, host, request: ARRAY OF CHAR; VAR port: INTEGER): LONGINT;
		VAR
			key, i, j, l: LONGINT;
			iskey: BOOLEAN;
			portS: ARRAY 8 OF CHAR;
		PROCEDURE Blanks();
		BEGIN
			WHILE (url[i] # 0X) & (url[i] <= " ") DO
				INC(i)
			END
		END Blanks;
	BEGIN
		(* Pre: url must be a finger url *)
		HyperDocs.UnESC(url);
		port := DefPort;
		i := 0;
		Blanks();
		(* skip finger *)
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
		iskey := TRUE;
		(* get host *)
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
			(* url was a key *)
			IF host # "" THEN
				Strings.StrToInt(host, key);
				HyperDocs.RetrieveLink(key, line);
				key := Split(line, host, request, port);
				RETURN key
			ELSE
				RETURN HyperDocs.UndefKey
			END
		END;
		IF url[i] = ":" THEN
			(* get port *)
			port := 0; INC(i);
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
		(* get request *)
		IF url[i] = "/" THEN
			INC(i)
		END;
		l := LEN(request);
		j := 0;
		WHILE url[i] # 0X DO
			IF j < l THEN
				request[j] := url[i]; INC(j)
			END;
			INC(i)
		END;
		request[j] := 0X;
		DEC(j);
		WHILE (j >= 0) & (request[j] <= " ") DO
			request[j] := 0X; DEC(j)
		END;
		(* normalize url *)
		COPY("finger://", url);
		Strings.Lower(host, host);
		Strings.Append(url, host);
		IF port # DefPort THEN
			Strings.AppendCh(url, ":");
			Strings.IntToStr(port, portS);
			Strings.Append(url, portS)
		END;
		IF request # "" THEN
			Strings.AppendCh(url, "/");
			Strings.Append(url, request)
		END;
		key := HyperDocs.RegisterLink(url);
		RETURN key
	END Split;

PROCEDURE finger0(VAR host, request: ARRAY OF CHAR; port: INTEGER; VAR F: Files.File);
VAR C: NetSystem.Connection;
	len, rlen, i, pos, count, coded: LONGINT; buf, cache: ARRAY 256 OF CHAR; ch: CHAR;
	ok: BOOLEAN; T: Texts.Text;
	
	PROCEDURE Cache(ch: CHAR);
	BEGIN IF pos < LEN(cache) - 1 THEN cache[pos] := ch; INC(pos) END;
	END Cache;
	
	PROCEDURE EndCache;
	BEGIN cache[pos] := 0X; pos := 0
	END EndCache;
	
BEGIN F := NIL; coded := -1;
	IF NetTools.Connect(C, port, host, FALSE) THEN
		NetTools.SendString(C, "/W "); (* verbose mode *)
		NetSystem.WriteString(C, request);
		NetTools.curPos := 0; NetTools.curLen := 128;
		pos := 0; count := 0;
		len := NetSystem.Available(C);
		WHILE (len > 0) OR (NetSystem.State(C) IN {NetSystem.in, NetSystem.inout}) DO
			WHILE len > 0 DO
				IF len > LEN(buf) THEN rlen := LEN(buf) ELSE rlen := len END;
				NetSystem.ReadBytes(C, 0, rlen, buf);
				INC(NetTools.curPos, rlen); NetTools.ProgMNotify();
				FOR i := 0 TO rlen - 1 DO
					ch := buf[i];
					IF ch = 0DX THEN
					ELSIF ch = 0AX THEN EndCache;
						Texts.WriteLn(W); INC(count);
						IF cache = "-----ASCIICODED" THEN coded := count END;
					ELSE Cache(ch);
						Texts.Write(W, ch); INC(count);
					END
				END;
				DEC(len, rlen);
			END;
			len := NetSystem.Available(C)
		END;
		IF W.buf.len > 0 THEN
			IF coded >= 0 THEN
				NEW(T); Texts.Open(T, "");
				Texts.Append(T, W.buf);
				F := Files.New(Temp);
				Texts.Save(T, 0, coded-1, W.buf);
				AsciiCoder.Decode(T, coded, F, ok);
				IF ok THEN
					Files.Register(F)
				ELSE F := NIL
				END
			END
		END;
		NetTools.Disconnect(C);
	END
END finger0;

(** Send the finger request to host. Most finger servers use port = Finger.DefPort.
		If the request failed for any reason, T is set to NIL otherwise T contains the response. *)
	PROCEDURE finger*(VAR host, request: ARRAY OF CHAR; port: INTEGER; VAR T: Texts.Text);
		VAR
			F: Files.File;
			res: INTEGER;
	BEGIN
		finger0( host, request, port, F);
		NEW(T);
		IF F # NIL THEN
			Texts.Open(T, Temp);
			Texts.Insert(T, 0, W.buf);
			Files.Delete(Temp, res)
		ELSE
			Texts.Open(T, "");
			Texts.Append(T, W.buf);
			IF T.len <= 0 THEN
				T := NIL
			END
		END
	END finger;

	PROCEDURE *LinkSchemeHandler(L: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			host: ARRAY NetTools.ServerStrLen OF CHAR;
			request: ARRAY NetTools.PathStrLen OF CHAR;
			len: LONGINT;
			T: Texts.Text;
			F: Files.File;
			R: Files.Rider;
			ch: CHAR;
			port, res: INTEGER;
	BEGIN
		WITH L: HyperDocs.LinkScheme DO
			IF M IS HyperDocs.RegisterLinkMsg THEN
				WITH M: HyperDocs.RegisterLinkMsg DO
					M.key := Split(M.link, host, request, port);
					IF M.key # HyperDocs.UndefKey THEN
						M.res := 0
					END
				END
			ELSIF M IS HyperDocs.FetchMsg THEN
				WITH M: HyperDocs.FetchMsg DO
					IF M.key # HyperDocs.UndefKey THEN
						HyperDocs.RetrieveLink(M.key, line);
						M.key := Split(line, host, request, port);
						Texts.WriteString(W, "finger://");
						Texts.WriteString(W, host);
						Texts.Write(W, "/");
						Texts.WriteString(W, request);
						Texts.Append(Oberon.Log, W.buf);
						finger0(host, request, port, F);
						IF F = NIL THEN
							NEW(T); Texts.Open(T, "");
							Texts.Append(T, W.buf);
							IF T.len > 0 THEN
								Texts.Store(T, Files.Base(M.R), Files.Pos(M.R), len);
								Files.Set(M.R, Files.Base(M.R), Files.Pos(M.R)+len);
								M.res := 0
							ELSE
								Texts.WriteString(W, " failed")
							END
						ELSE
							Files.Set(R, F, 0);
							Files.Read(R, ch);
							WHILE ~R.eof DO
								Files.Write(M.R, ch); Files.Read(R, ch)
							END;
							Files.Delete(Temp, res);
							M.res := 0
						END;
						IF M.res = 0 THEN
							Texts.WriteString(W, " done")
						END;
						Texts.WriteLn(W);
						Texts.Append(Oberon.Log, W.buf)
					ELSE
						M.res := 0
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.class := Objects.String;
						M.s := "Finger.NewLinkScheme";
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
		L.usePath := FALSE;
		Objects.NewObj := L
	END NewLinkScheme;

	PROCEDURE *LoadDoc(D: Documents.Document);
		VAR
			host: ARRAY NetTools.ServerStrLen OF CHAR;
			request: ARRAY NetTools.PathStrLen OF CHAR;
			port: INTEGER;
			key: LONGINT;
			T: Texts.Text;
	BEGIN
		D.dsc := NIL;
		key := Split(D.name, host, request, port);
		IF key # HyperDocs.UndefKey THEN
			finger(host, request, port, T);
			IF T # NIL THEN
				TextDocs.InitDoc(D);
				Links.SetLink(D.dsc, "Model", T)
			END;
			COPY(request, D.name);
			D.W := HyperDocs.docW; D.H := HyperDocs.docH;
			IF HyperDocs.context # NIL THEN
				HyperDocs.context.replace := FALSE;
				HyperDocs.context.history := FALSE
			END
		END
	END LoadDoc;

	PROCEDURE NewDoc*;
		VAR D: Documents.Document;
	BEGIN
		NEW(D);
		D.Load := LoadDoc;
		Objects.NewObj := D
	END NewDoc;

(** Finger.Finger user@host *)
	PROCEDURE Finger*;
		VAR
			S: Attributes.Scanner;
			host: ARRAY NetTools.ServerStrLen OF CHAR;
			request: ARRAY NetTools.PathStrLen OF CHAR;
			i, j: INTEGER;
			T: Texts.Text;
	BEGIN
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Attributes.Scan(S);
		IF S.class IN {Attributes.Name, Attributes.String} THEN
			j := 0; i := 0;
			WHILE (S.s[i] # 0X) & (S.s[i] # "@") DO
				request[j] := S.s[i];
				INC(j); INC(i)
			END;
			request[j] := 0X;
			IF S.s[i] = "@" THEN
				INC(i); j := 0;
				WHILE S.s[i] # 0X DO
					host[j] := S.s[i];
					INC(j); INC(i)
				END;
				host[j] := 0X;
				finger(host, request, DefPort, T);
				IF T # NIL THEN
					TextDocs.ShowText(S.s, T, HyperDocs.docW, HyperDocs.docH)
				END
			END
		END
	END Finger;

BEGIN Texts.OpenWriter(W)
END Finger.
