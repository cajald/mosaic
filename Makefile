PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
DATADIR ?= $(PREFIX)/share
DESTDIR ?=

GM2 ?= gm2
CC ?= cc
PKG_CONFIG ?= pkg-config

M2FLAGS ?= -O2 -g -Wall
CFLAGS ?= -O2 -g -Wall -Wextra
LDFLAGS ?=

X11_CFLAGS := $(shell $(PKG_CONFIG) --cflags x11 xft)
X11_LIBS := $(shell $(PKG_CONFIG) --libs x11 xft)

BUILD := build
SRCDIRS := src src/x11 src/sys src/lib src/ui src/wm src/desktop src/panel src/launcher src/files
INCLUDES := $(foreach d,$(SRCDIRS),-I$(d))

vpath %.mod $(SRCDIRS)
vpath %.c $(SRCDIRS)

PROGRAMS := mosaic mosaic-panel mosaic-launcher mosaic-files

# modules shared by every program
COMMON_OBJS := Log.o Str.o TextFile.o Config.o Spawn.o XServer.o Atoms.o Props.o \
	Gfx.o Win.o Widgets.o Menu.o xglue.o sysglue.o

MOSAIC_OBJS := mosaic.o Desktop.o Clients.o Frames.o Keys.o Ewmh.o Wm.o \
	$(COMMON_OBJS)
PANEL_OBJS := panel.o Tasks.o Dialog.o $(COMMON_OBJS)
LAUNCHER_OBJS := launcher.o Entries.o Dialog.o $(COMMON_OBJS)
FILES_OBJS := files.o Fs.o Dialog.o $(COMMON_OBJS)

all: $(PROGRAMS)

mosaic: $(addprefix $(BUILD)/,$(MOSAIC_OBJS))
	$(GM2) $(LDFLAGS) $^ -o $@ $(X11_LIBS)

mosaic-panel: $(addprefix $(BUILD)/,$(PANEL_OBJS))
	$(GM2) $(LDFLAGS) $^ -o $@ $(X11_LIBS)

mosaic-launcher: $(addprefix $(BUILD)/,$(LAUNCHER_OBJS))
	$(GM2) $(LDFLAGS) $^ -o $@ $(X11_LIBS)

mosaic-files: $(addprefix $(BUILD)/,$(FILES_OBJS))
	$(GM2) $(LDFLAGS) $^ -o $@ $(X11_LIBS)

# program modules carry the generated main and module initialisation
$(BUILD)/mosaic.o $(BUILD)/panel.o $(BUILD)/launcher.o \
	$(BUILD)/files.o: M2MAIN := -fscaffold-main -fscaffold-dynamic

$(BUILD)/%.o: %.mod | $(BUILD)
	$(GM2) $(M2FLAGS) $(M2MAIN) $(INCLUDES) -MMD -MP -c $< -o $@

$(BUILD)/%.o: %.c | $(BUILD)
	$(CC) $(CFLAGS) $(X11_CFLAGS) -MMD -MP -c $< -o $@

$(BUILD):
	mkdir -p $@

install: all
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 $(PROGRAMS) $(DESTDIR)$(BINDIR)

uninstall:
	rm -f $(addprefix $(DESTDIR)$(BINDIR)/,$(PROGRAMS))

clean:
	rm -rf $(BUILD) $(PROGRAMS)

.PHONY: all install uninstall clean

-include $(wildcard $(BUILD)/*.d)
