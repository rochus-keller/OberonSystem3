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

MODULE HTTPDocs;	(** portable *) (* ejz,   *)
	IMPORT Kernel, Files, Objects, Input, NetSystem, NetTools, Strings, HyperDocs, TextDocs, Texts, Links, Oberon, Documents,
		Attributes, HTTPDocs0, Streams, TextStreams, HTMLDocs, MIME;

(** This module implements the basis for the webbrowser.
		The following line should be added to the LinkSchemes section of the Registry:
			http = HTTPDocs.NewLinkScheme
		And the following line to the Documents section:
			http = HTTPDocs.NewDoc
		To access HTTP within a firewall, add the proxy to the NetSystem section of the Registry:
			HTTPProxy = host [ ":" port ] . *)

	CONST
		MaxWorkers = 4;
		IdentifyUser = FALSE;

	TYPE
		Worker = POINTER TO WorkerDesc;
		WorkerDesc = RECORD (HTTPDocs0.WorkerDesc)
			C: NetSystem.Connection;
			fname: ARRAY 32 OF CHAR;
			R: Files.Rider;
			cont: MIME.Content;
			useProxy: BOOLEAN
		END;
		Authorization =  POINTER TO AuthorizationDesc;
		AuthorizationDesc = RECORD
			host: ARRAY NetTools.ServerStrLen OF CHAR;
			path: ARRAY NetTools.PathStrLen OF CHAR;
			coded: ARRAY 64 OF CHAR;
			port: INTEGER;
			next: Authorization
		END;
		Cookie = POINTER TO CookieDesc;
		CookieDesc = RECORD
			name, domain: ARRAY 64 OF CHAR;
			val, path: ARRAY 256 OF CHAR;
			d, t: LONGINT;
			next: Cookie
		END;

	VAR
		W: Texts.Writer;
		buf: ARRAY NetTools.BufLen OF CHAR;
		noWorkers: INTEGER;
		encTable: ARRAY 64 OF CHAR;
		authorizations: Authorization;
		cookies: Cookie;
		EMail: ARRAY NetTools.ServerStrLen OF CHAR;
		client: ARRAY 64 OF CHAR;

	PROCEDURE *TCPAvailable(S: Streams.Stream): LONGINT;
	BEGIN
		HTTPDocs0.Wait(); RETURN NetTools.TCPAvailable(S)
	END TCPAvailable;

	PROCEDURE OpenStream(C: NetSystem.Connection): Streams.Stream;
		VAR S: Streams.Stream;
	BEGIN
		S := NetTools.OpenStream(C);
		S.Available := TCPAvailable;
		RETURN S
	END OpenStream;

	PROCEDURE EncBase64(VAR src, dest: ARRAY OF CHAR);
		VAR
			s, d, i, j, c, c0, c1, c2: LONGINT;
			chars: ARRAY 3 OF CHAR;
		PROCEDURE OutCode();
		BEGIN
			c0 :=ORD(chars[0]);
			c := ASH(c0, -2);
			dest[d] := encTable[c]; INC(d); c0 := c0-ASH(c, 2);
			c1 := ORD(chars[1]);
			c := ASH(c0, 4)+ASH(c1, -4);
			dest[d] := encTable[c]; INC(d); c1 := c1 MOD ASH(1, 4);
			c2 := ORD(chars[2]);
			c := ASH(c1, 2)+ASH(c2, -6);
			dest[d] := encTable[c]; INC(d); c2 := c2 MOD ASH(1, 6);
			dest[d] := encTable[c2]; INC(d)
		END OutCode;
	BEGIN
		s := 1; d := 0;
		chars[0] := src[0]; i := 1;
		WHILE src[s] # 0X DO
			IF i >= 3 THEN
				OutCode(); i := 0
			END;
			chars[i] := src[s]; INC(i);
			INC(s)
		END;
		IF i > 0 THEN
			j := i;
			WHILE i < 3 DO
				chars[i] := 0X; INC(i)
			END;
			OutCode();
			IF j < 3 THEN
				j := 3-j; d := d-j;
				FOR i := 1 TO j DO
					dest[d] := "="; INC(d)
				END
			END
		END;
		dest[d] := 0X
	END EncBase64;

	PROCEDURE GetAuthorization(VAR host, path: ARRAY OF CHAR; port: INTEGER): Authorization;
		VAR aut: Authorization;
	BEGIN
		aut := authorizations;
		WHILE (aut # NIL) & (aut.port # port) & (aut.host # host) & (aut.path # path) DO
			aut := aut.next
		END;
		RETURN aut
	END GetAuthorization;

	PROCEDURE FindCookie(root: Cookie; VAR host, path: ARRAY OF CHAR): Cookie;
		VAR c: Cookie;
	BEGIN
		c := root;
		WHILE (c # NIL) & ~Strings.Prefix(c.path, path) DO
			c := c.next
		END;
(* check domain & date *)
		RETURN c
	END FindCookie;

	PROCEDURE AddCookie(VAR host, path, value: ARRAY OF CHAR);
(* value = name = val ";" [ "path" = path ";" ] [ "expires" = date ";" ] [ "domain" = domain ";" ] . *)
		VAR
			i: LONGINT;
			name: ARRAY 64 OF CHAR;
			C, c: Cookie;
			p, e, d: BOOLEAN;
		PROCEDURE Skip();
		BEGIN
			WHILE (value[i] <= " ") & (value[i] # 0X) DO
				INC(i)
			END
		END Skip;
		PROCEDURE GetName();
			VAR j: LONGINT;
		BEGIN
			Skip(); j := 0;
			WHILE (value[i] > " ") & (value[i] # "=") & (value[i] # 0X) DO
				name[j] := Strings.UpperCh(value[i]); INC(j); INC(i)
			END;
			name[j] := 0X;
			Skip();
			IF value[i] = "=" THEN
				INC(i)
			END; Skip()
		END GetName;
		PROCEDURE GetValue(VAR val: ARRAY OF CHAR);
			VAR j: LONGINT;
		BEGIN
			Skip(); j := 0;
			WHILE (value[i] # ";") & (value[i] # 0X) DO
				val[j] := value[i]; INC(j); INC(i)
			END;
			val[j] := 0X;
			Skip();
			IF value[i] = ";" THEN
				INC(i)
			END; Skip()
		END GetValue;
	BEGIN
		i := 0;
		WHILE (value[i] # ":") & (value[i] # 0X) DO
			INC(i)
		END;
		IF value[i] = ":" THEN
			p := FALSE; e := FALSE; d := FALSE;
			C := NIL; INC(i);
			WHILE value[i] # 0X DO
				GetName();
				IF value[i] # 0X THEN
					IF C = NIL THEN NEW(C); C.name := "" END;
					IF name = "PATH" THEN
						GetValue(C.path); p := TRUE
					ELSIF name = "EXPIRES" THEN
						GetValue(name);
						
						e := TRUE
					ELSIF name = "DOMAIN" THEN
						GetValue(C.domain); d := TRUE
					ELSE
						COPY(name, C.name); GetValue(C.val)
					END
				END
			END;
			IF (C # NIL) & (C.name # "") THEN
				IF ~p THEN
					COPY(path, C.path)
				END;
				IF ~d THEN
					COPY(host, C.domain)
				END;
				IF ~e THEN
				
				END;
				c := cookies;
				WHILE (c # NIL) & ((c.name # C.name) OR (c.path # C.path)) DO
					c := c.next
				END;
				IF c # NIL THEN
					COPY(C.name, c.name);
					COPY(C.domain, c.domain);
					COPY(C.val, c.val);
					c.d := C.d; c.t := C.t
				ELSE
					C.next := cookies; cookies := C
				END
			END
		END
	END AddCookie;

(* "http://home.mcom.com/assist/support/server/tn/cross-platform/20019.html" *)
PROCEDURE ListCookies*;
	VAR c: Cookie;
BEGIN
	c := cookies;
	WHILE c # NIL DO
		Texts.WriteString(W, c.name); Texts.Write(W, "="); Texts.WriteString(W, c.val); Texts.Write(W, ";");
		Texts.WriteString(W, "path="); Texts.WriteString(W, c.path); Texts.Write(W, ";");
		Texts.WriteString(W, "expires="); Texts.WriteDate(W, c.t, c.d); Texts.Write(W, ";");
		Texts.WriteString(W, "domain="); Texts.WriteString(W, c.domain); Texts.WriteLn(W);
		c := c.next
	END;
	Texts.Append(Oberon.Log, W.buf)
END ListCookies;

	PROCEDURE NetLen(T: Texts.Text): LONGINT;
		VAR
			R: Texts.Reader;
			len: LONGINT;
			ch: CHAR;
	BEGIN
		len := 0;
		Texts.OpenReader(R, T, 0);
		Texts.Read(R, ch);
		WHILE ~R.eot DO
			IF ch = Strings.CR THEN
				INC(len)
			END;
			INC(len);
			Texts.Read(R, ch)
		END;
		RETURN len
	END NetLen;

	PROCEDURE Request*(C: NetSystem.Connection; method: ARRAY OF CHAR; VAR key: LONGINT; proxy: BOOLEAN; VAR query: Texts.Text; log: BOOLEAN);
		VAR
			str: ARRAY 12 OF CHAR;
			R: Texts.Reader;
			host: ARRAY NetTools.ServerStrLen OF CHAR;
			path: ARRAY NetTools.PathStrLen OF CHAR;
			label: ARRAY 64 OF CHAR;
			i, j: LONGINT;
			aut: Authorization;
			cookie: Cookie;
			port: INTEGER;
			ch: CHAR;
	BEGIN
		aut := NIL;
		IF log & (method # "GET") THEN
			Texts.WriteString(W, method); Texts.Write(W, " ")
		END;
		NetTools.SendString(C, method); NetSystem.Write(C, " ");
		HyperDocs.RetrieveLink(key, buf);
		IF ~proxy OR Strings.CAPPrefix("http:", buf) THEN
			key := HTTPDocs0.SplitHTTPAdr(buf, host, path, label, port);
			IF log THEN
				Texts.Append(Oberon.Log, W.buf)
			END;
			j := -1; i := 0;
			WHILE (path[i] # 0X) & (j < 0) DO
				IF path[i] = "?" THEN
					j := i
				(*ELSIF path[i] = "/" THEN
					j := -1*)
				END;
				INC(i)
			END;
			IF j > 0 THEN
				path[j] := 0X;
				IF query = NIL THEN
					INC(j);
					WHILE path[j] # 0X DO
						Texts.Write(W, path[j]); INC(j)
					END;
					NEW(query); Texts.Open(query, "");
					Texts.Append(query, W.buf)
				END
			END;
			IF proxy THEN
				buf := "http://";
				Strings.Append(buf, host);
				Strings.AppendCh(buf, ":");
				Strings.IntToStr(port, str);
				Strings.Append(buf, str);
				IF log THEN
					Texts.WriteString(W, host)
				END;
				NetTools.SendString(C, buf)
			END;
			aut := GetAuthorization(host, path, port);
			IF (aut = NIL) & (HyperDocs.context # NIL) & (HyperDocs.context IS HTTPDocs0.Context) & (HyperDocs.context(HTTPDocs0.Context).user # "") THEN
				NEW(aut);
				COPY(host, aut.host); aut.port := port; COPY(path, aut.path);
				COPY(HyperDocs.context(HTTPDocs0.Context).user, label);
				Strings.AppendCh(label, ":");
				Strings.Append(label, HyperDocs.context(HTTPDocs0.Context).passwd);
				EncBase64(label, aut.coded);
				HyperDocs.context(HTTPDocs0.Context).user := "";
				aut.next := authorizations; authorizations := aut
			END;
			COPY(path, buf);
			HyperDocs.ESC(buf, 0X);
			IF log THEN
				Texts.WriteString(W, buf)
			END;
			NetTools.SendString(C, buf);
			IF (query # NIL) & (method = "GET") THEN
				Strings.AppendCh(path, "?");
				i := 0;
				WHILE path[i] # 0X DO
					INC(i)
				END;
				Texts.OpenReader(R, query, 0);
				Texts.Read(R, ch);
				WHILE ~R.eot DO
					path[i] := ch; INC(i);
					Texts.Read(R, ch)
				END;
				path[i] := 0X;
				key := HTTPDocs0.RegisterHTTPAdr(host, path, label, port)
			END
		ELSE (* gopher or ftp with proxy *)
			IF log THEN
				Texts.WriteString(W, buf)
			END;
			NetTools.SendString(C, buf)
		END;
		IF (method = "GET") & (query # NIL) THEN
			NetSystem.Write(C, "?");
			Texts.OpenReader(R, query, 0);
			Texts.Read(R, ch);
			WHILE ~R.eot DO
				NetSystem.Write(C, ch);
				Texts.Read(R, ch)
			END
		END;
		IF log THEN
			Texts.Append(Oberon.Log, W.buf)
		END;
		NetSystem.WriteString(C, " HTTP/1.0");
		NetSystem.WriteString(C, "Accept: *.*");
		NetTools.SendString(C, "Host: "); NetSystem.WriteString(C, host);
		IF IdentifyUser & NetTools.QueryString("EMail", EMail) THEN
			NetTools.SendString(C, "From: "); NetSystem.WriteString(C, EMail)
		END;
		IF (HyperDocs.context # NIL) & (HyperDocs.context.old # NIL) THEN
			NetTools.SendString(C, "Referer: ");
			HyperDocs.RetrieveLink(HyperDocs.context.old.key, buf);
			NetSystem.WriteString(C, buf)
		END;
		IF aut # NIL THEN
			NetTools.SendString(C, "Authorization: Basic ");
			NetSystem.WriteString(C, aut.coded)
		END;
		NetTools.SendString(C, "User-Agent: "); NetSystem.WriteString(C, client);
		cookie := FindCookie(cookies, host, path);
		WHILE cookie # NIL DO
			NetTools.SendString(C, "Cookie: ");
			NetTools.SendString(C, cookie.name);
			NetSystem.Write(C, "=");
			NetSystem.WriteString(C, cookie.val);
			cookie := cookie.next;
			cookie := FindCookie(cookie, host, path)
		END;
		IF (method = "POST") & (query # NIL) & (query.len > 0) THEN
			NetSystem.WriteString(C, "Content-Type: application/x-www-form-urlencoded");
			NetTools.SendString(C, "Content-Length: ");
			Strings.IntToStr(NetLen(query), str);
			NetSystem.WriteString(C, str); NetTools.SendString(C, Strings.CRLF);
			MIME.WriteText(query, 0, query.len, OpenStream(C), MIME.textCont, FALSE, FALSE)
		END;
		NetTools.SendString(C, Strings.CRLF); NetTools.SendString(C, Strings.CRLF)
	END Request;

	PROCEDURE Response*(VAR C: NetSystem.Connection; key: LONGINT; main: BOOLEAN; VAR cont: MIME.Content; VAR location: ARRAY OF CHAR; log: BOOLEAN): LONGINT;
		VAR
			pos, len, time, status: LONGINT;
			base: HyperDocs.DefURL;
			h: MIME.Header;
			i: INTEGER;
	BEGIN
		NEW(base); HyperDocs.RetrieveLink(key, buf);
		key := HTTPDocs0.SplitHTTPAdr(buf, base.host, base.path, base.label, base.port);
		status := 0; COPY("", location);
		NEW(cont); cont.typ := MIME.GetContentType("text/plain"); cont.encoding := MIME.EncBin; cont.len := 0;
		time := Input.Time() + NetTools.TimeOut;
		REPEAT
			IF log THEN HTTPDocs0.Wait() END;
			len := NetSystem.Available(C)
		UNTIL (len > 0) OR ~NetTools.Connected(C, NetSystem.in) OR NetTools.UserBreak() OR (Input.Time() - time > 0);
		IF len <= 0 THEN
			IF log THEN
				Texts.WriteString(W, " no response");
				Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf)
			END;
			NetTools.Disconnect(C); C := NIL;
			RETURN status
		END;
		NetSystem.ReadString(C, buf);
		IF buf = "" THEN
			RETURN status
		ELSIF Strings.CAPPrefix("HTTP", buf) THEN
			i := 0;
			WHILE (buf[i] # 0X) & (buf[i] > " ") DO
				INC(i)
			END;
			Strings.StrToIntPos(buf, status, i);
			IF ~main & ((status < 200) OR (status >= 400)) THEN
				IF log THEN
					Texts.WriteLn(W);
					Texts.WriteString(W, buf);
					Texts.WriteLn(W);
					Texts.Append(Oberon.Log, W.buf)
				END;
				NetTools.Disconnect(C); C := NIL;
				RETURN status
			ELSIF status = 204 THEN
				RETURN status
			END
		ELSIF buf[0] = "<" THEN
			cont.typ := MIME.GetContentType("text/html"); buf := ""
		ELSE
			buf := ""
		END;
		IF buf # "" THEN
			MIME.ReadHeader(NetTools.OpenStream(C), NIL, h, len);
			pos := MIME.FindField(h, "Content-Type");
			IF pos > 0 THEN
				MIME.ExtractContentType(h, pos, cont);
				IF log THEN
					Texts.Write(W, " ");
					Texts.WriteString(W, cont.typ.typ);
					Texts.Write(W, "/");
					Texts.WriteString(W, cont.typ.subTyp)
				END;
				IF ~cont.typ.support THEN
					IF ~log THEN
						Texts.Write(W, " ");
						Texts.WriteString(W, cont.typ.typ);
						Texts.Write(W, "/");
						Texts.WriteString(W, cont.typ.subTyp)
					END;
					Texts.WriteString(W, " not supported");
					(*Texts.WriteLn(W);*) Texts.Append(Oberon.Log, W.buf)
				END;
				IF cont.typ.typ = "text" THEN
					pos := MIME.FindField(h, "Content-Transfer-Encoding");
					MIME.TextEncoding(h, pos, cont)
				END
			END;
			pos := MIME.FindField(h, "Content-Length");
			IF pos > 0 THEN
				MIME.ExtractValue(h, pos, buf);
				Strings.StrToInt(buf, cont.len)
			END;
			pos := MIME.FindField(h, "Location");
			IF (pos > 0) & (status >= 300) THEN
				MIME.ExtractValue(h, pos, location)
			END;
			pos := MIME.FindField(h, "Set-Cookie");
			IF pos > 0 THEN
				MIME.ExtractValue(h, pos, buf);
				AddCookie(base.host, base.path, buf)
			END
		END;
		IF log THEN
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END;
		RETURN status
	END Response;

	PROCEDURE Connect(VAR C: NetSystem.Connection; proxy: HTTPDocs0.Proxy; main, waitR, reloc, block: BOOLEAN; 
	method: ARRAY OF CHAR; VAR key: LONGINT; VAR cont: MIME.Content; query: Texts.Text; log: BOOLEAN; VAR useProxy: BOOLEAN): LONGINT;
		VAR
			status, key2: LONGINT;
			location: ARRAY NetTools.MaxLine OF CHAR;
			host: ARRAY NetTools.ServerStrLen OF CHAR;
			base: HyperDocs.DefURL;
			port: INTEGER;
	BEGIN
		status := 0; HyperDocs.RetrieveLink(key, location);
		NetTools.SplitHostPort(location, host, port);
		useProxy := NetTools.UseProxy(host) & (proxy # NIL);
		IF ~useProxy THEN
			IF port <= 0 THEN
				port := HTTPDocs0.DefPort
			END;
			IF block THEN
				IF ~NetTools.Connect(C, port, host, log) THEN
					C := NIL
				END
			ELSE
				IF ~NetTools.AsyncConnect(C, port, host, log) THEN
					C := NIL
				END
			END
		ELSE
			IF block THEN
				IF ~NetTools.Connect(C, proxy.port, proxy.host, FALSE) THEN
					C := NIL
				END
			ELSE
				IF ~NetTools.AsyncConnect(C, proxy.port, proxy.host, FALSE) THEN
					C := NIL
				END
			END
		END;
		IF C # NIL THEN
			IF log THEN
				Texts.Write(W, " ");
				Texts.Append(Oberon.Log, W.buf)
			END;
			IF waitR THEN
				Request(C, method, key, useProxy, query, log);
				status := Response(C, key, main, cont, location, log);
				IF C = NIL THEN
					RETURN status
				END;
				IF reloc & (location # "") THEN
					NEW(base);
					base.key := key; base.prefix := "http";
					HyperDocs.RetrieveLink(base.key, buf);
					key2 := HTTPDocs0.SplitHTTPAdr(buf, base.host, base.path, host, base.port);
					key2 := HyperDocs.BuildKey(base, location);
					IF key # key2 THEN
						IF log THEN
							Texts.WriteString(W, "relocating ");
							Texts.Append(Oberon.Log, W.buf)
						END;
						NetTools.Disconnect(C);
						key := key2; query := NIL; COPY("GET", method);
						status := Connect(C, proxy, main, waitR, FALSE, block, method, key, cont, query, log, useProxy)
					END
				END
			END
		END;
		IF log THEN
			Texts.Append(Oberon.Log, W.buf)
		END;
		RETURN status
	END Connect;

	PROCEDURE ^OpenHTTPDoc(D: Documents.Document; key: LONGINT; proxy: HTTPDocs0.Proxy);

	PROCEDURE *LinkSchemeHandler(L: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			link: ARRAY NetTools.MaxLine OF CHAR;
			host: ARRAY NetTools.ServerStrLen OF CHAR;
			path: ARRAY NetTools.PathStrLen OF CHAR;
			label: ARRAY 64 OF CHAR;
			cont: MIME.Content;
			C: NetSystem.Connection;
			status: LONGINT;
			proxy: HTTPDocs0.Proxy;
			T: Texts.Text;
			port: INTEGER;
			useProxy: BOOLEAN;
	BEGIN
		WITH L: HyperDocs.LinkScheme DO
			IF M IS HyperDocs.RegisterLinkMsg THEN
				WITH M: HyperDocs.RegisterLinkMsg DO
					status := HyperDocs.CheckPrefix(M.link);
					IF status >= 0 THEN
						IF M.base = NIL THEN
							M.key := HTTPDocs0.SplitHTTPAdr(M.link, host, path, label, port)
						ELSIF (status < 2) & (M.base.prefix = "http") THEN
							link := "http://"; Strings.Append(link, M.base.host);
							IF M.base.port # HTTPDocs0.DefPort THEN
								Strings.AppendCh(link, ":"); Strings.IntToStr(M.base.port, label); Strings.Append(link, label)
							END;
							HyperDocs.Path(M.base, link, M.link); M.key := HyperDocs.RegisterLink(link)
						ELSE
							M.key := HTTPDocs0.SplitHTTPAdr(M.link, host, path, label, port)
						END
					ELSIF M.base.prefix = "http" THEN
						link := "http://"; Strings.Append(link, M.base.host);
						IF M.base.port # HTTPDocs0.DefPort THEN
							Strings.AppendCh(link, ":"); Strings.IntToStr(M.base.port, label); Strings.Append(link, label)
						END;
						HyperDocs.Path(M.base, link, M.link); M.key := HyperDocs.RegisterLink(link)
					ELSE
						HyperDocs.LinkSchemeHandler(L, M)
					END;
					IF M.key # HyperDocs.UndefKey THEN
						M.res := 0
					END
				END
			ELSIF M IS HyperDocs.InfoMsg THEN
				WITH M: HyperDocs.InfoMsg DO
					status := Connect(C, HTTPDocs0.httpProxy, TRUE, FALSE, FALSE, TRUE, "HEAD", M.key, cont, NIL, TRUE, useProxy);
					IF C # NIL THEN T := NIL;
						Request(C, "HEAD", M.key, useProxy, T, TRUE);
						status := Response(C, M.key, TRUE, cont, path, TRUE);
						M.contType := cont.typ; M.size := cont.len;
						NetTools.Disconnect(C);
						M.res := 0
					ELSE
						HyperDocs.LinkSchemeHandler(L, M)
					END
				END
			ELSIF M IS HyperDocs.FetchMsg THEN
				WITH M: HyperDocs.FetchMsg DO
					IF M.key # HyperDocs.UndefKey THEN
						status := Connect(C, HTTPDocs0.httpProxy, TRUE, TRUE, TRUE, TRUE, "GET", M.key, cont, NIL, TRUE, useProxy);
						IF C # NIL THEN
							IF (status >= 200) & (status < 400) THEN
								M.res := 0;
								Texts.WriteString(W, " downloading ");
								Texts.Append(Oberon.Log, W.buf);
								NetTools.ReadData(C, M.R, MAX(LONGINT));
								Texts.WriteString(W, " done");
								Texts.WriteLn(W)
							END;
							NetTools.Disconnect(C)
						END;
						Texts.Append(Oberon.Log, W.buf)
					ELSE
						M.res := 0
					END
				END
			ELSIF M IS NetTools.ProxyMsg THEN
				WITH M: NetTools.ProxyMsg DO
					NEW(proxy);
					COPY(M.host, proxy.host); proxy.port := M.port;
					OpenHTTPDoc(M.D, M.key, proxy)
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.class := Objects.String;
						M.s := "HTTPDocs.NewLinkScheme";
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

	PROCEDURE ^StartWorker();

	PROCEDURE *DoWork(me: Oberon.Task);
		VAR
			e: HTTPDocs0.Entry;
			len, key: LONGINT;
			F: Files.File;
			location: ARRAY 1024 OF CHAR;
			T: Texts.Text;
			state: INTEGER;
	BEGIN
		WITH me: Worker DO
			IF me.local THEN RETURN END;
			CASE me.state OF
				0: IF me.entry.doc = NIL THEN
						me.entry.doc := HyperDocs.GetCachedDoc(me.entry.key);
						IF me.entry.doc = NIL THEN
							len := Connect(me.C, HTTPDocs0.httpProxy, FALSE, FALSE, FALSE, FALSE, "GET", me.entry.key, me.cont, NIL, FALSE, me.useProxy);
							IF me.C # NIL THEN
								me.state := 1; me.time := Input.Time() + (Input.TimeUnit DIV 20)
							ELSE
								me.state := 6; me.time := Input.Time() + 2*Input.TimeUnit
							END
						END
					END;
					IF (me.entry.doc # NIL) & (me.entry.text.len > me.entry.pos) THEN
						me.state := 5; HTTPDocs0.InsertDoc(me)
					END
				|1: state := NetSystem.State(me.C);
					IF state IN {NetSystem.in, NetSystem.inout} THEN
						T := NIL;
						Request(me.C, "GET", me.entry.key, me.useProxy, T, FALSE);
						me.state := 2
					ELSIF state = NetSystem.waitCon THEN
						me.time := Input.Time() + (Input.TimeUnit DIV 20)
					ELSE (* errorCon *)
						me.state := 6; me.time := Input.Time() + 2*Input.TimeUnit
					END
				|2: len := NetSystem.Available(me.C);
					IF len > 0 THEN
						len := Response(me.C, me.entry.key, FALSE, me.cont, location, FALSE);
						IF me.C # NIL THEN
							IF location # "" THEN
								key := HyperDocs.BuildKey(NIL, location);
								IF key # me.entry.key THEN
									me.entry.key := key; me.state := 6
								END
							END;
							IF me.state = 2 THEN
								IF ~me.cont.typ.support THEN
									me.state := 5
								ELSIF me.cont.typ.typ = "text" THEN
									me.state := 5
								ELSE
									MIME.MakeTempName(me.cont.typ, me.fname);
									F := Files.New(me.fname);
									Files.Set(me.R, F, 0);
									me.state := 3
								END
							END
						ELSE
							me.state := 5
						END
					ELSE
						me.time := Input.Time() + (Input.TimeUnit DIV 20)
					END
				|3: len := NetSystem.Available(me.C);
					IF len > 0 THEN
						IF len > NetTools.BufLen THEN
							len := NetTools.BufLen
						END;
						NetSystem.ReadBytes(me.C, 0, len, buf);
						Files.WriteBytes(me.R, buf, len)
					ELSIF ~NetTools.Connected(me.C, NetSystem.in) THEN
						me.state := 4
					ELSE
						INC(me.time, Input.TimeUnit DIV 50)
					END
				|4: Files.Register(Files.Base(me.R)); me.state := 5;
						me.entry.doc := Documents.Open(me.fname);
						IF (me.entry.doc # NIL) & (me.entry.doc.dsc # NIL) THEN
							HyperDocs.CacheDoc(me.entry.key, me.entry.doc);
							me.state := 0
						END
				|5, 6: IF me.C # NIL THEN
						NetTools.Disconnect(me.C); me.C := NIL;
					END;
					Oberon.Remove(me.entry.working);
					IF noWorkers > 0 THEN
						DEC(noWorkers)
					END;
					IF me # me.entry.working THEN
						Oberon.Remove(me)
					END;
					me.entry.working := NIL;
					IF me.state = 5 THEN
						e := HTTPDocs0.entries;
						WHILE (e # NIL) & (e.next # me.entry) DO
							e := e.next
						END;
						IF e # NIL THEN
							e.next := me.entry.next
						ELSE
							HTTPDocs0.entries := me.entry.next
						END
					END;
					Oberon.Collect(); StartWorker()
			END
		END
	END DoWork;

	PROCEDURE StartWorker();
		VAR
			W: Worker;
			E: HTTPDocs0.Entry;
	BEGIN
		E := HTTPDocs0.entries;
		WHILE (E # NIL) & (E.working # NIL) DO
			E := E.next
		END;
		IF E # NIL THEN
			INC(noWorkers);
			NEW(W); E.working := W; W.local := FALSE;
			W.C := NIL;
			W.state := 0;
			W.fname := "";
			Files.Set(W.R, NIL, 0);
			W.entry := E;
			W.safe := FALSE;
			W.time := Input.Time()+1;
			W.handle := DoWork;
			Oberon.Install(W)
		END
	END StartWorker;

	PROCEDURE Install(E: HTTPDocs0.Entry);
		VAR pe, e: HTTPDocs0.Entry;
	BEGIN
		E.working := NIL; E.same := NIL; E.doc := NIL;
		e := HTTPDocs0.entries;
		WHILE (e # NIL) & (e.key # E.key) DO
			e := e.next
		END;
		IF e # NIL THEN
			E.next := NIL;
			IF (e.text = E.text) & (e.pos = E.pos) THEN
				RETURN
			END;
			WHILE e.same # NIL DO
				e := e.same;
				IF (e.text = E.text) & (e.pos = E.pos) THEN
					RETURN
				END
			END;
			e.same := E
		ELSE
			pe := NIL; e := HTTPDocs0.entries;
			WHILE (e # NIL) & (e.basekey = E.basekey) DO
				pe := e; e := e.next
			END;
			IF pe # NIL THEN
				E.next := pe.next; pe.next := E
			ELSE
				E.next := HTTPDocs0.entries; HTTPDocs0.entries := E
			END;
			IF noWorkers < MaxWorkers THEN
				StartWorker()
			END
		END
	END Install;

(* Requests the document ientified by key. *)
	PROCEDURE *requestDoc(D: Documents.Document; proxy: HTTPDocs0.Proxy; VAR key: LONGINT; method: ARRAY OF CHAR; 
	main: BOOLEAN; E: HTTPDocs0.Entry; query: Texts.Text);
		VAR
			C: NetSystem.Connection;
			cont: MIME.Content;
			status, origKey: LONGINT;
			T: Texts.Text;
			D2: Documents.Document;
			temp: ARRAY 64 OF CHAR;
			F: Files.File;
			R: Files.Rider;
			S: Streams.Stream;
			i: LONGINT;
			P: HTMLDocs.Page;
			M: Objects.CopyMsg;
			useProxy, getQuery: BOOLEAN;
	BEGIN
		IF E # NIL THEN
			E.key := key; Install(E)
		ELSE
			D2 := HyperDocs.GetCachedDoc(key);
			IF (D2 # NIL) & (D2.dsc # NIL) THEN
				D^ := D2^; D.lib := NIL; D.ref := -1; RETURN
			ELSE
				i := HTTPDocs0.StripLoc(key); T := HyperDocs.GetCachedText(i);
				IF T # NIL THEN
					S := TextStreams.OpenReader(T, 0); S.mode := Streams.iso8859;
					HTMLDocs.Parse(D, key, S, TRUE, FALSE, FALSE);
					Attributes.SetInt(D, "DocURL", key);
					HyperDocs.RetrieveLink(key, D.name);
					RETURN
				ELSE
					P := HTMLDocs.pages;
					WHILE (P # NIL) & (P.docKey # key) DO
						P := P.next
					END;
					IF P # NIL THEN
						Objects.Stamp(M); M.dlink := NIL; M.obj := NIL; M.id := Objects.shallow;
						Documents.Copy(M, P.D, D); D.lib := NIL; D.ref := -1;
						Attributes.SetInt(D, "DocURL", key);
						HyperDocs.RetrieveLink(key, D.name);
						RETURN
					END
				END
			END;
			P := NIL; origKey := key;
			status := Connect(C, proxy, main, TRUE, TRUE, TRUE, method, key, cont, query, TRUE, useProxy);
			IF C # NIL THEN
				IF status = 204 THEN
					RETURN
				ELSIF status = 401 THEN
					TextDocs.InitDoc(D); D.W := HyperDocs.docW; D.H := HyperDocs.docH;
					NEW(T); Texts.Open(T, "Authorization.html");
					S := TextStreams.OpenReader(T, 0); S.mode := Streams.binary;
					HTMLDocs.Parse(D, key, S, TRUE, FALSE, FALSE)
				ELSIF cont.typ.support THEN
					IF cont.typ.typ = "text" THEN
						TextDocs.InitDoc(D); D.W := HyperDocs.docW; D.H := HyperDocs.docH;
						S := OpenStream(C);
						IF cont.typ.subTyp = "html" THEN
							HyperDocs.RetrieveLink(key, buf);
							getQuery := FALSE; i := 0;
							WHILE buf[i] # 0X DO
								getQuery := getQuery OR (buf[i] = "?"); INC(i)
							END;
							S.mode := Streams.iso8859;
							HTMLDocs.Parse(D, key (*origKey*), S, TRUE, (query = NIL) & ~getQuery, FALSE);
							C := NIL; P := HTMLDocs.pages
						ELSE
							NEW(T); Texts.Open(T, "");
							cont.len := MAX(LONGINT); MIME.ReadText(S, W, cont, FALSE);
							Texts.Append(T, W.buf);
							Links.SetLink(D.dsc, "Model", T);
							HyperDocs.RetrieveLink(origKey, D.name)
						END
					ELSE
						MIME.MakeTempName(cont.typ, temp);
						IF (cont.typ.typ = "application") & (cont.typ.subTyp = "octet-stream") THEN
							HyperDocs.RetrieveLink(origKey, D.name);
							Strings.GetSuffix(D.name, D.name);
							Strings.Append(temp, D.name)
						END;
						Texts.Append(Oberon.Log, W.buf);
						F := Files.New(temp); Files.Set(R, F, 0);
						NetTools.ReadData(C, R, MAX(LONGINT));
						Files.Register(F);
						D.name := ""; D.dsc := NIL;
						D2 := Documents.Open(temp);
						IF (D2 # NIL) & (D2.dsc # NIL) THEN
							D^ := D2^; D.lib := NIL; D.ref := -1;
(* HyperDocs.RetrieveLink(origKey, D.name) *)
						END
					END
				ELSE
					D.name := ""; D.dsc := NIL
				END;
				NetTools.Disconnect(C);
				IF (D # NIL) & (D.dsc # NIL) THEN
					IF (status >= 200) & (status < 400) & (cont.typ.typ = "text") & (cont.typ.subTyp = "html") THEN
						Attributes.SetInt(D, "DocURL", origKey);
						HyperDocs.RetrieveLink(key, D.name);
						IF query # NIL THEN
							HyperDocs.TempDocName("http://Temp.Query", D.name, key);
							IF P # NIL THEN
								P.docKey := key; P.cacheSource := TRUE
							END;
							IF (HyperDocs.context # NIL) & (HyperDocs.context.new # NIL) THEN
								HyperDocs.context.new.key := key
							END
						ELSE
							Attributes.GetString(D, "Type", temp);
							IF (temp # "HTML") & ~main THEN
								HyperDocs.CacheDoc(origKey, D)
							END
						END
					END
				END
			END
		END
	END requestDoc;

	PROCEDURE *OpenHTTPDoc(D: Documents.Document; key: LONGINT; proxy: HTTPDocs0.Proxy);
		VAR type: ARRAY 8 OF CHAR;
	BEGIN
		IF HyperDocs.context # NIL THEN
			HTTPDocs0.curNode := HyperDocs.context.new;
			IF HyperDocs.context IS HTTPDocs0.Context THEN
				HTTPDocs0.RequestDoc(D, proxy, key, HyperDocs.context(HTTPDocs0.Context).method, TRUE, NIL, HyperDocs.context(HTTPDocs0.Context).query)
			ELSE
				HTTPDocs0.RequestDoc(D, proxy, key, "GET", TRUE, NIL, NIL)
			END
		ELSE
			HyperDocs.Remember(key, NIL, HTTPDocs0.curNode);
			HTTPDocs0.RequestDoc(D, proxy, key, "GET", TRUE, NIL, NIL)
		END;
		IF (D # NIL) & (D.dsc # NIL) THEN
			Attributes.GetString(D, "Type", type);
			IF type = "HTML" THEN
				IF HyperDocs.context = NIL THEN
					HyperDocs.LinkNodeToDoc(D, HTTPDocs0.curNode)
				ELSE
					HyperDocs.context.history := TRUE
				END
			ELSIF HyperDocs.context # NIL THEN
				HyperDocs.context.history := FALSE;
				HyperDocs.context.replace := FALSE
			END
		END
	END OpenHTTPDoc;

	PROCEDURE LoadDoc*(D: Documents.Document);
		VAR key: LONGINT;
	BEGIN
		key := HyperDocs.BuildKey(NIL, D.name);
		IF key # HyperDocs.UndefKey THEN
			OpenHTTPDoc(D, key, HTTPDocs0.httpProxy)
		END
	END LoadDoc;

	PROCEDURE NewDoc*;
		VAR D: Documents.Document;
	BEGIN
		NEW(D);
		D.W := HyperDocs.docW; D.H := HyperDocs.docH;
		D.Load := LoadDoc;
		Objects.NewObj := D
	END NewDoc;

	PROCEDURE InitTables();
		VAR i, max: INTEGER;
	BEGIN
		max := ORD("Z")-ORD("A");
		FOR i := 0 TO max DO
			encTable[i] := CHR(i+ORD("A"))
		END;
		INC(max);
		FOR i := max TO max+ORD("z")-ORD("a") DO
			encTable[i] := CHR(i-max+ORD("a"))
		END;
		max := max+ORD("z")-ORD("a")+1;
		FOR i := max TO max+ORD("9")-ORD("0") DO
			encTable[i] := CHR(i-max+ORD("0"))
		END;
		encTable[62] := "+";
		encTable[63] := "/"
	END InitTables;

PROCEDURE ReplaceDoc*;
BEGIN
	HyperDocs.FollowLink()
END ReplaceDoc;

BEGIN
	client := "Oberon HTTPDocs (ejz) on ";
	Strings.Append(client, Kernel.version);
	InitTables(); Texts.OpenWriter(W);
	NEW(HTTPDocs0.httpProxy); HTTPDocs0.requestDoc := requestDoc;
	NetTools.GetHostPort("HTTPProxy", HTTPDocs0.httpProxy.host, HTTPDocs0.httpProxy.port, HTTPDocs0.DefPort);
	IF HTTPDocs0.httpProxy.host = "" THEN
		HTTPDocs0.httpProxy := NIL
	END;
	noWorkers :=  0; authorizations := NIL; cookies := NIL
END HTTPDocs.
