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

MODULE Watson;	(** portable *)	(** PS/tk   *)

	IMPORT
		Files, Modules, Objects, Fonts, Display, Texts, Oberon, Gadgets, TextGadgets0, TextGadgets, 
		Documents, TextDocs, Desktops, Watson0, Compress;

	CONST
	(* global constants *)
		Version = "1.7";

		(** valid options are:
			i: force output of comments to italic (only for mod file)
			p: force output to Fonts.Default font (only for mod file)

			d: show detail information (entry number, offset, key, etc) (only for symbol & object files)
			x: expand type (only for symbol file)

			following letters define lookup order of source files	(left most = most desired)
			D: definiton file
			M: module file
			S: symbol file
			C: commands
			T: Tutorial
		*)

		(* file name extensions *)
		defFileExt = ".Def"; tutFileExt = ".Book"; tutDelimiter = " ";
		
		(* title extension of document *)
		titleExt = ".Def";
		htmlExt = ".Def.html";	htmlBookExt = ".html";
		DefaultOrder = "DMSCT";

		(* document number attribute name *)
		DocNrAttr = "WDocNumber";

		(* public objects names *)
		orderObj = "Watson.Order"; tutorialObj = "Watson.TutorialText";
		archiveObj = "Watson.DefArchive"; modfileObj = "Watson.ModFile";

		(* typ of source file *)
		UndefTyp = 0; ModTyp = 1; DefTyp = 2; SymTyp = 3; CmdTyp = 4; TutTyp = 5; DefCTyp = 12;

	(* Constats for Mod-Scanner *)
		(* command strings *)
		BookCmd = "Desktops.OpenDoc "; GotoCmd = "Watson.Goto "; ObjCmd = "Watson.ShowObj ";
		ModCmd = "Watson.ShowDef ";
		Menu =  "Desktops.Copy[Copy] TextDocs.Search[Search] Watson.Back[Back] Desktops.StoreDoc[Store]";

		(* marker colors *)
		TextCol = 15; LinkCol = 3; DocuCol = 8; ImportCol = 1;
	
		MaxIdLen = 64; MaxMods = 32;
		
		(* some special characters *)
		TAB = 09X; CR = 0DX; 
	
		(* error codes *)
		errMod = 0; errImp = 1; errConst = 2; errType = 3; errVar = 4; errProc = 5;
		errModEnd = 6; errProcEnd = 7; errSym = 8; errTypeDef = 9; errIdent = 10;
		errNum = 11; errComment = 12;

		(* symbol values *)
		times = 0; and = 1; plus = 2; minus = 3; eql = 4; arrow = 5; 
		period = 6; comma = 7; colon = 8; rparen = 9; rbrak = 10; of = 11; 
		to = 12; lparen = 13; lbrak = 14; lbrace = 15; becomes = 16; number = 17; 
		string = 18; ident = 19; assert = 20; semicolon = 21; end = 22; if = 23; 
		case = 24; while = 25; for = 26; loop = 27; with = 28; array = 29; 
		record = 30; pointer = 31; begin = 32; code = 33; const = 34; type = 35; 
		var = 36; proc = 37; import = 38; module = 39; eot = 40; 
		none = 99;
		
		(* visibility of objects *)
		internal = 0; external = 1; externalR = 2;

	TYPE
	(* Type defs for Mod-Scanner *)
		Name = ARRAY MaxIdLen OF CHAR;

		Cmnt = POINTER TO CmntDesc;
		CmntDesc = RECORD
			next: Cmnt;
			wPos, bPos, ePos, insert: LONGINT;
			cnt: INTEGER;
			ln: BOOLEAN
		END;

		ModItem = RECORD
			real, alias: Name;
			exp, ln: BOOLEAN;
			cmnts: Cmnt;
		END;

		LocalIdent = POINTER TO IdentDesc;		(* list of local (= nonexported) idents *)
		IdentDesc = RECORD
			next: LocalIdent;
			name: Name;
			beg, end: LONGINT;
			class: INTEGER;
		END;

		Fixup = POINTER TO FixupDesc;	(* list of type names to fixup *)
		FixupDesc = RECORD
			next: Fixup;
			insert: LONGINT;
			name: Name;
			qualified: BOOLEAN;
		END;

		History = POINTER TO HistoryDesc;	(* history list *)
		HistoryDesc = RECORD
			next, succ: History;
			nr: LONGINT;
			cmd: ARRAY 64 OF CHAR
		END;

	VAR
	(* global variables *)
		W: Texts.Writer;

		history: History;	(* document history *)
		lastHistNr: LONGINT;	(* last history number used *)
		oObj: Objects.Object;	(* public object (default hierarchy) *)
		linkText: Texts.Text;	(* public object (link text to find corresponding tutorial) *)
		aObj: Objects.Object;	(* public object (archive of compressed def files) *)
		mObj: Objects.Object;	(* public object (format of mod file names) *)
		order: ARRAY 8 OF CHAR;	(* order of source files to look for *)
		defName: ARRAY 32 OF CHAR;	(* def-file name to look for (Compress.Enumerate) *)
		defFound: BOOLEAN;	(* indicates def-file found in archive (Compress.Enumerate) *)
		msgPrinted: BOOLEAN;	(* flag to indicate printing of Log-msg *)

	(* variables for Mod-Reader *)
		(* variables to remeber infos during scannig *)
		mods : INTEGER;	(* # of imported modules *)
		mod : ARRAY MaxMods OF ModItem;
		options: ARRAY 12 OF CHAR;	(* set by GetArgs and appended at a control's cmd *)
		localIds: IdentDesc;	(* non exported ident list *)
		fixups: FixupDesc;	(* fixup list of type idents *)
		cmnts: CmntDesc;	(* list of comments *)

		(* variables used by the scannig process *)
		ModT: Texts.Text;	(* source text *)
		R: Texts.Reader;	(* reader on source text *)
		id, label: Name;	(* current ident/tutorial-label *)
		num: LONGINT;	(* current number *)
		begPos, wPos: LONGINT;	(* beginning of symbol in source text (wPos = end of last symbol) *)
		numLines,	(* #lines skiped while scanning one symbol *)
		lines: INTEGER;	(* lines already read *)
		level, recLevel: INTEGER;	(* level: procedure level | recLevel: record level *)
		wasRecord: BOOLEAN;	(* last type read was a record *)
		newLine: BOOLEAN;	(* TRUE when read a line feed while scanning one symbol *)
		ch: CHAR;     (* current character *)
		sym: SHORTINT;	(* current symbol *)

		(* variables needed to write definition text *)
		OutT: Texts.Text;	(* text for definition output *)
		italic: Fonts.Font;	(* pointer to Oberon10i font *)
		lastPos, importPos: LONGINT;	(* position of last error *)
		noerr: BOOLEAN;
		curErr: SHORTINT;	(* current error code *)
		doItalic: BOOLEAN;	(* forces output of comments in italic *)

	(* ---------------------- string operations ----------------------- *)

	PROCEDURE Append (VAR d: ARRAY OF CHAR; s: ARRAY OF CHAR);	(* append string s to d *)
		VAR i, j: INTEGER; ch: CHAR;
	BEGIN
		i := 0; WHILE d[i] # 0X DO INC(i) END;
		j := 0; REPEAT ch := s[j]; d[i] := ch; INC(i); INC(j) UNTIL ch = 0X
	END Append;

	PROCEDURE AppendCh (VAR d: ARRAY OF CHAR; ch: CHAR);	(* append char ch to string d *)
		VAR i: INTEGER;
	BEGIN
		i := 0; WHILE d[i] # 0X DO INC(i) END;
		d[i]:= ch; d[i+1]:= 0X
	END AppendCh;

	PROCEDURE QualIdent (VAR qualifier, identifier: ARRAY OF CHAR);
	(* separates module and object name *)
		VAR i, j: INTEGER;
	BEGIN
		i := 0; j := 0;
		WHILE (qualifier[i] # ".") & (qualifier[i] # 0X) DO INC(i) END;
		qualifier[i] := 0X; INC(i); j := 0; 
		WHILE qualifier[i] # 0X DO identifier[j] := qualifier[i]; INC(i); INC(j) END;
		identifier[j] := 0X
	END QualIdent;

	(* ---------------------- output procedure ----------------------- *)

	PROCEDURE SetColor(col: SHORTINT);	(*  sets W color to col *)
	BEGIN Texts.SetColor(W, col)
	END SetColor;

	PROCEDURE Char(ch: CHAR);	(*  writes a char to W *)
	BEGIN Texts.Write(W, ch)
	END Char;

	PROCEDURE Str(str: ARRAY OF CHAR);	(*  writes a string to W *)
	BEGIN Texts.WriteString(W, str)
	END Str;
	
	PROCEDURE Int(i: LONGINT);	(*  writes an integer to W *)
	BEGIN Texts.WriteInt(W, i, 0)
	END Int;

	PROCEDURE Indent (i: INTEGER); 	(*  writes i tabs to W *)
	BEGIN WHILE i > 0 DO Texts.Write(W, TAB); DEC(i) END
	END Indent;

	PROCEDURE Ln;	(*  writes a line feed to W *)
	BEGIN Texts.WriteLn(W)
	END Ln;

	PROCEDURE Object(obj: Objects.Object);	(*  writes an object to W *)
	BEGIN Texts.WriteObj(W, obj)
	END Object;

	PROCEDURE ToLog;	(*  writes W to the Log *)
	BEGIN Texts.Append(Oberon.Log, W.buf)
	END ToLog;

	PROCEDURE PrintMsg;	(* writes program name & version to the Oberon Log *)
	BEGIN
		(* Texts.SetFont(W, Fonts.This("Oberon10b.Scn.Fnt")); *)
		Str("Watson "); Str(Version);
		(* Texts.SetFont(W, Fonts.Default); *)
		Str(" / PS January 95"); Ln; ToLog;
		msgPrinted:= TRUE
	END PrintMsg;


	(* ---------------------- history procedure ----------------------- *)

	PROCEDURE AddDocToHistory(oldNr: LONGINT): History;
		VAR new, h: History;
	BEGIN
		h:= history; WHILE (h # NIL) & (h.nr # oldNr) DO h:= h.next END;
		NEW(new); new.nr:= lastHistNr; INC(lastHistNr); new.succ:= h;
		new.next:= history; history:= new;
		RETURN new
	END AddDocToHistory;

	PROCEDURE GetDocSucc(nr: LONGINT): History;
		VAR h: History;
	BEGIN
		h:= history; WHILE (h # NIL) & (h.nr # nr) DO h:= h.next END;
		IF h # NIL THEN RETURN h.succ ELSE RETURN NIL END
	END GetDocSucc;

	PROCEDURE MakeHistoryCmd(h: History; cmd, mod, obj: ARRAY OF CHAR);
		VAR i, j: INTEGER;
	BEGIN
		IF h # NIL THEN
			COPY(cmd, h.cmd);
			i:= 0; WHILE h.cmd[i] # 0X DO INC(i) END;
			h.cmd[i]:= " "; h.cmd[i+1]:= Oberon.OptionChar; INC(i, 2);
			j:= 0; WHILE order[j] # 0X DO h.cmd[i]:= order[j]; INC(j); INC(i) END;
			j:= 0; WHILE options[j] # 0X DO h.cmd[i]:= options[j]; INC(j); INC(i) END;
			h.cmd[i]:= " "; INC(i);
			j:= 0; WHILE mod[j] # 0X DO h.cmd[i]:= mod[j]; INC(j); INC(i) END;
			REPEAT DEC(i) UNTIL h.cmd[i] = ".";
			INC(i);
			IF obj # "" THEN
				j:= 0; WHILE obj[j] # 0X DO h.cmd[i]:= obj[j]; INC(j); INC(i) END
			ELSE
				h.cmd[i] := "M"; INC(i); h.cmd[i] := "o"; INC(i); h.cmd[i] := "d"; INC(i)
			END;
			h.cmd[i]:= 0X
		END
	END MakeHistoryCmd;


	(* ---------------------- special document handler ----------------------- *)

	PROCEDURE DocHandler(D: Objects.Object; VAR M: Objects.ObjMsg);
	BEGIN
		IF M IS Objects.LinkMsg THEN
			WITH M: Objects.LinkMsg DO
				IF (M.id = Objects.get) & (M.name = "DeskMenu") THEN
					M.obj := Gadgets.CopyPublicObject("Watson.DeskMenu", TRUE);
					IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
					M.res := 0
				ELSIF (M.id = Objects.get) & (M.name = "SystemMenu") THEN
					M.obj := Gadgets.CopyPublicObject("Watson.SystemMenu", TRUE);
					IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
					M.res := 0
				ELSIF (M.id = Objects.get) & (M.name = "UserMenu") THEN
					M.obj := Gadgets.CopyPublicObject("Watson.UserMenu", TRUE);
					IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
					M.res := 0
				ELSE TextDocs.DocHandler(D, M)
				END
			END
		ELSE TextDocs.DocHandler(D, M)
		END
	END DocHandler;


	(* *************** DEF FILE *************** *)

	PROCEDURE OpenDef(T: Texts.Text; mod: ARRAY OF CHAR; compressed: BOOLEAN);	(* Opens a saved def-text *)
		VAR R: Files.Rider; len: LONGINT; x, y, w, h, tag, res: INTEGER; s: ARRAY 64 OF CHAR; ch: CHAR;
				A: Objects.AttrMsg;
	BEGIN Append(mod, defFileExt);
		IF compressed THEN	(* def. file is stored in the archive *)
			Files.Set(R, Files.New(""), 0);
			(* get name of def. archive *)
			A.id:= Objects.get; A.name:= "Value"; A.res:= -1; A.class:= Objects.Inval; aObj.handle(aObj, A);
			Compress.ExtractFile(A.s, mod, R, res);
			IF res # Compress.Done THEN Texts.Open(T, ""); RETURN END;
			Files.Set(R, Files.Base(R), 0);
			Files.ReadInt(R, tag);
			IF (tag = Documents.Id) OR (tag = 0727H) THEN
				(* there is a document header -> skip it *)
				Files.ReadString(R, s);
				Files.ReadInt(R, x); Files.ReadInt(R, y); Files.ReadInt(R, w); Files.ReadInt(R, h)
			ELSE Files.Set(R, Files.Base(R), 0)
			END;
			Files.Read(R, ch);
			IF (ch = Texts.TextBlockId) OR (ch = 01X) THEN
				(* load text from file *)
				Str("reading "); Str(mod);
				Str(" ("); Str(A.s); Str(") ");
				Texts.Load(T, Files.Base(R), Files.Pos(R), len);
				Files.Close(Files.Base(R))
			END
		ELSE Str("reading "); Str(mod); Texts.Open(T, mod)
		END;
		Ln; ToLog
	END OpenDef;


	(* *************** TUTORIAL *************** *)

	PROCEDURE OpenTut(this: ARRAY OF CHAR);	(* opens given tutorial at given label (this = Tutorial.html Label) *)
		VAR cmd: ARRAY 64 OF CHAR;
	BEGIN COPY("Desktops.OpenDoc ", cmd); Append(cmd, this);
		Str("reading "); Str(this); Ln; ToLog;
		Gadgets.Execute(cmd, NIL, NIL, NIL, NIL)
	END OpenTut;


	(* *************** MOD READER *************** *)

	(* ---------------------- forward declarations ----------------------- *)

	PROCEDURE ^ err(n: SHORTINT);	(* writes error n to the Oberon Log *)
	PROCEDURE ^ ShowType;	(* scans and writes any type definition *)
	PROCEDURE ^ SkipType;	(* skips any type definition *)
	PROCEDURE ^ Block(blockId: Name; vis: BOOLEAN);	(* scans and writes a module/procedure block *)

	(* ---------------------- handles local identifier/label list ----------------------- *)

	PROCEDURE FindIdent(VAR name: Name): LocalIdent;	(* looks for ident name *)
		VAR cur: LocalIdent;
	BEGIN
		cur:= localIds.next; WHILE (cur # NIL) & (cur.name # name) DO cur:= cur.next END;
		RETURN cur
	END FindIdent;
	
	PROCEDURE InsertIdent(VAR name: Name; class: INTEGER; VAR obj: LocalIdent);
	(* iserts ident name in list, if current level is the top level (= no local ident) *)
	BEGIN
		IF level = 0 THEN
			obj:= localIds.next; WHILE (obj # NIL) & (obj.name # name) DO obj:= obj.next END;
			IF obj = NIL THEN NEW(obj);
				COPY(name, obj.name); obj.class:= class; obj.beg:= 0; obj.end:= 0;
				obj.next:= localIds.next; localIds.next:= obj
			ELSE err(errIdent)
			END
		ELSE NEW(obj)
		END
	END InsertIdent;

	PROCEDURE NeedsLn(): BOOLEAN;	(* checks if exp. comment wrote an ln before *)
		VAR cmnt: Cmnt; res: BOOLEAN;
	BEGIN res:= TRUE; cmnt:= cmnts.next;
		WHILE (cmnt # NIL) & (cmnt.insert = W.buf.len) DO
			res:= res & ~cmnt.ln; cmnt:= cmnt.next
		END;
		RETURN res
	END NeedsLn;
		
	(* ---------------------- buffer / text operations ----------------------- *)

	PROCEDURE Copy(beg, end: LONGINT);
	(* copies the given text strech (= [beg, end)) from source text to writer W. Makes a copy of all objects in the text *)
		VAR F: Texts.Finder; obj: Objects.Object; C: Objects.CopyMsg;
	BEGIN
		IF end > ModT.len THEN end:= ModT.len END;
		Texts.OpenFinder(F, ModT, beg);
		WHILE F.pos < end DO
			IF beg < F.pos THEN Texts.Save(ModT, beg, F.pos, W.buf) END;
			beg:= F.pos; Texts.FindObj(F, obj);
			IF (obj IS Display.Frame) THEN
				C.id:= Objects.shallow; Objects.Stamp(C); obj.handle(obj, C);	(* copy *)
				Object(C.obj);
				INC(beg)
			END
		END;
		IF beg < end THEN Texts.Save(ModT, beg, end, W.buf) END
	END Copy;

	(* ---------------------- write error procedure ----------------------- *)

	PROCEDURE Pos(): LONGINT;	(* returns the current position in the source text *)
	BEGIN RETURN Texts.Pos(R)-1
	END Pos;

	PROCEDURE err(n: SHORTINT);	(* writes an error msg to the Oberon log *)
		VAR pos: LONGINT;
	BEGIN noerr:= FALSE; pos:= Pos();
		Texts.OpenBuf(W.buf); Texts.SetFont(W, Fonts.Default);
		IF lastPos+10 < pos THEN lastPos:= pos;
			SetColor(TextCol); Ln; Str("  pos  "); Int(pos); Str("   ");
			CASE n OF
				errMod: Str("module identifier missing")
				| errImp: Str("incorrect import block")
				| errConst: Str("incorrect constant block")
				| errType: Str("incorrect type block")
				| errVar: Str("incorrect var block")
				| errProc: Str("incorrect procedure declaration")
				| errModEnd: Str("end of module missing")
				| errProcEnd: Str("end of procedure missing")
				| errSym: Str("wrong symbol read: sym = "); Int(sym)
				| errTypeDef: Str("error in type definition")
				| errIdent: Str("identifier not declared (or twice)")
				| errNum: Str("not a number")
				| errComment: Str("comment not closed")
			ELSE Str("syntax error dedected")
			END;
			ToLog
		END
	END err;

	(* ---------------------- various procedure to write def. text ----------------------- *)

	PROCEDURE Control(name, cmd, par: ARRAY OF CHAR);
	(* inserts a Control with a name (= name) and a command (= cmd+options+par) to W *)
		VAR obj: Objects.Object; A: Objects.AttrMsg;
	BEGIN
		obj:= Gadgets.CreateObject("TextGadgets.NewControl");
		IF obj # NIL THEN
			IF par # "" THEN	(* set cmd-attribute *)
				A.id:= Objects.set; A.name:= "Cmd"; A.class:= Objects.String; A.res:= -1;
				COPY(cmd, A.s);
				IF (options # "") & (cmd # BookCmd)  THEN
					AppendCh(A.s, Oberon.OptionChar); Append(A.s, options); AppendCh(A.s, " ")
				END;
				Append(A.s, par);
				obj.handle(obj, A)
			END;
			IF name # "" THEN Gadgets.NameObj(obj, name) END;
			Object(obj)
		END
	END Control;

	PROCEDURE Identifier(name: ARRAY OF CHAR);
	(* writes an identifier & Control to W and checks if a Control-cmd is needed *)
		VAR par: ARRAY 32 OF CHAR; i, j: INTEGER; ch: CHAR;
	BEGIN 
		IF label # "" THEN
			(* if there is a tutorial label (= 'Tutorial.Label'), set par to 'Tutorial.html Label'*)
			SetColor(DocuCol);
			i:= 0; j:= 0;
			REPEAT ch:= label[j]; par[i]:= ch; INC(i); INC(j) UNTIL (ch = 0X) OR (ch = ".");
			par[i-1]:= 0X; Append(par, tutFileExt);
			i := 0; WHILE par[i] # 0X DO INC(i) END;
			par[i]:= tutDelimiter; INC(i);
			WHILE label[j] # 0X DO par[i]:= label[j]; INC(i); INC(j) END;
			par[i]:= 0X; label:= ""
		ELSE par:= ""
		END;
		Str(name); SetColor(TextCol);
		Control(name, BookCmd, par)
	END Identifier;

	PROCEDURE Keywords(VAR last: Cmnt; word: ARRAY OF CHAR; ln, indent: BOOLEAN);	(* writes a word and shift comments *)
		VAR cmnt: Cmnt; offset: LONGINT;
	BEGIN offset:= LEN(word)-1;
		IF indent THEN
			IF ln THEN Ln; INC(offset) END;
			Ln; Indent(1+recLevel); INC(offset, 2)
		END;
		Str(word);
		cmnt:= cmnts.next;
		WHILE (cmnt # last) DO cmnt.insert:= cmnt.insert+offset; cmnt:= cmnt.next END;
		last:= cmnts.next
	END Keywords;

	PROCEDURE Cmnts(offset: LONGINT);
		VAR fix: Fixup; curC: Cmnt;
	BEGIN curC:= cmnts.next;
		WHILE curC # NIL DO 
			fix:= fixups.next;
			WHILE (fix # NIL) & (fix.insert > curC.insert) DO
				fix.insert:= fix.insert + curC.ePos - curC.wPos - curC.cnt;
				IF curC.ln THEN fix.insert:= fix.insert + 1 END;
				fix:= fix.next
			END;
			IF curC.ln THEN Ln END;
			Copy(curC.wPos, curC.bPos); Copy(curC.bPos, curC.bPos+1);
			IF (curC.cnt > 1) & (curC.bPos+5 < curC.ePos) THEN
				INC(curC.cnt); Copy(curC.bPos+2, curC.ePos-curC.cnt); Copy(curC.ePos-2, curC.ePos)
			ELSE Copy(curC.bPos+2, curC.ePos)
			END;
			Texts.Insert(OutT, curC.insert+offset, W.buf);
			curC:= curC.next
		END
	END Cmnts;

	PROCEDURE Imports;	(* writes import list to W *)
		VAR i, j: INTEGER; first, ln: BOOLEAN;
		
		PROCEDURE OutCmnt(cmnt: Cmnt);
		BEGIN
			IF cmnt # NIL THEN
				OutCmnt(cmnt.next);
				IF cmnt.ln THEN Ln END;
				Copy(cmnt.wPos, cmnt.bPos); Copy(cmnt.bPos, cmnt.bPos+1);
				IF (cmnt.cnt > 1) & (cmnt.bPos+5 < cmnt.ePos) THEN
					INC(cmnt.cnt); Copy(cmnt.bPos+2, cmnt.ePos-cmnt.cnt); Copy(cmnt.ePos-2, cmnt.ePos)
				ELSE Copy(cmnt.bPos+2, cmnt.ePos)
				END
			END
		END OutCmnt;

	BEGIN j:= 0;
		IF mods > 1 THEN i:= 1;
			first:= TRUE; ln:= FALSE;
			WHILE i < mods DO
				ln:= ln OR mod[i].ln;
				IF mod[i].exp THEN
					IF first THEN first:= FALSE; Keywords(cmnts.next, "IMPORT",mod[0].ln, TRUE)
					ELSE Char(",")
					END;
					WHILE j < i DO OutCmnt(mod[j].cmnts); INC(j) END;
					IF ln THEN ln:= FALSE; Ln; Indent(2) ELSE Char(" ") END;
					IF mod[i].real # "SYSTEM" THEN SetColor(ImportCol);
						Str(mod[i].real); Control("" , ModCmd, mod[i].real);
						SetColor(TextCol)
					ELSE Str("SYSTEM")
					END
				END;
				INC(i)
			END;
			IF ~first THEN Char(";") END
		END;
		WHILE j # mods DO OutCmnt(mod[j].cmnts); INC(j) END
	END Imports;

	PROCEDURE Link(VAR name: Name; qualified: BOOLEAN);	(* writes string name and control obj to W *)
		VAR obj: LocalIdent;
	BEGIN
		IF qualified THEN	(* name of form mod.ident *)
			IF (name[0] = "S") & (name[1] = "Y") & (name[2] = "S") & (name[6] = ".") THEN Str(name)
			ELSE SetColor(LinkCol); Str(name); Control("", ObjCmd, name)
			END
		ELSE 
			(* check if ident is a keyword, if so write it and return *)
			IF (name = "CHAR") OR (name = "BOOLEAN") OR (name = "INTEGER") THEN Str(name); RETURN
			ELSIF (name = "LONGINT") OR (name = "SHORTINT") OR (name = "SET")THEN Str(name); RETURN
			ELSIF (name = "REAL") OR (name = "LONGREAL") THEN Str(name); RETURN
			ELSIF (name = "TRUE") OR (name = "FALSE") THEN Str(name); RETURN
			ELSIF (name = "MOD") OR (name = "DIV") THEN Str(name); RETURN
			ELSIF (name = "MAX") OR (name = "MIN") OR (name = "ABS") THEN Str(name); RETURN
			ELSIF (name = "ASH") OR (name = "ROT") OR (name = "ODD") THEN Str(name); RETURN
			ELSIF (name = "CAP") OR (name = "ORD") OR (name = "CHR") THEN Str(name); RETURN
			ELSIF (name = "LEN") OR (name = "SIZE") OR (name = "CHR") THEN Str(name); RETURN
			ELSIF (name = "LONG") OR (name = "SHORT") OR (name = "ENTIER") THEN Str(name); RETURN
			(*ELSIF (name = "PTR") THEN Str(name); RETURN*)
			ELSE obj:= FindIdent(name);
				(* check whether object is exported or not *)
				IF (obj = NIL) THEN (* exported => write control *) SetColor(LinkCol); Str(name); Control("", GotoCmd, name)
				ELSIF obj.class = const THEN (* not visible & constant => substitute value *) Copy(obj.beg, obj.end)
				ELSE (* not visible & type => no link *) Str(name)
				END
			END
		END;
		SetColor(TextCol)
	END Link;

	PROCEDURE Fixups(offset: LONGINT);	(* writes type fixups to OutT at position off *)
		VAR cur: Fixup;
	BEGIN cur:= fixups.next;
		WHILE cur # NIL DO
			Link(cur.name, cur.qualified); Texts.Insert(OutT, cur.insert+offset, W.buf);
			cur:= cur.next
		END
	END Fixups;

	(* ---------------------- scanner ----------------------- *)

	PROCEDURE GetCh;
	BEGIN IF ch = CR THEN INC(lines) END; Texts.Read(R, ch)
	END GetCh;
	
	PROCEDURE Ident;	(* reads an identifier into id *)
		VAR i: INTEGER;
	BEGIN i := 0;
		REPEAT
			id[i] := ch; INC(i); GetCh
		UNTIL (ch < "0") OR ("9" < ch) & (CAP(ch) < "A") OR ("Z" < CAP(ch)) OR (i = MaxIdLen);
		IF i = MaxIdLen THEN DEC(i);
			WHILE ("0" <= ch) & (ch <= "9") OR ("A" <= CAP(ch)) & (CAP(ch) <= "Z") DO GetCh END
		END;
		id[i]:= 0X
	END Ident;
	
	PROCEDURE String(ch0: CHAR);	(* skips a string *)
	VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE ch # ch0 DO
			IF i < 62 THEN id[i] := ch; INC(i) END;
			GetCh
		END;
		id[i] := 0X
	END String;

	PROCEDURE Number(ch0: CHAR);		(* reads a number into num *)
		VAR digit: ARRAY 24 OF CHAR; n: INTEGER;
		
		PROCEDURE Ord(ch: CHAR; hex: BOOLEAN): INTEGER;	(* converts a char to an integer *)
		BEGIN
			IF ch <= "9" THEN RETURN ORD(ch)-ORD("0")
			ELSIF hex THEN RETURN ORD(ch)-ORD("A")+10
			ELSE err(errNum); RETURN 0
			END
		END Ord;

		PROCEDURE ToNum(hex: BOOLEAN);	(* converts string digit to variable num *)
			VAR i, d: INTEGER;
		BEGIN i:= 0;
			WHILE i < n DO d:= Ord(digit[i], hex);
				IF num <= MAX(LONGINT) - d THEN num:= num*10+d END;
				INC(i)
			END
		END ToNum; 

	BEGIN n:= 1; digit[0]:= ch0; num:= 0;
		WHILE ("0"<=ch) & (ch<="9") OR ("A"<=ch) & (ch<="F") DO	(* read in all digits *)
			IF n < 24 THEN digit[n]:= ch; INC(n) END; GetCh
		END;
		IF ch = "." THEN GetCh;	(* either float or begin of range *)
			IF ch = "." THEN ToNum(FALSE); ch:= 7FX	(* 7FX = '..' *)
			ELSE	(* skip float *)
				REPEAT GetCh UNTIL (ch < "0") OR ("9" < ch);
				IF (ch = "E") OR (ch = "D") THEN
					GetCh;
					IF (ch = "+") OR (ch = "-") THEN GetCh END;
					REPEAT GetCh UNTIL (ch < "0") OR ("9" < ch)
				END
			END
		ELSIF ch = "X" THEN GetCh
		ELSIF ch = "H" THEN ToNum(TRUE); GetCh
		ELSE ToNum(FALSE)
		END
	END Number;

	PROCEDURE Comment(VAR oLine: INTEGER);	(* scans a comment and sets label or writes an exported comment to W *)
	(* cnt: # of '*' at the end of a comment | lev: level recursiv comments *)
		VAR cmnt: Cmnt; pos: LONGINT; lev, cnt: INTEGER; ch0: CHAR;
	BEGIN ch0:= ch; lev:= 1; cnt:= 0;
		IF ch = "*" THEN GetCh;
			IF ch = ")" THEN GetCh; RETURN END
		ELSIF ch = "L" THEN	(* label definition *)
			REPEAT GetCh UNTIL (ch = "*") OR (("A" <= CAP(ch)) & (CAP(ch) <= "Z"));
			IF ch # "*" THEN Ident;
				IF (ch = ".") & (id # "") THEN GetCh;
					COPY(id, label); AppendCh(label, ".");
					Ident;
					IF id # "" THEN Append(label, id)
					ELSE label:= ""
					END
				END
			END
		END;
		REPEAT	(* read to end of comment, but not after end of file *)
			IF ch = "*" THEN GetCh; INC(cnt);
				IF ch = ")" THEN GetCh; DEC(lev) END
			ELSIF ch = "(" THEN GetCh; cnt:= 0;
				IF ch = "*" THEN GetCh; INC(lev) END
			ELSE GetCh; cnt:= 0
			END
		UNTIL (lev = 0) OR R.eot;
		IF R.eot & (lev > 0) THEN err(errComment); RETURN END;
		IF ch0 = "*" THEN	(* export comment *)
			IF doItalic THEN pos:= Texts.Pos(R);
				Texts.ChangeLooks(ModT, wPos, Pos(), {0}, italic, 0, 0);
				Texts.OpenReader(R, ModT, pos)
			END;
			NEW(cmnt);
			cmnt.ln:= numLines > 1;
			cmnt.wPos:= wPos; cmnt.bPos:= begPos; cmnt.ePos:= Pos(); cmnt.cnt:= cnt;
			cmnt.insert:= W.buf.len;
			cmnt.next:= cmnts.next; cmnts.next:= cmnt;
			oLine:= lines
		END
	END Comment;

	PROCEDURE Sym;
	(* scans the next symbol; some of the will be skiped because they are not needed
		wPos: after last symbol or start of line
		begPos: beginnig of current symbol 
	*)
		VAR oLine: INTEGER; s: SHORTINT; ch0: CHAR;
	BEGIN
		IF sym = eot THEN RETURN END;	(* nothing more to scan *)
		s:= none; oLine:= lines;
		WHILE ~R.eot & (s = none) DO
			wPos:= Pos();
			WHILE ~R.eot & ((ch <= " ") OR ~(R.lib IS Fonts.Font))  DO	(* skip unnecessary chars *)
				IF ch = CR THEN wPos:= Pos() END; GetCh
			END;
			numLines:= lines-oLine; newLine:= numLines # 0;
			begPos:= Pos();
			IF ("a" <= ch) & (ch <= "z") THEN ch0:= CAP(ch) ELSE ch0:= ch END;
			IF ("A" <= ch0) & (ch0 <= "Z") THEN s:= ident; Ident ELSE GetCh END;
			CASE ch0 OF   (* ch0 > " " *)
				| 22X, 27X: String(ch0); GetCh; s:= string
				| "("  : IF ch = "*" THEN GetCh; Comment(oLine) ELSE s:= lparen END
				| ")" : s:= rparen
				| "{" : s:= lbrace
				| "*" : s :=  times
				| "-" : s:= minus
				| "+" : s:= plus
				| "&": s:= and
				| "," : s:= comma
				| ":" : IF ch = "=" THEN GetCh; s:= becomes ELSE s:= colon END
				| "=" : s:= eql
				| "." : s:= period
				| "^" : s:= arrow
				| ";" : s:= semicolon
				| "[" : s:= lbrak
				| "]" : s:= rbrak
				| "A":
					IF id = "ARRAY" THEN s:= array
					ELSIF id = "ASSERT" THEN s:= assert
					END
				| "B": IF id = "BEGIN" THEN s:= begin END
				| "C":
					IF id = "CONST" THEN s:= const 
					ELSIF id = "CODE" THEN s:= code
					ELSIF id = "CASE" THEN s:= case
					END
				| "E": IF id = "END" THEN s:= end END
				| "F": IF id = "FOR" THEN s:= for END
				| "I":
					IF id = "IMPORT" THEN s:= import
					ELSIF id = "IF" THEN s:= if
					END
				| "L": IF id = "LOOP" THEN s:= loop END
				| "M": IF id = "MODULE" THEN s:= module END
				| "O": IF id = "OF" THEN s:= of END
				| "P":
					IF id = "PROCEDURE" THEN s:= proc
					ELSIF id = "POINTER" THEN s:= pointer
					END
				| "R": IF id = "RECORD" THEN s:= record END
				| "T":
					IF id = "TYPE" THEN s:= type
					ELSIF id = "TO" THEN s:= to
					END
				| "V": IF id = "VAR" THEN s:= var END
				| "W":
					IF id = "WHILE" THEN s:= while
					ELSIF id = "WITH" THEN s:= with
					END
				| "0".."9": Number(ch0); s:= number
			ELSE
			END;	(* CASE *)
			IF R.eot & (ch0 # ".") THEN s:= eot END
		END;	(* WHILE *)
		sym:= s
	END Sym;

	(* ---------------------- parser procedures ----------------------- *)

	PROCEDURE FindMod(VAR name: Name): BOOLEAN;
	(* checks if module is in import list and returns module's real name *) 
		VAR i: INTEGER;
	BEGIN i:= 0;
		REPEAT
			IF mod[i].alias = name THEN
				mod[i].exp:= TRUE;
				COPY(mod[i].real, name);	(* substitute real name for alias name *)
				RETURN TRUE
			END;
			INC(i)
		UNTIL i >= mods;
		err(errIdent); RETURN FALSE
	END FindMod;
	
	(* ---------------- check single char/symbol ----------------- *)

	PROCEDURE CheckSym(s: INTEGER);
	BEGIN IF sym = s THEN Sym ELSE err(errSym) END
	END CheckSym;

	PROCEDURE CheckMark(VAR vis: SHORTINT);
	BEGIN
		IF (sym = times) OR (sym = minus) THEN
			IF level > 0 THEN vis:= internal
			ELSIF sym = times THEN vis:= external
			ELSE vis:= externalR
			END;
			Sym
		ELSE vis := internal
		END
	END CheckMark;
	
	(* ---------------- parse (qulified) identifier ----------------- *)

	PROCEDURE qualident(VAR end: LONGINT);	(* writes a (qualified) ident *)
		VAR qualifier: Name;
	BEGIN end:= Pos();
		COPY(id, qualifier); Sym; 
		IF sym = period THEN Sym; end:= Pos();
			IF ~FindMod(qualifier) THEN err(curErr) END;
			IF sym = ident THEN
				AppendCh(qualifier, "."); Append(qualifier, id); Link(qualifier, TRUE);
				Sym
			ELSE err(curErr)
			END
		ELSE Link(qualifier, FALSE)
		END
	END qualident;

	(* ---------------- parse constat block ----------------- *)

	PROCEDURE ConstExpression;	(* parses and writes an expression *)
		VAR beg: LONGINT; follow: SET;
	BEGIN beg:= wPos; curErr:= errConst;
		IF sym = lbrace THEN follow:= {rbrak, of} ELSE follow:= {comma, rbrak, of} END;
		LOOP
			WHILE ~(sym IN follow)  & (sym < ident) DO Sym END;
			IF sym = ident THEN
				Copy(beg, begPos); (*Char(" ");*) qualident(beg);
				IF sym = lparen THEN
					WHILE (sym # rparen) & (sym # eot) DO Sym() END
				END
			ELSE EXIT
			END
		END;	(* LOOP *)
		Copy(beg, begPos)
	END ConstExpression;
	
	PROCEDURE ConstDef;	(* parses and writes constant declarations *)
		VAR cmnt: Cmnt; obj: LocalIdent; vis: SHORTINT; first, newL, needsLn: BOOLEAN;
	BEGIN first:= TRUE; needsLn:= NeedsLn(); cmnt:= cmnts.next; Sym;
		WHILE sym = ident DO newL:= newL OR newLine;
			Sym; CheckMark(vis);
			IF vis > internal THEN
				IF first THEN first:= FALSE; Keywords(cmnt, "CONST", needsLn & (recLevel <= 0), TRUE); newL:= TRUE END;
				IF newL THEN newL:= FALSE; Ln; Indent(2 + recLevel) ELSE Char(" ") END;
				Identifier(id); Str(" =");
				IF (sym = eql) OR (sym = becomes) THEN Sym; ConstExpression ELSE err(errConst) END;
				Char(";");
			ELSE
				InsertIdent(id, const, obj); obj.beg:= Pos()(*+1*);
				REPEAT Sym UNTIL sym >= semicolon;
				obj.end:= begPos
			END;
			CheckSym(semicolon)
		END	(* WHILE *)
	END ConstDef;

	(* ----------------parse types ----------------- *)

	PROCEDURE CheckSysFlags;	(* parses and writes a system flag definition *)
	BEGIN
		IF sym = minus THEN Str(" -"); Sym END;	(* Macintosh *)
		IF sym = lbrak THEN Str(" [");
			Sym; ConstExpression;
			Char("]"); CheckSym(rbrak)
		END
	END CheckSysFlags;

	PROCEDURE RecordType;	(* parses and writes a record definition *)
		VAR endPos: LONGINT; vis: SHORTINT; first, ln: BOOLEAN;
	BEGIN
		Keywords(cmnts.next, "RECORD", FALSE, FALSE); Sym; CheckSysFlags;
		IF sym = lparen THEN Sym;	(* base type *)
			Str(" ( ");
			IF sym = ident THEN qualident(endPos) ELSE err(errTypeDef) END;
			Str(" ) ");
			WHILE sym < ident DO Sym END
		END;
		(*
		LOOP	(* parse field list *)
			IF sym = ident THEN first:= TRUE; ln:= newLine;
				LOOP	(* parse ident list *)
					IF sym = ident THEN Sym; CheckMark(vis);
						IF vis > internal THEN
							IF first THEN first:= FALSE;
								IF ln THEN Ln; Indent(2+recLevel) ELSE Char(" ") END
							ELSE Str(", ")
							END;
							Str(id); IF vis = externalR THEN Char("-") END
						END 
					ELSE err(errTypeDef)
					END;
					IF sym = comma THEN Sym ELSIF sym # ident THEN EXIT END
				END;	(* LOOP idents *)
				CheckSym(colon);
				IF ~first THEN Str(": "); ShowType
				ELSE SkipType
				END
			END;	(* IF *)
			IF sym = semicolon THEN
				IF ~first THEN Char(";") END; Sym
			ELSIF sym # ident THEN EXIT
			END;
		END;	(* LOOP *)
		*)
		Block("", TRUE)
	END RecordType;

	PROCEDURE ArrayType;	(* parses and writes an array type *)
	BEGIN
		Str("ARRAY");
		IF sym = of THEN	(* either dynamic or constant one dimensional *)
			ConstExpression
		ELSE
			LOOP CheckSysFlags;
				ConstExpression;
				IF sym = of THEN EXIT END;
				Sym; Char(",")
			END	(* LOOP *)
		END;
		Sym; Str("OF "); ShowType 
	END ArrayType;

	PROCEDURE PointerType;	(* parses and writes a pointer type *)
	BEGIN
		Str("POINTER"); CheckSysFlags;
		Str(" TO "); CheckSym(to);
		ShowType
	END PointerType;

	PROCEDURE FormalParameters;	(* parses and writes a paramater definition list of a procedure *)
		VAR endPos: LONGINT;
	BEGIN Str(" (");
		IF (sym = ident) OR (sym = var) THEN
			LOOP
				IF newLine THEN Copy(wPos, begPos) END;
				IF sym = var THEN Str("VAR "); Sym END;
				LOOP
					IF sym = ident THEN Sym; Str(id) ELSE err(errProc) END; 
					IF sym = comma THEN Sym ELSIF ~((sym = ident) OR (sym = var)) THEN EXIT END;
					Str(", ")
				END;
				Str(": "); CheckSym(colon); ShowType;
				IF sym = semicolon THEN Str("; "); Sym ELSIF ~((sym = ident) OR (sym = var)) THEN EXIT END
			END	(* LOOP *)
		END;
		IF newLine THEN Copy(wPos, begPos) END;
		Char(")"); CheckSym(rparen);
		IF sym = colon THEN Sym; Str(": ");
			IF sym = ident THEN qualident(endPos) END
		END
	END FormalParameters;

	PROCEDURE SkipFormalParameters;	(* skips a paramater definition list of a procedure *)
		VAR lev: INTEGER;
	BEGIN
		lev:= 1;
		LOOP Sym;
			IF sym = lparen THEN INC(lev)
			ELSIF sym = rparen THEN DEC(lev)
			END;
			IF (lev = 0) OR (sym > proc) THEN EXIT END
		END;	(* LOOP *)
		IF sym = rparen THEN Sym;
			IF sym = colon THEN Sym; SkipType END
		END
	END SkipFormalParameters;

	PROCEDURE ShowType;	(* parses and writes any type declaration *)
		VAR fix: Fixup;
	BEGIN curErr:= errTypeDef; wasRecord:= FALSE;
		IF sym < lparen THEN REPEAT Sym UNTIL sym >= lparen END;
		IF sym = ident THEN	(* remeber type so we can fix it later *)
			NEW(fix); fix.insert:= W.buf.len;
			COPY(id, fix.name); Sym; fix.qualified:= (sym = period);
			IF fix.qualified THEN Sym;	(* qulified identifier *)
				IF ~FindMod(fix.name) THEN err(errTypeDef) END;
				AppendCh(fix.name, ".");
				IF sym = ident THEN Append(fix.name, id); Sym
				ELSE err(errTypeDef)
				END
			END;
			fix.next:= fixups.next; fixups.next:= fix
		ELSIF sym = array THEN Sym; ArrayType
		ELSIF sym = record THEN INC(recLevel);
			RecordType; 
			IF newLine THEN Ln; Indent(1+recLevel) ELSE Char(" ") END; Str("END");
			(* CheckSym(end); *) DEC(recLevel); wasRecord:= TRUE
		ELSIF sym = pointer THEN Sym; PointerType
		ELSIF sym = proc THEN Str("PROCEDURE");
			Sym; CheckSysFlags;
			IF sym = lparen THEN Sym; FormalParameters END
		ELSE err(errType)
		END;
		LOOP
			IF (sym >= semicolon) & (sym <= end) OR (sym = rparen) OR (sym = eot) THEN EXIT END;
			err(errType); IF sym = ident THEN EXIT END;
			Sym
		END	(* LOOP *)
	END ShowType;

	PROCEDURE SkipType;	(* skips any type declaration *)
		VAR lev: INTEGER;
	BEGIN
		IF sym = ident THEN Sym;
			IF sym = period THEN Sym; IF sym = ident THEN Sym END END
		ELSIF sym = record THEN
			(* lev:= 1;
			LOOP Sym;
				IF sym = record THEN INC(lev)
				ELSIF sym = end THEN DEC(lev)
				END;
				IF (lev = 0) OR (sym > proc) THEN EXIT END
			END;	(* LOOP *)
			IF sym = end THEN Sym END
			*)
			INC(recLevel); Sym;
			IF sym = lparen THEN
				REPEAT Sym UNTIL (sym = rparen) OR (sym >= semicolon);
				IF sym = rparen THEN Sym END
			END;
			Block("", FALSE);
			DEC(recLevel)
		ELSIF sym = array THEN
			REPEAT Sym UNTIL sym = of; Sym; SkipType
		ELSIF sym = pointer THEN
			REPEAT Sym UNTIL sym = to; Sym; SkipType
		ELSIF sym = proc THEN Sym;
				IF sym = lparen THEN SkipFormalParameters END
		END;	(* IF *)
		LOOP
			IF (sym >= semicolon) & (sym <= end) OR (sym = rparen) OR (sym = eot) THEN EXIT END;
			IF sym = ident THEN EXIT END;
			Sym
		END	(* LOOP *)
	END SkipType;

	PROCEDURE TypeDef;	(* parses and writes a type declaration block *)
		VAR cmnt: Cmnt; obj: LocalIdent; vis: SHORTINT; first, newL, needsLn: BOOLEAN;
	BEGIN wasRecord:= FALSE; recLevel:= 0; first:= TRUE; needsLn:= NeedsLn(); cmnt:= cmnts.next; Sym;
		WHILE sym = ident DO newL:= newL OR newLine;
			Sym; CheckMark(vis);
			IF vis > internal THEN
				IF first THEN first:= FALSE; Keywords(cmnt, "TYPE", needsLn & (recLevel <= 0), TRUE); newL:= TRUE END;
				IF wasRecord & newL & NeedsLn() THEN Ln END;
				IF newL THEN newL:= FALSE; Ln; Indent(2 + recLevel) ELSE Char(" ") END;
				Identifier(id); Str(" = ");
				IF (sym = eql) OR (sym = becomes) THEN Sym; ShowType ELSE err(errType) END;
				Char(";");
			ELSE InsertIdent(id, type, obj); WHILE (sym # eql) & (sym < becomes) DO Sym END; Sym; SkipType
			END;
			CheckSym(semicolon)
		END	(* WHILE *)
	END TypeDef;

	(* ---------------- parse variable declaration block ----------------- *)

	PROCEDURE VarDef;	(* parses and writes a variable declaration block *)
		VAR cmnt: Cmnt; vis: SHORTINT; first, isVis, newL, needsLn, writeVar: BOOLEAN;
	BEGIN  first:= TRUE; needsLn:= NeedsLn(); cmnt:= cmnts.next;
		writeVar := sym = var;
		IF writeVar THEN Sym END;
		WHILE sym = ident DO isVis:= FALSE;
			LOOP	(* parse ident list *)
				IF sym = ident THEN newL:= newL OR newLine;
					Sym; CheckMark(vis);
					IF vis > internal THEN
						IF first THEN first:= FALSE;
							IF writeVar THEN Keywords(cmnt, "VAR", needsLn & (recLevel <= 0), TRUE) END;
							newL:= TRUE
						ELSIF isVis THEN Keywords(cmnt, ",", FALSE, FALSE)
						END;
						IF newL THEN newL:= FALSE; Ln; Indent(2+recLevel); cmnt := cmnts.next ELSE Char(" ") END;
						Identifier(id); IF vis = externalR THEN Char("-") END;
						isVis:= TRUE
					END
				ELSE err(errVar)
				END;
				IF ~(sym IN {comma, ident}) THEN EXIT END;
				CheckSym(comma)
			END;	(* LOOP idents *)
			CheckSym(colon);
			IF isVis THEN Str(": "); ShowType; IF (sym = semicolon) THEN Char(";") END
			ELSE SkipType
			END;
			IF (sym = semicolon) OR (recLevel = 0) THEN CheckSym(semicolon) END
		END	(* WHILE *)
	END VarDef;

	(* ---------------- parse procedure definition----------------- *)

	PROCEDURE ProcedureDeclaration;
		(* parses and writes/skips one procedure declaration. *)
		CONST LProc = 0; XProc = 1; IProc = 2; CProc = 3;
		VAR procId, self, typId: Name; vis, mode: SHORTINT; fwd, init, varPar: BOOLEAN;
	BEGIN fwd:= FALSE; init:= FALSE; mode:= LProc;
		IF (sym # ident) & (sym # string) & (sym # lparen) THEN
			IF sym = times THEN	(* not needed anymore *)
			ELSIF sym = arrow THEN fwd:= TRUE
			ELSIF sym = minus THEN mode:= CProc
			ELSIF sym = plus THEN mode:= IProc
			ELSIF sym = and THEN init := TRUE
			ELSE err(errProc)
			END;	(* IF *)
			Sym;
		END;	(* IF *)
		IF sym = lparen THEN	(* type bound procedure *)
			Sym; varPar:= (sym = var); IF varPar THEN Sym END;
			COPY (id, self); CheckSym(ident); CheckSym(colon);
			COPY (id, typId); CheckSym(ident); CheckSym(rparen);
			IF sym = ident THEN COPY(id, procId);
				Sym; CheckMark(vis);
				INC(level);
				IF FindIdent(typId) # NIL THEN vis:= internal END;
				IF vis # internal THEN
					Ln; Indent(1); Str("PROCEDURE (");
					IF varPar THEN Str("VAR ") END;
					Str(self); Str(" : "); Link(typId, FALSE); Str(") ");
					Identifier(procId);
					IF sym = lparen THEN Sym; FormalParameters END;
					Char(";")
				ELSIF (vis = internal) & (sym = lparen) THEN (*Sym;*) SkipFormalParameters
				END;
				CheckSym(semicolon);
				IF ~fwd THEN Block(procId, vis # internal) END;
				DEC(level)
			ELSE err(errProc)
			END
		ELSIF (sym = ident) OR (sym = string) THEN COPY(id, procId);
			Sym; CheckMark(vis);
			IF (vis # internal) & (mode = LProc) & ~fwd THEN mode:= XProc END;
			IF (level > 0) & (mode # LProc) THEN err(errProc); vis:= internal END;
			INC(level);
			IF (vis # internal) & (mode IN {XProc, CProc}) THEN
				Ln; Indent(1+recLevel*2);
				Str("PROCEDURE "); 
				IF init THEN Str("& ") END;
				Identifier(procId);
				IF sym = lparen THEN Sym; FormalParameters END;
				Char(";");
			ELSE	(* skip parameters *)
				IF sym = lparen THEN SkipFormalParameters END
			END;	(* IF *)
			(*IF mode = CProc THEN
				WHILE (sym # semicolon) & (sym < proc) DO Sym END;
			ELS*)
			IF  ~fwd THEN CheckSym(semicolon);
				curErr:= errProcEnd; Block(procId, mode = XProc)
			END;	(* IF *)
			DEC(level)
		END	(* IF *)
	END ProcedureDeclaration;

	(* ---------------- parse a module/procedure block ----------------- *)

	PROCEDURE Assert;	(* parses an ASSERT statement *)
		VAR beg, end: LONGINT;
	BEGIN Texts.SetFont(W, italic);
		beg:= Pos();
		LOOP
			WHILE ~(sym IN {comma, rparen}) DO Sym END;
			IF sym = comma THEN EXIT
			ELSE Sym;
				IF sym >= semicolon THEN EXIT END
			END
		END;
		end:= begPos;
		IF sym = comma THEN Sym;
			IF sym = number THEN Ln;
				Indent(2 + recLevel);
				IF (100 <= num) & (num < 110) THEN Str("(* precondition (")
				ELSIF (110 <= num) & (num < 120) THEN Str("(* invariant (")
				ELSIF (120 <= num) & (num < 130) THEN Str("(* postcondition (")
				ELSE Texts.SetFont(W, Fonts.Default); RETURN
				END;
				Int(num); Str("):"); Char(TAB); Copy(beg, end); Str(" *)");
			END
		END;
		Texts.SetFont(W, Fonts.Default)
	END Assert;

	PROCEDURE Block(blockId: Name; vis: BOOLEAN);	(* parses a module/procedure bolock *)
		VAR endcnt, len: LONGINT; nl: BOOLEAN;
	BEGIN
		nl := FALSE;
		LOOP
			IF sym = const THEN (*nl := TRUE;*) ConstDef END;
			IF sym = type THEN (* nl := TRUE;*) TypeDef END;
			IF (sym = var) OR ((sym = ident) & (blockId = "")) THEN (*nl := TRUE;*) VarDef END;
			IF sym = proc THEN
				IF level = 0 THEN
					IF nl THEN
						IF NeedsLn() THEN Ln END;
						nl := FALSE
					END;
					len:= W.buf.len
				END;
				Sym; ProcedureDeclaration;
				IF sym # proc THEN CheckSym(semicolon) END
			END;
			IF (sym < const) OR (sym > proc) THEN EXIT END
		END;	(* LOOP *)
		(*
		IF level = 0 THEN IF NeedsLn()THEN Ln END; len:= W.buf.len END;
		WHILE sym = proc DO
			Sym; ProcedureDeclaration;
			IF sym # proc THEN CheckSym(semicolon) END
		END;
		*)
		IF sym = code THEN
			Sym;
			LOOP
				WHILE sym < end DO Sym END;
				IF sym > with THEN err(curErr); EXIT
				ELSIF sym > end THEN Sym
				ELSE
					nl:= newLine; Sym;
					IF (sym = ident) OR (sym = string) THEN Sym;
						IF blockId = "" THEN id:= "" END
					ELSIF sym = semicolon THEN
						IF blockId = "" THEN id:= "" ELSE id:= "fault" END
					END;
					IF id = blockId THEN newLine := nl; EXIT END
				END
			END	(* LOOP *)
		ELSE
			IF sym = begin THEN Sym END;
			endcnt := 0;
			LOOP	(* skip to end of block *)
				WHILE (sym # assert) & (sym < end) DO Sym END;
				IF sym = assert THEN Sym; IF vis THEN Assert END
				ELSIF sym > with THEN err(curErr); EXIT
				ELSIF sym > end THEN Sym; INC(endcnt)
				ELSE	(* end *)
					nl:= newLine; Sym; DEC(endcnt);
					IF endcnt < 0 THEN
						IF (sym = ident) OR (sym = string) THEN Sym;
							IF blockId = "" THEN id:= "" END
						ELSIF sym IN {semicolon, end} THEN
							IF blockId = "" THEN id:= "" ELSE id:= "fault" END
						END;
						IF id = blockId THEN newLine := nl; EXIT END
					END
				END
			END	(* LOOP *)
		END;
		IF (blockId # "") & (level =  0) & (len # W.buf.len) THEN Ln END
	END Block;

	(* ---------------------- parse the import block ----------------------- *)

	PROCEDURE ImportBlock;	(* parses the import block of a module but does not write it *)
	BEGIN  Sym; 
		LOOP
			IF sym = ident THEN
				COPY(id, mod[mods].alias); COPY(id, mod[mods].real);
				mod[mods].exp:= FALSE; mod[mods].ln:= newLine;
				mod[mods-1].cmnts:= cmnts.next; cmnts.next:= NIL;
				Sym;
				IF sym = becomes THEN Sym;
					IF sym = ident THEN COPY(id, mod[mods].real); Sym ELSE err(errImp) END
				END;
				INC(mods)
			ELSE err(errImp)
			END;	(* IF *)
			IF sym = comma THEN Sym ELSIF sym # ident THEN EXIT END
		END;	(* LOOP *)
		WHILE (sym # end) & (sym < begin) DO Sym END
	END ImportBlock;

	(* ---------------- parse module definition ----------------- *)

	PROCEDURE Module(VAR modName: Name);
		VAR cmnt, curC: Cmnt;
	BEGIN level:= 0; mods:= 1;
		localIds.next:= NIL; fixups.next:= NIL; cmnts.next:= NIL;
		IF sym = module THEN Sym ELSE err(errMod) END ;
		IF sym = ident THEN
			COPY(id, modName);
			Str("DEFINITION "); Str(modName); Char(";");
			Sym; CheckSym(semicolon);
			mod[0].ln:= NeedsLn();
			Texts.Append(OutT, W.buf); Cmnts(0); cmnts.next:= NIL;
			importPos:= OutT.len;
			Ln; Str("END "); Str(modName); Char(".");
			Texts.Append(OutT, W.buf);
			IF sym = import THEN ImportBlock END;
			IF noerr THEN
				(* parse and write the module definition *)
				curErr:= errModEnd; Block(modName, FALSE);
				Texts.Insert(OutT, importPos, W.buf);
				IF noerr THEN
					cmnt:= cmnts.next;
					WHILE sym < eot DO Sym END;	(* write any comment after module end *)
					curC:= cmnts.next;
					WHILE curC # cmnt DO curC.insert:= curC.insert + OutT.len-importPos; curC:= curC.next END;
					Cmnts(importPos);	(* write exported comments *)
					Fixups(importPos);	(* write types *)
					Imports; Texts.Insert(OutT, importPos, W.buf)	(* write the import block *)
				END	(* IF *)
			END	(* IF *)
		ELSE err(ident)
		END;	(* IF *)
		localIds.next:= NIL; fixups.next:= NIL; cmnts.next:= NIL;	(* free chain -> garbage collcetor can collect them *)
	END Module;

	(* ---------------------- interface ----------------------- *)

	PROCEDURE GetText(): Texts.Text;	(* gets source text of marked document or viewer *)
		VAR T: Texts.Text; F: Display.Frame; L: Display.LocateMsg; M: Objects.LinkMsg; 
	BEGIN
		(* Returns the frame that is at X, Y on the display *)
		L.X := Oberon.Pointer.X; L.Y := Oberon.Pointer.Y; L.F := NIL; L.loc := NIL;
		Display.Broadcast(L); F := L.loc;
		(* Get the text *)
		IF F # NIL THEN
			M.id := Objects.get; M.name := "Model"; M.obj := NIL; M.res := -1; F.handle(F, M);
			IF (M.obj # NIL) & (M.obj IS Texts.Text) THEN T:= M.obj(Texts.Text) END
		END;
		IF T = NIL THEN NEW(T); Texts.Open(T, "") END;	(* open an empty text if there is none *)
		RETURN T
	END GetText;

	PROCEDURE MakeDef*(VAR mod: ARRAY OF CHAR; T: Texts.Text);	(* options = ["p"] *)
		VAR mT: Texts.Text; B: Texts.Buffer; name: ARRAY 128 OF CHAR; newName: Name; i: INTEGER; doPlain: BOOLEAN;
	BEGIN
		Str("reading "); NEW(ModT); 
		IF mod[0] = "*" THEN
			Char("*");
			Texts.Open(ModT, "");
			mT:= GetText(); NEW(B); Texts.OpenBuf(B);
			Texts.Save(mT, 0, mT.len, B); Texts.Append(ModT, B)
		ELSE
			COPY(mod, name); Str(name);
			Texts.Open(ModT, name)
		END;
		ToLog;
		
		(* init *)
		doPlain:= FALSE; doItalic:= FALSE; i:= 0;
		WHILE (options[i] # 0X) DO
			IF options[i] ="p" THEN doPlain:= TRUE
			ELSIF options[i] ="i" THEN doItalic:= TRUE
			END; INC(i)
		END;
		Texts.OpenReader(R, ModT, 0); lastPos:= -11;
		ch:= 0X; sym:= none; lines:= 0; noerr:= TRUE;
		OutT:= T;
		GetCh; Sym; Module(newName);

		(* finish *)
		IF noerr THEN
			IF doPlain THEN Texts.ChangeLooks(T, 0, T.len, {0}, Fonts.Default, 0, 0)  END;
			COPY(newName, mod)
		ELSE Texts.Delete(T, 0, T.len)
		END;
		Ln; ToLog
	END MakeDef;


	(* *************** Def to HTML convertion *************** *)

	PROCEDURE Convert2HTML(in, out: Texts.Text);
		VAR label: ARRAY 64 OF CHAR; R: Texts.Reader; BR: TextGadgets0.BackRd; fnt: Fonts.Font;
				obj: Objects.Object; i, l: INTEGER; bold, italic: BOOLEAN; ch, ch0: CHAR;
	
		PROCEDURE GetChar(VAR R: Texts.Reader; VAR ch: CHAR);
		BEGIN Texts.Read(R, ch); INC(l)
		END GetChar;

		PROCEDURE OutChar(ch: CHAR);
		BEGIN
			CASE ch OF
				CR: Ln; l:= 0
				| TAB: Char(" ")
				| "<": Str("&lt;")
				| "&": Str("&amp;")
				| "\": GetChar(R, ch); Char(ch)
				| "ä": Str("&auml;")
				| "ö": Str("&ouml;")
				| "ü": Str("&uuml;")
				| "Ä": Str("&Auml;")
				| "Ö": Str("&Ouml;")
				| "Ü": Str("&Uuml;")
			ELSE Char(ch)
			END	(* CASE *)
		END OutChar;

		PROCEDURE ConvertControl(obj: Objects.Object);
			VAR cmd: ARRAY 24 OF CHAR; i: INTEGER; A: Objects.AttrMsg;
		BEGIN
			A.id:= Objects.get; A.res:= -1; A.name:= "Name"; A.s:= ""; obj.handle(obj, A);
			IF (A.res >= 0) & (A.s # "") THEN
				Str("<A NAME= "); Char(22X); Str(A.s); Char(22X); Str("></A>");
			END;
			A.res:= -1; A.name:= "Cmd"; A.s:= ""; obj.handle(obj, A);
			IF (A.res >= 0) & (A.s # "") THEN
				Str("<A HREF= "); Char(22X);
				i:= 0; REPEAT cmd[i]:= A.s[i]; INC(i) UNTIL A.s[i] = " "; 
				cmd[i]:= A.s[i]; INC(i); cmd[i]:= 0X;
				(* skip options, if any *)
				IF A.s[i] = Oberon.OptionChar THEN
					WHILE A.s[i] # " " DO INC(i) END;
					INC(i)
				END;
				(* write HREF depending on command *)
				IF cmd = BookCmd THEN
					WHILE A.s[i] # "." DO Char(A.s[i]); INC(i) END;
					Str(htmlBookExt); Char("#");
					WHILE A.s[i] # tutDelimiter DO INC(i) END; INC(i);
					WHILE A.s[i] # 0X DO Char(A.s[i]); INC(i) END
				ELSIF cmd = GotoCmd THEN
					Char("#");
					WHILE A.s[i] # 0X DO Char(A.s[i]); INC(i) END
				ELSIF cmd = ModCmd THEN
					WHILE A.s[i] # 0X DO Char(A.s[i]); INC(i) END;
					Str(htmlExt)
				ELSIF cmd = ObjCmd THEN
					WHILE A.s[i] # "." DO Char(A.s[i]); INC(i) END;
					Str(htmlExt); Char("#");
					INC(i); WHILE A.s[i] # 0X DO Char(A.s[i]); INC(i) END
				END;
				Char(22X);Char(">"); Str(label); Str("</A>")
			END
		END ConvertControl;

		PROCEDURE ConvertObj(obj: Objects.Object);
		BEGIN
		END ConvertObj;

		PROCEDURE TestFont;
		BEGIN
			IF R.lib # fnt THEN
				IF bold THEN Str("</B>"); bold:= FALSE
				ELSIF italic THEN Str("</I>"); italic:= FALSE
				END;
				fnt:= R.lib(Fonts.Font);
				i:= 0; ch0:= fnt.name[0];
				WHILE (ch0 # 0X) & ("9" < ch0) DO INC(i); ch0:= fnt.name[i] END;
				WHILE (ch0 # 0X) & ("0" <= ch0) & (ch0 <= "9") DO INC(i); ch0:= fnt.name[i] END;
				ch0:= CAP(ch0);
				IF (ch0 = "B") OR (ch0 = "M") THEN Str("<B>"); bold:= TRUE
				ELSIF ch0 = "I" THEN Str("<I>"); italic:= TRUE
				END
			END
		END TestFont;

		PROCEDURE ParseComment(VAR R: Texts.Reader);
			CONST MaxChars = 75;
			VAR obj: Objects.Object; ch: CHAR;
		BEGIN GetChar(R, ch);
			LOOP
				IF R.eot THEN EXIT
				ELSIF ~(R.lib IS Fonts.Font) THEN
					R.lib.GetObj(R.lib, ORD(ch), obj);
					IF obj # NIL THEN ConvertObj(obj)END
				ELSE
					TestFont;
					IF (l > MaxChars) & ((ch = " ") OR (ch = TAB)) THEN Ln; l:= 0
					ELSIF ch = "(" THEN GetChar(R, ch);
						IF ch = "*" THEN Str("(*"); ParseComment(R)
						ELSE Char("("); OutChar(ch)
						END
					ELSIF ch = "*" THEN GetChar(R, ch);
						IF ch = ")" THEN Str("*)"); EXIT
						ELSE Char("*"); OutChar(ch)
						END
					ELSE OutChar(ch)
					END	(* IF *)
				END;	(* IF *)
				GetChar(R, ch)
			END	(* LOOP *)
		END ParseComment;

	BEGIN;
		(* write header of html document *)
		Str("<HTML>"); Ln; Str("<HEAD>"); Ln; Str("<! Generated by Watson >"); Ln;
		Texts.OpenReader(R, in, 0);
		REPEAT GetChar(R, ch) UNTIL ch = " ";
		Str("<TITLE> DEFINITION OF");
		WHILE ch # ";" DO Char(ch); GetChar(R, ch) END;
		Str("</TITLE>"); Ln;
		Str("</HEAD>"); Ln;
		Str("<BODY>"); Ln;
		Str("<PRE>"); Ln;
		
		(* begin of parsing definition file *)
		Texts.OpenReader(R, in, 0); GetChar(R, ch);
		bold:= FALSE; italic:= FALSE; fnt:= NIL; l:= 0;
		WHILE ~R.eot DO
			IF ~(R.lib IS Fonts.Font) THEN
				R.lib.GetObj(R.lib, ORD(ch), obj);
				IF obj # NIL THEN
					IF obj IS TextGadgets.Control THEN	(* a name-control *)
						TextGadgets0.OpenBackRd(BR, in, Texts.Pos(R)-1);
						i:= -1; REPEAT TextGadgets0.Read(BR, ch0); INC(i) UNTIL ch0 <= " ";
						Texts.Append(out, W.buf);
						ConvertControl(obj);
						Texts.Insert(out, out.len-i, W.buf)
					ELSE ConvertObj(obj)
					END
				END
			ELSE
				TestFont;
				IF R.col # TextCol THEN	(* save label *)
					i:= 0;
					REPEAT
						label[i]:= ch; INC(i);  GetChar(R, ch)
					UNTIL ~(R.lib IS Fonts.Font) OR (R.col = TextCol) OR (ch <= " ") OR (i = 63);
					label[i]:= 0X;
					IF ~(R.lib IS Fonts.Font) THEN	(* might be hyperlink *)
						R.lib.GetObj(R.lib, ORD(ch), obj);
						IF (obj # NIL) & (obj IS TextGadgets.Control) THEN ConvertControl(obj) END
					ELSE Str(label); Texts.OpenReader(R, in, Texts.Pos(R)-1)
					END
				ELSIF ch = "(" THEN GetChar(R, ch);
					IF ch = "*" THEN Str("(*"); ParseComment(R)
					ELSE Char("("); OutChar(ch)
					END
				ELSE OutChar(ch)
				END	(* IF *)
			END;
			GetChar(R, ch)
		END;
		IF bold THEN Str("</B>")
		ELSIF italic THEN Str("</I>")
		END;

		(* write end of html document *)
		Ln;
		Str("</PRE>"); Ln;
		Str("</BODY>"); Ln;
		Str("</HTML>"); Ln;
		Texts.Append(out, W.buf)
	END Convert2HTML;

	(* *************** WATSON MAIN PART *************** *)

	PROCEDURE GetArgs (VAR S: Texts.Scanner; VAR name: ARRAY OF CHAR);	(* reads in the given params *)
		VAR text: Texts.Text; beg, end, time: LONGINT; optS: SET; k: SHORTINT; A: Objects.AttrMsg;
				
		PROCEDURE SetOrder(str: ARRAY OF CHAR);
			VAR i: INTEGER; ch: CHAR;
		BEGIN i:= 0;
				WHILE str[i]#0X DO ch:= str[i];
					IF (ch = "T") & ~(TutTyp IN optS) THEN INCL(optS, TutTyp); order[k]:= ch; INC(k)
					ELSIF (ch = "D") & ~(DefTyp IN optS) THEN INCL(optS, DefTyp); order[k]:= ch; INC(k)
					ELSIF (ch = "M") & ~(ModTyp IN optS) THEN INCL(optS, ModTyp); order[k]:= ch; INC(k)
					ELSIF (ch = "S") & ~(SymTyp IN optS) THEN INCL(optS, SymTyp); order[k]:= ch; INC(k)
					ELSIF (ch = "C") & ~(CmdTyp IN optS) THEN INCL(optS, CmdTyp); order[k]:= ch; INC(k)
					END;
					INC(i)
				END
		END SetOrder;

	BEGIN k:= 0; optS:= {}; options:= ""; Watson0.options:= "";
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = Oberon.OptionChar) THEN Texts.Scan(S);	(* read in options *)
			IF S.class= Texts.Name THEN
				COPY(S.s, options); COPY(S.s, Watson0.options);	(* copy options to add them to Control-cmd *)
				SetOrder(S.s);
				Texts.Scan(S)
			END
		END;
		(* set default order *)
		A.id:= Objects.get; A.res:= -1; A.name:= "Value"; A.class:= Objects.Inval; oObj.handle(oObj, A);
		SetOrder(A.s);
		order[k]:= 0X; IF order = "" THEN COPY(DefaultOrder, order) END;

		(* now get name *)
		IF S.class = Texts.Char THEN
			IF S.c = "^" THEN	(* read name from text selection *)
				Oberon.GetSelection(text, beg, end, time);
				IF time>=0 THEN
					Texts.OpenScanner(S, text, beg); Texts.Scan(S) ELSE S.class := Texts.Inval
				END
			ELSIF S.c = "*" THEN	(* get info from an open text (must be a module) *)
				S.class:= Texts.Name; S.s[0]:= "*"; S.s[1]:= 0X
			END
		END;
		IF S.class = Texts.Name THEN COPY(S.s, name) ELSE name[0]:= 0X END;
		IF ~msgPrinted THEN PrintMsg END
	END GetArgs;

	PROCEDURE CheckDefName(h: Compress.Header; VAR stop: BOOLEAN);
	(* enumeartion proc. to check if def file is in archive *)
	BEGIN IF h.name = defName THEN stop:= TRUE; defFound:= TRUE END
	END CheckDefName;

	PROCEDURE Which(VAR mod: ARRAY OF CHAR; VAR typ: INTEGER);
	(* determines source file to get information from *)
		VAR F: Files.File; i: INTEGER;
		
		PROCEDURE OpenDef(mod: ARRAY OF CHAR);	(* tries to open an existing def file *)
			VAR res: INTEGER; A: Objects.AttrMsg;
		BEGIN Append(mod, defFileExt);
			F:= Files.Old(mod); IF F # NIL THEN RETURN END;

			(* check in archive, if there is one *)
			A.id:= Objects.get; A.name:= "Value"; A.class:= Objects.Inval; A.res:= -1; aObj.handle(aObj, A);
			IF A.res >= 0 THEN
				defFound:= FALSE; COPY(mod, defName);
				Compress.Enumerate(A.s, CheckDefName, FALSE, res);
				IF defFound THEN typ:= DefCTyp; F:= Files.Old(A.s) END
			END	(* IF *)
		END OpenDef;
		
		PROCEDURE OpenTutorial(VAR mod: ARRAY OF CHAR);
		(* tries to open the corresponding tutorial (refers to the link text) *)
			VAR tutName: ARRAY 64 OF CHAR; S: Texts.Scanner; i, j: INTEGER;
		BEGIN
			Texts.OpenScanner(S, linkText, 0); Texts.Scan(S); Texts.Scan(S);
			REPEAT
				IF S.class = Texts.Name THEN
					IF S.s = mod THEN Texts.Scan(S); COPY(S.s, tutName);
						i:= 0; j:= 0;
						WHILE tutName[i] # 0X DO IF tutName[i] = "." THEN j:= i END; INC(i) END;
						IF j = 0 THEN j:= i END;
						REPEAT DEC(i) UNTIL (i = 0) OR (tutName[i] = ".");
						tutName[j]:= 0X; Append(tutName, tutFileExt);
						F:= Files.Old(tutName);
						IF F # NIL THEN S.eot:= TRUE; COPY(tutName, mod);
							IF S.s[j] # 0X THEN
								i:= 0; REPEAT INC(i) UNTIL mod[i] = 0X; mod[i]:= tutDelimiter;
								REPEAT INC(j); INC(i); mod[i]:= S.s[j] UNTIL S.s[j] = 0X; 
							END
						ELSE Str("Tutorial '"); Str(tutName); Str("' does not exist"); Ln; ToLog
						END
					ELSE Texts.Scan(S)
					END
					ELSIF ~S.eot THEN Str("Watsons link text is corrupted"); Ln; ToLog; S.eot:= TRUE
				END
			UNTIL S.eot OR (F # NIL)
		END OpenTutorial;
		
		PROCEDURE OpenMod(VAR mod: ARRAY OF CHAR);	(* tries to open the mod file *)
			VAR fileName: ARRAY 64 OF CHAR; i, j, k: INTEGER; A: Objects.AttrMsg;
		BEGIN
			A.id:= Objects.get; A.name:= "Value"; A.res:= -1; mObj.handle(mObj, A);
			IF A.res < 0 THEN A.s:= "*.Mod" END;
			(* append prefix to file name if needed *)
			i:= 0; WHILE (A.s[i] # "*") & (A.s[i] # 0X) DO fileName[i]:= A.s[i]; INC(i) END;
			j:= i; k:= 0;
			IF A.s[i] = 0X THEN A.s[i]:= "."; A.s[i+1]:= "M"; A.s[i+2]:= "o"; A.s[i+3]:= "d"; A.s[i+4]:= 0X
			ELSE INC(i)
			END;
			(* append mod name to file name *)
			WHILE mod[k] # 0X DO fileName[j]:= mod[k]; INC(j); INC(k) END;
			(* append postfix to file name *)
			WHILE (A.s[i] # 0X) DO fileName[j]:= A.s[i]; INC(i); INC(j) END; fileName[j]:= 0X;
			(* try to open prefix+mod+postfix *)
			F:= Files.Old(fileName); IF F #NIL THEN COPY(fileName, mod); RETURN END;
			(* if there was a prefix, try to open mod+'.Mod' *)
			IF A.s[0] # "*" THEN i:= 0;
				WHILE mod[i] # 0X DO fileName[i]:= mod[i]; INC(i) END;
				fileName[i]:= "."; fileName[i+1]:= "M"; fileName[i+2]:= "o";
				fileName[i+3]:= "d"; fileName[i+4]:= 0X;
				F:= Files.Old(fileName); IF F #NIL THEN COPY(fileName, mod) END
			END
		END OpenMod;
		
		PROCEDURE OpenSym(mod: ARRAY OF CHAR);	(* tries to open the sym file *)
		BEGIN Append(mod, Modules.extension); F:= Files.Old(mod)
		END OpenSym;
		
		PROCEDURE OpenObj(mod: ARRAY OF CHAR);	(* tries to open the obj file *)
		BEGIN Append(mod, Modules.extension); F:= Files.Old(mod)
		END OpenObj;

	BEGIN
		(* first of all check if we have to check any file *)
		IF mod = "" THEN typ:= UndefTyp; RETURN END;
		
		(* yes we have, so check if we have a special case *)
		IF mod[0] = "*" THEN typ:= ModTyp; RETURN END;

		(* now check each file type (according to order) as long as F is not nil *)
		i:= 0;
		LOOP typ:= UndefTyp;
			IF order[i] = "T" THEN typ:= TutTyp; OpenTutorial(mod)	(* mod can be changed in OpenTut *)
			ELSIF order[i] = "D" THEN typ:= DefTyp; OpenDef(mod)	(* typ can be reset in OpenDef *)
			ELSIF order[i] = "M" THEN typ:= ModTyp; OpenMod(mod)	(* mod can be changed in OpenMod *)
			ELSIF order[i] = "S" THEN typ:= SymTyp; OpenSym(mod)
			ELSIF order[i] = "C" THEN typ:= CmdTyp; OpenObj(mod)
			END;
			IF (F # NIL) OR (order[i] = 0X) THEN EXIT END;
			INC(i)
		END;	(* LOOP *)
		IF F = NIL THEN
			Str("no information about '"); Str(mod); Str("' available"); Ln; ToLog
		END
	END Which;
		
	PROCEDURE JumpTo(F: TextGadgets.Frame; pos: LONGINT);
	(* set caret to position pos in text F.text and select objects name *)
		VAR BR: TextGadgets0.BackRd; ch: CHAR; S: Oberon.SelectMsg; C: Oberon.CaretMsg;
	BEGIN
		TextGadgets0.OpenBackRd(BR, F.text, pos);
		REPEAT TextGadgets0.Read(BR, ch) UNTIL ch <= " ";
		Objects.Stamp(S); S.id:= Oberon.set; S.F:= F; S.beg:= TextGadgets0.RdPos(BR)+1; S.end:= pos;
		S.text:= F.text; S.sel:= F; S.res:= -1;
		Display.Broadcast(S);
		Objects.Stamp(C); C.id:= Oberon.set; C.F:= F; C.pos:= pos; C.text:= F.text; C.car:= F; C.res:= -1;
		Display.Broadcast(C)
	END JumpTo;

	PROCEDURE FindMarker(T: Texts.Text; name: ARRAY OF CHAR): LONGINT;
	(* looks for a Control with given name and returns its position *)
		VAR F: Texts.Finder; obj: Objects.Object; pos: LONGINT; A: Objects.AttrMsg;
	BEGIN
		IF name # "" THEN
			Texts.OpenFinder(F, T, 0);
			WHILE ~F.eot DO
				pos := F.pos;
				Texts.FindObj(F, obj);
				IF (obj # NIL) THEN	(* 'ask' object about its name *)
					A.id := Objects.get; A.name := "Name"; A.class := Objects.Inval; A.res := -1; A.s := "";
					obj.handle(obj, A);
					IF (A.res >= 0) & (A.class = Objects.String) & (A.s = name) THEN RETURN pos END
				END
			END
		END;
		RETURN 0
	END FindMarker;

	PROCEDURE Open(mod: ARRAY OF CHAR; T: Texts.Text; pos: LONGINT): History;
	(* opens a TextDoc displaying the given text. Sets caret to position pos (if not 0) *)
		VAR D, oldD: Objects.Object; F: TextGadgets.Frame; h: History; A: Objects.AttrMsg;
		
		PROCEDURE IsWatsonDoc(D: Documents.Document): BOOLEAN;
			VAR i: INTEGER;
		BEGIN
			i:= 0; WHILE (D.name[i] # 0X) & (D.name[i] # ".") DO INC(i) END;
			RETURN (D.name[i] # 0X) & (D.name[i+1] = "D") & (D.name[i+2] = "e") & (D.name[i+3] = "f")
		END IsWatsonDoc;

	BEGIN h:= NIL;
		TextDocs.NewDoc; D:= Objects.NewObj(Documents.Document);
		IF D # NIL THEN
			oldD:= Desktops.CurDoc(Gadgets.context);
			IF oldD # NIL THEN
				A.id:= Objects.get; A.name:= DocNrAttr; A.res:= -1; oldD.handle(oldD, A);
				IF A.res = -1 THEN A.i:= -1 END
			ELSE A.i := -1
			END;
			h:= AddDocToHistory(A.i);
			WITH D: Documents.Document DO
				A.id:= Objects.set; A.name:= DocNrAttr; A.class:= Objects.Int; A.i:= h.nr; A.res:= -1;
				D.handle(D, A); 
				NEW(F); TextGadgets.Init(F(TextGadgets.Frame), T, FALSE);
				D.W:= 600; Documents.Init(D, F); D.handle:= DocHandler;
				COPY(mod, D.name);
				IF (oldD # NIL) & IsWatsonDoc(oldD(Documents.Document)) THEN Desktops.ReplaceCurrentDoc(D)
				ELSE Desktops.ShowDoc(D)
				END;
				IF pos > 0 THEN JumpTo(F, pos) END
			END
		END;
		RETURN h
	END Open;

	PROCEDURE StoreAscii(T: Texts.Text; name: ARRAY OF CHAR);
	(* stores text T to file name as ASCII-text *)
	VAR F: Files.File; R: Files.Rider; TR: Texts.Reader;
	BEGIN
		F:= Files.New(name);
		Files.Set(R, F, 0); Texts.OpenReader(TR, T, 0);
		Texts.Read(TR, ch);
		WHILE ~TR.eot DO
			IF ch = 0DX THEN ch:= 0AX END;
			Files.Write(R, ch);
			Texts.Read(TR, ch)
		END;
		Files.Register(F)
	END StoreAscii;

	(* *************** USER INTERFACE *************** *)

	(** command called by document's menu button 'Back' *)
	PROCEDURE Back*;	(** param:  none *)
		VAR D: Documents.Document; oldNr: LONGINT; h: History; A: Objects.AttrMsg;
	BEGIN
		D:= Desktops.CurDoc(Gadgets.context);
		IF D # NIL THEN
			A.id:= Objects.get; A.name:= DocNrAttr; A.res:= -1; D.handle(D, A);
			IF A.res # -1 THEN
				h:= GetDocSucc(A.i);
				IF h # NIL THEN
					oldNr:= lastHistNr; lastHistNr:= h.nr;	(* this is a hack *)
					Gadgets.Execute(h.cmd, Gadgets.executorObj, Gadgets.context, NIL, NIL);
					lastHistNr:= oldNr; history:= history.next	(* here is the 'antihack' *)
				END
			END
		END
	END Back;

	(** command called by control-gadegets in the generated def-texts (can only be used by Watson) *)
	PROCEDURE Goto*;	(** param:  object-name *)
		VAR S: Texts.Scanner; name: ARRAY 32 OF CHAR; obj: Objects.Object;
	BEGIN
		GetArgs(S, name);
		IF name # "" THEN
			obj:= Gadgets.executorObj;
			WHILE (obj # NIL) & ~(obj IS TextGadgets.Frame) DO obj := obj.dlink END;
			IF obj # NIL THEN
				WITH obj: TextGadgets.Frame DO
					JumpTo(obj, FindMarker(obj.text, name))
				END
			END
		END
	END Goto;

	(*L Watson.SHOWDEF *)
	(** user command to get best information about the given module *)
	PROCEDURE ShowDef*;	(** param: ["\"options] mod *)
		VAR S: Texts.Scanner; T: Texts.Text; h: History; mod, dummy: ARRAY 32 OF CHAR; typ: INTEGER;
	BEGIN
		GetArgs(S, mod); QualIdent(mod, dummy);
		Which(mod, typ);
		IF typ # UndefTyp THEN
			NEW(T); Texts.Open(T, "");
			IF typ = ModTyp THEN MakeDef(mod, T)
			ELSIF (typ MOD 10) = DefTyp THEN OpenDef(T, mod, (typ = DefCTyp));
			ELSIF typ = SymTyp THEN Watson0.ShowDef(mod, T)
			ELSIF typ = CmdTyp THEN Watson0.ShowCmd(mod, T)
			ELSE (* typ = Tut *) OpenTut(mod)
			END;
			IF T.len > 0 THEN
				Append(mod, titleExt); 
				h:= Open(mod, T, 0);
				MakeHistoryCmd(h, ModCmd, mod, "")
			END
		END
	END ShowDef;

	(*L Watson.SHOWOBJ *)
	(** user command to get best information about the given object in the specified module *)
	PROCEDURE ShowObj*;	(** param: ["\"options] mod.obj *)
		VAR S: Texts.Scanner; T: Texts.Text; h: History; mod, objName: ARRAY 32 OF CHAR; typ: INTEGER;
	BEGIN
		GetArgs(S, mod); QualIdent(mod, objName);
		Which(mod, typ);
		IF typ # UndefTyp THEN
			NEW(T); Texts.Open(T, "");
			IF typ = ModTyp THEN MakeDef(mod, T)
			ELSIF (typ MOD 10) = DefTyp THEN OpenDef(T, mod, (typ = DefCTyp))
			ELSIF typ = SymTyp THEN Watson0.ShowObj(mod, objName, T)
			ELSIF typ = CmdTyp THEN Watson0.ShowCmd(mod, T)
			ELSE (* typ = Tut *) OpenTut(mod)
			END;
			IF T.len > 0 THEN
				Append(mod, titleExt); 
				h:= Open(mod, T, FindMarker(T, objName));
				MakeHistoryCmd(h, ObjCmd, mod, objName)
			END
		END
	END ShowObj;

	PROCEDURE LookupObj*;
		VAR S: Texts.Scanner; mod: ARRAY 64 OF CHAR; D: Documents.Document;
	BEGIN	GetArgs(S, mod); 
		Texts.Scan(S);
		IF S.class IN {Texts.String, Texts.Name} THEN 
			Append(mod, ".Mod"); 
			D := Documents.Open(mod);
			IF (D # NIL) & (D.dsc # NIL) & (D.dsc IS TextGadgets0.Frame) THEN
				Desktops.ShowDoc(D);
				mod:='TextDocs.Search "'; Append(mod, S.s); Append(mod, '"');
				Gadgets.Execute(mod, D, D.dlink, NIL, NIL);
			ELSE Str(mod); Str(" not found"); Ln; ToLog
			END
		END
	END LookupObj;

	(*L Watson.MAKEDEFS *)
	(** user command to make definition files of given modules (if 'c' in options -> converts defs to HTML docs) *)
	PROCEDURE MakeDefs*;	(** param: ["\"options] mods *)
		VAR S: Texts.Scanner; T, HT: Texts.Text; F: Files.File; mod: ARRAY 32 OF CHAR;
				l: LONGINT; conv: BOOLEAN;
	BEGIN
		GetArgs(S, mod);
		l:= 0; conv:= FALSE; WHILE ~conv & (options[l] # 0X) DO conv:= (options[l] = "c"); INC(l) END;
		NEW(T); Texts.Open(T, "");
		WHILE S.class = Texts.Name DO
			Oberon.Collect;
			COPY(S.s, mod); MakeDef(mod, T);
			IF T.len > 0 THEN
				IF conv THEN NEW(HT); Texts.Open(HT, "");
					Convert2HTML(T, HT); T:= HT; Append(mod, htmlExt);
				ELSE Append(mod, titleExt)
				END;
				Str("writing "); Str(mod); Ln; ToLog;
				IF conv THEN StoreAscii(T, mod)
				ELSE F:= Files.New(mod); Texts.Store(T, F, 0, l); Files.Register(F)
				END;
				Texts.Open(T, "")
			END;
			Texts.Scan(S)
		END
	END MakeDefs;

	(*L Watson.CONVERTDEFS *)
	(** user command to convert definition files to HTML documents *)
	PROCEDURE ConvertDefs*;	(** param: ["\"options] defs *)
		VAR S: Texts.Scanner; T, outT: Texts.Text; F: Files.File; l: LONGINT; text: ARRAY 64 OF CHAR;
	BEGIN
		GetArgs(S, text); NEW(T); NEW(outT);
		WHILE S.class = Texts.Name DO
			COPY(S.s, text); 
			F:= Files.Old(text);
			l:= 3; REPEAT INC(l) UNTIL text[l] = 0X; text[l-4]:= 0X;
			OpenDef(T, text, F = NIL);
			IF T.len > 0 THEN Texts.Open(outT, "");
				Convert2HTML(T, outT); Append(text, htmlExt);
				Str("writing "); Str(text); Ln; ToLog;
				StoreAscii(outT, text);
			ELSE Char("'"); Str(S.s); Str("' not found"); Ln; ToLog
			END;
			Texts.Scan(S)
		END
	END ConvertDefs;


	(* *************** SOME GLOBAL INITS *************** *)

	PROCEDURE GetPublicObjects;	(* set public opjects (creates new if not found) *)
		VAR obj: Objects.Object; string: ARRAY 64 OF CHAR; A: Objects.AttrMsg;
		
		PROCEDURE GetObj(name: ARRAY 32 OF CHAR; VAR obj: Objects.Object);
			VAR L: Objects.LinkMsg;
		BEGIN
			obj:= Gadgets.FindPublicObj(name);
			IF obj # NIL THEN
				L.id:= Objects.get; L.res:= -1; L.name:= "Model"; obj.handle(obj, L); obj:= L.obj;
				IF obj = NIL THEN
					Str("public object '"); Str(name); Str("' has no model"); Ln; ToLog
				END
			ELSE Str("public object '"); Str(name); Str("' not found"); Ln; ToLog
			END
		END GetObj;
				
	BEGIN
		Gadgets.GetAlias("String", string);
		(* get default order *)
		GetObj(orderObj, oObj);
		IF oObj = NIL THEN oObj:= Gadgets.CreateObject(string);
			A.id:= Objects.set; A.name:= "Value"; A.res:= -1; A.class:= Objects.String;
			A.s:= DefaultOrder; oObj.handle(oObj, A)
		END;
		(* get link text *)
		GetObj(tutorialObj, obj);
		IF (obj = NIL) OR ~(obj IS Texts.Text) THEN NEW(linkText); Texts.Open(linkText, "")
		ELSE linkText:= obj(Texts.Text)
		END;
		(* get def-archive name *)		
		GetObj(archiveObj, aObj);
		IF aObj = NIL THEN aObj:= Gadgets.CreateObject(string) END;
		(* get mod file name format *)
		GetObj(modfileObj, mObj);
		IF mObj = NIL THEN mObj:= Gadgets.CreateObject(string);
			A.id:= Objects.set; A.name:= "Value"; A.res:= -1; A.class:= Objects.String;
			A.s:= "*.Mod"; mObj.handle(mObj, A)
		END;
	END GetPublicObjects;

BEGIN
	msgPrinted:= FALSE; history:= NIL; lastHistNr:= 0;
	Texts.OpenWriter(W); italic:= Fonts.This("Oberon10i.Scn.Fnt");
	GetPublicObjects
END Watson.
