IMPLEMENTATION MODULE Atoms ;

FROM Xlib IMPORT Atom, XInternAtom, False ;
FROM XServer IMPORT dpy ;

PROCEDURE Get (name: ARRAY OF CHAR) : Atom ;
BEGIN
  RETURN XInternAtom (dpy, name, False)
END Get ;

PROCEDURE Init ;
BEGIN
  WmProtocols := Get ("WM_PROTOCOLS") ;
  WmDeleteWindow := Get ("WM_DELETE_WINDOW") ;
  WmTakeFocus := Get ("WM_TAKE_FOCUS") ;
  WmState := Get ("WM_STATE") ;
  WmChangeState := Get ("WM_CHANGE_STATE") ;
  WmClass := Get ("WM_CLASS") ;
  Utf8String := Get ("UTF8_STRING") ;
  MotifWmHints := Get ("_MOTIF_WM_HINTS") ;
  NetSupported := Get ("_NET_SUPPORTED") ;
  NetSupportingWmCheck := Get ("_NET_SUPPORTING_WM_CHECK") ;
  NetClientList := Get ("_NET_CLIENT_LIST") ;
  NetClientListStacking := Get ("_NET_CLIENT_LIST_STACKING") ;
  NetActiveWindow := Get ("_NET_ACTIVE_WINDOW") ;
  NetNumberOfDesktops := Get ("_NET_NUMBER_OF_DESKTOPS") ;
  NetCurrentDesktop := Get ("_NET_CURRENT_DESKTOP") ;
  NetDesktopNames := Get ("_NET_DESKTOP_NAMES") ;
  NetDesktopGeometry := Get ("_NET_DESKTOP_GEOMETRY") ;
  NetDesktopViewport := Get ("_NET_DESKTOP_VIEWPORT") ;
  NetWorkarea := Get ("_NET_WORKAREA") ;
  NetCloseWindow := Get ("_NET_CLOSE_WINDOW") ;
  NetWmName := Get ("_NET_WM_NAME") ;
  NetWmVisibleName := Get ("_NET_WM_VISIBLE_NAME") ;
  NetWmDesktop := Get ("_NET_WM_DESKTOP") ;
  NetWmState := Get ("_NET_WM_STATE") ;
  NetWmStateFullscreen := Get ("_NET_WM_STATE_FULLSCREEN") ;
  NetWmStateHidden := Get ("_NET_WM_STATE_HIDDEN") ;
  NetWmStateMaximizedVert := Get ("_NET_WM_STATE_MAXIMIZED_VERT") ;
  NetWmStateMaximizedHorz := Get ("_NET_WM_STATE_MAXIMIZED_HORZ") ;
  NetWmStateModal := Get ("_NET_WM_STATE_MODAL") ;
  NetWmStateDemandsAttention := Get ("_NET_WM_STATE_DEMANDS_ATTENTION") ;
  NetWmWindowType := Get ("_NET_WM_WINDOW_TYPE") ;
  NetWmWindowTypeDock := Get ("_NET_WM_WINDOW_TYPE_DOCK") ;
  NetWmWindowTypeDesktop := Get ("_NET_WM_WINDOW_TYPE_DESKTOP") ;
  NetWmWindowTypeDialog := Get ("_NET_WM_WINDOW_TYPE_DIALOG") ;
  NetWmWindowTypeSplash := Get ("_NET_WM_WINDOW_TYPE_SPLASH") ;
  NetWmWindowTypeUtility := Get ("_NET_WM_WINDOW_TYPE_UTILITY") ;
  NetWmWindowTypeNormal := Get ("_NET_WM_WINDOW_TYPE_NORMAL") ;
  NetWmStrut := Get ("_NET_WM_STRUT") ;
  NetWmStrutPartial := Get ("_NET_WM_STRUT_PARTIAL") ;
  NetFrameExtents := Get ("_NET_FRAME_EXTENTS") ;
  NetRequestFrameExtents := Get ("_NET_REQUEST_FRAME_EXTENTS") ;
  NetWmPid := Get ("_NET_WM_PID") ;
  MosaicCommand := Get ("_MOSAIC_COMMAND")
END Init ;

END Atoms.
