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

MODULE NetDNS;	(** non-portable *)	(* 16.08.96 mg *)

IMPORT SYSTEM, Kernel, NetBase, NetPorts, NetIP, NetUDP;

CONST
	ArpaDomain = "IN-ADDR.ARPA";

	A = 1; PTR = 12; INx = 1; RD = 100H;
	T0 = 3 * Kernel.TimeUnit;	(*3 sec*)

	MaxDns = 4; MaxDom = 2;

	DNSPort = 53;

	Trace = FALSE;
	
CONST
	Done* = 0; NotDone* = 1;
		
TYPE
	Host* = POINTER TO RECORD
		name: ARRAY 64 OF CHAR;
		adr*: NetIP.Adr
	END;

	Cache = POINTER TO RECORD
		next: Cache;
		name: ARRAY 64 OF CHAR;
		adr: NetIP.Adr;
		expire: LONGINT
	END;
	
	DomName = ARRAY 65 OF CHAR;

VAR
	server*: ARRAY MaxDns OF Host;	(* all exported read-only *)
	dns*, nofdns*: INTEGER;
	dom*: ARRAY MaxDom OF DomName;
	nofdom*: INTEGER;
	id: INTEGER;
	cache: Cache;
	lastcleanup: LONGINT;

	Nreceived, Nsent: LONGINT;

PROCEDURE CacheCleanup;
VAR c, p: Cache;  now: LONGINT;
BEGIN
	now := Kernel.GetTimer();
	IF now - lastcleanup > Kernel.TimeUnit THEN
		lastcleanup := now;
		p := cache;  c := cache.next;
		WHILE c # NIL DO
			IF c.expire - now < 0 THEN
				IF Trace THEN
					Kernel.WriteChar("(");  Kernel.WriteString(c.name);  Kernel.WriteString(" expired) ")
				END;
				p.next := c.next;  c := c.next
			ELSE
				p := c;  c := c.next
			END
		END
	END
END CacheCleanup;

PROCEDURE CacheAdd(name: ARRAY OF CHAR;  adr: NetIP.Adr;  timeout: LONGINT);
VAR c: Cache;  expire: LONGINT;
BEGIN
	IF timeout > MAX(LONGINT) DIV Kernel.TimeUnit THEN timeout := MAX(LONGINT)
	ELSE timeout := timeout * Kernel.TimeUnit
	END;
	expire := Kernel.GetTimer() + timeout;  c := cache.next;
	WHILE (c # NIL) & (name # c.name) & (~NetBase.Equal(adr, c.adr, NetIP.AdrLen)) DO c := c.next END;
	IF c = NIL THEN
		IF Trace THEN Kernel.WriteString("added ");  Kernel.WriteInt(timeout, 1) END;
		NEW(c);  COPY(name, c.name);  NetBase.Copy(adr, c.adr, NetIP.AdrLen);
		c.expire := expire;  c.next := cache.next;  cache.next := c
	ELSE
		IF expire - c.expire > 0 THEN
			IF Trace THEN Kernel.WriteString("refreshed ");  Kernel.WriteInt(timeout, 1) END;
			c.expire := expire;  COPY(name, c.name);  NetBase.Copy(adr, c.adr, NetIP.AdrLen)
		END
	END
END CacheAdd;

PROCEDURE CacheFindName(name: ARRAY OF CHAR): Cache;
VAR c: Cache;
BEGIN
	CacheCleanup;
	c := cache.next;
	WHILE (c # NIL) & (name # c.name) DO c := c.next END;
	IF Trace THEN IF c = NIL THEN Kernel.WriteString("not ") END;  Kernel.WriteString("found ") END;
	RETURN c
END CacheFindName;

PROCEDURE CacheFindAdr(adr: NetIP.Adr): Cache;
VAR c: Cache;
BEGIN
	CacheCleanup;
	c := cache.next;
	WHILE (c # NIL) & (~NetBase.Equal(adr, c.adr, NetIP.AdrLen)) DO c := c.next END;
	IF Trace THEN IF c = NIL THEN Kernel.WriteString("not ") END;  Kernel.WriteString("found ") END;
	RETURN c
END CacheFindAdr;

PROCEDURE AppW(VAR k: INTEGER; VAR buf: ARRAY OF CHAR; n: INTEGER);
BEGIN buf[k] := CHR(n DIV 100H); buf[k+1] := CHR(n MOD 100H); INC(k, 2)
END AppW;

PROCEDURE QSect(VAR k: INTEGER; VAR buf, name: ARRAY OF CHAR; type, class: INTEGER);
VAR
	i, j: INTEGER;
BEGIN i := 0; j := k; (*k0 := k;*) INC(k);
	WHILE name[i] # 0X DO
		IF name[i] = "." THEN buf[j] := CHR(k - j - 1); j := k	(*fixup len*)
		ELSE buf[k] := name[i]
		END;
		INC(k); INC(i)
	END;
	buf[j] := CHR(k - j - 1); buf[k] := 0X; INC(k);
	AppW(k, buf, type); AppW(k, buf, class);
	(*type -> buf[j..j+1]*)
	(*class -> buf[j+2..j+3]*)
END QSect;

PROCEDURE PickW(VAR k: INTEGER; VAR buf: ARRAY OF CHAR; VAR n: INTEGER);
BEGIN n := SHORT(ASH(ORD(buf[k]), 8)) + ORD(buf[k+1]); INC(k, 2)
END PickW;

PROCEDURE Cap(VAR s: ARRAY OF CHAR);
VAR
	ch: CHAR;
	i: INTEGER;
BEGIN i := 0;
	WHILE s[i] # 0X DO ch := s[i];
		IF (ch >= "a") & (ch <= "z") THEN s[i] := CAP(ch) END; INC(i)
	END
END Cap;

PROCEDURE Name(VAR k, i: INTEGER; VAR buf, name: ARRAY OF CHAR);
VAR
	len, k0: INTEGER;
BEGIN len := ORD(buf[k]); INC(k);
	WHILE (len > 0) DO
		IF len >= 0C0H THEN k0 := 100H*(len-0C0H)+ORD(buf[k]); INC(k);
			Name(k0, i, buf, name); name[i] := 0X; RETURN
		ELSE
			WHILE len > 0 DO name[i] := buf[k]; INC(i); INC(k); DEC(len) END;
		END;
		len := ORD(buf[k]); INC(k);
		IF len > 0 THEN name[i] := "."; INC(i) END
	END;
	name[i] := 0X; Cap(name)
END Name;

PROCEDURE Header (VAR k: INTEGER; VAR buf: ARRAY OF CHAR; id, bits, qd, an, ns, ar: INTEGER);
BEGIN AppW(k, buf, id); AppW(k, buf, bits); AppW(k, buf, qd); AppW(k, buf, an);
	AppW(k, buf, ns); AppW(k, buf, ar)
END Header;

PROCEDURE Domain (VAR name: ARRAY OF CHAR; localdom: ARRAY OF CHAR; forced: BOOLEAN);
VAR
	i, j: INTEGER;
BEGIN i := 0; j := 0;
	WHILE name[i] # 0X DO
		IF name[i] = "." THEN j := i END; INC(i)
	END;
	IF forced OR (j = 0) THEN j := 0;
		name[i] := "."; INC(i); (*append domain*)
		WHILE localdom[j] # 0X DO name[i] := localdom[j]; INC(i); INC(j) END;
		name[i] := 0X
	END
END Domain;

PROCEDURE RetrieveHost (buf: ARRAY OF CHAR; VAR name: ARRAY OF CHAR; VAR timeout: LONGINT);
VAR
	name0: ARRAY 64 OF CHAR;
	i, k, l, id0, bits, qd, an, ns, ar, type, class, xx, ttl: INTEGER;
BEGIN k := 0;
	PickW(k, buf, id0);
	IF id0 = id THEN PickW(k, buf, bits);
		PickW(k, buf, qd); PickW(k, buf, an); PickW(k, buf, ns); PickW(k, buf, ar);
		IF bits MOD 10H = 0 THEN
			WHILE qd > 0 DO i := 0;
				Name(k, i, buf, name0); PickW(k, buf, type); PickW(k, buf, class);
				DEC(qd)
			END;
			WHILE an > 0 DO i := 0;
				Name(k, i, buf, name0); PickW(k, buf, type); PickW(k, buf, class);
				PickW(k, buf, xx); PickW(k, buf, ttl); PickW(k, buf, l);
				timeout := ttl;  IF timeout < 0 THEN INC(timeout, 65536) END;
				IF type = PTR THEN i := 0; Name(k, i, buf, name)
				ELSE INC(k, l)
				END;
				DEC(an)
			END
		END
	END
END RetrieveHost;

PROCEDURE RetrieveAdr (buf: ARRAY OF CHAR; VAR adr: NetIP.Adr; VAR timeout: LONGINT);
VAR
	name0: ARRAY 64 OF CHAR;
	adr0: NetIP.Adr;
	i, k, l, id0, bits, qd, an, ns, ar, type, class, xx, ttl: INTEGER;
BEGIN k := 0;  timeout := 0;
	PickW(k, buf, id0);
	IF id0 = id THEN PickW(k, buf, bits);
		PickW(k, buf, qd); PickW(k, buf, an); PickW(k, buf, ns); PickW(k, buf, ar);
		IF bits MOD 10H = 0 THEN
			WHILE qd > 0 DO i := 0;
				Name(k, i, buf, name0); PickW(k, buf, type); PickW(k, buf, class);
				DEC(qd)
			END;
			WHILE an > 0 DO i := 0;
				Name(k, i, buf, name0); PickW(k, buf, type); PickW(k, buf, class);
				PickW(k, buf, xx); PickW(k, buf, ttl); PickW(k, buf, l);
				timeout := ttl;  IF timeout < 0 THEN INC(timeout, 65536) END;
				IF type = A THEN
					adr0[0] := buf[k]; adr0[1] := buf[k+1]; adr0[2] := buf[k+2]; adr0[3] := buf[k+3];
					IF NetBase.Equal(adr, NetIP.IPany, NetIP.AdrLen) OR (NetIP.arpopt IN NetIP.routes[0].options) & NetIP.NetMatch(NetIP.routes[0], adr0) THEN
						NetBase.Copy(adr0, adr, NetIP.AdrLen)
					END;
					INC(k, 4)
				ELSE INC(k, l)
				END;
				DEC(an)
			END
		END
	END
END RetrieveAdr;

PROCEDURE ReceiveInfo (dns: NetIP.Adr; name: ARRAY OF CHAR; type: INTEGER; VAR buf: ARRAY OF CHAR; VAR len: LONGINT);
VAR
	C: NetUDP.Connection;
	radr: NetIP.Adr;
	rport: INTEGER;
	T: LONGINT;
	k, res: INTEGER;
BEGIN k := 0;
	Header(k, buf, id, 0 + RD, 1, 0, 0, 0); QSect(k, buf, name, type, INx);
	NetUDP.Open(C, NetPorts.anyport, NetIP.IPany, NetPorts.anyport, res);
	IF res = NetUDP.Done THEN NetUDP.Send(C, dns, DNSPort, buf, 0, k);
		T := Kernel.GetTimer() + T0; INC(Nsent);
		REPEAT NetUDP.Receive(C, radr, rport, buf, 0, len);
			IF len > 0 THEN INC(Nreceived) END
		UNTIL (rport = DNSPort) & (len > 0) OR (Kernel.GetTimer() - T > 0);
		NetUDP.Close(C)
	ELSE len := 0
	END
END ReceiveInfo;

PROCEDURE HostByName* (hostname: ARRAY OF CHAR; VAR adr: NetIP.Adr; VAR res: INTEGER);
VAR
	buf: ARRAY 512 OF CHAR;
	name: ARRAY 64 OF CHAR;
	i, j: INTEGER;
	len, timeout: LONGINT;
	c: Cache;
BEGIN
	i := 0;  WHILE (hostname[i] # 0X) & (i # 10) DO name[i] := CAP(hostname[i]);  INC(i) END;
	name[4] := ".";  name[i] := 0X;
	IF name = "TEMP.QUERY" THEN
		Kernel.WriteString("DNS ignored: ");  Kernel.WriteString(hostname);  Kernel.WriteLn;
		res := NotDone;
		RETURN
	END;
	i := 0;
	NetBase.Copy(NetIP.IPany, adr, NetIP.AdrLen);
	REPEAT COPY(hostname, name);
		Domain(name, dom[i], FALSE); Cap(name); j := 0;
		IF Trace THEN Kernel.WriteString(name);  Kernel.WriteChar(" ") END;
		c := CacheFindName(name);
		IF c # NIL THEN
			NetBase.Copy(c.adr, adr, NetIP.AdrLen);  res := Done
		ELSE
			REPEAT ReceiveInfo(server[dns MOD nofdns].adr, name, A, buf, len);
				IF len > 0 THEN RetrieveAdr(buf, adr, timeout) END;
				IF NetBase.Equal(NetIP.IPany, adr, NetIP.AdrLen) THEN res := NotDone ELSE res := Done END;
				IF res = NotDone THEN
					dns := (dns + 1) MOD nofdns;
					Kernel.WriteString("NetDNS: Switching to DNS");  Kernel.WriteInt(dns, 1);  Kernel.WriteLn
				END; INC(j);
				IF Trace & (res # Done) THEN Kernel.WriteString("retry ") END;
				IF id + 1 = MAX(INTEGER) THEN id := MIN(INTEGER) ELSE INC(id) END
			UNTIL (res = Done) OR (j >= nofdns);
			IF res = Done THEN CacheAdd(name, adr, timeout) END;
			INC(i)
		END;
		IF Trace THEN Kernel.WriteLn END
	UNTIL (res = Done) OR (i = MaxDom)
END HostByName;

PROCEDURE HostByNumber* (adr: NetIP.Adr; VAR hostname: ARRAY OF CHAR; VAR res: INTEGER);
VAR
	buf: ARRAY 512 OF CHAR;
	name: ARRAY 64 OF CHAR;
	num: ARRAY 4 OF CHAR;
	i, j, k: INTEGER;
	len, n, timeout: LONGINT;
	c: Cache;
	netadr: NetIP.Adr;
BEGIN
	NetBase.Copy(adr, netadr, NetIP.AdrLen);
	i := 0; hostname[0] := 0X; NetBase.NetLToHost(adr); j := 0;
	LOOP n := ORD(SYSTEM.VAL(CHAR, adr[i])); k := 0;
		REPEAT num[k] := CHR(n MOD 10 + 30H);
			n := n DIV 10; INC(k)
		UNTIL n = 0; num[k] := 0X;
		REPEAT DEC(k); name[j] := num[k]; INC(j) UNTIL k = 0;
		INC(i); IF i >= 4 THEN name[j] := 0X; EXIT END;
		name[j] := "."; INC(j)
	END;
	Domain(name, ArpaDomain, TRUE); j := 0;
	IF Trace THEN Kernel.WriteString(name);  Kernel.WriteChar(" ") END;
	c := CacheFindAdr(netadr);
	IF c # NIL THEN
		COPY(c.name, hostname);  res := Done
	ELSE
		REPEAT ReceiveInfo(server[dns MOD nofdns].adr, name, PTR, buf, len);
			IF len > 0 THEN RetrieveHost(buf, hostname, timeout) END;
			IF hostname[0] = 0X THEN res := NotDone ELSE res := Done END;
			IF res = NotDone THEN dns := (dns + 1) MOD nofdns END; INC(j);
			IF Trace & (res # Done) THEN Kernel.WriteString("retry ") END;
			IF id + 1 = MAX(INTEGER) THEN id := MIN(INTEGER) ELSE INC(id) END
		UNTIL (res = Done) OR (j >= nofdns);
		IF res = Done THEN
			NetBase.HostLToNet(adr);  CacheAdd(hostname, adr, timeout)
		END
	END;
	IF Trace THEN Kernel.WriteLn END
END HostByNumber;

PROCEDURE InstallDom* (name: ARRAY OF CHAR);
BEGIN COPY(name, dom[nofdom]); nofdom := (nofdom + 1) MOD MaxDom
END InstallDom;

PROCEDURE InstallDNS* (name: ARRAY OF CHAR; adr: NetIP.Adr);
BEGIN NEW(server[nofdns]);
	COPY(name, server[nofdns].name); NetBase.Copy(adr, server[nofdns].adr, NetIP.AdrLen);
	nofdns := (nofdns + 1) MOD MaxDns
END InstallDNS;

PROCEDURE Init*;
BEGIN nofdns := 0; dns := 0; nofdom := 0;
	Nreceived := 0; Nsent := 0;
	NEW(cache);  cache.next := NIL;
	lastcleanup := Kernel.GetTimer()
END Init;

BEGIN id := MIN(INTEGER); Init
END NetDNS.
