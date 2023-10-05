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

MODULE RXA;	(** portable *)	(* Andreas Margelisch, 1990 *)

IMPORT  Texts;

CONST
	tab = 9; cr = 13; blank = 32; dq = 34;

	(* values for tokenval *)

	shorthand = -1;
	metasymbol = -2;
	literal = -3;
	msalternation = -4;
	msopenpar = -5;
	msclosepar = -6;
	msopenquo = -7;
	msclosequo = -8;
	mssubexpr = -9;

	mult = 4;
	nofSET = MAX(SET) + 1;
	nofpos = mult * nofSET;
	nofstates = 128;
	nofchar = 134;
	nofsubexpr = 10;

	undefined= - 1;

	inoffset = 10;
	endoffset = 20;

	spezchar = 134;

	(* Error Codes  : errorcode >= 0 means CHR(errorval) expected *)

	noerror* = 0; (* Kein Fehler *)
	noposfree* = -1; (* position array  ist voll *)
	nostatesfree* = -2; (* states array  ist voll *)
	nometaexp* = -3; (* Unerwartetes Metasymbol gefunden *)
	chrleft* = -4; (* Mindestens eine schliessende Klammer ")", "]", "}" zuviel *)
	wsubexpr* = -5; (* Falscher Teilausdruck-Identifier *)
	subexprrest* = -6; (* Teilausdruck von { }-Klammernpaar umgeben *)
	wshorthand* = -7; (* Falscher Abkürzungs-Identifier *)
	notnotexp* = -8; (* Notoperator kann nicht angewendet werden *)
	nodfa* = -9; (* Replace unmöglich, da kein DFA vorhanden *)
	repllinefull* = -10; (* Parameter line bei Replace ist voll *)
	linecopofl* = -11; (* Interne Variable linecop in Prozedur Replace ist zu klein *)


TYPE PosSet = ARRAY (mult) OF SET;

		NodePtr = POINTER TO Node;

		Node = RECORD
			pos : INTEGER;
			ch : CHAR;
			nullable : BOOLEAN;
			first, last : PosSet;
			nextl, nextr : NodePtr
		END;

		PosDesc = RECORD
			ch : CHAR;
			shorthand, notoperator : BOOLEAN;
			follow : PosSet
		END;

		PosArray = ARRAY(nofpos) OF PosDesc;

		SubExprDesc = RECORD
			nodeptr : NodePtr;
			spos, epos : INTEGER;
			follow : PosSet
		END;

		DFASubExprDesc = RECORD
			set : BOOLEAN;
			beg, end : INTEGER
		END;

		TransDesc = RECORD
			state : INTEGER;
			subset : SET
		END;

		DFA* = POINTER TO DFADesc;

		DFADesc = RECORD
			nofst : INTEGER;
			subdetect : BOOLEAN;
			trans : ARRAY (nofstates),(nofchar+1) OF TransDesc;
			accepted : ARRAY (nofstates) OF BOOLEAN;
			sub : ARRAY (nofsubexpr) OF DFASubExprDesc
		END;

		Line = ARRAY MAX( INTEGER ) OF CHAR;


VAR
	rxl : Line;	(* LinePtr *)
	rxpos, tokenval, treepos, errorvar, countflag : INTEGER;
	lookahead : CHAR;
	pd : POINTER TO PosArray;
	subexpr : ARRAY (nofsubexpr) OF SubExprDesc;
	subdetect, notflag, inkleene, inquotes, first : BOOLEAN;

(* set operations for TYPE PosSet *)

 PROCEDURE PSEmpty( VAR set : PosSet );
 	VAR i : INTEGER;
 BEGIN
 	i := 0; WHILE i < mult DO set[i] := {}; INC(i) END
 END PSEmpty;

 PROCEDURE PSIsEmpty( set : PosSet ) : BOOLEAN;
 VAR i : INTEGER;
 BEGIN
 	i := 0; WHILE i < mult DO IF set[i] # {} THEN RETURN FALSE END; INC(i) END;
 	RETURN TRUE
 END PSIsEmpty;

 PROCEDURE PSIsEqual( set1, set2 : PosSet ) : BOOLEAN;
 	VAR i : INTEGER;
 BEGIN
 	i := 0; WHILE i < mult DO IF set1[i] # set2[i] THEN RETURN FALSE END; INC(i) END;
 	RETURN TRUE
 END PSIsEqual;

 PROCEDURE PSIn( set : PosSet; v : INTEGER ) : BOOLEAN;
 BEGIN
 	RETURN ( v MOD nofSET ) IN set[v DIV nofSET]
 END PSIn;

 PROCEDURE PSIncl( VAR set : PosSet; v : INTEGER );
 BEGIN
 	INCL( set[v DIV nofSET], v MOD nofSET )
 END PSIncl;

 PROCEDURE PSUnion( set1, set2 : PosSet; VAR resset : PosSet );
 	VAR i : INTEGER;
 BEGIN
 	i := 0; WHILE i < mult DO resset[i] := set1[i] + set2[i]; INC(i) END
 END PSUnion;


 PROCEDURE GetChar(): CHAR;
 	VAR ch: CHAR;
 BEGIN
 	ch := rxl[rxpos];
 	CASE countflag OF
 		0 : IF (ch = 0X) OR (rxpos >= LEN(rxl (* ^ *)) ) THEN INC( countflag ); RETURN ")"
 			 ELSE INC(rxpos); RETURN ch
 			 END |
 		1 : INC( countflag ); RETURN ("#") |
 	ELSE
 		IF errorvar = chrleft THEN errorvar := noerror END; RETURN("#")
 	END
 END GetChar;

 PROCEDURE SetPosition ( ptr : NodePtr; chr : CHAR );
 BEGIN
 	IF treepos < nofpos THEN
 		ptr.pos := treepos;
 		PSIncl( ptr.first, treepos );
 		PSIncl( ptr.last, treepos );
 		ptr.nullable := FALSE;
 		pd[treepos].ch := chr;
 		pd[treepos].shorthand := tokenval = shorthand;
 		pd[treepos].notoperator := notflag;
 		PSEmpty(pd[treepos].follow);
 		INC(treepos)
 	ELSE
 		errorvar := noposfree
 	END
END SetPosition;

PROCEDURE NewNode( VAR ptr : NodePtr );
BEGIN
	NEW(ptr);
	PSEmpty(ptr.first);
	PSEmpty(ptr.last);
	ptr.nextr := NIL;
	ptr.nextl := NIL;
	ptr.ch := lookahead;
	CASE tokenval OF
		literal : SetPosition( ptr, ptr.ch ) |
		shorthand : SetPosition( ptr, ptr.ch )
	ELSE (* metasymbol *)
		ptr.pos := metasymbol
	END;
	notflag := FALSE
END NewNode;

PROCEDURE LexAn():CHAR;
	VAR ch : CHAR;
BEGIN
	ch := GetChar();
	IF ~inquotes THEN WHILE (ORD(ch) = blank) OR (ORD( ch ) = cr ) OR ( ORD( ch ) = tab ) DO ch := GetChar() END END;
	IF ~first & ( ORD(ch) =  dq ) THEN inquotes := ~inquotes;
		IF inquotes THEN first := TRUE; tokenval := msopenquo ELSE tokenval := msclosequo END
	ELSE
		IF inquotes THEN
			tokenval := literal; first := FALSE
		ELSE
			CASE ch OF
				"A", "a", "b", "c", "d", "h", "i", "l", "o", "t", "w" : tokenval := shorthand |
				"X" : ch := GetChar(); tokenval := mssubexpr;
						 IF ( ch < "0" ) OR ( ch > "9" ) THEN errorvar := wsubexpr END |
				"{", "(", "[" : tokenval := msopenpar |
				"}", ")", "]" : tokenval := msclosepar |
				"|" : tokenval := msalternation |
				"~" : notflag := ~notflag; ch := LexAn();
						IF ( tokenval # msopenquo ) & ( tokenval # shorthand ) THEN errorvar := notnotexp END
			ELSE
				tokenval := literal;
				IF (ch # "#") OR ( countflag = 0 ) THEN errorvar := wshorthand END
			END
		END;
	END;
	RETURN ch
END LexAn;

PROCEDURE Match( ch : CHAR );
BEGIN
	IF ( errorvar = chrleft ) OR ( errorvar = noerror ) THEN
		IF lookahead = ch THEN
			lookahead := LexAn()
		ELSE
			errorvar := ORD(ch)
		END
	END;
END Match;

PROCEDURE InitSubExpr( ptr : NodePtr; spos : INTEGER; kleenef : BOOLEAN );
	VAR ind : INTEGER;
BEGIN
	IF kleenef THEN
		errorvar := subexprrest
	ELSE
		subdetect := TRUE;
		ind := ORD(lookahead) - ORD("0");
		Match( lookahead );
		subexpr[ind].nodeptr := ptr;
		subexpr[ind].spos := spos;
		subexpr[ind].epos := treepos;
		PSEmpty( subexpr[ind].follow )
	END
END InitSubExpr;

PROCEDURE^ Term( VAR ptr : NodePtr );
PROCEDURE^ Factor( VAR ptr : NodePtr );

PROCEDURE RegExpr( VAR ptr : NodePtr );
	VAR np : NodePtr;
BEGIN
	Term( ptr );
	WHILE ( tokenval = msalternation ) & (errorvar = chrleft) DO
		NewNode( np );
		Match( "|" );
		np.nextl := ptr;
		ptr := np;
		Term( ptr.nextr )
	END
END RegExpr;

PROCEDURE Term( VAR ptr : NodePtr );
	VAR np : NodePtr; tv : INTEGER; lh : CHAR;
BEGIN
	Factor( ptr );
	WHILE ( tokenval # msclosepar ) & ( tokenval # msclosequo ) & ( tokenval # msalternation ) & (errorvar = chrleft ) DO
		tv := tokenval; lh := lookahead;
		tokenval := metasymbol;
		lookahead := "u";
		NewNode( np );
		tokenval := tv; lookahead := lh;
		np.nextl := ptr;
		ptr := np;
		Factor( ptr.nextr )
	END
END Term;

PROCEDURE Factor( VAR ptr : NodePtr );
	VAR tpos : INTEGER;
		kleenef, not : BOOLEAN;
BEGIN
	kleenef := inkleene;
	tpos := treepos;
	CASE tokenval OF
		msopenpar :
			CASE lookahead OF
				"{" : inkleene := TRUE; NewNode( ptr ); Match( "{" ); ptr.ch := "{"; RegExpr( ptr.nextl ); Match( "}" );
						inkleene := FALSE |
				"[" : NewNode( ptr ); Match( "[" ); ptr.ch := "["; RegExpr( ptr.nextl ); Match( "]" ) |
				"(" : Match( "(" ); RegExpr( ptr ); Match( ")" )
			ELSE
			END |
		msopenquo : not := notflag; Match(CHR(dq)); RegExpr( ptr ); Match(CHR(dq));
							 IF not & ( treepos - tpos > 1 ) THEN errorvar := notnotexp END |
		shorthand, literal : NewNode( ptr ); Match( lookahead )
	ELSE errorvar := nometaexp
	END;
	IF ( errorvar = chrleft ) & ( tokenval = mssubexpr ) THEN InitSubExpr( ptr, tpos, kleenef ) END
END Factor;

PROCEDURE CalcFiLa( ptr : NodePtr );
BEGIN
	IF ( ptr.nextl # NIL ) & (ptr.nextl.pos = metasymbol) THEN CalcFiLa( ptr.nextl ) END;
	IF ( ptr.nextr # NIL ) & (ptr.nextr.pos = metasymbol) THEN CalcFiLa( ptr.nextr ) END;
	CASE ptr.ch OF
		"|" : ptr.nullable := ptr.nextl.nullable OR ptr.nextr.nullable;
			PSUnion(ptr.nextl.first, ptr.nextr.first, ptr.first);
			PSUnion(ptr.nextl.last, ptr.nextr.last, ptr.last) |
		"{", "[" : ptr.nullable := TRUE;
			ptr.first := ptr.nextl.first;
			ptr.last := ptr.nextl.last |
		"u" : ptr.nullable := ptr.nextl.nullable & ptr.nextr.nullable;
			ptr.first := ptr.nextl.first;
			IF ptr.nextl.nullable THEN PSUnion(ptr.first,ptr.nextr.first, ptr.first) END;
			ptr.last := ptr.nextr.last;
			IF ptr.nextr.nullable THEN PSUnion(ptr.last,ptr.nextl.last, ptr.last )END
	END
END CalcFiLa;

PROCEDURE CalcFollow( ptr : NodePtr );
	VAR j : INTEGER;
BEGIN
	IF ( ptr.nextl # NIL ) & (ptr.nextl.pos = metasymbol) THEN CalcFollow( ptr.nextl ) END;
	IF ( ptr.nextr # NIL ) & (ptr.nextr.pos = metasymbol) THEN CalcFollow( ptr.nextr ) END;
	CASE ptr.ch OF
		"{" :
			j := 0;
			WHILE j < treepos DO
				IF PSIn( ptr.last, j )THEN PSUnion(pd[j].follow, ptr.first, pd[j].follow )END;
				INC(j)
			END | (* WHILE*)
		"u" :
			j := 0;
			WHILE j < treepos DO
				IF PSIn( ptr.nextl.last, j ) THEN PSUnion( pd[j].follow, ptr.nextr.first, pd[j].follow ) END;
				INC(j)
			END (* WHILE*)
	ELSE (* alternation *)
	END
END CalcFollow;

PROCEDURE CalcFollowSubExpr;
	VAR i, j : INTEGER;
BEGIN
	i := 0;
	WHILE i < nofsubexpr DO
		IF subexpr[i].nodeptr # NIL THEN
			j := 0;
			WHILE j < treepos DO
				IF PSIn( subexpr[i].nodeptr.last, j ) THEN PSUnion( subexpr[i].follow, pd[j].follow, subexpr[i].follow ) END;
				INC(j)
			END
		END;
		INC(i)
	END; (* WHILE*)
END CalcFollowSubExpr;

PROCEDURE SetState( dfa : DFA; set : PosSet; VAR ind : INTEGER; VAR ps : ARRAY OF PosSet );
	VAR i, k : INTEGER;
BEGIN
	ind := 0;
	WHILE ind < dfa.nofst DO
		IF PSIsEqual( ps[ind],  set ) THEN RETURN ELSE INC(ind) END
	END;
	IF dfa.nofst  < nofstates THEN
		ps[dfa.nofst] := set;
		dfa.accepted[dfa.nofst] := PSIn( set, treepos -1 );
		IF ( dfa.accepted[dfa.nofst] ) & subdetect THEN
			k := 0;
			WHILE k < nofsubexpr DO
				IF subexpr[k].nodeptr # NIL THEN
					IF PSIsEqual( subexpr[k].follow, ps[dfa.nofst] ) THEN INCL( dfa.trans[ dfa.nofst, spezchar].subset,  k + endoffset ) END
				END;
				INC(k)
			END
		END;
		i := 0; WHILE i < nofchar DO dfa.trans[dfa.nofst, i].state := undefined; dfa.trans[dfa.nofst, i].subset := {}; INC(i) END;
		INC( dfa.nofst )
	ELSE
		errorvar := nostatesfree
	END
END SetState;

PROCEDURE ChrIn( sid : CHAR; ch : INTEGER; short : BOOLEAN ) : BOOLEAN;
BEGIN
	IF short THEN
		CASE sid OF
			"A" : RETURN ( ORD("A") <= ch ) & ( ch <= ORD("Z")) |
			"a" : RETURN ( ORD("a") <= ch ) & ( ch <= ORD("z")) |
			"b" : RETURN ( ORD("0") <= ch ) & ( ch <= ORD("1")) |
			"c" : RETURN ( ch = cr ) |
			"d" : RETURN ( ORD("0") <= ch ) & ( ch <= ORD("9")) |
			"h" : RETURN ( ChrIn( "d", ch, TRUE )) OR (( ORD("A") <= ch ) & ( ch <= ORD("F"))) |
			"i" : RETURN ChrIn( "l", ch, TRUE ) OR ChrIn( "d", ch, TRUE ) |
			"l" :  RETURN ( ChrIn( "A", ch, TRUE ) ) OR ( ChrIn( "a", ch, TRUE ) ) |
			"o" : RETURN ( ORD("0") <= ch ) & ( ch <= ORD("7")) |
			"t" : RETURN ( ch = tab ) |
			"w" : RETURN ( ch = tab ) OR ( ch = cr ) OR ( ch = blank )
		ELSE RETURN FALSE
		END
	ELSE RETURN sid = CHR( ch )
	END
END ChrIn;

PROCEDURE CalcStates(  dfa : DFA; anchor : NodePtr );
	VAR j, k, ind, unmark, index : INTEGER;
		ps : ARRAY (nofstates) OF PosSet;
		compstates : ARRAY (nofchar) OF PosSet;
		ch : CHAR;
		not, short : BOOLEAN;
		hset, set : SET;


	PROCEDURE HandleSubExpr( pos : INTEGER ) : SET;
		VAR set : SET;
			insub : BOOLEAN;
			k : INTEGER;

	BEGIN
		set := {}; k := 0;
		WHILE k < nofsubexpr DO
			IF subexpr[k].nodeptr # NIL THEN
				insub := (  subexpr[k].spos <= pos ) & ( pos < subexpr[k].epos );
				IF PSIn( subexpr[k].nodeptr.first, pos ) THEN INCL( set, k ) END;
				IF insub THEN INCL( set, k + inoffset ) END;
				IF ~insub & PSIn( subexpr[k].follow, pos ) THEN  INCL( set, k + endoffset ) END
			END;
			INC(k)
		END;
		RETURN set
	END HandleSubExpr;

BEGIN
	dfa.nofst := 0; unmark := 0; j := 0;
	WHILE j < nofchar DO PSEmpty( compstates[j] ); INC(j) END;
	SetState( dfa, anchor.first, ind, ps );
	WHILE unmark < dfa.nofst DO
		j := 0;
		WHILE j <  treepos DO
			IF PSIn( ps[unmark], j ) THEN
				not := pd[j].notoperator; short := pd[j].shorthand;
				IF short OR not THEN
					k := 0; ch := pd[j].ch; first := TRUE;
					WHILE k < nofchar DO
						IF ( ~ChrIn( ch, k, short ) & not ) OR ( ChrIn( ch, k, short ) & ~not ) THEN
							IF subdetect THEN
								IF first THEN set := HandleSubExpr( j ); first := FALSE END;
								hset := dfa.trans[unmark, k].subset; hset := set + hset; dfa.trans[unmark, k].subset := hset
							END;
							PSUnion( compstates[k], pd[j].follow, compstates[k] )
						END;
						INC(k)
					END
				ELSE
					index := ORD(pd[j].ch);
					IF subdetect THEN
						hset := dfa.trans[unmark, index].subset; hset := HandleSubExpr( j ) + hset; dfa.trans[unmark, index].subset := hset
					END;
					PSUnion( compstates[index], pd[j].follow, compstates[index] )
				END
			END;
			INC(j)
		END;
		j := 1; (* CHR(0) is reserved for EOS *)
		WHILE j < nofchar DO
			IF ~PSIsEmpty(compstates[j]) THEN
				SetState( dfa, compstates[j], ind, ps );
				dfa.trans[unmark, j].state := ind;
				PSEmpty( compstates[j] )
			END;
			INC(j)
		END;
		INC(unmark)
	END
END CalcStates;

PROCEDURE Dump*( dfa : DFA; VAR w : Texts.Writer );
(* Druckt den zu dfa gehörigen Automaten im System.Log Viewer aus. *)

	VAR i, j : INTEGER;
BEGIN
	Texts.WriteLn( w ); Texts.WriteString(w, " D F A "); Texts.WriteLn( w ); Texts.WriteLn( w );
	i := 0;
	WHILE i < dfa.nofst DO
		IF dfa.accepted[i] THEN Texts.WriteString( w, "accepted ") ELSE Texts.WriteString(w, "not accepted ") END;
		Texts.WriteString(w, "State "); Texts.WriteInt(w, i, 3); Texts.WriteString(w, " : "); Texts.WriteLn( w );
		j := 0;
		WHILE j < nofchar DO
			IF dfa.trans[i,j].state # undefined THEN
				Texts.WriteString(w, "( chr = "); Texts.Write(w, CHR(j)); Texts.WriteString(w, ", ORD = "); Texts.WriteInt(w,  j, 4 );
				Texts.WriteString(w, ", newstate = "); Texts.WriteInt(w, dfa.trans[i,j].state,2); Texts.WriteString(w, " )");
				Texts.WriteLn( w )
			END;
			INC(j)
		END;
		Texts.WriteLn( w );
		INC(i)
	END;
	Texts.WriteString( w, "end of dump" ); Texts.WriteLn( w )
END Dump;

PROCEDURE New*( rx : ARRAY OF CHAR; VAR dfa : DFA; VAR error, pos : INTEGER);
(*
		Konstruiert den passenden deterministischen endlichen Automaten dfa zum regulären Ausdruck rx.
		error > 0	:	character ( CHR( error ) ) wird an der Position pos in rx verlangt.
		error = 0	:	Automat konstruiert.
		error < 0	:	error enthält den Wert der entsprechenden Fehlerkonstante des in rx an der
								Position pos aufgetretenen Fehlers.
*)

	VAR
		i : INTEGER;
		anchor : NodePtr;
BEGIN
	NEW( dfa );
	NEW( pd );
	i := 0; WHILE i < nofsubexpr DO subexpr[i].nodeptr := NIL; INC(i) END;
	rxpos := 0;
	treepos := 0;
	countflag := 0;
	errorvar := chrleft;
	subdetect := FALSE; notflag := FALSE; inkleene := FALSE; inquotes := FALSE; first := FALSE;
	COPY(rx, rxl); (* rxl := SYSTEM.VAL( LinePtr, SYSTEM.ADR(rx) ); *)
	lookahead := "(";
	tokenval := msopenpar;
	anchor := NIL;
	RegExpr( anchor );
	IF inquotes THEN errorvar := dq END;
	IF errorvar = noerror THEN
		CalcFiLa( anchor );
		CalcFollow( anchor );
		IF subdetect THEN CalcFollowSubExpr END;
		CalcStates( dfa, anchor );
		dfa.subdetect := subdetect;
		i := 0;
		WHILE i < nofsubexpr DO dfa.sub[i].set := subexpr[i].nodeptr # NIL; INC(i) END
	END;
	(* rxl := NIL *)
	FOR i := 0 TO LEN(rxl)-1 DO rxl[i] := 0X END;
	anchor := NIL;
	error := errorvar;
	IF error # noerror THEN pos := rxpos; dfa := NIL; RETURN END
END New;

PROCEDURE Search*( dfa : DFA; line : ARRAY OF CHAR; VAR beg, end : INTEGER );
(*
		Sucht in line ab der Position beg den durch dfa bestimmten regulären Ausdruck.
		end >= 0	:	[beg, end[ ist der erste ( ab Suchposition beg ) und längste Bereich, der dem
							  gesuchten reglären Ausdruck entspricht.
		end < 0	  :	Regulärer Ausdruck in line nicht gefunden.
*)

	VAR state, i, pos, ch : INTEGER;
		len : LONGINT;
		block : ARRAY( nofsubexpr ) OF BOOLEAN;

	PROCEDURE SavePos( subset : SET; state : INTEGER );
		VAR i : INTEGER;
	BEGIN
		i := 0;
		WHILE i < nofsubexpr DO
			IF ( ~ block[i] ) & ( state # undefined ) THEN
				IF ( i IN subset ) & ( dfa.sub[i].beg = undefined ) THEN dfa.sub[i].beg := pos END;
				IF ~block[i] & ( dfa.sub[i].beg # undefined ) THEN
					IF ( i + endoffset IN subset ) THEN
						dfa.sub[i].end := pos
					ELSIF dfa.accepted[state] & (i + endoffset IN dfa.trans[state, spezchar].subset ) THEN
						dfa.sub[i].end := pos + 1
					END
				END;
				IF ( dfa.sub[i].beg # undefined ) & (~( i + inoffset IN subset ) ) THEN
					IF dfa.sub[i].end = undefined THEN dfa.sub[i].beg := undefined ELSE block[i] := TRUE END
				END
			END;
			INC(i)
		END
	END SavePos;

	PROCEDURE SearchRX( subexp : BOOLEAN );
	BEGIN
		len := LEN(line);
		end := undefined;
		WHILE ( end = undefined ) & ( beg < len ) & ( line[beg] # 0X) DO
			pos := beg;
			state := 0;
			LOOP
				ch := ORD(line[pos]);
				IF dfa.accepted[state] THEN end := pos END;
				IF ( pos >= len) OR (ch = 0) THEN EXIT END;
				IF subexp THEN SavePos( dfa.trans[state, ch].subset, dfa.trans[state, ch].state ) END;
				state := dfa.trans[state, ch].state;
				IF state = undefined THEN EXIT END;
				INC(pos)
			END; (* LOOP *)
			INC(beg)
		END;
		DEC(beg)
	END SearchRX;

BEGIN
	IF dfa # NIL THEN
		SearchRX( FALSE );
		IF dfa.subdetect & ( end  # undefined ) THEN
			i := 0;
			WHILE i < nofsubexpr DO dfa.sub[i].beg := undefined; dfa.sub[i].end := undefined; block[i] := ~dfa.sub[i].set; INC(i) END;
			SearchRX( TRUE )
		END
	END;
END Search;

PROCEDURE Replace*( dfa : DFA; VAR line : ARRAY OF CHAR; replpat : ARRAY OF CHAR;
										beg, end : INTEGER; VAR error, pos : INTEGER );
(*
		Ersetzt das Stück [beg, end[ in line durch replpat. linecop muss eine Kopie von line sein.
		error > 0	:	character ( CHR( error ) ) wird an der Position pos in replpat verlangt. line bleibt unverändert.
		error = 0	:	replace erfolgreich, das Stück [beg, end[ in line wurde durch ein Stück [beg, pos[
							   ersetzt.
		error < 0	:	error enthält den Wert der entsprechenden Fehlerkonstante des in replpat an der
							   Position pos aufgetretenen Fehlers. line bleibt unverändert.
*)

	CONST noofchar = 1024;
	VAR lineind, replind, ind, spos : INTEGER;
		ch : CHAR;
		EORPL, linefull, first, inquotes : BOOLEAN;
		linecop : ARRAY (noofchar) OF CHAR;

	PROCEDURE GetCh() : CHAR;
		VAR ch : CHAR;
	BEGIN
		ch := replpat[replind];
		IF (replind < LEN( replpat ) ) & (ch # 0X) THEN EORPL := FALSE; INC(replind) ELSE EORPL := TRUE END; RETURN ch
	END GetCh;

	PROCEDURE LexAn():CHAR;
		VAR ch : CHAR;
	BEGIN
		ch := GetCh();
		IF ~inquotes THEN WHILE (ORD(ch) = blank) OR (ORD(ch) = cr ) OR (ORD(ch) = tab) DO ch := GetCh() END END;
		IF ~first & ( ORD( ch ) = dq) THEN inquotes := ~inquotes;
			IF inquotes THEN first := TRUE; tokenval := msopenquo ELSE tokenval := msclosequo END
		ELSE
			IF inquotes THEN
				tokenval := literal; first := FALSE; RETURN ch
			ELSE
				CASE ch OF
				   "X" : ch := GetCh();
							IF ( "0" <= ch ) & ( ch <= "9" ) THEN tokenval := mssubexpr; RETURN ch END|
					"t" : tokenval := shorthand; RETURN CHR( tab ) |
					"c" : tokenval := shorthand; RETURN CHR( cr ) |
				ELSE
				END
			END;
			IF ~EORPL THEN error := wsubexpr END
		END;
		RETURN ch
	END LexAn;

	PROCEDURE Append( chr : CHAR );
	BEGIN
		IF lineind < LEN( line ) THEN line[lineind] := chr; INC(lineind); linefull := FALSE ELSE linefull := TRUE END
	END Append;

BEGIN
	IF dfa # NIL THEN
		(*IF LEN( line ) > noofchar THEN error := linecopofl; RETURN ELSE*) COPY( line, linecop ) (*END*);
		replind := 0; lineind := beg; linefull := FALSE; inquotes := FALSE; first := FALSE; error := noerror;
		ch := LexAn();
		WHILE (~linefull) & ( ~ EORPL ) & ( error = noerror ) DO
			CASE tokenval OF
				msopenquo : ch := LexAn();
									 WHILE ( tokenval # msclosequo ) & ( ~EORPL ) DO
									 	Append( ch ); ch := LexAn()
									 END;
									 IF tokenval # msclosequo THEN error := dq END |
				mssubexpr :  ind := ORD(ch) - ORD("0");
									 IF dfa.sub[ind].end # undefined THEN
									 	spos := dfa.sub[ind].beg;
									 	WHILE (spos < dfa.sub[ind].end) DO Append( linecop[spos] ); INC(spos ) END
									 END |
				shorthand   : Append( ch )
				ELSE
			END;
			ch := LexAn()
		END;
		IF error = noerror THEN
			pos := lineind;
			spos := end;
			WHILE ( spos < LEN( linecop ) ) & ( linecop[spos] # 0X ) DO Append( linecop[spos] ); INC( spos ) END;
			IF lineind < LEN( line ) THEN Append( CHR(0) ) END;
			IF linefull THEN error := repllinefull ELSE RETURN END
		END;
	ELSE
		error := nodfa
	END;
	pos := replind;
	COPY( linecop, line )
END Replace;

END RXA.
