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

MODULE LayLaDemo;	(** portable *)

IMPORT Gadgets, Texts, Objects, LayLa, LayLa2, Layouts, Out, Oberon,
				PanelDocs, Documents, Desktops, Display;
				
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
		T := Oberon.MarkedText(); beg := 0
	ELSIF (s.class = Texts.Char) & (s.c = '@') THEN	Texts.Scan (s);
		IF (s.class = Texts.Name) THEN COPY (s.s, Name)
		ELSE Out.String ("filename missing"); COPY ("Demo.Config", Name) END;
		NEW (T); Texts.Open (T, Name); beg := 0;
	ELSE T := Oberon.Par.text; beg := Oberon.Par.pos
	END
END GetText;

PROCEDURE Insert*;
VAR T : Texts.Text;
		pos : LONGINT;
		obj : Objects.Object;
BEGIN
	GetText (T, pos);
	obj := LayLa.ParseText (T, pos);
	Gadgets.Integrate(obj)
END Insert;

PROCEDURE InsertDoc*;
VAR T : Texts.Text;
		pos : LONGINT;
		obj : Objects.Object;
		doc : Documents.Document;
BEGIN
	GetText (T, pos);
	obj := LayLa.ParseText (T, pos);
	IF (obj # NIL) & (obj IS Display.Frame) THEN
		PanelDocs.NewDoc;
		doc := Objects.NewObj(Documents.Document);
		doc.W := obj(Display.Frame).W; doc.H := obj(Display.Frame).H;
		Documents.Init (doc, obj(Gadgets.Frame));
		Desktops.ShowDoc (doc)
	END
END InsertDoc;

PROCEDURE Insert2*;
VAR T : Texts.Text;
		pos : LONGINT;
		obj : Objects.Object;
BEGIN
	GetText (T, pos);
	obj := LayLa2.ParseText (T, pos);
	Gadgets.Integrate(obj)
END Insert2;

PROCEDURE Build1*;
VAR panel, break, hlist, gadget, attr, assign : Layouts.Node;
		obj : Objects.Object;
		
		(*	LayLaDemo.Insert
				(TABLE Panel (border=8 cols=3 grid=DYNAMIC)
					(NEW Button (ATTR Caption = "1"))
					(SPAN 2 1 (NEW Button (w=[1] h=[1]) (ATTR Caption = "2")))
					(NEW Button  (ATTR Caption = "3"))
					(NEW Button  (ATTR Caption = "4"))
					(NEW Button  (ATTR Caption = "5"))
					(BREAK (HLIST Panel (h=60 w=[] border=3)
						(NEW Caption (vjustifyMe=CENTER) (ATTR Value="Zwischentitel 2"))
						(NEW Button (hjustifyMe=RIGHT) (ATTR Caption="hello"))
					))	
					(NEW Button  (ATTR Caption = "6"))
					(NEW Button  (ATTR Caption = "7"))
				)
		*)
		
		PROCEDURE Button (Caption : ARRAY OF CHAR; layout : Layouts.Node) : Layouts.Node;
		VAR gadget, attr, assign : Layouts.Node;
		BEGIN
			gadget := Layouts.NewObject ("Button");	Layouts.Insert (gadget, layout);
			attr := Layouts.NewNode (Layouts.Attributes);	Layouts.Insert (gadget, attr);
			assign := Layouts.NewSet ("Caption", Layouts.NewString (Caption));	Layouts.Insert (attr, assign);
			RETURN gadget
		END Button;
		
BEGIN
	panel := Layouts.NewTable ("Panel");
	attr := Layouts.NewNode (Layouts.Layout);	Layouts.Insert (panel, attr);
	assign := Layouts.NewSet ("cols", Layouts.NewInt (3));	Layouts.Insert (attr, assign);
	assign := Layouts.NewSet ("border", Layouts.NewInt (8));	Layouts.Insert (attr, assign);
	assign := Layouts.NewSet ("grid", Layouts.NewFormat (Layouts.Dynamic));	Layouts.Insert (attr, assign);

	Layouts.Insert (panel, Button ("1", NIL));
	
	gadget := Layouts.NewSpan (2, 1);	Layouts.Insert (panel, gadget);						(*	(SPAN ... )	*)
	attr := Layouts.NewNode (Layouts.Layout);
	assign := Layouts.NewSet ("w", Layouts.NewSize (0, 1));	Layouts.Insert (attr, assign);
	assign := Layouts.NewSet ("h", Layouts.NewSize (0, 1));	Layouts.Insert (attr, assign);
	Layouts.Insert (gadget, Button ("2", attr));
	
	Layouts.Insert (panel, Button ("3", NIL));
	Layouts.Insert (panel, Button ("4", NIL));
	Layouts.Insert (panel, Button ("5", NIL));

	break := Layouts.NewBreak ();	Layouts.Insert (panel, break);							(*	(BREAK ... )	*)
	hlist := Layouts.NewHList ("Panel");	Layouts.Insert (break, hlist);
	attr := Layouts.NewNode (Layouts.Layout);	Layouts.Insert (hlist, attr);
	assign := Layouts.NewSet ("h", Layouts.NewSize (60, 0));	Layouts.Insert (attr, assign);
	assign := Layouts.NewSet ("w", Layouts.NewSize (0, 1));	Layouts.Insert (attr, assign);
	assign := Layouts.NewSet ("border", Layouts.NewInt (3));	Layouts.Insert (attr, assign);
	gadget := Layouts.NewObject ("Caption");	Layouts.Insert (hlist, gadget);						(*	(NEW Caption ...)	*)
	attr := Layouts.NewNode (Layouts.Layout);	Layouts.Insert (gadget, attr);
	assign := Layouts.NewSet ("vjustifyMe", Layouts.NewFormat (Layouts.Center));	Layouts.Insert (attr, assign);
	attr := Layouts.NewNode (Layouts.Attributes);	Layouts.Insert (gadget, attr);
	assign := Layouts.NewSet ("Value", Layouts.NewString ("Zwischentitel 2"));	Layouts.Insert (attr, assign);
	attr := Layouts.NewNode (Layouts.Layout);	Layouts.Insert (gadget, attr);					(*	(NEW Button ... )	*)
	assign := Layouts.NewSet ("hjustifyMe", Layouts.NewFormat (Layouts.Right));	Layouts.Insert (attr, assign);
	Layouts.Insert (hlist, Button ("Press", attr));
	
	Layouts.Insert (panel, Button ("6", NIL));
	Layouts.Insert (panel, Button ("7", NIL));

	obj := Layouts.Realize (panel);
	Gadgets.Integrate (obj);
END Build1;

PROCEDURE Build2*;
VAR conf, conf1, vlist, object, attr : Layouts.Node;
		
		(*	LayLaDemo.Insert
				(CONFIG
					(DEF Int (NEW Integer (ATTR (SET Value 75))))
					(DEF aSlider (CONFIG
						(DEF Int1 (NEW Integer (ATTR (SET Value 25))))
						(NEW Slider
							(LAYOUT (SET w 100) (SET h 20))
							(LINKS (SET Model Int1))
						)
					))
				
					(VLIST Panel (border=8)
						(NEW aSlider (PARAMS (SET Int1 Int)))
						aSlider
						(SCOPY Test.Slider (h=10))
						(SCOPY Test.TextField)
				))
		*)
		
BEGIN
	conf := Layouts.NewConfig ();
	
	object := Layouts.NewObject ("Integer");														(*	(DEF Int ... )	*)
	attr := Layouts.NewNode (Layouts.Attributes);	Layouts.Insert (object, attr);
	Layouts.Insert (attr, Layouts.NewSet ("Value", Layouts.NewInt (75)));
	Layouts.Insert (conf, Layouts.NewDef ("Int", object));
	
	conf1 := Layouts.NewConfig ();
	
	object := Layouts.NewObject ("Integer");														(*	(DEF Int1 ... )	*)
	attr := Layouts.NewNode (Layouts.Attributes);	Layouts.Insert (object, attr);
	Layouts.Insert (attr, Layouts.NewSet ("Value", Layouts.NewInt (25)));
	Layouts.Insert (conf1, Layouts.NewDef ("Int1", object));
	
	object := Layouts.NewObject ("Slider");	Layouts.Insert (conf1, object);		(*	(NEW Slider ... )	*)
	attr := Layouts.NewNode (Layouts.Layout);	Layouts.Insert (object, attr);
	Layouts.Insert (attr, Layouts.NewSet ("w", Layouts.NewSize (100, 0)));
	Layouts.Insert (attr, Layouts.NewSet ("h", Layouts.NewSize (20, 0)));
	attr := Layouts.NewNode (Layouts.Links);	Layouts.Insert (object, attr);
	Layouts.Insert (attr, Layouts.NewSet ("Model", Layouts.NewIdent ("Int1")));
	
	Layouts.Insert (conf, Layouts.NewDef ("aSlider", conf1));
	
	vlist := Layouts.NewVList ("Panel");	Layouts.Insert (conf, vlist);				(*	(VLIST Panel ... )	*)
	attr := Layouts.NewNode (Layouts.Layout);	Layouts.Insert (vlist, attr);
	Layouts.Insert (attr, Layouts.NewSet ("border", Layouts.NewInt (8)));
	
	object := Layouts.NewInstance ("aSlider");	Layouts.Insert (vlist, object);		(*	(NEW aSlider ... )	*)
	attr := Layouts.NewNode (Layouts.Params);	Layouts.Insert (object, attr);
	Layouts.Insert (attr, Layouts.NewSet ("Int1", Layouts.NewIdent ("Int")));
	
	Layouts.Insert (vlist, Layouts.NewInstance ("aSlider"));					(*	aSlider	*)
	
	object := Layouts.CopyPublicObj ("Test.Slider", FALSE);	Layouts.Insert (vlist, object);
	attr := Layouts.NewNode (Layouts.Layout);	Layouts.Insert (object, attr);
	Layouts.Insert (attr, Layouts.NewSet ("h", Layouts.NewSize (10, 0)));
	
	Layouts.Insert (vlist, Layouts.CopyPublicObj ("Test.TextField", FALSE));

	Gadgets.Integrate (Layouts.Realize (conf));
END Build2;

END LayLaDemo.



LayLaDemo.Insert
	(TABLE Panel (border=8 cols=3 grid=DYNAMIC)
		(NEW Button (ATTR Caption = "1"))
		(SPAN 2 1 (NEW Button (w=[1] h=[1]) (ATTR Caption = "2")))
		(NEW Button  (ATTR Caption = "3"))
		(NEW Button  (ATTR Caption = "4"))
		(NEW Button  (ATTR Caption = "5"))
		(BREAK (HLIST Panel (h=60 w=[] border=3)
			(NEW Caption (vjustifyMe=CENTER) (ATTR Value="Zwischentitel 2"))
			(NEW Button (hjustifyMe=RIGHT) (ATTR Caption="Press"))
		))	
		(NEW Button  (ATTR Caption = "6"))
		(NEW Button  (ATTR Caption = "7"))
	)

LayLaDemo.Build1



LayLaDemo.Insert
	(CONFIG
		(DEF Int (NEW Integer (ATTR (SET Value 75))))
		(DEF aSlider (CONFIG
			(DEF Int1 (NEW Integer (ATTR (SET Value 25))))
			(NEW Slider
				(LAYOUT (SET w 100) (SET h 20))
				(LINKS (SET Model Int1))
			)
		))
	
		(VLIST Panel (border=8)
			(NEW aSlider (PARAMS (SET Int1 Int)))
			aSlider
			(SCOPY Test.Slider (h=10))
			(SCOPY Test.TextField)
	))

LayLaDemo.Build2

