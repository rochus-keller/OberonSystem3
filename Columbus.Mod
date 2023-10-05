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

MODULE Columbus;	(** portable *)	(* PS   *)

(**  - an inspector tool for objects and libraries. *)

(*
	5.6.96	opens a new document not at the pointer's position anymore (thanks pm)
	5.6.96	removed bug when adding a string attribute (thanks pm)
	12.7.96	added commads Remove & RemoveFrom (thanks ejz)
	22.7.96	fixed bug in EnumLinks (thanks eos)
	25.7.96	change size of a gadget works now for 'off screen' frames, too
	15.1.97	StoreLib binds all objects to library first
	24.4.97	values are only set when changed
*)
	IMPORT
		Files, Objects, Fonts, Texts, Strings, Attributes, Links, Display, Oberon, Gadgets, Panels, TextFields,
		BasicGadgets, BasicFigures, RefGadgets, ScrollViews, TextGadgets, ListRiders, Documents, Desktops;
	
	CONST
		Version = "1.2";
		DocName = "Objects.Panel";

		(* object names in library editor panel *)
		ObjList = "objlist";
		ObjNameObj = "theobj"; LibNameObj = "thelib";
		RNameObj = "rname"; NNameObj = "nname";
		CopyStyleObj = "copystyle"; RefObj = "value";

		(* object names in inspector panel *)
		ViewModeObjName = "ViewMode";

		(* messures used to build inspector panel *)
		Border = 7; PanelW = 370;
		
		LargeW = 300; MediumW = 100; SmallW = 20;
		Height = 20;

		(* max. number of tabs in a layout *)
		Tabs = 6;

		(* item classes *)
		Attribute = 0;	Link = 1; Coord = 2;
		Control = 3;	Title = 4;
	
		(* inspector panel views *)
		ObjAttrView = 0; ObjLinkView = 1; ObjCoordView = 2;
		ObjDscView = 3; ObjDefView = 4;
		LibOverView = 5;  LibEditView = 6;
		NoView = 7;

		ObjViews = {ObjAttrView, ObjLinkView, ObjCoordView, ObjDscView, ObjDefView};

		(* layout align ids *)
		top = 0; middle = 1; bottom = 2;

	TYPE
		(* attribute or link items of current inspected object *)
		Item = POINTER TO ItemDesc;
		ItemDesc = RECORD
			next: Item;
			class: INTEGER;
			name: ARRAY 32 OF CHAR;	(* attr./link name *)
			val: Objects.Object;	(* model, representing attr./link value *)
		END;

		(* history of inspected objects *)
		HistoryItem = POINTER TO HistoryItemDesc;
		HistoryItemDesc = RECORD
			next: HistoryItem;
			obj: Objects.Object;
			lib: Objects.Library;
			view: INTEGER
		END;

		(* inspector panel *)
		Panel = POINTER TO PanelDesc;
		PanelDesc = RECORD (Panels.PanelDesc)
			items: Item;
			history: HistoryItem
		END;

		(* special frame to handle writing of layouts into layouts *)
		LayoutFrame = POINTER TO LayoutFrameDesc;
		LayoutFrameDesc = RECORD (Display.FrameDesc)
		END;

		Layout = RECORD
			align: INTEGER;	(* 0: top / 1: middle / 2: bottom *)
			X, Y, maxH: INTEGER;
			frames: Display.Frame;
			items: Item;
			tabs: ARRAY Tabs OF INTEGER
		END;

		(* miniframework to handle the different views *)
		CanProc = PROCEDURE (obj: Objects.Object; lib: Objects.Library): BOOLEAN;
		MakeProc = PROCEDURE (obj: Objects.Object; lib: Objects.Library; VAR L: Layout);
		ButtonProc = PROCEDURE (model, obj: Objects.Object; lib: Objects.Library): Display.Frame;

		ViewGenDesc = RECORD
			canView: CanProc;	(* can this view show info *)
			makeView: MakeProc;	(* make the view's depending panel *)
			getButton: ButtonProc	(* returns a button to insert in the view selection area *)
		END;

	VAR
		W: Texts.Writer;
		enumObj: Objects.Object;
		oldValues: Item;
		layout: Layout;
		msgPrinted: BOOLEAN;
		viewGens: ARRAY NoView OF ViewGenDesc;

	(* ---------------------- string opearation ----------------------- *)

(* converts a referece into a string of the form "# <i>". *) 
PROCEDURE RefToStr(i: LONGINT; VAR s: ARRAY OF CHAR); 
	VAR k, j: INTEGER; a: ARRAY 10 OF CHAR;
BEGIN k:= 0;
	REPEAT
		a[k] := CHR(i MOD 10 + 30H); i := i DIV 10; INC(k)
	UNTIL i = 0;
	j := 2;
    s[0]:= "#"; s[1]:= " ";
    REPEAT DEC(k); s[j] := a[k]; INC(j); UNTIL k = 0;
    s[j] := 0X
END RefToStr;

(* Appends <this> to <to>. *)
PROCEDURE Append(this: ARRAY OF CHAR; VAR to: ARRAY OF CHAR);
	VAR i, j, l: LONGINT;
BEGIN
	i := 0; WHILE to[i] # 0X DO INC(i) END;
	l := LEN(to)-1; j := 0;
	WHILE (i < l) & (this[j] # 0X) DO to[i] := this[j]; INC(i); INC(j) END;
	to[i] := 0X
END Append;

(* Appends <this> to <to>. *)
PROCEDURE AppendCh(this: CHAR; VAR to: ARRAY OF CHAR);
	VAR i: LONGINT;
BEGIN
	i := 0; WHILE to[i] # 0X DO INC(i) END;
	IF i < LEN(to) - 1 THEN to[i] := this; to[i+1] := 0X END
END AppendCh;


	(* ---------------------- output proceudre to writer ----------------------- *)

PROCEDURE Char(ch: CHAR);	(*  writes a char to W *)
BEGIN Texts.Write(W, ch)
END Char;

PROCEDURE String(str: ARRAY OF CHAR);	(*  writes a string to W *)
BEGIN Texts.WriteString(W, str)
END String;

PROCEDURE Int(i: LONGINT);	(*  writes an integer to W *)
BEGIN Texts.WriteInt(W, i, 0)
END Int;

PROCEDURE Ln;	(*  writes a line feed to W *)
BEGIN Texts.WriteLn(W)
END Ln;

PROCEDURE ToLog;	(*  writes content of W to the Oberon log *)
BEGIN Texts.Append(Oberon.Log, W.buf)
END ToLog;

PROCEDURE PrintMsg;	(*  writes program's name and version to the Oberon log *)
BEGIN
	Texts.SetFont(W, Fonts.This("Default10b.Scn.Fnt"));
	String("Columbus "); String(Version);
	Texts.SetFont(W, Fonts.Default);
	String(" / PS November 95"); Ln; ToLog;
	msgPrinted:= TRUE
END PrintMsg;


	(* ---------------------- forward declarations ----------------------- *)

PROCEDURE ^InspectThis(VAR P: Panel; obj: Objects.Object; lib: Objects.Library; view: INTEGER);

	(* ---------------------- document related procedures ----------------------- *)

PROCEDURE LoadDoc(D: Documents.Document);
	VAR lib: Objects.Library; i: LONGINT; view: INTEGER; p: Panel; name: ARRAY 64 OF CHAR;
BEGIN
	COPY(D.name, name);
	p:= NIL; lib := NIL; view := NoView;
	IF (name # "") & (name # DocName) THEN
		i := 0;
		WHILE name[i] # 0X DO INC(i) END;
		REPEAT DEC(i) UNTIL (i = 0) OR (name[i] = ".");
		IF i > 0 THEN
			name[i + 1] := "L"; name[i + 2] := "i"; name[i + 3] := "b"; name[i + 4] := 0X;
			lib := Objects.ThisLibrary(name);
			IF lib # NIL THEN view := LibEditView END
		END
	END;
	InspectThis(p, NIL, lib, view);
	COPY(DocName, D.name); D.W:= p.W; D.H:= p.H;
	Documents.Init(D, p)
END LoadDoc;

PROCEDURE StoreDoc(D: Documents.Document);
	VAR f: Files.File; R: Files.Rider; filename: ARRAY 64 OF CHAR;
BEGIN
	String("Store "); ToLog;
	IF D.name # "" THEN
		f:= Files.New(D.name); IF f = NIL THEN HALT(99) END;
		Files.Set(R, f, 0); Files.WriteInt(R, Documents.Id); Files.WriteString(R, "Columbus.NewDoc");
		Files.WriteInt(R, D.X); Files.WriteInt(R, D.Y); Files.WriteInt(R, D.W); Files.WriteInt(R, D.H);
		Files.Register(f);
		Char(22X); String(filename); Char(22X)
	ELSE String("[Untitled document]")
	END;
	Ln; ToLog
END StoreDoc;

PROCEDURE DocHandler(D: Objects.Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH D: Documents.Document DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF M.id = Objects.get THEN
					IF M.name = "Gen" THEN M.class := Objects.String; M.s := "Columbus.NewDoc"; M.res := 0
					ELSIF M.name = "Adaptive" THEN M.class := Objects.Bool; M.b := FALSE; M.res := 0
					ELSIF M.name = "Icon" THEN M.class := Objects.String; M.s := "Columbus.Icon"; M.res := 0
					ELSE Documents.Handler(D, M)
					END
				ELSE Documents.Handler(D, M)
				END
			END	(* WITH *)
		ELSIF M IS Objects.LinkMsg THEN
			WITH M: Objects.LinkMsg DO
				IF (M.name = "SystemMenu") OR (M.name = "UserMenu") OR (M.name = "DeskMenu") THEN
					M.obj := Desktops.NewMenu(""); M.res := 0
				ELSE Documents.Handler(D, M)
				END
			END
		ELSE Documents.Handler(D, M)
		END
	END	(* WITH *)
END DocHandler;

PROCEDURE NewDoc*;
	VAR D: Documents.Document;
BEGIN
	NEW(D);
	D.Load := LoadDoc; D.Store := StoreDoc; D.handle := DocHandler;
	D.W := 200; D.H := 200; 
	Objects.NewObj := D
END NewDoc;


	(* ---------------------- panel related procedures ----------------------- *)

(*
PROCEDURE CopyPanel(VAR M: Objects.CopyMsg; from, to: Panel);
	VAR h, newH: HistoryItem; i, newI: Item;
BEGIN
Log.Str("copying panel"); Log.Ln;
	Panels.CopyPanel(M, from, to);
	(* copy history *)
	h:= from.history; NEW(newH); to.history:= newH;
	WHILE h # NIL DO NEW(newH.next); newH:= newH.next; newH^:= h^; h:= h.next END;
	to.history:= to.history.next;
	(* copy items *)
	i:= from.items; NEW(newI); to.items:= newI;
	WHILE i # NIL DO NEW(newI.next); newI:= newI.next; newI^:= i^; i:= i.next END;
	to.items:= to.items.next
END CopyPanel;
*)

PROCEDURE PanelHandler(P: Objects.Object; VAR M: Objects.ObjMsg);
	VAR P1: Panel; f: Display.Frame; x, y, w, h, count: INTEGER;
BEGIN
	WITH P: Panel DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF (M.id = Objects.get) & (M.name = "Gen") THEN
					M.class:= Objects.String; COPY("Columbus.NewPanel", M.s); M.res:= 0
				ELSE Panels.PanelHandler(P, M)
				END
			END	(* WITH *)
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = P.stamp THEN M.obj := P.dlink (* non-first arrival *)
				ELSE (* first arrival -> make a new panel *)
					InspectThis(P1, NIL, NIL, NoView); P.stamp := M.stamp; P.dlink := P1; M.obj := P1
				END
			END	(* WITH *)
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Gadgets.framehandle(P, M)
				ELSIF M.id = Objects.load THEN
					Gadgets.framehandle(P, M);
					P.history:= NIL;
					InspectThis(P, NIL, NIL, NoView);
					(* size panel *)
					f:= P.dsc; WHILE f # NIL DO f.slink:= f.next; f:= f.next END;
					Panels.BoundingBox(P.dsc, x, y, w, h, count);
					P.W:= w + 2*Border; P.H:= h + 2*Border
				END
			END	(* WITH *)
		ELSE Panels.PanelHandler(P, M)
		END
	END	(* WITH *)
END PanelHandler;

PROCEDURE InitPanel(P: Panel);
BEGIN
	Panels.InitPanel(P); P.items:= NIL; P.history:= NIL;
	P.handle:= PanelHandler
END InitPanel;

PROCEDURE NewPanel*;
	VAR P: Panel;
BEGIN NEW(P); InitPanel(P); Objects.NewObj:= P
END NewPanel;


	(* ---------------------- aux. proceudres ----------------------- *)

PROCEDURE Max(x, x0: INTEGER): INTEGER;
BEGIN IF x >= x0 THEN RETURN x ELSE RETURN x0 END
END Max;


	(* ---------------------- frame generators ----------------------- *)

PROCEDURE MakeCaption(s: ARRAY OF CHAR; col: SHORTINT; bold: BOOLEAN): Display.Frame;
	VAR F: TextFields.Caption; nolines: INTEGER;
BEGIN
	TextFields.NewCaption; F:= Objects.NewObj(TextFields.Caption);
	Attributes.StrToTxt(s, F.text);
	Texts.ChangeLooks(F.text, 0, F.text.len, {1}, NIL, col, 0);
	IF bold THEN
		Texts.ChangeLooks(F.text, 0, F.text.len, {0}, Fonts.This("Default10b.Scn.Fnt"), 0, 0)
	END;
	TextFields.CalcSize(F, F.W, F.H, nolines, TRUE);
	RETURN F
END MakeCaption;

(* Makes a button. If <isPict> is true,  <caption> is interpreted as name of a public picture. *) 
PROCEDURE MakeCmd(caption, cmd: ARRAY OF CHAR; isPict: BOOLEAN): Display.Frame;
	VAR F: BasicGadgets.Button; A: Objects.AttrMsg;
BEGIN
	BasicGadgets.NewButton; F:= Objects.NewObj(BasicGadgets.Button);
	IF isPict THEN F.caption:= ""; F.look:= Gadgets.FindPublicObj(caption)
	ELSE COPY(caption, F.caption)
	END;
	F.val:= FALSE; F.popout:= TRUE;
	A.id:= Objects.set; A.class:= Objects.String; A.name:= "Cmd"; COPY(cmd, A.s); A.res:= -1;
	F.handle(F, A);
	F.W:= 50; F.H:= 25;
	RETURN F
END MakeCmd;

PROCEDURE MakeBool(val: BOOLEAN): Display.Frame;
	VAR F: BasicGadgets.CheckBox;
BEGIN
	BasicGadgets.NewCheckBox; F:= Objects.NewObj(BasicGadgets.CheckBox);
	BasicGadgets.NewBoolean; F.obj:= Objects.NewObj;
	F.obj(BasicGadgets.Boolean).val:= val; F.val:= val;
	F.W:= SmallW; F.H:= Height;
	RETURN F
END MakeBool;

PROCEDURE MakeString(val: ARRAY OF CHAR): Display.Frame;
	VAR F: TextFields.TextField;
BEGIN
	TextFields.NewTextField; F:= Objects.NewObj(TextFields.TextField);
	BasicGadgets.NewString; F.obj:= Objects.NewObj;
	F.W:= F.W*3;
	COPY(val, F.obj(BasicGadgets.String).val); COPY(val, F.val);
	F.W:= LargeW; F.H:= Height;
	RETURN F
END MakeString;

PROCEDURE MakeInt(val: LONGINT): Display.Frame;
	VAR F: TextFields.TextField;
BEGIN
	TextFields.NewTextField; F:= Objects.NewObj(TextFields.TextField);
	BasicGadgets.NewInteger; F.obj:= Objects.NewObj;
	F.obj(BasicGadgets.Integer).val:= val; Strings.IntToStr(val, F.val);
	F.W:= MediumW; F.H:= Height;
	RETURN F
END MakeInt;

PROCEDURE MakeReal(val: LONGREAL): Display.Frame;
	VAR F: TextFields.TextField;
BEGIN
	TextFields.NewTextField; F:= Objects.NewObj(TextFields.TextField);
	BasicGadgets.NewReal; F.obj:= Objects.NewObj;
	F.obj(BasicGadgets.Real).val:= val; Strings.RealToStr(val, F.val);
	F.W:= MediumW; F.H:= Height;
	RETURN F
END MakeReal;

PROCEDURE MakeLink(val: Objects.Object; locked: BOOLEAN): Display.Frame;
	VAR F: RefGadgets.Frame; A: Objects.AttrMsg;
BEGIN
	RefGadgets.NewFrame; F:= Objects.NewObj(RefGadgets.Frame);
	RefGadgets.NewReference; F.obj:= Objects.NewObj;
	A.id:= Objects.set; A.class:= Objects.String; A.name:= "Cmd"; A.s:= "Columbus.InspectLink Value";
	A.res:= -1;F.handle(F, A); 
	F.obj(RefGadgets.Reference).val:= val; F.val:= val;
	F.W:= SmallW; F.H:= Height; F.locked:= locked;
	RETURN F
END MakeLink;


	(* ---------------------- layout proceudres ----------------------- *)

PROCEDURE  ClearTabs(VAR L: Layout);
	VAR i: INTEGER;
BEGIN i:= 0; WHILE i < Tabs DO L.tabs[i]:= 0; INC(i) END
END ClearTabs;

PROCEDURE OpenLayout(VAR L: Layout);
BEGIN
	L.X:= 0; L.Y:= 0; L.maxH:= 0; L.align:= top; L.frames:= NIL; L.items:= NIL;
	ClearTabs(L)
END OpenLayout;

PROCEDURE SetTab(VAR L: Layout);
	VAR i: INTEGER;
BEGIN
	i:= 0; WHILE (i < Tabs) & (L.tabs[i] > 0) DO INC(i) END;
	IF i < Tabs THEN L.tabs[i]:= L.X END
END SetTab;

(* Adjusts the position of all frames line <L.Y>, corresponding to <L.align>. <L.Y> is decremented
	by <L.maxH> and <L.X> and <L.maxH> are set to zero. Inserts any subframes into <L.frames>. *)
PROCEDURE WriteLn(VAR L: Layout);
	VAR f, p, sf: Objects.Object;
BEGIN
	f:= L.frames; p:= NIL;
	WHILE f # NIL DO
		WITH f: Display.Frame DO
			IF f.Y+f.H-1 = L.Y THEN (* on the same line *)
				IF L.align = top THEN (* top *)
				ELSIF L.align = middle THEN (* middle *)
					f.Y:= L.Y - L.maxH DIV 2 - (f.H + 1) DIV 2 ;
				ELSE (* bottom *)
					f.Y:= L.Y - L.maxH + 1
				END
			END;	(* IF *)
			IF f IS LayoutFrame THEN
				IF p # NIL THEN p.slink:= f.dsc
				ELSE L.frames:= f.dsc
				END;
				sf:= f.dsc; p:= NIL;
				WHILE sf # NIL DO
					WITH sf: Display.Frame DO INC(sf.X, f.X); INC(sf.Y, f.Y+f.H-1) END;
					p:= sf; sf:= sf.slink
				END;
				p.slink:= f.slink; f:= p(Display.Frame)
			END
		END;	(* WITH *)
		p:= f; f:= f.slink
	END;	(* WHILE *)
	DEC(L.Y, L.maxH); L.maxH:= 0; L.X:= 0
END WriteLn;

PROCEDURE WriteHSpace(VAR L: Layout; w: INTEGER);
BEGIN INC(L.X, w)
END WriteHSpace;

(* Sets <L.X> to the next tab position or increments <L.X> by 20, if there is no
	tab position anymore. *)
PROCEDURE WriteTab(VAR L: Layout);
	VAR i: INTEGER;
BEGIN
	i:= 0; WHILE (i < Tabs) & (L.tabs[i] # 0) & (L.tabs[i] <= L.X) DO INC(i) END;
	IF (i < Tabs) & (L.tabs[i] # 0) THEN L.X:= L.tabs[i]
	ELSE L.X:= ((L.X+20) DIV 20)*20
	END
END WriteTab;

(* Writes a vertical space of length <h>. *)
PROCEDURE WriteVSpace(VAR L: Layout; h: INTEGER);
BEGIN DEC(L.Y, h)
END WriteVSpace;

(* Writes <F> to <L>. Sets <F.X> and <F.Y>, adds frame to <L.frames> and
	adjusts <L.X> and <L.maxH>.*)
PROCEDURE WriteFrame(VAR L: Layout; F: Display.Frame);
BEGIN
	F.X:= L.X; F.Y:= L.Y-F.H+1; INC(L.X, F.W); L.maxH:= Max(L.maxH, F.H);
	F.slink:= L.frames; L.frames:= F
END WriteFrame;

PROCEDURE WriteLine(VAR L: Layout);
	VAR F: BasicFigures.Figure;
BEGIN
	NEW(F); BasicFigures.InitLine(F, 0, 0, PanelW-10, 0);
	WriteLn(L); WriteVSpace(L, 2);
	F.X:= L.X; F.Y:= L.Y-F.H+1; INC(L.X, F.W); L.maxH:= Max(L.maxH, F.H);
	F.slink:= L.frames; L.frames:= F
END WriteLine;

PROCEDURE WriteCaption(VAR L: Layout; s: ARRAY OF CHAR; col: SHORTINT; bold: BOOLEAN);
	VAR F: Display.Frame;
BEGIN 
	F:= MakeCaption(s, col, bold);
	F.X:= L.X; F.Y:= L.Y-F.H+1; INC(L.X, F.W); L.maxH:= Max(L.maxH, F.H);
	F.slink:= L.frames; L.frames:= F
END WriteCaption;

PROCEDURE WriteCmd(VAR L: Layout; caption, cmd: ARRAY OF CHAR; isPict: BOOLEAN);
	VAR F: Display.Frame;
BEGIN
	F:= MakeCmd(caption, cmd, isPict);
	F.X:= L.X; F.Y:= L.Y-F.H+1; INC(L.X, F.W); L.maxH:= Max(L.maxH, F.H);
	F.slink:= L.frames; L.frames:= F
END WriteCmd;

(* Inserts a special frame, containing <l.frames> as its desc.. The subframes are added to <L> when
	the next WriteLn is performed. *)
PROCEDURE WriteLayout(VAR L, l: Layout);
	VAR F: LayoutFrame; cnt: INTEGER;
BEGIN
	NEW(F); Panels.BoundingBox(l.frames, F.X, F.Y, F.W, F.H, cnt);
	F.dsc:= l.frames;
	F.X:= L.X; F.Y:= L.Y-F.H+1; INC(L.X, F.W); L.maxH:= Max(L.maxH, F.H);
	F.slink:= L.frames; L.frames:= F
END WriteLayout;

PROCEDURE WriteLogo(VAR L: Layout; W: INTEGER);
	VAR obj: Objects.Object; F: Display.Frame; C: Objects.CopyMsg;
BEGIN
	obj:= Gadgets.FindPublicObj("Columbus.Logo");
	IF (obj # NIL) THEN
		C.id:= Objects.deep; Objects.Stamp(C); C.obj:= NIL; obj.handle(obj, C);
		IF (C.obj # NIL) & (C.obj IS Display.Frame) THEN F:= C.obj(Display.Frame)
		ELSE F:= MakeCaption("COLUMBUS", Display.FG, TRUE)
		END
	ELSE F:= MakeCaption("COLUMBUS", Display.FG, TRUE)
	END;
	IF F # NIL THEN
		F.X:= L.X + (W - F.W) DIV 2; F.Y:= L.Y-F.H+1; L.X:= F.X + F.W; L.maxH:= Max(L.maxH, F.H);
		F.slink:= L.frames; L.frames:= F
	END
END WriteLogo;

(* Write a list of items to <L>. *)
PROCEDURE WriteItems(VAR L: Layout; classes: SET);
(* index calculation:
	0	1	2	3	4	
	---------------------------
	LLLLLLLLLLLLLLLLLLLLLLLLLLL
	MMMMMMMMMMM	MMMMMMMMMMM
	MMMMMMMMMMM	SS	SS
	SS	MMMMMMMMMMM	SS
	SS	SS	MMMMMMMMMMM
	SS	SS	SS		SS
*)
	VAR width: ARRAY 6 OF INTEGER; index: INTEGER;

	PROCEDURE AdjustIndex(W: INTEGER);
	BEGIN
	(*
		IF index > 5 THEN index:= 0
		ELSIF (W = MediumW) & (index > 3) THEN index:= 0
		ELSIF W = LargeW THEN index:= 0
		END
	*)
		IF index > 4 THEN index:= 0
		ELSIF (W = MediumW) & (index > 3) THEN index:= 0
		ELSIF W = LargeW THEN index:= 0
		END
	END AdjustIndex;

	PROCEDURE NextIndex(W: INTEGER);
	BEGIN
	(*
		IF index = 0 THEN index:= -1 END;
		IF W = SmallW THEN INC(index, 2)
		ELSIF (W = MediumW) & (index # 2) THEN INC(index, 3)
		ELSE INC(index, 7)
		END
	*)
		IF W = SmallW THEN IF index = 2 THEN INC(index, 2) ELSE INC(index, 1) END
		ELSIF W = MediumW THEN INC(index, 3)
		ELSE INC(index, 5)
		END
	END NextIndex;

	PROCEDURE CalcWidth(VAR i: Item);
	BEGIN
		IF i.next # NIL THEN CalcWidth(i.next) END;
		IF i.class IN classes / {Title} THEN
			AdjustIndex(i.val(Display.Frame).W);
			width[index]:= Max(width[index], i.val(Display.Frame).next.W);
			NextIndex(i.val(Display.Frame).W)
		END
	END CalcWidth;

	PROCEDURE Write(i: Item);
		VAR n, f: Display.Frame; F: Gadgets.Frame;
	BEGIN
		IF i.next # NIL THEN Write(i.next) END;
		IF i.class IN classes THEN
			F:= i.val(Gadgets.Frame);
			IF i.class = Title THEN
				WriteLn(L); WriteVSpace(L, 4);
				L.align:= bottom; WriteFrame(L, F);
				WriteHSpace(L, PanelW - L.X); n:= F.next;
				WHILE n # NIL DO
					f:= n; n:= f.next;
					WriteHSpace(L, -f.W); WriteFrame(L, f); WriteHSpace(L, - f.W - 5)
				END; 
				WriteLn(L); L.align:= middle; WriteVSpace(L, 2);
				index:= 0; i.val:= NIL
			ELSE
				AdjustIndex(F.W);
				IF index = 0 THEN
					IF L.maxH # 0 THEN L.maxH:= Max(L.maxH, Height) END;
					WriteLn(L)
				ELSE WriteHSpace(L, 10)
				END;
				WriteHSpace(L, width[index]-F.next.W); WriteFrame(L, F.next);
				WriteHSpace(L, 3); WriteFrame(L, F);
				NextIndex(F.W);
				F.next:= NIL; i.val:= F.obj
			END
		END
	END Write;

BEGIN
	index:= 0; WHILE index < 6 DO width[index] := 0; INC(index) END;
	index:= 0; CalcWidth(L.items);
	index:= 0; Write(L.items)
END WriteItems;

	(* ---------------------- procs to create new items and add them to a layout ----------------------- *)

PROCEDURE AddItem(VAR L: Layout; name: ARRAY OF CHAR; class: INTEGER; val: Display.Frame);
	VAR new: Item;
BEGIN
	val.next:= MakeCaption(name, Display.FG, FALSE);
	NEW(new); COPY(name, new.name); new.val:= val; new.class:= class;
	new.next:= L.items; L.items:= new
END AddItem; 

PROCEDURE AddTitleItem(VAR L: Layout; str: ARRAY OF CHAR; cmds: Display.Frame);
	VAR f: Display.Frame; new: Item; 
BEGIN
	f:= MakeCaption(str, Display.FG, TRUE); f.next:= cmds;
	NEW(new); new.class:= Title; new.name:= "Title"; new.val:= f;
	new.next:= L.items; L.items:= new
END AddTitleItem;

PROCEDURE AddControlItem(VAR L: Layout; name, caption: ARRAY OF CHAR; val: Display.Frame);
	VAR new: Item; 
BEGIN
	val.next:= MakeCaption(caption, Display.FG, FALSE);
	NEW(new); new.class:= Control; COPY(name, new.name); new.val:= val;
	new.next:= L.items; L.items:= new
END AddControlItem;


	(* ---------------------- enumerators ----------------------- *)

(* Attribute enumerator: an attr. item is added to <layout>, if not already there. *)
PROCEDURE EnumAttr(name: ARRAY OF CHAR);
	VAR A: Objects.AttrMsg; i: Item; val: Display.Frame; s: ARRAY 2 OF CHAR;
BEGIN
	i:= layout.items; WHILE (i # NIL) & ((i.name # name) OR (i.class # Attribute)) DO i:= i.next END;
	IF i # NIL THEN RETURN END;

	A.id:= Objects.get; A.class:= Objects.Inval; COPY(name, A.name); A.res:= -1;
	enumObj.handle(enumObj, A);

	IF (A.res = -1) OR (A.class = Objects.Inval) THEN val:= MakeCaption("has no value", Display.FG, FALSE)
	ELSIF A.class = Objects.Bool THEN val:= MakeBool(A.b)
	ELSIF A.class = Objects.String THEN  val:= MakeString(A.s)
	ELSIF A.class = Objects.Int THEN val:= MakeInt(A.i)
	ELSIF A.class = Objects.Real THEN val:= MakeReal(A.x)
	ELSIF A.class = Objects.LongReal THEN val:= MakeReal(A.y)
	ELSIF A.class = Objects.Char THEN s[0]:= A.c; s[1]:= 0X; val:= MakeString(s)
	ELSE val:= MakeCaption("has unknown type", Display.FG, FALSE)
	END;
	AddItem(layout, name, Attribute, val)
END EnumAttr;

(* Link enumerator: a link item is add to <layout>, if not already there. *)
PROCEDURE EnumLink(name: ARRAY OF CHAR);
	VAR L: Objects.LinkMsg; i: Item;
BEGIN
	i:= layout.items; WHILE (i # NIL) & ((i.name # name) OR (i.class # Link)) DO i:= i.next END;
	IF i # NIL THEN RETURN END;

	L.id:= Objects.get; COPY (name, L.name); L.obj:= NIL; L.res := -1;
	enumObj.handle(enumObj, L);
	AddItem(layout, name, Link, MakeLink(L.obj, FALSE))
END EnumLink;


	(* ---------------------- main explore procedure ----------------------- *)

(* Inserts <frames> into <P> and resizes the it. Old objects in the panel are removed. *)
PROCEDURE MakePanel(P: Panels.Panel; frames: Display.Frame; border: INTEGER; new: BOOLEAN);
	VAR f: Display.Frame; x, y, w, h, cnt: INTEGER; A: Objects.AttrMsg; R: Display.ControlMsg;
			C: Display.ConsumeMsg; M: Display.ModifyMsg;
BEGIN
	Panels.BoundingBox(frames, x, y, w, h, cnt);

	(* remove old objects in panel *)
	R.id:= Display.remove; R.F:= NIL;
	f:= P.dsc;
	WHILE f # NIL DO f.slink:= R.F; R.F:= f; f:= f.next END;
	IF R.F # NIL THEN Display.Broadcast(R) END;

	(* size panel *)
	IF w + border*2 < Desktops.recDocWidth THEN w := Desktops.recDocWidth - 2*border END;
	IF new THEN P.W:= w + border*2; P.H:= h + border*2
	ELSE
		M.id:= Display.extend; M.F:= P; M.mode:= Display.display;
		M.W:= w + border*2; M.dW:= M.W - P.W; M.H:= h + border*2; M.dH:= M.H - P.H;
		M.X:= P.X; M.dX:= 0; M.Y:= P.Y + P.H - M.H; M.dY:= M.Y - P.Y;
		Display.Broadcast(M);
		A.id:= Objects.set; A.class:= Objects.Bool; A.name:= "Locked"; A.b:= FALSE; A.res:= -1;
		P.handle(P, A)
	END;

	(* insert new objects in panel *)
	C.id:= Display.drop; C.F:= P; C.obj:= frames; C.x:= 0; C.y:= 0;
	C.u:= border; C.v:= -border - h + 1; C.res:= -1; C.dlink:= NIL;
	P.handle(P, C);
	A.id:= Objects.set; A.class:= Objects.Bool; A.name:= "Locked"; A.b:= TRUE; A.res:= -1;
	P.handle(P, A)
END MakePanel;

(* Writes a reference, the library name and the lib. reference to the top right corner of the panel *)
PROCEDURE WriteGeneralObjInfo(obj: Objects.Object; VAR L: Layout);
	VAR f: Display.Frame; A: Objects.AttrMsg;
BEGIN
	WriteCaption(L, "Current Object", Display.FG, TRUE); WriteHSpace(L, 4); SetTab(L);
	f:= MakeLink(obj, FALSE);
	A.id:= Objects.set; A.class:= Objects.String; A.name:= "ConsumeCmd"; A.s:= "Columbus.InspectLink Value";
	A.res:= -1; f.handle(f, A);
	f(Gadgets.Frame).obj:= NIL;
	WriteFrame(L, f); WriteLn(L); WriteVSpace(L, 2);
END WriteGeneralObjInfo;

(* Writes library's name to the top, right corner of the panel *)
PROCEDURE WriteGeneralLibInfo(lib: Objects.Library; VAR L: Layout);
BEGIN
	WriteCaption(L, "Current Library", Display.FG, TRUE); WriteHSpace(L, 3);
	IF lib.name = "" THEN WriteCaption(L, "(Private)", Display.FG, FALSE)
	ELSE WriteCaption(L, lib.name, Display.FG, FALSE)
	END
END WriteGeneralLibInfo;

PROCEDURE InspectThis(VAR P: Panel; obj: Objects.Object; lib: Objects.Library; view: INTEGER);
	VAR int: BasicGadgets.Integer; h: HistoryItem; availViews:
			SET; i: INTEGER; new: BOOLEAN; subLay: Layout;
BEGIN
	new:= FALSE;
	IF P = NIL THEN NEW(P); InitPanel(P); new:= TRUE END;

	(* update panel's history *)
	h:= P.history;
	IF h = NIL THEN (* no history yet *)
		NEW(h); h.next:= P.history; P.history:= h; h.view:= NoView
	ELSIF h.view = NoView THEN (* current view is empty -> check if last was same *)
		h:= h.next;
		IF (h = NIL) OR (h.obj # obj) OR (h.lib # lib) THEN h:= P.history
		ELSE P.history:= h
		END
	ELSIF (h.obj # obj) OR (h.lib # lib) OR (h.view # view) THEN (* check if not same *)
		h:= NIL; NEW(h); h.next:= P.history; P.history:= h; h.view:= NoView
	END;
	IF h.view = NoView THEN h.obj:= obj; h.lib:= lib; h.view:= view END;

	(* write top, left corner *)
	OpenLayout(layout); layout.align:= middle;
	WriteLogo(layout, 104); WriteHSpace(layout, 104 - layout.X);
	WriteCmd(layout, "Columbus.Mag", "Columbus.Inspect", TRUE); WriteHSpace(layout, 2);
	IF P.history.next # NIL THEN WriteCmd(layout, "Columbus.Back", "Columbus.Back", TRUE) END;

	IF (obj = NIL) & (lib = NIL) THEN view:= NoView END;
	IF view < NoView THEN
		(* Get all available views *)
		i:= 0; availViews:= {};
		WHILE i < NoView DO
			IF (viewGens[i].canView # NIL) & viewGens[i].canView(obj, lib) THEN INCL(availViews, i) END;
			INC(i)
		END;
		(* Check if we can show desired view. If not, get first available view *)
		IF ~(view IN availViews) THEN
			view:= 0; WHILE ~(view IN availViews) & (view < NoView) DO INC(view) END;
		END;
		(* if there is a view, make panel *)
		IF view < NoView THEN
			(* write object or lib area (top, right corner) *)
			OpenLayout(subLay); subLay.align:= middle;
			IF view IN ObjViews THEN WriteGeneralObjInfo(obj, subLay)
			ELSE WriteGeneralLibInfo(lib, subLay)
			END;
			WriteLayout(layout, subLay);
			layout.frames.X:= PanelW - layout.frames.W - 1; (* hack *)
			WriteLn(layout);
			
			(* write view selection area *)
			OpenLayout(subLay);
			WriteVSpace(layout, 5);
			BasicGadgets.NewInteger; int:= Objects.NewObj(BasicGadgets.Integer);
			Gadgets.NameObj(int, ViewModeObjName);
			int.val:= view;
			i:= 0;
			WHILE i < NoView DO
				IF i IN availViews THEN
					IF i IN ObjViews THEN
						WriteFrame(layout, viewGens[i].getButton(int, obj, lib)); WriteHSpace(layout, 2)
					ELSE
						WriteHSpace(subLay, 2); WriteFrame(subLay, viewGens[i].getButton(int, obj, lib))
					END
				END;
				INC(i)
			END;
			IF subLay.frames # NIL THEN
				WriteLayout(layout, subLay);
				layout.frames.X:= PanelW - layout.frames.W - 1 (* hack *)
			END;

			(* write private area *)
			WriteLine(layout); WriteLn(layout);
			viewGens[view].makeView(obj, lib, layout)
		ELSE view:= NoView
		END
	END;
	WriteLn(layout);
	MakePanel(P, layout.frames, Border, new);
	P.items:= layout.items; 
END InspectThis;

(* ---------------------- attribute view ----------------------- *)

PROCEDURE CanViewAttr(obj: Objects.Object; lib: Objects.Library): BOOLEAN;
BEGIN RETURN obj # NIL
END CanViewAttr;

PROCEDURE AttrViewButton(model, obj: Objects.Object; lib: Objects.Library): Display.Frame;
	VAR f: Display.Frame;
BEGIN 
	f:= MakeCmd("Attr", "Columbus.InspectCurrent", FALSE);
	WITH f: BasicGadgets.Button DO
		f.obj:= model;
		f.setval:= ObjAttrView; f.popout:= FALSE; f.val:= (f.setval = model(BasicGadgets.Integer).val)
	END;
	RETURN f
END AttrViewButton;

PROCEDURE MakeAttrView(obj: Objects.Object; lib: Objects.Library; VAR L: Layout);
	VAR A: Objects.AttrMsg; cmds: Display.Frame;
BEGIN
	(* write attributes *)
	cmds:= MakeCmd("Apply", "Columbus.Apply", FALSE);
	AddTitleItem(L, "Attributes", cmds);
	A.id:= Objects.get; A.class:= Objects.String; A.name:= "Gen"; A.res:= -1; obj.handle(obj, A);
	AddItem(L, "Generator", Attribute, MakeCaption(A.s, Display.FG, FALSE));
	Gadgets.GetObjName(obj, A.s); AddItem(L, "Name", Attribute, MakeString(A.s));
	enumObj:= obj;
	A.id:= Objects.enum; A.Enum:= EnumAttr; obj.handle(obj, A);
	enumObj:= NIL;

	(* write attribute controls *)
	cmds:= MakeCmd("Add", "Columbus.Add", FALSE);
	cmds.next := MakeCmd("Del", "Columbus.Remove", FALSE);
	AddTitleItem(L, "New Attribute", cmds);
	AddControlItem(L, "AName", "Attr. Name", MakeString(""));
	AddControlItem(L, "AValue", "Attr. Value", MakeString(""));

	WriteItems(L, {Title, Attribute, Control})
END MakeAttrView;

(* ---------------------- link view ----------------------- *)

PROCEDURE CanViewLink(obj: Objects.Object; lib: Objects.Library): BOOLEAN;
BEGIN RETURN obj # NIL
END CanViewLink;

PROCEDURE LinkViewButton(model, obj: Objects.Object; lib: Objects.Library): Display.Frame;
	VAR f: Display.Frame;
BEGIN 
	f:= MakeCmd("Link", "Columbus.InspectCurrent", FALSE);
	WITH f: BasicGadgets.Button DO
		f.obj:= model;
		f.setval:= ObjLinkView; f.popout:= FALSE; f.val:= (f.setval = model(BasicGadgets.Integer).val)
	END;
	RETURN f
END LinkViewButton;

PROCEDURE MakeLinkView(obj: Objects.Object; lib: Objects.Library; VAR L: Layout);
	VAR cmds: Display.Frame; LM: Objects.LinkMsg;
BEGIN
	(* write links *)
	cmds:= MakeCmd("Apply", "Columbus.Apply", FALSE);
	AddTitleItem(L, "Links", cmds);
	enumObj:= obj;
	LM.id:= Objects.enum; LM.Enum:= EnumLink; obj.handle(obj, LM);
	enumObj:= NIL;
	IF L.items.class = Title THEN L.items:= L.items.next END;

	(* write link controls *)
	cmds:= MakeCmd("Add", "Columbus.Add", FALSE);
	cmds.next := MakeCmd("Del", "Columbus.Remove", FALSE);
	AddTitleItem(L, "New Link", cmds);
	AddControlItem(L, "LName", "Link Name", MakeString(""));
	AddControlItem(L, "LValue", "Link Value", MakeLink(NIL, FALSE));
	WriteItems(L, {Title, Link, Control})
END MakeLinkView;

(* ---------------------- coord view ----------------------- *)

PROCEDURE CanViewCoord(obj: Objects.Object; lib: Objects.Library): BOOLEAN;
BEGIN RETURN (obj # NIL) & (obj IS Gadgets.Frame)
END CanViewCoord;

PROCEDURE CoordViewButton(model, obj: Objects.Object; lib: Objects.Library): Display.Frame;
	VAR f: Display.Frame;
BEGIN 
	f:= MakeCmd("Coords", "Columbus.InspectCurrent", FALSE);
	WITH f: BasicGadgets.Button DO
		f.obj:= model;
		f.setval:= ObjCoordView; f.popout:= FALSE; f.val:= (f.setval = model(BasicGadgets.Integer).val)
	END;
	RETURN f
END CoordViewButton;

PROCEDURE MakeCoordView(obj: Objects.Object; lib: Objects.Library; VAR L: Layout);
	VAR cmds: Display.Frame;
BEGIN
	WITH obj: Gadgets.Frame DO
		(* write Coords *)
		cmds:= MakeCmd("Apply", "Columbus.Apply", FALSE);
		AddTitleItem(L, "Coordinates", cmds);
		AddItem(L, "X", Coord, MakeInt(obj.X));
		AddItem(L, "Y", Coord, MakeInt(obj.Y));
		AddItem(L, "W", Coord, MakeInt(obj.W));
		AddItem(L, "H", Coord, MakeInt(obj.H));

		WriteItems(L, {Coord, Title})
	END
END MakeCoordView;

(* ---------------------- def view ----------------------- *)

PROCEDURE CanViewDef(obj: Objects.Object; lib: Objects.Library): BOOLEAN;
BEGIN RETURN obj # NIL
END CanViewDef;

PROCEDURE DefViewButton(model, obj: Objects.Object; lib: Objects.Library): Display.Frame;
	VAR A: Objects.AttrMsg; str: ARRAY 64 OF CHAR;
BEGIN 
	A.id:= Objects.get; A.name:= "Gen"; A.res:= -1; obj.handle(obj, A);
	Append("Watson.ShowObj ", str); AppendCh(Oberon.OptionChar, str); Append("TMD ", str); Append(A.s, str);
	RETURN MakeCmd("Columbus.Def", str, TRUE)
END DefViewButton;

(* ---------------------- desc view ----------------------- *)

PROCEDURE CanViewDsc(obj: Objects.Object; lib: Objects.Library): BOOLEAN;
BEGIN RETURN (obj # NIL) & (obj IS Display.Frame) & (obj(Display.Frame).dsc # NIL)
END CanViewDsc;

PROCEDURE  DscViewButton(model, obj: Objects.Object; lib: Objects.Library): Display.Frame;
	VAR f: Display.Frame;
BEGIN 
	f:= MakeCmd("Comp", "Columbus.InspectCurrent", FALSE);
	WITH f: BasicGadgets.Button DO
		f.obj:= model;
		f.setval:= ObjDscView; f.popout:= FALSE; f.val:= (f.setval = model(BasicGadgets.Integer).val)
	END;
	RETURN f
END DscViewButton;

PROCEDURE MakeDscView(obj: Objects.Object; lib: Objects.Library; VAR L: Layout);
	VAR p: Panels.Panel; v: ScrollViews.View; o: Display.Frame; cnt: INTEGER;
			subLay: Layout; A: Objects.AttrMsg; M: Display.ModifyMsg;
			(* JSS Start *) Generator, Name: ARRAY 32 OF CHAR; offset: INTEGER; (* JSS End *)
BEGIN
	(* write objects in library *)
	OpenLayout(subLay); subLay.align:= middle;
	WriteHSpace(subLay, 150); SetTab(subLay);
	WriteLn(subLay);
	o:= obj(Display.Frame).dsc; cnt:= 0;
	WHILE o # NIL DO
		A.id:= Objects.get; A.name:= "Gen"; A.res:= -1; o.handle(o, A);
		(* JSS Start *)
		COPY(A.s,Generator);
		WriteCaption(subLay, A.s, Display.FG, FALSE); WriteTab(subLay);
		WriteFrame(subLay, MakeLink(o, TRUE)); 
		(* JSS Start of additions to display an indication of what the object does, e.g. its Name, Caption, Cmd or Value *)
        (* To do: An object such as a button with a Look (i.e. Icon) could do with the icon being displayed, and RefGadgets
                          could do with being handled in some way
        *)
        WriteTab(subLay);
        offset:= subLay.X;
        A.id := Objects.get;A.name := "Caption";A.res := -1;o.handle(o,A);
        COPY(A.s,Name);
        IF (Name = Generator)OR(Name = "") THEN
           A.id := Objects.get;A.name := "Name";A.res := -1;o.handle(o,A);COPY(A.s,Name);
           IF (Name = Generator)OR(Name = "") THEN
             A.id:= Objects.get;A.name:= "Cmd";A.res:= -1;o.handle(o,A);COPY(A.s,Name);
              IF (Name = Generator)OR(Name = "") THEN
                A.id := Objects.get;A.name := "Value";A.res := -1;o.handle(o,A);COPY(A.s,Name)
              END
           END
        END;
        IF (Name = Generator)OR(Name = "")   THEN
           Name := " "
        END;
        WriteCaption(subLay,Name,Display.FG,FALSE);
        (*JSS End of additions to display an indication of what the object does, e.g. its Name, Caption, Cmd or Value *)
        WriteLn(subLay);
		o:= o.next; INC(cnt)
	END;

	IF cnt > 10 THEN
		WriteHSpace(L, 17); WriteCaption(L, "Generator", Display.FG, TRUE);
		(* JSS Start *)
		WriteHSpace(L,offset - 50); (* The 50 was just a guess and seems to work *)
		WriteCaption(L,"Name/Caption/Cmd/Value",Display.FG,TRUE);
		(* JSS End *)
		WriteLn(L);
	
		Panels.NewPanel; p:= Objects.NewObj(Panels.Panel);
		INCL(p.state0, Panels.flatlook); p.borderW:= 0;
		MakePanel(p, subLay.frames, 2, TRUE);

		M.W:= p.W+20;
		v:= ScrollViews.ViewOf(p);
		ScrollViews.SetBars(v, TRUE, FALSE); INCL(v.state, Gadgets.lockedcontents);
		M.id:= Display.extend; M.mode:= Display.state; M.F:= v; M.res:= -1; M.dlink:= NIL;
		M.X:= v.X; M.H:= 205; M.Y:= v.Y + v.H - M.H;
		M.dX:= 0; M.dY:= M.Y - v.Y; M.dW:= M.W - v.W; M.dH:= M.H - v.H;
		Objects.Stamp(M); v.handle(v, M);
		
		WriteFrame(L, v)
	ELSE
		WriteCaption(L, "Generator", Display.FG, TRUE); 
				(* JSS Start *)
		WriteHSpace(L,offset - 50); (* The 50 was just a guess and seems to work *)
		WriteCaption(L,"Name/Caption/Cmd/Value",Display.FG,TRUE);
		(* JSS End *)
		WriteLn(L);
		WriteLayout(L, subLay)
	END
END MakeDscView;

(* ---------------------- lib editor ----------------------- *)

PROCEDURE CanViewEditor(obj: Objects.Object; lib: Objects.Library): BOOLEAN;
BEGIN RETURN (lib # NIL) & (lib.name # "")
END CanViewEditor;

PROCEDURE  LibEditorButton(model, obj: Objects.Object; lib: Objects.Library): Display.Frame;
	VAR f: Display.Frame;
BEGIN 
	f:= MakeCmd("Editor", "Columbus.InspectCurrent", FALSE);
	WITH f: BasicGadgets.Button DO
		f.obj:= model;
		f.setval:= LibEditView; f.popout:= FALSE; f.val:= (f.setval = model(BasicGadgets.Integer).val)
	END;
	RETURN f
END LibEditorButton;

PROCEDURE MakeLibContentsPanel(lib: Objects.Library): Panels.Panel;
	VAR obj: Objects.Object; f: Display.Frame; p: Panels.Panel; ref, i, j: INTEGER; name, refStr: Objects.Name;
			cmd: ARRAY 64 OF CHAR; A: Objects.AttrMsg; L: Layout;
BEGIN
	OpenLayout(L); L.align:= middle;
	IF lib # NIL THEN
		WriteHSpace(L, 150); SetTab(L);
		WriteHSpace(L, 40); SetTab(L);
		WriteHSpace(L, 117); SetTab(L);
		WriteLn(L);

		ref:= 0;
		WHILE ref <= lib.maxref DO
			Objects.GetName(lib.dict, ref, name);
			IF name # "" THEN
				lib.GetObj(lib, ref, obj);
				IF obj # NIL THEN
					A.id:= Objects.get; A.name:= "Gen"; A.res:= -1; obj.handle(obj, A);
					WriteCaption(L, A.s, Display.FG, FALSE); WriteTab(L);
					RefToStr(ref, refStr);
					WriteCaption(L, refStr, Display.FG, FALSE); WriteTab(L);
					cmd:= "Columbus.SetCurrent ";
					i:= 0; WHILE cmd[i] # 0X DO INC(i) END;
					j:= 0; WHILE lib.name[j] # "." DO cmd[i]:= lib.name[j]; INC(i); INC(j) END;
					cmd[i]:= "."; INC(i);
					j:= 0; WHILE name[j] # 0X DO cmd[i]:= name[j]; INC(i); INC(j) END;
					cmd[i]:= 0X;
					f:= MakeCmd(name, cmd, FALSE); f.W:= 115; f.H:= 20;
					WriteFrame(L, f); WriteTab(L);
					WriteFrame(L, MakeLink(obj, TRUE)); WriteLn(L)
				END
			END;
			INC(ref)
		END
	END;
	
	Panels.NewPanel; p:= Objects.NewObj(Panels.Panel);
	INCL(p.state0, Panels.flatlook); p.borderW:= 0;
	MakePanel(p, L.frames, 2, TRUE);
	IF p.W < 334 THEN p.W:= 334 END;
	IF p.H < 102 THEN p.H:= 102 END;
	RETURN p
END MakeLibContentsPanel;

PROCEDURE WriteCopyStyles(VAR L: Layout);
	VAR int: BasicGadgets.Integer; chBox: BasicGadgets.CheckBox;
BEGIN
	(* model *)
	BasicGadgets.NewInteger; int:= Objects.NewObj(BasicGadgets.Integer);
	int.val:= Objects.deep; Gadgets.NameObj(int, CopyStyleObj);
	(* ref checkbox *)
	BasicGadgets.NewCheckBox; chBox:= Objects.NewObj(BasicGadgets.CheckBox);
	chBox.obj:= int; chBox.setval:= -1; chBox.W:= 20; chBox.H:= 20; WriteFrame(L, chBox);
	WriteHSpace(L, 2); WriteCaption(L, "Ref", Display.FG, FALSE); WriteHSpace(L, 7);
	(* shallow checkbox *)
	BasicGadgets.NewCheckBox; chBox:= Objects.NewObj(BasicGadgets.CheckBox);
	chBox.obj:= int; chBox.setval:= Objects.shallow; chBox.W:= 20; chBox.H:= 20;
	WriteFrame(L, chBox);
	WriteHSpace(L, 2); WriteCaption(L, "SCopy", Display.FG, FALSE); WriteHSpace(L, 7);
	(* deep checkbox *)
	BasicGadgets.NewCheckBox; chBox:= Objects.NewObj(BasicGadgets.CheckBox);
	chBox.obj:= int; chBox.setval:= Objects.deep; chBox.W:= 20; chBox.H:= 20; chBox.val:= TRUE;
	WriteFrame(L, chBox);
	WriteHSpace(L, 2); WriteCaption(L, "DCopy", Display.FG, FALSE); WriteLn(L)
END WriteCopyStyles;
	
PROCEDURE MakeLibEditor(obj: Objects.Object; lib: Objects.Library; VAR L: Layout);
	VAR p: Panels.Panel; v: ScrollViews.View; f: Display.Frame; cmd, param0, param: ARRAY 64 OF CHAR;
			i: INTEGER; M: Display.ModifyMsg;
BEGIN
	WriteHSpace(L, 200);
	WriteCmd(L, "Unload", "Columbus.UnloadLib", FALSE);
	WriteCmd(L, "Cleanup", "Columbus.CleanupLib", FALSE);
	WriteCmd(L, "Store", "Columbus.StoreLib", FALSE);
	WriteLn(L); WriteVSpace(L, 8);

	WriteHSpace(L, 20); WriteCaption(L, "Generator", Display.FG, TRUE);
	WriteHSpace(L, 98); WriteCaption(L, "Ref", Display.FG, TRUE);
	WriteHSpace(L, 23); WriteCaption(L, "Name", Display.FG, TRUE);
	WriteLn(L);

	p:= MakeLibContentsPanel(lib);
	v:= ScrollViews.ViewOf(p); Gadgets.NameObj(v, ObjList);
	ScrollViews.SetBars(v, TRUE, FALSE); INCL(v.state, Gadgets.lockedcontents);
	M.id:= Display.extend; M.mode:= Display.state; M.F:= v; M.res:= -1; M.dlink:= NIL;
	M.W:= p.W+20; M.H:= 104; M.X:= v.X; M.Y:= v.Y + v.H - M.H;
	M.dX:= 0; M.dY:= M.Y - v.Y; M.dW:= M.W - v.W; M.dH:= M.H - v.H;
	Objects.Stamp(M); v.handle(v, M);
	WriteFrame(L, v); WriteLn(L);

	WriteLine(L); WriteLn(L); WriteVSpace(L, 2);
	WriteCaption(L, "Object", Display.FG, TRUE); WriteHSpace(L, 4); SetTab(L); 
	f:= MakeString(""); f.W:= MediumW; Gadgets.NameObj(f, ObjNameObj);
	WriteFrame(L, f);
	WriteLn(L); WriteVSpace(L, 6);

	COPY(lib.name, param0);
	i:= 0; WHILE (param0[i] # ".") & (param0[i] # 0X) DO INC(i) END;
	param0[i]:= 0X; Append(".&", param0); 
	COPY (param0, param); Append(ObjNameObj, param); Append(".Value", param);

	cmd:= "Columbus.GetObj "; Append(param, cmd);
	WriteTab(L); WriteCmd(L, "Retrieve", cmd, FALSE);
	WriteHSpace(L, 8); WriteCopyStyles(L);
	WriteLn(L);

	
	cmd:= "Columbus.RenameObj "; Append(param, cmd);
	Append("  &", cmd); Append(RNameObj, cmd); Append(".Value", cmd);
	WriteTab(L); WriteCmd(L, "Rename", cmd, FALSE);
	WriteHSpace(L, 8); f:= MakeString(""); f.W:= MediumW; Gadgets.NameObj(f, RNameObj); WriteFrame(L, f);
	WriteLn(L);

	cmd:= "Columbus.AddObj "; Append(param0, cmd);
	Append(NNameObj, cmd); Append(".Value", cmd);
	WriteTab(L); WriteCmd(L, "Install", cmd, FALSE);
	WriteHSpace(L, 8); f:= MakeString(""); f.W:= MediumW; Gadgets.NameObj(f, NNameObj); WriteFrame(L, f);
	WriteHSpace(L, 4); f:= MakeLink(NIL, FALSE); Gadgets.NameObj(f, RefObj); WriteFrame(L, f);
	WriteLn(L);

	cmd:= "Columbus.FreeObj "; Append(param, cmd);
	WriteTab(L); WriteCmd(L, "Free", cmd, FALSE)
END MakeLibEditor;

(* ---------------------- lib view ----------------------- *)

PROCEDURE CanViewLib(obj: Objects.Object; lib: Objects.Library): BOOLEAN;
BEGIN RETURN lib # NIL
END CanViewLib;

PROCEDURE  LibViewButton(model, obj: Objects.Object; lib: Objects.Library): Display.Frame;
	VAR f: Display.Frame;
BEGIN 
	f:= MakeCmd("Lib", "Columbus.InspectCurrent", FALSE);
	WITH f: BasicGadgets.Button DO
		f.obj:= model;
		f.setval:= LibOverView; f.popout:= FALSE; f.val:= (f.setval = model(BasicGadgets.Integer).val)
	END;
	RETURN f
END LibViewButton;

PROCEDURE MakeLibView(obj: Objects.Object; lib: Objects.Library; VAR L: Layout);
	VAR o: Objects.Object; v: ScrollViews.View; p: Panels.Panel; name: Objects.Name; ref, cnt: INTEGER;
			col: SHORTINT; public: BOOLEAN; A: Objects.AttrMsg; subLay: Layout; M: Display.ModifyMsg;
BEGIN
	public:= lib.name # "";
	(* write objects in library *)
	OpenLayout(subLay); subLay.align:= middle;
	WriteHSpace(subLay, 150); SetTab(subLay);
	WriteHSpace(subLay, 40); SetTab(subLay);
	WriteHSpace(subLay, 120); SetTab(subLay);
	WriteLn(subLay);

	ref:= 0; cnt:= 0;
	WHILE ref <= lib.maxref DO 
		lib.GetObj(lib, ref, o);
		IF o # NIL THEN
			IF o = obj THEN col:= 3 ELSE col:= Display.FG END;
			A.id:= Objects.get; A.name:= "Gen"; A.res:= -1; o.handle(o, A);
			WriteCaption(subLay, A.s, col, FALSE); WriteTab(subLay);
			RefToStr(ref, name);
			WriteCaption(subLay, name, col, FALSE); WriteTab(subLay);
			IF public THEN
				Objects.GetName(lib.dict, ref, name);
				IF name # "" THEN WriteCaption(subLay, name, col, FALSE) END;
				WriteTab(subLay)
			END;
			WriteFrame(subLay, MakeLink(o, TRUE)); WriteLn(subLay);
			INC(cnt)
		END;
		INC(ref)
	END;
	
	WriteVSpace(L, 2);
	IF cnt = 0 THEN
		WriteVSpace(L, 4); WriteCaption(L, "(empty library)", Display.FG, FALSE)
	ELSIF cnt > 10 THEN
		WriteHSpace(L, 17); WriteCaption(L, "Generator", Display.FG, TRUE);
		WriteHSpace(L, 98); WriteCaption(L, "Ref", Display.FG, TRUE);
		IF public THEN WriteHSpace(L, 23); WriteCaption(L, "Name", Display.FG, TRUE) END;
		WriteLn(L);
	
		Panels.NewPanel; p:= Objects.NewObj(Panels.Panel);
		INCL(p.state0, Panels.flatlook); p.borderW:= 0;
		MakePanel(p, subLay.frames, 2, TRUE);

		v:= ScrollViews.ViewOf(p);
		ScrollViews.SetBars(v, TRUE, FALSE); INCL(v.state, Gadgets.lockedcontents);
		M.id:= Display.extend; M.mode:= Display.state; M.F:= v; M.res:= -1; M.dlink:= NIL;
		M.W:= p.W+20; M.H:= 205; M.X:= v.X; M.Y:= v.Y + v.H - M.H;
		M.dX:= 0; M.dY:= M.Y - v.Y; M.dW:= M.W - v.W; M.dH:= M.H - v.H;
		Objects.Stamp(M); v.handle(v, M);
		WriteFrame(L, v)
	ELSE
		WriteCaption(L, "Generator", Display.FG, TRUE);
		WriteHSpace(L, 98); WriteCaption(L, "Ref", Display.FG, TRUE);
		IF public THEN WriteHSpace(L, 23); WriteCaption(L, "Name", Display.FG, TRUE) END;
		WriteLn(L); WriteLayout(L, subLay)
	END
END MakeLibView;


(* ---------------------- set & store procs ----------------------- *)

PROCEDURE EnumOldAttrValues (name: ARRAY OF CHAR);
VAR A: Objects.AttrMsg; i: Item;
BEGIN
	i:= oldValues; WHILE (i # NIL) & ((i.name # name) OR (i.class # Attribute)) DO i:= i.next END;
	IF i = NIL THEN
		A.id:= Objects.get; A.class:= Objects.Inval; COPY(name, A.name); A.res:= -1;
		enumObj.handle(enumObj, A);
		NEW(i); i.class := Attribute; COPY(name, i.name); i.next := oldValues; oldValues := i;

		IF (A.res < 0) OR (A.class = Objects.Inval) THEN i.val := NIL
		ELSIF A.class = Objects.Bool THEN
			i.val := Gadgets.CreateObject("Boolean"); i.val(BasicGadgets.Boolean).val := A.b
		ELSIF A.class = Objects.String THEN
			i.val := Gadgets.CreateObject("String"); COPY(A.s, i.val(BasicGadgets.String).val)
		ELSIF A.class = Objects.Int THEN
			i.val := Gadgets.CreateObject("Integer"); i.val(BasicGadgets.Integer).val := A.i
		ELSIF A.class = Objects.Real THEN
			i.val := Gadgets.CreateObject("Real"); i.val(BasicGadgets.Real).val := A.x
		ELSIF A.class = Objects.LongReal THEN
			i.val := Gadgets.CreateObject("Real"); i.val(BasicGadgets.Real).val := A.y
		ELSIF A.class = Objects.Char THEN
			A.s[0]:= A.c; A.s[1]:= 0X;
			i.val:= Gadgets.CreateObject("String"); COPY(A.s, i.val(BasicGadgets.String).val)
		ELSE i.val := NIL
		END
	END
END EnumOldAttrValues;

PROCEDURE EnumOldLinkValues (name: ARRAY OF CHAR);
VAR L: Objects.LinkMsg; i: Item;
BEGIN
	i:= oldValues; WHILE (i # NIL) & ((i.name # name) OR (i.class # Link)) DO i:= i.next END;
	IF i = NIL THEN
		L.id:= Objects.get; COPY (name, L.name); L.obj:= NIL; L.res := -1;
		enumObj.handle(enumObj, L);
		NEW(i); i.class := Link; COPY(name, i.name); i.val := L.obj; i.next := oldValues; oldValues := i
	END
END EnumOldLinkValues;

(* Sets attributes and links to <obj>. The values are taken from panels item list. A attr. or link
	is just set if it already exists and its value has changed. The function returns true if something
	has changed. *)
PROCEDURE SetObject(obj: Objects.Object; P: Panel): BOOLEAN;
	VAR item: Item; changeV, changeC: BOOLEAN;
			A: Objects.AttrMsg; L: Objects.LinkMsg; M: Display.ModifyMsg;

		(* returns TRUE if value exists and is different from the old one. *)
		PROCEDURE HasValue(item: Item): BOOLEAN;
		VAR i: Item; A0, A1: Objects.AttrMsg; res: BOOLEAN;
		BEGIN
			res := FALSE;
			i := oldValues; WHILE (i # NIL) & ((i.class # item.class) OR (i.name # item.name)) DO i := i.next END;
			IF i # NIL THEN
				IF i.class = Link THEN
					res := (item.val(RefGadgets.Reference).val # i.val)
				ELSIF (i.val # NIL) & (item.val # NIL) THEN
					A0.id := Objects.get; A0.class := Objects.Inval; COPY("Value", A0.name); A0.res := -1;
					A1 := A0;
					i.val.handle(i.val, A0); item.val.handle(item.val, A1);
					IF (A0.class = A1.class) & (A0.res >= 0) & (A1.res >= 0) & (A0.class # Objects.Inval) THEN
						IF A0.class = Objects.Bool THEN res := (A0.b # A1.b)
						ELSIF A0.class = Objects.String THEN res := (A0.s # A1.s)
						ELSIF A0.class = Objects.Int THEN res := (A0.i # A1.i)
						ELSIF A0.class = Objects.Real THEN res := (A0.x # A1.x)
						ELSIF A0.class = Objects.LongReal THEN res := (A0.y # A1.y)
						ELSIF A0.class = Objects.Char THEN res := (A0.c # A1.c)
						END
					END
				END
			END;
			RETURN res
		END HasValue;

BEGIN
	(* get a list of old values *)
	enumObj := obj;
	NEW(oldValues); oldValues.next := NIL; oldValues.class := Attribute; COPY("Name", oldValues.name);
	oldValues.val := Gadgets.CreateObject("String");
	Attributes.GetString(obj, "Name", oldValues.val(BasicGadgets.String).val); 
	A.id := Objects.enum; A.Enum := EnumOldAttrValues; obj.handle(obj, A);
	L.id := Objects.enum; L.Enum := EnumOldLinkValues; obj.handle(obj, L);
	enumObj := NIL;

	item:= P.items; changeC:= FALSE; changeV := FALSE;
	WHILE item #NIL DO
		IF (item.class = Attribute) & HasValue(item) THEN
			A.id:= Objects.set; COPY(item.name, A.name); A.res:= -1;
			IF item.val IS BasicGadgets.Boolean THEN
				A.class:= Objects.Bool; A.b:= item.val(BasicGadgets.Boolean).val
			ELSIF item.val IS BasicGadgets.Integer THEN
				A.class:= Objects.Int; A.i:= item.val(BasicGadgets.Integer).val
			ELSIF item.val IS BasicGadgets.Real THEN
				A.class:= Objects.LongReal; A.y:= item.val(BasicGadgets.Real).val
			ELSIF item.val IS BasicGadgets.String THEN
				A.class:= Objects.String; COPY(item.val(BasicGadgets.String).val, A.s)
			ELSE A.class:= Objects.Inval
			END;
			IF A.class # Objects.Inval THEN
				obj.handle(obj, A);
				IF (A.res < 0) & (A.class = Objects.LongReal) THEN
					A.class := Objects.Real; A.x := SHORT(A.y);
					obj.handle(obj, A)
				END;
				IF A.res < 0 THEN
					String("Attribute "); String(item.name); String(" could not be set");
					Ln; ToLog
				ELSE changeV := TRUE;
				END
			END
		ELSIF (item.class = Link) & HasValue(item) THEN
			L.id:= Objects.set; COPY(item.name, L.name); L.res:= -1;
			L.obj:= item.val(RefGadgets.Reference).val;
			IF (L.obj # NIL) & Gadgets.Recursive(obj, L.obj) THEN
				String("Link "); String(item.name); String(" could not be set (recursion)");
				Ln; ToLog
			ELSE
				obj.handle(obj, L);
				IF L.res < 0 THEN
					String("Link "); String(item.name); String(" could not be set");
					Ln; ToLog
				ELSE changeV := TRUE
				END
			END
		ELSIF (item.class = Coord) & (obj IS Display.Frame) THEN
			changeC:= TRUE;
			IF item.name = "X" THEN M.X:= SHORT(item.val(BasicGadgets.Integer).val)
			ELSIF item.name = "Y" THEN M.Y:= SHORT(item.val(BasicGadgets.Integer).val)
			ELSIF item.name = "W" THEN M.W:= SHORT(item.val(BasicGadgets.Integer).val)
			ELSIF item.name = "H" THEN M.H:= SHORT(item.val(BasicGadgets.Integer).val)
			END
		END;
		item:= item.next
	END;
	oldValues := NIL;	(* garbage collection *)

	IF changeC & (obj IS Display.Frame) THEN
		WITH obj: Display.Frame DO
			M.dX:= M.X - obj.X; M.dY:= M.Y - obj.Y; M.dW:= M.W - obj.W; M.dH:= M.H - obj.H;
			M.F:= obj; M.res:= -1; M.id:= Display.move; M.mode:= Display.display;
			IF (M.dX # 0) OR (M.dY # 0) OR (M.dW # 0) OR (M.dH # 0) THEN
				Display.Broadcast(M);
				IF M.res < 0 THEN obj.X := M.X; obj.Y := M.Y; obj.W := M.W; obj.H := M.H END
			END
		END
	END;
	RETURN changeV OR changeC
END SetObject;

(* Adds one attribute/link to <obj>. The values for the attribute's name and attribute's value
	or link's name and link's object is taken from panel's item list. *)
PROCEDURE SetNewAttrLink(obj: Objects.Object; P: Panel);
	VAR T: Texts.Text; item: Item; A: Objects.AttrMsg; L: Objects.LinkMsg; S: Texts.Scanner;
BEGIN
	A.name:= ""; A.class:= Objects.Inval; L.name:= ""; L.obj:= NIL;
	item:= P.items;
	WHILE item # NIL DO
		IF (item.name = "AName") & (item.val IS BasicGadgets.String) THEN
			COPY(item.val(BasicGadgets.String).val, A.name)
		ELSIF (item.name = "LName") & (item.val IS BasicGadgets.String) THEN
			COPY(item.val(BasicGadgets.String).val, L.name)
		ELSIF (item.name = "AValue") & (item.val IS BasicGadgets.String) THEN
			IF item.val(BasicGadgets.String).val # "" THEN
				NEW(T); Texts.Open(T, ""); String(item.val(BasicGadgets.String).val);
				Texts.Append(T, W.buf);
				Texts.OpenScanner(S, T, 0); Texts.Scan(S);
				IF S.class = Texts.Int THEN A.class:= Objects.Int; A.i:= S.i
				ELSIF S.class = Texts.Real THEN A.class:= Objects.Real; A.x:= S.x
				ELSIF S.class = Texts.LongReal THEN A.class:= Objects.LongReal; A.y:= S.y
				ELSIF (S.class = Texts.Char) & (T.len = 1) THEN A.class:= Objects.Char; A.c:= S.c
				ELSIF (S.s = "Yes") OR (S.s = "No") THEN A.class := Objects.Bool; Strings.StrToBool(S.s, A.b)
				ELSIF S.class IN {Texts.Name, Texts.String} THEN A.class := Objects.String; COPY(S.s, A.s)
				ELSE A.class:= Objects.String; COPY(item.val(BasicGadgets.String).val, A.s)
				END
			END
		ELSIF (item.name = "LValue") & (item.val IS RefGadgets.Reference) THEN
			L.obj:= item.val(RefGadgets.Reference).val
		END;
		item:= item.next
	END;

	(* add attribute *)
	IF (A.name # "") & (A.class # Objects.Inval) THEN
		A.id:= Objects.set; A.res:= -1; obj.handle(obj, A);
		IF A.res < 0 THEN String("Attribute "); String(A.name); String(" could not be set"); Ln; ToLog END
	END;

	(* add link *)
	IF (L.name # "") & (L.obj # NIL) THEN
		L.id:= Objects.set; L.res:= -1; obj.handle(obj, L);
		IF L.res < 0 THEN String("Link "); String(L.name); String(" could not be set"); Ln; ToLog END
	END
END SetNewAttrLink;

(* Removes one attribute/link to <obj>. The values for the attribute's or link's name is taken from panel's item list. *)
PROCEDURE RemoveAttrLink(obj: Objects.Object; P: Panel);
	VAR item: Item; name: ARRAY 64 OF CHAR; attribute: BOOLEAN;
BEGIN
	name:= ""; item:= P.items;
	WHILE item # NIL DO
		IF (item.name = "AName") & (item.val IS BasicGadgets.String) THEN
			COPY(item.val(BasicGadgets.String).val, name); attribute:= TRUE
		ELSIF (item.name = "LName") & (item.val IS BasicGadgets.String) THEN
			COPY(item.val(BasicGadgets.String).val, name); attribute:= FALSE
		END;
		item:= item.next
	END;

	IF name # "" THEN
		IF attribute THEN
			IF obj IS Gadgets.Object THEN Attributes.DeleteAttr(obj(Gadgets.Object).attr, name)
			ELSIF obj IS Gadgets.Frame THEN Attributes.DeleteAttr(obj(Gadgets.Frame).attr, name)
			END
		ELSE
			IF obj IS Gadgets.Object THEN Links.DeleteLink(obj(Gadgets.Object).link, name)
			ELSIF obj IS Gadgets.Frame THEN Links.DeleteLink(obj(Gadgets.Frame).link, name)
			END
		END
	END
END RemoveAttrLink;

	(* ---------------------- common help proceudre for commands ----------------------- *)

(* Gets the object/library to inspect. The order is 1. parameter, 2. selection, 3. marker. *)
PROCEDURE GetObjLib(VAR obj: Objects.Object; VAR lib: Objects.Library);
	VAR f: Display.Frame; T: Texts.Text; t1, t2, beg, end: LONGINT; S: Attributes.Scanner;

	PROCEDURE GetNamed;	(* affects local var lib, obj *)
		VAR i: INTEGER;
	BEGIN
		obj:= Gadgets.FindPublicObj(S.s);
		IF obj = NIL THEN
			i:= 0; WHILE (S.s[i] # 0X) & (S.s[i] # ".") DO INC(i) END;
			S.s[i]:= "."; S.s[i+1]:= "L"; S.s[i+2]:= "i"; S.s[i+3]:= "b"; S.s[i+4]:= 0X;
			lib:= Objects.ThisLibrary(S.s)
		ELSE lib:= obj.lib
		END 
	END GetNamed;

BEGIN
	(* read in parameter, if there is one *)
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Attributes.Scan(S);
	IF S.class IN {Attributes.String, Attributes.Name} THEN (* get public object/library *)
		GetNamed
	ELSE (* no param -> check selection, marker *)
		Gadgets.GetSelection(obj, t2);
		Oberon.GetSelection(T, beg, end, t1);
		IF t1 >= 0 THEN Attributes.OpenScanner(S, T, beg); Attributes.Scan(S)
		ELSE S.class:= Attributes.Inval
		END;
		IF (t2 >= 0) & (t1 < t2) THEN (* get selected object *)
			Gadgets.GetSelection(obj, t2);
			IF t2 >= 0 THEN lib:= obj.lib END
		ELSIF S.class IN {Attributes.String, Attributes.Name} THEN (* get public object/Library *)
			GetNamed
		ELSIF Oberon.Pointer.on THEN (* get marked object, if any *)
			f := Oberon.MarkedFrame();
			obj:= f; IF obj # NIL THEN lib:= obj.lib END
		END
	END
END GetObjLib;

(* Tries to find a Columbus.Panel in the dlink chain, starting at the current context. *)
PROCEDURE FindPanel(): Panel;
	VAR p: Objects.Object;
BEGIN
	p:= Gadgets.context;
	WHILE (p # NIL) & ~(p IS Panel) DO p:= p.dlink END;
	IF p  = NIL THEN RETURN NIL ELSE RETURN p(Panel) END
END FindPanel;

PROCEDURE GetViewMode(P: Panel): INTEGER;
	VAR modeObj: Objects.Object; mode: INTEGER;
BEGIN
	mode:= ObjAttrView;
	IF P # NIL THEN
		modeObj:= Gadgets.FindObj(P, ViewModeObjName);
		IF (modeObj # NIL) & (modeObj IS BasicGadgets.Integer) THEN
			mode:= SHORT(modeObj(BasicGadgets.Integer).val)
		END
	END;
	RETURN mode
END GetViewMode;

	(** ---------------------- columbus inspector commands ----------------------- *)

PROCEDURE InspectObj*(obj: Objects.Object);
	VAR P: Panel; D: Documents.Document;
BEGIN
	InspectThis(P, obj, NIL, ObjAttrView);
	IF Oberon.Pointer.on THEN Oberon.FadeCursor(Oberon.Pointer) END;
	NewDoc; D:= Objects.NewObj(Documents.Document);
	D.W:= P.W; D.H:= P.H; Documents.Init(D, P); D.name:= DocName;
	Desktops.ShowDoc(D);
	IF ~msgPrinted THEN PrintMsg END
END InspectObj;

(** Used in the form:	Columbus.Inspect [<Name>]

Inspects object or library. The target object or library can be specified by...
	- <Name>, name of a public object/library
	- a selected frame or a selected name of public a object/library
	- the marked frame 
The panel is opened in the attribute view. An existing Columbus panel is set to the attribute view, if the command is initiated within such a panel (magnifier button). If no target can be detected, a so-called empty panel is opened (an existing panel changes to this state, too). 
*)
PROCEDURE Inspect*;
	VAR obj: Objects.Object; lib: Objects.Library; P: Panel; D: Documents.Document; new: BOOLEAN;
BEGIN
	P:= FindPanel(); new:= (P = NIL);

	(* get object and/or library *)
	obj:= NIL; lib:= NIL; GetObjLib(obj, lib);

	(* make panel *)
	IF (obj # NIL) OR (lib # NIL) THEN
		InspectThis(P, obj, lib, ObjAttrView);
	ELSE
		InspectThis(P, NIL, NIL, NoView)
	END;
	IF new THEN
		IF Oberon.Pointer.on THEN Oberon.FadeCursor(Oberon.Pointer) END;
		NewDoc; D:= Objects.NewObj(Documents.Document);
		D.W:= P.W; D.H:= P.H; 
		Documents.Init(D, P); D.name:= DocName;
		Desktops.ShowDoc(D)
	END;
	IF ~msgPrinted THEN PrintMsg END
END Inspect;

(** Used in the form:	Columbus.InspectLink <LinkName>

Inspects the executor's link <LinkName>. The panel is opened in the attribute view. Columbus panels are automatically set to the attribute view, when initiating this command (reference gadgets on the panel use this command).
*)
PROCEDURE InspectLink*;
	VAR D: Documents.Document; obj: Objects.Object; P: Panel; new: BOOLEAN;
			L: Objects.LinkMsg; S: Attributes.Scanner;
BEGIN
	obj:= Oberon.Par.obj;
	IF obj # NIL THEN 
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Attributes.Scan(S);
		IF S.class IN {Attributes.String, Attributes.Name} THEN 
			P:= FindPanel(); new:= (P = NIL);
			L.id:= Objects.get; L.res:= -1; COPY(S.s, L.name); obj.handle(obj, L);
			IF L.obj # NIL THEN
				InspectThis(P, L.obj, L.obj.lib, ObjAttrView)
			ELSE
				InspectThis(P, NIL, NIL, NoView)
			END;
			IF new THEN
				NewDoc; D:= Objects.NewObj(Documents.Document);
				D.W:= P.W; D.H:= P.H; Documents.Init(D, P); D.name:= DocName;
				Desktops.ShowDoc(D)
			END
		END
	END;
	IF ~msgPrinted THEN PrintMsg END
END InspectLink;


	(** ---------------------- commands only usefull within Columbus ----------------------- *)

(** Inspects panel's current object/library *)
PROCEDURE InspectCurrent*;
	VAR P: Panel;
BEGIN
	P:= FindPanel();
	IF (P # NIL) & (P.history # NIL) THEN
		InspectThis(P, P.history.obj, P.history.lib, GetViewMode(P))
	END
END InspectCurrent;

(** Applies attributes or links to the panel's current object *)
PROCEDURE Apply*;
	VAR P: Panel; U: Gadgets.UpdateMsg;
BEGIN
	P:= FindPanel(); Oberon.Defocus;
	IF (P # NIL) & (P.history # NIL) THEN
		IF P.history.obj # NIL THEN
			IF SetObject(P.history.obj ,P) THEN
				U.obj:= P.history.obj; U.obj.slink:= NIL; U.F:= NIL;
				Display.Broadcast(U);
				InspectThis(P, P.history.obj, P.history.lib, P.history.view)
			END
		ELSE String("[No current object]"); Ln; ToLog
		END
	END
END Apply;

(** Applies attributes or links to the selected gadget frames *)
PROCEDURE ApplyTo*;
	VAR P: Panel; obj: Objects.Object; update: BOOLEAN; M: Display.SelectMsg; U: Gadgets.UpdateMsg;
BEGIN
	P:= FindPanel(); Oberon.Defocus;
	IF (P # NIL) & (P.history # NIL) THEN
		IF P.history.obj # NIL THEN
			M.id:= Display.get; M.time:= 0; M.F:= NIL; M.obj:= NIL; Display.Broadcast(M);
			IF M.obj # NIL THEN
				obj:= M.obj; update := FALSE;
				WHILE obj #NIL DO update := update OR SetObject(obj ,P); obj:= obj.slink END;
				IF update THEN U.obj:= M.obj;  U.F:= NIL; Display.Broadcast(U) END
			ELSE String("[No selection]"); Ln; ToLog
			END
		ELSE String("[No current object]"); Ln; ToLog
		END
	END
END ApplyTo;

(** Adds a new attribute or link to the panel's current object *)
PROCEDURE Add*;
	VAR P: Panel; U: Gadgets.UpdateMsg;
BEGIN
	P:= FindPanel(); Oberon.Defocus;
	IF (P # NIL) & (P.history # NIL) THEN	
		IF P.history.obj # NIL THEN
			SetNewAttrLink(P.history.obj, P);
			U.obj:= P.history.obj; U.obj.slink:= NIL; U.F:= NIL; Display.Broadcast(U);
			InspectThis(P, P.history.obj, P.history.lib, P.history.view)
		ELSE String("[No current object]"); Ln; ToLog
		END
	END
END Add;

(** Adds a new attribute or link to the selected gadget frames *)
PROCEDURE AddTo*;
	VAR P: Panel; obj: Objects.Object; M: Display.SelectMsg; U: Gadgets.UpdateMsg;
BEGIN
	P:= FindPanel(); Oberon.Defocus;
	IF (P # NIL) & (P.history # NIL) THEN	
		IF P.history.obj # NIL THEN
			M.id:= Display.get; M.time:= 0; M.F:= NIL; M.obj:= NIL; Display.Broadcast(M);
			IF M.obj # NIL THEN
				obj:= M.obj;
				WHILE obj # NIL DO SetNewAttrLink(obj, P); obj:= obj.slink END;
				U.obj:= M.obj; U.F:= NIL; Display.Broadcast(U)
			ELSE String("[No selection]"); Ln; ToLog
			END
		ELSE String("[No current object]"); Ln; ToLog
		END
	END
END AddTo;

(** Removes an attribute or link from the panel's current object *)
PROCEDURE Remove*;
	VAR P: Panel; U: Gadgets.UpdateMsg;
BEGIN
	P:= FindPanel(); Oberon.Defocus;
	IF (P # NIL) & (P.history # NIL) THEN	
		IF P.history.obj # NIL THEN
			RemoveAttrLink(P.history.obj, P);
			U.obj:= P.history.obj; U.obj.slink:= NIL; U.F:= NIL; Display.Broadcast(U);
			InspectThis(P, P.history.obj, P.history.lib, P.history.view)
		ELSE String("[No current object]"); Ln; ToLog
		END
	END
END Remove;

(** Removes an attribute or link from the selected gadget frames *)
PROCEDURE RemoveFrom*;
	VAR P: Panel; obj: Objects.Object; M: Display.SelectMsg; U: Gadgets.UpdateMsg;
BEGIN
	P:= FindPanel(); Oberon.Defocus;
	IF (P # NIL) & (P.history # NIL) THEN	
		IF P.history.obj # NIL THEN
			M.id:= Display.get; M.time:= 0; M.F:= NIL; M.obj:= NIL; Display.Broadcast(M);
			IF M.obj # NIL THEN
				obj:= M.obj;
				WHILE obj # NIL DO RemoveAttrLink(obj, P); obj:= obj.slink END;
				U.obj:= M.obj; U.F:= NIL; Display.Broadcast(U)
			ELSE String("[No selection]"); Ln; ToLog
			END
		ELSE String("[No current object]"); Ln; ToLog
		END
	END
END RemoveFrom;

(** Goes back one step in the panel's history *)
PROCEDURE Back*;
	VAR P: Panel; h: HistoryItem;
BEGIN
	P:= FindPanel();
	IF (P # NIL) & (P.history # NIL) THEN
		h:= P.history.next;
		IF h # NIL THEN
			P.history:= h;
			InspectThis(P, h.obj, h.lib, h.view)
		END
	END
END Back;


	(* ---------------------- library editor aux. proceudres ----------------------- *)

(* Renames the file "<name>" to "<name>.Bak". *)
PROCEDURE Backup (VAR name: ARRAY OF CHAR);
	VAR res, i: INTEGER; bak: ARRAY 64 OF CHAR;
BEGIN i := 0;
	WHILE name[i] # 0X DO bak[i]:= name[i]; INC(i) END;
	bak[i] := "."; bak[i+1] := "B"; bak[i+2] := "a"; bak[i+3] := "k"; bak[i+4] := 0X;
	Files.Rename(name, bak, res)
END Backup;

(* Splits <name> into two parts. First part starts at the beginning of <name> and ends at the first
	occurance of a "." or at the end of <name>. This part of the string will be copied to <libname>
	and the ".Lib" extension is added. The rest of <name> is copied to <objname>. *)
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

PROCEDURE OpenText(name: ARRAY OF CHAR; T: Texts.Text);
	VAR D: Objects.Object; F: TextGadgets.Frame;
BEGIN
	D := Gadgets.CreateObject("TextDocs.NewDoc");
	WITH D: Documents.Document DO
		COPY(name, D.name);
		NEW(F); TextGadgets.Init(F, T, FALSE);
		Documents.Init(D, F);
		Desktops.ShowDoc(D)
	END
END OpenText;

PROCEDURE SetTextToList(list: Objects.Object; T: Texts.Text);
	VAR d: ListRiders.String; listR: ListRiders.Rider; S: Texts.Scanner; M: ListRiders.ConnectMsg;
BEGIN
	M.R := NIL; list.handle(list, M); 
	IF M.R # NIL THEN
		listR := M.R;
		WHILE ~listR.eol DO listR.do.DeleteLink(NIL, listR) END;
		Texts.OpenScanner(S, T, 0); Texts.Scan(S);
		WHILE S.class IN {Texts.String, Texts.Name} DO
			NEW(d); COPY(S.s, d.s); listR.do.Write(listR, d);
			Texts.Scan(S)
		END;
		Gadgets.Update(list)
	END
END SetTextToList;

(* Returns value of object named "copystyle" in the current context. If the object could not
	be found, copy style deep is returned. *)
PROCEDURE GetCopyStyle(): INTEGER;
	VAR obj: Objects.Object; style: INTEGER; A: Objects.AttrMsg;
BEGIN
	style:= Objects.deep;
	obj:= Gadgets.FindObj(Gadgets.context, CopyStyleObj);
	IF obj # NIL THEN
		A.id := Objects.get; A.name := "Value"; A.res := -1; obj.handle(obj, A);
		IF (A.res >= 0) & (A.class = Objects.Int) THEN style:= SHORT(A.i) END;
		IF (style < -1) OR (style > 1) THEN style:= Objects.deep END
	END;
	RETURN style
END GetCopyStyle;

(* Returns an object from reference gadget named "value" in the current context. *)
PROCEDURE GetObject(): Objects.Object;
	VAR link, obj: Objects.Object; time: LONGINT; L: Objects.LinkMsg;
BEGIN obj:= NIL;
	link:= Gadgets.FindObj(Gadgets.context, RefObj);
	IF link # NIL THEN
		L.id:= Objects.get; L.name:= "Value"; L.obj:= NIL; L.res:= -1; link.handle(link, L);
		obj:= L.obj
	ELSE Gadgets.GetSelection(obj, time)
	END;
	RETURN obj
END GetObject;

(* Makes a list of all named objects in <lib>. Tries to insert the list as a panel in a camera view
	named "objlist". The values of the objects "theobj", "value" and "rname" are cleared, too.
	If the named objects cannot be found in the current context, a text is opened (if <openDoc>
	is true). *)
PROCEDURE UpdateObjList(lib: Objects.Library; openDoc: BOOLEAN);
	VAR obj, view: Objects.Object; P: Panels.Panel; T: Texts.Text; ref: INTEGER;
			A: Objects.AttrMsg; L: Objects.LinkMsg;
BEGIN
	view:= Gadgets.FindObj(Gadgets.context, ObjList);
	IF (view # NIL) & (view IS ScrollViews.View) THEN
		P:= MakeLibContentsPanel(lib);
		WITH view: ScrollViews.View DO
			IF P.W < view.W - 20 THEN P.W:= view.W - 20 END;
			IF P.H < view.H - 2 THEN P.H:= view.H - 2 END;
			view.obj:= P; INCL(view.state, Gadgets.lockedcontents);
			view.vy:= -1; view.vx:= 19;
			ScrollViews.SetBars(view, TRUE, FALSE)
		END;
		(* clear old values *)
		obj:= Gadgets.FindObj(Gadgets.context, ObjNameObj);
		IF obj # NIL THEN
			A.id:= Objects.set; A.name:= "Value"; A.class:= Objects.String; A.s:= ""; A.res:= -1;
			obj.handle(obj, A);
			Gadgets.Update(obj)
		END;
		obj:= Gadgets.FindObj(Gadgets.context, RNameObj);
		IF obj # NIL THEN
			A.id:= Objects.set; A.name:= "Value"; A.class:= Objects.String; A.s:= ""; A.res:= -1;
			obj.handle(obj, A);
			Gadgets.Update(obj)
		END;
		obj:= Gadgets.FindObj(Gadgets.context, NNameObj);
		IF obj # NIL THEN
			A.id:= Objects.set; A.name:= "Value"; A.class:= Objects.String; A.s:= ""; A.res:= -1;
			obj.handle(obj, A);
			Gadgets.Update(obj)
		END;
		obj:= Gadgets.FindObj(Gadgets.context, RefObj);
		IF obj # NIL THEN
			L.id:= Objects.set; L.name:= "Value"; L.obj:= NIL; L.res:= -1;
			obj.handle(obj, L);
			Gadgets.Update(obj)
		END
	ELSIF openDoc THEN
		String("List of named objects in "); String(lib.name); Ln;
		IF lib # NIL THEN ref:= 0;
			WHILE ref <= lib.maxref DO
				lib.GetObj(lib, ref, obj);
				IF obj # NIL THEN
					Objects.GetName(lib.dict, ref, A.s);
					IF A.s # "" THEN String(A.s); Ln END
				END;
				INC(ref)
			END
		END;
		NEW(T); Texts.Open(T, ""); Texts.Append(T, W.buf);
		OpenText("Columbus.ShowObjs", T)
	END
END UpdateObjList;

(* Library enumerator: if <L> is not of type Fonts.Font, the lib's name is written to global writer <W>. *)
PROCEDURE EnumLib(L: Objects.Library);
BEGIN IF ~(L IS Fonts.Font) THEN Texts.WriteString(W, L.name); Texts.WriteLn(W) END
END EnumLib;

(** Sets the attribute "Value" of an object named "theobj". *)
PROCEDURE SetCurrent*;
	VAR obj, field, dlink: Objects.Object; A: Objects.AttrMsg; S: Attributes.Scanner;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Attributes.Scan(S);
	IF S.class = Attributes.Name THEN
		obj:= Gadgets.FindPublicObj(S.s);
		IF obj # NIL THEN
			Objects.GetName(obj.lib.dict, obj.ref, A.s);
			dlink:= Gadgets.context;
			WHILE (dlink # NIL) & ~(dlink IS ScrollViews.View) DO dlink:= dlink.dlink END;
			IF dlink = NIL THEN dlink:= Gadgets.context
			ELSE dlink:= dlink.dlink
			END;
			field:= Gadgets.FindObj(dlink, ObjNameObj);
			IF field # NIL THEN
				A.id:= Objects.set; A.name:= "Value"; A.class:= Objects.String; A.res:= -1;
				field.handle(field, A);
				 Gadgets.Update(field);
			END
		ELSE String(" could not find object '"); String(S.s); Char("'"); Ln; ToLog
		END
	END
END SetCurrent;


	(** ---------------------- library editor object commands ----------------------- *)

(** Used in the form:	Columbus.ShowObjs <LibName>

Inserts a list of all named objects in <LibName> as panel into a scroll view named "objlist". <LibName> must include the ".Lib" extension. It also updates a text field named "thelib".  The view and the text field must be detectable in the current context. If the view can not be found, the list is shown as text.
	*)
PROCEDURE ShowObjs*;
	VAR lib: Objects.Library; dst: Objects.Object; i: INTEGER;
			S: Attributes.Scanner; A: Objects.AttrMsg;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Attributes.Scan(S);
	IF S.class = Attributes.Name THEN
		lib:= Objects.ThisLibrary(S.s);
		UpdateObjList(lib, TRUE);
		dst := Gadgets.FindObj(Gadgets.context, LibNameObj);
		IF dst # NIL THEN
			A.id:= Objects.set; A.name:= "Value"; A.class:= Objects.String; COPY(S.s, A.s); A.res:= -1; 
			i := 0; WHILE (A.s[i] # 0X) & (A.s[i] # ".") DO INC(i) END; A.s[i] := 0X;
			dst.handle(dst, A);
			Gadgets.Update(dst)
		END;
	END;
	IF ~msgPrinted THEN PrintMsg END
END ShowObjs;

(** Used in the form:	Columbus.GetObj <LibName.ObjName>


If <LibName.ObjName> is a document gadget, a (deep) copy of the document is opened on the display. Frame gadget are inserted at the caret. A copy is made depending on the value of an object named "copystyle". If this object cannot be dedected in the current context, the copy style 'deep' is assumed. If <LibName.ObjName> is a model, the "Model" link of all selected frames is set to this model (No copies are made for modelsl).
*)
PROCEDURE GetObj*;
	VAR obj, sel: Objects.Object; time: LONGINT; style: INTEGER; C: Objects.CopyMsg; L: Objects.LinkMsg; 
			S: Attributes.Scanner;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Attributes.Scan(S);
	IF S.class = Attributes.Name THEN
		obj:= Gadgets.FindPublicObj(S.s);
		IF obj # NIL THEN
			IF obj IS Documents.Document THEN
				C.id:= Objects.deep; C.obj:= NIL; Objects.Stamp(C); obj.handle(obj, C);
				IF C.obj # NIL THEN Desktops.ShowDoc(C.obj(Documents.Document))
				ELSE String(" could not make a copy of '"); String(S.s); Char("'"); Ln; ToLog
				END
			ELSIF obj IS Gadgets.Frame THEN
				style:= GetCopyStyle();
				IF style >= 0 THEN C.id:= style; C.obj:= NIL; Objects.Stamp(C); obj.handle(obj, C); obj:= C.obj END;
				IF obj # NIL THEN Gadgets.Integrate(obj)
				ELSE String(" could not make a copy of '"); String(S.s); Char("'"); Ln; ToLog
				END
			ELSIF obj IS Objects.Object THEN
				Gadgets.GetSelection(sel, time);
				IF time >= 0 THEN
					WHILE sel # NIL DO
						L.id:= Objects.set; L.name:= "Model"; L.obj:= obj; L.res:= -1; sel.handle(sel, L);
						sel:= sel.slink
					END;
					Gadgets.Update(obj)
				ELSE String(" could not link model '"); String(S.s); String("' - check selection"); Ln; ToLog
				END
			ELSE String(" object '"); String(S.s); String ("' is of unknown type"); Ln; ToLog
			END
		ELSE String(" could not find object '"); String(S.s); Char("'"); Ln; ToLog
		END
	END;
	IF ~msgPrinted THEN PrintMsg END
END GetObj;

(** Used in the form:	Columbus.FreeObj <LibName.ObjName>

Frees <LibName.ObjName>. The scroll view named "objlist" in the current context is cleared, too. 
*)
PROCEDURE FreeObj*;
	VAR lib: Objects.Library; dst, obj: Objects.Object; ref: INTEGER; S: Attributes.Scanner; A: Objects.AttrMsg;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Attributes.Scan(S);
	IF S.class = Attributes.Name THEN
		obj:= Gadgets.FindPublicObj(S.s);
		IF obj # NIL THEN
			String(" free object '"); String(S.s); Char("'");Ln; ToLog;
			lib:= obj.lib; ref:= obj.ref;
			Objects.PutName(lib.dict, ref, ""); lib.FreeObj(lib, ref);

			(* update obj list and text field*)
			dst:= Gadgets.FindObj(Gadgets.context, ObjNameObj);
			IF dst # NIL THEN
				A.id := Objects.set; A.name := "Value"; A.class := Objects.String; A.s := ""; A.res := -1; 
				dst.handle(dst, A);
				Gadgets.Update(dst)
			END;
			UpdateObjList(lib, FALSE)
		ELSE String(" could not find object '"); String(S.s); Char("'"); Ln; ToLog
		END
	END;
	IF ~msgPrinted THEN PrintMsg END
END FreeObj;

(** Used in the form:	Columbus.AddObj <LibName.ObjName>

Inserts the object taken from the reference gadget in the current context named  "value"  as <LibName.ObjName>. If the reference gadget cannot be detected, the selected frame will be added instead. This command also updates the scroll view named "objlist" in the current context.
*)
PROCEDURE AddObj*;
	VAR lib: Objects.Library; obj, old: Objects.Object; libname, objname: Objects.Name;
			ref: INTEGER; B: Objects.BindMsg; S: Attributes.Scanner;
BEGIN
	Oberon.Defocus;
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Attributes.Scan(S);
	IF S.class = Attributes.Name THEN
		SplitName(S.s, libname, objname);
		lib:= Objects.ThisLibrary(libname);
		IF objname # "" THEN
			obj:= GetObject();
			IF obj # NIL THEN
				Objects.GetRef(lib.dict, objname, ref);
				IF ref >= 0 THEN lib.GetObj(lib, ref, old) ELSE old:= NIL END;
				IF old = NIL THEN (* obj does not exists yet *)
					lib.GenRef(lib, ref);
					IF ref < 0 THEN String("Library is full, sorry"); Ln; ToLog; RETURN END;
					String(" add object '")
				ELSE String(" replace object '")
				END;
				String(S.s); Char("'"); Ln; ToLog;
				lib.PutObj(lib, ref, obj); Objects.PutName(lib.dict, ref, objname);
				B.lib:= lib; obj.handle(obj, B);
				UpdateObjList(lib, FALSE)
			ELSE String(" no object to install"); Ln; ToLog
			END
		ELSE String(" no name for object"); Ln; ToLog
		END
	END;
	IF ~msgPrinted THEN PrintMsg END
END AddObj;

(** Used in the form:	Columbus.RenameObj <LibName.ObjName> <NewName>

Renames <LibName.ObjName> with <NewName>. It also updates the the scroll view in the current context named "objlist".
*)
PROCEDURE RenameObj*;
	VAR lib: Objects.Library; obj: Objects.Object; name: Objects.Name; ref: INTEGER; S: Attributes.Scanner;
BEGIN
	Oberon.Defocus;
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Attributes.Scan(S);
	IF S.class = Attributes.Name THEN
		obj:= Gadgets.FindPublicObj(S.s); COPY(S.s, name);
		IF obj # NIL THEN
			Attributes.Scan(S);
			IF S.class = Attributes.Name THEN
				lib:= obj.lib;
				Objects.GetRef(lib.dict, S.s, ref);
				IF ref = MIN(INTEGER) THEN
					Objects.PutName(lib.dict, obj.ref, S.s);
					String(" rename object '"); String(name); String("' to '"); String(S.s); Char("'");
					Ln; ToLog;
					UpdateObjList(lib, FALSE);
				ELSE
					String(" could not rename object '"); String(name); String("' - name '");
					String(S.s); String("' already exists"); Ln; ToLog
				END
			END
		ELSE String(" could not find object '"); String(S.s); Char("'"); Ln; ToLog
		END
	END;
	IF ~msgPrinted THEN PrintMsg END
END RenameObj;


	(** ---------------------- library editor library commands ----------------------- *)

(** Used in the form:	Columbus.ShowLibs <ObjName>

Inserts the names of loaded libraries into a list named <ObjName> detectable in the current context. If the list could not be detected, a text is opened instead.
*)
PROCEDURE ShowLibs*;
	VAR T: Texts.Text; list: Objects.Object; S: Attributes.Scanner;
BEGIN
	Objects.Enumerate(EnumLib);
	NEW(T); Texts.Open(T, ""); Texts.Append(T, W.buf);

	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Attributes.Scan(S);
	IF S.class = Attributes.Name THEN list:= Gadgets.FindObj(Gadgets.context, S.s) END;
	IF list # NIL THEN SetTextToList(list, T)
	ELSE
		String("List of loaded libraries"); Ln; Texts.Insert(T, 0, W.buf);
		OpenText("Columbus.ShowLibs", T)
	END;
	IF ~msgPrinted THEN PrintMsg END
END ShowLibs;

(** Used in the form:	Columbus.StoreLib {<LibName>}

Stores <LibName>. <LibName> must include the ".Lib" extension.
*)
PROCEDURE StoreLib*;
	VAR P: Panel; lib: Objects.Library; S: Attributes.Scanner;
	
	PROCEDURE StoreThis(lib: Objects.Library);
		VAR f: Files.File; obj: Objects.Object; len: LONGINT; ref: INTEGER; B: Objects.BindMsg;
	BEGIN
		String("Store "); Char(22X); String(lib.name); Char(22X); Ln; ToLog;
		B.lib := lib; Objects.Stamp(B); B.dlink := NIL;
		FOR ref := 0 TO lib.maxref DO 
			lib.GetObj(lib, ref, obj);
			IF obj # NIL THEN obj.handle(obj, B) END
		END;

		Backup(lib.name);
		f := Files.New(lib.name);
		Objects.StoreLibrary(lib, f, 0, len);
		Files.Register(f); Files.Close(f)
	END StoreThis;

BEGIN
	P:= FindPanel();
	IF P # NIL THEN
		IF P.history # NIL THEN StoreThis(P.history.lib) END
	ELSE
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Attributes.Scan(S);
		WHILE S.class = Attributes.Name DO
			lib:= Objects.ThisLibrary(S.s);
			IF lib # NIL THEN StoreThis(lib) END;
			Attributes.Scan(S)
		END
	END;
	IF ~msgPrinted THEN PrintMsg END
END StoreLib;

(** Used in the form:	Columbus.UnloadLib {<LibName>}

Unloads <LibNames>. <LibName> must include the ".Lib" extension.
*)
PROCEDURE UnloadLib*;
	VAR obj: Objects.Object; P: Panel; A: Objects.AttrMsg; S: Attributes.Scanner;
BEGIN
	P:= FindPanel();
	IF P # NIL THEN
		IF P.history # NIL THEN
			String("Unload "); Char(22X); String(P.history.lib.name); Char(22X); Ln; ToLog;
			Objects.FreeLibrary(P.history.lib.name); P.history:= NIL;
			InspectThis(P, NIL, NIL, NoView)
		END
	ELSE
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Attributes.Scan(S);
		WHILE S.class = Attributes.Name DO
			String("Unload "); Char(22X); String(S.s); Char(22X); Ln; ToLog;
			Objects.FreeLibrary(S.s); Attributes.Scan(S)
		END;
		UpdateObjList(NIL, FALSE);
		obj:= Gadgets.FindObj(Gadgets.context, LibNameObj);
		IF obj # NIL THEN
			A.id:= Objects.set; A.name:= "Value"; A.class:= Objects.String; A.s:= ""; A.res:= -1;
			obj.handle(obj, A);
			Gadgets.Update(obj)
		END
	END;
	IF ~msgPrinted THEN PrintMsg END
END UnloadLib;

(** Used in the form:	Columbus.CleanupLib {<LibNames>}

Frees unused objects in <LibName>. <LibNames> must include the ".Lib" extendion. The cleaned librariy will be stored to disk and reloaded into the memory.
*)
PROCEDURE CleanupLib*;
	VAR P: Panel; S: Attributes.Scanner;

	PROCEDURE CleanupThis(lib: Objects.Library);
		VAR f: Files.File; lib0: Objects.Library; obj, obj0: Objects.Object; len: LONGINT; ref, cnt, cnt0: INTEGER;
			name: Objects.Name; C: Objects.CopyMsg; B: Objects.BindMsg;
	BEGIN
		IF (lib # NIL) & ~(lib IS Fonts.Font) THEN 
			String("Cleanup "); Char(22X); String(lib.name); Char(22X); ToLog;
			NEW(lib0); Objects.OpenLibrary(lib0);
			Objects.Stamp(C);
			
			(* copy reachable objects to new lib *)
			ref:= 0; cnt:= 0;
			WHILE ref <= lib.maxref DO
				lib.GetObj(lib, ref, obj);
				IF obj # NIL THEN INC(cnt);
					Objects.GetName(lib.dict, ref, name);
					IF name # "" THEN
						C.id:= Objects.deep; C.obj:= NIL; obj.handle(obj, C);
						IF C.obj = NIL THEN HALT(99) ELSE obj0:= C.obj END;
						B.lib:= lib0; obj0.handle(obj0, B);
						Objects.PutName(lib0.dict, obj0.ref, name)
					END
				END;
				INC(ref)
			END;
			
			(* count objs in new lib *)
			ref:= 0; cnt0:= 0;
			WHILE ref <= lib.maxref DO
				lib0.GetObj(lib0, ref, obj);
				IF obj # NIL THEN INC(cnt0) END;
				INC(ref)
			END;
			
			String(" - "); Int(cnt - cnt0); String(" objects collected"); Ln; ToLog;
			Backup(lib.name);
			f:= Files.New(lib.name);
			Objects.StoreLibrary(lib0, f, 0, len);
			Files.Register(f); Files.Close(f);
			
			Objects.FreeLibrary(lib.name)
		END
	END CleanupThis;

BEGIN
	P:= FindPanel();
	IF P # NIL THEN
		IF P.history # NIL THEN
			CleanupThis(P.history.lib);
			COPY(P.history.lib.name, S.s); P.history:= NIL;
			InspectThis(P, NIL, Objects.ThisLibrary(S.s), LibEditView)
		END
	ELSE
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Attributes.Scan(S);
		WHILE S.class = Attributes.Name DO
			CleanupThis(Objects.ThisLibrary(S.s));
			Attributes.Scan(S)
		END
	END;
	IF ~msgPrinted THEN PrintMsg END
END CleanupLib;


	(* ---------------------- init view generator structure ----------------------- *)

PROCEDURE InitViewDesc(nr: INTEGER; canProc: CanProc; makeProc: MakeProc; btnProc: ButtonProc);
BEGIN
	viewGens[nr].canView:= canProc;
	viewGens[nr].makeView:= makeProc;
	viewGens[nr].getButton:= btnProc
END InitViewDesc;

BEGIN
	Texts.OpenWriter(W);
	msgPrinted:= FALSE;
	
	InitViewDesc(ObjAttrView, CanViewAttr, MakeAttrView, AttrViewButton);
	InitViewDesc(ObjLinkView, CanViewLink, MakeLinkView, LinkViewButton);
	InitViewDesc(ObjCoordView, CanViewCoord, MakeCoordView, CoordViewButton);
	InitViewDesc(ObjDscView, CanViewDsc, MakeDscView, DscViewButton);
	InitViewDesc(ObjDefView, CanViewDef, NIL, DefViewButton);
	InitViewDesc(LibOverView, CanViewLib, MakeLibView, LibViewButton);
	InitViewDesc(LibEditView, CanViewEditor, MakeLibEditor, LibEditorButton)
END Columbus.

(**
Columbus is an universial tool for inspecting and changing different kind of information of objects like attributes and links. The tool can also be used to manage public libaries and their content.

Columbus consists of two different panels. One can be used to configure the state of objects and is called 'Objects.Panel'. The other can be used manipulate public libaries and is called 'Libraries.Panel'. Parts of the 'Libraries.Panel' is integrated in the object inspector. The 'Objects.Panel' on the other hand can directly be opened from the library editor.

Use the command Columbus.Inspect ~ to open the inspector panel. Before executing this commandf, you can specifiy the target object or library by...
	- the name of a public object/library
	- a selected frame or the selected name of public object/library
	- the marked frame 
The panel is opened in the attribute view. If no target can be detected, an so-calleds empty panel is opened.

Desktops.OpenDoc Libraries.Panel ~ opens the library editor. This editor lets you manipulate public libraries and their contents.
*)
