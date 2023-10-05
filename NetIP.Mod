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

MODULE NetIP;	(** non-portable *)	(* 16.08.96 mg *)

IMPORT SYSTEM, Kernel, NetBase;

CONST
	echoreply* = 0; unreachable* = 3; sourceq = 4; echorequest* = 8; timexc = 11;
	parm = 12; timrq = 13; timrp = 14; maskrequest* = 17; maskreply = 18;
		
	UDP* = 17; TCP* = 6; ICMP = 1; EGP = 8;

	ipid = 0800H; ipver = 4;

	TTL = 32; MinHdrLen* = 20;

	PLen = 8; IcmpHdrLen = 8; DataLength = 56;

	MaxService = 18;	MaxRoutes* = 2;

	AdrLen* = 4;

	(* ARP/RARP *)
	
	hw = 1; arpid = 0806H; rarpid = 08035H;

	request = 1; reply = 2; requestr = 3; replyr = 4;

	free = 0; pending = 1; resolved = 2;
	
	arpqsize = 10;	(* max items in queue per arp entry *)
	timo = 600;	(* timeout in s of arp entries *)
	rsend = 1;	(* arp resend interval in s *)
	mretry = 4;	(* max arp resends *)
	
	arplen = 28;  iplen = 20;
	
	(* route options *)
	arpopt* = 0;
	
	Trace = FALSE;
	
TYPE
	Adr* = ARRAY AdrLen OF SYSTEM.BYTE;

	IPHeader* = POINTER TO IPHeaderDesc;

	Arp* = POINTER TO ArpDesc;

	ArpDesc* =RECORD
		hwtype*: INTEGER;
		prtype*: INTEGER;
		hwlen*: SHORTINT;
		prlen*: SHORTINT;
		op*: INTEGER;
		sha*: ARRAY NetBase.AdrLen OF SYSTEM.BYTE;
		spa*: Adr;
		tha*: ARRAY NetBase.AdrLen OF SYSTEM.BYTE;
		tpa*: Adr
	END;

	Route* = POINTER TO RouteDesc;
	
	Entry = POINTER TO EntryDesc;
	EntryDesc = RECORD
		state: INTEGER;
		att, ttl: INTEGER;
		queue: NetBase.Queue;	(* state = free => Empty(queue) *)
		hwa: ARRAY NetBase.AdrLen OF SYSTEM.BYTE;
		pra: Adr;
		route: Route;
		next: Entry
	END;
	
	IPHeaderDesc* = RECORD
		verlen*, tos*: SHORTINT;
		len*, id*, frag*: INTEGER;
		ttl*, protocol*: SHORTINT;
		checksum*: INTEGER;
		src*, dst*: Adr;
		(*optdata*)
	END;
				
	ICMPHeader* = POINTER TO ICMPHeaderDesc;
	
	ICMPHeaderDesc* = RECORD
		type*, code*: SHORTINT;
		checksum*: INTEGER
	END;
	
	EchoMsg = POINTER TO EchoMsgDesc;
	
	EchoMsgDesc* = RECORD
		id*, seq*: INTEGER;
		optdata*: ARRAY DataLength OF SYSTEM.BYTE
	END;
	
	ParamMsg* = POINTER TO ParamMsgDesc;
	
	ParamMsgDesc* = RECORD
		ptr*, uusd1*: SHORTINT;
		uusd2*: INTEGER;
		optdata*: ARRAY MinHdrLen + PLen OF SYSTEM.BYTE
	END;
	
	MaskMsg* = POINTER TO MaskMsgDesc;

	MaskMsgDesc* = RECORD
		id*, seq*: INTEGER;
		mask*: Adr
	END;

	GenMsg* = POINTER TO GenMsgDesc;
	
	GenMsgDesc* = RECORD
		uusd*: LONGINT;
		optdata*: ARRAY MinHdrLen + PLen OF SYSTEM.BYTE
	END;
	
	RouteDesc* = RECORD
		adr*, subnet*, gway*: Adr;
		dev*: NetBase.Device;
		options*: SET
	END;
	
	DemuxProc* = PROCEDURE(item: NetBase.Item);

VAR
	(* icmp counters *)
	echoreqs*, echoreps*, unreachmsgs*, srcreqs*, timeouts*, parmsgs*: LONGINT;
	
	ippackid: LONGINT;

	(* Broadcast addresses: all'1s/all'0(BSD broadcast)/net broadcast/subnet broadcast *)
	IPall*, IPany*: Adr;

	netmask, submask: SET;	(* masks for broadcast check (Broadcast) *)

	NreceivedArp, NsentArp, Nreceived, Nsent, NreceivedIcmp, NsentIcmp: LONGINT;

	i: INTEGER;

	(* ARP *)

	cache: Entry;

	demux: ARRAY MaxService OF DemuxProc;

	routes*: ARRAY MaxRoutes OF Route;
	nofRoutes*: INTEGER;

	last, lact: LONGINT;

PROCEDURE IllegalClass (adr: Adr): BOOLEAN;
VAR set: SET; num: SHORTINT;
BEGIN
	num := SYSTEM.VAL(SHORTINT, adr[0]);
	set := SYSTEM.VAL(SET, LONG(LONG(num)));
	RETURN (set * {4..7} = {5..7}) OR (set * {4..7} = {4..7})
END IllegalClass;

PROCEDURE ClassA (adr: Adr): BOOLEAN;
VAR
	set: SET;
	num: SHORTINT;
BEGIN num := SYSTEM.VAL(SHORTINT, adr[0]);
	set := SYSTEM.VAL(SET, LONG(LONG(num))); RETURN set * {7} = {}
END ClassA;

PROCEDURE ClassB (adr: Adr): BOOLEAN;
VAR
	set: SET;
	num: SHORTINT;
BEGIN num := SYSTEM.VAL(SHORTINT, adr[0]);
	set := SYSTEM.VAL(SET, LONG(LONG(num))); RETURN set * {6,7} = {7}
END ClassB;

PROCEDURE ClassC (adr: Adr): BOOLEAN;
VAR
	set: SET;
	num: SHORTINT;
BEGIN num := SYSTEM.VAL(SHORTINT, adr[0]);
	set := SYSTEM.VAL(SET, LONG(LONG(num))); RETURN set * {5..7} = {6,7}
END ClassC;

PROCEDURE IsBroadcast* (adr: Adr): BOOLEAN;
VAR dstmask, hostmask: SET;
BEGIN
	dstmask := SYSTEM.VAL(SET, adr);
	IF (dstmask # SYSTEM.VAL(SET, IPall)) & (dstmask # SYSTEM.VAL(SET, IPany)) THEN
		IF dstmask * submask = submask THEN hostmask := dstmask * (-submask);
			RETURN (hostmask = {}) OR (hostmask = -submask)
		ELSIF dstmask * netmask = netmask THEN hostmask := dstmask * (-netmask);
			RETURN (hostmask = {}) OR (hostmask = -netmask)
		ELSE RETURN dstmask = {} (* BSD broadcast *)
		END
	ELSE RETURN TRUE
	END
END IsBroadcast;

PROCEDURE HdrLen* (hdr: IPHeader): INTEGER;
BEGIN
	RETURN SHORT(ASH(hdr.verlen MOD 16, 2))
END HdrLen;

PROCEDURE VerLen* (hdr: IPHeader);
VAR
	set: SET;
BEGIN set := SYSTEM.VAL(SET, ASH(ipver, 4)) + {0, 2};
	hdr.verlen := SHORT(SHORT(SYSTEM.VAL(LONGINT, set)))
END VerLen;

PROCEDURE NewEntry (VAR entry: Entry);
BEGIN NEW(entry); NetBase.Reset(entry.queue);
	entry.next := cache.next; cache.next := entry
END NewEntry;

PROCEDURE FindEntry (adr: Adr; VAR entry: Entry; VAR fnd: BOOLEAN);
VAR
	tentry: Entry;
BEGIN tentry := NIL;
	entry := cache.next;
	WHILE (entry # cache) & ((entry.state = free) OR ~NetBase.Equal(adr, entry.pra, AdrLen)) DO
		IF entry.state = free THEN tentry := entry END;
		entry := entry.next
	END;
	fnd := entry # cache;
	IF ~fnd THEN entry := tentry END
END FindEntry;

PROCEDURE SendArp (route: Route; ipdst: Adr);
VAR
	arp: Arp;
	dev: NetBase.Device;
	item: NetBase.Item;
BEGIN dev := route.dev; NetBase.NewItem(item);
	DEC(item.ofs, arplen);  INC(item.len, arplen);
	arp := SYSTEM.VAL(Arp, SYSTEM.ADR(item.data[item.ofs]));
	arp.hwtype := hw; NetBase.HostToNet(arp.hwtype);
	arp.prtype := ipid; NetBase.HostToNet(arp.prtype);
	arp.hwlen := NetBase.AdrLen; arp.prlen := AdrLen;
	arp.op := request; NetBase.HostToNet(arp.op);
	
	NetBase.Copy(dev.hostAdr, arp.sha, NetBase.AdrLen);
	NetBase.Copy(route.adr, arp.spa, AdrLen);
	NetBase.Copy(NetBase.anyadr, arp.tha, NetBase.AdrLen);
	NetBase.Copy(ipdst, arp.tpa, AdrLen);
	
	dev.Send(dev, arpid, dev.castAdr, item);
	INC(NsentArp)
END SendArp;

PROCEDURE ^ IPReceive* (item: NetBase.Item);

PROCEDURE ArpSend (route: Route; ipdst: Adr; item: NetBase.Item);
VAR
	entry: Entry;
	dev: NetBase.Device;
	fnd: BOOLEAN;
BEGIN	(* assumed: address is resolved *)
	IF Trace THEN Kernel.WriteString("ArpSend: ") END;
	IF NetBase.Equal(route.adr, ipdst, AdrLen) THEN
		IF Trace THEN Kernel.WriteString("local") END;
		IPReceive(item)
	ELSIF IsBroadcast(ipdst) THEN dev := route.dev;
		IF Trace THEN Kernel.WriteString("bcast") END;
		dev.Send(dev, ipid, dev.castAdr, item);
		INC(NsentArp)
	ELSE FindEntry(ipdst, entry, fnd);
		IF fnd THEN
			IF entry.state = resolved THEN dev := route.dev;
				IF Trace THEN Kernel.WriteString("resolved") END;
				dev.Send(dev, ipid, entry.hwa, item);
				INC(NsentArp)
			ELSIF entry.state = pending THEN
				IF Trace THEN Kernel.WriteString("pending") END;
				IF entry.queue.len < arpqsize THEN NetBase.PutItem(entry.queue, item)
				ELSE NetBase.RecycleItem(item)
				END
			ELSE HALT(MAX(INTEGER))
			END
		ELSE
			IF Trace THEN Kernel.WriteString("unresolved") END;
			IF entry = NIL THEN NewEntry(entry) END;
			entry.state := pending; entry.att := 1; entry.ttl := rsend;
			NetBase.PutItem(entry.queue, item); entry.route := route;
			NetBase.Copy(ipdst, entry.pra, AdrLen);
			SendArp(route, ipdst)
		END
	END;
	IF Trace THEN Kernel.WriteLn END
END ArpSend;

PROCEDURE NetMatch* (route: Route; adr: Adr): BOOLEAN;
VAR
	srcmask, dstmask: SET;
BEGIN  srcmask := SYSTEM.VAL(SET, route.adr) * SYSTEM.VAL(SET, route.subnet);
	dstmask := SYSTEM.VAL(SET, adr) * SYSTEM.VAL(SET, route.subnet);
	RETURN srcmask = dstmask
END NetMatch;

PROCEDURE GetRoute (adr: Adr): INTEGER;
VAR i: INTEGER;
BEGIN
	i := 0;  WHILE (i < nofRoutes) & ~NetMatch(routes[i], adr) DO INC(i) END;
	IF i < nofRoutes THEN RETURN i ELSE RETURN 0 END
END GetRoute;

(** IPSend - Send an IP packet.  IP header is prepended to item here. *)

PROCEDURE IPSend* (src, dst: Adr; protocol: SHORTINT; item: NetBase.Item);
VAR
	hdr: IPHeader;
	dev: NetBase.Device;
	dmy: ARRAY 1 OF SYSTEM.BYTE;
BEGIN DEC(item.ofs, iplen); INC(item.len, iplen);	(* add IP header *)
	hdr := SYSTEM.VAL(IPHeader, SYSTEM.ADR(item.data[item.ofs]));
	VerLen(hdr); hdr.tos := 0; hdr.len := item.len;	(* length includes IP header *)
	hdr.id := SHORT(ippackid); ippackid := (ippackid + 1) MOD MAX(INTEGER);
	hdr.frag := 0; hdr.ttl := TTL; hdr.protocol := protocol;
	NetBase.HostToNet(hdr.len); NetBase.HostToNet(hdr.id); NetBase.HostToNet(hdr.frag);
	hdr.dst := dst;  hdr.src := src;

	hdr.checksum := 0; hdr.checksum := SHORT(NetBase.CheckSum(hdr^, HdrLen(hdr), 0));
	INC(Nsent);
	
	IF IsBroadcast(hdr.dst) THEN i := 0;
		IF Trace THEN Kernel.WriteString("IPSend: Broadcast"); Kernel.WriteLn END;
		WHILE i < nofRoutes DO
			IF arpopt IN routes[i].options THEN
				ArpSend(routes[i], hdr.dst, item)
			ELSE dev := routes[i].dev;
				dev.Send(dev, ipid, dmy, item)
			END;
			INC(i)
		END
	ELSE
		IF nofRoutes = 1 THEN i := 0 ELSE i := GetRoute(hdr.dst) END;
		IF Trace THEN Kernel.WriteString("IPSend: Route "); Kernel.WriteInt(i, 1) END;
		IF arpopt IN routes[i].options THEN
			IF NetMatch(routes[i], hdr.dst) THEN
				IF Trace THEN Kernel.WriteString(" direct") END;
				ArpSend(routes[i], hdr.dst, item)
			ELSE
				IF Trace THEN Kernel.WriteString(" gateway") END;
				ArpSend(routes[i], routes[i].gway, item)
			END
		ELSE dev := routes[i].dev;
			IF Trace THEN Kernel.WriteString(" dirlink") END;
			dev.Send(dev, ipid, dmy, item)
		END;
		IF Trace THEN Kernel.WriteLn END
	END
END IPSend;

PROCEDURE ICMPCheckSum* (hdr: ICMPHeader; len: INTEGER): LONGINT;
BEGIN RETURN NetBase.CheckSum(hdr^, len, 0)
END ICMPCheckSum;

(** ICMPSend - Send an ICMP packet *)

PROCEDURE ICMPSend* (dst: Adr; type, code: SHORTINT; val1, val2: INTEGER; data: ARRAY OF SYSTEM.BYTE);
VAR
	item: NetBase.Item;
	icmphdr: ICMPHeader;
	echo: EchoMsg;
	gnl: GenMsg;
	prm: ParamMsg;
	(*mask: MaskMsg;*)
	i: INTEGER;
BEGIN NetBase.NewItem(item);

	CASE type OF
	echoreply, echorequest:
		DEC(item.ofs, SIZE(EchoMsgDesc));  INC(item.len, SIZE(EchoMsgDesc));
		echo := SYSTEM.VAL(EchoMsg, SYSTEM.ADR(item.data[item.ofs]));
		echo.id := val1; NetBase.HostToNet(echo.id);
		echo.seq := val2; NetBase.HostToNet(echo.seq);
		IF type = echoreply THEN i := 0;
			WHILE i < DataLength DO echo.optdata[i] := data[i]; INC(i) END
		ELSE i := 0;
			WHILE i < DataLength DO echo.optdata[i] := CHR(i); INC(i) END
		END
	|unreachable, timexc, sourceq:
		HALT(MAX(INTEGER))	(* not implemented yet *)
(*
		gnl := SYSTEM.VAL(GenMsg, SYSTEM.ADR(icmphdr.optdata[0]));
		gnl.uusd := 0; dlen := MinHdrLen + PLen;
		SYSTEM.MOVE(SYSTEM.ADR(item.data[0]), SYSTEM.ADR(gnl.optdata[0]), dlen)
*)
	|parm:
		HALT(MAX(INTEGER))	(* not implemented yet *)
(*
		prm := SYSTEM.VAL(ParamMsg, SYSTEM.ADR(icmphdr.optdata[0]));
		prm.ptr := SHORT(val1); prm.uusd1 := 0; prm.uusd2 := 0;
		dlen := MinHdrLen + PLen;
		SYSTEM.MOVE(SYSTEM.ADR(item.data[0]), SYSTEM.ADR(prm.optdata[0]), dlen)
*)
	|maskrequest:
		HALT(MAX(INTEGER))	(* not implemented yet *)
(*
		mask := SYSTEM.VAL(MaskMsg, SYSTEM.ADR(icmphdr.optdata[0]));
		mask.id := 0; (* here has to come something *) mask.seq := 0; 
		NetBase.Copy(IPany, mask.mask, AdrLen); dlen := AdrLen
*)
	ELSE NetBase.RecycleItem(item); RETURN
	END;

	DEC(item.ofs, SIZE(ICMPHeaderDesc));  INC(item.len, SIZE(ICMPHeaderDesc));
	icmphdr := SYSTEM.VAL(ICMPHeader, SYSTEM.ADR(item.data[item.ofs]));
	icmphdr.type := type; icmphdr.code := code;
	
	icmphdr.checksum := 0;
	icmphdr.checksum := SHORT(ICMPCheckSum(icmphdr, item.len));
	INC(NsentIcmp);
	IPSend(routes[0].adr, dst, ICMP, item)
END ICMPSend;

(** IPReceive - Process an IP packet (including header). *)

PROCEDURE IPReceive* (item: NetBase.Item);
VAR hdr: IPHeader;  checksum: INTEGER;  bcast: BOOLEAN;
BEGIN
	INC(Nreceived);
	hdr := SYSTEM.VAL(IPHeader, SYSTEM.ADR(item.data[item.ofs]));
	IF hdr.verlen DIV 16 = ipver THEN
		bcast := IsBroadcast(hdr.dst);
		IF bcast OR ~IllegalClass(hdr.dst) THEN
			checksum := hdr.checksum; hdr.checksum := 0;
			IF SHORT(NetBase.CheckSum(hdr^, HdrLen(hdr), 0)) = checksum THEN
				IF HdrLen(hdr) = MinHdrLen THEN	(* can not currently handle options *)
					NetBase.NetToHost(hdr.len); NetBase.NetToHost(hdr.id); NetBase.NetToHost(hdr.frag);
					IF (hdr.frag = 0) OR (hdr.frag DIV 2000H = 2) THEN
						IF NetBase.Equal(hdr.dst, routes[0].adr, AdrLen) OR bcast THEN
							demux[hdr.protocol](item)
						ELSE NetBase.RecycleItem(item)
						END
					ELSE NetBase.RecycleItem(item)
					END
				ELSE NetBase.RecycleItem(item)
				END
			ELSE NetBase.RecycleItem(item)
			END
		ELSE NetBase.RecycleItem(item)
		END
	ELSE NetBase.RecycleItem(item)
	END
END IPReceive;

(* ICMPReceive - Handle incoming ICMP packets *)

PROCEDURE ICMPReceive (item: NetBase.Item);
VAR
	icmphdr: ICMPHeader;
	mask: MaskMsg;
	echo: EchoMsg;
	hdr: IPHeader;
	checksum, i: INTEGER;
BEGIN INC(NreceivedIcmp);
	hdr := SYSTEM.VAL(IPHeader, SYSTEM.ADR(item.data[item.ofs]));
	icmphdr := SYSTEM.VAL(ICMPHeader, SYSTEM.ADR(item.data[item.ofs + HdrLen(hdr)]));
	checksum := icmphdr.checksum; icmphdr.checksum := 0;
	IF SHORT(ICMPCheckSum(icmphdr, hdr.len - HdrLen(hdr))) = checksum THEN
		IF icmphdr.type = echorequest THEN INC(echoreqs);
			echo := SYSTEM.VAL(EchoMsg, SYSTEM.VAL(LONGINT, icmphdr) + SIZE(ICMPHeaderDesc));
			NetBase.NetToHost(echo.id); NetBase.NetToHost(echo.seq);		
			ICMPSend(hdr.src, echoreply, 0, echo.id, echo.seq, echo.optdata)
		ELSIF icmphdr.type = maskreply THEN i := 0;
			WHILE (i < nofRoutes) & ~NetBase.Equal(hdr.dst, routes[i].adr, AdrLen) DO INC(i) END;
			IF i < nofRoutes THEN
				mask := SYSTEM.VAL(MaskMsg, SYSTEM.ADR(item.data[item.ofs]) + SIZE(ICMPHeaderDesc)); 
				NetBase.Copy(mask.mask, routes[i].subnet, AdrLen)
			END
		ELSE
			CASE icmphdr.type OF
			echoreply: echoreps := echoreps + 1
			|unreachable: unreachmsgs := unreachmsgs + 1
			|sourceq: srcreqs := srcreqs + 1
			|timexc: timeouts := timeouts + 1
			|parm: parmsgs := parmsgs + 1
			ELSE
			END
		END
	ELSE (*Kernel.WriteString("Bad ICMP checksum"); Kernel.WriteLn*)
	END;
	NetBase.RecycleItem(item)
END ICMPReceive;

PROCEDURE Dmy (item: NetBase.Item);
(*VAR hdr: IPHeader;*)
BEGIN
(*
	hdr := SYSTEM.VAL(IPHeader, SYSTEM.ADR(item.data[0]));
	EN.Copy(hdr.src, hdr.dst, AdrLen);
	IcmpSend(item, unreachable, 2, 0)
*)
	NetBase.RecycleItem(item)
END Dmy;

(* ARP *)

PROCEDURE ArpReceive (item: NetBase.Item);
VAR
	arp: Arp;
	route: Route;
	dev: NetBase.Device;
	entry: Entry;
	it: NetBase.Item;
	prtype, hwtype: INTEGER;
	fnd: BOOLEAN;
BEGIN INC(NreceivedArp);
	arp := SYSTEM.VAL(Arp, SYSTEM.ADR(item.data[item.ofs]));
	hwtype := arp.hwtype; NetBase.NetToHost(hwtype);
	prtype := arp.prtype; NetBase.NetToHost(prtype);
	IF (hwtype = hw) & (prtype = ipid) THEN
		FindEntry(arp.spa, entry, fnd);
		IF fnd THEN NetBase.Copy(arp.sha, entry.hwa, arp.hwlen);
			entry.state := resolved; entry.ttl := timo; route := entry.route; dev := route.dev;
			WHILE entry.queue.len > 0 DO NetBase.GetItem(entry.queue, it);
				dev.Send(dev, ipid, entry.hwa, it)
			END
		ELSE
			IF entry = NIL THEN NewEntry(entry) END;
			entry.state := resolved; entry.att := 0; entry.ttl := timo;
			NetBase.Copy(arp.sha, entry.hwa, NetBase.AdrLen);
			NetBase.Copy(arp.spa, entry.pra, AdrLen);
			entry.route := routes[GetRoute(entry.pra)]
		END;
		NetBase.NetToHost(arp.op);
		IF arp.op = request THEN i := GetRoute(arp.tpa);
			IF NetBase.Equal(routes[i].adr, arp.tpa, AdrLen) THEN
				arp.op := reply; NetBase.HostToNet(arp.op);
				
				NetBase.Copy(arp.spa, arp.tpa, AdrLen);
				NetBase.Copy(arp.sha, arp.tha, NetBase.AdrLen);

				NetBase.Copy(routes[i].adr, arp.spa, AdrLen);
				dev := routes[i].dev; NetBase.Copy(dev.hostAdr, arp.sha, NetBase.AdrLen);
				item.len := arplen;
				dev.Send(dev, arpid, arp.tha, item)
			ELSE NetBase.RecycleItem(item)
			END
		ELSE NetBase.RecycleItem(item)
		END
	ELSE NetBase.RecycleItem(item)
	END
END ArpReceive;

PROCEDURE Timer*(now: LONGINT);
VAR cur: Entry;  item: NetBase.Item;  delay: LONGINT;
BEGIN
	IF now - lact > Kernel.TimeUnit*3 THEN
		delay := (now - last) DIV Kernel.TimeUnit; last := now;
		cur := cache.next;
		WHILE cur # cache DO
			IF cur.state # free THEN
				cur.ttl := SHORT(cur.ttl - delay);
				IF cur.ttl <= 0 THEN
					IF (cur.state # resolved) & (cur.att < mretry) THEN
						INC(cur.att); cur.ttl := rsend; SendArp(cur.route, cur.pra)
					ELSE cur.state := free;
						WHILE cur.queue.len > 0 DO NetBase.GetItem(cur.queue, item);
							NetBase.RecycleItem(item)
						END
					END
				END
			END;
			cur := cur.next
		END;
		lact := Kernel.GetTimer()
	END
END Timer;

PROCEDURE InstallDemux* (proc: DemuxProc; service: INTEGER);
BEGIN demux[service] := proc
END InstallDemux;

PROCEDURE RemoveDemux* (service: INTEGER);
BEGIN demux[service] := Dmy
END RemoveDemux;

PROCEDURE StartIP*;
BEGIN
	NetBase.InstallProtocol(ArpReceive, arpid);
	NreceivedArp := 0; NsentArp := 0; cache.next := cache;
	last := Kernel.GetTimer(); lact := last;
	NetBase.InstallProtocol(IPReceive, ipid);
	NetBase.InstallTask(Timer);
	Nreceived := 0; Nsent := 0; NreceivedIcmp := 0; NsentIcmp := 0;
	echoreqs := 0; echoreps := 0; unreachmsgs := 0; srcreqs := 0; timeouts := 0; parmsgs := 0
END StartIP;

PROCEDURE StopIP*;
VAR cur: Entry;  item: NetBase.Item;
BEGIN
	cur := cache.next;
	WHILE cur # cache DO cur.state := free;
		WHILE cur.queue.len > 0 DO NetBase.GetItem(cur.queue, item);
			NetBase.RecycleItem(item)
		END;
		cur := cur.next
	END;
	nofRoutes := 0
END StopIP;

PROCEDURE SetDirectedCast* (route: Route);
BEGIN
	IF ClassA(route.adr) THEN netmask := {0..7}
	ELSIF ClassB(route.adr) THEN netmask := {0..15}
	ELSIF ClassC(route.adr) THEN netmask := {0..23}
	ELSE netmask := {0..31}
	END;
	submask := SYSTEM.VAL(SET, route.subnet)
END SetDirectedCast;

PROCEDURE InstallRoute*(route: Route);
BEGIN
	routes[nofRoutes] := route; INC(nofRoutes)
END InstallRoute;

BEGIN
	nofRoutes := 0;
	IPall[0] := 0FFX; IPall[1] := 0FFX; IPall[2] := 0FFX; IPall[3] := 0FFX;
	IPany[0] := 0X; IPany[1] := 0X; IPany[2] := 0X; IPany[3] := 0X;
	netmask := {}; submask := {};

	NEW(cache); cache.next := cache;

	i := 0; WHILE i < MaxService DO demux[i] := Dmy; INC(i) END;

	InstallDemux(ICMPReceive, ICMP);

	NreceivedArp := 0; NsentArp := 0; Nreceived := 0; Nsent := 0; NreceivedIcmp := 0; NsentIcmp := 0;
	echoreqs := 0; echoreps := 0; unreachmsgs := 0; srcreqs := 0; timeouts := 0; parmsgs := 0
END NetIP.
