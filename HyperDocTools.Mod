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

MODULE HyperDocTools;	(** portable *) (* ejz,   *)
	IMPORT Files, Objects, Fonts, Texts, Oberon, Display3, Attributes, Strings, Gadgets, TextGadgets, Documents,
		HyperDocs, TextDocs, Desktops;

(** Module HyperDocTools provides some tools to manipulate links.
	See also HyperDocs.Tool & HyperLinks.Panel . *)

	VAR
		W: Texts.Writer;
		link: ARRAY HyperDocs.MaxLink OF CHAR;

	PROCEDURE CurDoc(): Documents.Document;
		VAR
			S: Attributes.Scanner;
			curDoc: Documents.Document;
	BEGIN
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Attributes.Scan(S);
		IF (S.class = Attributes.Char) & (S.c = "*") THEN
			curDoc := Documents.MarkedDoc()
		ELSE
			curDoc := Desktops.CurDoc(Gadgets.context)
		END;
		RETURN curDoc
	END CurDoc;

(** HyperDocTools.History *
		Display the history for the marked document. *)
	PROCEDURE History*;
		VAR
			curDoc: Documents.Document;
			node: HyperDocs.Node;
			title: ARRAY 64 OF CHAR;
			key: LONGINT;
			T: Texts.Text;
	BEGIN
		curDoc := CurDoc();
		node := HyperDocs.NodeByDoc(curDoc);
		key := HyperDocs.UndefKey;
		WHILE node # NIL DO
			IF node.key # key THEN
				HyperDocs.RetrieveLink(node.key, link);
				Texts.Write(W, 22X);
				Texts.WriteString(W, link);
				Texts.Write(W, 22X);
				Texts.WriteLn(W);
				key := node.key
			END;
			node := node.old
		END;
		IF key # HyperDocs.UndefKey THEN
			NEW(T); Texts.Open(T, "");
			Texts.Append(T, W.buf);
			COPY(curDoc.name, title);
			Strings.ChangeSuffix(title, "History");
			TextDocs.ShowText(title, T, HyperDocs.docW, HyperDocs.docH)
		END
	END History;

	PROCEDURE ReadControls*(VAR label, link: Objects.Object);
		VAR
			T: Texts.Text;
			beg, end, time, pos: LONGINT;
			R: Texts.Reader;
			obj: Objects.Object;
			col: INTEGER;
			ch: CHAR;
	BEGIN
		label := NIL; link := NIL;
		T := NIL; time := -1;
		Oberon.GetSelection(T, beg, end, time);
		IF (T # NIL) & (time > 0) THEN
			pos := (beg+end) DIV 2;
			obj := NIL;
			Texts.OpenReader(R, T, pos);
			Texts.Read(R, ch);
			WHILE ~R.eot & (obj = NIL) DO
				IF ~(R.lib IS Fonts.Font) THEN
					R.lib.GetObj(R.lib, ORD(ch), obj)
				ELSE
					col := R.col
				END;
				INC(pos); Texts.Read(R, ch)
			END;
			IF (obj # NIL) & (obj IS TextGadgets.Control) & (Attributes.FindAttr("Key", obj(Gadgets.Frame).attr) # NIL) THEN
				link := obj; obj := NIL;
				DEC(pos, 2);
				Texts.OpenReader(R, T, pos);
				Texts.Read(R, ch);
				WHILE (pos > 0) & (obj = NIL) & (R.col = col) DO
					IF ~(R.lib IS Fonts.Font) THEN
						R.lib.GetObj(R.lib, ORD(ch), obj)
					END;
					DEC(pos);
					Texts.OpenReader(R, T, pos);
					Texts.Read(R, ch)
				END;
				IF (pos > 0) & (obj = NIL) & ~(R.lib IS Fonts.Font) THEN
					R.lib.GetObj(R.lib, ORD(ch), obj)
				END;
				IF (obj # NIL) & (obj IS TextGadgets.Control) THEN
					label := obj
				END;
				pos := (beg+end) DIV 2;
				obj := NIL;
				Texts.OpenReader(R, T, pos);
				Texts.Read(R, ch);
				WHILE ~R.eot & (obj = NIL) & (R.col = col) DO
					IF ~(R.lib IS Fonts.Font) THEN
						R.lib.GetObj(R.lib, ORD(ch), obj)
					END;
					Texts.Read(R, ch)
				END;
				IF ~R.eot & (obj = NIL) & ~(R.lib IS Fonts.Font) THEN
					R.lib.GetObj(R.lib, ORD(ch), obj)
				END;
				IF obj # link THEN
					link := NIL
				END
			END
		END
	END ReadControls;

(** HyperDocTools.Fetch ( locdoc | { link "=>" locdoc } ) "~"
		Download the document behind the selected link or the given link to locdoc. *)
	PROCEDURE Fetch*;
		VAR
			S: Attributes.Scanner;
			FM: HyperDocs.FetchMsg;
			L, pL: HyperDocs.LinkScheme;
			lnk, label: Objects.Object;
		PROCEDURE FetchF();
			VAR F: Files.File;
		BEGIN
			FM.res := -1;
			IF FM.key # HyperDocs.UndefKey THEN
				Texts.WriteString(W, link); Texts.WriteString(W, " => "); Texts.WriteString(W, S.s);
				Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf);
				L := HyperDocs.LinkSchemeByKey(FM.key);
				F := Files.New(S.s);
				Files.Set(FM.R, F, 0);
				L.handle(L, FM);
				IF FM.res = 0 THEN
					Files.Register(F)
				ELSE
					Texts.WriteString(W, " failed");
					Texts.WriteLn(W);
					Texts.Append(Oberon.Log, W.buf)
				END;
				IF (L # pL) & (pL # NIL) THEN
					FM.key := HyperDocs.UndefKey; FM.res := -1;
					pL.handle(pL, FM)
				END;
				pL := L
			END
		END FetchF;
	BEGIN
		pL := NIL;
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Attributes.Scan(S);
		IF S.class IN {Attributes.Name, Attributes.String} THEN
			COPY(S.s, link);
			Attributes.Scan(S);
			IF (S.class = Attributes.Char) & (S.c = "=") THEN
				LOOP
					IF (S.class = Attributes.Char) & (S.c = "=") THEN
						Attributes.Scan(S);
						IF (S.class # Attributes.Char) OR (S.c # ">") THEN
							EXIT
						ELSE
							Attributes.Scan(S)
						END
					ELSIF S.class IN {Attributes.Name, Attributes.String} THEN
						FM.key := HyperDocs.BuildKey(NIL, link);
						FetchF();
						Attributes.Scan(S);
						IF S.class IN {Attributes.Name, Attributes.String} THEN
							COPY(S.s, link);
							Attributes.Scan(S)
						ELSE
							EXIT
						END
					ELSE
						EXIT
					END
				END
			ELSE
				ReadControls(label, lnk);
				IF lnk # NIL THEN
					Attributes.GetInt(lnk, "Key", FM.key);
					HyperDocs.RetrieveLink(FM.key, link);
					FetchF()
				END
			END;
			IF L # NIL THEN
				FM.key := HyperDocs.UndefKey; FM.res := -1;
				L.handle(L, FM)
			END
		END
	END Fetch; 

(** HyperDocTools.LinkInfo (selection)
		Queries information about the document behind the selected link.
		Output is written to Oberon.Log or to the HyperLinks.Panel if called from it. *)
	PROCEDURE LinkInfo*;
		VAR
			link, obj: Objects.Object;
			key: LONGINT;
			s: HyperDocs.LinkScheme;
			I: HyperDocs.InfoMsg;
			val: ARRAY 64 OF CHAR;
	BEGIN
		ReadControls(obj, link);
		IF link # NIL THEN
			Attributes.GetInt(link, "Key", key);
			s := HyperDocs.LinkSchemeByKey(key);
			IF s = NIL THEN
				RETURN
			END;
			I.key := key; I.res := -1;
			s.handle(s, I);
			obj := Gadgets.FindObj(Gadgets.context, "Doc-Type");
			IF obj # NIL THEN
				COPY(I.contType.typ, val); Strings.AppendCh(val, "/");
				Strings.Append(val, I.contType.subTyp);
				Attributes.SetString(obj, "Value", val);
				Gadgets.Update(obj)
			ELSE
				Texts.WriteString(W, "Doc-Type: ");
				Texts.WriteString(W, I.contType.typ);
				Texts.Write(W, "/");
				Texts.WriteString(W, I.contType.subTyp);
				Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
			END;
			obj := Gadgets.FindObj(Gadgets.context, "Doc-Size");
			IF obj # NIL THEN
				Attributes.SetInt(obj, "Value", I.size);
				Gadgets.Update(obj)
			ELSE
				Texts.WriteString(W, "Doc-Size: ");
				Texts.WriteInt(W, I.size, 0);
				Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
			END
		END
	END LinkInfo;

(** HyperDocTools.Inspect (selection)
		Display the link behind the selected link. :-)
		Output is written to Oberon.Log or to the HyperLinks.Panel if called from it. *)
	PROCEDURE Inspect*;
		VAR
			label, lnk, obj: Objects.Object;
			key: LONGINT;
			s: HyperDocs.LinkScheme;
			opt: ARRAY 8 OF CHAR;
	BEGIN
		ReadControls(label, lnk);
		IF lnk # NIL THEN
			IF label = NIL THEN
				label := lnk
			END;
			Attributes.GetInt(lnk, "Key", key);
			s := HyperDocs.LinkSchemeByKey(key);
			IF s = NIL THEN
				RETURN
			END;
			HyperDocs.RetrieveLink(key, link);
			obj := Gadgets.FindObj(Gadgets.context, "URL");
			IF obj # NIL THEN
				Attributes.SetString(obj, "Value", link);
				Gadgets.Update(obj)
			ELSE
				Texts.WriteString(W, "Link: ");
				Texts.WriteString(W, link);
				Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf)
			END;
			Gadgets.GetObjName(label, link);
			obj := Gadgets.FindObj(Gadgets.context, "Label");
			IF obj # NIL THEN
				Attributes.SetString(obj, "Value", link);
				Gadgets.Update(obj)
			ELSIF link # "" THEN
				Texts.WriteString(W, "Label: ");
				Texts.WriteString(W, link);
				Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf)
			END;
			Attributes.GetString(lnk, "Opt", opt);
			IF opt = "" THEN
				opt[0] := "A"
			ELSE
				opt[0] := CAP(opt[0])
			END;
			opt[1] := 0X;
			obj := Gadgets.FindObj(Gadgets.context, opt);
			IF obj # NIL THEN
				Attributes.SetBool(obj, "Value", TRUE);
				Gadgets.Update(obj)
			END
		END
	END Inspect;

(** HyperDocTools.Apply
		used by HyperLinks.Panel *)
	PROCEDURE Apply*;
		VAR
			S: Attributes.Scanner;
			label, link: Objects.Object;
			key, beg, end, time: LONGINT;
			T: Texts.Text;
	BEGIN
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Attributes.Scan(S);
		IF (S.class IN {Texts.Name, Texts.String}) & (S.s # "") THEN
			ReadControls(label, link);
			IF link # NIL THEN
				IF label = NIL THEN
					label := link
				END;
				key := HyperDocs.BuildKey(NIL, S.s);
				Attributes.SetInt(link, "Key", key);
				Attributes.Scan(S);
				IF (S.class IN {Texts.Name, Texts.String}) & (S.s # "") THEN
					Gadgets.NameObj(label, S.s)
				END;
				Attributes.Scan(S);
				IF S.class = Texts.Name THEN
					S.s[0] := CAP(S.s[0]); S.s[1] := 0X;
					Attributes.SetString(link, "Opt", S.s)
				END
			ELSE
				key := HyperDocs.BuildKey(NIL, S.s);
				IF key # HyperDocs.UndefKey THEN
					T := NIL; time := -1;
					Oberon.GetSelection(T, beg, end, time);
					IF (T # NIL) & (time > 0) THEN
						link := HyperDocs.LinkControl(key);
						IF ~HyperDocs.Visited(key) THEN
							Texts.ChangeLooks(T, beg, end, {1}, NIL, SHORT(HyperDocs.linkC), 0)
						ELSE
							Texts.ChangeLooks(T, beg, end, {1}, NIL, SHORT(HyperDocs.oldLinkC), 0)
						END;
						Texts.WriteObj(W, link);
						Texts.Insert(T, end, W.buf);
						Attributes.Scan(S);
						IF (S.class IN {Texts.Name, Texts.String}) & (S.s # "") THEN
							label := Gadgets.CreateObject("TextGadgets.NewControl");
							Gadgets.NameObj(label, S.s);
							Texts.WriteObj(W, label);
							Texts.Insert(T, beg, W.buf)
						END;
						Attributes.Scan(S);
						IF S.class = Texts.Name THEN
							S.s[0] := CAP(S.s[0]); S.s[1] := 0X;
							Attributes.SetString(link, "Opt", S.s)
						END
					END
				END
			END
		END
	END Apply;

(** HyperDocTools.LinkIndex * (marked text)
		Display a sorted list of all links in the marked textdoc. *)
	PROCEDURE LinkIndex*;
		TYPE
			Scheme = POINTER TO SchemeDesc;
			SchemeDesc = RECORD
				scheme: HyperDocs.LinkScheme;
				W: Texts.Writer;
				next: Scheme
			END;
		VAR
			T: Texts.Text;
			pos, key, beg: LONGINT;
			F: Texts.Finder;
			obj: Objects.Object;
			S: HyperDocs.LinkScheme;
			schemes, s, last: Scheme;
			R: Texts.Reader;
			style: TextGadgets.Style;
			label: ARRAY 64 OF CHAR;
			i, col: INTEGER;
			ch: CHAR;
	BEGIN
		T := Oberon.MarkedText();
		IF T # NIL THEN
			style := TextGadgets.newStyle();
			style.mode := {TextGadgets.left};
			style.noTabs := 1;
			style.tab[0] := 16*W.lib(Fonts.Font).height;
			Texts.WriteObj(W, style);
			schemes := NIL; last := NIL;
			Texts.OpenFinder(F, T, 0);
			pos := F.pos;
			Texts.FindObj(F, obj);
			WHILE ~ F.eot DO
				IF (obj IS TextGadgets.Control) & (Attributes.FindAttr("Key", obj(Gadgets.Frame).attr) # NIL) THEN
					Attributes.GetInt(obj, "Key", key);
					IF key # HyperDocs.UndefKey THEN
						S := HyperDocs.LinkSchemeByKey(key);
						IF S # NIL THEN
							HyperDocs.RetrieveLink(key, link);
							s := schemes;
							WHILE (s # NIL) & (s.scheme # S) DO
								s := s.next
							END;
							IF s = NIL THEN
								NEW(s);
								IF last = NIL THEN
									schemes := s
								ELSE
									last.next := s
								END;
								last := s;
								s.scheme := S;
								Texts.OpenWriter(s.W)
							END;
							beg := pos-1;
							Texts.OpenReader(R, T, beg);
							Texts.Read(R, ch); col := R.col;
							WHILE (beg > 0) & (col = R.col) & (R.lib IS Fonts.Font) DO
								DEC(beg);
								Texts.OpenReader(R, T, beg);
								Texts.Read(R, ch)
							END;
							INC(beg);
							Texts.OpenReader(R, T, beg);
							Texts.Read(R, ch);
							WHILE (beg < pos) & (ch <= " ") DO
								Texts.Read(R, ch);
								INC(beg)
							END;
							i := 0;
							WHILE (beg < pos) & (i < 63) DO
								IF ch = Strings.CR THEN
									ch := " "
								END;
								label[i] := ch;
								INC(i);
								Texts.Read(R, ch);
								INC(beg)
							END;
							label[i] := 0X;
							IF ~HyperDocs.Visited(key) THEN
								Texts.SetColor(s.W, SHORT(HyperDocs.linkC))
							ELSE
								Texts.SetColor(s.W, SHORT(HyperDocs.oldLinkC))
							END;
							Texts.WriteString(s.W, label);
							Texts.WriteObj(s.W, obj);
							Texts.SetColor(s.W, SHORT(Display3.textC));
							Texts.Write(s.W, Strings.Tab);
							Texts.WriteString(s.W, link);
							Texts.WriteLn(s.W)
						END
					END
				END;
				pos := F.pos;
				Texts.FindObj(F, obj)
			END;
			Texts.SetFont(W, Fonts.This("Default12.Scn.Fnt"));
			NEW(T);
			Texts.Open(T, "");
			s := schemes;
			WHILE s # NIL DO
				Texts.WriteString(W, s.scheme.prefix);
				Texts.WriteLn(W);
				Texts.WriteLn(W);
				Texts.Append(T, W.buf);
				Texts.Append(T, s.W.buf);
				Texts.WriteLn(W);
				Texts.Append(T, W.buf);
				s := s.next
			END;
			IF T.len > 0 THEN
				TextDocs.ShowText("Links", T, HyperDocs.docW, HyperDocs.docH)
			END;
			Texts.SetFont(W, Fonts.Default)
		END
	END LinkIndex;

BEGIN
	Texts.OpenWriter(W)
END HyperDocTools.
