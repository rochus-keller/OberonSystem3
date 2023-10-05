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

MODULE Gopher;	(** portable *) (* ejz,   *)
	IMPORT Files, Objects, Display, Fonts, Texts, Oberon, NetSystem, Strings, HyperDocs, NetTools, Display3, Gadgets, Links,
		TextGadgets, Documents, Desktops, TextDocs, Attributes, MIME;

(** This module implements a gopher client (RFC 1436).
		The following line should be added to the LinkSchemes section of the Registry:
			gopher = Gopher.NewLinkScheme
		And the following line to the Documents section:
			gopher = Gopher.NewDoc
		To access Gopher within a firewall, add the proxy to the NetSystem section of the Registry:
			GopherProxy = host [ ":" port ] . *)

	CONST
		TempFile = "Temp.Gopher";
		TempGifFile = "Temp.Gopher.gif";
		TempHTMLFile = "Temp.Gopher.html";
		GopherDefPort = 70;
		TelnetDefPort = 23;
		MimeType = 0FFX;
		Menu = "HyperDocs.Back[Back] Desktops.StoreDoc[Store]";

	VAR
		W: Texts.Writer;
		proxyHost: ARRAY NetTools.ServerStrLen OF CHAR;
		proxyPort: INTEGER;
		proxy: BOOLEAN;

	PROCEDURE TextDoc(D: Documents.Document; C: NetSystem.Connection);
		VAR
			T: Texts.Text;
	BEGIN
		Texts.Append(Oberon.Log, W.buf);
		NEW(T); Texts.Open(T, "");
		MIME.textCont.len := MAX(LONGINT);
		MIME.ReadText(NetTools.OpenStream(C), W, MIME.textCont, TRUE);
		Texts.Append(T, W.buf);
		TextDocs.InitDoc(D);
		D.W := HyperDocs.docW; D.H := HyperDocs.docH;
		Links.SetLink(D.dsc, "Model", T)
	END TextDoc;

	PROCEDURE CSODoc(D: Documents.Document; C: NetSystem.Connection);
		VAR
			T: Texts.Text;
			line: ARRAY NetTools.MaxLine OF CHAR;
			res, val: LONGINT;
			i: INTEGER;
	BEGIN
		Texts.Append(Oberon.Log, W.buf);
		NEW(T);
		Texts.Open(T, "");
		NetSystem.ReadString(C, line);
		Strings.StrToInt(line, res);
		IF (res >= 100) & (res < 200) THEN
			res := 1;
			NetSystem.ReadString(C, line);
			WHILE line[0] = "-" DO
				i := 1;
				WHILE (line[i] # 0X) & Strings.IsDigit(line[i]) DO
					INC(i)
				END;
				IF line[i] = ":" THEN
					INC(i);
					Strings.StrToIntPos(line, val, i);
					IF val # res THEN
						INC(res);
						Texts.WriteLn(W)
					END;
					IF line[i] = ":" THEN
						INC(i)
					END;
					WHILE (line[i] # 0X) & (line[i] <= " ") DO
						INC(i)
					END
				END;
				WHILE line[i] # 0X DO
					Texts.Write(W, line[i]); INC(i)
				END;
				Texts.WriteLn(W);
				NetSystem.ReadString(C, line)
			END
		ELSE
			Texts.WriteString(W, line)
		END;
		Texts.Append(T, W.buf);
		TextDocs.InitDoc(D);
		D.W := HyperDocs.docW; D.H := HyperDocs.docH;
		Links.SetLink(D.dsc, "Model", T)
	END CSODoc;

	PROCEDURE ReadLine(VAR R: Texts.Reader; VAR line: ARRAY OF CHAR);
		VAR
			i, l: LONGINT;
			ch: CHAR;
	BEGIN
		l := LEN(line)-1;
		i := 0;
		Texts.Read(R, ch);
		WHILE ~R.eot & (ch # Strings.CR) DO
			IF i < l THEN
				line[i] := ch; INC(i)
			END;
			Texts.Read(R, ch)
		END;
		line[i] := 0X
	END ReadLine;

	PROCEDURE RegisterGopherAdr(host, selector, search: ARRAY OF CHAR; type: CHAR; port: INTEGER): LONGINT;
		VAR
			url: ARRAY NetTools.MaxLine OF CHAR;
			portS: ARRAY 8 OF CHAR;
			key: LONGINT;
	BEGIN
		COPY("gopher://", url);
		Strings.Lower(host, host);
		Strings.Append(url, host);
		IF port # GopherDefPort THEN
			Strings.AppendCh(url, ":");
			Strings.IntToStr(port, portS);
			Strings.Append(url, portS)
		END;
		IF type # 0X THEN
			Strings.AppendCh(url, "/");
			Strings.AppendCh(url, type);
			IF selector # "" THEN
				Strings.Append(url, selector)
			END;
			IF search # "" THEN
				Strings.AppendCh(url, "?");
				Strings.Append(url, search)
			END
		END;
		key := HyperDocs.RegisterLink(url);
		RETURN key
	END RegisterGopherAdr;

	PROCEDURE SplitMenuLine(VAR line: ARRAY OF CHAR; desc: BOOLEAN; VAR type: CHAR; VAR selector, host: ARRAY OF CHAR; VAR port: LONGINT; VAR login, plus: BOOLEAN);
		VAR
			str: ARRAY 12 OF CHAR;
			i, j: LONGINT;
	BEGIN
		type := line[0];
		i := 1;
		WHILE (line[i] # 0X) & (line[i] # Strings.Tab) DO
			IF desc THEN
				Texts.Write(W, line[i])
			END;
			INC(i)
		END;
		IF line[i] = Strings.Tab THEN
			INC(i)
		END;
		login := TRUE;
		j := 0;
		WHILE (line[i] # 0X) & (line[i] # Strings.Tab) DO
			selector[j] := line[i];
			IF line[i] <= " " THEN
				login := FALSE
			ELSIF j > 16 THEN
				login := FALSE
			END;
			INC(j); INC(i)
		END;
		selector[j] := 0X;
		IF line[i] = Strings.Tab THEN
			INC(i)
		END;
		j := 0;
		WHILE (line[i] # 0X) & (line[i] # Strings.Tab) DO
			host[j] := line[i];
			INC(j); INC(i)
		END;
		host[j] := 0X;
		IF line[i] = Strings.Tab THEN
			INC(i)
		END;
		j := 0;
		WHILE (line[i] # 0X) & (line[i] # Strings.Tab) DO
			str[j] := line[i];
			INC(j); INC(i)
		END;
		str[j] := 0X;
		IF line[i] = Strings.Tab THEN
			INC(i);
			plus := line[i] = "+"
		ELSE
			plus := FALSE
		END;
		Strings.StrToInt(str, port)
	END SplitMenuLine;

	PROCEDURE WriteMenuLink(T: Texts.Text; type: CHAR; VAR selector, host: ARRAY OF CHAR; port: LONGINT; login, plus: BOOLEAN): LONGINT;
		VAR
			line: ARRAY 128 OF CHAR;
			str: ARRAY 12 OF CHAR;
			link: Objects.Object;
			key, beg: LONGINT;
	BEGIN
		key := HyperDocs.UndefKey; beg := T.len;
		IF type # "-" THEN
			IF (type = "T") OR (type = "8") THEN
				IF port = 0 THEN
					port := TelnetDefPort
				END;
				line := "telnet://";
				IF login THEN
					Strings.Append(line, selector);
					Strings.AppendCh(line, "@")
				END;
				Strings.Append(line, host);
				Strings.AppendCh(line, ":");
				Strings.IntToStr(port, str);
				Strings.Append(line, str);
				key := HyperDocs.RegisterLink(line);
				link := HyperDocs.LinkControl(key);
				Texts.WriteObj(W, link)
			ELSIF port = 0 THEN
				Texts.Append(T, W.buf);
				Texts.ChangeLooks(T, beg, T.len, {1}, NIL, SHORT(Display3.textC), 0)
			ELSE
				key := RegisterGopherAdr(host, selector, "", type, SHORT(port));
				link := HyperDocs.LinkControl(key);
				Texts.WriteObj(W, link)
			END;
			IF plus THEN
				Texts.Write(W, Strings.Tab);
				link := Gadgets.CreateObject("Outlines.New");
				Attributes.SetString(link, "Host", host);
				Attributes.SetInt(link, "Port", port);
				Attributes.SetString(link, "Selector", selector);
				Attributes.SetString(link, "Cmd", "Gopher.Info");
				Texts.WriteObj(W, link)
			END
		END;
		RETURN key
	END WriteMenuLink;

	PROCEDURE HorzRule(): Objects.Object;
		VAR obj: Objects.Object;
	BEGIN
		obj := Gadgets.CreateObject("BasicFigures.NewRect3D");
		Attributes.SetBool(obj, "Filled", TRUE);
		Attributes.SetInt(obj, "Color", Display3.textbackC);
		Gadgets.ModifySize(obj(Display.Frame), Display.Width, 4);
		RETURN obj
	END HorzRule;

	PROCEDURE MenuDoc(D: Documents.Document; C: NetSystem.Connection; mkey: LONGINT);
		VAR
			T, T2: Texts.Text;
			R: Texts.Reader;
			line: ARRAY NetTools.MaxLine OF CHAR;
			host: ARRAY NetTools.ServerStrLen OF CHAR;
			selector: ARRAY NetTools.PathStrLen OF CHAR;
			type: CHAR;
			search, login, plus: BOOLEAN;
			beg, port: LONGINT;
			link: Objects.Object;
			style: TextGadgets.Style;
	BEGIN
		Texts.Append(Oberon.Log, W.buf);
		NEW(T);
		Texts.Open(T, "");
		MIME.textCont.len := MAX(LONGINT);
		MIME.ReadText(NetTools.OpenStream(C), W, MIME.textCont, TRUE);
		Texts.Append(T, W.buf);
		style := TextGadgets.newStyle();
		style.mode := {TextGadgets.left};
		style.noTabs := 1;
		style.tab[0] := W.lib(Fonts.Font).height;
		Texts.WriteObj(W, style);
		search := FALSE;
		NEW(T2);
		Texts.Open(T2, "");
		Texts.OpenReader(R, T, 0);
		ReadLine(R, line);
		WHILE ~R.eot DO
			type := line[0];
			IF (type # "+") & (type # "3") & (type # 0X) THEN
				CASE type OF
					"0", "i", "h": Texts.Write(W, CHR(28))
					|"1": Texts.Write(W, CHR(26))
					|"2", "7": search := TRUE;
							Texts.Write(W, "?")
					|"4" .. "6", "9", "I", "s", "M", "S", ":", ";", "<": Texts.Write(W, CHR(29))
					|"g": Texts.Write(W, "G")
					|"8", "T": Texts.Write(W, "T")
				ELSE
					IF type # "-" THEN
						Texts.Write(W, type)
					END
				END;
				IF  type # "-" THEN
					Texts.Write(W, Strings.Tab);
					Texts.SetColor(W, SHORT(HyperDocs.linkC))
				END;
				Texts.Append(T2, W.buf); beg := T2.len;
				SplitMenuLine(line, TRUE, type, selector, host, port, login, plus);
				IF HyperDocs.Visited(WriteMenuLink(T2, type, selector, host, port, login, plus)) THEN
					Texts.Append(T2, W.buf);
					Texts.ChangeLooks(T2, beg, T2.len, {1}, NIL, SHORT(HyperDocs.oldLinkC), 0)
				END;
				Texts.SetColor(W, SHORT(Display3.textC));
				Texts.WriteLn(W)
			END;
			ReadLine(R, line)
		END;
		Texts.Append(T2, W.buf);
		HyperDocs.RetrieveLink(mkey, line);
		Texts.Write(W, 22X);
		Texts.WriteString(W, line);
		Texts.Write(W, 22X);
		IF search THEN
			Texts.Write(W, Strings.Tab);
			Texts.WriteString(W, "Enter Search-String here: ");
			link := Gadgets.CreateObject("TextFields.NewTextField");
			Gadgets.NameObj(link, "Search");
			Texts.WriteObj(W, link)
		END;
		Texts.WriteLn(W);
		Texts.WriteObj(W, HorzRule()); Texts.WriteLn(W);
		Texts.Insert(T2, 0, W.buf);
		TextDocs.InitDoc(D);
		D.W := HyperDocs.docW; D.H := HyperDocs.docH;
		Links.SetLink(D.dsc, "Model", T2)
	END MenuDoc;

	PROCEDURE BinDoc(D: Documents.Document; C: NetSystem.Connection; typ: CHAR);
		VAR
			F: Files.File;
			R: Files.Rider;
			fname: ARRAY 32 OF CHAR;
			D2: Documents.Document;
	BEGIN
		IF (typ = "g") OR (typ = "I") THEN
			COPY(TempGifFile, fname)
		ELSIF typ = "h" THEN
			COPY(TempHTMLFile, fname)
		ELSE
			COPY(TempFile, fname)
		END;
		F := Files.New(fname);
		Files.Set(R, F, 0);
		NetTools.curLen := 0;
		NetTools.ReadData(C, R, MAX(LONGINT));
		Files.Register(F);
		IF (typ = "g") OR (typ = "h") OR (typ = "I") THEN
			D2 := Documents.Open(fname);
			IF (D2 # NIL) & (D2.dsc # NIL) THEN
				D^ := D2^;
				RETURN
			END
		END;
		Texts.WriteString(W, "Binary data stored as ");
		Texts.WriteString(W, fname);
		Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf)
	END BinDoc;

	PROCEDURE GopherPlusAns(C: NetSystem.Connection; VAR maxLen: LONGINT; VAR mail: BOOLEAN): BOOLEAN;
		VAR
			len: LONGINT;
			ch: CHAR;
			error: BOOLEAN;
			status: ARRAY 16 OF CHAR;
			i: INTEGER;
	BEGIN
		error := TRUE;
		i := -1;
		maxLen := MAX(LONGINT);
		mail := FALSE;
		ch := 0X;
		len := NetSystem.Available(C);
		WHILE (ch # Strings.LF) & ((len > 0) OR NetTools.Connected(C, NetSystem.in)) DO
			IF NetTools.UserBreak() THEN
				RETURN TRUE
			END;
			WHILE (ch # Strings.LF) & (len > 0) DO
				NetSystem.Read(C, ch);
				DEC(len);
				IF i < 0 THEN
					error := ch # "+";
					i := 0
				ELSIF (ch # Strings.LF) & (i < 15) THEN
					status[i] := ch;
					INC(i)
				END
			END;
			len := NetSystem.Available(C)
		END;
		IF i > 0 THEN
			status[i] := 0X;
			Strings.StrToInt(status, len);
			IF len = -1 THEN
				mail := TRUE
			ELSIF len >= 0 THEN
				maxLen :=len
			END
		END;
		RETURN error
	END GopherPlusAns;

	PROCEDURE MimeDoc(D: Documents.Document; C: NetSystem.Connection; VAR selector: ARRAY OF CHAR);
		VAR
			D2: Documents.Document;
			maxLen, i, j: LONGINT;
			mime, temp: ARRAY 32 OF CHAR;
			err, mail: BOOLEAN;
			T: Texts.Text;
			F: Files.File;
			R: Files.Rider;
			cont: MIME.Content;
	BEGIN
		err := GopherPlusAns(C, maxLen, mail);
		mime := "text/plain";
		IF ~err THEN
			i := 0;
			WHILE (selector[i] # 0X) & (selector[i] # Strings.Tab) DO
				INC(i)
			END;
			IF (selector[i] = Strings.Tab) & (selector[i+1] = "+") THEN
				i := i+2; j := 0;
				WHILE selector[i] > " " DO
					mime[j] := selector[i]; INC(j); INC(i)
				END;
				mime[j] := 0X
			END
		END;
		NEW(cont); cont.typ := MIME.GetContentType(mime); cont.encoding := MIME.EncBin;
		IF (cont.typ.typ # "text") OR (cont.typ.subTyp = "html") THEN
			MIME.MakeTempName(cont.typ, temp);
			F := Files.New(temp);
			IF (cont.typ.typ = "text") THEN
				cont.len := maxLen;
				MIME.ReadText(NetTools.OpenStream(C), W, cont, mail);
				NEW(T); Texts.Open(T, "");
				Texts.Append(T, W.buf);
				Texts.Store(T, F, 0, maxLen)
			ELSE
				Files.Set(R, F, 0);
				NetTools.ReadData(C, R, maxLen)
			END;
			Files.Register(F);
			D.name := ""; D.dsc := NIL;
			D2 := Documents.Open(temp);
			IF (D2 # NIL) & (D2.dsc # NIL) THEN
				D^ := D2^; D.lib := NIL; D.ref := -1
			END
		ELSE
			cont.encoding := MIME.Enc8Bit; cont.len := maxLen;
			MIME.ReadText(NetTools.OpenStream(C), W, cont, mail);
			NEW(T); Texts.Open(T, "");
			Texts.Append(T, W.buf);
			TextDocs.InitDoc(D);
			D.W := HyperDocs.docW; D.H := HyperDocs.docH;
			Links.SetLink(D.dsc, "Model", T)
		END
	END MimeDoc;

	PROCEDURE Connect(VAR C: NetSystem.Connection; host, selector: ARRAY OF CHAR; port: INTEGER; plus: CHAR; crlf: BOOLEAN): BOOLEAN;
	BEGIN
		IF NetTools.Connect(C, port, host, FALSE) THEN
			NetTools.SendString(C, selector);
			IF plus # 0X THEN
				NetSystem.Write(C, Strings.Tab);
				NetSystem.Write(C, plus)
			END;
			IF crlf THEN
				NetTools.SendString(C, Strings.CRLF)
			END;
			RETURN TRUE
		ELSE
			Texts.WriteString(W, host);
			Texts.WriteString(W, " connecting failed");
			RETURN FALSE
		END
	END Connect;

	PROCEDURE *DocHandler(D: Objects.Object; VAR M: Objects.ObjMsg);
	BEGIN
		WITH D: Documents.Document DO
			IF M IS Objects.LinkMsg THEN
				WITH M: Objects.LinkMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "DeskMenu" THEN
							M.obj := Gadgets.CopyPublicObject("NetDocs.GopherDeskMenu", TRUE);
							IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
							M.res := 0
						ELSIF M.name = "SystemMenu" THEN
							M.obj := Gadgets.CopyPublicObject("NetDocs.GopherSystemMenu", TRUE);
							IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
							M.res := 0
						ELSIF M.name = "UserMenu" THEN
							M.obj := Gadgets.CopyPublicObject("NetDocs.GopherUserMenu", TRUE);
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

	PROCEDURE Request(D: Documents.Document; key: LONGINT; VAR host, selector, search: ARRAY OF CHAR; VAR type: CHAR; VAR port: INTEGER);
		VAR
			C: NetSystem.Connection;
			obj: Objects.Object;
			new: HyperDocs.Node;
			replace: BOOLEAN;
	BEGIN
		replace := FALSE;
		C := NIL;
		CASE type OF
			"0", "i": IF Connect(C, host, selector, port, 0X, TRUE) THEN
						TextDoc(D, C);
						COPY(selector, D.name)
					END
			|0X, "1": IF Connect(C, host, selector, port, 0X, TRUE) THEN
						MenuDoc(D, C, key);
						HyperDocs.RetrieveLink(key, D.name);
						D.handle := DocHandler;
						replace := D.dsc # NIL
					END
			|"4" .. "6", "9", "g", "I", "s", "M", "h", "S", ":", ";", "<": IF Connect(C, host, selector, port, 0X, TRUE) THEN
						BinDoc(D, C, type);
						COPY(selector, D.name)
					END
			|"2", "7": IF search = "" THEN
						obj := Gadgets.FindObj(Gadgets.context, "Search");
						IF obj # NIL THEN
							Attributes.GetString(obj, "Value", search)
						END
					ELSE
						obj := NIL
					END;
					IF (search = "") & (obj # NIL) THEN
						Texts.WriteString(W, "No Search String")
					ELSIF Connect(C, host, selector, port, 0X, FALSE) THEN
						IF type = "7" THEN
							NetSystem.Write(C, Strings.Tab);
							NetSystem.WriteString(C, search);
							MenuDoc(D, C, key);
							HyperDocs.RetrieveLink(key, D.name);
							D.handle := DocHandler;
							replace := D.dsc # NIL
						ELSIF type = "2" THEN
							NetTools.SendString(C, "query ");
							NetSystem.WriteString(C, search);
							NetTools.SendString(C, Strings.CRLF);
							CSODoc(D, C);
							COPY(search, D.name)
						END
					END
			|MimeType: IF Connect(C, host, selector, port, 0X, TRUE) THEN
						MimeDoc(D, C, selector);
						COPY(selector, D.name)
					END
		ELSE
			Texts.WriteString(W, " Gopher ");
			Texts.Write(W, type);
			Texts.WriteString(W, " not yet supported")
		END;
		IF C # NIL THEN
			NetTools.Disconnect(C)
		ELSE
			Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf)
		END;
		IF HyperDocs.context # NIL THEN
			HyperDocs.context.replace := HyperDocs.context.replace & replace;
			HyperDocs.context.history := replace
		ELSIF (D.dsc # NIL) & replace THEN
			HyperDocs.Remember(key, NIL, new);
			HyperDocs.LinkNodeToDoc(D, new)
		END;
		IF replace & (D.dsc # NIL) THEN
			IF search = "" THEN
				HyperDocs.CacheDoc(key, D)
			END
		END
	END Request;

	PROCEDURE SplitGopherAdr(VAR url, host, selector, search: ARRAY OF CHAR; VAR type: CHAR; VAR port: INTEGER): LONGINT;
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
		(* Pre: url must be a gopher url *)
		HyperDocs.UnESC(url);
		port := GopherDefPort;
		i := 0;
		Blanks();
		(* skip gopher *)
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
		(* get host *)
		iskey := TRUE;
		l := LEN(host)-1;
		j := 0;
		WHILE (url[i] # "/") & (url[i] # ":") & (url[i] # 0X) DO
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
				HyperDocs.RetrieveLink(key, url);
				key := SplitGopherAdr(url, host, selector, search, type, port);
				RETURN key
			ELSE
				RETURN HyperDocs.UndefKey
			END
		END;
		(* get port *)
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
				port := GopherDefPort
			END
		END;
		IF url[i] = "/" THEN
			(* get type *)
			INC(i);
			Blanks();
			type := url[i];
			INC(i);
			Blanks();
			(* get selector *)
			l := LEN(selector)-1;
			j := 0;
			WHILE (url[i] # 0X) & ((url[i] # "?") OR (url[i] # Strings.Tab)) DO
				IF j < l THEN
					selector[j] := url[i]; INC(j)
				END;
				INC(i)
			END;
			selector[j] := 0X;
			DEC(j);
			WHILE (j >= 0) & (selector[j] <= " ") DO
				selector[j] := 0X; DEC(j)
			END;
			IF (url[i] = "?") OR (url[i] = Strings.Tab) THEN
				(* get search *)
				INC(i);
				l := LEN(search)-1;
				j := 0;
				WHILE url[i] # 0X DO
					IF j < l THEN
						search[j] := url[i]; INC(j)
					END;
					INC(i)
				END;
				search[j] := 0X
			ELSE
				COPY("", search)
			END
		ELSE
			type := 0X;
			COPY("", selector);
			COPY("", search)
		END;
		key := RegisterGopherAdr(host, selector, search, type, port);
		RETURN key
	END SplitGopherAdr;

	PROCEDURE ParseAttrs(T, OutT: Texts.Text);
		VAR
			R: Texts.Reader;
			line: ARRAY NetTools.MaxLine OF CHAR;
			attr, mime: ARRAY 32 OF CHAR;
			i: INTEGER;
			ch, old: CHAR;
			host: ARRAY NetTools.ServerStrLen OF CHAR;
			selector: ARRAY NetTools.PathStrLen OF CHAR;
			type: CHAR;
			login, plus: BOOLEAN;
			port, key, beg: LONGINT;
			link: Objects.Object;
			cont: MIME.Content;
	BEGIN
		Texts.OpenReader(R, T, 0);
		Texts.Read(R, ch);
		WHILE ~R.eot DO
			IF ch = "+" THEN
				i := 0;
				Texts.Read(R, ch);
				WHILE ~R.eot & Strings.IsAlpha(ch) & (i < 31) DO
					attr[i] := CAP(ch); INC(i);
					Texts.Read(R, ch)
				END;
				attr[i] := 0X;
				IF attr = "INFO" THEN
					IF ch = ":" THEN
						Texts.Read(R, ch)
					END;
					WHILE ~R.eot & (ch <= " ") & (ch # Strings.CR) DO
						Texts.Read(R, ch)
					END;
					i := 0;
					WHILE ~R.eot & (ch # Strings.CR) DO
						line[i] := ch; INC(i);
						Texts.Read(R, ch)
					END;
					line[i] := 0X;
					SplitMenuLine(line, FALSE, type, selector, host, port, login, plus);
					old := ch;
					WHILE ~R.eot & ~((ch = "+") & (old = Strings.CR)) DO
						old := ch;
						Texts.Read(R, ch)
					END
				ELSIF attr = "VIEWS" THEN
					Texts.Write(W, Strings.Tab);
					Texts.WriteString(W, "Views:");
					Texts.WriteLn(W);
					old := ch;
					WHILE ~R.eot & (old # Strings.CR) DO
						Texts.Read(R, old)
					END;
					Texts.Read(R, ch);
					WHILE ~R.eot & ~((ch = "+") & (old = Strings.CR)) DO
						Texts.Write(W, Strings.Tab); Texts.Write(W, Strings.Tab);
						old := ch;
						WHILE ~R.eot & (ch <= " ") & (ch # Strings.CR) DO
							old := ch; Texts.Read(R, ch)
						END;
						i := 0;
						WHILE ~R.eot & (ch > " ") DO
							IF (ch >= "A") & (ch <= "Z") THEN
								mime[i] := CHR(ORD(ch)-ORD("A")+ORD("a"))
							ELSE
								mime[i] := ch
							END;
							INC(i);
							old := ch; Texts.Read(R, ch)
						END;
						mime[i] := 0X;
						IF i > 0 THEN
							NEW(cont); cont.typ := MIME.GetContentType(mime); cont.encoding := MIME.EncBin;
							Texts.SetColor(W, SHORT(HyperDocs.linkC));
							Texts.Append(OutT, W.buf); beg := OutT.len; Texts.WriteString(W, mime);
							IF (cont.typ.typ = "application") & (cont.typ.subTyp = "gopher") THEN
								key := WriteMenuLink(OutT, type, selector, host, port, login, FALSE)
							ELSE
								COPY(selector, line);
								Strings.AppendCh(line, Strings.Tab);
								Strings.AppendCh(line, "+");
								Strings.Append(line, mime);
								Strings.AppendCh(line, Strings.Tab);
								i := 0;
								WHILE line[i] # 0X DO
									INC(i)
								END;
								WHILE ~R.eot & (ch # Strings.CR) & (ch # ":") DO
									Texts.Write(W, ch);
									line[i] := ch; INC(i);
									old := ch; Texts.Read(R, ch)
								END;
								line[i] := 0X;
								key := RegisterGopherAdr(host, line, "", MimeType, SHORT(port));
								link := HyperDocs.LinkControl(key);
								Texts.WriteObj(W, link)
							END;
							IF HyperDocs.Visited(key) THEN
								Texts.Append(OutT, W.buf);
								Texts.ChangeLooks(OutT, beg, OutT.len, {1}, NIL, SHORT(HyperDocs.oldLinkC), 0)
							END;
							Texts.SetColor(W, SHORT(Display3.textC));
							WHILE ~R.eot & (ch # Strings.CR) DO
								Texts.Write(W, ch);
								old := ch; Texts.Read(R, ch)
							END
						END;
						Texts.WriteLn(W);
						old := ch; Texts.Read(R, ch)
					END
				ELSE
					Texts.Write(W, Strings.Tab);
					Texts.Write(W, attr[0]);
					i := 1;
					WHILE attr[i] # 0X DO
						Texts.Write(W, CHR(ORD(attr[i])-ORD("A")+ORD("a")));
						INC(i)
					END;
					Texts.Write(W, ":");
					Texts.WriteLn(W);
					Texts.Write(W, Strings.Tab);
					Texts.Write(W, Strings.Tab);
					old := ch;
					WHILE ~R.eot & (old # Strings.CR) DO
						Texts.Read(R, old)
					END;
					Texts.Read(R, ch);
					WHILE ~R.eot & ~((ch = "+") & (old = Strings.CR)) DO
						Texts.Write(W, ch);
						IF ch = Strings.CR THEN
							Texts.Write(W, Strings.Tab);
							Texts.Write(W, Strings.Tab)
						END;
						old := ch; Texts.Read(R, ch)
					END
				END;
				IF ch = "+" THEN
					Texts.WriteLn(W)
				END
			ELSE (* ??? *)
				Texts.Read(R, ch)
			END
		END
	END ParseAttrs;

(** Command used by the Gopher+ outlines. *)
	PROCEDURE Info*;
		VAR
			F: Texts.Finder;
			pos, len: LONGINT;
			obj, tobj: Objects.Object;
			host: ARRAY NetTools.ServerStrLen OF CHAR;
			selector: ARRAY NetTools.PathStrLen OF CHAR;
			C: NetSystem.Connection;
			port: INTEGER;
			mail, err: BOOLEAN;
			T, OutT: Texts.Text;
	BEGIN
		Links.GetLink(Gadgets.context, "Model", tobj);
		Texts.OpenFinder(F, tobj(Texts.Text), 0);
		pos := F.pos;
		Texts.FindObj(F, obj);
		WHILE ~F.eot DO
			IF obj = Gadgets.executorObj THEN
				Attributes.GetBool(obj, "Open", err);
				IF ~err & (Attributes.FindAttr("Open", obj(Gadgets.Frame).attr) # NIL) THEN
					Attributes.SetBool(obj, "Open", TRUE)
				END;
				Attributes.GetString(obj, "Host", host);
				Attributes.GetInt(obj, "Port", len); port := SHORT(len);
				Attributes.GetString(obj, "Selector", selector);
				IF (port > 0) & (host # "") & (selector # "") THEN
					IF Connect(C, host, selector, port, "!", TRUE) THEN
						err := GopherPlusAns(C, MIME.textCont.len, mail);
						MIME.ReadText(NetTools.OpenStream(C), W, MIME.textCont, mail);
						NetTools.Disconnect(C);
						IF ~err THEN
							NEW(T); Texts.Open(T, "");
							Texts.Append(T, W.buf);
							NEW(OutT); Texts.Open(OutT, "");
							ParseAttrs(T, OutT);
							Texts.Save(OutT, 0, OutT.len, W.buf);
							Texts.Insert(tobj(Texts.Text), pos+1, W.buf);
							Attributes.SetString(obj, "Cmd", "")
						ELSE
							Texts.OpenWriter(W);
							Attributes.SetBool(obj, "Open", FALSE)
						END
					ELSE
						Attributes.SetBool(obj, "Open", FALSE)
					END
				END;
				RETURN
			END;
			pos := F.pos;
			Texts.FindObj(F, obj)
		END
	END Info;

(** The gopher protocol object. *)
	PROCEDURE *LinkSchemeHandler(L: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			port: INTEGER;
			line: ARRAY NetTools.MaxLine OF CHAR;
			host: ARRAY NetTools.ServerStrLen OF CHAR;
			selector, search: ARRAY NetTools.PathStrLen OF CHAR;
			type: CHAR;
			C: NetSystem.Connection;
	BEGIN
		WITH L: HyperDocs.LinkScheme DO
			IF M IS HyperDocs.RegisterLinkMsg THEN
				WITH M: HyperDocs.RegisterLinkMsg DO
					IF (M.base = NIL) OR (HyperDocs.CheckPrefix(M.link) >= 0) THEN
						M.key := SplitGopherAdr(M.link, host, selector, search, type, port)
					ELSIF M.base.prefix = "gopher" THEN
						line := "gopher:";
						IF (M.link[0] # "/") OR (M.link[1] # "/") THEN
							Strings.Append(line, "//"); Strings.Append(line, M.base.host);
							IF M.base.port > 0 THEN
								Strings.AppendCh(line, ":"); Strings.IntToStr(M.base.port, host); Strings.Append(line, host)
							END
						END;
						Strings.Append(line, M.link); M.key := HyperDocs.RegisterLink(line)
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
						M.key := SplitGopherAdr(line, host, selector, search, type, port);
						IF (type # "8") & (type # "T") & (type # "2") & (type # "7") THEN
							IF Connect(C, host, selector, port, 0X, TRUE) THEN
								M.res := 0;
								NetTools.curLen := 0;
								NetTools.ReadData(C, M.R, MAX(LONGINT));
								NetTools.Disconnect(C);
								Texts.WriteString(W, " done");
								Texts.WriteLn(W)
							END;
							Texts.Append(Oberon.Log, W.buf)
						END
					ELSE
						M.res := 0
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.class := Objects.String;
						M.s := "Gopher.NewLinkScheme";
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

	PROCEDURE *LoadDoc(D: Documents.Document);
		VAR
			host: ARRAY NetTools.ServerStrLen OF CHAR;
			selector, search: ARRAY NetTools.PathStrLen OF CHAR;
			key: LONGINT;
			P: NetTools.ProxyMsg;
			S: HyperDocs.LinkScheme;
			D2: Documents.Document;
			port: INTEGER;
			type: CHAR;
	BEGIN
		D.dsc := NIL;
		key := SplitGopherAdr(D.name, host, selector, search, type, port);
		IF (host # "") & (key # HyperDocs.UndefKey) THEN
			IF proxy & NetTools.UseProxy(host) THEN
				P.key := key; P.res := -1; P.D := D;
				COPY(proxyHost, P.host); P.port := proxyPort;
				S := HyperDocs.LinkSchemeByPrefix("http");
				S.handle(S, P)
			ELSE
				D2 := HyperDocs.GetCachedDoc(key);
				IF (D2 # NIL) & (D2.dsc # NIL) THEN
					D^ := D2^; D.handle := DocHandler
				ELSE
					Request(D, key, host, selector, search, type, port)
				END
			END;
			IF (D # NIL) & (D.dsc # NIL) & (D.dsc IS TextGadgets.Frame) THEN
				Attributes.SetInt(D.dsc, "LinkColor", HyperDocs.linkC);
				Attributes.SetInt(D.dsc, "OldLinkColor", HyperDocs.oldLinkC);
				D.dsc(TextGadgets.Frame).do := HyperDocs.linkMethods
			END
		END
	END LoadDoc;

	PROCEDURE NewDoc*;
		VAR D: Documents.Document;
	BEGIN
		NEW(D);
		D.Load := LoadDoc;
		D.Store := NIL;
		D.handle := DocHandler;
		Objects.NewObj := D
	END NewDoc;

BEGIN
	Texts.OpenWriter(W);
	NetTools.GetHostPort("GopherProxy", proxyHost, proxyPort, 80);
	proxy := proxyHost # ""
END Gopher.
