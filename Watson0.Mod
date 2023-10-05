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

MODULE Watson0;	(** portable *)	(** PS	/	 	/	OP2-Version *)

	IMPORT Modules, OPT, OPS, OPM, Files, Objects, Texts, Oberon, Gadgets, Out;

	CONST
	(* CONST used to read symbol file *)
		symFileId = 0BBX; 
		
		(*object modes *)
		Var = 1; VarPar = 2; Con = 3; Fld = 4; Typ = 5; LProc = 6; XProc = 7;
		SProc = 8; CProc = 9; IProc = 10; Mod = 11; TProc = 13; Head = 12;
	
		(* structure forms *)
		Undef = 0; Byte = 1; Bool = 2; Char = 3; SInt = 4; Int = 5; LInt = 6;
		Real = 7; LReal = 8; Set = 9; String = 10; NilTyp = 11; NoTyp = 12;
		Pointer = 13; ProcTyp = 14; Comp = 15;
			
		(* composite structure forms *)
		Basic = 1; StaticArr = 2; SDynArr = 3; DynArr = 4; OpenArr = 5; Record = 6;

		(* visibility of objects *)
		internal = 0; external = 1; externalR = 2;
	

	(* CONST used to read object file *)
		(* block ids *)
		objFileId = 0BBX; EntryId = 082X; CmdId = 083X; PtrId = 084X; ImpId = 085X;
		LinkId = 086X; DataId = 087X; CodeId = 088X; TypeId = 089X; RefId = 08BX;
		VarEntryId = 08CX;

		HeaderSize = 34;

		(* obj-file version *)
		Version	=	0AFX;


	(* other CONST *)
		(* text link colors *)
		TextCol = 15; LinkCol = 3; ImportCol = 1;

		(* commands *)
		ObjCmd = "Watson.ShowObj "; ModCmd = "Watson.ShowDef "; GotoCmd = "Watson.Goto ";

	VAR
	(* global vars *)
		W: Texts.Writer;
		options*: ARRAY 12 OF CHAR;	(** options: ['x' | 'd'] *)(* set by Watson.GetArgs and appended at a control's cmd *)
		expandTypes,	(* show base type(s) of record definition *)
		showAdr: BOOLEAN;	(* show adresses, entry number of object *)
		Hex: ARRAY 17 OF CHAR;	(* array of hex digits *)

	(* vars used by symbol file reader *)
		curObj: OPT.Object;	(* current object in process *)
		syspos: LONGINT;	(* text pos where to write imported modules *)
		sysImported,	(* indicates whether SYSTEM is imported or not *)
		first,	(* FALSE: keyword ['CONST' | 'TYPE' | 'VAR'] has already been written to text *)
		showObj: BOOLEAN;	(* TRUE: only one object is showen *)


	(* *************** AUX. PROCEDURES *************** *)

	(* ---------------------- string funktions ----------------------- *)

	PROCEDURE Append (VAR d: ARRAY OF CHAR; s: ARRAY OF CHAR);	(* appends string s to string d *)
		VAR i, j: INTEGER; ch: CHAR;
	BEGIN
		i := 0; WHILE d[i] # 0X DO INC(i) END;
		j := 0; REPEAT ch := s[j]; d[i] := ch; INC(i); INC(j) UNTIL ch = 0X
	END Append;

	PROCEDURE AppendCh (VAR d: ARRAY OF CHAR; ch: CHAR);	(* appends char ch to string d *)
		VAR i: INTEGER;
	BEGIN
		i := 0; WHILE d[i] # 0X DO INC(i) END;
		d[i]:= ch; d[i+1]:= 0X
	END AppendCh;

	(* ---------------------- output procedures ----------------------- *)

	PROCEDURE Str (s: ARRAY OF CHAR);	(* writes string s to W *)
	BEGIN Texts.WriteString(W, s) 
	END Str;
	
	PROCEDURE Ch (ch: CHAR);	(* writes char ch to W *)
	BEGIN Texts.Write(W, ch) 
	END Ch;
	
	PROCEDURE Num (i: LONGINT);	(* writes number i to W *)
	BEGIN Texts.WriteInt(W, i, 0);
	END Num;
	
	PROCEDURE Hexa(i: LONGINT; short: BOOLEAN);	(* writes number i to W as a hex. number *)
	BEGIN
		IF ~short THEN	(* fully 32 bit number *)
			Ch(Hex[i DIV 10000000H]); i:= i MOD 10000000H;
			Ch(Hex[i DIV 1000000H]); i:= i MOD 1000000H;
			Ch(Hex[i DIV 100000H]); i:= i MOD 100000H;
			Ch(Hex[i DIV 10000H]); i:= i MOD 10000H
		END;
		Ch(Hex[i DIV 1000H]); i:= i MOD 1000H;
		Ch(Hex[i DIV 100H]); i:= i MOD 100H;
		Ch(Hex[i DIV 10H]); Ch(Hex[i MOD 10H])
	END Hexa;
	
	PROCEDURE Ln;	(* writes a line feed to W *)
	BEGIN Texts.WriteLn(W) 
	END Ln;
	
	PROCEDURE Indent (i: INTEGER);	(* writes i tabs to W *)
	BEGIN WHILE i > 0 DO Ch(9X); DEC(i) END
	END Indent;

	PROCEDURE Control(name, cmd, par: ARRAY OF CHAR);
	(* writes a control object to W. Name will be set to name and command cmd+options+par *)
		VAR obj: Objects.Object; oldLib: Objects.Library; A: Objects.AttrMsg;
	BEGIN
		obj:= Gadgets.CreateObject("TextGadgets.NewControl");
		IF obj # NIL THEN
			IF par # "" THEN
				A.id:= Objects.set; A.name:= "Cmd"; A.class:= Objects.String; A.res:= -1;
				COPY(cmd, A.s);
				IF options # "" THEN AppendCh(A.s, Oberon.OptionChar); Append(A.s, options); AppendCh(A.s, " ") END;
				Append(A.s, par);
				obj.handle(obj, A)
			END;
			IF name # "" THEN Gadgets.NameObj(obj, name) END;
			Texts.WriteObj(W, obj);
		END
	END Control;

	PROCEDURE Identifier(name: ARRAY OF CHAR);	(* writes a string name and a control to W *)
		VAR i, j: INTEGER;
	BEGIN 
		Str(name);
		IF showObj THEN	(* cut module qualifier *)
			i:= 0; REPEAT INC(i) UNTIL (name[i]=".") OR (name[i]= 0X);
			IF name[i] # 0X THEN
				INC(i); j:= 0; REPEAT name[j]:= name[i]; INC(i); INC(j) UNTIL name[j]=0X
			END
		END;
		Control(name, "", "");
	END Identifier;

	(* *************** SYMBOL FILE *************** *)

	(* ---------------------- write sybol file info ----------------------- *)

	PROCEDURE WriteConstValue (obj: OPT.Object);	(* writes the value of a constant object *)
		VAR i: INTEGER; y: LONGINT; s: SET;
	BEGIN
		y:= obj.conval.intval;
		CASE obj.typ^.form OF
			| SInt, Int, LInt:  Texts.WriteInt(W, y, 0)
			| Real:  Texts.WriteReal(W, SHORT(obj.conval.realval), 15)
			| LReal:  Texts.WriteLongReal(W, obj.conval.realval, 20)
			| Bool:  IF y = 0 THEN Str("FALSE") ELSE Str("TRUE") END 
			| Char:
				IF (y >= 32) & (y <= 126) THEN Ch(22X); Ch(CHR(y)); Ch(22X)
				ELSE i := SHORT(y DIV 16);
					IF i > 0 THEN
						IF i > 9 THEN Ch("0") END;
						Ch(Hex[i])
					END;
					Ch(Hex[y MOD 16]); Ch("X")
				END
			| Set:
				Ch("{"); s := obj.conval.setval; y := 0;
				WHILE y <= MAX(SET) DO
					IF y IN s THEN Texts.WriteInt(W, y, 0); EXCL(s, y); IF s # {} THEN Str(", ") END END;
					INC(y)
				END;
				Ch("}")
			| NilTyp:  Str("NIL")
			| String: Ch(22X); Str(obj.conval.ext^); Ch(22X) 
		END
	END WriteConstValue;

	PROCEDURE ^ WriteType (typ: OPT.Struct; i: INTEGER);

	PROCEDURE WriteBase (typ: OPT.Struct);	(* writes the base type of a record *)
		VAR base: OPT.Struct;
	BEGIN
		base := typ.BaseTyp;
		IF base # NIL THEN
			Str(" ( "); WriteType(typ.BaseTyp, 0);
			IF expandTypes THEN WriteBase(typ.BaseTyp) END;
			Str(" )");
		END
	END WriteBase;
	
	PROCEDURE WriteFields (VAR obj: OPT.Object; i: INTEGER; recField: BOOLEAN);
	(* writes field list of a proc. or record: all variables of same type *)
		VAR typ: OPT.Struct; mode: INTEGER;
	BEGIN
		typ := obj.typ; mode := obj.mode;
		LOOP
			IF recField & showAdr THEN Ch("["); Num(obj.adr); Str("] ") END;
			Str(obj.name);
			IF (obj.vis = externalR) THEN Ch("-") END;
			obj := obj.link;
			IF (obj = NIL) OR (obj.mode # mode) OR (obj.typ # typ) THEN EXIT END;
			Str(", ");
		END;
		Str(": "); WriteType(typ, i + 1)
	END WriteFields;
	
	PROCEDURE WriteParams (param: OPT.Object; resTyp: OPT.Struct);	(* writes parameter list of a procedure *)
	BEGIN
		IF (param # NIL) OR (resTyp # OPT.notyp) THEN
			Str(" (");
			WHILE (param # NIL) DO
				IF param.mode = VarPar THEN Str("VAR ") END;
				IF param.name = "" THEN
					WriteType(param.typ, 0);
					param := param.link;
					IF param # NIL THEN Str(", ") END
				ELSE
					WriteFields(param, 0, FALSE);
					IF param # NIL THEN Str("; ") END
				END
			END;
			Ch(")");
		END;
		IF resTyp # OPT.notyp THEN Str(": "); WriteType(resTyp, 0) END
	END WriteParams;
	
	PROCEDURE WriteProc (obj: OPT.Object);	(* writes a procedure *)
	BEGIN
		IF showAdr & (obj.mode # CProc) THEN Ch("["); Num(obj.adr); Str("] ") END;
		Str("PROCEDURE ");
		Identifier(obj.name);
		WriteParams(obj.link, obj.typ);
		Ch(";")
	END WriteProc;
	
	PROCEDURE WriteTProcs (obj: OPT.Object; i: INTEGER);	(* writes a type bound procedure *)
		VAR firstpar: OPT.Object;
	BEGIN
		IF obj # NIL THEN
			WriteTProcs(obj.left, i);
			IF obj.mode = TProc THEN
				Indent(i);
				IF showAdr THEN
					Ch("["); Num(obj.adr MOD 10000H); Str(", "); Num(obj.adr DIV 10000H); Str("] ")
				END;
				Str("PROCEDURE "); firstpar := obj.link;
				IF firstpar.typ.strobj.link2 = obj THEN Str("& ")  END;
				Str(obj.name);
				WriteParams(firstpar^.link, obj.typ);
				Ch(";"); Ln;
			END;
			WriteTProcs(obj.right, i);
		END;
	END WriteTProcs;
	
	PROCEDURE WriteFieldList (obj: OPT.Object; i: INTEGER);	(* writes all record field lists, exept type bound proc.*)
	BEGIN
		WHILE (obj # NIL) & (obj.mode = Fld) DO
			IF obj.vis # internal THEN Indent(i); WriteFields(obj, i, TRUE); Ch(";"); Ln
			ELSE obj:= obj.link
			END;
		END
	END WriteFieldList;
	
	PROCEDURE WriteInstVars (typ: OPT.Struct; i: INTEGER; extlev: LONGINT);	(* writes a record definition *)
	BEGIN
		IF typ # NIL THEN
			IF expandTypes & (extlev > 0) THEN
				WriteInstVars(typ.BaseTyp, i, extlev);
				Indent(i); Str("(* "); Str(OPT.modules[typ.mno-1].name); Ch("."); Str(typ.strobj.name); Str(" *)"); Ln
			END;
			WriteFieldList(typ.link, i);
			WriteTProcs(typ.link, i)
		END
	END WriteInstVars;

	PROCEDURE WriteForm (typ: OPT.Struct; i: INTEGER);	(* writes a type *)
	BEGIN
		IF (typ.form = Comp) & (typ.comp = Record) THEN
			Str("RECORD"); WriteBase(typ);
			IF showAdr THEN Str(" [size = "); Num( typ.size); Ch("]") END;
			IF typ.link # NIL THEN Ln; WriteInstVars(typ, i, typ.extlev); Indent(i - 1) ELSE Ch(" ") END;
			Str("END")
		ELSIF (typ.form = Comp) & (typ.comp = StaticArr) THEN
			Str("ARRAY "); Num(typ.n); Str(" OF "); WriteType(typ.BaseTyp, i)
		ELSIF (typ.form = Comp) & (typ.comp = OpenArr) THEN
			Str("ARRAY OF "); WriteType(typ.BaseTyp, i)
		ELSIF (typ.form = Comp) & (typ.comp = DynArr) THEN
			Str("ARRAY * OF "); WriteType(typ.BaseTyp, i)
		ELSIF typ.form = Pointer THEN
			Str("POINTER TO ");
			IF typ.BaseTyp.ptr = typ THEN  WriteForm(typ.BaseTyp, i)  ELSE  WriteType(typ.BaseTyp, i)  END
		ELSIF typ.form = ProcTyp THEN
			Str("PROCEDURE");
			WriteParams(typ.link, typ.BaseTyp)
		END
	END WriteForm;

	PROCEDURE WriteType(typ: OPT.Struct; i: INTEGER);	(* writes a type declaration *)
		VAR cmd, par: ARRAY 32 OF CHAR; makeLink: BOOLEAN; ch: CHAR;
	BEGIN
		IF (typ.strobj # NIL) & (typ.strobj.name # "") THEN
			makeLink:= FALSE;
			IF (typ = OPT.bytetyp) (*OR (typ = OPT.sysptrtyp)*) THEN
				Str("SYSTEM."); sysImported := TRUE;
			ELSIF (typ.mno >= 1) & (ABS(typ.strobj.vis) > internal) THEN
				(* type def. is in an other module or is visible within this module => make a link *)
				makeLink:= TRUE;
				Texts.SetColor(W, LinkCol);
				IF (typ.mno >= 1) OR showObj THEN
					(* write module qualifier because object is not in cur. module or showObj option is on *)
					Str(OPT.modules[typ.mno(*-1*)].name); Ch(".")
				END 
			END;
			Str(typ.strobj.name);
			IF makeLink THEN
				IF (typ.mno >= 1) THEN	(* definition is in an other module *)
					cmd:= ObjCmd;
					COPY(OPT.modules[typ.mno(*-1*)].name, par); AppendCh(par, "."); Append(par, typ.strobj.name)
				ELSE
					IF ~showObj OR (curObj.link = typ.strobj) OR (curObj = typ.strobj) THEN
						(* type def. is in the same text *)
						cmd:= GotoCmd; par:= ""
					ELSE
						cmd:= ObjCmd;
						COPY(OPT.modules[typ.mno(*-1*)].name, par); AppendCh(par, ".")
					END;
					Append(par, typ.strobj.name)
				END;
				Control("", cmd, par); Texts.SetColor(W, TextCol)
			END
		ELSE (* anonymous type *) WriteForm(typ, i)
		END
	END WriteType;
	
	PROCEDURE WriteObject(obj: OPT.Object; mode: INTEGER);	(* writes any object as given mode *)
		VAR h: OPT.Object; name: ARRAY 64 OF CHAR;
	BEGIN
		curObj:= obj;	(* set cur. object in process *)
		IF mode = Con THEN
			IF first THEN Indent(1); Str("CONST"); Ln; first := FALSE END;
			Indent(2);
			Identifier(obj.name);
			Str(" = "); WriteConstValue(obj); Ch(";");
			Ln
		ELSIF mode = Var THEN
			IF first THEN Indent(1); Str("VAR"); Ln; first := FALSE END;
			Indent(2);
			IF showAdr THEN Str(" ["); Num(obj.adr); Str("] "); END;
			Identifier(obj.name);
			IF obj.vis  = externalR THEN Ch("-") END;
			Str(": "); WriteType(obj.typ, 3); Ch(";");
			Ln
		ELSIF (mode = Typ) & (obj.vis > internal) THEN	(* write a type object just if it is vivible *)
			IF first THEN Indent(1); Str("TYPE"); Ln; first := FALSE END;
			Indent(2);
			IF showObj THEN COPY(OPT.modules[obj.typ.mno (*-1*)].name, name); AppendCh(name, ".") 
			ELSE name:= ""
			END;
			Append(name, obj.name);
			Identifier(name);
			Str(" = ");
			IF obj.typ.strobj # obj THEN WriteType(obj.typ, 0)  (* alias type *)
			ELSE WriteForm(obj.typ, 3)
			END;
			Ch(";"); Ln;
			IF obj.link # NIL THEN (* group of two types (POINTER TO ... & ...Desc) and not alias *)
				h:= obj.link;
				IF ABS(h^.vis) > internal THEN
					Indent(2);
					IF showObj THEN COPY(OPT.modules[h.typ.mno (*-1*)].name, name); AppendCh(name, ".") 
					ELSE name:= ""
					END;
					Append(name, h.name);
					Identifier(name);
					Str(" = "); WriteForm(h.typ, 3); Ch(";"); Ln
				END
			END
		ELSIF mode IN {XProc, CProc} THEN first:= FALSE; Indent(1); WriteProc(obj); Ln
		END
	END WriteObject;
		
	PROCEDURE WriteImports;	(* write imported modules *)
		VAR i: INTEGER;
	BEGIN
		i:= 1; (* assume that OPT.modules[0] is "self" *)
		first := TRUE;
		WHILE i < OPT.nofmod DO
			IF first THEN Indent(1); Str("IMPORT "); first := FALSE; syspos := W.buf.len ELSE Str(", ") END;
			IF i MOD 11 = 0 THEN Ln; Indent(2) END;
			Texts.SetColor(W, ImportCol);
			Str(OPT.modules[i].name);
			Texts.SetColor(W, TextCol);
			Control("", ModCmd, OPT.modules[i].name);
			IF showAdr THEN Str(" ["); Texts.WriteHex(W, OPT.modules[i]^.adr); Ch("]"); END;
			INC(i)
		END;
		IF ~first THEN Ch(";"); Ln; Ln END;
	END WriteImports;
	
	PROCEDURE WriteScope(obj: OPT.Object; mode: INTEGER);	(* writes all objects of given mode *)
		PROCEDURE Scope (obj: OPT.Object; mode: INTEGER);
		BEGIN
			IF obj # NIL THEN
				Scope(obj.left, mode);
				IF obj.mode = mode THEN WriteObject(obj, mode) END;
				Scope(obj.right, mode);
			END;
		END Scope;	
	BEGIN first := TRUE;
		Scope(obj, mode);
		IF ~first THEN Ln END
	END WriteScope;

	PROCEDURE WriteModule;	(* writes a module definition *)
		VAR anchor: OPT.Object;
	BEGIN sysImported:= FALSE;
		anchor:= OPT.topScope.right;
		Str("DEFINITION "); Str(anchor.name);
		IF showAdr THEN Str(" ["); Texts.WriteHex(W, OPT.modules[0].adr); Ch("]") END;
		Ch(";"); Ln; Ln;
		syspos := W.buf.len;
		WriteImports;
		WriteScope(anchor.scope, Con);
		WriteScope(anchor.scope, Typ);
		WriteScope(anchor.scope, Var);
		WriteScope(anchor.scope, XProc);
		Str("END "); Str(anchor.name); Ch("."); Ln
	END WriteModule;

	PROCEDURE MakeText(T: Texts.Text);	(* appends writer W and inserts import list *)
	BEGIN
		Texts.Append(T, W.buf);
		IF sysImported & ~showObj THEN
			IF OPT.nofmod > 1 THEN Str("SYSTEM, ") ELSE Ch(09X); Str("IMPORT SYSTEM;"); Ln; Ln END;
			Texts.Insert(T, syspos, W.buf);
		END
	END MakeText;

	(* ------------------------ read & prepare symbols ------------------- *)

	PROCEDURE Find (name: ARRAY OF CHAR; VAR obj: OPT.Object);	(* looks for object name in the OPT top scope *)
	BEGIN obj := OPT.topScope.right.scope;
		LOOP
			IF obj = NIL THEN RETURN
			ELSIF name < obj.name THEN obj := obj.left
			ELSIF name > obj.name THEN obj := obj.right
			ELSE RETURN
			END
		END
	END Find;

	PROCEDURE FindPointer(name: ARRAY OF CHAR; VAR obj: OPT.Object);	(* find pointer to record name *)
	
		PROCEDURE FindP(name: ARRAY OF CHAR; root: OPT.Object; VAR obj: OPT.Object);
			VAR typ: OPT.Struct;
		BEGIN
			obj:= root;
			IF root = NIL THEN RETURN END;
			IF (root.mode = Typ) & (root.typ.form = Pointer) THEN
				typ:= root.typ.BaseTyp;
				IF (typ.strobj # NIL) & (typ.strobj.name = name) THEN RETURN END
			ELSE
				FindP(name, root.left, obj);
				IF obj = NIL THEN FindP(name, root.right, obj) END
			END
		END FindP;

	BEGIN FindP(name, OPT.topScope.right.scope, obj)
	END FindPointer;
	
	PROCEDURE GroupTypes (obj: OPT.Object);
	(* groups pointer and its corresponding record, so they can be writter together *)
		VAR typ: OPT.Struct; h: OPT.Object;
	BEGIN
		IF obj # NIL THEN
			GroupTypes(obj.left);
			IF (obj.mode = Typ) THEN typ:= obj.typ;
				IF typ.form = Pointer THEN
					IF typ.BaseTyp.strobj # NIL THEN (* named base type *)
						Find(typ.BaseTyp.strobj.name, h);
						IF (h # NIL) & (h.typ.mno = 1) THEN
							obj.link:= h;
							h.vis := -h.vis	(* prevent normal output of this type *)
						END;
					END;
				END
			END;
			GroupTypes(obj.right)
		END
	END GroupTypes;

	PROCEDURE ReadSym (VAR mod, fileName: ARRAY OF CHAR): BOOLEAN;	(* read the symbol file by calling OPT.Import *)
		VAR T: Texts.Text; RR: Texts.Reader; f: Files.File; R: Files.Rider;
			selfname, file: OPS.Name; ch: CHAR;
	BEGIN
		f:= Files.Old(fileName);
		IF (f # NIL) OR (mod = "SYSTEM") THEN
			IF mod = "SYSTEM" THEN Out.String("definition of SYSTEM not available"); Ln; RETURN FALSE
			ELSE Files.Set(R, f, 0); Files.Read(R, ch)
			END;
			IF ch = symFileId THEN
				NEW(T); Texts.Open(T, ""); Texts.OpenReader(RR, T, 0); OPM.Init({}, RR, Oberon.Log);
				COPY(mod, selfname); COPY(fileName, file);
				OPS.Init; OPT.Init(selfname, {}); OPT.OpenScope(0, NIL);
				OPT.Import(selfname, selfname, file);
				GroupTypes(OPT.topScope.right.scope);
				RETURN TRUE
			ELSE
				Out.String("-- not a symbol file"); Out.Ln;
				RETURN FALSE
			END
		ELSE
			Out.String("--  symbol file not found"); Out.Ln;
			RETURN FALSE
		END
	END ReadSym;


	(* *************** OBJECT FILE *************** *)

	(* ---------------------- write object info ----------------------- *)
	
	PROCEDURE Commands(F: Files.File; VAR modName: ARRAY OF CHAR);	(* writes all commands of this module  *)
	VAR R: Files.Rider; name: ARRAY 32 OF CHAR; ve, key, ref, symSize: LONGINT;
			i, c, e, nofentry, nofcmds: INTEGER; ch: CHAR;
	BEGIN Files.Set(R, F, 0);
		(* check if it is an object file *)
		Files.Read(R, ch);
		IF ch # objFileId THEN Out.String("not a object file"); RETURN END;

		(* check if it has right version *)
		Files.Read(R, ch);
		IF ch # Version THEN Out.String("object file has wrong version"); RETURN END;

		Files.ReadNum(R, symSize); Files.Set(R, F, Files.Pos(R) + symSize); (* skip symbol file *)
		
		Files.ReadBytes(R, ref, 4);	(* ref block pos *)
		Files.ReadBytes(R, nofentry, 2);	(* # entries *)
		Files.ReadBytes(R, nofcmds, 2);	(* # commands *)

		Files.Set(R, F, Files.Pos(R)+18);	(* skip rest *)
		REPEAT Files.Read(R, ch) UNTIL ch = 0X;	(* skip module name *)

		(* skip entry block *)
		Files.Read(R, ch); IF ch # EntryId THEN Out.String("corrunpted object file"); RETURN END;
		WHILE nofentry > 0 DO Files.ReadBytes(R, e, 2); DEC(nofentry) END;

		(* write commands *)
		Files.Read(R, ch); IF ch # CmdId THEN Out.String("corrunpted object file"); RETURN END;
		Str("DEFINITION "); Str(modName);
		IF showAdr THEN Str(" ["); Hexa(key, FALSE); Ch("]") END;
		Ch(";"); Ln;
		WHILE nofcmds > 0 DO
			i:= 0; REPEAT Files.Read(R, ch); name[i]:= ch; INC(i) UNTIL ch = 0X;
			Files.ReadBytes(R, c, 2);
			Ch(09X);	(* TAB *)
			IF showAdr THEN Ch("["); Hexa(c, TRUE); Str("] ") END;
			Str(modName); Ch("."); Str(name); Control(name, "", ""); Ln;
			DEC(nofcmds)
		END;
		Str("END "); Str(modName); Ch(".")
	END Commands;


	(* *************** INTERFACE *************** *)

	PROCEDURE SetOptions;	(* parses variable options and sets corresponding 'flags' *)
		VAR i: INTEGER;
	BEGIN
		expandTypes:= FALSE; showAdr:= FALSE; i:= 0;
		WHILE options[i] # 0X DO
			IF options[i] = "x" THEN expandTypes:= TRUE
			ELSIF options[i] = "d" THEN showAdr:= TRUE
			END;
			INC(i)
		END
	END SetOptions;

	(** converts a symbol file *)
	PROCEDURE ShowDef*(VAR mod: ARRAY OF CHAR; T: Texts.Text);
		VAR file: ARRAY 64 OF CHAR;
	BEGIN
		COPY(Modules.extension, OPM.extension);
		SetOptions; COPY(mod, file); Append(file, Modules.extension);
		Out.String("reading "); Out.String(file); Out.Ln;
		IF ReadSym(mod, file) THEN COPY(mod, file);
			showObj := FALSE;
			WriteModule; MakeText(T)
		END
	END ShowDef;

	(** converts a symbol file, only shows the desired object *)
	PROCEDURE ShowObj*(VAR mod, objName: ARRAY OF CHAR; T: Texts.Text);
		VAR obj, pObj: OPT.Object; file: ARRAY 64 OF CHAR;
	BEGIN
		COPY(Modules.extension, OPM.extension);
		SetOptions; COPY(mod, file); Append(file, Modules.extension);
		Out.String("reading "); Out.String(file); Out.Ln;
		IF ReadSym(mod, file) THEN
			Find(objName, obj);
			IF obj # NIL THEN COPY(mod, file);
				IF obj.vis < 0 THEN (* is a pair of types *)
					FindPointer(obj.name, pObj);	(* look for a corresponding pointer *)
					IF pObj # NIL THEN obj:= pObj; COPY(obj.name, objName) END
				END;
				showObj := TRUE; first := TRUE;
				WriteObject(obj, obj.mode); MakeText(T)
			ELSE Out.String("-- '"); Out.String(objName); Out.String("' not found"); Out.Ln
			END
		END
	END ShowObj;

	(** converts an object file and extracts commands *)
	PROCEDURE ShowCmd*(VAR file: ARRAY OF CHAR;  T: Texts.Text);
		VAR F: Files.File; fileName: ARRAY 64 OF CHAR;
	BEGIN
		COPY(Modules.extension, OPM.extension);
		SetOptions; COPY(file, fileName); Append(fileName, Modules.extension);
		F:= Files.Old(fileName);
		IF F # NIL THEN
			Out.String("reading "); Out.String(fileName); Out.Ln;
			Commands(F, file); Texts.Append(T, W.buf)
		END
	END ShowCmd;

BEGIN
	Hex := "0123456789ABCDEF";
	Texts.OpenWriter(W)
END Watson0.
