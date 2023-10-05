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

MODULE SLIP;	(** non-portable *)	(* 16.08.96 mg/dm *)

IMPORT
	SYSTEM, Oberon, Texts, NetTCP, NetIP, NetBase, V24, Input, Out;

CONST
	(* Header Compression *)
	MAXSlots = 16;													  (* must be > 2 and < 255 *)
	MAXHDR = 128;													(* max TCP + IP header length (by protocol def *)
	TYPEIP = 40H;
	TYPEUNCOMPRESSEDTCP = 70H;
	TYPECOMPRESSEDTCP = 80H;
	NEWU = 0; NEWW = 1; NEWA = 2; NEWS = 3; NEWP = 4;	(* Change-Bit numbers *)
	NEWI = 5; NEWC = 6;
	SPECIALI = {NEWS, NEWW, NEWU};							(* echoed interactive traffic *)
	SPECIALD = {NEWS, NEWA, NEWW, NEWU};				(* unidirectional data *)
	SPECIALMASK = {NEWS, NEWA, NEWW, NEWU};

	(* driver escape sequences *)
	SLIPEND = 0C0X; SLIPESC = 0DBX; SLIPESCEND = 0DCX; SLIPESCESC = 0DDX;

TYPE
	SlotList = POINTER TO SlotListDesc;	(* for LRU list *)
	SlotListDesc = RECORD
		id: SHORTINT;
		prev, next: SlotList
	END;

	SlotDesc = RECORD
		hlen: INTEGER;	(* size of header (receive only) *)
		hdr: ARRAY MAXHDR OF SYSTEM.BYTE
	END;
	
	Device* = POINTER TO DeviceDesc;
	DeviceDesc* = RECORD (NetBase.DeviceDesc)
		compressed*: BOOLEAN;
		port*: INTEGER;
		lastrecv, lastxmit: SHORTINT;
		err: BOOLEAN;
		recvslots, xmitslots: ARRAY MAXSlots OF SlotDesc;
		slist: SlotList
	END;

VAR
	default: Device;
	
PROCEDURE Decode(VAR a: ARRAY OF SYSTEM.BYTE; VAR index: INTEGER; VAR n: LONGINT);
VAR s1, s2: SHORTINT;
BEGIN
	n := 0;
	IF SYSTEM.VAL(SHORTINT,a[index]) = 0 THEN
		INC(index);
		s1 := SYSTEM.VAL(SHORTINT,a[index]); INC(index);
		s2 := SYSTEM.VAL(SHORTINT,a[index]); INC(index);
		n := SYSTEM.VAL(LONGINT,SYSTEM.LSH(SYSTEM.VAL(SET,s1) * {0..7},8))
				+ SYSTEM.VAL(LONGINT,SYSTEM.VAL(SET,s2) * {0..7});
	ELSE
		s1 := SYSTEM.VAL(SHORTINT,a[index]); INC(index);
		n := SYSTEM.VAL(LONGINT,SYSTEM.VAL(SET,s1) * {0..7});
	END
END Decode;

PROCEDURE SLDecompress(dev: Device; VAR item: NetBase.Item);
VAR
	iph, csiph: NetIP.IPHeader;
	tcph, cstcph: NetTCP.Header;
	iphlen, tcphlen, index, temp1, temp2, tothlen: INTEGER;
	templ1, templ2: LONGINT;
	type, ind, temps1, temps2, code: SHORTINT;
	changes, specialchanges: SET;
	new: NetBase.Item;
BEGIN
	ASSERT(item.ofs = 0);
	iph := SYSTEM.VAL(NetIP.IPHeader, SYSTEM.ADR(item.data[0]));
	type := iph.verlen;
	IF type = 0 THEN dev.err := TRUE; RETURN END;	(* packet error, ignore everything until next packet with C-Bit set *)
	type := SYSTEM.VAL(SHORTINT,SYSTEM.VAL(SET,type) * {4..7});
	IF SYSTEM.LSH(type, -4) = 4 THEN RETURN 	(* TYPE IP nothing to do*)
	ELSIF SYSTEM.VAL(SET,type) * {7} = {7} THEN			(* TYPE COMPRESSED TCP *)
		IF item.len < 3 THEN RETURN END;						(* no compressed packet is shorter than 3 Bytes *)
		(* read change byte *)
		changes := SYSTEM.VAL(SET,item.data[0]); index := 1;
		ind := dev.lastrecv;
		IF NEWC IN changes THEN
			(* read slot index, check if index is in range. if we have a good slot index clear the 'discard flag' *)
			ind := SYSTEM.VAL(SHORTINT,item.data[index]); INC(index);
			IF (ind < 0) OR (ind > MAXSlots - 1) THEN
				dev.err := TRUE; RETURN
			END;
			dev.err  := FALSE; dev.lastrecv := ind
		ELSE
			(* this packet has an implicit slot index. If we've had a line error since the last time and we got an implicit
				slot index, we have to ignore the packet *)
			IF dev.err THEN RETURN END
		END;
		(* fill in TCP Chksum an PUSH Bit *)
		csiph := SYSTEM.VAL(NetIP.IPHeader, SYSTEM.ADR(dev.recvslots[ind].hdr));
		cstcph := SYSTEM.VAL(NetTCP.Header, SYSTEM.ADR(dev.recvslots[ind].hdr[NetIP.HdrLen(csiph)]));
		temps1 := SYSTEM.VAL(SHORTINT,item.data[index]); INC(index);
		temps2 := SYSTEM.VAL(SHORTINT,item.data[index]); INC(index);
		temp1 :=  SYSTEM.VAL(INTEGER,SYSTEM.LSH(SYSTEM.VAL(SET,temps1) * {0..7},8))
						+ SYSTEM.VAL(INTEGER,SYSTEM.VAL(SET,temps2) * {0..7});
		NetBase.HostToNet(temp1); cstcph.chksum := temp1;
		code := cstcph.code;
		IF NEWP IN changes THEN INCL(SYSTEM.VAL(SET,code), NetTCP.Psh)
		ELSE EXCL(SYSTEM.VAL(SET,code), NetTCP.Psh)
		END;
		cstcph.code := code;
		(* Fix the slot's ack, seq, urg and win fileds based on the changemask *)
		specialchanges := changes * SPECIALMASK;
		IF specialchanges = SPECIALI THEN		(* echoed terminal traffic *)
			temp1 := csiph.len; NetBase.NetToHost(temp1); DEC(temp1,dev.recvslots[ind].hlen);
			NetBase.NetLToHost(cstcph.ack); INC(cstcph.ack,LONG(temp1)); NetBase.HostLToNet(cstcph.ack);
			NetBase.NetLToHost(cstcph.seq); INC(cstcph.seq,LONG(temp1)); NetBase.HostLToNet(cstcph.seq);
		ELSIF specialchanges = SPECIALD THEN	(* unidirectional data *)
			temp1 := csiph.len; NetBase.NetToHost(temp1); DEC(temp1,dev.recvslots[ind].hlen);
			NetBase.NetLToHost(cstcph.seq); INC(cstcph.seq,LONG(temp1)); NetBase.HostLToNet(cstcph.seq);
		ELSE
			code := cstcph.code;
			IF NEWU IN changes THEN
				INCL(SYSTEM.VAL(SET,code), NetTCP.Urg); Decode(item.data,index,templ1);
				temp1 := SHORT(templ1); NetBase.HostToNet(temp1); cstcph.up := temp1;
			ELSE EXCL(SYSTEM.VAL(SET,code), NetTCP.Urg)
			END;
			cstcph.code := code; 
			IF NEWW IN changes THEN
				Decode(item.data ,index ,templ1); temp2 := cstcph.win; NetBase.NetToHost(temp2);
				INC(templ1,LONG(temp2)); temp1 := SHORT(templ1); NetBase.HostToNet(temp1); cstcph.win := temp1
			END;
			IF NEWA IN changes THEN
				Decode(item.data,index,templ1); templ2 := cstcph.ack; NetBase.NetLToHost(templ2);
				INC(templ2, templ1); NetBase.HostLToNet(templ2); cstcph.ack := templ2
			END;
			IF NEWS IN changes THEN
				Decode(item.data,index,templ1); templ2 := cstcph.seq; NetBase.NetLToHost(templ2);
				INC(templ2,templ1); NetBase.HostLToNet(templ2); cstcph.seq := templ2
			END
		END;
		(* Update the IP ID *)
		IF NEWI IN changes THEN
			Decode(item.data,index,templ1); temp2 := csiph.id; NetBase.NetToHost(temp2);
			INC(templ1,LONG(temp2)); temp1 := SHORT(templ1); NetBase.HostToNet(temp1); csiph.id := temp1
		ELSE NetBase.NetToHost(csiph.id); INC(csiph.id); NetBase.HostToNet(csiph.id)
		END;
		temp1 := item.len - index; tothlen := dev.recvslots[ind].hlen;
		csiph.len := tothlen + temp1; NetBase.HostToNet(csiph.len);
		IF temp1 < 0 THEN dev.err := TRUE; RETURN END;
		NetBase.NewItem(new); NetBase.Copy(dev.recvslots[ind].hdr,new.data[0],tothlen); 
		NetBase.Copy(item.data[index],new.data[tothlen],temp1);
		NetBase.RecycleItem(item);
		new.len := tothlen + temp1; item := new;
		(* redevute IP Header Chksum *)
		iph := SYSTEM.VAL(NetIP.IPHeader, SYSTEM.ADR(item.data[0])); 
		iph.checksum := 0; iph.checksum := SHORT(NetBase.CheckSum(iph^, NetIP.HdrLen(iph), 0));

	ELSE 													(* TYPE UNCOMPRESSED TCP *)
		item.data[0] := SYSTEM.VAL(SYSTEM.BYTE,SYSTEM.VAL(SET,item.data[0]) * {0..3,6..7});
		(* locate the saved header fo this connection
			if the slot index is legal, clear the 'discard' flag *)
		iphlen := NetIP.HdrLen(iph); tcph := SYSTEM.VAL(NetTCP.Header,SYSTEM.ADR(item.data[iphlen]));
		tcphlen := SYSTEM.LSH(tcph.offs,-4);
		ind := iph.protocol;
		IF (item.len < NetIP.MinHdrLen) OR (iphlen < NetIP.MinHdrLen) OR ((ind < 0) OR (ind > MAXSlots - 1)) THEN 
			dev.err := TRUE; RETURN
		END;
		iph.protocol := NetIP.TCP; dev.lastrecv := ind;
		temp1 := iph.checksum; iph.checksum := 0;
		IF SHORT(NetBase.CheckSum(iph^,iphlen,0)) = temp1 THEN
			iph.checksum := temp1;
			dev.err := FALSE; dev.recvslots[ind].hlen := iphlen + (tcphlen * 4);
			NetBase.Copy(item.data[0], dev.recvslots[ind].hdr, iphlen + (tcphlen * 4));
			csiph := SYSTEM.VAL(NetIP.IPHeader, SYSTEM.ADR(dev.recvslots[ind].hdr));
		ELSE dev.err := TRUE;
		END
	END
END SLDecompress;

PROCEDURE Receive (dev: NetBase.Device; VAR prno: INTEGER; VAR src: ARRAY OF SYSTEM.BYTE; VAR item: NetBase.Item);
VAR
	ch: CHAR;
	t, res, len: LONGINT;
BEGIN
	(* assume ofs = 0 *)
	WITH dev: Device DO
		REPEAT len := 0;
			t := Input.Time() + 2*Input.TimeUnit;	(* 2s *)
			LOOP
				IF V24.Available(dev.port) > 0 THEN
					V24.Receive(dev.port, ch, res);
					IF (ch = SLIPEND) OR (len >= NetBase.MaxDataLen) THEN 
						EXIT
					END;
					IF ch = SLIPESC THEN V24.Receive(dev.port,ch,res);	(* block! *)
						IF ch = SLIPESCEND THEN ch := SLIPEND
						ELSIF ch = SLIPESCESC THEN ch := SLIPESC
						ELSE ch := 0X	(* must be line noise *)
						END
					END;
					item.data[len] := ch; INC(len)
				ELSIF Input.Time() - t > 0 THEN EXIT
				ELSE (* skip *)
				END
			END
		UNTIL len > 0;
		item.len := SHORT(len);
		IF len >= NetBase.MaxDataLen THEN item.data[0] := 0X END;	  (* set error "flag" *)
		IF dev.compressed THEN SLDecompress(dev, item) END;
		prno := 0800H
	END
END Receive;

PROCEDURE TestEqual(iph: NetIP.IPHeader; tcph: NetTCP.Header; VAR cs: SlotDesc): BOOLEAN;
VAR
	csiph: NetIP.IPHeader;
	cstcph: NetTCP.Header;
BEGIN
	csiph := SYSTEM.VAL(NetIP.IPHeader,SYSTEM.ADR(cs.hdr));
	cstcph := SYSTEM.VAL(NetTCP.Header,SYSTEM.ADR(cs.hdr[NetIP.HdrLen(csiph)]));
	RETURN (NetBase.Equal(iph.src, csiph.src, NetIP.AdrLen) & NetBase.Equal(iph.dst, csiph.dst, NetIP.AdrLen) &
					NetBase.Equal(tcph.src, cstcph.src, 2) & NetBase.Equal(tcph.dst, cstcph.dst, 2))
END TestEqual;

PROCEDURE GetSlot(root: SlotList; id: SHORTINT): SlotList;
VAR s: SlotList;
BEGIN s := root.next;
	WHILE (s # root) & (s.id # id) DO s := s.next END;
	IF s # root THEN
		s.prev.next := s.next; s.next.prev := s.prev;
		RETURN s
	END
	(* we should never come here *)
END GetSlot;

PROCEDURE PutSlot(root, s: SlotList);
BEGIN
	s.next := root; root.prev.next := s;
	s.prev := root.prev; root.prev := s;
END PutSlot;

PROCEDURE GetLRUSlot(root: SlotList): SHORTINT;
VAR s: SlotList;
BEGIN s := root.next;
	root.next := s.next; s.next.prev := root; PutSlot(root,s); RETURN s.id
END GetLRUSlot;

PROCEDURE SendUncompressed (dev: Device; id: SHORTINT; VAR item: NetBase.Item);
	(* update connection slot cs & send uncompressed packet *)
VAR
	iph: NetIP.IPHeader;
	tcph: NetTCP.Header;
	iphlen, tcphlen: INTEGER;
BEGIN
	iph := SYSTEM.VAL(NetIP.IPHeader, SYSTEM.ADR(item.data[item.ofs])); iphlen := NetIP.HdrLen(iph);
	tcph := SYSTEM.VAL(NetTCP.Header,SYSTEM.ADR(item.data[item.ofs+iphlen]));
	tcphlen := SYSTEM.LSH(tcph.offs,-4);
	NetBase.Copy(item.data[item.ofs],dev.xmitslots[id].hdr,iphlen + (tcphlen * 4));
	dev.lastxmit := id; iph.protocol := id;
	PutSlot(dev.slist, GetSlot(dev.slist,id));
END SendUncompressed;

PROCEDURE Encode (VAR a: ARRAY OF SYSTEM.BYTE; VAR index: INTEGER; n: LONGINT);
BEGIN
	n := SYSTEM.VAL(LONGINT,SYSTEM.VAL(SET,n) * {0..15});
	IF (n >= 256) OR (n = 0) THEN
		a[index] := 0; INC(index);
		a[index] := SYSTEM.VAL(SYSTEM.BYTE,SYSTEM.LSH(n,-8)); INC(index);
		a[index] := SYSTEM.VAL(SYSTEM.BYTE,n); INC(index);
	ELSE
		a[index] := SYSTEM.VAL(SYSTEM.BYTE,n); INC(index);
	END
 END Encode;

PROCEDURE SLCompress(dev: Device; VAR item: NetBase.Item): INTEGER;
TYPE
	Data = POINTER TO ARRAY MAX(INTEGER) OF CHAR;
VAR
	iph, csiph: NetIP.IPHeader;
	tcph, cstcph: NetTCP.Header;
	frag, csfrag, iphlen, tcphlen, tothlen, index, newindex, newindex0, temp1, temp2: INTEGER;
	deltaS, deltaA, templ1, templ2: LONGINT;
	ind: SHORTINT;
	newseq: ARRAY 16 OF SYSTEM.BYTE; changes: SET;
	new: NetBase.Item;
	d1, d2: Data;
BEGIN (* test if TCP packet is compressible -> it's not a fragment and ACK = 1 and the others are 0 *)
	iph := SYSTEM.VAL(NetIP.IPHeader, SYSTEM.ADR(item.data[item.ofs]));
	frag := iph.frag;  NetBase.NetToHost(frag);
	IF (SYSTEM.VAL(SET,frag) * {0..13} # {}) OR (item.len < 40) THEN RETURN(TYPEIP) END;
	iphlen := NetIP.HdrLen(iph); tcph := SYSTEM.VAL(NetTCP.Header,SYSTEM.ADR(item.data[item.ofs+iphlen]));
	tcphlen := SYSTEM.LSH(tcph.offs,-4);
	IF SYSTEM.VAL(SET,tcph.code) * {NetTCP.Syn, NetTCP.Fin, NetTCP.Rst, NetTCP.Ack} # {NetTCP.Ack} THEN RETURN(TYPEIP) END;
	(* packet is compressible *)
	ind := dev.lastxmit;
	LOOP
		IF TestEqual(iph, tcph, dev.xmitslots[ind]) THEN EXIT END;
		ind := (ind + 1) MOD MAXSlots;
		IF ind = dev.lastxmit THEN
			SendUncompressed(dev, GetLRUSlot(dev.slist), item); 
			RETURN(TYPEUNCOMPRESSEDTCP)
		END
	END;
	(* Make sure that only what we expect to change changed.
		Check the following:
			- IP protocol version, header length & type of service
			- "Don't fragment" bit
			- the time-to-live field
			- TCP header length
			- IP Options, if any
			- TCP Options, if any
		if any of these things are different between the previous & current datagram, send it uncompressed *)
	csiph := SYSTEM.VAL(NetIP.IPHeader,SYSTEM.ADR(dev.xmitslots[ind].hdr));
	cstcph := SYSTEM.VAL(NetTCP.Header,SYSTEM.ADR(dev.xmitslots[ind].hdr[NetIP.HdrLen(csiph)]));
	csfrag := csiph.frag; NetBase.NetToHost(csfrag);
	d1 := SYSTEM.VAL(Data, SYSTEM.ADR(iph.verlen) + SIZE(NetIP.IPHeaderDesc));
	d2 := SYSTEM.VAL(Data, SYSTEM.ADR(csiph.verlen) + SIZE(NetIP.IPHeaderDesc));
	IF (iph.verlen # csiph.verlen) OR (iph.tos # csiph.tos) OR
		((SYSTEM.VAL(SET,frag) * {14}) # (SYSTEM.VAL(SET,csfrag) * {14})) OR
		(iph.ttl # csiph.ttl) OR (tcphlen # SYSTEM.LSH(cstcph.offs,-4)) OR
		((iphlen DIV 4 > 5) & ~NetBase.Equal(d1^, d2^, (iphlen DIV 4 - 5) * 4)) OR
		((tcphlen > 5) & ~NetBase.Equal(tcph.data, cstcph.data, (tcphlen - 5) * 4)) THEN
			SendUncompressed(dev, ind, item); RETURN(TYPEUNCOMPRESSEDTCP)
	END;
	changes := {}; index := 0;
	(* Figure out which of the changing fields changed. The receiver expects changes in the order:
		urgent, window, ack, seq *)
	IF SYSTEM.VAL(SET,tcph.code) * {NetTCP.Urg} # {} THEN			(* URG *)
		temp1 := tcph.up; NetBase.NetToHost(temp1); Encode(newseq, index, temp1); INCL(changes,NEWU)
	ELSIF tcph.up # cstcph.up THEN								(* URG not set but urp changed RFC 793 doesn't prohibit this error *)
		SendUncompressed(dev, ind, item); RETURN(TYPEUNCOMPRESSEDTCP)
	END;

	temp1 := tcph.win; temp2 := cstcph.win; NetBase.NetToHost(temp1); NetBase.NetToHost(temp2); deltaS := temp1 - temp2;
	IF deltaS # 0 THEN Encode(newseq, index, deltaS); INCL(changes,NEWW) END;

	templ1 := tcph.ack; templ2 := cstcph.ack; NetBase.NetLToHost(templ1); NetBase.NetLToHost(templ2); deltaA := templ1 - templ2;
	IF deltaA # 0 THEN
		IF (deltaA < 0) OR (deltaA > 0FFFFH) THEN SendUncompressed(dev, ind, item); RETURN(TYPEUNCOMPRESSEDTCP) END;
		Encode(newseq, index, deltaA); INCL(changes,NEWA)
	END;

	templ1 := tcph.seq; templ2 := cstcph.seq; NetBase.NetLToHost(templ1); NetBase.NetLToHost(templ2); deltaS := templ1 - templ2;
	IF deltaS # 0 THEN
		IF (deltaS < 0) OR (deltaS > 0FFFFH) THEN SendUncompressed(dev, ind, item); RETURN(TYPEUNCOMPRESSEDTCP) END;
		Encode(newseq, index, deltaS); INCL(changes,NEWS)
	END;
	(* look for the special cases *)
	IF changes = {} THEN
		temp1 := csiph.len; NetBase.NetToHost(temp1);
		IF (iph.len # csiph.len) & (templ1 = iphlen + (tcphlen * 4)) THEN
		ELSE SendUncompressed(dev, ind, item); RETURN(TYPEUNCOMPRESSEDTCP)
		END
	ELSIF (changes = SPECIALI) OR (changes = SPECIALD) THEN	(* actual change match one of out special cases *)
		SendUncompressed(dev, ind, item); RETURN(TYPEUNCOMPRESSEDTCP)
	ELSIF changes = {NEWS, NEWA} THEN
		temp1 := iph.len; NetBase.NetToHost(temp1);
		IF (deltaS = deltaA) & (deltaS = temp1 - iphlen + (tcphlen * 4)) THEN (* special case for echoed terminal traffic *)
			changes := SPECIALI; index := 0
		END
	ELSIF changes = {NEWS} THEN
		temp1 := iph.len; NetBase.NetToHost(temp1);
		IF deltaS = temp1 - iphlen + (tcphlen * 4) THEN (* special case for data xfer *)
			changes := SPECIALD; index := 0
		END
	END;

	temp1 := iph.id; temp2 := csiph.id; NetBase.NetToHost(temp1); NetBase.NetToHost(temp2); deltaS := temp1 - temp2;
	IF deltaS # 1 THEN Encode(newseq, index, deltaS); INCL(changes, NEWI) END;

	IF SYSTEM.VAL(SET,tcph.code) * {NetTCP.Psh} # {} THEN INCL(changes, NEWP) END;

	(* update the slot with this packet's headers *)
	temp1 := tcph.chksum; NetBase.NetToHost(temp1); tothlen := iphlen + (tcphlen * 4);
	NetBase.Copy(item.data[item.ofs], dev.xmitslots[ind].hdr, tothlen);
	NetBase.NewItem(new); 
	DEC(new.ofs, 4 + index + item.len - tothlen);	(* enough space for all *)
	newindex := new.ofs;  newindex0 := newindex;
	IF (dev.lastxmit # ind) THEN
		dev.lastxmit := ind; INCL(changes, NEWC);
		new.data[newindex] := SYSTEM.VAL(SYSTEM.BYTE,changes); INC(newindex);
		new.data[newindex] := ind; INC(newindex)
	ELSE
		new.data[newindex] := SYSTEM.VAL(SYSTEM.BYTE,changes); INC(newindex)
	END;
	new.data[newindex] := SHORT(SYSTEM.LSH(temp1,-8)); INC(newindex);		(* Write TCP Checksum *)
	new.data[newindex] := SHORT(temp1); INC(newindex);
	NetBase.Copy(newseq[0],new.data[newindex],index); INC(newindex,index);
	NetBase.Copy(item.data[tothlen], new.data[newindex], item.len - tothlen);
	NetBase.RecycleItem(item);
	new.len := newindex-newindex0; item := new;
	RETURN(TYPECOMPRESSEDTCP)
END SLCompress;

PROCEDURE Send (dev: NetBase.Device; prno: INTEGER; VAR dest: ARRAY OF SYSTEM.BYTE; item: NetBase.Item);
VAR
	iph: NetIP.IPHeader;
	ch: CHAR;
	type, i: INTEGER;
	res: LONGINT;
BEGIN
	WITH dev: Device DO
		(* compress TCP header *)
		iph := SYSTEM.VAL(NetIP.IPHeader, SYSTEM.ADR(item.data[item.ofs]));
		IF dev.compressed & (iph.protocol = NetIP.TCP) THEN type := SLCompress(dev, item);
			item.data[item.ofs] := SYSTEM.VAL(SYSTEM.BYTE,SYSTEM.VAL(SET, item.data[item.ofs]) + SYSTEM.VAL(SET, type));
		END;
		(* send item to V24 *)
		V24.Send(dev.port,SLIPEND,res); i := 0;
		WHILE i < item.len DO ch := CHR(item.data[item.ofs+i]);
			IF ch = SLIPEND THEN V24.Send(dev.port,SLIPESC,res); V24.Send(dev.port,SLIPESCEND,res)
			ELSIF ch = SLIPESC THEN V24.Send(dev.port,SLIPESC,res); V24.Send(dev.port,SLIPESCESC,res)
			ELSE V24.Send(dev.port,ch,res)
			END;
			INC(i)
		END;
		V24.Send(dev.port, SLIPEND, res)
	END
END Send;

PROCEDURE Available (dev: NetBase.Device): BOOLEAN;
BEGIN RETURN V24.Available(dev(Device).port) > 0
END Available;

PROCEDURE InitCompress (dev: Device);
VAR
	s: SlotList;
	i, j: INTEGER;
BEGIN dev.err := TRUE;	(* ignore everything until we get an explicit connection id *)
	NEW(dev.slist); dev.slist.next := dev.slist;
	dev.slist.prev := dev.slist; i := 0;
	WHILE i < MAXSlots DO j := 0;
		WHILE j < MAXHDR DO dev.xmitslots[i].hdr[j] := 0X;
			dev.recvslots[i].hdr[j] := 0X; INC(j)
		END;
		NEW(s); s.id := SHORT(i); PutSlot(dev.slist,s);
		INC(i)
	END;
	dev.lastxmit := 0; dev.lastrecv := 0
END InitCompress;

PROCEDURE Install (port: INTEGER; compressed: BOOLEAN);
VAR dev: Device;
BEGIN NEW(dev);
	dev.compressed := compressed; InitCompress(dev); dev.port := port; dev.typ := NetBase.nobroadcast; 
	dev.Send := Send; dev.Receive := Receive; dev.Available := Available;
	NetBase.InstallDevice(dev);
	dev.state := NetBase.pending;
	Out.String("SLIP device installed on COM"); Out.Int(port+1, 1);
	IF compressed THEN Out.String(" (compressed)") END;
	Out.Ln;
	default := dev
END Install;

PROCEDURE InstallDevice*;
VAR
	S: Texts.Scanner;
	port: INTEGER;
	compressed: BOOLEAN;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
	IF S.class = Texts.Name THEN
		IF S.s[0] # "C" THEN Texts.Scan(S) END;	(* old config with device name? *)
		IF S.class = Texts.Name THEN
			IF S.s = "COM4" THEN port := V24.COM4
			ELSIF S.s = "COM3" THEN port := V24.COM3
			ELSIF S.s = "COM2" THEN port := V24.COM2
			ELSE port := V24.COM1
			END;
			Texts.Scan(S); compressed := (S.class = Texts.Name) & (S.s = "compressed");
			Install(port, compressed)
		ELSE HALT(98)
		END
	ELSE HALT(99)
	END
END InstallDevice;

PROCEDURE StartDevice*;	(* called from dial script *)
BEGIN
	IF (default # NIL) & (default.state = NetBase.pending) THEN
		default.state := NetBase.open;
		Out.String("SLIP device enabled");  Out.Ln
	END
END StartDevice;

END SLIP.