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

MODULE ET;	(** portable *)	(* uh, Wed, 30-Jun-1993 *)

	IMPORT Display, Texts, TextFrames, Viewers, Files, Input, MenuViewers, Oberon, Objects, Fonts;

CONST
	AsciiTemp = "ET.XXX.Tmp";	(* temporary used file *)
	ErrorsText = "OberonErrors.Text";	(* text for conversion error number to error message *)
	PopupText = "ET.Popup.Menu";	(* commands for standard popup menus *)
	LogFile = "ET.Name.Log";	(* register names of stored files *)
	UserMenu = "System.Close System.Copy System.Grow ET.Move ET.Search ET.Replace ET.Store";
	SysMenu = "System.Close System.Copy System.Grow ET.Store";
	LogMenu = "ET.Clear ET.Locate ET.Error ET.Search ET.Store";
	UserAscii = "System.Close System.Copy System.Grow ET.Move ET.Search ET.Replace ET.StoreAscii";
	SysAscii = "System.Close System.Copy System.Grow ET.StoreAscii";
	
	Err = -1;	(* scanner *)
	
	CR = 0DX;	TAB = 09X;	SPACE = " ";	LF = 0AX;	DEL = 07FX;	Quote = 22X;
	LtArrow = 0C4X;	RtArrow = 0C3X;
	ML = 2;	MM = 1;	MR = 0;
	Fnt = 0;	Colr = 1;	Voff = 2;

	MinSplitHeight = 40;	MaxPatLen = 128;	BufLen = 64;
	FG = Display.FG;

TYPE
	Frame = Display.Frame;
	Object = Objects.Object;
	ObjMsg = Objects.ObjMsg;
	UpdateMsg = Texts.UpdateMsg;
	SelectMsg = Oberon.SelectMsg;
	Handler = Objects.Handler;

	FocMsg = RECORD (Display.FrameMsg)
		V: Viewers.Viewer;
	END;

	BackRdr = RECORD
		text: Texts.Text;
		buf: ARRAY BufLen OF CHAR;
		begPos: LONGINT;
		last, next: INTEGER;
		beg: BOOLEAN
	END;
	
	MenuStr = ARRAY 255 OF CHAR;
	

VAR
	tW, WL: Texts.Writer;
	popup: Texts.Text;	(* name of popup text *)
	para: Texts.Text;	(* parameter text for Call *)
	log: RECORD f: Files.File; r: Files.Rider END;		(* for names of stored texts *)
	sPat: ARRAY MaxPatLen OF CHAR;	(* search pattern [read only] *)
	sDv: ARRAY MaxPatLen + 1 OF INTEGER;	(* displacement vector for search pattern *)
	sPatLen: INTEGER;	(* number of valid characters in sPat [read only] *)
	rBuf: Texts.Buffer;	(* replace buffer [read only] *)
	lTime: LONGINT;	(* most recent time for sPat and/or rBuf *)
	inFnt: Fonts.Font;	(* input font *)
	inColor: SHORTINT;	(* input color *)
	menuAvail: BOOLEAN;	(* true if modul Menu is available *)
	filter: BOOLEAN;	(* filter compiler warnings *)
	mStr: ARRAY 6 OF MenuStr;	(* menu strings: 0=user / 1=system / 2=log / 3=userascii / 4=systemascii *)
	sX, sY: INTEGER;	(* saved coordinates for new viewer [used in Marker and ExchangeMenu] *)
	ii: INTEGER;
	
	PROCEDURE Min(i, j: LONGINT): LONGINT;
	BEGIN
		IF i < j THEN RETURN i ELSE RETURN j END
	END Min;
	
	PROCEDURE Max(i, j: LONGINT): LONGINT;
	BEGIN
		IF i > j THEN RETURN i ELSE RETURN j END
	END Max;

	PROCEDURE OpenScanner(VAR S: Texts.Scanner; text: Texts.Text; pos: LONGINT);
	BEGIN
		S.line := 0;
		IF text = NIL THEN S.class := Err
		ELSE Texts.OpenReader(S, text, pos); Texts.Read(S, S.nextCh); S.class := Texts.Inval
		END
	END OpenScanner;
	
	PROCEDURE ScanName(DX: INTEGER; VAR X, Y: INTEGER; VAR S: Texts.Scanner);
		VAR text: Texts.Text;	beg, end, time: LONGINT;
	BEGIN
		IF DX = Oberon.SystemTrack(DX) THEN Oberon.AllocateSystemViewer(DX, X, Y)
		ELSE Oberon.AllocateUserViewer(DX, X, Y)
		END;
		OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); IF S.class = Err THEN RETURN END;	(* ### *)
		Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "^") OR (S.line > 0) THEN	(* check for selection *)
			text := NIL; time := 0; Oberon.GetSelection(text, beg, end, time);
			IF (text = NIL) OR (time <= 0) THEN S.class := Texts.Inval; RETURN END;	(* ### *)
			OpenScanner(S, text, beg); Texts.Scan(S)
		END;
		IF S.class = Texts.Int  THEN	(* option y coordinate *)
			IF (Display.Bottom + Viewers.minH <= S.i) & (S.i <= Display.Height) THEN X := DX; Y := SHORT(S.i) END;
			Texts.Scan(S)
		END
	END ScanName;
	
	PROCEDURE ViewerName(V : Viewers.Viewer; VAR S: Texts.Scanner);
	(* return first name of viewer text *)
	BEGIN
		S.class := Texts.Inval;
		IF (V IS MenuViewers.Viewer) & (V.dsc IS TextFrames.Frame) THEN
			OpenScanner(S, V.dsc(TextFrames.Frame).text, 0); Texts.Scan(S)
		END
	END ViewerName;
	
	PROCEDURE ScanPara(VAR S: Texts.Scanner);
		VAR text: Texts.Text;	beg, end, time: LONGINT;
	BEGIN
		OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); IF S.class = Err THEN RETURN END;	(* ### *)
		Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "^") OR (S.line > 0) THEN	(* check for selection *)
			text := NIL; time := 0; Oberon.GetSelection(text, beg, end, time);
			IF (text = NIL) OR (time <= 0) THEN S.class := Texts.Inval; RETURN END;	(* ### *)
			OpenScanner(S, text, beg); Texts.Scan(S)
		END
	END ScanPara;
	
	PROCEDURE ScanQuote(VAR S: Texts.Scanner; VAR s: ARRAY  OF CHAR);
		VAR i: INTEGER;
	BEGIN
		i := 0;
		WHILE (S.nextCh # Quote) & (S.nextCh # CR) & ~ S.eot DO Texts.Read(S, S.nextCh) END;
		IF S.nextCh = Quote THEN
			i := 0; Texts.Read(S, S.nextCh);
			WHILE (S.nextCh # Quote) & (S.nextCh # CR) & ~ S.eot DO
				IF i < LEN(s) THEN s[i] := S.nextCh; INC(i) END;
				Texts.Read(S, S.nextCh)
			END;
			IF S.nextCh = Quote THEN Texts.Read(S, S.nextCh) END
		END;
		IF i < LEN(s) THEN s[i] := 0X ELSE s[LEN(s)-1] := 0X END
	END ScanQuote;
	
	PROCEDURE FocusViewer(): Viewers.Viewer;
		VAR M: FocMsg;
	BEGIN
		M.V := NIL; M.F := NIL; Display.Broadcast(M);
		IF M.V = NIL THEN M.V := Oberon.MarkedViewer() END;
		RETURN M.V
	END FocusViewer;
	
	PROCEDURE SetFocus(V: Viewers.Viewer);
	BEGIN Oberon.Defocus
	END SetFocus;
	
	PROCEDURE Defocus(tF: TextFrames.Frame);
	BEGIN Oberon.Defocus
	END Defocus;

	PROCEDURE GetSelData(tF: TextFrames.Frame; VAR text: Texts.Text; VAR beg, end, time: LONGINT);
	VAR M: SelectMsg; (* gets correct selection data of textframe tF *)
	BEGIN
		M.time := -1; M.id := Display.get; TextFrames.GetSelection(tF, M);
		text := M.text; beg := M.beg; end := M.end; time := M.time
	END GetSelData;
	
	PROCEDURE GetSelFrame(VAR F: TextFrames.Frame);
		VAR M: Oberon.SelectMsg;
	BEGIN
		M.id := Oberon.get; M.F := NIL;
		M.time := -1; M.sel := NIL; M.text := NIL; 
		Display.Broadcast(M);
		IF (M.time >= 0) & (M.text # NIL) & (M.sel # NIL) & (M.sel IS TextFrames.Frame) THEN
			F := M.sel(TextFrames.Frame)
		ELSE F := NIL
		END
	END GetSelFrame;
	
	PROCEDURE ReaderFnt(VAR R: Texts.Reader): Fonts.Font;
	BEGIN RETURN R.lib(Fonts.Font)
	END ReaderFnt;
	
	PROCEDURE AdjustFont(VAR W: Texts.Writer; VAR R: Texts.Reader);
	BEGIN
		IF W.lib # R.lib THEN Texts.SetFont(tW, R.lib) END
	END AdjustFont;
	
	PROCEDURE SetDefFont(VAR W: Texts.Writer);
	BEGIN
		IF W.lib # Fonts.Default THEN Texts.SetFont(W, Fonts.Default) END
	END SetDefFont;
(*-v2-
	PROCEDURE FocusViewer(): Viewers.Viewer;
	BEGIN
		RETURN Oberon.FocusViewer
	END FocusViewer;
	
	PROCEDURE SetFocus(V: Viewers.Viewer);
	BEGIN
		IF Oberon.FocusViewer # V THEN Oberon.PassFocus(V) END
	END SetFocus;
	
	PROCEDURE Defocus(tF: TextFrames.Frame);
		VAR M: Oberon.InputMsg;
	BEGIN
		IF tF # NIL THEN SetFocus(Viewers.This(tF.X, tF.Y))
		ELSE
			M.id := Oberon.defocus; Oberon.FocusViewer.handle(Oberon.FocusViewer, M)
		END
	END Defocus;
	
	PROCEDURE GetSelData(tF: TextFrames.Frame; VAR text: Texts.Text; VAR beg, end, time: LONGINT);
	BEGIN
		text := NIL; time := -1;
		TextFrames.GetSelection(tF, text, beg, end, time)
	END GetSelData;
	
	PROCEDURE GetSelFrame(VAR F: TextFrames.Frame);
		VAR time: LONGINT; V: Viewers.Viewer; X: INTEGER; f: TextFrames.Frame;
	BEGIN
		time := -1; X := 0; F := NIL;
		WHILE X < Display.Width DO V := Viewers.This(X, 0);
			WHILE V.state > 1 DO
				IF (V.dsc # NIL) & (V.dsc.next # NIL) & (V.dsc.next IS TextFrames.Frame) THEN
					f := V.dsc.next(TextFrames.Frame); 
					IF (f.sel > 0) & (f.time > time) THEN F := f; time := f.time END
				END;
				V := Viewers.Next(V)
			END;
			X := X + V.W
		END
	END GetSelFrame;
	
	PROCEDURE ReaderFnt(VAR R: Texts.Reader): Fonts.Font;
	BEGIN RETURN R.fnt
	END ReaderFnt;
	
	PROCEDURE AdjustFont(VAR W: Texts.Writer; VAR R: Texts.Reader);
	BEGIN
		IF W.fnt # R.fnt THEN Texts.SetFont(tW, R.fnt) END
	END AdjustFont;
	
	PROCEDURE SetDefFont(VAR W: Texts.Writer);
	BEGIN
		IF W.fnt # Fonts.Default THEN Texts.SetFont(W, Fonts.Default) END
	END SetDefFont;
-v-*)
	
	PROCEDURE LinesOf(tF: TextFrames.Frame): INTEGER;
	BEGIN
		RETURN (tF.H - tF.top - tF.bot) DIV tF.lsp
	END LinesOf;
		
	PROCEDURE OpenBackRdr(VAR bR: BackRdr; text: Texts.Text; pos: LONGINT);
		VAR R: Texts.Reader;	i: INTEGER;	ch: CHAR;
	BEGIN
		bR.text := text; bR.beg := FALSE; bR.next := BufLen - 1;
		IF pos >= BufLen THEN
			bR.begPos := pos - BufLen; i := 0; Texts.OpenReader(R, text, bR.begPos)
		ELSE
		(*
			i := 0; WHILE i < (BufLen - pos) DO bR.buf[i] := 0X; INC(i) END;
		*)
			i := SHORT(BufLen - pos);
			bR.begPos := -i; Texts.OpenReader(R, text, 0)
		END;
		bR.last := i; Texts.Read(R, ch);
		WHILE i < BufLen DO bR.buf[i] := ch; INC(i); Texts.Read(R, ch) END
	END OpenBackRdr;
	
	PROCEDURE BackRead(VAR bR: BackRdr; VAR ch: CHAR);
	BEGIN
		IF bR.next >= bR.last THEN
			ch := bR.buf[bR.next]; DEC(bR.next); bR.beg := FALSE
		ELSIF (bR.next = -1) & (bR.begPos > 0) THEN
			OpenBackRdr(bR, bR.text, bR.begPos); BackRead(bR, ch)
		ELSE ch := 0X; bR.beg := TRUE
		END
	END BackRead;
	
	PROCEDURE RPos(VAR bR: BackRdr): LONGINT;
	BEGIN
		IF bR.next >= 0 THEN RETURN bR.begPos + bR.next + 1
		ELSE RETURN bR.begPos
		END
	END RPos;
	
	PROCEDURE LinesUp(text: Texts.Text; pos: LONGINT; nbr: INTEGER): LONGINT;
	(* returns the start position of nbr lines above line containing pos *)
		VAR bR: BackRdr;	l: INTEGER;	ch: CHAR;
	BEGIN
		OpenBackRdr(bR, text, pos); l := 0;
		REPEAT
			BackRead(bR, ch);
			IF ch = CR THEN INC(l) END
		UNTIL bR.beg OR (l > nbr);
		pos := RPos(bR); IF ~ bR.beg THEN INC(pos) END;	(* RPos(bR) = pos of CR *)
		RETURN pos
	END LinesUp;
	
	PROCEDURE RemoveMarks(tF : TextFrames.Frame);
	BEGIN
		TextFrames.RemoveSelection(tF); TextFrames.RemoveCaret(tF); 
		Oberon.RemoveMarks(tF.X, tF.Y, tF.W, tF.H)
	END RemoveMarks;
		
	PROCEDURE ShowPos(tF: TextFrames.Frame; pos: LONGINT);
		VAR org, lines: LONGINT;
	BEGIN
		IF (pos < TextFrames.Pos(tF, tF.X , tF.Y + tF.H)) OR (TextFrames.Pos(tF, tF.X + tF.W, tF.Y) < pos) THEN
			lines := LinesOf(tF);
			IF lines > 4 THEN org := LinesUp(tF.text, pos, 4)
			ELSE org := LinesUp(tF.text, pos, 1)
			END;
			TextFrames.Show(tF, org)
		END
	END ShowPos;

	PROCEDURE SendTabs(tF: TextFrames.Frame; VAR M: Oberon.InputMsg);
		VAR tR: Texts.Reader;	ch: CHAR;	pos: LONGINT;	T: Texts.Text;
	BEGIN
		T := tF.text;
		pos := LinesUp(T, tF.carloc.pos, 1);
		Texts.OpenReader(tR, T, pos); Texts.Read(tR, ch);
		WHILE ~ tR.eot & ((ch = TAB) OR (ch = SPACE)) DO 
			M.ch := ch; TextFrames.Handle(tF, M); Texts.Read(tR, ch)
		END
	END SendTabs;

	PROCEDURE ScrollFrame(tF: TextFrames.Frame; X, Y: INTEGER; keys: SET);
		VAR mm, mr, ml: BOOLEAN;	pos: LONGINT;	lPos: INTEGER;
	BEGIN
		ml := FALSE; mm := FALSE; mr := FALSE;
		IF keys = {ML} THEN
			TextFrames.TrackLine(tF, X, Y, pos, keys);
			IF MM IN keys THEN mm := TRUE END;
			IF MR IN keys THEN mr := TRUE END;
			IF mm OR mr THEN RETURN END;
			Oberon.FadeCursor(Oberon.Mouse); RemoveMarks(tF);
			TextFrames.Show(tF, pos)	(* scroll distance up *)
		ELSIF keys = {MM} THEN
			WHILE keys # {} DO
				Input.Mouse(keys, X, Y); Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, X, Y);
				IF ML IN keys THEN ml := TRUE END;
				IF MR IN keys THEN mr := TRUE END
			END;
			IF ml & mr THEN RETURN END;
			Oberon.FadeCursor(Oberon.Mouse); RemoveMarks(tF);
			IF mr THEN TextFrames.Show(tF, 0)	(* scroll to begin *)
			ELSIF ml THEN	(* scroll to end *)
				lPos := LinesOf(tF);
				IF lPos > 1 THEN TextFrames.Show(tF, LinesUp(tF.text, tF.text.len, lPos - 1)) END
			ELSE	(* relative positioning *)
				pos := (tF.text.len DIV tF.H) * (tF.Y + tF.H - Y);
				IF pos < 0 THEN pos := 0 END;
				IF tF.org # pos THEN TextFrames.Show(tF, pos) END
			END
		ELSIF keys = {MR} THEN mr := TRUE;
			TextFrames.TrackLine(tF, X, Y, pos, keys);	(* beginning of new bottom line *)
			IF MM IN keys THEN mm := TRUE END;
			IF ML IN keys THEN ml := TRUE END;
			IF ml OR mm THEN RETURN END;	(* ### *)
			Oberon.FadeCursor(Oberon.Mouse); RemoveMarks(tF);
			lPos := LinesOf(tF);
			IF lPos > 1 THEN TextFrames.Show(tF, LinesUp(tF.text, pos, lPos - 1)) END
		END
	END ScrollFrame;
	
	PROCEDURE DisplayMenu(tF: TextFrames.Frame; X, Y: INTEGER; text: Texts.Text; pos: LONGINT);
		VAR cmd: ARRAY 32 OF CHAR;	res: INTEGER;
	BEGIN
		IF menuAvail THEN
			cmd := "Menu.ShowCmd";
			Oberon.Par.text := text; Oberon.Par.pos := pos;
			Oberon.Par.vwr := Viewers.This(X, Y); Oberon.Par.frame := Oberon.Par.vwr.dsc;
			Oberon.Call(cmd, Oberon.Par, FALSE, res);
			menuAvail := (res = 0)
		END
	END DisplayMenu;

	PROCEDURE TrackedMM(tF: TextFrames.Frame; X, Y: INTEGER; keys: SET): BOOLEAN;
		VAR R: Texts.Reader;	bR: BackRdr;	T: Texts.Text;	ch: CHAR;
	BEGIN
		T := tF.text;
		Texts.OpenReader(R, T, TextFrames.Pos(tF, X, Y)); Texts.Read(R, ch);
		IF (ch = CR) OR (ch = TAB) OR (ch = SPACE) OR (ch = 0X) THEN
			IF (popup # NIL) & menuAvail THEN DisplayMenu(tF, X, Y, popup, 0); RETURN menuAvail
			ELSE RETURN FALSE
			END
		ELSE
			OpenBackRdr(bR, T, Texts.Pos(R)); BackRead(bR, ch);
			WHILE ~bR.beg & (ch # "^") & ~ ((ch = CR) OR (ch = TAB) OR (ch = SPACE) OR (ch = 0X)) DO BackRead(bR, ch) END;
			IF (ch = "^") & menuAvail THEN
				DisplayMenu(tF, X, Y, T, RPos(bR) + 1); RETURN menuAvail
			ELSE RETURN FALSE
			END
		END
	END TrackedMM;

	PROCEDURE right(F: Frame; nbr: SHORTINT);
		VAR tF: TextFrames.Frame;	text: Texts.Text;	R: Texts.Reader;	ch, dh: CHAR;
			beg, end, time, fLine, lLine: LONGINT;	nr: SHORTINT;
	BEGIN
		IF F = NIL THEN GetSelFrame(tF) ELSIF F IS TextFrames.Frame THEN tF := F(TextFrames.Frame) ELSE tF := NIL END;
		IF (tF # NIL) & (tF.sel > 0) THEN
			GetSelData(tF, text, beg, end, time);
			IF (text # NIL) & (time > 0) THEN
				fLine := LinesUp(text, beg, 0); lLine := LinesUp(text, end - 1, 0);
				Texts.OpenReader(R, text, fLine); Texts.Read(R, ch); AdjustFont(tW, R);
				IF (ch # SPACE) & (ch # TAB) THEN ch := TAB END;
				nr := nbr; WHILE nr > 0 DO Texts.Write(tW, ch); DEC(nr); INC(end) END; Texts.Insert(text, lLine, tW.buf);
				WHILE fLine # lLine DO
					lLine := LinesUp(text, lLine - 1, 0);
					Texts.OpenReader(R, text, lLine); Texts.Read(R, dh); AdjustFont(tW, R);
					nr := nbr; WHILE nr > 0 DO Texts.Write(tW, ch); DEC(nr); INC(end) END; Texts.Insert(text, lLine, tW.buf)
				END;
				TextFrames.SetSelection(tF, beg, end)
			END;
			Texts.SetFont(tW, Fonts.Default)
		END
	END right;
	
	PROCEDURE Right*;
	(* idents last current selected text to right by a tabulator *)
	BEGIN
		IF (Oberon.Par.vwr # NIL) & (Oberon.Par.frame = Oberon.Par.vwr.dsc) THEN
			right(Oberon.Par.vwr.dsc.next, 1)
		ELSE right(NIL, 1)
		END
	END Right;

	PROCEDURE IsCh(T: Texts.Text; pos: LONGINT): BOOLEAN;
	(* tests if character in text T at position pos is a tabulator or space *)
		VAR R: Texts.Reader;	ch: CHAR;
	BEGIN
		Texts.OpenReader(R, T, pos); Texts.Read(R, ch);
		RETURN (ch = SPACE) OR (ch = TAB)
	END IsCh;

	PROCEDURE left(F: Frame; nbr: SHORTINT);
		VAR tF: TextFrames.Frame;	text: Texts.Text;
			beg, end, time, fLine, lLine: LONGINT;	nr: SHORTINT;
	BEGIN
		IF F = NIL THEN GetSelFrame(tF) ELSIF F IS TextFrames.Frame THEN tF := F(TextFrames.Frame) ELSE tF := NIL END;
		IF (tF # NIL) & (tF.sel > 0) THEN
			GetSelData(tF, text, beg, end, time);
			IF (text # NIL) & (time > 0) THEN
				fLine := LinesUp(text, beg, 0); lLine := LinesUp(text, end - 1, 0);
				nr := nbr; WHILE (nr > 0) & IsCh(text, lLine) DO Texts.Delete(text, lLine, lLine + 1); DEC(nr); DEC(end) END;
				WHILE fLine # lLine DO
					lLine := LinesUp(text, lLine - 1, 0);
					nr := nbr; WHILE (nr > 0) & IsCh(text, lLine) DO Texts.Delete(text, lLine, lLine + 1); DEC(nr); DEC(end) END
				END;
				TextFrames.SetSelection(tF, beg, end)
			END
		END
	END left;

	PROCEDURE Left*;
	(* idents last current selected text to left *)
	BEGIN
		IF (Oberon.Par.vwr # NIL) & (Oberon.Par.frame = Oberon.Par.vwr.dsc) THEN
			left(Oberon.Par.vwr.dsc.next, 1)
		ELSE left(NIL, 1)
		END
	END Left;

	PROCEDURE SetInFnt(tF: TextFrames.Frame; VAR inFnt: Fonts.Font; VAR inCol: SHORTINT);
		VAR R: Texts.Reader;	ch: CHAR;
	BEGIN
		IF (tF.car > 0) & (tF.text.len > 0) THEN
			Texts.OpenReader(R, tF.text, tF.carloc.pos);
			Texts.Read(R, ch);
			IF R.eot & (tF.carloc.pos > 0) THEN
				Texts.OpenReader(R, tF.text, tF.carloc.pos-1); Texts.Read(R, ch)
			END;
			IF ~ R.eot THEN inFnt := ReaderFnt(R); inCol := R.col END
		ELSE inFnt := NIL; inCol := -1
		END
	END SetInFnt;
	
	PROCEDURE PredSelFrame(tF: TextFrames.Frame): TextFrames.Frame;
		VAR V: Viewers.Viewer;	f: TextFrames.Frame;
	BEGIN
		f := NIL; V := Viewers.This(tF.X, tF.Y); V := V.next(Viewers.Viewer);
		IF (V.dsc # NIL) & (V.dsc.next # NIL) & (V.dsc.next IS TextFrames.Frame) THEN
			f := V.dsc.next(TextFrames.Frame);
			IF (f.text = tF.text) & (f.sel > 0) THEN (* skip *) ELSE f := NIL END
		END;
		RETURN f
	END PredSelFrame;
	
	PROCEDURE PreHandleMR(tF: TextFrames.Frame; VAR X, Y: INTEGER; keys: SET);
		VAR V: Viewers.Viewer;	pF: TextFrames.Frame;	newPos, endPos: LONGINT;
	BEGIN
		IF (X >= tF.X  + Min(tF.left, TextFrames.barW)) THEN	(* not in scrollbar *)
			pF := PredSelFrame(tF);
			IF pF # NIL THEN
				newPos := TextFrames.Pos(tF, X, Y); endPos := TextFrames.Pos(pF, pF.X + pF.W, pF.Y) + 1;
				IF (pF.selend.pos < newPos) & (endPos <= newPos) & (pF.selbeg.pos <= tF.org) THEN
					TextFrames.SetSelection(pF, pF.selbeg.pos, endPos);
					X := tF.X + tF.left; Y := tF.Y + tF.H - 1;	(* to start selection at frame origin *)
				ELSE
					TextFrames.RemoveSelection(pF)
				END
			END
		END
	END PreHandleMR;
	
	PROCEDURE GetSelection(tF: TextFrames.Frame; VAR M: SelectMsg; VAR handled: BOOLEAN);
		VAR pF: TextFrames.Frame;
	BEGIN
		handled := (tF.sel > 0) & (tF.time > M.time);
		IF handled THEN
			GetSelData(tF, M.text, M.beg, M.end, M.time);
			pF := PredSelFrame(tF);
			IF (pF # NIL) & (pF.time < M.time) & (pF.selbeg.pos < M.end) THEN	(* enlarge selection *)
				M.beg := pF.selbeg.pos
			END
		END
	END GetSelection;

	PROCEDURE MarkMenu(F: Frame; updT: Texts.Text);
		VAR R: Texts.Reader; V: Viewers.Viewer; T: Texts.Text; ch: CHAR;
	BEGIN V := Viewers.This(F.X, F.Y);
		IF (V IS MenuViewers.Viewer) & (V.dsc IS TextFrames.Frame) THEN
			T := V.dsc(TextFrames.Frame).text;
			IF T # updT THEN
				IF T.len > 0 THEN Texts.OpenReader(R, T, T.len - 1); Texts.Read(R, ch) ELSE ch := 0X END;
				IF ch # "!" THEN Texts.WriteString(WL, " !"); Texts.Append(T, WL.buf) END
			END
		END
	END MarkMenu;

	PROCEDURE UnMarkMenu(F: Frame);
		VAR R: Texts.Reader; V: Viewers.Viewer; T: Texts.Text; ch: CHAR;
	BEGIN V := Viewers.This(F.X, F.Y);
		IF (V IS MenuViewers.Viewer) & (V.dsc IS TextFrames.Frame) THEN T := V.dsc(TextFrames.Frame).text;
			IF T.len > 0 THEN Texts.OpenReader(R, T, T.len - 1); Texts.Read(R, ch) ELSE ch := 0X END;
			IF ch = "!" THEN Texts.Delete(T, T.len - 2, T.len) END
		END
	END UnMarkMenu;
	
	PROCEDURE IsWarning(VAR M: UpdateMsg): BOOLEAN;
		VAR S: Texts.Scanner;
	BEGIN
		Texts.OpenScanner(S, M.text, M.beg); Texts.Scan(S);
		IF (S.class = Texts.Name) & (S.s = "pos") THEN Texts.Scan(S); Texts.Scan(S) END;
		RETURN (S.class = Texts.Name) & (S.s = "warning")
	END IsWarning;
	
	PROCEDURE TextProcessor(tF: TextFrames.Frame; VAR M: UpdateMsg);
		VAR scroll: BOOLEAN;	lUp, pos: LONGINT;
	BEGIN
		scroll := FALSE;
		IF tF.text = Oberon.Log THEN
			IF (tF.car = 0) & (M.beg = M.end) THEN
				IF filter & IsWarning(M) THEN
					tF.text := NIL; Texts.Delete(M.text, M.beg, M.beg+M.len);
					tF.text := M.text; RETURN	(* ### *)
				END;
				scroll := TRUE
			END
		ELSE  MarkMenu (tF, tF.text)
		END;
		TextFrames.Handle(tF, M);
		IF scroll THEN
			lUp := LinesOf(tF) - 1;
			IF lUp > 0 THEN
				pos := LinesUp(tF.text, tF.text.len, SHORT(lUp));
				IF pos > tF.org THEN TextFrames.Show(tF, pos) END
			END
		END
	END TextProcessor;
	
	PROCEDURE Handle*(F: Object; VAR M: ObjMsg);
		VAR tF: TextFrames.Frame;	handled, ml: BOOLEAN;	T: Texts.Text;
	BEGIN
		tF := F(TextFrames.Frame);
		T := tF.text; IF T = NIL THEN RETURN END;	(* ### *)
		handled := FALSE;
		IF M IS Oberon.InputMsg THEN
			WITH M: Oberon.InputMsg DO
				IF (M.id = Oberon.consume) & (tF.car > 0) THEN
					IF inFnt #  NIL THEN M.fnt := inFnt; M.col := inColor END;	(* adjust input font *)
					IF M.ch = CR THEN
						TextFrames.Handle(F, M); handled := TRUE;
						SendTabs(tF, M)
					ELSIF M.ch = LF THEN
						M.ch := CR; TextFrames.Handle(F, M); handled := TRUE; M.ch := LF	(* restore msg *)
					ELSIF (M.ch = LtArrow) THEN
						IF (tF.carloc.pos > 0) THEN
							TextFrames.RemoveCaret(tF); TextFrames.SetCaret(tF, tF.carloc.pos - 1)
						END;
						handled := TRUE
					ELSIF (M.ch = RtArrow) THEN
						IF (tF.carloc.pos < T.len) THEN
							TextFrames.RemoveCaret(tF); TextFrames.SetCaret(tF, tF.carloc.pos + 1)
						END;
						handled := TRUE
					END
				ELSIF M.id = Oberon.track THEN
					IF tF.Y <= M.Y THEN
						IF M.X >= tF.X + Min(tF.left, TextFrames.barW) THEN	(* not in scrollbar *)
							IF M.keys = {MM} THEN handled := TrackedMM(tF, M.X, M.Y, M.keys)
							ELSE
								IF M.keys = {MR} THEN PreHandleMR(tF, M.X, M.Y, M.keys) END;
								ml := M.keys = {ML}; handled := TRUE; TextFrames.Handle(F, M);
								IF ml THEN SetInFnt(tF, inFnt, inColor) END
							END
						ELSIF tF.left > TextFrames.barW THEN	(* scrollbar exisiting *)
							Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, M.X, M.Y); handled := TRUE;
							IF M.keys # {} THEN ScrollFrame(tF, M.X, M.Y, M.keys) END
						END
					END
				END	(* IF M.id = ... *)
			END		(* WITH M: ... *)
		ELSIF M IS UpdateMsg THEN
			WITH M: UpdateMsg DO
				IF M.text = T THEN TextProcessor(tF, M); handled := TRUE END
			END;
		ELSIF M IS SelectMsg THEN
			GetSelection(tF, M(SelectMsg), handled);
			IF handled THEN M(SelectMsg).sel := tF ELSE handled := TRUE END
		ELSIF M IS FocMsg THEN
			IF tF.car = 1 THEN M(FocMsg).V := Viewers.This(tF.X, tF.Y) END
		END;
		IF ~ handled THEN TextFrames.Handle(F, M) END
	END Handle;
	
	PROCEDURE AsciiText(name: ARRAY OF CHAR): Texts.Text;
		VAR text: Texts.Text;	res: INTEGER;	ch, pch: CHAR;
			f, g : Files.File;	Rf, Rg : Files.Rider;
	BEGIN
		f := Files.Old(name);
		IF f # NIL THEN g := Files.New(AsciiTemp);
			Files.Set(Rf, f, 0); Files.Set(Rg, g, 0); Files.Read(Rf, ch); pch := 0X;
			WHILE ~Rf.eof DO
				IF (ch = LF) & (pch # CR) THEN Files.Write(Rg, CR)	(* unix *)
				ELSIF (ch # LF) & (ch # 1AX) THEN Files.Write(Rg, ch) 
				END;
				pch := ch; Files.Read(Rf, ch) 
			END;
			Files.Register(g);
			text := TextFrames.Text(AsciiTemp);
			Files.Delete(AsciiTemp, res)
		ELSE text := TextFrames.Text("")
		END;
		RETURN text
	END AsciiText;
	
	PROCEDURE NewMF(mTitle: ARRAY OF CHAR; typ: INTEGER; VAR menuH: INTEGER): TextFrames.Frame;
		VAR F: TextFrames.Frame;
	BEGIN
		menuH := TextFrames.menuH;
		F := TextFrames.NewMenu(mTitle, mStr[typ]);
		F.handle := Handle;
		RETURN F
	END NewMF;
	
	PROCEDURE NewETF(text: Texts.Text; org: LONGINT): TextFrames.Frame;
		VAR F: TextFrames.Frame;
	BEGIN
		F := TextFrames.NewText(text, org);
		F.handle := Handle;
		RETURN F
	END NewETF;

	PROCEDURE OpenViewer(text: Texts.Text; title: ARRAY OF CHAR; pos: LONGINT;
												X, Y: INTEGER; kind: SHORTINT): Viewers.Viewer;
		VAR mF: TextFrames.Frame;	menuH: INTEGER;
	BEGIN
		IF text = NIL THEN text := TextFrames.Text("") END;
		mF := NewMF(title, kind, menuH);
		RETURN MenuViewers.New(mF, NewETF(text, pos), menuH, X, Y)
	END OpenViewer;
		
	PROCEDURE New*;
		VAR V: Viewers.Viewer;	X, Y: INTEGER;
	BEGIN
		Oberon.AllocateUserViewer(Oberon.UserTrack(Oberon.Par.vwr.X), X, Y);
		V := OpenViewer(NIL, "ET.New", 0, X, Y, 0)
	END New;
		
	PROCEDURE NewSys*;
		VAR V: Viewers.Viewer;	X, Y: INTEGER;
	BEGIN
		Oberon.AllocateSystemViewer(Oberon.SystemTrack(Oberon.Par.vwr.X), X, Y);
		V := OpenViewer(NIL, "ET.NewSys", 0, X, Y, 1)
	END NewSys;

	PROCEDURE Open*;
		VAR V: Viewers.Viewer;	X, Y: INTEGER;	text: Texts.Text;	S: Texts.Scanner;
	BEGIN
		ScanName(Oberon.UserTrack(Oberon.Par.vwr.X), X, Y, S);
		IF S.class = Texts.Name THEN text := TextFrames.Text(S.s); V := OpenViewer(text, S.s, 0, X, Y, 0)
		ELSE text := NIL; V := OpenViewer(text, "ET.Open", 0, X, Y, 0)
		END
	END Open;

	PROCEDURE OpenSys*;
		VAR V: Viewers.Viewer;	X, Y: INTEGER;	text: Texts.Text;	S: Texts.Scanner;
	BEGIN
		ScanName(Oberon.SystemTrack(Oberon.Par.vwr.X), X, Y, S);
		IF S.class = Texts.Name THEN text := TextFrames.Text(S.s); V := OpenViewer(text, S.s, 0, X, Y, 1)
		ELSE text := NIL; V := OpenViewer(text, "ET.OpenSys", 0, X, Y, 1)
		END
	END OpenSys;
	
	PROCEDURE OpenAscii*;
		VAR V: Viewers.Viewer;	X, Y: INTEGER;	S: Texts.Scanner;
	BEGIN
		ScanName(Oberon.UserTrack(Oberon.Par.vwr.X), X, Y, S);
		IF S.class = Texts.Name THEN V := OpenViewer(AsciiText(S.s), S.s, 0, X, Y, 3)
		ELSE V := OpenViewer(TextFrames.Text(""), "ET.OpenAscii", 0, X, Y, 3)
		END
	END OpenAscii;
	
	PROCEDURE OpenSysAscii*;
		VAR V: Viewers.Viewer;	X, Y: INTEGER;	S: Texts.Scanner;
	BEGIN
		ScanName(Oberon.SystemTrack(Oberon.Par.vwr.X), X, Y, S);
		IF S.class = Texts.Name THEN V := OpenViewer(AsciiText(S.s), S.s, 0, X, Y, 4)
		ELSE V := OpenViewer(TextFrames.Text(""), "ET.OpenSysAscii", 0, X, Y, 4)
		END
	END OpenSysAscii;
	
	PROCEDURE CalcDispVec(time: LONGINT);
		VAR i, j, d: INTEGER;
	BEGIN
		lTime := time;
		i := 1; d := 1;	(* calculate displacement vector *)
		WHILE i <= sPatLen DO
			j := 0; WHILE (j + d < sPatLen) & (sPat[j] = sPat[j + d]) DO INC(j) END;
			WHILE i <= j + d DO sDv[i] := d; INC(i) END;
			INC(d)
		END
	END CalcDispVec;

	PROCEDURE SPatFound(tF: TextFrames.Frame; text: Texts.Text; VAR pos:LONGINT): BOOLEAN;
	(* searches the next position for the search pattern sPat begining at position pos *)
	(* in the text text; resturns result accordingly *) 
		VAR R: Texts.Reader;	l: LONGINT;	i: INTEGER;	ch: CHAR;
	BEGIN
		IF sPatLen > 0 THEN
			IF tF # NIL THEN TextFrames.Mark(tF, -1) END;
			Texts.OpenReader(R, text, pos); Texts.Read(R, ch); INC(pos);
			l := text.len; i := 0;
			WHILE (i # sPatLen) & (pos <= l) DO
				IF ch = sPat[i] THEN
					INC(i); IF i < sPatLen THEN Texts.Read(R, ch); INC(pos) END
				ELSIF i = 0 THEN Texts.Read(R, ch); INC(pos)
				ELSE DEC(i, sDv[i])
				END
			END;
			IF tF # NIL THEN TextFrames.Mark(tF, 1) END
		ELSE i := -1
		END;
		RETURN i = sPatLen	(* pattern found *)
	END SPatFound;
	
	PROCEDURE Show*;
	(** specification needed: "text.pattern"; loads the text text, searches the pattern *)
	(** pattern and shows it in a viewer *)
		VAR text: Texts.Text;	S: Texts.Scanner;	V: Viewers.Viewer;
			X, Y, i, j, M: INTEGER;	pos, beg, end: LONGINT;	name: ARRAY 35 OF CHAR;
	BEGIN
		ScanName(Oberon.UserTrack(Oberon.Par.vwr.X), X, Y, S);
		IF S.class # Texts.Name THEN RETURN END;	(* ### *)
		i := -1; j := 0;
		WHILE S.s[j] # 0X DO
			IF S.s[j] = "." THEN i := j END;
			name[j] := S.s[j]; INC(j)
		END;
		IF i = -1 THEN i := j; name[i] := "." END;
		name[i+1] := "M"; name[i+2] := "o"; name[i+3] := "d"; name[i+4] := 0X;
		text := TextFrames.Text(name);
		j := i+1; M := 0;
		WHILE (M # MaxPatLen) & (S.s[j] # 0X) DO sPat[M] := S.s[j]; INC(j); INC(M) END;
		sPatLen := M;  CalcDispVec(Oberon.Time());	(* calculate displacement vector *)
		pos := 0;
		IF ~ SPatFound(NIL, text, pos) THEN pos := 0 END;
		V := OpenViewer(text, name, Max(0, pos-200), X, Y, 0);
		IF pos > 0 THEN
			SetFocus(V);
			TextFrames.SetCaret(V.dsc.next(TextFrames.Frame), pos)	(* passes the focus to this frame *)
		END		
	END Show;
	
	PROCEDURE WriteDate(VAR r: Files.Rider; t, d: LONGINT);

		PROCEDURE WritePair(ch: CHAR; x: LONGINT);
		BEGIN
			Files.Write(r, ch);
			Files.Write(r, CHR(x DIV 10 + 30H)); Files.Write(r, CHR(x MOD 10 + 30H))
		END WritePair;

	BEGIN
		WritePair(" ", d MOD 32); WritePair(".", d DIV 32 MOD 16); WritePair(".", d DIV 512 MOD 128);
		WritePair(" ", t DIV 4096 MOD 32); WritePair(":", t DIV 64 MOD 64);
		(* WritePair(":", t MOD 64) *)
	END WriteDate;
	
	PROCEDURE UpdateNameLog(name: ARRAY OF CHAR; typ: CHAR);
		VAR t, d: LONGINT;	i: INTEGER;
	BEGIN
		IF log.f # NIL THEN
			Oberon.GetClock (t, d); WriteDate(log.r, t, d);
			Files.Write(log.r, " "); Files.Write(log.r, " ");
			i := 0; WHILE name[i] # 0X DO Files.Write(log.r, name[i]); INC(i) END;
			IF typ # "t" THEN Files.Write(log.r, " "); Files.Write(log.r, typ) END;
			Files.Write(log.r, CR);
			Files.Close(log.f)	(* to flush buffers *)
		END	
	END UpdateNameLog;
	
	PROCEDURE RenameOld(name: ARRAY OF CHAR);
		VAR bck: ARRAY 32 OF CHAR;	i, res: INTEGER;
	BEGIN
		i := 0; WHILE (i < 32-5) & (name[i]# 0X) DO bck[i] := name[i]; INC(i) END;
		bck[i] := "."; INC(i); bck[i] := "B"; INC(i); bck[i] := "a"; INC(i); bck[i] := "k"; INC(i); bck[i] := 0X;
		Files.Rename(name, bck, res)
	END RenameOld;
			
	PROCEDURE store(typ: CHAR);
	(* typ specifies the type to store the text: "t": text / "a": ascii / "c": chars *)
		VAR par : Oberon.ParList;	V: Viewers.Viewer;	tF: TextFrames.Frame;
			f: Files.File;	r: Files.Rider; 	S: Texts.Scanner;	R: Texts.Reader;	len: LONGINT;	ch: CHAR;
	BEGIN
		par := Oberon.Par; tF := NIL; S.class := Texts.Inval;
		IF par.frame = par.vwr.dsc THEN	(* command in menu frame *)
			IF par.vwr.dsc.next IS TextFrames.Frame THEN
				tF := par.vwr.dsc.next(TextFrames.Frame); ViewerName(par.vwr, S)
			END
		ELSE
			V := Oberon.MarkedViewer();	(* marked viewer *)
			IF (V.dsc # NIL) & (V.dsc.next IS TextFrames.Frame) THEN	(* test if text is in marked viewer *)
				tF:= V.dsc.next(TextFrames.Frame); 
				OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
				IF S.class = Err THEN S.class := Texts.Inval
				ELSE Texts.Scan(S); 
					IF (S.class = Texts.Char) & (S.c = "*") THEN ViewerName(V, S) END	(* get name of marked viewer *)
				END
			END
		END;
		Texts.WriteString(tW, "ET.Store");
		IF typ = "a" THEN Texts.WriteString(tW, "Ascii") ELSIF typ = "c" THEN Texts.WriteString(tW, "Chars") ELSE typ := "t" END;
		Texts.Write(tW, " "); Texts.Append(Oberon.Log, tW.buf);
		IF tF = NIL THEN Texts.WriteString(tW, " not a text ")
		ELSIF S.class = Texts.Name THEN
			TextFrames.Mark(tF, -1); UnMarkMenu(tF);
			RenameOld(S.s);
			f := Files.New(S.s);
			IF typ = "t" THEN Texts.Store(tF.text, f, 0, len)
			ELSE Files.Set(r, f, 0);
				Texts.OpenReader(R, tF.text, 0); Texts.Read(R, ch);
				WHILE ~ R.eot DO
					Files.Write(r, ch); IF (ch = CR) & (typ = "a") THEN Files.Write(r, LF) END;
					Texts.Read(R, ch)
				END
			END;
			Files.Register(f);
			UpdateNameLog(S.s, typ); Texts.WriteString(tW, S.s);
			TextFrames.Mark(tF, 1)
		ELSE Texts.WriteString(tW, " illegal name ")
		END;
		Texts.WriteLn(tW); Texts.Append(Oberon.Log, tW.buf)
	END store;
	
	PROCEDURE Store*; BEGIN store("t") END Store;
	
	PROCEDURE StoreChar*; BEGIN store("c") END StoreChar;
	
	PROCEDURE StoreAscii*; BEGIN store("a") END StoreAscii;
	
	PROCEDURE Cleartrack(X: INTEGER);
		VAR Y : INTEGER;	V, lV: Viewers.Viewer;	M: Oberon.InputMsg;
	BEGIN
		Oberon.RemoveMarks(X, Display.Bottom, Display.Width, Display.Height);
		Defocus(NIL);
		REPEAT
			V := Viewers.This(X, 0); lV := NIL;	(* get bottom viewer *)
			WHILE V.state > 1 DO	(* if not filler *)
				lV := V; V := Viewers.Next(V)
			END;
			IF lV # NIL  THEN Viewers.Close(lV) END
		UNTIL lV = NIL
	END Cleartrack;
	
	PROCEDURE ClearTrack*; BEGIN Cleartrack(Oberon.UserTrack(Oberon.Par.vwr.X)) END ClearTrack;
	PROCEDURE ClearSysTrack*; BEGIN Cleartrack(Oberon.SystemTrack(Oberon.Par.vwr.X)) END ClearSysTrack;
	
	PROCEDURE ValidX(X: INTEGER): BOOLEAN;
	BEGIN
		RETURN (Display.Left <= X) & (X < Display.Left + Display.Width)
				OR (Display.ColLeft <= X) & (X < Display.ColLeft + Display.Width)
	END ValidX;
	
	PROCEDURE ValidY(Y: INTEGER): BOOLEAN;
	BEGIN
		RETURN (Display.Bottom <= Y) & (Y < Display.Bottom + Display.Height)
	END ValidY;

	PROCEDURE Marker*;
		VAR S: Texts.Scanner;	V : Viewers.Viewer;	cM: Oberon.ControlMsg;
	BEGIN
		ScanPara(S); IF S.class # Texts.Name THEN RETURN END;	(* ### *)
		IF S.s = "set" THEN
			Texts.Scan(S); cM.id := Oberon.mark + 999;
			IF (S.class = Texts.Name) & (S.s = "saved") THEN
				V := Viewers.This(sX + 1, sY - 1);
				IF (V # NIL) & (V.X <= sX) & (sX < V.X + V.W) & (V.Y + V.H = sY) THEN
					cM.id := Oberon.mark; cM.X := V.X + V.W DIV 2; cM.Y := V.Y + V.H DIV 2
				END
			ELSIF (S.class = Texts.Name) & (S.s = "this") THEN
				IF Oberon.Par.vwr # NIL THEN
					cM.id := Oberon.mark; cM.X := Oberon.Par.vwr.X + Oberon.Par.vwr.W DIV 2; 
					cM.Y := Oberon.Par.vwr.Y + Oberon.Par.vwr.H DIV 2
				END
			ELSIF (S.class = Texts.Int) & (S.i >= 0) THEN
				cM.X := SHORT(S.i); Texts.Scan(S);
				IF (S.class = Texts.Int) & (S.i >= 0) THEN
					cM.Y := SHORT(S.i);
					IF ValidX(cM.X) & ValidY(cM.Y) THEN cM.id := Oberon.mark END
				END
			END;
			IF cM.id = Oberon.mark THEN
				V := Viewers.This(cM.X, cM.Y); IF V # NIL THEN V.handle(V, cM) END	(* set marker *)
			END
		ELSIF S.s = "save" THEN
			Texts.Scan(S);
			IF S.class = Texts.Name THEN
				IF S.s = "system" THEN
					Oberon.AllocateSystemViewer(Oberon.SystemTrack(Oberon.Par.vwr.X), sX, sY)
				ELSIF S.s = "user" THEN
					Oberon.AllocateUserViewer(Oberon.UserTrack(Oberon.Par.vwr.X), sX, sY)
				ELSE sX := -1; sY := -1
				END
			END
		END
	END Marker;
	
	PROCEDURE MarkPatPos(tF: TextFrames.Frame; pos: LONGINT);
		VAR l: LONGINT;
	BEGIN	
		RemoveMarks(tF);
		IF (pos < TextFrames.Pos(tF, tF.X, tF.Y + tF.H)) OR (TextFrames.Pos(tF, tF.X + tF.W, tF.Y) < pos) THEN
			l := LinesOf(tF);
			IF l > 4 THEN l := LinesUp(tF.text, pos, 4) ELSE l := LinesUp(tF.text, pos, 1) END;
			TextFrames.Show(tF, l)
		END;
		Defocus(tF);
		TextFrames.SetCaret(tF, pos);
		TextFrames.SetSelection(tF, pos - sPatLen, pos); lTime := tF.time
	END MarkPatPos;

	PROCEDURE Search*;
		VAR tF: TextFrames.Frame;	V: Viewers.Viewer;
			R: Texts.Reader;	text: Texts.Text;
			pos, beg, end, time: LONGINT; 	i, j, d: INTEGER;
	BEGIN
		IF (Oberon.Par.vwr # NIL) & (Oberon.Par.frame = Oberon.Par.vwr.dsc) THEN V := Oberon.Par.vwr
		ELSE V := FocusViewer()
		END;
		IF (V.dsc = NIL) OR ~ (V.dsc.next IS TextFrames.Frame) THEN RETURN END;	(* ### *)
		tF := V.dsc.next(TextFrames.Frame);
		text := NIL; Oberon.GetSelection(text, beg, end, time);
		IF (text # NIL) & (time > lTime) THEN	(* set search pattern *)
			Texts.OpenReader(R, text, beg);
			i := 0; pos := beg;
			REPEAT Texts.Read(R, sPat[i]); INC(i); INC(pos) UNTIL (i = MaxPatLen) OR (pos = end);
			sPatLen := i; CalcDispVec(time)	(* calculate displacement vector *)
		END;
		IF tF.car > 0 THEN pos := tF.carloc.pos ELSE pos := 0 END;
		IF SPatFound(tF, tF.text, pos) THEN MarkPatPos(tF, pos)
		ELSE TextFrames.RemoveSelection(tF); TextFrames.RemoveCaret(tF)
		END
	END Search;
	
	PROCEDURE SearchDiff*;
		VAR F1, F2: TextFrames.Frame; pos1, pos2: LONGINT; R1, R2: Texts.Reader; ch1, ch2: CHAR;
	BEGIN
		GetSelFrame(F1);
		IF F1 # NIL THEN pos1 := F1.selbeg.pos; RemoveMarks(F1) END;
		GetSelFrame(F2);
		IF F2 # NIL THEN pos2 := F2.selbeg.pos; RemoveMarks(F2) END;
		IF (F1 # NIL) & (F2 # NIL) THEN
			TextFrames.Mark(F1, -1); TextFrames.Mark(F2, -1);
			Texts.OpenReader(R1, F1.text, pos1); 
			Texts.OpenReader(R2, F2.text, pos2); 
			REPEAT
				REPEAT
					Texts.Read(R1, ch1); INC(pos1)
				UNTIL (ch1 # 20X) & (ch1 # 0DX) & (ch1 # 09X);
				REPEAT
					Texts.Read(R2, ch2); INC(pos2)
				UNTIL (ch2 # 20X) & (ch2 # 0DX) & (ch2 # 09X)
			UNTIL (ch1 # ch2) OR (ch1 = 0X);
			DEC(pos1); ShowPos(F1, pos1); TextFrames.SetSelection(F1, pos1, pos1 + 1);
			DEC(pos2); ShowPos(F2, pos2); TextFrames.SetSelection(F2, pos2, pos2 + 1);
			TextFrames.Mark(F1, 1); TextFrames.Mark(F2, 1)
		END
	END SearchDiff;

	PROCEDURE replace(): BOOLEAN;
		VAR tF: TextFrames.Frame;	V: Viewers.Viewer;
			R: Texts.Reader;	tBuf: Texts.Buffer;	text: Texts.Text;
			pos, beg, end, time, p, len: LONGINT; 	i: INTEGER;	ch: CHAR;	T: Texts.Text;
	BEGIN
		V := FocusViewer();
		IF (V.dsc = NIL) OR ~ (V.dsc.next IS TextFrames.Frame) THEN RETURN FALSE END;	(* ### *)
		tF := V.dsc.next(TextFrames.Frame);
		T := tF.text;
		text := NIL; Oberon.GetSelection(text, beg, end, time);
		IF (text # NIL) & (time > lTime) THEN	(* set replace buffer *)
			lTime := time; NEW(rBuf); Texts.OpenBuf(rBuf); Texts.Save(text, beg, end, rBuf)
		END;
		IF (tF.car <= 0) OR ~ (sPatLen > 0) OR (rBuf = NIL) THEN RETURN FALSE END;	(* ### *)
		pos := tF.carloc.pos; p := pos - sPatLen;
		IF p < 0 THEN RETURN FALSE END;	(* ### *)
		Texts.OpenReader(R, T, p); Texts.Read(R, ch); i := 0;
		WHILE (ch = sPat[i]) & (i < sPatLen) DO Texts.Read(R, ch); INC(i) END;
		IF i = sPatLen THEN
			Texts.Delete(T, p, pos); pos := p;
			NEW(tBuf); Texts.OpenBuf(tBuf);
			Texts.Copy(rBuf, tBuf); len := tBuf.len;
			Texts.Insert(T, pos, tBuf); pos := pos + len
		END;
		IF SPatFound(tF, tF.text, pos) THEN MarkPatPos(tF, pos); RETURN TRUE
		ELSE TextFrames.RemoveSelection(tF); TextFrames.RemoveCaret(tF); RETURN FALSE
		END
	END replace;
	
	PROCEDURE Replace*;
	BEGIN
		IF replace() THEN END
	END Replace;
	
	PROCEDURE ReplaceAll*;
	BEGIN
		WHILE replace() DO END
	END ReplaceAll;

	PROCEDURE Locate*;
		VAR tF: TextFrames.Frame;	V: Viewers.Viewer;
			text: Texts.Text;	S: Texts.Scanner;	beg, end, time: LONGINT;
	BEGIN
		V := Oberon.MarkedViewer();
		IF (V.dsc # NIL) & (V.dsc.next IS TextFrames.Frame) THEN
			tF := V.dsc.next(TextFrames.Frame);
			text := NIL; Oberon.GetSelection(text, beg, end, time);
			IF (text # NIL) & (time > 0) THEN
				OpenScanner(S, text, beg);
				REPEAT Texts.Scan(S) UNTIL (S.class >= Texts.Int);	(*skip names*)
				IF S.class = Texts.Int THEN
					RemoveMarks(tF);
					ShowPos(tF, S.i);
					SetFocus(V);
					TextFrames.SetCaret(tF, S.i)
				END
			END
		END
	END Locate;

	PROCEDURE Error*;
		VAR text: Texts.Text;	S: Texts.Scanner;	V: Viewers.Viewer;
			X, Y, i: INTEGER;	pos, beg, end, time: LONGINT;
	BEGIN
		text := NIL; Oberon.GetSelection(text, beg, end, time);
		IF (text # NIL) & (time > 0) THEN
			OpenScanner(S, text, beg);
			Texts.Scan(S);
			REPEAT Texts.Scan(S) UNTIL ((S.class = Texts.Name) & (S.s = "err")) OR (S.class > Texts.Int);
			IF (S.class = Texts.Name) & (S.s = "err") THEN
				text := TextFrames.Text(ErrorsText);
				IF text.len > 0 THEN
					i := 0;
					WHILE S.nextCh = " " DO Texts.Read(S, S.nextCh) END;
					WHILE ("0" <= S.nextCh) & (S.nextCh <= "9") DO
						sPat[i] := S.nextCh; INC(i); Texts.Read(S, S.nextCh)
					END;
					sPat[i] := TAB; INC(i);
					sPatLen := i; pos := 0; CalcDispVec(Oberon.Time());
					IF SPatFound(NIL, text, pos) THEN
						Oberon.AllocateUserViewer(Oberon.UserTrack(Oberon.Par.vwr.X), X, Y);
						V := OpenViewer(text, ErrorsText, LinesUp(text, pos, 4), X, Y, 0);
						IF pos > 0 THEN
							SetFocus(V);
							TextFrames.SetCaret(V.dsc.next(TextFrames.Frame), pos)
						END
					END
				END
			END
		END
	END Error;

	PROCEDURE MenuExchange(F: Frame; vwrName, menuStr: ARRAY OF CHAR);
		VAR mF: TextFrames.Frame;	menuH: INTEGER;
	BEGIN
		IF F IS TextFrames.Frame THEN
			mF := F(TextFrames.Frame); SetDefFont(tW);
			Texts.WriteString(tW, vwrName); Texts.WriteString(tW, " | "); Texts.WriteString(tW, menuStr);
			IF mF.text.len > 0 THEN Texts.Delete(mF.text, 0, mF.text.len) END;	(* delete old menu *)
			Texts.Append(mF.text, tW.buf)	(* insert new menu *)
		END
	END MenuExchange;			
			
	PROCEDURE Init*;
		VAR V: Viewers.Viewer;	S: Texts.Scanner;	typ: INTEGER;	h1,h2 : Handler;
	BEGIN
		ScanPara(S); V := NIL;
		IF (S.class = Texts.Name) & (S.s = "saved") THEN
			V := Viewers.This(sX + 1, sY - 1);
			IF (V # NIL) & ((sX < V.X) OR (V.X + V.W <= sX) OR (V.Y + V.H # sY)) THEN V := NIL END
		ELSIF ((S.class = Texts.Name) & (S.s = "marked")) OR ((S.class = Texts.Char) & (S.c = "*")) THEN
			V := Viewers.This(Oberon.Pointer.X + 1, Oberon.Pointer.Y - 1)
		END;
		IF (V # NIL) & (V.dsc # NIL) & (V.dsc.next # NIL) THEN
			h1 := V.dsc.next.handle; h2 := TextFrames.Handle; 
			IF  h1 = h2 THEN
				V.dsc.next.handle := Handle;
				ViewerName(V, S); IF S.class # Texts.Name THEN S.s := "ET.Init" END;
				IF V.X = Oberon.SystemTrack(V.X) THEN
					IF S.s = "System.Log" THEN typ := 2 ELSE typ := 1 END
				ELSE typ := 0
				END;
				MenuExchange(V.dsc, S.s, mStr[typ])
			END
		END
	END Init;
	
	PROCEDURE ExchangeMenu*;
		VAR V: Viewers.Viewer;	S: Texts.Scanner;	menu: MenuStr;
	BEGIN
		ScanPara(S); IF S.class # Texts.Name THEN RETURN END;	(* ### *)
		menu := "";
		IF S.s = "marked" THEN
			V := Oberon.MarkedViewer(); ScanQuote(S, menu);
		ELSIF S.s = "saved" THEN
			V := Viewers.This(sX + 1, sY - 1);
			IF (V # NIL) & (V.X <= sX) & (sX < V.X + V.W) & (V.Y + V.H = sY) THEN ScanQuote(S, menu) END
		END;
		IF (menu # "") & (V.dsc # NIL) THEN
			ViewerName(V, S); IF S.class # Texts.Name THEN S.s := "ET" END;
			MenuExchange(V.dsc, S.s, menu)
		END
	END ExchangeMenu;
	
	PROCEDURE Delete*;
		VAR tF: TextFrames.Frame;	text: Texts.Text;	beg,end, time: LONGINT;
	BEGIN
		GetSelFrame(tF);
		IF tF # NIL THEN
			GetSelData(tF, text, beg, end, time);
			RemoveMarks(tF);
			Texts.Delete(text, beg, end);
			Defocus(tF);
			TextFrames.SetCaret(tF, beg)
		END
	END Delete;

	PROCEDURE Move*;
		VAR T: Texts.Text; tF: TextFrames.Frame;	V: Viewers.Viewer;
			beg, end, time, carloc : LONGINT; 	B: Texts.Buffer;
	BEGIN
		Oberon.GetSelection(T, beg, end, time);
		IF time > 0 THEN
			V := FocusViewer();
			IF V.dsc.next IS TextFrames.Frame THEN
				tF := V.dsc.next(TextFrames.Frame);
				IF tF.text = T THEN
					carloc := tF.carloc.pos;
					IF (carloc > end) OR (carloc < beg) THEN
						RemoveMarks(tF); 
						IF carloc > end THEN carloc := carloc - (end-beg) END;
						Texts.Delete(T, beg, end);
						NEW(B); Texts.OpenBuf(B);
						Texts.Recall(B);
						Texts.Insert(T, carloc, B);
						TextFrames.SetCaret(tF, carloc + end-beg)
					END
				END
			END
		END 
	END Move;
	
	PROCEDURE LogOpen(X, Y: INTEGER);
		VAR V: Viewers.Viewer;
	BEGIN
		V := OpenViewer(Oberon.Log, "System.Log", 0, X, Y, 2);
	 END LogOpen;
	
	PROCEDURE OpenLog*;
		VAR X, Y: INTEGER;
	BEGIN
		Oberon.AllocateSystemViewer(Oberon.SystemTrack(Oberon.Par.vwr.X), X, Y);
		LogOpen(X, Y)
	END OpenLog;
	
	PROCEDURE Clear*;
		VAR V: Viewers.Viewer;		tF: TextFrames.Frame;
	BEGIN
		V := Oberon.Par.vwr;
		IF V.dsc # Oberon.Par.frame THEN V := Oberon.MarkedViewer() END;	(* if command not in menu *)
		IF (V.dsc # NIL) & (V.dsc.next IS TextFrames.Frame) THEN
			tF := V.dsc.next(TextFrames.Frame);
			Texts.Delete(tF.text, 0, tF.text.len)
		END
	END Clear;

	PROCEDURE Recall*;
		VAR tF: TextFrames.Frame;	V: Viewers.Viewer;
			buf: Texts.Buffer;	pos: LONGINT;
	BEGIN
		V := FocusViewer();
		IF (V.dsc # NIL) & (V.dsc.next IS TextFrames.Frame) THEN
			tF := V.dsc.next(TextFrames.Frame);
			IF tF.car > 0 THEN
				NEW(buf); Texts.OpenBuf(buf);
				Texts.Recall(buf); pos := tF.carloc.pos + buf.len;
				Texts.Insert(tF.text, tF.carloc.pos, buf);
				TextFrames.SetCaret(tF, pos)
			END
		END
	END Recall;
	
	PROCEDURE Font*;
		VAR S: Texts.Scanner;	text: Texts.Text;	ext: ARRAY 12 OF CHAR;
			beg, end, time: LONGINT;	i, j: INTEGER;
	BEGIN
		ScanPara(S); IF S.class # Texts.Name THEN RETURN END;	(* ### *)
		i := 0; WHILE (S.s[i] # 0X) & (S.s[i] # ".") DO INC(i) END;
		IF S.s[i] = 0X THEN	(* add font extension *)
			ext := ".Scn.Fnt"; j := 0;
			WHILE ext[j] # 0X DO S.s[i] := ext[j]; INC(i); INC(j) END;
			S.s[i] := 0X
		END;
		text := NIL; Oberon.GetSelection(text, beg, end, time);
		IF (text # NIL) & (time > 0) THEN
			Texts.ChangeLooks(text, beg, end, {Fnt}, Fonts.This(S.s), 0, 0)
		END
	END Font;

	PROCEDURE Color*;
		VAR S: Texts.Scanner;	text: Texts.Text;
			beg, end, time: LONGINT;	col: SHORTINT;
	BEGIN
		ScanPara(S); IF S.class # Texts.Int THEN RETURN END;	(* ### *)
		col := SHORT(SHORT(S.i));
		IF (0 <= col) & (col <= 15) THEN
			text := NIL; Oberon.GetSelection(text, beg, end, time);
			IF (text # NIL) & (time > 0) THEN
				Texts.ChangeLooks(text, beg, end, {Colr}, NIL, col, 0)
			END
		END
    END Color;
	
	PROCEDURE Do*;
		VAR S: Texts.Scanner;	text: Texts.Text;	pos: LONGINT;	res: INTEGER;
		
		PROCEDURE NextLine(text: Texts.Text; pos: LONGINT): LONGINT;
			VAR tR: Texts.Reader;	ch: CHAR;
		BEGIN
			IF pos < text.len THEN 
				Texts.OpenReader(tR, text, pos); Texts.Read(tR, ch);
				WHILE ~ tR.eot & (ch # CR) DO Texts.Read(tR, ch) END;
				IF tR.eot THEN RETURN -1 ELSE RETURN Texts.Pos(tR)  END
			ELSE RETURN -1
			END
		END NextLine;
	
	BEGIN
		ScanPara(S); IF S.class # Texts.Name THEN RETURN END;	(* ### *)
		text := TextFrames.Text(S.s); IF (text = NIL) OR (text.len = 0) THEN RETURN END;	(* ### *)
		Texts.OpenScanner(S, text, 0); Texts.Scan(S);
		WHILE S.class = Texts.Name DO
			pos := Texts.Pos(S) - 1; 
			Oberon.Par.text := text; Oberon.Par.pos := pos;
			Oberon.Call(S.s, Oberon.Par, FALSE, res);
			pos := NextLine(text, pos);
			IF pos > 0 THEN Texts.OpenScanner(S, text, pos); Texts.Scan(S)
			ELSE S.class :=Texts.Inval
			END
		END
	END Do;
	
	PROCEDURE Process(text: Texts.Text; beg, end: LONGINT; s: ARRAY OF CHAR);
		VAR S: Texts.Scanner;	pos: LONGINT;	i: INTEGER;
	BEGIN
		i := 0; WHILE (s[i] # 0X) & (s[i] # "*") DO INC(i) END;
		IF s[i] = 0X THEN	
			Texts.WriteString(tW, s); Texts.WriteLn(tW);
			Texts.Append(para, tW.buf)
		ELSIF beg < end THEN
			OpenScanner(S, text, beg); pos := beg;
			WHILE pos < end DO
				Texts.Scan(S);
				IF S.class = Texts.Name THEN
					i := 0;
					WHILE s[i] # 0X DO
						IF s[i] = "*" THEN Texts.WriteString(tW, S.s)
						ELSE Texts.Write(tW, s[i])
						END;
						INC(i)
					END;
					Texts.WriteLn(tW)
				END;
				WHILE (S.nextCh = CR) OR (S.nextCh = SPACE) OR (S.nextCh = TAB) DO Texts.Read(S, S.nextCh) END;
				pos := Texts.Pos(S) - 1	(* one character look ahead *)
			END;
			IF tW.buf.len > 0 THEN Texts.Append(para, tW.buf) END
		END
	END Process;	
	
	PROCEDURE Call*;
	(* expected parameters: M.P  {Processor} *)
	(* Processor: specified as string; "*" -> specifies name of list *)
		VAR S: Texts.Scanner;	text: Texts.Text;	beg, end, time: LONGINT;
			cmd: ARRAY 32 OF CHAR;	res: INTEGER;
	BEGIN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF S.class # Texts.Name THEN RETURN END;	(* ### *)
		COPY(S.s, cmd);
		IF para.len > 0 THEN Texts.Delete(para, 0, para.len) END;	(* clear parameter text *)
		text := NIL; time := 0; Oberon.GetSelection(text, beg, end, time);
		IF (text = NIL) OR (time <= 0) THEN beg := end END;
		Texts.Scan(S);
		WHILE S.class = Texts.String DO
			Process(text, beg, end, S.s);
			Texts.Scan(S)
		END;
		Oberon.Par.text := para; Oberon.Par.pos := 0;
		Oberon.Call(cmd, Oberon.Par, FALSE, res)
	END Call;
	
	PROCEDURE ListNames*;
		VAR S, S0: Texts.Scanner;	text: Texts.Text;	beg, end, time: LONGINT;
			V: Viewers.Viewer;	X, Y: INTEGER;
	BEGIN
		ScanPara(S); IF S.class # Texts.Name THEN RETURN END;	(* ### *)
		text := TextFrames.Text("");
		Texts.WriteString(tW, S.s); Texts.WriteLn(tW);
		Texts.WriteString(tW, "~ "); Texts.Append(text, tW.buf);
		Texts.Scan(S);
		WHILE S.class = Texts.Name DO
			OpenScanner(S0, text, 0); Texts.Scan(S0);
			WHILE (S0.class = Texts.Name) & (S0.s # S.s) DO Texts.Scan(S0) END;
			IF S0.class # Texts.Name THEN
				Texts.WriteString(tW, S.s); Texts.WriteLn(tW);
				Texts.Insert(text, 0, tW.buf)
			END;
			Texts.Scan(S)
		END;
		Oberon.AllocateUserViewer(Oberon.UserTrack(Oberon.Par.vwr.X), X, Y);
		V := OpenViewer(text, "ET.ListNames", 0, X, Y, 0)
	END ListNames;
	
	PROCEDURE Para*;
		VAR V: Viewers.Viewer;	X, Y: INTEGER;
	BEGIN
		Oberon.AllocateUserViewer(Oberon.UserTrack(Oberon.Par.vwr.X), X, Y);
		V := OpenViewer(para, "ET.Para", 0, X, Y, 0)
	END Para;
	
	PROCEDURE Remind*;
	(** reads the name after the command and *)
	(** displays the text in the oberon log *)
		VAR text: Texts.Text;	R: Texts.Reader;	S: Texts.Scanner;	ch: CHAR;
	BEGIN
		ScanPara(S); IF S.class # Texts.Name THEN RETURN END;	(* ### *)
		text := TextFrames.Text(S.s);
		IF text.len = 0 THEN RETURN END;	(* ### *)
		Texts.OpenReader(R, text, 0); Texts.Read(R, ch);
		WHILE ~ R.eot DO
			Texts.Write(tW, ch); Texts.Read(R, ch)
		END;
		Texts.WriteLn(tW); Texts.Append(Oberon.Log, tW.buf);
		Texts.WriteString(tW, "ET.Open "); Texts.WriteString(tW, S.s);
		Texts.WriteLn(tW); Texts.Append(Oberon.Log, tW.buf)
	END Remind;
	
	PROCEDURE NameLog*;
		VAR S: Texts.Scanner;
	BEGIN
		ScanPara(S); IF S.class # Texts.Name THEN RETURN END;	(* ### *)
		IF S.s = "on" THEN
			log.f := Files.Old(LogFile);
			IF log.f = NIL THEN
				log.f := Files.New(LogFile); Files.Register(log.f)
			END;
			Files.Set(log.r, log.f, Files.Length(log.f));
			Texts.WriteString(tW, "ET.NameLog on"); Texts.WriteLn(tW);
			Texts.Append(Oberon.Log, tW.buf)
		ELSIF S.s = "off" THEN
			log.f := NIL; Files.Set(log.r, log.f, 0);
			Texts.WriteString(tW, "ET.NameLog off"); Texts.WriteLn(tW);
			Texts.Append(Oberon.Log, tW.buf)
		END
	END NameLog;
	
	PROCEDURE Filter*;
		VAR S: Texts.Scanner;
	BEGIN
		ScanPara(S); IF S.class # Texts.Name THEN RETURN END;	(* ### *)
		IF S.s = "on" THEN filter := TRUE;
			Texts.WriteString(tW, "ET.Filter on"); Texts.WriteLn(tW);
			Texts.Append(Oberon.Log, tW.buf)
		ELSIF S.s = "off" THEN filter := FALSE;
			Texts.WriteString(tW, "ET.Filter off"); Texts.WriteLn(tW);
			Texts.Append(Oberon.Log, tW.buf)
		END
	END Filter;
	
	PROCEDURE Popup*;
		VAR S: Texts.Scanner;
	BEGIN
		ScanPara(S); IF S.class # Texts.Name THEN RETURN END;	(* ### *)
		IF S.s = "on" THEN
			menuAvail := TRUE;
			IF Files.Old(PopupText) = NIL THEN popup := NIL
			ELSE popup := TextFrames.Text("");
				Texts.WriteString(tW, PopupText); Texts.Append(popup, tW.buf)
			END;	(* standard popup menu *)
			Texts.WriteString(tW, "ET.Popup on"); Texts.WriteLn(tW);
			Texts.Append(Oberon.Log, tW.buf)
		ELSIF S.s = "off" THEN
			menuAvail := FALSE; popup := NIL;
			Texts.WriteString(tW, "ET.Popup off"); Texts.WriteLn(tW);
			Texts.Append(Oberon.Log, tW.buf)
		END
	END Popup;
	
	PROCEDURE SetMenu*;
	(* initializes menu texts regarding user defined menus *)
		VAR text: Texts.Text;	S: Texts.Scanner;
	BEGIN
		ScanPara(S); IF S.class # Texts.Name THEN RETURN END;	(* ### *)
		IF S.s = "default" THEN
			mStr[0] := UserMenu; mStr[1] := SysMenu; mStr[2] := LogMenu;
			mStr[3] := UserAscii; mStr[4] := SysAscii
		ELSIF S.s = "user" THEN ScanQuote(S, mStr[0])
		ELSIF S.s = "system" THEN ScanQuote(S, mStr[1])
		ELSIF S.s = "log" THEN ScanQuote(S, mStr[2])
		ELSIF S.s = "userascii" THEN ScanQuote(S, mStr[3])
		ELSIF S.s = "systemascii" THEN ScanQuote(S, mStr[4])
		END
	END SetMenu;
	
	PROCEDURE StrSearch(pat: ARRAY OF CHAR;  VAR str: ARRAY OF CHAR;  VAR pos: LONGINT);
		VAR i: LONGINT; found: BOOLEAN;
	BEGIN
		found := FALSE;
		WHILE (str[pos] # 0X) & ~found DO
			i := 0; WHILE (pat[i] # 0X) & (pat[i] = str[pos]) DO INC(i); INC(pos) END;
			DEC(pos, i);
			IF pat[i] = 0X THEN found := TRUE
			ELSE INC(pos)
			END
		END;
		IF ~found THEN pos := -1 END
	END StrSearch;
	
	PROCEDURE StrDelete(VAR str: ARRAY OF CHAR;  pos, len: LONGINT);
	VAR i, n: LONGINT;
	BEGIN
		i := pos+len;  n := 0;  WHILE str[n] # 0X DO INC(n) END;
		IF i < n THEN
			WHILE str[i] # 0X DO str[pos] := str[i]; INC(pos); INC(i) END
		END;
		str[pos] := 0X
	END StrDelete;
	
	PROCEDURE ShowText(title: ARRAY OF CHAR; T: Texts.Text; W, H: INTEGER);
		VAR X, Y: INTEGER; V: Viewers.Viewer; pos: LONGINT;
	BEGIN
		IF T = Oberon.Log THEN
			Oberon.AllocateSystemViewer(Oberon.SystemTrack(Oberon.Par.vwr.X), X, Y);
			LogOpen(X, Y)
		ELSE
			X := 0; WHILE (title[X] # 0X) & (title[X] # "|") DO INC(X) END;
			IF title[X] = "|" THEN
				title[X] := 0X;  INC(X);  Y := 0;
				WHILE title[X] # 0X DO mStr[5][Y] := title[X];  INC(X);  INC(Y) END;
				mStr[5][Y] := 0X;  pos := 0;
				LOOP
					StrSearch("Edit.", mStr[5], pos);
					IF pos = -1 THEN EXIT END;
					StrDelete(mStr[5], pos+1, 2);
					mStr[5][pos+1] := "T"
				END
			ELSE
				mStr[5] := "System.Close System.Copy System.Grow ET.Search ET.Store"
			END;
			IF W > Display.Width DIV 8 * 3 THEN
				Oberon.AllocateUserViewer(Oberon.SystemTrack(Oberon.Par.vwr.X), X, Y)
			ELSE
				Oberon.AllocateSystemViewer(Oberon.SystemTrack(Oberon.Par.vwr.X), X, Y)
			END;
			V := OpenViewer(T, title, 0, X, Y, 5)
		END
	END ShowText;
	
	PROCEDURE ReplaceSystemEditor*;
	BEGIN
		Oberon.OpenText := ShowText
	END ReplaceSystemEditor;
	
BEGIN
	Texts.OpenWriter(tW);
	Texts.OpenWriter(WL);
	log.f := NIL;	(* name log off *)
	filter := FALSE;	(* filter for compiler warnings off *)
	menuAvail := TRUE;	(* popup menus available *)
	IF Files.Old(PopupText) = NIL THEN popup := NIL
	ELSE popup := TextFrames.Text("");
		Texts.WriteString(tW, PopupText); Texts.Append(popup, tW.buf)
	END;
	inFnt := NIL; inColor := FG;
	para := TextFrames.Text("");
	ii := 0; WHILE ii < MaxPatLen DO sPat[ii] := 0X; INC(ii) END;	(* search and replace *)
	lTime := -1; sPatLen := 0; rBuf := NIL;
	mStr[0] := UserMenu; mStr[1] := SysMenu; mStr[2] := LogMenu;	(* set standard menus *)
	mStr[3] := UserAscii; mStr[4] := SysAscii;
	sX := -1; sY := -1
END ET.
