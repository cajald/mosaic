MODULE mosaic ;

FROM StrLib IMPORT StrEqual ;
FROM Args IMPORT GetArg, Narg ;
FROM libc IMPORT exit ;
FROM Posix IMPORT mx_watch_signals, mx_take_signal, mx_init_locale ;
FROM XGlue IMPORT Event ;
IMPORT Log, XServer, Atoms ;

CONST
  Version = "0.1" ;

VAR
  arg: ARRAY [0..255] OF CHAR ;
  event: Event ;
  running: BOOLEAN ;

BEGIN
  Log.SetProgram ("mosaic") ;
  IF Narg () > 1
  THEN
    IF GetArg (arg, 1) AND StrEqual (arg, "--version")
    THEN
      Log.Out ("mosaic ") ; Log.OutLn (Version) ;
      exit (0)
    END ;
    Log.Error ("usage: mosaic [--version]") ;
    exit (2)
  END ;
  mx_init_locale ;
  mx_watch_signals ;
  IF NOT XServer.Open ()
  THEN
    exit (1)
  END ;
  Atoms.Init ;
  running := TRUE ;
  WHILE running DO
    IF XServer.WaitEvent (1000)
    THEN
      IF XServer.NextEvent (event) THEN END
    END ;
    IF mx_take_signal () # 0
    THEN
      running := FALSE
    END
  END ;
  XServer.Close ;
  exit (0)
END mosaic.
