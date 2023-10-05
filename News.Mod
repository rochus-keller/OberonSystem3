(* OBERON System 3, Release 2.3.

Copyright 1999 ETH Zürich Institute for Computer Systems, 
ETH Center, CH-8092 Zürich.  e-mail: oberon@inf.ethz.ch.

This module may be used under the conditions of the general Oberon 
System 3 license contract.  The full text can be downloaded from

	"ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/license.txt;A"

Under the license terms stated it is in particular (a) prohibited to modify
the interface of this module in any way that disagrees with the style
or content of the system and (b) requested to provide all conversions
of the source code to another platform with the name OBERON. *)

MODULE News; (** portable *)	(* ejz,   *)
	IMPORT BTrees, Strings, HyperDocs, Files, Objects, Texts, Display, Fonts, Display3, Oberon, NetSystem, NetTools, Gadgets,
		Attributes, TextGadgets, TextDocs, Documents, Desktops, Links, Modules, MIME, Streams, TextStreams, Mail, Dates;

(** This module implements a newsreader (RFC 977, 1036) for oberon. The News-modul supports news and nntp urls.
		The nntp host is specified in the NetSystem section of the Registry (e.g. NNTP=news.inf.ethz.ch).
		The following lines should be added to the LinkSchemes section of the Registry:
			nntp = News.NewNNTPLinkScheme
			news = News.NewNewsLinkScheme
		And the following lines to the Documents section:
			nntp News.NewDoc
			news News.NewDoc.
		For sending or posting new articles your e-mail address should be defined in the NetSystem section of the Registry.
		e.g.: EMail = "me@home" *)

	CONST
		DefPort = 119;
		InitText = "News.Read.Text";
		Done* = NetTools.Done;
		ErrGroup* = 1;
		ErrXOver* = 2;
		ErrArticle* = 3;
		ErrStat* = 4;
		ErrList* = 5;
		ErrPost* = 6;
		Failed* = NetTools.Failed;
		MaxMessages = 16*1024;

	TYPE
		ArtNrs = POINTER TO ArtNrsDesc;
		ArtNrsDesc = RECORD
			beg, end: LONGINT;
			next: ArtNrs
		END;
		Group = POINTER TO GroupDesc;
		GroupDesc = RECORD
			name: ARRAY 128 OF CHAR;
			subscribed: BOOLEAN;
			readArtNrs: ArtNrs;
			next: Group
		END;
(** The connection to an nntp. *)
		Session* = POINTER TO SessionDesc;
		SessionDesc* = RECORD (Mail.SMTPSessionDesc)
		END;

	VAR
		W, Wr: Texts.Writer;
		groups, curGrp: Group;
		curGrpNewOnly: BOOLEAN;
		newgDate, newgTime: LONGINT;
		EMail: ARRAY NetTools.ServerStrLen OF CHAR;
		refs: Files.File;
		indexM, indexA: BTrees.Tree;
		availBeg, beg, end, level, thread: LONGINT;
		marked: POINTER TO ARRAY OF BOOLEAN;
		line: ARRAY 2*NetTools.MaxLine OF CHAR;
		newsFont: Fonts.Font;

	PROCEDURE ScanInt(VAR S: Texts.Scanner; VAR i: INTEGER);
	BEGIN
		IF S.class = Texts.Int THEN
			i := SHORT(S.i);
			Texts.Scan(S)
		ELSE
			i := 0
		END
	END ScanInt;

	PROCEDURE ScanDate(VAR S: Texts.Scanner; VAR date: LONGINT);
		VAR day, month, year: INTEGER;
	BEGIN
		ScanInt(S, day); ScanInt(S, month); ScanInt(S, year);
		IF year < 100 THEN
			IF (month = 0) OR (day = 0) THEN
				year := 1980; month := 1; day := 1
			ELSE
				year := year + 1900
			END
		END;
		date := Dates.ToDate(year, month, day)
	END ScanDate;

	PROCEDURE ScanTime(VAR S: Texts.Scanner; VAR time: LONGINT);
		VAR hour, min, sec: INTEGER;
	BEGIN
		ScanInt(S, hour); ScanInt(S, min); ScanInt(S, sec);
		time := Dates.ToTime(hour, min, sec)
	END ScanTime;

	PROCEDURE TwoDigit(i: INTEGER; VAR str: ARRAY OF CHAR);
	BEGIN
		str[0] := CHR((i DIV 10)+ORD("0"));
		str[1] := CHR((i MOD 10)+ORD("0"));
		str[2] := 0X
	END TwoDigit;

	PROCEDURE ConcatDate(VAR line: ARRAY OF CHAR; VAR date: LONGINT);
		VAR
			str: ARRAY 8 OF CHAR;
			day, month, year: INTEGER;
	BEGIN
		Dates.ToYMD(date, year, month, day);
		IF year < 2000 THEN
			TwoDigit(year MOD 100, str)
		ELSE
			Strings.IntToStr(year, str)	
		END;
		Strings.Append(line, str);
		TwoDigit(month, str);
		Strings.Append(line, str);
		TwoDigit(day, str);
		Strings.Append(line, str)
	END ConcatDate;

	PROCEDURE ConcatTime(VAR line: ARRAY OF CHAR; VAR time: LONGINT);
		VAR
			str: ARRAY 8 OF CHAR;
			hour, min, sec: INTEGER;
	BEGIN
		Dates.ToHMS(time, hour, min, sec);
		TwoDigit(hour, str);
		Strings.Append(line, str);
		TwoDigit(min, str);
		Strings.Append(line, str);
		TwoDigit(sec, str);
		Strings.Append(line, str)
	END ConcatTime;

	PROCEDURE LoadInitText();
		VAR
			text: Texts.Text;
			S: Texts.Scanner;
			group, lastg: Group;
			art, last: ArtNrs;
			i: LONGINT;
			val: ARRAY 64 OF CHAR;
	BEGIN
		IF NetTools.QueryString("NewsFont", val) & (Fonts.This(val) # NIL) THEN
			newsFont := Fonts.This(val)
		ELSE
			newsFont := Fonts.Default
		END;
		groups := NIL; lastg := NIL;
		NEW(text); Texts.Open(text, InitText);
		Texts.OpenScanner(S, text, 0); Texts.Scan(S);
		ScanDate(S, newgDate); ScanTime(S, newgTime);
		WHILE ~S.eot DO
			NEW(group);
			IF (S.class = Texts.Char) & (S.c = "!") THEN
				group.subscribed := FALSE;
				Texts.Scan(S)
			ELSE
				group.subscribed := TRUE
			END;
			IF S.class IN {Texts.Name, Texts.String} THEN
				COPY(S.s, group.name);
				i := 0;
				WHILE group.name[i] # 0X DO
					INC(i)
				END;
				IF group.name[i-1] = ":" THEN
					group.name[i-1] := 0X
				END;
				group.next := NIL;
				IF lastg # NIL THEN
					lastg.next := group
				ELSE
					groups := group
				END;
				lastg := group;
				group.readArtNrs := NIL; last := NIL;
				Texts.Scan(S);
				IF ((S.class = Texts.Char) & (S.c = ":")) OR ((S.class IN {Texts.Name, Texts.String}) & (S.s = ":")) THEN
					Texts.Scan(S)
				END;
				WHILE ~S.eot & (S.class = Texts.Int) DO
					NEW(art); art.next := NIL;
					IF last = NIL THEN
						group.readArtNrs := art
					ELSE
						last.next := art
					END;
					last := art;
					art.beg := S.i; Texts.Scan(S);
					IF ((S.class = Texts.Char) & (S.c = "-")) OR ((S.class IN {Texts.Name, Texts.String}) & (S.s = "-")) THEN
						Texts.Scan(S);
						IF S.class = Texts.Int THEN
							art.end := S.i;
							Texts.Scan(S)
						ELSE
							art.end := art.beg
						END
					ELSIF (S.class = Texts.Int) & (S.i < 0) THEN
						art.end := -S.i;
						Texts.Scan(S)
					ELSE
						art.end := art.beg
					END;
					IF (S.class = Texts.Char) & (S.c = ",") THEN
						Texts.Scan(S)
					END
				END
			ELSE
				Texts.Scan(S)
			END
		END
	END LoadInitText;

	PROCEDURE WriteDate(VAR W: Texts.Writer; VAR date: LONGINT);
		VAR day, month, year: INTEGER;
	BEGIN
		Dates.ToYMD(date, year, month, day);
		Texts.WriteInt(W, day, 0);
		Texts.Write(W, " ");
		Texts.WriteInt(W, month, 0);
		Texts.Write(W, " ");
		Texts.WriteInt(W, year, 0)
	END WriteDate;

	PROCEDURE WriteTime(VAR W: Texts.Writer; VAR time: LONGINT);
		VAR hour, min, sec: INTEGER;
	BEGIN
		Dates.ToHMS(time, hour, min, sec);
		Texts.WriteInt(W, hour, 0);
		Texts.Write(W, " ");
		Texts.WriteInt(W, min, 0);
		Texts.Write(W, " ");
		Texts.WriteInt(W, sec, 0)
	END WriteTime;

	PROCEDURE *storeInitText();
		VAR
			text: Texts.Text;
			group: Group;
			article, nextart: ArtNrs;
			F: Files.File;
			len: LONGINT;
	BEGIN
		NEW(text); Texts.Open(text, "");
		WriteDate(W, newgDate);
		Texts.Write(W, " ");
		WriteTime(W, newgTime);
		Texts.WriteLn(W);
		group := groups;
		WHILE group # NIL DO
			IF ~group.subscribed THEN
				Texts.Write(W, "!")
			END;
			len := 0;
			WHILE (group.name[len] # 0X) & (Strings.IsAlpha(group.name[len]) OR (group.name[len] = ".")) DO
				INC(len)
			END;
			IF group.name[len] # 0X THEN
				Texts.Write(W, 22X);
				Texts.WriteString(W, group.name);
				Texts.Write(W, 22X)
			ELSE
				Texts.WriteString(W, group.name)
			END;
			Texts.WriteString(W, ": ");
			article := group.readArtNrs;
			WHILE article # NIL DO
				nextart := article.next;
				Texts.WriteInt(W, article.beg, 0);
				IF (nextart # NIL) & (nextart.beg = (article.end+1)) THEN
					Texts.WriteString(W, " - ");
					Texts.WriteInt(W, nextart.end, 0);
					nextart := nextart.next
				ELSIF article.end > article.beg THEN
					Texts.WriteString(W, " - ");
					Texts.WriteInt(W, article.end, 0)
				END;
				article := nextart;
				IF article # NIL THEN
					Texts.WriteString(W, ", ")
				END
			END;
			Texts.WriteLn(W);
			group := group.next
		END;
		Texts.Append(text, W.buf);
		F := Files.New(InitText);
		Texts.Store(text, F, 0, len);
		Files.Register(F)
	END storeInitText;

(** News.StoreInitText
		Store information on read articles and subscribed groups. *)
	PROCEDURE StoreInitText*;
	BEGIN
		Texts.WriteString(W, "Store ");
		Texts.WriteString(W, InitText);
		Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf);
		storeInitText()
	END StoreInitText;

	PROCEDURE AddArtNr(group: Group; nr: LONGINT);
		VAR prev, cur, art: ArtNrs;
	BEGIN
		IF group.readArtNrs = NIL THEN
			NEW(cur);
			cur.beg := nr;
			cur.end := nr;
			cur.next := NIL;
			group.readArtNrs := cur
		ELSE
			prev := group.readArtNrs;
			cur := group.readArtNrs;
			WHILE (cur # NIL) & (cur.beg <= nr) DO
				prev := cur;
				cur := cur.next
			END;
			IF (prev.beg-1) = nr THEN
				prev.beg := nr
			ELSIF (prev.end+1) = nr THEN
				prev.end := nr
			ELSIF nr < prev.beg THEN
				NEW(cur);
				cur.beg := nr;
				cur.end := nr;
				cur.next := prev;
				group.readArtNrs := cur
			ELSIF nr > prev.end THEN
				IF (cur # NIL) & (nr = (cur.beg-1)) THEN
					cur.beg := nr
				ELSE
					NEW(art);
					art.beg := nr;
					art.end := nr;
					prev.next := art;
					art.next := cur
				END
			END
		END
	END AddArtNr;

	PROCEDURE GetGroup(name: ARRAY OF CHAR; new: BOOLEAN): Group;
		VAR group: Group;
	BEGIN
		group := groups;
		WHILE (group # NIL) & (group.name # name) DO
			group := group.next
		END;
		IF (group = NIL) & new THEN
			NEW(group);
			COPY(name, group.name);
			group.subscribed := FALSE;
			group.readArtNrs := NIL;
			group.next := groups;
			groups := group
		END;
		RETURN group
	END GetGroup;

	PROCEDURE ReadArt(group: Group; nr: LONGINT): BOOLEAN;
		VAR article: ArtNrs;
	BEGIN
		article := group.readArtNrs;
		WHILE (article # NIL) & (article.beg <= nr) DO
			IF (nr >= article.beg) & (nr <= article.end) THEN
				RETURN TRUE
			END;
			article := article.next
		END;
		RETURN FALSE
	END ReadArt;

	PROCEDURE ReadResponse(S: Session);
		VAR i: LONGINT;
	BEGIN
		NetSystem.ReadString(S.C, S.reply);
		Strings.StrToInt(S.reply, i);
		S.status := SHORT(i)
	END ReadResponse;

(** Open a new session to nntp-host host on ort port. *)
	PROCEDURE Open*(VAR S: Session; host: ARRAY OF CHAR; port: INTEGER);
	BEGIN
		NEW(S);
		IF NetTools.Connect(S.C, port, host, FALSE) THEN
			ReadResponse(S);
			IF S.status # 200 THEN
				NetTools.Disconnect(S.C); S.C := NIL; S.S := NIL
			ELSE
				S.S := NetTools.OpenStream(S.C);
				S.res := Done; RETURN
			END
		ELSE
			S.reply := "no connection"
		END;
		S.res := Failed
	END Open;

(** Close the connection for session S. *)
	PROCEDURE Close*(S: Session);
	BEGIN
		IF S.C # NIL THEN
			NetTools.Disconnect(S.C); S.C := NIL; S.S := NIL
		END
	END Close;

	PROCEDURE Connect(VAR S: Session): BOOLEAN;
		VAR
			NNTPHost: ARRAY 64 OF CHAR;
			NNTPPort: INTEGER;
	BEGIN
		NetTools.GetHostPort("NNTP", NNTPHost, NNTPPort, DefPort);
		IF NNTPHost # "" THEN
			Open(S, NNTPHost, NNTPPort)
		ELSE
			NEW(S); S.C := NIL;
			S.reply := "NNTP-Host not set";
			S.res := Failed
		END;
		RETURN S.res = Done
	END Connect;

	PROCEDURE RegisterNewsAdr(host, group: ARRAY OF CHAR): LONGINT;
		VAR key: LONGINT;
	BEGIN
		COPY("news:", line);
		Strings.Append(line, group);
		IF host # "" THEN
			Strings.AppendCh(line, "@");
			Strings.Append(line, host)
		END;
		key := HyperDocs.RegisterLink(line);
		RETURN key
	END RegisterNewsAdr;

	PROCEDURE WriteGroup(VAR group: ARRAY OF CHAR);
		VAR
			i, key: LONGINT;
			link: Objects.Object;
	BEGIN
		Texts.SetColor(W, SHORT(HyperDocs.linkC));
		i := 0;
		WHILE (group[i] # 0X) & (group[i] > " ") DO
			Texts.Write(W, group[i]);
			INC(i)
		END;
		group[i] := 0X;
		key := RegisterNewsAdr("", group);
		link := HyperDocs.LinkControl(key);
		Texts.WriteObj(W, link);
		Texts.SetColor(W, SHORT(Display3.textC));
		Texts.WriteLn(W)
	END WriteGroup;

	PROCEDURE SubGroups(T: Texts.Text);
		VAR group: Group;
	BEGIN
		group := groups;
		WHILE group # NIL DO
			IF group.subscribed THEN
				WriteGroup(group.name)
			END;
			group := group.next
		END;
		Texts.Append(T, W.buf)
	END SubGroups;

(** Write al list of all available groups to T. *)
	PROCEDURE AllGroups*(S: Session; VAR T: Texts.Text);
	BEGIN
		NetSystem.WriteString(S.C, "LIST");
		ReadResponse(S);
		IF S.status = 215 THEN
			NEW(T); Texts.Open(T, "");
			NetSystem.ReadString(S.C, line);
			WHILE (line[0] # ".") OR (line[1] # 0X) DO
				Texts.WriteString(W, "news:"); Texts.WriteString(W, line); Texts.WriteLn(W);
				NetSystem.ReadString(S.C, line)
			END;
			Texts.Append(T, W.buf);
			S.res := Done
		ELSE
			T := NIL;
			S.res := ErrList
		END
	END AllGroups;

(** List all new groups since the last access. *)
	PROCEDURE NewGroups*(S: Session; date, time: LONGINT; VAR T: Texts.Text);
	BEGIN
		line := "NEWGROUPS ";
		ConcatDate(line, date);
		Strings.AppendCh(line, " ");
		ConcatTime(line, time);
		NetSystem.WriteString(S.C, line);
		ReadResponse(S);
		IF S.status = 231 THEN
			NEW(T); Texts.Open(T, "");
			NetSystem.ReadString(S.C, line);
			WHILE (line[0] # ".") OR (line[1] # 0X) DO
				Texts.WriteString(W, "news:"); Texts.WriteString(W, line); Texts.WriteLn(W);
				NetSystem.ReadString(S.C, line)
			END;
			Texts.Append(T, W.buf);
			S.res := Done
		ELSE
			T := NIL;
			S.res := ErrList
		END
	END NewGroups;

	PROCEDURE NewGrp(S: Session; VAR T: Texts.Text);
		VAR time, date: LONGINT;
	BEGIN
		Oberon.GetClock(time, date);
		NewGroups(S, newgDate, newgTime, T);
		IF S.res = Done THEN
			newgDate := date; newgTime := time
		END
	END NewGrp;

	PROCEDURE HorzRule(): Objects.Object;
		VAR obj: Objects.Object;
	BEGIN
		obj := Gadgets.CreateObject("BasicFigures.NewRect3D");
		Attributes.SetBool(obj, "Filled", TRUE);
		Attributes.SetInt(obj, "Color", Display3.textbackC);
		Gadgets.ModifySize(obj(Display.Frame), Display.Width, 4);
		RETURN obj
	END HorzRule;

	PROCEDURE WriteGrpHead(group: ARRAY OF CHAR);
	BEGIN
		Texts.Write(Wr, 22X);
		Texts.WriteString(Wr, "news:");
		Texts.WriteString(Wr, group);
		Texts.Write(Wr, 22X);
		Texts.WriteLn(Wr);
		Texts.WriteObj(Wr, HorzRule());
		Texts.WriteLn(Wr)
	END WriteGrpHead;

	PROCEDURE RegisterNNTPAdr(group: ARRAY OF CHAR; artnr: LONGINT): LONGINT;
		VAR
			line: ARRAY NetTools.MaxLine OF CHAR;
			str: ARRAY 12 OF CHAR;
			key: LONGINT;
	BEGIN
		COPY("nntp:", line);
		Strings.Append(line, group);
		Strings.AppendCh(line, "/");
		Strings.IntToStr(artnr, str);
		Strings.Append(line, str);
		key := HyperDocs.RegisterLink(line);
		RETURN key
	END RegisterNNTPAdr;

	PROCEDURE WriteArticle(nr: LONGINT; VAR line: ARRAY OF CHAR);
		VAR
			link: Objects.Object;
			i, key: LONGINT;
	BEGIN
		IF nr >= availBeg THEN
			IF ~ReadArt(curGrp, nr) THEN
				Texts.SetColor(Wr, SHORT(Display3.red))
			ELSE
				Texts.SetColor(Wr, SHORT(HyperDocs.linkC))
			END
		ELSE
			Texts.SetColor(Wr, SHORT(Display3.textC))
		END;
		i := 0;
		WHILE line[i] # 0X DO
			Texts.Write(Wr, line[i]);
			IF (line[i] = Strings.Tab) & (Wr.col # Display3.textC) THEN
				key := RegisterNNTPAdr(curGrp.name, nr);
				link := HyperDocs.LinkControl(key);
				Texts.WriteObj(Wr, link);
				Texts.SetColor(Wr, SHORT(Display3.textC))
			END;
			INC(i)
		END;
		Texts.WriteLn(Wr);
		Texts.SetColor(Wr, SHORT(Display3.textC))
	END WriteArticle;

	PROCEDURE ListArts(T: Texts.Text);
		VAR
			R: Files.Rider;
			key, org: LONGINT;
	BEGIN
		Files.Set(R, refs, 0);
		Files.ReadLInt(R, org);
		WHILE ~R.eof DO
			Files.ReadLInt(R, key);
			Files.Set(R, refs, org);
			Files.ReadString(R, line);
			WriteArticle(key, line);
			Texts.Insert(T, 0, Wr.buf);
			Files.ReadLInt(R, org)
		END
	END ListArts;

	PROCEDURE *enumThread(key, org: LONGINT; VAR cont: BOOLEAN);
		VAR
			R: Files.Rider;
			sorg, app, i, oldThread: LONGINT;
			inthread: BOOLEAN;
	BEGIN
		inthread := FALSE;
		Files.Set(R, refs, org);
		Files.ReadLInt(R, sorg);
		Files.ReadLInt(R, app);
		Files.ReadLInt(R, app);
		WHILE (app >= 0) & ~inthread DO	(* for all references *)
			inthread := thread = app;
			Files.ReadLInt(R, app)
		END;
		IF inthread & ~marked[key-beg] THEN
			marked[key-beg] := TRUE;
			Files.Set(R, refs, sorg);
			Files.ReadString(R, line);
			FOR i := 1 TO level DO
				Texts.Write(Wr, Strings.Tab)
			END;
			WriteArticle(key, line);
			oldThread := thread; thread := org; INC(level);
			BTrees.EnumLInt(indexA, key+1, end, enumThread);
			thread := oldThread; DEC(level)
		END
	END enumThread;
	
	PROCEDURE Thread(T: Texts.Text);
		VAR
			R: Files.Rider;
			a, org, sorg, porg: LONGINT;
			re: INTEGER;
	BEGIN
		NEW(marked, MaxMessages);
		FOR a := 0 TO MaxMessages-1 DO
			marked[a] := FALSE
		END;
		IF (end - beg) >= MaxMessages  THEN beg := end - MaxMessages  + 1 END;
		NetTools.curLen := end-beg;
		FOR a := beg TO end DO	(* from oldest to newest *)
			BTrees.SearchLInt(indexA, a, org, re);
			IF re = BTrees.Done THEN
				Files.Set(R, refs, org);
				Files.ReadLInt(R, sorg);
				Files.ReadLInt(R, porg);
				Files.ReadLInt(R, porg);
				IF porg < 0 THEN	(* article has no references *)
					Files.Set(R, refs, sorg);
					Files.ReadString(R, line);
					WriteArticle(a, line);
					marked[a-beg] := TRUE;
					thread := org; level := 1;
					BTrees.EnumLInt(indexA, a+1, end, enumThread)	(* enum all newer articles *)
				ELSIF ~marked[a-beg] THEN (* article not yet marked *)
					Files.Set(R, refs, sorg);
					Files.ReadString(R, line);
					WriteArticle(a, line);
					marked[a-beg] := TRUE
				END;
				Texts.Insert(T, 0, Wr.buf)
			END
		END;
		marked := NIL
	END Thread;

(** List all available articles in group in a certain range. 0-0 = all *)
	PROCEDURE ArticleRange(S: Session; group: ARRAY OF CHAR; VAR T: Texts.Text; thread: BOOLEAN; from, to: LONGINT);
		VAR
			nr: LONGINT;
			org, org2, org3, fixup: LONGINT;
			str: ARRAY 16 OF CHAR;
			msgid: ARRAY 128 OF CHAR;
			dummy: ARRAY 256 OF CHAR;
			R: Files.Rider;
			i, j, iRef, bres: INTEGER;
	BEGIN
		line := "GROUP ";
		Strings.Append(line, group);
		NetSystem.WriteString(S.C, line);
		ReadResponse(S);
		IF S.status = 211 THEN
			NEW(T); Texts.Open(T, "");
			i := 0;
			Strings.StrToIntPos(S.reply, beg, i);
			Strings.StrToIntPos(S.reply, beg, i);
			Strings.StrToIntPos(S.reply, beg, i);
			Strings.StrToIntPos(S.reply, end, i);
			Texts.WriteString(W, group);  Texts.WriteString(W, " available: ");
			Texts.WriteInt(W, beg, 1);  Texts.Write(W, "-");  Texts.WriteInt(W, end, 1);
			IF (from #  0) & (to = 0) THEN
				(* get 'from' newest articles *)
				beg := end - from + 1;
			ELSIF (from #  0) & (to # 0) THEN
				(* from-to articles *)
				beg := from;  end := to;
			END;
			(* be careful that your number range is smaller than MaxMessages  *)
			IF (end - beg) >= MaxMessages  THEN beg := end - MaxMessages  + 1; END;
			Texts.WriteString(W, ", get ");  Texts.WriteInt(W, beg, 1);
			Texts.Write(W, "-");  Texts.WriteInt(W, end, 1);
			IF curGrpNewOnly THEN Texts.WriteString(W, " unread"); END;
			Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf);
			indexM := BTrees.NewStr(Files.New(""), 0, SHORT(2*(end-beg))); BTrees.Flush(indexM);
			indexA := BTrees.NewLInt(BTrees.Base(indexM), Files.Length(BTrees.Base(indexM)), SHORT(2*(end-beg)));
			NetTools.curLen := end-beg; availBeg := beg;
			refs := Files.New(""); Files.Set(R, refs, 0);
			line := "XOVER ";
			Strings.IntToStr(beg, str);
			Strings.Append(line, str);
			Strings.AppendCh(line, "-");
			Strings.IntToStr(end, str);
			Strings.Append(line, str);
			NetSystem.WriteString(S.C, line);
			ReadResponse(S);
			IF S.status = 224 THEN
				curGrp := GetGroup(group, TRUE);
				NetSystem.ReadString(S.C, line);
				WHILE (line[0] # ".") OR (line[1] # 0X) DO	(* parse "message" line *)
					Strings.StrToInt(line, nr);
					IF ~curGrpNewOnly OR ~ReadArt(curGrp, nr) THEN
						i := 0; j := 0;
						WHILE (line[i] # 0X) & (j < 4) DO
							IF line[i] = Strings.Tab THEN
								INC(j)
							END;
							INC(i)
						END;
						line[i-1] := 0X;
						j := 0;
						WHILE (line[i] > " ") & (line[i] # ">") DO
							msgid[j] := line[i];
							INC(j); INC(i)
						END;
						IF line[i] = ">" THEN
							msgid[j] := line[i];
							INC(j); INC(i)
						END;
						msgid[j] := 0X;
						Strings.Upper(msgid, msgid);
						WHILE (line[i] # 0X) & (line[i] # "<") DO
							INC(i)
						END;
						org := Files.Pos(R);
						BTrees.InsertStr(indexM, msgid, org, bres);	(* add msgid to msgs index *)
						BTrees.InsertLInt(indexA, nr, org, bres);
						Files.WriteLInt(R, -1);	(* offset of title line *)
						Files.WriteLInt(R, nr);	(* the article nr. for article msgid *)
						iRef := i; fixup := 0;
						WHILE line[i] = "<" DO
							j := 0;
							WHILE (line[i] > " ") & (line[i] # ">") DO
								msgid[j] := line[i];
								INC(j); INC(i)
							END;
							IF line[i] = ">" THEN
								msgid[j] := line[i];
								INC(j); INC(i)
							END;
							msgid[j] := 0X;
							Strings.Upper(msgid, msgid);
							BTrees.SearchStr(indexM, msgid, org2, bres);	(* lookup the msgid referenced *)
							IF bres = BTrees.Done THEN
								Files.WriteLInt(R, org2)	(* add it to the references list *)
							ELSE	(* referenced article no longer available *)
								Files.WriteLInt(R, -2); INC(fixup)
							END;
							WHILE (line[i] # 0X) & (line[i] # "<") DO
								INC(i)
							END
						END;
						Files.WriteLInt(R, -1);	(* end of reference list *)
						org2 := Files.Pos(R);
						Files.Set(R, refs, org);	(* fixup for title line *)
						Files.WriteLInt(R, org2);
						Files.Set(R, refs, org2);	(* write the title line *)
						Files.WriteString(R, line);
						IF thread & (fixup > 0) THEN
							Files.Set(R, refs, org);
							Files.ReadLInt(R, org);
							Files.ReadLInt(R, org);
							i := iRef;
							WHILE line[i] = "<" DO
								j := 0;
								WHILE (line[i] > " ") & (line[i] # ">") DO
									msgid[j] := line[i];
									INC(j); INC(i)
								END;
								IF line[i] = ">" THEN
									msgid[j] := line[i];
									INC(j); INC(i)
								END;
								msgid[j] := 0X;
								Strings.Upper(msgid, msgid);
								Files.ReadLInt(R, org);
								IF org = -2 THEN
									org2 := Files.Length(refs); DEC(beg);
									BTrees.InsertStr(indexM, msgid, org2, bres);
									BTrees.InsertLInt(indexA, beg, org2, bres);
									org := Files.Pos(R)-4;
									Files.Set(R, refs, org2);
									Files.WriteLInt(R, -1);	(* offset of title line *)
									Files.WriteLInt(R, beg);	(* the article nr. for article msgid *)
									Files.WriteLInt(R, -1);	(* end of reference list *)
									org3 := Files.Pos(R);
									Strings.IntToStr(beg, dummy); Strings.AppendCh(dummy, Strings.Tab);
									Strings.Append(dummy, "Was: "); Strings.Append(dummy, msgid);
									Files.WriteString(R, dummy);	(* write the title line *)
									Files.Set(R, refs, org2);
									Files.WriteLInt(R, org3);	(* fixup for title line *)
									Files.Set(R, refs, org);
									Files.WriteLInt(R, org2);
									DEC(fixup)
								END;
								WHILE (line[i] # 0X) & (line[i] # "<") DO
									INC(i)
								END
							END;
							org := Files.Length(refs); Files.Set(R, refs, org)
						END
					END;
					NetSystem.ReadString(S.C, line)
				END;
				S.res := Done
			ELSE
				S.res := ErrXOver
			END
		ELSE
			S.res := ErrGroup
		END;
		IF S.res = Done THEN
			IF thread THEN
				Thread(T)
			ELSE
				ListArts(T)
			END;
			Texts.Append(T, Wr.buf);
			WriteGrpHead(group);
			Texts.Insert(T, 0, Wr.buf)
		END;
		curGrp := NIL; refs := NIL;
		indexM := NIL; indexA := NIL
	END ArticleRange;

(** List all available articles in group. *)
	PROCEDURE Articles*(S: Session; group: ARRAY OF CHAR; VAR T: Texts.Text; thread: BOOLEAN);
	BEGIN
		ArticleRange(S, group, T, thread, 0, 0)
	END Articles;

	PROCEDURE ReadString(VAR R: Texts.Reader; VAR s: ARRAY OF CHAR);
		VAR
			l, i: LONGINT;
			ch: CHAR;
	BEGIN
		l := LEN(s)-1; i := 0;
		Texts.Read(R, ch);
		WHILE ~R.eot & (ch # Strings.CR) & (i < l) DO
			IF R.lib IS Fonts.Font THEN
				s[i] := ch; INC(i)
			END;
			Texts.Read(R, ch)
		END;
		s[i] := 0X
	END ReadString;

	PROCEDURE ReadArticle(S: Session; VAR T: Texts.Text);
		VAR
			h: MIME.Header;
			cont: MIME.Content;
			out: Streams.Stream;
			val: ARRAY 256 OF CHAR;
			pos: LONGINT;
			mT: Texts.Text;
			i: INTEGER;
	BEGIN
		out := TextStreams.OpenWriter(T);
		MIME.ReadHeader(S.S, out, h, pos); out.Flush(out);
		Mail.ParseContent(h, cont);
		pos := MIME.FindField(h, "Xref");
		IF pos > 0 THEN
			MIME.ExtractValue(h, pos, line);
			i := 0; pos := 0;
			WHILE line[pos] # 0X DO
				IF line[pos] <= " " THEN
					i := 0; INC(pos)
				ELSIF line[pos] = ":" THEN
					val[i] := 0X; INC(pos); i := SHORT(pos);
					Strings.StrToIntPos(line, pos, i);
					AddArtNr(GetGroup(val, TRUE), pos);
					pos := i
				ELSE
					val[i] := line[pos];
					INC(i); INC(pos)
				END
			END
		END;
		Texts.Append(T, W.buf); (*Texts.WriteLn(W);*)
		cont.len := MAX(LONGINT);
		IF cont.typ.typ # "multipart" THEN
			MIME.ReadText(S.S, W, cont, TRUE)
		ELSE
			Texts.Append(T, W.buf);
			MIME.ReadMultipartText(S.S, mT, cont, TRUE); Texts.Save(mT, 0, mT.len, W.buf)
		END;
		Texts.Append(T, W.buf);
		IF (cont.typ.typ = "application") & (cont.encoding IN {MIME.EncAsciiCoder, MIME.EncAsciiCoderC, MIME.EncAsciiCoderCPlain}) THEN
			Mail.DecodeMessage(T, h, cont, -1);
		ELSIF NetTools.QueryString("NewsFont", val) & (Fonts.This(val) # NIL) THEN
			newsFont := Fonts.This(val);
			Texts.ChangeLooks(T, 0, T.len, {0}, newsFont, 0, 0)
		END
	END ReadArticle;

(** Retrieve article with number artnr in group. *)
	PROCEDURE ArticleByNr*(S: Session; group: ARRAY OF CHAR; artnr: LONGINT; VAR T: Texts.Text);
		VAR str: ARRAY 12 OF CHAR;
	BEGIN
		line := "GROUP ";
		Strings.Append(line, group);
		NetSystem.WriteString(S.C, line);
		ReadResponse(S);
		IF S.status = 211 THEN
			NEW(T); Texts.Open(T, "");
			line := "STAT ";
			Strings.IntToStr(artnr, str);
			Strings.Append(line, str);
			NetSystem.WriteString(S.C, line);
			ReadResponse(S);
			IF S.status = 223 THEN
				line := "ARTICLE";
				NetSystem.WriteString(S.C, line);
				ReadResponse(S);
				IF S.status = 220 THEN
					AddArtNr(GetGroup(group, TRUE), artnr);
					ReadArticle(S, T);
					S.res := Done
				ELSE
					S.res := ErrArticle
				END
			ELSE
				S.res := ErrStat
			END
		ELSE
			S.res := ErrGroup
		END
	END ArticleByNr;

(** Retrieve the article with the message-id msgid. *)
	PROCEDURE ArticleByMsgId*(S: Session; msgid: ARRAY OF CHAR; VAR T: Texts.Text);
	BEGIN
		line := "ARTICLE <";
		Strings.Append(line, msgid);
		Strings.AppendCh(line, ">");
		NetSystem.WriteString(S.C, line);
		ReadResponse(S);
		IF S.status = 220 THEN
			NEW(T); Texts.Open(T, "");
			ReadArticle(S, T);
			S.res := Done
		ELSE
			S.res := ErrArticle
		END
	END ArticleByMsgId;

	PROCEDURE ReadGroupName(VAR name: ARRAY OF CHAR);
		VAR
			R: Texts.Reader;
			beg, end, time: LONGINT;
			text: Texts.Text;
			ch: CHAR;
	BEGIN
		COPY("", name);
		Texts.OpenReader(R, Oberon.Par.text, Oberon.Par.pos);
		Texts.Read(R, ch);
		WHILE ~R.eot & (ch <= " ") DO
			Texts.Read(R, ch)
		END;
		IF ~R.eot & (ch = "^") THEN
			time := -1; text := NIL;
			Oberon.GetSelection(text, beg, end, time);
			IF (text # NIL) & (time >= 0) THEN
				Texts.OpenReader(R, text, beg);
				Texts.Read(R, ch);
				WHILE ~R.eot & (ch <= " ") DO
					Texts.Read(R, ch)
				END
			ELSE
				RETURN
			END
		END;
		IF ch = 22X THEN
			Texts.Read(R, ch)
		END;
		beg := 0;
		WHILE ~R.eot & (ch > " ") & (ch # 22X) DO
			name[beg] := ch;
			INC(beg);
			IF ch = ":" THEN
				beg := 0
			END;
			Texts.Read(R, ch)
		END;
		name[beg] := 0X
	END ReadGroupName;

(** News.SubGroup ^
		Subscribe a group (selection). *)
	PROCEDURE SubGroup*;
		VAR
			name: ARRAY 128 OF CHAR;
			group: Group;
	BEGIN
		ReadGroupName(name);
		IF name # "" THEN
			group := GetGroup(name, TRUE);
			group.subscribed := TRUE;
			Texts.WriteString(W, name);
			Texts.WriteString(W, " subcribed");
			Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf)
		END
	END SubGroup;

(** News.UnsubGroup ^
		Unsubscribe a group (selection). *)
	PROCEDURE UnsubGroup*;
		VAR
			name: ARRAY 128 OF CHAR;
			group: Group;
	BEGIN
		ReadGroupName(name);
		IF name # "" THEN
			Texts.WriteString(W, name);
			group := GetGroup(name, FALSE);
			IF group # NIL THEN
				group.subscribed := FALSE;
				Texts.WriteString(W, " unsubcribed")
			ELSE
				Texts.WriteString(W, " not found")
			END;
			Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf)
		END
	END UnsubGroup;

	PROCEDURE catchUp(S: Session; group: Group);
		VAR
			end: LONGINT;
			art: ArtNrs;
			i: INTEGER;
	BEGIN
		line := "GROUP ";
		Strings.Append(line, group.name);
		NetSystem.WriteString(S.C, line);
		ReadResponse(S);
		IF S.status = 211 THEN
			i := 0;
			Strings.StrToIntPos(S.reply, end, i);
			Strings.StrToIntPos(S.reply, end, i);
			Strings.StrToIntPos(S.reply, end, i);
			Strings.StrToIntPos(S.reply, end, i)
		ELSE
			Texts.WriteString(W, S.reply);Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf);
			art := group.readArtNrs;
			WHILE art # NIL DO
				IF art.end > end THEN end := art.end END;
				art := art.next
			END
		END;
		NEW(art); art.beg := 0; art.end := end; art.next := NIL;
		group.readArtNrs := art
	END catchUp;

(** News.CatchUp ^
		Mark all articles in a group (selection) as read. *)
	PROCEDURE CatchUp*;
		VAR
			name: ARRAY 128 OF CHAR;
			group: Group;
			S: Session;
	BEGIN
		ReadGroupName(name);
		IF name # "" THEN
			group := GetGroup(name, TRUE);
			IF Connect(S) THEN
				catchUp(S, group)
			END;
			IF (S # NIL) & (S.res # Done) THEN
				Texts.WriteString(W, S.reply);
				Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
			END;
			Close(S)
		END
	END CatchUp;

(** News.CatchUpAll
		Mark all articles in all subscribed groups. *)
	PROCEDURE CatchUpAll*;
		VAR
			group: Group;
			S: Session;
	BEGIN
		IF Connect(S) THEN
			group := groups;
			WHILE group # NIL DO
				IF group.subscribed THEN
					catchUp(S, group)
				END;
				group := group.next
			END
		END;
		IF (S # NIL) & (S.res # Done) THEN
			Texts.WriteString(W, S.reply);
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END;
		Close(S)
	END CatchUpAll;

	PROCEDURE SplitNewsAdr(VAR url, host, groupart: ARRAY OF CHAR): LONGINT;
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
		HyperDocs.UnESC(url);
		i := 0;
		Blanks();
		(* skip news *)
		WHILE (url[i] # 0X) & (url[i] # ":") DO
			INC(i)
		END;
		(* skip : *)
		WHILE (url[i] # 0X) & (url[i] = ":") DO
			INC(i)
		END;
		Blanks();
		(* get groupart *)
		iskey := TRUE;
		l := LEN(groupart);
		j := 0;
		WHILE (url[i] # 0X) & (url[i] # "@") DO
			IF (url[i] > " ") & ~Strings.IsDigit(url[i]) THEN
				iskey := FALSE
			END;
			IF j < l THEN
				groupart[j] := url[i];
				INC(j)
			END;
			INC(i)
		END;
		groupart[j] := 0X;
		DEC(j);
		WHILE (j >= 0) & (groupart[j] <= " ") DO
			groupart[j] := 0X;
			DEC(j)
		END;
		IF (url[i] = 0X) & iskey THEN
			IF groupart # "" THEN
				Strings.StrToInt(groupart, key);
				HyperDocs.RetrieveLink(key, line);
				key := SplitNewsAdr(line, host, groupart);
				RETURN key
			ELSE
				RETURN HyperDocs.UndefKey
			END
		ELSIF url[i] = "@" THEN
			INC(i);
			l := LEN(host);
			j := 0;
			WHILE url[i] # 0X DO
				IF j < l THEN
					host[j] := url[i];
					INC(j)
				END;
				INC(i)
			END;
			host[j] := 0X;
			DEC(j);
			WHILE (j >= 0) & (host[j] <= " ") DO
				host[j] := 0X;
				DEC(j)
			END
		ELSE
			COPY("", host)
		END;
		key := RegisterNewsAdr(host, groupart);
		RETURN key
	END SplitNewsAdr;

	PROCEDURE SplitNNTPAdr(VAR url, group: ARRAY OF CHAR; VAR artnr: LONGINT): LONGINT;
		VAR
			i, j, l, key: LONGINT;
			iskey: BOOLEAN;
			str: ARRAY 12 OF CHAR;
		PROCEDURE Blanks();
		BEGIN
			WHILE (url[i] # 0X) & (url[i] <= " ") DO
				INC(i)
			END
		END Blanks;
	BEGIN
		HyperDocs.UnESC(url);
		i := 0;
		Blanks();
		(* skip nntp *)
		WHILE (url[i] # 0X) & (url[i] # ":") DO
			INC(i)
		END;
		(* skip : *)
		WHILE (url[i] # 0X) & (url[i] = ":") DO
			INC(i)
		END;
		Blanks();
		(* get group *)
		iskey := TRUE;
		l := SHORT(LEN(group));
		j := 0;
		WHILE (url[i] # 0X) & (url[i] # "/") DO
			IF (url[i] > " ") & ~Strings.IsDigit(url[i]) THEN
				iskey := FALSE
			END;
			IF j < l THEN
				group[j] := url[i];
				INC(j)
			END;
			INC(i)
		END;
		group[j] := 0X;
		DEC(j);
		WHILE (j >= 0) & (group[j] <= " ") DO
			group[j] := 0X;
			DEC(j)
		END;
		IF (url[i] = 0X) & iskey THEN
			IF group # "" THEN
				Strings.StrToInt(group, key);
				HyperDocs.RetrieveLink(key, line);
				key := SplitNNTPAdr(line, group, artnr);
				RETURN key
			ELSE
				RETURN -1
			END
		ELSIF url[i] = "/" THEN
			INC(i);
			l := 12;
			j := 0;
			WHILE url[i] # 0X DO
				IF j < l THEN
					str[j] := url[i];
					INC(j)
				END;
				INC(i)
			END;
			str[j] := 0X;
			Strings.StrToInt(str, artnr)
		ELSE
			artnr := 0
		END;
		key := RegisterNNTPAdr(group, artnr);
		RETURN key
	END SplitNNTPAdr;

	PROCEDURE *DocHandler(D: Objects.Object; VAR M: Objects.ObjMsg);
	BEGIN
		WITH D: Documents.Document DO
			TextDocs.DocHandler(D, M)
		END
	END DocHandler;

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

	PROCEDURE *LoadDoc(D: Documents.Document);
		VAR
			host: ARRAY NetTools.ServerStrLen OF CHAR;
			group, msgid: ARRAY NetTools.PathStrLen OF CHAR;
			T: Texts.Text;
			pos, artnr, artnr1: LONGINT;
			date, time: LONGINT;
			S: Session;
			obj, t: Objects.Object;
			F: Texts.Finder;
			article: BOOLEAN;
			sPos: INTEGER;
	BEGIN
		S := NIL;
		article := FALSE;
		D.dsc := NIL;
		IF (D.name = "") OR (D.name = "subgroups") THEN
			TextDocs.InitDoc(D);
			NEW(T); Texts.Open(T, "");
			SubGroups(T);
			IF T.len = 0 THEN
				Texts.WriteString(W, "No subscribed groups");
				Texts.WriteLn(W);
				Texts.Append(T, W.buf)
			END;
			COPY("Subscribed Groups", D.name)
		ELSIF D.name = "newgroups" THEN
			IF Connect(S) THEN
				date := newgDate; time := newgTime;
				TextDocs.InitDoc(D);
				NEW(T);
				Texts.Open(T, "");
				NewGrp(S, T);
				IF T # NIL THEN
					IF T.len = 0 THEN
						Texts.WriteString(W, "No new groups since ")
					ELSE
						Texts.WriteString(W, "New groups since ")
					END;
					Texts.WriteDate(W, time, date); Texts.WriteLn(W);
					Texts.WriteLn(W); Texts.Insert(T, 0, W.buf)
				END;
				COPY("New Groups", D.name);
				Close(S)
			END
		ELSIF D.name = "news:" THEN
			IF Connect(S) THEN
				TextDocs.InitDoc(D);
				COPY("All Groups", D.name);
				AllGroups(S, T);
				Close(S)
			END
		ELSIF Strings.CAPPrefix("news:", D.name) THEN
			IF SplitNewsAdr(D.name, host, group) # HyperDocs.UndefKey THEN
				IF Connect(S) THEN
					TextDocs.InitDoc(D);
					curGrpNewOnly := FALSE;
					IF group = "" THEN
						COPY("All Groups", D.name);
						AllGroups(S, T)
					ELSIF host = "" THEN
						COPY(group, D.name);
						Articles(S, group, T, NetTools.QueryBool("NewsThreading"))
					ELSE
						(* news:<group>@<number[-<number>][\n] *)
						sPos := 0; Strings.StrToIntPos(host, artnr, sPos);
						IF artnr # 0 THEN (* a number was found *)
							IF host[sPos] = "-" THEN (* a range *) 
								INC(sPos); Strings.StrToIntPos(host, artnr1, sPos)
								(* get articles #artnr to #artnr1 *)
							ELSE
								artnr1 := 0 (* get the artnr newest articles *)
							END;
							curGrpNewOnly :=  (host[sPos] = "\" ) & (host[sPos+1] = "n" );  (* look for option \n *)
							ArticleRange(S, group, T, NetTools.QueryBool("NewsThreading"), artnr, artnr1)
						ELSE (* a real host *)
							COPY(group, msgid);
							Strings.AppendCh(msgid, "@");
							Strings.Append(msgid, host);
							COPY(msgid, D.name);
							ArticleByMsgId(S, msgid, T);
							article := TRUE
						END
					END;
					Close(S)
				END
			END
		ELSIF Strings.CAPPrefix("nntp:", D.name) THEN
			IF SplitNNTPAdr(D.name, group, artnr) # HyperDocs.UndefKey THEN
				IF Connect(S) THEN
					TextDocs.InitDoc(D);
					ArticleByNr(S, group, artnr, T);
					COPY(group, D.name);
					Strings.AppendCh(D.name, ".");
					Strings.IntToStr(artnr, msgid);
					Strings.Append(D.name, msgid);
					article := TRUE;
					IF (S.res = Done) & (Gadgets.executorObj # NIL) & (Gadgets.executorObj IS TextGadgets.Control) THEN
						Links.GetLink(Gadgets.context, "Model", t);
						IF (t # NIL) & (t IS Texts.Text) THEN
							Texts.OpenFinder(F, t(Texts.Text), 0);
							pos := F.pos; Texts.FindObj(F, obj);
							WHILE ~F.eot DO
								IF obj = Gadgets.executorObj THEN
									artnr := pos; FindBeg(t(Texts.Text), artnr);
									Texts.ChangeLooks(t(Texts.Text), artnr, pos-1, {1}, NIL, SHORT(HyperDocs.linkC), 0)
								END;
								pos := F.pos; Texts.FindObj(F, obj)
							END
						END
					END;
					Close(S)
				END
			END
		ELSE
			HALT(99)
		END;
		IF (S # NIL) & (S.res # Done) THEN
			D.dsc := NIL;
			Texts.WriteString(W, S.reply);
			Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf)
		ELSE
			Links.SetLink(D.dsc, "Model", T);
			D.W := HyperDocs.docW; D.H := HyperDocs.docH;
			IF ~article THEN
				D.handle := DocHandler
			END
		END;
		IF HyperDocs.context # NIL THEN
			HyperDocs.context.replace := FALSE;
			HyperDocs.context.history := FALSE
		END
	END LoadDoc;

	PROCEDURE NewDoc*;
		VAR D: Documents.Document;
	BEGIN
		NEW(D);
		D.Load := LoadDoc;
		D.Store := NIL;
		D.handle := NIL;
		Objects.NewObj := D
	END NewDoc;

(** News.ShowAllGroups
		Show all newsgroups. *)
	PROCEDURE ShowAllGroups*;
		VAR doc: Documents.Document;
	BEGIN
		NewDoc();
		doc := Objects.NewObj(Documents.Document);
		doc.name := "news:";
		doc.Load(doc);
		IF (doc # NIL) & (doc.dsc # NIL) THEN
			Desktops.ShowDoc(doc)
		END
	END ShowAllGroups;

(** News.ShowNewGroups
		Show new groups since last access. *)
	PROCEDURE ShowNewGroups*;
		VAR doc: Documents.Document;
	BEGIN
		NewDoc();
		doc := Objects.NewObj(Documents.Document);
		doc.name := "newgroups";
		doc.Load(doc);
		IF (doc # NIL) & (doc.dsc # NIL) THEN
			Desktops.ShowDoc(doc)
		END
	END ShowNewGroups;

(** News.SubscribedGroups
		List subscribed groups. *)
	PROCEDURE SubscribedGroups*;
		VAR doc: Documents.Document;
	BEGIN
		NewDoc();
		doc := Objects.NewObj(Documents.Document);
		doc.name := "subgroups";
		doc.Load(doc);
		IF (doc # NIL) & (doc.dsc # NIL) THEN
			Desktops.ShowDoc(doc)
		END
	END SubscribedGroups;

	PROCEDURE *NewsSchemeHandler(L: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			host: ARRAY NetTools.ServerStrLen OF CHAR;
			group: ARRAY NetTools.PathStrLen OF CHAR;
	BEGIN
		WITH L: HyperDocs.LinkScheme DO
			IF M IS HyperDocs.RegisterLinkMsg THEN
				WITH M: HyperDocs.RegisterLinkMsg DO
					M.key := SplitNewsAdr(M.link, host, group);
					IF M.key # HyperDocs.UndefKey THEN
						M.res := 0
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.class := Objects.String;
						M.s := "News.NewNewsLinkScheme";
						M.res := 0
					ELSE
						HyperDocs.LinkSchemeHandler(L, M)
					END
				END
			ELSE
				HyperDocs.LinkSchemeHandler(L, M)
			END
		END
	END NewsSchemeHandler;

	PROCEDURE NewNewsLinkScheme*;
		VAR L: HyperDocs.LinkScheme;
	BEGIN
		NEW(L); L.handle := NewsSchemeHandler;
		L.usePath := FALSE;
		Objects.NewObj := L
	END NewNewsLinkScheme;

	PROCEDURE *NNTPSchemeHandler(L: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			group: ARRAY NetTools.PathStrLen OF CHAR;
			artnr: LONGINT;
	BEGIN
		WITH L: HyperDocs.LinkScheme DO
			IF M IS HyperDocs.RegisterLinkMsg THEN
				WITH M: HyperDocs.RegisterLinkMsg DO
					M.key := SplitNNTPAdr(M.link, group, artnr);
					IF M.key # HyperDocs.UndefKey THEN
						M.res := 0
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.class := Objects.String;
						M.s := "News.NewNNTPLinkScheme";
						M.res := 0
					ELSE
						HyperDocs.LinkSchemeHandler(L, M)
					END
				END
			ELSE
				HyperDocs.LinkSchemeHandler(L, M)
			END
		END
	END NNTPSchemeHandler;

	PROCEDURE NewNNTPLinkScheme*;
		VAR L: HyperDocs.LinkScheme;
	BEGIN
		NEW(L); L.handle := NNTPSchemeHandler;
		L.usePath := FALSE;
		Objects.NewObj := L
	END NewNNTPLinkScheme;

	PROCEDURE SendArticle*(S: Session; T: Texts.Text; cont: MIME.Content);
		VAR
			s: Streams.Stream;
			h: MIME.Header;
			head: Texts.Text;
			R: Texts.Reader;
			beg: LONGINT;
			ch: CHAR;
	BEGIN
		NetSystem.WriteString(S.C, "POST");
		ReadResponse(S);
		IF S.status = 340 THEN
			s := TextStreams.OpenReader(T, 0); 
			MIME.ReadHeader(s, NIL, h, beg);
			NEW(head); Texts.Open(head, "");
			Texts.OpenReader(R, T, beg); Texts.Read(R, ch);
			IF (ch = Strings.CR) OR (ch = Strings.LF) THEN
				WHILE (beg > 0) & ((ch = Strings.CR) OR (ch = Strings.LF)) DO
					DEC(beg); Texts.OpenReader(R, T, beg); Texts.Read(R, ch)
				END;
				INC(beg); IF beg > T.len THEN beg := T.len END
			END;
			Texts.Save(T, 0, beg, W.buf); Texts.Append(head, W.buf);
			(*Texts.WriteLn(W);*) Texts.Append(head, W.buf);
			Mail.GetSetting("EMail", S.from, FALSE);
			Texts.OpenReader(R, T, beg); Texts.Read(R, ch); DEC(beg);
			WHILE ~R.eot & ((ch <= " ") & (R.lib IS Fonts.Font)) DO
				Texts.Read(R, ch); INC(beg)
			END;
			Mail.SendText(S, head, T, beg, T.len, cont); 
			ReadResponse(S);
			IF S.status = 240 THEN
				S.res := Done; Mail.SendReplyLine(S, cont)
			ELSE
				S.res := ErrPost
			END
		ELSE
			S.res := ErrPost
		END
	END SendArticle;

(** News.Send [mime] *
		Send article (the marked text), mime:
			ascii : text/plain, us-ascii
			iso : text/plain, iso 8bit
			oberon : text/plain with application/compressed/oberondoc attachment
			<no mime> :
				- Simple Text without different colors or fonts
					no Umlaut -> ascii
					Umlaut -> iso
				- Text without objects, but with different colors or fonts -> oberon
				- Text with objects -> ooberon *)
	PROCEDURE Send*;
		VAR
			T, sig: Texts.Text;
			cont: MIME.Content;
			Sc: Attributes.Scanner;
			S: Session;
			val: ARRAY 64 OF CHAR;
	BEGIN
		T := Oberon.MarkedText();
		IF T # NIL THEN
			NEW(cont); cont.typ := MIME.GetContentType("text/plain");
			Attributes.OpenScanner(Sc, Oberon.Par.text, Oberon.Par.pos);
			Sc.s := ""; Attributes.Scan(Sc);
			IF CAP(Sc.s[0]) = "O" THEN
				cont.typ := MIME.GetContentType(MIME.OberonMime); cont.encoding := MIME.EncAsciiCoderC
			ELSIF CAP(Sc.s[0]) = "A" THEN
				cont.encoding := MIME.EncBin
			ELSIF CAP(Sc.s[0]) = "I" THEN
				cont.encoding := MIME.Enc8Bit
			ELSE
				Mail.QueryContType(T, 0, cont)
			END;
			Mail.GetSetting("NewsSignature", val, FALSE);
			IF val # "" THEN
				NEW(sig); Texts.Open(sig, val);
				IF sig.len > 0 THEN
					Texts.Save(T, 0, T.len, W.buf);
					NEW(T); Texts.Open(T, "");
					Texts.WriteLn(W); Texts.Append(T, W.buf);
					Texts.Save(sig, 0, sig.len, W.buf);
					Texts.Append(T, W.buf)
				END
			END;
			Texts.WriteString(W, "sending ");
			Texts.Append(Oberon.Log, W.buf);
			IF Connect(S) THEN
				SendArticle(S, T, cont)
			END;
			Texts.WriteString(W, S.reply);
			Close(S);
			Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf)
		END
	END Send;

(** News.Reply (selection)
	Compose a minimal followup article for the selected article. *)
	PROCEDURE Reply*;
		VAR
			T, text: Texts.Text;
			S: Attributes.Scanner;
			time, beg, end: LONGINT;
			par, msgid, from: ARRAY 256 OF CHAR;
			R: Texts.Reader;
			lib: Objects.Library;
			grp, sub, frm: BOOLEAN;
	BEGIN
		lib := W.lib; Texts.SetFont(W, newsFont);
		grp := FALSE; sub := FALSE; frm := FALSE;
		Mail.GetSetting("EMail", EMail, FALSE);
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		IF (S.class = Texts.Char) & (S.c = "^") THEN
			text := NIL; time := -1;
			Oberon.GetSelection(text, beg, end, time);
			IF time < 0 THEN text := NIL END
		ELSE
			text := Oberon.MarkedText(); beg := 0
		END;
		from := "nobody"; msgid := "<>";
		IF text # NIL THEN
			Texts.OpenReader(R, text, beg);
			ReadString(R, line);
			WHILE ~R.eot & (line # "") DO
				IF Strings.CAPPrefix("Message-ID:", line) THEN
					Strings.GetPar(line, msgid);
					Texts.WriteString(W, "References: ");
					Texts.WriteString(W, msgid);
					Texts.WriteLn(W)
				ELSIF Strings.CAPPrefix("Subject:", line) THEN
					sub := TRUE;
					Strings.GetPar(line, par);
					Texts.WriteString(W, "Subject: ");
					Mail.Re(W, par);
					Texts.WriteLn(W)
				ELSIF Strings.CAPPrefix("Newsgroups:", line) THEN
					grp := TRUE; frm := TRUE;
					Texts.WriteString(W, line);
					Texts.WriteLn(W);
					Strings.GetPar(line, par);
					Texts.WriteString(W, "Followup-To: ");
					Texts.WriteString(W, par);
					Texts.WriteLn(W)
				ELSIF Strings.CAPPrefix("From:", line) THEN
					Strings.GetPar(line, from)
				END;
				ReadString(R, line)
			END
		END;
		NEW(T); Texts.Open(T, "");
		Texts.Append(T, W.buf);
		IF ~grp THEN
			Texts.WriteString(W, "Newsgroups: ");
			Texts.WriteLn(W);
			Texts.Insert(T, 0, W.buf)
		END;
		IF ~frm THEN
			Texts.WriteString(W, "From: ");
			Texts.WriteString(W, EMail);
			Texts.WriteLn(W)
		END;
		IF ~sub THEN
			Texts.WriteString(W, "Subject: ");
			Texts.WriteLn(W)
		END;
		Texts.WriteLn(W);
		Texts.WriteString(W, "In article "); Texts.WriteString(W, msgid); Texts.WriteString(W, ", ");
		Texts.WriteString(W, from); Texts.WriteString(W, " wrote: "); Texts.WriteLn(W);
		IF text # NIL THEN
			Texts.WriteLn(W);
			Mail.CiteText(W, text, Texts.Pos(R), text.len)
		END;
		Texts.WriteLn(W); Texts.Append(T, W.buf);
		Texts.SetFont(W, lib);
		TextDocs.ShowText("Article.Text", T, HyperDocs.docW, HyperDocs.docH)
	END Reply;

BEGIN
	Texts.OpenWriter(W); Texts.OpenWriter(Wr);
	LoadInitText(); Modules.InstallTermHandler(storeInitText)
END News.

News.Read.Text

News.StoreInitText

System.Free News ~
