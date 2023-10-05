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

MODULE BookCompiler;	(** portable *)
	IMPORT Oberon, Texts, Files, Display, Gadgets, TextGadgets, Fonts, Objects, Books, Books0, BookDocs,
		Strings, Documents, Lists, TextFields, TextDocs, Desktops, Panels;
	
	CONST
		(* symbols for scanner *)
		noSy = 0; identSy = 1; bsSy = 2; lbrSy = 3; rbrSy = 4; starSy = 5; minusSy = 6; plusSy = 7; eqSy = 8;
		bookSy = 9; chapterSy = 10; labelSy = 11; linkSy = 12; indexSy = 13; callSy = 14; noteSy = 15;
		lprSy = 17; rprSy = 18; commaSy = 19; numberSy = 20;
		(* limit for the number of objects in a text *)
		maxObj = 256;
		
	TYPE
		Chapter = POINTER TO ChapterDesc;
		Label = POINTER TO LabelDesc;
		Node = POINTER TO NodeDesc;
		PosList = POINTER TO PosListDesc;
		NotePosList = POINTER TO NotePosListDesc;
		SectNode = POINTER TO SectNodeDesc;
		
		(* list of chapters/pages *)
		ChapterDesc = RECORD
			nObj: INTEGER;
			text: Texts.Text;
			ind: LONGINT;
			next: Chapter
		END;
		
		(* multi-way tree for contents page *)
		SectNodeDesc = RECORD
			B: Texts.Buffer;
			next, desc: SectNode;
			c: Books0.ContElem
		END;

		(* list of labels/footnotes *)
		LabelDesc = RECORD
			name: ARRAY Books0.identLen OF CHAR;
			frame: Books0.LocFrame;
			export: BOOLEAN;
			next: Label
		END;
		
		(* binary tree for index page *)
		NodeDesc = RECORD
			beg, end: LONGINT;
			pos: PosList;
			left, right: Node
		END;
		(* list of double index entries *)
		PosListDesc = RECORD
			pos: LONGINT;
			chapter: Chapter;
			next: PosList
		END;
		NotePosListDesc = RECORD (PosListDesc)
			pos2: LONGINT
		END;
		
	VAR
		chapters, contents, curChap: Chapter;
		labels: Label;
		root: Node;
		imports: Books0.ImpList;
		bookName: ARRAY Books0.nameLen OF CHAR;
		ident: ARRAY Books0.identLen OF CHAR;
		B: Texts.Buffer;
		inText, callText, noteText: Texts.Text;
		R: Texts.Reader;
		W, Wr: Texts.Writer;
		sym, width, heigth: INTEGER;
		ch: CHAR;
		number: LONGINT;
		begId, endId, lastPos, oldPos, nextChap: LONGINT;
		sections: ARRAY Books.maxSect OF INTEGER;
		eol, expand, error: BOOLEAN;
		options, styleMode: SET;
		iconStr: ARRAY 2*Books0.nameLen OF CHAR;
		sectRoot: SectNode;
		
(* report error message *)
	PROCEDURE Mark(msg1, msg2: ARRAY OF CHAR);
	BEGIN
		error := TRUE;
		IF Texts.Pos(R) > lastPos-1 THEN
			Texts.WriteLn(Wr);
			Texts.WriteString(Wr, msg1);
			Texts.WriteString(Wr, msg2);
			Texts.WriteString(Wr, " at ");
			Texts.WriteInt(Wr, lastPos, 0);
			Texts.Append(Oberon.Log, Wr.buf)
		END
	END Mark;

(* change font *)
	PROCEDURE MarkFnt(T: Texts.Text; beg, end: LONGINT; fnt: Fonts.Font);
	BEGIN
		Texts.ChangeLooks(T, beg, end, {Books.looksLib}, fnt, 0, 0)
	END MarkFnt;

(* increment number of objects in this chapter-page *)
	PROCEDURE IncObj(c: Chapter);
	BEGIN
		INC(c.nObj);
		IF c.nObj > maxObj THEN
			Mark("", "too many objects")
		END
	END IncObj;
	
(* replace old font in textstrecth (beg, end) to bew font *)
	PROCEDURE ChangeFont(t: Texts.Text; old, new: Fonts.Font; beg, end: LONGINT);
		VAR
			R: Texts.Reader;
			ch: CHAR;
			pos: LONGINT;
	BEGIN
		Texts.OpenReader(R, t, beg);
		Texts.Read(R, ch);
		pos := Texts.Pos(R);
		WHILE ~R.eot & (pos < end) DO
			IF R.lib = old THEN
				WHILE ~R.eot & (R.lib = old) & (pos < end) DO
					Texts.Read(R, ch)
				END;
				MarkFnt(t, pos-1, Texts.Pos(R)-1, new)
			END;
			IF ~R.eot THEN
				Texts.Read(R, ch);
				pos := Texts.Pos(R)
			END
		END
	END ChangeFont;

(* create a new contents-tree node *)
	PROCEDURE NewSectNode(VAR nd: SectNode);
	BEGIN
		NEW(nd);
		nd.next := NIL; nd.desc := NIL;
		NEW(nd.B); Texts.OpenBuf(nd.B);
		Books0.NewContElem();
		nd.c := Objects.NewObj(Books0.ContElem)
	END NewSectNode;
	
(* expand commands \\ and \} in the given text-stretch *)
	PROCEDURE Expand(VAR t: Texts.Text; beg, end: LONGINT);
		VAR
			R: Texts.Reader;
			ch: CHAR;
			pos: LONGINT;
	BEGIN
		IF expand THEN
			Texts.OpenReader(R, t, beg);
			Texts.Read(R, ch);
			WHILE ~R.eot & (Texts.Pos(R) < end) DO
				IF ch = "\" THEN
					Texts.Read(R, ch);
					IF (ch = "}") OR (ch = "\") THEN
						pos := Texts.Pos(R)-1;
						Texts.Delete(t, pos-1, pos);
						Texts.OpenReader(R, t, pos);
						Texts.Read(R, ch);
						DEC(end)
					END
				ELSE
					Texts.Read(R, ch)
				END
			END
		END
	END Expand;
	
(* create a new chapter-page *)
	PROCEDURE NewChapter(VAR c: Chapter);
	BEGIN
		NEW(c);
		NEW(c.text);
		Texts.Open(c.text, "");
		c.nObj := 0;
		c.next := NIL;
		c.ind := nextChap;
		INC(nextChap)
	END NewChapter;

(* search a item named ident in the labels list *)
	PROCEDURE SearchLabel(): Label;
		VAR l: Label;
	BEGIN
		l := labels;
		WHILE (l # NIL) & (l.name # ident) DO
			l := l.next
		END;
		RETURN l
	END SearchLabel;

(* define a new label (curC -> at the end of the current chapter) *)
	PROCEDURE DefChapLabel(curC: BOOLEAN): Label;
		VAR l, cl: Label;
	BEGIN
		l := SearchLabel();
		IF l = NIL THEN
			NEW(cl);
			COPY(ident, cl.name);
			cl.next := labels;
			labels := cl
		ELSIF  l.frame.pos1 >= 0 THEN
			NEW(cl);
			COPY(ident, cl.name);
			cl.next := labels;
			labels := cl;
			Mark(ident, " label allready defined")
		ELSE
			cl := l
		END;
		IF cl # l THEN
			cl.export := FALSE;
			Books0.NewLoc();
			cl.frame := Objects.NewObj(Books0.LocFrame);
			cl.frame.mode := Books.link
		END;
		IF curC THEN
			cl.frame.pos1 := curChap.ind;
			cl.frame.pos2 := curChap.text.len
		ELSE
			cl.frame.pos1 := -1;
			cl.frame.pos2 := -1
		END;
		RETURN cl
	END DefChapLabel;
	
(* initialize all global data for a new tutorial *)
	PROCEDURE NewBook(title: BOOLEAN);
		VAR
			beg: LONGINT;
			cl: Label;
	BEGIN
		labels := NIL;
		imports := NIL;
		nextChap := 0;
		NewChapter(chapters);
		chapters.next := NIL;
		curChap := chapters;
		contents := chapters;
		ident := "Contents";
		cl := DefChapLabel(TRUE);
		IF ~title THEN
			Texts.WriteString(W, "Contents of ");
			Texts.WriteString(W, bookName);
			Texts.WriteString(W, ": ");
			Texts.Append(contents.text, W.buf)
		ELSE
			beg := contents.text.len;
			Texts.Save(inText, begId, endId, B);
			Texts.Append(contents.text, B);
			Expand(contents.text, beg, contents.text.len)
		END;
		Texts.WriteLn(W);
		Texts.Append(contents.text, W.buf);
		MarkFnt(contents.text, 0, contents.text.len, BookDocs.titleFont);
		NewSectNode(sectRoot);
		Texts.Save(contents.text, 0, contents.text.len, sectRoot.B);
		NEW(root);
		root.left := NIL; root.right := NIL; root.pos := NIL;
		root.beg := 0; root.end := 0;
		NEW(callText);
		Texts.Open(callText, "");
		NEW(noteText);
		Texts.Open(noteText, "")
	END NewBook;

(* defines a new, empty footnote *)
	PROCEDURE DefFootnoteLabel(): Label;
		VAR l, pl: Label;
	BEGIN
		l := SearchLabel();
		IF l = NIL THEN
			NEW(pl);
			COPY(ident, pl.name);
			pl.next := labels;
			labels := pl
		ELSE
			Mark(ident, " label allready defined");
			pl := l
		END;
		pl.export := FALSE;
		Books0.NewLoc();
		pl.frame := Objects.NewObj(Books0.LocFrame);
		pl.frame.mode := Books.note;
		pl.frame.pos1 := -1;
		pl.frame.pos2 := -1;
		RETURN pl
	END DefFootnoteLabel;
		
(* creates a link to the label/footnote named ident *)
	PROCEDURE DefLink(): Books0.Frame;
		VAR l: Label;
	BEGIN
		l := SearchLabel();
		IF l = NIL THEN
			l := DefChapLabel(FALSE)
		END;
		RETURN l.frame
	END DefLink;

(* creates a external link to the label/footnote named name *)
	PROCEDURE DefExtLink(i: Books0.ImpList; VAR name: ARRAY OF CHAR): Books0.Frame;
		VAR
			el: Books0.ExtLabel;
			lk: Books0.Frame;
	BEGIN
		el := i.extLabels;
		WHILE (el # NIL) & (el.name # name) DO
			el := el.next
		END;
		IF el # NIL THEN
			IF el.frame = NIL THEN
				Books0.NewExt();
				lk := Objects.NewObj(Books0.ExtFrame);
				lk.mode := el.mode;
				lk(Books0.ExtFrame).imp := el;
				el.frame := lk
			ELSE
				lk := el.frame
			END
		ELSE
			Texts.WriteLn(Wr);
			Texts.WriteString(Wr, "Warning: external label ");
			Texts.WriteString(Wr, i.name);
			Texts.Write(Wr, ".");
			Texts.WriteString(Wr, name);
			Texts.WriteString(Wr, " not found");
			Texts.Append(Oberon.Log, Wr.buf);
			NEW(el);
			COPY(name, el.name);
			el.next := i.extLabels;
			i.extLabels := el;
			el.book := i;
			el.mode := Books.link;
			Books0.NewExt();
			lk := Objects.NewObj(Books0.ExtFrame);
			lk.mode := el.mode;
			lk(Books0.ExtFrame).imp := el;
			el.frame := lk
		END;
		RETURN lk	
	END DefExtLink;

(* defines a new comand link *)
	PROCEDURE DefCallGadgets(beg: LONGINT);
		VAR obj: Books0.LocFrame;
	BEGIN
		Books0.NewLoc();
		obj := Objects.NewObj(Books0.LocFrame);
		obj.mode:= Books.call;
		obj.pos1 := beg;
		obj.pos2 := callText.len;
		Books0.AppendFrame(curChap.text, obj);
		IncObj(curChap)
	END DefCallGadgets;

(* mark the given text-stretch with the correct (mode) color and font (if ft) *)
	PROCEDURE MarkText(T: Texts.Text; beg, end: LONGINT; mode: SHORTINT; ft: BOOLEAN);
	BEGIN
		IF ft THEN
			CASE mode OF
				Books.link: Texts.ChangeLooks(T, beg, end, {Books.looksCol, Books.looksLib}, BookDocs.linkFont, Books.linkCol, 0)
				|Books.call: Texts.ChangeLooks(T, beg, end, {Books.looksCol, Books.looksLib}, BookDocs.callFont, Books.callCol, 0)
				|Books.note: Texts.ChangeLooks(T, beg, end, {Books.looksCol, Books.looksLib}, BookDocs.noteFont, Books.noteCol, 0)
			ELSE
			END
		ELSE
			CASE mode OF
				Books.link: Texts.ChangeLooks(T, beg, end, {Books.looksCol}, NIL, Books.linkCol, 0)
				|Books.call: Texts.ChangeLooks(T, beg, end, {Books.looksCol}, NIL, Books.callCol, 0)
				|Books.note: Texts.ChangeLooks(T, beg, end, {Books.looksCol}, NIL, Books.noteCol, 0)
			ELSE
			END
		END;
	END MarkText;

(* adds a chapter of level s to the contents tree *)

	PROCEDURE Visit(VAR n: SectNode; d: INTEGER);
	BEGIN
		IF (n.desc # NIL) & (d > 0) THEN
			n := n.desc;
			WHILE n.next # NIL DO
				n := n.next
			END;
			Visit(n, d-1)
		END
	END Visit;

	PROCEDURE DefSection(s: INTEGER; e: BOOLEAN);
		VAR
			i: INTEGER;
			obj: Books0.LocFrame;
			beg: LONGINT;
			cl: Label;
			nd, nd2: SectNode;
	BEGIN
		IF ident # "" THEN
			cl := DefChapLabel(TRUE);
			cl.export := e
		END;
		Books0.NewLoc();
		obj := Objects.NewObj(Books0.LocFrame);
		obj.mode := Books.link;
		obj.pos1 := curChap.ind;
		obj.pos2 := curChap.text.len;
		Texts.WriteLn(W);
		Texts.Write(W, Books.Tab);
		i := 0;
		WHILE i < s DO
			Texts.Write(W, Books.Tab);
			INC(i)
		END;
		Texts.Append(contents.text, W.buf);
		Texts.Save(inText, begId, endId, B);
		beg := contents.text.len;
		Texts.Append(contents.text, B);
		Expand(contents.text, beg, contents.text.len);
		MarkText(contents.text, beg, contents.text.len, Books.link, TRUE);
		Books0.AppendFrame(contents.text, obj);
		IncObj(contents);
		IF (Books.formated IN options) & (s < Books.maxSect) THEN
			MarkFnt(contents.text, beg, contents.text.len, BookDocs.sectionFonts[s])
		END;
		IF s >= Books.maxSect THEN
			Mark("", "to deep chapter nesting"); s := 1
		ELSIF sections[s-1] = 0 THEN
			Mark("", "no chapter of previous level"); s := 1
		ELSE
			INC(sections[s])
		END;
		NewSectNode(nd);
		Texts.Save(contents.text, beg, contents.text.len, nd.B);
		nd2 := sectRoot;
		Visit(nd2, s);
		IF nd2.desc = NIL THEN
			nd2.desc := nd
		ELSE
			nd2 := nd2.desc;
			WHILE (nd2.next # NIL) DO
				nd2 := nd2.next
			END;
			nd2.next := nd
		END;
		Texts.Save(inText, begId, endId, B);
		beg := curChap.text.len;
		Texts.Append(curChap.text, B);
		Expand(curChap.text, beg, curChap.text.len);
		IF (Books.formated IN options) & (s < Books.maxSect) THEN
			MarkFnt(curChap.text, beg, curChap.text.len, BookDocs.sectionFonts[s])
		END
	END DefSection;
	
(* defines a new chapter-page *)
	PROCEDURE DefChapter(e: BOOLEAN);
		VAR
			chap: Chapter;
			i: INTEGER;
			obj: Books0.LocFrame;
			beg: LONGINT;
			style: TextGadgets.Style;
			cl: Label;
			nd, nd2: SectNode;
	BEGIN
		IF (curChap # NIL) & (curChap # chapters) THEN
			Texts.WriteLn(W);
			Texts.Append(curChap.text, W.buf)
		END;
		NewChapter(chap);
		curChap.next := chap;
		curChap := chap;
		IF ident # "" THEN
			cl := DefChapLabel(TRUE);
			cl.export := e
		END;
		Books0.NewLoc();
		obj := Objects.NewObj(Books0.LocFrame);
		obj.mode := Books.link;
		obj.pos1 := curChap.ind;
		obj.pos2 := 0;
		Texts.WriteLn(W);
		Texts.Write(W, Books.Tab);
		Texts.Append(contents.text, W.buf);
		beg := contents.text.len;
		IF endId >= begId THEN
			Texts.Save(inText, begId, endId, B);
			Texts.Append(contents.text, B);
			Expand(contents.text, beg, contents.text.len)
		ELSE
			Texts.WriteString(W, ident);
			Texts.Append(contents.text, W.buf)
		END;
		MarkText(contents.text, beg, contents.text.len, Books.link, TRUE);
		Books0.AppendFrame(contents.text, obj);
		IncObj(contents);
		IF Books.formated IN options THEN
			MarkFnt(contents.text, beg, contents.text.len, BookDocs.sectionFonts[0])
		END;
		NewSectNode(nd);
		Texts.Save(contents.text, beg, contents.text.len, nd.B);
		IF sectRoot.desc = NIL THEN
			sectRoot.desc := nd
		ELSE
			nd2 := sectRoot.desc;
			WHILE (nd2.next # NIL) DO
				nd2 := nd2.next
			END;
			nd2.next := nd
		END;
		sections[0] := 1;
		i := 1;
		WHILE i < Books.maxSect DO
			sections[i] := 0;
			INC(i)
		END;
		beg := chap.text.len;
		IF endId >= begId THEN
			Texts.Save(inText, begId, endId, B);
			Texts.Append(chap.text, B)
		END;
		Expand(chap.text, beg, chap.text.len);
		IF Books.formated IN options THEN
			IF endId >= begId THEN
				Texts.WriteLn(W);
				Texts.Append(chap.text, W.buf)
			END;
			style := TextGadgets.newStyle();
			style.width := width-Books.borderL-Books.borderR-Books.scrollBW;
			style.mode := styleMode;
			Books0.AppendFrame(curChap.text, style);
			IncObj(curChap);
			MarkFnt(curChap.text, beg, curChap.text.len, BookDocs.sectionFonts[0])
		END
	END DefChapter;
	
(* adds an index entry *)

	PROCEDURE Compare(a, b: Node): INTEGER;
		VAR
			R0, R1: Texts.Reader;
			ch0, ch1: CHAR;
	BEGIN
		Texts.OpenReader(R0, inText, a.beg);
		Texts.OpenReader(R1, inText, b.beg);
		Texts.Read(R0, ch0); Texts.Read(R1, ch1);
		WHILE ~R0.eot & ~R1.eot & (CAP(ch0) = CAP(ch1)) & (Texts.Pos(R0) <= a.end) & (Texts.Pos(R1) <= b.end) DO
			Texts.Read(R0, ch0); Texts.Read(R1, ch1)
		END;
		IF ~(R0.eot OR (Texts.Pos(R0) > a.end)) & ~(R1.eot OR (Texts.Pos(R1) > b.end)) THEN
			RETURN ORD(CAP(ch1))-ORD(CAP(ch0))
		ELSIF (R0.eot OR (Texts.Pos(R0) > a.end)) & (R1.eot OR (Texts.Pos(R1) > b.end)) THEN
			RETURN 0
		ELSIF R0.eot OR (Texts.Pos(R0) > a.end) THEN
			RETURN +1
		ELSIF R1.eot OR (Texts.Pos(R1) > b.end) THEN
			RETURN -1
		ELSE
			RETURN 0
		END
	END Compare;

	PROCEDURE DefIndex(pos: LONGINT; mode: SHORTINT);
		VAR
			n, cur, prev: Node;
			res: INTEGER;
			pl, pl2: PosList;
			npl: NotePosList;
	BEGIN
		NEW(n);
		n.beg := begId; n.end := endId;
		n.pos := NIL; n.left := NIL; n.right := NIL;
		cur := root; prev := NIL;
		WHILE cur # NIL DO
			prev := cur;
			res := Compare(cur, n);
			IF res < 0 THEN
				cur := cur.left
			ELSIF res > 0 THEN
				cur := cur.right
			ELSE
				cur := NIL
			END
		END;
		IF mode = Books.link THEN
			NEW(pl);
			pl.chapter := curChap;
			pl.pos := pos;
			pl.next := NIL
		ELSIF mode = Books.note THEN
			NEW(npl);
			npl.chapter := NIL;
			npl.pos := pos;
			npl.pos2 := noteText.len;
			npl.next := NIL;
			pl := npl
		END;
		IF res < 0 THEN
			prev.left := n;
			n.pos := pl
		ELSIF res > 0 THEN
			prev.right := n;
			n.pos := pl
		ELSIF (prev.right # NIL) & ((endId-begId) > (prev.end-prev.beg)) THEN
			prev.right := n;
			n.pos := pl
		ELSIF (prev.left # NIL) & ((endId-begId) < (prev.end-prev.beg)) THEN
			prev.left := n;
			n.pos := pl
		ELSE
			n := prev;
			pl2 := n.pos;
			WHILE pl2.next # NIL DO
				pl2 := pl2.next
			END;
			pl2.next := pl
		END
	END DefIndex;
	
(* adds the text to an earlier defined footnote *)
	PROCEDURE InsertFootnote(pl: Label);
		VAR beg: LONGINT;
	BEGIN
		pl.frame.pos1 := noteText.len;
		Texts.Save(inText, begId, endId, B);
		beg := noteText.len;
		Texts.Append(noteText, B);
		Expand(noteText, beg, noteText.len);
		pl.frame.pos2 := noteText.len
	END InsertFootnote;
		
(* check if all labels/footnotes used got defined *)
	PROCEDURE CheckLabels();
		VAR l: Label;
	BEGIN
		ident := "Open";
		l := SearchLabel();
		IF l = NIL THEN
			l := DefChapLabel(FALSE);
			l.frame.pos1 := 0;
			l.frame.pos2 := 0
		ELSIF l.frame.pos1 < 0 THEN
			l.frame.pos1 := 0;
			l.frame.pos2 := 0
		END;
		l.export := TRUE;
		l := labels;
		WHILE l # NIL DO
			IF l.frame.pos1 < 0 THEN
				Mark(l.name, " label never defined")
			END;
			l := l.next
		END
	END CheckLabels;
	
(* create the tutorial file *)
	PROCEDURE RegisterBook();
		VAR
			c: Chapter;
			F: Files.File;
			R: Files.Rider;
			ind, len, pos, fixPos1, fixPos2, fixPos3: LONGINT;
			il: Books0.ImpList;
			l: Label;
			IM: BookDocs.InValMsg;
	BEGIN
		F := Files.New(bookName);
		Texts.WriteString(Wr, ", writing: ");
		Texts.WriteString(Wr, bookName);
		Texts.WriteLn(Wr);
		Texts.Append(Oberon.Log, Wr.buf);
		IF F = NIL THEN
			HALT(99)
		END;
		Files.Set(R, F, 0);
		ident := "Open";
		l := SearchLabel();
		l.export := TRUE;
		ind := l.frame.pos1;
		pos := l.frame.pos2;
		BookDocs.WriteHeader(R, 0, 0, width, heigth, ind, pos, options, iconStr);
		fixPos1 := Files.Pos(R);
		Files.WriteLInt(R, 0);
		fixPos2:= Files.Pos(R);
		Files.WriteLInt(R, 0);
		fixPos3 := Files.Pos(R);
		Files.WriteLInt(R, 0);
		ind := 0;
		il := imports;
		WHILE il # NIL DO
			il.ind := ind;
			INC(ind);
			Files.WriteString(R, il.name);
			il := il.next
		END;
		Files.WriteString(R, "");
		c := chapters;
		WHILE c # NIL DO
			len := c.text.len;
			IF c.text = noteText THEN
				pos := Files.Pos(R);
				Files.Set(R, F, fixPos2);
				Files.WriteLInt(R, pos);
				Files.Set(R, F, pos)
			END;
			Files.WriteLInt(R, len);
			IF len > 0 THEN
				pos := Files.Pos(R);
				Texts.Store(c.text, F, pos, len);
				Files.Set(R, F, pos+len)
			END;
			c := c.next
		END;
		Files.WriteLInt(R, -1);
		pos := Files.Pos(R);
		Files.Set(R, F, fixPos1);
		Files.WriteLInt(R, pos);
		Files.Set(R, F, pos);
		l := labels;
		WHILE l # NIL DO
			IF l.export THEN
				Files.Write(R, l.frame.mode);
				Files.WriteLInt(R, l.frame.pos1);
				Files.WriteLInt(R, l.frame.pos2);
				Files.WriteString(R, l.name)
			END;
			l := l.next
		END;
		Files.Write(R, Books0.none);
		pos := Files.Pos(R);
		Files.Set(R, F, fixPos3);
		Files.WriteLInt(R, pos);
		Files.Set(R, F, pos);
		Files.Register(F);
		Files.Close(F);
		IM.F := NIL;
		COPY(bookName, IM.name);
		IM.res := -1;
		Display.Broadcast(IM)
	END RegisterBook;

(* scanning/parsing procedures *)

	PROCEDURE isLetter(ch: CHAR): BOOLEAN;
	BEGIN
		RETURN ((ch >= "a") & (ch <= "z")) OR ((ch >= "A") & (ch <= "Z"))
	END isLetter;
	
	PROCEDURE isDigit(ch: CHAR): BOOLEAN;
	BEGIN
		RETURN (ch >= "0") & (ch <= "9")
	END isDigit;

	PROCEDURE isChar(VAR R: Texts.Reader): BOOLEAN;
	BEGIN
		RETURN ~R.eot & (R.lib IS Fonts.Font)
	END isChar;
		
	PROCEDURE Ident(VAR c: CHAR);
		VAR
			i: INTEGER;
			cc: CHAR;
	BEGIN
		i := 0;
		cc := ch;
		WHILE (i < Books0.identLen) & isChar(R) & (isLetter(cc) OR isDigit(cc)) DO
			ident[i] := cc;
			INC(i);
			Texts.Read(R, cc)
		END;
		sym := identSy;
		IF i >= Books0.identLen THEN
			ident[Books0.identLen-1] := 0X;
			Mark("", "identifier too long")
		ELSE
			ident[i] := 0X
		END;
		IF ident = "Book" THEN
			sym := bookSy
		ELSIF ident = "Chapter" THEN
			sym := chapterSy
		ELSIF ident = "Label" THEN
			sym := labelSy
		ELSIF ident = "Link" THEN
			sym := linkSy
		ELSIF ident = "Index" THEN
			sym := indexSy
		ELSIF ident = "Call" THEN
			sym := callSy
		ELSIF ident = "Note" THEN
			sym := noteSy
		ELSE
			sym := identSy
		END;
		c := cc
	END Ident;
	
	PROCEDURE GetIdent();
	BEGIN
		begId := Texts.Pos(R)-1; lastPos := begId;
		Ident(ch);
		endId := Texts.Pos(R)-1
	END GetIdent;
	
	PROCEDURE GetNumber();
		VAR i: INTEGER;
	BEGIN
		i := 0;
		WHILE (i < Books0.identLen) & isChar(R) & isDigit(ch) DO
			ident[i] := ch;
			INC(i);
			Texts.Read(R, ch)
		END;
		sym := numberSy;
		IF i >= Books0.identLen THEN
			ident[Books0.identLen-1] := 0X;
			Mark("", "identifier too long")
		ELSE
			ident[i] := 0X
		END;
		Strings.StrToInt(ident, number)
	END GetNumber;
	
	PROCEDURE Get();
	BEGIN
		oldPos := Texts.Pos(R);
		lastPos := oldPos;
		WHILE isChar(R) & (ch <= " ") DO
			Texts.Read(R, ch)
		END;
		sym := noSy;
		IF isChar(R) THEN
			CASE ch OF
				"A".."Z", "a".."z": GetIdent()
				|"0" .. "9": GetNumber()
				|"\": sym := bsSy; Texts.Read(R, ch)
				|"{": sym := lbrSy; Texts.Read(R, ch)
				|"}": sym := rbrSy; Texts.Read(R, ch)
				|"*": sym := starSy; Texts.Read(R, ch)
				|"-": sym := minusSy; Texts.Read(R, ch)
				|"+": sym := plusSy; Texts.Read(R, ch)
				|"=": sym := eqSy; Texts.Read(R, ch)
				|"[": sym := lprSy; Texts.Read(R, ch)
				|"]": sym := rprSy; Texts.Read(R, ch)
				|",": sym := commaSy; Texts.Read(R, ch)
			ELSE
				sym := noSy
			END
		END
	END Get;
		
	PROCEDURE SymToName(s: INTEGER; VAR na: ARRAY OF CHAR);
		VAR name: ARRAY Books0.identLen OF CHAR;
	BEGIN
		CASE s OF
			identSy: name := "ident"
			|bsSy: name := "\ "
			|lbrSy: name := "{ "
			|rbrSy: name := "} "
			|starSy: name := "* "
			|minusSy: name := "- "
			|plusSy: name := "+ "
			|eqSy: name := "= "
			|bookSy: name := "Book "
			|chapterSy: name := "Chapter "
			|labelSy: name := "Label "
			|linkSy: name := "Link "
			|indexSy: name := "Index "
			|callSy: name := "Call "
			|noteSy: name := "Note "
			|lprSy: name := "[ "
			|rprSy: name := "] "
			|commaSy: name := " ,"
			|numberSy: name := "number"
		ELSE
			name := "???"
		END;
		COPY(name, na)
	END SymToName;
	
	PROCEDURE Check(sy: INTEGER);
		VAR name: ARRAY Books0.identLen OF CHAR;
	BEGIN
		Get();
		IF sy # sym THEN
			SymToName(sy, name);
			Mark(name, " expected");
			number := 0;
			ident := ""
		END
	END Check;
	
	PROCEDURE GetString(objs: BOOLEAN);
	BEGIN
		expand := FALSE; eol := FALSE;
		begId := Texts.Pos(R)-1;
		WHILE ~R.eot & ~(isChar(R) & (ch = "}")) & (objs OR isChar(R)) DO
			IF isChar(R) & (ch = "\") THEN
				Texts.Read(R, ch);
				IF isChar(R) THEN
					CASE ch OF
						"}": expand := TRUE; Texts.Read(R, ch)
						|"\": expand := TRUE; Texts.Read(R, ch)
						|"A" .. "Z", "a" .. "z": Mark("", "commands not allowed in string")
					ELSE
					END
				END
			ELSIF isChar(R) & (ch = Books.EOL) THEN
				eol := TRUE;
				Texts.Read(R, ch)
			ELSE
				Texts.Read(R, ch)
			END
		END;
		IF R.eot THEN
			Mark("", "unexpected end of text")
		ELSIF ~objs & ~isChar(R) THEN
			Mark("", "objects not allow in string")
		END;
		endId := Texts.Pos(R)-1
	END GetString;
	
	PROCEDURE GetName(VAR name: ARRAY OF CHAR): BOOLEAN;
		VAR
			i: INTEGER;
			dot: BOOLEAN;
	BEGIN
		dot := FALSE;
		begId := Texts.Pos(R)-1;
		i := 0;
		WHILE (i < Books0.nameLen+1+Books0.identLen) & isChar(R) & (isLetter(ch) OR isDigit(ch) OR (ch = ".")) DO
			IF ch = "." THEN
				dot := TRUE
			END;
			name[i] := ch;
			INC(i);
			Texts.Read(R, ch)
		END;
		IF i >= Books0.nameLen+1+Books0.identLen THEN
			name[Books0.nameLen+Books0.identLen] := 0X;
			Mark("", "identifier too long")
		ELSIF ~dot & (i >= Books0.identLen) THEN
			name[Books0.identLen-1] := 0X;
			Mark("", "identifier too long")
		ELSE
			name[i] := 0X
		END;
		endId := Texts.Pos(R)-1;
		RETURN dot
	END GetName;
	
	(* process the contents of the chapters *)
	PROCEDURE Contents();
		VAR
			beg, end: LONGINT;
			Fi: Texts.Finder;
			obj: Objects.Object;
	BEGIN
		LOOP
			beg := Texts.Pos(R)-1;
			WHILE ~R.eot & ~((ch = "\") & (R.lib IS Fonts.Font)) DO
				IF ~(R.lib IS Fonts.Font) THEN
					Texts.OpenFinder(Fi, inText, Texts.Pos(R)-1);
					Texts.FindObj(Fi, obj);
					(*!!
					IF (obj # NIL) & (obj IS Gadgets.Frame) & ~(Gadgets.nodelete IN obj(Gadgets.Frame).state) THEN
						INCL(obj(Gadgets.Frame).state, Gadgets.nodelete);
						INCL(obj(Gadgets.Frame).state, Gadgets.nomove)
					END;
					*)
					IncObj(curChap)
				END;
				Texts.Read(R, ch)
			END;
			end := Texts.Pos(R)-1;
			Texts.Save(inText, beg, end, B);
			beg := curChap.text.len;
			Texts.Append(curChap.text, B);
			IF Books.formatText IN options THEN
				ChangeFont(curChap.text, Fonts.Default, BookDocs.textFont, beg, curChap.text.len)
			END;
			IF R.eot THEN
				sym := noSy; EXIT
			ELSE
				Texts.Read(R, ch);
				IF isChar(R) & isLetter(ch) THEN
					GetIdent();
					IF sym = bookSy THEN
						Mark(ident, " \Book not allowed in text");
						IF ~R.eot THEN Texts.Read(R, ch) END
					ELSIF sym # identSy THEN
						EXIT
					ELSE
						Mark(ident, " unknown command");
						IF ~R.eot THEN Texts.Read(R, ch) END
					END
				ELSIF isChar(R) & (ch = "\") THEN
					Texts.Save(inText, end+1, Texts.Pos(R), B);
					beg := curChap.text.len;
					Texts.Append(curChap.text, B);
					IF Books.formatText IN options THEN
						ChangeFont(curChap.text, Fonts.Default, BookDocs.textFont, beg, curChap.text.len)
					END;
					IF ~R.eot THEN Texts.Read(R, ch) END
				END
			END
		END;
		lastPos := Texts.Pos(R)-1
	END Contents;
	
(* parse the commands *)

	PROCEDURE GetBookName(VAR lname, name, ident: ARRAY OF CHAR);
		VAR
			i, d: INTEGER;
	BEGIN
		i := 0; d := -1;
		WHILE lname[i] # 0X DO
			name[i] := lname[i];
			IF lname[i] = "." THEN
				d := i
			END;
			INC(i)
		END;
		name[d] := 0X;
		i := d+1;
		WHILE lname[i] # 0X DO
			ident[i-d-1] := lname[i];
			INC(i)
		END;
		ident[i-d-1] := 0X
	END GetBookName;
	
	PROCEDURE Import(VAR name: ARRAY OF CHAR): Books0.ImpList;
		VAR il: Books0.ImpList;
	BEGIN
		Books0.StrConcat(name, ".Book");
		il := imports;
		WHILE (il # NIL) & (il.name # name) DO
			il := il.next
		END;
		IF il = NIL THEN
			NEW(il);
			il.extLabels := NIL;
			il.next := imports;
			imports := il;
			il.ind := -1;
			COPY(name, il.name);
			IF ~BookDocs.Import(il, TRUE) THEN
				Texts.WriteLn(Wr);
				Texts.WriteString(Wr, "Warning: tutorial ");
				Texts.WriteString(Wr, name);
				Texts.WriteString(Wr, " not found");
				Texts.Append(Oberon.Log, Wr.buf)
			END
		END;
		RETURN il
	END Import;

	PROCEDURE PosToIdent(beg: LONGINT; VAR exp: BOOLEAN);
		VAR
			c: CHAR;
			pos: LONGINT;
	BEGIN
		exp := FALSE;
		pos := Texts.Pos(R);
		Texts.OpenReader(R, inText, beg);
		Texts.Read(R, ch);
		Ident(c);
		WHILE ~R.eot & (Texts.Pos(R) < pos) DO
			IF c = "*" THEN exp := TRUE END;
			Texts.Read(R, c)
		END;
		Texts.OpenReader(R, inText, pos-1);
		Texts.Read(R, ch)
	END PosToIdent;
	
	PROCEDURE EmptyOpt();
	BEGIN
		Get();
		IF sym = lprSy THEN
			Check(rprSy);
			Check(lbrSy)
		ELSIF sym # lbrSy THEN
			Mark(" {", " expected")
		END
	END EmptyOpt;
	
	(* "code-generating" for all commands *)
	PROCEDURE Chapters();
		VAR
			cl: Label;
			lk: Books0.Frame;
			i: Books0.ImpList;
			lname: ARRAY Books0.nameLen+1+Books0.identLen OF CHAR;
			name: ARRAY Books0.nameLen OF CHAR;
			ext: BOOLEAN;
			beg, begC, lev, lastLev, oldBegId, oldEndId, lastChap: LONGINT;
	BEGIN
		lastLev := 0;
		WHILE sym = chapterSy DO
			lev := 0;
			Get();
			IF sym = lprSy THEN
				Get();
				IF sym = plusSy THEN
					IF lastLev+1 < Books.maxSect THEN
						lev := lastLev+1
					ELSE
						lev := Books.maxSect-1;
						Mark("", "to deep chapter nesting")
					END;
					Check(rprSy)
				ELSIF sym = minusSy THEN
					IF lastLev > 0 THEN
						lev := lastLev-1
					ELSE
						lev := 0;
						Mark("", "negative levels not allowed")
					END;
					Check(rprSy)
				ELSIF sym = numberSy THEN
					IF number < Books.maxSect THEN
						lev := number
					ELSE
						lev := Books.maxSect-1;
						Mark("", "to deep chapter nesting")
					END;
					Check(rprSy)
				ELSIF sym = eqSy THEN
					lev := lastLev;
					Check(rprSy)
				ELSIF sym # rprSy THEN
					Mark("] ", " expected")
				ELSE
					lev := lastLev
				END;
				Check(lbrSy)
			ELSIF sym # lbrSy THEN
				Mark(" {", " expected")
			END;
			GetString(FALSE);
			Check(rbrSy);
			oldBegId := begId; oldEndId := endId;
			Get();
			IF sym = lbrSy THEN
				PosToIdent(begId, ext);
				GetString(FALSE);
				Check(rbrSy)
			ELSE
				ext := FALSE;
				ident := "";
				begId := oldBegId; endId := oldEndId;
				Texts.OpenReader(R, inText, oldPos-1);
				Texts.Read(R, ch)
			END;
			IF lev = 0 THEN
				Texts.Write(Wr, ".");
				Texts.Append(Oberon.Log, Wr.buf);
				lastChap := 0;
				DefChapter(ext)
			ELSE
				lastChap := curChap.text.len;
				DefSection(SHORT(lev), ext)
			END;
			lastLev := lev;
			sym := noSy;
			WHILE ~R.eot & (sym # chapterSy) DO
			Contents();
			IF sym = linkSy THEN
				EmptyOpt();
				IF GetName(lname) THEN
					GetBookName(lname, name, ident);
					i := Import(name);
					lk := DefExtLink(i, ident)
				ELSE
					COPY(lname, ident);
					lk := DefLink()
				END;
				Check(rbrSy);
				Check(lbrSy);
				GetString(FALSE);
				Texts.Save(inText, begId, endId, B);
				beg := curChap.text.len;
				Texts.Append(curChap.text, B);
				Expand(curChap.text, beg,  curChap.text.len);
				IF lk = NIL THEN
				ELSIF lk.mode = Books.note THEN
					MarkText(curChap.text, beg, curChap.text.len, Books.note, Books.formatText IN options);
					INCL(options, Books.usesnotes);
					Books0.AppendFrame(curChap.text, lk);
					IncObj(curChap)
				ELSE
					MarkText(curChap.text, beg, curChap.text.len, Books.link, Books.formatText IN options);
					Books0.AppendFrame(curChap.text, lk);
					IncObj(curChap)
				END;
				Check(rbrSy)
			ELSIF sym = labelSy THEN
				EmptyOpt();
				ext := FALSE;
				Check(identSy);
				Get();
				IF sym = starSy THEN
					ext := TRUE;
					Check(rbrSy)
				ELSIF sym # rbrSy THEN
					Mark(" }", " expected")
				END;
				cl := DefChapLabel(TRUE);
				cl.export := ext
			ELSIF sym = indexSy THEN
				beg := curChap.text.len;
				begC := beg;
				Get();
				ext := TRUE;
				IF sym = lprSy THEN
					REPEAT
						Get();
						IF sym = minusSy THEN
							ext := FALSE;
							Get()
						ELSIF sym = plusSy THEN
							ext := TRUE;
							Get()
						ELSIF sym = numberSy THEN
							IF number # 0 THEN
								Mark(" 0", " expected")
							END;
							begC := lastChap;
							Get()
						END
					UNTIL sym # commaSy;
					IF sym # rprSy THEN
						Mark(" ]", " expected")
					END;
					Check(lbrSy)
				ELSIF sym # lbrSy THEN
					Mark(" {", " expected")
				END;
				GetString(FALSE);
				IF ext THEN
					Texts.Save(inText, begId, endId, B);
					Texts.Append(curChap.text, B);
					Expand(curChap.text, beg, curChap.text.len)
				END;
				DefIndex(begC, Books.link);
				IF Books.formatText IN options THEN
					ChangeFont(curChap.text, Fonts.Default, BookDocs.textFont, beg, curChap.text.len)
				END;
				Check(rbrSy)
			ELSIF sym = callSy THEN
				EmptyOpt();
				begC := callText.len;
				GetString(FALSE);
				IF eol THEN
					Mark("", "eols not allowed in commands")
				END;
				Texts.Save(inText, begId, endId, B);
				beg := callText.len;
				Texts.Append(callText, B);
				Expand(callText, beg, callText.len);
				Texts.WriteLn(W);
				Texts.Append(callText, W.buf);
				Check(rbrSy);
				oldBegId := begId; oldEndId := endId;
				Get();
				IF sym = lbrSy THEN
					WHILE sym = lbrSy DO
						GetString(FALSE);
						Check(rbrSy);
						oldBegId := begId; oldEndId := endId;
						Get();
						IF sym = lbrSy THEN
							IF eol THEN
								Mark("", "eols not allowed in commands")
							END;
							Texts.Save(inText, begId, endId, B);
							beg := callText.len;
							Texts.Append(callText, B);
							Expand(callText, beg, callText.len);
							Texts.WriteLn(W);
							Texts.Append(callText, W.buf)
						ELSE
							begId := oldBegId; endId := oldEndId;
							Texts.OpenReader(R, inText, oldPos-1);
							Texts.Read(R, ch)
						END
					END
				ELSE
					begId := oldBegId; endId := oldEndId;
					Texts.OpenReader(R, inText, oldPos-1);
					Texts.Read(R, ch)
				END;
				Texts.Save(inText, begId, endId, B);
				beg := curChap.text.len;
				Texts.Append(curChap.text, B);
				Expand(curChap.text, beg, curChap.text.len);
				MarkText(curChap.text, beg, curChap.text.len, Books.call, Books.formatText IN options);
				DefCallGadgets(begC)
			END
			END
		END;
		IF ~R.eot THEN
			Mark("Chapter", " expected")
		END
	END Chapters;

(* sort the binary index-tree to a (flat) text *)
	PROCEDURE BuildIndex();
		VAR
			obj: Books0.LocFrame;
			beg, pos: LONGINT;
			pl: PosList;
			ch, lastCh: CHAR;
			R: Texts.Reader;
		PROCEDURE Sort(n: Node);
		BEGIN
			IF n # NIL THEN
				Sort(n.left);
				IF n.end > n.beg THEN
					Texts.Save(inText, n.beg, n.end, B);
					beg := curChap.text.len;
					Texts.Append(curChap.text, B);
					Expand(curChap.text, beg, curChap.text.len);
					IF n.pos IS NotePosList THEN
						MarkText(curChap.text, beg, curChap.text.len, Books.note, TRUE);
						Books0.NewLoc();
						obj := Objects.NewObj(Books0.LocFrame);
						obj.mode := Books.note;
						obj.pos1 := n.pos.pos;
						obj.pos2 := n.pos(NotePosList).pos2
					ELSE
						MarkText(curChap.text, beg, curChap.text.len, Books.link, TRUE);
						Books0.NewLoc();
						obj := Objects.NewObj(Books0.LocFrame);
						obj.mode := Books.link;
						obj.pos1 := n.pos.chapter.ind;
						obj.pos2 := n.pos.pos
					END;
					Books0.AppendFrame(curChap.text, obj);
					IncObj(curChap);
					IF n.pos.next # NIL THEN
						Texts.WriteLn(W);
						Texts.Write(W, Books.Tab);
						Texts.Append(curChap.text, W.buf);
						pl := n.pos;
						WHILE pl # NIL DO
							IF ~(pl IS NotePosList) THEN
							beg := curChap.text.len;
							Texts.WriteInt(W, pl.chapter.ind, 0);
							Texts.Write(W, ":");
							Texts.WriteInt(W, pl.pos, 0);
							IF pl.next # NIL THEN
								Texts.Write(W, ",")
							END;
							Texts.Append(curChap.text, W.buf);
							MarkText(curChap.text, beg, curChap.text.len, Books.link, TRUE);
							Books0.NewLoc();
							obj := Objects.NewObj(Books0.LocFrame);
							obj.mode := Books.link;
							obj.pos1 := pl.chapter.ind;
							obj.pos2 := pl.pos;
							Books0.AppendFrame(curChap.text, obj);
							IncObj(curChap);
							IF pl.next # NIL THEN
								Texts.Write(W, " ");
								Texts.Append(curChap.text, W.buf)
							END
							END;
							pl := pl.next
						END
					END;
					Texts.WriteLn(W);
					Texts.Append(curChap.text, W.buf)
				END;
				Sort(n.right)
			END
		END Sort;
	BEGIN
		ident := "Index"; begId := 0; endId := -1;
		DefChapter(FALSE);
		Texts.WriteString(W, "Index"); Texts.WriteLn(W);
		Texts.Append(curChap.text, W.buf);
		pos := curChap.text.len;
		MarkFnt(curChap.text, 0, pos, BookDocs.titleFont);
		Sort(root);
		Texts.WriteLn(W);
		Texts.Append(curChap.text, W.buf);
		expand := TRUE;
		Expand(curChap.text, 0, curChap.text.len);
		expand := FALSE;
		lastCh := 0X;
		Texts.OpenReader(R, curChap.text, 0);
		Texts.Read(R, ch);
		pos := 0;
		WHILE ~R.eot DO
			WHILE ~R.eot & ~((R.lib IS Fonts.Font) & (ch = Books.EOL)) DO
				Texts.Read(R, ch)
			END;
			pos := Texts.Pos(R);
			IF ~R.eot THEN
				Texts.Read(R, ch);
				IF (ch > " ") & (CAP(ch) # lastCh) THEN
					lastCh := CAP(ch);
					Texts.WriteLn(W);
					Texts.Write(W, lastCh);
					Texts.WriteLn(W);
					Texts.Insert(curChap.text, pos, W.buf);
					MarkFnt(curChap.text, pos+1, pos+2, BookDocs.sectionFonts[0]);
					Texts.OpenReader(R, curChap.text, pos+2);
					Texts.Read(R, ch)
				END
			END
		END
	END BuildIndex;

(* append the footnotes to the text-list *)
	PROCEDURE BuildFootnotes();
		VAR chap: Chapter;
	BEGIN
		NewChapter(chap);
		curChap.next := chap;
		curChap := chap;
		curChap.text := noteText
	END BuildFootnotes;
	
(* append the commands to the text-list *)
	PROCEDURE BuildCmds();
		VAR chap: Chapter;
	BEGIN
		NewChapter(chap);
		curChap.next := chap;
		curChap := chap;
		curChap.text := callText
	END BuildCmds;
	
(* flatten the contents-tree to a text *)
	PROCEDURE BuildContents();
		VAR
			text: Texts.Text;
		PROCEDURE Visit(n: SectNode);
			VAR nd: SectNode;
		BEGIN
			n.c.beg := text.len;
			IF n.desc # NIL THEN
				n.c.mode := Books0.node
			ELSE
				n.c.mode := Books0.leaf
			END;
			nd := n.desc;
			WHILE nd # NIL DO
				Books0.AppendFrame(text, nd.c);
				IncObj(contents);
				Texts.Write(W, Books.Tab);
				Texts.Append(text, W.buf);
				Texts.Append(text, nd.B);
				Texts.WriteLn(W);
				Texts.Append(text, W.buf);
				nd := nd.next
			END;
			n.c.end := text.len;
			nd := n.desc;
			WHILE nd # NIL DO
				Visit(nd);
				nd := nd.next
			END
		END Visit;
	BEGIN
		NEW(text); Texts.Open(text, "");
		Books0.AppendFrame(text, sectRoot.c);
		IncObj(contents);
		Texts.Append(text, sectRoot.B);
		Texts.WriteLn(W);
		Texts.Append(text, W.buf);
		Visit(sectRoot);
		contents.text := text
	END BuildContents;

(* start scanning/parsing; handels \BOok and \Note commands *)
	PROCEDURE Book();
		VAR
			pl: Label;
			beg, end: LONGINT;
			noteIndex: BOOLEAN;
	BEGIN
		width := BookDocs.W; heigth := BookDocs.H;
		options := {Books.formated, Books.resize};
		styleMode := {};
		Check(bookSy);
		Get();
		IF sym = lprSy THEN
			REPEAT
				Get();
				IF sym = minusSy THEN
					Check(identSy);
					IF CAP(ident[0]) = "F" THEN
						EXCL(options, Books.formated)
					ELSIF CAP(ident[0]) = "T" THEN
						EXCL(options, Books.formatText)
					ELSIF CAP(ident[0]) = "R" THEN
						EXCL(options, Books.resize)
					ELSE
						Mark("f, t or r", " expected")
					END;
					Get()
				ELSIF sym = plusSy THEN
					Check(identSy);
					IF CAP(ident[0]) = "F" THEN
						INCL(options, Books.formated)
					ELSIF CAP(ident[0]) = "T" THEN
						INCL(options, Books.formatText)
					ELSIF CAP(ident[0]) = "R" THEN
						INCL(options, Books.resize)
					ELSE
						Mark("f, t or r", " expected")
					END;
					Get()
				ELSIF sym = identSy THEN
					IF CAP(ident[0]) = "W" THEN
						Check(eqSy);
						Check(numberSy);
						width := SHORT(number)
					ELSIF CAP(ident[0]) = "H" THEN
						Check(eqSy);
						Check(numberSy);
						heigth := SHORT(number)
					ELSIF CAP(ident[0]) = "I" THEN
						INCL(options, Books.icon);
						Check(eqSy);
						IF GetName(iconStr) THEN
							IF Gadgets.FindPublicObj(iconStr) = NIL THEN
								Mark(iconStr, " icon not found")
							END
						END
					ELSIF CAP(ident[0]) = "L" THEN
						INCL(styleMode, TextGadgets.left)
					ELSIF CAP(ident[0]) = "M" THEN
						INCL(styleMode, TextGadgets.middle)
					ELSIF CAP(ident[0]) = "R" THEN
						INCL(styleMode, TextGadgets.right)
					ELSIF CAP(ident[0]) = "P" THEN
						INCL(styleMode, TextGadgets.pad)
					ELSE
						Mark("w, h, i, l, m, r, or p", " expected")
					END;
					Get()
				END
			UNTIL sym # commaSy;
			IF sym # rprSy THEN
				Mark(" ]", " expected")
			END;
			Check(lbrSy)
		ELSIF sym # lbrSy THEN
			Mark(" {", " expected")
		END;
		IF styleMode = {} THEN
			INCL(styleMode, TextGadgets.left)
		END;
		IF TextGadgets.left IN styleMode THEN
			INCL(options, Books.left)
		END;
		IF TextGadgets.middle IN styleMode THEN
			INCL(options, Books.middle)
		END;
		IF TextGadgets.right IN styleMode THEN
			INCL(options, Books.right)
		END;
		IF TextGadgets.pad IN styleMode THEN
			INCL(options, Books.pad)
		END;
		Check(identSy);
		IF error THEN RETURN END;
		COPY(ident, bookName);
		Texts.WriteString(Wr, "compiling: ");
		Texts.WriteString(Wr, ident);
		Texts.Append(Oberon.Log, Wr.buf);
		Check(rbrSy);
		Get();
		IF sym = lbrSy THEN
			GetString(FALSE);
			NewBook(endId > begId);
			Check(rbrSy);
			Check(bsSy)
		ELSE
			NewBook(FALSE);
			IF sym # bsSy THEN
				Mark(" \", " expected")
			END
		END;
		Get();
		WHILE sym = noteSy DO
			noteIndex := FALSE;
			Get();
			IF sym = lprSy THEN
				Get();
				IF sym = plusSy THEN
					noteIndex := TRUE;
					Check(rprSy)
				ELSIF sym = minusSy THEN
					noteIndex := FALSE;
					Check(rprSy)
				ELSIF sym # rprSy THEN
					Mark("] ", " expected")
				END;
				Check(lbrSy)
			ELSIF sym # lbrSy THEN
				Mark(" {", " expected")
			END;
			Check(identSy);
			pl := DefFootnoteLabel();
			beg := begId; end := endId;
			Get();
			IF sym = starSy THEN
				pl.export := TRUE;
				Check(rbrSy)
			ELSIF sym # rbrSy THEN
				Mark(" }", " expected")
			END;
			Check(lbrSy);
			GetString(TRUE);
			Check(rbrSy);
			InsertFootnote(pl);
			begId := beg; endId := end;
			IF noteIndex THEN
				DefIndex(pl.frame.pos1, Books.note)
			END;
			Check(bsSy);
			Get()
		END;
		IF Books.formatText IN options THEN
			ChangeFont(noteText, Fonts.Default, BookDocs.textFont, 0, noteText.len)
		END;
		Books0.StrConcat(bookName, ".Book");
		Chapters();
		IF ~error THEN
			BuildIndex();
			BuildCmds();
			BuildFootnotes();
			CheckLabels();
			IF ~error THEN
				BuildContents();
				IF ~error THEN
					RegisterBook()
				END
			END
		END
	END Book;
	
(* start compiling text T; update list in "Developer's Panel" *)
	PROCEDURE Parse(T: Texts.Text);
		VAR
			obj: Objects.Object;
			c: TextFields.Caption;
			l: Lists.Item;
			ll: Lists.List;
			t: Texts.Text;
		PROCEDURE CmpTextStr(t: Texts.Text; str: ARRAY OF CHAR): BOOLEAN;
			VAR
				R: Texts.Reader;
				ch: CHAR;
				i: INTEGER;
		BEGIN
			i := 0;
			Texts.OpenReader(R, t, 0);
			Texts.Read(R, ch);
			WHILE ~R.eot & (str[i] # 0X) & (ch = str[i]) DO
				Texts.Read(R, ch);
				INC(i)
			END;
			RETURN R.eot & (str[i] = 0X)
		END CmpTextStr;
	BEGIN
		IF (T = NIL) OR (T.len <= 0) THEN
			RETURN
		END;
		inText := T;
		error := FALSE;
		lastPos := -1;
		Texts.OpenReader(R, T, 0);
		Texts.Read(R, ch);
		WHILE ~R.eot & ~((ch = "\") & (R.lib IS Fonts.Font)) DO
			Texts.Read(R, ch)
		END;
		IF R.eot THEN
			Mark("", "unexpected end of text")
		ELSE
			Texts.Read(R, ch);
			Book();
			IF ~error & (Gadgets.context # NIL) THEN
				obj := Gadgets.FindObj(Gadgets.context, "fileList");
				IF (obj # NIL) & (obj IS Lists.List) THEN
					l := obj(Lists.List).items;
					WHILE (l # NIL) & (l.s # bookName) DO
						l := l.next
					END;
					IF l = NIL THEN
						NEW(t); Texts.Open(t, "");
						Texts.Write(W, Books.quote);
						Texts.WriteString(W, bookName);
						Texts.Write(W, Books.quote);
						Texts.Append(t, W.buf);
						Lists.InsertItems(obj(Lists.List), t, 0, t.len);
					END;
					obj := Gadgets.FindObj(Gadgets.context, "BookName");
					IF (obj # NIL) & (obj IS TextFields.Caption) THEN
						c := obj(TextFields.Caption);
						Books0.CutSuffix(bookName);
						IF CmpTextStr(c.text, bookName) THEN
							NEW(t); Texts.Open(t, "");
							obj := Gadgets.FindObj(Gadgets.context, "Notes");
							IF (obj # NIL) & (obj IS Lists.List) THEN
								ll := obj(Lists.List);
								ll.items := NIL;
								ll.beg := NIL;
								ll.pointed := NIL;
								ll.noitems := 0;
								Lists.InsertItems(ll, t, 0, 0)
							END;
							obj := Gadgets.FindObj(Gadgets.context, "Labels");
							IF (obj # NIL) & (obj IS Lists.List) THEN
								ll := obj(Lists.List);
								ll.items := NIL;
								ll.beg := NIL;
								ll.pointed := NIL;
								ll.noitems := 0;
								Lists.InsertItems(ll, t, 0, 0)
							END;
							Texts.Delete(c.text, 0, c.text.len);
							Texts.WriteString(W, "no tutorial");
							Texts.Append(c.text, W.buf)
						END
					END
				END
			END
		END
	END Parse;

	PROCEDURE GetMarked(VAR text: Texts.Text);
		VAR
			F, V: Display.Frame;
			L: Objects.LinkMsg;
	BEGIN
		text := NIL;
		F := Oberon.MarkedFrame();
		IF F = NIL THEN
			V := Oberon.MarkedViewer();
			IF (V # NIL) & (V.dsc # NIL) THEN
				F := V.dsc.next
			END
		END;
		IF F # NIL THEN
			L.id := Objects.get;
			L.name := "Model";
			L.obj := NIL;
			F.handle(F, L);
			IF (L.obj # NIL) & (L.obj IS Texts.Text) THEN
				text := L.obj(Texts.Text)
			END
		END
	END GetMarked;

(* compiling command; *, ^, ~ *)
	PROCEDURE Compile*;
		VAR
			S: Texts.Scanner;
			t: Texts.Text;
			beg, end, time, pos: LONGINT;
	BEGIN
		t := NIL;
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		pos := Texts.Pos(S);
		Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "*") THEN
			Texts.Scan(S);
			GetMarked(t);
			IF t # NIL THEN
				Parse(t)
			END;
			Oberon.Collect();
			RETURN
		END;
		IF (S.class = Texts.Char) & (S.c = "^") THEN
			Oberon.GetSelection(t, beg, end, time);
			IF (t # NIL) & (time > 0) THEN
				Texts.OpenScanner(S, t, beg);
				pos := Texts.Pos(S);
				Texts.Scan(S)
			END
		ELSE
			end := Oberon.Par.text.len
		END;
		IF S.class = Texts.Name THEN
			WHILE (S.class = Texts.Name) & (pos < end) DO
				NEW(t); Texts.Open(t, S.s);
				IF t.len > 0 THEN
					Parse(t)
				ELSE
					Texts.WriteString(Wr, S.s);
					Texts.WriteString(Wr, " not found");
					Texts.WriteLn(Wr);
					Texts.Append(Oberon.Log, Wr.buf)
				END;
				pos := Texts.Pos(S);
				Texts.Scan(S);
				Oberon.Collect()
			END
		END
	END Compile;

(* create a new TextDoc; used by "Developer's Panel" *)
	PROCEDURE NewTextDoc*;
		VAR T: Texts.Text;
	BEGIN
		NEW(T);
		Texts.Open(T, "");
		Texts.WriteString(Wr, "\Book{}{}");
		Texts.WriteLn(Wr);
		Texts.WriteString(Wr, "\Chapter{}");
		Texts.WriteLn(Wr);
		Texts.Append(T, Wr.buf);
		TextDocs.ShowText("", T, Display.Width DIV 3, Display.Height DIV 3)
	END NewTextDoc;
	
(* browser for tutorial-files; update lists in "Developer's Panel" *)
	PROCEDURE Browse*;
		VAR
			il: Books0.ImpList;
			el: Books0.ExtLabel;
			S: Texts.Scanner;
			doc: Documents.Document;
			obj: Objects.Object;
			t, tL, tN: Texts.Text;
			verbose, text: BOOLEAN;
			F: Files.File;
			R: Files.Rider;
			fix1, fix2: LONGINT;
			beg, end, time: LONGINT;
			name: ARRAY Books0.nameLen OF CHAR;
			Wr: Texts.Writer;
			lNotes, lLabels: Lists.List;
	BEGIN
		NEW(il); il.extLabels := NIL;
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(S);
		verbose := FALSE; text := FALSE;
		IF (S.class = Texts.Char) & (S.c = Oberon.OptionChar) THEN
			Texts.Scan(S);
			verbose := (S.class = Texts.Name) & (CAP(S.s[0]) = "V");
			text := (S.class = Texts.Name) & (CAP(S.s[0]) = "T");
			Texts.Scan(S);
			IF (S.class = Texts.Char) & (S.c = Oberon.OptionChar) THEN
				Texts.Scan(S);
				text := (S.class = Texts.Name) & (CAP(S.s[0]) = "T");
				Texts.Scan(S)
			END;
			text := text OR verbose
		END;
		IF S.class = Texts.Name THEN
			COPY(S.s, il.name)
		ELSIF (S.class =  Texts.Char) & (S.c = "^") THEN
			Oberon.GetSelection(t, beg, end, time);
			IF (t # NIL) & (time > 0) THEN
				Texts.OpenScanner(S, t, beg);
				Texts.Scan(S);
				IF S.class = Texts.Name THEN
					COPY(S.s, il.name)
				ELSE
					RETURN
				END
			ELSE
				RETURN
			END
		ELSE
			RETURN
		END;
		lNotes := NIL; lLabels := NIL;
		IF ~text & (Gadgets.context # NIL) & (Gadgets.context IS Panels.Panel) THEN
			obj := Gadgets.FindObj(Gadgets.context, "Notes");
			lNotes := obj(Lists.List);
			obj := Gadgets.FindObj(Gadgets.context, "Labels");
			lLabels := obj(Lists.List)
		END;
		IF (lNotes = NIL) OR (lLabels = NIL) THEN
			text := TRUE;
			lNotes := NIL;
			lLabels := NIL
		END;		
		Texts.OpenWriter(Wr);
		IF ~BookDocs.Import(il, TRUE) THEN
			Texts.WriteString(Wr, il.name);
			Texts.WriteString(Wr, " not found");
			Texts.WriteLn(Wr);
			Texts.Append(Oberon.Log, Wr.buf);
			RETURN
		END;
		IF text THEN
		Texts.SetFont(Wr, BookDocs.textFont);
		TextDocs.NewDoc();
		doc := Objects.NewObj(Documents.Document);
		doc.W := BookDocs.W; doc.H := BookDocs.H;
		COPY(il.name, doc.name);
		Books0.StrConcat(doc.name, "Def");
		obj := Gadgets.CreateObject("TextGadgets.New");
		Documents.Init(doc, obj(Gadgets.Frame));
		t := doc.dsc(TextGadgets.Frame).text;
		IF verbose THEN
			F := Files.Old(il.name);
			Files.Set(R, F, 0);
			IF ~BookDocs.SkipHeader(R) THEN
				Files.Close(F);
				RETURN
			END;
			Files.ReadLInt(R, fix1);
			Files.ReadLInt(R, fix2);
			Files.ReadLInt(R, beg);
			Files.ReadString(R, name);
			IF name # "" THEN
				Texts.WriteString(Wr, "Imports: ")
			END;
			WHILE name # "" DO
				Texts.WriteString(Wr, name);
				Files.ReadString(R, name);
				IF name # "" THEN
					Texts.WriteString(Wr, ", ")
				END
			END;
			Texts.WriteLn(Wr);
			Texts.Append(t, Wr.buf);
			Files.Close(F)
		END;
		el := il.extLabels;
		WHILE el # NIL DO
			IF el.mode = Books.note THEN
				Texts.WriteString(Wr, "\Note{")
			ELSIF  el.mode = Books.link THEN
				Texts.WriteString(Wr, "\Label{")
			END;
			Texts.WriteString(Wr, el.name);
			Texts.Write(Wr, "}");
			IF verbose THEN
				IF el.mode = Books.note THEN
					Texts.Write(Wr, "{");
					Texts.Append(t, Wr.buf);
					Texts.Save(il.notes, el.pos1, el.pos2, B);
					Texts.Append(t, B);
					Texts.Write(Wr, "}")
				ELSIF el.mode = Books.link THEN
					Texts.WriteString(Wr, " on page number: ");
					Texts.WriteInt(Wr, el.pos1, 0);
					Texts.WriteString(Wr, ", at page position: ");
					Texts.WriteInt(Wr, el.pos2, 0)
				END
			END;
			Texts.WriteLn(Wr);
			Texts.Append(t, Wr.buf);
			el := el.next
		END;
		Desktops.ShowDoc(doc)
		ELSE
			lNotes.items := NIL;
			lNotes.beg := NIL;
			lNotes.pointed := NIL;
			lNotes.noitems := 0;
			lLabels.items := NIL;
			lLabels.beg := NIL;
			lLabels.pointed := NIL;
			lLabels.noitems := 0;
			obj := Gadgets.FindObj(Gadgets.context, "BookName");
			IF (obj # NIL) & (obj IS TextFields.Caption) THEN
				WITH obj: TextFields.Caption DO
					Texts.Delete(obj.text, 0, obj.text.len);
					Books0.CutSuffix(il.name);
					Texts.WriteString(Wr, il.name);
					Texts.Append(obj.text, Wr.buf)
				END
			END;
			NEW(tN); NEW(tL);
			Texts.Open(tN, ""); Texts.Open(tL, "");
			el := il.extLabels;
			WHILE el # NIL DO
				IF el.mode = Books.note THEN
					Texts.Write(Wr, Books.quote);
					Texts.WriteString(Wr, el.name);
					Texts.Write(Wr, Books.quote);
					Texts.WriteLn(Wr);
					Texts.Append(tN, Wr.buf)
				ELSIF el.mode = Books.link THEN
					Texts.Write(Wr, Books.quote);
					Texts.WriteString(Wr, el.name);
					Texts.Write(Wr, Books.quote);
					Texts.WriteLn(Wr);
					Texts.Append(tL, Wr.buf)
				END;
				el := el.next
			END;
			Lists.InsertItems(lNotes, tN, 0, tN.len);
			Lists.InsertItems(lLabels, tL, 0, tL.len)
		END
	END Browse;		

(* insert command at text-selection; used by "Developer's Panel" command iconizer *)
	PROCEDURE InsertCmd*;
		VAR
			S: Texts.Scanner;
			t: Texts.Text;
			R: Texts.Reader;
			Wr: Texts.Writer;
			beg, end, time: LONGINT;
			ch: CHAR;
	BEGIN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(S);
		IF S.class IN {Texts.Name, Texts.String} THEN
			t := NIL;
			Oberon.GetSelection(t, beg, end, time);
			IF (t # NIL) & (time > 0) & (beg < t.len) & (end <= t.len) THEN
				Texts.OpenReader(R, t, beg);
				Texts.Read(R, ch);
				IF R.lib IS Fonts.Font THEN
					Texts.OpenWriter(Wr);
					Texts.SetFont(Wr, R.lib(Fonts.Font));
					IF S.class = Texts.Name THEN
						Texts.Write(Wr, "}");
						Texts.Insert(t, end, Wr.buf);
						Texts.WriteString(Wr, "\Link{");
						Texts.WriteString(Wr, S.s);
						Texts.WriteString(Wr, "}{");
						Texts.Insert(t, beg, Wr.buf)
					ELSE
						IF (S.s = "\Link") OR (S.s = "\Note") THEN
							Texts.WriteString(Wr, "}{ }")
						ELSE
							Texts.Write(Wr, "}")
						END;
						Texts.Insert(t, end, Wr.buf);
						Texts.WriteString(Wr, S.s);
						Texts.Write(Wr, "{");
						Texts.Insert(t, beg, Wr.buf)
					END
				END
			END
		END
	END InsertCmd;

BEGIN
	Texts.OpenWriter(W);
	Texts.OpenWriter(Wr);
	NEW(B);
	Texts.OpenBuf(B)
END BookCompiler.