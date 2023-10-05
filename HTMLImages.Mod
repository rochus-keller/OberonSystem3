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

MODULE HTMLImages;	(** portable *)
	IMPORT Objects, Strings, HyperDocs, Display, Texts, Display3, Oberon, Gadgets, Effects, Links, Rembrandt, HTTPDocs0,
		HTMLDocs, Documents, Desktops, Attributes, Files, Pictures, Fonts;

	CONST
		middle = 1;

	TYPE
		Area = POINTER TO AreaDesc;
		AreaDesc = RECORD
			key: LONGINT;
			x, y: INTEGER;
			next: Area
		END;
		Map = POINTER TO MapDesc;
		MapDesc = RECORD (Gadgets.ObjDesc)
			name: ARRAY 64 OF CHAR;
			areas: Area;
			next: Map
		END;
		RectArea = POINTER TO RectAreaDesc;
		RectAreaDesc = RECORD (AreaDesc)
			x2, y2: INTEGER
		END;
		Icon = POINTER TO IconDesc;
		IconDesc = RECORD (Rembrandt.FrameDesc)
			entry: HTTPDocs0.Entry
		END;

	VAR
		maps: Map;

	PROCEDURE HandleMap(obj: Objects.Object; VAR M: Objects.ObjMsg);
	BEGIN
		WITH obj: Map DO
			IF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "Gen" THEN
							M.class := Objects.String;
							M.s := "HTMLImages.NewMap";
							M.res := 0
						ELSIF M.name = "MapName" THEN
							M.class := Objects.String;
							COPY(obj.name, M.s);
							M.res := 0
						ELSE
							Gadgets.objecthandle(obj, M)
						END
					ELSIF M.id = Objects.enum THEN
						Gadgets.objecthandle(obj, M);
						M.Enum("MapName"); M.res := 0
					ELSE
						Gadgets.objecthandle(obj, M)
					END
				END
			ELSIF M IS Objects.FileMsg THEN
				WITH M: Objects.FileMsg DO
					Gadgets.objecthandle(obj, M);

				END
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
Gadgets.objecthandle(obj, M);

				END
			ELSE
				Gadgets.objecthandle(obj, M)
			END
		END
	END HandleMap;

	PROCEDURE *InitMap(map: Map);
	BEGIN
		map.handle := HandleMap;
		map.name := "";
		map.next := NIL;
		map.areas := NIL
	END InitMap;

	PROCEDURE NewMap*;
		VAR m: Map;
	BEGIN
		NEW(m);
		InitMap(m);
		Objects.NewObj := m
	END NewMap;

	PROCEDURE *MAP(VAR S: HTMLDocs.Scanner; on: BOOLEAN);
		VAR
			P: HTMLDocs.Page;
			attr: ARRAY 64 OF CHAR;
			map, m: Map;
	BEGIN
		P := S.page;
		IF on THEN
			map := NIL;
			WHILE HTMLDocs.NextAttr(S, attr) DO
				IF attr = "NAME" THEN
					NEW(map); InitMap(map);
					COPY(S.value, map.name);
					m := maps;
					WHILE (m # NIL) & (m.name # map.name) DO
						m := m.next
					END;
					IF m = NIL THEN
						map.next := maps; maps := map
					ELSE
						map := m; map.areas := NIL
					END
				END
			END;
			Links.SetLink(P, "CurMap", map)
		ELSE
			Links.SetLink(P, "CurMap", NIL)
		END;
	END MAP;

	PROCEDURE *InitMaps(P: HTMLDocs.Page);
	BEGIN
		Links.SetLink(P, "CurMap", NIL)
	END InitMaps;

	PROCEDURE *AREA(VAR S: HTMLDocs.Scanner; on: BOOLEAN);
		VAR
			attr: ARRAY 64 OF CHAR;
			area: Area;
			rarea: RectArea;
			val: LONGINT;
			obj: Objects.Object;
			curMap: Map;
			pos: INTEGER;
	BEGIN
		IF on THEN
			Links.GetLink(S.page, "CurMap", obj);
			IF (obj # NIL) & (obj IS Map) THEN
				curMap := obj(Map);
				area := NIL;
				WHILE HTMLDocs.NextAttr(S, attr) DO
					IF attr = "SHAPE" THEN
						Strings.Upper(S.value, S.value);
						IF S.value = "RECT" THEN
							NEW(rarea); area := rarea
						ELSIF S.value = "DEFAULT" THEN
							NEW(area)
						ELSE
							Texts.WriteString(HTMLDocs.Wr, "AREA "); Texts.WriteString(HTMLDocs.Wr, S.value);
							Texts.WriteString(HTMLDocs.Wr, " not implemented"); Texts.WriteLn(HTMLDocs.Wr);
							Texts.Append(Oberon.Log, HTMLDocs.Wr.buf)
						END
					ELSIF area # NIL THEN
						IF attr = "COORDS" THEN
							pos := 0; Strings.StrToIntPos(S.value, val, pos);
							area.x := SHORT(val);
							INC(pos); Strings.StrToIntPos(S.value, val, pos);
							area.y := SHORT(val);
							IF area IS RectArea THEN
								WITH area: RectArea DO
									INC(pos); Strings.StrToIntPos(S.value, val, pos);
									area.x2 := SHORT(val);
									INC(pos); Strings.StrToIntPos(S.value, val, pos);
									area.y2 := SHORT(val)
								END
							END
						ELSIF attr = "HREF" THEN
							area.key := HyperDocs.BuildKey(S.page.base, S.value)
						END
					END
				END;
				IF area # NIL THEN
					area.next := curMap.areas; curMap.areas := area
				END
			ELSE
				Texts.WriteString(HTMLDocs.Wr, "not within a map");
				Texts.WriteLn(HTMLDocs.Wr); Texts.Append(Oberon.Log, HTMLDocs.Wr.buf)
			END
		END
	END AREA;

(** HTMLDocs.LoadIMG
		Load the image linked to the icon. *)
	PROCEDURE LoadIMG*;
		VAR
			pos: LONGINT;
			F: Texts.Finder;
			obj, icon: Objects.Object;
			key: LONGINT;
			text: Texts.Text;
			node: HyperDocs.Node;
			doc: Documents.Document;
	BEGIN
		icon := Gadgets.executorObj;
		text := HTMLDocs.GetText(Gadgets.context);
		node := HyperDocs.NodeByDoc(Desktops.CurDoc(Gadgets.context));
		Texts.OpenFinder(F, text, 0);
		pos := F.pos; Texts.FindObj(F, obj);
		WHILE ~F.eot DO
			IF obj = icon THEN
				Attributes.GetInt(obj, "IMGKey", key);
				IF key # HyperDocs.UndefKey THEN
					WITH icon: Icon DO
						icon.entry.basekey := node.key; icon.entry.obj := icon;
						icon.entry.text := text; icon.entry.pos := pos; icon.entry.key := key;
						NEW(doc);
						HyperDocs.DocNameByKey(doc.name, key);
						doc.handle := NIL; doc.dsc := NIL;
						HTTPDocs0.RequestDoc(doc, HTTPDocs0.httpProxy, key, "GET", FALSE, icon.entry, NIL)
					END
				ELSE
					Attributes.GetInt(obj, "OBJKey", key);
HALT(99)
				END;
				RETURN
			END;
			pos := F.pos; Texts.FindObj(F, obj)
		END
	END LoadIMG;

(** HTMLDocs.LoadAllIcons
		Load all images and object linked to icons in the marked page. *)
	PROCEDURE LoadAllIcons*;
		VAR
			T: Texts.Text;
			F: Texts.Finder;
			pos: LONGINT;
			obj: Objects.Object;
			key: LONGINT;
			doc: Documents.Document;
			node: HyperDocs.Node;
	BEGIN
		doc := Documents.MarkedDoc();
		node := HyperDocs.NodeByDoc(doc);
		T := Oberon.MarkedText();
		IF T # NIL THEN
			Texts.OpenFinder(F, T, 0);
			pos := F.pos; Texts.FindObj(F, obj);
			WHILE ~F.eot DO
				IF obj IS Icon THEN
					IF Attributes.FindAttr("IMGKey", obj(Gadgets.Frame).attr) # NIL THEN
						Attributes.GetInt(obj, "IMGKey", key);
						IF key # HyperDocs.UndefKey THEN
							WITH obj: Icon DO
								obj.entry.basekey := node.key; obj.entry.obj := obj;
								obj.entry.text := T; obj.entry.pos := pos; obj.entry.key := key;
								NEW(doc);
								HyperDocs.DocNameByKey(doc.name, key);
								doc.handle := NIL; doc.dsc := NIL;
								HTTPDocs0.RequestDoc(doc, HTTPDocs0.httpProxy, key, "GET", FALSE, obj.entry, NIL)
							END
						END
					ELSIF Attributes.FindAttr("OBJKey", obj(Gadgets.Frame).attr) # NIL THEN
						Attributes.GetInt(obj, "OBJKey", key);
						IF key # HyperDocs.UndefKey THEN
HALT(99)
						END
					ELSE
						HALT(99)
					END
				END;
				pos := F.pos; Texts.FindObj(F, obj)
			END
		END
	END LoadAllIcons;

	PROCEDURE CopyIcon(VAR C: Objects.CopyMsg; F, F1: Icon);
	BEGIN
		Rembrandt.Copy(C, F, F1);
		F1.entry := F.entry
	END CopyIcon;

	PROCEDURE StoreEntry(F: Icon; VAR R: Files.Rider; entry: HTTPDocs0.Entry);
		VAR
			Fi: Texts.Finder;
			obj: Objects.Object;
			elem: HTTPDocs0.ObjList;
	BEGIN
		IF entry # NIL THEN
			Files.WriteBool(R, FALSE);
			Attributes.StoreAttributes(R, entry.attrs);
			Gadgets.WriteRef(R, F.lib, entry.text);
			Files.WriteLInt(R, entry.pos);
			IF (entry.text # NIL) & (entry.ol # NIL) THEN
				Texts.OpenFinder(Fi, entry.text, 0);
				Texts.FindObj(Fi, obj);
				WHILE ~Fi.eot DO
					IF obj IS HTMLDocs.Form THEN
						elem := obj(HTMLDocs.Form).elems;
						WHILE elem # NIL DO
							IF elem = entry.ol THEN
								Gadgets.WriteRef(R, F.lib, obj);
								RETURN
							END;
							elem := elem.next
						END
					END;
					Texts.FindObj(Fi, obj)
				END
			END;
			Gadgets.WriteRef(R, F.lib, NIL)
		ELSE
			Files.WriteBool(R, TRUE)
		END
	END StoreEntry;

	PROCEDURE LoadEntry(F: Icon; VAR R: Files.Rider; VAR entry: HTTPDocs0.Entry);
		VAR
			nil: BOOLEAN;
			obj, form: Objects.Object;
			elem: HTTPDocs0.ObjList;
	BEGIN
		Files.ReadBool(R, nil);
		IF ~nil THEN
			NEW(entry);
			Attributes.LoadAttributes(R, entry.attrs);
			Gadgets.ReadRef(R, F.lib, obj);
			IF (obj # NIL) & (obj IS Texts.Text) THEN
				entry.text := obj(Texts.Text)
			ELSE
				entry.text := NIL
			END;
			Files.ReadLInt(R, entry.pos);
			Gadgets.ReadRef(R, F.lib, form);
			IF form # NIL THEN
				elem := form(HTMLDocs.Form).elems;
				WHILE elem # NIL DO
					IF elem.obj = F THEN
						entry.ol := elem;
						RETURN
					END;
					elem := elem.next
				END
			ELSE
				entry.ol := NIL
			END
		ELSE
			entry := NIL
		END
	END LoadEntry;

	PROCEDURE *IconHandler(F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			F1: Icon;
			key: LONGINT;
	BEGIN
		WITH F: Icon DO
			IF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "Gen" THEN
							M.class := Objects.String;
							M.s := "HTMLImages.NewIcon";
							M.res := 0
						ELSE
							Rembrandt.Handle(F, M)
						END
					ELSE
						Rembrandt.Handle(F, M)
					END
				END
			ELSIF M IS Objects.FileMsg THEN
				WITH M: Objects.FileMsg DO
					Rembrandt.Handle(F, M);
					IF M.id = Objects.store THEN
						Attributes.GetInt(F, "IMGKey", key);
						HyperDocs.StoreLink(M.R, key);
						Attributes.GetInt(F, "OBJKey", key);
						HyperDocs.StoreLink(M.R, key);
						StoreEntry(F, M.R, F.entry)
					ELSIF M.id = Objects.load THEN
						HyperDocs.LoadLink(M.R, key);
						Attributes.SetInt(F, "IMGKey", key);
						HyperDocs.LoadLink(M.R, key);
						Attributes.SetInt(F, "OBJKey", key);
						LoadEntry(F, M.R, F.entry)
					END
				END
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					IF M.stamp = F.stamp THEN
						M.obj := F.dlink
					ELSE
						NEW(F1);
						F.stamp := M.stamp;
						F.dlink := F1;
						CopyIcon(M, F, F1);
						M.obj := F1
					END
				END
			ELSE
				Rembrandt.Handle(F, M)
			END
		END
	END IconHandler;

	PROCEDURE NewIcon*;
		VAR icon: Icon;
	BEGIN
		NEW(icon);
		icon.entry := NIL;
		icon.handle := IconHandler;
		Objects.NewObj := icon
	END NewIcon;

	PROCEDURE LocalName(VAR url, name: ARRAY OF CHAR);
		VAR i, j: LONGINT;
	BEGIN
		i := 0; j := 0;
		WHILE url[i] # 0X DO
			name[j] := url[i]; INC(j);
			IF url[i] = "/" THEN
				j := 0
			END;
			INC(i)
		END;
		name[j] := 0X
	END LocalName;

	PROCEDURE FetchObj(P: HTMLDocs.Page; VAR S: HTMLDocs.Scanner): Objects.Object;
		VAR
			objname, libname: ARRAY 64 OF CHAR;
			s: HyperDocs.LinkScheme;
			key: LONGINT;
			obj: Objects.Object;
			C: Objects.CopyMsg;
			lib: Objects.Library;
			F: Files.File;
			M: HyperDocs.FetchMsg;
	BEGIN
		Strings.GetSuffix(S.value, objname); Strings.ChangeSuffix(S.value, "Lib");
		key := HyperDocs.BuildKey(P.base, S.value);
		s := HyperDocs.LinkSchemeByKey(key);
		IF s # NIL THEN
			LocalName(S.value, libname);
			lib := Objects.ThisLibrary(libname);
			IF lib.maxref <= 0 THEN
				Objects.FreeLibrary(libname);
				IF s.prefix # "file" THEN
					F := Files.New(libname); Files.Set(M.R, F, 0);
					M.key := key; M.res := -1;
					s.handle(s, M);
					IF M.res = 0 THEN
						Files.Register(F)
					END
				END
			END;
			Strings.ChangeSuffix(libname, objname);
			obj := Gadgets.FindPublicObj(libname);
			IF obj # NIL THEN
				C.id := Objects.deep; C.obj := NIL; C.dlink := NIL;
				Objects.Stamp(C); obj.handle(obj, C);
				obj := C.obj
			END;
			RETURN obj
		ELSE
			RETURN NIL
		END
	END FetchObj;

	PROCEDURE IMG(VAR S: HTMLDocs.Scanner; on: BOOLEAN);
		(* HTML 2.0: Level 0 *)
		(* BORDER: Netscape Navigator extension *)
		(* OBJECT: ejz *)
		VAR
			P: HTMLDocs.Page;
			attr, mapname: ARRAY 64 OF CHAR;
			alt: ARRAY 512 OF CHAR;
			okey, ikey, l: LONGINT;
			doc: Documents.Document;
			ismap: BOOLEAN;
			obj: Objects.Object;
			form: HTMLDocs.Form;
			border: INTEGER;
			E: HTTPDocs0.Entry;
			sattr: Attributes.StringAttr;
			battr: Attributes.BoolAttr;
			w, h, x, i, dsr: INTEGER;
			icon: Display.Frame;
			iCon: Icon;
			C: Objects.CopyMsg;
			locked: BOOLEAN;
		PROCEDURE ImgIcon(keyAttr: ARRAY OF CHAR; key: LONGINT);
		BEGIN
			doc := NIL;
			obj := Gadgets.FindPublicObj("Icons.Picture");
			Links.GetLink(obj, "Model", obj);
			C.id := Objects.shallow; Objects.Stamp(C);
			C.dlink := NIL; C.obj := NIL; obj.handle(obj, C);					
			NEW(iCon); E.obj := iCon; iCon.entry := E;
			Rembrandt.NewP(iCon, C.obj(Pictures.Picture));
			icon := iCon; icon.handle := IconHandler;
			Attributes.SetInt(icon, keyAttr, key);
			Attributes.SetString(icon, "Cmd", "HTMLImages.LoadIMG")
		END ImgIcon;
	BEGIN
		P := S.page; P.left := FALSE;
		IF on THEN
		alt := ""; border := 0; mapname := ""; ismap := FALSE;
		doc := NIL; obj := NIL; w := 0; h := 0; icon := NIL; locked := TRUE;
		NEW(E); ikey := HyperDocs.UndefKey; okey := HyperDocs.UndefKey;
		WHILE HTMLDocs.NextAttr(S, attr) DO
			IF (attr = "SRC") & (doc = NIL) & (icon = NIL) THEN
				ikey := HyperDocs.BuildKey(P.base, S.value);
				Texts.Append(P.T, P.W.buf); locked := TRUE;
				E.basekey := P.base.dockey; E.ol := NIL; E.attrs := NIL;
				E.text := P.T; E.pos := P.T.len; E.key := HyperDocs.UndefKey;
				(*IF HTMLDocs.imgs THEN
					NEW(doc);
					HyperDocs.DocNameByKey(doc.name, ikey);
					doc.handle := NIL; doc.dsc := NIL;
					HTTPDocs0.RequestDoc(doc, HTTPDocs0.httpProxy, ikey, "GET", FALSE, E, NIL);
					doc := NIL
				END;
				IF ~HTMLDocs.imgs OR (doc = NIL) THEN
					ImgIcon("IMGKey", ikey); Attributes.SetInt(icon, "OBJKey", HyperDocs.UndefKey)
				END*)
			ELSIF attr = "OBJECT" THEN
				IF HTMLDocs.imgs THEN
					NEW(doc); doc.handle := NIL;
					obj := FetchObj(P, S); locked := FALSE;
					IF (obj # NIL) & (obj IS Display.Frame) THEN
						doc.dsc := obj(Display.Frame)
					ELSE
						doc.dsc := NIL
					END
				END;
				IF ~HTMLDocs.imgs OR (doc = NIL) THEN
					okey := HyperDocs.BuildKey(P.base, S.value);
					ImgIcon("OBJKey", okey); Attributes.SetInt(icon, "IMGKey", HyperDocs.UndefKey)
				END
			ELSIF attr = "ALIGN" THEN
				P.left := Strings.CAPPrefix("L", S.value)
			ELSIF attr = "WIDTH" THEN
				Strings.StrToInt(S.value, l); w := SHORT(l)
			ELSIF attr = "HEIGHT" THEN
				Strings.StrToInt(S.value, l); h := SHORT(l)
			ELSIF attr = "ISMAP" THEN
				ismap := TRUE;
				IF S.value # "" THEN
					COPY(S.value, mapname)
				END
			ELSIF (attr = "ALT") & (S.value # "") THEN
				COPY(S.value, alt)
			ELSIF attr = "BORDER" THEN
				IF S.value # "" THEN
					Strings.StrToInt(S.value, l); border := SHORT(l)
				ELSE
					border := 1
				END
			ELSIF attr = "USEMAP" THEN
				NEW(sattr);
				IF S.value[0] # "#" THEN
					COPY(S.value, sattr.s)
				ELSE
					i := 1;
					WHILE S.value[i] # 0X DO
						sattr.s[i-1] := S.value[i]; INC(i)
					END;
					sattr.s[i-1] := 0X
				END;
				Attributes.InsertAttr(E.attrs, "UseMap", sattr)
			END		
		END;
		IF (ikey # HyperDocs.UndefKey) & ((doc = NIL) OR (doc.dsc = NIL)) THEN
			IF HTMLDocs.imgs THEN
				NEW(doc);
				HyperDocs.DocNameByKey(doc.name, ikey);
				doc.handle := NIL; doc.dsc := NIL;
				HTTPDocs0.RequestDoc(doc, HTTPDocs0.httpProxy, ikey, "GET", FALSE, E, NIL);
				doc := NIL
			END;
			IF ~HTMLDocs.imgs OR (doc = NIL) THEN
				ImgIcon("IMGKey", ikey); Attributes.SetInt(icon, "OBJKey", HyperDocs.UndefKey)
			END
		END;
		IF (doc # NIL) & (doc.dsc # NIL) THEN
			icon := doc.dsc
		ELSE
			doc := NIL
		END;
		IF icon # NIL THEN
			HTMLDocs.WriteObj(P, icon);
			IF ismap THEN
				HTMLDocs.NewForm(); form := Objects.NewObj(HTMLDocs.Form);
				HTMLDocs.WriteObj(P, form);
				obj := Gadgets.CreateObject("BasicGadgets.NewInteger");
				IF P.alink # NIL THEN
					Attributes.SetInt(obj, "Value", P.linkkey)
				ELSE
					Attributes.SetInt(obj, "Value", P.base.key)
				END;
				HTMLDocs.AddFormObj(P, form, obj, "@ACTION", FALSE, FALSE);
				NEW(sattr);
				sattr.s := "ISMAP";
				Attributes.InsertAttr(E.attrs, "Query", sattr);
				Attributes.SetString(icon, "Query", "ISMAP");
				NEW(sattr);
				sattr.s := "GET";
				Attributes.InsertAttr(E.attrs, "Method", sattr);
				Attributes.SetString(icon, "Method", "GET");
				NEW(sattr);
				sattr.s := "HTMLDocs.SubmitQuery";
				Attributes.InsertAttr(E.attrs, "Cmd", sattr);
				IF doc # NIL THEN
					Attributes.SetString(icon, "Cmd", "HTMLDocs.SubmitQuery")
				END;
				HTMLDocs.AddFormObj(P, form, icon, mapname, FALSE, FALSE);
				E.ol := form.elems;
				WHILE E.ol.next # NIL DO
					E.ol := E.ol.next
				END;
				E.ol.obj := icon
			ELSIF P.alink # NIL THEN
				NEW(sattr);
				sattr.s := "HTMLDocs.ExecNext";
				Attributes.InsertAttr(E.attrs, "Cmd", sattr);
				IF doc # NIL THEN
					Attributes.SetString(icon, "Cmd", "HTMLDocs.ExecNext")
				END
			END;
			
			NEW(battr); battr.b := locked;
			Attributes.InsertAttr(E.attrs, "Locked", battr);
			
			NEW(battr); battr.b := border > 0;
			Attributes.InsertAttr(E.attrs, "Border", battr);
			Attributes.SetBool(icon, "Border", battr.b);
			IF w > 0 THEN
				icon.W := w+border
			END;
			IF h > 0 THEN
				icon.H := h+border
			END;
			IF doc = NIL THEN
				IF alt # "" THEN
					Display3.StringSize(alt, Fonts.Default, w, h, dsr);
					Pictures.ReplConst(C.obj(Pictures.Picture), Display.BG, border DIV 2, (icon.H-h) DIV 2, icon.W-border, h+1, Display3.replace);
					x := (icon.W-w) DIV 2; dsr := dsr+(icon.H-h) DIV 2; i := 0;
					WHILE (alt[i] # 0X) & (C.obj # NIL) DO
						Fonts.Default.GetObj(Fonts.Default, ORD(alt[i]), obj);
						WITH obj: Fonts.Char DO
Pictures.ReplPattern(C.obj(Pictures.Picture), Display.FG, obj.pat, x+obj.x, dsr+obj.y, obj.w, obj.h, Display3.paint);
							INC(x, obj.dx)
						END;
						INC(i)
					END
				END;
				icon.handle := IconHandler
			END;
			Attributes.SetBool(icon, "Locked", TRUE)
		ELSE
			Texts.WriteString(P.W, alt)
		END; HTMLDocs.WriteSpace(P)
		END
	END IMG;

	PROCEDURE *Dummy(P: HTMLDocs.Page);
	BEGIN
	END Dummy;

	PROCEDURE NewMAP*;
		VAR e: HTMLDocs.ExtTag;
	BEGIN
		NEW(e);
		e.handle := MAP;
		e.start := InitMaps; e.stop := InitMaps;
		HTMLDocs.newTag := e
	END NewMAP;

	PROCEDURE NewAREA*;
		VAR e: HTMLDocs.ExtTag;
	BEGIN
		NEW(e);
		e.handle := AREA;
		e.start := Dummy; e.stop := Dummy;
		HTMLDocs.newTag := e
	END NewAREA;

	PROCEDURE NewIMG*;
		VAR e: HTMLDocs.ExtTag;
	BEGIN
		NEW(e);
		e.handle := IMG;
		e.start := Dummy; e.stop := Dummy;
		HTMLDocs.newTag := e
	END NewIMG;

	PROCEDURE FindMap(name: ARRAY OF CHAR): Map;
		VAR map: Map;
	BEGIN
		map := maps;
		WHILE (map # NIL) & (map.name # name) DO
			map := map.next
		END;
		RETURN map
	END FindMap;

	PROCEDURE EditArea(map: Map; F: Rembrandt.Frame; Q: Display3.Mask; VAR M: Oberon.InputMsg; x, y: INTEGER): BOOLEAN;
		VAR
			area: Area;
			u, v: INTEGER;
			keysum: SET;
		PROCEDURE FindArea();
		BEGIN
			area := map.areas;
			LOOP
				IF area = NIL THEN
					EXIT
				ELSE
					IF area IS RectArea THEN
						WITH area: RectArea DO
							IF (u >= area.x) & (v >= area.y) & (u <= area.x2) & (v <= area.y2) THEN
								EXIT
							END
						END
					END			
				END;
				area := area.next
			END
		END FindArea;
		PROCEDURE Default();
		BEGIN
			area := map.areas;
			WHILE area # NIL DO
IF ~(area IS RectArea) THEN
	RETURN
END;
				area := area.next
			END
		END Default;
	BEGIN
		u := M.X-x; v := -(M.Y-(y+F.H-1)); FindArea();
		IF area # NIL THEN
			Gadgets.MakeMask(F, x, y, M.dlink, Q);
			IF area IS RectArea THEN
				WITH area: RectArea DO
					Display3.ReplConst(Q, Display.FG, x+area.x, y+F.H-area.y2, area.x2-area.x, area.y2-area.y, Display.invert);
					keysum := M.keys;
					REPEAT
						Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow);
						keysum := keysum + M.keys;
						u := M.X-x; v := -(M.Y-(y+F.H-1));
						IF (area = NIL) OR ~((u >= area.x) & (v >= area.y) & (u <= area.x2) & (v <= area.y2)) THEN
							IF area # NIL THEN
								Display3.ReplConst(Q, Display.FG, x+area.x, y+F.H-area.y2, area.x2-area.x, area.y2-area.y, Display.invert)
							END;
							FindArea();
							IF area # NIL THEN
								Display3.ReplConst(Q, Display.FG, x+area.x, y+F.H-area.y2, area.x2-area.x, area.y2-area.y, Display.invert)
							END
						END
					UNTIL M.keys = {};
					IF area # NIL THEN
						Display3.ReplConst(Q, Display.FG, x+area.x, y+F.H-area.y2, area.x2-area.x, area.y2-area.y, Display.invert)
					END;
					IF keysum = {middle} THEN
						IF area = NIL THEN
							Default()
						END;
						IF area # NIL THEN
Attributes.SetString(F, "Cmd", "HyperDocs.FollowLink  % R  #UseMapKey");
							Attributes.SetInt(F, "UseMapKey", area.key);
							Gadgets.ExecuteAttr(F, "Cmd", M.dlink, NIL, NIL);
							M.res := 0; RETURN TRUE
						END
					END;
					Attributes.SetInt(F, "UseMapKey", HyperDocs.UndefKey)
				END
			END
		END;
		RETURN FALSE
	END EditArea;

(*	PROCEDURE Restore(map: Map; F: Rembrandt.Frame; Q: Display3.Mask; x, y: INTEGER);
		VAR area: Area;
	BEGIN
		area := map.areas;
		WHILE area # NIL DO
			IF area IS RectArea THEN
				WITH area: RectArea DO
					Display3.Rect(Q, Display.FG, Display.solid, x+area.x, y+F.H-area.y2, area.x2-area.x, area.y2-area.y, 2, Display.invert)
				END
			END;
			area := area.next
		END
	END Restore;	*)

	PROCEDURE *ImgHandle(F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			Q: Display3.Mask;
			x, y: INTEGER;
			link: Links.Link;
			name: ARRAY 64 OF CHAR;
			map: Map;
A: Objects.AttrMsg;
		PROCEDURE GetMap();
		BEGIN
			link := Links.FindLink("UseMap", F(Gadgets.Frame).link);
			IF link = NIL THEN
				Attributes.GetString(F, "UseMap", name);
				map := FindMap(name);
				IF map # NIL THEN
					NEW(link); link.name := "UseMap";
					link.obj := map;
					Links.InsertLink(F(Gadgets.Frame).link, "UseMap", link)
				END
			ELSE
				map := link.obj(Map)
			END
		END GetMap;
	BEGIN
		WITH F: Rembrandt.Frame DO
			IF M IS Display.FrameMsg THEN
				WITH M: Display.FrameMsg DO
					IF (M.F = NIL) OR (M.F = F) THEN
					(*	IF M IS Display.DisplayMsg THEN
							Rembrandt.Handle(F, M); GetMap();
							IF map # NIL THEN
								x := M.x + F.X; y := M.y + F.Y;
								WITH M: Display.DisplayMsg DO
									IF M.device = Display.screen THEN
										IF (M.id = Display.full) OR (M.F = NIL) THEN
											Gadgets.MakeMask(F, x, y, M.dlink, Q);
											Restore(map, F, Q, x, y)
										ELSIF M.id = Display.area THEN
											Gadgets.MakeMask(F, x, y, M.dlink, Q);
											Display3.AdjustMask(Q, x + M.u, y + F.H - 1 + M.v, M.w, M.h);
											Restore(map, F, Q, x, y)
										END
									END
								END
							END
						ELS	*)	IF M IS Oberon.InputMsg THEN
							WITH M: Oberon.InputMsg DO
								IF (M.id = Oberon.track) & Gadgets.InActiveArea(F, M) THEN
									IF M.keys = {middle} THEN
										GetMap();
										IF map # NIL THEN
											x := M.x + F.X; y := M.y + F.Y;
											Gadgets.MakeMask(F, x, y, M.dlink, Q);
											IF ~EditArea(map, F, Q, M, x, y) THEN
												Rembrandt.Handle(F, M)
											END
										ELSE
											Rembrandt.Handle(F, M)
										END
ELSIF M.keys = {} THEN
	A.id := Objects.get; A.name := "Cmd"; A.res := -1; A.s := "";
	F.handle(F, A);
	IF (A.res = 0) & (A.s # "") THEN
		Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, M.X, M.Y); M.res := 0
	ELSE
		Rembrandt.Handle(F, M)
	END
									ELSE
										Rembrandt.Handle(F, M)
									END
								ELSE
									Rembrandt.Handle(F, M)
								END
							END
						ELSE
							Rembrandt.Handle(F, M)
						END
					END
				END
			ELSE
				Rembrandt.Handle(F, M)
			END
		END
	END ImgHandle;

BEGIN
	HTTPDocs0.ImgHandle := ImgHandle
END HTMLImages.

System.Set HTMLTags MAP := HTMLImages.NewMAP ~
System.Set HTMLTags AREA := HTMLImages.NewAREA ~
System.Set HTMLTags IMG := HTMLImages.NewIMG ~

to do: AddImg (for INPUT TYPE="image")