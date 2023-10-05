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

MODULE HyperDocs;	(** portable *) (* ejz,   *)
	IMPORT Files, BTrees, Strings, Objects, Display3, Fonts, Texts, Oberon, Attributes, Links,
		Modules, Gadgets, TextGadgets0, TextGadgets, Documents, Desktops, Pictures, Display, MIME;

(** Module HyperDocs allows to build links between any documents. Documents are either documents on the
		local disk or documents retrieved from the internet. A link to a document is just a string, which describes
		where and how to get the document. The strings are encoded according to the URL (Uniform Resource Locators)
		syntax (RFC 1738).
		These module handles the following tasks:
			- a database for links: each link is associated to a unique key (LONGINT)
			- associating links to documents: history & caching

		This modul supports file urls. The following line should be added to the LinkSchemes section of the Registry:
			file = HyperDocs.NewLinkScheme
		And the following line to the Documents section:
			file = HyperDocs.NewDoc *)

	CONST
	(** Maximal length of different link parts. *)
		PrefixStrLen* = 16;
		MaxLink* = 1024;
		ServerStrLen* = 64;
		PathStrLen* = 256;
		UndefKey* = -1; (** A key value which is not associated to a link. *)

	TYPE
		LinkScheme* = POINTER TO LinkSchemeDesc;
		Node* = POINTER TO NodeDesc;

	(** The different link types (so called link schemes) are distinguished by different prefixes (e.g. http ). For each prefix
		a single object is allocated the first time a link of that kind is generated. The different link schemes are defined in the
		LinkSchemes section of Registry. The syntax for such an entry is: scheme "=" generator . *)
		LinkSchemeDesc* = RECORD (Gadgets.ObjDesc)
			prefix*: ARRAY PrefixStrLen OF CHAR; (** The schemes prefix in all lowercase *)
			usePath*: BOOLEAN; (** TRUE if prefix must be followed by :// *)
			next: LinkScheme
		END;

	(** Base class for messages sent to a link scheme object. *)
		LinkSchemeMsg* = RECORD (Objects.ObjMsg)
			key*: LONGINT;
			res*: INTEGER
		END;
		DefURL* = POINTER TO DefURLDesc;
		DefURLDesc* = RECORD
			key*: LONGINT;
			prefix*: ARRAY PrefixStrLen OF CHAR;
			host*: ARRAY ServerStrLen OF CHAR;
			path*: ARRAY PathStrLen OF CHAR;
			label*: ARRAY 64 OF CHAR;
			port*: INTEGER
		END;

	(** Reqeuest to a link scheme object to parse link and register its normalized form in the database.
		If base # NIL, the link may be a relative link.
		res = 0: The link was succefully parsed and key contains a unique key for that link.
		res # 0: The link does not match the syntax of the link scheme. *)
		RegisterLinkMsg* = RECORD (LinkSchemeMsg)
			link*: ARRAY MaxLink OF CHAR;
			base*: DefURL
		END;

	(** Reqeuest to a link scheme object to query the type and size of the document referenced by key.
		res = 0: Type and size contain the reqeuested information.
		res # 0: The reqeuest failed for some reason. *)
		InfoMsg* = RECORD (LinkSchemeMsg)
			contType*: MIME.ContentType;
			size*, date*, time*: LONGINT
		END;

	(** Reqeuest to a link scheme object to write the data of the document referenced by key to R.
		res = 0: Ok
		res = 1: Not supported
		res # 0: Failed *)
		FetchMsg* = RECORD (LinkSchemeMsg)
			R*: Files.Rider
		END;

	(** An entry in the history. *)
		NodeDesc* = RECORD
			id, key*, org*: LONGINT;
			old*, prev*: Node
		END;

	(** Context when taking a link. old and new are the history entries for the old (curDoc) and new document.
		 replace: the old document is replaced by the new one.
		 history: enter the new document into the history. *)
		Context* = POINTER TO ContextDesc;
		ContextDesc* = RECORD
			old*, new*: Node;
			curDoc*: Documents.Document;
			replace*, history*: BOOLEAN
		END;

	VAR
		linkSchemes: LinkScheme;
		linksIndex, keysIndex: BTrees.Tree;
		linksFile: Files.File;
		curKey, curID, loadingKey*: LONGINT;
		history: Node;
		context*: Context; (** Context for the current link. *)
		linkC*, oldLinkC*: INTEGER; (** Default colors for text-links. *)
		linkMethods*, linkPictMethods*: TextGadgets0.Methods; (** New methods for TextGadgets which handle underline for hyperlinks and background images. *)
		link, cmpBuf: ARRAY MaxLink OF CHAR;
		diskCache: Files.File;
		linkBeg, linkEnd: LONGINT;
		linkF: Gadgets.Frame;
		docW*, docH*: INTEGER;
		keepurls: BOOLEAN;
		
	PROCEDURE HexVal(ch: CHAR): INTEGER;
	BEGIN
		IF (ch >= "0") & (ch <= "9") THEN
			RETURN ORD(ch)-ORD("0")
		ELSIF (ch >= "A") & (ch <= "F") THEN
			RETURN ORD(ch)-ORD("A")+10
		ELSIF (ch >= "a") & (ch <= "f") THEN
			RETURN ORD(ch)-ORD("a")+10
		END
	END HexVal;

	PROCEDURE HexDigit(i: INTEGER): CHAR;
	BEGIN
		IF i < 10 THEN
			RETURN CHR(i+ORD("0"))
		ELSE
			RETURN CHR(i-10+ORD("A"))
		END
	END HexDigit;

(** Escape sequences in url are expanded. E.g. "Hello%20World" becomes "Hello World". *)
	PROCEDURE UnESC*(VAR url: ARRAY OF CHAR);
		VAR i, j: LONGINT;
	BEGIN
		i := 0;
		WHILE url[i] # 0X DO
			IF (url[i] = "%") & Strings.IsHexDigit(url[i+1]) & Strings.IsHexDigit(url[i+2]) THEN
				url[i] := CHR(16*HexVal(url[i+1])+HexVal(url[i+2]));
				j := i+1;
				REPEAT
					url[j] := url[j+2]; INC(j)
				UNTIL url[j] = 0X
			END;
			INC(i)
		END
	END UnESC;

(** All special charactrs in str are escaped. E.g. "a+b" becomes "a%2Bb".
		Special characters are: 1X .. 20X, "+", "&", "=", "?", "%", "$", ";". "#", ":" & special. *)
	PROCEDURE ESC*(VAR str: ARRAY OF CHAR; special: CHAR);
		VAR
			i, j, l: LONGINT;
			ch: CHAR;
	BEGIN
		l := LEN(str)-1; i := 0;
		WHILE str[i] # 0X DO
			ch := str[i];
			IF (ch <= 020X) OR (ch = "+") OR(ch = "&") OR (ch = "=") OR (ch = "?") OR (ch = "%") OR (ch = "$") OR
				(ch = ";") OR (ch = "#") OR (ch = ":") OR (ch = special) THEN
				j := l;
				WHILE (j-2) > i DO
					str[j] := str[j-2]; DEC(j)
				END;
				str[i] := "%";
				str[i+1] := HexDigit(ORD(ch) DIV 16);
				str[i+2] := HexDigit(ORD(ch) MOD 16)
			END;
			INC(i)
		END
	END ESC;

(** Get the link scheme object for prefix. *)
	PROCEDURE LinkSchemeByPrefix*(prefix: ARRAY OF CHAR): LinkScheme;
		VAR
			l: LinkScheme;
			gen: ARRAY 64 OF CHAR;
			obj: Objects.Object;
			S: Texts.Scanner;
	BEGIN
		Strings.Lower(prefix, prefix); l := linkSchemes;
		WHILE (l # NIL) & (l.prefix # prefix) DO
			l := l.next
		END;
		IF l = NIL THEN
			gen := "LinkSchemes."; Strings.Append(gen, prefix);
			Oberon.OpenScanner(S, gen);
			IF S.class IN {Texts.Name, Texts.String} THEN
				obj := Gadgets.CreateObject(S.s);
				IF (obj # NIL) & (obj IS LinkScheme) THEN
					l := obj(LinkScheme); COPY(prefix, l.prefix);
					l.next := linkSchemes; linkSchemes := l
				END
			END
		END;
		RETURN l
	END LinkSchemeByPrefix;

(** Get the link scheme object for the link-scheme associated to key. *)
	PROCEDURE LinkSchemeByKey*(key: LONGINT): LinkScheme;
		VAR
			R: Files.Rider;
			i: LONGINT;
			prefix: ARRAY PrefixStrLen OF CHAR;
			res: INTEGER;
			ch: CHAR;
	BEGIN
		BTrees.SearchLInt(keysIndex, key, i, res);
		IF res = BTrees.Done THEN
			Files.Set(R, linksFile, i);
			Files.ReadLInt(R, i); (* key *)
			Files.ReadLInt(R, i); (* cache *)
			Files.ReadLInt(R, i); (* next *)
			i := 0;
			Files.Read(R, ch); (* link *)
			WHILE (ch # 0X) & (ch # ":") & (i < (PrefixStrLen-1)) DO
				prefix[i] := ch; INC(i);
				Files.Read(R, ch)
			END;
			prefix[i] := 0X;
			RETURN LinkSchemeByPrefix(prefix)
		ELSE
			RETURN NIL
		END
	END LinkSchemeByKey;

(** Add link (in normalized form) to the database returning a unique key. *)
	PROCEDURE RegisterLink*(VAR link: ARRAY OF CHAR): LONGINT;
		VAR
			R: Files.Rider;
			org, key, cache, next, porg, l: LONGINT;
			res: INTEGER;
			same: BOOLEAN;
		PROCEDURE SameLink(): BOOLEAN;
		BEGIN
			Files.ReadBytes(R, cmpBuf, l);
			cmpBuf[l] := 0X;
			RETURN cmpBuf = link
		END SameLink;
	BEGIN
		IF link = "" THEN
			RETURN UndefKey
		END;
		BTrees.SearchStr(linksIndex, link, porg, res);
		IF res = BTrees.Done THEN
			org := Files.Length(linksFile);
			l := Strings.Length(link);
			Files.Set(R, linksFile, porg);
			Files.ReadLInt(R, key); (* key *)
			IF l < (BTrees.StrKeySize-1) THEN
				RETURN key
			END; INC(l);
			Files.ReadLInt(R, cache); (* cache *)
			porg := Files.Pos(R);
			Files.ReadLInt(R, next); (* next *)
			same := SameLink(); (* link *)
			WHILE (next > 0) & ~same DO
				Files.Set(R, linksFile, next);
				Files.ReadLInt(R, key); (* key *)
				Files.ReadLInt(R, cache); (* cache *)
				porg := Files.Pos(R);
				Files.ReadLInt(R, next); (* next *)
				same := SameLink() (* link *)
			END;
			IF same THEN
				RETURN key
			ELSE
				Files.Set(R, linksFile, porg); (* fixup next chain *)
				Files.WriteLInt(R, org)
			END
		ELSE
			BTrees.InsertStr(linksIndex, link, -1, res);
			org := Files.Length(linksFile);
			BTrees.InsertStr(linksIndex, link, org, res)
		END;
		INC(curKey); key := curKey;
		Files.Set(R, linksFile, org);
		Files.WriteLInt(R, key); (* key *)
		Files.WriteLInt(R, -1); (* cache *)
		Files.WriteLInt(R, -1); (* next *)
		Files.WriteString(R, link); (* link *)
		BTrees.InsertLInt(keysIndex, key, org, res);
		RETURN key
	END RegisterLink;

(** Try to normalize link and add it to the database returning a unique key. If base # NIL, link is a relative link to that
		base. *)
	PROCEDURE BuildKey*(base: DefURL; link: ARRAY OF CHAR): LONGINT;
		VAR
			R: RegisterLinkMsg;
			prefix: ARRAY PrefixStrLen OF CHAR;
			i: LONGINT;
			s: LinkScheme;
	BEGIN
		s := NIL; i := 0;
		WHILE (link[i] # 0X) & (link[i] # ":") & Strings.IsAlpha(link[i]) & (i < (PrefixStrLen-1)) DO
			prefix[i] := link[i]; INC(i)
		END;
		IF link[i] = ":" THEN
			prefix[i] := 0X; s := LinkSchemeByPrefix(prefix)
		END;
		IF (s = NIL) & (base # NIL) THEN
			s := LinkSchemeByPrefix(base.prefix)
		END;
		IF s = NIL THEN
			s := LinkSchemeByPrefix("file") (* file-url = [ "file://" ] docname *)
		END;
		IF s # NIL THEN
			R.key := UndefKey; R.res := -1; R.base := base;
			COPY(link, R.link);
			s.handle(s, R);
			RETURN R.key
		ELSE
			RETURN UndefKey
		END
	END BuildKey;

(** Create a temporary file name for D which is prefixed by prefix. key identifies the new name. *)
	PROCEDURE TempDocName*(prefix: ARRAY OF CHAR; VAR name: ARRAY OF CHAR; VAR key: LONGINT);
		VAR noStr: ARRAY 8 OF CHAR;
	BEGIN
		COPY(prefix, name); Strings.IntToStr(curKey+1, noStr); Strings.Append(name, noStr);
		Strings.Append(name, ".Temp"); key := BuildKey(NIL, name) (* key = noStr *)
	END TempDocName;

(** Retrieve the link associated to key. *)
	PROCEDURE RetrieveLink*(key: LONGINT; VAR link: ARRAY OF CHAR);
		VAR
			R: Files.Rider;
			org, i, l: LONGINT;
			res: INTEGER;
			ch: CHAR;
	BEGIN
		BTrees.SearchLInt(keysIndex, key, org, res);
		IF res = BTrees.Done THEN
			Files.Set(R, linksFile, org);
			Files.ReadLInt(R, org); (* key *)
			Files.ReadLInt(R, org); (* cache *)
			Files.ReadLInt(R, org); (* next *)
			l := LEN(link)-1; i := 0;
			Files.Read(R, ch); (* link *)
			WHILE (ch # 0X) & (i < l) DO
				link[i] := ch; INC(i);
				Files.Read(R, ch)
			END;
			link[i] := 0X
		ELSE
			COPY("", link)
		END
	END RetrieveLink;

(** Store the link associated to key. *)
	PROCEDURE StoreLink*(VAR R: Files.Rider; key: LONGINT);
		VAR
			Rl: Files.Rider;
			org: LONGINT;
			res: INTEGER;
			ch: CHAR;
	BEGIN
		BTrees.SearchLInt(keysIndex, key, org, res);
		IF res = BTrees.Done THEN
			Files.Set(Rl, linksFile, org);
			Files.ReadLInt(Rl, org); (* key *)
			Files.ReadLInt(Rl, org); (* cache *)
			Files.ReadLInt(Rl, org); (* next *)
			Files.Read(Rl, ch);
			WHILE ch # 0X DO
				Files.Write(R, ch); Files.Read(Rl, ch)
			END
		END;
		Files.Write(R, 0X)
	END StoreLink;

(** Reload a link previously stored with StoreLink.*)
	PROCEDURE LoadLink*(VAR R: Files.Rider; VAR key: LONGINT);
	BEGIN
		Files.ReadString(R, link);
		key := RegisterLink(link)
	END LoadLink;

(** Default message handler for link scheme objects. *)
	PROCEDURE LinkSchemeHandler*(L: Objects.Object; VAR M: Objects.ObjMsg);
		VAR pl, l: LinkScheme;
	BEGIN
		WITH L: LinkScheme DO
			IF M IS LinkSchemeMsg THEN
				WITH M: LinkSchemeMsg DO
					IF M IS RegisterLinkMsg THEN
						WITH M: RegisterLinkMsg DO
							M.key := UndefKey; M.res := -1
						END
					ELSIF M IS InfoMsg THEN
						WITH M: InfoMsg DO
							M.contType := MIME.GetContentType("text/plain");
							M.time := 0; M.date := 0; M.size := 0; M.res := 0
						END
					ELSIF M IS FetchMsg THEN
						M.res := 1
					ELSE
						M.res := -1
					END
				END
			ELSIF M IS Objects.FileMsg THEN
				WITH M: Objects.FileMsg DO
					Gadgets.objecthandle(L, M);
					IF M.id = Objects.store THEN
						Files.WriteString(M.R, L.prefix);
						Files.WriteBool(M.R, L.usePath)
					ELSIF M.id = Objects.load THEN
						Files.ReadString(M.R, L.prefix);
						Files.ReadBool(M.R, L.usePath);
						pl := NIL; l := linkSchemes;
						WHILE (l # NIL) & (l.prefix # L.prefix) DO
							pl := l; l := l.next
						END;
						IF l = NIL THEN
							L.next := linkSchemes; linkSchemes := L
						ELSIF l # L THEN
							IF pl # NIL THEN
								pl.next := l.next
							ELSE
								linkSchemes := l.next
							END;
							L.next := linkSchemes; linkSchemes := L
						END
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "Prefix" THEN
							M.class := Objects.String; COPY(L.prefix, M.s); M.res := 0
						ELSE
							Gadgets.objecthandle(L, M)
						END
					ELSIF M.id = Objects.set THEN
						Gadgets.objecthandle(L, M)
					ELSIF M.id = Objects.enum THEN
						Gadgets.objecthandle(L, M);
						M.Enum("Prefix"); M.res := 0
					END
				END
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					M.obj := L
				END
			ELSE
				Gadgets.objecthandle(L, M)
			END
		END
	END LinkSchemeHandler;

	PROCEDURE *LinkControlHandler(obj: Objects.Object; VAR M: Objects.ObjMsg);
		VAR key: LONGINT;
	BEGIN
		IF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				TextGadgets.ControlHandler(obj, M);
				IF M.id = Objects.store THEN
					Attributes.GetInt(obj, "Key", key);
					StoreLink(M.R, key)
				ELSIF M.id = Objects.load THEN
					LoadLink(M.R, key);
					Attributes.SetInt(obj, "Key", key)
				END
			END
		ELSIF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF (M.id = Objects.get) & (M.name = "Gen") THEN
					M.class := Objects.String; M.s := "HyperDocs.NewLinkControl"; M.res := 0
				ELSIF (M.id = Objects.set) & (M.name = "Cmd") THEN
					(* Cmd is read-only *)
				ELSE
					TextGadgets.ControlHandler(obj, M)
				END
			END
		ELSE
			TextGadgets.ControlHandler(obj, M)
		END
	END LinkControlHandler;

	PROCEDURE NewLinkControl*;
	BEGIN
		TextGadgets.NewControl();
		Attributes.SetString(Objects.NewObj, "Cmd", "HyperDocs.FollowLink  % #Opt  #Key");
		Attributes.SetInt(Objects.NewObj, "Key", UndefKey);
		Attributes.SetString(Objects.NewObj, "Opt", "A");
		Objects.NewObj.handle := LinkControlHandler
	END NewLinkControl;

(** Create a text hyperlink object for key. *)
	PROCEDURE LinkControl*(key: LONGINT): Objects.Object;
	BEGIN
		NewLinkControl();
		Attributes.SetInt(Objects.NewObj, "Key", key);
		Attributes.SetString(Objects.NewObj, "Opt", "A");
		RETURN Objects.NewObj 
	END LinkControl;

(** Get the node linked to doc. *)
	PROCEDURE NodeByDoc*(doc: Documents.Document): Node;
		VAR
			id: LONGINT;
			node: Node;
	BEGIN
		IF (doc # NIL) & (Attributes.FindAttr("DocID", doc.attr) # NIL) THEN
			Attributes.GetInt(doc, "DocID", id);
			node := history;
			WHILE (node # NIL) & (node.id # id) DO
				node := node.prev
			END;
			RETURN node
		ELSE
			RETURN NIL
		END
	END NodeByDoc;

(** Link node to doc. *)
	PROCEDURE LinkNodeToDoc*(doc: Documents.Document; node: Node);
	BEGIN
		IF doc # NIL THEN
			IF node # NIL THEN
				Attributes.SetInt(doc, "DocID", node.id)
			ELSE
				Attributes.SetInt(doc, "DocID", -1);
				Attributes.DeleteAttr(doc.attr, "DocID")
			END
		END
	END LinkNodeToDoc;

(** Create a new entry in the history. *)
	PROCEDURE Remember*(key: LONGINT; old: Node; VAR new: Node);
	BEGIN
		IF (old # NIL) & (old.key = key) & (old.org = 0) THEN
			new := old
		ELSE
			INC(curID); NEW(new);
			new.org := 0; new.id := curID;
			new.key := key; new.old := old;
			new.prev := history; history := new
		END
	END Remember;

(** Create a new entry in the history, when scrolling within the same document. *)
	PROCEDURE RememberOrg*(org: LONGINT; old: Node; VAR new: Node);
	BEGIN
		IF old.org # org THEN
			Remember(old.key, old, new)
		ELSE
			new := old
		END;
		new.org := org
	END RememberOrg;

	PROCEDURE RemoveNode(node: Node);
		VAR n0, n1: Node;
	BEGIN
		n0 := NIL; n1 := history;
		WHILE n1 # node DO
			IF n1.old = node THEN
				n1.old := NIL
			END;
			n0 := n1; n1 := n1.prev
		END;
		IF n0 # NIL THEN
			n0.prev := node.prev
		ELSE
			history := node.prev
		END
	END RemoveNode;

(** Create a document name for key. *)
	PROCEDURE DocNameByKey*(VAR name: ARRAY OF CHAR; key: LONGINT);
		VAR
			s: LinkScheme;
			str: ARRAY 16 OF CHAR;
	BEGIN
		s := LinkSchemeByKey(key);
		IF s # NIL THEN
			COPY(s.prefix, name);
			Strings.AppendCh(name, ":");
			Strings.IntToStr(key, str);
			Strings.Append(name, str)
		ELSE
			COPY("", name)
		END
	END DocNameByKey;

	PROCEDURE SetVisited(key: LONGINT);
		VAR
			R: Files.Rider;
			org: LONGINT;
			res: INTEGER;
	BEGIN
		BTrees.SearchLInt(keysIndex, key, org, res);
		IF res = BTrees.Done THEN
			Files.Set(R, linksFile, org);
			Files.ReadLInt(R, org); (* key *)
			Files.ReadLInt(R, org); (* cache *)
			IF org = -1 THEN
				Files.Set(R, linksFile, Files.Pos(R)-4);
				Files.WriteLInt(R, -2)
			END
		END
	END SetVisited;

	PROCEDURE SetVisitedCol(doc: Documents.Document);
		VAR
			obj: Objects.Object;
			ocol: LONGINT;
			col: SHORTINT;
	BEGIN
		IF (doc # NIL) & (doc.dsc = linkF) THEN
			Links.GetLink(linkF, "Model", obj);
			IF (obj # NIL) & (obj IS Texts.Text) THEN
				IF Attributes.FindAttr("OldLinkColor", linkF.attr) # NIL THEN
					Attributes.GetInt(linkF, "OldLinkColor", ocol);
					col := SHORT(SHORT(ocol))
				ELSE
					col := SHORT(oldLinkC)
				END;
				Texts.ChangeLooks(obj(Texts.Text), linkBeg, linkEnd, {1}, NIL, col, 0)
			END
		END;
		linkF := NIL
	END SetVisitedCol;

	PROCEDURE Open(VAR name: ARRAY OF CHAR): Documents.Document;
		VAR D: Documents.Document;
	BEGIN
		D := Documents.Open(name);
		loadingKey := UndefKey;
		RETURN D
	END Open;

(** Open newDoc (key) using context cont. *)
	PROCEDURE FollowKeyLink*(cont: Context; newDoc: LONGINT);
		VAR
			name: ARRAY 32 OF CHAR;
			s: LinkScheme;
			okey: LONGINT;
			D: Documents.Document;
	BEGIN
		IF newDoc # UndefKey THEN
			SetVisited(newDoc);
			DocNameByKey(name, newDoc); loadingKey := newDoc;
			IF cont = NIL THEN NEW(cont) END; context := cont;
			context.curDoc := Desktops.CurDoc(Gadgets.context);
			SetVisitedCol(context.curDoc);
			context.old := NodeByDoc(context.curDoc);
			IF (context.old = NIL) & (context.curDoc # NIL) & (context.curDoc.name # "") THEN
				s := LinkSchemeByKey(newDoc);
				IF (s # NIL) & (s.prefix = "file") THEN
					okey := BuildKey(NIL, context.curDoc.name);
					IF okey # UndefKey THEN
						Remember(okey, NIL, context.old);
						LinkNodeToDoc(context.curDoc, context.old)
					END
				END
			END;
			IF (context.old # NIL) & (context.curDoc # NIL) THEN
				IF context.curDoc.dsc IS TextGadgets.Frame THEN
					RememberOrg(context.curDoc.dsc(TextGadgets.Frame).org, context.old, context.old)
				END;
				LinkNodeToDoc(context.curDoc, context.old)
			END;
			context.history := TRUE;
			Remember(newDoc, context.old, context.new);
			IF context.old # NIL THEN
				context.replace := LinkSchemeByKey(context.old.key) = LinkSchemeByKey(context.new.key)
			ELSE
				context.replace := FALSE
			END;
			D := Open(name);
			IF (D # NIL) & (D.dsc # NIL) THEN
				IF context.history THEN
					LinkNodeToDoc(D, context.new)
				ELSE
					RemoveNode(context.new)
				END;
				IF context.replace THEN
					Desktops.ReplaceCurrentDoc(D)
				ELSE
					Desktops.ShowDoc(D)
				END
			ELSE
				RemoveNode(context.new)
			END
		END;
		context := NIL
	END FollowKeyLink;

(** HyperDocs.FollowLink [ "%" ( "R" | "N" ) ] ( key | name )
		Open document key or name using Desktops.ReplaceCurrentDoc (%R) or Desktops.ShowDoc (%N). *)
	PROCEDURE FollowLink*;
		VAR
			S: Attributes.Scanner;
			D: Documents.Document;
			key, okey: LONGINT;
			forceR, forceN: BOOLEAN;
	BEGIN
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Attributes.Scan(S);
		forceR := FALSE; forceN := FALSE;
		IF (S.class = Attributes.Char) & (S.c = "%") THEN
			Attributes.Scan(S);
			IF S.class = Attributes.Name THEN
				forceR := CAP(S.s[0]) = "R"; forceN := CAP(S.s[0]) = "N"
			END;
			Attributes.Scan(S)
		END;
		IF S.class IN {Attributes.Name, Attributes.String} THEN
			key := BuildKey(NIL, S.s)
		ELSIF S.class = Attributes.Int THEN
			key := S.i;
			IF key < 0 THEN
				key := UndefKey
			END
		ELSE
			key := UndefKey
		END;
		IF key # UndefKey THEN
			SetVisited(key);
			DocNameByKey(S.s, key);
			NEW(context);
			context.curDoc := Desktops.CurDoc(Gadgets.context);
			SetVisitedCol(context.curDoc);
			context.old := NodeByDoc(context.curDoc);
			IF (context.old = NIL) & (context.curDoc # NIL) & (context.curDoc.name # "") THEN
				okey := BuildKey(NIL, context.curDoc.name);
				IF okey # UndefKey THEN
					Remember(okey, NIL, context.old);
					LinkNodeToDoc(context.curDoc, context.old)
				END
			END;
			IF (context.old # NIL) & (context.curDoc # NIL) THEN
				IF context.curDoc.dsc IS TextGadgets.Frame THEN
					RememberOrg(context.curDoc.dsc(TextGadgets.Frame).org, context.old, context.old)
				END;
				LinkNodeToDoc(context.curDoc, context.old)
			END;
			context.history := TRUE;
			Remember(key, context.old, context.new);
			IF context.old # NIL THEN
				context.replace := LinkSchemeByKey(context.old.key) = LinkSchemeByKey(context.new.key)
			ELSE
				context.replace := FALSE
			END;
			loadingKey := key;
			D := Open(S.s);
			IF forceN THEN
				context.replace := FALSE
			ELSIF forceR THEN
				context.replace := TRUE
			END;
			IF (D # NIL) & (D.dsc # NIL) THEN
				IF context.history THEN
					LinkNodeToDoc(D, context.new)
				ELSE
					RemoveNode(context.new)
				END;
				IF context.replace THEN
					Desktops.ReplaceCurrentDoc(D)
				ELSE
					Desktops.ShowDoc(D)
				END
			ELSE
				RemoveNode(context.new)
			END
		END;
		context := NIL
	END FollowLink;

(** Replace the current doc by newD, key is the key for the old document. *)
	PROCEDURE ReplaceCurDoc*(key: LONGINT; newD: Documents.Document);
		VAR
			old, new: Node;
			curD: Documents.Document;
	BEGIN
		curD := Desktops.CurDoc(Gadgets.context);
		old := NodeByDoc(curD);
		IF curD.dsc IS TextGadgets.Frame THEN
			RememberOrg(curD.dsc(TextGadgets.Frame).org, old, old)
		END;
		LinkNodeToDoc(curD, old);
		Remember(key, old, new);
		LinkNodeToDoc(newD, new);
		Desktops.ReplaceCurrentDoc(newD)
	END ReplaceCurDoc;

(* Find the line containing pos. *)
	PROCEDURE FindBeg(T: Texts.Text; VAR pos: LONGINT);
		VAR
			R: Texts.Reader;
			ch: CHAR;
	BEGIN
		Texts.OpenReader(R, T, pos);
		Texts.Read(R, ch);
		WHILE (pos > 0) & ((ch # Strings.CR) OR ~(R.lib IS Fonts.Font)) DO
			DEC(pos);
			Texts.OpenReader(R, T, pos);
			Texts.Read(R, ch)
		END;
		IF ch = Strings.CR THEN
			INC(pos)
		END
	END FindBeg;

	PROCEDURE ScrollTo*(F: TextGadgets.Frame; pos: LONGINT);
	BEGIN
		FindBeg(F.text, pos);
		TextGadgets0.ScrollTo(F, pos)
	END ScrollTo;

	PROCEDURE VisitNode(curDoc: Documents.Document; cnode, node: Node);
		VAR
			D: Documents.Document;
			docName: ARRAY 64 OF CHAR;
	BEGIN
		IF cnode.key # node.key THEN
			NEW(context);
			context.curDoc := curDoc;
			context.old := NodeByDoc(curDoc);
			context.new := node;
			context.history := TRUE;
			context.replace := TRUE;
			DocNameByKey(docName, node.key); loadingKey := node.key;
			D := Open(docName);
			IF (D # NIL) & (D.dsc # NIL) THEN
				IF context.history THEN
					LinkNodeToDoc(D, node)
				END;
				IF context.replace THEN
					Desktops.ReplaceCurrentDoc(D)
				ELSE
					Desktops.ShowDoc(D)
				END;
(*				IF (D.dsc IS TextGadgets.Frame) & (node.org >= 0) THEN
					ScrollTo(D.dsc(TextGadgets.Frame), node.org)
				END	*)
			END;
			context := NIL
		ELSE
(*			IF (curDoc.dsc IS TextGadgets.Frame) & (node.org >= 0) THEN
				ScrollTo(curDoc.dsc(TextGadgets.Frame), node.org)
			END;	*)
			LinkNodeToDoc(curDoc, node)
		END
	END VisitNode;

(** HyperDocs.Back
		Go one step back in the history of the current document. *)
	PROCEDURE Back*;
		VAR
			curDoc: Documents.Document;
			cnode, tnode: Node;
	BEGIN
		linkF := NIL;
		curDoc := Desktops.CurDoc(Gadgets.context);
		cnode := NodeByDoc(curDoc);
		IF cnode # NIL THEN
			tnode := history;
			WHILE (tnode # NIL) & (tnode # cnode.old) DO
				tnode := tnode.prev
			END;
			IF tnode # NIL THEN
				VisitNode(curDoc, cnode, tnode)
			ELSE
				cnode.org := 0;
				VisitNode(curDoc, cnode, cnode)
			END
		END
	END Back;

	PROCEDURE *LocateString(F: TextGadgets0.Frame; x, y, X, Y: INTEGER; VAR loc: TextGadgets0.Loc);
		VAR
			R: Texts.Reader;
			ch: CHAR;
			Fi: Texts.Finder;
			obj: Objects.Object;
			loc1, loc2: TextGadgets0.Loc;
			line: TextGadgets0.Line;
			pos, beg, end: LONGINT;
			linkC, oldLinkC: INTEGER;
	BEGIN
		Attributes.GetInt(F, "LinkColor", pos);
		linkC := SHORT(pos);
		Attributes.GetInt(F, "OldLinkColor", pos);
		oldLinkC := SHORT(pos); linkF := NIL;
		TextGadgets.methods.LocateChar(F, x, y, X, Y, loc);
		Texts.OpenReader(R, F.text, loc.pos);
		Texts.Read(R, ch);
		WHILE ~R.eot & (R.lib IS Fonts.Font) & ((R.col = linkC) OR (R.col = oldLinkC)) DO
			Texts.Read(R, ch)
		END;
		Texts.OpenFinder(Fi, F.text, Texts.Pos(R)-1);
		pos := Fi.pos;
		Texts.FindObj(Fi, obj);
		IF (pos+1 # Texts.Pos(R)) OR (obj = NIL) OR ~(obj IS TextGadgets.Control) THEN
			TextGadgets.methods.LocateString(F, x, y, X, Y, loc);
			RETURN
		END;
		pos := loc.pos;
		beg := F.org;
		line := F.trailer.next;
		WHILE (line.next # F.trailer) & ((beg+line.len) <= pos) DO
			INC(beg, line.len);
			line := line.next
		END;
		end := beg+loc.line.len;
		Texts.OpenReader(R, F.text, pos);
		Texts.Read(R, ch);
		WHILE (pos >= beg) & ((R.col = linkC) OR (R.col = oldLinkC)) & (R.lib IS Fonts.Font) DO
			DEC(pos);
			Texts.OpenReader(R, F.text, pos);
			Texts.Read(R, ch)
		END;
		Texts.OpenReader(R, F.text, loc.pos);
		Texts.Read(R, ch);
		WHILE ~R.eot & (Texts.Pos(R) < end) & ((R.col = linkC) OR (R.col = oldLinkC)) & (R.lib IS Fonts.Font) DO
			Texts.Read(R, ch)
		END;
		linkF := F;
		linkBeg := pos+1;
		F.do.LocatePos(F, linkBeg, loc1);
		linkEnd := Texts.Pos(R)-1;
		F.do.LocatePos(F, linkEnd, loc2);
		loc.x := loc1.x; loc.pos := pos+1;
		loc.dx := loc2.x-loc1.x
	END LocateString;

(** Parsing of an file url. *)
	PROCEDURE SplitFileAdr*(VAR url, path, label: ARRAY OF CHAR): LONGINT;
		VAR
			prefix: ARRAY 8 OF CHAR;
			key, i, j, l: LONGINT;
			iskey: BOOLEAN;
		PROCEDURE Blanks();
		BEGIN
			WHILE (url[i] # 0X) & (url[i] <= " ") DO
				INC(i)
			END
		END Blanks;
	BEGIN
		(* Pre: url must be a file url *)
		i := 0;
		Blanks();
		(* skip file *)
		j := 0;
		WHILE (url[i] # 0X) & (url[i] # ":") DO
			IF (j < 7) & Strings.IsAlpha(url[i]) THEN
				prefix[j] := CAP(url[i]); INC(j)
			END;
			INC(i)
		END; prefix[j] := 0X;
		(* skip :// *) l := 0;
		IF (url[i] = ":") & (prefix = "FILE") THEN
			INC(i);
			Blanks();
			WHILE (url[i] # 0X) & (url[i] = "/") DO
				INC(l); INC(i)
			END;
			IF Strings.IsAlpha(url[i]) & (url[i+1] = "|") THEN
				path[0] := url[i]; path[1] := ":"; path[2] := "/"; path[3] := 0X;
				j := 3; INC(i, 2); l := MAX(INTEGER)
			END
		ELSE
			i := 0 (* url has no "file:" prefix *)
		END;
		Blanks();
		IF l < MAX(INTEGER) THEN
			j := i;
			IF l >= 2 THEN
				path[0] := "/"; j := 1
			ELSE
				j := 0
			END
		END;
		(* get path *)
		iskey := TRUE;
		l := LEN(path)-1;
		WHILE (url[i] # 0X) & (url[i] # "#")  & (url[i] # "?")DO
			IF (url[i] > " ") & ~Strings.IsDigit(url[i]) THEN
				iskey := FALSE
			END;
			IF j < l THEN
				path[j] := url[i]; INC(j)
			END;
			INC(i)
		END;
		path[j] := 0X;
		DEC(j);
		WHILE (j >= 0) & (path[j] <= " ") DO
			path[j] := 0X; DEC(j)
		END;
		IF (url[i] = 0X) & iskey THEN
			IF path # "" THEN
				Strings.StrToInt(path, key);
				RetrieveLink(key, link);
				key := SplitFileAdr(link, path, label);
				RETURN key
			ELSE
				RETURN UndefKey
			END
		END;
		(* get label *)
		IF (url[i] = "#") OR (url[i] = "?") THEN
			INC(i); Blanks();
			l := LEN(label)-1;
			j := 0;
			WHILE (url[i] # 0X) DO
				IF j < l THEN
					label[j] := url[i]; INC(j)
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
		COPY("file:", url);
		IF path # "" THEN
			IF path[0] = "/" THEN
				Strings.AppendCh(url, "/")
			END;
			Strings.Append(url, path);
			IF label # "" THEN
				Strings.AppendCh(url, "#");
				Strings.Append(url, label)
			END
		END;
		key := RegisterLink(url);
		RETURN key
	END SplitFileAdr;

	PROCEDURE DecPath(VAR path, dpath: ARRAY OF CHAR);
		VAR i, slash, lslash: INTEGER;
	BEGIN
		slash := -1; lslash := -2; i := 0;
		WHILE path[i] # 0X DO
			IF path[i] = "/" THEN
				lslash := slash; slash := i
			END;
			INC(i)
		END;
		COPY(path, dpath);
		IF lslash >= 0 THEN
			dpath[lslash+1] := 0X
		ELSIF slash > 0 THEN
			dpath[0] := 0X
		ELSE
			dpath[0] := "/"; dpath[1] := 0X
		END
	END DecPath;

(** Make an absolute url out of value using base. *) 
	PROCEDURE Path*(base: DefURL; VAR url, value: ARRAY OF CHAR);
		VAR
			i, j, k, l: LONGINT;
			dpath: ARRAY PathStrLen OF CHAR;
	BEGIN
		i := 0; k := -1;
		WHILE url[i] # 0X DO
			IF url[i] = "/" THEN
				k := i
			END;
			INC(i)
		END;
		l := 0; j := -1;
		WHILE value[l] # 0X DO
			IF value[l] = ":" THEN
				j := l
			END;
			INC(l)
		END;
		IF j > 2 THEN (* rel. URL prefix *)
			INC(j)
		ELSE
			j := 0
		END;
		IF (value[j] = "/") OR (value[j] = "~") THEN
			IF value[j] = "~" THEN
				url[i] := "/"; INC(i)
			END;
			WHILE value[j] # 0X DO
				url[i] := value[j]; INC(i); INC(j)
			END;
			url[i] := 0X
		ELSIF (value[j] = ".") & (value[j+1] = ".") THEN
			DecPath(base.path, dpath); INC(j, 3);
			WHILE (value[j] = ".") & (value[j+1] = ".") DO
				DecPath(dpath, dpath); INC(j, 3)
			END;
			k := 0;
			WHILE dpath[k] # 0X DO
				url[i] := dpath[k]; INC(i); INC(k)
			END;
			WHILE value[j] # 0X DO
				url[i] := value[j]; INC(i); INC(j)
			END;
			url[i] := 0X
		ELSE
			l := 0;
			WHILE base.path[l] # 0X DO
				url[i] := base.path[l];
				IF url[i] = "/" THEN
					k := i
				END;
				INC(i); INC(l)
			END;
			IF k > 0 THEN
				i := k+1
			END;
			IF (value[j] = ".") & (value[j+1] = "/") THEN
				INC(j, 2)
			END;
			WHILE value[j] # 0X DO
				url[i] := value[j]; INC(i); INC(j)
			END;
			url[i] := 0X
		END
	END Path;

(** Checks if link is preceeded by a valid scheme-prefix. *)
	PROCEDURE CheckPrefix*(VAR link: ARRAY OF CHAR): LONGINT;
		VAR
			i, j, p: LONGINT;
			prefix: ARRAY PrefixStrLen OF CHAR;
			s: LinkScheme;
	BEGIN
		p := -1; j := 0; i := 0;
		WHILE (link[i] # 0X) & (link[i] # ":") DO
			IF j < (PrefixStrLen-1) THEN
				prefix[j] := link[i]; INC(j)
			END;
			INC(i)
		END;
		IF link[i] = ":" THEN
			p := 0; prefix[j] := 0X;
			s := LinkSchemeByPrefix(prefix);
			IF (s # NIL) & s.usePath THEN
				INC(i);
				WHILE (link[i] # 0X) & (link[i] <= " ") DO
					INC(i)
				END;
				WHILE link[i] = "/" DO
					INC(p); INC(i)
				END
			ELSIF s = NIL THEN
				p := -1
			END
		END;
		RETURN p
	END CheckPrefix;

	PROCEDURE *FileSchemeHandler(L: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			path, label: ARRAY 64 OF CHAR;
			F: Files.File;
			R: Files.Rider;
			ch: CHAR;
	BEGIN
		WITH L: LinkScheme DO
			IF M IS RegisterLinkMsg THEN
				WITH M: RegisterLinkMsg DO
					IF (M.base = NIL) OR (CheckPrefix(M.link) >= 0) THEN
						M.key := SplitFileAdr(M.link, link, label)
					ELSIF M.base.prefix = "file" THEN
						link := "file:";
						cmpBuf := ""; Path(M.base, cmpBuf, M.link);
						IF cmpBuf[0] = "/" THEN
							Strings.AppendCh(link, "/")
						END;
						Strings.Append(link, cmpBuf);
						M.key := RegisterLink(link)
					ELSE
						LinkSchemeHandler(L, M)
					END;
					IF M.key # UndefKey THEN
						M.res := 0
					END
				END
			ELSIF M IS InfoMsg THEN
				WITH M: InfoMsg DO
					RetrieveLink(M.key, link);
					M.key := SplitFileAdr(link, path, label);
					M.contType := MIME.GetContentType("application/oberondoc");
					F := Files.Old(path);
					IF F # NIL THEN
						M.size := Files.Length(F);
						Files.GetDate(F, M.time, M.date)
					ELSE
						M.time := 0; M.date := 0; M.size := 0
					END;
					M.res := 0
				END
			ELSIF M IS FetchMsg THEN
				WITH M: FetchMsg DO
					IF M.key # UndefKey THEN
						RetrieveLink(M.key, link);
						M.key := SplitFileAdr(link, path, label);
						F := Files.Old(path);
						IF F # NIL THEN
							Files.Set(R, F, 0);
							Files.Read(R, ch);
							WHILE ~R.eof DO
								Files.Write(M.R, ch);
								Files.Read(R, ch)
							END;
							M.res := 0
						END
					ELSE
						M.res := 0
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.class := Objects.String;
						M.s := "HyperDocs.NewLinkScheme";
						M.res := 0
					ELSE
						LinkSchemeHandler(L, M)
					END
				END
			ELSE
				LinkSchemeHandler(L, M)
			END
		END
	END FileSchemeHandler;

	PROCEDURE NewLinkScheme*;
		VAR L: LinkScheme;
	BEGIN
		NEW(L); L.handle := FileSchemeHandler;
		L.usePath := TRUE;
		Objects.NewObj := L
	END NewLinkScheme;

	PROCEDURE *LoadDoc(D: Documents.Document);
		VAR
			key: LONGINT;
			path, label: ARRAY 64 OF CHAR;
			D2: Documents.Document;
			new: Node;
	BEGIN
		key := SplitFileAdr(D.name, path, label);
		IF key # UndefKey THEN
			loadingKey := key;
			D2 := Open(path);
			IF (D2 # NIL) & (D2.dsc # NIL) THEN
				D^ := D2^; D.lib := NIL; D.ref := -1;
				IF context = NIL THEN
					Remember(key, NIL, new);
					LinkNodeToDoc(D, new)
				ELSE
					context.history := TRUE
				END
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

	PROCEDURE CacheText*(key: LONGINT; text: Texts.Text);
		VAR
			R: Files.Rider;
			org, len: LONGINT;
			res: INTEGER;
	BEGIN
		BTrees.SearchLInt(keysIndex, key, org, res);
		IF res = BTrees.Done THEN
			IF text # NIL THEN
				Files.Set(R, linksFile, org);
				Files.ReadLInt(R, org); (* key *)
				org := Files.Length(diskCache);
				Files.WriteLInt(R, org); (* cache *)
				len := 0; Texts.Store(text, diskCache, org, len)
			ELSE
				Files.Set(R, linksFile, org);
				Files.ReadLInt(R, org); (* key *)
				Files.WriteLInt(R, -2) (* cache *)
			END
		END
	END CacheText;

(** Add doc to the document cache. If the system is running out of memory documents in the cache are thrown
		away. Cache entries marked as writeBack are written to disk. *)
	PROCEDURE CacheDoc*(key: LONGINT; doc: Documents.Document);
		VAR
			C: Objects.CopyMsg;
			B: Objects.BindMsg;
			cdoc: Documents.Document;
			F: Display.Frame;
			oldLib, newLib: Objects.Library;
			R: Files.Rider;
			org, len: LONGINT;
			oldRef, res: INTEGER;
	BEGIN
		BTrees.SearchLInt(keysIndex, key, org, res);
		IF res = BTrees.Done THEN
			IF (doc # NIL) & (doc.dsc # NIL) THEN
				NEW(cdoc); cdoc.handle := doc.handle; cdoc.dsc := NIL;
				C.id := Objects.shallow; C.obj := NIL; C.dlink := NIL; Objects.Stamp(C);
				Documents.Copy(C, doc, cdoc); F := doc.dsc;
				oldLib := F.lib; oldRef := F.ref; F.lib := NIL; F.ref := -1;
				Files.Set(R, linksFile, org);
				Files.ReadLInt(R, org); (* key *)
				org := Files.Length(diskCache);
				Files.WriteLInt(R, org); (* cache *)
				NEW(newLib); Objects.OpenLibrary(newLib);
				B.lib := newLib; Objects.Stamp(B); B.dlink := NIL;
				cdoc.handle(cdoc, B); F.handle(F, B);
				Files.Set(R, diskCache, org); Files.WriteInt(R, cdoc.ref); Files.WriteInt(R, F.ref);
				len := 0; Objects.StoreLibrary(newLib, diskCache, Files.Pos(R), len);
				F.lib := oldLib; F.ref := oldRef
			ELSE
				Files.Set(R, linksFile, org);
				Files.ReadLInt(R, org); (* key *)
				Files.WriteLInt(R, -2) (* cache *)
			END
		END
	END CacheDoc;

	PROCEDURE Reload*;
		VAR
			D: Documents.Document;
			node: Node;
			docName: ARRAY 64 OF CHAR;
			key: LONGINT;
	BEGIN
		D := Desktops.CurDoc(Gadgets.context);
		node := NodeByDoc(D);
		IF node # NIL THEN
			CacheDoc(node.key, NIL);
			Attributes.GetInt(D, "DocURL", key);
			IF key > 0 THEN
				node.key := key;
				CacheDoc(node.key, NIL)
			END;
			node.org := 0;
			DocNameByKey(docName, node.key);
			loadingKey := node.key;
			D := Open(docName);
			IF (D # NIL) & (D.dsc # NIL) THEN
				LinkNodeToDoc(D, node);
				Desktops.ReplaceCurrentDoc(D)
			END
		END
	END Reload;

(** Retrieve a document from the document cache. *)
	PROCEDURE GetCachedDoc*(key: LONGINT): Documents.Document;
		VAR
			R: Files.Rider;
			org, len: LONGINT;
			obj: Objects.Object;
			res, refd, reff: INTEGER;
			lib: Objects.Library;
			doc: Documents.Document;
			tag: CHAR;
	BEGIN
		doc := NIL; BTrees.SearchLInt(keysIndex, key, org, res);
		IF res = BTrees.Done THEN
			Files.Set(R, linksFile, org);
			Files.ReadLInt(R, org); (* key *)
			Files.ReadLInt(R, org); (* cache *)
			IF org >= 0 THEN
				Files.Set(R, diskCache, org);
				Files.ReadInt(R, refd); Files.ReadInt(R, reff);
				NEW(lib); Objects.OpenLibrary(lib);
				Files.Read(R, tag);
				IF tag # Objects.LibBlockId THEN
					RETURN NIL
				END;
				org := Files.Pos(R);
				Objects.LoadLibrary(lib, diskCache, org, len);
				lib.GetObj(lib, refd, obj);
				doc := obj(Documents.Document);
				lib.GetObj(lib, reff, obj);
				doc.dsc := obj(Gadgets.Frame);
				IF doc.dsc IS TextGadgets.Frame THEN
					Links.GetLink(doc.dsc, "Picture", obj);
					IF obj # NIL THEN
						doc.dsc(TextGadgets.Frame).do := linkPictMethods
					ELSE
						doc.dsc(TextGadgets.Frame).do := linkMethods
					END
				END
			END
		END;
		RETURN doc
	END GetCachedDoc;

	PROCEDURE GetCachedText*(key: LONGINT): Texts.Text;
		VAR
			R: Files.Rider;
			org, len: LONGINT;
			text: Texts.Text;
			res: INTEGER;
			tag: CHAR;
	BEGIN
		text := NIL; BTrees.SearchLInt(keysIndex, key, org, res);
		IF res = BTrees.Done THEN
			Files.Set(R, linksFile, org);
			Files.ReadLInt(R, org); (* key *)
			Files.ReadLInt(R, org); (* cache *)
			IF org >= 0 THEN
				Files.Set(R, diskCache, org);
				Files.Read(R, tag);
				IF tag # Texts.TextBlockId THEN
					RETURN NIL
				END;
				NEW(text); len := 0; org := Files.Pos(R);
				Texts.Load(text, diskCache, org, len)
			END
		END;
		RETURN text
	END GetCachedText;

(** All documents in the cache are released. *)
	PROCEDURE ClearCache*;
		VAR
			R: Files.Rider;
			key, org, min, max, cache: LONGINT;
			res: INTEGER;
	BEGIN
		diskCache := Files.New("");
		BTrees.MinLIntKey(keysIndex, min, res);
		BTrees.MaxLIntKey(keysIndex, max, res);
		IF res = BTrees.Done THEN
			FOR key := min TO max DO
				BTrees.SearchLInt(keysIndex, key, org, res);
				IF res = BTrees.Done THEN
					Files.Set(R, linksFile, org);
					Files.ReadLInt(R, org); (* key *)
					Files.ReadLInt(R, cache); (* cache *)
					IF cache >= 0 THEN
						Files.Set(R, linksFile, Files.Pos(R)-4);
						Files.WriteLInt(R, -2)
					END
				END
			END
		END
	END ClearCache;

	PROCEDURE *Background(F: TextGadgets0.Frame; R: Display3.Mask; X, Y, x, y, w, h: INTEGER);
		VAR
			pict: Objects.Object;
			cx, cy, cw, ch, px, py, pw, ph: INTEGER;
	BEGIN
		Links.GetLink(F, "Picture", pict);
		cx := R.X; cy := R.Y; cw := R.W; ch := R.H;
		Display3.AdjustMask(R, X + x, Y + F.H - 1 + y, w, h);
		Oberon.RemoveMarks(R.X, R.Y, R.W, R.H);
		IF (pict # NIL) & (pict IS Pictures.Picture) THEN
			WITH pict: Pictures.Picture DO
				pw := pict.width; ph := pict.height;
				IF (pw > 0) & (ph > 0) THEN
					px := X;
					WHILE px < (X+F.W) DO
						py := Y+F.H;
						WHILE py > Y DO
							DEC(py, ph);
							Display3.Pict(R, pict, 0, 0, pw, ph, px, py, Display.replace)
						END;
						INC(px, pw)
					END
				ELSE
					Display3.ReplConst(R, F.col, X, Y, F.W, F.H, Display.replace)
				END
			END
		ELSE
			Display3.ReplConst(R, F.col, X, Y, F.W, F.H, Display.replace)
		END;
		R.X := cx; R.Y := cy; R.W := cw; R.H := ch
	END Background;

	PROCEDURE Visited*(key: LONGINT): BOOLEAN;
		VAR
			R: Files.Rider;
			org: LONGINT;
			res: INTEGER;
	BEGIN
		BTrees.SearchLInt(keysIndex, key, org, res);
		IF res = BTrees.Done THEN
			Files.Set(R, linksFile, org);
			Files.ReadLInt(R, org); (* key *)
			Files.ReadLInt(R, org); (* cache *)
			RETURN org # -1
		ELSE
			RETURN FALSE
		END
	END Visited;

	PROCEDURE InitIndex(new: BOOLEAN);
		VAR
			R: Files.Rider;
			org: LONGINT;
			W: Texts.Writer;
			res: INTEGER;
	BEGIN
		linksFile := Files.Old("URL.DB");
		IF (linksFile = NIL) OR new THEN
			IF keepurls THEN
				Texts.OpenWriter(W);
				Texts.WriteString(W, "HyperDocs: Creating URL.DB"); 
				Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
			END;
			linksFile := Files.New("URL.DB");
			Files.Set(R, linksFile, 0);
			curKey := 0; Files.WriteLInt(R, -curKey-1);
			Files.WriteLInt(R, -1); Files.WriteLInt(R, -1);
			linksIndex := BTrees.NewStr(linksFile, 12, 100);
			org := Files.Length(linksFile);
			keysIndex := BTrees.NewLInt(linksFile, org, 100);
			Files.Set(R, linksFile, 4);
			Files.WriteLInt(R, 12); Files.WriteLInt(R, org);
			IF keepurls THEN Files.Register(linksFile) END
		ELSE
			Files.Set(R, linksFile, 0);
			Files.ReadLInt(R, curKey);
			IF (curKey < 0) OR ~keepurls THEN
				Files.Rename("URL.DB", "URL.DB.Bak", res);
				InitIndex(TRUE)
			ELSE
				Files.Set(R, linksFile, 0);
				Files.WriteLInt(R, -curKey-1);
				Files.ReadLInt(R, org);
				linksIndex := BTrees.Old(linksFile, org);
				Files.ReadLInt(R, org);
				keysIndex := BTrees.Old(linksFile, org)
			END
		END
	END InitIndex;

	PROCEDURE *FreeMod();
		VAR R: Files.Rider;
	BEGIN
		Files.Set(R, linksFile, 0);
		Files.WriteLInt(R, curKey);
		BTrees.Flush(linksIndex); BTrees.Flush(keysIndex);
		Files.Close(linksFile)
	END FreeMod;

PROCEDURE Init;
VAR S: Texts.Scanner;  W: Texts.Writer;
BEGIN
	Oberon.OpenScanner(S, "LinkSchemes");
	IF S.class = Texts.Inval THEN
		Texts.OpenWriter(W);
		Texts.WriteString(W, "Oberon.Text - LinkSchemes not found");
		Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf)
	END;
	Oberon.OpenScanner(S, "NetSystem.KeepURLs");
	IF (S.class = Texts.Name) OR (S.class = Texts.String) THEN
		keepurls := CAP(S.s[0]) = "Y"
	ELSE
		keepurls := FALSE
	END
END Init;

BEGIN
	Init;
	linkSchemes := NIL;
	curKey := 0; diskCache := Files.New("");
	InitIndex(FALSE);
	curID := 0; history := NIL; context := NIL;
	linkC := Display3.blue; oldLinkC := 17;
	NEW(linkMethods);
	linkMethods^ := TextGadgets.methods^;
	linkMethods.LocateString := LocateString;
	NEW(linkPictMethods);
	linkPictMethods ^ := linkMethods^;
	linkPictMethods.Background := Background;
	ClearCache();
	Modules.InstallTermHandler(FreeMod);
	(*docW := Oberon.SystemTrack(0)-Oberon.UserTrack(0); docH := Display.Height-Desktops.menuH*)
	docW := Display.Width*5 DIV 8;
	docH := Display.Height*7 DIV 8
END HyperDocs.
