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

MODULE Sound;	(** non-portable *)	(** tb, SS96 *)
IMPORT Kernel, CD, Texts, Oberon, Out;

(**
Sound-Module : Interface for Sound-Devices (Mixer, Audio, CD-ROM)
Author: Thomas Burri ; CD-Interface by Emil Zeller (ejz)
Last Update: 
*)
(*
08.07.96 pjm - new Kernel.RemoveIP, DBdataSize
*)

	CONST
		DBdataSize* = 32768;	(* should be half of DMA.BufSize *)

		(** result codes *)
		Done* = 0;	(** call succeded *)
		Failed* = 1;	(** call failed *)
		NotOpened* = 2;	(** device isn't opened *)
		NotRunning* = 3;	(** device is Not Running (playing or recording *)
		NSStereo* = 6;	(** stereo mode is Not Supported with this soundcard *)
		NS16bit* = 7;	(** 16 bit is Not Supported with this soundcard *)
		NSFreq* = 8;	(** frequency is Not Supported with this soundcard *)
		NSSignedData* = 9;	(** signed data is Not Supported with this soundcard *)
		
		(** format *)
		PCM* = 0;
		ADPCM8b2b* = 1;
		ADPCM8b3b* = 2;
		ADPCM8b4b* = 3;

		(** devState bits of Audio and CD *)
		opened* = 0;
		playing* = 1;
		recording* = 2;
		paused* = 3;
		stopped* = 4;
		mediapresent* = 5;	(** only in use with CD *)

	TYPE
		Trigger* = PROCEDURE (end: BOOLEAN);
		(** end = FALSE : add new block / end = TRUE : play or recording finished *)
		AudioDef* = RECORD	(** defines how to play or record the audio file *)
			format*: INTEGER;	(** PCM, ADPCMxbxb *)
			stereo*, signed* : BOOLEAN;
			bits* : INTEGER;	(** 8 / 16 bits *)
			freq* : LONGINT;
			blocks*: LONGINT;	(** number of transferblocks needed for the audio file to play *)
			handle*: Trigger
		END;
		
		Channel* = RECORD	(** Mixer-Channel capabilities & desciption*)
			name*: ARRAY 32 OF CHAR;
			Ch*, nofSubCh*: LONGINT;
		END;
		SubChannel* = RECORD	(** Mixer-SubChannel capabilities & desciption *)
			name*: ARRAY 32 OF CHAR;
			Ch*, SubCh*, maxval*: LONGINT;	(** maxval = 0: use a checkbox, else a slider *)
			(** minval explicit 0 *)
		END;
		
		DataBlock* = POINTER TO DataBlockDesc;
		DataBlockDesc* = RECORD
			data*: ARRAY DBdataSize OF BYTE;
			len*: LONGINT;
			next: DataBlock
		END;
		
	VAR
		res*: INTEGER;

(* Soundcard *)

(** Mixer *)
(** GetNofChannels : returns number of usable Mixer-Channels with your Mixer-chip *)
PROCEDURE GetNofChannels*(): LONGINT;

END GetNofChannels;

(** GetChCapas : returns capabilities & description of a Mixer-Channel *)
PROCEDURE GetChCapas*(VAR c: Channel);

END GetChCapas;

(** GetSubChCapas : returns  capabilities & descprition of a Mixer-SubChannel *)
PROCEDURE GetSubChCapas*(VAR sc: SubChannel);

END GetSubChCapas;

(** GetValue : gets value of this SubChannel *)
PROCEDURE GetValue*(c, sc: LONGINT; VAR val: LONGINT);

END GetValue;

(** SetValue : sets SubChannel to val *)
PROCEDURE SetValue*(c, sc, val: LONGINT);

END SetValue;

PROCEDURE StopAudio*();

END StopAudio;

PROCEDURE CloseAudio*();

END CloseAudio;

PROCEDURE OpenAudio*(VAR d: AudioDef);

END OpenAudio;

PROCEDURE PlayAudio*();

END PlayAudio;

PROCEDURE RecordAudio*();

END RecordAudio;

PROCEDURE PauseAudio*();

END PauseAudio;

PROCEDURE ResumeAudio*();

END ResumeAudio;

PROCEDURE AddBlock*(buf: DataBlock);

END AddBlock;

PROCEDURE GetAudioPos*(VAR msec: LONGINT);

END GetAudioPos;

PROCEDURE GetAudioState*(): SET;

END GetAudioState;

(** CD *)
PROCEDURE CloseCD*();

END CloseCD;

PROCEDURE OpenCD*();

END OpenCD;

PROCEDURE NrOfCDTracks*(): INTEGER;

END NrOfCDTracks;

PROCEDURE CDTrackInfo*(track: INTEGER; VAR min, sec: INTEGER);

END CDTrackInfo;

PROCEDURE StopCD*();

END StopCD;

PROCEDURE CloseDoor*();

END CloseDoor;

PROCEDURE OpenDoor*();

END OpenDoor;

PROCEDURE PlayCD*(track0, min0, sec0, track1, min1, sec1: INTEGER);

END PlayCD;

PROCEDURE PauseCD*();

END PauseCD;

PROCEDURE ResumeCD*();

END ResumeCD;

PROCEDURE GetCDState*(): SET;

END GetCDState;

PROCEDURE GetCDPos*(VAR track, min, sec: INTEGER);

END GetCDPos;

BEGIN

END Sound.


(** Remarks :
	1. If you have a SoundBlaster Pro then you should notice that you can use only one
		source-channel at a time. That means the choice of one source-channel is exclusive,
		and so the checkboxes for the selection of the needed source should be initialized
		with the same model. This way they behave like the known RadioButtons
		in the Windows environment (only one can be selected at a time).
*)
