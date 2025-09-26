ASM = nasm
ASMFLAGS = -f bin
TARGET = itsy.com
SRC = itsy.asm

all: $(TARGET)

$(TARGET): $(SRC)
	$(ASM) $(ASMFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)

