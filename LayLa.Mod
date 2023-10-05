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

MODULE LayLa;	(** portable *)	(*	Jörg Derungs, 31.7.1996	*)

IMPORT LayLaS, Layouts, Objects, Texts, Gadgets, Oberon, Panels, Documents, Desktops, PanelDocs;

CONST param = 1;
			outermost = 2;

VAR sym : INTEGER;
		curtext : Texts.Text;
		W : Texts.Writer;

PROCEDURE String (str: ARRAY OF CHAR);
BEGIN
	Texts.WriteString(W, str); Texts.WriteLn(W);
	Texts.Append(Oberon.Log, W.buf)
END String;

PROCEDURE ^Eval (flag : INTEGER) : Layouts.Node;

PROCEDURE Size (outermost : BOOLEAN) : Layouts.Node;
VAR min, factor : INTEGER;
BEGIN
	IF sym = LayLaS.Int THEN min := SHORT (LayLaS.int); LayLaS.Get (sym)
	ELSIF sym = LayLaS.Default THEN min := MIN (INTEGER); LayLaS.Get (sym)
	ELSIF sym # LayLaS.lbrak THEN min := 0; LayLaS.Mark (LayLaS.Pos (), "Integer expected")
	END;
	IF sym = LayLaS.lbrak THEN	LayLaS.Get (sym);
		IF sym = LayLaS.Int THEN factor := SHORT (LayLaS.int); LayLaS.Get (sym)
		ELSIF sym = LayLaS.rbrak THEN factor := 1
		ELSE LayLaS.Mark (LayLaS.Pos (), "Integer expected") END;
		IF sym # LayLaS.rbrak THEN LayLaS.Mark (LayLaS.Pos (), "']' expected")
		ELSIF ~outermost THEN LayLaS.Get (sym) END
	ELSE factor := 0 END;
	RETURN Layouts.NewSize (min, factor)
END Size;

PROCEDURE Def () : Layouts.Node;
VAR name : Objects.Name;
		node : Layouts.Node;
BEGIN	LayLaS.Get (sym);
	IF sym # LayLaS.Ident THEN LayLaS.Mark (LayLaS.Pos (), "identifier expected"); name[0] := 0X
	ELSE COPY (LayLaS.ident, name); LayLaS.Get (sym) END;
	IF sym # LayLaS.close THEN node := Eval (0) ELSE node := NIL END;
	IF name # "" THEN node := Layouts.NewDef (name, node) END;
	RETURN node;
END Def;

PROCEDURE Set () : Layouts.Node;
VAR name : Objects.Name;
		node : Layouts.Node;
BEGIN	LayLaS.Get (sym);
	IF sym # LayLaS.Ident THEN LayLaS.Mark (LayLaS.Pos (), "identifier expected"); name[0] := 0X
	ELSE COPY (LayLaS.ident, name); LayLaS.Get (sym) END;
	IF sym = LayLaS.equal THEN LayLaS.Get (sym); LayLaS.Mark (LayLaS.Pos (), "no '=' in SET") END;
	node := Eval (0);
	IF (name # "") & (node # NIL) THEN node := Layouts.NewSet (name, node) END;
	RETURN node;
END Set;

PROCEDURE SetList (op : INTEGER; omit : BOOLEAN) : Layouts.Node;
VAR list, node : Layouts.Node;
BEGIN	IF ~omit THEN LayLaS.Get (sym) END;
	list := Layouts.NewNode (op);
	WHILE sym # LayLaS.close DO
		node := Eval (0);
		IF (node # NIL) & ((node.id = Layouts.Set) OR (node.id = Layouts.Ident)) THEN Layouts.Insert (list, node)
		ELSE LayLaS.Mark (LayLaS.Pos (), "SET operator expected") END
	END;
	RETURN list
END SetList;

PROCEDURE Copy (deep : BOOLEAN) : Layouts.Node;
VAR node : Layouts.Node;
BEGIN	LayLaS.Get (sym);
	IF sym # LayLaS.Qualident THEN
		LayLaS.Mark (LayLaS.Pos (), "Lib.Obj expected");
		node := Layouts.NewObject ("")
	ELSE node := Layouts.CopyPublicObj (LayLaS.ident, deep); LayLaS.Get (sym) END;
	WHILE sym # LayLaS.close DO Layouts.Insert (node, Eval (0)) END;
	RETURN node
END Copy;

PROCEDURE SetParams (node : Layouts.Node);		(*	sym # LayLaS.close	*)
VAR params, dmy : Layouts.Node;
BEGIN
	params := Eval (param);
	IF (params # NIL) & ((params.id = Layouts.Params) OR (params.id = Layouts.Ident))
	THEN Layouts.SetParams (node, params)
	ELSE LayLaS.Mark (LayLaS.Pos (), "PARAMS expected") END;
	IF sym # LayLaS.close THEN
		LayLaS.Mark (LayLaS.Pos (), "')' expected");
		REPEAT dmy := Eval (0) UNTIL sym = LayLaS.close
	END
END SetParams;

PROCEDURE Include () : Layouts.Node;
VAR node : Layouts.Node;
		oldpos : LONGINT;
		oldtext : Texts.Text;
BEGIN	LayLaS.Get (sym);
	IF (sym # LayLaS.Qualident) & (sym # LayLaS.Ident) THEN
		LayLaS.Mark (LayLaS.Pos (), "filename expected"); node := Layouts.NewObject ("")
	ELSE
		oldpos := LayLaS.Pos ()-1;	oldtext := curtext;
		NEW (curtext); Texts.Open (curtext, LayLaS.ident);
		IF curtext.len = 0 THEN LayLaS.Mark (LayLaS.Pos (), "file not found or empty");
			node := Layouts.NewObject ("")
		ELSE
			LayLaS.OpenText (curtext, 0);	LayLaS.Get (sym);	node := Eval (outermost);
			curtext := oldtext;	LayLaS.OpenText (curtext, oldpos)
		END;
		LayLaS.Get (sym)
	END;
	IF sym # LayLaS.close THEN SetParams (node) END;
	RETURN node
END Include;

PROCEDURE New () : Layouts.Node;
VAR node : Layouts.Node;
		alias : ARRAY 64 OF CHAR;
BEGIN	LayLaS.Get (sym);
	IF sym = LayLaS.Virtual THEN
		node := Layouts.NewObject (""); LayLaS.Get (sym);
		WHILE sym # LayLaS.close DO Layouts.Insert (node, Eval (0)) END
	ELSIF sym = LayLaS.Ident THEN
		Gadgets.GetAlias (LayLaS.ident, alias);
		IF alias = "" THEN
			node := Layouts.NewInstance (LayLaS.ident);	LayLaS.Get (sym);
			IF sym # LayLaS.close THEN SetParams (node) END;
		ELSE node := Layouts.NewObject (LayLaS.ident); LayLaS.Get (sym);
			WHILE sym # LayLaS.close DO Layouts.Insert (node, Eval (0)) END
		END
	ELSIF sym = LayLaS.Qualident THEN
		node := Layouts.NewObject (LayLaS.ident); LayLaS.Get (sym);
		WHILE sym # LayLaS.close DO Layouts.Insert (node, Eval (0)) END
	ELSE LayLaS.Mark (LayLaS.Pos (), "NewProc expected"); node := Layouts.NewObject ("")
	END;
	RETURN node
END New;

PROCEDURE MakeObj (NewObj : PROCEDURE (NewProc : ARRAY OF CHAR) : Layouts.Node) : Layouts.Node;
VAR node : Layouts.Node;
BEGIN	LayLaS.Get (sym);
	IF sym = LayLaS.Virtual THEN
		node := NewObj (""); LayLaS.Get (sym);
		WHILE sym # LayLaS.close DO Layouts.Insert (node, Eval (0)) END
	ELSIF (sym = LayLaS.Ident) OR (sym = LayLaS.Qualident) THEN
		node := NewObj (LayLaS.ident); LayLaS.Get (sym);
		WHILE sym # LayLaS.close DO Layouts.Insert (node, Eval (0)) END
	ELSE LayLaS.Mark (LayLaS.Pos (), "NewProc expected"); node := NewObj ("")
	END;
	RETURN node
END MakeObj;

PROCEDURE Break () : Layouts.Node;
VAR break, node : Layouts.Node;
BEGIN	LayLaS.Get (sym);
	break := Layouts.NewBreak ();
	node := Eval (0);
	IF (node = NIL) OR
		((node.id # Layouts.Obj) & (node.id # Layouts.Break)
		& (node.id # Layouts.Ident) & (node.id # Layouts.Instance))
	THEN LayLaS.Mark (LayLaS.Pos (), "Object expected"); node := Layouts.NewObject ("") END;
	Layouts.Insert (break, node);
	IF sym # LayLaS.close THEN
		LayLaS.Mark (LayLaS.Pos (), "')' expected");
		REPEAT node := Eval (0) UNTIL sym = LayLaS.close
	END;
	RETURN break
END Break;

PROCEDURE Span () : Layouts.Node;
VAR span, node : Layouts.Node;
		rows, cols : INTEGER;
BEGIN	LayLaS.Get (sym);
	IF sym = LayLaS.Int THEN rows := SHORT (LayLaS.int)
	ELSE LayLaS.Mark (LayLaS.Pos (), "Integer expected"); rows := 0 END;
	LayLaS.Get (sym);
	IF sym = LayLaS.Int THEN cols := SHORT (LayLaS.int)
	ELSE LayLaS.Mark (LayLaS.Pos (), "Integer expected"); cols := 0 END;
	LayLaS.Get (sym);
	span := Layouts.NewSpan (rows, cols);
	node := Eval (0);
	IF (node = NIL) OR
		((node.id # Layouts.Obj) & (node.id # Layouts.Break)
		& (node.id # Layouts.Ident) & (node.id # Layouts.Instance))
	THEN LayLaS.Mark (LayLaS.Pos (), "Object expected"); node := Layouts.NewObject ("") END;
	Layouts.Insert (span, node);
	IF sym # LayLaS.close THEN
		LayLaS.Mark (LayLaS.Pos (), "')' expected");
		REPEAT node := Eval (0) UNTIL sym = LayLaS.close
	END;
	RETURN span
END Span;

PROCEDURE Config () : Layouts.Node;
VAR config : Layouts.Node;
BEGIN
	LayLaS.Get (sym);
	config := Layouts.NewConfig ();
	WHILE sym # LayLaS.close DO
		Layouts.Insert (config, Eval (0))
	END;
	RETURN config
END Config;

PROCEDURE Eval (flag : INTEGER) : Layouts.Node;
VAR node : Layouts.Node;
		Ident : ARRAY 64 OF CHAR;
BEGIN	node := NIL;
	CASE sym OF
		LayLaS.String : node := Layouts.NewString (LayLaS.s); IF ~(flag = outermost) THEN LayLaS.Get (sym) END
		| LayLaS.Int, LayLaS.Default, LayLaS.lbrak : node := Size (flag = outermost)
		| LayLaS.Real : node := Layouts.NewReal (LayLaS.real); IF ~(flag = outermost) THEN LayLaS.Get (sym) END
		| LayLaS.Char : node := Layouts.NewChar (LayLaS.char); IF ~(flag = outermost) THEN LayLaS.Get (sym) END
		| LayLaS.Bool : node := Layouts.NewBool (LayLaS.bool); IF ~(flag = outermost) THEN LayLaS.Get (sym) END
		| LayLaS.Left..LayLaS.Vert : node := Layouts.NewFormat (sym); IF ~(flag = outermost) THEN LayLaS.Get (sym) END
		| LayLaS.Qualident : node := Layouts.WrappedObject (Gadgets.FindPublicObj (LayLaS.ident));
													IF ~(flag = outermost) THEN LayLaS.Get (sym) END
		| LayLaS.Virtual : node := Layouts.NewObject (""); IF ~(flag = outermost) THEN LayLaS.Get (sym) END
		| LayLaS.Ident : COPY (LayLaS.ident, Ident); LayLaS.Get (sym);
				IF sym = LayLaS.equal THEN
					LayLaS.Get (sym); node := Eval (flag);
					IF node # NIL THEN node := Layouts.NewSet (Ident, node) END
				ELSE node := Layouts.NewIdent (Ident) END
		| LayLaS.open :
				LayLaS.Get (sym);
				CASE sym OF
					LayLaS.Config : node := Config ()
					| LayLaS.Deep : node := Copy (TRUE)
					| LayLaS.Shallow : node := Copy (FALSE)
					| LayLaS.Include : node := Include ()
					| LayLaS.New : node := New ()
					| LayLaS.HList : node := MakeObj (Layouts.NewHList)
					| LayLaS.VList : node := MakeObj (Layouts.NewVList)
					| LayLaS.Table : node := MakeObj (Layouts.NewTable)
					| LayLaS.Place : node := MakeObj (Layouts.NewPlace)
					| LayLaS.Break : node := Break ()
					| LayLaS.Span : node := Span ()
					| LayLaS.Def : node := Def ()
					| LayLaS.Set : node := Set ()
					| LayLaS.Params : node := SetList (Layouts.Params, FALSE)
					| LayLaS.Layout : node := SetList (Layouts.Layout, FALSE)
					| LayLaS.Attributes : node := SetList (Layouts.Attributes, FALSE)
					| LayLaS.Links : node := SetList (Layouts.Links, FALSE)
					| LayLaS.Ident :
							IF flag = param THEN node := SetList (Layouts.Params, TRUE)
							ELSE node := SetList (Layouts.Layout, TRUE) END
				ELSE LayLaS.Mark (LayLaS.Pos (), "unexpected operator")
				END;
				IF sym # LayLaS.close THEN LayLaS.Mark (LayLaS.Pos (), "')' expected")
				ELSIF ~(flag = outermost) THEN LayLaS.Get (sym) END;
	ELSE
		LayLaS.Mark (LayLaS.Pos(), "unexpected symbol");
		IF (sym # LayLaS.close) & ~(flag = outermost) THEN LayLaS.Get (sym) END
	END;
	RETURN node;
END Eval;

PROCEDURE ParseText* (text : Texts.Text; pos : LONGINT) : Objects.Object;
VAR node : Layouts.Node;
BEGIN
	curtext := text;
	LayLaS.Init; LayLaS.OpenText (curtext, pos); LayLaS.Get (sym);
	node := Eval (outermost);
	IF ~LayLaS.error THEN RETURN Layouts.Realize (node) ELSE RETURN NIL END
END ParseText;

PROCEDURE ParseString* (str : ARRAY OF CHAR; pos : LONGINT) : Objects.Object;
BEGIN
	Texts.WriteString (W, str);
	NEW (curtext); Texts.Open (curtext, ""); Texts.Append (curtext, W.buf);
	RETURN ParseText (curtext, pos)
END ParseString;

PROCEDURE GetText (VAR T : Texts.Text; VAR beg : LONGINT);
VAR s : Texts.Scanner;
		end, time : LONGINT;
		Name : ARRAY 64 OF CHAR;
BEGIN
	Texts.OpenScanner (s, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan (s);
	IF (s.class = Texts.Char) & (s.c = '^') THEN Oberon.GetSelection (T, beg, end, time);
		IF time < 0 THEN String ("no selection"); RETURN END
	ELSIF (s.class = Texts.Char) & (s.c = '*') THEN
		T := Oberon.MarkedText()
	ELSIF (s.class = Texts.Char) & (s.c = '@') THEN	Texts.Scan (s);
		IF s.class = Texts.Name THEN COPY (s.s, Name)
		ELSE String ("filename missing"); Name[0] := 0X END;
		NEW (T); Texts.Open (T, Name); beg := 0;
	ELSE T := Oberon.Par.text; beg := Oberon.Par.pos
	END;
END GetText;

PROCEDURE SplitName(name: ARRAY OF CHAR; VAR libname, objname: ARRAY OF CHAR);
	VAR i, j, k: INTEGER;
BEGIN
	i := 0; j := 0;
	WHILE (name[i] # ".") & (name[i] # 0X) DO libname[j] := name[i]; INC(j); INC(i); END;
	IF name[i] = 0X THEN RETURN END;
	libname[j] := 0X; k := j; INC(i); j := 0;
	WHILE (name[i] # " ") & (name[i] # 0X) DO objname[j] := name[i]; INC(j); INC(i); END;
	objname[j] := 0X;
	libname[k] := "."; libname[k+1] := "L"; libname[k+2] := "i"; libname[k+3] := "b"; libname[k+4] := 0X
END SplitName;

PROCEDURE Insert*;
(**
		Insert reads the specified layout text and inserts the new gadget at the caret position.

		 Insert ^		read from latest selection
		 Insert *		read from marked viewer / TextGadget
		 Insert @ file	read from file
		 Insert (NEW object)
*)
VAR T : Texts.Text;
		pos : LONGINT;
		obj : Objects.Object;
BEGIN
	GetText (T, pos);
	obj := ParseText (T, pos);
	Gadgets.Integrate(obj)
END Insert;

PROCEDURE OpenAsDoc*;
(**
		OpenAsDoc reads the specified layout text and opens the new gadget as a document. If the top most
		gadget is not a Panel, the created gadget(s) are inserted in a new PanelDoc. 

		 OpenAsDoc ^		read from latest selection
		 OpenAsDoc *		read from marked viewer / TextGadget
		 OpenAsDoc @ file	read from file
		 OpenAsDoc (NEW object)
*)
VAR T : Texts.Text;
		pos : LONGINT;
		obj : Objects.Object;
		D: Documents.Document;
		P: Panels.Panel;
		x, y, w, h, cnt: INTEGER;
BEGIN
	GetText (T, pos);
	obj := ParseText (T, pos);
	D := NIL;
	IF obj IS Panels.Panel THEN
		WITH obj: Gadgets.Frame DO
			NEW(D);
			D.Load := PanelDocs.LoadPanel; D.Store := PanelDocs.StorePanel; D.handle := PanelDocs.DocHandle;
			D.name := ""; D.W := obj.W; D.H := obj.H;
			Documents.Init(D, obj)
		END
	ELSIF obj IS Gadgets.Frame THEN
		WITH obj: Gadgets.Frame DO
			NEW(D);
			Panels.BoundingBox(obj, x, y, w, h, cnt);
			PanelDocs.InitDoc(D, w + 12, h+12);
			P := D.dsc(Panels.Panel);
			P.do.InsertFrames(P, 6, -h - 6, obj)
		END
	END;
	IF D # NIL THEN Desktops.ShowDoc(D) END
END OpenAsDoc;

PROCEDURE AddToLibrary*;
(**
		AddToLibrary reads the specified layout text and inserts the gadget in the library L with name O. If the
		top most container is VIRTUAL, only the first gadget returned is inserted.

		 AddToLibrary L.O ^		read from latest selection
		 AddToLibrary L.O *		read from marked viewer / TextGadget
		 AddToLibrary L.O @ file	read from file
		 AddToLibrary L.O (NEW object)
*)
VAR T : Texts.Text;
		pos : LONGINT;
		old, obj : Objects.Object;
		lib: Objects.Library;
		libname, objname: ARRAY 64 OF CHAR;
		ref: INTEGER;
		S: Texts.Scanner;
		B: Objects.BindMsg;
BEGIN
	Texts.OpenScanner (S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan (S);
	IF S.class = Texts.Name THEN
		SplitName(S.s, libname, objname);
		IF (libname # "") & (objname # "") THEN
			lib:= Objects.ThisLibrary(libname);
			Oberon.Par.pos := Texts.Pos(S);
			GetText (T, pos);
			obj := ParseText (T, pos);
			obj.slink := NIL;
			Objects.GetRef(lib.dict, objname, ref);
			IF ref >= 0 THEN lib.GetObj(lib, ref, old) ELSE old:= NIL END;
			IF old = NIL THEN (* obj does not exists yet *)
				lib.GenRef(lib, ref);
				IF ref < 0 THEN String("Library is full, sorry"); RETURN END;
				String(" adding object")
			ELSE String(" replacing object '")
			END;
			lib.PutObj(lib, ref, obj); Objects.PutName(lib.dict, ref, objname);
			B.lib:= lib; obj.handle(obj, B)
		ELSE
			String("no name specified")
		END
	ELSE
		String("no name specified")
	END
END AddToLibrary;

BEGIN
	Texts.OpenWriter (W)
END LayLa.


