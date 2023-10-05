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

MODULE TextMail;	(** portable *)	(*RS/ARD/JG, 12.10.97*)

	IMPORT FileDir, Files, Texts, TextFrames, Oberon, Viewers, MenuViewers, NS := NetSystem, Display, Fonts, Strings;
	
	CONST POP = 110; SMTP = 25; TAB = 9X; CR = 0DX; LF = 0AX; maxlen = 32;
		StandardMenu = "System.Close System.Copy System.Grow Edit.Search Edit.Store";
		CopySelf = TRUE;
		
	VAR
		res*: INTEGER; M, fpos: INTEGER;
        W: Texts.Writer;
		iso, quoted: BOOLEAN;
		host: ARRAY 32 OF CHAR;
        spat: ARRAY maxlen OF CHAR; (*file name pattern, search pattern*)
        d: ARRAY 256 OF INTEGER;

    PROCEDURE ReadLInt (VAR R: Files.Rider; VAR n: LONGINT);
      VAR i: INTEGER; ch: CHAR;
    BEGIN n := 0; Files.Read(R, ch);
      WHILE ("0" <= ch) & (ch <= "9") DO 
        n := n*10 + (ORD(ch) - ORD("0")); Files.Read(R, ch)
      END
    END ReadLInt;

    PROCEDURE WriteLInt (VAR R: Files.Rider; n: LONGINT);
      VAR i: INTEGER; d: ARRAY 14 OF INTEGER;
    BEGIN i := 0;
      REPEAT d[i] := SHORT(n MOD 10); n := n DIV 10; INC(i) UNTIL n = 0;
      WHILE i # 14 DO d[i] := 0; INC(i) END;
      REPEAT DEC(i); Files.Write(R, CHR(ORD("0") + d[i])) UNTIL i = 0
    END WriteLInt;
	
	PROCEDURE MarkedText(): Texts.Text;
	VAR V, F: Display.Frame;
	BEGIN V := Oberon.MarkedViewer();
		IF (V # NIL) & (V.dsc # NIL) THEN F := V.dsc.next;
			IF (F # NIL) & (F IS TextFrames.Frame) THEN
				RETURN F(TextFrames.Frame).text
			END
		END;
		RETURN NIL
	END MarkedText;
		
	PROCEDURE String(s: ARRAY OF CHAR);
	BEGIN Texts.WriteString(W, s); Texts.Append(Oberon.Log, W.buf)
	END String;

	PROCEDURE Ln;
	BEGIN Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END Ln;

	PROCEDURE Response(S: NS.Connection; VAR s: ARRAY OF CHAR);
	BEGIN NS.ReadString(S, s);
		WHILE s[3] = "-" DO NS.ReadString(S, s) END	(*skip multiple response lines*)
	END Response;

	PROCEDURE OpenViewer(name: ARRAY OF CHAR; T: Texts.Text; user: BOOLEAN);
	VAR V: MenuViewers.Viewer; X, Y: INTEGER;
			menu: ARRAY 128 OF CHAR;
			t: TextFrames.Frame;
	BEGIN X := Oberon.Mouse.X;
		IF user THEN
			Oberon.AllocateUserViewer(Oberon.UserTrack(X), X, Y);
			menu := "System.Close System.Copy System.Grow Edit.Search Edit.Store"
		ELSE
			Oberon.AllocateSystemViewer(Oberon.SystemTrack(X), X, Y);
			menu := "System.Close  TextMail.Show  TextMail.Delete  Edit.Search  Edit.Store";
		END;
		V := MenuViewers.New(TextFrames.NewMenu(name, menu), TextFrames.NewText(T, 0), TextFrames.menuH, X, Y);
	END OpenViewer;

	PROCEDURE Connect(VAR S: NS.Connection; host: ARRAY OF CHAR; port: INTEGER; VAR res: INTEGER);
	VAR ip: NS.IPAdr;
	BEGIN NS.GetIP(host, ip);
		NEW(S); NS.OpenConnection(S, NS.anyport, ip, port, res); 
	END Connect;

	PROCEDURE SendCmd(S: NS.Connection; cmd, arg: ARRAY OF CHAR);
	VAR buf: ARRAY 514 OF CHAR; i, j: INTEGER;
	BEGIN i := 0;
		WHILE cmd[i] # 0X DO buf[i] := cmd[i]; INC(i) END;
		IF arg[0] # 0X THEN buf[i] := " "; INC(i); j := 0;
			WHILE arg[j] # 0X DO buf[i] := arg[j]; INC(i); INC(j) END
		END;
		buf[i] := CR; buf[i+1] := LF; buf[i+2] := 0X;
		NS.WriteBytes(S, 0, i+2, buf)
	END SendCmd;

	PROCEDURE Prefix(t: ARRAY OF CHAR; VAR s: ARRAY OF CHAR): BOOLEAN;
	VAR i: INTEGER;
	BEGIN i := 0;
		WHILE (t[i] # 0X) & (t[i] = s[i]) DO INC(i) END;
		RETURN (t[i] = 0X)
	END Prefix;

	PROCEDURE Copy(i: INTEGER; VAR s, t: ARRAY OF CHAR);	(*chop off first i characters*)
	VAR j: INTEGER;
	BEGIN j := 0;
		WHILE s[i] = " " DO INC(i) END;	(*skip leading blanks*)
		WHILE s[i] # 0X DO t[j] := s[i]; INC(j); INC(i) END;
        t[j] := 0X
	END Copy;

	PROCEDURE IsHexDigit(ch: CHAR): BOOLEAN;
	BEGIN RETURN ((ch >= "0") & (ch <= "9")) OR ((ch >= "A") & (ch <= "F"))
	END IsHexDigit;

	PROCEDURE HexVal(ch: CHAR): INTEGER;
	BEGIN
		IF (ch >= "0") & (ch <= "9") THEN RETURN ORD(ch)-ORD("0")
		ELSIF (ch >= "A") & (ch <= "F") THEN RETURN ORD(ch)-ORD("A")+10 END
	END HexVal;

	PROCEDURE WriteStringI2O(VAR W: Texts.Writer; VAR str: ARRAY OF CHAR; quoted: BOOLEAN);
	VAR i: LONGINT; ch: CHAR;
	BEGIN i := 0;
		WHILE str[i] # 0X DO ch := str[i];
			IF iso THEN 
				IF quoted & (ch = "=") & IsHexDigit(str[i+1]) & IsHexDigit(str[i+2]) THEN
					ch := Strings.ISOToOberon[HexVal(str[i+1])*16+HexVal(str[i+2])];
					INC(i, 2)
				ELSE ch := Strings.ISOToOberon[ORD(ch)]
                END
			END;
			Texts.Write(W, ch);
			INC(i)
		END
	END WriteStringI2O;
	
	PROCEDURE ReceiveHead(S: NS.Connection; dir, full: BOOLEAN);
	VAR from, subject, date: ARRAY 256 OF CHAR; to: BOOLEAN;
			s: ARRAY 1024 OF CHAR; i: INTEGER; 
	BEGIN
		NS.ReadString(S, s); subject[0] := 0X; from[0] := 0X; date[0] := 0X; to := FALSE;
		IF s[0] = "+" THEN NS.ReadString(S, s); iso := FALSE; quoted := FALSE;
			WHILE s[0] # 0X DO
				IF full THEN WriteStringI2O(W, s, FALSE); Texts.WriteLn(W);
					IF Prefix("Content-Type:", s) THEN 
						i := 0;
						WHILE (s[i] # "=") & (s[i] # 0X) DO INC(i) END;
						IF (s[i] = "=") & (s[i+1] = 22X) THEN INC(i) END;
						IF s[i] # 0X THEN
							IF (CAP(s[i+1]) = "I") & (CAP(s[i+2]) = "S") & (CAP(s[i+3]) = "O") THEN iso := TRUE END
						END
					ELSIF Prefix("Content-Transfer-Encoding:", s) THEN 
						i := 0;
						WHILE (s[i] # ":") & (s[i] # 0X) DO INC(i) END;
						IF s[i] = ":" THEN INC(i) END;
						IF s[i] # 0X THEN
							IF (s[i+1] = "8") & (CAP(s[i+2]) = "B") & (CAP(s[i+3]) = "I") & (CAP(s[i+4]) = "T") THEN quoted := FALSE 
							ELSIF iso THEN quoted := TRUE
							END
						END
					END;
				ELSIF Prefix("From:", s) THEN
					IF dir THEN Copy(5+1,s, from) ELSE WriteStringI2O(W, s, quoted); Texts.WriteLn(W) END;
				ELSIF Prefix("Subject:", s) THEN
					IF dir THEN Copy(8+1, s, subject) ELSE WriteStringI2O(W, s, quoted); Texts.WriteLn(W) END;
				ELSIF Prefix("To:", s) THEN
					IF ~dir THEN WriteStringI2O(W, s, quoted); Texts.WriteLn(W) END;
					to := ~dir;
				ELSIF Prefix("Cc:", s) OR Prefix("cc:", s) THEN
					IF ~dir THEN WriteStringI2O(W, s, quoted); Texts.WriteLn(W) END;
					to := ~dir;
				ELSIF Prefix("Date:", s) THEN
					IF dir THEN Copy(5+1, s, date) ELSE WriteStringI2O(W, s, quoted); Texts.WriteLn(W) END;
				ELSIF Prefix("Content-Type:", s) THEN 
					i := 0;
					WHILE (s[i] # "=") & (s[i] # 0X) DO INC(i) END;
					IF (s[i] = "=") & (s[i+1] = 22X) THEN INC(i) END;
					IF s[i] # 0X THEN
						IF (CAP(s[i+1]) = "I") & (CAP(s[i+2]) = "S") & (CAP(s[i+3]) = "O") THEN iso := TRUE END
					END;
				ELSIF ((s[0] = " ") OR (s[0] = TAB)) & to THEN	(*multiple lines*)
					WriteStringI2O(W, s, quoted); Texts.WriteLn(W);
				ELSE to := FALSE
				END;
				NS.ReadString(S, s);
			END;
			IF dir THEN
				WriteStringI2O(W, date, quoted); Texts.Write(W, " ");
				WriteStringI2O(W, from, quoted); Texts.Write(W, " ");
				WriteStringI2O(W, subject, quoted); Texts.WriteLn(W);
			END
		END
	END ReceiveHead;

	PROCEDURE Body(S: NS.Connection);
	VAR s: ARRAY 1024 OF CHAR;
	BEGIN NS.ReadString(S, s);
		WHILE (s[0] # ".") OR (s[1] # 0X) DO
			IF s = "--- start of oberon mail ---" THEN s := "AsciiCoder.DecodeText %" END;
			WriteStringI2O(W, s, quoted); Texts.WriteLn(W); NS.ReadString(S, s)
		END
	END Body;

	PROCEDURE Close(S: NS.Connection);
	VAR s: ARRAY 256 OF CHAR;
	BEGIN SendCmd(S, "quit", ""); NS.ReadString(S, s); NS.CloseConnection(S)
	END Close;

	PROCEDURE OpenPop(VAR S: NS.Connection; host: ARRAY OF CHAR; VAR mails: INTEGER): BOOLEAN;
	VAR s: ARRAY 256 OF CHAR; i: INTEGER;  user, passwd: ARRAY 16 OF CHAR;
	BEGIN
		Connect(S, host, POP, res);
		IF res = 0 THEN NS.ReadString(S, s); 
			IF s[0] = "+" THEN
				user := "";  NS.GetPassword("pop", host, user, passwd);
				SendCmd(S, "user", user); NS.ReadString(S, s); 
				IF s[0] = "+" THEN SendCmd(S, "pass", passwd); NS.ReadString(S, s);
					IF s[0] = "+" THEN	(*+OK user has N message(s) (X octets).*)
						i := 4; WHILE (s[i] < "0") OR (s[i] > "9") DO INC(i) END;
						mails := 0;
						WHILE (s[i] >= "0") & (s[i] <= "9") DO
						  mails := 10*mails + ORD(s[i])-30H; INC(i)
						END;
						RETURN TRUE
					ELSE String("wrong password"); Ln
					END
				ELSE String("no such user"); Ln
				END
			ELSIF s[0] = 0X THEN String("timed out"); Ln
			END;
			Close(S)
		ELSE String("no connection"); Ln
		END;
		RETURN FALSE
	END OpenPop;

	PROCEDURE OpenScanner(pop: BOOLEAN;  VAR S: Texts.Scanner);
	BEGIN
		IF pop THEN Oberon.OpenScanner(S, "NetSystem.POP")
		ELSE Oberon.OpenScanner(S, "NetSystem.SMTP")
		END;
		IF S.class = Texts.String THEN S.class := Texts.Name END
	END OpenScanner;
	
	PROCEDURE directory;
	VAR Mail: NS.Connection;
			arg: ARRAY 8 OF CHAR;
			text: Texts.Text;
			mails, k: INTEGER;
	BEGIN
		IF OpenPop(Mail, host, mails) THEN
			k := 1;
			WHILE k <= mails DO
				Strings.IntToStr(k, arg);  Strings.Append(arg, " 0");
				SendCmd(Mail, "top", arg);
				ReceiveHead(Mail, TRUE, FALSE);
				Body(Mail);	(*should be empty*)
				INC(k); 
			END;
			Close(Mail);
			NEW(text); Texts.Open(text, ""); Texts.Append(text, W.buf); 
			OpenViewer(host, text, FALSE)
		END;
	END directory;

	PROCEDURE Directory*;
	VAR S: Texts.Scanner;
	BEGIN OpenScanner(TRUE, S);
		IF S.class = Texts.Name THEN COPY(S.s, host); directory
		ELSE String("mail host missing"); Ln
        END
	END Directory;

	PROCEDURE LocateMail (VAR text: Texts.Text; VAR pos: LONGINT);
	VAR f: Display.Frame; F: TextFrames.Frame; end, time: LONGINT;
	BEGIN f := Oberon.Par.frame;
		IF Oberon.Par.vwr.dsc = f THEN	(*menu frame*)
			f := f.next;
			IF (f # NIL) & (f IS TextFrames.Frame) THEN F := f(TextFrames.Frame); text := F.text;
				IF F.sel > 0 THEN pos := F.selbeg.pos ELSE pos := 0 END
			END
        ELSE Oberon.GetSelection(text, pos, end, time)
        END
	END LocateMail;

	PROCEDURE MailNo (text: Texts.Text; pos: LONGINT; VAR mail: INTEGER; VAR beg, end: LONGINT);
	  VAR R: Texts.Reader; ch: CHAR;
	BEGIN mail := 0;
        Texts.OpenReader(R, text, 0); Texts.Read(R, ch); end := 0;
        WHILE ~R.eot & (end <= pos) DO
          beg := end;
          WHILE ~R.eot & (ch # CR) DO Texts.Read(R, ch) END;
          IF ch = CR THEN INC(mail); end := Texts.Pos(R) END;	(*number starts with 1*)
          Texts.Read(R, ch)
		END
	END MailNo;

	PROCEDURE DeleteMail(S: NS.Connection; mailno: INTEGER; VAR done: BOOLEAN);
	  VAR s: ARRAY 256 OF CHAR; arg: ARRAY 8 OF CHAR;
	BEGIN
		Strings.IntToStr(mailno, arg);
		SendCmd(S, "dele", arg); NS.ReadString(S, s);
		done := (s[0] = "+")
	END DeleteMail;

	PROCEDURE delete;
	VAR Mail: NS.Connection;
			text: Texts.Text; pos, beg, end: LONGINT;
			n, mails: INTEGER;
			done: BOOLEAN;
	BEGIN
        LocateMail(text, pos); MailNo(text, pos, n, beg, end);
		IF (n > 0) & OpenPop(Mail, host, mails) THEN
			IF n <= mails THEN
				DeleteMail(Mail, n, done);
				IF done THEN Texts.Delete(text, beg, end) END
			END;
			Close(Mail)
		ELSE String("no connection"); Ln
        END
	END delete;
	
	PROCEDURE Delete*;
	VAR S: Texts.Scanner;
	BEGIN OpenScanner(TRUE, S);
		IF S.class = Texts.Name THEN COPY(S.s, host); delete
		ELSE String("mail host missing"); Ln
        END
	END Delete;

	PROCEDURE deleteAll;
	VAR Mail: NS.Connection;
			text: Texts.Text; pos, beg, end: LONGINT;
			mails, n, d: INTEGER;
			done: BOOLEAN;
	BEGIN
        LocateMail(text, pos); MailNo(text, pos, n, beg, end);
		IF (n > 0) & OpenPop(Mail, host, mails) THEN done := TRUE;
          WHILE done & (n <= mails)  & (pos < text.len) DO DeleteMail(Mail, n, done);
			IF done THEN
			  Texts.Delete(text, beg, end); MailNo(text, pos, d, beg, end); INC(n)
			END
          END;
          Close(Mail)
        END
	END deleteAll;
	
	PROCEDURE DeleteAll*;
	VAR S: Texts.Scanner;
	BEGIN OpenScanner(TRUE, S);
		IF S.class = Texts.Name THEN COPY(S.s, host); deleteAll
		ELSE String("mail host missing"); Ln
		END
	END DeleteAll;

	PROCEDURE ReceiveMail(S: NS.Connection; mailno: INTEGER; VAR text: Texts.Text);
	VAR arg: ARRAY 8 OF CHAR;
	BEGIN
		Strings.IntToStr(mailno, arg);
		SendCmd(S, "retr", arg); ReceiveHead(S, FALSE, TRUE);
		Texts.WriteLn(W);
		Body(S);
		NEW(text); Texts.Open(text, ""); Texts.Append(text, W.buf);
	END ReceiveMail;

	PROCEDURE show;
	VAR Mail: NS.Connection; text: Texts.Text; pos, d: LONGINT; n, mails: INTEGER;
	BEGIN
		LocateMail(text, pos); MailNo(text, pos, n, d, d);
		IF (n > 0) & OpenPop(Mail, host, mails) THEN
			IF n <= mails THEN
				ReceiveMail(Mail, n, text);
				OpenViewer("Mail.Text", text, TRUE)
			ELSE String("no such mail"); Ln
			END;
			Close(Mail)
		END
	END show;

	PROCEDURE Show*;
	VAR S: Texts.Scanner;
	BEGIN OpenScanner(TRUE, S);
		IF S.class = Texts.Name THEN COPY(S.s, host); show
		ELSE String("mail host missing"); Ln
        END
	END Show;

	(*--TDB--*)

	PROCEDURE getAll;
	VAR Mail: NS.Connection; f: Files.File;
			S: Texts.Scanner; text: Texts.Text; mpos, pos, len, d: LONGINT;
			n, mails: INTEGER;
	BEGIN
        Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
        IF S.class = Texts.Name THEN f := Files.Old(S.s);
           IF f = NIL THEN f := Files.New(S.s) END;
           pos := Files.Length(f);
           LocateMail(text, mpos); MailNo(text, mpos, n, d, d);
	       IF (n > 0) & OpenPop(Mail, host, mails) THEN
		    	WHILE n <= mails DO
			    	ReceiveMail(Mail, n, text); Texts.Store(text, f, pos, len);
                    pos := pos + len; INC(n)
		    	END;
		    	Close(Mail)
           ELSE String("no such mail")
           END;
           Files.Register(f); Files.Close(f)
        ELSE String("no database specified")
		END
	END getAll;

	PROCEDURE GetAll*;
	VAR S: Texts.Scanner;
	BEGIN
         OpenScanner(TRUE, S);
	  	IF S.class = Texts.Name THEN COPY(S.s, host); getAll
		  ELSE String("mail host missing"); Ln
		  END
	END GetAll;

    PROCEDURE Store*;
	  VAR S: Texts.Scanner; T: Texts.Text; RT: Texts.Reader; f: Files.File; ch: CHAR; len: LONGINT;
	BEGIN
      Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
      IF S.class = Texts.Name THEN T := MarkedText();
        IF T # NIL THEN f := Files.Old(S.s);
          IF f = NIL THEN f := Files.New(S.s) END;
          Texts.Store(T, f, Files.Length(f), len);
          Files.Register(f); Files.Close(f)
        END
      END
	END Store;

  PROCEDURE Search*;
    VAR
      par: Oberon.ParList; S: Texts.Scanner; T: Texts.Text; RT: Texts.Reader;
      this: Files.File; R: Files.Rider;
      i, j, n: INTEGER; beg, end, time, pos, fpos, len: LONGINT; ch: CHAR;
      name, buf: ARRAY 32 OF CHAR;

      PROCEDURE Forward (n: INTEGER);
        VAR m: INTEGER; j: INTEGER;
      BEGIN m := M - n; j := 0;
        WHILE j # m DO buf[j] := buf[n + j]; INC(j) END;
        WHILE j # M DO Texts.Read(RT, buf[j]); INC(j) END
      END Forward;

	BEGIN
      par := Oberon.Par; 
      Texts.OpenScanner(S, par.text, par.pos); Texts.Scan(S);
      IF S.class = Texts.Name THEN
        COPY(S.s, name); this := Files.Old(S.s);
        IF this # NIL THEN Texts.Scan(S);
          IF (S.class = Texts.Char) & (S.c = "^") THEN
            Oberon.GetSelection(T, beg, end, time);
            IF time > 0 THEN
              Texts.OpenReader(RT, T, beg); i := 0; pos := beg;
              REPEAT Texts.Read(RT, spat[i]); INC(i); INC(pos) UNTIL (i = maxlen) OR (pos = end)
            END
          ELSIF S.class = Texts.String THEN i := 0;
            REPEAT spat[i] := S.s[i]; INC(i) UNTIL (i = maxlen) OR (i = S.len)
          END;
          IF i > 0 THEN M := i; j := 0;
            WHILE j # 256 DO d[j] := M; INC(j) END;
            j := 0;
            WHILE j # M - 1 DO d[ORD(spat[j])] := M - 1 - j; INC(j) END;
            NEW(T); fpos := 0;
            Files.Set(R, this, fpos); Files.Read(R, ch);
            WHILE ch = Texts.TextBlockId DO INC(fpos);
              Texts.Load(T, this, fpos, len); Texts.OpenReader(RT, T, 0);
              Forward(M); pos := M;
              LOOP j := M;
                REPEAT DEC(j) UNTIL (j < 0) OR (buf[j] # spat[j]);
                IF (j < 0) OR (pos >= T.len) THEN EXIT END;
                n := d[ORD(buf[M-1])];
                Forward(n); pos := pos + n
              END;
              IF j < 0 THEN
                Texts.WriteString(W, name); Texts.Write(W, "\"); Texts.WriteInt(W, fpos, 1); Texts.Write(W, " ");
                Texts.OpenReader(RT, T, 0);
                FOR i := 0 TO 15 DO
                  Texts.OpenScanner(S, T, Texts.Pos(RT)); Texts.Scan(S);
                  IF (S.class = Texts.Name) & ((S.s = "Date:") OR (S.s = "From:") OR (S.s = "Subject:")) THEN
                    Texts.Read(RT, ch);
                    WHILE (ch # CR) & (ch # 0X) DO Texts.Write(W, ch); Texts.Read(RT, ch) END;
                    Texts.Write(W, " ")
                  ELSE Texts.Read(RT, ch);
                    WHILE (ch # CR) & (ch # 0X) DO Texts.Read(RT, ch) END
                  END
                END;
                Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
              END;
              fpos := fpos + len;
              Files.Set(R, this, fpos); Files.Read(R, ch)
            END
          END
       END
    END
  END Search;

  PROCEDURE Open*;
		VAR T: Texts.Text;
		S: Texts.Scanner;
		V: Viewers.Viewer;
		X, Y: INTEGER;
		beg, end, time, pos, len: LONGINT;
        f: Files.File;
  BEGIN
    Oberon.GetSelection(T, beg, end, time);
    IF time > 0 THEN
      Texts.OpenScanner(S, T, beg); Texts.Scan(S);
      IF S.class = Texts.Name THEN f := Files.Old(S.s);
        IF f # NIL THEN Texts.Scan(S);
          IF (S.class = Texts.Char) & (S.c = "\") THEN Texts.Scan(S);
            IF S.class = Texts.Int THEN pos := S.i;
              NEW(T); Texts.Load(T, f, pos, len);
		      Oberon.AllocateUserViewer(Oberon.Par.vwr.X, X, Y);
		      V := MenuViewers.New(TextFrames.NewMenu(S.s, StandardMenu),
			    TextFrames.NewText(T, 0), TextFrames.menuH, X, Y)
            END
          END
        END
      END
    END
  END Open;

	(*--SMTP--*)
	
	PROCEDURE HexDigit(i: INTEGER): CHAR;
	BEGIN
		IF i < 10 THEN RETURN CHR(i+ORD("0")) ELSE RETURN CHR(i+ORD("A")-10) END;
	END HexDigit;

	PROCEDURE ReadStringO2I(VAR R: Texts.Reader; VAR s: ARRAY OF CHAR; quoted: BOOLEAN);
	VAR i: INTEGER;
			ch, iso: CHAR;
	BEGIN
		i := 0;
		Texts.Read(R, ch);
		WHILE ~R.eot & (ch # CR) & (i+3 < LEN(s)) DO
			IF R.lib IS Fonts.Font THEN
				iso := Strings.OberonToISO[ORD(ch)];
				IF ~quoted OR ((iso < CHR(128)) & (iso # "=")) THEN s[i] := iso
				ELSE
					s[i] := "=";
					s[i+1] := HexDigit((ORD(iso) DIV 16) MOD 16);
					s[i+2] := HexDigit(ORD(iso) MOD 16);
					INC(i, 2)
				END;
				INC(i)
			END;
			Texts.Read(R, ch)
		END;
		s[i] := 0X
	END ReadStringO2I;

	PROCEDURE Recipient(VAR i: INTEGER; VAR s, rcpt: ARRAY OF CHAR);
	VAR j: INTEGER;
	BEGIN j := 0;
		WHILE (s[i] # 0X) & (s[i] < "0") DO INC(i) END;
		WHILE (s[i] >= "0") OR (s[i] = ".") OR (s[i] = "%") OR (s[i] = "-") DO rcpt[j] := s[i]; INC(j); INC(i) END;
		rcpt[j] := 0X
	END Recipient;

	PROCEDURE SendText(S: NS.Connection; VAR R: Texts.Reader; user: ARRAY OF CHAR);
	VAR s: ARRAY 512 OF CHAR; t: ARRAY 32 OF CHAR; i, j: INTEGER;
	BEGIN
		s := "Mime-Version: 1.0"; NS.WriteString(S, s);
		s := "Content-Type: text/plain; charset=";
		i := 0; WHILE s[i] # 0X DO INC(i) END; s[i] := 22X; INC(i);
		t := "iso-8859-1";
		j := 0; WHILE t[j] # 0X DO s[i] := t[j]; INC(j); INC(i) END; s[i] := 22X; INC(i); s[i] := 0X;
		NS.WriteString(S, s);
		s := "Content-Transfer-Encoding: 8bit"; NS.WriteString(S, s);
		s := "X-Mailer: Original Oberon-mailer by RS/ARD"; NS.WriteString(S, s);
		IF CopySelf THEN
			s := "Bcc: "; Strings.Append(s, user); NS.WriteString(S, s)
		END;
		REPEAT
			ReadStringO2I(R, s, FALSE);
			IF (s[0] = ".") & (s[1] = 0X) THEN s[1] := "."; s[2] := 0X END;	(*safety*)
			SendCmd(S, s, "")
		UNTIL R.eot;
		SendCmd(S, ".", "")
	END SendText;

	PROCEDURE send;
	VAR Mail: NS.Connection;
			R: Texts.Reader; text: Texts.Text;
			s, t: ARRAY 2048 OF CHAR;
			rcpt: ARRAY 64 OF CHAR; i: INTEGER;
			user, pwd: ARRAY 16 OF CHAR;
	BEGIN
		text := MarkedText();
		IF text # NIL THEN
			Texts.OpenReader(R, text, 0); ReadStringO2I(R, t, FALSE);	(*valid mail text*)
			IF Prefix("To:", t) THEN Connect(Mail, host, SMTP, res);
				IF res = 0 THEN String("mailing");
					Response(Mail, s);
					IF s[0] = "2" THEN	(*connected*)
						SendCmd(Mail, "HELO", NS.hostName); Response(Mail, s);
						IF s[0] = "2" THEN
							user := "";  NS.GetPassword("pop", host, user, pwd);
							SendCmd(Mail, "MAIL FROM:", user); Response(Mail, s);
							IF s[0] = "2" THEN
								REPEAT
									i := 3;	(*set behind "To:", "Cc:", "cc:"*)
									Recipient(i, t, rcpt);
									WHILE rcpt[0] # 0X DO
										SendCmd(Mail, "RCPT TO:", rcpt); Response(Mail, s);
										IF s[0] # "2" THEN String(rcpt); String(" not found"); Ln END;
										Recipient(i, t, rcpt)
									END;
									ReadStringO2I(R, t, FALSE)
								UNTIL ~Prefix("To:", t) & ~Prefix("Cc:", t) & ~Prefix("cc:", t);
								IF CopySelf THEN
									SendCmd(Mail, "RCPT TO:", user); Response(Mail, s);
									IF s[0] # "2" THEN String(user); String(" not found"); Ln END
								END;
								SendCmd(Mail, "DATA", ""); Response(Mail, s);
								IF s[0] = "3" THEN
									Texts.OpenReader(R, text, 0); SendText(Mail, R, user); Response(Mail, s);
									IF s[0] = "2" THEN String(" done") ELSE String(" not done") END;
									Ln
								END
							END
						END
					ELSE String(" failed (mailer)"); Ln
                    END;
					Close(Mail)
				ELSE NS.CloseConnection(Mail); String("no connection"); Ln
                END
			ELSE String("no recipient"); Ln
            END
		END
	END send;
	
	PROCEDURE Send*;
	VAR S: Texts.Scanner;
	BEGIN OpenScanner(FALSE, S);
		IF S.class = Texts.Name THEN COPY(S.s, host); send
		ELSE String("mail host missing"); Ln
        END
	END Send;
	
    PROCEDURE Cite*;
      VAR  V: Viewers.Viewer; R: Texts.Reader; T: TextFrames.Frame;
        pos, beg, end, time: LONGINT; ch: CHAR;
    BEGIN
      V := Oberon.MarkedViewer();
      IF (V.dsc # NIL) & (V.dsc.next IS TextFrames.Frame) THEN
        T := V.dsc.next(TextFrames.Frame);
         IF T.sel > 0 THEN
           pos := T.selbeg.org; end := T.selend.pos;
           REPEAT
             Texts.WriteString(W, "> "); Texts.Insert(T.text, pos, W.buf);
             pos := pos + 2; end := end + 2;
             Texts.OpenReader(R, T.text, pos); Texts.Read(R, ch); INC(pos);
             WHILE (pos # end) & (ch # CR) DO Texts.Read(R, ch); INC(pos) END
           UNTIL pos = end
        END
      END
    END Cite;

BEGIN Texts.OpenWriter(W)
END TextMail.

!System.DeleteFiles Mail.TDB ~
!TextMail.DeleteAll
TextMail.Search Mail.TDB "From"
TextMail.GetAll Mail.TDB
TextMail.Store Mail.TDB
TextMail.Open

System.Free TextMail ~

TextMail.Send *
