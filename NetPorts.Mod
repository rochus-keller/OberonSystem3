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

MODULE NetPorts;	(** non-portable *)	(* 16.08.96 mg *)

IMPORT NetBase, NetIP;

CONST
	anyport* = 0; minport = 1023; maxport = 2000;

	passive* = 0; active* = 1; conctless* = 3;
		
TYPE
	Port* = POINTER TO PortDesc;
	
	PortDesc* = RECORD
		lport*, rport*: INTEGER;
		lip*, rip*: NetIP.Adr;
		mode: SHORTINT;
		next: Port
	END;

	EntryHandler = PROCEDURE (port: Port);

VAR
	ports: Port;
	portnr: INTEGER;

PROCEDURE Available* (lip: NetIP.Adr; VAR lport: INTEGER; rip: NetIP.Adr; rport: INTEGER): BOOLEAN;
VAR
	curr: Port;
	oldnr: INTEGER;
BEGIN
	IF lport = 0 THEN oldnr := portnr;
		REPEAT
			IF portnr = maxport THEN portnr := minport ELSE INC(portnr) END;
			curr := ports.next;
			WHILE (curr # ports) & (curr.lport # portnr) DO curr := curr.next END
		UNTIL (curr = ports) OR (portnr = oldnr);
		lport := portnr
	ELSE oldnr := 0;
		curr := ports.next;
		LOOP
			IF curr = ports THEN EXIT END;
			IF NetBase.Equal(curr.rip, rip, NetIP.AdrLen) & (curr.lport = lport) & (curr.rport = rport) THEN
				EXIT
			END;
			curr := curr.next
		END
	END;
	RETURN (curr = ports) & ~(portnr = oldnr)
END Available;

PROCEDURE Access* (port: Port; lip: NetIP.Adr; loc: INTEGER; rip: NetIP.Adr; rmt: INTEGER; mode: SHORTINT): BOOLEAN;
BEGIN port.mode := mode;
	port.lport := loc; port.rport := rmt;
	NetBase.Copy(lip, port.lip, NetIP.AdrLen); NetBase.Copy(rip, port.rip, NetIP.AdrLen);
	port.next := ports.next; ports.next := port;
	RETURN TRUE
END Access;

PROCEDURE Search* (lip: NetIP.Adr; loc: INTEGER; rip: NetIP.Adr; rmt: INTEGER; startup: BOOLEAN; VAR port: Port): BOOLEAN;
VAR
	nport: Port;
BEGIN
	nport := NIL; port := ports.next;
	LOOP
		IF port = ports THEN EXIT END;
		IF port.lport = loc THEN
			IF NetBase.Equal(port.rip, rip, NetIP.AdrLen) & (port.rport = rmt) THEN EXIT END;
			IF (port.mode = passive) OR (port.mode = conctless) THEN
				IF NetBase.Equal(port.rip, NetIP.IPany, NetIP.AdrLen) THEN
					IF (port.rport = rmt) OR (port.rport = anyport) THEN nport := port END
				ELSIF NetBase.Equal(port.rip, rip, NetIP.AdrLen) THEN
					IF port.rport = anyport THEN nport := port END
				END
			END
		END;
		port := port.next
	END;
	IF port = ports THEN
		IF startup OR (nport # NIL) & (nport.mode = conctless) THEN port := nport ELSE port := NIL END
	END; 
	RETURN port # NIL
END Search;

PROCEDURE Release* (port: Port);
VAR
	prev, curr: Port;
BEGIN prev := ports; curr := ports.next;
	WHILE (curr # ports) & (curr # port) DO
		prev := curr; curr := curr.next
	END;
	IF curr # ports THEN prev.next := curr.next END
END Release;

PROCEDURE Enumerate* (proc: EntryHandler);
VAR curr: Port;
BEGIN
	curr := ports.next;
	WHILE curr # ports DO proc(curr); curr := curr.next END
END Enumerate;

PROCEDURE Init*;
BEGIN ports.next := ports; portnr := minport
END Init;

BEGIN NEW(ports);
	ports.next := ports; portnr := minport
END NetPorts.