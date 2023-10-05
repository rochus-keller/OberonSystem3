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

MODULE LayLa2;	(** portable *)

IMPORT LayLa2S, Layouts, Objects, Texts, Out, Gadgets, Oberon;

CONST debug = FALSE;
			outermost = 1;


VAR sym : INTEGER;
		curtext : Texts.Text;
		W : Texts.Writer;

PROCEDURE ^Eval (flag : INTEGER) : Layouts.Node;

PROCEDURE Size (outermost : BOOLEAN) : Layouts.Node;
VAR min, factor : INTEGER;
BEGIN
	IF sym = LayLa2S.Int THEN min := SHORT (LayLa2S.int); LayLa2S.Get (sym)
	ELSIF sym = LayLa2S.Default THEN min := MIN (INTEGER); LayLa2S.Get (sym)
	ELSIF sym # LayLa2S.lbrak THEN min := 0; LayLa2S.Mark (LayLa2S.Pos (), "Integer expected")
	END;
	IF sym = LayLa2S.lbrak THEN	LayLa2S.Get (sym);
		IF sym = LayLa2S.Int THEN factor := SHORT (LayLa2S.int); LayLa2S.Get (sym)
		ELSIF sym = LayLa2S.rbrak THEN factor := 1
		ELSE LayLa2S.Mark (LayLa2S.Pos (), "Integer expected") END;
		IF sym # LayLa2S.rbrak THEN LayLa2S.Mark (LayLa2S.Pos (), "']' expected")
		ELSIF ~outermost THEN LayLa2S.Get (sym) END
	ELSE factor := 0 END;
	RETURN Layouts.NewSize (min, factor)
END Size;

PROCEDURE Def (flag : INTEGER) : Layouts.Node;
VAR name : Objects.Name;
		node : Layouts.Node;
BEGIN	LayLa2S.Get (sym);
	IF sym # LayLa2S.Ident THEN LayLa2S.Mark (LayLa2S.Pos (), "identifier expected"); name[0] := 0X
	ELSE COPY (LayLa2S.ident, name); LayLa2S.Get (sym) END;
	IF debug THEN Out.String ("Def"); Out.Int (sym, 5); Out.Ln END;
	IF sym = LayLa2S.equal THEN LayLa2S.Get (sym); node := Eval (flag) ELSE node := NIL END;
	IF name # "" THEN node := Layouts.NewDef (name, node) END;
	RETURN node;
END Def;

PROCEDURE SetList (op : INTEGER) : Layouts.Node;
VAR list, node : Layouts.Node;
BEGIN	LayLa2S.Get (sym);
	IF debug THEN Out.String ("SetList"); Out.Int (sym, 5); Out.Ln END;
	list := Layouts.NewNode (op);
	WHILE sym = LayLa2S.Ident DO
		node := Eval (0);
		IF (node # NIL) & ((node.id = Layouts.Set) OR (node.id = Layouts.Ident)) THEN Layouts.Insert (list, node)
		ELSE LayLa2S.Mark (LayLa2S.Pos (), "'Ident = Value' expected") END
	END;
	RETURN list
END SetList;

PROCEDURE Copy (deep : BOOLEAN) : Layouts.Node;
VAR node : Layouts.Node;
BEGIN	LayLa2S.Get (sym);
	IF debug THEN Out.String ("Copy"); Out.Int (sym, 5); Out.Ln END;
	IF sym # LayLa2S.Qualident THEN
		LayLa2S.Mark (LayLa2S.Pos (), "Lib.Obj expected");
		node := Layouts.NewObject ("")
	ELSE node := Layouts.CopyPublicObj (LayLa2S.ident, deep); LayLa2S.Get (sym) END;
	WHILE sym # LayLa2S.End DO Layouts.Insert (node, Eval (0)) END;
	RETURN node
END Copy;

PROCEDURE SetParams (node : Layouts.Node);		(*	sym # LayLa2S.close	*)
VAR params, dmy : Layouts.Node;
BEGIN
	params := Eval (0);
	IF (params # NIL) & ((params.id = Layouts.Params) OR (params.id = Layouts.Ident))
	THEN Layouts.SetParams (node, params)
	ELSE LayLa2S.Mark (LayLa2S.Pos (), "PARAMS expected") END;
	IF sym # LayLa2S.End THEN
		LayLa2S.Mark (LayLa2S.Pos (), "'END' expected");
		REPEAT dmy := Eval (0) UNTIL sym = LayLa2S.End
	END
END SetParams;

PROCEDURE Include () : Layouts.Node;
VAR node : Layouts.Node;
		oldpos : LONGINT;
		oldtext : Texts.Text;
BEGIN	LayLa2S.Get (sym);
	IF debug THEN Out.String ("Include"); Out.Int (sym, 5); Out.Ln END;
	IF (sym # LayLa2S.Qualident) & (sym # LayLa2S.Ident) THEN
		LayLa2S.Mark (LayLa2S.Pos (), "filename expected"); node := Layouts.NewObject ("")
	ELSE
		oldpos := LayLa2S.Pos ()-1;	oldtext := curtext;
		NEW (curtext); Texts.Open (curtext, LayLa2S.ident);
		IF curtext.len = 0 THEN LayLa2S.Mark (LayLa2S.Pos (), "file not found or empty");
			node := Layouts.NewObject ("")
		ELSE
			LayLa2S.OpenText (curtext, 0);	LayLa2S.Get (sym);	node := Eval (outermost);
			curtext := oldtext;	LayLa2S.OpenText (curtext, oldpos)
		END;
		LayLa2S.Get (sym)
	END;
	IF sym # LayLa2S.End THEN SetParams (node) END;
	RETURN node
END Include;

PROCEDURE New () : Layouts.Node;
VAR node : Layouts.Node;
		alias : ARRAY 64 OF CHAR;
BEGIN	LayLa2S.Get (sym);
	IF sym = LayLa2S.Virtual THEN
		node := Layouts.NewObject (""); LayLa2S.Get (sym);
		WHILE sym # LayLa2S.End DO Layouts.Insert (node, Eval (0)) END
	ELSIF sym = LayLa2S.Ident THEN
		Gadgets.GetAlias (LayLa2S.ident, alias);
		IF alias = "" THEN
			node := Layouts.NewInstance (LayLa2S.ident);	LayLa2S.Get (sym);
			IF sym # LayLa2S.End THEN SetParams (node) END;
		ELSE node := Layouts.NewObject (LayLa2S.ident); LayLa2S.Get (sym);
			WHILE sym # LayLa2S.End DO Layouts.Insert (node, Eval (0)) END
		END
	ELSIF sym = LayLa2S.Qualident THEN
		node := Layouts.NewObject (LayLa2S.ident); LayLa2S.Get (sym);
		WHILE sym # LayLa2S.End DO Layouts.Insert (node, Eval (0)) END
	ELSE LayLa2S.Mark (LayLa2S.Pos (), "NewProc expected"); node := Layouts.NewObject ("")
	END;
	RETURN node
END New;

PROCEDURE MakeObj (NewObj : PROCEDURE (NewProc : ARRAY OF CHAR) : Layouts.Node) : Layouts.Node;
VAR node : Layouts.Node;
BEGIN	LayLa2S.Get (sym);
	IF debug THEN Out.String ("MakeObj  "); Out.Int (sym, 5); Out.Ln END;
	IF sym = LayLa2S.Virtual THEN
		node := NewObj (""); LayLa2S.Get (sym);
		WHILE sym # LayLa2S.End DO Layouts.Insert (node, Eval (0)) END
	ELSIF (sym = LayLa2S.Ident) OR (sym = LayLa2S.Qualident) THEN
		node := NewObj (LayLa2S.ident); LayLa2S.Get (sym);
		WHILE sym # LayLa2S.End DO Layouts.Insert (node, Eval (0)) END
	ELSE LayLa2S.Mark (LayLa2S.Pos (), "NewProc expected");
		WHILE sym # LayLa2S.End DO node := Eval (0) END;
		node := NewObj ("")
	END;
	RETURN node
END MakeObj;

PROCEDURE Break (flag : INTEGER) : Layouts.Node;
VAR break, node : Layouts.Node;
BEGIN	LayLa2S.Get (sym);
	break := Layouts.NewBreak ();
	IF debug THEN Out.String ("Break"); Out.Int (sym, 5); Out.Ln END;
	node := Eval (flag);
	IF (node = NIL) OR
		((node.id # Layouts.Obj) & (node.id # Layouts.Break)
		& (node.id # Layouts.Ident) & (node.id # Layouts.Instance))
	THEN LayLa2S.Mark (LayLa2S.Pos (), "Object expected"); node := Layouts.NewObject ("") END;
	Layouts.Insert (break, node);
	RETURN break
END Break;

PROCEDURE Span (flag : INTEGER) : Layouts.Node;
VAR span, node : Layouts.Node;
		rows, cols : INTEGER;
BEGIN	LayLa2S.Get (sym);
	IF debug THEN Out.String ("Span"); Out.Int (sym, 5); Out.Ln END;
	IF sym = LayLa2S.Int THEN rows := SHORT (LayLa2S.int)
	ELSE LayLa2S.Mark (LayLa2S.Pos (), "Integer expected"); rows := 0 END;
	LayLa2S.Get (sym);
	IF sym = LayLa2S.Int THEN cols := SHORT (LayLa2S.int)
	ELSE LayLa2S.Mark (LayLa2S.Pos (), "Integer expected"); cols := 0 END;
	LayLa2S.Get (sym);
	span := Layouts.NewSpan (rows, cols);
	node := Eval (flag);
	IF (node = NIL) OR
		((node.id # Layouts.Obj) & (node.id # Layouts.Break)
		& (node.id # Layouts.Ident) & (node.id # Layouts.Instance))
	THEN LayLa2S.Mark (LayLa2S.Pos (), "Object expected"); node := Layouts.NewObject ("") END;
	Layouts.Insert (span, node);
	RETURN span
END Span;

PROCEDURE Config () : Layouts.Node;
VAR config : Layouts.Node;
BEGIN
	LayLa2S.Get (sym);
	IF debug THEN Out.String ("Config"); Out.Int (sym, 5); Out.Ln END;
	config := Layouts.NewConfig ();
	WHILE sym # LayLa2S.End DO
		Layouts.Insert (config, Eval (0))
	END;
	RETURN config
END Config;

PROCEDURE Eval (flag : INTEGER) : Layouts.Node;
VAR node : Layouts.Node;
		Ident : ARRAY 64 OF CHAR;
BEGIN	node := NIL;
	IF debug THEN Out.String ("Eval"); Out.Int (sym, 5); Out.Ln END;
	CASE sym OF
		LayLa2S.Contents : node := NIL; IF ~(flag = outermost) THEN LayLa2S.Get (sym) END
		| LayLa2S.String : node := Layouts.NewString (LayLa2S.s); IF ~(flag = outermost) THEN LayLa2S.Get (sym) END
		| LayLa2S.Int, LayLa2S.Default, LayLa2S.lbrak : node := Size (flag = outermost)
		| LayLa2S.Real : node := Layouts.NewReal (LayLa2S.real); IF ~(flag = outermost) THEN LayLa2S.Get (sym) END
		| LayLa2S.Char : node := Layouts.NewChar (LayLa2S.char); IF ~(flag = outermost) THEN LayLa2S.Get (sym) END
		| LayLa2S.Bool : node := Layouts.NewBool (LayLa2S.bool); IF ~(flag = outermost) THEN LayLa2S.Get (sym) END
		| LayLa2S.Left..LayLa2S.Vert : node := Layouts.NewFormat (sym); IF ~(flag = outermost) THEN LayLa2S.Get (sym) END
		| LayLa2S.Qualident : node := Layouts.WrappedObject (Gadgets.FindPublicObj (LayLa2S.ident));
													IF ~(flag = outermost) THEN LayLa2S.Get (sym) END
		| LayLa2S.Virtual : node := Layouts.NewObject (""); IF ~(flag = outermost) THEN LayLa2S.Get (sym) END
		| LayLa2S.Ident : COPY (LayLa2S.ident, Ident); LayLa2S.Get (sym);
				IF sym = LayLa2S.equal THEN
					LayLa2S.Get (sym); node := Eval (flag);
					IF node # NIL THEN node := Layouts.NewSet (Ident, node) END
				ELSE node := Layouts.NewIdent (Ident) END
		| LayLa2S.Config : node := Config (); IF ~(flag = outermost) THEN LayLa2S.Get (sym) END
		| LayLa2S.Deep : node := Copy (TRUE); IF ~(flag = outermost) THEN LayLa2S.Get (sym) END
		| LayLa2S.Shallow : node := Copy (FALSE); IF ~(flag = outermost) THEN LayLa2S.Get (sym) END
		| LayLa2S.Include : node := Include (); IF ~(flag = outermost) THEN LayLa2S.Get (sym) END
		| LayLa2S.New : node := New (); IF ~(flag = outermost) THEN LayLa2S.Get (sym) END
		| LayLa2S.HList : node := MakeObj (Layouts.NewHList); IF ~(flag = outermost) THEN LayLa2S.Get (sym) END
		| LayLa2S.VList : node := MakeObj (Layouts.NewVList); IF ~(flag = outermost) THEN LayLa2S.Get (sym) END
		| LayLa2S.Table : node := MakeObj (Layouts.NewTable); IF ~(flag = outermost) THEN LayLa2S.Get (sym) END
		| LayLa2S.Place : node := MakeObj (Layouts.NewPlace); IF ~(flag = outermost) THEN LayLa2S.Get (sym) END
		| LayLa2S.Break : node := Break (flag)
		| LayLa2S.Span : node := Span (flag)
		| LayLa2S.Def : node := Def (flag)
		| LayLa2S.Params : node := SetList (Layouts.Params)
		| LayLa2S.Layout : node := SetList (Layouts.Layout)
		| LayLa2S.Attributes : node := SetList (Layouts.Attributes)
		| LayLa2S.Links : node := SetList (Layouts.Links)
	ELSE
		LayLa2S.Mark (LayLa2S.Pos(), "unexpected symbol");
		IF sym # LayLa2S.End THEN LayLa2S.Get (sym) END
	END;
	RETURN node;
END Eval;

PROCEDURE ParseText* (text : Texts.Text; pos : LONGINT) : Objects.Object;
VAR node : Layouts.Node;
BEGIN
	curtext := text;
	LayLa2S.Init; LayLa2S.OpenText (curtext, pos); LayLa2S.Get (sym);
	node := Eval (outermost);
	IF ~LayLa2S.error THEN RETURN Layouts.Realize (node) ELSE RETURN NIL END
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
		IF time < 0 THEN Out.String ("no selection"); Out.Ln; RETURN END
	ELSIF (s.class = Texts.Char) & (s.c = '*') THEN
		T := Oberon.MarkedText()
	ELSIF (s.class = Texts.Char) & (s.c = '@') THEN	Texts.Scan (s);
		IF (s.class = Texts.Name) THEN COPY (s.s, Name)
		ELSE Out.String ("filename missing"); COPY ("Demo.Config", Name) END;
		NEW (T); Texts.Open (T, Name); beg := 0;
	ELSE T := Oberon.Par.text; beg := Oberon.Par.pos
	END;
END GetText;

PROCEDURE Insert*;
(**
		Insert reads the specified layout text and inserts the new gadget at the caret position.

		 Insert ^		read from latest selection
		 Insert *		read from marked viewer / TextGadget
		 Insert @ file	read from file
		 Insert NEW Button END
*)
VAR T : Texts.Text;
		pos : LONGINT;
		obj : Objects.Object;
BEGIN
	GetText (T, pos);
	obj := ParseText (T, pos);
	Gadgets.Integrate(obj)
END Insert;

BEGIN
	Texts.OpenWriter (W)
END LayLa2.


