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

MODULE PPPIPCP;	(** non-portable *)
(* $VCS   1, Edgar.Schwarz@z.zgs.de, 28 Feb 99, 22:17:0 $
    $Log$
$   1, Edgar.Schwarz@z.zgs.de, 28 Feb 99, 22:17:0
version for PPP 1.0.0
*)
IMPORT 
	FSM:=PPPFSM, HDLC:=PPPHDLC, 
	PT := (*es*)NetBase, NetIP, (*PacketTools,*)
	T:=PPPTools, Debug := PPPDebug;

CONST
	(* Protocol Constants *)	
	IPCP*=-07FDFH;	(* =08021H *)
	MaxStates=16;		(* Slots for VJ Compression *)

	(* Configure Information Options *)
	Addrs = 1;								(* IP-Addresses, old *)
	CompressType = 2;					(* Compression Type *)
	Addr = 3;								(* IP Address, new *)
	
	(* IPCP codes *)
	VJCompression = 002DH;	
		
	(* Options Index *)
	NegAddrs = 0;	(* Accept old IP-Addresses *)
	NegAddr = 2;		(* Accept Address *)
	NegVJ = 8; 			(* Accept Van Jacobsen Header Compression *)
		
	(* Length of the Configuration Options *)
	VoidLen = 2; CompressLen = 4; VJLen = 6; AddrLen = 6; AddrsLen = 10;  	(* = Type (1 Byte) + Length (1 Byte) + Data *) 
	
TYPE
	Options*=RECORD
		O*: SET								(* Bits defined by Options Index *);
		OurAddress*, HisAddress*: (*es*)NetIP.Adr(*PT.IPAdr*);
		CompressProt*: INTEGER;	MaxSlot*, CFlag*: SHORTINT;		(* VJ Stuff *)		
	END;
	
	IPCPfsm*=POINTER TO IPCPfsmDesc;
	IPCPfsmDesc=RECORD (FSM.FSMDesc)
		wo*, go(*es*)*(*-*), 
		ao*, ho(*es*)*(*-*): Options;		
		(* WantOptions, GotOptions, AllowOptions, HisOptions *)
		AcceptLocal, AcceptRemote: BOOLEAN; 	
		(* Accept his proposal for our IP_address / for his IP_address  *)	
	END;
		
VAR	
	(* Upcalls to PPP *)
	PPPHandleIPCPUp*: PROCEDURE (U:HDLC.PPPUnit);
	PPPHandleIPCPDown*: PROCEDURE (U:HDLC.PPPUnit);
	
	ZeroIP*: (*es*)NetIP.Adr(*PT.IPAdr*);
	i: INTEGER;

	
	(* Open - IPCP can come up *)
	PROCEDURE Open* (f: IPCPfsm); BEGIN f.Flags:={}; FSM.Open(f) END Open;
	
	(* Close - Take IPCP down *)
	PROCEDURE Close* (f: IPCPfsm); BEGIN FSM.Close(f) END Close;

	(* LowerUp - The Lower Layer is Up *)
	PROCEDURE LowerUp* (f: IPCPfsm); BEGIN FSM.LowerUp(f) END LowerUp;
	
	(* LowerDown - The Lower Layer is Down *)
	PROCEDURE LowerDown* (f: IPCPfsm); BEGIN FSM.LowerDown(f) END LowerDown;
	
	(* Input - New IPCP Packet *)
	PROCEDURE Input* (f: IPCPfsm; VAR p: ARRAY OF CHAR; pos, len:INTEGER); BEGIN FSM.Input(f, p, pos, len); END Input;

	(*  RecProtRej - Protocol Reject received, pretend his lower layer went down, so we do the same *)
	PROCEDURE *RecProtRej(f: FSM.FSM; VAR p: ARRAY OF CHAR; pos, len:INTEGER);
	BEGIN FSM.LowerUp(f)
	END RecProtRej;	

	(* ResetCI - Reset The Configuration Information *)
	PROCEDURE *ResetCI (f: FSM.FSM);
	BEGIN
		WITH f:IPCPfsm DO
			f.AcceptLocal:=PT.Equal(f.wo.OurAddress, ZeroIP, 
				(*es*)NetIP.AdrLen(*PT.IPAdrLen*));
			f.AcceptRemote:=PT.Equal(f.wo.HisAddress, ZeroIP, 
				(*es*)NetIP.AdrLen(*PT.IPAdrLen*));
			f.go:=f.wo;		(* GotOptions := WantOptions *)
		END
	END ResetCI;
	
	(* CIlen - Returns Length of the Conf. Inf. *)
	PROCEDURE *CILen (f: FSM.FSM): INTEGER;
	VAR i:INTEGER;
	BEGIN i:=0;
		WITH f:IPCPfsm DO
			IF (NegAddrs IN f.go.O) THEN INC(i, AddrsLen); END;
			IF (NegAddr IN f.go.O) THEN INC(i, AddrLen); END;
			IF (NegVJ IN f.go.O) THEN INC(i, VJLen); END;	(* To update if more Options supported *)
		END;
		RETURN i 
	END CILen;
	
	(* AddCI - Add our desired Conf. Inf. to a packet (at pos) *)
	PROCEDURE *AddCI (f: FSM.FSM; VAR p: ARRAY OF CHAR; pos: INTEGER; VAR len: INTEGER);
	BEGIN len:=0;
		WITH f:IPCPfsm DO
			IF (NegAddrs IN f.go.O) THEN INC(len, AddrsLen);
				p[pos]:=CHR(Addrs); p[pos+1]:=CHR(AddrsLen);
				T.PutIP(f.go.OurAddress, p, pos+2); 
				T.PutIP(f.go.HisAddress, p, pos+6); INC(pos, AddrsLen);
			END;
			IF (NegAddr IN f.go.O) THEN INC(len, AddrLen);
				p[pos]:=CHR(Addr); p[pos+1]:=CHR(AddrLen); 
				T.PutIP(f.go.OurAddress, p, pos+2); INC(pos, AddrLen);
			END;
			IF (NegVJ IN f.go.O) THEN INC(len, VJLen);
				p[pos]:=CHR(CompressType); p[pos+1]:=CHR(VJLen); T.PutInt(f.go.CompressProt, p, pos+2);
				p[pos+4]:=CHR(f.go.MaxSlot); p[pos+5]:=CHR(f.go.CFlag); INC(pos, VJLen);
			END
		END																								(* To update if more Options supported *)
	END AddCI;
	
	(* AckCI - An Ack Packet has been received as answer to our req *)
	PROCEDURE *AckCI (f: FSM.FSM; VAR p: ARRAY OF CHAR; pos, len: INTEGER): BOOLEAN;
	VAR b:BOOLEAN;
	BEGIN b:=TRUE;
		WITH f:IPCPfsm DO				(* No changes to our former req are allowed, otherwise the ack is bad *)
			IF (NegAddrs IN f.go.O) THEN
				b:= b & (len>=AddrsLen) & (ORD(p[pos])=Addrs) & 
				(ORD(p[pos+1])=AddrsLen)
				& T.EqualIP(p, pos+2, f.go.OurAddress) & 
				T.EqualIP(p, pos+6, f.go.HisAddress);
				DEC(len, AddrsLen); INC(pos, AddrsLen);
			END;
			IF (NegAddr IN f.go.O) THEN
				b:= b & (len>=AddrLen) & (ORD(p[pos])=Addr)
				& (ORD(p[pos+1])=AddrLen) & T.EqualIP(p, pos+2, f.go.OurAddress);
				DEC(len, AddrLen); INC(pos, AddrLen);
			END;
			IF (NegVJ IN f.go.O) THEN
				b:=b & (len>=VJLen) & (ORD(p[pos])=CompressType) 
						& (ORD(p[pos+1])=VJLen) 
						& (T.GetInt(p, pos+2)=f.go.CompressProt) 
						& (ORD(p[pos+4])=f.go.MaxSlot) 
						& (ORD(p[pos+5])=f.go.CFlag);
				DEC(len, VJLen); INC(pos, VJLen);
			END;																							(* To update if more Options supported *)
			b:=b & (len=0);
			IF ~b THEN Debug.String("Received bad Ack!!"); END;
			RETURN b
		END
	END AckCI; 
	
	(* NakCI - A Nak Packet has been received as answer to our req *)
	PROCEDURE *NakCI (f: FSM.FSM; VAR p: ARRAY OF CHAR; pos, len: INTEGER): BOOLEAN;
	VAR no, try: Options;	(* no: Options with Naks, try: Options we try next time *)
		type, size:INTEGER; b, nakd:BOOLEAN;
	BEGIN b:=TRUE;
 		WITH f:IPCPfsm DO (* same order as we sent it, but only the nak'd ones *)
			no.O:={}; try.O:=f.go.O;
			IF (NegAddrs IN f.go.O) & (len>=AddrsLen) 
			& (ORD(p[pos])=Addrs) & (ORD(p[pos+1])=AddrsLen) THEN 
				nakd:=FALSE;
				IF ~T.EqualIP(p, pos+2, f.go.OurAddress) 
				& ~T.EqualIP(p, pos+2, ZeroIP) & f.AcceptLocal THEN
					T.GetIP(p, pos+2, try.OurAddress); 
					T.GetIP(p, pos+2, f.ho.OurAddress); 
					nakd:=TRUE;
				ELSE 
					try.OurAddress:=f.go.OurAddress;
				END;
				IF ~T.EqualIP(p, pos+6, f.go.HisAddress) 
				& ~T.EqualIP(p, pos+6, ZeroIP) & f.AcceptRemote THEN
					T.GetIP(p, pos+6, try.HisAddress); 
					T.GetIP(p, pos+6, f.ho.HisAddress); 
					nakd:=TRUE;
				ELSE
					try.HisAddress:=f.go.HisAddress;
				END;
				IF ~nakd THEN Debug.String(" Addresses-NAK wrong (no changes)"); Debug.Ln; b:=FALSE; END;
				INCL(no.O, NegAddrs); DEC(len, AddrsLen); INC(pos, AddrsLen);
			END;
			IF (NegAddr IN f.go.O) & (len>=AddrLen) & (ORD(p[pos])=Addr) & (ORD(p[pos+1])=AddrLen) THEN 
				IF (f.AcceptLocal & ~T.EqualIP(p, pos+2, ZeroIP)) THEN T.GetIP(p, pos+2, try.OurAddress)  (* Accept New Option *)
				ELSE Debug.String(" Our Address is not accepted or ZeroIP-proposal"); Debug.Ln;
				END;
				INCL(no.O, NegAddr); DEC(len, AddrLen); INC(pos, AddrLen);
			END;
			IF (NegVJ IN f.go.O) & (len>=VJLen) & (ORD(p[pos])=CompressType) THEN size:=ORD(p[pos+1]);
				IF (len=VJLen) & (T.GetInt(p, pos+2)=f.go.CompressProt) THEN 
					IF ((ORD(p[pos+4])#f.go.MaxSlot) OR (ORD(p[pos+5])#f.go.CFlag)) THEN	INCL(no.O, NegVJ);
						IF (ORD(p[pos+4])<=f.go.MaxSlot) THEN
							try.MaxSlot:=SHORT(ORD(p[pos+4])); try.CFlag:=SHORT(ORD(p[pos+5])); END;
						DEC(len, VJLen); INC(pos, VJLen);
					ELSE b:=FALSE;	Debug.String(" Compr-NAK wrong (no changes)"); Debug.Ln;	(* No changes made! *)
					END;
				ELSE Debug.String ("An other Compression Type is wanted! Type: "); Debug.Int(T.GetInt(p,pos+2),6); Debug.Ln;
					INCL(no.O, NegVJ); EXCL(try.O,NegVJ);	(* we switch off VJ-Comp. *)
					DEC(len, size); INC(pos, size);
				END;
			END;
												(* there may be remaining options , but no changes possible ! (Just checking if Nak is ok) *)
			WHILE b & (len>VoidLen) DO
				type:=ORD(p[pos]); size:=ORD(p[pos+1]);
				CASE type OF
					   Addr: b:=((size=AddrLen) & ~(NegAddr IN f.go.O) & ~(NegAddr IN no.O)); 
					| CompressType: b:=((size>=CompressLen) & ~(NegVJ IN f.go.O) & ~(NegVJ IN no.O)); 
					| Addrs: b:=(size=AddrsLen)
				ELSE
				END;
				INC(pos, size);
			END;
			b:=b & (len=0); IF len#0 THEN Debug.String ("Len not zero"); Debug.Int(len,6); Debug.Ln; END;
			
			IF b & (f.State#FSM.Opened) THEN f.go:=try;		 (* Update State *)	END;
			RETURN b
		END
	END NakCI;
	
	(* RejCI - A Reject Packet has been received as answer to our req*)
	PROCEDURE *RejCI (f: FSM.FSM; VAR p: ARRAY OF CHAR; pos, len: INTEGER): BOOLEAN;
	VAR try: Options; (* try: Option to request next time *)
	BEGIN 
		WITH f:IPCPfsm DO	(* Look which options were rejected. Same order and same value! Otherwise a bad packet. *)
			try:=f.go;
			IF (NegAddrs IN f.go.O) & (len>=AddrsLen) & (ORD(p[pos])=Addrs) 
			& (ORD(p[pos+1])=AddrsLen) & T.EqualIP(p, pos+2, f.go.OurAddress) 
			& T.EqualIP(p, pos+6, f.go.HisAddress) THEN
				DEC(len, AddrsLen); INC(pos, AddrsLen); EXCL(try.O, NegAddr);
			END;
			IF (NegAddr IN f.go.O) & (len>=AddrLen) & (ORD(p[pos])=Addr) 
			& (ORD(p[pos+1])=AddrLen) & T.EqualIP(p, pos+2, f.go.OurAddress) THEN
				DEC(len, AddrLen); INC(pos, AddrLen); EXCL(try.O, NegAddr); INCL(try.O, NegAddrs);
			END;
			IF (NegVJ IN f.go.O) & (len>VJLen) & (ORD(p[pos])=CompressType) 
			& (ORD(p[pos+1])=VJLen) & (T.GetInt(p, pos+2)=f.go.CompressProt) 
			& (ORD(p[pos+4])=f.go.MaxSlot) & (ORD(p[pos+5])=f.go.CFlag) THEN
					DEC(len, VJLen); INC(pos, VJLen); EXCL(try.O, NegVJ);
			END;			
			IF len#0 THEN
				Debug.String("Received bad Reject ! len:"); 
				Debug.Int(len, 5); Debug.Ln; RETURN FALSE
			ELSE	
				IF f.State#FSM.Opened THEN f.go:=try; END;	
				(* Update the Options *)
				RETURN TRUE
			END
		END
	END RejCI;
	
	(* ReqCI - Conf. Request has arrived: Check the requested CIs and send appropriate respose
		Returns:  ConfigureAck, ConfigureNak or ConfigureReject and modified packet (p, pos, length in len)
		If Mode is true always send Reject, never Nak *)	
	PROCEDURE ReqCI (f: FSM.FSM; VAR p: ARRAY OF CHAR; VAR pos, len: INTEGER; Mode:BOOLEAN): SHORTINT;
	CONST Ack=0; Nak=1; Rej=2; RejAll=3; (* Ack: Can Ack, Nak: Should Nak, Rej: reject of some options needed, RejAll: serious reject: rej whole packet *)
	VAR type, size, posp, posw, lenp, x:INTEGER;
		eo:SET; (* eo: Options to Nak/Rej *)
		status, MaxSlot, CFlag:SHORTINT;  
	BEGIN eo:={};		 
		WITH f:IPCPfsm DO	
			lenp:=len; posp:=pos; status:=Ack; f.ho.O:={};
			WHILE (status#RejAll) & (lenp>=VoidLen) DO
				size:=ORD(p[posp+1]);
				IF (size<VoidLen) OR (size>lenp) THEN 
					Debug.String("Bad CI Length!"); Debug.Ln; status:=RejAll;
				ELSE type:=ORD(p[posp]);
					CASE type OF
						  Addr: INCL(f.ho.O, NegAddr);
							IF (NegAddr IN f.ao.O) & (size=AddrLen) THEN 
								T.GetIP(p, posp+2, f.ho.HisAddress);
								IF ~f.AcceptRemote OR T.EqualIP(p, posp+2, ZeroIP) THEN
									INCL(eo, Addr); IF status=Ack THEN status:=Nak; END;
								END;
							ELSE status:=Rej; INCL(eo, Addr);
							END;
						| CompressType: INCL(f.ho.O, NegVJ);
							IF (NegVJ IN f.ao.O) & (size>=CompressLen) THEN 
								x:=T.GetInt(p, posp+2); f.ho.CompressProt:=x;
								IF (x=VJCompression) &(size=VJLen) THEN
									MaxSlot:=SHORT(ORD(p[posp+4])); 
									CFlag:=SHORT(ORD(p[posp+5]));
									f.ho.MaxSlot:=MaxSlot; f.ho.CFlag:=CFlag;
									IF (MaxSlot>f.ao.MaxSlot) OR (CFlag>f.ao.CFlag) THEN
										INCL(eo, CompressType); 
										IF status=Ack THEN status:=Nak; END;
									END;
								ELSE status:=Rej; INCL(eo, CompressType);
								END;
							ELSE status:=Rej; INCL(eo, CompressType)
							END;
						| Addrs: INCL(f.ho.O, NegAddrs);
							IF (NegAddrs IN f.ao.O) & (size=AddrsLen) THEN
								T.GetIP(p, posp+2, f.ho.HisAddress); 
								T.GetIP(p, posp+6, f.ho.OurAddress);
								IF (~f.AcceptRemote 
								& ~T.EqualIP(p, posp+2, f.go.HisAddress)) 
								OR T.EqualIP(p, posp+2, ZeroIP) THEN
									INCL(eo, Addrs); IF status=Ack THEN status:=Nak; END;
								END;
								IF (~f.AcceptLocal 
								& ~T.EqualIP(p, posp+6, f.go.OurAddress)) 
								OR T.EqualIP(p, posp+6, ZeroIP) THEN
									INCL(eo, Addrs); IF status=Ack THEN status:=Nak; END;
								END;
							ELSE status:=Rej; INCL(eo, Addrs);
							END;
					ELSE status:=Rej;				(* unknown Type ->reject *)
					END;
					DEC(lenp, size); INC(posp, size);
				END;
			END;
			IF lenp#0 THEN status:=RejAll; END;

			IF (status=RejAll) THEN RETURN FSM.ConfRej; (* len, pos are ok *)
			ELSIF (status=Ack) THEN RETURN FSM.ConfAck; (* len, pos are ok *)
			ELSE	IF Mode THEN status:=Rej; END;
				lenp:=len; posp:=pos; posw:=pos;
				WHILE lenp#0 DO
					type:=ORD(p[posp]); size:=ORD(p[posp+1]);
					IF (type IN eo) THEN			(* This type needs to be corrected *)
						IF status=Nak THEN 	(* make better proposals *)
							CASE type OF
								   Addr: T.PutIP(f.wo.HisAddress, p, posp+2);
								   (* write over old values *)
								| CompressType:
									IF (f.ho.MaxSlot>f.ao.MaxSlot) THEN 
										p[posp+4]:=CHR(f.wo.MaxSlot); 
									END;
									IF (f.ho.CFlag>f.ao.CFlag) THEN p[posp+5]:=0X; END;
								| Addrs: T.PutIP(f.wo.HisAddress, p, posp+2); 
									T.PutIP(f.wo.OurAddress, p, posp+6); 
									(* write over old values *)
							ELSE
							END;
						END;
						IF posw#posp THEN T.CopyString(p, posp, posw, size); END;
						INC(posw,size); (* 'shift' it together *)						
					END;
					INC(posp, size); DEC(lenp, size);
				END;
				len:=posw-pos;
				IF status=Rej THEN RETURN FSM.ConfRej; ELSE RETURN FSM.ConfNak; END;
			END
		END
	END ReqCI;
		
		
	(* Up - IPCP is ready *)
	PROCEDURE *Up (f: FSM.FSM);
		VAR ip:(*es*)NetIP.Adr(*PT.IPAdr*); i:INTEGER;
	BEGIN
		WITH f: IPCPfsm DO
			IF PT.Equal(f.ho.HisAddress, ZeroIP, (*es*)NetIP.AdrLen(*PT.IPAdrLen*)) THEN 
				PT.Copy(f.wo.HisAddress, f.ho.HisAddress, (*es*)NetIP.AdrLen(*PT.IPAdrLen*)); END;
			
			IF PT.Equal(f.ho.HisAddress, ZeroIP,(*es*)NetIP.AdrLen(*PT.IPAdrLen*)) THEN	
				Debug.String("Could not determine remote IP address!"); Debug.Ln;
				Close(f); RETURN
			ELSIF
				PT.Equal(f.go.OurAddress, ZeroIP,(*es*)NetIP.AdrLen(*PT.IPAdrLen*)) THEN	
					Debug.String("Could not determine local IP address!"); Debug.Ln;
				Close(f); RETURN
			ELSE	(* success ! *)
				PPPHandleIPCPUp(f.HDLCConfig); 	(* PPP will inform other protocols *)
			END;
		END;
	END Up;
	
	(* Down - IPCP has to close *)
	PROCEDURE *Down (f: FSM.FSM);
	BEGIN
		PPPHandleIPCPDown(f.HDLCConfig); 	(* PPP will inform other protocols *)		
	END Down;
	
	(* Initialisation IPCP*)
	PROCEDURE Init* (VAR f:IPCPfsm; C:HDLC.PPPUnit; OurIP, HisIP:(*es*)NetIP.Adr(*PT.IPAdr*));
	BEGIN
		NEW(f); f.Protocol:=IPCP; f.ProtoName:="IPCP";	(* IPCP Protocol *)
		f.ResetCI:=ResetCI; f.CILen:=CILen; f.AddCI:=AddCI; f.AckCI:=AckCI; f.NakCI:=NakCI; f.RejCI:=RejCI;
		f.ReqCI:=ReqCI; f.Up:=Up; f.Down:=Down; f.ExtCode:=NIL; f.HDLCConfig:=C;
		FSM.Init(f); 
		f.AcceptLocal:=PT.Equal(OurIP, ZeroIP, (*es*)NetIP.AdrLen(*PT.IPAdrLen*)); f.wo.OurAddress:=OurIP;
		f.AcceptRemote:=PT.Equal(HisIP, ZeroIP, (*es*)NetIP.AdrLen(*PT.IPAdrLen*)); f.wo.HisAddress:=HisIP;
		f.wo.O:={NegAddr};
		f.wo.CompressProt:=VJCompression; f.wo.MaxSlot:=MaxStates-1; f.wo.CFlag:=1;				(* Want Option *)
		f.ao.O:={NegAddr, NegAddrs};
		f.ao.CompressProt:=VJCompression; f.ao.MaxSlot:=MaxStates-1; f.ao.CFlag:=1;				(* Allow Option *)
		
	END Init;
	
BEGIN
	FOR i:=0 TO (*es*)NetIP.AdrLen(*PT.IPAdrLen*)-1 DO ZeroIP[i]:=0X; END

END PPPIPCP.
		