-------------------------------------
Translated Report (Full Report Below)
-------------------------------------
Process:             MarkdownEditor [87461]
Path:                /Users/USER/Documents/*/MarkdownEditor.app/Contents/MacOS/MarkdownEditor
Identifier:          com.example.MarkdownEditor
Version:             1.0 (1)
Code Type:           ARM-64 (Native)
Role:                Foreground
Parent Process:      launchd [1]
Coalition:           com.example.MarkdownEditor [28284]
User ID:             501

Date/Time:           2026-05-26 16:11:42.4349 +0800
Launch Time:         2026-05-26 16:09:51.3839 +0800
Hardware Model:      Mac16,8
OS Version:          macOS 26.5 (25F71)
Release Type:        User

Crash Reporter Key:  2BE2A560-BF05-2312-B679-6667750DA683
Incident Identifier: 5C8F13A7-AED3-47EC-840E-97C24C0985C3

Sleep/Wake UUID:       2688CFCD-84C0-48B5-8910-39F3F0925C2A

Time Awake Since Boot: 180000 seconds
Time Since Wake:       8228 seconds

System Integrity Protection: enabled

Triggered by Thread: 0, Dispatch Queue: com.apple.main-thread

Exception Type:    EXC_BAD_ACCESS (SIGSEGV)
Exception Subtype: KERN_INVALID_ADDRESS at 0x0000216b7cf75fb8
Exception Codes:   0x0000000000000001, 0x0000216b7cf75fb8

Termination Reason:  Namespace SIGNAL, Code 11, Segmentation fault: 11
Terminating Process: exc handler [87461]


VM Region Info: 0x216b7cf75fb8 is not in any region.  
      REGION TYPE                    START - END         [ VSIZE] PRT/MAX SHRMOD  REGION DETAIL
      UNUSED SPACE AT START
--->  
      UNUSED SPACE AT END

Thread 0 Crashed::  Dispatch queue: com.apple.main-thread
0   libobjc.A.dylib               	       0x1895c4014 objc_release + 16
1   MarkdownEditor                	       0x104663410 objectdestroy.6Tm + 72
2   libswiftCore.dylib            	       0x19d0ebcb0 _swift_release_dealloc + 64
3   libswiftCore.dylib            	       0x19d14eae4 bool swift::RefCounts<swift::RefCountBitsT<(swift::RefCountInlinedness)1>>::doDecrementSlow<(swift::PerformDeinit)1>(swift::RefCountBitsT<(swift::RefCountInlinedness)1>, unsigned int) + 168
4   libsystem_blocks.dylib        	       0x1896ec3fc _call_dispose_helpers_excp + 48
5   libsystem_blocks.dylib        	       0x1896ec1c0 _Block_release + 236
6   libdispatch.dylib             	       0x18987ddb8 _dispatch_source_handler_dispose + 36
7   libdispatch.dylib             	       0x18987e220 _dispatch_source_latch_and_call + 504
8   libdispatch.dylib             	       0x18987ce84 _dispatch_source_invoke + 844
9   libdispatch.dylib             	       0x18989e314 _dispatch_main_queue_drain.cold.6 + 612
10  libdispatch.dylib             	       0x1898759e4 _dispatch_main_queue_drain + 176
11  libdispatch.dylib             	       0x189875924 _dispatch_main_queue_callback_4CF + 44
12  CoreFoundation                	       0x189b1b724 __CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE__ + 16
13  CoreFoundation                	       0x189addcb8 __CFRunLoopRun + 1944
14  CoreFoundation                	       0x189bb01c4 _CFRunLoopRunSpecificWithOptions + 532
15  HIToolbox                     	       0x1968c3560 RunCurrentEventLoopInMode + 320
16  HIToolbox                     	       0x1968c68bc ReceiveNextEventCommon + 488
17  HIToolbox                     	       0x196a5014c _BlockUntilNextEventMatchingListInMode + 48
18  AppKit                        	       0x18e5b835c _DPSBlockUntilNextEventMatchingListInMode + 228
19  AppKit                        	       0x18df0c084 _DPSNextEvent + 576
20  AppKit                        	       0x18eaa18b0 -[NSApplication(NSEventRouting) _nextEventMatchingEventMask:untilDate:inMode:dequeue:] + 688
21  AppKit                        	       0x18eaa15bc -[NSApplication(NSEventRouting) nextEventMatchingMask:untilDate:inMode:dequeue:] + 72
22  AppKit                        	       0x18deff13c -[NSApplication run] + 368
23  AppKit                        	       0x18ded77b0 NSApplicationMain + 880
24  SwiftUI                       	       0x1be84a47c specialized runApp(_:) + 140
25  SwiftUI                       	       0x1bec004a4 runApp<A>(_:) + 104
26  SwiftUI                       	       0x1beecc344 static App.main() + 224
27  MarkdownEditor                	       0x104638550 main + 64
28  dyld                          	       0x189663e00 start + 6992

Thread 1:: com.apple.NSEventThread
0   libsystem_kernel.dylib        	       0x1899ddc34 mach_msg2_trap + 8
1   libsystem_kernel.dylib        	       0x1899f0574 mach_msg2_internal + 76
2   libsystem_kernel.dylib        	       0x1899e69c0 mach_msg_overwrite + 480
3   libsystem_kernel.dylib        	       0x1899ddfc0 mach_msg + 24
4   CoreFoundation                	       0x189adf0d8 __CFRunLoopServiceMachPort + 160
5   CoreFoundation                	       0x189add9c4 __CFRunLoopRun + 1188
6   CoreFoundation                	       0x189bb01c4 _CFRunLoopRunSpecificWithOptions + 532
7   AppKit                        	       0x18e02dc7c _NSEventThread + 184
8   libsystem_pthread.dylib       	       0x189a21c58 _pthread_start + 136
9   libsystem_pthread.dylib       	       0x189a1cc1c thread_start + 8

Thread 2:: WebCore: Scrolling
0   libsystem_kernel.dylib        	       0x1899ddc34 mach_msg2_trap + 8
1   libsystem_kernel.dylib        	       0x1899f0574 mach_msg2_internal + 76
2   libsystem_kernel.dylib        	       0x1899e69c0 mach_msg_overwrite + 480
3   libsystem_kernel.dylib        	       0x1899ddfc0 mach_msg + 24
4   CoreFoundation                	       0x189adf0d8 __CFRunLoopServiceMachPort + 160
5   CoreFoundation                	       0x189add9c4 __CFRunLoopRun + 1188
6   CoreFoundation                	       0x189bb01c4 _CFRunLoopRunSpecificWithOptions + 532
7   CoreFoundation                	       0x189b53af4 CFRunLoopRun + 64
8   JavaScriptCore                	       0x1abae55a8 WTF::Detail::CallableWrapper<WTF::RunLoop::create(WTF::ASCIILiteral, WTF::ThreadType, WTF::Thread::QOS)::$_0, void>::call() + 244
9   JavaScriptCore                	       0x1abb2d254 WTF::Thread::entryPoint(WTF::Thread::NewThreadContext*) + 300
10  JavaScriptCore                	       0x1ab8fb088 WTF::wtfThreadEntryPoint(void*) + 16
11  libsystem_pthread.dylib       	       0x189a21c58 _pthread_start + 136
12  libsystem_pthread.dylib       	       0x189a1cc1c thread_start + 8

Thread 3:: Log work queue
0   libsystem_kernel.dylib        	       0x1899ddbb0 semaphore_wait_trap + 8
1   WebKit                        	       0x1b4ed6d9c IPC::StreamConnectionWorkQueue::startProcessingThread()::$_0::operator()() + 48
2   JavaScriptCore                	       0x1abb2d254 WTF::Thread::entryPoint(WTF::Thread::NewThreadContext*) + 300
3   JavaScriptCore                	       0x1ab8fb088 WTF::wtfThreadEntryPoint(void*) + 16
4   libsystem_pthread.dylib       	       0x189a21c58 _pthread_start + 136
5   libsystem_pthread.dylib       	       0x189a1cc1c thread_start + 8

Thread 4:: JavaScriptCore libpas scavenger
0   libsystem_kernel.dylib        	       0x1899e150c __psynch_cvwait + 8
1   libsystem_pthread.dylib       	       0x189a22128 _pthread_cond_wait + 980
2   JavaScriptCore                	       0x1ad1b926c scavenger_thread_main + 1416
3   libsystem_pthread.dylib       	       0x189a21c58 _pthread_start + 136
4   libsystem_pthread.dylib       	       0x189a1cc1c thread_start + 8

Thread 5:

Thread 6:

Thread 7:

Thread 8:

Thread 9:


Thread 0 crashed with ARM Thread State (64-bit):
    x0: 0x0000000cae22ed00   x1: 0x0000001c00000003   x2: 0x0000216b7cf75f98   x3: 0x0000000000000001
    x4: 0x0000001c00000003   x5: 0x0000000000000001   x6: 0x0000001c00000003   x7: 0x0000000000000001
    x8: 0xfffffffe00000000   x9: 0x00000000fffffffe  x10: 0x0000000043000002  x11: 0x0000000000000002
   x12: 0x0000000043000001  x13: 0x0000000cac3b62e8  x14: 0x0000000043000002  x15: 0x0000000cadf38000
   x16: 0x25ea216b7cf75f9e  x17: 0x0000001a00000003  x18: 0x0000000000000000  x19: 0x0000000000000000
   x20: 0x0000000cac79f200  x21: 0x0000000000000000  x22: 0x0000000000000002  x23: 0x00000001f5ba6800
   x24: 0x0000000cac34f100  x25: 0x0000000000000001  x26: 0x00000001f5ba6800  x27: 0x000000016b7c9d70
   x28: 0x00000001f5ba6880   fp: 0x000000016b7c9ad0   lr: 0x0000000104663410
    sp: 0x000000016b7c9ad0   pc: 0x00000001895c4014 cpsr: 0x00000000
   far: 0x0000216b7cf75fb8  esr: 0x92000005 (Data Abort) byte read Translation fault

Binary Images:
       0x104634000 -        0x1046a7fff com.example.MarkdownEditor (1.0) <3c80263b-2a1c-3ec1-ae77-072622708e5e> /Users/USER/Documents/*/MarkdownEditor.app/Contents/MacOS/MarkdownEditor
       0x1047b4000 -        0x1047dbfff libcmark-gfm.0.29.0.gfm.13.dylib (*) <e5635193-e70c-3370-beb0-42808d01ba44> /opt/homebrew/*/libcmark-gfm.0.29.0.gfm.13.dylib
       0x104784000 -        0x10478bfff libcmark-gfm-extensions.0.29.0.gfm.13.dylib (*) <b6b3722b-4e00-35b0-bd8b-ad70e77c6d11> /opt/homebrew/*/libcmark-gfm-extensions.0.29.0.gfm.13.dylib
       0x10d204000 -        0x10d20ffff libobjc-trampolines.dylib (*) <ca58aa96-b997-3a6d-9132-19d49be4b3e9> /usr/lib/libobjc-trampolines.dylib
       0x118a58000 -        0x1192cffff com.apple.AGXMetalG16X (351.2) <7499d423-c36d-31c5-9c15-3f5b0ad94779> /System/Library/Extensions/AGXMetalG16X.bundle/Contents/MacOS/AGXMetalG16X
       0x1189a4000 -        0x118a07fff com.apple.AppleMetalOpenGLRenderer (1.0) <ed97217d-dbc3-3bd9-a531-e874ea072aa6> /System/Library/Extensions/AppleMetalOpenGLRenderer.bundle/Contents/MacOS/AppleMetalOpenGLRenderer
       0x1895bc000 -        0x18960eb4b libobjc.A.dylib (*) <ff1d8ae4-abef-35f1-a30a-1183b9cb414f> /usr/lib/libobjc.A.dylib
       0x19d0e0000 -        0x19d6817bf libswiftCore.dylib (*) <7669d858-d332-36c7-9c6c-4564ffbea8d2> /usr/lib/swift/libswiftCore.dylib
       0x1896eb000 -        0x1896ee228 libsystem_blocks.dylib (*) <cc947089-488d-316b-a9c7-46dec0f73145> /usr/lib/system/libsystem_blocks.dylib
       0x189865000 -        0x1898ac23f libdispatch.dylib (*) <f071efe4-299f-3089-acc4-0025b8ffb52a> /usr/lib/system/libdispatch.dylib
       0x189a61000 -        0x189fbf31f com.apple.CoreFoundation (6.9) <04e3598b-f226-3250-b3b2-ce938dd4db7e> /System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation
       0x196806000 -        0x196b0111f com.apple.HIToolbox (2.1.1) <8716490e-acc2-3688-8c2f-5ca42b4c9da9> /System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/HIToolbox
       0x18ded3000 -        0x18f5f5f9f com.apple.AppKit (6.9) <cf57a4fc-4be3-3d95-b543-d744e8718b26> /System/Library/Frameworks/AppKit.framework/Versions/C/AppKit
       0x1be73f000 -        0x1bfe8877f com.apple.SwiftUI (7.5.3) <90f7fa24-a280-3e8a-a62d-148b11bfc28d> /System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI
       0x189644000 -        0x1896ea217 dyld (*) <a237ef81-b68b-37ba-a165-92c965529534> /usr/lib/dyld
               0x0 - 0xffffffffffffffff ??? (*) <00000000-0000-0000-0000-000000000000> ???
       0x1899dd000 -        0x189a1a2af libsystem_kernel.dylib (*) <cc1cf985-bc65-3725-809f-4c1e36b8f4ba> /usr/lib/system/libsystem_kernel.dylib
       0x189a1b000 -        0x189a27b3b libsystem_pthread.dylib (*) <4f33683c-18c8-39a1-800b-2e3bd43bcc13> /usr/lib/system/libsystem_pthread.dylib
       0x1ab8f5000 -        0x1ad3d4e7f com.apple.JavaScriptCore (21624) <c2013e04-a794-3826-8682-29ad862df9c9> /System/Library/Frameworks/JavaScriptCore.framework/Versions/A/JavaScriptCore
       0x1b3cbe000 -        0x1b52a4d9f com.apple.WebKit (21624) <c67d8890-c314-324b-9b5d-8d41082ad492> /System/Library/Frameworks/WebKit.framework/Versions/A/WebKit

External Modification Summary:
  Calls made by other processes targeting this process:
    task_for_pid: 0
    thread_create: 0
    thread_set_state: 0
  Calls made by this process:
    task_for_pid: 0
    thread_create: 0
    thread_set_state: 0
  Calls made by all processes on this machine:
    task_for_pid: 0
    thread_create: 0
    thread_set_state: 0

VM Region Summary:
ReadOnly portion of Libraries: Total=1.8G resident=0K(0%) swapped_out_or_unallocated=1.8G(100%)
Writable regions: Total=4.5G written=929K(0%) resident=929K(0%) swapped_out=0K(0%) unallocated=4.5G(100%)

                                VIRTUAL   REGION 
REGION TYPE                        SIZE    COUNT (non-coalesced) 
===========                     =======  ======= 
Accelerate framework               128K        1 
Activity Tracing                   256K        1 
AttributeGraph Data               1024K        1 
ColorSync                           32K        2 
CoreAnimation                     5104K      133 
CoreGraphics                        48K        3 
CoreServices                       624K        2 
CoreUI image data                  656K        5 
Foundation                          16K        1 
JS VM Gigacage (reserved)          4.0G        1         reserved VM address space (unallocated)
Kernel Alloc Once                   32K        1 
MALLOC                           186.0M       56 
MALLOC guard page                 4128K        4 
Memory Tag 22                     64.0M        1 
STACK GUARD                       56.2M       10 
Stack                             12.8M       10 
VM_ALLOCATE                       3472K       10 
WebKit Malloc                    256.1M        7 
__AUTH                            5995K      636 
__AUTH_CONST                      89.0M     1024 
__CTF                               824        1 
__DATA                            34.3M      977 
__DATA_CONST                      34.6M     1034 
__DATA_DIRTY                      8388K      882 
__FONT_DATA                        2352        1 
__GLSLBUILTINS                    5176K        1 
__LINKEDIT                       576.5M        7 
__OBJC_RO                         79.1M        1 
__OBJC_RW                         2599K        1 
__TEXT                             1.2G     1056 
__TPRO_CONST                       128K        2 
mapped file                      711.7M       66 
page table in kernel               929K        1 
shared memory                     1952K       17 
===========                     =======  ======= 
TOTAL                              7.3G     5956 
TOTAL, minus reserved VM space     3.3G     5956 


-----------
Full Report
-----------

{"app_name":"MarkdownEditor","timestamp":"2026-05-26 16:11:45.00 +0800","app_version":"1.0","slice_uuid":"3c80263b-2a1c-3ec1-ae77-072622708e5e","build_version":"1","platform":1,"bundleID":"com.example.MarkdownEditor","share_with_app_devs":0,"is_first_party":0,"bug_type":"309","os_version":"macOS 26.5 (25F71)","roots_installed":0,"name":"MarkdownEditor","incident_id":"5C8F13A7-AED3-47EC-840E-97C24C0985C3"}
{
  "uptime" : 180000,
  "procRole" : "Foreground",
  "version" : 2,
  "userID" : 501,
  "deployVersion" : 210,
  "modelCode" : "Mac16,8",
  "coalitionID" : 28284,
  "osVersion" : {
    "train" : "macOS 26.5",
    "build" : "25F71",
    "releaseType" : "User"
  },
  "captureTime" : "2026-05-26 16:11:42.4349 +0800",
  "codeSigningMonitor" : 2,
  "incident" : "5C8F13A7-AED3-47EC-840E-97C24C0985C3",
  "pid" : 87461,
  "translated" : false,
  "cpuType" : "ARM-64",
  "procLaunch" : "2026-05-26 16:09:51.3839 +0800",
  "procStartAbsTime" : 4508192711522,
  "procExitAbsTime" : 4510857735262,
  "procName" : "MarkdownEditor",
  "procPath" : "\/Users\/USER\/Documents\/*\/MarkdownEditor.app\/Contents\/MacOS\/MarkdownEditor",
  "bundleInfo" : {"CFBundleShortVersionString":"1.0","CFBundleVersion":"1","CFBundleIdentifier":"com.example.MarkdownEditor"},
  "storeInfo" : {"deviceIdentifierForVendor":"F0E5EEF7-01DB-5735-B268-57ABBCDBACBE","thirdParty":true},
  "parentProc" : "launchd",
  "parentPid" : 1,
  "coalitionName" : "com.example.MarkdownEditor",
  "crashReporterKey" : "2BE2A560-BF05-2312-B679-6667750DA683",
  "appleIntelligenceStatus" : {"state":"unavailable","reasons":["regionIneligible"]},
  "developerMode" : 1,
  "codeSigningID" : "com.example.MarkdownEditor",
  "codeSigningTeamID" : "",
  "codeSigningFlags" : 570425857,
  "codeSigningValidationCategory" : 10,
  "codeSigningTrustLevel" : 4294967295,
  "codeSigningAuxiliaryInfo" : 0,
  "instructionByteStream" : {"beforePC":"gf7\/VMADX9bAA1\/W4Wo9sCHgK5EABgAUAAAA6m3\/\/1QQAED5Aq59kg==","atPC":"URBA+TEDEDYwBAA2Ef5305H+\/7Q\/BgDxYAIAVBEg4NIRAhHL4QMQqg=="},
  "bootSessionUUID" : "56DFD9E3-1CD9-49CA-B631-AEEEBD05D0AF",
  "wakeTime" : 8228,
  "sleepWakeUUID" : "2688CFCD-84C0-48B5-8910-39F3F0925C2A",
  "sip" : "enabled",
  "vmRegionInfo" : "0x216b7cf75fb8 is not in any region.  \n      REGION TYPE                    START - END         [ VSIZE] PRT\/MAX SHRMOD  REGION DETAIL\n      UNUSED SPACE AT START\n--->  \n      UNUSED SPACE AT END",
  "exception" : {"codes":"0x0000000000000001, 0x0000216b7cf75fb8","rawCodes":[1,36745541803960],"type":"EXC_BAD_ACCESS","signal":"SIGSEGV","subtype":"KERN_INVALID_ADDRESS at 0x0000216b7cf75fb8"},
  "termination" : {"flags":0,"code":11,"namespace":"SIGNAL","indicator":"Segmentation fault: 11","byProc":"exc handler","byPid":87461},
  "vmregioninfo" : "0x216b7cf75fb8 is not in any region.  \n      REGION TYPE                    START - END         [ VSIZE] PRT\/MAX SHRMOD  REGION DETAIL\n      UNUSED SPACE AT START\n--->  \n      UNUSED SPACE AT END",
  "extMods" : {"caller":{"thread_create":0,"thread_set_state":0,"task_for_pid":0},"system":{"thread_create":0,"thread_set_state":0,"task_for_pid":0},"targeted":{"thread_create":0,"thread_set_state":0,"task_for_pid":0},"warnings":0},
  "faultingThread" : 0,
  "threads" : [{"triggered":true,"id":3814767,"threadState":{"x":[{"value":54461132032},{"value":120259084291},{"value":36745541803928},{"value":1},{"value":120259084291},{"value":1},{"value":120259084291},{"value":1},{"value":18446744065119617024},{"value":4294967294},{"value":1124073474},{"value":2},{"value":1124073473},{"value":54429180648},{"value":1124073474},{"value":54458023936},{"value":2732032869495431070},{"value":111669149699},{"value":0},{"value":0},{"value":54433280512},{"value":0},{"value":2},{"value":8417601536,"symbolLocation":0,"symbol":"_dispatch_main_q"},{"value":54428758272},{"value":1},{"value":8417601536,"symbolLocation":0,"symbol":"_dispatch_main_q"},{"value":6098296176},{"value":8417601664,"symbolLocation":0,"symbol":"_dispatch_mgr_q"}],"flavor":"ARM_THREAD_STATE64","lr":{"value":4368774160},"cpsr":{"value":0},"fp":{"value":6098295504},"sp":{"value":6098295504},"esr":{"value":2449473541,"description":"(Data Abort) byte read Translation fault"},"pc":{"value":6599491604,"matchesCrashFrame":1},"far":{"value":36745541803960}},"queue":"com.apple.main-thread","frames":[{"imageOffset":32788,"symbol":"objc_release","symbolLocation":16,"imageIndex":6},{"imageOffset":193552,"symbol":"objectdestroy.6Tm","symbolLocation":72,"imageIndex":0},{"imageOffset":48304,"symbol":"_swift_release_dealloc","symbolLocation":64,"imageIndex":7},{"imageOffset":453348,"symbol":"bool swift::RefCounts<swift::RefCountBitsT<(swift::RefCountInlinedness)1>>::doDecrementSlow<(swift::PerformDeinit)1>(swift::RefCountBitsT<(swift::RefCountInlinedness)1>, unsigned int)","symbolLocation":168,"imageIndex":7},{"imageOffset":5116,"symbol":"_call_dispose_helpers_excp","symbolLocation":48,"imageIndex":8},{"imageOffset":4544,"symbol":"_Block_release","symbolLocation":236,"imageIndex":8},{"imageOffset":101816,"symbol":"_dispatch_source_handler_dispose","symbolLocation":36,"imageIndex":9},{"imageOffset":102944,"symbol":"_dispatch_source_latch_and_call","symbolLocation":504,"imageIndex":9},{"imageOffset":97924,"symbol":"_dispatch_source_invoke","symbolLocation":844,"imageIndex":9},{"imageOffset":234260,"symbol":"_dispatch_main_queue_drain.cold.6","symbolLocation":612,"imageIndex":9},{"imageOffset":68068,"symbol":"_dispatch_main_queue_drain","symbolLocation":176,"imageIndex":9},{"imageOffset":67876,"symbol":"_dispatch_main_queue_callback_4CF","symbolLocation":44,"imageIndex":9},{"imageOffset":763684,"symbol":"__CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE__","symbolLocation":16,"imageIndex":10},{"imageOffset":511160,"symbol":"__CFRunLoopRun","symbolLocation":1944,"imageIndex":10},{"imageOffset":1372612,"symbol":"_CFRunLoopRunSpecificWithOptions","symbolLocation":532,"imageIndex":10},{"imageOffset":775520,"symbol":"RunCurrentEventLoopInMode","symbolLocation":320,"imageIndex":11},{"imageOffset":788668,"symbol":"ReceiveNextEventCommon","symbolLocation":488,"imageIndex":11},{"imageOffset":2400588,"symbol":"_BlockUntilNextEventMatchingListInMode","symbolLocation":48,"imageIndex":11},{"imageOffset":7230300,"symbol":"_DPSBlockUntilNextEventMatchingListInMode","symbolLocation":228,"imageIndex":12},{"imageOffset":233604,"symbol":"_DPSNextEvent","symbolLocation":576,"imageIndex":12},{"imageOffset":12380336,"symbol":"-[NSApplication(NSEventRouting) _nextEventMatchingEventMask:untilDate:inMode:dequeue:]","symbolLocation":688,"imageIndex":12},{"imageOffset":12379580,"symbol":"-[NSApplication(NSEventRouting) nextEventMatchingMask:untilDate:inMode:dequeue:]","symbolLocation":72,"imageIndex":12},{"imageOffset":180540,"symbol":"-[NSApplication run]","symbolLocation":368,"imageIndex":12},{"imageOffset":18352,"symbol":"NSApplicationMain","symbolLocation":880,"imageIndex":12},{"imageOffset":1094780,"symbol":"specialized runApp(_:)","symbolLocation":140,"imageIndex":13},{"imageOffset":4986020,"symbol":"runApp<A>(_:)","symbolLocation":104,"imageIndex":13},{"imageOffset":7918404,"symbol":"static App.main()","symbolLocation":224,"imageIndex":13},{"imageOffset":17744,"symbol":"main","symbolLocation":64,"imageIndex":0},{"imageOffset":130560,"symbol":"start","symbolLocation":6992,"imageIndex":14}]},{"id":3814880,"name":"com.apple.NSEventThread","threadState":{"x":[{"value":268451845},{"value":21592279046},{"value":8589934592},{"value":131954280235008},{"value":0},{"value":131954280235008},{"value":2},{"value":4294967295},{"value":0},{"value":17179869184},{"value":0},{"value":2},{"value":0},{"value":0},{"value":30723},{"value":0},{"value":18446744073709551569},{"value":8440903440},{"value":0},{"value":4294967295},{"value":2},{"value":131954280235008},{"value":0},{"value":131954280235008},{"value":21592279046},{"value":6101721224},{"value":8589934592},{"value":18446744073709550527},{"value":4412409862}],"flavor":"ARM_THREAD_STATE64","lr":{"value":6603867508},"cpsr":{"value":0},"fp":{"value":6101721072},"sp":{"value":6101720992},"esr":{"value":1442840704,"description":"(Syscall)"},"pc":{"value":6603791412},"far":{"value":0}},"frames":[{"imageOffset":3124,"symbol":"mach_msg2_trap","symbolLocation":8,"imageIndex":16},{"imageOffset":79220,"symbol":"mach_msg2_internal","symbolLocation":76,"imageIndex":16},{"imageOffset":39360,"symbol":"mach_msg_overwrite","symbolLocation":480,"imageIndex":16},{"imageOffset":4032,"symbol":"mach_msg","symbolLocation":24,"imageIndex":16},{"imageOffset":516312,"symbol":"__CFRunLoopServiceMachPort","symbolLocation":160,"imageIndex":10},{"imageOffset":510404,"symbol":"__CFRunLoopRun","symbolLocation":1188,"imageIndex":10},{"imageOffset":1372612,"symbol":"_CFRunLoopRunSpecificWithOptions","symbolLocation":532,"imageIndex":10},{"imageOffset":1420412,"symbol":"_NSEventThread","symbolLocation":184,"imageIndex":12},{"imageOffset":27736,"symbol":"_pthread_start","symbolLocation":136,"imageIndex":17},{"imageOffset":7196,"symbol":"thread_start","symbolLocation":8,"imageIndex":17}]},{"id":3815037,"name":"WebCore: Scrolling","threadState":{"x":[{"value":268451845},{"value":21592279046},{"value":8589934592},{"value":379344396484608},{"value":0},{"value":379344396484608},{"value":2},{"value":4294967295},{"value":0},{"value":17179869184},{"value":0},{"value":2},{"value":0},{"value":0},{"value":88323},{"value":14293651164416},{"value":18446744073709551569},{"value":8440903440},{"value":0},{"value":4294967295},{"value":2},{"value":379344396484608},{"value":0},{"value":379344396484608},{"value":21592279046},{"value":6104014792},{"value":8589934592},{"value":18446744073709550527},{"value":4412409862}],"flavor":"ARM_THREAD_STATE64","lr":{"value":6603867508},"cpsr":{"value":0},"fp":{"value":6104014640},"sp":{"value":6104014560},"esr":{"value":1442840704,"description":"(Syscall)"},"pc":{"value":6603791412},"far":{"value":0}},"frames":[{"imageOffset":3124,"symbol":"mach_msg2_trap","symbolLocation":8,"imageIndex":16},{"imageOffset":79220,"symbol":"mach_msg2_internal","symbolLocation":76,"imageIndex":16},{"imageOffset":39360,"symbol":"mach_msg_overwrite","symbolLocation":480,"imageIndex":16},{"imageOffset":4032,"symbol":"mach_msg","symbolLocation":24,"imageIndex":16},{"imageOffset":516312,"symbol":"__CFRunLoopServiceMachPort","symbolLocation":160,"imageIndex":10},{"imageOffset":510404,"symbol":"__CFRunLoopRun","symbolLocation":1188,"imageIndex":10},{"imageOffset":1372612,"symbol":"_CFRunLoopRunSpecificWithOptions","symbolLocation":532,"imageIndex":10},{"imageOffset":994036,"symbol":"CFRunLoopRun","symbolLocation":64,"imageIndex":10},{"imageOffset":2033064,"symbol":"WTF::Detail::CallableWrapper<WTF::RunLoop::create(WTF::ASCIILiteral, WTF::ThreadType, WTF::Thread::QOS)::$_0, void>::call()","symbolLocation":244,"imageIndex":18},{"imageOffset":2327124,"symbol":"WTF::Thread::entryPoint(WTF::Thread::NewThreadContext*)","symbolLocation":300,"imageIndex":18},{"imageOffset":24712,"symbol":"WTF::wtfThreadEntryPoint(void*)","symbolLocation":16,"imageIndex":18},{"imageOffset":27736,"symbol":"_pthread_start","symbolLocation":136,"imageIndex":17},{"imageOffset":7196,"symbol":"thread_start","symbolLocation":8,"imageIndex":17}]},{"id":3815047,"name":"Log work queue","threadState":{"x":[{"value":14},{"value":4496330704},{"value":0},{"value":6105160000},{"value":8372730880,"symbolLocation":0,"symbol":"_os_log_current_test_callback"},{"value":1},{"value":69287924},{"value":6105166048},{"value":0},{"value":0},{"value":0},{"value":0},{"value":3848},{"value":3848},{"value":8417592848,"symbolLocation":0,"symbol":"OBJC_CLASS_$_OS_os_log"},{"value":8417592848,"symbolLocation":0,"symbol":"OBJC_CLASS_$_OS_os_log"},{"value":18446744073709551580},{"value":8440905936},{"value":0},{"value":4764731520},{"value":4764731560},{"value":6105165824},{"value":0},{"value":0},{"value":4764786688},{"value":0},{"value":0},{"value":0},{"value":0}],"flavor":"ARM_THREAD_STATE64","lr":{"value":7330426268},"cpsr":{"value":2147483648},"fp":{"value":6105165648},"sp":{"value":6105165616},"esr":{"value":1442840704,"description":"(Syscall)"},"pc":{"value":6603791280},"far":{"value":0}},"frames":[{"imageOffset":2992,"symbol":"semaphore_wait_trap","symbolLocation":8,"imageIndex":16},{"imageOffset":18976156,"symbol":"IPC::StreamConnectionWorkQueue::startProcessingThread()::$_0::operator()()","symbolLocation":48,"imageIndex":19},{"imageOffset":2327124,"symbol":"WTF::Thread::entryPoint(WTF::Thread::NewThreadContext*)","symbolLocation":300,"imageIndex":18},{"imageOffset":24712,"symbol":"WTF::wtfThreadEntryPoint(void*)","symbolLocation":16,"imageIndex":18},{"imageOffset":27736,"symbol":"_pthread_start","symbolLocation":136,"imageIndex":17},{"imageOffset":7196,"symbol":"thread_start","symbolLocation":8,"imageIndex":17}]},{"id":3816322,"name":"JavaScriptCore libpas scavenger","threadState":{"x":[{"value":260},{"value":0},{"value":133888},{"value":0},{"value":0},{"value":160},{"value":0},{"value":99999088},{"value":6100577960},{"value":0},{"value":0},{"value":2},{"value":2},{"value":0},{"value":0},{"value":0},{"value":305},{"value":8440901560},{"value":0},{"value":4838205504},{"value":4838205568},{"value":6100578528},{"value":99999088},{"value":0},{"value":133888},{"value":145409},{"value":145664},{"value":0},{"value":8420253696,"symbolLocation":3504,"symbol":"bmalloc_common_primitive_heap_support"}],"flavor":"ARM_THREAD_STATE64","lr":{"value":6604071208},"cpsr":{"value":1610612736},"fp":{"value":6100578080},"sp":{"value":6100577936},"esr":{"value":1442840704,"description":"(Syscall)"},"pc":{"value":6603805964},"far":{"value":0}},"frames":[{"imageOffset":17676,"symbol":"__psynch_cvwait","symbolLocation":8,"imageIndex":16},{"imageOffset":28968,"symbol":"_pthread_cond_wait","symbolLocation":980,"imageIndex":17},{"imageOffset":25969260,"symbol":"scavenger_thread_main","symbolLocation":1416,"imageIndex":18},{"imageOffset":27736,"symbol":"_pthread_start","symbolLocation":136,"imageIndex":17},{"imageOffset":7196,"symbol":"thread_start","symbolLocation":8,"imageIndex":17}]},{"id":3816581,"frames":[],"threadState":{"x":[{"value":6102298624},{"value":78095},{"value":6101762048},{"value":0},{"value":409604},{"value":18446744073709551615},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0}],"flavor":"ARM_THREAD_STATE64","lr":{"value":0},"cpsr":{"value":0},"fp":{"value":0},"sp":{"value":6102298624},"esr":{"value":1442840704,"description":"(Syscall)"},"pc":{"value":6604049416},"far":{"value":0}}},{"id":3817127,"frames":[],"threadState":{"x":[{"value":6098857984},{"value":10111},{"value":6098321408},{"value":0},{"value":409604},{"value":18446744073709551615},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0}],"flavor":"ARM_THREAD_STATE64","lr":{"value":0},"cpsr":{"value":0},"fp":{"value":0},"sp":{"value":6098857984},"esr":{"value":1442840704,"description":"(Syscall)"},"pc":{"value":6604049416},"far":{"value":0}}},{"id":3817276,"frames":[],"threadState":{"x":[{"value":6107459584},{"value":101923},{"value":6106923008},{"value":0},{"value":409604},{"value":18446744073709551615},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0}],"flavor":"ARM_THREAD_STATE64","lr":{"value":0},"cpsr":{"value":0},"fp":{"value":0},"sp":{"value":6107459584},"esr":{"value":1442840704,"description":"(Syscall)"},"pc":{"value":6604049416},"far":{"value":0}}},{"id":3817399,"frames":[],"threadState":{"x":[{"value":6103445504},{"value":116259},{"value":6102908928},{"value":0},{"value":409604},{"value":18446744073709551615},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0}],"flavor":"ARM_THREAD_STATE64","lr":{"value":0},"cpsr":{"value":0},"fp":{"value":0},"sp":{"value":6103445504},"esr":{"value":1442840704,"description":"(Syscall)"},"pc":{"value":6604049416},"far":{"value":0}}},{"id":3817400,"frames":[],"threadState":{"x":[{"value":6104592384},{"value":0},{"value":6104055808},{"value":0},{"value":278532},{"value":18446744073709551615},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0}],"flavor":"ARM_THREAD_STATE64","lr":{"value":0},"cpsr":{"value":0},"fp":{"value":0},"sp":{"value":6104592384},"esr":{"value":0},"pc":{"value":6604049416},"far":{"value":0}}}],
  "usedImages" : [
  {
    "source" : "P",
    "arch" : "arm64",
    "base" : 4368580608,
    "CFBundleShortVersionString" : "1.0",
    "CFBundleIdentifier" : "com.example.MarkdownEditor",
    "size" : 475136,
    "uuid" : "3c80263b-2a1c-3ec1-ae77-072622708e5e",
    "path" : "\/Users\/USER\/Documents\/*\/MarkdownEditor.app\/Contents\/MacOS\/MarkdownEditor",
    "name" : "MarkdownEditor",
    "CFBundleVersion" : "1"
  },
  {
    "source" : "P",
    "arch" : "arm64",
    "base" : 4370153472,
    "size" : 163840,
    "uuid" : "e5635193-e70c-3370-beb0-42808d01ba44",
    "path" : "\/opt\/homebrew\/*\/libcmark-gfm.0.29.0.gfm.13.dylib",
    "name" : "libcmark-gfm.0.29.0.gfm.13.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64",
    "base" : 4369956864,
    "size" : 32768,
    "uuid" : "b6b3722b-4e00-35b0-bd8b-ad70e77c6d11",
    "path" : "\/opt\/homebrew\/*\/libcmark-gfm-extensions.0.29.0.gfm.13.dylib",
    "name" : "libcmark-gfm-extensions.0.29.0.gfm.13.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 4515184640,
    "size" : 49152,
    "uuid" : "ca58aa96-b997-3a6d-9132-19d49be4b3e9",
    "path" : "\/usr\/lib\/libobjc-trampolines.dylib",
    "name" : "libobjc-trampolines.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 4708466688,
    "CFBundleShortVersionString" : "351.2",
    "CFBundleIdentifier" : "com.apple.AGXMetalG16X",
    "size" : 8880128,
    "uuid" : "7499d423-c36d-31c5-9c15-3f5b0ad94779",
    "path" : "\/System\/Library\/Extensions\/AGXMetalG16X.bundle\/Contents\/MacOS\/AGXMetalG16X",
    "name" : "AGXMetalG16X",
    "CFBundleVersion" : "351.2"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 4707729408,
    "CFBundleShortVersionString" : "1.0",
    "CFBundleIdentifier" : "com.apple.AppleMetalOpenGLRenderer",
    "size" : 409600,
    "uuid" : "ed97217d-dbc3-3bd9-a531-e874ea072aa6",
    "path" : "\/System\/Library\/Extensions\/AppleMetalOpenGLRenderer.bundle\/Contents\/MacOS\/AppleMetalOpenGLRenderer",
    "name" : "AppleMetalOpenGLRenderer",
    "CFBundleVersion" : "1"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 6599458816,
    "size" : 338764,
    "uuid" : "ff1d8ae4-abef-35f1-a30a-1183b9cb414f",
    "path" : "\/usr\/lib\/libobjc.A.dylib",
    "name" : "libobjc.A.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 6929907712,
    "size" : 5904320,
    "uuid" : "7669d858-d332-36c7-9c6c-4564ffbea8d2",
    "path" : "\/usr\/lib\/swift\/libswiftCore.dylib",
    "name" : "libswiftCore.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 6600699904,
    "size" : 12841,
    "uuid" : "cc947089-488d-316b-a9c7-46dec0f73145",
    "path" : "\/usr\/lib\/system\/libsystem_blocks.dylib",
    "name" : "libsystem_blocks.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 6602248192,
    "size" : 291392,
    "uuid" : "f071efe4-299f-3089-acc4-0025b8ffb52a",
    "path" : "\/usr\/lib\/system\/libdispatch.dylib",
    "name" : "libdispatch.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 6604328960,
    "CFBundleShortVersionString" : "6.9",
    "CFBundleIdentifier" : "com.apple.CoreFoundation",
    "size" : 5628704,
    "uuid" : "04e3598b-f226-3250-b3b2-ce938dd4db7e",
    "path" : "\/System\/Library\/Frameworks\/CoreFoundation.framework\/Versions\/A\/CoreFoundation",
    "name" : "CoreFoundation",
    "CFBundleVersion" : "5026.5.4"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 6819962880,
    "CFBundleShortVersionString" : "2.1.1",
    "CFBundleIdentifier" : "com.apple.HIToolbox",
    "size" : 3125536,
    "uuid" : "8716490e-acc2-3688-8c2f-5ca42b4c9da9",
    "path" : "\/System\/Library\/Frameworks\/Carbon.framework\/Versions\/A\/Frameworks\/HIToolbox.framework\/Versions\/A\/HIToolbox",
    "name" : "HIToolbox"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 6676099072,
    "CFBundleShortVersionString" : "6.9",
    "CFBundleIdentifier" : "com.apple.AppKit",
    "size" : 24260512,
    "uuid" : "cf57a4fc-4be3-3d95-b543-d744e8718b26",
    "path" : "\/System\/Library\/Frameworks\/AppKit.framework\/Versions\/C\/AppKit",
    "name" : "AppKit",
    "CFBundleVersion" : "2685.60.104"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 7490236416,
    "CFBundleShortVersionString" : "7.5.3",
    "CFBundleIdentifier" : "com.apple.SwiftUI",
    "size" : 24418176,
    "uuid" : "90f7fa24-a280-3e8a-a62d-148b11bfc28d",
    "path" : "\/System\/Library\/Frameworks\/SwiftUI.framework\/Versions\/A\/SwiftUI",
    "name" : "SwiftUI",
    "CFBundleVersion" : "7.5.3"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 6600015872,
    "size" : 680472,
    "uuid" : "a237ef81-b68b-37ba-a165-92c965529534",
    "path" : "\/usr\/lib\/dyld",
    "name" : "dyld"
  },
  {
    "size" : 0,
    "source" : "A",
    "base" : 0,
    "uuid" : "00000000-0000-0000-0000-000000000000"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 6603788288,
    "size" : 250544,
    "uuid" : "cc1cf985-bc65-3725-809f-4c1e36b8f4ba",
    "path" : "\/usr\/lib\/system\/libsystem_kernel.dylib",
    "name" : "libsystem_kernel.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 6604042240,
    "size" : 52028,
    "uuid" : "4f33683c-18c8-39a1-800b-2e3bd43bcc13",
    "path" : "\/usr\/lib\/system\/libsystem_pthread.dylib",
    "name" : "libsystem_pthread.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 7173263360,
    "CFBundleShortVersionString" : "21624",
    "CFBundleIdentifier" : "com.apple.JavaScriptCore",
    "size" : 28180096,
    "uuid" : "c2013e04-a794-3826-8682-29ad862df9c9",
    "path" : "\/System\/Library\/Frameworks\/JavaScriptCore.framework\/Versions\/A\/JavaScriptCore",
    "name" : "JavaScriptCore",
    "CFBundleVersion" : "21624.2.5.11.4"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 7311450112,
    "CFBundleShortVersionString" : "21624",
    "CFBundleIdentifier" : "com.apple.WebKit",
    "size" : 22965664,
    "uuid" : "c67d8890-c314-324b-9b5d-8d41082ad492",
    "path" : "\/System\/Library\/Frameworks\/WebKit.framework\/Versions\/A\/WebKit",
    "name" : "WebKit",
    "CFBundleVersion" : "21624.2.5.11.4"
  }
],
  "sharedCache" : {
  "base" : 6598885376,
  "size" : 5990596608,
  "uuid" : "46e0097f-f385-36c8-84a9-a40d315a32d1"
},
  "vmSummary" : "ReadOnly portion of Libraries: Total=1.8G resident=0K(0%) swapped_out_or_unallocated=1.8G(100%)\nWritable regions: Total=4.5G written=929K(0%) resident=929K(0%) swapped_out=0K(0%) unallocated=4.5G(100%)\n\n                                VIRTUAL   REGION \nREGION TYPE                        SIZE    COUNT (non-coalesced) \n===========                     =======  ======= \nAccelerate framework               128K        1 \nActivity Tracing                   256K        1 \nAttributeGraph Data               1024K        1 \nColorSync                           32K        2 \nCoreAnimation                     5104K      133 \nCoreGraphics                        48K        3 \nCoreServices                       624K        2 \nCoreUI image data                  656K        5 \nFoundation                          16K        1 \nJS VM Gigacage (reserved)          4.0G        1         reserved VM address space (unallocated)\nKernel Alloc Once                   32K        1 \nMALLOC                           186.0M       56 \nMALLOC guard page                 4128K        4 \nMemory Tag 22                     64.0M        1 \nSTACK GUARD                       56.2M       10 \nStack                             12.8M       10 \nVM_ALLOCATE                       3472K       10 \nWebKit Malloc                    256.1M        7 \n__AUTH                            5995K      636 \n__AUTH_CONST                      89.0M     1024 \n__CTF                               824        1 \n__DATA                            34.3M      977 \n__DATA_CONST                      34.6M     1034 \n__DATA_DIRTY                      8388K      882 \n__FONT_DATA                        2352        1 \n__GLSLBUILTINS                    5176K        1 \n__LINKEDIT                       576.5M        7 \n__OBJC_RO                         79.1M        1 \n__OBJC_RW                         2599K        1 \n__TEXT                             1.2G     1056 \n__TPRO_CONST                       128K        2 \nmapped file                      711.7M       66 \npage table in kernel               929K        1 \nshared memory                     1952K       17 \n===========                     =======  ======= \nTOTAL                              7.3G     5956 \nTOTAL, minus reserved VM space     3.3G     5956 \n",
  "legacyInfo" : {
  "threadTriggered" : {
    "queue" : "com.apple.main-thread"
  }
},
  "logWritingSignature" : "7869493a7bd78ba50f288ba61d394d112f8cb8da",
  "bug_type" : "309",
  "roots_installed" : 0,
  "trmStatus" : 1,
  "trialInfo" : {
  "rollouts" : [
    {
      "rolloutId" : "6434420a89ec2e0a7a38bf5a",
      "factorPackIds" : [

      ],
      "deploymentId" : 240000011
    },
    {
      "rolloutId" : "5f72dc58705eff005a46b3a9",
      "factorPackIds" : [

      ],
      "deploymentId" : 240000015
    }
  ],
  "experiments" : [

  ]
}
}

Model: Mac16,8, BootROM 18000.120.36, proc 12:8:4:0 processors, 24 GB, SMC 
Graphics: Apple M4 Pro, Apple M4 Pro, Built-In
Display: Color LCD, 3024 x 1964 Retina, Main, MirrorOff, Online
Memory Module: LPDDR5, Micron
AirPort: spairport_wireless_card_type_wifi (0x14E4, 0x4388), wl0: Feb  2 2026 19:18:30 version 23.50.20.0.41.51.208 FWID 01-ef259bc2
IO80211_driverkit-1561.3 "IO80211_driverkit-1561.3" Apr 18 2026 17:42:26
AirPort: 
Bluetooth: Version (null), 0 services, 0 devices, 0 incoming serial ports
Network Service: Wi-Fi, AirPort, en0
Thunderbolt Bus: MacBook Pro, Apple Inc.
Thunderbolt Bus: MacBook Pro, Apple Inc.
Thunderbolt Bus: MacBook Pro, Apple Inc.
