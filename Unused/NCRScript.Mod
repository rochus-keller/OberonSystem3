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

(* ConvertNCRScript.Do *)

MODULE NCRScript;	(** non-portable *)	(* Contributed by P. Ryser to the System 3 project *)

	IMPORT SYSTEM;
	
	CONST
		dsaSelect* = 0; dsaMsgOut* = 1; dsaCmd* = 2;
		dsaStatus* = 3; dsaData* = 4; dsaMsgIn* = 5;
		dsaTableSize = 6;

		AIntErrUnexpectedPhase* = 000000000H;
		AIntErrSelectFailed* = 000000040H;
		AIntHandleMsgIn* = 000000021H;
		AIntNormCommandComplete* = 000000022H;
		AIntNormDisc* = 000000023H;
		AIntGotSIGP* = 000000024H;
		AIntReselected* = 000000025H;
		AIntMsgOutPhase* = 000000030H;
		AIntCmdPhase* = 000000031H;
		AIntDataInPhase* = 000000032H;
		AIntDataOutPhase* = 000000033H;
		AIntStatusPhase* = 000000034H;
		AIntMsgInPhase* = 000000035H;
		EntCommandComplete*   = 0000000B8H;
		EntCompleteMsgInPhase* = 000000100H;
		EntDisconnected*      = 0000000E0H;
		EntRejectMsg*         = 000000150H;
		EntResumeDataInPhase* = 000000058H;
		EntResumeCmdPhase*    = 000000038H;
		EntResumeDataOutPhase* = 000000078H;
		EntResumeMsgInPhase*  = 0000000A8H;
		EntResumeMsgOutPhase* = 000000020H;
		EntResumeStatusPhase* = 000000090H;
		EntSelection*         = 000000000H;
		EntToDecisions*       = 000000108H;
		EntWaitReselect*      = 000000138H;

	TYPE
		TableEntry* = RECORD
			count*, address*: LONGINT
		END;
		BufferTable* = ARRAY dsaTableSize OF TableEntry;
		
	VAR
		ScriptsAddress*: LONGINT;
		Script*: ARRAY  2*67H + 3 OF LONGINT;


	PROCEDURE CheckAlign;
	VAR adr: LONGINT;
	BEGIN
		adr := SYSTEM.ADR(Script[0]);
		ASSERT((adr DIV 4) * 4 = adr, 100)
	END CheckAlign;

	PROCEDURE Init;
	BEGIN
		Script[0] := 060000200H;	Script[1] := 000000000H;
		Script[2] := 047000000H;	Script[3] := 000000168H;
		Script[4] := 086830000H;	Script[5] := 0000000F0H;
		Script[6] := 080000000H;	Script[7] := 000000000H;	(*		Script[b] := 098080000H;	Script[b] := 000000030H; *)
		Script[8] := 01E000000H;	Script[9] := 000000008H;
		Script[10] := 082830000H;	Script[11] := 0000000D8H;
		Script[12] := 080000000H;	Script[13] := 000000000H;	(*		Script[b] := 098080000H;	Script[b] := 000000031H;  *)
		Script[14] := 060000008H;	Script[15] := 000000000H;
		Script[16] := 01A000000H;	Script[17] := 000000010H;
		Script[18] := 081830000H;	Script[19] := 0000000B8H;
		Script[20] := 080000000H;	Script[21] := 000000000H;	(*		Script[b] := 098080000H;	Script[b] := 000000032H;	*)
		Script[22] := 019000000H;	Script[23] := 000000020H;
		Script[24] := 0838B0000H;	Script[25] := 000000020H;
		Script[26] := 080880000H;	Script[27] := 000000098H;
		Script[28] := 080000000H;	Script[29] := 000000000H;	(*		Script[b] := 098080000H;	Script[b] := 000000033H;	*)
		Script[30] := 018000000H;	Script[31] := 000000020H;
		Script[32] := 083830000H;	Script[33] := 000000080H;
		Script[34] := 080000000H;	Script[35] := 000000000H;	(*		Script[b] := 098080000H;	Script[b] := 000000034H;	*)
		Script[36] := 01B000000H;	Script[37] := 000000018H;
		Script[38] := 087830000H;	Script[39] := 000000068H;
		Script[40] := 080000000H;	Script[41] := 000000000H;	(*		Script[b] := 098080000H;	Script[b] := 000000035H;	*)
		Script[42] := 01F000000H;	Script[43] := 000000028H;
		Script[44] := 098080000H;	Script[45] := 000000021H;
		Script[46] := 07C027F00H;	Script[47] := 000000000H;
		Script[48] := 060000040H;	Script[49] := 000000000H;
		Script[50] := 098180000H;	Script[51] := 000000000H;
		Script[52] := 048000000H;	Script[53] := 000000000H;
		Script[54] := 098080000H;	Script[55] := 000000022H;
		Script[56] := 07C027F00H;	Script[57] := 000000000H;
		Script[58] := 060000040H;	Script[59] := 000000000H;
		Script[60] := 048000000H;	Script[61] := 000000000H;
		Script[62] := 098080000H;	Script[63] := 000000023H;
		Script[64] := 060000040H;	Script[65] := 000000000H;
		Script[66] := 0878B0000H;	Script[67] := 0FFFFFF90H;
		Script[68] := 0828A0000H;	Script[69] := 0FFFFFF18H;
		Script[70] := 0818A0000H;	Script[71] := 0FFFFFF30H;
		Script[72] := 0808A0000H;	Script[73] := 0FFFFFF48H;
		Script[74] := 0838A0000H;	Script[75] := 0FFFFFF58H;
		Script[76] := 098080000H;	Script[77] := 000000000H;
		Script[78] := 054000000H;	Script[79] := 000000030H;
		Script[80] := 0720A0000H;	Script[81] := 000000000H;
		Script[82] := 098080000H;	Script[83] := 000000025H;
		Script[84] := 058000008H;	Script[85] := 000000000H;
		Script[86] := 060000040H;	Script[87] := 000000000H;
		Script[88] := 01E000000H;	Script[89] := 000000008H;
		Script[90] := 080880000H;	Script[91] := 0FFFFFF98H;
		Script[92] := 098080000H;	Script[93] := 000000024H;
		Script[94] := 098080000H;	Script[95] := 000000040H;
		ScriptsAddress := SYSTEM.ADR(Script[0]);
		CheckAlign
	END Init;

BEGIN
	Init
END NCRScript.




(* old Version: without disconnect/reconnect: WORKS!!!! 
MODULE NCRScript;

	CONST
		ETestDestUsed* = 0000000ACH;
		ETestSrcUsed* = 0000000ABH;
		AIntErrUnexpectedPhase* = 000000000H;
		AIntErrCheckCondition* = 000030000H;
		AIntErrSelectFailed* = 000040000H;
		AIntMsgWdtr* = 001000000H;
		AIntMsgSdtr* = 001010000H;
		AIntMsg1* = 001020000H;
		AIntNormCommandComplete* = 002020000H;
		AIntNormDisc* = 002030000H;
		AIntTest1* = 004000000H;
		AIntTest2* = 004010000H;
		AIntTest2NormDisc* = 004020000H;
		EntAcceptMessage* = 000000218H;
		EntCmdoutCmdout* = 000000048H;
		EntCommandComplete* = 000000248H;
		EntCommandCompleteMsgIn* = 000000258H;
		EntMsgIn* = 0000000E0H;
		EntRespondMessage* = 000000228H;
		EntRejectMessage* = 0000001F8H;
		EntSelectMsgOut* = 000000018H;
		EntSelection* = 000000000H;
		EntTest1* = 0000002A8H;
		EntTest2* = 0000002BCH;
		EntTest2MsgOut* = 0000002D4H;

	VAR
		Script*: ARRAY 201 OF LONGINT;


	PROCEDURE Init;
	BEGIN
		Script[ 0] := 060000200H;	Script[ 1] := 000000000H;	Script[ 2] := 047000000H;	Script[ 3] := 000000290H;
		Script[ 4] := 0868B0000H;	Script[ 5] := 000000000H;	Script[ 6] := 01E000000H;	Script[ 7] := 000000008H;
		Script[ 8] := 0828B0000H;	Script[ 9] := 000000018H;	Script[ 10] := 09F030000H;	Script[ 11] := 000000000H;
		Script[ 12] := 08F8B0000H;	Script[ 13] := 0000000A8H;	Script[ 14] := 0878B0000H;	Script[ 15] := 0FFFFFFF0H;
		Script[ 16] := 09A030000H;	Script[ 17] := 000000000H;	Script[ 18] := 01A000000H;	Script[ 19] := 000000018H;
		Script[ 20] := 09A0B0000H;	Script[ 21] := 000000000H;	Script[ 22] := 08F8B0000H;	Script[ 23] := 000000080H;
		Script[ 24] := 09E0B0000H;	Script[ 25] := 000000000H;	Script[ 26] := 0808B0000H;	Script[ 27] := 000000028H;
		Script[ 28] := 0818B0000H;	Script[ 29] := 000000010H;	Script[ 30] := 0838B0000H;	Script[ 31] := 0000001C8H;
		Script[ 32] := 080880000H;	Script[ 33] := 0FFFFFFC8H;	Script[ 34] := 019000000H;	Script[ 35] := 000000028H;
		Script[ 36] := 080880000H;	Script[ 37] := 000000010H;	Script[ 38] := 018000000H;	Script[ 39] := 000000028H;
		Script[ 40] := 080880000H;	Script[ 41] := 000000000H;	Script[ 42] := 09A0B0000H;	Script[ 43] := 000000000H;
		Script[ 44] := 08F8B0000H;	Script[ 45] := 000000028H;	Script[ 46] := 09E0B0000H;	Script[ 47] := 000000000H;
		Script[ 48] := 0980B0000H;	Script[ 49] := 000000000H;	Script[ 50] := 0990B0000H;	Script[ 51] := 000000000H;
		Script[ 52] := 0838B0000H;	Script[ 53] := 000000170H;	Script[ 54] := 080880000H;	Script[ 55] := 0FFFFFFC8H;
		Script[ 56] := 01F000000H;	Script[ 57] := 000000038H;	Script[ 58] := 0808C0001H;	Script[ 59] := 000000070H;
		Script[ 60] := 0808CDF20H;	Script[ 61] := 000000030H;	Script[ 62] := 0808C0002H;	Script[ 63] := 000000118H;
		Script[ 64] := 0808C0003H;	Script[ 65] := 000000110H;	Script[ 66] := 0808C0004H;	Script[ 67] := 000000030H;
		Script[ 68] := 0980C0007H;	Script[ 69] := 001020000H;	Script[ 70] := 0980C000FH;	Script[ 71] := 001020000H;
		Script[ 72] := 080880000H;	Script[ 73] := 0000000D0H;	Script[ 74] := 080880000H;	Script[ 75] := 0000000C8H;
		Script[ 76] := 060000040H;	Script[ 77] := 000000000H;	Script[ 78] := 090080000H;	Script[ 79] := 000000000H;
		Script[ 80] := 07C027F00H;	Script[ 81] := 000000000H;	Script[ 82] := 060000040H;	Script[ 83] := 000000000H;
		Script[ 84] := 048000000H;	Script[ 85] := 000000000H;	Script[ 86] := 098080000H;	Script[ 87] := 002030000H;
		Script[ 88] := 060000040H;	Script[ 89] := 000000000H;	Script[ 90] := 09F030000H;	Script[ 91] := 000000000H;
		Script[ 92] := 01F000000H;	Script[ 93] := 000000040H;	Script[ 94] := 0808C0002H;	Script[ 95] := 000000010H;
		Script[ 96] := 0808C0003H;	Script[ 97] := 000000038H;	Script[ 98] := 080880000H;	Script[ 99] := 000000068H;
		Script[ 100] := 060000040H;	Script[ 101] := 000000000H;	Script[ 102] := 01F000000H;	Script[ 103] := 000000048H;
		Script[ 104] := 080840002H;	Script[ 105] := 000000050H;	Script[ 106] := 060000040H;	Script[ 107] := 000000000H;
		Script[ 108] := 01F000000H;	Script[ 109] := 000000050H;	Script[ 110] := 098080000H;	Script[ 111] := 001000000H;
		Script[ 112] := 060000040H;	Script[ 113] := 000000000H;	Script[ 114] := 01F000000H;	Script[ 115] := 000000048H;
		Script[ 116] := 080840001H;	Script[ 117] := 000000020H;	Script[ 118] := 060000040H;	Script[ 119] := 000000000H;
		Script[ 120] := 01F000000H;	Script[ 121] := 000000050H;	Script[ 122] := 01F000000H;	Script[ 123] := 000000058H;
		Script[ 124] := 098080000H;	Script[ 125] := 001010000H;	Script[ 126] := 058000008H;	Script[ 127] := 000000000H;
		Script[ 128] := 060000040H;	Script[ 129] := 000000000H;	Script[ 130] := 01E000000H;	Script[ 131] := 000000060H;
		Script[ 132] := 090080000H;	Script[ 133] := 000000000H;	Script[ 134] := 060000040H;	Script[ 135] := 000000000H;
		Script[ 136] := 090080000H;	Script[ 137] := 000000000H;	Script[ 138] := 058000008H;	Script[ 139] := 000000000H;
		Script[ 140] := 060000040H;	Script[ 141] := 000000000H;	Script[ 142] := 01E000000H;	Script[ 143] := 000000010H;
		Script[ 144] := 090080000H;	Script[ 145] := 000000000H;	Script[ 146] := 01B000000H;	Script[ 147] := 000000020H;
		Script[ 148] := 06A340000H;	Script[ 149] := 000000000H;	Script[ 150] := 01F000000H;	Script[ 151] := 000000030H;
		Script[ 152] := 07C027F00H;	Script[ 153] := 000000000H;	Script[ 154] := 060000040H;	Script[ 155] := 000000000H;
		Script[ 156] := 072340000H;	Script[ 157] := 000000000H;	Script[ 158] := 098180000H;	Script[ 159] := 000000000H;
		Script[ 160] := 048000000H;	Script[ 161] := 000000000H;	Script[ 162] := 098080000H;	Script[ 163] := 002020000H;
		Script[ 164] := 048000000H;	Script[ 165] := 000000000H;	Script[ 166] := 098080000H;	Script[ 167] := 000030000H;
		Script[ 168] := 098080000H;	Script[ 169] := 000040000H;	Script[ 170] := 0C0000004H;	Script[ 171] := 000000000H;
		Script[ 172] := 000000000H;	Script[ 173] := 098080000H;	Script[ 174] := 004000000H;	Script[ 175] := 060000200H;
		Script[ 176] := 000000000H;	Script[ 177] := 047000000H;	Script[ 178] := 000000050H;	Script[ 179] := 0868B0000H;
		Script[ 180] := 000000000H;	Script[ 181] := 01E000000H;	Script[ 182] := 000000008H;	Script[ 183] := 01A000000H;
		Script[ 184] := 000000018H;	Script[ 185] := 019000000H;	Script[ 186] := 000000028H;	Script[ 187] := 01B000000H;
		Script[ 188] := 000000020H;	Script[ 189] := 01F000000H;	Script[ 190] := 000000030H;	Script[ 191] := 07C027F00H;
		Script[ 192] := 000000000H;	Script[ 193] := 060000040H;	Script[ 194] := 000000000H;	Script[ 195] := 048000000H;
		Script[ 196] := 000000000H;	Script[ 197] := 098080000H;	Script[ 198] := 004020000H;	Script[ 199] := 098080000H;
		Script[ 200] := 004010000H;	
	END Init;

BEGIN
	Init
END NCRScript.
*)
