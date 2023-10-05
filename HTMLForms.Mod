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

MODULE HTMLForms;	(** portable *)
	IMPORT Objects, Display, Fonts, Texts, Oberon, Display3, Attributes, Gadgets, Lists, Strings, Links, HTMLDocs, TextGadgets,
		HyperDocs;

(** HTML 3.0 Fill-Out form support
	[HTMLTags]
	FORM=HTMLForms.NewFORM
	INPUT=HTMLForms.NewINPUT
	SELECT=HTMLForms.NewSELECT
	TEXTAREA=HTMLForms.NewTEXTAREA
*)

	PROCEDURE *FORM(VAR S: HTMLDocs.Scanner; on: BOOLEAN);
		VAR
			P: HTMLDocs.Page;
			attr, method: ARRAY 64 OF CHAR;
			obj: Objects.Object;
			curForm: HTMLDocs.Form;
			key: LONGINT;
			s: HyperDocs.LinkScheme;
	BEGIN
		P := S.page; HTMLDocs.CloseA(P);
		IF on THEN
			method := "GET"; key := HyperDocs.UndefKey;
			HTMLDocs.NewForm(); curForm := Objects.NewObj(HTMLDocs.Form);
			HTMLDocs.WriteObj(P, curForm);
			Links.SetLink(P, "CurForm", curForm);
			WHILE HTMLDocs.NextAttr(S, attr) DO
				IF attr = "METHOD" THEN
					IF CAP(S.value[0]) = "G" THEN
						method := "GET"
					ELSIF CAP(S.value[0]) = "P" THEN
						method := "POST"
					ELSIF CAP(S.value[0]) = "M" THEN
						method := "MAILTO"
					ELSE
						COPY(S.value, method)
					END
				ELSIF attr = "ACTION" THEN
					IF method = "Authorization" THEN
						key := P.base.dockey
					ELSE
						key := HyperDocs.BuildKey(P.base, S.value)
					END
				END
			END;
			s := HyperDocs.LinkSchemeByKey(key);
			IF (s # NIL) & (s.prefix = "mailto") THEN
				method := "MAILTO"
			END;
			obj := Gadgets.CreateObject("BasicGadgets.NewString");
			Attributes.SetString(obj, "Value", method);
			HTMLDocs.AddFormObj(P, curForm, obj, "@METHOD", FALSE, FALSE);
			obj := Gadgets.CreateObject("BasicGadgets.NewInteger");
			Attributes.SetInt(obj, "Value", key);
			HTMLDocs.AddFormObj(P, curForm, obj, "@ACTION", FALSE, FALSE)
		ELSE
			Links.SetLink(P, "CurForm", NIL)
		END
	END FORM;

	PROCEDURE GetButCap(attrs: HTMLDocs.TagAttr; obj: Objects.Object; cap: ARRAY OF CHAR);
		VAR
			attr: HTMLDocs.TagAttr;
			dsr, w, h: INTEGER;
	BEGIN
		attr := HTMLDocs.FindAttr(attrs, "ALT");
		IF attr # NIL THEN
			Attributes.SetString(obj, "Caption", attr.value);
			COPY(attr.value, cap)
		ELSE
			Attributes.SetString(obj, "Caption", cap)
		END;
		Display3.StringSize(cap, Fonts.Default, w, h, dsr);
		IF obj(Display.Frame).W < (w+8) THEN
			obj(Display.Frame).W := w+8
		END
	END GetButCap;

	PROCEDURE *INPUT(VAR S: HTMLDocs.Scanner; on: BOOLEAN);
		VAR
			P: HTMLDocs.Page;
			attrs, attr: HTMLDocs.TagAttr;
			typ, name, str: ARRAY 32 OF CHAR;
			value: ARRAY 512 OF CHAR;
			obj, obj2: Objects.Object;
			curForm: HTMLDocs.Form;
			val: LONGINT;
			rval, min, max: LONGREAL;
			y: LONGREAL;
	BEGIN
		IF on THEN
			P := S.page; Links.GetLink(S.page, "CurForm", obj);
			IF (obj = NIL) OR ~(obj IS HTMLDocs.Form) THEN
				Texts.WriteString(HTMLDocs.Wr, "not within a form");
				Texts.WriteLn(HTMLDocs.Wr);
				Texts.Append(Oberon.Log, HTMLDocs.Wr.buf)
			ELSE
				curForm := obj(HTMLDocs.Form);
				HTMLDocs.GetAttrs(S, attrs); attr := HTMLDocs.FindAttr(attrs, "TYPE");
				IF attr # NIL THEN
					Strings.Upper(attr.value, typ);
					IF (typ = "FILE") OR (typ = "SCRIBBLE") THEN
						typ := "TEXT"
					END
				ELSE
					typ := "TEXT"
				END;
				attr := HTMLDocs.FindAttr(attrs, "NAME");
				IF attr # NIL THEN
					COPY(attr.value, name)
				ELSE
					name := ""
				END;
				attr := HTMLDocs.FindAttr(attrs, "VALUE");
				IF attr # NIL THEN
					COPY(attr.value, value)
				ELSE
					value := ""
				END;
				IF (typ = "TEXT") OR (typ = "PASSWORD") THEN
					IF typ = "PASSWORD" THEN
						obj := Gadgets.CreateObject("PasswordFields.New");
						Attributes.SetString(obj, "FormElem", "PASSWORD")
					ELSE
						obj := Gadgets.CreateObject("TextFields.NewTextField")
					END;
					Attributes.SetString(obj, "Value", value);
					attr := HTMLDocs.FindAttr(attrs, "MAXLENGTH");
					IF attr # NIL THEN
						Strings.StrToInt(attr.value, val);
						Attributes.SetInt(obj, "MaxLen", val)
					END;
					attr := HTMLDocs.FindAttr(attrs, "SIZE");
					IF attr # NIL THEN
						Strings.StrToInt(attr.value, val);
						WITH obj: Gadgets.Frame DO
							IF 6*val > obj.W THEN
								obj.W := SHORT(6*val)
							END
						END
					END;
					HTMLDocs.AddFormObj(P, curForm, obj, name, TRUE, TRUE)
				ELSIF typ = "CHECKBOX" THEN
					obj := Gadgets.CreateObject("BasicGadgets.NewCheckBox");
					Attributes.SetString(obj, "YesVal", value);
					Attributes.SetBool(obj, "Value", HTMLDocs.FindAttr(attrs, "CHECKED") # NIL);
					HTMLDocs.AddFormObj(P, curForm, obj, name, TRUE, TRUE)
				ELSIF typ = "RADIO" THEN
					obj := Gadgets.CreateObject("BasicGadgets.NewCheckBox");
					WITH obj: Gadgets.Frame DO
						obj2 := HTMLDocs.FindFormObj(curForm, name);
						IF obj2 = NIL THEN
							obj.obj := Gadgets.CreateObject("BasicGadgets.NewInteger");
							Attributes.SetInt(obj.obj, "Value", -1);
							Attributes.SetInt(obj, "SetVal", 0);
							HTMLDocs.AddFormObj(P, curForm, obj.obj, "", TRUE, FALSE)
						ELSE
							obj.obj := obj2(Gadgets.Frame).obj;
							Attributes.GetInt(obj2, "SetVal", val);
							Attributes.SetInt(obj, "SetVal", val+1)
						END;
						Attributes.SetString(obj, "YesVal", value);
						IF HTMLDocs.FindAttr(attrs, "CHECKED") # NIL THEN
							Attributes.SetBool(obj, "Value", TRUE);
							HTMLDocs.RememberValue(obj.obj)
						END;
						HTMLDocs.AddFormObj(P, curForm, obj, name, FALSE, TRUE)
					END
				ELSIF typ = "HIDDEN" THEN
					obj := Gadgets.CreateObject("BasicGadgets.NewString");
					Attributes.SetString(obj, "Value", value);
					HTMLDocs.AddFormObj(P, curForm, obj, name, TRUE, FALSE)
				ELSIF typ = "RESET" THEN
					obj := Gadgets.CreateObject("BasicGadgets.NewButton");
					Attributes.SetString(obj, "Cmd", "HTMLDocs.Reset");
					IF value = "" THEN
						value := "Reset"
					END;
					GetButCap(attrs, obj, value);
					HTMLDocs.AddFormObj(P, curForm, obj, "@RESET", FALSE, TRUE)
ELSIF (typ = "SUBMIT") OR (typ = "IMAGE") THEN
					obj := Gadgets.CreateObject("BasicGadgets.NewButton");
attr := HTMLDocs.FindAttr(attrs, "CMD");
IF attr # NIL THEN
	Attributes.SetString(obj, "Cmd", attr.value)
ELSE
	Attributes.SetString(obj, "Cmd", "HTMLDocs.SubmitQuery")
END;
					Attributes.SetString(obj, "Query", "FORM");
					obj2 := HTMLDocs.FindFormObj(curForm, "@METHOD");
					Attributes.GetString(obj2, "Value", str);
					Attributes.SetString(obj, "Method", str);
					IF name = "" THEN
						name := "@SUBMIT"
					END;
					IF value = "" THEN
						value := "Submit"
					ELSIF name # "@SUBMIT" THEN
						Attributes.SetString(obj, "SubmitVal", value)
					END;
					GetButCap(attrs, obj, value);
					HTMLDocs.AddFormObj(P, curForm, obj, name, FALSE, TRUE)
(*ELSIF typ = "IMAGE" THEN
(* same as submit, but SRC is the reference to the image *)*)

				ELSIF typ = "RANGE" THEN
					obj := Gadgets.CreateObject("BasicGadgets.NewSlider");
					attr := HTMLDocs.FindAttr(attrs, "MIN");
					IF attr # NIL THEN
						Strings.StrToReal(attr.value, min)
					ELSE
						Attributes.GetLongReal(obj, "Min", min)
					END;
					attr := HTMLDocs.FindAttr(attrs, "MAX");
					IF attr # NIL THEN
						Strings.StrToReal(attr.value, max)
					ELSE
						Attributes.GetLongReal(obj, "Max", max)
					END;
					IF value # "" THEN
						Strings.StrToReal(value, rval)
					ELSE
						rval := (min+max) / 2
					END;
					Attributes.SetLongReal(obj, "Min", min);
					Attributes.SetLongReal(obj, "Max", max);
					Attributes.SetLongReal(obj, "Value", rval);
					IF (max-min) > 200 THEN
						obj(Gadgets.Frame).W := 200
					ELSIF (max-min) < 40 THEN
						obj(Gadgets.Frame).W := 40
					ELSE
						obj(Gadgets.Frame).W := SHORT(ENTIER(max-min))
					END;
					obj(Gadgets.Frame).H := 20;
					HTMLDocs.AddFormObj(P, curForm, obj, name, TRUE, TRUE)
				ELSIF typ = "INT" THEN
					obj := Gadgets.CreateObject("TextFields.NewTextField");
					WITH obj: Gadgets.Frame DO
						obj.obj := Gadgets.CreateObject("BasicGadgets.NewInteger");
						Strings.StrToInt(value, val);
						Attributes.SetInt(obj.obj, "Value", val);
						attr := HTMLDocs.FindAttr(attrs, "SIZE");
						IF attr # NIL THEN
							Strings.StrToInt(attr.value, val);
							Attributes.SetInt(obj, "MaxLen", val)
						END;
						HTMLDocs.AddFormObj(P, curForm, obj.obj, "", TRUE, FALSE)
					END;
					HTMLDocs.AddFormObj(P, curForm, obj, name, FALSE, TRUE)
				ELSIF typ = "FLOAT" THEN
					obj := Gadgets.CreateObject("TextFields.NewTextField");
					WITH obj: Gadgets.Frame DO
						obj.obj := Gadgets.CreateObject("BasicGadgets.NewReal");
						Strings.StrToReal(value, y);
						Attributes.SetLongReal(obj.obj, "Value", y);
						HTMLDocs.AddFormObj(P, curForm, obj.obj, "", TRUE, FALSE)
					END;
					HTMLDocs.AddFormObj(P, curForm, obj, name, FALSE, TRUE)
				ELSE
					Texts.WriteString(HTMLDocs.Wr, "INPUT TYPE=");
					Texts.WriteString(HTMLDocs.Wr, typ);
					Texts.WriteString(HTMLDocs.Wr, " not supported");
					Texts.WriteLn(HTMLDocs.Wr);
					Texts.Append(Oberon.Log, HTMLDocs.Wr.buf)
				END
			END;
			HTMLDocs.WriteSpace(P)
		END
	END INPUT;

	PROCEDURE *SELECT(VAR S: HTMLDocs.Scanner; on: BOOLEAN);
		VAR
			P: HTMLDocs.Page;
			obj: Objects.Object;
			attrs, attr: HTMLDocs.TagAttr;
			val, i: LONGINT;
			list: Lists.List;
			item: Lists.Item;
			litem: HTMLDocs.Item;
			curForm: HTMLDocs.Form;
			str: ARRAY 8 OF CHAR;
			done: BOOLEAN;
	BEGIN
		P := S.page; Links.GetLink(S.page, "CurForm", obj);
		IF (obj = NIL) OR ~(obj IS HTMLDocs.Form) THEN
			Texts.WriteString(HTMLDocs.Wr, "not within a form");
			Texts.WriteLn(HTMLDocs.Wr);
			Texts.Append(Oberon.Log, HTMLDocs.Wr.buf);
			RETURN
		END;
		IF on THEN
			curForm := obj(HTMLDocs.Form);
			obj := Gadgets.CreateObject("Lists.NewList"); list := obj(Lists.List);
			Attributes.SetString(obj, "FormElem", "SELECT");
			Attributes.SetBool(obj, "Sorted", FALSE);
			list.W := 150; list.H := 100;
			HTMLDocs.GetAttrs(S, attrs);
			attr := HTMLDocs.FindAttr(attrs, "SIZE");
			IF attr # NIL THEN
(* Strings.StrToInt(attr.value, val); list.H := SHORT(val*14) *)
			END;
			attr := HTMLDocs.FindAttr(attrs, "NAME");
			IF attr # NIL THEN
				HTMLDocs.AddFormObj(P, curForm, list, attr.value, FALSE, TRUE)
			ELSE
				HTMLDocs.AddFormObj(P, curForm, list, "", FALSE, TRUE)
			END;
			Attributes.SetBool(list, "MultiSel", HTMLDocs.FindAttr(attrs, "MULTIPLE") # NIL);
			WHILE ~S.end & (S.class # HTMLDocs.CloseTag) DO
				HTMLDocs.Next(S)
			END;
			S.state := HTMLDocs.TextHtml; HTMLDocs.Next(S);
			WHILE ~S.end & (S.class # HTMLDocs.OpenTag) DO
				HTMLDocs.Next(S)
			END;
			done := TRUE;
			WHILE done & (S.class IN {HTMLDocs.OpenTag, HTMLDocs.OpenEndTag}) DO
				S.state := HTMLDocs.InTag; HTMLDocs.Next(S);
				on := S.class # HTMLDocs.OpenEndTag;
				IF ~on THEN
					HTMLDocs.Next(S)
				END;
				IF S.class = HTMLDocs.Value THEN
					Strings.Upper(S.value, S.value);
					IF S.value = "OPTION" THEN
						NEW(litem);
						IF on THEN
							INC(list.noitems); item := list.items;
							WHILE (item # NIL) & (item.next # NIL) DO
								item := item.next
							END;
							litem.next := NIL; litem.prev := item;
							IF item = NIL THEN
								list.items := litem; list.beg := litem
							ELSE
								item.next := litem
							END
						END;
						HTMLDocs.GetAttrs(S, attrs);
						litem.sel := HTMLDocs.FindAttr(attrs, "SELECTED") # NIL;
						litem.oldSel := litem.sel;
						attrs := HTMLDocs.FindAttr(attrs, "VALUE");
						IF attrs # NIL THEN
							COPY(attrs.value, litem.value); litem.hasVal := TRUE
						ELSE
							litem.value := ""; litem.hasVal := FALSE
						END;
						WHILE ~S.end & (S.class # HTMLDocs.CloseTag) DO
							HTMLDocs.Next(S)
						END; S.state := HTMLDocs.TextHtml;
						i := 0; HTMLDocs.Next(S);
						WHILE ~S.end & (S.class IN {HTMLDocs.Character, HTMLDocs.WhiteSpace, HTMLDocs.CharRef}) DO
							IF i < 63 THEN
								IF S.class = HTMLDocs.Character THEN
									litem.s[i] := S.char
								ELSIF S.class = HTMLDocs.CharRef THEN
									HTMLDocs.CharRefStr(P, S, str); litem.s[i] := 0X;
									Strings.Append(litem.s, str);
									i := 0;
									WHILE litem.s[i] # 0X DO
										INC(i)
									END; DEC(i)
								ELSE
									litem.s[i] := " "
								END;
								INC(i)
							END;
							HTMLDocs.Next(S)
						END;
						litem.s[i] := 0X
					ELSE
						done := FALSE
					END
				ELSE
					done := FALSE
				END
			END;
			IF S.class = HTMLDocs.OpenTag THEN
				S.state := HTMLDocs.InTag
			END;
			Attributes.GetBool(list, "MultiSel", done);
			IF (list # NIL) & ~done THEN
				val := 0;
				item := list.items;
				WHILE item # NIL DO
					IF item.sel THEN
						INC(val)
					END;
					item := item.next
				END;
				IF val = 0 THEN
					item := list.items;
					IF item # NIL THEN
						item.sel := TRUE
					END
				END
			END
		END
	END SELECT;

	PROCEDURE *TEXTAREA(VAR S: HTMLDocs.Scanner; on: BOOLEAN);
		VAR
			P: HTMLDocs.Page;
			obj: Objects.Object;
			attrs, attr: HTMLDocs.TagAttr;
			curForm: HTMLDocs.Form;
			val: LONGINT;
			pre: BOOLEAN;
	BEGIN
		P := S.page; Links.GetLink(S.page, "CurForm", obj);
		IF (obj = NIL) OR ~(obj IS HTMLDocs.Form) THEN
			Texts.WriteString(HTMLDocs.Wr, "not within a form");
			Texts.WriteLn(HTMLDocs.Wr);
			Texts.Append(Oberon.Log, HTMLDocs.Wr.buf);
			RETURN
		END;
		IF on THEN
			curForm := obj(HTMLDocs.Form);
			obj := Gadgets.CreateObject("TextGadgets.New");
			WITH obj: TextGadgets.Frame DO
				obj.W := 200; obj.H := 80;
				HTMLDocs.GetAttrs(S, attrs);
				attr := HTMLDocs.FindAttr(attrs, "ROWS");
				IF attr # NIL THEN
					Strings.StrToInt(attr.value, val);
					IF val*14 > obj.H THEN
						obj.H := SHORT(val*14)
					END
				END;
				attr := HTMLDocs.FindAttr(attrs, "COLS");
				IF attr # NIL THEN
					Strings.StrToInt(attr.value, val);
					IF val*6 > obj.W THEN
						obj.W := SHORT(val*6)
					END
				END;
				Attributes.SetString(obj, "FormElem", "TEXTAREA");
				attr := HTMLDocs.FindAttr(attrs, "NAME");
				IF attr # NIL THEN
					HTMLDocs.AddFormObj(P, curForm, obj, attr.value, FALSE, TRUE)
				ELSE
					HTMLDocs.AddFormObj(P, curForm, obj, "", FALSE, TRUE)
				END;
				WHILE ~S.end & (S.class # HTMLDocs.CloseTag) DO
					HTMLDocs.Next(S)
				END; S.state := HTMLDocs.TextHtml; pre := S.pre; S.pre := TRUE; HTMLDocs.Next(S);
				Texts.Append(P.T, P.W.buf);
				WHILE ~S.end & (S.class IN {HTMLDocs.Character, HTMLDocs.WhiteSpace, HTMLDocs.CharRef}) DO
					IF S.class = HTMLDocs.Character THEN
						Texts.Write(P.W, S.char)
					ELSIF S.class = HTMLDocs.CharRef THEN
						HTMLDocs.WriteCharRef(P, S)
					ELSE
						Texts.Write(P.W, " ")
					END;
					HTMLDocs.Next(S)
				END;
				Texts.Append(obj.text, P.W.buf);
				S.state := HTMLDocs.InTag; HTMLDocs.Next(S); S.pre := pre;
				IF S.class = HTMLDocs.OpenEndTag THEN
					HTMLDocs.Next(S)
				END
			END
		END
	END TEXTAREA;

	PROCEDURE *InitForms(P: HTMLDocs.Page);
	BEGIN
		Links.SetLink(P, "CurForm", NIL)
	END InitForms;

	PROCEDURE *Dummy(P: HTMLDocs.Page);
	BEGIN
	END Dummy;

	PROCEDURE NewFORM*;
		VAR e: HTMLDocs.ExtTag;
	BEGIN
		NEW(e);
		e.handle := FORM;
		e.start := InitForms; e.stop := InitForms;
		HTMLDocs.newTag := e
	END NewFORM;

	PROCEDURE NewINPUT*;
		VAR e: HTMLDocs.ExtTag;
	BEGIN
		NEW(e);
		e.handle := INPUT;
		e.start := Dummy; e.stop := Dummy;
		HTMLDocs.newTag := e
	END NewINPUT;

	PROCEDURE NewSELECT*;
		VAR e: HTMLDocs.ExtTag;
	BEGIN
		NEW(e);
		e.handle := SELECT;
		e.start := Dummy; e.stop := Dummy;
		HTMLDocs.newTag := e
	END NewSELECT;

	PROCEDURE NewTEXTAREA*;
		VAR e: HTMLDocs.ExtTag;
	BEGIN
		NEW(e);
		e.handle := TEXTAREA;
		e.start := Dummy; e.stop := Dummy;
		HTMLDocs.newTag := e
	END NewTEXTAREA;

END HTMLForms.

System.Set HTMLTags FORM := HTMLForms.NewFORM ~
System.Set HTMLTags INPUT := HTMLForms.NewINPUT ~
System.Set HTMLTags SELECT := HTMLForms.NewSELECT ~

<FORM METHOD="POST" ACTION="http://www.webtechs.com/cgi-bin/html-check.pl">
<INPUT NAME="recommended" VALUE="0" TYPE="hidden">
<INPUT NAME="level" VALUE="Mozilla" TYPE="hidden">
<INPUT NAME="input" VALUE="0" TYPE="hidden">
<INPUT NAME="esis" VALUE="0" TYPE="hidden">
<INPUT NAME="render" VALUE="0" TYPE="hidden">
<INPUT NAME="URLs" VALUE="http://www.webtechs.com/html-val-svc/about.html" TYPE="hidden">
<INPUT TYPE="image" SRC="http://www.webtechs.com/html-val-svc/images/valid_html.mcom.gif">
</FORM>

