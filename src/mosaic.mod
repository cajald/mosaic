MODULE mosaic ;

FROM StrLib IMPORT StrEqual ;
FROM Args IMPORT GetArg, Narg ;
FROM libc IMPORT exit ;
IMPORT Log ;

CONST
  Version = "0.1" ;

VAR
  arg: ARRAY [0..255] OF CHAR ;

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
  END
END mosaic.
