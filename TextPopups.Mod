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

(** 
 	TextPopups
	
	This module displays simple popup menus in TextDocs when clicking outside the text.
	The contents of the menus can be edited and are stored in the file "TextPopups.Text"
	
	This is an example of a menu description:
	
	[Mod]	<= applies for files with suffix .Mod
	Compiler.Compile *
	Compiler.Compile */s
	Compiler.Compile */f	<= commands that can be executed
	Decoder.Decode ^
	Analyzer.Analyze *
	--------------------
	<5 Recent Files>	<= include a list with the 5 recent files, you can also replace 5 by any other 	--------------------		number. These files can be opened directly by selecting the appropriate menu item
	<Procedures>	<= include a list of all procedures declared in the text file
			You can jump to the corresponding text position by selecting a menu item

	<Types>	<= include a list of all types declared in the text file
			You can jump to the corresponding text position by selecting a menu item
	[Text]	<= applies for files with suffix .Text
	TextDocs.SearchDiff /w
	--------------------
	<5 Recent Files>
	
	
	[Tool]	<= applies for files with suffix .Tool
	<5 Recent Files>
	
	...
*)

MODULE TextPopups;	(** portable *)	(* tk 6.12.95 *)

	(* some marked compiler calls are not portable - but can easily be adopted for different implementations *)

	IMPORT
		Modules, Display, Objects, OPM, OPS, ListRiders, Links, Attributes, Documents, Desktops,
		Texts, Oberon, Effects, Fonts, Display3, Gadgets, TextDocs, TextGadgets0, TextGadgets, 
		Input, Views, Strings;

	CONST
		times = 1; and = 5; plus=6; minus=7; eql = 9; arrow = 17; colon=20; rparen=22; lparen=30; 
		ident = 40; semicolon = 41; end = 43; record = 57; begin = 59; const = 60; type = 61; var = 62;
		procedure = 63; eof = 67;
		CR = 0DX;	TAB = 09X;	SPACE = " ";	LF = 0AX;	
		MaxHistory = 20; MaxHeight = 250;
		PopupFileName = "TextPopups.Text";
		
	TYPE
		(* generic menu item *)
		MenuItem = POINTER TO MenuItemDesc;
		MenuItemDesc = RECORD	val: ARRAY 128 OF CHAR; link: MenuItem	END;

		(* oberon command *)
		CmdMenuItem = POINTER TO CmdMenuItemDesc;
		CmdMenuItemDesc = RECORD	(MenuItemDesc)	END;
		
		(* procedure name marker *)
		PMarkerMenuItem = POINTER TO PMarkerMenuItemDesc;
		PMarkerMenuItemDesc = RECORD	(MenuItemDesc) pos: LONGINT	END;

		(* type name marker *)
		TMarkerMenuItem = POINTER TO TMarkerMenuItemDesc;
		TMarkerMenuItemDesc = RECORD	(MenuItemDesc) pos: LONGINT	END;

		(* procedure name marker *)
		FileMenuItem = POINTER TO FileMenuItemDesc;
		FileMenuItemDesc = RECORD	(MenuItemDesc)	END;
		
		(* list of recently opened files *)
		FileHistory = POINTER TO FileHistoryDesc;
		FileHistoryDesc = RECORD	filename: ARRAY 128 OF CHAR; link: FileHistory	END;

	VAR 
		W: Texts.Writer; nofLines, width: INTEGER; 
		itemList, lastItem: MenuItem; doItem: MenuItem; called: BOOLEAN;
		fileHistory: FileHistory; 
		
(* execute a command *)
		
	PROCEDURE Call(F: TextGadgets.Frame; T: Texts.Text; x, y: INTEGER);
		VAR text: Texts.Text; R: Texts.Reader; res: INTEGER; cmd: ARRAY 64 OF CHAR;
			d: Documents.Document;
	BEGIN
		IF doItem=NIL THEN RETURN END;
		IF doItem IS PMarkerMenuItem THEN
			WITH doItem: PMarkerMenuItem DO	
				TextDocs.SetCaret(F, T, doItem.pos)	
			END
		ELSIF doItem IS TMarkerMenuItem THEN
			WITH doItem: TMarkerMenuItem DO	
				TextDocs.SetCaret(F, T, doItem.pos)	
			END
		ELSIF doItem IS CmdMenuItem THEN
			WITH doItem: CmdMenuItem DO
				NEW(text); Texts.Open(text, ""); Texts.WriteString(W, doItem.val);
				Texts.WriteLn(W); Texts.Append(text, W.buf);
				Texts.OpenReader(R, text, 0); 
				res:=0; REPEAT Texts.Read(R, cmd[res]); INC(res) UNTIL cmd[res-1]<=" ";
				cmd[res-1]:=0X;
				Oberon.FadeCursor(Oberon.Pointer);
				Oberon.Pointer.X:=x; Oberon.Pointer.Y:=y;
				Oberon.Par.text:=text; Oberon.Par.pos:=Texts.Pos(R)-1;
				Oberon.Call(cmd, Oberon.Par, FALSE, res)
			END
		ELSIF doItem IS FileMenuItem THEN
			WITH doItem: FileMenuItem DO
				d:=Documents.Open(doItem.val); Desktops.ShowDoc(d);
			END
		END
	END Call;	
	
	PROCEDURE Do*;
		VAR S: Texts.Scanner; p: MenuItem; i: INTEGER;
	BEGIN	called:=TRUE;
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF (S.class=Texts.String) OR (S.class=Texts.Name) THEN 
			p:=itemList.link; 
			LOOP
				IF p=NIL THEN EXIT END;
				i:=0; WHILE (S.s[i]#0X) & (p.val[i]#0X) & (p.val[i]=S.s[i]) DO INC(i) END;
				IF  (p.val[i]="^") & (S.s[i]#"*") OR (p.val[i]=S.s[i]) THEN EXIT ELSE p:=p.link END;
			END;
			doItem:=p;
		ELSE doItem:=NIL END
	END Do;
	
(* build item list *)
	PROCEDURE ExtractProcTypeNames(T: Texts.Text; VAR lastProc, lastType: MenuItem);
		CONST	rec = 0; proc = 1; mod = 2;
		VAR R: Texts.Reader; isType, init: BOOLEAN; sym, prevsym: SHORTINT;
			Stack: ARRAY 16 OF SHORTINT; ST, i: LONGINT;
			Context, name: ARRAY 128 OF CHAR;startP, startT, q: MenuItem; p: PMarkerMenuItem; t: TMarkerMenuItem;
	BEGIN
		Texts.OpenReader(R, T, 0);
		OPM.Init({}, R, Oberon.Log(*Null*)); OPS.Init; startP := lastProc; startT := lastType; isType := FALSE;
		ST := 0; Stack[ST] := mod; Context := ""; OPS.Get(sym);
		REPEAT
			IF sym = type THEN	isType := TRUE
			ELSIF (sym = ident) & isType THEN
				COPY(OPS.name, name); i := OPM.curpos-1;
				OPS.Get(sym);
				IF sym = times THEN OPS.Get(sym) END;
				IF (sym =  eql) THEN
					NEW(t); COPY(Context, t.val); Strings.Append(t.val, name); t.pos := i;
					q := startT; WHILE (q.link # NIL) & (q.link.val < t.val) DO q := q.link END;
					IF q.link = NIL THEN lastType := t END; t.link := q.link; q.link := t;
					OPS.Get(sym);
					IF sym=procedure THEN
						OPS.Get(sym);
						IF sym = lparen THEN
							WHILE (sym#rparen)&(sym#eof) DO OPS.Get(sym) END
						END
					END
				END
			ELSIF (sym = const) OR (sym = var) OR (sym = begin) THEN
				isType := FALSE
			ELSIF sym = record THEN
				INC(ST); Stack[ST] := rec; Strings.Append(Context, name); Strings.AppendCh(Context, ".");
				isType := FALSE
			ELSIF (sym = procedure) & ((prevsym # colon) & (prevsym # eql)) THEN	(*procdecl*)
				OPS.Get(sym);
				IF sym # arrow THEN	(*skip forw*)
					IF sym = lparen THEN	(*O2-method*)
						OPS.Get(sym);
						IF sym = var THEN OPS.Get(sym) END;
						IF sym = ident THEN OPS.Get(sym);
							OPS.Get(sym);	(*colon*)
							IF sym = ident THEN
								COPY(OPS.name, Context); Strings.AppendCh(Context, ".");
								OPS.Get(sym)
							END
						END
					END;
					init := sym = and;
					IF (sym=and) OR (sym=minus) OR (sym=plus) OR (sym=times) THEN OPS.Get(sym) END;	(*skip &, -, ... *)
					IF sym = ident THEN
						COPY(OPS.name, name);
						NEW(p); COPY(Context, p.val); Strings.Append(p.val, name); p.pos := OPM.curpos-1;
						q := startP; WHILE (q.link # NIL) & (q.link.val < p.val) DO q := q.link END;
						IF q.link = NIL THEN lastProc := p END; p.link := q.link; q.link := p;
						INC(ST); Stack[ST] := proc; Strings.Append(Context, name); Strings.AppendCh(Context, ".");
						isType := FALSE
					END
				END
			ELSIF (Stack[ST] = rec)&(sym = end) OR (Stack[ST] = proc)&(prevsym=end)&(sym=ident) THEN
				isType := (Stack[ST] = rec)OR(Stack[ST-1] = rec);
				DEC(ST);
				i := Strings.Length(Context)-2;
				WHILE (i>0) & (Context[i]#".") DO DEC(i) END;
				IF i <= 0 THEN Context[0] := 0X ELSE Context[i+1] := 0X END;
			END;
			prevsym := sym; OPS.Get(sym);
		UNTIL sym = eof;
		OPM.Close;  OPS.Init
	END ExtractProcTypeNames;
	
	PROCEDURE ExtractHistory(nof: INTEGER);
		VAR h: FileHistory; q: FileMenuItem;
	BEGIN
		h:=fileHistory; WHILE (h#NIL) & (nof>0) DO
			NEW(q); COPY(h.filename, q.val); lastItem.link:=q; lastItem:=q;
			h:=h.link; DEC(nof)
		END;
	END ExtractHistory;
	
	PROCEDURE CreateMenuItems(listR: ListRiders.Rider; T: Texts.Text; ext: ARRAY OF CHAR): BOOLEAN;
		VAR p: MenuItem; w, h, dsr: INTEGER; R: Texts.Reader; cmd: CmdMenuItem; text: Texts.Text;
			s: ARRAY 128 OF CHAR; ch: CHAR; d: ListRiders.String;
			plist, tlist, plast, tlast: MenuItem; parsed: BOOLEAN;
		
		PROCEDURE Scan;
			VAR i: INTEGER;
		BEGIN i:=0; s[0]:=0X; Texts.Read(R, ch); 
			WHILE ~R.eot & (ch#"[") & (ch#"]") & (ch#CR) & (ch#LF) DO s[i]:=ch; INC(i); Texts.Read(R, ch) END; s[i]:=0X; 
		END Scan;
		
	BEGIN	
		IF listR = NIL THEN RETURN FALSE END;
		nofLines:=0; width:=0; NEW(itemList); lastItem:=itemList; 
		NEW(plist); plast := plist; NEW(tlist); tlast := tlist; parsed := FALSE;
		NEW(text); Texts.Open(text, PopupFileName); Texts.OpenReader(R, text, 0);
		LOOP
			REPEAT	Texts.Read(R, ch)	UNTIL R.eot OR (ch="[");
			IF	R.eot	THEN	RETURN FALSE	ELSE	Scan	END;
			IF	s=ext	THEN	EXIT	END;
		END;	
		REPEAT
			Scan; 
			IF s="" THEN (* ignore *)
			ELSIF s = "<Procedures>" THEN
				IF ~parsed THEN ExtractProcTypeNames(T, plast, tlast); parsed := TRUE END;
				IF plist.link # NIL THEN lastItem.link := plist.link; lastItem := plast END
			ELSIF s = "<Types>" THEN
				IF ~parsed THEN ExtractProcTypeNames(T, plast, tlast); parsed := TRUE END;
				IF tlist.link # NIL THEN lastItem.link := tlist.link; lastItem := tlast END
			ELSIF s[0]="<" THEN (* recent files *)
				h:=1; w:=0; WHILE (s[h]#0X) & (s[h]>="0") & (s[h]<="9") DO
					w:=w*10+ORD(s[h])-ORD("0"); INC(h)
				END;
				ExtractHistory(w); 
			ELSE
				NEW(cmd); lastItem.link:=cmd; lastItem:=cmd; cmd.link:=NIL; COPY(s, cmd.val);
			END
		UNTIL R.eot OR (ch="[");
		p:=itemList.link; 
		WHILE p # NIL DO 
			NEW(d); COPY(p.val, d.s); listR.do.Write(listR, d);
			Display3.StringSize(p.val, Fonts.Default, w, h, dsr);
			IF w+25>width THEN width:=w+25 END;
			INC(nofLines); p:=p.link
		END;
		RETURN TRUE
	END CreateMenuItems;
	
	PROCEDURE GetFileExtension(name: ARRAY OF CHAR; VAR ext: ARRAY OF CHAR);
		VAR i, j, l: INTEGER;
	BEGIN	i:=0; l:=0;
		WHILE name[i]#0X DO 
			IF name[i]="." THEN l:=i+1 END; 
			INC(i) 
		END;
		IF l=0 THEN l:=i END;
		j := 0; WHILE (j < LEN(ext)-1) & (name[l] # 0X) & (name[l] > " ") DO ext[j] := name[l]; INC(l); INC(j) END;
		ext[j]:=0X;
	END GetFileExtension;
	
	PROCEDURE NewList(F: TextGadgets.Frame; D: Documents.Document): Gadgets.Frame;
		VAR L: Gadgets.Frame; obj: Objects.Object; M: ListRiders.ConnectMsg; ext: ARRAY 12 OF CHAR;
	BEGIN
		GetFileExtension(D.name, ext);
		L := NIL;
		obj := Gadgets.CreateObject("ListModels.NewList");
		IF obj # NIL THEN
			Attributes.SetBool(obj, "Sorted", FALSE);
			M.R := NIL; obj.handle(obj, M);
			IF CreateMenuItems(M.R, F.text, ext) THEN
				IF nofLines > 0 THEN
					obj := Gadgets.CreateObject("ListGadgets.NewFrame");
					IF obj # NIL THEN
						L := obj(Gadgets.Frame);
						L.H := nofLines*Fonts.Default.height + 8;
						IF L.H > MaxHeight THEN L.H := MaxHeight END;
						IF L.H > Display.Height-50 THEN L.H := Display.Height - 50 END; L.W := width;
						Attributes.SetBool(L, "MultiSel", FALSE);
						Attributes.SetString(L, "Cmd", "TextPopups.Do '#Point'");
						Links.SetLink(L, "Model", M.R.base)
					END
				END
			END
		END;
		RETURN L
	END NewList;
	
	PROCEDURE CalcPlace(VAR x, y, px, py, w, h: INTEGER);
		VAR cx, cy, cw, ch: INTEGER;
	BEGIN
		cx := 10; cy := 10; cw := Display.Width - 10; ch := Display.Height - 10;
		px := x - w DIV 2; py := y - h DIV 2;
		IF px < cx THEN px := cx; END;
		IF px + w >= cx + cw THEN px := cx + cw - 1 - w; END;
		IF py < cy THEN py := cy; END;
		IF py + h >= cy + ch THEN py := cy + ch - 1 - h END;
	END CalcPlace;
			
	PROCEDURE Popup(F: TextGadgets.Frame; x, y: INTEGER; VAR M: Oberon.InputMsg);
		VAR block: Views.Block; of: Gadgets.Frame; R: Display3.Mask; px, py: INTEGER;
				CM: Display.ControlMsg; D: Display.DisplayMsg; O: Display3.OverlapMsg;
	BEGIN	
		of:=NewList(F, M.dlink(Documents.Document)); 
		IF of # NIL THEN
			CalcPlace(x, y, px, py, of.W, of.H);
			Oberon.RemoveMarks(px, py, of.W, of.H);
			Views.GetBlock(px, py, of.W, of.H, M.dlink, block);
			CM.id := Display.restore; CM.F := of; CM.x := 0; CM.y := 0; CM.res := -1; CM.dlink := NIL; of.handle(of, CM);
			O.F := of; O.M := NIL; O.x := 0; O.y := 0; O.res := -1; O.dlink := NIL; of.handle(of, O);
			D.device := Display.screen; D.id := Display.full; D.F := of; D.res := -1; D.dlink := M.dlink;
			D.x := px - of.X; D.y := py - of.Y; of.handle(of, D);
			called:=FALSE;
			Gadgets.MakeMask(of, px, py, M.dlink, R); 
			Input.Mouse(M.keys, M.X, M.Y);
			M.x := px - of.X; M.y := py - of.Y;
			WHILE (M.keys # {}) & (M.res < 0) DO
				of.handle(of, M);
				Input.Mouse(M.keys, M.X, M.Y); 
				Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y)
			END;
			Oberon.FadeCursor(Oberon.Mouse);
			Views.RestoreBlock(block);
			IF called THEN Call(F, F.text, x, y) END;
			M.res := 0
		END
	END Popup;

(* file history *)

	PROCEDURE InsertIntoHistory(VAR D: Documents.Document);
		VAR h: FileHistory; i: INTEGER;
	BEGIN	IF D=NIL THEN RETURN END;
		h:=fileHistory; WHILE (h#NIL) & (h.filename#D.name) DO h:=h.link END;
		IF h=NIL THEN
			NEW(h); COPY(D.name, h.filename); h.link:=fileHistory; fileHistory:=h;
			i:=0; WHILE (h#NIL) & (i<MaxHistory) DO h:=h.link; INC(i) END;
			IF h#NIL THEN h.link:=NIL END;
		END
	END InsertIntoHistory;

(* doc and text handler *)
	
	PROCEDURE PopupHandler(F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR x, y, X, Y: INTEGER; R: Texts.Reader; l: TextGadgets0.Loc; ch: CHAR; keys: SET;
	BEGIN	
		WITH F: TextGadgets.Frame DO
			IF M IS Oberon.InputMsg THEN 
				WITH M: Oberon.InputMsg DO
					IF M.id=Oberon.track THEN
						x := M.x + F.X; y := M.y + F.Y; 
						Input.Mouse(keys, X, Y);
						IF (X-x>14) (* sliderW *) & (M.keys={1}) THEN
							F.do.LocateChar(F, x, y, X, Y, l);
							Texts.OpenReader(R, F.text, l.pos); Texts.Read(R, ch); 
							IF (M.dlink IS Documents.Document) & ((R.lib = NIL) OR (R.lib IS Fonts.Font)) & ((ch = CR) OR (ch = TAB) OR (ch = SPACE) OR (ch=0X) & (l.pos>=F.text.len)) THEN
								Popup(F, X, Y, M)
							END
						END
					END
				END
			END
		END
	END PopupHandler;

	PROCEDURE Install*;
	BEGIN
		TextGadgets.popupHook:=PopupHandler; Documents.historyHook:=InsertIntoHistory
	END Install;
	
	PROCEDURE Remove*;
	BEGIN
		TextGadgets.popupHook:=NIL; Documents.historyHook:=NIL
	END Remove;

BEGIN
	Texts.OpenWriter(W);  Modules.InstallTermHandler(Remove);
	Texts.WriteString(W, "TextPopups using ");  Texts.WriteString(W, PopupFileName);
	Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf)
END TextPopups.

System.Free TextPopups ~
TextPopups.Install
TextPopups.Remove
