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

MODULE NetTCP;	(** non-portable *)	(* 16.08.96 mg *)

IMPORT SYSTEM, Kernel, NetBase, NetPorts, NetIP;

CONST
	(* standardized error codes *)
	Done* = 0; NotDone* = 1; Timeout* = 2; LocalPortInUse* = 3; DescriptorInUse* = 4;

CONST
(* send/receive buffer size *)
	BufSize = 2 * 4096;

TYPE
	Header* = POINTER TO HeaderDesc;
	HeaderDesc* = RECORD
		src*, dst*: INTEGER;
		seq*, ack*: LONGINT;
		offs*, code*: SHORTINT;
		win*: INTEGER;
		chksum*, up*: INTEGER;
		data*: ARRAY 1 OF SYSTEM.BYTE
	END;

	Connection* = POINTER TO ConnectionDesc;

	Listener* = POINTER TO ListenerDesc;

	ConnectionDesc* = RECORD (NetPorts.PortDesc)
		rbuf, sbuf: ARRAY BufSize OF SYSTEM.BYTE;	(* receive/send buffer *)
		rfst, rlst, sfst, slst: LONGINT;	(* buffer admin indexes *)
		rcnt, scnt: LONGINT;	(* number of bytes in buffer *)
		instate, outstate: SHORTINT;	(* I/O - state machines *)
		res: SHORTINT;
		xcnt: INTEGER;	(* number of retransmissions *)
		xamt, pamt: LONGINT;	(* retransmission/persist delays *)
		code, flags: SET;
		smss, rmss: INTEGER;
		swin, swl1, swl2, slast: LONGINT;
		iss, suna, snext, rnext, cwin: LONGINT;
		rup: INTEGER;
		ocsem: INTEGER;
		pcon: Listener;
		lq: Connection;
		rq: NetBase.Queue;
		next: Connection
	END;

	ListenerDesc = RECORD (NetPorts.PortDesc)
		state, res: SHORTINT;
		lqfirst, lqlast: Connection;
		lqn: INTEGER
	END;

	Event = POINTER TO EventDesc;
	EventDesc = RECORD
		type: SHORTINT;
		time: LONGINT;
		con: Connection;
		next: Event
	END;

	Word = ARRAY 2 OF SYSTEM.BYTE;

	ProcState = PROCEDURE (C: Connection; item: NetBase.Item; iph: NetIP.IPHeader; tcph: Header; code: SET);

CONST
	MaxQSize = 30;

(* packet bits *)
	Fin* = 0; Syn* = 1; Rst* = 2; Psh* = 3; Ack* = 4; Urg* = 5;

(* communication flags *)
	ssyn = 0; sfin = 2; rfin = 3; sffirst = 4;
	
(* input states *)
	closed = 0; listen = 1; sent = 2; rcvd = 3; estab = 4; finw1 = 5;
	finw2 = 6; clwait = 7; clos = 8; lack = 9; tiwait = 10;

(* output states *)
	idle = 0; trans = 1; retrans = 2; persist = 3;
	
	TcpIncr = 904; MinHLen = 20; MinOffset = 50H; MaxOffset = 60H;

(* time out values *)	
	maxretries = 12;

	minrtime = Kernel.TimeUnit DIV 2;	(* 0.5 sec. *)

	maxrtime = 20*Kernel.TimeUnit;	(* 20 sec. *)

	maxptime = 60*Kernel.TimeUnit;

	twomsl = 120*Kernel.TimeUnit; timeo = 20*Kernel.TimeUnit;

(* return codes *)	
	ok = 0; sys = -1; crf = -2; crs = -3; cnx = -4; cne = -5; (*irs = -6;*) cti = -7;

(* event codes *)
	deleteev = 0; retransev = 1; sendev = 2; persistev = 3;

(* options *)
	eool = 0; noop = 1; mss = 2;

VAR
	sq: Event;
	demux: ARRAY tiwait + 1 OF ProcState;
	sqct: INTEGER;
	iss: LONGINT;
	tasklist: Connection;
	Nreceived, Nsent: LONGINT;

PROCEDURE HLen (tcph: Header): INTEGER;
VAR set: SET;
BEGIN
	set := SYSTEM.VAL(SET, LONG(LONG(tcph.offs))) * {4..7};
	RETURN SHORT(SYSTEM.VAL(LONGINT, SYSTEM.LSH(set, -2)))
END HLen;

PROCEDURE Max (n, m: LONGINT): LONGINT;
BEGIN
	IF n > m THEN RETURN n ELSE RETURN m END
END Max;

PROCEDURE Min (n, m: LONGINT): LONGINT;
BEGIN
	IF n < m THEN RETURN n ELSE RETURN m END
END Min;

PROCEDURE ChkSum* (src, dst: NetIP.Adr; tcph: Header; len: INTEGER): LONGINT;
TYPE
	Data = POINTER TO DataDesc;
	DataDesc = RECORD data: ARRAY 1500 OF SYSTEM.BYTE END;
VAR
	tcpph: RECORD src, dst: NetIP.Adr; proto, len: INTEGER END;
	data: Data;
	chksum: LONGINT;
BEGIN
	tcpph.src := src; tcpph.dst := dst;
	
	tcpph.proto := NetIP.TCP; NetBase.HostToNet(tcpph.proto);
	tcpph.len := len; NetBase.HostToNet(tcpph.len);
	
	chksum := NetBase.ByteSum(tcpph, 12);
	IF len MOD 2 # 0 THEN
		data := SYSTEM.VAL(Data, tcph); data.data[len] := 0X; INC(len)
	END;
	chksum := NetBase.CheckSum(tcph^, len, chksum);
	RETURN chksum
END ChkSum;

PROCEDURE ChkSeqSpace (C: Connection; tcph: Header; iph: NetIP.IPHeader; code: SET): BOOLEAN;
VAR
	len: INTEGER;
	wlast, slast, rwin: LONGINT;
	res: BOOLEAN;
BEGIN
	len := iph.len - NetIP.MinHdrLen - HLen(tcph);
	IF Syn IN code THEN INC(len) END; IF Fin IN code THEN INC(len) END;
	rwin := BufSize - C.rcnt;
	IF (rwin = 0) & (len = 0) THEN
		RETURN tcph.seq = C.rnext
	ELSE wlast := C.rnext + rwin - 1;
		res := (C.rnext - tcph.seq <= 0) & (tcph.seq - wlast <= 0);
		IF len = 0 THEN RETURN res
		ELSE slast := tcph.seq + len - 1;
			IF rwin = 0 THEN iph.len := NetIP.HdrLen(iph) + HLen(tcph) END;
			RETURN res OR (C.rnext - slast <= 0) & (slast - wlast <= 0)
		END
	END
END ChkSeqSpace;

PROCEDURE ClearEvent (C: Connection; type: SHORTINT);
VAR tv, pv: Event;
BEGIN
	pv := sq; tv := sq.next;
	WHILE (tv # sq) & ((tv.con # C) OR (tv.type # type)) DO
		pv := tv; tv := tv.next
	END;
	IF tv # sq THEN pv.next := tv.next; DEC(sqct) END
END ClearEvent;

PROCEDURE SetEvent (C: Connection; type: SHORTINT; time: LONGINT);
VAR sv, tv, pv: Event;
BEGIN
	ClearEvent(C, type);
	pv := sq; tv := sq.next; time := time + Kernel.GetTimer();
	WHILE (tv # sq) & (tv.time - time < 0) DO
		pv := tv; tv := tv.next
	END;
	NEW(sv); sv.type := type; sv.time := time;
	sv.con := C; sv.next := tv; pv.next := sv;
	INC(sqct)
END SetEvent;

PROCEDURE Abort (C: Connection; res: SHORTINT);
VAR
	item: NetBase.Item;
BEGIN C.res := res;
	ClearEvent(C, retransev); ClearEvent(C, persistev);
	IF C.ocsem < 1 THEN INC(C.ocsem);
		IF C.instate = lack THEN C.instate := closed;
			WHILE C.rq.len > 0 DO
				NetBase.GetItem(C.rq, item); NetBase.RecycleItem(item)
			END;
			NetPorts.Release(C); Remove(C)
		END
	END
END Abort;

PROCEDURE Delete (port: NetPorts.Port);
VAR
	item: NetBase.Item;
BEGIN
	IF port IS Connection THEN
		WITH port: Connection DO
			ClearEvent(port, retransev); ClearEvent(port, persistev);
			port.instate := closed; NetPorts.Release(port);
			WHILE port.rq.len > 0 DO
				NetBase.GetItem(port.rq, item); NetBase.RecycleItem(item)
			END;
			Remove(port)
		END
	END
END Delete;

PROCEDURE SendItem (src, dst: NetIP.Adr; item: NetBase.Item);
VAR
	tcph: Header;
BEGIN tcph := SYSTEM.VAL(Header, SYSTEM.ADR(item.data[item.ofs]));
	NetBase.HostToNet(tcph.src); NetBase.HostToNet(tcph.dst);
	NetBase.HostLToNet(tcph.seq); NetBase.HostLToNet(tcph.ack); NetBase.HostToNet(tcph.win); NetBase.HostToNet(tcph.up);
	tcph.chksum := 0; tcph.chksum := SHORT(ChkSum(src, dst, tcph, item.len));
	INC(Nsent);
	NetIP.IPSend(src, dst, NetIP.TCP, item);
END SendItem;

PROCEDURE SendRst (iph: NetIP.IPHeader; tcph: Header; code: SET);
VAR
	item: NetBase.Item;
	ntcph: Header;
BEGIN NetBase.NewItem(item);
	DEC(item.ofs, MinHLen); INC(item.len, MinHLen);
	ntcph := SYSTEM.VAL(Header, SYSTEM.ADR(item.data[item.ofs]));
	IF Ack IN code THEN
		ntcph.seq := tcph.ack; ntcph.code := SHORT(SHORT(SYSTEM.VAL(LONGINT, {Rst})))
	ELSE
		ntcph.ack := tcph.seq + (iph.len - NetIP.HdrLen(iph) - HLen(tcph));
		IF code * {Fin,Syn} # {} THEN INC(ntcph.ack) END;
		ntcph.seq := 0; ntcph.code := SHORT(SHORT(SYSTEM.VAL(LONGINT, {Rst, Ack})))
	END;
	ntcph.src := tcph.dst; ntcph.dst := tcph.src;
	ntcph.offs := MinOffset; ntcph.win := 0; ntcph.up := 0;
	SendItem(iph.dst, iph.src, item)
END SendRst;

PROCEDURE RWindow (C: Connection): LONGINT;
VAR
	win: LONGINT;
BEGIN win := BufSize - C.rcnt;
	IF C.instate >= estab THEN
		IF (win * 4 < BufSize) OR (win - C.rmss < 0) THEN win := 0 END;
		win := Max(win, C.cwin - C.rnext);
		C.cwin := C.rnext + win
	END;
(* IF win < 1460 THEN Log.Int(win); Log.Ln END; *)
	RETURN win
END RWindow;

PROCEDURE SWindow (C: Connection; tcph: Header; VAR ack: BOOLEAN);
VAR
	olast, nlast: LONGINT;
BEGIN ack := FALSE;
	IF (C.swl1 - tcph.seq < 0) & ((C.swl1 # tcph.seq) OR (C.swl2 - tcph.ack <= 0)) THEN
		olast := C.swl2 + C.swin;
		C.swin := LONG(tcph.win) MOD 10000H;
		C.swl1 := tcph.seq; C.swl2 := tcph.ack;
		nlast := C.swl2 + C.swin;
		IF nlast - olast > 0 THEN ack := TRUE;
			IF C.outstate = persist THEN
				ClearEvent(C, persistev); C.outstate := trans
			END
		END
	END
END SWindow;

PROCEDURE SendAck (C: Connection; iph: NetIP.IPHeader; tcph: Header; code: SET);
VAR
	ntcph: Header;
	item: NetBase.Item;
BEGIN
	IF (NetIP.MinHdrLen + HLen(tcph) < iph.len) OR (code * {Syn, Fin} # {}) THEN
		NetBase.NewItem(item);
		DEC(item.ofs, MinHLen); INC(item.len, MinHLen);
		ntcph := SYSTEM.VAL(Header, SYSTEM.ADR(item.data[item.ofs]));
		ntcph.src := tcph.dst; ntcph.dst := tcph.src;
		ntcph.seq := C.snext; ntcph.ack := C.rnext;
		ntcph.code := SHORT(SHORT(SYSTEM.VAL(LONGINT, {Ack})));
		ntcph.offs := MinOffset; ntcph.up := 0;
		ntcph.win := SHORT(RWindow(C));
		SendItem(iph.dst, iph.src, item)
	END
END SendAck;

PROCEDURE SendData (C: Connection; retrans: BOOLEAN);
VAR
	item: NetBase.Item;
	tcph: Header;
	l: Word;
	spos, dlen, dlen0: INTEGER;
	sfst, offs, hseq: LONGINT;
	hcode: SHORTINT;
BEGIN
	IF retrans THEN hseq := C.suna;
		dlen := SHORT(Min(C.scnt, C.smss)); sfst := C.sfst
	ELSE hseq := C.snext;
		offs := C.snext - C.suna;
		dlen := SHORT(Min(Min(C.scnt - offs, C.swin), C.smss));
		sfst := (C.sfst + offs) MOD BufSize
	END;
		(* ??? C.slast = 0 until after Disconnect *)
	IF ((sfin IN C.flags) OR (sffirst IN C.flags)) & (hseq + dlen = C.slast) THEN
		IF ~retrans OR (sfin IN C.flags) THEN C.code := C.code + {Fin}; C.flags := C.flags - {sffirst} END
	END;
	IF ~retrans THEN C.snext := C.snext + dlen;
		IF Fin IN C.code THEN INC(C.snext) END;
		IF Syn IN C.code THEN INC(C.snext) END
	ELSE C.snext := C.snext + Max(C.suna + dlen - C.snext, 0)
	END;
	IF dlen > 0 THEN hcode := SHORT(SHORT(SYSTEM.VAL(LONGINT, C.code + {Psh})))
	ELSE hcode := SHORT(SHORT(SYSTEM.VAL(LONGINT, C.code)))
	END;
	
	NetBase.NewItem(item);
	DEC(item.ofs, dlen); INC(item.len, dlen);	(* space for data *)
	spos := item.ofs;
	IF Syn IN C.code THEN
		DEC(item.ofs, 4); INC(item.len, 4);
		item.data[item.ofs] := mss; item.data[item.ofs+1] := 4;
		l := SYSTEM.VAL(Word, C.smss);
		item.data[item.ofs+2] := l[1]; item.data[item.ofs+3] := l[0]
	END;
	WHILE dlen > 0 DO dlen0 := SHORT(Min(dlen, BufSize - sfst));
		NetBase.FastCopy(SYSTEM.ADR(C.sbuf[sfst]), SYSTEM.ADR(item.data[spos]), dlen0);
		sfst := (sfst + dlen0) MOD BufSize; DEC(dlen, dlen0); INC(spos, dlen0)
	END;

	DEC(item.ofs, MinHLen); INC(item.len, MinHLen);
	tcph := SYSTEM.VAL(Header, SYSTEM.ADR(item.data[item.ofs]));
	tcph.src := C.lport; tcph.dst := C.rport;
	tcph.seq := hseq; tcph.ack := C.rnext; tcph.code := hcode;
	IF Syn IN C.code THEN tcph.offs := MaxOffset ELSE tcph.offs := MinOffset END;
	tcph.win := SHORT(RWindow(C)); tcph.up := 0;

	SendItem(C.lip, C.rip, item)
END SendData;

PROCEDURE Retrans (C: Connection);
BEGIN
	IF C.xcnt < maxretries THEN SendData(C, TRUE);
		INC(C.xcnt); C.xamt := Min(2 * C.xamt, maxrtime);
		SetEvent(C, retransev, C.xamt);
	ELSE Abort(C, cti)
	END
END Retrans;

PROCEDURE Trans (C: Connection);
VAR
	scnt: LONGINT;
BEGIN scnt := C.suna + C.scnt - C.snext;
	IF (Syn IN C.code) OR (sfin IN C.flags) THEN INC(scnt) END;
	IF scnt # 0 THEN
		IF C.swin > 0 THEN C.outstate := trans;
			WHILE (scnt > 0) & (C.swin >= C.snext - C.suna) DO
				SendData(C, FALSE); scnt := C.suna + C.scnt - C.snext;
				IF (Syn IN C.code) OR (sfin IN C.flags) THEN INC(scnt) END
			END;
			SetEvent(C, retransev, C.xamt)
		ELSE C.outstate := persist;
			C.pamt := C.xamt; SendData(C, FALSE);
			SetEvent(C, persistev, C.pamt)
		END
	ELSE SendData(C, FALSE)
	END
END Trans;

PROCEDURE Output (C: Connection; type: SHORTINT);
BEGIN
	IF type # deleteev THEN
		IF C.outstate = idle THEN
			IF type = sendev THEN Trans(C) END
		ELSIF C.outstate = trans THEN
			IF type = retransev THEN
				Retrans(C); C.outstate := retrans
			ELSE
				Trans(C)
			END
		ELSIF C.outstate = retrans THEN
			IF type = retransev THEN Retrans(C) END
		ELSIF C.outstate = persist THEN
			IF type = persistev THEN
				SendData(C, TRUE);
				C.pamt := Min(2 * C.pamt, maxptime);
				SetEvent(C, persistev, C.pamt)
			END
		END
	ELSE Delete(C) (* type = deleteev *)
	END
END Output;

PROCEDURE ProcessText (C: Connection; item: NetBase.Item; iph: NetIP.IPHeader; tcph: Header; code: SET; VAR ack: BOOLEAN);
VAR
	rwin, len, dst, offs, len0, l, overlap: LONGINT;
BEGIN ack := FALSE;
	IF (tcph.seq = C.rnext) THEN
		len := iph.len - NetIP.MinHdrLen - HLen(tcph); rwin := BufSize - C.rcnt;
		IF len > rwin THEN len := rwin; code := code - {Fin} END;
		offs := LONG(NetIP.MinHdrLen + HLen(tcph)); len0 := len;
		WHILE len0 > 0 DO l := Min(len0, BufSize - C.rlst);
			dst := SYSTEM.ADR(C.rbuf[C.rlst]);
			NetBase.FastCopy(SYSTEM.ADR(item.data[item.ofs+offs]), dst, l);
			C.rlst := (C.rlst + l) MOD BufSize; DEC(len0, l); INC(offs, l)
		END;
		C.rnext := C.rnext + len; C.rcnt := C.rcnt + len;
		IF Fin IN code THEN ack := TRUE;
			C.flags := C.flags + {rfin}; INC(C.rnext)
		ELSE ack := len > 0
		END
	ELSIF tcph.seq - C.rnext < 0 THEN	(* this is probably unnecessary *)
		overlap := C.rnext-tcph.seq;
		Kernel.WriteString("NetTCP: tcph.seq < C.rnext ");
		WriteIP(C.rip);  Kernel.WriteChar(":");  Kernel.WriteInt(C.rport, 1);
		Kernel.WriteChar(" ");  Kernel.WriteInt(overlap, 1);
		len := iph.len - NetIP.MinHdrLen - HLen(tcph) - overlap; rwin := BufSize - C.rcnt;
		IF len > 0 THEN
			Kernel.WriteChar(" ");  Kernel.WriteInt(len, 1);
			IF len > rwin THEN len := rwin; code := code - {Fin} END;
			offs := LONG(NetIP.MinHdrLen + HLen(tcph)) + overlap; len0 := len;
			WHILE len0 > 0 DO l := Min(len0, BufSize - C.rlst);
				dst := SYSTEM.ADR(C.rbuf[C.rlst]);
				NetBase.FastCopy(SYSTEM.ADR(item.data[item.ofs+offs]), dst, l);
				C.rlst := (C.rlst + l) MOD BufSize; DEC(len0, l); INC(offs, l)
			END;
			C.rnext := C.rnext + len; C.rcnt := C.rcnt + len;
			IF Fin IN code THEN ack := TRUE;
				C.flags := C.flags + {rfin}; INC(C.rnext)
			ELSE ack := len > 0
			END
		END;
		Kernel.WriteLn
	END
END ProcessText;

PROCEDURE ProcessAck (C: Connection; iph: NetIP.IPHeader; tcph: Header; code: SET);
VAR
	acked: INTEGER;
BEGIN
	IF C.suna - tcph.ack < 0 THEN
		IF tcph.ack - C.snext <= 0 THEN
			acked := SHORT(tcph.ack - C.suna); C.suna := tcph.ack;
			IF Syn IN C.code THEN DEC(acked); C.code := (C.code - {Syn}) + {Ack} END;
			IF (Fin IN C.code) & (tcph.ack = C.snext) THEN
				DEC(acked); C.code := C.code - {Fin}; C.flags := C.flags - {sfin}
			END;
			C.sfst := (C.sfst + acked) MOD BufSize; C.scnt := C.scnt - acked;
			IF C.outstate = retrans THEN
				C.xamt := minrtime; C.xcnt := 0;
				IF C.snext = C.suna THEN C.outstate := trans;
					IF (C.scnt > 0) OR (sfin IN C.flags) THEN Output(C, sendev)
					ELSE C.outstate := idle
					END
				ELSE SetEvent(C, retransev, C.xamt)
				END
			ELSIF C.outstate = trans THEN
				IF (C.scnt = 0) & ~(sfin IN C.flags) THEN C.outstate := idle END
			END
		ELSE SendAck(C, iph, tcph, code)
		END
	END
END ProcessAck;

PROCEDURE ProcessOpts (C: Connection; item: NetBase.Item; len: INTEGER; code: SET);
VAR
	l: ARRAY 2 OF SYSTEM.BYTE;
	smss, i: INTEGER;
BEGIN
	i := NetIP.MinHdrLen + MinHLen;
	LOOP
		CASE SYSTEM.VAL(SHORTINT, item.data[item.ofs+i]) OF
		noop: INC(i)
		|eool: EXIT
		|mss: 
			IF Syn IN code THEN
				INC(i, 2); l[0] := item.data[item.ofs+i]; INC(i); l[1] := item.data[item.ofs+i]; INC(i);
				smss := SYSTEM.VAL(INTEGER, l); NetBase.NetToHost(smss);
				C.smss := SHORT(Min(smss - MinHLen, C.smss));
			END;
		ELSE EXIT
		END;
		IF i >= len THEN EXIT END
	END
END ProcessOpts;

PROCEDURE * Handle (C: Connection; item: NetBase.Item);
VAR
	tcph: Header;
	iph: NetIP.IPHeader;
	code: SET;
	len: INTEGER;
BEGIN
	iph := SYSTEM.VAL(NetIP.IPHeader, SYSTEM.ADR(item.data[item.ofs]));
	tcph := SYSTEM.VAL(Header, SYSTEM.ADR(item.data[item.ofs + NetIP.MinHdrLen]));
	code := SYSTEM.VAL(SET, LONG(LONG(tcph.code))); len := HLen(tcph) - MinHLen;
	IF ChkSeqSpace(C, tcph, iph, code) THEN
		IF len > 0 THEN ProcessOpts(C, item, len, code) END;
		demux[C.instate](C, item, iph, tcph, code)
	ELSIF ~(Rst IN code) THEN SendAck(C, iph, tcph, code)
	END;
	NetBase.RecycleItem(item)
END Handle;

PROCEDURE Create (VAR C: Connection);
BEGIN
	NEW(C);
	C.rfst := 0; C.rlst := 0; C.sfst := 0; C.slst := 0;
	C.rcnt := 0; C.scnt := 0;
	C.flags := {}; C.res := ok;
	C.instate := closed; C.outstate := idle;
	C.smss := 1500 - MinHLen- NetIP.MinHdrLen (*536;*);
	C.swin := C.smss; C.rmss := C.smss;
	C.iss := iss; INC(iss, TcpIncr);
	C.snext := C.iss; C.suna := C.iss; C.swl2 := C.iss;
	C.rup := 0; 
	C.xamt := minrtime; C.xcnt := 0;
	C.ocsem := 1;
	C.pcon := NIL;
	NetBase.Reset(C.rq)
END Create;

PROCEDURE Install(c: Connection);
VAR n: Connection;
BEGIN
	n := tasklist;  WHILE (n # NIL) & (n # c) DO n := n.next END;
	IF n = NIL THEN c.next := tasklist;  tasklist := c END
END Install;

PROCEDURE Remove(c: Connection);
VAR p, n: Connection;
BEGIN
	p := NIL;  n := tasklist;
	WHILE (n # NIL) & (n # c) DO p := n;  n := n.next END;
	IF n # NIL THEN
		IF p = NIL THEN tasklist := c.next ELSE p.next := c.next END
	END
END Remove;

PROCEDURE ProcListen (L: Listener; item: NetBase.Item; iph: NetIP.IPHeader; tcph: Header; code: SET);
VAR C: Connection; ack, res: BOOLEAN;
BEGIN
	IF ~(Rst IN code) THEN
		IF ~(Ack IN code) & (Syn IN code) THEN
			Create(C);
			res := NetPorts.Access(C, NetIP.routes[0].adr, tcph.dst, iph.src, tcph.src, NetPorts.active);
			C.instate := rcvd; C.code := {Syn, Ack};
			C.pcon := L;
			C.swin := LONG(tcph.win) MOD 10000H;
			C.swl1 := tcph.seq; C.cwin := tcph.seq + BufSize;
			tcph.seq := tcph.seq + 1; C.rnext := tcph.seq;
			ProcessText(C, item, iph, tcph, code, ack); Output(C, sendev);
			Install(C)
		ELSE
			SendRst(iph, tcph, code);
		END
	END
END ProcListen;

PROCEDURE ProcSent (C: Connection; item: NetBase.Item; iph: NetIP.IPHeader; tcph: Header; code: SET);
VAR
	ack: BOOLEAN;
BEGIN
	IF (Ack IN code) & ((tcph.ack - C.iss <= 0) OR (tcph.ack - C.snext > 0)) THEN
		IF ~(Rst IN code) THEN
			SendRst(iph, tcph, code)
		END
	ELSIF Rst IN code THEN
		IF Ack IN code THEN
			ClearEvent(C, retransev); ClearEvent(C, persistev);
			C.instate := closed; C.res := crs; INC(C.ocsem)
		END
	ELSIF Syn IN code THEN
		C.swin := LONG(tcph.win) MOD 10000H;
		C.swl1 := tcph.seq; C.rnext := tcph.seq;
		C.cwin := C.rnext + BufSize;
		IF Ack IN code THEN ProcessAck(C, iph, tcph, code) END;
		tcph.seq := tcph.seq + 1; C.rnext := tcph.seq;
		ProcessText(C, item, iph, tcph, code, ack); Output(C, sendev);
		IF Syn IN C.code THEN C.instate := rcvd
		ELSE C.instate := estab; INC(C.ocsem)
		END
	END
END ProcSent;

PROCEDURE ProcRcvd (C: Connection; item: NetBase.Item; iph: NetIP.IPHeader; tcph: Header; code: SET);
VAR
	L: Listener;
	ack: BOOLEAN;
BEGIN
	IF {Rst, Syn} * code # {} THEN
		IF Rst IN code THEN
			IF C.pcon = NIL THEN Abort(C, crf) ELSE Delete(C) END
		ELSE
			SendRst(iph, tcph, code); Abort(C, crs)
		END
	ELSE
		IF C.suna - tcph.ack < 0 THEN
			IF tcph.ack - C.snext <= 0 THEN
				C.suna := tcph.ack; C.code := C.code - {Syn};
				IF C.suna = C.snext THEN
					IF C.outstate = retrans THEN
						C.xamt := minrtime; C.xcnt := 0
					END;
					C.outstate := idle
				ELSE HALT(MAX(INTEGER)); RETURN
				END;
				IF C.pcon # NIL THEN L := C.pcon;
					IF L.lqlast # NIL THEN L.lqlast.lq := C ELSE L.lqfirst := C END;
					L.lqlast := C; C.lq := NIL; INC(L.lqn)
				ELSE INC(C.ocsem)
				END;
				C.instate := estab;
				IF Urg IN code THEN C.rup := SHORT(Max(LONG(C.rup), LONG(tcph.up))) END;
				ProcessText(C, item, iph, tcph, code, ack); IF ack THEN Output(C, sendev) END;
				IF rfin IN C.flags THEN C.instate := clwait END
			ELSE SendRst(iph, tcph, code)
			END
		END
	END
END ProcRcvd;

PROCEDURE Wait (C: Connection);
BEGIN ClearEvent(C, retransev); SetEvent(C, deleteev, twomsl)
END Wait;

PROCEDURE ProcClosed (C: Connection; item: NetBase.Item; iph: NetIP.IPHeader; tcph: Header; code: SET);
BEGIN
	IF ~(Rst IN code) THEN
		SendRst(iph, tcph, code)
	END
END ProcClosed;

PROCEDURE ProcEstab (C: Connection; item: NetBase.Item; iph: NetIP.IPHeader; tcph: Header; code: SET);
VAR
	ack0, ack1: BOOLEAN;
BEGIN
	IF {Rst, Syn} * code # {} THEN
		IF Syn IN code THEN
			SendRst(iph, tcph, code)
		END;
		Abort(C, crs)
	ELSE ProcessAck(C, iph, tcph, code);
		IF Urg IN code THEN C.rup := SHORT(Max(C.rup, tcph.up)) END;
		ProcessText(C, item, iph, tcph, code, ack0); SWindow(C, tcph, ack1);
		IF ack0 OR ack1 THEN Output(C, sendev)
		END;
		IF rfin IN C.flags THEN C.instate := clwait END
	END
END ProcEstab;

PROCEDURE ProcFinw1 (C: Connection; item: NetBase.Item; iph: NetIP.IPHeader; tcph: Header; code: SET);
VAR
	ack0, ack1: BOOLEAN;
BEGIN
	IF {Rst, Syn} * code # {} THEN
		IF Syn IN code THEN
			SendRst(iph, tcph, code)
		END;
		Abort(C, crs)
	ELSE ProcessAck(C, iph, tcph, code);
		IF Urg IN code THEN C.rup := SHORT(Max(C.rup, tcph.up)) END;
		ProcessText(C, item, iph, tcph, code, ack0); SWindow(C, tcph, ack1);
		IF ack0 OR ack1 THEN Output(C, sendev) END;
		IF rfin IN C.flags THEN
			IF Fin IN C.code THEN C.instate := clos
			ELSE C.instate := tiwait;
				INC(C.ocsem); Wait(C)
			END
		ELSIF ~(Fin IN C.code) THEN
			C.instate := finw2; INC(C.ocsem)
		END
	END
END ProcFinw1;

PROCEDURE ProcFinw2 (C: Connection; item: NetBase.Item; iph: NetIP.IPHeader; tcph: Header; code: SET);
VAR
	ack: BOOLEAN;
BEGIN
	IF {Rst, Syn} * code # {} THEN
		IF Syn IN code THEN
			SendRst(iph, tcph, code)
		END;
		Abort(C, crs)
	ELSE ProcessAck(C, iph, tcph, code);
		IF Urg IN code THEN C.rup := SHORT(Max(C.rup, tcph.up)) END;
		ProcessText(C, item, iph, tcph, code, ack); IF ack THEN Output(C, sendev) END;
		IF rfin IN C.flags THEN C.instate := tiwait; Wait(C) END
	END
END ProcFinw2;

PROCEDURE ProcClwait (C: Connection; item: NetBase.Item; iph: NetIP.IPHeader; tcph: Header; code: SET);
VAR
	ack: BOOLEAN;
BEGIN
	IF {Rst, Syn} * code # {} THEN
		IF Syn IN code THEN
			SendRst(iph, tcph, code)
		END;
		Abort(C, crs)
	ELSE ProcessAck(C, iph, tcph, code);
		SWindow(C, tcph, ack); IF ack THEN Output(C, sendev) END
	END
END ProcClwait;

PROCEDURE ProcTiwait (C: Connection; item: NetBase.Item; iph: NetIP.IPHeader; tcph: Header; code: SET);
VAR
	ack: BOOLEAN;
BEGIN
	IF {Rst, Syn} * code # {} THEN Delete(C)
	ELSE ProcessAck(C, iph, tcph, code);
		ProcessText(C, item, iph, tcph, code, ack); IF ack THEN Output(C, sendev) END;
		Wait(C)
	END
END ProcTiwait;

PROCEDURE ProcClos (C: Connection; item: NetBase.Item; iph: NetIP.IPHeader; tcph: Header; code: SET);
BEGIN
	IF {Rst, Syn} * code # {} THEN Delete(C)
	ELSE ProcessAck(C, iph, tcph, code);
		IF ~(Fin IN C.code) THEN C.instate := tiwait;
			INC(C.ocsem); Wait(C)
		END
	END
END ProcClos;

PROCEDURE ProcLack (C: Connection; item: NetBase.Item; iph: NetIP.IPHeader; tcph: Header; code: SET);
BEGIN
	IF {Rst, Syn} * code # {} THEN
		IF Syn IN code THEN
			SendRst(iph, tcph, code)
		END;
		Abort(C, crs)
	ELSE ProcessAck(C, iph, tcph, code);
		IF ~(Fin IN C.code) THEN INC(C.ocsem); Delete(C) END
	END
END ProcLack;

PROCEDURE Timer(t: LONGINT);
VAR tv: Event;  c: Connection;  item: NetBase.Item;
BEGIN
	c := tasklist;
	WHILE c # NIL DO
		WHILE c.rq.len > 0 DO
			NetBase.GetItem(c.rq, item); INC(Nreceived); Handle(c, item)
		END;
		c := c.next
	END;
	tv := sq.next;
	WHILE (tv # sq) & (tv.time - t <= 0) DO
		sq.next := tv.next; DEC(sqct);
		Output(tv.con, tv.type);
		tv := sq.next
	END
END Timer;

PROCEDURE Demux(item: NetBase.Item);
VAR
	tcph: Header;
	iph: NetIP.IPHeader;
	C: NetPorts.Port;
	code: SET;
	chksum: INTEGER;
BEGIN
	iph := SYSTEM.VAL(NetIP.IPHeader, SYSTEM.ADR(item.data[item.ofs]));
	tcph := SYSTEM.VAL(Header, SYSTEM.ADR(item.data[item.ofs + NetIP.MinHdrLen]));
	chksum := tcph.chksum; tcph.chksum := 0;
	IF SHORT(ChkSum(iph.src, iph.dst, tcph, iph.len - NetIP.MinHdrLen)) = chksum THEN
		NetBase.NetToHost(tcph.src); NetBase.NetToHost(tcph.dst);
		NetBase.NetLToHost(tcph.seq); NetBase.NetLToHost(tcph.ack);
		NetBase.NetToHost(tcph.win); NetBase.NetToHost(tcph.up);
		code := SYSTEM.VAL(SET, LONG(LONG(tcph.code)));
		IF NetPorts.Search(NetIP.routes[0].adr, tcph.dst, iph.src, tcph.src, Syn IN code, C) THEN
			IF C IS Connection THEN
				WITH C: Connection DO
					IF (closed <= C.instate) & (C.instate <= sent) THEN
						demux[C.instate](C, item, iph, tcph, code); NetBase.RecycleItem(item)
					ELSE
						IF C.rq.len < MaxQSize THEN NetBase.PutItem(C.rq, item)
						ELSE NetBase.RecycleItem(item)
						END
					END
				END
			ELSIF C IS Listener THEN
				WITH C: Listener DO
					IF C.state = listen THEN
						ProcListen(C, item, iph, tcph, code)
					ELSE HALT(MAX(INTEGER))
					END
				END;
				NetBase.RecycleItem(item)
			END
		ELSE
			IF ~(Rst IN code) THEN SendRst(iph, tcph, code);
				NetBase.RecycleItem(item)
			END
		END
	ELSE NetBase.RecycleItem(item)
	END
END Demux;

PROCEDURE Poll (port: NetPorts.Port);
VAR item: NetBase.Item;
BEGIN
	IF port IS Connection THEN
		WITH port: Connection DO
			WHILE (port.rq.len > 0) & (RWindow(port) - port.rmss > 0) DO
				NetBase.GetItem(port.rq, item); Handle(port, item)
			END
		END
	END
END Poll;

PROCEDURE Send* (C: Connection; VAR buf: ARRAY OF SYSTEM.BYTE; beg: LONGINT; VAR len: LONGINT);
VAR
	dst, len0, l, l0: LONGINT;
BEGIN
	IF (C.instate = estab) OR (C.instate = clwait) THEN
		WHILE (C.res = ok) & (len > 0) DO
			l := Min(len, BufSize - C.scnt);
			IF l > 0 THEN len0 := l;
				WHILE len0 > 0 DO l0 := Min(len0, BufSize - C.slst);
					dst := SYSTEM.ADR(C.sbuf[C.slst]);
					NetBase.FastCopy(SYSTEM.ADR(buf[beg]), dst, l0);
					C.slst := (C.slst + l0) MOD BufSize; DEC(len0, l0); INC(beg, l0)
				END;
				C.scnt := C.scnt + l; len := len - l;
				IF C.snext = C.suna THEN Output(C, sendev) END
			END;
			NetBase.Poll; NetPorts.Enumerate(Poll)
		END;
		len := C.res
	ELSE len := sys
	END
END Send;

PROCEDURE Receive* (C: Connection; VAR buf: ARRAY OF SYSTEM.BYTE; beg: LONGINT; VAR len: LONGINT);
VAR
	dst, len0, l: LONGINT;
BEGIN
	IF (estab <= C.instate) & (C.instate <= clos) OR (C.instate = tiwait) THEN
		WHILE (estab <= C.instate) & (C.instate <= finw2) & (C.rcnt = 0) & (C.res = ok) DO
			NetBase.Poll; NetPorts.Enumerate(Poll)
		END;
		IF C.res = ok THEN 
			IF (C.rcnt = 0) & (C.instate >= clwait) THEN len := sys		(* input closed, no data left, reading past the end *) 
			ELSE
				IF len > C.rcnt THEN len := C.rcnt END; len0 := len;
				WHILE len0 > 0 DO l := Min(len0, BufSize - C.rfst);
					dst := SYSTEM.ADR(buf[beg]);
					NetBase.FastCopy(SYSTEM.ADR(C.rbuf[C.rfst]), dst, l);
					C.rfst := (C.rfst + l) MOD BufSize; DEC(len0, l); INC(beg, l)
				END;
				C.rcnt := C.rcnt - len
			END
		ELSE len := C.res
		END
	ELSE len := sys
	END
END Receive;

PROCEDURE Connect* (VAR C: Connection; lport: INTEGER; radr: NetIP.Adr; rport: INTEGER; VAR res: INTEGER);
VAR item: NetBase.Item; timeout: LONGINT;
BEGIN
	IF NetPorts.Available(NetIP.routes[0].adr, lport, radr, rport) THEN
		Create(C);
		IF NetPorts.Access(C, NetIP.routes[0].adr, lport, radr, rport, NetPorts.active) THEN
			C.instate := sent; C.code := {Syn}; Output(C, sendev);

			timeout := Kernel.GetTimer() + timeo; DEC(C.ocsem);
			WHILE (C.ocsem < 1) & (Kernel.GetTimer() - timeout < 0) DO
				NetBase.Poll; NetPorts.Enumerate(Poll)
			END;

			IF (C.ocsem > 0) & (C.res = ok) THEN
				Install(C); res := Done
			ELSE
				IF res = ok THEN ClearEvent(C, retransev);
					res := Timeout;
				ELSE res := NotDone
				END;
				C.instate := closed; NetPorts.Release(C);
				WHILE C.rq.len > 0 DO
					NetBase.GetItem(C.rq, item); NetBase.RecycleItem(item)
				END
			END
		ELSE res := DescriptorInUse
		END
	ELSE res := LocalPortInUse
	END
END Connect;

PROCEDURE Listen* (VAR L: Listener; lport: INTEGER; radr: NetIP.Adr; rport: INTEGER; VAR res: INTEGER);
BEGIN 
	IF NetPorts.Available(NetIP.routes[0].adr, lport, radr, rport) THEN NEW(L);
		IF NetPorts.Access(L, NetIP.routes[0].adr, lport, radr, rport, NetPorts.passive) THEN L.state := listen;
			L.lqn := 0; L.lqfirst := NIL; L.lqlast := NIL; res := Done
		ELSE res := DescriptorInUse
		END
	ELSE res := LocalPortInUse
	END
END Listen;

PROCEDURE Requested* (L: Listener): BOOLEAN;
BEGIN
	NetBase.Poll; NetPorts.Enumerate(Poll);
	RETURN L.lqn > 0
END Requested;

PROCEDURE Accept* (L: Listener; VAR C: Connection; VAR res: INTEGER);
BEGIN 
	REPEAT
		NetBase.Poll; NetPorts.Enumerate(Poll)
	UNTIL (L.lqn > 0) OR (L.state = closed);
	IF L.lqn > 0 THEN res := Done;
		C := L.lqfirst; L.lqfirst := L.lqfirst.lq; DEC(L.lqn);
		IF L.lqfirst = NIL THEN L.lqlast := NIL END
	ELSE res := NotDone
	END
END Accept;

PROCEDURE Disconnect* (C: Connection);
BEGIN
	IF (C.instate = rcvd) OR (C.instate = estab) OR (C.instate = clwait) THEN
		IF C.res = ok THEN
			C.flags := C.flags + {sffirst}; C.slast := C.suna + C.scnt;
			IF C.instate = estab THEN C.instate := finw1
			ELSE C.instate := lack
			END;
			Output(C, sendev); DEC(C.ocsem);
		ELSE Delete(C)
		END
	ELSIF C.instate = sent THEN Delete(C)
	END
END Disconnect;

PROCEDURE Close* (L: Listener);
BEGIN L.state := closed;
	WHILE L.lqn > 0 DO Delete(L.lqfirst);
		L.lqfirst := L.lqfirst.lq; DEC(L.lqn)
	END;
	NetPorts.Release(L)
END Close;

PROCEDURE Connected* (C: Connection): BOOLEAN;
BEGIN RETURN ~(rfin IN C.flags)
END Connected;

PROCEDURE Available* (C: Connection): LONGINT;
BEGIN
	NetBase.Poll; NetPorts.Enumerate(Poll);
	IF C.res = ok THEN RETURN C.rcnt ELSE RETURN C.res END
END Available;

PROCEDURE Start*;
BEGIN
	NetIP.InstallDemux(Demux, NetIP.TCP);
	Nreceived := 0; Nsent := 0;
	NetBase.InstallTask(Timer)
END Start;

PROCEDURE Stop*;
BEGIN
	NetIP.RemoveDemux(NetIP.TCP);
	NetPorts.Enumerate(Delete);
	sq.next := sq; sqct := 0
END Stop;

PROCEDURE WriteCode(s: SET);
BEGIN
	IF Fin IN s THEN Kernel.WriteString("Fin") END;
	IF Syn IN s THEN Kernel.WriteString("Syn") END;
	IF Rst IN s THEN Kernel.WriteString("Rst") END;
	IF Psh IN s THEN Kernel.WriteString("Psh") END;
	IF Ack IN s THEN Kernel.WriteString("Ack") END;
	IF Urg IN s THEN Kernel.WriteString("Urg") END
END WriteCode;

PROCEDURE WriteFlags(s: SET);
BEGIN
	IF ssyn IN s THEN Kernel.WriteString("Ssyn") END;
	IF sfin IN s THEN Kernel.WriteString("Sfin") END;
	IF rfin IN s THEN Kernel.WriteString("Rfin") END;
	IF sffirst IN s THEN Kernel.WriteString("Sffirst") END
END WriteFlags;

PROCEDURE WriteIP(ip: NetIP.Adr);
BEGIN
	Kernel.WriteInt(ORD(ip[0]) MOD 100H, 1);  Kernel.WriteChar(".");
	Kernel.WriteInt(ORD(ip[1]) MOD 100H, 1);  Kernel.WriteChar(".");
	Kernel.WriteInt(ORD(ip[2]) MOD 100H, 1);  Kernel.WriteChar(".");
	Kernel.WriteInt(ORD(ip[3]) MOD 100H, 1)
END WriteIP;

PROCEDURE WriteInState(s: LONGINT);
BEGIN
	CASE s OF
		closed: Kernel.WriteString("closed")
		|listen: Kernel.WriteString("listen")
		|sent: Kernel.WriteString("sent")
		|rcvd: Kernel.WriteString("rcvd")
		|estab: Kernel.WriteString("estab")
		|finw1: Kernel.WriteString("finw1")
		|finw2: Kernel.WriteString("finw2")
		|clwait: Kernel.WriteString("clwait")
		|clos: Kernel.WriteString("clos")
		|lack: Kernel.WriteString("lack")
		|tiwait: Kernel.WriteString("tiwait")
		ELSE Kernel.WriteInt(s, 1)
	END
END WriteInState;

PROCEDURE WriteOutState(s: LONGINT);
BEGIN
	CASE s OF
		idle: Kernel.WriteString("idle")
		|trans: Kernel.WriteString("trans")
		|retrans: Kernel.WriteString("retrans")
		|persist: Kernel.WriteString("persist")
		ELSE Kernel.WriteInt(s, 1)
	END
END WriteOutState;

PROCEDURE ShowState*;
VAR c: Connection;
BEGIN
	Kernel.WriteLn;
	Kernel.WriteString("iss=");  Kernel.WriteInt(iss, 1);
	Kernel.WriteString(" sqct=");  Kernel.WriteInt(sqct, 1);
	Kernel.WriteString(" Nreceived=");  Kernel.WriteInt(Nreceived, 1);
	Kernel.WriteString(" Nsent=");  Kernel.WriteInt(Nsent, 1);
	Kernel.WriteLn;
	c := tasklist;
	WHILE c # NIL DO
		WriteIP(c.lip);  Kernel.WriteChar(":");  Kernel.WriteInt(c.lport, 1);  Kernel.WriteChar(" ");
		WriteIP(c.rip);  Kernel.WriteChar(":");  Kernel.WriteInt(c.rport, 1);
		Kernel.WriteString(" in=");  WriteInState(c.instate);
		Kernel.WriteString(" out=");  WriteOutState(c.outstate);
		Kernel.WriteLn;
		Kernel.WriteString(" res=");  Kernel.WriteInt(c.res, 1);	(* return code *)
		Kernel.WriteString(" xcnt=");  Kernel.WriteInt(c.xcnt, 1);	(* number of retransmissions *)
		Kernel.WriteString(" xamt=");  Kernel.WriteInt(c.xamt, 1);	(* retransmission delay *)
		Kernel.WriteString(" pamt=");  Kernel.WriteInt(c.pamt, 1);	(* persist delay *)
		Kernel.WriteString(" code=");  WriteCode(c.code);	(* packet bits in connection *)
		Kernel.WriteString(" flags=");  WriteFlags(c.flags);	(* communication flags *)
		Kernel.WriteLn;
		Kernel.WriteString(" rcnt=");  Kernel.WriteInt(c.rcnt, 1);	(* bytes in receive buffer *)
		Kernel.WriteString(" scnt=");  Kernel.WriteInt(c.scnt, 1);	(* bytes in send buffer *)
		Kernel.WriteString(" swin=");  Kernel.WriteInt(c.swin, 1);	(* send window *)
		Kernel.WriteString(" smss=");  Kernel.WriteInt(c.smss, 1);	(* send MSS *)
		Kernel.WriteString(" rmss=");  Kernel.WriteInt(c.rmss, 1);	(* receive MSS *)
		Kernel.WriteString(" rup=");  Kernel.WriteInt(c.rup, 1);	(* urgent p *)
		Kernel.WriteString(" ocsem=");  Kernel.WriteInt(c.ocsem, 1);
		Kernel.WriteLn;
		Kernel.WriteString(" iss=");  Kernel.WriteInt(c.iss, 1);	(* initial seq *)
		Kernel.WriteString(" swl2=");  Kernel.WriteInt(c.swl2, 1);	(* highest ack seen *)
		Kernel.WriteString(" suna=");  Kernel.WriteInt(c.suna, 1);	(* unacked? *)
		Kernel.WriteString(" snext=");  Kernel.WriteInt(c.snext, 1);	(* next send seq *)
		Kernel.WriteString(" slast=");  Kernel.WriteInt(c.slast, 1);	(* last seq after Disconnect *)
		Kernel.WriteLn;
		Kernel.WriteString(" swl1=");  Kernel.WriteInt(c.swl1, 1);	(* highest seq seen *)
		Kernel.WriteString(" rnext=");  Kernel.WriteInt(c.rnext, 1);	(* next recv seq *)
		Kernel.WriteString(" cwin=");  Kernel.WriteInt(c.cwin, 1);	(* seq of recv window end *)
		Kernel.WriteLn;
		c := c.next
	END
END ShowState;

BEGIN
	NEW(sq);
	sq.next := sq; sqct := 0; iss := Kernel.GetTimer();
	Nreceived := 0; Nsent := 0;
	tasklist := NIL;
	demux[closed] := ProcClosed; demux[sent] := ProcSent;
	demux[rcvd] := ProcRcvd; demux[estab] := ProcEstab;
	demux[finw1] := ProcFinw1; demux[finw2] := ProcFinw2;
	demux[clwait] := ProcClwait; demux[clos] := ProcClos;
	demux[lack] := ProcLack; demux[tiwait] := ProcTiwait
END NetTCP.

Compiler.Compile NetTCP.Mod\s NetSystem.Mod ~

(*
TestTCP.Test 1 lillian 1024	(* receive *)
caused the following on 26.01.1999
NetTCP: tcph.seq < C.rnext 129.132.134.2:19 74 1386
NetTCP: tcph.seq < C.rnext 129.132.134.2:19 1386 74
NetTCP: tcph.seq < C.rnext 129.132.134.2:19 74 20
NetTCP: tcph.seq < C.rnext 129.132.134.2:19 74 1386
NetTCP: tcph.seq < C.rnext 129.132.134.2:19 1386 74
NetTCP: tcph.seq < C.rnext 129.132.134.2:19 74 20
06.04.1999
NetTCP: tcph.seq < C.rnext 129.132.167.4:23 1427 33
NetTCP: tcph.seq < C.rnext 129.132.167.4:23 33 1131
*)
