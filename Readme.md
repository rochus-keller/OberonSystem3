This is a version of the Oberon System 3 (also known as ETH Oberon), compatible with the [Oberon+ compiler, IDE and runtimes](https://github.com/rochus-keller/Oberon/blob/master/README.md) and the [OBX Platform Abstraction Layer (PAL)](https://github.com/rochus-keller/Oberon/tree/master/runtime/Pal), and thus truly cross-platform (runs on all platforms where [LeanQt](https://github.com/rochus-keller/LeanQt) is available). 

The migration is still work in progress, but sufficiently complete and stable to explore the platform. The latest commit is tested on both the Mono CLI and as a native executable built with the generated C code.

Here is a screenshot of the migrated system in action:

![Oberon System 3 on ObxPal Screenshot](http://software.rochus-keller.ch/oberon_system_3_obxpal_2.3.6_minimal_system_4.png)

And here is a screenshot of the migrated Oberon gadget system desktop:

![Oberon System 3 Desktop Screenshot](http://software.rochus-keller.ch/oberon_system_3_obxpal_2.3.6_minimal_system_6.png)

The migrated system is based on the PC Native Oberon System 3 Release 2.3.6 (Stand-alone) originally downloaded from [here](https://github.com/pcayuela/oldftpETHZOberon/tree/master/System3/Native/StdAlone). 

See [Changes.txt](./Changes.txt) for additional information about the applied migration steps, and [MigrationStatus.ods](./MigrationStatus.ods) for a module status matrix. Also note that there is a Git commit history documenting all modifications starting from the original code.

To run the system, [these Oberon system and documentation files](http://software.rochus-keller.ch/OberonSystem3_R2.3.6_Files.zip) (or [the ones from the previous release](http://software.rochus-keller.ch/OberonSystem3_R2.2_Files.tar.gz)) can be used. Copy the *Files* directory to the same directory where the compiled binaries are; note that in the same directory there must also be a copy of the PAL shared library (libPal.so on Linux, libPal.dylib on Mac and Pal.dll on Windows, compiled for the same processor architecture as the Oberon System binaries); also note that you have to use the Oberon IDE compiler version 0.9.94 or later (the pre-compiled versions might not be the most recent ones).

The system is included with the precompiled versions of the Oberon+ IDE.

Here are precompiled versions of the system. The packages include all required elements to run the system (just unpack and run, no installation required).

- [Windows x86](http://software.rochus-keller.ch/OberonSystem3_win32.zip)
- [Windows x64](http://software.rochus-keller.ch/OberonSystem3_win64.zip)
- [Linux x86](http://software.rochus-keller.ch/OberonSystem_linux_i386.tar.gz)
- [Linux x64](http://software.rochus-keller.ch/OberonSystem_linux_x86_64.tar.gz)
- [Mac x64](http://software.rochus-keller.ch/OberonSystem3_macOS_x64.dmg)
- [Mac M1](http://software.rochus-keller.ch/OberonSystem3_macOS_M1.dmg)

And here is the [generated C source code](http://software.rochus-keller.ch/OberonSystem_generated_C_source.zip) from which the precompiled versions were built, in case you want to have a look at it or build it yourself:

If you need support please post an issue on Github or send me an email.
