.PHONY : all help

all:  mdm.dll

CFLAGS += -O2
LDFLAGS += -llua51

ifdef JIT
	CFLAGS += -I $(LUAJIT_HOME)/include
	LDFLAGS += -L $(LUAJIT_HOME)/lib
else
	CFLAGS += -I $(LUA_HOME)/include
	LDFLAGS += -L $(LUA_HOME)/lib
endif


OBJS = str_translate.o

help:
	@echo make [JIT=yes] [help]

clean:
	rm -f *.o *.dll

mdm.dll: $(OBJS)
	$(CC) -o mdm.dll -shared  $(OBJS) $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<
