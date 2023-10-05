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

MODULE HTTPDocs0;	(** portable *)
	IMPORT Objects, Modules, Display, Input, Texts, HyperDocs, Strings, Oberon, Attributes, Links, Documents, Rembrandt,
		TextGadgets, Gadgets, Desktops;

	CONST
		DefPort* = 80;
		MaxWorkers = 4;

	TYPE
		ObjList* = POINTER TO ObjListDesc;
		ObjListDesc* = RECORD
			obj*: Objects.Object;
			next*: ObjList
		END;
		Context* = POINTER TO ContextDesc;
		ContextDesc* = RECORD (HyperDocs.ContextDesc)
			query*: Texts.Text;
			method*: ARRAY 8 OF CHAR;
			user*, passwd*: ARRAY 64 OF CHAR
		END;
		Entry* = POINTER TO EntryDesc;
		Worker* = POINTER TO WorkerDesc;
		EntryDesc* = RECORD
			basekey*, key*, pos*: LONGINT;
			attrs*: Attributes.Attr;
			text*: Texts.Text;
			ol*: ObjList;
			obj*: Objects.Object;
			next*, same*: Entry;
			doc*: Documents.Document;
			working*: Worker
		END;
		WorkerDesc* = RECORD (Oberon.TaskDesc)
			entry*: Entry;
			state*: INTEGER; (* 0: connect, 1: reading response, 2: reading data, 3: open doc, 4: kill, 5: retry later *)
			local*: BOOLEAN
		END;
		Proxy* = POINTER TO ProxyDesc;
		ProxyDesc* = RECORD
			host*: ARRAY 64 OF CHAR;
			port*: INTEGER
		END;

	VAR
		buf: ARRAY 2048 OF CHAR;
		entries*: Entry;
		noWorkers: INTEGER;
		ImgHandle*: Objects.Handler;
		W: Texts.Writer;
		curNode*: HyperDocs.Node;
		httpProxy*: Proxy;
		requestDoc*: PROCEDURE (D: Documents.Document; proxy: Proxy; VAR key: LONGINT; method: ARRAY OF CHAR; main: BOOLEAN; E: Entry; query: Texts.Text);

	PROCEDURE StripLoc*(key: LONGINT): LONGINT;
		VAR i: LONGINT;
	BEGIN
		HyperDocs.RetrieveLink(key, buf);
		i := 0;
		WHILE (buf[i] # 0X) & (buf[i] # "#") DO
			INC(i)
		END;
		buf[i] := 0X;
		RETURN HyperDocs.RegisterLink(buf)
	END StripLoc;

(** Register a new http url. *)
	PROCEDURE RegisterHTTPAdr*(VAR host, path, label: ARRAY OF CHAR; VAR port: INTEGER): LONGINT;
		VAR portS: ARRAY 8 OF CHAR;
	BEGIN
		buf := "http://";
		Strings.Lower(host, host);
		Strings.Append(buf, host);
		IF port # DefPort THEN
			Strings.AppendCh(buf, ":");
			Strings.IntToStr(port, portS);
			Strings.Append(buf, portS)
		END;
		IF path # "" THEN
			Strings.Append(buf, path);
			IF label # "" THEN
				Strings.AppendCh(buf, "#");
				Strings.Append(buf, label)
			END
		ELSE
			Strings.AppendCh(buf, "/")
		END;
		RETURN HyperDocs.RegisterLink(buf)
	END RegisterHTTPAdr;

(** Parsing of an http url. *)
	PROCEDURE SplitHTTPAdr*(VAR url, host, path, label: ARRAY OF CHAR; VAR port: INTEGER): LONGINT;
		VAR
			i, j, l, key: LONGINT;
			iskey: BOOLEAN;
		PROCEDURE Blanks();
		BEGIN
			WHILE (url[i] # 0X) & (url[i] <= " ") DO
				INC(i)
			END
		END Blanks;
	BEGIN
		(* Pre: url must be a http url *)
		HyperDocs.UnESC(url);
		port := DefPort;
		i := 0;
		Blanks();
		(* skip http *)
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
		l := LEN(host)-1; j := 0;
		WHILE (url[i] # "/") & (url[i] # ":") & (url[i] # 0X) DO
			IF url[i] > " " THEN
				IF ~Strings.IsDigit(url[i]) THEN
					iskey := FALSE
				END;
				IF j < l THEN
					host[j] := url[i]; INC(j)
				END
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
				key := SplitHTTPAdr(buf, host, path, label, port);
				RETURN key
			ELSE
				RETURN HyperDocs.UndefKey
			END
		END;
		(* get port *)
		IF url[i] = ":" THEN
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
		(* get path *)
		l := LEN(path)-1; j := 0;
		WHILE (url[i] # 0X) & (url[i] # "#") DO
			IF (url[i] > " ") OR ((j > 0) & (url[i] = " ")) THEN
				IF j < l THEN
					path[j] := url[i]; INC(j)
				END
			END;
			INC(i)
		END;
		path[j] := 0X;
		DEC(j);
		WHILE (j >= 0) & (path[j] <= " ") DO
			path[j] := 0X; DEC(j)
		END;
		(* get label *)
		IF url[i] = "#" THEN
			INC(i);
			l := LEN(label)-1; j := 0;
			WHILE (url[i] # 0X) DO
				IF url[i] > " " THEN
					IF j < l THEN
						label[j] := url[i]; INC(j)
					END
				END;
				INC(i)
			END;
			label[j] := 0X;
			DEC(j);
			WHILE (j >= 0) & (label[j] <= " ") DO
				label[j] := 0X; DEC(j)
			END
		ELSE
			COPY("", label)
		END;
		key := RegisterHTTPAdr(host, path, label, port);
		RETURN key
	END SplitHTTPAdr;

	PROCEDURE StopAll();
		VAR entry, pentry: Entry;
	BEGIN
		pentry := NIL; entry := entries;
		WHILE entry # NIL DO
			IF entry.working # NIL THEN
				entry.working.state := 5;
				pentry:= entry
			ELSIF pentry # NIL THEN
				pentry.next := entry.next
			ELSE
				entries := entry.next
			END;
			entry := entry.next
		END
	END StopAll;

	PROCEDURE StopDoc*(D: Documents.Document);
		VAR
			node: HyperDocs.Node;
			entry, pentry: Entry;
	BEGIN
		node := HyperDocs.NodeByDoc(D);
		IF node # NIL THEN
			pentry := NIL; entry := entries;
			WHILE entry # NIL DO
				IF entry.basekey = node.key THEN
					IF entry.working # NIL THEN
						entry.working.state := 5;
						pentry:= entry
					ELSIF pentry # NIL THEN
						pentry.next := entry.next
					ELSE
						entries := entry.next
					END
				ELSE
					pentry := entry
				END;
				entry := entry.next
			END
		ELSE
			StopAll()
		END
	END StopDoc;

	PROCEDURE Wait*();
		VAR
			best, e: Entry;
			time: LONGINT;
	BEGIN
		time := MAX(LONGINT); best := NIL; e := entries;
		WHILE e # NIL DO
			IF (e.working # NIL) & (e.working.time < time) THEN
				best := e; time := best.working.time
			END;
			e := e.next
		END;
		IF best # NIL THEN
			best.working.handle(best.working)
		END
	END Wait;

	PROCEDURE ^Install(E: Entry);

	PROCEDURE InsertDoc*(me: Worker);
		VAR
			E, entry: Entry;
			attr: Attributes.Attr;
			A: Objects.AttrMsg;
			doc, mainD: Documents.Document;
			L: Objects.LinkMsg;
			M: Display.ModifyMsg;
	BEGIN
		doc := me.entry.doc; me.entry.key := HyperDocs.UndefKey;
		entry := me.entry;
		WHILE entry # NIL DO
			entry.doc := doc;
			IF entry.pos < 0 THEN
				mainD := entry.obj(Documents.Document);
				Links.SetLink(mainD.dsc, "Picture", doc.dsc(Rembrandt.Frame).pict);
				mainD.dsc(TextGadgets.Frame).do := HyperDocs.linkPictMethods;
				Gadgets.Update(entry.obj);
				entry := entry.same
			ELSIF entry.pos < entry.text.len THEN
				IF entry.obj # NIL THEN
					IF (entry.obj IS Rembrandt.Frame) & (doc.dsc IS Rembrandt.Frame) THEN
						Attributes.SetString(entry.obj, "Cmd", "");
						M.F := entry.obj(Rembrandt.Frame);
						M.dW := doc.dsc.W-M.F.W-2; M.dH := doc.dsc.H-M.F.H-2;
						Attributes.GetBool(entry.obj, "Border", A.b);
						IF A.b THEN
							INC(M.dW, 2); INC(M.dH, 2)
						END;
						L.id := Objects.set; L.name := "Model";
						L.obj := doc.dsc(Rembrandt.Frame).pict;
						entry.obj.handle(entry.obj, L);
						IF (M.dW # 0) OR (M.dH # 0) THEN
							Attributes.SetBool(entry.obj, "Locked", FALSE);
							M.id := Display.extend; M.mode := Display.display;
							M.X := 0; M.Y := 0; M.dX := 0; M.dY := 0;
							M.W := M.F.W+M.dW; M.H := M.F.H+M.dH; M.res := -1;
							Display.Broadcast(M);
							IF M.res # 0 THEN (* not in display space *)
								M.mode := Display.state; M.F.handle(M.F, M)
							END;
							Attributes.SetBool(entry.obj, "Locked", TRUE)
						ELSE
							Gadgets.Update(M.F)
						END;
						NEW(entry.doc); entry.doc.dsc := M.F;
						M.F.handle := ImgHandle
					ELSE
						Texts.Delete(entry.text, entry.pos, entry.pos+1);
						Texts.WriteObj(W, entry.doc.dsc);
						Texts.Insert(entry.text, entry.pos, W.buf);
						Gadgets.GetObjName(entry.obj, A.name);
						Gadgets.NameObj(entry.doc.dsc, A.name)
					END
				ELSE
					Desktops.ShowDoc(entry.doc)
				END;
				IF entry.ol # NIL THEN
					entry.ol.obj := entry.doc.dsc
				END;
				attr := entry.attrs;
				WHILE attr # NIL DO
					A.id := Objects.set;
					COPY(attr.name, A.name);
					IF attr IS Attributes.IntAttr THEN
						A.class := Objects.Int;
						A.i := attr(Attributes.IntAttr).i
					ELSIF attr IS Attributes.BoolAttr THEN
						A.class := Objects.Bool;
						A.b := attr(Attributes.BoolAttr).b
					ELSIF attr IS Attributes.StringAttr THEN
						A.class := Objects.String;
						COPY(attr(Attributes.StringAttr).s, A.s)
					END;
					entry.doc.dsc.handle(entry.doc.dsc, A);
					attr := attr.next
				END;
				IF entry.doc.dsc IS Rembrandt.Frame THEN
					entry.doc.dsc.handle := ImgHandle;
					IF Attributes.FindAttr("UseMap", entry.doc.dsc(Gadgets.Frame).attr) # NIL THEN
						Gadgets.Update(entry.doc.dsc)
					END
				END;
				entry := entry.same
			ELSE
				E := entry; entry := entry.same;
				Install(E); E.doc := doc
			END
		END;
		Oberon.Collect()
	END InsertDoc;

	PROCEDURE ^StartWorker();

	PROCEDURE *DoWork(me: Oberon.Task);
		PROCEDURE Remove(me: Worker);
			VAR e: Entry;
		BEGIN
			Oberon.Remove(me.entry.working);
			IF noWorkers > 0 THEN
				DEC(noWorkers)
			END;
			IF me # me.entry.working THEN
				Oberon.Remove(me)
			END;
			me.entry.working := NIL;
			e := entries;
			WHILE (e # NIL) & (e.next # me.entry) DO
				e := e.next
			END;
			IF e # NIL THEN
				e.next := me.entry.next
			ELSE
				entries := me.entry.next
			END;
			Oberon.Collect(); StartWorker()
		END Remove;
	BEGIN
		WITH me: Worker DO
			IF ~me.local THEN Remove(me) END;
			IF me.entry.doc = NIL THEN
				me.entry.doc := HyperDocs.GetCachedDoc(me.entry.key)
			END;
			IF me.entry.doc # NIL THEN
				IF me.entry.text.len > me.entry.pos THEN
					InsertDoc(me);
					Remove(me)
				END
			END
		END
	END DoWork;

	PROCEDURE StartWorker();
		VAR
			W: Worker;
			E: Entry;
	BEGIN
		E := entries;
		WHILE (E # NIL) & (E.working # NIL) DO
			E := E.next
		END;
		IF E # NIL THEN
			INC(noWorkers);
			NEW(W); E.working := W; W.local := TRUE;
			W.state := 0;
			W.entry := E;
			W.safe := FALSE;
			W.time := Input.Time()+1;
			W.handle := DoWork;
			Oberon.Install(W)
		END
	END StartWorker;

	PROCEDURE Install(E: Entry);
		VAR pe, e: Entry;
	BEGIN
		E.working := NIL; E.same := NIL; E.doc := NIL;
		e := entries;
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
			pe := NIL; e := entries;
			WHILE (e # NIL) & (e.basekey = E.basekey) DO
				pe := e; e := e.next
			END;
			IF pe # NIL THEN
				E.next := pe.next; pe.next := E
			ELSE
				E.next := entries; entries := E
			END;
			IF noWorkers < MaxWorkers THEN
				StartWorker()
			END
		END
	END Install;

(** Requests the document ientified by key. *)
	PROCEDURE RequestDoc*(D: Documents.Document; proxy: Proxy; VAR key: LONGINT; method: ARRAY OF CHAR; 
		main: BOOLEAN; E: Entry; query: Texts.Text);
		VAR
			s: HyperDocs.LinkScheme;
			D2: Documents.Document;
	BEGIN
		s := HyperDocs.LinkSchemeByKey(key);
		IF s = NIL THEN
			RETURN
		ELSIF s.prefix = "file" THEN
			HyperDocs.DocNameByKey(D.name, key);
			D2 := Documents.Open(D.name);
			IF (D2 # NIL) & (D2.dsc # NIL) THEN
				D^ := D2^; D.lib := NIL; D.ref := -1;
				IF D.name = "" THEN
					HyperDocs.RetrieveLink(key, D.name)
				END;
				IF E # NIL THEN
					E.key := key;
					Install(E);
					E.doc := D2
				END
			END;
			RETURN
		END;
		IF requestDoc # NIL THEN
			requestDoc(D, proxy, key, method, main, E, query)
		END
	END RequestDoc;

BEGIN
	entries := NIL; Modules.InstallTermHandler(StopAll);
	ImgHandle := Rembrandt.Handle; httpProxy := NIL;
	requestDoc := NIL; Texts.OpenWriter(W)
END HTTPDocs0.
