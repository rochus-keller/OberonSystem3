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

MODULE PPPPAP;	(** non-portable *)
(* $VCS   1, Edgar.Schwarz@z.zgs.de, 28 Feb 99, 22:18:18 $
    $Log$
$   1, Edgar.Schwarz@z.zgs.de, 28 Feb 99, 22:18:18
version for PPP 1.0.0
*)
IMPORT
	 HDLC:=PPPHDLC, T:=PPPTools, Debug:=PPPDebug, SYSTEM;

CONST
	(* Protocol Constants *)
	PAPProt* = -3FDDH;	(* = 0C023H*)	
	PAPReq = 1;
	PAPAck = 2;
	PAPNak = 3;
	
	Initial* = 0;			(* Connection down *)
	Closed* = 1;		(*Connection up, haven't requested auth *)
	Pending* = 2;		(* Connection down, have requested auth *)
	AuthReq* = 3;	(* We have send an Auth-Request *)
	Open* = 4;		(* We've received an Ack *)
	BadAuth* = 5;	(* We've received an Nak *)
	
	PAPHeaderLen = 4;		(* code + id + len *)
	StartPos = HDLC.StartPos + HDLC.HDLCHeaderLen;
	
	DefTimeout = 30000;
	Defnrmaxtransmit = 10;
	
TYPE
	PAPStat* = POINTER TO PAPStatDesc;
	
	MyParams = POINTER TO MyParamsDesc;
	MyParamsDesc = RECORD (HDLC.ParamsDesc) 
		f: PAPStat
	END;

	PAPStatDesc* = RECORD
		PPPid: HDLC.PPPUnit;
		user, passwd: ARRAY 32 OF CHAR;
		timeout: LONGINT;
		userlen, passwdlen, nrtransmit, nrmaxtransmit: INTEGER;
		state*, id: SHORTINT;
		params: MyParams;
	END;

	PROCEDURE ^SendAuthReq(f: PAPStat);
	PROCEDURE ^ReceiveAuthAck(f: PAPStat; VAR p: ARRAY OF CHAR; pos, size: INTEGER);
	PROCEDURE ^ReceiveAuthNak(f: PAPStat; VAR p: ARRAY OF CHAR; pos, size: INTEGER);
		
	PROCEDURE Timeout(p: HDLC.Params);
	BEGIN
		WITH p: MyParams DO
			IF p.f.state = AuthReq THEN
				IF p.f.nrtransmit < p.f.nrmaxtransmit THEN
					SendAuthReq(p.f);
				ELSE
					p.f.state := BadAuth
				END
			END
		END
	END Timeout;
	
	(* LowerUp - The Lower Layer is Up *)
	PROCEDURE LowerUp*(f: PAPStat);
	BEGIN
		IF f.state = Initial THEN
			(* little hack *)
			f.nrtransmit := 0;
			SendAuthReq(f)
			(*f.state := Closed*)
		ELSE
			IF f.state = Pending THEN
				f.nrtransmit := 0;
				SendAuthReq(f)
			END
		END
	END LowerUp;
	
	(* LowerDown - The Lower Layer is Down *)
	PROCEDURE LowerDown*(f: PAPStat);
	BEGIN
		IF f.state = AuthReq THEN
			HDLC.UNTIMEOUT(f.PPPid, Timeout)
		END;
		f.state := Initial
	END LowerDown;
	
	(* Input *)
	PROCEDURE Input* (f: PAPStat; VAR p: ARRAY OF CHAR; pos, len:INTEGER); 
	VAR code, id: SHORTINT; size: INTEGER;
	BEGIN
		IF len >= PAPHeaderLen THEN
			code := SHORT(ORD(p[pos])); id := SHORT(ORD(p[pos + 1])); size := T.GetInt(p, pos + 2);
			IF (size > PAPHeaderLen) & (size <= len) THEN
				DEC(size, PAPHeaderLen);
				CASE code OF
					|PAPReq:
						(* we never wanted to receive a request *)
					|PAPAck:
						ReceiveAuthAck(f, p, pos + PAPHeaderLen, size)
					|PAPNak:
						ReceiveAuthNak(f, p, pos + PAPHeaderLen, size)
				ELSE
					IF HDLC.debug THEN Debug.String("unknown AuthCode"); Debug.Ln END
				END
			END
		END
	END Input;
	
	PROCEDURE ReceiveAuthAck(f: PAPStat; VAR p: ARRAY OF CHAR; pos, size: INTEGER);
	VAR msglen: SHORTINT;
	BEGIN
		IF f.state = AuthReq THEN
			IF size > 0 THEN
				msglen := SHORT(ORD(p[pos]));
				(* print message from p[pos + 1] to p[pos + 1 + msglen] *)
				f.state := Open;	
			END
		END
	END ReceiveAuthAck;
	
	PROCEDURE ReceiveAuthNak(f: PAPStat; VAR p: ARRAY OF CHAR; pos, size: INTEGER);
	VAR msglen: SHORTINT;
	BEGIN
		IF f.state = AuthReq THEN
			IF size > 0 THEN
				msglen := SHORT(ORD(p[pos]));
				(* print message from p[pos + 1] to p[pos + 1 + msglen] *)
				f.state := BadAuth;	
			END
		END
	END ReceiveAuthNak;
	
	PROCEDURE SendAuthReq(f: PAPStat);
	VAR p: ARRAY HDLC.ArrayLength OF CHAR; i, len: INTEGER;
	BEGIN i := StartPos;
		p[i] := CHR(PAPReq); INC(i);
		INC(f.id); p[i] := CHR(f.id); INC(i);
		len := PAPHeaderLen + 2 + f.userlen + f.passwdlen;
		T.PutInt(len, p, i); INC(i, 2);
		p[i] := CHR(f.userlen); INC(i); 
		SYSTEM.MOVE(SYSTEM.ADR(f.user), SYSTEM.ADR(p[i]), f.userlen); INC(i, f.userlen);
		p[i] := CHR(f.passwdlen); INC(i);
		SYSTEM.MOVE(SYSTEM.ADR(f.passwd), SYSTEM.ADR(p[i]), f.passwdlen); INC(i, f.passwdlen);
		HDLC.SendPacket(f.PPPid, PAPProt, p, StartPos, len);
		INC(f.nrtransmit);
		HDLC.TIMEOUT(f.PPPid, Timeout, f.params, f.timeout);
		f.state := AuthReq
	END SendAuthReq;
	
	PROCEDURE GiveState*(f: PAPStat; VAR s: ARRAY OF CHAR);
	BEGIN
		CASE f.state OF
			|Initial: COPY("Initial", s)
			|Closed: COPY("Closed", s)
			|Pending: COPY("Pending", s)
			|AuthReq: COPY("AuthReq", s)
			|Open: COPY("Open", s)
			|BadAuth: COPY("BadAuth", s)
		ELSE COPY("unknown state", s)
		END
	END GiveState;

	(* Init Object *)	
	PROCEDURE Init*(VAR f: PAPStat; id: HDLC.PPPUnit; username, passwd: ARRAY OF CHAR);
	VAR i: INTEGER;
	BEGIN
		NEW(f); f.PPPid := id;
		i := 0; WHILE (i < LEN(f.user) - 1) & (i < LEN(username)) & (username[i] # 0X) DO f.user[i] := username[i]; INC(i) END;
		f.user[i] := 0X; f.userlen := i;
		i := 0; WHILE (i < LEN(f.passwd) - 1) & (i < LEN(passwd)) & (passwd[i] # 0X) DO f.passwd[i] := passwd[i]; INC(i) END;
		f.passwd[i] := 0X; f.passwdlen := i;
		NEW(f.params); f.params.f := f;
		f.timeout := DefTimeout; f.nrtransmit := 0; f.nrmaxtransmit := Defnrmaxtransmit;
		f.id := 0; f.state := Initial
	END Init;
	
END PPPPAP.
