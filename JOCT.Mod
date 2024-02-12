(*
	Juice(TM), Version 1.1

	Copyright (c) 1996-1997 Regents of the University of California. 
	All rights reserved.

	This software was developed as part of the Juice project by the research 
	group of Prof. Dr. M. Franz at the University of California, Irvine.
	http://www.ics.uci.edu/~juice

	Redistribution and use in source and binary forms are permitted
	provided that:
	
	(a)	the above copyright notice and this paragraph are duplicated 
			in all such forms and provided that any documentation,
			advertising materials, and other materials related to such
			distribution and use acknowledge that the software was 
			developed by the University of California, Irvine.  
		
	(b)	all interface changes and all conversions of this software to other 
			platforms agree with style and content of Juice. In case of doubt
			juice-request@ics.uci.edu shall be asked for consent.
	
	The name of the University may not be used to endorse or promote products derived
	from this software without specific prior written permission.
	
	THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
	IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
	WARRANTIES OF MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

	"Juice" is a trademark owned by the Regents of the University of California
*)

MODULE JOCT;	(* NW, RC 6.3.89 / tk 30.6.96 *)

	(* Juice Compiler - Symbol Table Handler *)

	IMPORT
		SYS:=SYSTEM, Files, OPS := JOCS, OPM := JOCM;

	CONST
		MaxConstLen* = OPS.MaxStrLen; 
		DefMaxImport=64; DefMaxStruct=32; DefMaxReimp=32;

	(* object modes *)
		Var = 1; VarPar = 2; Con = 3; Fld = 4; Typ = 5; LProc = 6; XProc = 7;
		SProc = 8; CProc = 9; Mod = 11; Head = 12; TProc = 13; Alias=14;

	(* structure forms *)
		Undef = 0; Byte = 1; Bool = 2; Char = 3; SInt = 4; Int = 5; LInt = 6;
		Real = 7; LReal = 8; Set = 9; String = 10; NilTyp = 11; NoTyp = 12;
		Pointer = 13; ProcTyp = 14; Comp = 15;
		
	(* composite structure forms *)
		Basic = 1; Array = 2; DynArr = 3; Record = 4;

	(*function number*)
		haltfn = 0; newfn = 1; absfn = 2; capfn = 3; ordfn = 4;
		entierfn = 5; oddfn = 6; minfn = 7; maxfn = 8; chrfn = 9;
		shortfn = 10; longfn = 11; sizefn = 12; incfn = 13; decfn = 14;
		inclfn = 15; exclfn = 16; lenfn = 17; copyfn = 18; ashfn = 19; assertfn = 32;
		
	(*SYSTEM function number*)
		adrfn = 20; ccfn = 21; lshfn = 22; rotfn = 23;
		getfn = 24; putfn = 25; getrfn = 26; putrfn = 27;
		bitfn = 28; valfn = 29; sysnewfn = 30; movefn = 31;
		
	(* module visibility of objects *)
		internal = 0; external = 1; externalR = 2;

		isRedef = 2;	
		
	(*symbol tags*)
		SFtypBool=01H; SFtypChar=02H; SFtypSInt=03H; SFtypInt=04H; SFtypLInt=05H;
		SFtypReal=06H; SFtypLReal=07H; SFtypSet=08H; SFtypString=09H; SFtypNoTyp=0AH; SFtypNilTyp=0BH;
		SFtypByte=0CH; SFtypSptr=0DH;
		SFmod1=0EH; SFmod31=2CH; SFmodOther=2DH;
		SFtypDynArr=2EH; SFtypArray=2FH; SFtypPointer=30H; SFtypRecord=31H; SFtypProcTyp=32H;
		SFsysflag=33H; SFinvisible=34H; SFreadonly=35H; SFleaf=36H;
		SFconst=37H; SFvar=38H;
		SFlproc=39H; SFxproc=3AH; SFcproc=3BH; SFtproc=3CH;
		SFalias=3DH; SFtyp=3EH; SFend=3FH;

	(* history *)
		inserted = 0;	same = 1;	removed = 3;	modified = 4;


	TYPE
		Const* = POINTER TO ConstDesc;
		Object* = POINTER TO ObjDesc;
		Module*=POINTER TO ModDesc;
		Struct* = POINTER TO StrDesc;
		Node* = POINTER TO NodeDesc;
		ConstExt* = POINTER TO OPS.String;

		ConstDesc* = RECORD
			ext*: ConstExt;	(* string or code for code proc *)
			intval*: LONGINT;	(* constant value or adr, proc par size, text position or least case label *)
			intval2*: LONGINT;	(* string length, proc var size or larger case label *)
			setval*: SET;	(* constant value, procedure body present or "ELSE" present in case *)
			realval*: LONGREAL	(* real or longreal constant value *)
		END;

		ObjDesc* = RECORD
			left*, right*, link*, scope*: Object;
			name*: OPS.Name;
			leaf*: BOOLEAN;
			mode*, mnolev*: SHORTINT;	(* mnolev < 0 -> mno = -mnolev *)
			vis*: SHORTINT;	(* 0: internal; 1: external; 2: externalR *)
			typ*: Struct;
			conval*: Const;
			adr*, linkadr*: LONGINT;
			nxtobj*, sibling*: Object; par: BOOLEAN; inited*, used*: BOOLEAN; fp*: LONGINT; history*: SHORTINT;
		END ;

		StructArr=POINTER TO ARRAY OF Struct;
		ModArr=POINTER TO ARRAY OF Module;
		ModDesc*=RECORD (ObjDesc)
			publics*: Object; directImp*: BOOLEAN;
			nofimp: INTEGER; import: ModArr;
			nofstr: INTEGER; struct: StructArr;
			nofreimp: INTEGER; reimp: StructArr;
		END;

		StrDesc* = RECORD
			form*, comp*, mno*, extlev*: SHORTINT;
			ref*: INTEGER;  align*, sysflag*: SHORTINT;
			n*, size*, tdadr*, offset*, txtpos*: LONGINT;
			BaseTyp*: Struct;
			link*, strobj*: Object; fpdone*, sref*, oref*: INTEGER;
			pvused*, pbused*: BOOLEAN; fp*, pvfp*, pbfp*: LONGINT;
		END ;
		
		NodeDesc* = RECORD
			left*, right*, link*: Node;
			class*, subcl*: SHORTINT;
			readonly*: BOOLEAN;
			typ*: Struct;
			obj*: Object;
			conval*: Const;
			global*: BOOLEAN; up*, down*: Node; ref*: LONGINT; flag*, subflg*: SHORTINT	(*Backend*)
		END ;
		
	VAR
		topScope*, objects*: Object;
		undftyp*, bytetyp*, booltyp*, chartyp*, sinttyp*, inttyp*, linttyp*,
		realtyp*, lrltyp*, settyp*, stringtyp*, niltyp*, notyp*, sysptrtyp*, ptrtyp*: Struct;
		SYSimported*: BOOLEAN;
		nofmod*: SHORTINT; modules*: ModArr;	(*global for each module being compiled*)
		nofemod*: SHORTINT; emodules*: ModArr; modNo*: INTEGER;	(*global for each module being compiled*)
		universe, syslink: Object;
		
		strucForm: ARRAY SFtypProcTyp+1 OF SHORTINT;	(*forms of structures*)
		strucComp: ARRAY SFtypProcTyp+1 OF SHORTINT;	(*forms of structures*)
		predefStruct: ARRAY SFtypSptr+1 OF Struct;	(*predefined types*)
		strucFormSF: ARRAY Comp+1 OF SHORTINT;	(*forms of structures*)
		strucCompSF: ARRAY Comp+1 OF SHORTINT;	(*forms of structures*)

		export: BOOLEAN; exp: ARRAY Alias+1 OF Object; nofstruc: INTEGER;
		newSF, extSF, symNew, symExtended, sfpresent, impSelf, expGlobal: BOOLEAN;
		typSize*: PROCEDURE (typ: Struct; allocDesc: BOOLEAN);


	PROCEDURE err(n: INTEGER);
	BEGIN OPM.err(n)
	END err;
	
	PROCEDURE Close*;	(* garbage collection *)
		VAR i: INTEGER;
	BEGIN	topScope:=NIL; objects:=NIL; 
		i:=0; WHILE i<LEN(modules^) DO modules[i]:=NIL; INC(i) END;
		i:=0; WHILE i<LEN(emodules^) DO emodules[i]:=NIL; INC(i) END;
		i:=0; WHILE i<Alias+1 DO exp[i]:=NIL; INC(i) END;
		nofmod:=0; nofemod:=0;
	END Close;
	
	PROCEDURE NewMod(): Module;
		VAR M: Module;
	BEGIN
		NEW(M); 
		NEW(M.struct, DefMaxStruct); 
		NEW(M.reimp, DefMaxReimp);
		NEW(M.import, DefMaxImport);
		RETURN M
	END NewMod;
	
	PROCEDURE NewConst*(): Const;
		VAR const: Const;
	BEGIN NEW(const);  RETURN const
	END NewConst;
	
	PROCEDURE NewObj*(): Object;
		VAR obj: Object;
	BEGIN NEW(obj);  RETURN obj
	END NewObj;
	
	PROCEDURE NewStr*(form, comp: SHORTINT): Struct;
		VAR typ: Struct;
	BEGIN NEW(typ); typ.form := form; typ.comp := comp;
		typ.tdadr := OPM.TDAdrUndef; typ.offset := OPM.TDAdrUndef;
		typ.txtpos := OPM.errpos; typ.size := -1; typ.BaseTyp := undftyp; RETURN typ
	END NewStr;
	
	PROCEDURE NewNode*(class: SHORTINT): Node;
		VAR node: Node;
	BEGIN	NEW(node); node.class := class; RETURN node
	END NewNode;
	
	PROCEDURE NewExt*(): ConstExt;
		VAR ext: ConstExt;
	BEGIN	NEW(ext); RETURN ext
	END NewExt;

	PROCEDURE DoubleStructArr(VAR x: StructArr);
		VAR i: LONGINT; h: StructArr;
	BEGIN
		i := LEN(x^); h := x; NEW(x, 2*i);
		ASSERT(x # NIL);
		SYS.MOVE(SYS.ADR(h[0]), SYS.ADR(x[0]), i*SIZE(Struct));
	END DoubleStructArr;

	PROCEDURE DoubleModArr(VAR x: ModArr);
		VAR i: LONGINT; h: ModArr;
	BEGIN
		i := LEN(x^); h := x; NEW(x, 2*i);
		ASSERT(x # NIL);
		SYS.MOVE(SYS.ADR(h[0]), SYS.ADR(x[0]), i*SIZE(Module));
	END DoubleModArr;

	PROCEDURE MarkObj*(obj: Object);
	BEGIN
		IF obj#NIL THEN	obj.used:=TRUE;
			IF obj.mnolev<0 THEN modules[-obj.mnolev].used:=TRUE END;
		END;
	END MarkObj;

	PROCEDURE MarkType*(typ: Struct);
	BEGIN typ.pvused:=TRUE; MarkObj(typ.strobj);
	END MarkType;

	PROCEDURE FindImport*(mod: Object; VAR res: Object);
		VAR obj: Object;
	BEGIN obj := mod^.scope;
		LOOP
			IF obj = NIL THEN EXIT END ;
			IF OPS.name < obj^.name THEN obj := obj^.left
			ELSIF OPS.name > obj^.name THEN obj := obj^.right
			ELSE (*found*)
				IF (obj^.mode = Typ) & (obj^.vis = internal) THEN obj := NIL 
				ELSE MarkObj(obj) END ;
				EXIT
			END
		END ;
		res := obj
	END FindImport;

	PROCEDURE Find*(VAR res: Object);
		VAR obj, head: Object;
	BEGIN head := topScope;
		LOOP obj := head.right;
			LOOP
				IF obj = NIL THEN EXIT END;
				IF OPS.name < obj.name THEN obj := obj.left
				ELSIF OPS.name > obj.name THEN obj := obj.right
				ELSE (*found*) EXIT
				END
			END ;
			IF obj # NIL THEN EXIT END;
			head := head.left;
			IF head = NIL THEN EXIT END
		END; res := obj
	END Find;

	PROCEDURE FindField*(VAR name: OPS.Name; typ: Struct; VAR res: Object; mark: BOOLEAN);
		VAR obj: Object;
	BEGIN res:=NIL;
		WHILE (typ # NIL) & (res=NIL) DO obj := typ^.link;
			WHILE obj # NIL DO
				IF name < obj^.name THEN obj := obj^.left
				ELSIF name > obj^.name THEN obj := obj^.right
				ELSE (*found*) res := obj; obj:=NIL
				END
			END ;
			IF (res # NIL) & (res.mode = TProc) & (res.mnolev < 0) & (res.vis = internal) THEN res := NIL END;
			IF res=NIL THEN
				IF (typ.BaseTyp#NIL) & (typ.BaseTyp.strobj.vis=internal) & mark THEN MarkObj(typ.strobj) END;
				typ := typ^.BaseTyp
			END
		END ;
		IF res = NIL THEN RETURN END;
		IF mark THEN res.used:=TRUE; MarkObj(typ.strobj); typ.pbused:=TRUE END
	END FindField;
	
	PROCEDURE Insert*(VAR name: OPS.Name; VAR obj: Object);
		VAR ob0, ob1: Object; left: BOOLEAN;
	BEGIN ob0 := topScope; ob1 := ob0.right; left := FALSE;
		LOOP
			IF ob1 # NIL THEN
				IF name < ob1.name THEN ob0 := ob1; ob1 := ob0.left; left := TRUE
				ELSIF name > ob1.name THEN ob0 := ob1; ob1 := ob0.right; left := FALSE
				ELSE (*double def*) err(1); ob0 := ob1; ob1 := ob0.right
				END
			ELSE (*insert*) ob1:=NewObj(); ob1.leaf := TRUE;
				IF left THEN ob0.left := ob1 ELSE ob0.right := ob1 END;
				ob1.left:=NIL; ob1.right:=NIL; COPY(name, ob1.name);
				ob1.mnolev := topScope.mnolev; EXIT
			END
		END; obj := ob1
	END Insert;

	PROCEDURE OpenScope*(level: SHORTINT; owner: Object);
		VAR head: Object;
	BEGIN
		head:=NewObj();
		head.mode := Head; head.mnolev := level; head.link := owner;
		IF owner # NIL THEN owner.scope := head END;
		head.left := topScope; head.right:=NIL; head.scope:=NIL; topScope := head
	END OpenScope;

	PROCEDURE CloseScope*;
	BEGIN 
		IF topScope # NIL THEN topScope := topScope.left END
	END CloseScope;

	PROCEDURE Init*(VAR name: OPS.Name; opt: SET);
		CONST nsf=10; esf=11;
	BEGIN topScope := universe; OpenScope(0, NIL); nofmod := 1; SYSimported := FALSE; impSelf:=FALSE;
		sfpresent:=TRUE; newSF:=nsf IN opt; extSF:=newSF OR (esf IN opt);
		modules[0]:=NewMod(); SYS.MOVE(SYS.VAL(LONGINT, topScope), SYS.VAL(LONGINT, modules[0]), SIZE(ObjDesc));
		modules[0].name:=name;
		topScope:=modules[0]; 
	END Init;

	(* ----- Fingerprinting ----- *)

	PROCEDURE ^ FPrintTyp0(typ: Struct);
	PROCEDURE ^ FPrintTyp*(typ: Struct);

	PROCEDURE FPrintName(VAR fp: LONGINT; VAR name: ARRAY OF CHAR);
		VAR i: INTEGER; ch: CHAR; 
	BEGIN i:=0; REPEAT ch:=name[i]; OPM.FPrint(fp, ORD(ch)); INC(i) UNTIL ch=0X
	END FPrintName;

	PROCEDURE FPrintSign(VAR fp: LONGINT; result: Struct; par: Object);
	BEGIN 
		FPrintTyp0(result); OPM.FPrint(fp, result.fp);
		WHILE par#NIL DO
			OPM.FPrint(fp, par.mode);  
			IF par.typ # NIL THEN FPrintTyp0(par.typ); OPM.FPrint(fp, par.typ.fp) END;
			par:=par.link;
		END;
	END FPrintSign;

	PROCEDURE FPrintMeth(typ: Struct; fld: Object);
		VAR fp: LONGINT; 
	BEGIN
		IF fld#NIL THEN FPrintMeth(typ, fld.left);
			IF (fld.mode=TProc) & (fld.vis#internal) THEN 
				fp:=0; OPM.FPrint(fp, TProc); FPrintName(fp, fld.name); FPrintSign(fp, fld.typ, fld.link); fld.fp:=fp;	
				OPM.FPrint(fp, fld.adr DIV 10000H); OPM.FPrint(typ.pbfp, fp); OPM.FPrint(typ.pvfp, fp);
			END;
			FPrintMeth(typ, fld.right);
		END
	END FPrintMeth;

	PROCEDURE FPrintRecord(typ: Struct);
		VAR fld: Object; fp, pbfp, pvfp: LONGINT;
	BEGIN 
		pvfp:=typ.fp; pbfp:=typ.fp; 
		IF typ.BaseTyp#NIL THEN OPM.FPrint(pvfp, typ.BaseTyp.pvfp);
			OPM.FPrint(pbfp, typ.BaseTyp.pbfp);
		END; 
		IF typ.size<0 THEN typSize(typ, FALSE) END;
		fld:=typ.link; 
		FPrintMeth(typ, fld); 
		WHILE (fld#NIL) & (fld.mode=Fld) DO FPrintTyp(fld.typ); 
			IF fld.vis#internal THEN fp:=0; OPM.FPrint(fp, fld.mode);
				FPrintName(fp, fld.name); OPM.FPrint(fp, fld.vis); 
				OPM.FPrint(fp, fld.typ.fp); fld.fp:=fp;
				OPM.FPrint(pbfp, fld.typ.pbfp); OPM.FPrint(pbfp, fld.adr); 
				OPM.FPrint(pvfp, fld.typ.pvfp);  OPM.FPrint(pvfp, fld.adr); 
				OPM.FPrint(pvfp, fp); OPM.FPrint(pbfp, fp);
				fld:=fld.link;
			ELSE 
				OPM.FPrint(pvfp, fld.fp); fld:=fld.link;
			END;
		END;
		typ.pbfp := pbfp; typ.pvfp := pvfp
	END FPrintRecord;

	PROCEDURE FPrintTyp0(typ: Struct);
	(* calculate fingerprint without looking at record fields, private and public fingerprints *)
		VAR fp: LONGINT; f, c: SHORTINT; btyp: Struct;
	BEGIN 
		IF (typ # NIL) & (typ.fpdone >= 0) THEN (* not a built in type *)
			fp:=0; f:=typ.form; c:=typ.comp; OPM.FPrint(fp, f); OPM.FPrint(fp, c); 
			IF typ.sysflag#0 THEN OPM.FPrint(fp, 1) END; 
			IF typ.mno#modNo THEN FPrintName(fp, modules[typ.mno].name); FPrintName(fp, typ.strobj.name);
			END;
			btyp:=typ.BaseTyp; typ.fp:=fp;
			IF (c=Record) & (btyp#NIL) OR (f=Pointer) THEN FPrintTyp0(btyp); OPM.FPrint(typ.fp, btyp.fp); 
			ELSIF (c=DynArr) OR (c=Array) THEN FPrintTyp0(btyp); OPM.FPrint(typ.fp, btyp.fp);
				IF c=Array THEN OPM.FPrint(typ.fp, typ.n) END; typ.pbfp:=typ.fp; typ.pvfp:=typ.fp;
			ELSIF f=ProcTyp THEN FPrintSign(typ.fp, btyp, typ.link); typ.pbfp:=typ.fp; typ.pvfp:=typ.fp;
			END;
		END;
	END FPrintTyp0;

	PROCEDURE FPrintTyp*(typ: Struct);	
	(* fpdone  0: not done yet  >0: done for module fpdone-1  =-1: built in type *)
	BEGIN 
		IF (typ # NIL) & (typ.fpdone#modNo+1) & (typ.fpdone>=0) THEN	
			FPrintTyp0(typ);
			IF (typ.comp # Record) THEN typ.fpdone:=modNo+1 END;
			IF typ.BaseTyp#NIL THEN FPrintTyp(typ.BaseTyp) END;
			IF (typ.comp=Record) THEN FPrintRecord(typ) END;
			typ.fpdone:=modNo+1;
		END;
	END FPrintTyp;

	PROCEDURE FPrintObj*(obj: Object);
		VAR fp: LONGINT; rval: REAL; f, m: INTEGER; ext: ConstExt;
	BEGIN 
		fp:=0; 
		OPM.FPrint(fp, obj.mode); FPrintName(fp, obj.name); OPM.FPrint(fp, obj.vis);
		IF obj.mode=Con THEN
			f:=obj.typ.form; OPM.FPrint(fp, f); OPM.FPrint(fp, obj.typ.comp);
			CASE f OF
			| Bool, Char, SInt, Int, LInt: OPM.FPrint(fp, obj.conval.intval);
			| Set: OPM.FPrintSet(fp, obj.conval.setval);
			| Real: rval:=SHORT(obj.conval.realval); OPM.FPrintReal(fp, rval);
			| LReal: OPM.FPrintLReal(fp, obj.conval.realval);
			| String: FPrintName(fp, obj.conval.ext^);
			| NilTyp:
			END
		ELSIF obj.mode=Var THEN FPrintTyp(obj.typ); OPM.FPrint(fp, obj.typ.fp);
		ELSIF obj.mode=XProc THEN  FPrintSign(fp, obj.typ, obj.link); 
		ELSIF obj.mode=CProc THEN
			FPrintSign(fp, obj.typ, obj.link); ext:=obj.conval.ext;
			m:=ORD(ext^[0]); f:=1; OPM.FPrint(fp, m);
			WHILE f<=m DO OPM.FPrint(fp, ORD(ext^[f])); INC(f) END
		ELSIF obj.mode=Typ THEN FPrintTyp(obj.typ); OPM.FPrint(fp, obj.typ.fp);
		END;
		obj.fp:=fp;
	END FPrintObj;
		
	PROCEDURE FPrintErr(obj: Object);
		VAR errNo: INTEGER;
	BEGIN 
		IF	expGlobal	THEN
			IF	obj.history=removed	THEN	errNo:=450
			ELSIF	obj.history=inserted	THEN	errNo:=451
			ELSIF	obj.history=modified	THEN	errNo:=452
			ELSE	RETURN
			END;
			COPY(obj.name, OPM.errName);
			IF errNo=451 THEN (* inserted *)
				IF ~extSF THEN err(errNo) END;
				symExtended:=TRUE;
			ELSE
				IF ~newSF THEN err(errNo) END;
				symNew:=TRUE;
			END;
			IF errNo=450 THEN obj.vis:=internal END;
		END
	END FPrintErr;			

(* Import *)

	PROCEDURE InsertImport(obj: Object; root: Object);
		VAR ob0, ob1: Object; left: BOOLEAN;	(* old in obj.scope *)
	BEGIN	ob0:=root; ob1:=ob0.right; left:=FALSE;
		LOOP
			IF	ob1#NIL	THEN
				IF	obj.name < ob1.name	THEN	ob0:=ob1; ob1:=ob1.left; left:=TRUE
				ELSIF	obj.name > ob1.name	THEN	ob0:=ob1; ob1:=ob1.right; left:=FALSE
				ELSIF	obj.name=""	THEN	obj.scope:=NIL; RETURN
				ELSE	obj.scope:=ob1; EXIT
				END
			ELSE
				IF	left	THEN	ob0.left:=obj	ELSE	ob0.right:=obj	END;
				obj.left:=NIL; obj.right:=NIL; obj.scope:=NIL; 
				obj.mnolev:=root.mnolev; RETURN
			END
		END
	END InsertImport;

	PROCEDURE CompOldTyp(typ, oldtyp: Struct): SHORTINT;
	BEGIN
		IF (typ.form=Comp) & (typ.comp#Record) OR (typ.form=Pointer) THEN
			RETURN CompOldTyp(typ.BaseTyp, oldtyp.BaseTyp)
		ELSIF (typ.form=Comp) & (typ.comp=Record) THEN
			IF (typ.pvfp#oldtyp.pvfp) OR (typ.pbfp#oldtyp.pbfp) THEN RETURN modified
			ELSE RETURN same
			END
		ELSE RETURN same END
	END CompOldTyp;

	PROCEDURE CompOldSym(obj: Object);
		VAR old: Object; 
	BEGIN	
		WHILE obj#NIL DO old:=obj.scope;
			IF old#NIL THEN	 
				FPrintObj(obj); FPrintObj(old); 
				IF obj.fp#old.fp THEN
					IF	(obj.vis#old.vis) & (old.vis=internal)	THEN	obj.history:=removed; FPrintErr(obj)	
					ELSE	old.history:=modified	END
				ELSIF (obj.mode=Typ) OR (obj.typ.form=Comp) & (obj.typ.comp=Record) & (obj.typ.strobj.name="") THEN old.history:=CompOldTyp(obj.typ, old.typ); 
				ELSE old.history:=same END
			ELSE obj.history:=removed END;
			obj:=obj.nxtobj;
		END 
	END CompOldSym;

	(* ----- read sym file ----- *)

	PROCEDURE Imp(VAR impName, modName: OPS.Name; VAR M: Module);
		VAR R: Files.Rider; i: INTEGER; tag: LONGINT; done: BOOLEAN; mode: SHORTINT; obj, last: Object; tdum: Struct;
			new: BOOLEAN;
			
		PROCEDURE^InStruct(VAR typ: Struct; par: BOOLEAN);

		PROCEDURE GetImports;
			VAR name: OPS.Name; TM: Module;
		BEGIN	OPM.ReadString(R, name);
			WHILE	name#""	DO	Imp(name, modName, TM);
				M.import[M.nofimp]:=TM; 
				INC(M.nofimp); IF M.nofimp>=LEN(M.import^) THEN DoubleModArr(M.import) END;
				M.nofreimp:=0; OPM.ReadString(R, name)
			END
		END GetImports;

		PROCEDURE InParList(VAR first: Object);
			VAR last, par: Object;
		BEGIN	first:=NIL; last:=NIL; Files.ReadNum(R, tag);
			WHILE	tag#SFend	DO	NEW(par);
				IF	last=NIL	THEN	first:=par	ELSE	last.link:=par	END;
				last:=par;
				IF	tag=SFvar	THEN	par.mode:=VarPar; Files.ReadNum(R, tag)	ELSE par.mode:=Var END;
				IF	tag=SFleaf	THEN	par.leaf:=TRUE; Files.ReadNum(R, tag)	END;
				InStruct(par.typ, TRUE); OPM.ReadString(R, par.name); Files.ReadNum(R, tag)
			END
		END InParList;

		(* Cyclic types must be post-processed *)
		PROCEDURE SetTypFlags(typ: Struct);
			
			PROCEDURE TraverseTProc(fld: Object);
				VAR redef: Object;
			BEGIN
				IF fld # NIL THEN
					TraverseTProc(fld.left);
					IF fld.mode = TProc THEN
						FindField(fld.name, typ.BaseTyp, redef, FALSE);
						IF redef # NIL THEN fld.adr := (redef.adr DIV 10000H) * 10000H; INCL(fld^.conval^.setval, isRedef)
						ELSE fld.adr:=typ.n*10000H; INC(typ.n)
						END
					END;
					TraverseTProc(fld.right)
				END
			END TraverseTProc;
		
		BEGIN
			IF (typ.extlev = -1) OR (typ.n < 0) THEN 
				IF typ.BaseTyp # NIL THEN SetTypFlags(typ.BaseTyp); 
					typ.extlev := typ.BaseTyp.extlev + 1; typ.n := typ.BaseTyp.n
				ELSE typ.extlev := 0; typ.n := 0
				END;
				TraverseTProc(typ.link)
			END
		END SetTypFlags;
		
		PROCEDURE InRecord(typ: Struct);
			VAR scope, last, fld: Object; btyp: Struct; 	
		BEGIN	NEW(scope); scope.mode:=Head; scope.mnolev:=-typ.mno; last:=NIL; btyp:=typ.BaseTyp;
			Files.ReadNum(R, tag);
			WHILE	tag<SFtproc	DO	NEW(fld); 
				IF	last#NIL	THEN	last.link:=fld	END;
				last:=fld;
				IF tag=SFreadonly THEN Files.ReadNum(R, tag); fld.vis:=externalR ELSE fld.vis:=external END;
				fld.mode:=Fld; InStruct(fld.typ, FALSE); OPM.ReadString(R, fld.name);
				IF	fld.name=""	THEN	fld.vis:=internal	END;
				InsertImport(fld, scope); Files.ReadNum(R, tag);
			END;
			IF	tag=SFtproc	THEN	Files.ReadNum(R, tag);
				WHILE	tag#SFend	DO	NEW(fld); fld.mode:=TProc; fld.vis:=external; 
					fld.conval:=NewConst(); fld.conval.setval:={}; fld.linkadr := OPM.LANotAlloc;	
					InStruct(fld.typ, FALSE); OPM.ReadString(R, fld.name); 
					IF fld.name = "" THEN fld.vis:=internal; OPM.ReadString(R, fld.name) END;
					InParList(fld.link); InsertImport(fld, scope);
					Files.ReadNum(R, tag)
				END
			END;
			typ.link:=scope.right
		END InRecord;

		PROCEDURE InStruct(VAR typ: Struct; par: BOOLEAN);
			VAR typtag, typadr: LONGINT; vis: SHORTINT; tobj: Object; btyp: Struct; typname: OPS.Name; 
				mod: Module; i: INTEGER;
		BEGIN
			IF	tag <= 0	THEN	ASSERT(tag>-LEN(M.struct^)); typ:=M.struct[-tag]
			ELSIF tag <= SFtypSptr THEN typ:=predefStruct[tag]
			ELSIF tag <= SFmodOther THEN
				IF tag = SFmodOther THEN Files.ReadNum(R, tag) ELSE tag:=tag-SFmod1 END;
				mod:=M.import[tag]; OPM.ReadString(R, typname); 
				IF typname[0]#0X THEN
					i:=1; WHILE (i<mod.nofstr) & (mod.struct[i].strobj.name#typname) DO INC(i) END;
					IF i<mod.nofstr THEN typ:=mod.struct[i];  INC(mod.nofreimp); 
						IF mod.nofreimp>=LEN(mod.reimp^) THEN DoubleStructArr(mod.reimp) END;
						mod.reimp[mod.nofreimp]:=typ;  
					ELSE	typ:=niltyp; IF ~impSelf THEN err(150) END	END;
				ELSE 
					Files.ReadNum(R, typadr); ASSERT(typadr<LEN(mod.reimp^)); typ:=mod.reimp[typadr]; 
				END
			ELSE
				NEW(typ); M.struct[M.nofstr]:=typ; typ.tdadr:=OPM.TDAdrUndef; typ.offset:=OPM.TDAdrUndef;
				typ.sref:=-M.nofstr; INC(M.nofstr); 
				IF M.nofstr>=LEN(M.struct^) THEN DoubleStructArr(M.struct) END;
				IF	tag=SFinvisible	THEN	vis:=internal; Files.ReadNum(R, tag)	ELSE	vis:=external	END;
				IF	tag=SFsysflag	THEN	Files.ReadNum(R, tag); typ.sysflag:=1; Files.ReadNum(R, tag)	END;
				typ.form:=strucForm[tag]; typ.comp:=strucComp[tag]; typ.mno:=-M.mnolev; typ.size:=-1; 
				typtag:=tag; Files.ReadNum(R, tag); typ.extlev := -1;
				InStruct(btyp, par); typ.BaseTyp:=btyp;
				IF	(typ.form=Pointer) & (typ.BaseTyp=NIL) THEN typ:=ptrtyp; DEC(M.nofstr); RETURN END;
				NEW(tobj); tobj.mode:=Typ; tobj.nxtobj:=last; last:=tobj; tobj.typ:=typ; OPM.ReadString(R, tobj.name);
				typ.strobj:=tobj; 
				IF	tobj.name#""	THEN	tobj.vis:=vis; tobj.typ:=typ; InsertImport(tobj, M)	END;
				CASE	typtag	OF
				| SFtypDynArr:
						IF	btyp.comp=DynArr	THEN	typ.n:=btyp.n+1	END
				| SFtypArray:	Files.ReadNum(R, typ.n)
				| SFtypPointer:
				| SFtypRecord:	InRecord(typ); typ.n := -1
				| SFtypProcTyp:	InParList(typ.link)
				END;
				IF impSelf & (tobj.name#"") & (tobj.vis#internal) THEN 
					typ.sref:=0;
				END;
			END
		END InStruct;

		PROCEDURE InObj;
		BEGIN	NEW(obj); obj.mode:=mode; obj.nxtobj:=last; last:=obj;
			IF tag=SFreadonly THEN Files.ReadNum(R, tag); obj.vis:=externalR ELSE obj.vis:=external END;
			IF tag=SFleaf THEN Files.ReadNum(R, tag); obj.leaf:=TRUE END;
			InStruct(obj.typ, FALSE); OPM.ReadString(R, obj.name); InsertImport(obj, M)
		END InObj;

		PROCEDURE InConst;
			VAR conval: Const; s: INTEGER; r: REAL;
		BEGIN	NEW(conval); obj.conval:=conval;
			CASE	tag	OF
			| SFtypBool, SFtypChar, SFtypSInt..SFtypLInt:	Files.ReadNum(R, conval.intval)
			| SFtypSet:	Files.ReadNum(R, SYS.VAL(LONGINT, conval.setval)); conval.setval:=OPM.FlipSet(conval.setval);
			| SFtypReal:	Files.ReadReal(R, r); conval.realval:=r; conval.intval:=OPM.ConstNotAlloc;
			| SFtypLReal:	Files.ReadLReal(R, conval.realval); conval.intval:=OPM.ConstNotAlloc;
			| SFtypString:	NEW(conval.ext); OPM.ReadString(R, conval.ext^); 
				s:=0; WHILE conval.ext[s]#0X DO INC(s) END; conval.intval:=OPM.ConstNotAlloc; conval.intval2:=s+1
			| SFtypNilTyp:
			END
		END InConst;

		PROCEDURE InCode;
			VAR conval: Const; ext: ConstExt; ch: CHAR; i, s: INTEGER;
		BEGIN	NEW(conval); obj.conval:=conval; NEW(ext); conval.ext:=ext; Files.Read(R, ch); s:=ORD(ch); ext[0]:=ch; i:=1;
			WHILE	i <= s	DO	Files.Read(R, ext[i]); INC(i)	END
		END InCode;

	BEGIN	i:=0;
		WHILE	(i < nofmod) & (impName#modules[i].name)	DO	INC(i)	END;
		IF	i < nofmod	THEN	M:=modules[i]; new:=FALSE; 
		ELSE	M:=NewMod(); COPY(impName, M.name); M.mnolev:=-nofmod; 
			modules[nofmod]:=M; 
			INC(nofmod); 
			IF nofmod>=LEN(modules^) THEN DoubleModArr(modules) END;
			new:=TRUE 
		END;
		M.nofreimp:=0; 
		IF	new	OR	impSelf&(i=0)	THEN
			M.nofimp:=0; M.struct[0]:=NIL; M.nofstr:=1; 
			OPM.OpenSym(R, impName, done);
			IF	done	THEN	GetImports;
				IF	OPM.noerr	THEN
					i:=0; WHILE i<nofmod DO modules[i].nofreimp:=0; INC(i) END;
					last:=NIL; Files.ReadNum(R, tag);
					IF	tag=SFconst	THEN	mode:=Con; Files.ReadNum(R, tag);
						WHILE	tag < SFvar	DO	InObj; InConst; Files.ReadNum(R, tag)	END
					END;
					IF	tag=SFvar	THEN	mode:=Var; Files.ReadNum(R, tag);
						WHILE	tag < SFxproc	DO	InObj; Files.ReadNum(R, tag)	END
					END;
					IF	tag=SFxproc	THEN	mode:=XProc; Files.ReadNum(R, tag);
						WHILE	tag < SFcproc	DO	InObj; InParList(obj.link); obj.conval:=NewConst(); obj.conval.setval:={};
							Files.ReadNum(R, tag)	END
					END;
					IF	tag=SFcproc	THEN	mode:=CProc; Files.ReadNum(R, tag);
						WHILE	tag < SFalias	DO	InObj; InParList(obj.link); InCode; Files.ReadNum(R, tag)	END
					END;
					IF	tag=SFalias	THEN	Files.ReadNum(R, tag);
						WHILE	tag < SFtyp	DO	NEW(obj); obj.vis:=external; obj.mode:=Typ;
							InStruct(obj.typ, FALSE); OPM.ReadString(R, obj.name); 							
							InsertImport(obj, M); CompOldSym(obj);
							Files.ReadNum(R, tag)
						END
					END;
					IF	tag=SFtyp	THEN	Files.ReadNum(R, tag);
						WHILE	tag < SFend	DO	InStruct(tdum, FALSE); Files.ReadNum(R, tag)	END
					END;
					M.publics:=last; 
					WHILE last # NIL DO
						IF (last.mode = Typ) & (last.typ.form = Comp) & (last.typ.comp = Record) THEN SetTypFlags(last.typ) END;
						last := last.nxtobj
					END;
					Files.Close(Files.Base(R))
				END
			ELSE 
				IF impSelf THEN newSF:=TRUE; extSF:=TRUE; sfpresent:=FALSE 
				ELSE err(152);  
				END;
			END
		END;
	END Imp;

	PROCEDURE Import*(VAR aliasName, impName, selfName: OPS.Name);
		VAR ali: Object; M: Module;
	BEGIN
		Insert(aliasName, ali); ali.mode:=Mod; ali.typ:=notyp;
		IF impName="SYSTEM" THEN err(502)
		ELSE 
			IF (impName=selfName) & (aliasName#"@self") THEN M:=NewMod(); err(49) END;
			impSelf := (impName=modules[0].name);
			Imp(impName, selfName, M); M.directImp:=TRUE; ali.scope:=M.right; ali.mnolev:=M.mnolev
		END
	END Import;

(* Export *)

	PROCEDURE OutMod*(mod: Module);
	BEGIN
		IF	mod.mode=0	THEN
			OPM.SymWMod(mod.name);
			INC(nofemod); 
			IF nofemod>=LEN(emodules^) THEN DoubleModArr(emodules) END;
			emodules[nofemod]:=mod; mod.mode:=nofemod
		END
	END OutMod;

	PROCEDURE ^ OutStruct(typ: Struct);

	PROCEDURE Enumerate(obj: Object);
	BEGIN
		IF	obj#NIL	THEN
			Enumerate(obj.left);
			IF	(obj.vis > internal)=export	THEN
				IF	expGlobal & (obj.history=removed)	THEN	FPrintErr(obj); obj.mode:=Undef
				ELSE
					IF	(obj.mode#Typ) OR (obj.typ.strobj#obj)	THEN	FPrintErr(obj)	END;
					IF	(obj.mode=Typ)&(obj.typ.strobj#obj) 	THEN	
						obj.sibling:=exp[Alias]; exp[Alias]:=obj
					ELSIF	(obj.mode#Var) OR (~obj.par)	THEN
						obj.sibling:=exp[obj.mode]; exp[obj.mode]:=obj;
					END
				END
			END;
			Enumerate(obj.right)
		END
	END Enumerate;

	PROCEDURE OutParList(par: Object);
	BEGIN	
		WHILE	par#NIL	DO
			IF	par.mode=VarPar	THEN	OPM.SymW(CHR(SFvar))	END;
			IF	par.leaf	THEN	OPM.SymW(CHR(SFleaf))	END;
			OutStruct(par.typ); OPM.SymWString(par.name); par.par:=TRUE; par.nxtobj:=par.link ; par:=par.link
		END;
		OPM.SymW(CHR(SFend))
	END OutParList;

	PROCEDURE OutFld(fld: Object);
	BEGIN
		WHILE	fld#NIL	DO
			IF	fld.vis=externalR	THEN	OPM.SymW(CHR(SFreadonly))	END;
			OutStruct(fld.typ);
			IF	fld.vis > internal	THEN	OPM.SymWString(fld.name)	ELSE	OPM.SymW(0X)	END;
			fld:=fld.link
		END
	END OutFld;

	PROCEDURE OutRecord(typ: Struct);
		VAR btyp: Struct; count: LONGINT;

		PROCEDURE TraverseT(fld: Object);
		BEGIN
			IF	fld#NIL	THEN	TraverseT(fld.left);
				IF	fld.mode=TProc	THEN	
					IF	count=0	THEN	OPM.SymW(CHR(SFtproc))	END;
					INC(count); OutStruct(fld.typ); 
					IF	fld.vis = internal	THEN	OPM.SymW(0X)	END;
					OPM.SymWString(fld.name); OutParList(fld.link)
				END;
				TraverseT(fld.right)
			END
		END TraverseT;

	BEGIN	btyp:=typ.BaseTyp;
		IF	(typ.link#NIL)&(typ.link.mode#TProc)	THEN	OutFld(typ.link)	END;
		count:=0; TraverseT(typ.link);
		OPM.SymW(CHR(SFend))
	END OutRecord;

	PROCEDURE OutStruct(typ: Struct);
		VAR tag: SHORTINT; mod: Module; tobj: Object; 
	BEGIN
		IF	typ=NIL	THEN	OPM.SymW(0X)
		ELSIF	typ.mno#0	THEN	mod:=modules[typ.mno]; OutMod(mod); 
			IF mod.nofstr>0 THEN mod.nofstr:=0 END;
			IF mod.mode>31 THEN OPM.SymW(CHR(SFmodOther)); OPM.SymWNum(mod.mode-1) ELSE OPM.SymW(CHR(SFmod1-1+mod.mode)) END;
			IF typ.sref<0 THEN DEC(mod.nofstr); typ.sref:=-mod.nofstr; OPM.SymWString(typ.strobj.name); 
			ELSE OPM.SymW(0X); OPM.SymWNum(typ.sref) END; 
		ELSIF	typ.sref#0	THEN	OPM.SymWNum(typ.sref)
		ELSIF	typ=ptrtyp	THEN	OPM.SymW(CHR(SFtypPointer)); OPM.SymW(0X)
		ELSE	DEC(nofstruc); typ.sref:=nofstruc; tag:=strucFormSF[typ.form]+strucCompSF[typ.comp];
			IF	export&(typ.strobj#NIL)&(typ.strobj.vis=internal)	THEN	OPM.SymW(CHR(SFinvisible))	END;
			IF	typ.sysflag#0	THEN	OPM.SymW(CHR(SFsysflag))	END;
			OPM.SymW(CHR(tag)); OutStruct(typ.BaseTyp);
			NEW(tobj); tobj.mode:=Typ; tobj.nxtobj:=objects; objects:=tobj; tobj.typ:=typ;
			IF	typ.strobj=NIL	THEN	OPM.SymW(0X)
			ELSE	FPrintErr(typ.strobj); OPM.SymWString(typ.strobj.name); COPY(typ.strobj.name, tobj.name)	END;
			CASE	tag	OF
			| SFtypDynArr:
			| SFtypArray:	OPM.SymWNum(typ.n)
			| SFtypPointer:
			| SFtypRecord:	OutRecord(typ)
			| SFtypProcTyp:	OutParList(typ.link)
			END
		END
	END OutStruct;

	PROCEDURE OutConst(form: SHORTINT; conval: Const);
	BEGIN
		CASE	form	OF
		| Bool, Char, SInt..LInt:	OPM.SymWNum(conval.intval)
		| Set:	OPM.SymWSet(conval.setval)
		| Real:	OPM.SymWReal(conval.realval)
		| LReal:	OPM.SymWLReal(conval.realval)
		| String:	OPM.SymWString(conval.ext^)
		| NilTyp:
		END
	END OutConst;

	PROCEDURE OutObj(obj: Object);
	BEGIN	obj.nxtobj:=objects; objects:=obj; OutStruct(obj.typ); OPM.SymWString(obj.name)
	END OutObj;

	PROCEDURE OutCode(obj: Object);
		VAR ext: ConstExt; s, i: INTEGER;
	BEGIN	ext:=obj.conval.ext; s:=ORD(ext[0]); OPM.SymW(CHR(s)); i:=1;
		WHILE	i <= s	DO	OPM.SymW(ext[i]); INC(i)	END
	END OutCode;

	PROCEDURE OutScope*(scope: Object; public: BOOLEAN);
		VAR obj: Object; first: BOOLEAN;
	BEGIN	export:=public;
		exp[Con]:=NIL; exp[Var]:=NIL; exp[LProc]:=NIL; exp[XProc]:=NIL; exp[CProc]:=NIL; exp[Alias]:=NIL; exp[Typ]:=NIL;
		Enumerate(scope);
		
		IF	exp[Con]#NIL	THEN	OPM.SymW(CHR(SFconst)); obj:=exp[Con];
			WHILE	obj#NIL	DO	OutObj(obj); OutConst(obj.typ.form, obj.conval); obj:=obj.sibling	END;
		END;
		IF	exp[Var]#NIL	THEN	OPM.SymW(CHR(SFvar)); obj:=exp[Var];
			WHILE	obj#NIL	DO
				IF	obj.vis=externalR	THEN	OPM.SymW(CHR(SFreadonly))	END;
				IF	obj.leaf	THEN	OPM.SymW(CHR(SFleaf))	END;
				OutObj(obj); obj:=obj.sibling
			END;
		END;
		IF	exp[LProc]#NIL	THEN	OPM.SymW(CHR(SFlproc)); obj:=exp[LProc];
			WHILE	obj#NIL	DO	
				IF	obj.leaf	THEN	OPM.SymW(CHR(SFleaf))	END;
				OutObj(obj); OutParList(obj.link); obj:=obj.sibling	
			END;
		END;
		IF	exp[XProc]#NIL	THEN	OPM.SymW(CHR(SFxproc)); obj:=exp[XProc];
			WHILE	obj#NIL	DO	
				IF	obj.leaf	THEN	OPM.SymW(CHR(SFleaf))	END;
				OutObj(obj); OutParList(obj.link); obj:=obj.sibling	
			END;
		END;
		IF	exp[CProc]#NIL	THEN	OPM.SymW(CHR(SFcproc)); obj:=exp[CProc];
			WHILE	obj#NIL	DO	OutObj(obj); OutParList(obj.link); OutCode(obj); obj:=obj.sibling	END;
		END;
		IF	exp[Alias]#NIL	THEN	OPM.SymW(CHR(SFalias)); obj:=exp[Alias];
			WHILE	obj#NIL	DO	OutStruct(obj.typ); OPM.SymWString(obj.name); obj:=obj.sibling	END;
		END;
		IF	exp[Typ]#NIL	THEN	obj:=exp[Typ]; first:=TRUE;
			WHILE	obj#NIL	DO
				IF	obj.typ.sref=0	THEN
					IF	first	THEN	OPM.SymW(CHR(SFtyp)); first:=FALSE	END;
					IF	~export OR (obj.typ.strobj#NIL) & (obj.typ.strobj.vis#internal)	THEN	OutStruct(obj.typ)	END;
				END;
				obj:=obj.sibling
			END;
		END;
		OPM.SymW(CHR(SFend))
	END OutScope;

	PROCEDURE Export*(VAR modName: OPS.Name; VAR newsf, extsf: BOOLEAN);
		VAR mods: SHORTINT; aliasName: OPS.Name;
	BEGIN symExtended:=FALSE; symNew:=FALSE; nofstruc:=0; nofemod:=0; objects:=NIL;
		modNo:=0; COPY("@self", aliasName); mods:=nofmod;
		Import(aliasName, modName, modName); nofmod:=mods;
		IF OPM.noerr THEN expGlobal:=TRUE; CompOldSym(modules[0].publics);
			OutScope(topScope.right, TRUE); expGlobal:=FALSE;
			extsf:=sfpresent & symExtended; newsf:=~sfpresent OR symNew;
			OPM.EndSym; 
			IF ~OPM.noerr THEN err(155); newsf:=FALSE; extsf:=FALSE END;
		ELSE newSF:=FALSE; extSF:=FALSE END;
	END Export;


(* Initialisation *)

	PROCEDURE InitStruct(VAR typ: Struct; form, sref: SHORTINT);
	BEGIN typ := NewStr(form, Basic); typ^.ref := form; typ^.size := OPM.ByteSize; typ^.sref:=sref;
		predefStruct[sref]:=typ; typ^.tdadr := 0; typ^.offset := 0; typ^.strobj := NewObj();
		typ.fpdone:=-1; typ.pvfp:=form; typ.pbfp:=form; typ.fp:=form;
	END InitStruct;

	PROCEDURE EnterBoolConst(name: OPS.Name; value: LONGINT);
		VAR obj: Object;
	BEGIN Insert(name, obj); obj.conval := NewConst();
		obj.mode := Con; obj.typ := booltyp; obj.conval.intval := value
	END EnterBoolConst;

	PROCEDURE EnterTyp(name: OPS.Name; form: SHORTINT; size: INTEGER; VAR res: Struct; sref: SHORTINT);
		VAR obj: Object; typ: Struct;
	BEGIN Insert(name, obj);
		typ := NewStr(form, Basic); obj^.mode := Typ; obj^.typ := typ; obj^.vis := external; typ.sref:=sref; predefStruct[sref]:=typ;
		typ^.strobj := obj; typ^.size := size; typ^.tdadr := 0; typ^.offset := 0; typ^.ref := form; res := typ;
		typ.fpdone:=-1; typ.pvfp:=size; typ.pbfp:=form; typ.fp:=form
	END EnterTyp;

	PROCEDURE EnterProc(name: OPS.Name; num: INTEGER);
		VAR obj: Object;
	BEGIN Insert(name, obj);
		obj.mode := SProc; obj.typ := notyp; obj.adr := num
	END EnterProc;

BEGIN
	topScope:=NIL; NEW(modules, DefMaxImport); NEW(emodules, DefMaxImport);
	OpenScope(0, NIL); OPM.errpos:=0;
	
	InitStruct(undftyp, Undef, 0); 
	InitStruct(notyp, NoTyp, SFtypNoTyp); InitStruct(stringtyp, String, SFtypString); InitStruct(niltyp, NilTyp, SFtypNilTyp);
	undftyp^.BaseTyp := undftyp;

	(*initialization of module SYSTEM*)
	EnterTyp("BYTE", Byte, OPM.ByteSize, bytetyp, SFtypByte); EnterTyp("PTR", Pointer, OPM.PointerSize, sysptrtyp, SFtypSptr);
	EnterProc("ADR", adrfn); EnterProc("CC", ccfn);
	EnterProc("LSH", lshfn); EnterProc("ROT", rotfn);
	EnterProc("GET", getfn); EnterProc("PUT", putfn);
	EnterProc("GETREG", getrfn); EnterProc("PUTREG", putrfn);
	EnterProc("BIT", bitfn); EnterProc("VAL", valfn);
	EnterProc("NEW", sysnewfn); EnterProc("MOVE", movefn);
	syslink := topScope.right; universe := topScope; topScope.right := NIL;

	EnterTyp("CHAR", Char, OPM.CharSize, chartyp, SFtypChar);
	EnterTyp("SET", Set, OPM.SetSize, settyp, SFtypSet);
	EnterTyp("REAL", Real, OPM.RealSize, realtyp, SFtypReal);
	EnterTyp("INTEGER", Int, OPM.IntSize, inttyp, SFtypInt);
	EnterTyp("LONGINT",  LInt, OPM.LIntSize, linttyp, SFtypLInt);
	EnterTyp("LONGREAL", LReal, OPM.LRealSize, lrltyp, SFtypLReal);
	EnterTyp("SHORTINT", SInt, OPM.SIntSize, sinttyp, SFtypSInt);
	EnterTyp("BOOLEAN", Bool, OPM.BoolSize, booltyp, SFtypBool);
	EnterTyp("PTR", Pointer, OPM.PointerSize, ptrtyp, 0);

	EnterBoolConst("FALSE", 0); EnterBoolConst("TRUE",  1);
	EnterProc("HALT", haltfn); EnterProc("NEW", newfn);
	EnterProc("ABS", absfn); EnterProc("CAP", capfn);
	EnterProc("ORD", ordfn); EnterProc("ENTIER", entierfn);
	EnterProc("ODD", oddfn); EnterProc("MIN", minfn);
	EnterProc("MAX", maxfn); EnterProc("CHR", chrfn);
	EnterProc("SHORT", shortfn); EnterProc("LONG", longfn);
	EnterProc("SIZE", sizefn); EnterProc("INC", incfn);
	EnterProc("DEC", decfn); EnterProc("INCL", inclfn); EnterProc("EXCL", exclfn);
	EnterProc("LEN", lenfn);EnterProc("COPY", copyfn);
	EnterProc("ASH", ashfn);EnterProc("ASSERT", assertfn);

	strucForm[SFtypPointer]:=Pointer; strucForm[SFtypRecord]:=Comp; strucForm[SFtypProcTyp]:=ProcTyp;
	strucForm[SFtypDynArr]:=Comp; strucForm[SFtypArray]:=Comp;
	strucComp[SFtypPointer]:=Basic; strucComp[SFtypRecord]:=Record; strucComp[SFtypProcTyp]:=Basic;
	strucComp[SFtypDynArr]:=DynArr; strucComp[SFtypArray]:=Array;
	strucFormSF[Pointer]:=SFtypPointer; strucFormSF[ProcTyp]:=SFtypProcTyp;
	strucCompSF[Array]:=SFtypArray; strucCompSF[DynArr]:=SFtypDynArr; strucCompSF[Record]:=SFtypRecord
END JOCT.
