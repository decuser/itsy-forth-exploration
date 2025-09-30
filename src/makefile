ASM = nasm
ASMFLAGS = -f elf64 -g -F dwarf -l $(SRC:.asm=.lst)
LD = ld
TARGET = itsy64
SRC = itsy64.asm
OBJ = $(SRC:.asm=.o)
GDBSCRIPT = gdb.script

all: $(TARGET)

$(OBJ): $(SRC)
	$(ASM) $(ASMFLAGS) -o $@ $<

$(TARGET): $(OBJ)
	$(LD) -o $@ $^

run: $(TARGET)
	./$(TARGET)

gdb: $(TARGET)
	gdb -x $(GDBSCRIPT) ./$(TARGET)

clean:
	rm -f $(TARGET) $(OBJ) $(SRC:.asm=.lst)

