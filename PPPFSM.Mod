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

MODULE PPPFSM;	(** non-portable *)
(* $VCS   1, Edgar.Schwarz@z.zgs.de, 28 Feb 99, 22:15:39 $
    $Log$
$   1, Edgar.Schwarz@z.zgs.de, 28 Feb 99, 22:15:39
version for PPP 1.0.0
*)
IMPORT 
	HDLC := PPPHDLC, Debug := PPPDebug, Tools := PPPTools;

CONST
	(** CP (LCP, IPCP, etc.) codes *)
	ConfReq* = 1;	(* configuration request *)
	ConfAck* = 2;	(* configuration ack *)
	ConfNak* = 3;	(* configuration nak *)
	ConfRej* = 4;	(* configuration reject *)
	TermReq = 5;	(* termination request *)
	TermAck = 6;	(* termination ack *)
	CodeRej = 7;	(* code reject *)
	ProtRej = 8; 	(* protocol reject *)

	(** Link states *)
	Initial* = 0;	(* down, hasn't been opened *)
	Starting* = 1;	(* down, been opened *)
	Closed* = 2;	(* up, hasn't been opened *)
	Stopped* = 3;	(* open, waiting for down event *)
	Closing* = 4;	(* Terminating the connection, not open *)
	Stopping* = 5;	(* terminating, but open *)
	ReqSent* = 6;	(* we've sent a config request *)
	AckRcvd* = 7;	(* we've received a config ack *)
	AckSent* = 8;	(* we've sent a config ack *)
	Opened* = 9;	(* connection available *)

	(** Flags *)
	Passive* = 0;	(* don't die if we don't get a response *)
	Restart* = 1;	(* treat second Open as Down, Up *)
	Silent* = 2;	(* wait for peer to speak first *)

	(** Timeouts *)
	DefTimeout* = 30000;	(* timeout time in milliseconds *)
	DefMaxTermReqs* = 2;	(* maximum terminate-request transmissions *)
	DefMaxConfReqs* = 10;	(* maximum configure-request transmissions *)
	DefMaxNakLoops* = 10;	(* maximum # of nak loops *)

	HeaderLen = 4;	(* code(1) + id(1) + len(2) = HeaderLen of a CP-Packet *)
	StartPos = HDLC.StartPos + HDLC.HDLCHeaderLen + HeaderLen;

	newtransmit = TRUE; retransmit = FALSE;

	StrLen* = 33;

TYPE
	Params = POINTER TO ParamsDesc;

	FSM* = POINTER TO FSMDesc;
	FSMDesc* = RECORD
		Protocol*: INTEGER;	ProtoName*: ARRAY 32 OF CHAR;
		
		State*: SHORTINT;
		Flags*: SET;
		ID*, reqID*: SHORTINT;	(* unsigned char *)
		TimeoutTime: LONGINT;
		MaxConfReqTransmits*, Retransmits*, MaxTermTransmits*, NakLoops*, MaxNakLoops*: INTEGER;
					
		(* Callback Procedures *)
		ResetCI*: PROCEDURE (f: FSM);
		CILen*: PROCEDURE (f: FSM): INTEGER;
		AddCI*: PROCEDURE (f: FSM; VAR p: ARRAY OF CHAR; pos: INTEGER; VAR len: INTEGER);
		AckCI*: PROCEDURE (f: FSM; VAR p: ARRAY OF CHAR; pos, len: INTEGER): BOOLEAN;
		NakCI*: PROCEDURE (f: FSM; VAR p: ARRAY OF CHAR; pos, len: INTEGER): BOOLEAN;
		RejCI*: PROCEDURE (f: FSM; VAR p: ARRAY OF CHAR; pos, len: INTEGER): BOOLEAN;
		ReqCI*: PROCEDURE (f: FSM; VAR p: ARRAY OF CHAR; VAR pos, len: INTEGER; mode: BOOLEAN): SHORTINT;
		Up*: PROCEDURE (f: FSM);
		Down*: PROCEDURE (f: FSM);
(*		Starting*: PROCEDURE (f: FSM); *)
(*		Finished*: PROCEDURE (f: FSM); *)
		ExtCode*: PROCEDURE (f: FSM; code, id:SHORTINT; VAR inp: ARRAY OF CHAR; pos, len: INTEGER): BOOLEAN;
		
		HDLCConfig*: HDLC.PPPUnit;
	
		params: Params;
	END;
	
	ParamsDesc = RECORD (HDLC.ParamsDesc) f:FSM END;
	
	String* = ARRAY StrLen OF CHAR;
	
VAR
	ActTimeout*:LONGINT;
	ActMaxConfReqs*:INTEGER;


PROCEDURE ^ Init* (f: FSM);
PROCEDURE ^ LowerUp* (f: FSM);
PROCEDURE ^ LowerDown* (f: FSM);
PROCEDURE ^ Open* (f: FSM);
PROCEDURE ^ Close* (f: FSM);
PROCEDURE ^ Timeout (params: HDLC.Params);
PROCEDURE ^ Input* (f: FSM; VAR p: ARRAY OF CHAR; pos, len: INTEGER);
PROCEDURE ^ ReceiveConfReq* (f: FSM; id: SHORTINT; 
						VAR p: ARRAY OF CHAR; pos, len: INTEGER);
PROCEDURE ^ ReceiveConfAck* (f: FSM; id: SHORTINT; 
						VAR p:  ARRAY OF CHAR; pos, len: INTEGER);
PROCEDURE ^ ReceiveConfNakRej* (f: FSM; code, id: SHORTINT; 
						VAR p: ARRAY OF CHAR; pos, len: INTEGER);
PROCEDURE ^ ReceiveTermReq* (f: FSM; id: SHORTINT);
PROCEDURE ^ ReceiveTermAck* (f: FSM);
PROCEDURE ^ ReceiveCodeRej* (f: FSM; VAR p: ARRAY OF CHAR; 
						pos, len: INTEGER);
PROCEDURE ^ ProtReject* (f: FSM);
PROCEDURE ^ SendConfReq* (f: FSM; retransmit: BOOLEAN);
PROCEDURE ^ SendData* (f: FSM; code, id: SHORTINT; 
						VAR p: ARRAY OF CHAR; pos, len: INTEGER);


PROCEDURE OutLog* (text1, text2:ARRAY OF CHAR; f:FSM) ;
BEGIN
	Debug.String(text1); Debug.Ln; 
	IF text2 # "" THEN Debug.String(text2); Debug.Ln; END;
	Debug.String("protocol: "); Debug.String(f.ProtoName); 
	Debug.String("  -  channel: "); Debug.String(f.HDLCConfig.cname); 
	Debug.Ln;
END OutLog;

PROCEDURE OutCode* (code: SHORTINT);
BEGIN Debug.String("code: ");
	CASE code OF
		   ConfReq:	Debug.String("ConfReq")
		| ConfAck:	Debug.String("ConfAck")
		| ConfNak:	Debug.String("ConfNak")
		| ConfRej:	Debug.String("ConfRej")
		| TermReq:	Debug.String("TermReq")
		| TermAck:	Debug.String("TermAck")
		| CodeRej:	Debug.String("CodeRej")
		| ProtRej:	Debug.String("ProtocolRej")
	ELSE	Debug.String("*** illegal code ***"); Debug.Int(code, 4);
	END;
	Debug.Ln
END OutCode;

PROCEDURE GiveState*(state: SHORTINT; VAR s: String);
BEGIN
	CASE state OF
		   Initial:		s:="Initial";	| Starting:	s:="Starting";	
		| Closed:		s:="Closed";	| Stopped:	s:="Stopped";
		| Closing:		s:="Closing"; | Stopping:	s:="Stopping";	
		| ReqSent:	s:="ReqSent";	| AckRcvd:	s:="AckRcvd";
		| AckSent:	s:="AckSent"; | Opened:	s:="Opened";
	ELSE	s:=" *** unknown state ***";
	END;
END GiveState;

PROCEDURE OutState* (state: SHORTINT);
	VAR s: String;
BEGIN
	Debug.String("state: "); GiveState(state, s); Debug.String(s); Debug.Ln 
END OutState;

(* Init FSM *)
PROCEDURE Init* (f: FSM);
BEGIN
	f.State := Initial;	f.Flags := {};	f.ID := 0;	(* f.reqID set later *)
	f.TimeoutTime := ActTimeout;
	f.MaxConfReqTransmits := ActMaxConfReqs;	
	f.MaxTermTransmits := DefMaxTermReqs;
	f.MaxNakLoops := DefMaxNakLoops;
	NEW(f.params); f.params.f:=f;
END Init;


(* The lower layer is up *)
PROCEDURE LowerUp* (f: FSM);
BEGIN
	IF HDLC.debug THEN OutLog("FSM.LowerUp","",f); OutState(f.State); Debug.Ln; END;
	CASE f.State OF
		   Initial:	f.State := Closed
		| Starting:
			IF Silent IN f.Flags THEN f.State := Stopped
			ELSE SendConfReq(f, newtransmit); f.State := ReqSent	(* send an initial configure-request *)
			END
		
	ELSE
		OutLog("FSM.LowerUp","ERROR: in wrong state",f); OutState(f.State); Debug.Ln;
	END
END LowerUp;

(* The lower layer is down - cancel all timeouts and inform upper layers *)
PROCEDURE LowerDown* (f: FSM);
BEGIN
	IF HDLC.debug THEN OutLog("FSM.LowerDown","",f); OutState(f.State); Debug.Ln; END;
	CASE f.State OF
		   Closed:	f.State := Initial
		| Stopped:	f.State := Starting (* ; f.Starting (f) *)
		| Closing:	f.State := Initial; HDLC.UNTIMEOUT(f.HDLCConfig, Timeout)	(* cancel timeout *)
		| Stopping, ReqSent, AckRcvd, AckSent:	f.State := Starting; HDLC.UNTIMEOUT(f.HDLCConfig, Timeout)	(* cancel timeout *)
		| Opened:	f.Down(f); f.State := Starting
	ELSE
		OutLog("FSM.LowerDown", "ERROR: in wrong state", f); OutState(f.State); Debug.Ln
	END
END LowerDown;

(* Link is allowed to come up *)
PROCEDURE Open* (f: FSM);
BEGIN
	IF HDLC.debug THEN OutLog("FSM.Open","",f); OutState(f.State); Debug.Ln; END;
	CASE f.State OF
		   Initial:	f.State := Starting; (* f.Starting(f) *)
		| Closed:
			IF Silent IN f.Flags THEN f.State := Stopped
			ELSE SendConfReq(f, newtransmit); f.State := ReqSent;	(* send an initial configure-request *)
			END
		| Closing:	f.State := Stopping; IF Restart IN f.Flags THEN LowerDown(f); LowerUp(f) END
		| Stopped, Opened:	IF Restart IN f.Flags THEN LowerDown(f); LowerUp(f) END
	ELSE
	END
END Open;

(* Start closing connection *)
PROCEDURE Close* (f: FSM);
	VAR p: ARRAY HDLC.ArrayLength OF CHAR;
BEGIN
	IF HDLC.debug THEN OutLog("FSM.Close","",f); OutState(f.State); Debug.Ln; END;
	CASE f.State OF
		   Starting:	f.State := Initial
		| Stopped:	f.State := Closed
		| Stopping:	f.State := Closing
		| ReqSent, AckRcvd, AckSent, Opened:
			IF f.State # Opened THEN HDLC.UNTIMEOUT(f.HDLCConfig, Timeout)	(* cancel timeout *)
			ELSE f.Down(f)	(* inform upper layers we're down *)
			END;
			f.Retransmits := f.MaxTermTransmits; INC(f.ID); f.reqID := f.ID;
			SendData(f, TermReq, f.reqID, p, StartPos, 4);
			HDLC.TIMEOUT(f.HDLCConfig, Timeout, f.params, f.TimeoutTime);
			DEC(f.Retransmits);
			f.State := Closing
	ELSE
	END			
END Close;

(* Timeout expired *)
PROCEDURE Timeout (params: HDLC.Params);
VAR f: FSM;
BEGIN
	f := params(Params).f;
	IF HDLC.debug THEN OutLog("FSM.TimeOut","TimeOut-Handler called",f); OutState(f.State); Debug.Ln; END;
	CASE f.State OF
		   Closing, Stopping:
			IF f.Retransmits <= 0 THEN	(* we've waited for an ack long enough, peer probably heard us *)
				IF f.State = Closing THEN f.State := Closed ELSE f.State := Stopped END;
				(* f.Finished(f) *)
			ELSE	(* send terminate-request *)
				INC(f.ID); f.reqID := f.ID;
				SendData(f, TermReq, f.reqID, f.HDLCConfig.data2, StartPos, 0);
				HDLC.TIMEOUT(f.HDLCConfig, Timeout, params, f.TimeoutTime);
				DEC(f.Retransmits)
			END
		| ReqSent, AckRcvd, AckSent:
			IF f.Retransmits <= 0 THEN OutLog("LOG: FSM.Timeout", "Stop: sended all TimeOuts, no answer", f); Debug.Ln;
					f.State := Stopped;
				(* IF ~(Passive IN f.Flags) THEN f.Finished(f) END *)
			ELSE	(* retransmit the configure-request *)
				SendConfReq(f, retransmit);
				IF f.State = AckRcvd THEN f.State := ReqSent END
			END
	ELSE
		IF HDLC.debug THEN 
			OutLog("FSM.Timeout", "ERROR:in wrong state", f); 
			OutState(f.State); Debug.Ln;
		END
	END
END Timeout;

(* Input packet *)
PROCEDURE Input* (f: FSM; VAR p: ARRAY OF CHAR; pos, len: INTEGER);
	VAR code, id: SHORTINT; size: INTEGER;
BEGIN
	(* parse header (code, id and length). if packet too short, drop it. *)
	IF HDLC.debug THEN 
		OutLog("FSM.Input","new Input",f); OutState(f.State); Debug.Ln;
		Tools.OutPacket(p, pos, len); Debug.Ln;
	END;

	IF len < HeaderLen THEN
		IF HDLC.debug THEN 
			OutLog("FSM.Input", "ERROR: Received short header", f); 
		END;
		RETURN	
	END;

	code := SHORT(ORD(p[pos]));
	id := SHORT(ORD(p[pos + 1]));
	size := Tools.GetInt(p, pos + 2);
	
	IF size < HeaderLen THEN
		IF HDLC.debug THEN 
			OutLog("FSM.Input", "ERROR: Received illegal length", f); 
		END; 
		RETURN	
	END;
	
	IF size < len THEN
		IF HDLC.debug THEN
			OutLog("FSM.Input", "ERROR: Received short packet", f); 
		END; 
		RETURN
	END;
	
	DEC(size, HeaderLen); INC(pos, HeaderLen);
	IF (f.State = Initial) OR (f.State = Starting) THEN
		IF HDLC.debug THEN 
			OutLog("FSM.Input", "ERROR: Received packet in wrong state", f); 
			OutState(f.State); Debug.Ln; 
		END;
		RETURN
	END;
	(* action depends on code *)
	CASE code OF
		   ConfReq:	ReceiveConfReq(f, id, p, pos, size)
		| ConfAck:	ReceiveConfAck(f, id, p, pos, size)
		| ConfNak, ConfRej:	ReceiveConfNakRej(f, code, id, p, pos, size)
		| TermReq:	ReceiveTermReq(f, id)
		| TermAck:	ReceiveTermAck(f)
		| CodeRej:	ReceiveCodeRej(f, p, pos, size)
	ELSE
		IF ~f.ExtCode(f, code, id, p, pos, size) THEN
			INC(f.ID); SendData(f, CodeRej, f.ID, p, pos - HeaderLen, size + HeaderLen)
		END
	END
END Input;

(* Receive Configure-Request *)
PROCEDURE ReceiveConfReq* (f: FSM; id: SHORTINT; 
						VAR p: ARRAY OF CHAR; pos, len: INTEGER);
	VAR code: SHORTINT; RejectIfDisagree: BOOLEAN;
BEGIN
	IF HDLC.debug THEN 
		OutLog("FSM.ReceiveConfigureRequest", "", f); Debug.String("id: "); 
		Debug.Int(id, 4); Debug.Ln; Debug.Ln 
	END;
	
	CASE f.State OF
		   Closed:	SendData(f, TermAck, id, p, StartPos, 0); 
		   	RETURN	(* go away, we're closed *)
		| Closing, Stopping:	RETURN
		| Opened:	f.Down(f); SendConfReq(f, newtransmit)	
				(* go down and restart negotiation, inform upper layers, 
					send initial configure-request *)
		| Stopped:	SendConfReq(f, newtransmit); f.State := ReqSent;	
				(* send initial configure-request *)
	ELSE
	END;

	(* pass the requested configuration options to protocol-specific code for checking *)
	RejectIfDisagree := f.NakLoops >= f.MaxNakLoops;
	code := f.ReqCI(f, p, pos, len, RejectIfDisagree);
	
	
	(* send the Ack, Nak or Rej to the peer *)
	SendData(f, code, id, p, pos, len);
	
	IF code = ConfAck THEN
		IF f.State = AckRcvd THEN
			HDLC.UNTIMEOUT(f.HDLCConfig, Timeout);
			f.State := Opened;
			f.Up(f)
		ELSE f.State := AckSent; f.NakLoops := 0
		END
	ELSE	(* we sent ConfAck or ConfRej *)
		IF f.State # AckRcvd THEN f.State := ReqSent END;
		IF code = ConfNak THEN INC(f.NakLoops) END;
	END
END ReceiveConfReq;

(* Receive Configure-Ack *)
PROCEDURE ReceiveConfAck* (f: FSM; id: SHORTINT; VAR p: ARRAY OF CHAR; pos, len: INTEGER);
BEGIN
	IF HDLC.debug THEN OutLog("FSM.ReceiveConfAck", "", f); Debug.String("id: "); Debug.Int(id, 4); Debug.Ln; Debug.Ln END;

	IF (id=f.reqID) & f.AckCI(f, p, pos, len) THEN
		f.reqID := -1;
		CASE f.State OF
			   Closed, Stopped:	SendData(f, TermAck, id, p, StartPos, 0)
			| ReqSent:	f.State := AckRcvd; f.Retransmits := f.MaxConfReqTransmits
			| AckRcvd:	SendConfReq(f, newtransmit); f.State := ReqSent	(* huh?, an extra Ack? oh well... *)
			| AckSent:	HDLC.UNTIMEOUT(f.HDLCConfig, Timeout);	(* cancel timeout *)
				f.State := Opened; f.Retransmits := f.MaxConfReqTransmits;
				f.Up(f)
			| Opened:	(* go down and restart negotiation *)
				f.Down(f);
				SendConfReq(f, newtransmit); f.State := ReqSent
		ELSE
		END
	END
END ReceiveConfAck;

(* Receive Configure-Nak or Configure-Reject *)
PROCEDURE ReceiveConfNakRej* (f: FSM; code, id: SHORTINT; VAR p: ARRAY OF CHAR; pos, len: INTEGER);
BEGIN
	IF HDLC.debug THEN OutLog("FSM.ReceiveConfigureNak/Reject", "", f);
		Debug.String("id: "); Debug.Int(id, 4); Debug.Ln; Debug.Ln
	END;

	IF id # f.reqID THEN RETURN END;	(* expected ID? nope -> toss... *)
	
	IF ((code = ConfNak) & ~f.NakCI(f, p, pos, len)) OR ((code=ConfRej) & ~f.RejCI(f, p, pos, len)) THEN	(* Nak/Reject is bad - ignore it *)
		IF HDLC.debug THEN OutLog("FSM.ReceiveConfNakRej", "ERROR: Received bad Nak/Rej", f);
			Debug.String("id: "); Debug.Int(f.ID, 4); Debug.Ln; OutCode(code); Debug.Ln; 
			RETURN
		END
	END;
	
	f.reqID := -1;
	
	CASE f.State OF
		   Closed, Stopped:	SendData(f, TermAck, id, p, StartPos, 0)
		| ReqSent, AckSent:	HDLC.UNTIMEOUT(f.HDLCConfig, Timeout); SendConfReq(f, newtransmit)	(* They didn't agree to what we wanted - try another request *)
		| AckRcvd:	SendConfReq(f, newtransmit); f.State := ReqSent	(* got a Nak/Reject  when we had already had an Ack?? oh well... *)
		| Opened:	(* go down and restart negotiation *)
			f.Down(f);
			SendConfReq(f, newtransmit); f.State := ReqSent
	ELSE
	END
END ReceiveConfNakRej;

(* Receive Terminate-Request *)
PROCEDURE ReceiveTermReq* (f: FSM; id: SHORTINT);
	VAR p: ARRAY HDLC.ArrayLength OF CHAR;
BEGIN
	IF HDLC.debug THEN OutLog("FSM.ReceiveTermReq", "", f); Debug.String("id: "); Debug.Int(id, 4); Debug.Ln; Debug.Ln END;

	CASE f.State OF
		   AckRcvd, AckSent:	f.State := ReqSent
		| Opened:
			OutLog("FSM.ReceiveTermReq", "Terminated at peer's request", f);
			f.Down(f);
			f.Retransmits := 0; f.State := Stopping;
			HDLC.TIMEOUT(f.HDLCConfig, Timeout, f.params, f.TimeoutTime)
	ELSE
	END;
	SendData(f, TermAck, id, p, StartPos, 0)
END ReceiveTermReq;

(* Receive Terminate-Ack *)
PROCEDURE ReceiveTermAck* (f: FSM);
BEGIN
	IF HDLC.debug THEN OutLog("FSM.ReceiveTermAck", "", f); Debug.Ln; END;

	CASE f.State OF
		   Closing:	f.State := Closed (* ; IF f.Finished # NIL THEN f.Finished(f) END *)
		| Stopping:	f.State := Stopped (* ; IF f.Finished # NIL THEN f.Finished(f) END *)
		| AckRcvd:	f.State := ReqSent
		| Opened:	f.Down(f); SendConfReq(f, newtransmit)
	ELSE
	END
END ReceiveTermAck;

(* Receive a Code-Reject *)
PROCEDURE ReceiveCodeRej* (f: FSM; VAR p: ARRAY OF CHAR; pos, len: INTEGER);
	VAR code, id: SHORTINT;
BEGIN
	
	IF len < HeaderLen THEN
		IF HDLC.debug THEN OutLog("FSM.ReceiveCodeRej", "ERROR: too short", f); Debug.Ln; END; RETURN
	END;
	code := SHORT(ORD(p[pos])); id := SHORT(ORD(p[pos + 1]));	(* syslog *)
	
	IF HDLC.debug THEN
		OutLog("FSM.ReceiveCodeRej", "Received Code-Reject", f);
		OutCode(code); Debug.String("id: "); Debug.Int(id, 4); Debug.Ln; Debug.Ln;
	END;

	IF f.State = AckRcvd THEN f.State := ReqSent END
END ReceiveCodeRej;

(* Peer doesn't speak this protocol - Treat this as a catastrophic error (RXJ-)*)
PROCEDURE ProtReject* (f: FSM);
	VAR p: ARRAY HDLC.ArrayLength OF CHAR;
BEGIN
	IF HDLC.debug THEN OutLog("FSM.ProtReject", "", f); Debug.Ln; END;
	CASE f.State OF
		   Closing:	HDLC.UNTIMEOUT(f.HDLCConfig, Timeout); f.State := Closed; (* IF f.Finished # NIL THEN f.Finished(f) END *)
		| Closed:	f.State := Closed; (* IF f.Finished # NIL THEN f.Finished(f) END *)
		| Stopping, ReqSent, AckRcvd, AckSent:	HDLC.UNTIMEOUT(f.HDLCConfig, Timeout); f.State := Stopped (* ; IF f.Finished # NIL THEN f.Finished(f) END *)
		| Stopped:	f.State := Stopped (* IF f.Finished # NIL THEN f.Finished(f) END *)
		| Opened:	f.Down(f);
			(* init restart counter, send terminate-request *)
			f.Retransmits := f.MaxTermTransmits;
			INC(f.ID); f.reqID := f.ID;
			SendData(f, TermReq, f.reqID, p, StartPos, 0);
			HDLC.TIMEOUT(f.HDLCConfig, Timeout, f.params, f.TimeoutTime);
			DEC(f.Retransmits);
			f.State := Stopping
		ELSE
			IF HDLC.debug THEN OutLog("FSM.ProtReject", "ERROR: in wrong state", f); OutState(f.State); Debug.Ln END
		END
END ProtReject;

(* Send a Configure-Request *)
	PROCEDURE SendConfReq* (f: FSM; retransmit: BOOLEAN);
	VAR pos: INTEGER; CILen: INTEGER; p: ARRAY HDLC.ArrayLength OF CHAR;
BEGIN
	
	IF (f.State # ReqSent) & (f.State # AckRcvd) & (f.State # AckSent) THEN
		(* not currently negotiating - reset options *)
		f.ResetCI(f);
		f.NakLoops := 0
	END;
	
	IF retransmit THEN
		(* new request - reset transmission counter, use new ID *)
		f.Retransmits := f.MaxConfReqTransmits;
		INC(f.ID); f.reqID := f.ID
	END;
	
	IF HDLC.debug THEN OutLog("FSM.SendConfReq", "", f); Debug.String("id: "); Debug.Int(f.reqID, 4); 
	Debug.String("    "); OutState(f.State); Debug.Ln; Debug.Ln END;
	
	(* make up a request packet *)
	pos := StartPos;
	IF f.CILen(f) < f.HDLCConfig.MTU - HeaderLen THEN
		f.AddCI(f, p, pos, CILen)
	ELSE
		OutLog("FSM.SendConfReq", "ERROR: Configure Request too big", f); 
		RETURN
	END;
	
	(* send the request to our peer *)
	SendData(f, ConfReq, f.reqID, p, pos, CILen);
	
	(* start the retransmit timer *)
	DEC(f.Retransmits);
	HDLC.TIMEOUT(f.HDLCConfig, Timeout, f.params, f.TimeoutTime);
	
END SendConfReq;

(* SendData - Create a packet with code, id and data, 
	data is in p[pos .. pos+len] *)
PROCEDURE SendData* (f: FSM; code, id: SHORTINT; 
												VAR p: ARRAY OF CHAR; pos, len: INTEGER);
	VAR minpos, maxlen: INTEGER;
BEGIN
	maxlen:=f.HDLCConfig.MTU - HeaderLen;
	IF len > maxlen THEN len := maxlen; END;	
	
	(* adjust length (of information + padding) to be smaller than MTU *)
	minpos:=HDLC.HDLCHeaderLen+HeaderLen;
	IF pos<minpos THEN 
		Tools.CopyString(p, pos, minpos, len); pos:=minpos; 
	END;
	DEC(pos, HeaderLen); INC(len, HeaderLen); 
	p[pos]:=CHR(code); p[pos+1]:=CHR(id); Tools.PutInt(len, p, pos+2);
	IF HDLC.debug THEN
		OutLog("FSM.SendData", "", f); OutCode(code); OutState(f.State); 
		Debug.String("id: "); Debug.Int(id, 4); Debug.Ln;
		Tools.OutPacket(p, pos, len); Debug.Ln;
	END;
	HDLC.SendPacket(f.HDLCConfig, f.Protocol, p, pos, len);
END SendData;

BEGIN
	ActTimeout:=DefTimeout;
	ActMaxConfReqs:=DefMaxConfReqs

END PPPFSM.
