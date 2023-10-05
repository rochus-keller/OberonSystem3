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

MODULE HTMLDocs;	(** portable *) (* ejz, Greek & Math support by afi *)
	IMPORT Objects, Input, Strings, Display, Display3, Fonts, HyperDocs, Texts, Gadgets, Documents, HTTPDocs0, TextDocs,
		Oberon, TextGadgets, Lists, Attributes, Desktops, Links, Streams, TextStreams;

	CONST
		(* class *)
		WhiteSpace* = 0; OpenTag* = 1; OpenEndTag* = 2; CloseTag* = 3; CharRef* = 4; Character* = 5; Value* = 6; Undef* = 7;
		(* state *)
		TextPlain* = 1; TextHtml* = 2; InTag* = 3; End* = 4;
		(* list types *)
		DefList = 0; DescList = 1; OrderedList = 2;
		DefStyle = {TextGadgets.left};
		Menu = "Desktops.Copy[Copy] HyperDocs.Back[Back] HyperDocs.Reload[Reload] TextDocs.Search[Search] Desktops.StoreDoc[Store]";
		GreekCap = "0013143516173415192134222324252728202931323337372636180000000000";
		GreekMin = "004546674849664751536654555657596052616364656969586850";

	TYPE
		DocURL* = POINTER TO DocURLDesc;
		DocURLDesc* = RECORD (HyperDocs.DefURLDesc)
			dockey*: LONGINT
		END;
		TextAttrs = POINTER TO TextAttrsDesc;
		TextAttrsDesc = RECORD
			lib: Objects.Library;
			style: TextGadgets.Style;
			col, voff: SHORTINT;
			next: TextAttrs
		END;
		Page* = POINTER TO PageDesc;
		Scanner* = RECORD
			page*: Page;
			S*: Streams.Stream;
			class*, state*: INTEGER;
			value*: ARRAY 1024 OF CHAR;
			pre*, end*: BOOLEAN;
			ch*, next*, char*: CHAR;
			avail: LONGINT
		END;
		List = POINTER TO ListDesc;
		ListDesc = RECORD
			style: TextGadgets.Style;
			kind, nesting, itemNr: INTEGER;
			dtok: BOOLEAN;
			next: List
		END;
		Form* = POINTER TO FormDesc;
		FormDesc* = RECORD (TextGadgets.ControlDesc)
			elems*: HTTPDocs0.ObjList
		END;
		PageDesc* = RECORD (Gadgets.ObjDesc)
			W*, Ws*: Texts.Writer;
			textAttrs: TextAttrs;
			T*, source*: Texts.Text;
			D*: Documents.Document;
			alink*, clink: Objects.Object;
			style: TextGadgets.Style;
			base*: DocURL;
			orgLabel: ARRAY 64 OF CHAR;
			lists: List;
			orgPos, linkkey*, headerLen, docKey*: LONGINT;
			next*: Page;
			task: Oberon.Task;
			textC*, linkC*, oldLinkC*, textbackC*, lines*: INTEGER;
			left*, blank*, head, cacheSource*: BOOLEAN
		END;
		Item* = POINTER TO ItemDesc;
		ItemDesc* = RECORD (Lists.ItemDesc)
			value*: ARRAY 64 OF CHAR;
			oldSel*, hasVal*: BOOLEAN
		END;
		TagHandler* = PROCEDURE (VAR S: Scanner; on: BOOLEAN);
		ExtTag* = POINTER TO ExtTagDesc;
		ExtTagDesc* = RECORD
			tag: ARRAY 32 OF CHAR;
			handle*: TagHandler;
			start*, stop*: PROCEDURE (P: Page);
			next: ExtTag
		END;
		TagAttr* = POINTER TO TagAttrDesc;
		TagAttrDesc* = RECORD
			name: ARRAY 64 OF CHAR;
			value*: ARRAY 512 OF CHAR;
			next: TagAttr
		END;
		Task = POINTER TO TaskDesc;
		TaskDesc = RECORD (Oberon.TaskDesc)
			S: Scanner;
			P: Page
		END;

	VAR
		bullets: ARRAY 2 OF RECORD
				f: Fonts.Font;
				c: CHAR
			END;
		Wr*, Wq: Texts.Writer;
		imgs*: BOOLEAN;
		extTags, newTag*: ExtTag;
		entities*: ARRAY 69, 7 OF CHAR;
		entityEncoding*: ARRAY 69 OF CHAR;
		pages*: Page;
		searchAttr: ARRAY 32 OF CHAR;
		mono: Fonts.Font;
		found: BOOLEAN;
		dispW: INTEGER;
		GreekTab: ARRAY 128 OF CHAR;

	PROCEDURE WriteLn*(P: Page);
	BEGIN
		INC(P.lines);
		IF P.lines < 3 THEN
			Texts.WriteLn(P.W); P.blank := FALSE
		END
	END WriteLn;

	PROCEDURE WriteSpace*(P: Page);
	BEGIN
		IF P.blank THEN
			Texts.Write(P.W, " "); P.blank := FALSE
		END
	END WriteSpace;

	PROCEDURE WriteObj*(P: Page; obj: Objects.Object);
	BEGIN
		Texts.WriteObj(P.W, obj);
		IF (obj IS Display.Frame) & (obj(Display.Frame).W >= (HyperDocs.docW-16)) THEN
			INC(P.lines); P.blank := FALSE
		ELSIF obj IS TextGadgets.Style THEN
			P.blank := FALSE
		ELSIF ~(obj IS TextGadgets.Control) THEN
			P.lines := 0; P.blank := TRUE
		END
	END WriteObj;

	PROCEDURE InitTabs(style: TextGadgets.Style);
		VAR i: LONGINT;
	BEGIN
		style.W := ((dispW DIV 8) * 5)-24; style.width := style.W;
		style.noTabs := 32;
		FOR i := 0 TO 31 DO
			style.tab[i] := SHORT(32+i*32)
		END
	END InitTabs;

	PROCEDURE Syntax(size: INTEGER; attr: CHAR): Fonts.Font;
		VAR
			name: ARRAY 32 OF CHAR;
			sizeS: ARRAY 4 OF CHAR;
	BEGIN
		name := "Default";
		IF dispW < 800 THEN DEC(size, 2) END;
		IF size <= 8 THEN size := 8
		ELSIF size <= 10 THEN size := 10
		ELSIF size <= 12 THEN size := 12
		ELSIF size <= 14 THEN size := 14
		ELSIF size <= 16 THEN size := 16
		ELSIF size <= 20 THEN size := 20
		ELSE size := 24
		END;
		Strings.IntToStr(size, sizeS);
		IF attr = 0X THEN (* skip *)
		ELSIF attr = "i" THEN (* skip *)
		ELSIF attr = "m" THEN attr := "b"
		ELSIF attr = "b" THEN (* skip *)
		ELSE attr := 0X
		END;
		Strings.Append(name, sizeS); Strings.AppendCh(name, attr); Strings.Append(name, ".Scn.Fnt");
		RETURN Fonts.This(name)
	END Syntax;

	PROCEDURE PushTextAttrs*(P: Page);
		VAR attr: TextAttrs;
	BEGIN
		NEW(attr);
		attr.lib := P.W.lib; attr.col := P.W.col; attr.voff := P.W.voff;
		attr.style := P.style;
		attr.next := P.textAttrs; P.textAttrs := attr
	END PushTextAttrs;

	PROCEDURE PopTextAttrs*(P: Page);
		VAR
			style: TextGadgets.Style;
			M: Objects.CopyMsg;
	BEGIN
		IF P.textAttrs # NIL THEN
			Texts.SetFont(P.W, P.textAttrs.lib);
			Texts.SetColor(P.W, P.textAttrs.col);
			Texts.SetOffset(P.W, P.textAttrs.voff);
			style := P.textAttrs.style;
			IF (P.style.mode # style.mode) OR (P.style.leftM # style.leftM) OR (P.style.width # style.width) THEN
				M.id := Objects.shallow; Objects.Stamp(M); M.obj := NIL; M.dlink := NIL;
				style.handle(style, M); style := M.obj(TextGadgets.Style);
				P.style := style; WriteObj(P, style)
			END;
			P.textAttrs := P.textAttrs.next
		ELSE
			Texts.SetFont(P.W, Syntax(12, 0X));
			Texts.SetColor(P.W, SHORT(P.textC));
			Texts.SetOffset(P.W, 0);
			style := TextGadgets.newStyle(); InitTabs(style); style.mode := DefStyle;
			IF (P.style.mode # style.mode) OR (P.style.leftM # style.leftM) OR (P.style.width # style.width) THEN
				P.style := style; WriteObj(P, style)
			END
		END
	END PopTextAttrs;

	PROCEDURE SplitFontName(f: Fonts.Font; VAR family: ARRAY OF CHAR; VAR size: INTEGER; VAR attr: CHAR);
		VAR
			val: LONGINT;
			i: INTEGER;
	BEGIN
		i := 0;
		WHILE (f.name[i] # 0X) & ~Strings.IsDigit(f.name[i]) DO
			INC(i)
		END;
		COPY(f.name, family); family[i] := 0X;
		Strings.StrToIntPos(f.name, val, i); size := SHORT(val);
		IF Strings.IsAlpha(f.name[i]) THEN
			attr := f.name[i]
		ELSE
			attr := 0X
		END
	END SplitFontName;

	PROCEDURE FontSize(f: Fonts.Font; VAR size: INTEGER);
		VAR
			family: ARRAY 64 OF CHAR;
			attr: CHAR;
	BEGIN
		SplitFontName(f, family, size, attr)
	END FontSize;

	PROCEDURE GetFontSize*(P: Page): INTEGER;
		VAR size: INTEGER;
	BEGIN
		FontSize(P.W.lib(Fonts.Font), size);
		IF dispW < 800 THEN
			INC(size, 2)
		END;
		IF size <= 8 THEN
			size := 1
		ELSIF size <= 10 THEN
			size := 2
		ELSIF size <= 12 THEN
			size := 3
		ELSIF size <= 14 THEN
			size := 4
		ELSIF size <= 16 THEN
			size := 5
		ELSIF size <= 20 THEN
			size := 6
		ELSE
			size := 7
		END;
		RETURN size
	END GetFontSize;

	PROCEDURE ChangeFontAttr(f: Fonts.Font; attr: CHAR): Fonts.Font;
		VAR
			family: ARRAY 64 OF CHAR;
			str: ARRAY 4 OF CHAR;
			size: INTEGER;
			oldattr: CHAR;
	BEGIN
		IF attr = "m" THEN attr := "b" END;
		SplitFontName(f, family, size, oldattr);
		IF oldattr # attr THEN
			Strings.IntToStr(size, str); Strings.Append(family, str);
			IF attr # 0X THEN
				Strings.AppendCh(family, attr)
			END;
			Strings.Append(family, ".Scn.Fnt");
			RETURN Fonts.This(family)
		ELSE
			RETURN f
		END
	END ChangeFontAttr;

	PROCEDURE ChangeFontSize(f: Fonts.Font; size: INTEGER): Fonts.Font;
		VAR
			family: ARRAY 64 OF CHAR;
			str: ARRAY 4 OF CHAR;
			oldsize: INTEGER;
			attr: CHAR;
	BEGIN
		IF dispW < 800 THEN
			DEC(size, 2)
		END;
		SplitFontName(f, family, oldsize, attr);
		IF oldsize # size THEN
			Strings.IntToStr(size, str); Strings.Append(family, str);
			IF attr # 0X THEN
				Strings.AppendCh(family, attr)
			END;
			Strings.Append(family, ".Scn.Fnt");
			RETURN Fonts.This(family)
		ELSE
			RETURN f
		END
	END ChangeFontSize;

	PROCEDURE SetFontSize*(P: Page; size: INTEGER);
		VAR fnt: Fonts.Font;
	BEGIN
		fnt := P.W.lib(Fonts.Font);
		IF size < 1 THEN
			size := 1
		ELSIF size > 9 THEN
			size := 9
		END;
		PushTextAttrs(P);
		CASE size OF
			1: Texts.SetFont(P.W, ChangeFontSize(fnt, 8))
			|2: Texts.SetFont(P.W, ChangeFontSize(fnt, 10))
			|3: Texts.SetFont(P.W, ChangeFontSize(fnt, 12))
			|4: Texts.SetFont(P.W, ChangeFontSize(fnt, 14))
			|5: Texts.SetFont(P.W, ChangeFontSize(fnt, 16))
			|6: Texts.SetFont(P.W, ChangeFontSize(fnt, 20))
			|7: Texts.SetFont(P.W, ChangeFontSize(fnt, 24))
			|8: fnt := ChangeFontSize(fnt, 24);
				Texts.SetFont(P.W, ChangeFontAttr(fnt, "m"))
			|9: fnt := ChangeFontSize(fnt, 24);
				Texts.SetFont(P.W, ChangeFontAttr(fnt, "b"))
		END
	END SetFontSize;

	PROCEDURE HorzRule*(P: Page; w, h: INTEGER);
		VAR obj: Objects.Object;
	BEGIN
		IF P.lines <= 0 THEN
			WriteLn(P)
		END;
		h := 2*h;
		IF h < 4 THEN
			h := 4
		END;
		obj := Gadgets.CreateObject("BasicFigures.NewRect3D");
		Attributes.SetBool(obj, "Filled", TRUE);
		Attributes.SetInt(obj, "Color", P.textbackC);
		Gadgets.ModifySize(obj(Display.Frame), w, h);
		WriteObj(P, obj); P.lines := 1; WriteLn(P)
	END HorzRule;

	PROCEDURE TextAlign*(VAR align: ARRAY OF CHAR): TextGadgets.Style;
		VAR style: TextGadgets.Style;
	BEGIN
		style := TextGadgets.newStyle(); style.mode := {}; InitTabs(style);
		CASE CAP(align[0]) OF
			|"L": INCL(style.mode, TextGadgets.left)
			|"R": INCL(style.mode, TextGadgets.right)
			|"C", "J": INCL(style.mode, TextGadgets.middle)
		ELSE (* BLEED... *)
			CASE CAP(align[5]) OF
				"L":  INCL(style.mode, TextGadgets.left)
				|"R": INCL(style.mode, TextGadgets.right)
				|"C", "J": INCL(style.mode, TextGadgets.middle)
			ELSE
			END
		END;
		IF style.mode # {} THEN
			RETURN style
		ELSE
			RETURN NIL
		END
	END TextAlign;

	PROCEDURE CloseA*(P: Page);
	BEGIN
		IF P.alink # NIL THEN
			WriteObj(P, P.alink); P.alink := NIL;
			WHILE (P.W.col = SHORT(P.linkC)) OR (P.W.col = SHORT(P.oldLinkC)) DO
				PopTextAttrs(P);
				IF P.textAttrs = NIL THEN RETURN END
			END
		END
	END CloseA;

	PROCEDURE OpenList(P: Page; kind: INTEGER);
		VAR list: List;
	BEGIN
		PushTextAttrs(P);
		NEW(list); list.itemNr := 0;
		list.style := TextGadgets.newStyle(); InitTabs(list.style); list.style.mode := DefStyle;
		IF P.lists = NIL THEN
			list.nesting := 0;
			WriteLn(P); WriteLn(P)
		ELSE
			list.nesting := P.lists.nesting+1
		END;
		P.style := list.style; WriteObj(P, list.style);
		list.dtok := FALSE; list.kind := kind;
		list.next := P.lists; P.lists := list
	END OpenList;

	PROCEDURE CloseList(P: Page);
	BEGIN
		IF P.lists # NIL THEN
			IF P.lists.itemNr = 0 THEN
				P.lists.style.leftM := 32
			END;
			P.lists := P.lists.next
		END;
		PopTextAttrs(P);
		IF P.lists = NIL THEN
			WriteLn(P); WriteLn(P)
		END
	END CloseList;

	PROCEDURE FindFormObj*(form: Form; name: ARRAY OF CHAR): Objects.Object;
		VAR
			ol: HTTPDocs0.ObjList;
			oname: ARRAY 64 OF CHAR;
			obj: Objects.Object;
	BEGIN
		obj := NIL;
		ol := form.elems;
		WHILE ol # NIL DO
			Attributes.GetString(ol.obj, "Name", oname);
			IF oname = name THEN
				obj := ol.obj
			END;
			ol := ol.next
		END;
		RETURN obj
	END FindFormObj;

	PROCEDURE RememberValue*(obj: Objects.Object);
		VAR A: Objects.AttrMsg;
	BEGIN
		A.id := Objects.get; A.name := "Value"; A.class := Objects.Inval;
		obj.handle(obj, A);
		A.id := Objects.set; A.name := "IniValue";
		obj.handle(obj, A)
	END RememberValue;

	PROCEDURE AddFormObj*(P: Page; form: Form; obj: Objects.Object; name: ARRAY OF CHAR; storeVal, write: BOOLEAN);
		VAR ol, op: HTTPDocs0.ObjList;
	BEGIN
		NEW(ol); ol.obj := obj; ol.next := NIL;
		op := form.elems;
		WHILE (op # NIL) & (op.next # NIL) DO
			op := op.next
		END;
		IF op # NIL THEN
			op.next := ol
		ELSE
			form.elems := ol
		END;
		IF storeVal THEN
			RememberValue(obj)
		END;
		IF name # "" THEN
			Gadgets.NameObj(obj, name)
		END;
		IF write THEN
			WriteObj(P, obj)
		END
	END AddFormObj;

	PROCEDURE *FindA(name: ARRAY OF CHAR);
	BEGIN
		IF name = searchAttr THEN
			found := TRUE
		END
	END FindA;

	PROCEDURE HasA(obj: Objects.Object; name : ARRAY OF CHAR): BOOLEAN;
		VAR A: Objects.AttrMsg;
	BEGIN
		found := FALSE; COPY(name, searchAttr);
		A.id := Objects.enum; COPY(name, A.name); A.res := -1;
		A.Enum := FindA;
		obj.handle(obj, A);
		RETURN found
	END HasA;

	PROCEDURE ResetValues(form: Form);
		VAR
			A: Objects.AttrMsg;
			ol: HTTPDocs0.ObjList;
			item: Item;
	BEGIN
		ol := form.elems;
		WHILE ol # NIL DO
			IF HasA(ol.obj, "IniValue") THEN
				A.id := Objects.get; A.name := "IniValue"; A.class := Objects.Inval;
				ol.obj.handle(ol.obj, A);
				A.id := Objects.set; A.name := "Value";
				ol.obj.handle(ol.obj, A);
				Gadgets.Update(ol.obj)
			ELSIF ol.obj IS Lists.List THEN
				item := ol.obj(Lists.List).items(Item);
				WHILE item # NIL DO
					item.sel := item.oldSel;
					IF item.next # NIL THEN
						item := item.next(Item)
					ELSE
						item := NIL
					END
				END;
				Gadgets.Update(ol.obj)
			END;
			ol := ol.next
		END
	END ResetValues;

	PROCEDURE GetText*(view: Objects.Object): Texts.Text;
		VAR model: Objects.Object;
	BEGIN
		IF view # NIL THEN
			Links.GetLink(view, "Model", model);
			IF (model # NIL) & (model IS Texts.Text) THEN
				RETURN model(Texts.Text)
			ELSE
				RETURN NIL
			END
		ELSE
			RETURN NIL
		END
	END GetText;

(** HTMLDocs.Locate label
		Used for hyperlinks within the same page. *)
	PROCEDURE Locate*;
		VAR
			S: Attributes.Scanner;
			F: Texts.Finder;
			pos: LONGINT;
			obj: Objects.Object;
			name: ARRAY 32 OF CHAR;
			curDoc: Documents.Document;
			node: HyperDocs.Node;
			text: Texts.Text;
	BEGIN
		curDoc := Desktops.CurDoc(Gadgets.context);
		node := HyperDocs.NodeByDoc(curDoc);
		text := GetText(Gadgets.context);
		IF (curDoc # NIL) & (text # NIL) THEN
			Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
			Attributes.Scan(S);
			IF (S.class = Attributes.String) OR (S.class = Attributes.Name) THEN
				Texts.OpenFinder(F, text, 0);
				pos := F.pos; Texts.FindObj(F, obj);
				WHILE ~F.eot DO
					IF obj IS Gadgets.Frame THEN
						Attributes.GetString(obj, "Name", name);
						IF S.s = name THEN
							IF node # NIL THEN
								HyperDocs.RememberOrg(curDoc.dsc(TextGadgets.Frame).org, node, node);
								HyperDocs.LinkNodeToDoc(curDoc, node)
							END;
							HyperDocs.ScrollTo(curDoc.dsc(TextGadgets.Frame), pos);
							RETURN
						END
					END;
					pos := F.pos; Texts.FindObj(F, obj)
				END
			END
		END
	END Locate;

(** HTMLDocs.ExecNext
		Used by clickable images to activate the surrounding hyperlink. *)
	PROCEDURE ExecNext*;
		VAR
			F: Texts.Finder;
			exec, obj: Objects.Object;
			text: Texts.Text;
	BEGIN
		exec := Gadgets.executorObj;
		text := GetText(Gadgets.context);
		IF (text # NIL) & (exec # NIL) THEN
			Texts.OpenFinder(F, text, 0);
			Texts.FindObj(F, obj);
			WHILE ~F.eot DO
				IF obj = exec THEN
					exec := NIL
				ELSIF (exec = NIL) & (obj IS TextGadgets.Control) THEN
					Gadgets.ExecuteAttr(obj(TextGadgets.Control), "Cmd", Gadgets.context, NIL, NIL);
					RETURN
				END;
				Texts.FindObj(F, obj)
			END
		END
	END ExecNext;

	PROCEDURE CurForm(context: Objects.Object): Form;
		VAR
			F: Texts.Finder;
			exec, obj: Objects.Object;
			ol: HTTPDocs0.ObjList;
			text: Texts.Text;
	BEGIN
		IF context # NIL THEN
			exec := Gadgets.executorObj; text := GetText(context);
			IF text # NIL THEN
				Texts.OpenFinder(F, text, 0);
				Texts.FindObj(F, obj);
				WHILE ~F.eot DO
					IF obj IS Form THEN
						ol := obj(Form).elems;
						WHILE (ol # NIL) & (ol.obj # exec) DO
							ol := ol.next
						END;
						IF ol # NIL THEN
							RETURN obj(Form)
						END
					END;
					Texts.FindObj(F, obj)
				END
			END;
			RETURN CurForm(context.dlink)
		END;
		RETURN NIL
	END CurForm;

(** HTMLDocs.Reset
		Used by the "Reset" button in forms. *)
	PROCEDURE Reset*;
	BEGIN
		ResetValues(CurForm(Gadgets.context))
	END Reset;

	PROCEDURE CopyForm(VAR M: Objects.CopyMsg; from, to: Form);
	BEGIN
		TextGadgets.CopyControl(M, from, to);
to.elems := from.elems
	END CopyForm;

	PROCEDURE *FormHandler(F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			ol: HTTPDocs0.ObjList;
			obj, action: Objects.Object;
			key: LONGINT;
			F1: Form;
	BEGIN
		WITH F: Form DO
			IF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.class := Objects.String;
						M.s := "HTMLDocs.NewForm";
						M.res := 0
					ELSE
						TextGadgets.ControlHandler(F, M)
					END
				END
			ELSIF M IS Objects.FileMsg THEN
				WITH M: Objects.FileMsg DO
					TextGadgets.ControlHandler(F, M);
					IF M.id = Objects.load THEN
						HyperDocs.LoadLink(M.R, key);
						action := Gadgets.CreateObject("BasicGadgets.NewInteger");
						Attributes.SetInt(action, "Value", key);
						Gadgets.NameObj(action, "@ACTION");
						NEW(F.elems);
						F.elems.obj := action;
						F.elems.next := NIL;
						Gadgets.ReadRef(M.R, F.lib, obj);
						WHILE obj # NIL DO
							NEW(ol);
							ol.next := F.elems;
							F.elems := ol;
							ol.obj := obj;
							Gadgets.ReadRef(M.R, F.lib, obj)
						END
					ELSIF M.id = Objects.store THEN
						action := FindFormObj(F, "@ACTION");
						Attributes.GetInt(action, "Value", key);
						HyperDocs.StoreLink(M.R, key);
						ol := F.elems;
						WHILE ol # NIL DO
							IF ol.obj # action THEN
								Gadgets.WriteRef(M.R, F.lib, ol.obj)
							END;
							ol := ol.next
						END;
						Gadgets.WriteRef(M.R, F.lib, NIL)
					END
				END
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					IF M.stamp = F.stamp THEN
						M.obj := F.dlink
					ELSE
						NEW(F1);
						F.stamp := M.stamp; F.dlink := F1;
						CopyForm(M, F, F1);
						M.obj := F1
					END
				END
			ELSIF M IS Objects.BindMsg THEN
				ol := F.elems;
				WHILE ol # NIL DO
					ol.obj.handle(ol.obj, M);
					ol := ol.next
				END
			ELSE
				TextGadgets.ControlHandler(F, M)
			END
		END
	END FormHandler;

	PROCEDURE NewForm*;
		VAR form: Form;
	BEGIN
		NEW(form);
		form.W := 0; form.H := 0;
		form.elems := NIL;
		form.handle := FormHandler;
		Objects.NewObj := form
	END NewForm;

	PROCEDURE HexDigit(i: INTEGER): CHAR;
	BEGIN
		IF i < 10 THEN
			RETURN CHR(i+ORD("0"))
		ELSE
			RETURN CHR(i-10+ORD("A"))
		END
	END HexDigit;

	PROCEDURE MapCoord(obj: Objects.Object; VAR x, y: INTEGER);
		VAR M: Display.LocateMsg;
	BEGIN
		M.F := NIL; M.loc := NIL; M.res := -1;
		M.X := Oberon.Mouse.X; M.Y := Oberon.Mouse.Y;
		Display.Broadcast(M);
		IF M.loc = obj THEN
			x := M.u; y := -M.v
		ELSE
			x := 0; y := 0
		END
	END MapCoord;

	PROCEDURE ComposeQuery(form: Form; exec: Objects.Object; VAR query: Texts.Text);
		VAR
			ol: HTTPDocs0.ObjList;
			x, y: INTEGER;
			obj: Objects.Object;
			text: Texts.Text;
			name: Objects.Name;
			str: ARRAY 64 OF CHAR; (* LEN(Objects.AttrMsg.s) *)
			item: Item;
			A: Objects.AttrMsg;
			R: Texts.Reader;
			ch: CHAR;
			multisel, done: BOOLEAN;
		PROCEDURE WriteEscCh(ch: CHAR);
		BEGIN
			ch := Strings.OberonToISO[ORD(ch)];
			IF (ch < 020X) OR (ch = "+") OR(ch = "&") OR (ch = "=") OR (ch = "?") OR (ch = "%") OR (ch = "$") OR
				(ch = ";") OR (ch = "/") OR (ch = "#") OR (ch = ":") THEN
				Texts.Write(Wr, "%");
				Texts.Write(Wr, HexDigit(ORD(ch) DIV 16));
				Texts.Write(Wr, HexDigit(ORD(ch) MOD 16))
			ELSIF ch = 020X THEN
				Texts.Write(Wr, "+");
			ELSIF ch >= CHR(128) THEN
				Texts.Write(Wr, "%");
				Texts.Write(Wr, HexDigit(ORD(ch) DIV 16));
				Texts.Write(Wr, HexDigit(ORD(ch) MOD 16))
			ELSE
				Texts.Write(Wr, ch)
			END
		END WriteEscCh;
		PROCEDURE IntAttr(i: LONGINT);
		BEGIN
			Texts.WriteString(Wr, name);
			Texts.Write(Wr, "=");
			Texts.WriteInt(Wr, i, 0);
			Texts.Write(Wr, "&")
		END IntAttr;
		PROCEDURE StrAttr(s: ARRAY OF CHAR);
			VAR i: INTEGER;
		BEGIN
			Texts.WriteString(Wr, name);
			Texts.Write(Wr, "=");
			i := 0;
			WHILE s[i] # 0X DO
				WriteEscCh(s[i]);
				INC(i)
			END;
			Texts.Write(Wr, "&")
		END StrAttr;
		PROCEDURE RealAttr(y: LONGREAL; l: INTEGER);
		BEGIN
			Texts.WriteString(Wr, name);
			Texts.Write(Wr, "=");
			Texts.WriteLongReal(Wr, y, l);
			Texts.Write(Wr, "&")
		END RealAttr;
	BEGIN
		NEW(query);
		Texts.Open(query, "");
		ol := form.elems;
		WHILE ol # NIL DO
			obj := ol.obj;
			Gadgets.GetObjName(obj, name);
			IF (name # "") & (name[0] # "@") THEN
				IF HasA(obj, "FormElem") THEN
					Attributes.GetString(obj, "FormElem", str);
					IF (str = "IMAGE") & (exec = obj) THEN
						MapCoord(obj, x, y);
						Strings.Append(name, ".x");
						IntAttr(x);
						Gadgets.GetObjName(obj, name);
						Strings.Append(name, ".y");
						IntAttr(y)
					ELSIF str = "SELECT" THEN
						done := FALSE;
						Attributes.GetBool(obj, "MultiSel", multisel);
						item := obj(Lists.List).items(Item);
						WHILE (item # NIL) & (~done OR multisel) DO
							IF item.sel THEN
								done := TRUE;
								IF item.hasVal THEN
									StrAttr(item.value)
								ELSE
									StrAttr(item.s)
								END
							END;
							IF item.next # NIL THEN
								item := item.next(Item)
							ELSE
								item := NIL
							END
						END;
						IF ~done THEN
							StrAttr("")
						END
					ELSIF str = "TEXTAREA" THEN
						Texts.WriteString(Wr, name);
						Texts.Write(Wr, "=");
						text := GetText(obj);
						IF text # NIL THEN
							Texts.OpenReader(R, text, 0);
							Texts.Read(R, ch);
							WHILE ~R.eot DO
								IF ch = Strings.CR THEN
									(* SendText -> CRLF *)
									Texts.WriteLn(Wr)
								ELSE
									WriteEscCh(ch)
								END;
								Texts.Read(R, ch)
							END
						END;
						Texts.Write(Wr, "&")
					ELSIF str = "PASSWORD" THEN
						Attributes.GetString(obj, "Value", A.s);
						StrAttr(A.s)
					END
				ELSIF HasA(obj, "YesVal") THEN
					Attributes.GetBool(obj, "Value", A.b);
					IF A.b THEN
						Attributes.GetString(obj, "YesVal", str);
						StrAttr(str)
					ELSIF HasA(obj, "SubmitVal") & (obj = exec) THEN
						Attributes.GetString(obj, "SubmitVal", str);
						StrAttr(str)
					END
				ELSIF HasA(obj, "Value") THEN
					IF HasA(obj, "MaxLen") THEN
						Attributes.GetInt(obj, "MaxLen", A.i);
						x := SHORT(A.i)
					ELSE
						x := -1
					END;
					A.id := Objects.get;
					A.name := "Value";
					A.class := Objects.Inval;
					A.res := -1;
					obj.handle(obj, A);
					CASE A.class OF
						Objects.Int: IntAttr(A.i);
						|Objects.String: IF (x >= 0) & (x < LEN(A.s)) THEN
														A.s[x] := 0X
													END;
													StrAttr(A.s)
						|Objects.Real: IF x > 0 THEN
													RealAttr(A.x, x)
												ELSE
													RealAttr(A.x, 15)
												END
						|Objects.LongReal: IF x > 0 THEN
													RealAttr(A.y, x)
												ELSE
													RealAttr(A.y, 15)
												END
					ELSE
					END
				END
			END;
			ol := ol.next
		END;
		Texts.Append(query, Wr.buf);
		Texts.Delete(query, query.len-1, query.len)
	END ComposeQuery;

(** HTMLDocs.SubmitQuery
		Used by the "Submit" button in forms. *)
	PROCEDURE SubmitQuery*;
		VAR
			exec, obj: Objects.Object;
			attr, qury: ARRAY 32 OF CHAR;
			key, mkey: LONGINT;
			docname: ARRAY 1024 OF CHAR;
			query: Texts.Text;
			form: Form;
			x, y: INTEGER;
			cont: HTTPDocs0.Context;
			doc: Documents.Document;
			clearCache: BOOLEAN;
	BEGIN
		query := NIL;
		exec := Gadgets.executorObj;
		IF HasA(exec, "Query") & HasA(exec, "Method") THEN
			clearCache := TRUE;
			form := CurForm(Gadgets.context);
			obj := FindFormObj(form, "@ACTION");
			Attributes.GetInt(obj, "Value", key);
			HyperDocs.DocNameByKey(docname, key);
			Attributes.GetString(exec, "Query", qury);
			IF qury = "ISINDEX" THEN
				obj := FindFormObj(CurForm(Gadgets.context), "QUERY");
				Attributes.GetString(obj, "Value", attr);
				NEW(query);
				Texts.Open(query, "");
				Texts.WriteString(Wq, attr);
				Texts.Append(query, Wq.buf);
				attr := "GET"
			ELSIF qury = "ISMAP" THEN
				IF HasA(exec, "UseMapKey") THEN
					clearCache := FALSE;
					query := NIL; Attributes.GetInt(exec, "UseMapKey", mkey)
				ELSE
					mkey := HyperDocs.UndefKey
				END;
				IF mkey = HyperDocs.UndefKey THEN
					NEW(query);
					Texts.Open(query, "");
					MapCoord(exec, x, y);
					Texts.WriteInt(Wq, x, 0);
					Texts.Write(Wq, ",");
					Texts.WriteInt(Wq, y, 0);
					Texts.Append(query, Wq.buf)
				ELSE
					query := NIL; key := mkey
				END;
				attr := "GET"
			ELSIF qury = "FORM" THEN
				ComposeQuery(form, exec, query);
				Attributes.GetString(exec, "Method", attr)
			ELSE
				Texts.WriteString(Wr, "unknown query type ");
				Texts.WriteString(Wr, qury);
				Texts.WriteLn(Wr);
				Texts.Append(Oberon.Log, Wr.buf);
				RETURN
			END;
			IF (attr = "GET") OR (attr = "POST") THEN
				NEW(cont);
				cont.query := query;
				COPY(attr, cont.method);
				cont.user := ""; cont.passwd := "";
				IF clearCache THEN
					HyperDocs.CacheDoc(key, NIL);
					HyperDocs.CacheText(key, NIL)
				END;
				HyperDocs.FollowKeyLink(cont, key)
			ELSIF attr = "Authorization" THEN
				NEW(cont); cont.query := NIL;
				cont.method := "GET";
				obj := FindFormObj(form, "Username");
				Attributes.GetString(obj, "Value", cont.user);
				obj := FindFormObj(form, "Password");
				Attributes.GetString(obj, "Value", cont.passwd);
				HyperDocs.FollowKeyLink(cont, key)
			ELSIF attr = "MAILTO" THEN
				NEW(cont);
				cont.curDoc := NIL; cont.new := NIL;
				cont.replace := FALSE; cont.history := FALSE;
				cont.old := HyperDocs.NodeByDoc(Desktops.CurDoc(Gadgets.context));
				HyperDocs.context := cont;
				HyperDocs.RetrieveLink(key, docname);
				doc := Documents.Open(docname);
				HyperDocs.context := NIL;
				IF (doc # NIL) & (doc.dsc # NIL) THEN
					IF (query # NIL) & (doc.dsc IS TextGadgets.Frame) THEN
						Texts.WriteLn(Wr); Texts.Insert(query, 0, Wr.buf);
						Texts.WriteLn(Wr); Texts.Append(query, Wr.buf);
						Texts.Save(query, 0, query.len, Wr.buf);
						Texts.Append(doc.dsc(TextGadgets.Frame).text, Wr.buf)
					END;
					Desktops.ShowDoc(doc)
				ELSIF query # NIL THEN
					TextDocs.ShowText("mailto query", query, HyperDocs.docW, HyperDocs.docH)
				END
			ELSE
				Texts.WriteString(Wr, "unknown query method ");
				Texts.WriteString(Wr, attr);
				Texts.WriteLn(Wr);
				Texts.Append(Oberon.Log, Wr.buf);
				RETURN
			END
		END
	END SubmitQuery;

	PROCEDURE HREF(P: Page; VAR href, cmd: ARRAY OF CHAR; VAR key: LONGINT);
		VAR i, j: LONGINT;
	BEGIN
		key := -1; COPY("", cmd); i := 0;
		WHILE (href[i] # 0X) & (href[i] <= " ") DO
			INC(i)
		END;
		IF href[i] = "#" THEN
			COPY("HTMLDocs.Locate ", cmd); href[0] := " ";
			Strings.Append(cmd, href); cmd[16] := 022X;
			Strings.AppendCh(cmd, 022X)
		ELSE
			WHILE (href[i] # 0X) & (href[i] # "#") DO
				INC(i)
			END;
			IF href[i] = "#" THEN
				DEC(i); j := 0;
				WHILE P.base.path[j] # 0X DO
					INC(j)
				END; DEC(j);
				WHILE (i > 0) & (j > 0) & (href[i] = P.base.path[j]) DO
					DEC(i); DEC(j)
				END;
				IF i = 0 THEN
					COPY("HTMLDocs.Locate ", cmd);
					j := 0;
					WHILE cmd[j] # 0X DO
						INC(j)
					END;
					cmd[j] := 022X; INC(j);
					WHILE (href[i] # 0X) & (href[i] # "#") DO
						INC(i)
					END; INC(i);
					WHILE href[i] # 0X DO
						cmd[j] := href[i]; INC(j); INC(i)
					END;
					cmd[j] := 022X; cmd[j+1] := 0X;
					RETURN
				END
			END;
			key := HyperDocs.BuildKey(P.base, href);
			IF key = HyperDocs.UndefKey THEN
				Texts.WriteString(Wr, href);
				Texts.WriteString(Wr, " link-typ not supported");
				Texts.WriteLn(Wr);
				Texts.Append(Oberon.Log, Wr.buf)
			END
		END
	END HREF;

	PROCEDURE Read*(VAR S: Scanner);
		VAR St: Streams.Stream;
	BEGIN
		St := S.S; S.ch := S.next;
		IF St.eos & (St.Available(St) <= 0) THEN
			S.avail := 0; S.next := 0X; S.end := TRUE
		ELSE
			TextStreams.Read(St, S.next); DEC(S.avail);
			Texts.Write(S.page.Ws, S.next);
			IF S.ch = Strings.CR THEN
				IF S.next = Strings.LF THEN
					TextStreams.Read(St, S.next); DEC(S.avail);
					Texts.Write(S.page.Ws, S.next)
				END;
				S.ch := Strings.CR
			ELSIF S.ch = Strings.LF THEN
				S.ch := Strings.CR
			END
		END
	END Read;

	PROCEDURE ChangeFontFamily(f: Fonts.Font; newfamily: ARRAY OF CHAR): Fonts.Font;
		VAR
			family: ARRAY 64 OF CHAR;
			str: ARRAY 4 OF CHAR;
			size: INTEGER;
			attr: CHAR;
	BEGIN
		SplitFontName(f, family, size, attr);
		IF family # newfamily THEN
			COPY(newfamily, family);
			Strings.IntToStr(size, str); Strings.Append(family, str);
			IF attr # 0X THEN
				Strings.AppendCh(family, attr)
			END;
			Strings.Append(family, ".Scn.Fnt");
			RETURN Fonts.This(family)
		ELSE
			RETURN f
		END
	END ChangeFontFamily;

	PROCEDURE WriteCharRef*(P: Page; VAR S: Scanner);
		VAR
			i, j, k: LONGINT;
			entity: ARRAY 64 OF CHAR; istr: ARRAY 4 OF CHAR;
			lib: Objects.Library;
			obj: Objects.Object;
			fnt: Fonts.Font;
			ref: INTEGER;
	BEGIN
		IF S.ch = "#" THEN
			Read(S);
			IF Strings.IsDigit(S.ch) THEN
				i := 0;
				WHILE ~S.end & (i < 9100) & Strings.IsDigit(S.ch) DO
					i := 10*i+ORD(S.ch)-ORD("0"); Read(S)
				END;
				IF S.ch = ";" THEN
					Read(S)
				END;
				CASE i OF
					169: Texts.WriteString(P.W, "(c)")
					|174: Texts.WriteString(P.W, "(R)")
					|188: Texts.WriteString(P.W, " 1/4")
					|189: Texts.WriteString(P.W, " 1/2")
					|190: Texts.WriteString(P.W, " 3/4")
				ELSE
					fnt := P.W.lib(Fonts.Font);
					IF (i >= 913) & (i <= 982) THEN	(* Greek character *)
						Strings.IntToStr(i - 900, istr);
						k := 0;
						WHILE ((istr[0] # GreekTab[k]) OR (istr[1] # GreekTab[k+1])) & (k < 120) DO
							k := k + 2
						END;
						k := k DIV 2;
						Texts.SetFont (P.W, ChangeFontFamily(fnt, "Greek"));
						Texts.Write(P.W, CHR(k + ORD("@")));
						Texts.SetFont (P.W, fnt);
					ELSIF (i >= 8501) & (i <= 9002) THEN	(* Math character *)
						Texts.SetFont (P.W, ChangeFontFamily(fnt, "Math"));
 		CASE i OF	(*   glyph	TeX name *)
			  9001: Texts.Write(P.W, "a")	(*	a	langle *)
			(* b *)	(*	b	vdash *)
			(* c *)	(*	c	models *)
			(* d *)	(*	d	dashv *)
			| 8721: Texts.Write(P.W, "e")	(*	e	sum *)
			(* f *)	(*	f	ll *)
			(* g *)	(*	g	gg *)
			| 8968: Texts.Write(P.W, "h")	(*	h	lceil *)
			| 8969: Texts.Write(P.W, "i")	(*	i	rceil *)
			| 8970: Texts.Write(P.W, "j")	(*	j	lfloor *)
			| 8971: Texts.Write(P.W, "k")	(*	k	rfloor *)
			(* l *)	(*	l	Vert *)
			(* m *)	(*	m	mp *)
			(* n *)	(*	n	prec *)
			(* o *)	(*	o	succ *)
			| 8776: Texts.Write(P.W, "p")	(*	p	simeq *)
			| 9002: Texts.Write(P.W, "q")	(*	q	rangle *)
			(* r *)	(*	r	not supset *)
			| 8629: Texts.Write(P.W, "s")	(*	s	(carriage return) *)
			(* t *)	(*	t	?? *)
			(* u *)	(*	u	?? *)
			(* v - moved down *)	(*	v	S *)
			(* w *)	(*	w	?? *)
			| 8747: Texts.Write(P.W, "x")	(*	x	int *)
			(* y *)	(*	y	oint *)
			(* z *)	(*	z	because *)
			(* C *)	(*	C	wp *)
			(* D *)	(*	D	oslash *)
			| 8853: Texts.Write(P.W, "E")	(*	E	oplus *)
			| 8709: Texts.Write(P.W, "F")	(*	F	emptyset *)
			| 8745: Texts.Write(P.W, "G")	(*	G	cap *)
			| 8746: Texts.Write(P.W, "H")	(*	H	cup *)
			| 8835: Texts.Write(P.W, "I")	(*	I	supset *)
			| 8839: Texts.Write(P.W, "J")	(*	J	supseteq *)
			| 8836: Texts.Write(P.W, "K")	(*	K	not subset *)
			| 8834: Texts.Write(P.W, "L")	(*	L	subset *)
			| 8838: Texts.Write(P.W, "M")	(*	M	subseteq *)
			| 8712: Texts.Write(P.W, "N")	(*	N	in *)
			| 8713: Texts.Write(P.W, "O")	(*	O	not in *)
			| 8736: Texts.Write(P.W, "P")	(*	P	angle *)
			| 8711: Texts.Write(P.W, "Q")	(*	Q	nabla *)
			| 8704: Texts.Write(P.W, "R")	(*	R	forall *)
			| 8707: Texts.Write(P.W, "S")	(*	S	exists *)
			| 8715: Texts.Write(P.W, "T")	(*	T	owns *)
			(* U *)	(*	U	sqcap *)
			| 8730: Texts.Write(P.W, "V")	(*	V	surb *)
			| 8901: Texts.Write(P.W, "W")	(*	W	cdot *)
			(* X *)	(*	X	lnot *)
			| 8869: Texts.Write(P.W, "Y")	(*	Y	land *)
			| 8870: Texts.Write(P.W, "Z")	(*	Z	lor *)
			(* 0 - moved down *)	(*	0	deg *)
			(* 1 - moved down *)	(*	1	pm *)
			| 8805: Texts.Write(P.W, "3")	(*	3	geq *)
			(* 4 *)	(*	4	times *)
			| 8733: Texts.Write(P.W, "5")	(*	5	propto *)
			| 8706: Texts.Write(P.W, "6")	(*	6	partial *)
			(* 7 - moved down *)	(*	7	bullet *)
			(* 8 - moved down *)	(*	8	div *)
			| 8800: Texts.Write(P.W, "9")	(*	9	not= *)
			(* ) *)	(*	)	swarrow *)
			(* ! *)	(*	!	mathbb R ?? *)
			| 8501: Texts.Write(P.W, "@")	(*	@	aleph *)
			| 8804: Texts.Write(P.W, "#")	(*	#	leq *)
			(* $ - moved down *)	(*	$	/ *)
			| 8734: Texts.Write(P.W, "%")	(*	%	infty *)
			| 8658: Texts.Write(P.W, "^")	(*	^	Rightarrow *)
			(* & *)	(*	&	>> *)
			(* * *)	(*	*	searrow *)
			(* ( *)	(*	(	nwarrow *)
			| 8592: Texts.Write(P.W, ",")	(*	,	gets *)
			| 8594: Texts.Write(P.W, ".")	(*	.	to *)
			| 8773: Texts.Write(P.W, ";")	(*	;	approx *)
			(* ' *)	(*	'	nearrow *)
			(* ` *)	(*	`	?? *)
			| 8593: Texts.Write(P.W, "-")	(*	-	uparrow *)
			(* = *)	(*	=	vert *)
			| 8595: Texts.Write(P.W, "/")	(*	/	downarrow *)
			| 8656: Texts.Write(P.W, "\")	(*	\	Leftarrow *)
			| 8660: Texts.Write(P.W, "[")	(*	[	Leftrightarrow *)
			| 8657: Texts.Write(P.W, "]")	(*	]	Uparrow *)
			(* < - moved down *)	(*	<	dots *)
			| 8722: Texts.Write(P.W, ">")	(*	>	(minus sign) *)
			| 8801: Texts.Write(P.W, ":")	(*	:	equiv *)
			(* " - moved down *)	(*	"	prime *)
			(* ~ - moved down *)	(*	~	cents *)
			| 8659: Texts.Write(P.W, "_")	(*	_	Downarrow *)
			| 8596: Texts.Write(P.W, "+")	(*	+	leftrightarrow *)
			ELSE
			END;
						Texts.SetFont (P.W, fnt);
					ELSIF (i >= 8201) & (i <= 8500) THEN	(* Math character *)
						Texts.SetFont (P.W, ChangeFontFamily(fnt, "Math"));
		CASE i OF	(*   glyph	TeX name *)
			  8465: Texts.Write(P.W, "A")	(*	A	Im *)
			| 8476: Texts.Write(P.W, "B")	(*	B	Re *)
			| 8243: Texts.Write(P.W, "2")	(*	2	(double prime) *)
			| 8226: Texts.Write(P.W, "7")	(*	7	bullet *)
			| 8260: Texts.Write(P.W, "$")	(*	$	/ *)
			| 8230: Texts.Write(P.W, "<")	(*	<	dots *)
			| 8242: Texts.Write(P.W, '"')	(*	"	prime *)
			| 8224: Texts.Write(P.W, "}")	(*	}	dagger *)
		ELSE
		END;
						Texts.SetFont (P.W, fnt);
					ELSIF (i >= 160) & (i <= 250) THEN	(* Math character *)
						Texts.SetFont (P.W, ChangeFontFamily(fnt, "Math"));
		CASE i OF	(*   glyph	TeX name *)
			  167: Texts.Write(P.W, "v")	(*	v	S *)
			| 176: Texts.Write(P.W, "0")	(*	0	deg *)
			| 177: Texts.Write(P.W, "1")	(*	1	pm *)
			| 247: Texts.Write(P.W, "8")	(*	8	div *)
			| 162: Texts.Write(P.W, "~")	(*	~	cents *)
		ELSE
		END;
						Texts.SetFont (P.W, fnt);
					ELSE
						Texts.Write(P.W, Strings.ISOToOberon[i])
					END
				END
			ELSE
				Texts.WriteString(P.W, "&#")
			END
		ELSE
			i := 0;
			WHILE ~S.end & Strings.IsAlpha(S.ch) & (i < 63) DO
				entity[i] := S.ch; INC(i); entity[i] := 0X;
				j := 0;
				WHILE (j < LEN(entities)) & (entities[j] # entity) DO
					INC(j)
				END;
				IF j < LEN(entities) THEN
					i := 63
				END;
				Read(S)
			END;
			entity[i] := 0X;
			i := 0;
			WHILE (i < LEN(entities)) & (entities[i] # entity) DO
				INC(i)
			END;
			IF i < LEN(entities) THEN
				Texts.Write(P.W, entityEncoding[i])
			ELSIF entity = "trade" THEN
				PushTextAttrs(P); Texts.SetOffset(P.W, 4);
				Texts.WriteString(P.W, "TM");
				PopTextAttrs(P)
			ELSIF entity = "reg" THEN
				Texts.WriteString(P.W, "(R)")
			ELSIF entity = "copy" THEN
				Texts.WriteString(P.W, "(c)")
			ELSE
				lib := Objects.ThisLibrary("HTMLIcons.Lib");
				Objects.GetRef(lib.dict, entity, ref);
				IF ref >= 0 THEN
					lib.GetObj(lib, ref, obj); WriteObj(P, obj)
				ELSE
					Texts.Write(P.W, "&"); Texts.WriteString(P.W, entity); RETURN
				END
			END;
			IF S.ch = ";" THEN
				Read(S)
			END
		END
	END WriteCharRef;

	PROCEDURE CharRefStr*(P: Page; VAR S: Scanner; VAR str: ARRAY OF CHAR);
		VAR
			i, j: LONGINT;
			entity: ARRAY 64 OF CHAR;
	BEGIN
		COPY("", str);
		IF S.ch = "#" THEN
			Read(S);
			IF Strings.IsDigit(S.ch) THEN
				i := 0;
				WHILE ~S.end & (i < 256) & Strings.IsDigit(S.ch) DO
					i := 10*i+ORD(S.ch)-ORD("0"); Read(S)
				END;
				IF S.ch = ";" THEN
					Read(S)
				END;
				CASE i OF
					169: Strings.Append(str, "(c)")
					|174: Strings.Append(str, "(R)")
					|188: Strings.Append(str, " 1/4")
					|189: Strings.Append(str, " 1/2")
					|190: Strings.Append(str, " 3/4")
				ELSE
					Strings.AppendCh(str, Strings.ISOToOberon[i])
				END
			ELSE
				Strings.Append(str, "&#")
			END
		ELSIF Strings.IsAlpha(S.ch) THEN
			i := 0;
			WHILE ~S.end & Strings.IsAlpha(S.ch) & (i < 63) DO
				entity[i] := S.ch; INC(i); entity[i] := 0X;
				j := 0;
				WHILE (j < LEN(entities)) & (entities[j] # entity) DO
					INC(j)
				END;
				IF j < LEN(entities) THEN
					i := 63
				END;
				Read(S)
			END;
			entity[i] := 0X;
			i := 0;
			WHILE (i < LEN(entities)) & (entities[i] # entity) DO
				INC(i)
			END;
			IF i < LEN(entities) THEN
				Strings.AppendCh(str, entityEncoding[i])
			ELSIF entity = "trade" THEN
				Strings.Append(str, "TM")
			ELSIF entity = "reg" THEN
				Strings.Append(str, "(R)")
			ELSIF entity = "copy" THEN
				Strings.Append(str, "(c)")
			ELSE
				Strings.AppendCh(str, "&"); Strings.Append(str, entity); RETURN
			END;
			IF S.ch = ";" THEN
				Read(S)
			END
		ELSE
			COPY("&", str)
		END
	END CharRefStr;

	PROCEDURE Next*(VAR S: Scanner);
		VAR i, l: LONGINT;
	BEGIN
		CASE S.state OF
			TextHtml: IF S.ch = "<" THEN
								Read(S);
								IF Strings.IsAlpha(S.ch) OR (S.ch = "/") OR (S.ch = "!") THEN
									S.class := OpenTag
								ELSE
									S.char := S.ch; S.class := Character
								END
							ELSIF S.ch = "&" THEN
								Read(S); S.class := CharRef
							ELSIF (S.ch <= " ") & (S.ch # 0X) & ~S.pre THEN
								WHILE ~S.end & (S.ch <= " ") DO
									Read(S)
								END;
								IF (S.ch = "<") & (S.class = CloseTag) THEN
									Read(S);
									IF Strings.IsAlpha(S.ch) OR (S.ch = "/") OR (S.ch = "!") THEN
										S.class := OpenTag
									ELSE
										S.char := S.ch; S.class := Character
									END
								ELSIF S.end THEN
									S.class := Undef; S.state := End
								ELSE
									S.class := WhiteSpace
								END
							ELSIF ~S.end THEN
								S.char := S.ch; Read(S); S.class := Character(*; S.skipWS := FALSE*)
							ELSE
								S.class := Undef; S.state := End
							END
			|TextPlain: IF S.ch # 0X THEN
								S.char := S.ch; Read(S); S.class := Character
							ELSE
								S.class := Undef; S.state := End
							END
			|InTag: WHILE ~S.end & (S.ch <= " ") DO
							Read(S)
						END;
						IF S.ch = "/" THEN
							Read(S); S.class := OpenEndTag
						ELSIF S.ch = ">" THEN
							Read(S); S.class := CloseTag
						ELSIF S.ch = "&" THEN
							Read(S); S.class := CharRef
						ELSIF Strings.IsAlpha(S.ch) THEN
							i := 0; l := LEN(S.value)-1;
							WHILE ~S.end & (Strings.IsAlpha(S.ch) OR Strings.IsDigit(S.ch)) DO
								IF i < l THEN
									S.value[i] := S.ch; INC(i)
								END;
								Read(S)
							END;
							S.value[i] := 0X; S.class := Value;
WHILE ~S.end & (S.ch <= " ") DO
	Read(S)
END;
IF S.ch = "<" THEN
	Read(S);
	WHILE ~S.end & (S.ch <= " ") DO
		Read(S)
	END;
	IF Strings.IsAlpha(S.ch) THEN
		i := 0; l := LEN(S.value)-1;
		WHILE ~S.end & (Strings.IsAlpha(S.ch) OR Strings.IsDigit(S.ch)) DO
			IF i < l THEN
				S.value[i] := S.ch; INC(i)
			END;
			Read(S)
		END
	END
END
						ELSIF ~S.end THEN
							S.char := S.ch; Read(S); S.class := Character
						ELSE
							S.class := Undef; S.state := End
						END
		ELSE
			S.class := Undef; S.state := End
		END
	END Next;

	PROCEDURE NextAttr*(VAR S: Scanner; VAR name: ARRAY OF CHAR): BOOLEAN;
		VAR
			i, l: LONGINT;
			charRef: ARRAY 16 OF CHAR;
			quoted: BOOLEAN;
	BEGIN
		WHILE ~S.end & (S.ch <= " ") DO
			Read(S)
		END;
		IF (S.ch = ",") OR (S.ch = ";") THEN
			Read(S);
			WHILE ~S.end & (S.ch <= " ") DO
				Read(S)
			END
		END;
		i := 0; l := LEN(name)-1;
		WHILE ~S.end & Strings.IsAlpha(S.ch) DO
			IF i < l THEN
				name[i] := CAP(S.ch); INC(i)
			END;
			Read(S)
		END;
		name[i] := 0X;
		IF i > 0 THEN
			WHILE ~S.end & (S.ch <= " ") DO
				Read(S)
			END;
			IF S.ch = "=" THEN
				Read(S);
				WHILE ~S.end & (S.ch <= " ") DO
					Read(S)
				END;
				IF S.ch = 022X THEN
					Read(S); quoted := TRUE
				ELSE
					quoted := FALSE
				END;
				i := 0; l := LEN(S.value)-1;
				WHILE ~S.end & ( (~quoted & (S.ch > " ") & (S.ch # ">")) OR (quoted & (S.ch # 022X)) ) DO
					IF i < l THEN
						IF S.ch = "&" THEN
							Read(S); CharRefStr(S.page, S, charRef);
							S.value[i] := 0X; Strings.Append(S.value, charRef);
							i := Strings.Length(S.value)
						ELSIF (S.ch >= " ") OR (S.ch = Strings.Tab) THEN
							S.value[i] := S.ch; INC(i); Read(S)
						ELSE
							Read(S)
						END
					ELSE
						Read(S)
					END
				END;
				IF S.ch = 022X THEN
					Read(S)
				END;
				WHILE ~quoted & (i > 0) & (S.value[i-1] <= " ") DO
					S.value[i-1] := 0X; DEC(i)
				END;
				S.value[i] := 0X
			ELSE
				COPY("", S.value)
			END;
			S.class := Value; RETURN TRUE
		END;
		COPY("", name); COPY("", S.value); RETURN FALSE
	END NextAttr;

	PROCEDURE GetAttrs*(VAR S: Scanner; VAR attrs: TagAttr);
		VAR attr: TagAttr;
	BEGIN
		attrs := NIL; NEW(attr);
		WHILE NextAttr(S, attr.name) DO
			attr.next := attrs; attrs := attr;
			COPY(S.value, attr.value);
			NEW(attr)
		END
	END GetAttrs;

	PROCEDURE FindAttr*(attrs: TagAttr; name: ARRAY OF CHAR): TagAttr;
		VAR attr: TagAttr;
	BEGIN
		attr := attrs;
		WHILE (attr # NIL) & (attr.name # name) DO
			attr := attr.next
		END;
		RETURN attr
	END FindAttr;

	PROCEDURE OpenScanner*(VAR S: Scanner; St: Streams.Stream);
	BEGIN
		(*S.skipWS := FALSE; S.genWS := FALSE;*)
		S.ch := 0X; S.next := 0X; S.end := FALSE;
		S.S := St; S.class := Undef; S.state := TextHtml; S.pre := FALSE;
		Read(S)
	END OpenScanner;

	PROCEDURE A(VAR S: Scanner; on: BOOLEAN);
		VAR
			P: Page;
			attr: ARRAY 64 OF CHAR;
			obj: Objects.Object;
			isRef, newDoc: BOOLEAN;
	BEGIN
		P := S.page; CloseA(P); P.linkkey := HyperDocs.UndefKey;
		IF on THEN
			isRef := FALSE; newDoc := FALSE;
			WHILE NextAttr(S, attr) DO
				IF attr = "HREF" THEN
					isRef := TRUE; HREF(P, S.value, attr, P.linkkey);
					IF P.linkkey # HyperDocs.UndefKey THEN
						P.alink := HyperDocs.LinkControl(P.linkkey)
					ELSE
						P.alink := Gadgets.CreateObject("TextGadgets.NewControl");
						Attributes.SetString(P.alink, "Cmd", attr)
					END
				ELSIF (attr = "NAME") OR (attr = "ID") THEN
					IF S.value = P.orgLabel THEN
						Texts.Append(P.T, P.W.buf); P.orgPos := P.T.len
					END;
					obj := Gadgets.CreateObject("TextGadgets.NewControl");
					WriteObj(P, obj); Attributes.SetString(obj, "Name", S.value)
				ELSIF attr = "TARGET" THEN
					newDoc := TRUE
				END
			END;
			IF isRef THEN
				IF newDoc THEN
					Attributes.SetString(P.alink, "Opt", "New")
				END;
				IF ~HyperDocs.Visited(P.linkkey) THEN
					PushTextAttrs(P); Texts.SetColor(P.W, SHORT(P.linkC))
				ELSE
					PushTextAttrs(P); Texts.SetColor(P.W, SHORT(P.oldLinkC))
				END
			END
		END
	END A;

	PROCEDURE ADDRESS(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			PushTextAttrs(P);
			Texts.SetFont(P.W, Syntax(12, "i"))
		ELSE
			PopTextAttrs(P)
		END
	END ADDRESS;

	PROCEDURE B(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			PushTextAttrs(P);
			Texts.SetFont(P.W, ChangeFontAttr(P.W.lib(Fonts.Font), "b"))
		ELSE
			PopTextAttrs(P)
		END
	END B;

	PROCEDURE SplitHostPort(VAR url, host: ARRAY OF CHAR; VAR port: INTEGER);
		VAR
			i, j: INTEGER;
			val: LONGINT;
	BEGIN
		i := 0;
		WHILE (url[i] # 0X) & (url[i] # "/") DO
			INC(i)
		END;
		WHILE url[i] = "/" DO
			INC(i)
		END;
		j := 0;
		WHILE (url[j] # 0X) & (url[j] # "@") DO
			INC(j)
		END;
		IF url[j] = "@" THEN
			i := j+1
		END;
		j := 0;
		WHILE (url[i] # 0X) & (url[i] # "/") & (url[i] # ":") DO
			host[j] := url[i]; INC(i); INC(j)
		END;
		host[j] := 0X;
		IF url[i] = ":" THEN
			INC(i); Strings.StrToIntPos(url, val, i);
			port := SHORT(val)
		ELSE
			port := 0
		END
	END SplitHostPort;

	PROCEDURE BASE(VAR S: Scanner; on: BOOLEAN);
		VAR
			P: Page;
			attr, label: ARRAY 64 OF CHAR;
			s: HyperDocs.LinkScheme;
			key: LONGINT;
			port: INTEGER;
	BEGIN
		IF on THEN
			P := S.page;
			WHILE NextAttr(S, attr) DO
				IF attr = "HREF" THEN
					P.base.key := HyperDocs.BuildKey(P.base, S.value);
					s := HyperDocs.LinkSchemeByKey(P.base.key);
					IF s = NIL THEN
						s := HyperDocs.LinkSchemeByPrefix("file")
					END;
					COPY(s.prefix, P.base.prefix);
					HyperDocs.RetrieveLink(P.base.key, S.value);
					IF P.base.prefix = "http" THEN
						P.base.key := HTTPDocs0.SplitHTTPAdr(S.value, P.base.host, P.base.path, label, P.base.port)
					ELSIF P.base.prefix = "file" THEN
						P.base.key := HyperDocs.SplitFileAdr(S.value, P.base.path, label);
						P.base.host := ""; P.base.port := 0
					ELSE (* proxy *)
						SplitHostPort(S.value, P.base.host, P.base.port);
						key := HTTPDocs0.SplitHTTPAdr(S.value, P.base.host, P.base.path, label, port)
					END
				END
			END
		END
	END BASE;

	PROCEDURE HexVal(ch: CHAR): INTEGER;
	BEGIN
		IF (ch >= "0") & (ch <= "9") THEN
			RETURN ORD(ch)-ORD("0")
		ELSIF (ch >= "A") & (ch <= "F") THEN
			RETURN ORD(ch)-ORD("A")+10
		ELSIF (ch >= "a") & (ch <= "f") THEN
			RETURN ORD(ch)-ORD("a")+10
		ELSE
			RETURN 256
		END
	END HexVal;

	PROCEDURE Color(VAR val: ARRAY OF CHAR; VAR col: INTEGER);
		VAR
			r, g, b, rr, gg, bb, i, bestC: INTEGER;
			diff, mdiff: REAL;
	BEGIN
		IF val[0] = "#" THEN
			r := 16*HexVal(val[1])+HexVal(val[2]);
			g := 16*HexVal(val[3])+HexVal(val[4]);
			b := 16*HexVal(val[5])+HexVal(val[6])
		ELSE
			r := 16*HexVal(val[0])+HexVal(val[1]);
			g := 16*HexVal(val[2])+HexVal(val[3]);
			b := 16*HexVal(val[4])+HexVal(val[5])
		END;
		IF (r > 255) OR (g > 255) OR (b > 255) THEN
			RETURN
		END;
		mdiff := MAX(REAL); bestC := 0;
		i := 0;
		WHILE (i < 256) & (mdiff > 0.0) DO
			Display.GetColor(i, rr, gg, bb);
			diff := LONG(rr-r)*LONG(rr-r);
			diff := diff+LONG(gg-g)*LONG(gg-g);
			diff := diff+LONG(bb-b)*LONG(bb-b);
			IF diff < mdiff THEN
				bestC := i; mdiff := diff
			END;
			INC(i)
		END;
		col := bestC
	END Color;

	PROCEDURE BASEFONT(VAR S: Scanner; on: BOOLEAN);
		VAR
			P: Page;
			attr: ARRAY 64 OF CHAR;
			val: LONGINT;
			size, i: INTEGER;
			col: BOOLEAN;
	BEGIN
		P := S.page;
		IF on THEN
			col := FALSE; size := GetFontSize(P);
			WHILE NextAttr(S, attr) DO
				IF attr = "SIZE" THEN
					i := 1;
					IF S.value[0] = "-" THEN
						Strings.StrToIntPos(S.value, val, i);
						size := size-SHORT(val)
					ELSIF S.value[0] = "+" THEN
						Strings.StrToIntPos(S.value, val, i);
						size := size+SHORT(val)
					ELSE
						i := 0;
						Strings.StrToIntPos(S.value, val, i);
						size := SHORT(val)
					END
				ELSIF attr = "COLOR" THEN
					Color(S.value, P.textC); col := TRUE
				END
			END;
			SetFontSize(P, size);
			IF col THEN
				Texts.SetColor(P.W, SHORT(P.textC))
			END
		ELSE
			PopTextAttrs(P)
		END
	END BASEFONT;

	PROCEDURE BIG(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			SetFontSize(P, GetFontSize(P)+2)
		ELSE
			PopTextAttrs(P)
		END
	END BIG;

	PROCEDURE BLINK(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			PushTextAttrs(P);
			Texts.SetColor(P.W, SHORT(Display3.red))
		ELSE
			PopTextAttrs(P)
		END
	END BLINK;

	PROCEDURE BLOCKQUOTE(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			PushTextAttrs(P);
			P.style := TextGadgets.newStyle(); InitTabs(P.style); P.style.mode := DefStyle;
			WriteObj(P, P.style);
			Texts.SetFont(P.W, Syntax(12, "i"))
		ELSE
			PopTextAttrs(P)
		END;
		(*S.skipWS := TRUE*)
	END BLOCKQUOTE;

	PROCEDURE ChangeColors(P: Page; from, to: SHORTINT);
		VAR tattr: TextAttrs;
	BEGIN
		IF P.W.col = from THEN
			Texts.SetColor(P.W, to)
		END;
		tattr := P.textAttrs;
		WHILE tattr # NIL DO
			IF tattr.col = from THEN
				tattr.col := to
			END;
			tattr := tattr.next
		END
	END ChangeColors;

	PROCEDURE BODY(VAR S: Scanner; on: BOOLEAN);
		VAR
			P: Page;
			attr: ARRAY 64 OF CHAR;
			key: LONGINT;
			doc: Documents.Document;
			BackE: HTTPDocs0.Entry;
			col: INTEGER;
	BEGIN
		P := S.page;
		IF on THEN
			Texts.Append(P.T, P.W.buf);
			WHILE NextAttr(S, attr) DO
				IF attr = "BGCOLOR" THEN
					Color(S.value, P.textbackC); Attributes.SetInt(P.D.dsc, "Color", P.textbackC)
				ELSIF attr = "TEXT" THEN
					col := P.textC; Color(S.value, col);
					ChangeColors(P, SHORT(P.textC), SHORT(col));
					P.textC := col
				ELSIF attr = "LINK" THEN (* hyper text link *)
					col := P.linkC; Color(S.value, col);
					ChangeColors(P, SHORT(P.linkC), SHORT(col));
					P.linkC := col; Attributes.SetInt(P.D.dsc, "LinkColor", P.linkC)
				ELSIF attr = "VLINK" THEN (* visited hyper text link *)
					col := P.oldLinkC; Color(S.value, col);
					ChangeColors(P, SHORT(P.oldLinkC), SHORT(col));
					P.oldLinkC := col; Attributes.SetInt(P.D.dsc, "OldLinkColor", P.oldLinkC)
				ELSIF attr = "BACKGROUND" THEN
					key := HyperDocs.BuildKey(P.base, S.value);
					IF imgs THEN
						NEW(BackE);
						BackE.basekey := P.base.dockey; BackE.ol := NIL; BackE.attrs := NIL; BackE.text := P.T;
						BackE.pos := -1; BackE.key := HyperDocs.UndefKey; BackE.obj := P.D;
						NEW(doc); HyperDocs.DocNameByKey(doc.name, key); doc.handle := NIL; doc.dsc := NIL;
						HTTPDocs0.RequestDoc(doc, HTTPDocs0.httpProxy, key, "GET", FALSE, BackE, NIL)
					END
				END
			END
		END
	END BODY;

	PROCEDURE BR(VAR S: Scanner; on: BOOLEAN);
	BEGIN
		IF on THEN
			WriteLn(S.page)(*; S.page.lines := 0*)
		END;
		(*S.skipWS := TRUE*)
	END BR;

	PROCEDURE ExecAttrs*;
		VAR
			exec, cont: Objects.Object;
			name, nr: ARRAY 32 OF CHAR;
			i: LONGINT;
	BEGIN
		cont := Gadgets.context; exec := Gadgets.executorObj;
		IF exec # NIL THEN
			i := 1; name := "Cmd";
			Strings.IntToStr(i, nr);
			Strings.Append(name, nr);
			WHILE Attributes.FindAttr(name, exec(Gadgets.Frame).attr) # NIL DO
				Gadgets.ExecuteAttr(exec(Gadgets.Frame), name, cont, NIL, NIL);
				INC(i); name := "Cmd";
				Strings.IntToStr(i, nr);
				Strings.Append(name, nr)
			END
		END
	END ExecAttrs;

	PROCEDURE CALL(VAR S: Scanner; on: BOOLEAN);
		(* ejz *)
		VAR
			P: Page;
			name, attr: ARRAY 32 OF CHAR;
			i: LONGINT;
	BEGIN
		P := S.page; CloseA(P);
		IF on THEN
			P.clink := Gadgets.CreateObject("TextGadgets.NewControl");
			i := 0;
			WHILE NextAttr(S, attr) DO
				IF attr = "CMD" THEN
					INC(i); name := "Cmd";
					Strings.IntToStr(i, attr);
					Strings.Append(name, attr);
					Attributes.SetString(P.clink, name, S.value)
				END
			END;
			IF i = 0 THEN
				P.clink := NIL
			ELSE
				Attributes.SetString(P.clink, "Cmd", "HTMLDocs.ExecAttrs")
			END;
			PushTextAttrs(P);
			Texts.SetColor(P.W, SHORT(Display3.red))
		ELSE
			IF P.clink # NIL THEN
				WriteObj(P, P.clink)
			END;
			P.clink := NIL; PopTextAttrs(P)
		END
	END CALL;

	PROCEDURE CENTER(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			PushTextAttrs(P);
			P.style := TextGadgets.newStyle(); InitTabs(P.style); P.style.mode := {TextGadgets.middle};
			WriteObj(P, P.style)
		ELSE
			PopTextAttrs(P)
		END;
		 (*S.skipWS := TRUE*)
	END CENTER;

	PROCEDURE CITE(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			PushTextAttrs(P);
			Texts.SetFont(P.W, ChangeFontAttr(P.W.lib(Fonts.Font), "i"))
		ELSE
			PopTextAttrs(P)
		END
	END CITE;

	PROCEDURE CODEx(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			PushTextAttrs(P);
			Texts.SetFont(P.W, mono)
		ELSE
			PopTextAttrs(P)
		END
	END CODEx;

	PROCEDURE DD(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			IF (P.lists # NIL) & (P.lists.kind = DescList) & P.lists.dtok THEN
				Texts.Write(P.W, Strings.Tab)
			ELSE
				IF P.lists # NIL THEN
					INC(P.lists.itemNr);
					IF P.lists.itemNr > 1 THEN
						WriteLn(P)
					END
				ELSE
					WriteLn(P)
				END
			END
		END;
		P.blank := FALSE
		(*S.skipWS := TRUE*)
	END DD;

	PROCEDURE DFN(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			PushTextAttrs(P);
			Texts.SetFont(P.W, ChangeFontAttr(P.W.lib(Fonts.Font), "i"))
		ELSE
			PopTextAttrs(P)
		END
	END DFN;

	PROCEDURE DIR(VAR S: Scanner; on: BOOLEAN);
	BEGIN
		IF on THEN
			OpenList(S.page, DefList)
		ELSE
			CloseList(S.page)
		END;
		(*S.skipWS := TRUE*)
	END DIR;

	PROCEDURE DIVI(VAR S: Scanner; on: BOOLEAN);
		VAR
			P: Page;
			attr: ARRAY 32 OF CHAR;
			style: TextGadgets.Style;
	BEGIN
		P := S.page;
		IF on THEN
			PushTextAttrs(P);
			style := NIL;
			WHILE NextAttr(S, attr) DO
				IF attr = "ALIGN" THEN
					style := TextAlign(S.value)
				END
			END;
			IF style # NIL THEN
				P.style := style; WriteObj(P, P.style)
			END
		ELSE
			PopTextAttrs(P)
		END;
		(*S.skipWS := TRUE*)
	END DIVI;

	PROCEDURE DL(VAR S: Scanner; on: BOOLEAN);
	BEGIN
		IF on THEN
			OpenList(S.page, DescList)
		ELSE
			CloseList(S.page)
		END;
		(*S.skipWS := TRUE*)
	END DL;

	PROCEDURE DT(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			IF P.lists # NIL THEN
				INC(P.lists.itemNr);
				IF P.lists.itemNr > 1 THEN
					WriteLn(P)
				END;
				IF P.lists.kind = DescList THEN
					P.lists.dtok := TRUE;
					Texts.Write(P.W, Strings.Tab)
				END
			ELSE
				WriteLn(P)
			END
		END;
		P.blank := FALSE
		(*S.skipWS := TRUE*)
	END DT;

	PROCEDURE EM(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			PushTextAttrs(P);
			Texts.SetFont(P.W, ChangeFontAttr(P.W.lib(Fonts.Font), "i"))
		ELSE
			PopTextAttrs(P)
		END
	END EM;

	PROCEDURE FRAME(VAR S: Scanner; on: BOOLEAN);
		VAR
			P: Page;
			attr: ARRAY 64 OF CHAR;
	BEGIN
		P := S.page; CloseA(P); P.linkkey := HyperDocs.UndefKey;
		IF on THEN
			WHILE NextAttr(S, attr) DO
				IF (attr = "SRC") OR (attr = "HREF") THEN
					P.lines := 0; WriteLn(P); WriteLn(P); Texts.WriteString(P.W, "FRAME Reference: ");
					HREF(P, S.value, attr, P.linkkey);
					IF P.linkkey # HyperDocs.UndefKey THEN
						P.alink := HyperDocs.LinkControl(P.linkkey);
						HyperDocs.RetrieveLink(P.linkkey, S.value);
						Attributes.SetString(P.alink, "Opt", "N")
					ELSE
						P.alink := Gadgets.CreateObject("TextGadgets.NewControl");
						Attributes.SetString(P.alink, "Cmd", attr)
					END;
					PushTextAttrs(P); Texts.SetColor(P.W, SHORT(P.linkC));
					Texts.WriteString(P.W, S.value); WriteObj(P, P.alink);
					P.alink := NIL; P.linkkey := HyperDocs.UndefKey;
					PopTextAttrs(P); WriteLn(P)
				END
			END
		END
	END FRAME;

	PROCEDURE FONT(VAR S: Scanner; on: BOOLEAN);
		VAR
			P: Page;
			attr: ARRAY 64 OF CHAR;
			val: LONGINT;
			size, i, textC: INTEGER;
			col: BOOLEAN;
	BEGIN
		P := S.page;
		IF on THEN
			col := FALSE; size := GetFontSize(P);
			WHILE NextAttr(S, attr) DO
				IF attr = "SIZE" THEN
					i := 1;
					IF S.value[0] = "-" THEN
						Strings.StrToIntPos(S.value, val, i);
						size := size-SHORT(val)
					ELSIF S.value[0] = "+" THEN
						Strings.StrToIntPos(S.value, val, i);
						size := size+SHORT(val)
					ELSE
						i := 0;
						Strings.StrToIntPos(S.value, val, i);
						size := SHORT(val)
					END
				ELSIF attr = "COLOR" THEN
					Color(S.value, textC); col := TRUE
				END
			END;
			SetFontSize(P, size);
			IF col THEN
				Texts.SetColor(P.W, SHORT(textC))
			END
		ELSE
			PopTextAttrs(P)
		END
	END FONT;

	PROCEDURE GREEN(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			PushTextAttrs(P);
			Texts.SetColor(P.W, SHORT(Display3.green))
		ELSE
			PopTextAttrs(P)
		END
	END GREEN;

	PROCEDURE H(VAR S: Scanner; on: BOOLEAN);
		VAR
			P: Page;
			attr: ARRAY 64 OF CHAR;
			style: TextGadgets.Style;
	BEGIN
		P := S.page;
		IF on THEN
			style := NIL; PushTextAttrs(P);
			IF ~P.left THEN
				WriteLn(P); WriteLn(P)
			ELSE
				P.left := FALSE
			END;
			CASE ORD(S.value[1])-ORD("0") OF
				1: Texts.SetFont(P.W, Syntax(20, 0X))
				|2: Texts.SetFont(P.W, Syntax(16, 0X))
				|3: Texts.SetFont(P.W, Syntax(16, "i"))
				|4: Texts.SetFont(P.W, Syntax(14, 0X))
				|5: Texts.SetFont(P.W, Syntax(14, "i"))
				|6: Texts.SetFont(P.W, Syntax(12, 0X))
			ELSE
				Texts.SetFont(P.W, Syntax(12, 0X))
			END;
			WHILE NextAttr(S, attr) DO
				IF attr = "ALIGN" THEN
					style := TextAlign(S.value)
				ELSIF attr = "SRC" THEN
(* get image *)
				ELSIF attr = "DINGBAT" THEN
(* get icon with name value *)
				END
			END;
			IF style # NIL THEN
				P.style := style; WriteObj(P, P.style)
			END
		ELSE
			CloseA(P); PopTextAttrs(P);
			WriteLn(P); WriteLn(P)
		END;
		(*S.skipWS := TRUE*)
	END H;

	PROCEDURE HEAD(VAR S: Scanner; on: BOOLEAN);
	BEGIN
		(* ignore *)
	END HEAD;

	PROCEDURE HP(VAR S: Scanner; on: BOOLEAN);
	BEGIN
		(* ignore *)
	END HP;

	PROCEDURE HR(VAR S: Scanner; on: BOOLEAN);
		VAR
			attr: ARRAY 64 OF CHAR;
			P: Page;
			l: LONGINT;
			w, h, pos: INTEGER;
	BEGIN
		IF on THEN
			P := S.page; CloseA(P);
			w := dispW; h := 1;
			WHILE NextAttr(S, attr) DO
				IF attr = "SIZE" THEN
					Strings.StrToInt(S.value, l); h := SHORT(l)
				ELSIF attr = "WIDTH" THEN
					pos := 0; Strings.StrToIntPos(S.value, l, pos);
					w := SHORT(l);
					IF S.value[pos] = "%" THEN
						w := SHORT( (LONG((5*dispW) DIV 8) * w) DIV LONG(100) )
					END
				END
			END;
			HorzRule(P, w, h)
		END;
		(*S.skipWS := TRUE*)
	END HR;

	PROCEDURE HTML(VAR S: Scanner; on: BOOLEAN);
	BEGIN
(*		IF ~on THEN
			Texts.WriteLn(S.page.W);
			(*S.skipWS := TRUE; *)S.state := TextPlain
		END *)
	END HTML;

	PROCEDURE HTTP(VAR S: Scanner; on: BOOLEAN);
	BEGIN
		(* ignore *)
	END HTTP;

	PROCEDURE I(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			PushTextAttrs(P);
			Texts.SetFont(P.W, ChangeFontAttr(P.W.lib(Fonts.Font), "i"))
		ELSE
			PopTextAttrs(P)
		END
	END I;

	PROCEDURE KBD(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			PushTextAttrs(P);
			Texts.SetFont(P.W, mono)
		ELSE
			PopTextAttrs(P)
		END
	END KBD;

	PROCEDURE LI(VAR S: Scanner; on: BOOLEAN);
		VAR
			P: Page;
			i: INTEGER;
	BEGIN
		P := S.page;
		IF on THEN
			IF P.lists # NIL THEN
				INC(P.lists.itemNr);
				IF P.lists.itemNr > 1 THEN
					WriteLn(P)
				END;
				FOR i := 1 TO P.lists.nesting DO
					Texts.Write(P.W, Strings.Tab)
				END
			ELSE
				WriteLn(P)
			END;
			IF (P.lists # NIL) & (P.lists.kind = OrderedList) THEN
				Texts.WriteInt(P.W, P.lists.itemNr, 0)
			ELSE
				IF P.lists # NIL THEN
					i := P.lists.nesting MOD LEN(bullets)
				ELSE
					i := 0
				END;
				PushTextAttrs(P);
				Texts.SetFont(P.W, bullets[i].f);
				Texts.Write(P.W, bullets[i].c);
				PopTextAttrs(P)
			END;
			Texts.Write(P.W, Strings.Tab)
		END;
		P.blank := FALSE
		(*S.skipWS := TRUE*)
	END LI;

	PROCEDURE LINK(VAR S: Scanner; on: BOOLEAN);
(*		VAR
			P: Page;
			attr, cmd, caption: ARRAY 64 OF CHAR;
			key: LONGINT;
			obj: Objects.Object;
	BEGIN
		IF on THEN
			P := S.page; caption := ""; cmd := "";
			WHILE NextAttr(S, attr) DO
				IF attr = "HREF" THEN
					HREF(P, S.value, cmd, key);
					IF key # HyperDocs.UndefKey THEN
						cmd := "HyperDocs.FollowLink #Key"
					END
				ELSIF attr = "REV" THEN
					IF caption = "" THEN
						COPY(S.value, caption)
					END
				ELSIF attr = "REL" THEN
					IF caption = "" THEN
						COPY(S.value, caption)
					END
				ELSIF attr = "TITLE" THEN
					COPY(S.value, caption)
				END
			END;
			IF cmd # "" THEN
				obj := Gadgets.CreateObject("BasicGadgets.NewButton");
				Attributes.SetString(obj, "Caption", caption);
				Attributes.SetString(obj, "Cmd", cmd);
(* ?! fixup on reload *)
				Attributes.SetInt(obj, "Key", key);
				WriteObj(P, obj)
			END
		END	*)
	END LINK;

	PROCEDURE LISTING(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			PushTextAttrs(P);
			Texts.SetFont(P.W, mono);
			S.pre := TRUE
		ELSE
			PopTextAttrs(P);
			S.pre := FALSE
		END
	END LISTING;

	PROCEDURE ISINDEX(VAR S: Scanner; on: BOOLEAN);
		VAR
			P: Page;
			objt, objb: Objects.Object;
			form: Form;
			attr: ARRAY 64 OF CHAR;
			prompt: ARRAY 512 OF CHAR;
			key: LONGINT;
	BEGIN
		IF on THEN
			P := S.page;
			key := P.base.key; NewForm(); form := Objects.NewObj(Form);
			prompt := "This is a searchable index. Enter search keywords: ";
			WHILE NextAttr(S, attr) DO
				IF attr = "PROMPT" THEN
					COPY(S.value, prompt)
				ELSIF attr = "HREF" THEN
					key := HyperDocs.BuildKey(P.base, S.value)
				END
			END;
			WriteObj(P, form); HorzRule(P, dispW, 1);
			Texts.WriteString(P.W, prompt);
			objt := Gadgets.CreateObject("BasicGadgets.NewInteger");
			Attributes.SetInt(objt, "Value", key);
			AddFormObj(P, form, objt, "@ACTION", FALSE, FALSE);
			objt := Gadgets.CreateObject("TextFields.NewTextField");
			AddFormObj(P, form, objt, "QUERY", FALSE, TRUE);
			objb := Gadgets.CreateObject("BasicGadgets.NewButton");
			objb(Display.Frame).H := objt(Display.Frame).H;
			Attributes.SetString(objb, "Query", "ISINDEX");
			Attributes.SetString(objb, "Method", "GET");
			Attributes.SetString(objb, "Caption", "Search");
			Attributes.SetString(objb, "Cmd", "HTMLDocs.SubmitQuery");
			AddFormObj(P, form, objb, "", FALSE, TRUE);
			HorzRule(P, dispW, 1)
		END
	END ISINDEX;

	PROCEDURE MENU(VAR S: Scanner; on: BOOLEAN);
	BEGIN
		IF on THEN
			OpenList(S.page, DefList)
		ELSE
			CloseList(S.page)
		END;
		(*S.skipWS := TRUE*)
	END MENU;

	PROCEDURE META(VAR S: Scanner; on: BOOLEAN);
	BEGIN
		(* ignore *)
	END META;

	PROCEDURE NEXTID(VAR S: Scanner; on: BOOLEAN);
	BEGIN
		(* ignore *)
	END NEXTID;

	PROCEDURE NOFRAMES(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		HorzRule(P, dispW, 1)
	END NOFRAMES;

	PROCEDURE OL(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			OpenList(P, OrderedList)
		ELSE
			CloseList(P)
		END;
		(*S.skipWS := TRUE*)
	END OL;

	PROCEDURE P(VAR S: Scanner; on: BOOLEAN);
		VAR
			P: Page;
			attr: ARRAY 64 OF CHAR;
			style: TextGadgets.Style;
	BEGIN
		P := S.page;
		IF on THEN
			style := NIL; CloseA(P);
			WriteLn(P); WriteLn(P); (*P.lines := 0;*)
			WHILE NextAttr(S, attr) DO
				IF attr = "ALIGN" THEN
					style := TextAlign(S.value)
				END
			END;
			IF style # NIL THEN
				PushTextAttrs(P);
				P.style := style; WriteObj(P, P.style)
			END
		ELSE
			PopTextAttrs(P)
		END;
		(*S.skipWS := TRUE*)
	END P;

	PROCEDURE PLAINTEXT(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			PushTextAttrs(P);
			Texts.SetFont(P.W, mono);
			S.state := TextPlain; S.pre := TRUE
		ELSE
			PopTextAttrs(P);
			S.state := TextHtml; S.pre := FALSE
		END
	END PLAINTEXT;

	PROCEDURE PRE(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			PushTextAttrs(P);
			Texts.SetFont(P.W, mono);
			S.pre := TRUE
		ELSE
			PopTextAttrs(P);
			S.pre := FALSE
		END
	END PRE;

	PROCEDURE Q(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			Texts.WriteString(P.W, "<<")
		ELSE
			Texts.WriteString(P.W, ">>")
		END
	END Q;

	PROCEDURE RANGE(VAR S: Scanner; on: BOOLEAN);
	BEGIN
		(* ignore *)
	END RANGE;

	PROCEDURE SAMP(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			PushTextAttrs(P);
			Texts.SetFont(P.W, mono)
		ELSE
			PopTextAttrs(P)
		END
	END SAMP;

	PROCEDURE SMALL(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			SetFontSize(P, GetFontSize(P)-2)
		ELSE
			PopTextAttrs(P)
		END
	END SMALL;

	PROCEDURE STRIKE(VAR S: Scanner; on: BOOLEAN);
		(* strikethrough text, how ? *)
	BEGIN
		(* ignore *)
	END STRIKE;

	PROCEDURE STRONG(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			PushTextAttrs(P);
			Texts.SetFont(P.W, ChangeFontAttr(P.W.lib(Fonts.Font), "b"))
		ELSE
			PopTextAttrs(P)
		END
	END STRONG;

	PROCEDURE STYLE(VAR S: Scanner; on: BOOLEAN);
	BEGIN
		(* ignore *)
	END STYLE;

	PROCEDURE SUB(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			SetFontSize(P, GetFontSize(P)-2);
			Texts.SetOffset(P.W, P.W.voff-4)
		ELSE
			PopTextAttrs(P)
		END
	END SUB;

	PROCEDURE SUP(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			SetFontSize(P, GetFontSize(P)-2);
			Texts.SetOffset(P.W, P.W.voff+4)
		ELSE
			PopTextAttrs(P)
		END
	END SUP;

	PROCEDURE TINY(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			SetFontSize(P, GetFontSize(P)-2)
		ELSE
			PopTextAttrs(P)
		END
	END TINY;

	PROCEDURE TITLE(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF P.head THEN
			IF on THEN
				PushTextAttrs(P);
				Texts.SetFont(P.W, Syntax(12, 0X));
				Texts.WriteString(P.W, "Title: ")
			ELSE
				WriteLn(P); PopTextAttrs(P);
				HorzRule(P, dispW, 2);
				Texts.Append(P.T, P.W.buf);
				P.headerLen := P.T.len
			END
ELSIF ~on THEN
	PushTextAttrs(P);
	Texts.OpenWriter(P.W);
	PopTextAttrs(P)
		END
		(*S.skipWS := TRUE*)
	END TITLE;

	PROCEDURE TT(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			PushTextAttrs(P);
			Texts.SetFont(P.W, mono)
		ELSE
			PopTextAttrs(P)
		END
	END TT;

	PROCEDURE TAB(VAR S: Scanner; on: BOOLEAN);
		VAR
			P: Page;
			attr: ARRAY 64 OF CHAR;
			style: TextGadgets.Style;
	BEGIN
		P := S.page;
		IF on THEN
			Texts.Write(P.W, Strings.Tab);
			style := NIL;
			WHILE NextAttr(S, attr) DO
				IF attr = "ALIGN" THEN
					style := TextAlign(S.value)
				END
			END;
			IF style # NIL THEN
				PushTextAttrs(P);
				P.style := style; WriteObj(P, P.style)
			END
		ELSE
			PopTextAttrs(P)
		END;
		P.blank := FALSE
		(*S.skipWS := TRUE*)
	END TAB;

	PROCEDURE U(VAR S: Scanner; on: BOOLEAN);
		(* underline text, how ? *)
	BEGIN
		(* ignore *)
	END U;

	PROCEDURE UL(VAR S: Scanner; on: BOOLEAN);
	BEGIN
		IF on THEN
			OpenList(S.page, DefList)
		ELSE
			CloseList(S.page)
		END;
		(*S.skipWS := TRUE*)
	END UL;

	PROCEDURE VARN(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			PushTextAttrs(P);
			Texts.SetFont(P.W, ChangeFontAttr(P.W.lib(Fonts.Font), "i"))
		ELSE
			PopTextAttrs(P)
		END
	END VARN;

	PROCEDURE XMP(VAR S: Scanner; on: BOOLEAN);
		VAR P: Page;
	BEGIN
		P := S.page;
		IF on THEN
			PushTextAttrs(P);
			Texts.SetFont(P.W, mono);
			S.pre := TRUE
		ELSE
			PopTextAttrs(P); S.pre := FALSE
		END
	END XMP;

	PROCEDURE HandleTag(VAR S: Scanner);
		VAR
			Ss: Texts.Scanner;
			gen: ARRAY 64 OF CHAR;
			e: ExtTag;
			i: INTEGER;
			found, on: BOOLEAN;
			prev: CHAR;
	BEGIN
		WHILE ~S.end & (S.ch <= " ") DO
			Read(S)
		END;
		IF S.ch = "!" THEN
			prev := S.ch; Read(S);
			IF S.ch = "-" THEN
				prev := S.ch; Read(S);
				IF S.ch = "-" THEN
					WHILE ~S.end & ((S.ch # ">") OR ((prev # "-") & (prev # "!"))) DO
						IF S.ch > " " THEN
							prev := S.ch
						END;
						Read(S)
					END
				ELSE
					WHILE ~S.end & (S.ch # ">") DO
						Read(S)
					END
				END
			ELSE
				WHILE ~S.end & (S.ch # ">") DO
					Read(S)
				END
			END;
			Read(S)
		ELSIF ~Strings.IsAlpha(S.ch) & (S.ch # "/") THEN
			Texts.Write(S.page.W, "<")
		ELSE
			S.state := InTag; Next(S);
			IF S.class = OpenEndTag THEN
				on := FALSE; Next(S)
			ELSE
				on := TRUE
			END;
			IF S.class = Value THEN
				Strings.Upper(S.value, S.value); found := TRUE;
				CASE S.value[0] OF
					"A": IF S.value[1] = 0X THEN
								A(S, on)
							ELSIF (S.value = "ADDR") OR (S.value = "ADDRESS") THEN
								ADDRESS(S, on)
							ELSE
								found := FALSE
							END
					|"B": IF S.value[1] = 0X THEN
								B(S, on)
							ELSIF S.value = "BASE" THEN
								BASE(S, on)
							ELSIF S.value = "BASEFONT" THEN
								BASEFONT(S, on)
							ELSIF S.value = "BIG" THEN
								BIG(S, on)
							ELSIF S.value = "BLINK" THEN
								BLINK(S, on)
							ELSIF (S.value = "BQ") OR (S.value = "BLOCKQUOTE") THEN
								BLOCKQUOTE(S, on)
							ELSIF S.value = "BODY" THEN
								BODY(S, on)
							ELSIF S.value = "BR" THEN
								BR(S, on)
							ELSE
								found := FALSE
							END
					|"C": IF S.value = "CALL" THEN
								CALL(S, on)
							ELSIF S.value = "CENTER" THEN
								CENTER(S, on)
							ELSIF S.value = "CITE" THEN
								CITE(S, on)
							ELSIF S.value = "CODE" THEN
								CODEx(S, on)
							ELSE
								found := FALSE
							END
					|"D": IF S.value = "DD" THEN
								DD(S, on)
							ELSIF S.value = "DFN" THEN
								DFN(S, on)
							ELSIF S.value = "DIR" THEN
								DIR(S, on)
							ELSIF S.value = "DIV" THEN
								DIVI(S, on)
							ELSIF S.value = "DL" THEN
								DL(S, on)
							ELSIF S.value = "DT" THEN
								DT(S, on)
							ELSE
								found := FALSE
							END
					|"E": IF S.value = "EM" THEN
								EM(S, on)
							ELSE
								found := FALSE
							END
					|"F": IF S.value = "FRAME" THEN
								FRAME(S, on)
							ELSIF S.value = "FONT" THEN
								FONT(S, on)
							ELSE
								found := FALSE
							END
					|"G": IF S.value = "GREEN" THEN
								GREEN(S, on)
							ELSE
								found := FALSE
							END
					|"H": IF (S.value = "HEAD") OR (S.value = "HEADER") THEN
								HEAD(S, on)
							ELSIF S.value = "HP" THEN
								HP(S, on)
							ELSIF S.value = "HR" THEN
								HR(S, on)
							ELSIF S.value = "HTML" THEN
								HTML(S, on)
							ELSIF S.value = "HTTP" THEN
								HTTP(S, on)
							ELSIF Strings.IsDigit(S.value[1]) THEN
								H(S, on)
							ELSE
								found := FALSE
							END
					|"I": IF S.value[1] = 0X THEN
								I(S, on)
							ELSIF S.value = "ISINDEX" THEN
								ISINDEX(S, on)
							ELSE
								found := FALSE
							END
					|"K": IF S.value = "KBD" THEN
								KBD(S, on)
							ELSE
								found := FALSE
							END
					|"L": IF S.value = "LI" THEN
								LI(S, on)
							ELSIF S.value = "LINK" THEN
								LINK(S, on)
							ELSIF S.value = "LISTING" THEN
								LISTING(S, on)
							ELSE
								found := FALSE
							END
					|"M": IF S.value = "MENU" THEN
								MENU(S, on)
							ELSIF S.value = "META" THEN
								META(S, on)
							ELSE
								found := FALSE
							END
					|"N": IF S.value = "NEXTID" THEN
								NEXTID(S, on)
							ELSIF S.value = "NOFRAMES" THEN
								NOFRAMES(S, on)
							ELSE
								found := FALSE
							END
					|"O": IF S.value = "OL" THEN
								OL(S, on)
							ELSE
								found := FALSE
							END
					|"P": IF S.value[1] = 0X THEN
								P(S, on)
							ELSIF S.value = "PLAINTEXT" THEN
								PLAINTEXT(S, on)
							ELSIF S.value = "PRE" THEN
								PRE(S, on)
							ELSE
								found := FALSE
							END
					|"Q": IF S.value[1] = 0X THEN
								Q(S, on)
							ELSE
								found := FALSE
							END
					|"R": IF S.value = "RANGE" THEN
								RANGE(S, on)
							ELSE
								found := FALSE
							END
					|"S": IF S.value[1] = 0X THEN
								STRIKE(S, on)
							ELSIF S.value = "SAMP" THEN
								SAMP(S, on)
							ELSIF S.value = "STRIKE" THEN
								STRIKE(S, on)
							ELSIF S.value = "STRONG" THEN
								STRONG(S, on)
							ELSIF S.value = "STYLE" THEN
								STYLE(S, on)
							ELSIF S.value = "SMALL" THEN
								SMALL(S, on)
							ELSIF S.value = "SUB" THEN
								SUB(S, on)
							ELSIF S.value = "SUP" THEN
								SUP(S, on)
							ELSE
								found := FALSE
							END
					|"T": IF S.value = "TITLE" THEN
								TITLE(S, on)
							ELSIF S.value = "TT" THEN
								TT(S, on)
							ELSIF S.value = "TAB" THEN
								TAB(S, on)
							ELSIF S.value = "TINY" THEN
								TINY(S, on)
							ELSE
								found := FALSE
							END
					|"U": IF S.value[1] = 0X THEN
								U(S, on)
							ELSIF S.value = "UL" THEN
								UL(S, on)
							ELSE
								found := FALSE
							END
					|"V": IF S.value = "VAR" THEN
								VARN(S, on)
							ELSE
								found := FALSE
							END
					|"X": IF S.value = "XMP" THEN
								XMP(S, on)
							ELSE
								found := FALSE
							END
				ELSE
					found := FALSE
				END;
				IF ~found THEN
					e := extTags;
					WHILE (e # NIL) & (e.tag # S.value) DO
						e := e.next
					END;
					IF e = NIL THEN
						gen := "HTMLTags.";  Strings.Append(gen, S.value);
						Oberon.OpenScanner(Ss, gen);
						IF Ss.class IN {Texts.Name, Texts.String} THEN
							COPY(Ss.s, gen);
							newTag := NIL; Oberon.Call(gen, Oberon.Par, FALSE, i);
							IF i # 0 THEN
								Texts.WriteString(Wr, gen);
								Texts.WriteLn(Wr);
								Texts.Append(Oberon.Log, Wr.buf)
							END;
							IF newTag # NIL THEN
								e := newTag; COPY(S.value, e.tag);
								e.next := extTags; extTags := e;
								e.start(S.page)
							END
						END
					END;
					IF e # NIL THEN
						e.handle(S, on); found := TRUE
					END
				END;
				WHILE ~S.end & (S.class # CloseTag) DO
					Next(S)
				END;
				IF ~found THEN

				ELSE

				END
			END
		END;
		S.state := TextHtml
	END HandleTag;

	PROCEDURE *DocHandler(D: Objects.Object; VAR M: Objects.ObjMsg);
	BEGIN
		WITH D: Documents.Document DO
			IF M IS Objects.LinkMsg THEN
				WITH M: Objects.LinkMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "DeskMenu" THEN
							M.obj := Gadgets.CopyPublicObject("NetDocs.HTMLDeskMenu", TRUE);
							IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
							M.res := 0
						ELSIF M.name = "SystemMenu" THEN
							M.obj := Gadgets.CopyPublicObject("NetDocs.HTMLSystemMenu", TRUE);
							IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
							M.res := 0
						ELSIF M.name = "UserMenu" THEN
							M.obj := Gadgets.CopyPublicObject("NetDocs.HTMLUserMenu", TRUE);
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

	PROCEDURE TextColor(col: INTEGER): SHORTINT;
		VAR r, g, b: INTEGER;
	BEGIN
		Display.GetColor(col, r, g, b);
		IF (0.3*r+0.59*g+0.11*b) > 0.35 THEN
			RETURN SHORT(Display3.black)
		ELSE
			RETURN SHORT(Display3.white)
		END
	END TextColor;

	PROCEDURE EndPage(P: Page);
		VAR
			me: Oberon.Task;
			e: ExtTag;
			p: Page;
	BEGIN
		me := P.task; CloseA(P);
		e := extTags;
		WHILE e # NIL DO
			e.stop(P); e := e.next
		END;
		Texts.Append(P.T, P.W.buf);
		WITH me: Task DO
			IF me.S.S # NIL THEN
				me.S.S.Close(me.S.S); me.S.S := NIL
			END
		END;
		P.D.handle := DocHandler;
		Attributes.SetString(P.D, "Type", "HTML");
		Attributes.SetInt(P.D.dsc, "Color", P.textbackC);
		IF P.textbackC # Display3.textbackC THEN
			Texts.ChangeLooks(P.T, 0, P.headerLen, {1}, NIL, TextColor(P.textbackC), 0)
		END;
		IF (P.orgPos > 0) & (P.D.dsc(TextGadgets.Frame).org = 0) THEN
			HyperDocs.ScrollTo(P.D.dsc(TextGadgets.Frame), P.orgPos);
			IF HTTPDocs0.curNode # NIL THEN
				HyperDocs.RememberOrg(P.orgPos, HTTPDocs0.curNode, HTTPDocs0.curNode)
			END
		END;
		Texts.Append(P.source, P.Ws.buf);
		IF P.cacheSource THEN
			HyperDocs.CacheText(HTTPDocs0.StripLoc(P.docKey), P.source)
		END;
		Oberon.Remove(me); p := pages;
		WHILE (p # NIL) & (p.next # P) DO
			p := p.next
		END;
		IF p # NIL THEN
			p.next := P.next
		ELSE
			pages := P.next
		END;
		P.task := NIL; Oberon.Collect()
	END EndPage;

	PROCEDURE *ParseNext(me: Oberon.Task);
		VAR
			P: Page;
			St: Streams.Stream;
			i, minSize, timeOut: LONGINT;
			app: BOOLEAN;
	BEGIN
		WITH me: Task DO
			P := me.S.page;
			IF me.S.state # End THEN
				i := Input.Time();
				IF me.time = 0 THEN timeOut := i + 10*Input.TimeUnit ELSE timeOut := i + Input.TimeUnit END;
				me.time := i;
				St := me.S.S; app := FALSE;
				me.S.avail := St.Available(St); minSize := 64;
				IF (me.S.avail < minSize) & (me.S.avail > 0) THEN
					IF St.State(St) = Streams.closed THEN
						minSize := me.S.avail
					ELSIF ~St.buffer THEN
						minSize := 1
					END
				END;
				WHILE (me.S.avail >= minSize) & (me.time < timeOut) DO
					app := TRUE;
					CASE me.S.class OF
						WhiteSpace: WriteSpace(P)
						|OpenTag: HandleTag(me.S)
						|CharRef: WriteCharRef(P, me.S); P.lines := 0; P.blank := TRUE
						|Character: Texts.Write(P.W, me.S.char); P.lines := 0; P.blank := TRUE
					ELSE
					(* ??? *)
					END;
					Next(me.S);
					IF me.S.avail <= minSize THEN
						me.S.avail := St.Available(St); me.time := Input.Time()
					END;
					IF (me.S.avail < minSize) & (me.S.avail > 0) THEN
						IF St.State(St) = Streams.closed THEN
							minSize := me.S.avail
						ELSIF ~St.buffer THEN
							minSize := 1
						END
					END
				END;
				me.time := Input.Time(); i := 0;
				WHILE St.eos & (me.S.state # End) & (i < 5) DO (* :-) *)
					app := TRUE;
					CASE me.S.class OF
						WhiteSpace: WriteSpace(P)
						|OpenTag: HandleTag(me.S)
						|CharRef: WriteCharRef(P, me.S); P.lines := 0; P.blank := TRUE
						|Character: Texts.Write(P.W, me.S.char); P.lines := 0; P.blank := TRUE
					ELSE
					(* ??? *)
					END;
					Next(me.S); INC(i)
				END;
				me.S.avail := 0;
				IF app THEN
					Texts.Append(P.T, P.W.buf); INC(me.time, Input.TimeUnit DIV 5)
				ELSE
					INC(me.time, Input.TimeUnit)
				END
			END;
			IF me.S.state = End THEN
				EndPage(P)
			END
		END
	END ParseNext;

(* Query a string setting in the NetSystem section in Registry. *)
	PROCEDURE QueryString(key: ARRAY OF CHAR; VAR s: ARRAY OF CHAR): BOOLEAN;
	VAR lKey: ARRAY 32 OF CHAR;  S: Texts.Scanner;
	BEGIN
		lKey := "NetSystem."; Strings.Append(lKey, key);
		Oberon.OpenScanner(S, lKey);
		IF S.class IN {Texts.Name, Texts.String} THEN
			COPY(S.s, s)
		ELSE
			COPY("", s)
		END;
		RETURN s # ""
	END QueryString;

	PROCEDURE QueryBool(key: ARRAY OF CHAR): BOOLEAN;
		VAR
			str: ARRAY 16 OF CHAR;
			b: BOOLEAN;
	BEGIN
		IF QueryString(key, str) THEN
			Strings.StrToBool(str, b);
			RETURN b
		ELSE
			RETURN FALSE
		END
	END QueryBool;

	PROCEDURE Parse*(D: Documents.Document; basekey: LONGINT; S: Streams.Stream; head, cache, blocking: BOOLEAN);
		VAR
			me: Task;
			s: HyperDocs.LinkScheme;
			e: ExtTag;
			i, j: LONGINT;
	BEGIN
		imgs := QueryBool("HTMLImages");
		NEW(me);
		IF (D.handle = NIL) OR (D.Store = NIL) THEN
			TextDocs.InitDoc(D); D.W := HyperDocs.docW; D.H := HyperDocs.docH
		END;
		D.dsc(TextGadgets.Frame).do := HyperDocs.linkMethods;
		NEW(me.P); me.P.D := D; NEW(me.P.T); Texts.Open(me.P.T, ""); me.P.alink := NIL; me.P.clink := NIL;
		me.P.cacheSource := cache; NEW(me.P.source); Texts.Open(me.P.source, ""); Texts.OpenWriter(me.P.Ws);
		me.P.next := pages; pages := me.P; me.P.task := me; me.P.docKey := basekey;
		me.P.handle := Gadgets.objecthandle; me.P.blank := FALSE;
		Links.SetLink(D.dsc, "Model", me.P.T); me.P.lines := 0; me.P.linkkey := HyperDocs.UndefKey;
		me.P.textAttrs := NIL; Texts.OpenWriter(me.P.W); me.P.left := FALSE;
		me.P.linkC := HyperDocs.linkC; me.P.oldLinkC := HyperDocs.oldLinkC; 
		me.P.textC := Display3.textC; me.P.textbackC := Display3.textbackC;
		Attributes.SetInt(me.P.D.dsc, "LinkColor", me.P.linkC);
		Attributes.SetInt(me.P.D.dsc, "OldLinkColor", me.P.oldLinkC);
		me.S.page := me.P; me.P.lists := NIL;
		NEW(me.P.base); me.P.base.key := basekey; me.P.base.dockey := me.P.base.key;
		me.P.style := TextGadgets.newStyle(); InitTabs(me.P.style); me.P.style.mode := DefStyle;
		WriteObj(me.P, me.P.style); PopTextAttrs(me.P); me.P.orgPos := 0; me.P.head := head;
		OpenScanner(me.S, S);
		IF head THEN
			Texts.WriteString(me.P.W, "URL: "); Texts.Write(me.P.W, 22X)
		END;
		s := HyperDocs.LinkSchemeByKey(me.P.base.key);
		IF s = NIL THEN
			s := HyperDocs.LinkSchemeByPrefix("file")
		END;
		COPY(s.prefix, me.P.base.prefix);
		HyperDocs.RetrieveLink(me.P.base.key, me.S.value);
		IF me.P.base.prefix = "http" THEN
			me.P.base.key := HTTPDocs0.SplitHTTPAdr(me.S.value, me.P.base.host, me.P.base.path, me.P.orgLabel, me.P.base.port);
			i := 0;
			WHILE me.S.value[i] # 0X DO
				INC(i)
			END;
			WHILE (i > 0) & (me.S.value[i] # "/") DO
				DEC(i)
			END;
			IF me.S.value[i] = "/" THEN
				me.S.value[i+1] := 0X
			END
		ELSIF me.P.base.prefix = "file" THEN
			HyperDocs.RetrieveLink(HyperDocs.loadingKey, me.S.value);
			i := HyperDocs.SplitFileAdr(me.S.value, me.P.base.path, me.P.orgLabel);
			HyperDocs.RetrieveLink(me.P.base.key, me.S.value);
			me.P.base.key := HyperDocs.SplitFileAdr(me.S.value, me.P.base.path, searchAttr);
			me.P.base.host := ""; me.P.base.port := 0;
			i := 0; j := 0;
			WHILE me.P.base.path[i] # 0X DO
				IF me.P.base.path[i] = "/" THEN j := i+1 END;
				INC(i)
			END;
			me.P.base.path[j] := 0X
		ELSE (* proxy *)
			me.P.orgLabel := "";
			SplitHostPort(me.S.value, me.P.base.host, me.P.base.port);
			IF me.P.base.prefix = "ftp" THEN
				i := 6;
				WHILE (me.S.value[i] # 0X) & (me.S.value[i] # "/") DO
					INC(i)
				END;
				j := 0;
				WHILE me.S.value[i] # 0X DO
					me.P.base.path[j] := me.S.value[i]; INC(j); INC(i)
				END;
				IF j > 0 THEN
					me.P.base.path[j] := 0X
				ELSE
					me.P.base.path := "/"
				END
			ELSE
				me.P.base.path := ""
			END
		END;
		HyperDocs.RetrieveLink(me.P.base.key, me.S.value);
		IF head THEN
			Texts.WriteString(me.P.W, me.S.value);
			Texts.Write(me.P.W, 22X); WriteLn(me.P)
		END;
		e := extTags;
		WHILE e # NIL DO
			e.start(me.P); e := e.next
		END;
		me.P.D.handle := DocHandler;
		Attributes.SetString(me.P.D, "Type", "HTML");
		Attributes.SetInt(me.P.D.dsc, "Color", me.P.textbackC);
		Texts.Append(me.P.T, me.P.W.buf); Read(me.S); Next(me.S);
		me.P.headerLen := me.P.T.len;
		me.time := 0; me.safe := FALSE; me.handle := ParseNext; Oberon.Install(me);
		IF blocking THEN
			WHILE me.P.task = me DO
				me.handle(me)
			END
		END
	END Parse;

	PROCEDURE Show*;
		VAR
			T: Texts.Text;
			D: Objects.Object;
	BEGIN
		T := Oberon.MarkedText();
		IF T # NIL THEN
			HTTPDocs0.curNode := NIL;
			D := Gadgets.CreateObject("TextDocs.NewDoc");
			WITH D: Documents.Document DO
				D.W := HyperDocs.docW; D.H := HyperDocs.docH;
				D.handle := DocHandler;
				Parse(D, HyperDocs.UndefKey, TextStreams.OpenReader(T, 0), TRUE, FALSE, TRUE);
				Desktops.ShowDoc(D)
			END
		END
	END Show;

(** HTMLDocs.Stop *
	Stop all background task for the marked html document. *)
	PROCEDURE Stop*;
		VAR
			S: Attributes.Scanner;
			doc: Documents.Document;
			P, nextP: Page;
	BEGIN
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Attributes.Scan(S);
		IF (S.class = Attributes.Char) & (S.c = "*") THEN
			doc := Desktops.CurDoc(Gadgets.context)
		ELSE
			doc := NIL; P := NIL
		END;
		IF doc # NIL THEN
			HTTPDocs0.StopDoc(doc);
			P := pages;
			WHILE (P # NIL) & (P.D # doc) DO
				P := P.next
			END;
			IF P # NIL THEN
				HTTPDocs0.StopDoc(P.D); EndPage(P)
			END
		ELSE
			P := pages;
			WHILE P # NIL DO
				nextP := P.next;
				HTTPDocs0.StopDoc(P.D); EndPage(P);
				P := nextP
			END
		END
	END Stop;

	PROCEDURE *LoadDoc(D: Documents.Document);
		VAR
			key: LONGINT;
			s, so: HyperDocs.LinkScheme;
			T: Texts.Text;
			path, label: ARRAY 64 OF CHAR;
	BEGIN
		key := HyperDocs.BuildKey(NIL, D.name);
		IF key # HyperDocs.UndefKey THEN
			s := HyperDocs.LinkSchemeByKey(key);
			IF s.prefix = "file" THEN
				IF HyperDocs.context # NIL THEN
					HTTPDocs0.curNode := HyperDocs.context.new
				ELSE
					HyperDocs.Remember(key, NIL, HTTPDocs0.curNode)
				END;
				key := HyperDocs.SplitFileAdr(D.name, path, label);
				NEW(T); Texts.Open(T, path);
				TextDocs.InitDoc(D); D.W := HyperDocs.docW; D.H := HyperDocs.docH;
				Parse(D, key, TextStreams.OpenReader(T, 0), TRUE, FALSE, FALSE);
				IF (D # NIL) & (D.dsc # NIL) THEN
					IF HyperDocs.context = NIL THEN
						HyperDocs.LinkNodeToDoc(D, HTTPDocs0.curNode)
					ELSE
						HyperDocs.context.history := TRUE
					END;
					IF D.name = "" THEN
						HyperDocs.RetrieveLink(key, D.name)
					END
				END
			ELSE
HALT(99)
			END;
			IF (HyperDocs.context # NIL) & (HyperDocs.context.old # NIL) THEN
				so := HyperDocs.LinkSchemeByKey(HyperDocs.context.old.key);
				IF (so.prefix = "file") OR (so.prefix = "http") THEN
					HyperDocs.context.replace := TRUE
				END
			END
		END
	END LoadDoc;

	PROCEDURE NewDoc*;
		VAR doc: Objects.Object;
	BEGIN
		doc := Gadgets.CreateObject("TextDocs.NewDoc");
		WITH doc: Documents.Document DO
			doc.W := HyperDocs.docW; doc.H := HyperDocs.docH;
			doc.Load := LoadDoc
		END;
		doc.handle := DocHandler;
		Objects.NewObj := doc
	END NewDoc;

	PROCEDURE InitEntities();
	BEGIN
		entityEncoding := "AAAAAAÄCDEEEEIIIINOOOOOÖPUUUÜYáâaà&aaäçéêèdë>iîìï<ñoôòooö ßpuûùüyy";
		entityEncoding[57] := 22X;
		entityEncoding[66] := 22X;
		entityEncoding[67] := Strings.Tab;
		entityEncoding[68] := " ";
		entities[0] := "AElig";
		entities[1] := "Aacute";
		entities[2] := "Acirc";
		entities[3] := "Agrave";
		entities[4] := "Aring";
		entities[5] := "Atilde";
		entities[6] := "Auml";
		entities[7] := "Ccedil";
		entities[8] := "ETH";
		entities[9] := "Eacute";
		entities[10] := "Ecirc";
		entities[11] := "Egrave";
		entities[12] := "Euml";
		entities[13] := "Iacute";
		entities[14] := "Icirc";
		entities[15] := "Igrave";
		entities[16] := "Iuml";
		entities[17] := "Ntilde";
		entities[18] := "Oacute";
		entities[19] := "Ocirc";
		entities[20] := "Ograve";
		entities[21] := "Oslash";
		entities[22] := "Otilde";
		entities[23] := "Ouml";
		entities[24] := "THORN";
		entities[25] := "Uacute";
		entities[26] := "Ucirc";
		entities[27] := "Ugrave";
		entities[28] := "Uuml";
		entities[29] := "Yacute";
		entities[30] := "aacute";
		entities[31] := "acirc";
		entities[32] := "aelig";
		entities[33] := "agrave";
		entities[34] := "amp";
		entities[35] := "aring";
		entities[36] := "atilde";
		entities[37] := "auml";
		entities[38] := "ccedil";
		entities[39] := "eacute";
		entities[40] := "ecirc";
		entities[41] := "egrave";
		entities[42] := "eth";
		entities[43] := "euml";
		entities[44] := "gt";
		entities[45] := "iacute";
		entities[46] := "icirc";
		entities[47] := "igrave";
		entities[48] := "iuml";
		entities[49] := "lt";
		entities[50] := "ntilde";
		entities[51] := "oacute";
		entities[52] := "ocirc";
		entities[53] := "ograve";
		entities[54] := "oslash";
		entities[55] := "otilde";
		entities[56] := "ouml";
		entities[57] := "quot";
		entities[58] := "szlig";
		entities[59] := "thorn";
		entities[60] := "uacute";
		entities[61] := "ucirc";
		entities[62] := "ugrave";
		entities[63] := "uuml";
		entities[64] := "yacute";
		entities[65] := "yuml";
		entities[66] := "quote";
		entities[67] := "tab";
		entities[68] := "nbsp"
	END InitEntities;

(** HTMLDocs.ShowHTML
		Display the HTML-source of the marked page. *)
PROCEDURE ShowHTML*;
	VAR
		D: Documents.Document;
		node: HyperDocs.Node;
		P: Page;
		key, pos: LONGINT;
		T: Texts.Text;
		R: Texts.Reader;
		ch: CHAR;
BEGIN
	D := Documents.MarkedDoc();
	node := HyperDocs.NodeByDoc(D);
	IF node # NIL THEN
		Attributes.GetInt(D, "DocURL", key);
		P := pages;
		WHILE (P # NIL) & (P.docKey # key) DO
			P := P.next
		END;
		IF P # NIL THEN
			Texts.Append(P.source, P.Ws.buf); T := P.source
		ELSE
			key := HTTPDocs0.StripLoc(key);
			T := HyperDocs.GetCachedText(key)
		END;
		IF T # NIL THEN
			Texts.OpenReader(R, T, 0);
			Texts.Read(R, ch); pos := 0;
			WHILE ~R.eot DO
				IF ch = Strings.LF THEN
					Texts.WriteLn(Wr);
					Texts.Delete(T, pos, pos+1);
					Texts.Insert(T, pos, Wr.buf);
					Texts.OpenReader(R, T, pos)
				ELSE
					INC(pos)
				END;
				Texts.Read(R, ch)
			END;
			TextDocs.ShowText("HTML", T, HyperDocs.docW, HyperDocs.docH)
		END
	END
END ShowHTML;

(** HTMLDocs.SetImages
	Switch image loading on or off. *)
PROCEDURE SetImages*;
	VAR
		S: Attributes.Scanner;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Attributes.Scan(S);
	IF (S.class = Attributes.Name) OR (S.class = Attributes.String) THEN
		Strings.StrToBool(S.s, imgs)
	END;
END SetImages;

PROCEDURE Check();
VAR S: Texts.Scanner;
BEGIN
	Oberon.OpenScanner(S, "HTMLTags");
	IF S.class = Texts.Inval THEN
		Texts.WriteString(Wr, "Oberon.Text - HTMLTags not found");
		Texts.WriteLn(Wr);  Texts.Append(Oberon.Log, Wr.buf)
	END
END Check;

BEGIN
	COPY(GreekCap, GreekTab);
	Strings.Append(GreekTab, GreekMin);
	InitEntities(); mono := Fonts.This("Courier10.Scn.Fnt");
	bullets[0].f := Fonts.This("Default10.Scn.Fnt"); bullets[0].c := CHR(29);
	bullets[1].f := bullets[0].f; bullets[1].c := CHR(28);
	Texts.OpenWriter(Wr); Texts.OpenWriter(Wq);
	imgs := TRUE; extTags := NIL; newTag := NIL;
	pages := NIL; dispW := Display.Width;
	Check()
END HTMLDocs.
