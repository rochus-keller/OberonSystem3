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

MODULE PPPLCP;	(** non-portable *)
(* $VCS   1, Edgar.Schwarz@z.zgs.de, 28 Feb 99, 22:19:22 $
    $Log$
$   1, Edgar.Schwarz@z.zgs.de, 28 Feb 99, 22:19:22
version for PPP 1.0.0
*)
IMPORT 
	FSM := PPPFSM, PAP := PPPPAP, HDLC := PPPHDLC, T := PPPTools, 
	Debug := PPPDebug, SYSTEM;

CONST
	(* Protocol Constants *)
	DefMRU = HDLC.MTU; MinMRU = 128; MaxMRU = HDLC.MTU;
	WarnLoops = 10; 				(* Warn about loop-backs this often *)
	
	LCP*=-03FDFH; (* =0C021H *)

	(* Configure Information Options *)
	Illegal0 = 0;					(*es some PPP implementations send that *)
	MRU = 1;						(* Maximum Receive Unit *)
	AsyncMap = 2;				(* Async Control Character Map *)
	AuthType = 3;				(* Authentication Protocol *)
	Quality = 4;					(* Quality Protocol *)
	MagicNumber = 5;
	(* =  6; *)                       (*es RESERVED*)
	PCompression = 7;		(* Protocol Field Compression *)
	ACCompression = 8;		(* Address And Control Field Compression *)
	(*es extensions from RFC1570 Jan 1994 *)
	(* = 9; *)                      (*es FCSAlternatives *)
	(* = 10; *)                    (*es Self Describing Padding *)
	(* = 13; *)                    (*es Callback *)
	(* = 15; *)                    (*es Compound Frames *)
	LCPConf17 = 17;           (*es* ? *)
	LCPConf19 = 19;           (*es* ? *)

	(* LCP codes *)
	ProtocolRej = 8;	EchoReq = 9;	EchoReply = 10;	DiscardReq = 11;
	(*es*)Identification = 12; TimeRemaining = 13; (**)
	
	(* Options Index *)
	Passive* = FSM.Passive;	(* Don't die if we get no response *)
	Silent* = FSM.Silent;		(* Wait for the other end to start first *)
	NegMRU* = 8; NegAsyncMap* = 9; NegUPap* = 10;	
	(* Negotiate MRU, Async Map, User/Password *)
	NegChap = 11; NegMagicNumber* = 12; NegPComp = 13; 		
	(* Crypt-Auth, MagicNumber, PCompression *)
	NegACComp = 14; NegLqr = 15;													
	(* AC-Compr., Link Quality Reports *)
	
	(* Length of the Configuration Options *)
	VoidLen = 2; ShortLen = 4; ChapLen = 5; LongLen = 6; LqrLen = 8;  	
	(* = Type (1 Byte) + Length (1 Byte) + Data *) 
	
TYPE
	Options*=RECORD
		O*: SET								(* Bits defined by Options Index *);	
		MRU*:INTEGER;					(* Max. Receive Unit *)
		MagicNumb*:LONGINT; NumLoops*:INTEGER;		(* Magic Number Stuff *)
		AsyncMap*:SET;
	END;
	
	LCPfsm*=POINTER TO LCPfsmDesc;
	LCPfsmDesc=RECORD (FSM.FSMDesc)
		wo*, go(*es*)*(*-*),ao*, ho(*es*)*(*-*): Options;
		(* WantOptions, GotOptions, AllowOptions, HisOptions *)
	END;
		
VAR	
	(* Upcalls to PPP *)
	PPPHandleLCPUp*: PROCEDURE (U:HDLC.PPPUnit);
	PPPHandleLCPDown*: PROCEDURE (U:HDLC.PPPUnit); 
	PPPHandleProtRej*: PROCEDURE (U:HDLC.PPPUnit; prot:INTEGER);
	
	(* Open - LCP can come up *)
	PROCEDURE Open* (f: LCPfsm);
	BEGIN	f.Flags:=f.wo.O*{Passive, Silent};
		FSM.Open(f);
	END Open;
	
	(* Close - Take LCP down *)
	PROCEDURE Close* (f: LCPfsm);
	BEGIN
		IF (f.State=FSM.Stopped) & (f.Flags*{Passive, Silent} # {}) THEN	f.State:=FSM.Closed
		ELSE	FSM.Close(f)
		END
	END Close;

	(* LowerUp - The Lower Layer is Up *)
	PROCEDURE LowerUp* (f: LCPfsm);
	BEGIN
		f.HDLCConfig.MTU:=DefMRU; f.HDLCConfig.SendAsyncMap:={0..31}; 
		(* Send Configuration *)
		
		f.HDLCConfig.MRU:=DefMRU; (* Receive Configuration *)
		f.ao.AsyncMap:={}; 
		FSM.LowerUp(f)
	END LowerUp;
	
	(* LowerDown - The Lower Layer is Down *)
	PROCEDURE LowerDown* (f: LCPfsm); 
	BEGIN FSM.LowerDown(f) END LowerDown;
	
	(* Input - New LCP Packet *)
	PROCEDURE Input* (f: LCPfsm; VAR p: ARRAY OF CHAR; pos, len:INTEGER); 
	BEGIN FSM.Input(f, p, pos, len); END Input;
	
	(* SendProtRej - Send a Protocol Reject *)
	PROCEDURE SendProtRej* (f: LCPfsm; VAR p: ARRAY OF CHAR; pos, len:INTEGER);
	BEGIN
		INC(f.ID); FSM.SendData(f, ProtocolRej, f.ID, p, pos+2, len-2); 
	END SendProtRej;

	(* ResetCI - Reset The Configuration Information *)
	PROCEDURE *ResetCI (f: FSM.FSM);
	BEGIN
		IF HDLC.debug THEN Debug.String("reset CI"); Debug.Ln; END;
		WITH f:LCPfsm DO
			f.wo.MagicNumb:=T.Magic(); f.wo.NumLoops:=0;		(* WantOptions *)
			f.go:=f.wo;		(* GotOptions := WantOptions *)
			f.HDLCConfig.MTU:=HDLC.MTU			(* Max. Transmit Unit *)
		END
	END ResetCI;
	
	(* CILen - Returns Length of the Conf. Inf. *)
	PROCEDURE *CILen (f: FSM.FSM): INTEGER;
	VAR i: INTEGER;
	BEGIN i:=0;
		WITH f:LCPfsm DO
			IF (NegMRU IN f.go.O) THEN INC(i, ShortLen); END;
			IF (NegAsyncMap IN f.go.O) THEN INC(i, LongLen); END;
			IF (NegMagicNumber IN f.go.O) THEN INC(i, LongLen); END;	
			(* To update if more Options supported *)
		END;
		RETURN i 
	END CILen;
	
		(* AddCI  - Add our desired Conf. Inf. to a packet (at pos) *)
	PROCEDURE *AddCI (f: FSM.FSM; VAR p: ARRAY OF CHAR; pos: INTEGER; VAR len: INTEGER);
	BEGIN len:=0;
		IF HDLC.debug THEN FSM.OutLog("LCP.AddCI", "", f); END;
		WITH f:LCPfsm DO
			IF (NegMRU IN f.go.O) THEN INC(len, ShortLen); IF HDLC.debug THEN Debug.String("MRU "); END;
				p[pos]:=CHR(MRU); p[pos+1]:=CHR(ShortLen); T.PutInt(f.go.MRU, p, pos+2); INC(pos, ShortLen);
			END;
			IF (NegAsyncMap IN f.go.O) THEN INC(len, LongLen); IF HDLC.debug THEN Debug.String("AsyncMap "); END;
				p[pos]:=CHR(AsyncMap); p[pos+1]:=CHR(LongLen); T.PutSet(f.go.AsyncMap, p, pos+2); INC(pos, LongLen);
			END;
			IF (NegMagicNumber IN f.go.O) THEN INC(len, LongLen); IF HDLC.debug THEN Debug.String("MagicNumber "); END;
				p[pos]:=CHR(MagicNumber); p[pos+1]:=CHR(LongLen);
				T.PutLong(f.go.MagicNumb, p, pos+2); INC(pos, LongLen)
			END
		END;																							(* To update if more Options supported *)
		IF HDLC.debug THEN Debug.Ln; Debug.Ln; END
	END AddCI;
	
	(* AckCI - An Ack Packet has been received as answer to our req *)
	PROCEDURE *AckCI (f: FSM.FSM; VAR p: ARRAY OF CHAR; pos, len: INTEGER): BOOLEAN;
	VAR b:BOOLEAN;
	BEGIN b:=TRUE;
		WITH f:LCPfsm DO				(* No changes to our former req are allowed, otherwise the ack is bad *)
			IF (NegMRU IN f.go.O) THEN
				b:= b & (len>=ShortLen) & (ORD(p[pos])=MRU) & (ORD(p[pos+1])=ShortLen) & (T.GetInt(p, pos+2)=f.go.MRU);
				DEC(len, ShortLen); INC(pos, ShortLen);
			END;
			IF (NegAsyncMap IN f.go.O) THEN
				b:=b & (len>=LongLen) & (ORD(p[pos])=AsyncMap) & (ORD(p[pos+1])=LongLen) 
						& (T.GetSet(p, pos+2)=f.go.AsyncMap);
				DEC(len, LongLen); INC(pos, LongLen);
			END;
			IF (NegMagicNumber IN f.go.O) THEN
				b:=b & (len>=LongLen) & (ORD(p[pos])=MagicNumber) & (ORD(p[pos+1])=LongLen)
					& (T.GetLong(p, pos+2)=f.go.MagicNumb);
				DEC(len, LongLen); INC(pos, LongLen);
			END;
			(* To update if more Options supported *)
			b:=b & (len=0);
			IF HDLC.debug & ~b THEN Debug.String("Received bad Ack!!"); Debug.Ln END;
			RETURN b
		END
	END AckCI; 
	
	(* NakCI - A Nak Packet has been received as answer to our req *)
	PROCEDURE *NakCI (f: FSM.FSM; VAR p: ARRAY OF CHAR; pos, len: INTEGER): BOOLEAN;
	VAR no, try: Options;	(* no: Options with Naks, try: Options we try next time *)
		x, type, size:INTEGER; loopedback, b:BOOLEAN;
	BEGIN
		WITH f:LCPfsm DO				(* same order as we sent it, but only the nak'd ones *)
			no.O:={}; try.O:=f.go.O;
			IF (NegMRU IN f.go.O) & (len>=ShortLen) & (ORD(p[pos])=MRU) & (ORD(p[pos+1])=ShortLen) THEN 
				x:=T.GetInt(p, pos+2); IF (x<DefMRU) THEN no.MRU:=x; try.MRU:=x; END;		(* Accept New Option *)
				INCL(no.O, NegMRU); DEC(len, ShortLen); INC(pos, ShortLen);
			END;
			IF (NegAsyncMap IN f.go.O) & (len>=LongLen) & (ORD(p[pos])=AsyncMap) & (ORD(p[pos+1])=LongLen) THEN
				INCL(no.O, NegAsyncMap); try.AsyncMap:=try.AsyncMap + T.GetSet(p, pos+2);
				DEC(len, LongLen); INC(pos, LongLen); 	(* Include New Chars (our receive side)*)
			END;
			IF (NegMagicNumber IN f.go.O) & (len>=LongLen) & (ORD(p[pos])=MagicNumber) & (ORD(p[pos+1])=LongLen) THEN
				INCL(no.O, NegMagicNumber); try.MagicNumb:=T.Magic(); INC(try.NumLoops); loopedback:=TRUE;
				DEC(len, LongLen); INC(pos, LongLen);
			END;
			b:=TRUE;						(* there may be remaining options , but no changes possible ! (Just checking if Nak is ok) *)
			WHILE b & (len>VoidLen) DO
				type:=ORD(p[pos]); size:=ORD(p[pos+1]);
				CASE type OF
					  MRU: b:=((size=ShortLen) & ~(NegMRU IN f.go.O) & ~(NegMRU IN no.O));
					| AsyncMap: b:=((size=LongLen) & ~(NegAsyncMap IN f.go.O) & ~(NegAsyncMap IN no.O)); 
					| MagicNumber: b:=((size=LongLen) & ~(NegMagicNumber IN f.go.O) & ~(NegMagicNumber IN no.O));
					| PCompression, ACCompression: b:=(size=VoidLen);
					| Quality: b:=(size=LqrLen);
					| AuthType: b:=((size=ChapLen) OR (size=ShortLen));
				ELSE	(* probably an unknown Configuration Option *)
				END;
				INC(pos, size);
			END;
			b:=b & (len=0);
			
			IF b & (f.State#FSM.Opened) THEN f.go:=try;		 (* Update State *)
				IF loopedback & ((try.NumLoops MOD WarnLoops) = 0) THEN 
					Debug.String("This line could be looped back!!"); Debug.Ln; 
				END;
			END;
			RETURN b
		END
	END NakCI;
	
	(* RejCI - A Reject Packet has been received as answer to our req*)
	PROCEDURE *RejCI (f: FSM.FSM; VAR p: ARRAY OF CHAR; pos, len: INTEGER): BOOLEAN;
	VAR try: Options; (* try: Option to request next time *)
	BEGIN
		WITH f:LCPfsm DO	(* Look which options were rejected. Same order and same value! Otherwise a bad packet. *)
			try:=f.go;
			IF (NegMRU IN f.go.O) & (len>=ShortLen) & (ORD(p[pos])=MRU) & (ORD(p[pos+1])=ShortLen)
				& (T.GetInt(p, pos+2)=f.go.MRU) THEN
					DEC(len, ShortLen); INC(pos, ShortLen); EXCL(try.O, NegMRU);
			END;				
			IF (NegAsyncMap IN f.go.O) & (len>=LongLen) & (ORD(p[pos])=AsyncMap) & (ORD(p[pos+1])=LongLen)
				& (T.GetSet(p, pos+2)=f.go.AsyncMap) THEN
					DEC(len, LongLen); INC(pos, LongLen); EXCL(try.O, NegAsyncMap);
			END;
			IF (NegMagicNumber IN f.go.O) & (len>=LongLen) & (ORD(p[pos])=MagicNumber) & (ORD(p[pos+1])=LongLen)
				& (T.GetLong(p, pos+2)=f.go.MagicNumb) THEN
				DEC(len, LongLen); INC(pos, LongLen); EXCL(try.O, NegMagicNumber);
			END;
			
			IF len#0 THEN IF HDLC.debug THEN Debug.String("Received bad Reject !"); END; RETURN FALSE
			ELSE	IF f.State#FSM.Opened THEN	f.go:=try; END;	(* Update the Options *)
				RETURN TRUE
			END
		END
	END RejCI;
	
	(* ReqCI - Conf. Request has arrived: Check the requested CIs and send 
		appropriate response
		Returns:  ConfigureAck, ConfigureNak or ConfigureReject and modified 
		packet (p, pos, length in len)
		If Mode is true, always send Reject, never Nak *)	
	PROCEDURE ReqCI (f: FSM.FSM; VAR p: ARRAY OF CHAR; 
							VAR pos, len: INTEGER; Mode: BOOLEAN): SHORTINT;
	CONST Ack=0; Nak=1; Rej=2; RejAll=3;
	VAR type, size, posp, posw, lenp, x: INTEGER;
		y: LONGINT; eo, s: SET; (* eo: Error-Options: Options to Nak/Rej *)
		status: SHORTINT;  (* Ack: Can Ack, Nak: Should Nak,  Rej: reject of
			some options needed, RejAll: serious reject: rej whole packet *)
	BEGIN eo:={};
		 (* Two steps: 
		 First find out if packet can be accepted, or have to be naked or rejected 
		 Second step: If nak, then modify (better proposals), 
		 	if rej then send back same packet *)
		WITH f:LCPfsm DO
			lenp:=len; posp:=pos; status:=Ack; f.ho.O:={};
			WHILE (status#RejAll) & (lenp>=VoidLen) DO
				size:=ORD(p[posp+1]);
				IF (size<VoidLen) OR (size>lenp) THEN
				ELSE type:=ORD(p[posp]);
					CASE type OF
						  (*es reject 0 if a bad peer sends it *)
						  Illegal0: status:=Rej; INCL(eo, Illegal0);
							IF HDLC.debug THEN Debug.String("RejIllegal0"); END;
						  | (**) MRU: INCL(f.ho.O, NegMRU);
							IF (NegMRU IN f.ao.O) & (size=ShortLen) THEN 
								x:=T.GetInt(p, posp+2); f.ho.MRU:=x;
								IF (x<MinMRU) THEN
									(* Minimal size needed: we have to change ->NAK *)
									INCL(eo, MRU); 
									IF status=Ack THEN status:=Nak; END;
								END;
							ELSE
								IF HDLC.debug THEN Debug.String("RejMRU"); END;
								status:=Rej; INCL(eo, MRU);
							END;
						| AsyncMap: INCL(f.ho.O, NegAsyncMap);
							IF (NegAsyncMap IN f.ao.O) & (size=LongLen) THEN 
								s:=T.GetSet(p, posp+2); f.ho.AsyncMap:=s;
								IF (f.ao.AsyncMap * (s/{0..31} (* = ~s *)) # {} ) THEN 
									(* at least our options needed *)
									INCL(eo, AsyncMap); 
									IF status=Ack THEN status:=Nak; END;
								END;
							ELSE 
								IF HDLC.debug THEN Debug.String("RejAsyncMap"); END;
								status:=Rej; INCL(eo, AsyncMap); 
							END;
						| MagicNumber: INCL(f.ho.O, NegMagicNumber);
							IF (NegMagicNumber IN f.ao.O) & (size=LongLen) THEN 
								y:=T.GetLong(p, posp+2); f.ho.MagicNumb:=y;
								IF(NegMagicNumber IN f.go.O)&(y=f.go.MagicNumb)THEN 	
									(* MagicNumber MUST be different *)
									INCL(eo, MagicNumber); 
									IF status=Ack THEN status:=Nak; END;
								END;
							ELSE 
								IF HDLC.debug THEN Debug.String("RejMagic"); END;
								status:=Rej; INCL(eo, MagicNumber);
							END;
						| AuthType:
							IF size>=ShortLen THEN x := T.GetInt(p, posp+2);
								IF x = PAP.PAPProt THEN (*UPap *)
									IF (NegUPap IN f.ao.O) & (size >= ShortLen) THEN 
										(* dm:1.10.96: size = ShortLen *)
										INCL(f.ho.O, NegUPap);
									ELSE
										status := Rej; INCL(eo, AuthType);
									END
								ELSE 
									INCL(f.ho.O, NegChap); INCL(eo, AuthType);
									IF status = Ack THEN status := Nak END;
								END
							ELSE
								IF HDLC.debug THEN Debug.String("RejAuth"); END;
								status := Rej; INCL(eo, AuthType);
							END;
							Debug.Ln
						| PCompression: INCL(f.ho.O, NegPComp); status:=Rej; 
							IF HDLC.debug THEN Debug.String("RejPCComp"); END;
							INCL(eo, PCompression);	(* not supported *)
						| ACCompression: INCL(f.ho.O, NegACComp); status:=Rej; 
							IF HDLC.debug THEN Debug.String("RejACComp"); END;
							INCL(eo, ACCompression);	(* not supported *)
						| Quality: INCL(f.ho.O, NegLqr); status:=Rej; 
							IF HDLC.debug THEN Debug.String("RejQuality"); END;
							INCL(eo, Quality);	(* not supported *)
(*es es fehlt weitere Info, einfach mal ablehnen *)
						| LCPConf17: status:=Rej; 
							INCL(eo, LCPConf17);	(* not supported *)
							IF HDLC.debug THEN Debug.String("RejLCPConf17"); END;
						| LCPConf19: status:=Rej; 
							IF HDLC.debug THEN Debug.String("RejLCPConf19"); END;
							INCL(eo, LCPConf19);	(* not supported *)
(**)
					ELSE 
						status:=Rej; (* unknown Type ->reject *)
						Debug.String("unknown type"); 
						(*es*)Debug.Int(type, 5); (**) Debug.Ln;
					END;
					DEC(lenp, size); INC(posp, size);
				END;
			END;
			IF lenp # 0 THEN status:=RejAll; END;
			
			IF (status=RejAll) THEN RETURN FSM.ConfRej;(* len, pos are ok *)
			ELSIF (status=Ack) THEN RETURN FSM.ConfAck; (* len, pos are ok *)
			ELSE	IF Mode THEN status:=Rej; END;
				(* little hack *)
				IF status = Rej THEN EXCL(eo, AuthType) END;
				
				lenp:=len; posp:=pos; posw:=pos;
				WHILE lenp#0 DO
					type:=ORD(p[posp]); size:=ORD(p[posp+1]);
					IF (type IN eo) THEN
						IF status=Nak THEN 	(* make better proposals *)
							CASE type OF
								   MRU: T.PutInt(MinMRU, p, posp+2); 
								   (* write over old values *)
								| AsyncMap: 
									T.PutSet(f.ao.AsyncMap+ f.ho.AsyncMap, p, posp+2);
								| MagicNumber: T.PutLong(T.Magic(), p, posp+2);
								|AuthType: T.PutInt(PAP.PAPProt, p, posp+2);
							ELSE
							END
						END;
						IF posw # posp THEN T.CopyString(p, posp, posw, size); END;
						INC(posw,size); (* 'shift' it together *)
					END;
					INC(posp, size); DEC(lenp, size);
				END;
				len:=posw-pos;
				IF status=Rej 
				THEN RETURN FSM.ConfRej; 
				ELSE RETURN FSM.ConfNak; END;
			END
		END;
	END ReqCI;
		
		
	(* Up - LCP is ready *)
	PROCEDURE *Up (f: FSM.FSM);
	VAR x:INTEGER; s:SET;
	BEGIN
		WITH f: LCPfsm DO
					
			(* Configure our HDLC: Receive: MTU: Take WantOption, but not bigger than our Allow Option! *)
			IF (NegMRU IN f.ho.O) THEN x:=f.ho.MRU; ELSE x:=HDLC.MTU; END;
			IF x>f.ao.MRU THEN x:=f.ao.MRU; END;
			f.HDLCConfig.MTU:=x;
									
			IF (NegAsyncMap IN f.ho.O) THEN s:=f.ho.AsyncMap; ELSE s:={0..31}; END;
			f.HDLCConfig.SendAsyncMap:=s;
									
			(* Receive Config *)
			IF (NegMRU IN f.wo.O) THEN x:=f.go.MRU ELSE x:=HDLC.MTU; END;
			f.HDLCConfig.MRU:=x;
			PPPHandleLCPUp(f.HDLCConfig); 	(* PPP will inform other protocols *)
		END;
	END Up;
	
	(* Down - LCP has to close *)
	PROCEDURE *Down (f: FSM.FSM);
	BEGIN
		PPPHandleLCPDown(f.HDLCConfig); 	(* PPP will inform other protocols *)		
		
		f.HDLCConfig.MTU:=HDLC.MTU; f.HDLCConfig.SendAsyncMap:={0..31};
		f.HDLCConfig.MRU:=HDLC.MTU;

	END Down;
	
	(*  RecProtRej - Protocol Reject received *)
	PROCEDURE *RecProtRej(f: FSM.FSM; VAR p: ARRAY OF CHAR; pos, len:INTEGER);
	VAR prot:INTEGER;
	BEGIN
		IF len>1 THEN
			prot:=T.GetInt(p, pos); Debug.String(" Protocol rejected: "); Debug.Int(prot, 10); Debug.Ln;
			IF f.State#FSM.Opened THEN Debug.String(" Protocol reject discarded "); Debug.Ln;
			ELSE	PPPHandleProtRej(f.HDLCConfig, prot); 	(* PPP will inform protocols *)
			END
		ELSE Debug.String("Short ProtReject received"); Debug.Ln
		END		
	END RecProtRej;

	(*		To implement if we intend to send Echo-Requests
	PROCEDURE RecEchoReply(f:FSM.FSM; id:SHORTINT; VAR p:ARRAY OF CHAR; pos, len:LONGINT); BEGIN END RecEchoReply;
	*)

	(* ExtCode - Handle LCP-Codes *)
	PROCEDURE *ExtCode(f: FSM.FSM; code, id: SHORTINT; VAR p: ARRAY OF CHAR; pos, len:INTEGER): BOOLEAN;
	BEGIN
		WITH f:LCPfsm DO
			CASE code OF
				  ProtocolRej: RecProtRej(f, p, pos, len); RETURN TRUE
				| EchoReq: IF len<4 THEN len:=4; END; T.PutLong(f.go.MagicNumb, p, pos);
					FSM.SendData(f, EchoReply, id, p, pos, len); RETURN TRUE
				| EchoReply: (* RecEchoReply(f, id, p, pos, len); To implement if we intend to send Echo-Requests *) RETURN TRUE
				| DiscardReq: RETURN TRUE
			ELSE RETURN FALSE
			END
		END
	END ExtCode;
	
	(* Initialisation LCP*)
	PROCEDURE Init* (VAR f:LCPfsm; wo, ao:Options; C:HDLC.PPPUnit);
	BEGIN
		NEW(f); f.Protocol:=LCP; f.ProtoName:="LCP";	(* LCP Protocol *)
		f.ResetCI:=ResetCI; f.CILen:=CILen; f.AddCI:=AddCI; f.AckCI:=AckCI; f.NakCI:=NakCI; f.RejCI:=RejCI;
		f.ReqCI:=ReqCI; f.Up:=Up; f.Down:=Down; f.ExtCode:=ExtCode; f.HDLCConfig:=C;
		FSM.Init(f);
		f.wo:=wo; f.ao:=ao
	END Init;
		
END PPPLCP.
