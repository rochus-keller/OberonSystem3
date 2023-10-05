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

MODULE NetUDP;	(** non-portable *)	(* 16.08.96 mg *)

IMPORT SYSTEM, NetBase, NetPorts, NetIP;

CONST
	Done* = 0; LocalPortInUse* = 3; DescriptorInUse* = 4;
	
CONST
	HdrLen = 8; MaxQSize = 20;
	MaxDataLen* = 1472;	(* currently one full EtherNet frame, could be more with fragmentation *)

TYPE
	Header* = POINTER TO HeaderDesc;

	HeaderDesc* = RECORD
		src*: INTEGER;
		dst*: INTEGER;
		len*: INTEGER;
		chksum*: INTEGER
	END;

	Connection* = POINTER TO ConnectionDesc;

	ConnectionDesc = RECORD (NetPorts.PortDesc)
		rq: NetBase.Queue
	END;

VAR
	Nreceived, Nsent: LONGINT;

(** ChkSum - Compute UDP checksum.  If len is odd, extra 0 byte is appended *)

PROCEDURE ChkSum* (src, dst: NetIP.Adr; udph: Header; len: INTEGER): LONGINT;
TYPE
	Data = POINTER TO DataDesc;
	DataDesc = RECORD data: ARRAY 1500 OF SYSTEM.BYTE END;
VAR
	udpph: RECORD src, dst: NetIP.Adr; proto, len: INTEGER END;
	data: Data;
	chksum: LONGINT;
BEGIN
	(*NetBase.Copy(iph.src, udpph.src, NetIP.AdrLen); NetBase.Copy(iph.dst, udpph.dst, NetIP.AdrLen);*)
	udpph.src := src;  udpph.dst := dst;
	udpph.proto := NetIP.UDP; NetBase.HostToNet(udpph.proto);
	udpph.len := len; NetBase.HostToNet(udpph.len);
	chksum := NetBase.ByteSum(udpph, 12);
	IF len MOD 2 # 0 THEN
		data := SYSTEM.VAL(Data, udph); data.data[len] := 0X; INC(len)
	END;
	chksum := NetBase.CheckSum(udph^, len, chksum);
	IF chksum # 0 THEN RETURN chksum ELSE RETURN 0FFFFH END
END ChkSum;

PROCEDURE *Input (item: NetBase.Item);
VAR
	udph: Header;
	iph: NetIP.IPHeader;
	com: NetPorts.Port;
	chksum: LONGINT;
BEGIN iph := SYSTEM.VAL(NetIP.IPHeader, SYSTEM.ADR(item.data[item.ofs]));
	udph := SYSTEM.VAL(Header, SYSTEM.ADR(item.data[item.ofs + NetIP.HdrLen(iph)]));
	NetBase.NetToHost(udph.len); INC(Nreceived);
	chksum := udph.chksum; udph.chksum := 0;
	IF (udph.chksum = 0) OR (SHORT(ChkSum(iph.src, iph.dst, udph, udph.len)) = chksum) THEN
		NetBase.NetToHost(udph.src); NetBase.NetToHost(udph.dst);
		IF NetPorts.Search(NetIP.routes[0].adr, udph.dst, iph.src, udph.src, FALSE, com) THEN
			IF com IS Connection THEN
				WITH com: Connection DO
					IF com.rq.len < MaxQSize THEN NetBase.PutItem(com.rq, item)
					ELSE NetBase.RecycleItem(item)
					END
				END
			ELSE HALT(99)
			END
		ELSE (* NetIP.IcmpSend(NetIP.ipadr, iph.src, NetIP.unreach, 3, 0, 0, dmy); *)
			NetBase.RecycleItem(item)
		END
	ELSE NetBase.RecycleItem(item)
	END
END Input;

PROCEDURE Open* (VAR C: Connection; lport: INTEGER; radr: NetIP.Adr; rport: INTEGER; VAR res: INTEGER);
BEGIN
	IF NetPorts.Available(NetIP.routes[0].adr, lport, radr, rport) THEN NEW(C); NetBase.Reset(C.rq);
		IF NetPorts.Access(C, NetIP.routes[0].adr, lport, radr, rport, NetPorts.conctless) THEN res := Done
		ELSE res := DescriptorInUse; HALT(98)
		END 
	ELSE res := LocalPortInUse; HALT(99)
	END
END Open;

PROCEDURE Close* (C: Connection);
BEGIN
	NetPorts.Release(C); NetBase.Reset(C.rq)
END Close;

PROCEDURE Available* (C: Connection): LONGINT;
BEGIN
	NetBase.Poll;
	RETURN C.rq.len
END Available;

PROCEDURE Send* (C: Connection; radr: NetIP.Adr; rport: INTEGER; VAR buf: ARRAY OF SYSTEM.BYTE; beg, len: LONGINT);
VAR
	item: NetBase.Item;
	udph: Header;
BEGIN
	ASSERT(len <= MaxDataLen);	(* no fragmentation implemented yet *)
	ASSERT(len <= LEN(buf));	(* not allowed to send more than available *)
	IF len > 0 THEN
		NetBase.NewItem(item);
		DEC(item.ofs, SHORT(len)); INC(item.len, SHORT(len));
		NetBase.FastCopy(SYSTEM.ADR(buf[beg]), SYSTEM.ADR(item.data[item.ofs]), len);

		DEC(item.ofs, HdrLen); INC(item.len, HdrLen);
		udph := SYSTEM.VAL(Header, SYSTEM.ADR(item.data[item.ofs]));
		udph.src := C.lport; NetBase.HostToNet(udph.src);
		udph.dst := rport; NetBase.HostToNet(udph.dst);
		udph.len := SHORT(len) + HdrLen; NetBase.HostToNet(udph.len);

		udph.chksum := 0; udph.chksum := SHORT(ChkSum(C.lip, radr, udph, SHORT(len) + HdrLen));
		INC(Nsent);
		NetIP.IPSend(C.lip, radr, NetIP.UDP, item)
	END
END Send;

PROCEDURE Receive* (C: Connection; VAR radr: NetIP.Adr; VAR rport: INTEGER; VAR buf: ARRAY OF SYSTEM.BYTE;
	beg: LONGINT; VAR len: LONGINT);
VAR
	item: NetBase.Item;
	udph: Header;
	iph: NetIP.IPHeader;
BEGIN
	NetBase.Poll;
	IF C.rq.len > 0 THEN NetBase.GetItem(C.rq, item);
		iph := SYSTEM.VAL(NetIP.IPHeader, SYSTEM.ADR(item.data[item.ofs]));
		udph := SYSTEM.VAL(Header, SYSTEM.ADR(item.data[item.ofs + NetIP.HdrLen(iph)]));
		NetBase.Copy(iph.src, radr, NetIP.AdrLen); rport := udph.src;
		len := udph.len - HdrLen;
		ASSERT(len <= LEN(buf));
		NetBase.FastCopy(SYSTEM.ADR(item.data[item.ofs + NetIP.HdrLen(iph) + HdrLen]), SYSTEM.ADR(buf[beg]), len)
	ELSE len := -1
	END
END Receive;

PROCEDURE Start*;
BEGIN NetIP.InstallDemux(Input, NetIP.UDP);
	Nreceived := 0; Nsent := 0
END Start;

PROCEDURE Stop*;
BEGIN NetIP.RemoveDemux(NetIP.UDP)
END Stop;

BEGIN Nreceived := 0; Nsent := 0
END NetUDP.