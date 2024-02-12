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

MODULE JOCV;	(* mf 21.11.94 / tk 30.6.96 *)

	(* Juice Compiler - Tree Traverser *)

	IMPORT
		OPM:=JOCM, OPT:=JOCT;

	CONST
		Var=1; VarPar=2; Con=3; Fld=4; Typ=5; LProc=6; XProc=7; CProc=9; TProc=13; Comp=15;
		Bool=2; Char=3; SInt=4; Int=5; LInt=6; Real=7; LReal=8; Set=9; String=10; NilTyp=11;
		Pointer=13; Basic=1; Array=2; DynArr=3; Record=4; internal=0;
		assign=0; newfn=1; incfn=13; decfn=14; inclfn=15; exclfn=16; copyfn=18; assertfn=32;
		times=1; slash=2; div=3; mod=4; and=5; plus=6; minus=7; or=8; eql=9; neq=10; lss=11; leq=12; gtr=13;
		geq=14; in=15; is=16; ash=17; msk=18; len=19; conv=20; abs=21; cap=22; odd=23; not=33;
		Nvar=0; Nvarpar=1; Nfield=2; Nderef=3; Nindex=4; Nguard=5; Neguard=6; Nconst=7; Nproc=9;
		Nupto=10; Nmop=11; Ndop=12; Ncall=13; Ninittd=14; Nenter=18; Nassign=19; Nifelse=20;
		Ncase=21; Nwhile=22; Nrepeat=23; Nloop=24; Nexit=25; Nreturn=26; Nwith=27; Ntrap=28;

		Tend=00H; Telsif=01H; Telse=02H; Twend=03H; Tcastrap=04H; Tcaslbl1=05H; Tcasrng1=06H; Tcaslbl2=07H; Tcasrng2=08H;
		Tbegin=09H; TconstNil=00H; TconstFalse=01H; TconstTrue=02H; TconstChar=03H;
		TconstSInt=04H; TconstInt=05H; TconstLInt=06H; TconstSet=07H; TconstReal=08H; TconstLReal=09H; TconstString=0AH;
		Tderef=0BH; Tindex=0CH; TmopNot=0DH; TmopMinus=0EH; TmopAbs=0FH; TmopCap=10H; TmopOdd=11H;
		TdopAnd=12H; TdopOr=13H; TdopTimes=14H; TdopSlash=15H; TdopDiv=16H; TdopMod=17H;
		TdopPlus=18H; TdopMinus=19H; TdopMsk=1AH; TdopAsh=1BH; TdopLen=1CH; TdopIn=1DH;
		TdopEql=1EH; TdopNeq=1FH; TdopLss=20H; TdopLeq=21H; TdopGtr=22H; TdopGeq=23H; Tupto=24H;
		Tcall=25H; TasgnNewfn=26H; TasgnAssign=27H; TasgnIncfn=28H; TasgnDecfn=29H; TasgnInclfn=2AH; TasgnExclfn=2BH;
		TasgnCopyfn=2CH; Tassert=2DH; Tif=2EH; Tcase=2FH; Twhile=30H; Trepeat=31H; Tloop=32H; Texit=33H; Twith=34H; Ttrap=35H;
		Uvar=40H; Uvarpar=41H; Uproc=42H; Ufield=43H; Uguard=44H; Ueguard=45H; UmopIs=46H; UmopConv=47H; Uenter=48H; Ureturn=49H; 

		flgOK=0; flgNoLeft=-1; flgNoRight=-2; flgEnter=-3;
		MaxPar=21; MaxToken=Ureturn+1;

		L=0; G=1;
		Local=FALSE; Global=TRUE;
		Internal=FALSE; External=TRUE;
		super = 1;	

	(*Export/Use Section*)	
		EUEnd = 0X; EURecord = 1X; 

	VAR
		constNodeOT: ARRAY NilTyp+1 OF INTEGER;
		mopNodeOT: ARRAY not+1 OF INTEGER;
		dopNodeOT: ARRAY len+1 OF INTEGER;
		asgnNodeOT: ARRAY copyfn+1 OF INTEGER;
		nodeNodeOT: ARRAY Ntrap+1 OF INTEGER;

		(*global for each module being compiled*)
		above, below, minNod: LONGINT; notFound, globalNode: OPT.Node;
		nodePar: ARRAY 2, MaxPar OF OPT.Node; fullNode, partialNode: ARRAY 2, MaxToken OF OPT.Node;


	PROCEDURE NoTypSize*(typ: OPT.Struct; allocDesc: BOOLEAN);
	BEGIN	
		IF (typ.comp = Basic) & (typ.size > 0) THEN
		ELSE typ.size:=1; OPM.err(501)
		END
	END NoTypSize;

	PROCEDURE NoTypSizeF*(typ: OPT.Struct; allocDesc: BOOLEAN);
	BEGIN	
		IF (typ.comp = Basic) & (typ.size > 0) THEN (* do nothing *)
		ELSE typ.size:=1
		END
	END NoTypSizeF;

(*Node Dictionary*)

	PROCEDURE InitDict;
		VAR i, j: INTEGER; nL, nG: OPT.Node;
	BEGIN	i:=1; j:=0;
		WHILE	i < MaxPar	DO	NEW(nL); NEW(nG); nL.link:=nG; nG.link:=nL; nodePar[L, i]:=nL; nodePar[G, i]:=nG; INC(i)	END;
		WHILE	j < MaxToken	DO
			NEW(nL); NEW(nG); nL.link:=nG; nG.link:=nL; fullNode[L, j]:=nL; fullNode[G, j]:=nG;
			NEW(nL); NEW(nG); nL.link:=nG; nG.link:=nL; partialNode[L, j]:=nL; partialNode[G, j]:=nG;
			INC(j)
		END
	END InitDict;

	PROCEDURE PushDict;
		VAR i, j: INTEGER; n: OPT.Node;
	BEGIN	i:=1; j:=3;
		WHILE	i < MaxPar	DO	NEW(n); n.link:=nodePar[L, i].link; n.up:=nodePar[L, i].up; nodePar[L, i].up:=n; INC(i)	END;
		WHILE	j < MaxToken	DO
			NEW(n); n.link:=fullNode[L, j].link; n.up:=fullNode[L, j].up; fullNode[L, j].up:=n;
			NEW(n); n.link:=partialNode[L, j].link; n.up:=partialNode[L, j].up; partialNode[L, j].up:=n;
			INC(j)
		END;
		fullNode[L, 3].up.ref:=below
	END PushDict;

	PROCEDURE PopDict;
		VAR i, j: INTEGER;
	BEGIN	i:=1; j:=3;
		IF	below < minNod	THEN	minNod:=below	END;
		below:=fullNode[L, 3].up.ref;
		WHILE	i < MaxPar	DO	nodePar[L, i].link:=nodePar[L, i].up.link; nodePar[L, i].up:=nodePar[L, i].up.up; INC(i)	END;
		WHILE	j < MaxToken	DO
			fullNode[L, j].link:=fullNode[L, j].up.link; fullNode[L, j].up:=fullNode[L, j].up.up;
			partialNode[L, j].link:=partialNode[L, j].up.link; partialNode[L, j].up:=partialNode[L, j].up.up;
			INC(j)
		END
	END PopDict;


(*Node Tags*)

	PROCEDURE Tag(n: OPT.Node): INTEGER;
	BEGIN
		CASE	n.class	OF
		| Nconst:
				IF	n.typ#OPT.booltyp	THEN	RETURN constNodeOT[n.typ.form]
				ELSIF	n.conval.intval=0	THEN	RETURN TconstFalse	ELSE	RETURN TconstTrue	END
		| Nmop:	RETURN mopNodeOT[n.subcl]
		| Ndop:	RETURN dopNodeOT[n.subcl]
		| Nassign:	RETURN asgnNodeOT[n.subcl]
		| Nifelse:	IF	n.subcl=assertfn	THEN	RETURN Tassert	ELSE	RETURN Tif	END
		ELSE	RETURN nodeNodeOT[n.class]	END
	END Tag;


(*Node Creation*)

	PROCEDURE NewConstNode(VAR n: OPT.Node; tag: INTEGER; conval: OPT.Const);
	BEGIN	NEW(n); n.ref:=above; INC(above); n.link:=fullNode[G, tag].link; fullNode[G, tag].link:=n; n.conval:=conval; n.global:=TRUE
	END NewConstNode;

	PROCEDURE NNode(VAR n: OPT.Node; tag: INTEGER; typ: OPT.Struct; obj: OPT.Object; left, right: OPT.Node; global: BOOLEAN);
	BEGIN	NEW(n);
		IF	global	THEN	n.ref:=above; INC(above); n.link:=fullNode[G, tag].link; fullNode[G, tag].link:=n
		ELSE	n.ref:=below; DEC(below); n.link:=fullNode[L, tag].link; fullNode[L, tag].link:=n	END;
		n.typ:=typ; n.obj:=obj; n.left:=left; n.right:=right; n.global:=global; n.subcl := 0	
	END NNode;

	PROCEDURE UNodeO(tag: INTEGER; flag: SHORTINT; typ: OPT.Struct; obj: OPT.Object; global: BOOLEAN);
		VAR n: OPT.Node;
	BEGIN	NEW(n);
		IF	global	THEN	n.ref:=above; INC(above); n.link:=partialNode[G, tag].link; partialNode[G, tag].link:=n
		ELSE	n.ref:=below; DEC(below); n.link:=partialNode[L, tag].link; partialNode[L, tag].link:=n	END;
		n.flag:=flag; n.typ:=typ; n.obj:=obj; n.global:=global
	END UNodeO;

	PROCEDURE UNodeLR(tag: INTEGER; flag: SHORTINT; typ: OPT.Struct; left, right: OPT.Node; global: BOOLEAN);
		VAR n: OPT.Node;
	BEGIN	NEW(n);
		IF	global	THEN	n.ref:=above; INC(above); n.link:=partialNode[G, tag].link; partialNode[G, tag].link:=n
		ELSE	n.ref:=below; DEC(below); n.link:=partialNode[L, tag].link; partialNode[L, tag].link:=n	END;
		n.flag:=flag; n.typ:=typ; n.left:=left; n.right:=right; n.global:=global
	END UNodeLR;

	PROCEDURE PNode(VAR p: OPT.Node; remain, match: SHORTINT; par: OPT.Node; global: BOOLEAN);
		VAR n: OPT.Node;
	BEGIN	NEW(n);
		IF	global	THEN	n.ref:=above; INC(above); n.link:=nodePar[G, match].link; nodePar[G, match].link:=n
		ELSE	n.ref:=below; DEC(below); n.link:=nodePar[L, match].link; nodePar[L, match].link:=n	END;
		n.flag:=remain; n.subflg:=match; n.left:=p; n.right:=par; n.global:=global; p:=n
	END PNode;


(*Predef Nodes*)

	PROCEDURE NofPar(firstpar: OPT.Object): SHORTINT;
		VAR nofpar: SHORTINT;
	BEGIN	nofpar:=0;
		WHILE	firstpar#NIL	DO	INC(nofpar); firstpar:=firstpar.link	END;
		RETURN nofpar
	END NofPar;

	PROCEDURE VarNodes(n: OPT.Node; typ: OPT.Struct; global: BOOLEAN);
	BEGIN
		UNodeLR(TasgnAssign, flgNoLeft, NIL, NIL, n, global);
		UNodeLR(TasgnAssign, flgNoRight, NIL, n, NIL, global);
		IF	typ.form=Pointer	THEN
			NNode(n, Tderef, typ.BaseTyp, NIL, n, NIL, global)
		ELSIF	(typ.comp=Array) OR (typ.comp=DynArr)	THEN
			UNodeLR(Tindex, flgNoRight, typ.BaseTyp, n, NIL, global)
		END
	END VarNodes;

	PROCEDURE GenTProcs(obj: OPT.Object; btyp: OPT.Struct; external, global: BOOLEAN);	
		VAR n, p: OPT.Node; 
	BEGIN
		IF obj # NIL THEN
			GenTProcs(obj.left, btyp, external, global);
			IF obj.mode # Fld THEN
				NNode(p, Uproc, NIL, obj, NIL, NIL, global);  
				NNode(n, Tcall, NIL, obj.link, p, NIL, global); n.flag:=NofPar(obj.link);  
				NNode(n, Tcall, NIL, obj.link, p, NIL, global); n.flag:=NofPar(obj.link); n.subcl := super;  
				IF ~external THEN UNodeO(Uenter, flgEnter, NIL, obj, global) END;
			END;
			GenTProcs(obj.right, btyp, external, global)
		END
	END GenTProcs;

	PROCEDURE GenNodes(obj: OPT.Object; external, global: BOOLEAN);
		VAR n, dum: OPT.Node; fld: OPT.Object;
	BEGIN
		WHILE	obj#NIL	DO
			IF	obj.mode IN {Var, VarPar}	THEN
				IF	obj.mode=Var	THEN	NNode(n, Uvar, NIL, obj, NIL, NIL, global)
				ELSE	NNode(n, Uvarpar, NIL, obj, NIL, NIL, global)	END;
				IF	~external	THEN	VarNodes(n, obj.typ, global)	END
			ELSIF	obj.mode=Typ	THEN
				IF	(obj.typ.form=Pointer) OR (obj.typ.comp=Record)	THEN
					UNodeO(Uguard, flgNoLeft, obj.typ, NIL, global);
					UNodeO(Ueguard, flgNoLeft, obj.typ, NIL, global);
					UNodeO(UmopIs, flgNoLeft, obj.typ, NIL, global);
					IF	obj.typ.comp=Record	THEN	fld:=obj.typ.link;
						WHILE	fld#NIL	DO	(* mfix *)
							IF fld.mode = Fld THEN UNodeO(Ufield, flgNoLeft, NIL, fld, global) END;
							fld:=fld.link	
						END;
						GenTProcs(obj.typ.link, obj.typ.BaseTyp, external, global);
					END
				END
			ELSIF	obj.mode IN {LProc, XProc}	THEN
				NNode(n, Uproc, NIL, obj, NIL, NIL, global);
				NNode(n, Tcall, NIL, obj.link, n, NIL, global); n.flag:=NofPar(obj.link);
				IF	~external	THEN	UNodeO(Uenter, flgEnter, NIL, obj, global)	END
			ELSIF	(obj.mode=Con)&(obj.typ.form#Bool)	THEN	NewConstNode(dum, constNodeOT[obj.typ.form], obj.conval)	END;
			obj:=obj.nxtobj
		END
	END GenNodes;


(* Code Part *)

	PROCEDURE ^ EquivNode(n: OPT.Node): OPT.Node;

	PROCEDURE EquivCall(n: OPT.Node): OPT.Node;
		VAR match: SHORTINT; hd, p, proc, par, eqpar, up: OPT.Node;
	BEGIN	hd:=fullNode[L, Tcall]; p:=hd.link; proc:=EquivNode(n.left); hd.left:=proc;
		WHILE	(p#hd) & ((proc#p.left) OR (p.subcl#n.left.subcl))	DO	p:=p.link	END;	(* mfix *)
		IF	p=hd	THEN	RETURN notFound;	(*procedure object not found*)
		ELSE	par:=n.right; match:=1;
			WHILE	par#NIL	DO	up:=p; eqpar:=EquivNode(par);
				IF	eqpar=NIL	THEN	RETURN up	(*parameter not seen before*)
				ELSE	hd:=nodePar[L, match]; p:=hd.link; hd.left:=up; hd.right:=eqpar;
					WHILE	(up#p.left) OR (eqpar#p.right)	DO	p:=p.link	END;
					IF	p=hd	THEN	RETURN up	ELSE	par:=par.link;  INC(match)	END
				END
			END;
			RETURN p
		END
	END EquivCall;

	PROCEDURE EquivNewArg(n: OPT.Node): OPT.Node;
		VAR tag: INTEGER; hd, h0, h1, p, left, right: OPT.Node; 
	BEGIN	tag:=Tag(n); hd:=fullNode[L, tag]; p:=hd.link;
		IF	n.right=NIL	THEN	left:=EquivNode(n.left); hd.left:=left; WHILE	(left#p.left) OR (p.right#NIL)	DO	p:=p.link	END
		ELSE	
			left:=EquivNode(n.left);
			LOOP
				h0:=n.right; h1:=p.right;
				WHILE	(h0#NIL) & (h1#NIL) & (EquivNode(h0)=h1.left)	DO	h0:=h0.link; h1:=h1.right	END;
				IF	(p=hd) OR (left=p.left) & (h0=NIL) & (h1=NIL)	THEN	EXIT	END;
				p:=p.link
			END
		END;
		RETURN p;
	END EquivNewArg;

	PROCEDURE EquivNode(n: OPT.Node): OPT.Node;
		VAR tag: INTEGER; obj: OPT.Object; typ: OPT.Struct;
				hd, p, left, right: OPT.Node; intval: LONGINT; setval: SET; realval: LONGREAL; ext: OPT.ConstExt; 
	BEGIN	tag:=Tag(n); hd:=fullNode[L, tag]; p:=hd.link;
		CASE	tag	OF
		| TconstNil..TconstTrue:	RETURN notFound
		| TconstChar..TconstLInt:	hd.conval:=n.conval; p:=fullNode[G, tag].link; intval:=n.conval.intval;
				WHILE	intval#p.conval.intval	DO	p:=p.link	END
		| TconstSet:	hd.conval:=n.conval; p:=fullNode[G, TconstSet].link; setval:=n.conval.setval;
				WHILE	setval#p.conval.setval	DO	p:=p.link	END
		| TconstReal, TconstLReal:	hd.conval:=n.conval; p:=fullNode[G, tag].link; realval:=n.conval.realval;
				WHILE	realval#p.conval.realval	DO	p:=p.link	END
		| TconstString:	hd.conval:=n.conval; p:=fullNode[G, TconstString].link; ext:=n.conval.ext;
				WHILE	ext^#p.conval.ext^	DO	p:=p.link	END
		| Tderef, TmopNot..TmopOdd:	left:=EquivNode(n.left); hd.left:=left;
				WHILE	left#p.left	DO	p:=p.link	END
		| TasgnNewfn:	p:=EquivNewArg(n)
		| Tindex, TdopAnd..Tupto, TasgnIncfn..TasgnCopyfn:
				left:=EquivNode(n.left); right:=EquivNode(n.right); hd.left:=left; hd.right:=right;
				WHILE	(left#p.left) OR (right#p.right)	DO	p:=p.link	END
		| UmopConv, Uguard, Ueguard:	typ:=n.typ; left:=EquivNode(n.left); hd.typ:=typ; hd.left:=left;
				WHILE	(left#p.left) OR (typ#p.typ)	DO	p:=p.link	END
		| UmopIs:	typ:=n.obj.typ; left:=EquivNode(n.left); hd.typ:=typ; hd.left:=left;
				WHILE	(left#p.left) OR (typ#p.typ)	DO	p:=p.link	END
		| Uvar, Uvarpar, Uproc:	obj:=n.obj; hd.obj:=obj;
				WHILE	obj#p.obj	DO	p:=p.link	END
		| TasgnAssign:
				left:=EquivNode(n.left); right:=EquivNode(n.right); hd.left:=left; hd.right:=right;
				WHILE	(left#p.left) OR (right#p.right)	DO	p:=p.link	END
		| Ufield:	obj:=n.obj; left:=EquivNode(n.left); hd.obj:=obj; hd.left:=left;
				WHILE	(left#p.left) OR (obj#p.obj)	DO	p:=p.link	END
		| Ureturn:	obj:=n.obj;
				IF	obj.typ=OPT.notyp	THEN	hd.obj:=obj;
					WHILE	obj#p.obj	DO	p:=p.link	END
				ELSE	left:=EquivNode(n.left); hd.obj:=obj; hd.left:=left;
					WHILE	(left#p.left) OR (obj#p.obj)	DO	p:=p.link	END
				END
		| Uenter, Tassert..Ttrap:	RETURN notFound
		| Tcall:	p:=EquivCall(n);
				IF	p.flag=0	THEN	RETURN p	ELSE	RETURN notFound	END
		END;
		IF	p#hd	THEN	RETURN p	ELSE	RETURN notFound	END
	END EquivNode;

	PROCEDURE EquivHalfNode(n: OPT.Node): OPT.Node;
		VAR tag: INTEGER; obj: OPT.Object; typ: OPT.Struct; hd, p, left, right: OPT.Node;
	BEGIN	tag:=Tag(n); hd:=partialNode[L, tag]; p:=hd.link;
		CASE	tag	OF
		| TconstNil..TconstString, Tderef, TmopNot..TmopOdd, TasgnNewfn, Tassert..Ttrap:	RETURN notFound
		| Tindex, TdopAnd..Tupto, TasgnAssign..TasgnCopyfn:
				left:=EquivNode(n.left); right:=EquivNode(n.right); hd.left:=left; hd.right:=right;
				WHILE	(left#p.left) & (right#p.right)	DO	p:=p.link	END
		| UmopConv, Uguard, Ueguard:	typ:=n.typ; hd.typ:=typ;
				WHILE	typ#p.typ	DO	p:=p.link	END
		| UmopIs:	typ:=n.obj.typ; hd.typ:=typ;
				WHILE	typ#p.typ	DO	p:=p.link	END
		| Ufield, Uenter, Ureturn:	obj:=n.obj; hd.obj:=obj;
				WHILE	obj#p.obj	DO	p:=p.link	END
		| Tcall:	RETURN EquivCall(n)
		END;
		IF	p#hd	THEN	RETURN p	ELSE	RETURN notFound	END
	END EquivHalfNode;


	PROCEDURE ^ Expression(VAR n: OPT.Node);
	PROCEDURE ^ Statement(n: OPT.Node);

	PROCEDURE Sequence(n: OPT.Node);
	BEGIN	WHILE	n#NIL	DO	Statement(n); n:=n.link	END
	END Sequence;

	PROCEDURE Enter(VAR n: OPT.Node; left, right: OPT.Node);
		VAR dum: OPT.Node; proc: OPT.Object;
	BEGIN	proc:=n.obj;
		PushDict;
			IF	proc.typ=OPT.notyp	THEN	NNode(dum, Ureturn, NIL, proc, NIL, NIL, Local)
			ELSE	UNodeO(Ureturn, flgNoLeft, NIL, proc, Local)	END;
			OPT.objects:=proc.link;	(*parameters*)
			OPT.OutScope(proc.scope.right, FALSE); 
			GenNodes(OPT.objects, Internal, Local);	(*nested objects*)
			(*nested*)Sequence(left); OPM.SymW(CHR(Tbegin)); n.obj.inited:=TRUE;
			(*body*)Sequence(right); OPM.SymW(CHR(Tend));
		PopDict
	END Enter;


	PROCEDURE CompleteNode(VAR n: OPT.Node; tag: INTEGER; left, right: OPT.Node);
		VAR match, remain, skip: SHORTINT; par: OPT.Node;
	BEGIN
		IF	n.flag#flgOK	THEN
			IF	n.flag > 0	THEN	match:=n.subflg; remain:=n.flag; skip:=match;	(*params*)
				WHILE	skip > 0	DO	right:=right.link; DEC(skip)	END;
				WHILE	remain > 0	DO	par:=right; Expression(par);
					INC(match); DEC(remain); PNode(n, remain, match, par, n.global&par.global); right:=right.link
				END
			ELSE	(*partial node*)
				CASE	n.flag	OF
				| flgNoLeft:	Expression(left); NNode(n, tag, n.typ, n.obj, left, n.right, left.global&n.global)
				| flgNoRight:	Expression(right); NNode(n, tag, n.typ, n.obj, n.left, right, n.global&right.global)
				| flgEnter:	Enter(n, left, right)
				END
			END
		END
	END CompleteNode;

	PROCEDURE Expression(VAR n: OPT.Node);
		VAR tag: INTEGER; obj: OPT.Object; left, right, e, h: OPT.Node; conval: OPT.Const;
	BEGIN	obj:=n.obj; left:=n.left; right:=n.right; conval:=n.conval; tag:=Tag(n); e:=EquivNode(n);
		IF	e#notFound	THEN	OPM.SymWNum(e.ref); n:=e
		ELSE	h:=EquivHalfNode(n);
			IF	h#notFound	THEN	OPM.SymWNum(h.ref); CompleteNode(h, tag, left, right); n:=h
			ELSE	OPM.SymW(CHR(tag));
				CASE	tag	OF
				| TconstNil..TconstTrue:	n:=globalNode
				| TconstChar..TconstLInt:	OPM.SymWNum(conval.intval); NewConstNode(n, tag, conval)
				| TconstSet:	OPM.SymWSet(conval.setval); NewConstNode(n, TconstSet, conval)
				| TconstReal:	OPM.SymWReal(conval.realval); NewConstNode(n, TconstReal, conval)
				| TconstLReal:	OPM.SymWLReal(conval.realval); NewConstNode(n, TconstLReal, conval)
				| TconstString:	OPM.SymWString(conval.ext^); NewConstNode(n, TconstString, conval)
				| Tderef, TmopNot..TmopOdd:	Expression(left); NNode(n, tag, NIL, NIL, left, NIL, left.global)
				| Tindex, TdopAnd..Tupto:	Expression(left); Expression(right); NNode(n, tag, NIL, NIL, left, right, left.global&right.global)
				| Tcall:	Expression(left); NNode(n, Tcall, NIL, NIL, left, NIL, left.global); n.flag:=NofPar(obj); CompleteNode(n, Tcall, NIL, right)
				END
			END
		END
	END Expression;

	PROCEDURE ^ Statement(n: OPT.Node);

	PROCEDURE IfStat(n: OPT.Node; tag: INTEGER);
		VAR if, t: OPT.Node; obj: OPT.Object; typ: OPT.Struct; class: INTEGER;
	BEGIN	if:=n.left; OPM.errpos:=if.conval.intval; class:=if.left.class; Expression(if.left); 
		IF	(tag=Twith) & (class=Nmop)	THEN
			PushDict;
			obj:=if.left.left.obj; typ:=obj.typ; obj.typ:=if.left.typ;
			IF	obj.mode=Var	THEN	NNode(t, Uvar, NIL, obj, NIL, NIL, if.left.left.global)
			ELSE	NNode(t, Uvarpar, NIL, obj, NIL, NIL, if.left.left.global)	END;
			VarNodes(t, obj.typ, if.left.left.global);
		END;
		Sequence(if.right); if:=if.link;
		WHILE	if#NIL	DO	OPM.SymW(CHR(Telsif)); class:=if.left.class; Expression(if.left); 
			IF	(tag=Twith) & (class=Nmop)	THEN
				obj.typ:=typ; PopDict; PushDict;
				obj:=if.left.left.obj; typ:=obj.typ; obj.typ:=if.left.typ;
				IF	obj.mode=Var	THEN	NNode(t, Uvar, NIL, obj, NIL, NIL, if.left.left.global)
				ELSE	NNode(t, Uvarpar, NIL, obj, NIL, NIL, if.left.left.global)	END;
				VarNodes(t, obj.typ, if.left.left.global);
			END;
			Sequence(if.right); if:=if.link	END;
		IF	(n.class=Nwith) & (n.subcl=0)	THEN	OPM.SymW(CHR(Twend)); IF class=Nmop THEN obj.typ:=typ; PopDict END;
		ELSE
			IF	n.right#NIL	THEN	OPM.SymW(CHR(Telse)); 
			IF (tag=Twith) & (class=Nmop) THEN obj.typ:=typ; PopDict END;
			Sequence(n.right)	END;
			OPM.SymW(CHR(Tend))
		END
	END IfStat;

	PROCEDURE CaseStat(left, right: OPT.Node);
		VAR case, lab: OPT.Node;
	BEGIN	OPM.SymWNum(right.conval.intval); OPM.SymWNum(right.conval.intval2); Expression(left);
		IF	right.conval.setval={}	THEN	OPM.SymW(CHR(Tcastrap))	ELSE	Sequence(right.right)	END;
		case:=right.left;
		WHILE	case#NIL	DO	lab:=case.left;
			IF	lab.conval.intval=lab.conval.intval2	THEN	OPM.SymW(CHR(Tcaslbl1)); OPM.SymWNum(lab.conval.intval)
			ELSE	OPM.SymW(CHR(Tcasrng1)); OPM.SymWNum(lab.conval.intval); OPM.SymWNum(lab.conval.intval2)	END;
			lab:=lab.link;
			WHILE	lab#NIL	DO
				IF	lab.conval.intval=lab.conval.intval2	THEN	OPM.SymW(CHR(Tcaslbl2)); OPM.SymWNum(lab.conval.intval)
				ELSE	OPM.SymW(CHR(Tcasrng2)); OPM.SymWNum(lab.conval.intval); OPM.SymWNum(lab.conval.intval2)	END;
				lab:=lab.link
			END;
			Sequence(case.right); case:=case.link
		END;
		OPM.SymW(CHR(Tend))
	END CaseStat;

	PROCEDURE Statement(n: OPT.Node);
		VAR tag: INTEGER; obj: OPT.Object; left, right, e, h: OPT.Node;
	BEGIN	OPM.errpos:=n.conval.intval; obj:=n.obj; left:=n.left; right:=n.right; tag:=Tag(n); e:=EquivNode(n);
		IF	e#notFound	THEN	OPM.SymWNum(e.ref)
		ELSE	h:=EquivHalfNode(n);
			IF	h#notFound	THEN	OPM.SymWNum(h.ref); CompleteNode(h, tag, left, right)
			ELSE	OPM.SymW(CHR(tag));
				CASE	tag	OF
				| Tcall:	Expression(left); NNode(n, Tcall, NIL, NIL, left, NIL, left.global); n.flag:=NofPar(obj); CompleteNode(n, tag, NIL, right)
				| TasgnNewfn:	Expression(left); NNode(n, tag, NIL, NIL, left, NIL, left.global); 
					WHILE right#NIL DO h:=right; Expression(h); NEW(e); n.right:=e; e.left:=h; n:=e; right:=right.link END;
				| TasgnAssign..TasgnCopyfn:	Expression(left); Expression(right); NNode(n, tag, NIL, NIL, left, right, left.global&right.global)
				| Tif, Twith:	IfStat(n, tag)
				| Tcase:	CaseStat(left, right)
				| Twhile:	Expression(left); Sequence(right); OPM.SymW(CHR(Tend))
				| Trepeat:	Sequence(left); OPM.SymW(CHR(Tend)); Expression(right)
				| Tloop:	Sequence(left); OPM.SymW(CHR(Tend))
				| Texit:
				| Tassert:	OPM.SymWNum(left.right.right.conval.intval); Expression(left.left)
				| Ttrap:	OPM.SymWNum(right.conval.intval)
				| Uenter:	OPM.err(504)
				END
			END
		END
	END Statement;

	PROCEDURE Use(obj: OPT.Object);
		VAR typ: OPT.Struct; n, p: OPT.Node;	

		PROCEDURE UseTProc(obj: OPT.Object);
		BEGIN
			IF obj # NIL THEN
				UseTProc(obj.left);
				IF obj.used & (obj.mode = TProc) THEN
					OPM.SymWNum(obj.fp); OPM.SymWString(obj.name); 
					NNode(p, Uproc, NIL, obj, NIL, NIL, Global);  
					NNode(n, Tcall, NIL, obj.link, p, NIL, Global); n.flag:=NofPar(obj.link);  
					NNode(n, Tcall, NIL, obj.link, p, NIL, Global); n.flag:=NofPar(obj.link); n.subcl := super;  
				END;
				UseTProc(obj.right)
			END;
		END UseTProc;

		PROCEDURE UseRecord(typ: OPT.Struct);
			VAR fld: OPT.Object; mth: OPT.Object;
		BEGIN
			IF (typ.oref=0) & (typ.mno=OPT.modNo) THEN
				UNodeO(Uguard, flgNoLeft, typ, NIL, Global);
				UNodeO(Ueguard, flgNoLeft, typ, NIL, Global);
				UNodeO(UmopIs, flgNoLeft, typ, NIL, Global);
				OPM.SymW(EURecord); typ.oref:=-1; 	(* just mark *)
				OPT.FPrintTyp(typ);
				IF (typ.BaseTyp#NIL) & (typ.BaseTyp.strobj.used) THEN UseRecord(typ.BaseTyp) END;
				(* Methods not implemented here *)
				fld:=typ.link; mth := typ.link;
				WHILE fld#NIL DO
					IF (fld.used) & (fld.mode = Fld) THEN
						OPM.SymWNum(fld.fp); OPM.SymWString(fld.name);
						UNodeO(Ufield, flgNoLeft, NIL, fld, Global);
						typ:=fld.typ;
						WHILE (typ#NIL) & ((typ.form=Comp) & (typ.comp#Record) OR (typ.form=Pointer)) DO
							IF typ.form=Pointer THEN 
								UNodeO(Uguard, flgNoLeft, typ, NIL, Global);
								UNodeO(Ueguard, flgNoLeft, typ, NIL, Global);
								UNodeO(UmopIs, flgNoLeft, typ, NIL, Global);
							END;
							typ:=typ.BaseTyp
						END;
						IF (typ#NIL) & (typ.form=Comp) & (typ.comp=Record) THEN UseRecord(typ)
						END;
					END;
					fld:=fld.link;
				END;
				UseTProc(mth);	
				OPM.SymW(EUEnd);
			END
		END UseRecord;

	BEGIN
		IF obj#NIL THEN
			Use(obj.left);
			IF obj.used & (obj.vis#internal) THEN OPT.FPrintObj(obj);
				OPM.SymWNum(obj.fp); OPM.SymWString(obj.name);
				IF obj.mode=Var THEN NNode(n, Uvar, NIL, obj, NIL, NIL, Global)
				ELSIF obj.mode=XProc THEN 
					NNode(n, Uproc, NIL, obj, NIL, NIL, Global); 
					NNode(n, Tcall, NIL, obj.link, n, NIL, Global); n.flag:=NofPar(obj.link)
				ELSIF (obj.mode=Con) & (obj.typ.form#Bool) THEN 
					NewConstNode(n, constNodeOT[obj.typ.form], obj.conval)
				ELSIF obj.mode=CProc THEN OPM.err(503); RETURN
				END;
				IF (obj.mode=Typ) OR (obj.mode=Var) THEN
					typ:=obj.typ; 
					WHILE (typ#NIL) & ((typ.form=Comp) & (typ.comp#Record) OR (typ.form=Pointer)) DO 
						IF typ.form=Pointer THEN 
							UNodeO(Uguard, flgNoLeft, typ, NIL, Global);
							UNodeO(Ueguard, flgNoLeft, typ, NIL, Global);
							UNodeO(UmopIs, flgNoLeft, typ, NIL, Global);
						END;
						typ:=typ.BaseTyp 
					END;
					IF (typ#NIL) & (typ.form=Comp) & (typ.comp=Record) THEN UseRecord(typ) END;
				END;
			END;
			Use(obj.right);
		END					
	END Use;


	PROCEDURE Module*(prog: OPT.Node);
		VAR i: INTEGER; stat: OPT.Node; expSect: LONGINT;
	BEGIN	i:=1;
		WHILE	i < OPT.nofmod	DO	IF OPT.modules[i].used THEN OPT.OutMod(OPT.modules[i]) END; INC(i)	END;
		OPT.OutScope(OPT.topScope.right, FALSE);
		expSect:=OPM.SymWPos()+1;

		InitDict; below:=-1; above:=Ttrap+1; minNod:=0;
		UNodeO(UmopConv, flgNoLeft, OPT.chartyp, NIL, Global);
		UNodeO(UmopConv, flgNoLeft, OPT.sinttyp, NIL, Global);
		UNodeO(UmopConv, flgNoLeft, OPT.inttyp, NIL, Global);
		UNodeO(UmopConv, flgNoLeft, OPT.linttyp, NIL, Global);
		UNodeO(UmopConv, flgNoLeft, OPT.realtyp, NIL, Global);
		UNodeO(UmopConv, flgNoLeft, OPT.lrltyp, NIL, Global);
		UNodeO(UmopConv, flgNoLeft, OPT.settyp, NIL, Global);

		GenNodes(OPT.objects, Internal, Global);
		
		i:=1; WHILE i<OPT.nofmod DO
			IF OPT.modules[i].used THEN
				OPM.SymWString(OPT.modules[i].name); OPT.modNo:=i;
				Use(OPT.modules[i].right); OPM.SymW(EUEnd);
			END;
			INC(i)
		END;
		OPM.SymW(EUEnd);

		IF OPM.noerr THEN
			stat:=prog.right;
			WHILE	(stat#NIL)&(stat.class=Ninittd)	DO	stat:=stat.link	END;
			Sequence(prog.left); OPM.SymW(CHR(Tbegin)); Sequence(stat);
	
			IF OPM.noerr THEN
				OPM.ObjWNum(expSect); OPM.ObjWNum(-minNod); OPM.ObjWNum(above); OPM.EndObj;
				OPM.LogW(9X); OPM.LogWNum(-minNod+above, 10)
			END
		END
	END Module;


BEGIN
	NEW(notFound); NEW(globalNode); globalNode.global:=Global;

(*node tags*)
	constNodeOT[Char]:=TconstChar;
	constNodeOT[SInt]:=TconstSInt; constNodeOT[Int]:=TconstInt; constNodeOT[LInt]:=TconstLInt;
	constNodeOT[Real]:=TconstReal; constNodeOT[LReal]:=TconstLReal; constNodeOT[Set]:=TconstSet;
	constNodeOT[String]:=TconstString; constNodeOT[NilTyp]:=TconstNil;
	mopNodeOT[not]:=TmopNot; mopNodeOT[minus]:=TmopMinus; mopNodeOT[is]:=UmopIs; mopNodeOT[conv]:=UmopConv;
	mopNodeOT[abs]:=TmopAbs; mopNodeOT[cap]:=TmopCap; mopNodeOT[odd]:=TmopOdd;
	dopNodeOT[times]:=TdopTimes; dopNodeOT[slash]:=TdopSlash; dopNodeOT[div]:=TdopDiv; dopNodeOT[mod]:=TdopMod;
	dopNodeOT[and]:=TdopAnd; dopNodeOT[or]:=TdopOr; dopNodeOT[plus]:=TdopPlus; dopNodeOT[minus]:=TdopMinus;
	dopNodeOT[eql]:=TdopEql; dopNodeOT[neq]:=TdopNeq;
	dopNodeOT[lss]:=TdopLss; dopNodeOT[leq]:=TdopLeq; dopNodeOT[gtr]:=TdopGtr; dopNodeOT[geq]:=TdopGeq;
	dopNodeOT[in]:=TdopIn; dopNodeOT[ash]:=TdopAsh; dopNodeOT[msk]:=TdopMsk; dopNodeOT[len]:=TdopLen;
	asgnNodeOT[assign]:=TasgnAssign; asgnNodeOT[newfn]:=TasgnNewfn;
	asgnNodeOT[incfn]:=TasgnIncfn; asgnNodeOT[decfn]:=TasgnDecfn;
	asgnNodeOT[inclfn]:=TasgnInclfn; asgnNodeOT[exclfn]:=TasgnExclfn;
	asgnNodeOT[copyfn]:=TasgnCopyfn;
	nodeNodeOT[Nvar]:=Uvar; nodeNodeOT[Nvarpar]:=Uvarpar;
	nodeNodeOT[Nfield]:=Ufield; nodeNodeOT[Nderef]:=Tderef; nodeNodeOT[Nindex]:=Tindex;
	nodeNodeOT[Nguard]:=Uguard; nodeNodeOT[Neguard]:=Ueguard; nodeNodeOT[Nproc]:=Uproc;
	nodeNodeOT[Nupto]:=Tupto; nodeNodeOT[Ncall]:=Tcall; nodeNodeOT[Nenter]:=Uenter;
	nodeNodeOT[Nifelse]:=Tif; nodeNodeOT[Ncase]:=Tcase; nodeNodeOT[Nwhile]:=Twhile; nodeNodeOT[Nrepeat]:=Trepeat;
	nodeNodeOT[Nloop]:=Tloop; nodeNodeOT[Nexit]:=Texit; nodeNodeOT[Nreturn]:=Ureturn;
	nodeNodeOT[Nwith]:=Twith; nodeNodeOT[Ntrap]:=Ttrap
END JOCV.