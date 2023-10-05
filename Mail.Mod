(* OBERON System 3, Release 2.3.

Copyright 1999 ETH Zürich Institute for Computer Systems, 
ETH Center, CH-8092 Zürich. e-mail: oberon@inf.ethz.ch.

This module may be used under the conditions of the general Oberon 
System 3 license contract. The full text can be downloaded from

	"ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/license.txt;type=A"

Under the license terms stated it is in particular (a) prohibited to modify
the interface of this module in any way that disagrees with the style
or content of the system and (b) requested to provide all conversions
of the source code to another platform with the name OBERON. *)

MODULE Mail; (** portable *)	(* ejz,   *)
	IMPORT Kernel, Files, Strings, Dates, Objects, Display, Fonts, Texts, Oberon, NetSystem, NetTools, MIME, Streams,
		TextStreams, Display3, Attributes, Links, Gadgets, ListRiders, ListGadgets, AsciiCoder, TextGadgets, TextDocs, Documents,
		Desktops, HyperDocs, MD5, FileDir;

	CONST
		MsgFile = "MailMessages";
		DefPOPPort = 110;
		OberonStart* = "--- start of oberon mail ---";
		BufLen = 4096;
		Read= 0; Deleted = 1;
		SortByDateTime = 1; SortByReplyTo = 2; SortBySubject = 3;
		Version = 0;
		eq = 1; leq = 2; le = 3; geq = 4; ge = 5; neq = 6; or = 7; and = 8;
		from = 20; subject = 21; date = 22; time = 23; text = 24; topic = 25; notopic = 26; readFlag = 27;
		Menu = "Desktops.Copy[Copy] TextDocs.Search[Search] Mail.Show[Source] Mail.Reply[Reply] Desktops.StoreDoc[Store]";
		SysMenu = "Desktops.Copy[Copy] Mail.Reply[Reply] Desktops.StoreDoc[Store]";
		DefSMTPPort* = 25;
		simpler = TRUE;

	TYPE
		UIDL = ARRAY 64 OF CHAR;
		UIDLList = POINTER TO ARRAY OF UIDL;
		UIDLSet = POINTER TO UIDLSetDesc;
		UIDLSetDesc = RECORD
			F: Files.File;
			pop, user: ARRAY 64 OF CHAR;
			nouidls: LONGINT;
			uidls: UIDLList;
			next: UIDLSet
		END;

		MsgHead = RECORD
			pos, len (* - From head *), state, stamp: LONGINT;
			flags, topics: SET;
			date, time: LONGINT;
			replyTo, subject: ARRAY 64 OF CHAR
		END;
		MsgHeadList = POINTER TO ARRAY OF MsgHead;

		Topic = POINTER TO TopicDesc;
		TopicDesc = RECORD
			no, state, stamp: LONGINT;
			topic: ListRiders.String;
			next: Topic
		END;

		SortList = POINTER TO ARRAY OF LONGINT;

		Rider = POINTER TO RiderDesc;
		RiderDesc = RECORD (ListRiders.RiderDesc)
			noMsgs: LONGINT;
			key, pos, sortPos: LONGINT;
			ascending: BOOLEAN;
			sort: SortList
		END;

		ConnectMsg = RECORD (ListRiders.ConnectMsg)
			query: ARRAY 128 OF CHAR;
			sortBy: INTEGER; (* SortByDateTime, SortByReplyTo, SortBySubject *)
			ascending: BOOLEAN
		END;

		TopicRider = POINTER TO TopicRiderDesc;
		TopicRiderDesc = RECORD (ListRiders.RiderDesc)
			topic: Topic
		END;

		Model = POINTER TO ModelDesc;
		ModelDesc = RECORD (Gadgets.ObjDesc)
		END;

		Frame = POINTER TO FrameDesc;
		FrameDesc = RECORD (ListGadgets.FrameDesc)
			query, sortBy, ascending: Objects.Object
		END;

		Cond = POINTER TO CondDesc;
		CondDesc = RECORD
			val: ARRAY 64 OF CHAR;
			date, time: LONGINT;
			op, field: LONGINT;
			value, eval: BOOLEAN;
			next: Cond
		END;

		Node = POINTER TO NodeDesc;
		NodeDesc = RECORD (CondDesc)
			left, right: Cond
		END;

		Query = RECORD
			query: ARRAY 128 OF CHAR;
			conds, root: Cond;
			error: BOOLEAN
		END;

		SMTPSession* = POINTER TO SMTPSessionDesc;
		SMTPSessionDesc* = RECORD (NetTools.SessionDesc)
			from*: ARRAY 64 OF CHAR
		END;

	VAR
		msgs: MsgHeadList;
		noMsgs, delMsgs: LONGINT;
		msgsF: Files.File;
		msgList: Model;

		topicList: Model;
		topics: Topic;

		uidls: UIDLSet;
		lastUIDL: LONGINT;

		W: Texts.Writer;
		mMethod, tmMethod: ListRiders.Method;
		vMethod: ListGadgets.Method;

		textFnt, headFnt, fieldFnt: Fonts.Font;
		mailer: ARRAY 64 OF CHAR;

		trace: BOOLEAN;

	PROCEDURE NrToArg(nr: LONGINT; VAR arg: ARRAY OF CHAR);
	BEGIN
		IF nr > 9 THEN
			Strings.IntToStr(nr, arg)
		ELSE
			arg[0] := " "; arg[1] := CHR(nr+ORD("0")); arg[2] := 0X
		END
	END NrToArg;

	PROCEDURE SendCmd(S: NetTools.Session; cmd, arg: ARRAY OF CHAR);
	BEGIN
		IF trace THEN
			Texts.WriteString(W, "SND: "); Texts.WriteString(W, cmd);
			IF arg # "" THEN
				Texts.Write(W, " ");
				IF cmd # "PASS" THEN Texts.WriteString(W, arg) ELSE Texts.WriteString(W, "****") END
			END;
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END;
		NetTools.SendString(S.C, cmd);
		IF arg # "" THEN
			NetSystem.Write(S.C, " ")
		END;
		NetSystem.WriteString(S.C, arg)
	END SendCmd;

	PROCEDURE ReadState(S: NetTools.Session): BOOLEAN;
	BEGIN
		NetSystem.ReadString(S.C, S.reply);
		IF trace THEN
			Texts.WriteString(W, "RCV: "); Texts.WriteString(W, S.reply);
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END;
		IF S.reply[0] = "+" THEN
			S.status := NetTools.Done; S.res := NetTools.Done
		ELSE
			S.status := NetTools.Failed; S.res := NetTools.Failed
		END;
		RETURN S.status = NetTools.Done
	END ReadState;

	PROCEDURE ClosePOP(S: NetTools.Session);
	BEGIN
		IF S.C # NIL THEN
			SendCmd(S, "QUIT", "");
			S.res := NetTools.Done;
			NetTools.Disconnect(S.C); S.C := NIL; S.S := NIL
		ELSE
			S.res := NetTools.Failed
		END
	END ClosePOP;

	PROCEDURE APOP(S: NetTools.Session; user, passwd: ARRAY OF CHAR);
		VAR
			cont: MD5.Context;
			digest: MD5.Digest;
			stamp, login: ARRAY 64 OF CHAR;
			i, j: LONGINT;
	BEGIN
		i := 0;
		WHILE (S.reply[i] # 0X) & (S.reply[i] # "<") DO
			INC(i)
		END;
		j := 0;
		WHILE (S.reply[i] # 0X) & (S.reply[i] # ">") DO
			stamp[j] := S.reply[i]; INC(i); INC(j)
		END;
		stamp[j] := ">"; stamp[j+1] := 0X;
		cont := MD5.New();
		MD5.WriteBytes(cont, stamp, Strings.Length(stamp));
		MD5.WriteBytes(cont, passwd, Strings.Length(passwd));
		MD5.Close(cont, digest);
		MD5.ToString(digest, stamp);
		COPY(user, login); Strings.AppendCh(login, " "); Strings.Append(login, stamp);
		SendCmd(S, "APOP", login)
	END APOP;

	PROCEDURE OpenPOP(VAR S: NetTools.Session; host, user, passwd: ARRAY OF CHAR; port: INTEGER; apop: BOOLEAN);
		VAR
			hostIP: NetSystem.IPAdr;
			i: LONGINT;
			login: BOOLEAN;
	BEGIN
		IF trace THEN
			Texts.WriteString(W, "--- POP");
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END;
		IF (port <= 0) OR (port >= 10000) THEN
			port := DefPOPPort
		END;
		NEW(S);
		IF (host[0] # "<") & (host[0] # 0X) & (user[0] # 0X) & (passwd[0] # 0X) THEN
			NetSystem.GetIP(host, hostIP);
			IF NetTools.Connect(S.C, port, host, FALSE) THEN
				S.S := NetTools.OpenStream(S.C);
				IF ReadState(S) THEN
					login := TRUE;
					IF apop THEN
						APOP(S, user, passwd)
					ELSE
						SendCmd(S, "USER", user);
						IF ReadState(S) THEN
							SendCmd(S, "PASS", passwd)
						ELSE
							login := FALSE
						END
					END;
					IF login & ReadState(S) THEN
						S.reply := "connected"; S.res := NetTools.Done;
						RETURN
					END;
					i := 0;
					Strings.Search("assword", S.reply, i);
					IF i > 0 THEN
						NetSystem.DelPassword("pop", host, user)
					END
				ELSIF S.reply[0] = 0X THEN
					S.reply := "timed out"
				END;
				ClosePOP(S)
			ELSE
				S.reply := "no connection"
			END
		ELSE
			IF (host[0] = "<") OR (host[0] = 0X) THEN
				S.reply := "no pop-host specified"
			ELSIF user[0] = 0X THEN
				S.reply := "no pop user set"
			ELSE
				S.reply := "no pop password set"
			END
		END;
		S.res := NetTools.Failed; S.C := NIL; S.S := NIL
	END OpenPOP;

	PROCEDURE ReadText(S: NetTools.Session; VAR R: Files.Rider);
		VAR
			buffer: ARRAY BufLen OF CHAR;
			len, rlen, i, offs: LONGINT;
			state: INTEGER;
			ch, old: CHAR;
	BEGIN
		old := 0X; offs := 1;
		len := NetSystem.Available(S.C);
		state := NetSystem.State(S.C);
		WHILE (len > 0) OR (state = NetSystem.inout) DO
			IF len > (BufLen-2) THEN
				rlen := BufLen-2
			ELSE
				rlen := len
			END;
			NetSystem.ReadBytes(S.C, 0, rlen, buffer);
			i := 0;
			WHILE i < rlen DO
				ch := buffer[i];
				IF ch = Strings.CR THEN
					Files.Write(R, ch);
					IF (offs = 2) & (old = ".") THEN
						Files.Write(R, Strings.LF);
						RETURN
					END;
					offs := 0
				ELSE
					IF (offs > 0) OR (ch # ".") THEN
						Files.Write(R, ch)
					END;
					INC(offs)
				END;
				old := ch; INC(i)
			END;
			DEC(len, rlen);
			IF len <= 0 THEN
				len := NetSystem.Available(S.C);
				state := NetSystem.State(S.C)
			END
		END
	END ReadText;

	PROCEDURE DeleteMail(S: NetTools.Session; no: LONGINT);
		VAR arg: ARRAY 4 OF CHAR;
	BEGIN
		NrToArg(no, arg); SendCmd(S, "DELE", arg);
		IF ~ReadState(S) THEN
		END
	END DeleteMail;

	PROCEDURE ReceiveMail(S: NetTools.Session; no: LONGINT; VAR R: Files.Rider);
		VAR arg: ARRAY 8 OF CHAR;
	BEGIN
		NrToArg(no, arg); SendCmd(S, "RETR", arg);
		IF ReadState(S) THEN
			ReadText(S, R)
		END
	END ReceiveMail;

	PROCEDURE MessageSize(S: NetTools.Session; no: LONGINT): LONGINT;
		VAR
			arg: ARRAY 8 OF CHAR;
			size: LONGINT;
			i: INTEGER;
	BEGIN
		NrToArg(no, arg); SendCmd(S, "LIST", arg);
		IF ReadState(S) THEN
			i := 4; Strings.StrToIntPos(S.reply, size, i);
			Strings.StrToIntPos(S.reply, size, i)
		ELSE
			size := 0
		END;
		RETURN size
	END MessageSize;

	PROCEDURE GetUIDLs(S: NetTools.Session; VAR T: Texts.Text);
		VAR
			F: Files.File;
			R: Files.Rider;
	BEGIN
		SendCmd(S, "UIDL", "");
		IF ReadState(S) THEN
			F := Files.New(""); Files.Set(R, F, 0);
			ReadText(S, R);
			NEW(T); Texts.LoadAscii(T, F)
		ELSE
			T := NIL
		END
	END GetUIDLs;

	PROCEDURE UIDLFile(VAR pop, user: ARRAY OF CHAR; new: BOOLEAN): Files.File;
		VAR
			F: Files.File;
			name: FileDir.FileName;
	BEGIN
		COPY(pop, name);
		Strings.AppendCh(name, ".");
		Strings.Append(name, user);
		Strings.Append(name, ".UIDLs");
		F := Files.Old(name);
		IF F # NIL THEN
			Files.GetName(F, name)
		END;
		IF new OR (F = NIL) THEN
			F := Files.New(name); Files.Register(F)
		END;
		RETURN F
	END UIDLFile;

	PROCEDURE GetUIDLSet(VAR pop, user: ARRAY OF CHAR): UIDLSet;
		VAR
			set: UIDLSet;
			uidll: UIDLList;
			R: Files.Rider;
			i, j, l: LONGINT;
	BEGIN
		set := uidls;
		WHILE (set # NIL) & ~((set.pop = pop) & (set.user = user)) DO
			set := set.next
		END;
		IF set = NIL THEN
			NEW(set); set.next := uidls; uidls := set;
			COPY(pop, set.pop); COPY(user, set.user);
			NEW(set.uidls, 128); l := 128;
			set.F := UIDLFile(pop, user, FALSE);
			IF Files.Length(set.F) <= 0 THEN
				set.nouidls := 0
			ELSE
				Files.Set(R, set.F, 0); i := 0;
				Files.ReadString(R, set.uidls[i]);
				WHILE ~R.eof DO
					INC(i);
					IF i >= l THEN
						NEW(uidll, l+128);
						FOR j := 0 TO l-1 DO
							uidll[j] := set.uidls[j]
						END;
						INC(l, 128); set.uidls := uidll
					END;
					Files.ReadString(R, set.uidls[i])
				END;
				set.nouidls := i
			END
		ELSIF set.F = NIL THEN
			set.F := UIDLFile(pop, user, TRUE)
		END;
		lastUIDL := 0;
		RETURN set
	END GetUIDLSet;

	PROCEDURE NewUIDLSet(VAR pop, user: ARRAY OF CHAR): UIDLSet;
		VAR set: UIDLSet;
	BEGIN
		NEW(set); set.next := NIL;
		COPY(pop, set.pop); COPY(user, set.user);
		NEW(set.uidls, 128); set.nouidls := 0;
		set.F := UIDLFile(pop, user, TRUE);
		RETURN set
	END NewUIDLSet;

	PROCEDURE AddUIDL(set: UIDLSet; VAR uidl: UIDL);
		VAR
			R: Files.Rider;
			uidll: UIDLList;
			i, l: LONGINT;
	BEGIN
		Files.Set(R, set.F, Files.Length(set.F));
		Files.WriteString(R, uidl);
		l := LEN(set.uidls^);
		IF l <= set.nouidls THEN
			NEW(uidll, 2*l);
			FOR i := 0 TO l-1 DO
				uidll[i] := set.uidls[i]
			END;
			set.uidls := uidll
		END;
		(*COPY(uidl, set.uidls[set.nouidls]);*)
		set.uidls[set.nouidls] := uidl;
		INC(set.nouidls)
	END AddUIDL;

	PROCEDURE ExistsUIDL(set: UIDLSet; VAR uidl: UIDL): LONGINT;
		VAR
			nouidls, i: LONGINT;
			uidls: UIDLList;
	BEGIN
		nouidls := set.nouidls; uidls := set.uidls;
		i := lastUIDL;
		WHILE (i < nouidls) & (uidls[i] # uidl) DO
			INC(i)
		END;
		IF i >= nouidls THEN
			i := 0;
			WHILE (i < lastUIDL) & (uidls[i] # uidl) DO
				INC(i)
			END;
			IF i < lastUIDL THEN
				RETURN i
			ELSE
				RETURN -1
			END
		ELSE
			lastUIDL := i+1;
			RETURN i
		END
	END ExistsUIDL;

	PROCEDURE FlushUIDL(set: UIDLSet);
	BEGIN
		IF set.F # NIL THEN
			Files.Close(set.F); set.F := NIL
		END
	END FlushUIDL;

	PROCEDURE ParseContent*(h: MIME.Header; VAR cont: MIME.Content);
		VAR
			val: ARRAY 32 OF CHAR;
			pos: LONGINT;
	BEGIN
		cont := NIL;
		pos := MIME.FindField(h, "X-Content-Type");
		IF pos > 0 THEN
			MIME.ExtractContentType(h, pos, cont);
			IF cont.typ.typ = "application" THEN
				COPY(cont.typ.subTyp, val);
				IF Strings.CAPPrefix("oberon", val) THEN
					cont.encoding := MIME.EncAsciiCoder
				ELSIF Strings.CAPPrefix("compressed/oberon", val) THEN
					cont.encoding := MIME.EncAsciiCoderC
				ELSE
					cont := NIL
				END
			ELSE
				cont := NIL
			END
		END;
		IF cont = NIL THEN
			pos := MIME.FindField(h, "Content-Type");
			IF pos < 0 THEN
				pos := MIME.FindField(h, "X-Content-Type")
			END;
			IF pos > 0 THEN
				MIME.ExtractContentType(h, pos, cont);
				IF cont.typ.typ = "text" THEN
					pos := MIME.FindField(h, "Content-Transfer-Encoding");
					MIME.TextEncoding(h, pos, cont)
				END
			ELSE
				NEW(cont); cont.typ := MIME.GetContentType("text/plain");
				IF MIME.FindField(h, "X-Sun-Charset") > 0 THEN
					cont.encoding := MIME.Enc8Bit
				ELSE
					cont.encoding := MIME.EncBin
				END
			END
		END;
		cont.len := MAX(LONGINT)
	END ParseContent;

	PROCEDURE AddMsgHead(pos: LONGINT);
		VAR
			S: Streams.Stream;
			h: MIME.Header;
			cont: MIME.Content;
			nmsgs: MsgHeadList;
			len, i, v: LONGINT;
			str: ARRAY 16 OF CHAR;
	BEGIN
		S := Streams.OpenFileReader(msgsF, pos);
		MIME.ReadHeader(S, NIL, h, len);
		ParseContent(h, cont);
		len := LEN(msgs^);
		IF noMsgs >= len THEN
			NEW(nmsgs, 2*len);
			FOR i := 0 TO noMsgs-1 DO
				nmsgs[i] := msgs[i]
			END;
			msgs := nmsgs
		END;
		msgs[noMsgs].pos := pos;
		msgs[noMsgs].state:= 0;
		msgs[noMsgs].stamp := 0;
		msgs[noMsgs].len := -1;

		pos := MIME.FindField(h, "Reply-To");
		IF pos < 0 THEN
			pos := MIME.FindField(h, "From")
		END;
		(* ASSERT(pos > 0); *)
		MIME.ExtractEMail(h, pos, msgs[noMsgs].replyTo);

		pos := MIME.FindField(h, "Date");
		MIME.ExtractGMTDate(h, pos, msgs[noMsgs].time, msgs[noMsgs].date);

		pos := MIME.FindField(h, "Subject");
		MIME.ExtractValue(h, pos, msgs[noMsgs].subject);

		pos := MIME.FindField(h, "X-Oberon-Status");
		msgs[noMsgs].flags := {}; msgs[noMsgs].topics := {};
		IF pos > 0 THEN
			MIME.ExtractValue(h, pos, str);
			IF CAP(str[0]) = "R" THEN
				INCL(msgs[noMsgs].flags, Read)
			END;
			IF CAP(str[1]) = "D" THEN
				INCL(msgs[noMsgs].flags, Deleted);
				INC(delMsgs); DEC(noMsgs)
			ELSE
				v := 0;
				FOR i := 7 TO 0 BY-1 DO
					IF str[2+i] <= "9" THEN
						v := 16*v+ORD(str[2+i])-ORD("0")
					ELSE
						v := 16*v+ORD(str[2+i])-ORD("A")+10
					END
				END;
				FOR i := MIN(SET) TO MAX(SET) DO
					IF (v MOD 2) > 0 THEN
						INCL(msgs[noMsgs].topics, i)
					END;
					v := v DIV 2
				END
			END
		END;
		INC(noMsgs)
	END AddMsgHead;

	PROCEDURE FindObj(name: ARRAY OF CHAR): Objects.Object;
		VAR obj, context: Objects.Object;
	BEGIN
		context := Gadgets.context;
		obj := Gadgets.FindObj(context, name);
		WHILE (obj = NIL) & (context # NIL) DO
			context := context.dlink;
			obj := Gadgets.FindObj(context, name)
		END;
		RETURN obj
	END FindObj;

	PROCEDURE GetSetting*(name: ARRAY OF CHAR; VAR value: ARRAY OF CHAR; local: BOOLEAN);
		VAR obj: Objects.Object;
	BEGIN
		obj := FindObj(name);
		IF obj # NIL THEN
			Attributes.GetString(obj, "Value", value)
		ELSE
			COPY("", value)
		END;
		IF (value = "") & ~local THEN
			IF ~NetTools.QueryString(name, value) THEN
				COPY("", value)
			END
		END
	END GetSetting;

	PROCEDURE ShowStatus(msg: ARRAY OF CHAR);
		VAR obj: Objects.Object;
	BEGIN
		obj := FindObj("StatusBar");
		IF obj # NIL THEN
			Attributes.SetString(obj, "Value", msg);
			Gadgets.Update(obj)
		ELSE
			Texts.WriteString(W, msg); Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf)
		END
	END ShowStatus;

	PROCEDURE WriteString(VAR R: Files.Rider; str: ARRAY OF CHAR);
		VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE str[i] # 0X DO
			Files.Write(R, str[i]); INC(i)
		END
	END WriteString;

	PROCEDURE WriteLn(VAR R: Files.Rider);
	BEGIN
		Files.WriteBytes(R, Strings.CRLF, 2)
	END WriteLn;

	PROCEDURE SetVPos(F: Objects.Object);
		VAR obj: Objects.Object;
	BEGIN
		Links.GetLink(F, "VPos", obj);
		Attributes.SetInt(obj, "Value", 0);
		Gadgets.Update(obj);
	END SetVPos;

	PROCEDURE Synchronize*;
		VAR
			S: NetTools.Session;
			set, newSet: UIDLSet;
			uidl: UIDL;
			pop, user: ARRAY 64 OF CHAR;
			passwd: ARRAY 16 OF CHAR;
			Ri: Files.Rider;
			uT: Texts.Text;
			Sc: Texts.Scanner;
			R: Texts.Reader;
			pos, i, k, new, maxSize: LONGINT;
			onServer: BOOLEAN;
			obj: Objects.Object;
			ch: CHAR;
			apop, add: BOOLEAN;
	BEGIN
		trace := NetTools.QueryBool("TraceMail");
		GetSetting("POPMode", pop, FALSE); Strings.Upper(pop, pop);
		apop := pop = "APOP";
		GetSetting("MaxMsgSize", user, TRUE);
		Strings.StrToInt(user, maxSize);
		GetSetting("LeaveOnServer", user, TRUE);
		IF user # "" THEN
			Strings.StrToBool(user, onServer)
		ELSE
			onServer := TRUE
		END;
		GetSetting("User", user, FALSE); GetSetting("POP", pop, FALSE);
		NetSystem.GetPassword("pop", pop, user, passwd);
		ShowStatus("downloading...");
		OpenPOP(S, pop, user, passwd, DefPOPPort, apop);
		IF S.res = NetTools.Done THEN
			set := GetUIDLSet(pop, user); newSet := NewUIDLSet(pop, user);
			GetUIDLs(S, uT);
			IF (S.res = NetTools.Done) & (uT # NIL) & (uT.len > 0) THEN
				k := 0;
				WHILE k < set.nouidls DO
					set.uidls[k][63] := 0X; INC(k)
				END;
				Texts.OpenScanner(Sc, uT, 0); Texts.Scan(Sc);
				new := 0; i := 1;
				WHILE (Sc.class = Texts.Int) & (Sc.i = i) & (S.res = NetTools.Done) DO
					Texts.OpenReader(R, uT, Texts.Pos(Sc));
					k := 0; Texts.Read(R, ch);
					WHILE ~R.eot & (ch > " ") DO
						uidl[k] := ch; INC(k);
						Texts.Read(R, ch)
					END;
					uidl[k] := 0X; k := ExistsUIDL(set, uidl); add := TRUE;
					IF k < 0 THEN
						k := MessageSize(S, i);
						IF k <= maxSize THEN
							INC(new);
							Files.Set(Ri, msgsF, Files.Length(msgsF));
							WriteString(Ri, "From "); WriteLn(Ri); (* msg tag *)
							pos := Files.Pos(Ri);
							WriteString(Ri, "X-Oberon-Status: 0010000000"); WriteLn(Ri);
							WriteString(Ri, "X-UIDL: "); WriteString(Ri, uidl); WriteLn(Ri);
							AddUIDL(set, uidl); set.uidls[set.nouidls-1][63] := 01X;
							ReceiveMail(S, i, Ri); add := S.res = NetTools.Done;
							AddMsgHead(pos); msgs[noMsgs-1].len := Files.Length(msgsF)-msgs[noMsgs-1].pos;
							IF add & ~onServer THEN
								Files.Close(msgsF); DeleteMail(S, i)
							END
						ELSE
							Texts.WriteString(W, "message "); Texts.WriteInt(W, i, 0);
							Texts.WriteString(W, " too large ("); Texts.WriteInt(W, k, 0);
							Texts.WriteString(W, " bytes)"); Texts.WriteLn(W);
							Texts.Append(Oberon.Log, W.buf); add := FALSE
						END
					ELSIF set.uidls[k][63] # 0X THEN
						FlushUIDL(newSet); set^ := newSet^;
						HALT(99)
					ELSE
						set.uidls[k][63] := 01X
					END;
					IF add THEN
						AddUIDL(newSet, uidl)
					END;
					Texts.OpenScanner(Sc, uT, Texts.Pos(R));
					INC(i); Texts.Scan(Sc);
					WHILE (Sc.class = Texts.Char) & (Sc.c <= " ") DO
						Texts.Scan(Sc)
					END
				END
			END; 
			ClosePOP(S);
			FlushUIDL(newSet); set^ := newSet^;
			IF new > 0 THEN
				Files.Close(msgsF);
				Gadgets.Update(msgList);
				obj := FindObj("MailList");
				SetVPos(obj)
			END
		END;
		IF S.res # NetTools.Done THEN
			ShowStatus(S.reply)
		ELSIF new = 0 THEN
			ShowStatus("no new mail")
		ELSE
			Strings.IntToStr(new, passwd); Strings.Append(passwd, " new messages");
			ShowStatus(passwd)
		END
	END Synchronize;

	PROCEDURE POPCollect*;
		VAR
			S: NetTools.Session;
			set, newSet: UIDLSet;
			uidl: UIDL;
			pop, user: ARRAY 64 OF CHAR;
			passwd: ARRAY 16 OF CHAR;
			uT: Texts.Text;
			Sc: Texts.Scanner;
			R: Texts.Reader;
			i, k: LONGINT;
			apop: BOOLEAN;
			ch: CHAR;
	BEGIN
		GetSetting("POPMode", pop, FALSE); Strings.Upper(pop, pop);
		apop := pop = "APOP";
		GetSetting("User", user, FALSE); GetSetting("POP", pop, FALSE);
		NetSystem.GetPassword("pop", pop, user, passwd);
		OpenPOP(S, pop, user, passwd, DefPOPPort, apop);
		IF S.res = NetTools.Done THEN
			set := GetUIDLSet(pop, user);
			GetUIDLs(S, uT);
			IF S.res = NetTools.Done THEN
				Texts.OpenScanner(Sc, uT, 0); Texts.Scan(Sc);
				i := 1;
				WHILE (Sc.class = Texts.Int) & (Sc.i = i) & (S.res = NetTools.Done) DO
					Texts.OpenReader(R, uT, Texts.Pos(Sc));
					k := 0; Texts.Read(R, ch);
					WHILE ~R.eot & (ch > " ") DO
						uidl[k] := ch; INC(k);
						Texts.Read(R, ch)
					END;
					uidl[k] := 0X;
					IF ExistsUIDL(set, uidl) >= 0 THEN
						Strings.IntToStr(i, passwd); ShowStatus(passwd);
						DeleteMail(S, i)
					END;
					Texts.OpenScanner(Sc, uT, Texts.Pos(R));
					INC(i); Texts.Scan(Sc);
					WHILE (Sc.class = Texts.Char) & (Sc.c <= " ") DO
						Texts.Scan(Sc)
					END
				END
			END;
			ClosePOP(S)
		END;
		IF S.res # NetTools.Done THEN
			ShowStatus(S.reply)
		ELSE
			newSet := NewUIDLSet(pop, user);
			FlushUIDL(newSet); set^ := newSet^;
			ShowStatus("")
		END
	END POPCollect;

	PROCEDURE ReadString(VAR R: Texts.Reader; VAR s: ARRAY OF CHAR);
		VAR
			l, i: LONGINT;
			ch: CHAR;
	BEGIN
		l := LEN(s)-1; i := 0;
		Texts.Read(R, ch);
		WHILE ~R.eot & (ch # Strings.CR) & (i < l) DO
			s[i] := ch; INC(i);
			Texts.Read(R, ch)
		END;
		WHILE ~R.eot & (ch # Strings.CR) DO
			Texts.Read(R, ch)
		END;
		s[i] := 0X
	END ReadString;

	PROCEDURE ScanHeader(no: LONGINT; VAR h: MIME.Header);
		VAR
			S: Streams.Stream;
			len: LONGINT;
	BEGIN
		S := Streams.OpenFileReader(msgsF, msgs[no].pos); S.mode := Streams.binary;
		MIME.ReadHeader(S, NIL, h, len)
	END ScanHeader;

	PROCEDURE WriteStatus(h: MIME.Header; no: LONGINT);
		VAR
			R: Files.Rider;
			pos, i, v: LONGINT;
			ch: CHAR;
	BEGIN
		pos := MIME.FindField(h, "X-Oberon-Status");
		IF pos > 0 THEN
			pos := msgs[no].pos+pos;
			Files.Set(R, msgsF, pos);
			IF Read IN msgs[no].flags THEN
				Files.Write(R, "R")
			ELSE
				Files.Write(R, "0")
			END;
			IF Deleted IN msgs[no].flags THEN
				Files.Write(R, "D")
			ELSE
				Files.Write(R, "0")
			END;
			v := 0;
			FOR i := MAX(SET) TO MIN(SET) BY -1 DO
				v := 2*v;
				IF i IN msgs[no].topics THEN
					INC(v)
				END
			END;
			FOR i := 0 TO 7 DO
				ch := CHR(ORD("0")+(v MOD 16));
				IF ch > "9" THEN
					ch := CHR(ORD("A")+(v MOD 16)-10)
				END;
				Files.Write(R, ch);
				v := v DIV 16
			END
		END
	END WriteStatus;

	PROCEDURE WriteField(VAR h: MIME.Header; field: ARRAY OF CHAR; empty, long: BOOLEAN);
		VAR
			caption, value: ARRAY 128 OF CHAR;
			pos: LONGINT; first: BOOLEAN;
	BEGIN
		COPY(field, caption);
		pos := MIME.FindField(h, field);
		first := empty;
		WHILE (pos > 0) OR first DO
			first := FALSE; Texts.SetFont(W, headFnt);
			MIME.ExtractValue(h, pos, value);
			IF empty OR (value # "") THEN
				Texts.WriteString(W, caption); Texts.Write(W, ":");
				IF pos > 0 THEN
					Texts.SetFont(W, fieldFnt); Texts.Write(W, Strings.Tab);
					IF long THEN
						WHILE h.fields[pos] # 0X DO
							Texts.Write(W, Strings.ISOToOberon[ORD(h.fields[pos])]); INC(pos)
						END
					ELSE
						Texts.WriteString(W, value)
					END
				END;
				Texts.WriteLn(W)
			END;
			IF (pos > 0) & (field # "") THEN
				MIME.FindFieldPos(h, field, pos)
			ELSE
				pos := -1
			END
		END
	END WriteField;

	PROCEDURE DecodeMessage*(VAR T: Texts.Text; h: MIME.Header; cont: MIME.Content; no: LONGINT);
		VAR
			F, Fc: Files.File;
			R: Texts.Reader;
			str: ARRAY 64 OF CHAR;
			style: TextGadgets.Style;
			topic: Topic;
			pos, len: LONGINT;
			first, ok, oberon: BOOLEAN;
	BEGIN
		oberon := (cont.typ.typ = "application") & (cont.encoding IN {MIME.EncAsciiCoder, MIME.EncAsciiCoderC, MIME.EncAsciiCoderCPlain});
		pos := 0; len := 0;
		Texts.OpenReader(R, T, pos);
		ok := TRUE; ReadString(R, str);
		WHILE ~R.eot & ((~oberon & (len > 0)) OR (str # OberonStart)) DO
			len := Texts.Pos(R);
			IF (str # "") & ok THEN
				pos := Texts.Pos(R)
			ELSE
				ok := FALSE
			END;
			ReadString(R, str)
		END;
		IF str = OberonStart THEN
			F := Files.New(""); len := Texts.Pos(R);
			AsciiCoder.Decode(T, len, F, ok);
			IF ok THEN
				IF cont.encoding = MIME.EncAsciiCoderC THEN
					Fc := Files.New(""); AsciiCoder.Expand(F, Fc)
				ELSE
					Fc := F
				END;
				Texts.Save(T, 0, pos+1, W.buf);
				NEW(T); Texts.Load(T, Fc, 1, len);
				Texts.Insert(T, 0, W.buf)
			END
		END;
		IF no >= 0 THEN
			style := TextGadgets.newStyle();
			Attributes.SetInt(style, "Message", no);
			style.mode := {TextGadgets.left};
			style.noTabs := 1;
			style.tab[0] := 6*(headFnt.maxX-headFnt.minX);
			Texts.WriteObj(W, style);
			WriteField(h, "Reply-To", FALSE, FALSE);
			WriteField(h, "From", TRUE, FALSE);
			WriteField(h, "Subject", TRUE, FALSE);
			IF msgs[no].topics # {} THEN
				Texts.SetFont(W, headFnt);
				Texts.WriteString(W, "Topics:"); Texts.Write(W, Strings.Tab);
				Texts.SetFont(W, fieldFnt);
				first := TRUE;
				FOR pos := MIN(SET) TO MAX(SET) DO
					IF pos IN msgs[no].topics THEN
						topic := topics;
						WHILE (topic # NIL) & (topic.no # pos) DO
							topic:= topic.next
						END;
						IF ~first THEN
							Texts.WriteString(W, ", ")
						ELSE
							first := FALSE
						END;
						IF topic # NIL THEN
							Texts.WriteString(W, topic.topic.s)
						ELSE
							Texts.WriteString(W, "Topic"); Texts.WriteInt(W, pos, 1)
						END
					END
				END;
				Texts.WriteLn(W);
			END;
			WriteField(h, "Date", TRUE, FALSE);
			WriteField(h, "To", TRUE, TRUE);
			WriteField(h, "Cc", FALSE, TRUE);
			WriteField(h, "Bcc", FALSE, TRUE);
			style := TextGadgets.newStyle();
			style.mode := {TextGadgets.left};
			style.noTabs := 0;
			Texts.WriteObj(W, style);
			Texts.Insert(T, 0, W.buf)
		END;
		Texts.SetFont(W, Fonts.Default)
	END DecodeMessage;

	PROCEDURE decodeMessage(no: LONGINT; VAR T: Texts.Text; plain: BOOLEAN);
		VAR
			S: Streams.Stream;
			mT: Texts.Text;
			h: MIME.Header;
			cont: MIME.Content;
			len: LONGINT;
	BEGIN
		S := Streams.OpenFileReader(msgsF, msgs[no].pos); S.mode := Streams.binary;
		IF plain THEN
			NEW(cont); cont.typ := MIME.GetContentType("text/plain");
			S := Streams.OpenFileReader(msgsF, msgs[no].pos)
		ELSE
			MIME.ReadHeader(S, NIL, h, len); ParseContent(h, cont);
			S := Streams.OpenFileReader(msgsF, msgs[no].pos+len)
		END;
		S.mode := Streams.binary;
		cont.len := msgs[no].len;
		IF plain THEN
			Texts.SetFont(W, Fonts.Default)
		ELSE
			Texts.SetFont(W, textFnt)
		END;
		IF cont.typ.typ # "multipart" THEN
			MIME.ReadText(S, W, cont, TRUE)
		ELSE
			MIME.ReadMultipartText(S, mT, cont, TRUE); Texts.Save(mT, 0, mT.len, W.buf)
		END;
		NEW(T); Texts.Open(T, "");
		Texts.Append(T, W.buf);
		IF ~plain THEN
			DecodeMessage(T, h, cont, no)
		END;
		IF ~(Read IN msgs[no].flags) THEN
			INCL(msgs[no].flags, Read);
			WriteStatus(h, no); Files.Close(msgsF);
			Gadgets.Update(msgList)
		END
	END decodeMessage;

	PROCEDURE *DocHandler(D: Objects.Object; VAR M: Objects.ObjMsg);
	BEGIN
		WITH D: Documents.Document DO
			IF M IS Objects.LinkMsg THEN
				WITH M: Objects.LinkMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "DeskMenu" THEN
							M.obj := Gadgets.CopyPublicObject("NetDocs.MailDeskMenu", TRUE);
							IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
							M.res := 0
						ELSIF M.name = "SystemMenu" THEN
							M.obj := Gadgets.CopyPublicObject("NetDocs.MailSystemMenu", TRUE);
							IF M.obj = NIL THEN M.obj := Desktops.NewMenu(SysMenu) END;
							M.res := 0
						ELSIF M.name = "UserMenu" THEN
							M.obj := Gadgets.CopyPublicObject("NetDosc.MailUserMenu", TRUE);
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

	PROCEDURE ShowText(title: ARRAY OF CHAR; T: Texts.Text; reply: BOOLEAN);
		VAR
			D: Documents.Document;
			F: TextGadgets.Frame;
	BEGIN
		NEW(D); TextDocs.InitDoc(D);
		NEW(F); TextGadgets.Init(F, T, FALSE);
		Documents.Init(D, F); COPY(title, D.name);
		IF reply THEN D.handle := DocHandler END;
		Desktops.ShowDoc(D)
	END ShowText;

	PROCEDURE Show*;
		VAR
			S: Attributes.Scanner;
			T: Texts.Text;
			D: Documents.Document;
			obj: Objects.Object;
			F: Texts.Finder;
			no: LONGINT;
			plain: BOOLEAN;
	BEGIN
		Attributes.OpenScanner(S, Oberon.Par.text,Oberon.Par.pos);
		Attributes.Scan(S);
		IF S.class = Attributes.Int THEN
			IF (S.i >= 0) & (S.i < noMsgs) THEN
				decodeMessage(S.i, T, FALSE);
				ShowText("Mail.Text", T, TRUE)
			END
		ELSIF Desktops.IsInMenu(Gadgets.context) THEN
			D := Desktops.CurDoc(Gadgets.context);
			Links.GetLink(D.dsc, "Model", obj);
			IF (obj # NIL) & (obj IS Texts.Text) THEN
				Texts.OpenFinder(F, obj(Texts.Text), 0);
				Texts.FindObj(F, obj);
				IF (obj # NIL) & (obj IS TextGadgets.Style) THEN
					Attributes.SetString(Gadgets.executorObj, "Caption", "Text");
					Attributes.GetInt(obj, "Message", no); plain := TRUE
				ELSE
					Attributes.SetString(Gadgets.executorObj, "Caption", "Source");
					Attributes.GetInt(Gadgets.executorObj, "Message", no); plain := FALSE
				END;
				IF (no >= 0) & (no < noMsgs) THEN
					decodeMessage(no, T, plain);
					Attributes.SetInt(Gadgets.executorObj, "Message", no);
					Links.SetLink(D.dsc, "Model", T)
				END;
				Gadgets.Update(Gadgets.executorObj)
			END
		END
	END Show;

	PROCEDURE Shrink();
		VAR
			F: Files.File;
			R: Files.Rider;
			bak: ARRAY 64 OF CHAR;
			beg, end, offs, i: LONGINT;
			res: INTEGER;
			ch, old: CHAR;
		PROCEDURE Copy();
			VAR
				R, r: Files.Rider;
				ch: CHAR;
		BEGIN
			IF (msgs[i].pos > beg) & (msgs[i].pos < end) THEN
				Files.Set(R, msgsF, beg);
				Files.Set(r, F, Files.Length(F));
				msgs[i].pos := Files.Pos(r)+offs;
				WHILE beg < end DO
					Files.Read(R, ch); Files.Write(r, ch);
					INC(beg)
				END;
				INC(i)
			END
		END Copy;
	BEGIN
		ShowStatus("shrinking message file");
		COPY(MsgFile, bak); Strings.Append(bak, ".Bak");
		Files.Rename(MsgFile, bak, res); ASSERT(res = 0);
		F := Files.New(MsgFile); i := 0;
		msgsF := Files.Old(bak); Files.Set(R, msgsF, 0);
		old := Strings.LF; beg := MAX(LONGINT);
		Files.Read(R, ch);
		WHILE ~R.eof DO
			end := Files.Pos(R)-1;
			IF (ch = "F") & (old = Strings.LF) THEN
				Files.Read(R, ch);
				IF ch = "r" THEN
					Files.Read(R, ch);
					IF ch = "o" THEN
						Files.Read(R, ch);
						IF ch = "m" THEN
							Files.Read(R, ch);
							IF ch = " " THEN
								WHILE ~R.eof & (ch >= " ") DO
									Files.Read(R, ch)
								END;
								WHILE ~R.eof & (ch < " ") DO
									Files.Read(R, ch)
								END;
								IF end > beg THEN
									Copy()
								END;
								offs := Files.Pos(R)-1-end; beg := end
							END
						END
					END
				END
			END;
			old := ch; Files.Read(R, ch)
		END;
		end := Files.Length(msgsF);
		Copy();
		ASSERT(i = noMsgs); delMsgs := 0;
		Files.Register(F); msgsF := F;
		ShowStatus("")
	END Shrink;

	PROCEDURE collect();
		VAR i, j, no: LONGINT;
	BEGIN
		i := 0; j := 0; no := noMsgs;
		WHILE i < no DO
			IF msgs[i].pos >= 0 THEN
				msgs[j] := msgs[i]; INC(j)
			ELSE
				INC(delMsgs); DEC(noMsgs)
			END;
			INC(i)
		END;
		IF delMsgs > 100 THEN
			Shrink()
		END
	END collect;

	PROCEDURE Collect*;
	BEGIN
		delMsgs := 200; collect();
		Gadgets.Update(msgList)
	END Collect;

	PROCEDURE DeleteMessage(no: LONGINT);
		VAR h: MIME.Header;
	BEGIN
		INCL(msgs[no].flags, Deleted);
		ScanHeader(no, h); 
		WriteStatus(h, no);
		msgs[no].pos := -1
	END DeleteMessage;

	PROCEDURE Re*(VAR W: Texts.Writer; VAR t: ARRAY OF CHAR);
		VAR
			i, j, re, oldre: LONGINT;
			p: INTEGER;
			end: BOOLEAN;
		PROCEDURE Blanks();
		BEGIN
			WHILE (t[i] # 0X) & (t[i] <= " ") DO
				INC(i)
			END
		END Blanks;
	BEGIN
		re := 1; i := 0;
		REPEAT
			end := TRUE; Blanks(); j := i;
			IF CAP(t[i]) = "R" THEN
				IF CAP(t[i+1]) = "E" THEN
					INC(i, 2); Blanks();
					IF t[i] = ":" THEN
						INC(i); INC(re); end := FALSE
					ELSIF t[i] = "(" THEN
						INC(i); p := SHORT(i); oldre := re;
						Strings.StrToIntPos(t, re, p);
						IF re > 0 THEN
							i := p; Blanks();
							IF t[i] = ")" THEN
								INC(i); Blanks();
								IF t[i] = ":" THEN
									INC(i)
								END;
								INC(re); end := FALSE
							END
						ELSE
							re := oldre
						END
					END
				END
			END
		UNTIL end;
		IF t[j] = 0X THEN
			RETURN
		ELSIF re > 1 THEN
			Texts.WriteString(W, "Re ("); Texts.WriteInt(W, re, 0); Texts.WriteString(W, "): ")
		ELSE
			Texts.WriteString(W, "Re: ")
		END;
		WHILE t[j] # 0X DO
			Texts.Write(W, t[j]); INC(j)
		END
	END Re;

	PROCEDURE ReplyText(T: Texts.Text);
		VAR
			S: Streams.Stream;
			R: Texts.Reader;
			h: MIME.Header;
			t: ARRAY 512 OF CHAR;
			pos, len: LONGINT;
			ch: CHAR;
	BEGIN
		pos := 0; Texts.OpenReader(R, T, pos);
		Texts.Read(R, ch);
		WHILE ~R.eot & (ch <= " ") & ~(R.lib IS Fonts.Font) DO
			Texts.Read(R, ch); INC(pos)
		END;
		Texts.WriteString(W, "To: ");
		S := TextStreams.OpenReader(T, pos);
		MIME.ReadHeader(S, NIL, h, len);
		pos := MIME.FindField(h, "Reply-To");
		IF pos < 0 THEN
			pos := MIME.FindField(h, "From")
		END;
		MIME.ExtractEMail(h, pos, t);
		Texts.WriteString(W, t); Texts.WriteLn(W);
		pos := MIME.FindField(h, "Subject");
		MIME.ExtractValue(h, pos, t);
		Texts.WriteString(W, "Subject: "); Re(W, t);
		Texts.WriteLn(W)
	END ReplyText;

	PROCEDURE CiteText*(VAR W: Texts.Writer; T: Texts.Text; beg, end: LONGINT);
		VAR
			R: Texts.Reader;
			lib: Objects.Library;
			col, voff: SHORTINT;
			ch: CHAR;
	BEGIN
		lib := W.lib; col := W.col; voff := W.voff;
		Texts.OpenReader(R, T, beg); Texts.Read(R, ch);
		Texts.WriteString(W, "> ");
		WHILE ~R.eot & (Texts.Pos(R) <= end) DO
			Texts.SetFont(W, R.lib); Texts.SetColor(W, R.col); Texts.SetOffset(W, R.voff);
			Texts.Write(W, ch);
			IF (R.lib IS Fonts.Font) & (ch = Strings.CR) & (Texts.Pos(R) < end) THEN
				Texts.SetFont(W, lib); Texts.SetColor(W, col); Texts.SetOffset(W, voff);
				Texts.WriteString(W, "> ")
			END;
			Texts.Read(R, ch)
		END;
		Texts.SetFont(W, lib); Texts.SetColor(W, col); Texts.SetOffset(W, voff)
	END CiteText;

	PROCEDURE Reply*;
		VAR
			S: Attributes.Scanner;
			T, text: Texts.Text;
			D: Documents.Document;
			obj: Objects.Object;
			beg, end, time: LONGINT;
			fnt: Objects.Library;
	BEGIN
		fnt := W.lib; Texts.SetFont(W, textFnt);
		NEW(T); Texts.Open(T, "");
		Attributes.OpenScanner(S, Oberon.Par.text,Oberon.Par.pos);
		Attributes.Scan(S);
		IF S.class = Attributes.Int THEN
			IF (S.i >= 0) & (S.i < noMsgs) THEN
				Texts.WriteString(W, "To: "); Texts.WriteString(W, msgs[S.i].replyTo); Texts.WriteLn(W);
				Texts.WriteString(W, "Subject: "); Re(W, msgs[S.i].subject); Texts.WriteLn(W)
			END
		ELSIF Desktops.IsInMenu(Gadgets.context) THEN
			D := Desktops.CurDoc(Gadgets.context);
			Links.GetLink(D.dsc, "Model", obj);
			IF (obj # NIL) & (obj IS Texts.Text) THEN
				ReplyText(obj(Texts.Text));
				text := NIL; time := -1;
				Oberon.GetSelection(text, beg, end, time);
				IF text = obj THEN
					Texts.WriteLn(W);
					CiteText(W, text, beg, end)
				END
			END
		ELSE
			Texts.WriteString(W, "To: "); Texts.WriteLn(W);
			Texts.WriteString(W, "Subject: "); Texts.WriteLn(W)
		END;
		Texts.WriteLn(W); Texts.Append(T, W.buf);
		ShowText("Mail.Out.Text", T, FALSE);
		Texts.SetFont(W, fnt)
	END Reply;

	PROCEDURE DoTopic(set: BOOLEAN);
		VAR
			S: Attributes.Scanner;
			mailL: Objects.Object;
			topic: Topic;
			C: ListRiders.ConnectMsg;
			R: ListRiders.Rider;
			mLine: ListGadgets.Line;
			h: MIME.Header;
			no: LONGINT;
	BEGIN
		Attributes.OpenScanner(S, Oberon.Par.text,Oberon.Par.pos);
		Attributes.Scan(S);
		IF S.class IN {Attributes.Name, Attributes.String} THEN
			mailL := FindObj(S.s);
			Attributes.Scan(S);
			IF S.class IN {Attributes.Name, Attributes.String} THEN
				topic := topics;
				WHILE (topic # NIL) & (topic.topic.s # S.s) DO
					topic := topic.next
				END;
				IF topic # NIL THEN
					WITH mailL: ListGadgets.Frame DO
						C.R := NIL; Objects.Stamp(C); mailL.obj.handle(mailL.obj, C); R := C.R;
						mLine := mailL.lines;
						REPEAT
							IF mLine.sel THEN
								R.do.Seek(R, mLine.key);
								no := R.d(ListRiders.Int).i;
								IF set THEN
									INCL(msgs[no].topics, topic.no)
								ELSE
									EXCL(msgs[no].topics, topic.no)
								END;
								ScanHeader(no, h); 
								WriteStatus(h, no)
							END;
							mLine := mLine.next
						UNTIL mLine = mailL.lines;
						Files.Close(msgsF); Gadgets.Update(msgList)
					END
				END
			END
		END
	END DoTopic;

	PROCEDURE SetTopic*;
	BEGIN
		DoTopic(TRUE)
	END SetTopic;

	PROCEDURE ClearTopic*;
	BEGIN
		DoTopic(FALSE)
	END ClearTopic;

	PROCEDURE QueryTopic*;
		VAR
			S: Attributes.Scanner;
			obj: Objects.Object;
			topic: Topic;
			query: ARRAY 64 OF CHAR;
	BEGIN
		Attributes.OpenScanner(S, Oberon.Par.text,Oberon.Par.pos);
		Attributes.Scan(S);
		IF S.class IN {Attributes.Name, Attributes.String} THEN
			obj := FindObj(S.s);
			Attributes.Scan(S);
			IF S.class IN {Attributes.Name, Attributes.String} THEN
				topic := topics;
				WHILE (topic # NIL) & (topic.topic.s # S.s) DO
					topic := topic.next
				END;
				IF (obj # NIL) & (topic # NIL) THEN
					query := 'topic="';
					Strings.Append(query, topic.topic.s);
					Strings.AppendCh(query, '"');
					Attributes.SetString(obj, "Value", query);
					Gadgets.Update(obj)
				END
			END
		END
	END QueryTopic;

(*	PROCEDURE LoadMsgs();
		VAR
			R: Files.Rider;
			p: LONGINT;
			ch, old: CHAR;
	BEGIN
		uidls := NIL;
		NEW(msgs, 128); noMsgs := 0; delMsgs := 0;
		msgsF := Files.Old(MsgFile);
		IF msgsF = NIL THEN
			msgsF := Files.New(MsgFile); Files.Register(msgsF)
		END;
		Files.Set(R, msgsF, 0);
		old := Strings.LF; Files.Read(R, ch);
		WHILE ~R.eof DO
			p := Files.Pos(R)-1;
			IF (ch = "F") & (old = Strings.LF) THEN
				Files.Read(R, ch);
				IF ch = "r" THEN
					Files.Read(R, ch);
					IF ch = "o" THEN
						Files.Read(R, ch);
						IF ch = "m" THEN
							Files.Read(R, ch);
							IF ch = " " THEN
								WHILE ~R.eof & (ch >= " ") DO
									Files.Read(R, ch)
								END;
								WHILE ~R.eof & (ch < " ") DO
									Files.Read(R, ch)
								END;
								IF (noMsgs > 0) & (msgs[noMsgs-1].len <= 0) THEN
									msgs[noMsgs-1].len := p-msgs[noMsgs-1].pos
								END;
								AddMsgHead(Files.Pos(R)-1)
							END
						END
					END
				END
			END;
			old := ch; Files.Read(R, ch)
		END;
		IF (noMsgs > 0) & (msgs[noMsgs-1].len <= 0) THEN
			msgs[noMsgs-1].len := p-msgs[noMsgs-1].pos
		END
	END LoadMsgs;	*)

	PROCEDURE LoadMsgs();
(* to do: From at end of buf (cur)
	first msg *)
		CONST BufSize = 4*1024;
		VAR
			R: Files.Rider;
			buf: ARRAY BufSize+4 OF CHAR;
			pat: ARRAY 8 OF CHAR;
			div: ARRAY 8 OF LONGINT;
			pos: LONGINT;
		PROCEDURE Search(VAR pos: LONGINT);
			VAR
				i: LONGINT;
				ch: CHAR;
		BEGIN
			ch := buf[pos]; i := 0;
			WHILE (i # 6) & (ch # 0X) DO
				IF ch = pat[i] THEN
					INC(i);
					IF i < 6 THEN
						INC(pos); ch := buf[pos]
					END
				ELSIF i = 0 THEN
					INC(pos); ch := buf[pos]
				ELSE
					i := i - div[i]
				END
			END;
			IF i # 6 THEN
				pos := -1
			END
		END Search;
		PROCEDURE AddMsgs();
			VAR i, j: LONGINT;
		BEGIN
			i := 0; Search(i);
			WHILE i >= 0 DO
				j := i;
				WHILE buf[i] >= " " DO
					INC(i)
				END;
				WHILE (buf[i] # 0X) & (buf[i] < " ") DO
					INC(i)
				END;
				IF buf[i] # 0X THEN
					IF (noMsgs > 0) & (msgs[noMsgs-1].len <= 0) THEN
						msgs[noMsgs-1].len := pos+j-4-msgs[noMsgs-1].pos
					END;
					AddMsgHead(pos+i)
				ELSE
					pos := pos+j-8;
					Files.Set(R, msgsF, pos);
					RETURN
				END;
				Search(i)
			END;
			IF ~R.eof THEN
				i := BufSize-5;
				WHILE (i < BufSize) & (buf[i] # Strings.LF) DO
					INC(i)
				END;
				IF i < BufSize THEN
					pos := pos+i;
					Files.Set(R, msgsF, pos);
					RETURN
				END
			END;
			INC(pos, BufSize);
			Files.Set(R, msgsF, pos)
		END AddMsgs;
		PROCEDURE CalcDispVec();
			VAR i, j, d: LONGINT;
		BEGIN
			i := 1; d := 1;
			WHILE i <= 6 DO
				j := 0; 
				WHILE ((j + d) < 6) & (pat[j] = pat[j+d]) DO
					INC(j)
				END;
				WHILE i <= j + d DO
					div[i] := d; INC(i)
				END;
				INC(d)
			END
		END CalcDispVec;
	BEGIN
		uidls := NIL; pat := " From "; pat[0] := Strings.LF;
		NEW(msgs, 128); noMsgs := 0; delMsgs := 0;
		msgsF := Files.Old(MsgFile);
		IF msgsF = NIL THEN
			msgsF := Files.New(MsgFile); Files.Register(msgsF)
		END;
		CalcDispVec();
		Files.Set(R, msgsF, 0); buf[BufSize] := 0X;
		IF Files.Length(msgsF) > 7 THEN
			AddMsgHead(7)
		END;
		pos := 0; Files.ReadBytes(R, buf, BufSize);
		WHILE ~R.eof DO
			AddMsgs();
			Files.ReadBytes(R, buf, BufSize)
		END;
		buf[BufSize-R.res] := 0X;
		AddMsgs();
		IF (noMsgs > 0) & (msgs[noMsgs-1].len <= 0) THEN
			msgs[noMsgs-1].len := Files.Length(msgsF)-1-msgs[noMsgs-1].pos
		END
	END LoadMsgs;

	PROCEDURE LoadTopics();
		VAR
			key: ARRAY 32 OF CHAR;
			value: ARRAY 64 OF CHAR;
			topic: Topic;
			i: LONGINT;
	BEGIN
		topics := NIL; i := 0;
		LOOP
			key := "Topic"; Strings.IntToStr(i, value);
			Strings.Append(key, value);
			IF NetTools.QueryString(key, value) THEN
				NEW(topic); topic.next := topics; topics := topic; topic.no := i; INC(i);
				NEW(topic.topic); COPY(value, topic.topic.s)
			ELSE
				EXIT
			END
		END;
		IF topicList # NIL THEN
			Gadgets.Update(topicList)
		END
	END LoadTopics;

	PROCEDURE *Key(R: ListRiders.Rider): LONGINT;
	BEGIN
		RETURN R(Rider).key
	END Key;

	PROCEDURE *Seek(R: ListRiders.Rider; key: LONGINT);
	BEGIN
		WITH R: Rider DO
			R.key := key; R.pos := 0; R.sortPos := 0;
			WHILE (R.pos < noMsgs) & (msgs[R.pos].pos # key) DO
				INC(R.pos)
			END;
			IF R.pos >= noMsgs THEN
				R.key := -1; R.pos := -1; R.sortPos := -1; R.eol := TRUE;
				RETURN
			END;
			IF R.sort # NIL THEN
				WHILE msgs[R.sort[R.sortPos]].pos # key DO
					INC(R.sortPos)
				END
			END;
			R.d(ListRiders.Int).i := R.pos
		END
	END Seek;

	PROCEDURE *Pos(R: ListRiders.Rider): LONGINT;
		VAR pos: LONGINT;
	BEGIN
		WITH R: Rider DO
			IF R.sort # NIL THEN
				pos := R.sortPos
			ELSE
				pos := R.pos
			END;
			IF ~R.ascending THEN
				pos := R.noMsgs-pos-1
			END;
			RETURN pos
		END
	END Pos;

	PROCEDURE *Set(R: ListRiders.Rider; pos: LONGINT);
	BEGIN
		WITH R: Rider DO
			IF (pos >= 0) & (pos < R.noMsgs) THEN
				IF ~R.ascending THEN
					pos := R.noMsgs-pos-1
				END;
				IF R.sort # NIL THEN
					R.pos := R.sort[pos]; R.sortPos := pos
				ELSE
					R.pos := pos; R.sortPos := 0
				END;
				R.key := msgs[R.pos].pos
			ELSE
				R.key := -1; R.pos := -1; R.sortPos := -1; R.eol := TRUE
			END;
			R.d(ListRiders.Int).i := R.pos
		END
	END Set;

	PROCEDURE *GetState(R: ListRiders.Rider): LONGINT;
	BEGIN
		RETURN msgs[R(Rider).pos].state
	END GetState;

	PROCEDURE *SetState(R: ListRiders.Rider; state: LONGINT);
	BEGIN
		msgs[R(Rider).pos].state := state
	END SetState;

	PROCEDURE *GetStamp(R: ListRiders.Rider): LONGINT;
	BEGIN
		RETURN msgs[R(Rider).pos].stamp
	END GetStamp;

	PROCEDURE *SetStamp(R: ListRiders.Rider; stamp: LONGINT);
	BEGIN
		msgs[R(Rider).pos].stamp := stamp
	END SetStamp;

	PROCEDURE *Write(R: ListRiders.Rider; d: ListRiders.Data);
	END Write;

	PROCEDURE *WriteLink(R, linkR: ListRiders.Rider);
	END WriteLink;

	PROCEDURE *DeleteLink(R, linkR: ListRiders.Rider);
		VAR no: LONGINT;
	BEGIN
		R := linkR;
		WITH R: Rider DO
			no := R.pos;
			IF ~(Deleted IN msgs[no].flags) THEN
				DeleteMessage(no);
				Files.Close(msgsF); collect();
				(*R.do.Set(R, no)*)
			END
		END
	END DeleteLink;

	PROCEDURE *Desc(R, old: ListRiders.Rider): ListRiders.Rider;
	END Desc;

	PROCEDURE Less(VAR i, j: MsgHead; sortBy: INTEGER): BOOLEAN;
	BEGIN
		CASE sortBy OF
			SortByDateTime: IF i.date < j.date THEN
											RETURN TRUE
										ELSIF i.date = j.date THEN
											IF i.time < j.time THEN
												RETURN TRUE
											ELSIF i.time > j.time THEN
												RETURN FALSE
											END
										ELSIF i.date > j.date THEN
											RETURN FALSE
										END
			|SortByReplyTo: IF i.replyTo < j.replyTo THEN
										RETURN TRUE
									ELSIF i.replyTo > j.replyTo THEN
										RETURN FALSE
									END
			|SortBySubject: IF i.subject < j.subject THEN
										RETURN TRUE
									ELSIF i.subject > j.subject THEN
										RETURN FALSE
									END
		END;
		RETURN i.pos < j.pos
	END Less;

	PROCEDURE QuickSort(sort: SortList; noMsgs: LONGINT; sortBy: INTEGER);
		PROCEDURE Sort(lo, hi: LONGINT);
			VAR
				i, j: LONGINT;
				m, t: LONGINT;
		BEGIN
			IF lo < hi THEN
				i := lo; j := hi;
				m := sort[(lo + hi) DIV 2];
				REPEAT
					WHILE Less(msgs[sort[i]], msgs[m], sortBy) DO INC(i) END;
					WHILE Less(msgs[m], msgs[sort[j]], sortBy) DO DEC(j) END;
					IF i <= j THEN
						t := sort[i]; sort[i] := sort[j]; sort[j] := t;
						INC(i); DEC(j)
					END
				UNTIL i > j;
				Sort(lo, j); Sort(i, hi)
			END
		END Sort;
	BEGIN
		Sort(0, noMsgs - 1)
	END QuickSort;

	PROCEDURE ToISO(VAR value: ARRAY OF CHAR);
		VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE value[i] # 0X DO
			value[i] := Strings.OberonToISO[ORD(value[i])];
			INC(i)
		END
	END ToISO;
	
	PROCEDURE CompileQuery(VAR Q: Query);
		CONST
			eof = 0; colon = 9; name = 10; string = 11; number = 12; dot = 13; today = 14; now = 15;
			read = 16; unread = 17;
		VAR
			str, keyw: ARRAY 64 OF CHAR;
			pos, num, d, m, y, h, s, sym: LONGINT;
			ch: CHAR;
		PROCEDURE GetName();
			VAR j: LONGINT;
		BEGIN
			j := 0;
			WHILE (ch # 0X) & (Strings.IsAlpha(ch) OR (ch = ".") OR (ch = "@") OR Strings.IsDigit(ch)) DO
				str[j] := ch; INC(j); ch := Q.query[pos]; INC(pos)
			END;
			str[j] := 0X
		END GetName;
		PROCEDURE GetString();
			VAR j: LONGINT;
		BEGIN
			j := 0;
			WHILE (ch # 0X) & (ch # 022X) DO
				str[j] := ch; INC(j); ch := Q.query[pos]; INC(pos)
			END;
			IF ch = 022X THEN
				ch := Q.query[pos]; INC(pos)
			END;
			str[j] := 0X
		END GetString;
		PROCEDURE GetNumber();
		BEGIN
			num := 0;
			WHILE (ch # 0X) & Strings.IsDigit(ch) DO
				num := 10*num+ORD(ch)-ORD("0"); ch := Q.query[pos]; INC(pos)
			END
		END GetNumber;
		PROCEDURE Next();
		BEGIN
			WHILE (ch # 0X) & (ch <= " ") DO
				ch := Q.query[pos]; INC(pos)
			END;
			CASE ch OF
				"=": sym := eq; ch := Q.query[pos]; INC(pos)
				|":": sym := colon; ch := Q.query[pos]; INC(pos)
				|"<": ch := Q.query[pos]; INC(pos);
						IF ch = "=" THEN
							ch := Q.query[pos]; INC(pos); sym := leq
						ELSE
							sym := le
						END
				|">": ch := Q.query[pos]; INC(pos);
						IF ch = "=" THEN
							ch := Q.query[pos]; INC(pos); sym := geq
						ELSE
							sym := ge
						END
				|"&": sym := and; ch := Q.query[pos]; INC(pos)
				|".": sym := dot; ch := Q.query[pos]; INC(pos)
				|"#": sym := neq; ch := Q.query[pos]; INC(pos)
				|"A" .. "Z", "a" .. "z": GetName(); Strings.Upper(str, keyw);
								IF (keyw = "FROM") OR (keyw = "REPLYTO") THEN
									sym := from
								ELSIF keyw = "SUBJECT" THEN
									sym := subject
								ELSIF keyw = "DATE" THEN
									sym := date
								ELSIF keyw = "NOW" THEN
									sym := now
								ELSIF keyw = "TEXT" THEN
									sym := text
								ELSIF keyw = "TIME" THEN
									sym := time
								ELSIF keyw = "TOPIC" THEN
									sym := topic
								ELSIF keyw = "TODAY" THEN
									sym := today
								ELSIF keyw = "OR" THEN
									sym := or
								ELSIF keyw = "READ" THEN
									sym := read
								ELSIF keyw = "UNREAD" THEN
									sym := unread
								ELSE
									sym := name
								END
				|"0" .. "9": sym := number; GetNumber()
				|022X: sym := string; ch := Q.query[pos]; INC(pos); GetString()
			ELSE
				sym := eof
			END
		END Next;
		PROCEDURE Check(sy: LONGINT);
		BEGIN
			IF sy = sym THEN
				Next()
			ELSE
				Q.error := TRUE
			END
		END Check;
		PROCEDURE Factor(): Cond;
			VAR
				cond: Cond;
				topicp: Topic;
		BEGIN
			NEW(cond); cond.field := sym;
			IF sym IN {from, subject, topic, text} THEN
				Next();
				IF sym IN {eq, neq} THEN
					cond.op := sym
				ELSE
					Q.error := TRUE
				END;
				Next();
				IF sym IN {name, string} THEN
					COPY(str, cond.val); Next();
					IF cond.field = topic THEN
						topicp := topics;
						WHILE (topicp # NIL) & ~Strings.CAPCompare(cond.val, topicp.topic.s) DO
							topicp := topicp.next
						END;
						IF topicp # NIL THEN
							cond.time := topicp.no
						ELSIF cond.val = "" THEN
							cond.field := notopic
						ELSE
							Q.error := TRUE
						END
					ELSIF cond.field = text THEN
						ToISO(cond.val)
					END
				ELSE
					Q.error := TRUE
				END
			ELSIF sym = date THEN
				Next();
				IF sym IN {eq, leq, le, geq, ge, neq} THEN
					cond.op := sym
				ELSE
					Q.error := TRUE
				END;
				Next();
				IF sym = today THEN
					MIME.GetClock(cond.time, cond.date); Next()
				ELSE
					Check(number);
					d := num;
					Check(dot);
					Check(number);
					m := num;
					Check(dot);
					Check(number);
					y := num;
					IF y >= 1900 THEN DEC(y, 1900) END;	(* assume user typed 4-digit year *)
					cond.date := (y*16+m)*32+d;
					cond.time := Dates.ToTime(SHORT(Dates.TimeDiff DIV 60), SHORT(Dates.TimeDiff MOD 60), 0);
					Dates.AddTime(cond.time, cond.date, -Dates.TimeDiff * 60)
				END
			ELSIF sym = time THEN
				Next();
				IF sym IN {eq, leq, le, geq, ge, neq} THEN
					cond.op := sym
				ELSE
					Q.error := TRUE
				END;
				Next();
				IF sym = now THEN
					MIME.GetClock(cond.time, cond.date); Next()
				ELSE
					Check(number);
					h := num;
					Check(colon);
					Check(number);
					m := num;
					IF sym = colon THEN
						Check(colon);
						Check(number);
						s := num
					ELSE
						s := 0
					END;
					cond.time := h*1000H + m*40H + s;
					cond.time := Dates.AddMinute(cond.time, -SHORT(Dates.TimeDiff))
				END
			ELSIF sym IN {read, unread} THEN
				cond.field := readFlag; cond.op := eq;
				COPY(keyw, cond.val); Next()
			ELSIF sym IN {name, string} THEN
				cond.field := text; cond.op := eq;
				COPY(str, cond.val); ToISO(cond.val);
				Next()
			ELSE
				Q.error := TRUE
			END;
			IF ~Q.error THEN
				cond.next := Q.conds; Q.conds := cond
			END;
			RETURN cond		
		END Factor;
		PROCEDURE Term(): Cond;
			VAR
				factor: Cond;
				term: Node;
		BEGIN
			factor := Factor();
			WHILE (sym = and) & ~Q.error DO
				NEW(term); term.field := MAX(INTEGER); term.op := and;
				term.next := Q.conds; Q.conds := term; term.left := factor;
				Next(); term.right := Factor(); factor := term
			END;
			RETURN factor
		END Term;
		PROCEDURE Expr(): Cond;
			VAR
				term: Cond;
				expr: Node;
		BEGIN
			term := Term();
			WHILE (sym = or) & ~Q.error DO
				NEW(expr); expr.field := MAX(INTEGER); expr.op := or;
				expr.next := Q.conds; Q.conds := expr; expr.left := term;
				Next(); expr.right := Expr(); term := expr
			END;
			RETURN term
		END Expr;
	BEGIN
		Q.conds := NIL; Q.root := NIL; Q.error := FALSE;
		ch := Q.query[0]; pos := 1;
		Next(); Q.root := Expr();
		IF (sym # eof) OR Q.error THEN
			Q.conds := NIL; Q.root := NIL;
			Q.error := TRUE
		END
	END CompileQuery;

	PROCEDURE TextSearch(cond: Cond; no: LONGINT): BOOLEAN;
		CONST
			MaxPatLen = 128;
		VAR
			i, pos, end, sPatLen: LONGINT;
			R: Files.Rider;
			sPat: ARRAY MaxPatLen OF CHAR;
			sDv: ARRAY MaxPatLen + 1 OF LONGINT;
			ch: CHAR;
		PROCEDURE CalcDispVec();
			VAR i, j, d: LONGINT;
		BEGIN
			i := 1; d := 1;
			WHILE i <= sPatLen DO
				j := 0; 
				WHILE ((j + d) < sPatLen) & (sPat[j] = sPat[j+d]) DO
					INC(j)
				END;
				WHILE i <= j + d DO
					sDv[i] := d; INC(i)
				END;
				INC(d)
			END
		END CalcDispVec;
	BEGIN
		COPY(cond.val, sPat);
		sPatLen := Strings.Length(sPat);
		CalcDispVec();
		IF sPatLen > 0 THEN
			pos := msgs[no].pos; Files.Set(R, msgsF, pos);
			Files.Read(R, ch); INC(pos);
			end := msgs[no].pos+msgs[no].len;
			i := 0;
			WHILE (i # sPatLen) & (pos <= end) DO
				IF ch = sPat[i] THEN
					INC(i);
					IF i < sPatLen THEN
						Files.Read(R, ch); INC(pos)
					END
				ELSIF i = 0 THEN
					Files.Read(R, ch); INC(pos)
				ELSE
					i := i - sDv[i]
				END
			END
		ELSE
			i := -1
		END;
		RETURN i = sPatLen
	END TextSearch;

	PROCEDURE MatchQuery(VAR Q: Query; no: LONGINT; VAR msg: MsgHead): BOOLEAN;
		VAR
			cond: Cond;
			pos, i: LONGINT;
			txt: BOOLEAN;
	BEGIN
		cond := Q.conds; txt := FALSE;
		WHILE cond # NIL DO (* evaluate simple conditions *)
			cond.eval := TRUE;
			CASE cond.field OF
				from: pos := 0;
						Strings.Search(cond.val, msg.replyTo, pos);
						cond.value := ((cond.op = eq) & (pos >= 0)) OR ((cond.op = neq) & (pos < 0))
				|subject: pos := 0;
							Strings.Search(cond.val, msg.subject, pos);
							cond.value := ((cond.op = eq) & (pos >= 0)) OR ((cond.op = neq) & (pos < 0))
				|topic: cond.value := ((cond.op = eq) & (cond.time IN msg.topics)) OR ((cond.op = neq) & ~(cond.time IN msg.topics))
				|notopic: cond.value := msg.topics = {}
				|date: CASE cond.op OF
								eq: cond.value := msg.date = cond.date
								|leq: cond.value := msg.date <= cond.date
								|le: cond.value := msg.date < cond.date
								|geq: cond.value := msg.date >= cond.date
								|ge: cond.value := msg.date > cond.date
								|neq: cond.value := msg.date # cond.date
							END
				|time: CASE cond.op OF
								eq: cond.value := msg.time = cond.time
								|leq: cond.value := msg.time <= cond.time
								|le: cond.value := msg.time < cond.time
								|geq: cond.value := msg.time >= cond.time
								|ge: cond.value := msg.time > cond.time
								|neq: cond.value := msg.time # cond.time
							END
				|readFlag: cond.value := (Read IN msg.flags) = (cond.val[0] = "R")
				|text: txt := TRUE; cond.value := FALSE; cond.eval := FALSE
			ELSE (* or, and *)
				cond.value := FALSE; cond.eval := FALSE
			END;
			cond := cond.next
		END;
		LOOP
			REPEAT
				i := 0; cond := Q.conds; (* evaluate logical ops *)
				WHILE cond # NIL DO
					IF cond IS Node THEN
						WITH cond: Node DO
							IF ~cond.eval THEN
								IF cond.left.eval & cond.right.eval THEN
									IF cond.op = or THEN (* OR *)
										cond.value := cond.left.value OR cond.right.value
									ELSIF cond.op = and THEN (* AND *)
										cond.value := cond.left.value & cond.right.value
									ELSE
										HALT(99)
									END;
									cond.eval := TRUE; INC(i)
								ELSIF (cond.op = or) & ((cond.left.eval & cond.left.value) OR (cond.right.eval & cond.right.value)) THEN
									cond.value := TRUE; cond.eval := TRUE; cond.left.eval := TRUE; cond.right.eval := TRUE; INC(i)
								ELSIF (cond.op = and) & ((cond.left.eval & ~cond.left.value) OR (cond.right.eval & ~cond.right.value)) THEN
									cond.value := FALSE; cond.eval := TRUE; cond.left.eval := TRUE; cond.right.eval := TRUE; INC(i)
								END
							END
						END
					END;
					cond := cond.next
				END
			UNTIL Q.root.eval OR (i <= 0);
			IF Q.root.eval THEN
				RETURN Q.root.value
			ELSIF txt THEN
				cond := Q.conds;
				WHILE cond # NIL DO
					IF (cond.field = text) & ~cond.eval THEN
						cond.value := TextSearch(cond, no);
						cond.eval := TRUE
					END;
					cond := cond.next
				END
			ELSE
				HALT(99)
			END
		END
	END MatchQuery;

	PROCEDURE ConnectRider(VAR M: ListRiders.ConnectMsg; base: Model);
		VAR
			R: Rider;
			int: ListRiders.Int;
			i: LONGINT;
			Q: Query;
	BEGIN
		NEW(R); R.do := mMethod; R.sort := NIL;
		R.noMsgs := noMsgs; Q.error := FALSE;
		IF M IS ConnectMsg THEN
			WITH M: ConnectMsg DO
				R.ascending := M.ascending;
				IF ((M.sortBy > 0) OR (M.query # "")) & (noMsgs > 0) THEN
					NEW(R.sort, noMsgs);
					FOR i := 0 TO noMsgs-1 DO
						R.sort[i] := i
					END;
					IF M.query # "" THEN
						COPY(M.query, Q.query);
						CompileQuery(Q);
						IF ~Q.error THEN
							R.noMsgs := 0;
							FOR i := 0 TO noMsgs-1 DO
								IF MatchQuery(Q, i, msgs[i]) THEN
									R.sort[R.noMsgs] := i; INC(R.noMsgs)
								END
							END
						ELSE
							ShowStatus("error in query")
						END
					END;
					IF M.sortBy > 0 THEN
						QuickSort(R.sort, R.noMsgs, M.sortBy)
					END
				END
			END
		ELSE
			R.ascending := FALSE
		END;
		R.base := base; R.dsc := FALSE; R.eol := FALSE;
		NEW(int); R.d := int;
		R.do.Set(R, 0); M.R := R
	END ConnectRider;

	PROCEDURE *ModelHandler(obj: Objects.Object; VAR M: Objects.ObjMsg);
	BEGIN
		WITH obj: Model DO
			IF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.class := Objects.String; M.s := "Mail.NewModel"; M.res := 0
					ELSE
						Gadgets.objecthandle(obj, M)
					END
				END
			ELSIF M IS Objects.CopyMsg THEN
				M(Objects.CopyMsg).obj := obj
			ELSIF M IS ListRiders.ConnectMsg THEN
				ConnectRider(M(ListRiders.ConnectMsg), obj)
			ELSE
				Gadgets.objecthandle(obj, M)
			END
		END
	END ModelHandler;

	PROCEDURE NewModel*;
	BEGIN
		 Objects.NewObj := msgList
	END NewModel;

	PROCEDURE *GetRider(F: ListGadgets.Frame; new: BOOLEAN): ListRiders.Rider;
		VAR
			M: ConnectMsg;
			i: LONGINT;
	BEGIN
		IF ((F.R = NIL) OR new) & (F.obj # NIL) THEN
			IF F IS Frame THEN
				WITH F: Frame DO
					Attributes.GetString(F.sortBy, "Value", M.query);
					Strings.Upper(M.query, M.query);
					IF (M.query = "DATE") OR (M.query = "TIME") THEN
						M.sortBy := SortByDateTime
					ELSIF M.query = "REPLYTO" THEN
						M.sortBy := SortByReplyTo
					ELSIF M.query = "SUBJECT" THEN
						M.sortBy := SortBySubject
					ELSE
						Attributes.GetInt(F.sortBy, "Value", i);
						M.sortBy := SHORT(i)
					END;
					Attributes.GetBool(F.ascending, "Value", M.ascending);
					Attributes.GetString(F.query, "Value", M.query)
				END
			ELSE
				M.sortBy := 0; M.ascending := FALSE; M.query := ""
			END;
			M.R := NIL; Objects.Stamp(M);
			F.obj.handle(F.obj, M); F.R := M.R
		END;
		RETURN F.R
	END GetRider;

	PROCEDURE *FormatLine(F: ListGadgets.Frame; R: ListRiders.Rider; L: ListGadgets.Line);
	BEGIN
		L.w := F.W; L.h := F.fnt.height; L.dsr := -F.fnt.minY; L.dx := 0
	END FormatLine;

	PROCEDURE *DisplayLine(F: ListGadgets.Frame; Q: Display3.Mask; x, y, w, h: INTEGER; R: ListRiders.Rider; L: ListGadgets.Line);
		VAR
			Q2: Display3.Mask;
			str: ARRAY 16 OF CHAR;
			textC: INTEGER;
	BEGIN
		Display3.ReplConst(Q, F.backC, x, y, w-50, h, Display.replace);
		WITH R: Rider DO
			IF Read IN msgs[R.pos].flags THEN
				textC := F.textC
			ELSE
				textC := Display3.red
			END;
			Display3.String(Q, textC, x + (w DIV 3) + 8, y + L.dsr, F.fnt, msgs[R.pos].subject, Display.paint);
			Display3.Copy(Q, Q2); Display3.AdjustMask(Q2, x, y, w DIV 3, h);
			Display3.String(Q2, textC, x, y + L.dsr, F.fnt, msgs[R.pos].replyTo, Display.paint);
			Strings.DateToStr(msgs[R.pos].date, str);
			Display3.ReplConst(Q, F.backC, x+w-50, y, 50, h, Display.replace);
			Display3.String(Q, textC, x+w-42, y + L.dsr, F.fnt, str, Display.paint)
		END
	END DisplayLine;

	PROCEDURE CopyFrame(VAR M: Objects.CopyMsg; from, to: Frame);
	BEGIN
		ListGadgets.CopyFrame(M, from, to);
		to.query := Gadgets.CopyPtr(M, from.query);
		to.sortBy := Gadgets.CopyPtr(M, from.sortBy);
		to.ascending := Gadgets.CopyPtr(M, from.ascending)
	END CopyFrame;

	PROCEDURE Update(F: Frame);
		VAR M: Gadgets.UpdateMsg;
	BEGIN
		M.F := F; M.obj := F.obj;
		Display.Broadcast(M);
		SetVPos(F)
	END Update;

	PROCEDURE *FrameHandler(F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			F1: Frame;
			obj: Objects.Object;
			ver: INTEGER;
	BEGIN
		WITH F: Frame DO
			IF M IS Display.FrameMsg THEN
				WITH M: Display.FrameMsg DO
					IF (M.F = NIL) OR (M.F = F) THEN
						IF M IS Gadgets.UpdateMsg THEN
							WITH M: Gadgets.UpdateMsg DO
								IF M.obj # NIL THEN
									IF M.obj = F.query THEN
										Update(F)
									ELSIF M.obj = F.sortBy THEN
										Update(F)
									ELSIF M.obj = F.ascending THEN
										Update(F)
									ELSE
										ListGadgets.FrameHandler(F, M)
									END
								ELSE
									ListGadgets.FrameHandler(F, M)
								END
							END
						ELSE
							ListGadgets.FrameHandler(F, M)
						END
					ELSE
						ListGadgets.FrameHandler(F, M)
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.class := Objects.String; M.s := "Mail.NewFrame"; M.res := 0
					ELSE
						ListGadgets.FrameHandler(F, M)
					END
				END
			ELSIF M IS Objects.LinkMsg THEN
				WITH M: Objects.LinkMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "SortBy" THEN
							M.obj := F.sortBy; M.res := 0
						ELSIF M.name = "Ascending" THEN
							M.obj := F.ascending; M.res := 0
						ELSIF M.name = "Query" THEN
							M.obj := F.query; M.res := 0
						ELSE
							ListGadgets.FrameHandler(F, M)
						END
					ELSIF M.id = Objects.set THEN
						IF M.name = "SortBy" THEN
							F.sortBy := M.obj; M.res := 0
						ELSIF M.name = "Ascending" THEN
							F.ascending := M.obj; M.res := 0
						ELSIF M.name = "Query" THEN
							F.query := M.obj; M.res := 0
						ELSE
							ListGadgets.FrameHandler(F, M)
						END
					ELSIF M.id = Objects.enum THEN
						ListGadgets.FrameHandler(F, M);
						M.Enum("SortBy"); M.Enum("Ascending"); M.Enum("Query")
					ELSE
						ListGadgets.FrameHandler(F, M)
					END
				END
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					IF M.stamp = F.stamp THEN
						M.obj := F.dlink
					ELSE
						NEW(F1); F.stamp := M.stamp; F.dlink := F1;
						CopyFrame(M, F, F1); M.obj := F1
					END
				END
			ELSIF M IS Objects.FileMsg THEN
				WITH M: Objects.FileMsg DO
					IF M.id = Objects.load THEN
						Files.ReadInt(M.R, ver); ASSERT(ver = Version);
						Gadgets.ReadRef(M.R, F.lib, F.sortBy);
						Gadgets.ReadRef(M.R, F.lib, F.ascending);
						Gadgets.ReadRef(M.R, F.lib, F.query)
					ELSIF M.id = Objects.store THEN
						Files.WriteInt(M.R, Version);
						Gadgets.WriteRef(M.R, F.lib, F.sortBy);
						Gadgets.WriteRef(M.R, F.lib, F.ascending);
						Gadgets.WriteRef(M.R, F.lib, F.query)
					END;
					ListGadgets.FrameHandler(F, M);
					IF M.id = Objects.load THEN
						Links.GetLink(F, "VRange", obj);
						Attributes.SetInt(obj, "Value", noMsgs)
					END
				END
			ELSE
				ListGadgets.FrameHandler(F, M)
			END
		END
	END FrameHandler;

	PROCEDURE InitFrame(F: Frame);
	BEGIN
		ListGadgets.InitFrame(F);
		F.handle := FrameHandler; F.do := vMethod; F.tab := 8;
		F.ascending := NIL; F.sortBy := NIL; F.query := NIL;
		Attributes.SetString(F, "Cmd", "Mail.Show #Point")
	END InitFrame;

	PROCEDURE NewFrame*;
		VAR F: Frame;
	BEGIN
		NEW(F); InitFrame(F);
		Objects.NewObj := F
	END NewFrame;

	PROCEDURE *TopicKey(R: ListRiders.Rider): LONGINT;
	BEGIN
		WITH R: TopicRider DO
			IF R.topic # NIL THEN
				RETURN R.topic.no
			ELSE
				RETURN 0
			END
		END
	END TopicKey;

	PROCEDURE *TopicSeek(R: ListRiders.Rider; key: LONGINT);
	BEGIN
		WITH R: TopicRider DO
			R.topic := topics;
			WHILE (R.topic # NIL) & (R.topic.no # key) DO
				R.topic := R.topic.next
			END;
			IF R.topic # NIL THEN
				R.d := R.topic.topic
			END;
			R.eol := R.topic = NIL
		END
	END TopicSeek;

	PROCEDURE *TopicPos(R: ListRiders.Rider): LONGINT;
	BEGIN
		RETURN R.do.Key(R)
	END TopicPos;

	PROCEDURE *TopicSet(R: ListRiders.Rider; pos: LONGINT);
	BEGIN
		R.do.Seek(R, pos)
	END TopicSet;

	PROCEDURE *TopicGetState(R: ListRiders.Rider): LONGINT;
	BEGIN
		RETURN R(TopicRider).topic.state
	END TopicGetState;

	PROCEDURE *TopicSetState(R: ListRiders.Rider; state: LONGINT);
	BEGIN
		R(TopicRider).topic.state := state
	END TopicSetState;

	PROCEDURE *TopicGetStamp(R: ListRiders.Rider): LONGINT;
	BEGIN
		RETURN R(TopicRider).topic.stamp
	END TopicGetStamp;

	PROCEDURE *TopicSetStamp(R: ListRiders.Rider; stamp: LONGINT);
	BEGIN
		R(TopicRider).topic.stamp := stamp
	END TopicSetStamp;

	PROCEDURE *TopicDeleteLink(R, linkR: ListRiders.Rider);
	BEGIN
	END TopicDeleteLink;

	PROCEDURE ConnectTopicRider(VAR M: ListRiders.ConnectMsg; base: Model);
		VAR
			R: TopicRider;
	BEGIN
		NEW(R); R.do := tmMethod;
		R.base := base; R.dsc := FALSE; R.eol := FALSE;
		R.do.Set(R, 0); M.R := R
	END ConnectTopicRider;

	PROCEDURE *TopicModelHandler(obj: Objects.Object; VAR M: Objects.ObjMsg);
	BEGIN
		WITH obj: Model DO
			IF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.class := Objects.String; M.s := "Mail.NewTopicModel"; M.res := 0
					ELSE
						Gadgets.objecthandle(obj, M)
					END
				END
			ELSIF M IS Objects.CopyMsg THEN
				M(Objects.CopyMsg).obj := obj
			ELSIF M IS ListRiders.ConnectMsg THEN
				ConnectTopicRider(M(ListRiders.ConnectMsg), obj)
			ELSE
				Gadgets.objecthandle(obj, M)
			END
		END
	END TopicModelHandler;

	PROCEDURE NewTopicModel*;
	BEGIN
		Objects.NewObj := topicList
	END NewTopicModel;

	PROCEDURE Recipient(VAR i: LONGINT; VAR s, rcpt: ARRAY OF CHAR);
		VAR
			j, k, end, dom: LONGINT;
			candidate: ARRAY 128 OF CHAR;
			special: BOOLEAN;
			ch, old, close: CHAR;
	BEGIN
		IF simpler THEN
			WHILE (s[i] # 0X) & (s[i] <= " ") DO
				INC(i)
			END;
			IF s[i] = "," THEN
				INC(i);
				WHILE (s[i] # 0X) & (s[i] <= " ") DO
					INC(i)
				END
			END;
			j := 0;
			WHILE (s[i] > " ") & (s[i] # ",") DO
				rcpt[j] := s[i];
				INC(j); INC(i)
			END;
			rcpt[j] := 0X
		ELSE
			j := i; ch := s[j]; old := 01X; close := 02X;
			WHILE (ch # 0X) & ~( ((ch = ",") & (close = 02X)) OR (old = close) ) DO
				IF ch = "(" THEN
					close := ")"
				ELSIF ch = "<" THEN
					close := ">"
				ELSIF ch = "{" THEN
					close := "}"
				ELSIF ch = "[" THEN
					close := "]"
				ELSIF ch = 22X THEN
					close := 22X
				END;
				INC(j); old := ch; ch := s[j]
			END;
			IF old # close THEN
				end := j
			ELSE
				end := j-1
			END;
			WHILE (j >= i) & (s[j] <= " ") DO
				DEC(j)
			END;
			WHILE (j >= i) & (s[j] > " ") DO
				DEC(j)
			END;
			INC(j);
			k := 0; dom := -1; special := FALSE; ch := s[j];
			IF ch = "(" THEN
				close := ")"; INC(j)
			ELSIF ch = "<" THEN
				close := ">"; INC(j)
			ELSIF ch = "{" THEN
				close := "}"; INC(j)
			ELSIF ch = "[" THEN
				close := "]"; INC(j)
			ELSE
				close := 02X
			END;
			ch := s[j];
			WHILE (ch > " ") & (j < end) & (ch # close) DO
				IF ch = "@" THEN
					dom := j
				ELSIF (dom < 0) & ((ch = "(") OR (ch = ")") OR (ch = "<") OR (ch = ">") OR (ch = ",") OR (ch = ";") OR (ch = ":") OR
					(ch = "\") OR (ch = 22X) OR (*(ch = ".") OR*) (ch = "[") OR (ch = "]") OR (ch = "/")) THEN
					special := TRUE
				END;
				candidate[k] := ch; INC(k); INC(j); ch := s[j]
			END;
			candidate[k] := 0X;
			IF special THEN
				IF candidate[0] # 22X THEN
					rcpt[0] := 22X; k := 1
				ELSE
					k := 0
				END; j := 0;
				WHILE (candidate[j] # 0X) & (candidate[j] # "@") DO
					rcpt[k] := candidate[j]; INC(k); INC(j)
				END;
				rcpt[k] := 22X; INC(k);
				WHILE candidate[j] # 0X DO
					rcpt[k] := candidate[j]; INC(k); INC(j)
				END;
				IF candidate[j-1] = 22X THEN
					DEC(k)
				END;
				rcpt[k] := 0X
			ELSE
				COPY(candidate, rcpt)
			END;
			WHILE (s[end] # 0X) & (s[end] # ",") DO
				INC(end)
			END;
			IF s[end] = "," THEN
				i := end+1
			ELSE
				i := end
			END
		END
	END Recipient;

	PROCEDURE QueryContType*(T: Texts.Text; beg: LONGINT; cont: MIME.Content);
		VAR R: Texts.Reader; ch: CHAR;
	BEGIN
		cont.typ := MIME.GetContentType("text/plain"); cont.encoding := MIME.EncBin;
		Texts.OpenReader(R, T, beg); Texts.Read(R, ch);
		WHILE ~R.eot & ((ch <= " ") OR ~(R.lib IS Fonts.Font)) DO
			Texts.Read(R, ch)
		END;
		WHILE ~R.eot DO
			IF ~(R.lib IS Fonts.Font) THEN
				cont.typ := MIME.GetContentType(MIME.OberonMime);
				cont.encoding := MIME.EncAsciiCoderC; RETURN
			ELSIF ch > CHR(127) THEN
				cont.encoding := MIME.Enc8Bit
			END;
			Texts.Read(R, ch)
		END
	END QueryContType;

	PROCEDURE ReadResponse(S: SMTPSession);
		VAR
			reply: ARRAY NetTools.MaxLine OF CHAR;
			l: LONGINT;
	BEGIN
		NetSystem.ReadString(S.C, S.reply);
		IF trace THEN
			Texts.WriteString(W, "RCV: "); Texts.WriteString(W, S.reply);
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END;
		Strings.StrToInt(S.reply, l); S.status := SHORT(l);
		COPY(S.reply, reply);
		WHILE reply[3] = "-" DO
			NetSystem.ReadString(S.C, reply);
			IF trace THEN
				Texts.WriteString(W, "RCV: "); Texts.WriteString(W, S.reply);
				Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
			END
		END
	END ReadResponse;

	PROCEDURE CloseSMTP*(S: SMTPSession);
	BEGIN
		IF S.C # NIL THEN
			SendCmd(S, "QUIT", "");
			(*NetSystem.ReadString(S.C, S.reply);*)
			S.res := NetTools.Done;
			NetTools.Disconnect(S.C); S.C := NIL; S.S := NIL
		ELSE
			S.res := NetTools.Failed
		END
	END CloseSMTP;

	PROCEDURE OpenSMTP*(VAR S: SMTPSession; host, from: ARRAY OF CHAR; port: INTEGER);
	BEGIN
		IF trace THEN
			Texts.WriteString(W, "--- SMTP");
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END;
		IF (port <= 0) OR (port >= 10000) THEN
			port := DefSMTPPort
		END;
		NEW(S);
		IF (host[0] # "<") & (host[0] # 0X) THEN
			IF NetTools.Connect(S.C, port, host, FALSE) THEN
				S.S := NetTools.OpenStream(S.C);
				ReadResponse(S);
				IF S.reply[0] = "2" THEN
					SendCmd(S, "HELO", NetSystem.hostName);
					ReadResponse(S);
					IF S.reply[0] = "2" THEN
						COPY(from, S.from); S.res := NetTools.Done;
						RETURN
					END
				END;
				CloseSMTP(S)
			ELSE
				S.reply := "no connection"
			END
		ELSE
			S.reply := "no smtp-host specified"
		END;
		S.res := NetTools.Failed; S.C := NIL; S.S := NIL
	END OpenSMTP;

	PROCEDURE SendReplyLine*(S: NetTools.Session; cont: MIME.Content);
	BEGIN
		S.reply := "Done ";
		CASE cont.encoding OF
			MIME.EncBin: Strings.Append(S.reply, "ASCII")
			|MIME.Enc8Bit: Strings.Append(S.reply, "ASCII (ISO 8bit)")
			|MIME.Enc7Bit: Strings.Append(S.reply, "ASCII (ISO 7bit)")
			|MIME.EncQuoted: Strings.Append(S.reply, "ASCII (ISO quoted)")
			|MIME.EncAsciiCoder, MIME.EncAsciiCoderC: Strings.Append(S.reply, "Oberon + Text")
			|MIME.EncAsciiCoderCPlain: Strings.Append(S.reply, "Oberon")
		ELSE
			Strings.Append(S.reply, "???")
		END
	END SendReplyLine;

	PROCEDURE MakeAscii*(body: Texts.Text; beg, end: LONGINT; compress: BOOLEAN; VAR ascii: Texts.Text);
		VAR
			F, Fc: Files.File;
			buf: Texts.Buffer;
			len: LONGINT;
	BEGIN
		NEW(buf); Texts.OpenBuf(buf);
		Texts.Save(body, beg, end, buf);
		NEW(ascii); Texts.Open(ascii, "");
		Texts.Append(ascii, buf);
		F := Files.New("");
		Texts.Store(ascii, F, 0, len);
		IF compress THEN
			Fc := Files.New("");
			AsciiCoder.Compress(F, Fc);
			F := Fc
		END;
		NEW(ascii); Texts.Open(ascii, "");
		AsciiCoder.Code(F, ascii)
	END MakeAscii;

	PROCEDURE SendText*(S: SMTPSession; head, body: Texts.Text; beg, end: LONGINT; cont: MIME.Content);
		VAR
			enc: LONGINT;
			ascii: Texts.Text;
	BEGIN
		enc := cont.encoding; cont.len := MAX(LONGINT);
		SendCmd(S,"From: ", S.from);
		SendCmd(S, "X-Mailer:", mailer);
		IF enc IN {MIME.EncAsciiCoder, MIME.EncAsciiCoderC, MIME.EncAsciiCoderCPlain} THEN
			SendCmd(S, "X-Content-Type:", MIME.OberonMime);
			cont.encoding := MIME.Enc8Bit
		END;
		IF cont.encoding # MIME.EncBin THEN
			MIME.WriteISOMime(S.S, cont)
		END;
		cont.encoding := MIME.Enc8Bit;
		MIME.WriteText(head, 0, head.len, S.S, cont, TRUE, FALSE);
		NetSystem.WriteString(S.C, "");
		IF enc IN {MIME.EncAsciiCoder, MIME.EncAsciiCoderC, MIME.EncAsciiCoderCPlain} THEN
			IF enc IN {MIME.EncAsciiCoder, MIME.EncAsciiCoderC} THEN
				MIME.WriteText(body, beg, end, S.S, cont, TRUE, FALSE)
			END;
			NetSystem.WriteString(S.C, "");
			NetSystem.WriteString(S.C, OberonStart);
			MakeAscii(body, beg, end, enc # MIME.EncAsciiCoder, ascii);
			MIME.WriteText(ascii, 0, ascii.len, S.S, cont, TRUE, TRUE)
		ELSE
			cont.encoding := enc;
			MIME.WriteText(body, beg, end, S.S, cont, TRUE, TRUE)
		END;
		cont.encoding := enc;
		NetSystem.WriteString(S.C, ".")
	END SendText;

	PROCEDURE SendMail*(S: SMTPSession; T: Texts.Text; cont: MIME.Content; autoCc: BOOLEAN);
		VAR
			R: Texts.Reader;
			t: ARRAY 2048 OF CHAR;
			pos: LONGINT;
			head: Texts.Text;
			ch, old: CHAR;
		PROCEDURE Recipients(VAR pos: LONGINT): BOOLEAN;
			VAR
				R: Texts.Reader;
				t: ARRAY 2048 OF CHAR;
				i: LONGINT;
				rcpt: ARRAY 64 OF CHAR;
				first: BOOLEAN;
		BEGIN
			Texts.OpenReader(R, T, pos); ReadString(R, t); first := TRUE;
			WHILE (Strings.CAPPrefix("TO:", t) OR Strings.CAPPrefix("CC:", t) OR Strings.CAPPrefix("BCC:", t)) OR
				(~first & (t[0] = " ") OR (t[0] = 09X)) DO
				Texts.WriteString(W, t); Texts.WriteLn(W);
				IF (t[0] = " ") OR (t[0] = 09X) THEN
					i := 1
				ELSIF Strings.CAPPrefix("BCC:", t) THEN
					i := 4
				ELSE
					i := 3
				END;
				Recipient(i, t, rcpt);
				WHILE rcpt # "" DO
					Texts.Append(head, W.buf);
					Texts.WriteString(W, "To: "); Texts.WriteString(W, rcpt);
					Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
					SendCmd(S, "RCPT TO:", rcpt); ReadResponse(S);
					IF S.reply[0] # "2" THEN
						S.res := NetTools.Failed; RETURN FALSE
					END;
					Recipient(i, t, rcpt); first := FALSE
				END;
				pos := Texts.Pos(R); ReadString(R, t)
			END;
			IF autoCc THEN
				Texts.WriteString(W, "Cc: "); Texts.WriteString(W, S.from);
				Texts.WriteLn(W); Texts.Append(head, W.buf);
				SendCmd(S, "RCPT TO:", S.from); ReadResponse(S);
				IF S.reply[0] # "2" THEN
					S.res := NetTools.Failed; RETURN FALSE
				END
			END;
			Texts.Append(head, W.buf);
			RETURN TRUE
		END Recipients;
	BEGIN
		Texts.OpenReader(R, T, 0); Texts.Read(R, ch); pos := 1;
		WHILE ~R.eot & ((ch <= " ") OR ~(R.lib IS Fonts.Font)) DO
			Texts.Read(R, ch); INC(pos)
		END;
		DEC(pos); Texts.OpenReader(R, T, pos);
		REPEAT
			pos := Texts.Pos(R); ReadString(R, t)
		UNTIL R.eot OR Strings.CAPPrefix("TO:", t) OR Strings.CAPPrefix("CC:", t) OR Strings.CAPPrefix("BCC:", t);
		IF ~R.eot THEN
			SendCmd(S, "MAIL FROM:", S.from); ReadResponse(S);
			IF S.reply[0] = "2" THEN
				S.res := NetTools.Done;
				NEW(head); Texts.Open(head, "");
				IF Recipients(pos) THEN
					Texts.OpenReader(R, T, pos);
					old := 0X; Texts.Read(R, ch);
					WHILE ~R.eot & ~( ((old = Strings.CR) OR (old = Strings.LF)) & ((ch = Strings.CR) OR (ch = Strings.LF)) ) DO
						old := ch; Texts.Read(R, ch)
					END;
					Texts.Save(T, pos, Texts.Pos(R)-1, W.buf);
					Texts.Append(head, W.buf);
					SendCmd(S, "DATA", ""); ReadResponse(S);
					IF S.reply[0] = "3" THEN
						SendText(S, head, T, Texts.Pos(R), T.len, cont); ReadResponse(S);
						IF S.reply[0] = "2" THEN
							SendReplyLine(S, cont); RETURN
						END
					END
				END
			END
		ELSE
			S.reply := "no recipient"
		END;
		S.res := NetTools.Failed
	END SendMail;

	(** (es), Mail.Send ( @ | ^ | {mailfile} ~ ) *)
	PROCEDURE Send*;
		VAR
			email, server, val: ARRAY 64 OF CHAR;
			S: SMTPSession;
			cont: MIME.Content;
			Sc: Texts.Scanner;
			T, sig: Texts.Text;
			F: Texts.Finder;
			obj: Objects.Object;
			beg, end, time, i: LONGINT;
			autoCc: BOOLEAN;
		PROCEDURE SendIt();
		BEGIN
			IF T # NIL THEN
				IF cont.encoding = MIME.EncAuto THEN
					QueryContType(T, beg, cont)
				END;
				GetSetting("MailSignature", val, FALSE);
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
				OpenSMTP(S, server, email, DefSMTPPort);
				IF S.res = NetTools.Done THEN
					ShowStatus("mailing ");
					SendMail(S, T, cont, autoCc);
					CloseSMTP(S)
				END;
				ShowStatus(S.reply)
			ELSE
				ShowStatus("no text")
			END
		END SendIt;
	BEGIN
		trace := NetTools.QueryBool("TraceMail");
		GetSetting("EMail", email, FALSE);
		GetSetting("SMTP", server, FALSE);
		GetSetting("AutoCc", val, TRUE);
		Strings.StrToBool(val, autoCc);
		IF email = "" THEN
			ShowStatus("no return address set"); RETURN
		ELSE
			i := 0; Recipient(i, email, val);
			IF val # email THEN
				ShowStatus("invalid return address"); RETURN
			END
		END;
		GetSetting("ContType", val, TRUE);
		NEW(cont); cont.typ := MIME.GetContentType("text/plain");
		IF val[0] = "0" THEN
			cont.encoding := MIME.EncBin
		ELSIF val[0] = "1" THEN
			cont.encoding := MIME.Enc8Bit
		ELSIF val[0] = "2" THEN
			cont.typ := MIME.GetContentType(MIME.OberonMime); cont.encoding := MIME.EncAsciiCoderC
		ELSE
			cont.encoding := MIME.EncAuto
		END;
		beg := 0; T := NIL;
		Texts.OpenScanner(Sc, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(Sc);
		IF (Sc.class = Texts.Char) & (Sc.c = "*") THEN (* send marked text *)
			T := Oberon.MarkedText(); SendIt()
		ELSIF (Sc.class = Texts.Char) & (Sc.c = "^") THEN (* send selected text *)
			Oberon.GetSelection(T, beg, end, time);
			IF time >= 0 THEN
				Texts.OpenScanner(Sc, T, beg); Texts.Scan(Sc);
				IF Sc.class IN {Texts.Name, Texts.String} THEN NEW(T); Texts.Open(T, Sc.s); SendIt() END
			END
		ELSIF (Sc.class = Texts.Char) & (Sc.c = "@") THEN (* Send button (mailto url) *)
			IF Gadgets.executorObj # NIL THEN
				Gadgets.GetObjName(Gadgets.executorObj, val);
				IF val = "mailto" THEN
					Links.GetLink(Gadgets.context, "Model", obj);
					IF (obj # NIL) & (obj IS Texts.Text) THEN
						T := obj(Texts.Text);
						Texts.OpenFinder(F, T, beg);
						beg := F.pos; Texts.FindObj(F, obj);
						WHILE ~F.eot & (obj # Gadgets.executorObj) DO
							beg := F.pos; Texts.FindObj(F, obj)
						END;
						INC(beg);
						SendIt()
					END
				END
			END
		ELSIF Sc.class IN {Texts.Name, Texts.String} THEN (* {filename} ~ *)
			WHILE Sc.class IN {Texts.Name, Texts.String} DO
				NEW(T); Texts.Open(T, Sc.s); SendIt();
				Texts.Scan(Sc)
			END
		END
	END Send;

(** Mail.Cite (selection & caret)
		Copy the selection to the caret with an left indent "> ". *)
	PROCEDURE Cite*;
		VAR
			text: Texts.Text;
			beg, end, time: LONGINT;
			C: Oberon.CaretMsg;
	BEGIN
		text := NIL; time := -1;
		Oberon.GetSelection(text, beg, end, time);
		IF (text # NIL) & (time > 0) THEN
			C.id := Oberon.get; C.car := NIL; C.text := NIL; C.pos := -1; C.F := NIL;
			Objects.Stamp(C); Display.Broadcast(C);
			IF C.text # NIL THEN
				CiteText(W, text, beg, end);
				Texts.Insert(C.text, C.pos, W.buf)
			END
		END
	END Cite;

(** Mail.Mono (marked text)
		Change the font of the marked viewer into Courier10. *)
	PROCEDURE Mono*;
		VAR T: Texts.Text;
	BEGIN
		T := Oberon.MarkedText();
		IF T # NIL THEN
			Texts.ChangeLooks(T, 0, T.len, {0, 1}, textFnt, Display.FG, 0)
		END
	END Mono;

(** Mail.CutLines [width] (marked text)
		Break all lines in the marked viewer after a maximum of width characters.
		The default width is 80. *)
	PROCEDURE CutLines*;
		VAR
			S: Attributes.Scanner;
			T: Texts.Text;
			R: Texts.Reader;
			pos, n, l: LONGINT;
			ch: CHAR;
	BEGIN
		T := Oberon.MarkedText();
		IF T = NIL THEN
			RETURN
		END;
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Attributes.Scan(S);
		IF S.class = Attributes.Int THEN
			IF S.i < 40 THEN
				n := 40
			ELSIF S.i > 132 THEN
				n := 132
			ELSE
				n := S.i
			END 
		ELSE
			n := 80
		END;
		Texts.OpenReader(R, T, 0); Texts.Read(R, ch);
		pos := 0; l := 1;
		WHILE ~R.eot DO
			IF R.lib IS Fonts.Font THEN
				IF ch = Strings.CR THEN
					l := 0
				ELSIF l >= n THEN
					Texts.WriteLn(W); Texts.Insert(T, pos, W.buf);
					Texts.OpenReader(R, T, Texts.Pos(R)+1);
					l := Texts.Pos(R)-pos
				ELSIF ch <= " " THEN
					pos := Texts.Pos(R)
				END
			ELSE
				pos := Texts.Pos(R)
			END;
			Texts.Read(R, ch); INC(l)
		END
	END CutLines;

(** Parsing of a mailto url. *)
	PROCEDURE SplitMailTo*(VAR url, mailadr: ARRAY OF CHAR): LONGINT;
		VAR
			key, i, j, l: LONGINT;
			buffer: ARRAY NetTools.MaxLine OF CHAR;
			iskey: BOOLEAN;
		PROCEDURE Blanks();
		BEGIN
			WHILE (url[i] # 0X) & (url[i] <= " ") DO
				INC(i)
			END
		END Blanks;
	BEGIN
		HyperDocs.UnESC(url);
		i := 0; Blanks();
		(* skip mailto *)
		WHILE (url[i] # 0X) & (url[i] # ":") DO
			INC(i)
		END;
		(* skip : *)
		WHILE (url[i] # 0X) & ((url[i] = ":") OR (url[i] = "/")) DO
			INC(i)
		END;
		Blanks();
		(* get mailadr *)
		iskey := TRUE;
		l := LEN(mailadr); j := 0;
		WHILE url[i] # 0X DO
			IF (url[i] > " ") & ~Strings.IsDigit(url[i]) THEN
				iskey := FALSE
			END;
			IF j < l THEN
				mailadr[j] := url[i]; INC(j)
			END;
			INC(i)
		END;
		mailadr[j] := 0X; DEC(j);
		WHILE (j >= 0) & (mailadr[j] <= " ") DO
			mailadr[j] := 0X; DEC(j)
		END;
		IF (url[i] = 0X) & iskey THEN
			IF mailadr # "" THEN
				Strings.StrToInt(mailadr, key);
				HyperDocs.RetrieveLink(key, buffer);
				key := SplitMailTo(buffer, mailadr)
			ELSE
				key := HyperDocs.UndefKey
			END
		ELSE
			COPY("mailto:", url);
			Strings.Append(url, mailadr);
			key := HyperDocs.RegisterLink(url)
		END;
		RETURN key
	END SplitMailTo;

	PROCEDURE *MailToSchemeHandler(L: Objects.Object; VAR M: Objects.ObjMsg);
		VAR mailadr: ARRAY NetTools.PathStrLen OF CHAR;
	BEGIN
		WITH L: HyperDocs.LinkScheme DO
			IF M IS HyperDocs.RegisterLinkMsg THEN
				WITH M: HyperDocs.RegisterLinkMsg DO
					M.key := SplitMailTo(M.link, mailadr);
					IF M.key # HyperDocs.UndefKey THEN
						M.res := 0
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.class := Objects.String;
						M.s := "Mail.NewMailToLinkScheme";
						M.res := 0
					ELSE
						HyperDocs.LinkSchemeHandler(L, M)
					END
				END
			ELSE
				HyperDocs.LinkSchemeHandler(L, M)
			END
		END
	END MailToSchemeHandler;

	PROCEDURE NewMailToLinkScheme*;
		VAR L: HyperDocs.LinkScheme;
	BEGIN
		NEW(L); L.usePath := FALSE;
		L.handle := MailToSchemeHandler; Objects.NewObj := L
	END NewMailToLinkScheme;

(** Parsing of a mailserver url. *)
	PROCEDURE SplitMailServer*(VAR url, mailadr, subject, body: ARRAY OF CHAR): LONGINT;
		VAR
			key, i, j, l: LONGINT;
			buffer: ARRAY NetTools.MaxLine OF CHAR;
			iskey: BOOLEAN;
		PROCEDURE Blanks();
		BEGIN
			WHILE (url[i] # 0X) & (url[i] <= " ") DO
				INC(i)
			END
		END Blanks;
	BEGIN
		HyperDocs.UnESC(url);
		i := 0; Blanks();
		(* skip mailserver *)
		WHILE (url[i] # 0X) & (url[i] # ":") DO
			INC(i)
		END;
		(* skip : *)
		WHILE (url[i] # 0X) & ((url[i] = ":") OR (url[i] = "/")) DO
			INC(i)
		END;
		Blanks();
		(* get mailadr *)
		iskey := TRUE;
		l := LEN(mailadr); j := 0;
		WHILE (url[i] # 0X) & (url[i] # "/") DO
			IF (url[i] > " ") & ~Strings.IsDigit(url[i]) THEN
				iskey := FALSE
			END;
			IF j < l THEN
				mailadr[j] := url[i]; INC(j)
			END;
			INC(i)
		END;
		mailadr[j] := 0X; DEC(j);
		WHILE (j >= 0) & (mailadr[j] <= " ") DO
			mailadr[j] := 0X; DEC(j)
		END;
		IF (url[i] = 0X) & iskey THEN
			IF mailadr # "" THEN
				Strings.StrToInt(mailadr, key);
				HyperDocs.RetrieveLink(key, buffer);
				key := SplitMailServer(buffer, mailadr, subject, body)
			ELSE
				key := HyperDocs.UndefKey
			END;
			RETURN key
		END;
		IF url[i] = "/" THEN
			INC(i)
		END;
		l := LEN(subject); j := 0;
		WHILE (url[i] # 0X) & (url[i] # "/") DO
			IF j < l THEN
				subject[j] := url[i]; INC(j)
			END;
			INC(i)
		END;
		subject[j] := 0X; DEC(j);
		WHILE (j >= 0) & (subject[j] <= " ") DO
			subject[j] := 0X; DEC(j)
		END;
		IF url[i] = "/" THEN
			INC(i)
		END;
		l := LEN(body); j := 0;
		WHILE url[i] # 0X DO
			IF j < l THEN
				body[j] := url[i]; INC(j)
			END;
			INC(i)
		END;
		body[j] := 0X;
		COPY("mailserver:", url);
		Strings.Append(url, mailadr);
		Strings.AppendCh(url, "/");
		Strings.Append(url, subject);
		Strings.AppendCh(url, "/");
		Strings.Append(url, body);
		key := HyperDocs.RegisterLink(url);
		RETURN key
	END SplitMailServer;

	PROCEDURE *MailServerSchemeHandler(L: Objects.Object; VAR M: Objects.ObjMsg);
		VAR mailadr, subject, body: ARRAY NetTools.PathStrLen OF CHAR;
	BEGIN
		WITH L: HyperDocs.LinkScheme DO
			IF M IS HyperDocs.RegisterLinkMsg THEN
				WITH M: HyperDocs.RegisterLinkMsg DO
					M.key := SplitMailServer(M.link, mailadr, subject, body);
					IF M.key # HyperDocs.UndefKey THEN
						M.res := 0
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.class := Objects.String;
						M.s := "Mail.NewMailServerLinkScheme";
						M.res := 0
					ELSE
						HyperDocs.LinkSchemeHandler(L, M)
					END
				END
			ELSE
				HyperDocs.LinkSchemeHandler(L, M)
			END
		END
	END MailServerSchemeHandler;

	PROCEDURE NewMailServerLinkScheme*;
		VAR L: HyperDocs.LinkScheme;
	BEGIN
		NEW(L); L.usePath := FALSE;
		L.handle := MailServerSchemeHandler; Objects.NewObj := L
	END NewMailServerLinkScheme;

	PROCEDURE *LoadDoc(D: Documents.Document);
		VAR
			T, text: Texts.Text;
			objb: Objects.Object;
			mailadr, subject, body: ARRAY NetTools.PathStrLen OF CHAR;
			buffer: ARRAY NetTools.MaxLine OF CHAR;
			key, beg, end, time, i: LONGINT;
			node: HyperDocs.Node;
	BEGIN
		IF Strings.CAPPrefix("mailto", D.name) THEN
			key := SplitMailTo(D.name, mailadr); subject := ""; body := ""
		ELSIF Strings.CAPPrefix("mailserver", D.name) THEN
			key := SplitMailServer(D.name, mailadr, subject, body)
		ELSE
			key := HyperDocs.UndefKey
		END;
		IF key = HyperDocs.UndefKey THEN
			D.dsc := NIL; RETURN
		END;
		NEW(T); Texts.Open(T, "");
		objb := Gadgets.CreateObject("BasicGadgets.NewButton");
		Attributes.SetString(objb, "Caption", "Send"); Attributes.SetString(objb, "Cmd", "Mail.Send @ ~");
		Gadgets.NameObj(objb, "mailto");
		Texts.WriteObj(W, objb); Texts.WriteLn(W); Texts.WriteLn(W);
		Texts.WriteString(W, "To: "); Texts.WriteString(W, mailadr); Texts.WriteLn(W);
		Texts.WriteString(W, "Subject: "); Texts.WriteString(W, subject); Texts.WriteLn(W);
		IF (HyperDocs.context # NIL) & (HyperDocs.context.old # NIL) THEN
			node := HyperDocs.context.old
		ELSE
			node := HyperDocs.NodeByDoc(Desktops.CurDoc(Gadgets.context))
		END;
		IF node # NIL THEN
			Texts.WriteString(W, "X-URL: "); HyperDocs.RetrieveLink(node.key, buffer); Texts.WriteString(W, buffer); Texts.WriteLn(W)
		END;
		IF body # "" THEN
			Texts.WriteLn(W); i := 0;
			WHILE body[i] # 0X DO
				IF body[i] = "/" THEN
					Texts.WriteLn(W)
				ELSE
					Texts.Write(W, body[i])
				END;
				INC(i)
			END;
			Texts.WriteLn(W)
		ELSE
			text := NIL; time := -1;
			Oberon.GetSelection(text, beg, end, time);
			IF (text # NIL) & (time > 0) THEN
				Texts.WriteLn(W); Texts.Append(T, W.buf); CiteText(W, text, beg, end)
			END
		END;
		Texts.Append(T, W.buf);
		COPY(mailadr, D.name); Links.SetLink(D.dsc, "Model", T);
		IF HyperDocs.context # NIL THEN
			HyperDocs.context.replace := FALSE; HyperDocs.context.history := FALSE
		END
	END LoadDoc;

(** Mail.NewDoc
		Document new-procedure for "mailto:" & "mailserver:" documents.
		E.g. Use Desktops.OpenDoc "mailto:zeller@inf.ethz.ch" to send me a mail. *)
	PROCEDURE NewDoc*;
		VAR D: Objects.Object;
	BEGIN
		D := Gadgets.CreateObject("TextDocs.NewDoc");
		WITH D: Documents.Document DO
			D.Load := LoadDoc
		END
	END NewDoc;

BEGIN
	trace := NetTools.QueryBool("TraceMail");
	mailer := "Oberon Mail (ejz) on "; Strings.Append(mailer, Kernel.version);
	headFnt := Fonts.This("Default12b.Scn.Fnt");
	fieldFnt := Fonts.This("Default12.Scn.Fnt");
	textFnt := Fonts.This("Courier10.Scn.Fnt");
	Texts.OpenWriter(W); LoadMsgs(); LoadTopics();
	NEW(mMethod);
	mMethod.Key := Key; mMethod.Seek := Seek;
	mMethod.Pos := Pos; mMethod.Set := Set;
	mMethod.State := GetState; mMethod.SetState := SetState;
	mMethod.GetStamp := GetStamp; mMethod.SetStamp := SetStamp;
	mMethod.Write := Write; mMethod.WriteLink := WriteLink;
	mMethod.DeleteLink := DeleteLink; mMethod.Desc := Desc;
	NEW(msgList); msgList.handle := ModelHandler;
	NEW(vMethod); vMethod^ := ListGadgets.methods^;
	vMethod.GetRider := GetRider;
	vMethod.Display := DisplayLine; vMethod.Format := FormatLine;
	NEW(tmMethod); tmMethod^ := mMethod^;
	tmMethod.Key := TopicKey; tmMethod.Seek := TopicSeek;
	tmMethod.Pos := TopicPos; tmMethod.Set := TopicSet;
	tmMethod.State := TopicGetState; tmMethod.SetState := TopicSetState;
	tmMethod.GetStamp := TopicGetStamp; tmMethod.SetStamp := TopicSetStamp;
	tmMethod.DeleteLink := TopicDeleteLink;
	NEW(topicList); topicList.handle := TopicModelHandler
END Mail.

System.Free News Mail NetTools HyperDocs MIME ~

!System.CopyFiles MailMessages => ejz.MailMessages ~
!System.CopyFiles ejz.MailMessages => MailMessages ~
!System.DeleteFiles MailMessages MailMessages.Bak lillian.inf.ethz.ch.zeller.UIDLs ~

System.Set NetSystem Topic0 := Miscellaneous ~
System.Set NetSystem Topic1 := "Bug Report" ~
System.Set NetSystem Topic2 := "To Do" ~

ListGadgets.InsertVScrollList Mail.NewFrame Mail.NewModel ~
Gadgets.Insert ListGadgets.NewFrame Mail.NewTopicModel ~

Mail.Mod
Mail.Panel

Mail.Collect

- snooper?
- signature?
- simplify GetUIDLs -> Texts.LoadAscii
- ReSync: delete messages on server
- import/export
- use faster text search (t-search)
(- query, optimize with stamp)


LayLa.OpenAsDoc	( CONFIG { Mail.Panel }
	{ Patch: 
		1. Mark the pin of the Settings iconizer and open a Columbus inspector.
		2. Click on pin of Settings iconizer to open settings panel.
		3. Click on Coords button in Columbus, set X=4 Y=-195 and Apply.
	}
	(DEF CW 32) (DEF BW 42) (DEF BH 23) (DEF IW 42) (DEF IW2 87) 
	(DEF LW 80) (DEF LH 100) (DEF SW 376) (DEF SH 192)
	(DEF mailmodel (NEW Mail.NewModel))
	(DEF topicmodel (NEW Mail.NewTopicModel))
	(DEF query (NEW String (ATTR Name="Query" Value="")))
	(DEF vpos (NEW Integer))
	(DEF vrange (NEW Integer))
	(DEF sortby (NEW Integer (ATTR Value=1)))
	(DEF ascend (NEW Boolean (ATTR Value=TRUE)))
	(DEF cont (NEW Integer (ATTR Name="ContType" Value=3)))
	
		{ Iconizer front panels }
	( DEF set0 (HLIST Panel (w=IW h=BH vjustify=CENTER hjustify=CENTER) (ATTR Locked=TRUE) 
		(NEW Caption (ATTR Value="Set")))
	)
	( DEF clear0 (HLIST Panel (w=IW h=BH vjustify=CENTER hjustify=CENTER) (ATTR Locked=TRUE) 
		(NEW Caption (ATTR Value="Clear")))
	)
	( DEF query0 (HLIST Panel (w=IW h=BH vjustify=CENTER hjustify=CENTER) (ATTR Locked=TRUE) 
		(NEW Caption (ATTR Value="Query")))
	)
	( DEF conf0 (HLIST Panel (w=IW2 h=BH vjustify=CENTER hjustify=CENTER) (ATTR Locked=TRUE) 
		(NEW Caption (ATTR Value="Settings")))
	)
	
		{ Iconizer insides }
	( DEF set1
		(NEW ListGadget (w=LW h=LH) (LINKS Model=topicmodel) (ATTR Cmd="Mail.SetTopic MailList '#Point '"))
	)
	( DEF clear1
		(NEW ListGadget (w=LW h=LH) (LINKS Model=topicmodel) (ATTR Cmd="Mail.ClearTopic MailList '#Point '"))
	)
	( DEF query1
		(NEW ListGadget (w=LW h=LH) (LINKS Model=topicmodel) (ATTR Cmd="Mail.QueryTopic Query '#Point '"))
	)
	( DEF conf1	{ Settings panel }
		( HLIST Panel (border=5 w=SW h=SH dist=14 vjustify=CENTER) (ATTR Locked=TRUE)
			( VLIST VIRTUAL (w=[2] dist=8)
				( HLIST VIRTUAL (w=[] hjustify=CENTER)
					(NEW Caption (ATTR Value="Local Settings (override Oberon.Text)"))
				)
				( TABLE VIRTUAL (w=[] cols=2)
					(NEW Caption (ATTR Value="EMail Address"))
					(NEW TextField (w=[10]) (ATTR Name="EMail"))
					(NEW Caption (ATTR Value="SMTP Server"))
					(NEW TextField (w=[10]) (ATTR Name="SMTP"))
					(NEW Caption (ATTR Value="POP Server"))
					( HLIST VIRTUAL (w=[10])
						(NEW TextField (w=[7]) (ATTR Name="POP"))
						(NEW TextField (w=[3]) (ATTR Name="POPMode") (ATTR Value="POP3"))
					)
					(NEW Caption (ATTR Value="POP User"))
					(NEW TextField (w=[10]) (ATTR Name="User"))
					(NEW Caption (ATTR Value="Max message size"))
					(NEW TextField (w=[10]) (ATTR Name="MaxMsgSize" Value="80000"))
				)
				( HLIST VIRTUAL (w=[])
					(NEW Caption (ATTR Value="Leave messages on server"))
					(NEW CheckBox (ATTR Name="LeaveOnServer"))
					(NEW VIRTUAL (w=[]))
					(NEW Caption (ATTR Value="Auto Cc"))
					(NEW CheckBox (ATTR Name="AutoCc" Value=TRUE))
				)
			)
			( TABLE VIRTUAL (w=[] orientation=VERT rows=6)
				(HLIST VIRTUAL (w=45 h=BH hjustify=CENTER vjustify=CENTER) (NEW Caption (ATTR Value="Sorting")))
				(NEW Button (w=[] h=BH) (ATTR Caption="Date" SetVal=1) (LINKS Model=sortby))
				(NEW Button (w=[] h=BH) (ATTR Caption="From" SetVal=2) (LINKS Model=sortby))
				(NEW Button (w=[] h=BH) (ATTR Caption="Subject" SetVal=3) (LINKS Model=sortby))
				(NEW Button (w=[] h=BH) (ATTR Caption="None" SetVal=0) (LINKS Model=sortby))
				( SPAN 1 2 
					( HLIST VIRTUAL (w=[]) 
						(NEW Caption (ATTR Value="Ascending"))
						(NEW CheckBox (LINKS Model=ascend))
						(NEW VIRTUAL (w=[]))
					)
				)
				(HLIST VIRTUAL (w=[] h=BH hjustify=CENTER vjustify=CENTER) (NEW Caption (ATTR Value="Content")))
				(NEW Button (w=[] h=BH) (ATTR Caption="Auto" SetVal=3) (LINKS Model=cont))
				(NEW Button (w=[] h=BH) (ATTR Caption="Oberon" SetVal=2) (LINKS Model=cont))
				(NEW Button (w=[] h=BH) (ATTR Caption="ISO-8859-1" SetVal=1) (LINKS Model=cont))
				(NEW Button (w=[] h=BH) (ATTR Caption="ASCII" SetVal=0) (LINKS Model=cont))
			)
		)
	)

		{ Main panel }
	( VLIST Panel (border=5 w=384 h=200 dist=3 vjustify=CENTER) (ATTR Locked=TRUE)
		( HLIST VIRTUAL (w=[] h=[] dist=0)	{ Mail list & scrollbar }
			( NEW Mail.NewFrame (w=[] h=[]) (ATTR Name="MailList")
				(LINKS Model=mailmodel SortBy=sortby Ascending=ascend Query=query VPos=vpos VRange=vrange)
			)
			(NEW Scrollbar (h=[]) (ATTR Max=0 HeavyDrag=TRUE) (LINKS Min=vrange Model=vpos))
		)
		( HLIST VIRTUAL (w=[] vdist=5 hdist=3 vjustify=CENTER)	{ Top row }
			(HLIST VIRTUAL (w=CW hjustify=CENTER) (NEW Caption (ATTR Value="Filter")))	
			(NEW Button (w=BW h=BH) (ATTR Caption="Unread" Cmd="Gadgets.Set Query.Value unread"))
			(NEW Button (w=BW h=BH) (ATTR Caption="All" Cmd="Gadgets.Set Query.Value ''"))
			(NEW TextField (w=[]) (LINKS Model=query)) 
		)
		( HLIST VIRTUAL (w=[] vdist=5 hdist=3 vjustify=CENTER)	{ Middle row }
			(HLIST VIRTUAL (w=CW hjustify=CENTER) (NEW Caption (ATTR Value="Text")))
			(NEW Button (w=BW h=BH) (ATTR Caption="Reply" Cmd="Mail.Reply ^"))
			(NEW Button (w=BW h=BH) (ATTR Caption="Cite ^" Cmd="Mail.Cite"))
			(NEW Button (w=66 h=BH) (ATTR Caption="AsciiCode ^" Cmd="AsciiCoder.CodeFiles % ^"))
			(NEW VIRTUAL (w=[]))
			(HLIST VIRTUAL (w=BW hjustify=CENTER) (NEW Caption (ATTR Value="Topic")))
			(NEW Iconizer (w=IW h=[]) (ATTR Popup=TRUE Pin=FALSE Locked=TRUE) (LINKS Closed=set0 Open=set1))
			(NEW Iconizer (w=IW h=[]) (ATTR Popup=TRUE Pin=FALSE Locked=TRUE) (LINKS Closed=clear0 Open=clear1))
			(NEW Iconizer (w=IW h=[]) (ATTR Popup=TRUE Pin=FALSE Locked=TRUE) (LINKS Closed=query0 Open=query1))
		) 
		( HLIST VIRTUAL (w=[] vdist=5 hdist=3 vjustify=CENTER)	{ Bottom row }
			(HLIST VIRTUAL (w=CW hjustify=CENTER) (NEW Caption (ATTR Value="Server")))
			(NEW Button (w=BW h=BH) (ATTR Caption="Get" Cmd="Mail.Synchronize"))
			(NEW Button (w=BW h=BH) (ATTR Caption="Send *" Cmd="Mail.Send *"))
			(NEW TextField (w=[]) (ATTR Name="StatusBar" Value="")) 
			(NEW Iconizer (w=IW2 h=[]) (ATTR FixedViews=FALSE Locked=TRUE) (LINKS Closed=conf0 Open=conf1))
		)
	)
)


UIDL handling

POPCollect -> remove all UIDLs -> new UIDL file
Synchronize -> store only UIDLs current (from UIDL command) UIDL
