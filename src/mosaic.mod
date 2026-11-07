MODULE mosaic ;

(* mosaic: the window manager and desktop; it also keeps the panel
   running for the length of the session *)

FROM SYSTEM IMPORT ADR ;
FROM Args IMPORT GetArg, Narg ;
FROM libc IMPORT exit, time, setenv ;
FROM Posix IMPORT SIGTERM, kill, mx_watch_signals, mx_take_signal,
                  mx_init_locale ;
FROM XGlue IMPORT Event ;
FROM Spawn IMPORT Args ;
IMPORT Log, Str, XServer, Atoms, Config, Gfx, Spawn, Wm ;

CONST
  Version = "0.1" ;
  RestartLimit = 5 ;
  RestartWindow = 60 ;

VAR
  arg: ARRAY [0..255] OF CHAR ;
  event: Event ;
  panelPid, pid: INTEGER ;
  restarts: INTEGER ;
  firstRestart, restartAt: LONGINT ;

PROCEDURE StartPanel ;
VAR
  a: Args ;
  path: ARRAY [0..4095] OF CHAR ;
BEGIN
  Spawn.Sibling ("mosaic-panel", path) ;
  Spawn.Clear (a) ;
  IF Spawn.Add (a, path)
  THEN
    panelPid := Spawn.Run (a, "")
  END
END StartPanel ;

(* a crashed panel comes back, unless it keeps crashing *)
PROCEDURE PanelExited ;
VAR
  now: LONGINT ;
BEGIN
  panelPid := -1 ;
  now := time (NIL) ;
  IF now - firstRestart > RestartWindow
  THEN
    firstRestart := now ;
    restarts := 0
  END ;
  INC (restarts) ;
  IF restarts > RestartLimit
  THEN
    Log.Error ("the panel keeps exiting; not restarting it") ;
    restartAt := -1
  ELSE
    restartAt := now + 1
  END
END PanelExited ;

BEGIN
  Log.SetProgram ("mosaic") ;
  IF Narg () > 1
  THEN
    IF GetArg (arg, 1) AND Str.Equal (arg, "--version")
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
  Config.Load ;
  Atoms.Init ;
  IF NOT (Gfx.Init () AND Wm.Start ())
  THEN
    Gfx.Done ;
    XServer.Close ;
    exit (1)
  END ;
  IF setenv (ADR ("XDG_CURRENT_DESKTOP"), ADR ("Mosaic"), 1) # 0 THEN END ;
  panelPid := -1 ;
  restarts := 0 ;
  firstRestart := 0 ;
  restartAt := -1 ;
  StartPanel ;
  WHILE NOT Wm.quit DO
    IF XServer.WaitEvent (1000) AND XServer.NextEvent (event)
    THEN
      Wm.Handle (event)
    END ;
    pid := Spawn.Reap () ;
    WHILE pid > 0 DO
      IF pid = panelPid
      THEN
        PanelExited
      END ;
      pid := Spawn.Reap ()
    END ;
    IF (restartAt >= 0) AND (time (NIL) >= restartAt)
    THEN
      restartAt := -1 ;
      StartPanel
    END ;
    IF mx_take_signal () # 0
    THEN
      Wm.quit := TRUE
    END
  END ;
  IF panelPid > 0
  THEN
    IF kill (panelPid, SIGTERM) # 0 THEN END
  END ;
  Wm.Stop ;
  Gfx.Done ;
  XServer.Close ;
  exit (0)
END mosaic.
