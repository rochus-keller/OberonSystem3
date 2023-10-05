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

(* $VCS   1, Edgar.Schwarz@z.zgs.de, 28 Feb 99, 22:13:54 $ *)
MODULE PPPHDLC;	(** non-portable *)
(* $Log$
$   1, Edgar.Schwarz@z.zgs.de, 28 Feb 99, 22:13:54
version for PPP 1.0.0
*)
IMPORT 
	Debug := PPPDebug, SYSTEM, T:=PPPTools,
	(*es*) Oberon, Ker:=Kernel, V24, PT := NetBase, Input, Out, Strings;
	(* Ker:=PPCXOKernel, P:=Peripherals; *)
		
CONST
	HDLCAddress=0FFX;
	HDLCControl=03X;
	
	HDLCHeaderLen* = 4;	(* Flag + Address, Protocol (2 Byte) *)

	EscSymbol = 7DX;
	FlagSymbol = 7EX;

	MTU*=1500;
	StartPos*=4;	(* even if we received a packed Packet, we can send back an unpacked one, using the same array *)
	ArrayLength* = MTU+100;	(* some bytes more needed *)
	
TYPE
	Params* = POINTER TO ParamsDesc;
	ParamsDesc* = RECORD END;
	CallbackProc*=PROCEDURE (p:Params);
	
	TimeOut = POINTER TO TimeOutDesc;
	TimeOutDesc = RECORD
		time: LONGINT;
		callback: CallbackProc;	params: Params;
		next: TimeOut;
	END;
	
	PPPUnit* = POINTER TO PPPUnitDesc;
	MyTask* = POINTER TO MyTaskDesc;
	MyTaskDesc = RECORD
		(*es*) (Oberon.TaskDesc)
		(* (Ker.MainEventDesc) (* Oberon.TaskDesc *)  *)
		Config*:PPPUnit; 
	END;
		
	PPPUnitDesc* = RECORD
		MTU*, MRU*:INTEGER;		(* Maximum Transmit Unit, how big our packets are; M Receive U, how big he may send*)
		SendAsyncMap*:SET;		(* Transmit AsyncMap; What characters have to be stuffed *)
		(*es*) c*: LONGINT;
		(* c*: P.SerialChannel; *)
		cname*:ARRAY 32 OF CHAR;
		task*: MyTask;
		
		data, data2*: ARRAY ArrayLength OF CHAR;
			
		TOqueue: TimeOut;
		TOempty: BOOLEAN;
	END;
	
VAR
(*es*)
	debug*: BOOLEAN;
	TOtask: Oberon.Task; (* check for timeout *)
	TOunit: PPPUnit; (* instead of extending task *)
(*TOrecycle: TimeOut;*)
(*es*) (* save uncomplete frames between calls to Reveive *)
	receiveFrame: RECORD
		active: BOOLEAN; (* ready to receive data *)
		(*deadline: LONGINT; (* until we want to receive the end *)*)
		i: INTEGER;  (* index of last received byte in receive buffer *)
		esc: BOOLEAN; (* last byte received was EscSymbol *) 
	END;
(**)PPPHandleReceive*: 
	PROCEDURE (U:PPPUnit; prot:INTEGER; VAR p: ARRAY OF CHAR;
			pos, len:INTEGER; VAR prno: INTEGER;  VAR item: PT.Item);

	PROCEDURE SendString(c: (*es*)LONGINT(*P.SerialChannel*); 
												VAR s: ARRAY OF CHAR);
	VAR l0, l1, start: LONGINT;
		(*es*)res: LONGINT;(**)
	BEGIN
		l0 := 0; WHILE s[l0] # 0X DO INC(l0) END; l1 := l0; start := 0;
		(*es*) WHILE l0 > 0 DO
			V24.SendBytes(c, s, l1, res);
			DEC(l0, l1); 
		END
(*	WHILE l0 > 0 DO
			c.Write(s, start, l1);
			DEC(l0, l1); INC(start, l1) 
		END *)
	END SendString;
			
	(* Init *)
	PROCEDURE Init* (Config:PPPUnit; 
									c:(*es*)LONGINT(* P.SerialChannel*); 
						VAR cname, sstr, loginname, loginpasswd: ARRAY OF CHAR);
		VAR to:TimeOut; l: LONGINT; temp: ARRAY 4 OF CHAR; 
			cr: ARRAY 2 OF CHAR;
			(*es*)res: LONGINT;(**)
	BEGIN 
		Config.c := c; COPY(cname, Config.cname);
(*es??? die V24 und Loginsachen macht doch der Dialer. Oder ?
		(* clear input-buffer *)
		WHILE V24.Available(c) > 0 DO V24.Receive(c, temp[0],res); END;
		(* WHILE c.Available > 0 DO l := 1; c.Read(temp, 0, l) END; *)
		(* send start string *)
		IF sstr[0] # 0X THEN
			SendString(c, sstr);
			(* consume some bytes (they contain the reply string from server) *)
			REPEAT
				WHILE c.Available > 0 DO l := 1; c.Read(temp, 0, l) END;
				Ker.Sleep(1, Ker.ONEsec)
			UNTIL c.Available = 0
		END;
		IF loginname[0] # 0X THEN	(* start normal unix-login procedure *)
			cr[0] := 0DX; cr[1] := 0X;
			(* send two CR *)
			SendString(c, cr); Ker.Sleep(1, Ker.ONEsec); 
			SendString(c, cr); Ker.Sleep(5,Ker.ONEsec);
			(* send loginname *)
			SendString(c, loginname); SendString(c, cr);
			Ker.Sleep(1, Ker.ONEsec);
			(* send loginpasswd *)
			SendString(c, loginpasswd); SendString(c, cr);
			Ker.Sleep(1, Ker.ONEsec);
		END;
		REPEAT
			WHILE c.Available > 0 DO 
				l := 1; c.Read(temp, 0, l); 
				Debug.Int(ORD(temp[0]),4); 
				IF (temp[0] >= 20X) & (temp[0] <= 7FX) THEN
					Debug.Char(9X); Debug.Char(temp[0])
				END;
				Debug.Ln;
			END;
			Ker.Sleep(5,Ker.ONEsec);
			Debug.Ln;
		UNTIL c.Available = 0;
es*)
		Debug.String(" Starting receiving-loop"); Debug.Ln;
		NEW(Config.task); Config.task.Config:=Config;	
		(*es???*) Debug.String("Pustekuchen, macht Devicepolling"); Debug.Ln;
		(*Ker.InitMain(Config.task);*)
		NEW(to); Config.TOqueue:=to; to.next:=to; 
		to.time:=MAX(LONGINT); Config.TOempty:=TRUE;	(* sentinel *)
	END Init;

	PROCEDURE CheckTimer((*es*)me: Oberon.Task(*C: PPPUnit*));
	(* Called only when TOqueue is not empty *)
		VAR cur:TimeOut;
	BEGIN
		cur:=(*es*)TOunit(*C*).TOqueue; 
		IF cur.time < (*es*)Input.Time()(*Ker.Time()*) THEN  
(*es*)  Oberon.Remove(me); 
			IF TOunit.cname # "" THEN
				(* output only if ppp is still running. See PPPMain.StopInst *)
				Out.String("PPP timeout"); Out.Ln;
			END;
(**)
			(*es*)TOunit(*C*).TOempty:=TRUE; 
			cur.callback(cur.params);
		END
	END CheckTimer;

	(* TimeOut Handling *)
	PROCEDURE TIMEOUT* (C: PPPUnit; callb:CallbackProc; p:Params; 
											msec:LONGINT); (* msec: in microS-sec *)
	VAR cur:TimeOut;
	BEGIN
		cur:=C.TOqueue; cur.callback:=callb; cur.params:=p; 
		cur.time:=(*es*) Input.Time(*Ker.Time*)()+msec;	
		C.TOempty:=FALSE;
		(*es install timer task *)
		TOtask.safe := FALSE; TOtask.time := 0;
		TOtask.handle := CheckTimer;
		Oberon.Install(TOtask);
		TOunit := C;
		(**)
	END TIMEOUT;
	
	PROCEDURE UNTIMEOUT* (C: PPPUnit; callb:CallbackProc);
	BEGIN	
		C.TOempty:=TRUE;
		(*es*) Oberon.Remove(TOtask); (**)
	END UNTIMEOUT;
	
	(* CheckPacket - Check  a HDLC-Packet *)
	PROCEDURE CheckPacket(Config: PPPUnit; VAR p: ARRAY OF CHAR; 
						pos, len:INTEGER; VAR prno: INTEGER; VAR item: PT.Item);
    (*es*)VAR timeStr: ARRAY 16 OF CHAR; time, date: LONGINT;(**)
	BEGIN
		IF debug THEN
			Oberon.GetClock(time, date);
			Strings.TimeToStr(time,timeStr); Debug.String(timeStr); 
			Debug.String('CheckPacket: len='); Debug.Int(len, 5); Debug.Ln; 
			T.OutPacket(p, pos, len);
		END;
		IF len > HDLCHeaderLen+2 THEN 
			(*[HDLC_Address+HDLC-Control+Protocol] + Checksum (2 Bytes)*)
			IF T.CheckFCS(p, pos, len) THEN 
				(* CheckSum ok? The whole packet needed! *)
				IF (p[pos] = HDLCAddress) & (p[pos+1] = HDLCControl) THEN
					PPPHandleReceive(Config, T.GetInt(p, pos+2), p, pos+4, len-6,
													prno, item);
				ELSE (* silently discarded *) 
					IF debug THEN
						Debug.String("Address, Code wrong"); Debug.Ln; 
					END;
				END
			ELSE
				IF debug THEN Debug.String("Checksum failure"); END
			END
		ELSE 
			IF debug & (len > 0) THEN 
				Debug.String("Length too short, length:"); 
				Debug.Int(len, 6); Debug.Ln; 
			END;
		END
	END CheckPacket;
	
	PROCEDURE XOR20(ch:LONGINT):LONGINT;
	BEGIN RETURN SYSTEM.VAL(LONGINT, (SYSTEM.VAL(SET, ch) / {5} ));
	END XOR20;
	
	(* ReceivePacket - ReiceiveLoop: Task , needs extended Event 
		(including PPPUnit)*)
(*es*) (* ReceivePacket is indirectly called by NetBase.Polldevices when 
	characters at the serial interface are available. So just read the characters
	into a buffer (Config.data) and return prno=0 (no handler installed for this
	protocol hopefully). When you get end of frame (FlagSymbol) then check
	it and return the stuff. *)
(**)PROCEDURE ReceivePacket*(Config: PPPUnit; VAR prno: INTEGER;
													VAR item: PT.Item);
	VAR (*es*) (*i:INTEGER;*)
		ch: ARRAY 4 OF CHAR; l: LONGINT;
		(*es*)c, res, endTime: LONGINT; timeOut : TimeOut;
		(* c: P.SerialChannel; *)
	BEGIN
		c:=Config.c;
		(*es*)(* i:=StartPos; ch[0]:=0X;	(* not Esc-Symbol *) *)
(*es*)IF receiveFrame.active THEN
			prno := 0;
		ELSE
			(*receiveFrame.deadline := Input.Time() + 10(*s*) * Input.TimeUnit;*)
			receiveFrame.i := StartPos;
			receiveFrame.active := TRUE;
			receiveFrame.esc := FALSE;
			ch[0]:=0X;
		END;
		IF receiveFrame.esc THEN ch[0] := EscSymbol ELSE ch[0]:=0X; END;
(**) LOOP
			IF (*es*)V24.Available(c)(*c.Available*)>0 THEN		
				(* New chars in buffer ? *)
				IF ch[0] (* last received *) #EscSymbol THEN
					(*es*) V24.Receive(c, ch[0], res); 
					(*l := 1; c.Read(ch, 0, l);*)
					IF ch[0] = FlagSymbol THEN (* end of frame received *)
						CheckPacket(Config, Config.data, StartPos, 
											  receiveFrame.i-StartPos, prno, item);
(*es*)			  (* data now in item *) receiveFrame.active := FALSE; RETURN;
						(* receiveFrame.i:=StartPos; *)
					ELSE
						IF ch[0] # EscSymbol THEN 
							Config.data[receiveFrame.i]:=ch[0]; 
							INC(receiveFrame.i) ;
(*es*)				 receiveFrame.esc := FALSE;
						ELSE
							receiveFrame.esc := TRUE;
(**) 				END
					END;
				ELSE
					(*es*) V24.Receive(c, ch[0], res); receiveFrame.esc := FALSE;
					(*l := 1; c.Read(ch, 0, l);*)
					Config.data[receiveFrame.i]:=CHR(XOR20(ORD(ch[0])));
					INC(receiveFrame.i); ch[0]:=0X; (* not Esc-,or Flag-Symbol *)
				END;
				IF receiveFrame.i>=ArrayLength THEN 
					Debug.String("Array Overflow!!"); 
					(*HALT(99);*) 
					receiveFrame.active := FALSE; RETURN
				END;
			ELSE
				RETURN; (* pause until more characters are available *)
(**)
			END;
		END
	END ReceivePacket;
	
	(* SendPacket - Send a packet to the V24 *)
	PROCEDURE SendPacket* (Config: PPPUnit; prot:INTEGER;
						VAR p:ARRAY OF CHAR; pos, len:INTEGER);
	VAR minpos, code, k, begin: INTEGER; ch: ARRAY 4 OF CHAR; l0, l1, start: LONGINT; x: CHAR;
		(*es*)c, res: LONGINT;
		timeStr: ARRAY 16 OF CHAR; time, date: LONGINT;
		(*c: P.SerialChannel;*)
	BEGIN
		c:=Config.c;
		minpos:=HDLCHeaderLen;
		IF pos<minpos THEN T.CopyString(p, pos, minpos, len); pos:=minpos; END;	(* More space needed *)
				
		DEC(pos, HDLCHeaderLen); INC(len, HDLCHeaderLen);
		p[pos]:=0FFX; p[pos+1]:=03X;		(* pos + 0: HDLC_Address = 0FFX; pos + 1: HDLC_Control =3X *)
		T.PutInt(prot, p, pos+2);				(* pos + 2: Protocol *)

		code:=T.CalcFCS(p, pos, len);
		p[pos+len]:=CHR(code MOD 256); 
		p[pos+len+1]:=CHR(SYSTEM.LSH(code, -8)); INC(len, 2); 
		(* insert the checksum *)
		IF debug THEN
			Oberon.GetClock(time, date);
			Strings.TimeToStr(time,timeStr); Debug.String(timeStr); 
			Debug.String('SendPacket: len = '); Debug.Int(len, 5); Debug.Ln; 
			T.OutPacket(p, pos, len);
		END;

		(* send it to the V24 *)
		ch[0]:=FlagSymbol;
		l0 := 1; l1 := l0; start := 0;
		WHILE l0 > 0 DO 
			(*es*)V24.Send(c,ch[start], res);
			(* c.Write(ch, start, l1); *)
			DEC(l0, l1); INC(start, l1) 
		END;

(*es auskommentiert: der Trick ist irgendwie alle Zeichen zu sammeln,
	die man ohne Maskierung (EscSymbol) senden kann. Wenn man dann
	auf eines trifft, verpackt man es und schickt die Dinger von zuvor 
	auf weg. Das ist mir etwas zu undurchsichtig.
		begin:=pos;
		FOR k:=pos TO pos+len-1 DO	x:=p[k];
			IF ((ORD(x)<20H) & (ORD(x) IN Config.SendAsyncMap)) 
			OR (x=EscSymbol) OR (x=FlagSymbol) THEN
				l0 :=k-begin; l1 := l0; start := begin;
				WHILE l0 > 0 DO c.Write(p, start, l1); DEC(l0,l1); INC(start,l1);END;
				begin:=k+1;
				ch[0]:=EscSymbol; ch[1]:=CHR(XOR20(ORD(x))); 
				l0 := 2; l1 := l0; start := 0;
				WHILE l0 > 0 DO c.Write(ch, start, l1); DEC(l0,l1); INC(start,l1);END; 
			END;
		END;
		p[pos+len]:=FlagSymbol; l0 := pos+len+1-begin; l1 := l0; start := begin; 
		WHILE l0 > 0 DO c.Write(p, start, l1); DEC(l0, l1); INC(start, l1); END;
*)
(*es*)
		FOR k:=pos TO pos+len-1 DO
			x:=p[k];
			IF ((ORD(x)<20H) & (ORD(x) IN Config.SendAsyncMap)) 
			OR (x=EscSymbol) OR (x=FlagSymbol) THEN
				V24.Send(c,EscSymbol, res);
				IF res # 0 THEN HALT(99); END;
				V24.Send(c,CHR(XOR20(ORD(x))), res);
				IF res # 0 THEN HALT(99); END;
			ELSE
				V24.Send(c, x, res);
				IF res # 0 THEN HALT(99); END;
			END;
		END;
		(* frame complete: send end flag *)
		V24.Send(c,FlagSymbol, res);
		IF res # 0 THEN HALT(99); END;
(**)
	END SendPacket;	 

BEGIN
	debug := FALSE;
	(*es*) receiveFrame.active := FALSE;
	NEW(TOtask);
	(*NEW(TOrecycle); TOrecycle.next:=TOrecycle; (* Sentinel *)*)
END PPPHDLC.
