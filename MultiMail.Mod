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

MODULE MultiMail;	(** portable *) (* ejz,   *)
	IMPORT Files, Objects, Texts, Oberon, Strings, Fonts, Base64, NetTools, MIME, Mail, Links, Gadgets, Lists, Streams,
		TextStreams;

	VAR
		W: Texts.Writer;

	PROCEDURE SearchText(text: Texts.Text; VAR pat: ARRAY OF CHAR; VAR pos: LONGINT): BOOLEAN;
		CONST
			MaxPatLen = 128;
		VAR
			i, l, sPatLen: LONGINT;
			R: Texts.Reader;
			sPat: ARRAY MaxPatLen OF CHAR;
			sDv: ARRAY MaxPatLen + 1 OF INTEGER;
			ch: CHAR;
		PROCEDURE CalcDispVec();
			VAR i, j, d: LONGINT;
		BEGIN
			i := 1; d := 1;
			WHILE i <= sPatLen DO
				j := 0; 
				WHILE (j + d < sPatLen) & (sPat[j] = sPat[j + d]) DO
					INC(j)
				END;
				WHILE i <= j + d DO
					sDv[i] := SHORT(d); INC(i)
				END;
				INC(d)
			END
		END CalcDispVec;
	BEGIN
		COPY(pat, sPat);
		sPatLen := SHORT(Strings.Length(sPat));
		CalcDispVec();
		IF sPatLen > 0 THEN
			Texts.OpenReader(R, text, pos);
			Texts.Read(R, ch); INC(pos);
			l := text.len; i := 0;
			WHILE (i # sPatLen) & (pos <= l) DO
				IF ch = sPat[i] THEN
					INC(i);
					IF i < sPatLen THEN
						Texts.Read(R, ch); INC(pos)
					END
				ELSIF i = 0 THEN
					Texts.Read(R, ch); INC(pos)
				ELSE
					i := i - sDv[i]
				END
			END
		ELSE
			i := -1
		END;
		RETURN i = sPatLen
	END SearchText;

	PROCEDURE Send*;
		VAR
			S: Mail.SMTPSession;
			Sw: Streams.Stream;
			server, email: ARRAY 64 OF CHAR;
			cont: MIME.Content;
			obj: Objects.Object;
			text, mail, ascii: Texts.Text;
			buf: Texts.Buffer;
			list: Lists.List;
			item: Lists.Item;
			boundary: ARRAY 128 OF CHAR;
			magStr, val: ARRAY 16 OF CHAR;
			pos, magic: LONGINT;
			F: Files.File;
			h: MIME.Header;
			R: Texts.Reader;
			ch: CHAR;
			autoCc: BOOLEAN;
	BEGIN
		Texts.OpenWriter(W);
		obj := Gadgets.FindObj(Gadgets.context, "body");
		Links.GetLink(obj, "Model", obj);
		text := obj(Texts.Text);
		obj := Gadgets.FindObj(Gadgets.context, "files");
		list := obj(Lists.List);
		NEW(mail); Texts.Open(mail, "");
		NEW(buf); Texts.OpenBuf(buf);

		Mail.GetSetting("SMTP", server, FALSE); Mail.GetSetting("EMail", email, FALSE);
		Mail.GetSetting("AutoCc", boundary, TRUE); Strings.StrToBool(boundary, autoCc);

(* gen boundary *)
		magic := Oberon.Time(); boundary := "------------";
		Strings.IntToStr(magic, magStr); Strings.Append(boundary, magStr);

(* mime header *)
		Sw := TextStreams.OpenReader(text, 0); 
		MIME.ReadHeader(Sw, NIL, h, pos);
		Texts.OpenReader(R, text, pos); Texts.Read(R, ch);
		IF ((ch = Strings.CR) OR (ch = Strings.LF)) OR R.eot THEN
			ch := Strings.CR;
			WHILE (pos > 0) & ((ch = Strings.CR) OR (ch = Strings.LF)) DO
				DEC(pos); Texts.OpenReader(R, text, pos); Texts.Read(R, ch)
			END;
			INC(pos); IF pos > text.len THEN pos := text.len END
		END;
		Texts.Save(text, 0, pos, buf); Texts.Append(mail, buf);
		Texts.WriteLn(W);
		Texts.WriteString(W, "X-Mailer: MultiMail for Oberon (ejz)"); Texts.WriteLn(W);
		Texts.WriteString(W, "MIME-Version: 1.0"); Texts.WriteLn(W);
		Texts.WriteString(W, 'Content-Type: multipart/mixed; boundary="');
		Texts.WriteString(W, boundary); Texts.Write(W, 022X); Texts.WriteLn(W);
		Texts.WriteLn(W);
		Texts.WriteString(W, "This is a multi-part message in MIME format.");
		Texts.WriteLn(W); Texts.WriteLn(W);

(* message *)
		Texts.WriteString(W, "--"); Texts.WriteString(W, boundary);
		Texts.WriteLn(W); Texts.Append(mail, W.buf);
		Mail.GetSetting("ContType", val, TRUE);
		NEW(cont); cont.typ := MIME.GetContentType("text/plain");
		IF val[0] = "0" THEN
			cont.encoding := MIME.EncBin
		ELSIF val[0] = "1" THEN
			cont.encoding := MIME.Enc8Bit
		ELSIF val[0] = "2" THEN
			cont.typ := MIME.GetContentType(MIME.OberonMime); cont.encoding := MIME.EncAsciiCoderC
		ELSE
			cont.encoding := MIME.EncAuto;
			Mail.QueryContType(text, pos, cont)
		END;
		IF cont.encoding IN {MIME.EncAsciiCoder, MIME.EncAsciiCoderC, MIME.EncAsciiCoderCPlain} THEN
			Texts.WriteString(W, "X-Content-Type: "); Texts.WriteString(W, MIME.OberonMime);
			Texts.WriteLn(W); Texts.Append(mail, W.buf)
		END;
		Sw := TextStreams.OpenWriter(mail);
		MIME.WriteISOMime(Sw, cont);
		TextStreams.WriteLn(Sw); TextStreams.WriteLn(Sw);
		IF cont.encoding IN {MIME.EncAsciiCoder, MIME.EncAsciiCoderC, MIME.EncAsciiCoderCPlain} THEN
			IF cont.encoding IN {MIME.EncAsciiCoder, MIME.EncAsciiCoderC} THEN
				MIME.WriteText(text, pos, text.len, Sw, cont, FALSE, TRUE)
			END;
			TextStreams.WriteString(Sw, Mail.OberonStart); TextStreams.WriteLn(Sw);
			Mail.MakeAscii(text, pos, text.len, cont.encoding # MIME.EncAsciiCoder, ascii);
			cont.typ := MIME.GetContentType("text/plain");
			MIME.WriteText(ascii, 0, ascii.len, Sw, cont, FALSE, TRUE)
		ELSE
			Texts.OpenReader(R, text, pos); Texts.Read(R, ch); INC(pos);
			WHILE ~R.eot & (ch <= " ") & (R.lib IS Fonts.Font) DO
				Texts.Read(R, ch); INC(pos)
			END;
			DEC(pos);
			MIME.WriteText(text, pos, text.len, Sw, cont, FALSE, TRUE)
		END;
		TextStreams.WriteLn(Sw); Sw.Flush(Sw);

(* attachments *)
		pos := 0; ASSERT(~SearchText(text, boundary, pos));
		NEW(text); item := list.items;
		WHILE item # NIL DO
			Texts.WriteString(W, "--"); Texts.WriteString(W, boundary); Texts.WriteLn(W);
			Texts.WriteString(W, "Mime-Version: 1.0"); Texts.WriteLn(W);
			Texts.WriteString(W, "Content-Type: application/octet-stream"); Texts.WriteLn(W);
			Texts.WriteString(W, "Content-Transfer-Encoding: base64"); Texts.WriteLn(W);
			Texts.WriteString(W, 'Content-Disposition: attachment; filename="');
			Texts.WriteString(W, item.s); Texts.Write(W, 022X); Texts.WriteLn(W);
			Texts.WriteLn(W); Texts.Append(mail, W.buf);
			F := Files.Old(item.s);
			IF F # NIL THEN
				Texts.Open(text, ""); Base64.EncodeFile(F, text);
				Texts.Save(text, 0, text.len, buf); Texts.Append(mail, buf);
				pos := 0; ASSERT(~SearchText(text, boundary, pos));
				Texts.WriteLn(W)
			ELSE
				Texts.OpenWriter(W);
				Texts.WriteString(W, item.s); Texts.WriteString(W, " not found");
				Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
				RETURN
			END;
			item := item.next
		END;
		Texts.WriteString(W, "--"); Texts.WriteString(W, boundary); Texts.WriteString(W, "--"); Texts.WriteLn(W);
		Texts.WriteLn(W); Texts.Append(mail, W.buf);

		cont.typ := MIME.GetContentType("text/plain"); cont.encoding := MIME.EncBin;
		Mail.OpenSMTP(S, server, email, Mail.DefSMTPPort);
		IF S.res = NetTools.Done THEN
			Texts.WriteString(W, "mailing "); Texts.Append(Oberon.Log, W.buf);
			Mail.SendMail(S, mail, cont, autoCc);
			Mail.CloseSMTP(S)
		END;
		Texts.WriteString(W, S.reply); Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf)
	END Send;

END MultiMail.

MultiMail.Panel

System.Free MultiMail ~
